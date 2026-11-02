// Runs the create-and-sign flow on a local Aztec network with two separate wallets (two PXEs).
// `MetaLeXRelay` stands in for the MetaLeX document vault and mailbox. It only stores ciphertext.
//
// Usage: AZTEC_NODE_URL=http://localhost:8090 node e2e.ts

import { createCipheriv, createDecipheriv, createHash, hkdfSync, randomBytes } from 'node:crypto';
import { getInitialTestAccountsData } from '@aztec-labs/accounts/testing';
import { AztecAddress } from '@aztec-labs/aztec.js/addresses';
import type { OffchainMessage } from '@aztec-labs/aztec.js/contracts';
import { SponsoredFeePaymentMethod } from '@aztec-labs/aztec.js/fee';
import { Fr } from '@aztec-labs/aztec.js/fields';
import { createAztecNodeClient, waitForNode } from '@aztec-labs/aztec.js/node';
import { SponsoredFPCContract } from '@aztec-labs/noir-contracts.js/SponsoredFPC';
import { EmbeddedWallet } from '@aztec-labs/wallets/embedded';
import { createFundedInitializerlessAccounts } from '@aztec-labs/wallets/testing';
import { getContractInstanceFromInstantiationParams } from '@aztec-labs/aztec.js/contracts';
import { CyberAgreementRegistryContract } from './artifacts/CyberAgreementRegistry.ts';

const MAX_PARTIES = 4;

class MetaLeXRelay {
  vault = new Map<string, Buffer>();
  mailbox = new Map<string, OffchainMessage[]>();

  putDocument(locator: string, ciphertext: Buffer) {
    this.vault.set(locator, ciphertext);
  }

  getDocument(locator: string): Buffer {
    const doc = this.vault.get(locator);
    if (!doc) throw new Error(`no document at ${locator}`);
    return doc;
  }

  post(messages: OffchainMessage[]) {
    for (const m of messages) {
      const key = m.recipient.toString();
      this.mailbox.set(key, [...(this.mailbox.get(key) ?? []), m]);
    }
  }

  fetch(recipient: AztecAddress): OffchainMessage[] {
    const messages = this.mailbox.get(recipient.toString()) ?? [];
    this.mailbox.delete(recipient.toString());
    return messages;
  }
}

function sha256(...parts: (string | Buffer)[]): Buffer {
  const h = createHash('sha256');
  for (const p of parts) h.update(p);
  return h.digest();
}

// The terms hash commits to the canonical JSON of the document. Keys must be sorted.
function termsHashOf(doc: object): Fr {
  return Fr.fromBufferReduce(sha256(canonicalJson(doc)));
}

function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value && typeof value === 'object') {
    const entries = Object.entries(value).sort(([a], [b]) => (a < b ? -1 : 1));
    return `{${entries.map(([k, v]) => `${JSON.stringify(k)}:${canonicalJson(v)}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

// HKDF-SHA256 with the agreement salt as input key material. The salt is random, so the HKDF salt is empty.
function hkdf(salt: Fr, label: string): Buffer {
  return Buffer.from(hkdfSync('sha256', salt.toBuffer(), Buffer.alloc(0), label, 32));
}

// The salt gives the vault locator and the document key. MetaLeX sees only the locator.
function docKeysOf(salt: Fr) {
  return {
    locator: hkdf(salt, 'metalex.doc.locator.v1').toString('hex'),
    key: hkdf(salt, 'metalex.doc.key.v1'),
  };
}

function encrypt(key: Buffer, plaintext: string): Buffer {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const body = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), body]);
}

function decrypt(key: Buffer, blob: Buffer): string {
  const decipher = createDecipheriv('aes-256-gcm', key, blob.subarray(0, 12));
  decipher.setAuthTag(blob.subarray(12, 28));
  return Buffer.concat([decipher.update(blob.subarray(28)), decipher.final()]).toString('utf8');
}

function agreementOf(termsHash: Fr, salt: Fr, expiry: bigint, parties: AztecAddress[]) {
  const padded = [...parties, ...Array(MAX_PARTIES - parties.length).fill(AztecAddress.ZERO)];
  return { terms_hash: termsHash, salt, expiry, party_count: parties.length, parties: padded };
}

function check(condition: boolean, label: string) {
  if (!condition) throw new Error(`FAIL: ${label}`);
  console.log(`ok - ${label}`);
}

