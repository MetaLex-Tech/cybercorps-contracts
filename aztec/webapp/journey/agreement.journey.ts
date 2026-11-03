import { type Browser, expect, type Locator, type Page, test } from '@playwright/test';

/**
 * The happy path of the web app. The wallets run in the browser; MetaLeX runs on the server with Postgres.
 *
 * Bob onboards. Alice drafts and signs. Bob opens the invite link and signs. MetaLeX sends one private `finalize`.
 * An auditor opens the invite and checks both proofs. Bob restores his key on a new device and opens the agreement
 * from the data key store. MetaLeX ends the retention period. Alice sends the invite link again. Each step saves a
 * screenshot in the test's output folder.
 */

// A testnet tx takes a real proof and a block, so each wait is long.
const long = { timeout: 10 * 60_000 };

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
const rowOf = (page: Page, section: string, agreementId: string): Locator =>
  page.locator(`#${section} tr`, { hasText: short(agreementId) });

// Waits for `target`, but fails at once when the app shows an error.
const shown = async (page: Page, target: Locator) => {
  await expect(target.or(page.locator('.error')).first()).toBeVisible(long);
  const error = page.locator('.error');
  if (await error.count()) throw new Error(`app error: ${await error.first().textContent()}`);
};

const addressOf = async (page: Page) => (await page.locator('.role .mono').first().textContent())!.trim();

