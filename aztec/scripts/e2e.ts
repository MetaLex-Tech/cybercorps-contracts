// Runs the agreement lifecycle on a local Aztec network with four separate wallets (four PXEs): Alice, Bob, the
// MetaLeX settler and an auditor. `MetaLeXServices` stands in for the MetaLeX document vault, signature collector and
// data key store.
//
// Usage: AZTEC_NODE_URL=http://localhost:8090 node e2e.ts

import { NO_FROM } from '@aztec-labs/aztec.js/account';
import { Fr } from '@aztec-labs/aztec.js/fields';
import {
  agreementOf,
  canonicalJson,
  docKeysOf,
  documentOf,
  encrypt,
  inviteOf,
  openInvite,
  startPoc,
  termsHashOf,
} from './poc.ts';

function check(condition: boolean, label: string) {
  if (!condition) throw new Error(`FAIL: ${label}`);
  console.log(`ok - ${label}`);
}

async function main() {
  const nodeUrl = process.env.AZTEC_NODE_URL ?? 'http://localhost:8080';
  const poc = await startPoc(nodeUrl);
  const { node, metalex, sign, settle, settler } = poc;
  const { address: alice, wallet: aliceWallet, registry: aliceRegistry } = poc.alice;
  const { address: bob, wallet: bobWallet, registry: bobRegistry } = poc.bob;
  const auditorRegistry = poc.auditor.registry;
  console.log(`registry deployed at ${poc.registry}`);

  // 1. Alice drafts the document in the MetaLeX webapp. It never goes onchain.
  const document = documentOf('2026-11-01', [
    [alice, 'Alice Corp'],
    [bob, 'Bob LLC'],
  ]);
  const salt = Fr.random();
  const { result: termsCommitment } = await aliceRegistry.methods
    .terms_commitment_of(termsHashOf(document), salt)
    .simulate({ from: alice });
  const agreement = agreementOf(new Fr(termsCommitment), 0n, [alice, bob]);
  const { result: agreementIdRaw } = await aliceRegistry.methods.agreement_id(agreement).simulate({ from: alice });
  const agreementId = new Fr(agreementIdRaw);
  const { locator, key } = docKeysOf(salt);
  metalex.putDocument(locator, encrypt(key, canonicalJson(document)));
  const invite = inviteOf(salt, agreement.expiry, [alice, bob]);
  const retainUntil = Date.now() + 30 * 24 * 3600 * 1000;
  metalex.putDataKey(agreementId, salt, [alice, bob], retainUntil);

  // 2. Alice signs offchain. The collector waits for Bob.
  metalex.submitSignature(agreementId, agreement, await sign(aliceWallet, aliceRegistry, alice, agreement));
  const pending = metalex.pendingSigners(agreementId);
  check(pending.length === 1 && pending[0].equals(bob), 'collector waits for Bob');
  await expectFailure(
    () => settle(agreement, metalex.collector.get(agreementId.toString())!.signatures),
    'finalize without the consent of Bob is rejected',
    'Unknown auth witness',
  );

  // 3. Bob opens the invite, reviews the document and signs.
  const bobView = await openInvite(bobRegistry, bob, invite, metalex);
  check(bobView.agreementId.equals(agreementId), 'Bob derives the same agreement id from the invite');
  check(canonicalJson(bobView.document) === canonicalJson(document), 'Bob decrypts the same document');
  check(bobView.finalized === false, 'Bob sees the status "pending"');
  metalex.submitSignature(agreementId, bobView.agreement, await sign(bobWallet, bobRegistry, bob, bobView.agreement));
  check(metalex.pendingSigners(agreementId).length === 0, 'collector has all signatures');

  // 4. The settler finalizes in one tx. Its input holds no salt and no terms hash.
  const collected = metalex.collector.get(agreementId.toString())!;
  const collectedJson = JSON.stringify(collected, (_, v) => (typeof v === 'bigint' ? v.toString() : v));
  check(
    !collectedJson.includes(salt.toString().slice(2)) && !collectedJson.includes(termsHashOf(document).toString().slice(2)),
    'collector and settler have no salt and no terms hash',
  );
  const { receipt } = await settle(collected.agreement, collected.signatures);
  console.log(`finalize mined in block ${receipt.blockNumber}, tx ${receipt.txHash}`);

  const tx = await node.getTxByHash(receipt.txHash);
  check(tx !== undefined && tx.data.feePayer.equals(poc.fpc), 'fee payer is the FPC');
  const effect = (await node.getTxEffect(receipt.txHash))!.data;
  console.log(
    `public tx effects: ${effect.nullifiers.length} nullifiers, ${effect.noteHashes.length} note hashes, ` +
      `${effect.privateLogs.length} private logs, ${effect.publicLogs.length} public logs`,
  );
  check(effect.noteHashes.length === 0 && effect.privateLogs.length === 0 && effect.publicLogs.length === 0, 'no note hashes and no logs onchain');

  // 5. Alice, Bob and an auditor see the details and the status "finalized". Alice gives the invite to the auditor.
  for (const [name, reg, from] of [
    ['Alice', aliceRegistry, alice],
    ['Bob', bobRegistry, bob],
    ['Auditor', auditorRegistry, NO_FROM],
  ] as const) {
    const view = await openInvite(reg, from, invite, metalex);
    check(view.finalized && canonicalJson(view.document) === canonicalJson(document), `${name} sees the document and the status "finalized"`);
  }

  // 6. Bob opens the agreement on a new device without the invite. The data key store gives the salt to a party
  // only, and only until the retention ends.
  const row = metalex.dataKeys.get(agreementId.toString())!;
  check(
    !row.ciphertext.includes(Buffer.from(salt.toString())) && !row.ciphertext.includes(salt.toBuffer()),
    'data key store keeps the salt encrypted',
  );
  const stored = collected.agreement;
  const recovered = inviteOf(
    metalex.getDataKey(agreementId, bob),
    stored.expiry,
    stored.parties.slice(0, stored.party_count),
  );
  const bobRecovered = await openInvite(bobRegistry, bob, recovered, metalex);
  check(bobRecovered.finalized && canonicalJson(bobRecovered.document) === canonicalJson(document), 'Bob opens the agreement with the salt from the data key store');
  await expectFailure(async () => metalex.getDataKey(agreementId, settler), 'data key store refuses a non-party', 'access denied');
  metalex.deleteExpiredDataKeys(retainUntil);
  await expectFailure(async () => metalex.getDataKey(agreementId, bob), 'data key store deletes the salt after the retention period', 'no data key');
  const bobWithInvite = await openInvite(bobRegistry, bob, invite, metalex);
  check(
    metalex.vault.has(locator) && bobWithInvite.finalized && canonicalJson(bobWithInvite.document) === canonicalJson(document),
    'after the retention period, the vault keeps the document and the invite opens it',
  );

  // 7. A second finalize of the same agreement fails.
  await expectFailure(() => settle(collected.agreement, collected.signatures), 'second finalize is rejected', 'nullifier');

  // 8. A one-party agreement gives the same nullifier count, so the chain does not show the party count.
  const solo = agreementOf(Fr.random(), 0n, [alice]);
  const { result: soloIdRaw } = await aliceRegistry.methods.agreement_id(solo).simulate({ from: alice });
  metalex.submitSignature(new Fr(soloIdRaw), solo, await sign(aliceWallet, aliceRegistry, alice, solo));
  const { receipt: soloReceipt } = await settle(solo, metalex.collector.get(new Fr(soloIdRaw).toString())!.signatures);
  const soloEffect = (await node.getTxEffect(soloReceipt.txHash))!.data;
  check(soloEffect.nullifiers.length === effect.nullifiers.length, `same nullifier count for one and two parties (${effect.nullifiers.length})`);

  // 9. The network drops a finalize after the agreement expiry.
  const header = (await node.getBlockData('latest'))!.header;
  const expired = agreementOf(Fr.random(), header.globalVariables.timestamp, [alice]);
  await expectFailure(
    async () => settle(expired, [await sign(aliceWallet, aliceRegistry, alice, expired)]),
    'finalize after the expiry is rejected',
    'timestamp',
  );

  console.log('all checks passed');
  process.exit(0);
}

// The call must fail with an error that contains `expected`.
async function expectFailure(fn: () => Promise<unknown>, label: string, expected: string) {
  let message: string;
  try {
    await fn();
  } catch (err) {
    message = (err as Error).message.split('\n')[0];
    if (!message.includes(expected)) throw new Error(`FAIL: ${label}: unexpected error: ${message}`);
    console.log(`ok - ${label}: ${message}`);
    return;
  }
  throw new Error(`FAIL: ${label}: no error`);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