async function main() {
  const nodeUrl = process.env.AZTEC_NODE_URL ?? 'http://localhost:8080';
  const node = createAztecNodeClient(nodeUrl);
  await waitForNode(node);

  const [aliceData, bobData] = await getInitialTestAccountsData();
  const aliceWallet = await EmbeddedWallet.create(nodeUrl, { ephemeral: true });
  const bobWallet = await EmbeddedWallet.create(nodeUrl, { ephemeral: true });
  const [aliceAccount] = await createFundedInitializerlessAccounts(aliceWallet, [aliceData]);
  const [bobAccount] = await createFundedInitializerlessAccounts(bobWallet, [bobData]);
  const alice = aliceAccount.address;
  const bob = bobAccount.address;
  const relay = new MetaLeXRelay();

  // The local network has a sponsored FPC. On mainnet, MetaLeX runs its own fee payer.
  const fpc = await getContractInstanceFromInstantiationParams(SponsoredFPCContract.artifact, { salt: new Fr(0) });
  await aliceWallet.registerContract(fpc, SponsoredFPCContract.artifact);
  const sponsored = { fee: { paymentMethod: new SponsoredFeePaymentMethod(fpc.address) } };

  // MetaLeX deploys the registry once. Any wallet can then register it from the node.
  const { contract: registry, instance } = await CyberAgreementRegistryContract.deploy(aliceWallet).send({
    from: alice,
  });
  console.log(`registry deployed at ${registry.address}`);
  await bobWallet.registerContract(instance, CyberAgreementRegistryContract.artifact);
  const bobRegistry = CyberAgreementRegistryContract.at(registry.address, bobWallet);

  // 1. Alice drafts the document in the MetaLeX app. It never goes onchain.
  const document = {
    template: { title: 'Mutual NDA', uri: 'ipfs://example-template', globalFields: ['effectiveDate'], partyFields: ['name'] },
    globalValues: ['2026-11-01'],
    partyValues: [
      [alice.toString(), ['Alice Corp']],
      [bob.toString(), ['Bob LLC']],
    ],
  };
  const salt = Fr.random();
  const agreement = agreementOf(termsHashOf(document), salt, 0n, [alice, bob]);
  const { locator, key } = docKeysOf(salt);
  relay.putDocument(locator, encrypt(key, canonicalJson(document)));

  // 2. Alice creates and signs in one private tx. MetaLeX pays the fee.
  const { result: expectedId } = await registry.methods.agreement_id(agreement).simulate({ from: alice });
  const { receipt, offchainMessages } = await registry.methods
    .create_bound_contract_and_sign_for(alice, agreement, 0)
    .send({ from: alice, ...sponsored });
  console.log(`create_bound_contract_and_sign_for mined in block ${receipt.blockNumber}, tx ${receipt.txHash}`);
  check(offchainMessages.length === 2, 'one offchain message for each party');

  const tx = await node.getTxByHash(receipt.txHash);
  check(tx !== undefined && tx.data.feePayer.equals(fpc.address), 'fee payer is the FPC, not Alice');

  const txEffect = await node.getTxEffect(receipt.txHash);
  const effect = txEffect!.data;
  console.log(
    `public tx effects: ${effect.nullifiers.length} nullifiers, ${effect.noteHashes.length} note hashes, ` +
      `${effect.privateLogs.length} private logs, ${effect.publicLogs.length} public logs`,
  );
  check(effect.privateLogs.length === 0, 'no private logs onchain (messages go offchain)');
  check(effect.noteHashes.length === 0, 'no note hashes onchain');

  // 3. Alice uploads the encrypted messages to the MetaLeX mailbox.
  relay.post(offchainMessages);

  // 4. Bob syncs his mailbox into his own PXE.
  const toArg = (m: OffchainMessage) => ({
    ciphertext: m.payload,
    recipient: m.recipient,
    tx_hash: { _is_some: true, _value: receipt.txHash.hash },
    anchor_block_timestamp: m.anchorBlockTimestamp,
  });
  const bobMessages = relay.fetch(bob);
  check(bobMessages.length === 1, 'mailbox has one message for Bob');
  await bobRegistry.methods.offchain_receive(bobMessages.map(toArg)).simulate({ from: bob });

  const events = await bobWallet.getPrivateEvents<any>(CyberAgreementRegistryContract.events.AgreementSigned, {
    contractAddress: registry.address,
    scopes: [bob],
  });
  check(events.length === 1, 'Bob PXE decrypted one AgreementSigned event');
  const received = events[0].event;
  check(received.signer.equals(alice), 'event names Alice as signer');

  // 5. Bob opens the document from the vault and checks it against the terms hash.
  const receivedSalt = new Fr(BigInt(received.agreement.salt));
  const bobKeys = docKeysOf(receivedSalt);
  const opened = JSON.parse(decrypt(bobKeys.key, relay.getDocument(bobKeys.locator)));
  check(termsHashOf(opened).toBigInt() === BigInt(received.agreement.terms_hash), 'document matches terms hash');

  // 6. Bob checks the signature onchain. Only holders of the agreement data can do this.
  const { result: aliceSigned } = await bobRegistry.methods.is_signed(received.agreement, alice).simulate({ from: bob });
  const { result: bobSigned } = await bobRegistry.methods.is_signed(received.agreement, bob).simulate({ from: bob });
  check(aliceSigned === true, 'Alice signature exists');
  check(bobSigned === false, 'Bob has not signed yet');
  const { result: bobSideId } = await bobRegistry.methods.agreement_id(received.agreement).simulate({ from: bob });
  check(BigInt(bobSideId) === BigInt(expectedId), 'Bob derives the same agreement id');

  // 7. A second creation of the same agreement fails.
  await expectFailure(
    () => registry.methods.create_bound_contract_and_sign_for(alice, agreement, 0).send({ from: alice }),
    'second creation of the same agreement is rejected',
  );

  // 8. The network drops a tx after the agreement expiry.
  const header = (await node.getBlockData('latest'))!.header;
  const expired = agreementOf(termsHashOf(document), Fr.random(), header.globalVariables.timestamp, [alice, bob]);
  await expectFailure(
    () => registry.methods.create_bound_contract_and_sign_for(alice, expired, 0).send({ from: alice }),
    'expired agreement is rejected',
  );

  console.log('all checks passed');
  process.exit(0);
}

async function expectFailure(fn: () => Promise<unknown>, label: string) {
  try {
    await fn();
  } catch (err) {
    console.log(`ok - ${label}: ${(err as Error).message.split('\n')[0]}`);
    return;
  }
  throw new Error(`FAIL: ${label}`);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