test('two parties sign, MetaLeX finalizes, an auditor verifies, a new device restores the agreement', async ({
  browser,
}) => {
  const bob = await device(browser);
  await bob.goto('/bob');
  await shown(bob, bob.locator('#mine h2'));
  const bobAddress = await addressOf(bob);
  const bobKey = await bob.evaluate(() => localStorage.getItem('signing-key:bob'));

  // Alice and Bob play in one browser: Alice's page derives Bob's address from Bob's key in the browser.
  const alice = await device(browser);
  await alice.context().addInitScript(key => localStorage.setItem('signing-key:bob', key), bobKey!);
  let invite = '';
  let agreementId = '';

  await test.step('Alice drafts the agreement', async () => {
    await alice.goto('/alice');
    await shown(alice, alice.locator('#draft'));
    await alice.getByLabel('Effective date').fill('2026-11-03');
    await alice.getByLabel('Your legal name').fill('Alice Corp');
    await expect(alice.locator('#counterparty')).toHaveValue(new RegExp(short(bobAddress).replace('…', '.')));
    await alice.getByLabel('Counterparty legal name').fill('Bob LLC');
    await shot(alice, 'alice-drafts');
    await alice.getByRole('button', { name: 'Review' }).click();
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

  const metalex = await device(browser);

  await test.step('MetaLeX holds only ciphertext and waits for Bob', async () => {
    await metalex.goto('/metalex');
    const row = rowOf(metalex, 'collector', agreementId);
    await shown(metalex, row);
    await expect(row).toContainText('Waiting for signatures');
    const html = await metalex.content();
    expect(html).not.toContain('Alice Corp');
    expect(html).not.toContain('Return or destruction.');
    await shot(metalex, 'metalex-waits-for-bob');
  });

  await test.step('Bob opens the invite link and signs; MetaLeX sends finalize', async () => {
    await bob.goto(`/bob#invite=${invite}`);
    const agreement = bob.locator('#agreement');
    await shown(bob, agreement.locator('.status'));
    await expect(agreement.locator('.status')).toHaveText('Pending');
    await expect(agreement.locator('dd').first()).toHaveText(agreementId);
    await expect(agreement).toContainText('Waiting for: Bob');
    await shot(bob, 'bob-opens-invite');
    await bob.getByRole('button', { name: 'Sign', exact: true }).click();
    await shown(bob, bob.locator('#sent, #finalized'));
    await shot(bob, 'bob-sees-tx-sent');
    await shown(bob, agreement.locator('.status', { hasText: 'Finalized' }));
    await expect(bob.locator('#finalized a')).toHaveAttribute('href', /\/tx-effects\/0x[0-9a-f]{64}$/);
    await expect(rowOf(bob, 'mine', agreementId).locator('.status')).toHaveText('Finalized');
    await shot(bob, 'bob-sees-finalized');
  });

  await test.step('MetaLeX shows one finalize tx with 6 nullifiers', async () => {
    await metalex.reload();
    const row = rowOf(metalex, 'collector', agreementId);
    await expect(row).toContainText('6 nullifiers, 0 note hashes, 0 logs', long);
    await shot(metalex, 'metalex-finalized');
  });

  await test.step('the auditor sees "finalized" and verifies both proofs', async () => {
    const auditor = await device(browser);
    await auditor.goto(`/auditor#invite=${invite}`);
    const agreement = auditor.locator('#agreement');
    await shown(auditor, agreement.locator('.status'));
    await expect(agreement.locator('.status')).toHaveText('Finalized');
    await expect(agreement.getByRole('button', { name: 'Sign' })).toHaveCount(0);
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
    await auditor.getByRole('button', { name: 'Reset to the invite' }).click();
    await expect(verdict).toContainText(signed, long);
  });

  const bobNewDevice = await device(browser);

  await test.step('Bob restores his key on a new device and opens the agreement from the data key store', async () => {
    await bobNewDevice.goto('/bob');
    await shown(bobNewDevice, bobNewDevice.locator('#mine h2'));
    await bobNewDevice.locator('#signing-key summary').click();
    await bobNewDevice.getByLabel('Restore a signing key').fill(bobKey!);
    await bobNewDevice.getByRole('button', { name: 'Restore' }).click();
    await shown(bobNewDevice, bobNewDevice.locator('#mine h2'));
    expect(await addressOf(bobNewDevice)).toBe(bobAddress);
    const row = rowOf(bobNewDevice, 'mine', agreementId);
    await shown(bobNewDevice, row.locator('.status'));
    await expect(row.locator('.status')).toHaveText('Finalized');
    await expect(bobNewDevice.locator('#no-invites')).toBeVisible();
    await shot(bobNewDevice, 'bob-new-device-list');
  });

  await test.step('MetaLeX ends the retention period: the salt goes, the encrypted document stays', async () => {
    await metalex.reload();
    await shown(metalex, rowOf(metalex, 'data-keys', agreementId));
    const vaultRows = await metalex.locator('#vault tbody tr').count();
    await rowOf(metalex, 'data-keys', agreementId).getByRole('button', { name: 'End retention now' }).click();
    await expect(rowOf(metalex, 'data-keys', agreementId)).toHaveCount(0);
    await expect(metalex.locator('#vault tbody tr')).toHaveCount(vaultRows);
    await shot(metalex, 'metalex-ends-retention');
    await bobNewDevice.reload();
    await shown(bobNewDevice, bobNewDevice.locator('#mine h2'));
    await shown(bobNewDevice, bobNewDevice.locator('#no-agreements'));
    await shot(bobNewDevice, 'bob-new-device-after-retention');
  });

  await test.step('Bob asks Alice for the invite link again and opens the agreement from the vault', async () => {
    await alice.goto('/alice');
    const link = alice.getByLabel(`Invite link ${short(agreementId)}`);
    await shown(alice, link);
    const resent = await link.inputValue();
    expect(new URL(resent).hash).toBe(`#invite=${invite}`);
    await shot(alice, 'alice-invite-links-on-device');
    await bobNewDevice.goto(resent);
    const agreement = bobNewDevice.locator('#agreement');
    await shown(bobNewDevice, agreement.locator('.status'));
    await expect(agreement.locator('.status')).toHaveText('Finalized');
    await expect(agreement).toContainText('Encrypted in the MetaLeX vault');
    await shot(bobNewDevice, 'bob-opens-with-invite-again');
  });
});
