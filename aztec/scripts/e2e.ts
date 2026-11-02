// Runs the agreement lifecycle on a local Aztec network with four separate wallets (four PXEs): Alice, Bob, the
// MetaLeX settler and an auditor. `MetaLeXServices` stands in for the MetaLeX document vault and signature collector.
//
// Usage: AZTEC_NODE_URL=http://localhost:8090 node e2e.ts

import { createCipheriv, createDecipheriv, createHash, hkdfSync, randomBytes } from 'node:crypto';
import { getInitialTestAccountsData } from '@aztec-labs/accounts/testing';
import { NO_FROM } from '@aztec-labs/aztec.js/account';
import { AztecAddress } from '@aztec-labs/aztec.js/addresses';
import type { AuthWitness } from '@aztec-labs/aztec.js/authorization';
import { getContractInstanceFromInstantiationParams, type ContractInstanceWithAddress } from '@aztec-labs/aztec.js/contracts';
import { SponsoredFeePaymentMethod } from '@aztec-labs/aztec.js/fee';
import { Fr } from '@aztec-labs/aztec.js/fields';
import { createAztecNodeClient, waitForNode } from '@aztec-labs/aztec.js/node';
import { Schnorr } from '@aztec-labs/foundation/crypto/schnorr';
import { SchnorrInitializerlessAccountContract } from '@aztec-labs/noir-contracts.js/SchnorrInitializerlessAccount';
import { SponsoredFPCContract } from '@aztec-labs/noir-contracts.js/SponsoredFPC';
import { EmbeddedWallet } from '@aztec-labs/wallets/embedded';
import { createFundedInitializerlessAccounts } from '@aztec-labs/wallets/testing';
import { CyberAgreementRegistryContract } from './artifacts/CyberAgreementRegistry.ts';

const MAX_PARTIES = 4;

type Agreement = { terms_commitment: Fr; expiry: bigint; party_count: number; parties: AztecAddress[] };

// The public account data that a user gives MetaLeX at onboarding. The settler PXE needs it to run the authwit
// check of the user account.
type PartyAccount = { address: AztecAddress; instance: ContractInstanceWithAddress; signingPublicKey: { x: Fr; y: Fr } };

// What a party sends to the collector. It holds no salt and no terms.
type Signature = { signer: AztecAddress; authWitness: AuthWitness };

class MetaLeXServices {
  vault = new Map<string, Buffer>();
  accounts = new Map<string, PartyAccount>();
  collector = new Map<string, { agreement: Agreement; signatures: Signature[] }>();

  onboard(account: PartyAccount) {
    this.accounts.set(account.address.toString(), account);
  }

  accountOf(address: AztecAddress): PartyAccount {
    const account = this.accounts.get(address.toString());
    if (!account) throw new Error(`no onboarded account ${address}`);
    return account;
  }

  putDocument(locator: string, ciphertext: Buffer) {
    this.vault.set(locator, ciphertext);
  }

  getDocument(locator: string): Buffer {
    const doc = this.vault.get(locator);
    if (!doc) throw new Error(`no document at ${locator}`);
    return doc;
  }

  submitSignature(agreementId: Fr, agreement: Agreement, signature: Signature) {
    const entry = this.collector.get(agreementId.toString()) ?? { agreement, signatures: [] };
    entry.signatures.push(signature);
    this.collector.set(agreementId.toString(), entry);
  }

