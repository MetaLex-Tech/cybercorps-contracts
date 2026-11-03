import { createAztecNodeClient } from '@aztec-labs/aztec.js/node';
import { TxHash } from '@aztec-labs/aztec.js/tx';
import { type Browser, expect, type Locator, type Page, test } from '@playwright/test';

/**
 * The happy path of the PoC web app on a local network, with fake proofs.
 *
 * Alice drafts and signs. Bob opens the invite link and signs. MetaLeX sends one private `finalize`. An auditor
 * opens the invite. Bob opens the agreement on a new device from the data key store. MetaLeX ends the retention
 * period. Each step saves a screenshot in the test's output folder.
 *
 *     npm run journey
 */

const NODE_URL = process.env.AZTEC_NODE_URL ?? 'http://localhost:8090';
const long = { timeout: 5 * 60_000 };

const screenshots = () => {
  let count = 0;
  return async (page: Page, name: string) => {
    count += 1;
    await page.screenshot({
      path: test.info().outputPath(`${String(count).padStart(2, '0')}-${name}.png`),
      fullPage: true,
    });
  };
};
const shot = screenshots();

// Each role opens in its own browser context, as on its own device.
const device = async (browser: Browser) => (await browser.newContext()).newPage();
const short = (hex: string) => `${hex.slice(0, 10)}…${hex.slice(-6)}`;
// Waits for `target`, but fails at once when the app shows an error.
const shown = async (page: Page, target: Locator) => {
  await expect(target.or(page.locator('.error')).first()).toBeVisible(long);
  const error = page.locator('.error');
  if (await error.count()) throw new Error(`app error: ${await error.first().textContent()}`);
};
const rowOf = (page: Page, section: string, agreementId: string): Locator =>
  page.locator(`#${section} tr`, { hasText: short(agreementId) });