  pendingSigners(agreementId: Fr): AztecAddress[] {
    const entry = this.collector.get(agreementId.toString())!;
    const signed = entry.signatures.map(s => s.signer.toString());
    return entry.agreement.parties
      .slice(0, entry.agreement.party_count)
      .filter(p => !signed.includes(p.toString()));
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

// The invite is what a party shares with a counterparty or an auditor. The app puts it in the URL fragment, so the
// MetaLeX servers never receive it.
type Invite = { salt: string; expiry: string; parties: string[] };

function inviteOf(salt: Fr, expiry: bigint, parties: AztecAddress[]): string {
  const invite: Invite = { salt: salt.toString(), expiry: expiry.toString(), parties: parties.map(p => p.toString()) };
  return Buffer.from(JSON.stringify(invite)).toString('base64url');
}

// An invite is untrusted input, so each party address must be a valid address.
async function readInvite(encoded: string) {
  const invite: Invite = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'));
  const parties = invite.parties.map(p => AztecAddress.fromStringUnsafe(p));
  for (const p of parties) {
    if (!(await p.isValid())) throw new Error(`invalid party address ${p}`);
  }
  return { salt: Fr.fromString(invite.salt), expiry: BigInt(invite.expiry), parties };
}

function agreementOf(termsCommitment: Fr, expiry: bigint, parties: AztecAddress[]): Agreement {
  const padded = [...parties, ...Array(MAX_PARTIES - parties.length).fill(AztecAddress.ZERO)];
  return { terms_commitment: termsCommitment, expiry, party_count: parties.length, parties: padded };
}

function check(condition: boolean, label: string) {
  if (!condition) throw new Error(`FAIL: ${label}`);
  console.log(`ok - ${label}`);
}

async function main() {
  const nodeUrl = process.env.AZTEC_NODE_URL ?? 'http://localhost:8080';
  const node = createAztecNodeClient(nodeUrl);
  await waitForNode(node);

  const [aliceData, bobData, settlerData] = await getInitialTestAccountsData();
  const aliceWallet = await EmbeddedWallet.create(nodeUrl, { ephemeral: true });
  const bobWallet = await EmbeddedWallet.create(nodeUrl, { ephemeral: true });
  const settlerWallet = await EmbeddedWallet.create(nodeUrl, { ephemeral: true });
  const auditorWallet = await EmbeddedWallet.create(nodeUrl, { ephemeral: true });
  const [aliceAccount] = await createFundedInitializerlessAccounts(aliceWallet, [aliceData]);
  const [bobAccount] = await createFundedInitializerlessAccounts(bobWallet, [bobData]);
  const [settlerAccount] = await createFundedInitializerlessAccounts(settlerWallet, [settlerData]);
  const alice = aliceAccount.address;
  const bob = bobAccount.address;
  const settler = settlerAccount.address;
  const metalex = new MetaLeXServices();

  // Onboarding: each user gives MetaLeX its address, account instance and signing public key.
  for (const [account, data] of [
    [aliceAccount, aliceData],
    [bobAccount, bobData],
  ] as const) {
    const signingPublicKey = await new Schnorr().computePublicKey(data.signingKey);
    metalex.onboard({ address: account.address, instance: account.getInstance(), signingPublicKey });
  }

  // The local network has a sponsored FPC. On mainnet, MetaLeX runs its own fee payer.
  const fpc = await getContractInstanceFromInstantiationParams(SponsoredFPCContract.artifact, { salt: new Fr(0) });
  await settlerWallet.registerContract(fpc, SponsoredFPCContract.artifact);
  const sponsored = { fee: { paymentMethod: new SponsoredFeePaymentMethod(fpc.address) } };

  // MetaLeX deploys the registry once. Any wallet can then register it.
  const { contract: registry, instance } = await CyberAgreementRegistryContract.deploy(settlerWallet).send({
    from: settler,
  });
  console.log(`registry deployed at ${registry.address}`);
  const registryIn = async (wallet: EmbeddedWallet) => {
    await wallet.registerContract(instance, CyberAgreementRegistryContract.artifact);
    return CyberAgreementRegistryContract.at(registry.address, wallet);
  };
  const aliceRegistry = await registryIn(aliceWallet);
  const bobRegistry = await registryIn(bobWallet);
  const auditorRegistry = await registryIn(auditorWallet);

  // A party signs in its own wallet. It sends only the authwit.
  const sign = async (
    wallet: EmbeddedWallet,
    reg: CyberAgreementRegistryContract,
    signer: AztecAddress,
    agreement: Agreement,
  ): Promise<Signature> => {
    const { result: innerHash } = await reg.methods.consent_hash_of(agreement, signer).simulate({ from: signer });
    const authWitness = await wallet.createAuthWit(signer, { consumer: registry.address, innerHash: new Fr(innerHash) });
    return { signer, authWitness };
  };

  // The settler registers each party account and stores its public key. The account checks the key against its
  // immutables hash. No secret of the party is needed. The party addresses are scopes only so that the settler PXE
  // can read the stored keys.
  const registered = new Set<string>();
  const settle = async (agreement: Agreement, signatures: Signature[]) => {
    const parties = agreement.parties.slice(0, agreement.party_count);
    for (const party of parties.filter(p => !registered.has(p.toString()))) {
      const { instance: account, signingPublicKey } = metalex.accountOf(party);
      await settlerWallet.registerContract(account, SchnorrInitializerlessAccountContract.artifact);
      await SchnorrInitializerlessAccountContract.at(party, settlerWallet)
        .methods.constructor(signingPublicKey.x, signingPublicKey.y)
        .simulate({ from: NO_FROM, additionalScopes: [party] });
      registered.add(party.toString());
    }
    return registry.methods
      .finalize(agreement)
      .with({ authWitnesses: signatures.map(s => s.authWitness) })
      .send({ from: settler, additionalScopes: parties, ...sponsored });
  };

  // 1. Alice drafts the document in the MetaLeX webapp. It never goes onchain.
  const document = {
    template: { title: 'Mutual NDA', uri: 'ipfs://example-template', globalFields: ['effectiveDate'], partyFields: ['name'] },
    globalValues: ['2026-11-01'],
    partyValues: [
      [alice.toString(), ['Alice Corp']],
      [bob.toString(), ['Bob LLC']],
    ],
  };
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
  check(tx !== undefined && tx.data.feePayer.equals(fpc.address), 'fee payer is the FPC');
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

  // 6. A second finalize of the same agreement fails.
  await expectFailure(() => settle(collected.agreement, collected.signatures), 'second finalize is rejected', 'nullifier');

  // 7. A one-party agreement gives the same nullifier count, so the chain does not show the party count.
  const solo = agreementOf(Fr.random(), 0n, [alice]);
  const { result: soloIdRaw } = await aliceRegistry.methods.agreement_id(solo).simulate({ from: alice });
  metalex.submitSignature(new Fr(soloIdRaw), solo, await sign(aliceWallet, aliceRegistry, alice, solo));
  const { receipt: soloReceipt } = await settle(solo, metalex.collector.get(new Fr(soloIdRaw).toString())!.signatures);
  const soloEffect = (await node.getTxEffect(soloReceipt.txHash))!.data;
  check(soloEffect.nullifiers.length === effect.nullifiers.length, `same nullifier count for one and two parties (${effect.nullifiers.length})`);

  // 8. The network drops a finalize after the agreement expiry.
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

// The webapp opens an invite: it fetches and checks the document, and reads the status from the chain.
async function openInvite(
  reg: CyberAgreementRegistryContract,
  from: AztecAddress | typeof NO_FROM,
  invite: string,
  metalex: MetaLeXServices,
) {
  const { salt, expiry, parties } = await readInvite(invite);
  const { locator, key } = docKeysOf(salt);
  const document = JSON.parse(decrypt(key, metalex.getDocument(locator)));
  const { result: termsCommitment } = await reg.methods.terms_commitment_of(termsHashOf(document), salt).simulate({ from });
  const agreement = agreementOf(new Fr(termsCommitment), expiry, parties);
  const { result: id } = await reg.methods.agreement_id(agreement).simulate({ from });
  const { result: finalized } = await reg.methods.is_finalized(agreement).simulate({ from });
  return { agreement, agreementId: new Fr(id), document, finalized: finalized as boolean };
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