test('two parties sign, MetaLeX finalizes, an auditor and a new device open the agreement', async ({ browser, request }) => {
  const alice = await device(browser);
  let invite = '';
  let agreementId = '';

  await test.step('Alice drafts the agreement', async () => {
    await alice.goto('/alice');
    await alice.getByLabel('Effective date').fill('2026-11-02');
    await alice.getByLabel('Your legal name').fill('Alice Corp');
    await alice.getByLabel('Counterparty legal name').fill('Bob LLC');
    await shot(alice, 'alice-drafts');
    await alice.getByRole('button', { name: 'Review' }).click();
    await expect(alice.locator('#review-step .doc')).toContainText('Bob LLC');
    await expect(alice.locator('#review-step .doc')).toContainText('Return or destruction.');
    await shot(alice, 'alice-reviews');
  });

  await test.step('Alice signs and gets the invite link', async () => {
    await alice.getByRole('button', { name: 'Sign', exact: true }).click();
    await shown(alice, alice.locator('#invite'));
    const link = await alice.getByLabel('Invite link', { exact: true }).inputValue();
    invite = new URL(link).hash.slice('#invite='.length);
    agreementId = (await alice.locator('#invite dd').first().textContent())!.trim();
    await shot(alice, 'alice-invite');
  });

  const salt = JSON.parse(Buffer.from(invite, 'base64url').toString('utf8')).salt as string;
  const metalex = await device(browser);

  await test.step('MetaLeX holds only ciphertext and waits for Bob', async () => {
    await metalex.goto('/metalex');
    const row = rowOf(metalex, 'collector', agreementId);
    await expect(row).toContainText('Waiting for signatures');
    await expect(row.locator('td').nth(3)).toHaveText('Bob');
    await expect(rowOf(metalex, 'data-keys', agreementId)).toBeVisible();
    const html = await metalex.content();
    expect(html).not.toContain('Alice Corp');
    expect(html).not.toContain('Bob LLC');
    expect(html).not.toContain('Return or destruction.');
    expect(html).not.toContain(salt.slice(2));
    await shot(metalex, 'metalex-waits-for-bob');
  });

  const bob = await device(browser);

  await test.step('Bob opens the invite link and sees "pending"', async () => {
    await bob.goto(`/bob#invite=${invite}`);
    const agreement = bob.locator('#agreement');
    await shown(bob, agreement);
    await expect(agreement.locator('.status')).toHaveText('Pending');
    await expect(agreement.locator('dd').first()).toHaveText(agreementId);
    await expect(agreement).toContainText('Waiting for: Bob');
    await expect(agreement.locator('.doc')).toContainText('Alice Corp');
    await expect(agreement).toContainText('Encrypted in the MetaLeX vault');
    await shot(bob, 'bob-opens-invite');
  });

  await test.step('Bob signs and MetaLeX finalizes', async () => {
    await bob.getByRole('button', { name: 'Sign', exact: true }).click();
    await shown(bob, bob.getByText('MetaLeX is sending the finalize transaction'));
    await shot(bob, 'bob-signs');
    await shown(bob, bob.locator('#agreement .status', { hasText: 'Finalized' }));
    await expect(rowOf(bob, 'mine', agreementId).locator('.status')).toHaveText('Finalized');
    await shot(bob, 'bob-sees-finalized');
  });

  await test.step('the chain has 6 nullifiers, no note hashes and no logs; the FPC pays', async () => {
    await metalex.reload();
    const row = rowOf(metalex, 'collector', agreementId);
    await expect(row).toContainText('6 nullifiers, 0 note hashes, 0 logs');
    await expect(row).toContainText('Fee payer: MetaLeX FPC');
    await shot(metalex, 'metalex-finalized');

    const view = await (await request.get('/api/metalex')).json();
    const { txHash } = view.collector.find((c: { agreementId: string }) => c.agreementId === agreementId).settlement;
    const node = createAztecNodeClient(NODE_URL);
    const effect = (await node.getTxEffect(TxHash.fromString(txHash)))!.data;
    expect(effect.nullifiers.length).toBe(6);
    expect(effect.noteHashes.length).toBe(0);
    expect(effect.privateLogs.length + effect.publicLogs.length).toBe(0);
    const tx = (await node.getTxByHash(TxHash.fromString(txHash)))!;
    expect(tx.data.feePayer.toString()).toBe(view.fpc);

    // The parties and MetaLeX get a link to the one finalize tx.
    const href = `https://explorer.invalid/tx-effects/${txHash}`;
    await expect(rowOf(metalex, 'collector', agreementId).locator(`a[href="${href}"]`)).toBeVisible();
    await bob.reload();
    await expect(bob.locator(`#finalized a[href="${href}"]`)).toBeVisible();
  });

  await test.step('the auditor opens the invite link and sees "finalized"', async () => {
    const auditor = await device(browser);
    await auditor.goto(`/auditor#invite=${invite}`);
    const agreement = auditor.locator('#agreement');
    await shown(auditor, agreement);
    await expect(agreement.locator('.status')).toHaveText('Finalized');
    await expect(agreement.locator('.doc')).toContainText('Bob LLC');
    await expect(agreement.getByRole('button', { name: 'Sign' })).toHaveCount(0);
    await shot(auditor, 'auditor-sees-finalized');

    const verdict = auditor.locator('#verify-result .verdict');
    const signed = 'These are the exact terms that the parties signed';
    const notSigned = 'These terms were not signed and finalized';
    await expect(verdict).toContainText(signed, long);
    await expect(auditor.locator('#verify-result')).not.toContainText('✗');
    await shot(auditor, 'auditor-verifies-both-proofs');

    const clause = auditor.getByLabel('Clause 8');
    await clause.fill((await clause.inputValue()).replace('2 years', '1 year'));
    await expect(verdict).toContainText(notSigned, long);
    await expect(auditor.locator('#verify-result')).toContainText('✗ finalized nullifier');
    await expect(auditor.locator('#verify-result')).toContainText('✗ signature over these terms');
    await shot(auditor, 'auditor-changes-a-clause');

    const reset = auditor.getByRole('button', { name: 'Reset to the invite' });
    await reset.click();
    await expect(verdict).toContainText(signed, long);

    await auditor.getByLabel('Expiry (Unix seconds, 0 = none)').fill('1');
    await expect(verdict).toContainText(notSigned, long);
    await reset.click();
    await expect(verdict).toContainText(signed, long);

    await auditor.getByLabel(/^Party 2 address/).fill(await auditor.getByLabel(/^Party 1 address/).inputValue());
    await expect(verdict).toContainText(notSigned, long);
    await shot(auditor, 'auditor-changes-a-party');
  });

  const bobNewDevice = await device(browser);

  await test.step('Bob opens the agreement on a new device from the data key store', async () => {
    await bobNewDevice.goto('/bob');
    const row = rowOf(bobNewDevice, 'mine', agreementId);
    await shown(bobNewDevice, row);
    await expect(row.locator('.status')).toHaveText('Finalized');
    await shot(bobNewDevice, 'bob-new-device-list');
    await row.getByRole('link', { name: 'Open' }).click();
    await shown(bobNewDevice, bobNewDevice.locator('#agreement'));
    await expect(bobNewDevice.locator('#agreement .status')).toHaveText('Finalized');
    await expect(bobNewDevice.locator('#agreement dd').first()).toHaveText(agreementId);
    await shot(bobNewDevice, 'bob-new-device-opens');
  });

  await test.step('MetaLeX ends the retention period: the salt goes, the encrypted document stays', async () => {
    await metalex.reload();
    const vaultRows = await metalex.locator('#vault tbody tr').count();
    await rowOf(metalex, 'data-keys', agreementId).getByRole('button', { name: 'End retention now' }).click();
    await expect(rowOf(metalex, 'data-keys', agreementId)).toHaveCount(0);
    await expect(metalex.locator('#vault tbody tr')).toHaveCount(vaultRows);
    await shot(metalex, 'metalex-ends-retention');
  });

  await test.step('Bob on the new device has no data key and no invite link', async () => {
    await bobNewDevice.goto('/bob');
    await shown(bobNewDevice, bobNewDevice.locator('#mine h2'));
    await expect(rowOf(bobNewDevice, 'mine', agreementId)).toHaveCount(0);
    await expect(bobNewDevice.locator('#no-invites')).toBeVisible();
    await shot(bobNewDevice, 'bob-new-device-after-retention');
  });

  let resent = '';

  await test.step('Bob asks Alice for the invite link again', async () => {
    await alice.goto('/alice');
    const link = alice.getByLabel(`Invite link ${short(agreementId)}`);
    await expect(link).toBeVisible();
    resent = await link.inputValue();
    expect(new URL(resent).hash).toBe(`#invite=${invite}`);
    await shot(alice, 'alice-invite-links-on-device');
  });

  await test.step('Bob opens the agreement from the vault with the invite link', async () => {
    await bobNewDevice.goto(resent);
    const agreement = bobNewDevice.locator('#agreement');
    await shown(bobNewDevice, agreement);
    await expect(agreement.locator('.status')).toHaveText('Finalized');
    await expect(agreement).toContainText('Encrypted in the MetaLeX vault');
    await expect(agreement.locator('.doc')).toContainText('Return or destruction.');
    await shot(bobNewDevice, 'bob-opens-with-invite-again');
  });
});
