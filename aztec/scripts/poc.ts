// The PoC parts that `e2e.ts` and the web app share: four separate wallets (four PXEs) for Alice, Bob, the MetaLeX
// settler and an auditor, the registry, and `MetaLeXServices`. `MetaLeXServices` stands in for the MetaLeX document
// vault, signature collector and data key store.

import { createCipheriv, createDecipheriv, createHash, hkdfSync, randomBytes } from 'node:crypto';
import { getInitialTestAccountsData } from '@aztec-labs/accounts/testing';
import { deriveSecretKeyFromSigningKey } from '@aztec-labs/accounts/utils';
import { NO_FROM } from '@aztec-labs/aztec.js/account';
import { AztecAddress } from '@aztec-labs/aztec.js/addresses';
import { type AuthWitness, computeAuthWitMessageHash } from '@aztec-labs/aztec.js/authorization';
import {
  getContractClassFromArtifact,
  getContractInstanceFromInstantiationParams,
  type ContractInstanceWithAddress,
} from '@aztec-labs/aztec.js/contracts';
import { SponsoredFeePaymentMethod } from '@aztec-labs/aztec.js/fee';
import { Fq, Fr, Point } from '@aztec-labs/aztec.js/fields';
import { createAztecNodeClient, waitForNode } from '@aztec-labs/aztec.js/node';
import { poseidon2Hash } from '@aztec-labs/foundation/crypto/poseidon';
import { Schnorr, SchnorrSignature } from '@aztec-labs/foundation/crypto/schnorr';
import { SchnorrInitializerlessAccountContract } from '@aztec-labs/noir-contracts.js/SchnorrInitializerlessAccount';
import { SponsoredFPCContract } from '@aztec-labs/noir-contracts.js/SponsoredFPC';
import { computeContractAddressFromInstance } from '@aztec-labs/stdlib/contract';
import { PublicKeys } from '@aztec-labs/stdlib/keys';
import { EmbeddedWallet } from '@aztec-labs/wallets/embedded';
import { createFundedInitializerlessAccounts } from '@aztec-labs/wallets/testing';
import { CyberAgreementRegistryContract } from './artifacts/CyberAgreementRegistry.ts';
import { NETWORKS } from './deployments.ts';

export const MAX_PARTIES = 4;

export type Agreement = { terms_commitment: Fr; expiry: bigint; party_count: number; parties: AztecAddress[] };

// The public account data that a user gives MetaLeX at onboarding. The settler PXE needs it to run the authwit
// check of the user account.
export type PartyAccount = {
  address: AztecAddress;
  instance: ContractInstanceWithAddress;
  signingPublicKey: { x: Fr; y: Fr };
};

// What a party sends to the collector. It holds no salt and no terms.
export type Signature = { signer: AztecAddress; authWitness: AuthWitness };

// A data key store row. The access rule lets each party of the agreement get the salt until the retention ends.
export type DataKeyRow = { ciphertext: Buffer; parties: string[]; retainUntil: number };

export class MetaLeXServices {
  vault = new Map<string, Buffer>();
  accounts = new Map<string, PartyAccount>();
  collector = new Map<string, { agreement: Agreement; signatures: Signature[] }>();
  dataKeys = new Map<string, DataKeyRow>();
  // Stands in for ENCRYPTION_KEY in the KMS. The key never goes into a data key store row.
  encryptionKey = randomBytes(32);

  putDataKey(agreementId: Fr, salt: Fr, parties: AztecAddress[], retainUntil: number) {
    this.dataKeys.set(agreementId.toString(), {
      ciphertext: encrypt(this.encryptionKey, salt.toString()),
      parties: parties.map(p => p.toString()),
      retainUntil,
    });
  }

  // `requester` stands in for the signed-in user.
  getDataKey(agreementId: Fr, requester: AztecAddress): Fr {
    const row = this.dataKeys.get(agreementId.toString());
    if (!row) throw new Error(`no data key for ${agreementId}`);
    if (!row.parties.includes(requester.toString())) throw new Error(`access denied for ${requester}`);
    return Fr.fromString(decrypt(this.encryptionKey, row.ciphertext));
  }

  deleteExpiredDataKeys(now: number) {
    for (const [id, row] of this.dataKeys) {
      if (row.retainUntil <= now) this.dataKeys.delete(id);
    }
  }

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

// A template from the MetaLeX catalog. The document holds its full text, so the vault blob is the whole agreement
// and the terms hash commits to the exact text.
export const NDA_TEMPLATE = {
  title: 'Mutual Non-Disclosure Agreement',
  globalFields: ['effectiveDate'],
  partyFields: ['name'],
  text: [
    'Purpose. The parties want to discuss a possible business relationship (the "Purpose"). For the Purpose, each party can disclose Confidential Information to the other party.',
    'Confidential Information. "Confidential Information" is all non-public business, technical and financial information that a party (the "Discloser") discloses to the other party (the "Recipient"), in any form, that is marked confidential or that a reasonable person would think is confidential.',
    'Exclusions. Confidential Information does not include information that: (a) is public, or becomes public through no fault of the Recipient; (b) the Recipient knew before the disclosure; (c) the Recipient gets from a third party that has no duty of confidentiality; or (d) the Recipient develops independently.',
    'Obligations. The Recipient must: (a) use the Confidential Information only for the Purpose; (b) keep it confidential with at least reasonable care; and (c) disclose it only to its employees and advisers who must know it for the Purpose and who have duties of confidentiality at least as strict as this agreement.',
    'Required disclosure. If law or a court requires the Recipient to disclose Confidential Information, the Recipient must tell the Discloser promptly, if the law permits, and disclose only the part that is required.',
    'Return or destruction. When the Discloser asks, the Recipient must return or destroy all Confidential Information and confirm this in writing.',
    'No license. This agreement gives no license or other right to the Confidential Information, other than for the Purpose.',
    'Term. This agreement starts on the Effective Date. The obligations in it continue for 2 years after the last disclosure.',
    'Remedies. A breach can cause harm that money cannot fully repair. So the Discloser can ask a court for an injunction, in addition to other remedies.',
    'General. Delaware law governs this agreement. This agreement is the entire agreement of the parties on its subject. A change to it must be in writing and signed by both parties.',
  ],
};

// The document that the parties sign: the template with its full text, and the field values.
export function documentOf(effectiveDate: string, parties: [AztecAddress, string][]) {
  return {
    template: NDA_TEMPLATE,
    globalValues: [effectiveDate],
    partyValues: parties.map(([address, name]) => [address.toString(), [name]]),
  };
}

function sha256(...parts: (string | Buffer)[]): Buffer {
  const h = createHash('sha256');
  for (const p of parts) h.update(p);
  return h.digest();
}

// The terms hash commits to the canonical JSON of the document. Keys must be sorted.
export function termsHashOf(doc: object): Fr {
  return Fr.fromBufferReduce(sha256(canonicalJson(doc)));
}

export function canonicalJson(value: unknown): string {
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
export function docKeysOf(salt: Fr) {
  return {
    locator: hkdf(salt, 'metalex.doc.locator.v1').toString('hex'),
    key: hkdf(salt, 'metalex.doc.key.v1'),
  };
}

export function encrypt(key: Buffer, plaintext: string): Buffer {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const body = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), body]);
}

export function decrypt(key: Buffer, blob: Buffer): string {
  const decipher = createDecipheriv('aes-256-gcm', key, blob.subarray(0, 12));
  decipher.setAuthTag(blob.subarray(12, 28));
  return Buffer.concat([decipher.update(blob.subarray(28)), decipher.final()]).toString('utf8');
}

// The invite is what a party shares with a counterparty or an auditor. The app puts it in the URL fragment, so a
// shared link does not send it to MetaLeX.
type Invite = { salt: string; expiry: string; parties: string[] };

export function inviteOf(salt: Fr, expiry: bigint, parties: AztecAddress[]): string {
  const invite: Invite = { salt: salt.toString(), expiry: expiry.toString(), parties: parties.map(p => p.toString()) };
  return Buffer.from(JSON.stringify(invite)).toString('base64url');
}

// An invite is untrusted input, so each party address must be a valid address.
export async function readInvite(encoded: string) {
  const invite: Invite = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'));
  const parties = invite.parties.map(p => AztecAddress.fromStringUnsafe(p));
  for (const p of parties) {
    if (!(await p.isValid())) throw new Error(`invalid party address ${p}`);
  }
  return { salt: Fr.fromString(invite.salt), expiry: BigInt(invite.expiry), parties };
}

export function agreementOf(termsCommitment: Fr, expiry: bigint, parties: AztecAddress[]): Agreement {
  const padded = [...parties, ...Array(MAX_PARTIES - parties.length).fill(AztecAddress.ZERO)];
  return { terms_commitment: termsCommitment, expiry, party_count: parties.length, parties: padded };
}

// The proof of one party's signature. It holds the authwit and public account data only. The party's device stores
// it in the vault, encrypted with the document key, so each holder of the invite can check it without MetaLeX.
export type Evidence = {
  signer: string;
  signingPublicKey: { x: string; y: string };
  instance: {
    salt: string;
    deployer: string;
    originalContractClassId: string;
    initializationHash: string;
    immutablesHash: string;
    publicKeys: string;
  };
  witness: string[];
};

function evidenceLocatorOf(salt: Fr, signer: AztecAddress) {
  return hkdf(salt, `metalex.evidence.locator.v1:${signer}`).toString('hex');
}

export function putEvidence(
  metalex: MetaLeXServices,
  salt: Fr,
  signature: Signature,
  account: { instance: ContractInstanceWithAddress; signingPublicKey: { x: Fr; y: Fr } },
) {
  const { instance, signingPublicKey } = account;
  const evidence: Evidence = {
    signer: signature.signer.toString(),
    signingPublicKey: { x: signingPublicKey.x.toString(), y: signingPublicKey.y.toString() },
    instance: {
      salt: instance.salt.toString(),
      deployer: instance.deployer.toString(),
      originalContractClassId: instance.originalContractClassId.toString(),
      initializationHash: instance.initializationHash.toString(),
      immutablesHash: instance.immutablesHash.toString(),
      publicKeys: instance.publicKeys.toString(),
    },
    witness: signature.authWitness.witness.map(f => f.toString()),
  };
  metalex.putDocument(evidenceLocatorOf(salt, signature.signer), encrypt(docKeysOf(salt).key, JSON.stringify(evidence)));
}

function findEvidence(metalex: MetaLeXServices, salt: Fr, signer: AztecAddress): Evidence | undefined {
  const blob = metalex.vault.get(evidenceLocatorOf(salt, signer));
  return blob && JSON.parse(decrypt(docKeysOf(salt).key, blob));
}

// The authwit witness holds the 64-byte signature as four 16-byte limbs, in the order of `toLimbFields`.
function signatureOf(witness: string[]) {
  const [b, a, d, c] = witness.map(w => Fr.fromString(w).toBuffer().subarray(16));
  return new SchnorrSignature(Buffer.concat([a, b, c, d]));
}

let schnorrAccountClassId: Fr | undefined;

// Checks one party's evidence against `messageHash`, the authwit message hash of the agreement being checked.
async function checkSignature(evidence: Evidence, party: AztecAddress, messageHash: Fr) {
  schnorrAccountClassId ??= (await getContractClassFromArtifact(SchnorrInitializerlessAccountContract.artifact)).id;
  const key = new Point(Fr.fromString(evidence.signingPublicKey.x), Fr.fromString(evidence.signingPublicKey.y));
  const preimage = {
    version: 2 as const,
    salt: Fr.fromString(evidence.instance.salt),
    deployer: AztecAddress.fromStringUnsafe(evidence.instance.deployer),
    originalContractClassId: Fr.fromString(evidence.instance.originalContractClassId),
    initializationHash: Fr.fromString(evidence.instance.initializationHash),
    immutablesHash: Fr.fromString(evidence.instance.immutablesHash),
    publicKeys: PublicKeys.fromString(evidence.instance.publicKeys),
  };
  return {
    // The party address commits to the account preimage.
    addressMatches: (await computeContractAddressFromInstance(preimage)).equals(party),
    // The initializerless Schnorr account checks signatures with the key in its immutables.
    schnorrAccount: preimage.originalContractClassId.equals(schnorrAccountClassId),
    keyMatches: preimage.immutablesHash.equals(await poseidon2Hash([key.x, key.y])),
    signatureValid: await new Schnorr().verifySignature(messageHash, key, signatureOf(evidence.witness)),
  };
}

// Checks the two proofs that the parties signed exactly `document`, `expiry` and `parties`:
// path 1, the registry recorded the agreement as finalized; path 2, each party's stored signature is valid for it.
export async function verifyAgreement(
  reg: CyberAgreementRegistryContract,
  from: AztecAddress | typeof NO_FROM,
  metalex: MetaLeXServices,
  salt: Fr,
  expiry: bigint,
  parties: AztecAddress[],
  document: object,
) {
  const termsHash = termsHashOf(document);
  const { result: commitment } = await reg.methods.terms_commitment_of(termsHash, salt).simulate({ from });
  const agreement = agreementOf(new Fr(commitment), expiry, parties);
  const { result: id } = await reg.methods.agreement_id(agreement).simulate({ from });
  const { result: finalized } = await reg.methods.is_finalized(agreement).simulate({ from });
  const chainInfo = await reg.wallet.getChainInfo();
  const signatures = [];
  for (const party of parties) {
    const evidence = findEvidence(metalex, salt, party);
    if (!evidence) {
      signatures.push({ party: party.toString(), evidenceFound: false });
      continue;
    }
    const { result: consent } = await reg.methods.consent_hash_of(agreement, party).simulate({ from });
    const messageHash = await computeAuthWitMessageHash(
      { consumer: reg.address, innerHash: new Fr(consent) },
      chainInfo,
    );
    signatures.push({ party: party.toString(), evidenceFound: true, ...(await checkSignature(evidence, party, messageHash)) });
  }
  const signed = signatures.every(
    s => s.evidenceFound && s.addressMatches && s.schnorrAccount && s.keyMatches && s.signatureValid,
  );
  return {
    termsHash: termsHash.toString(),
    agreementId: new Fr(id).toString(),
    finalized: finalized as boolean,
    signed,
    signatures,
  };
}

// The webapp opens an invite: it fetches and checks the document, and reads the status from the chain.
export async function openInvite(
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
  return { agreement, agreementId: new Fr(id), document, locator, finalized: finalized as boolean };
}

// A node behind a free RPC plan can refuse large JSON-RPC batches. `AZTEC_NODE_MAX_BATCH_SIZE` caps each batch.
export function nodeClientOptions() {
  const maxBatchSize = process.env.AZTEC_NODE_MAX_BATCH_SIZE;
  return maxBatchSize ? { maxBatchSize: Number(maxBatchSize) } : {};
}

// A wallet with its own PXE and in-memory stores.
export function walletAt(nodeUrl: string) {
  return EmbeddedWallet.create(nodeUrl, { ephemeral: true, nodeClientOptions: nodeClientOptions() });
}

type AccountType = 'schnorr' | 'schnorr_initializerless';

// The keys that `aztec-wallet create-account` printed for an account.
export type AccountKeys = { type: AccountType; signingKey: Fq; salt: Fr };

function envOf(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

// The settler can be any account type. A party must be initializerless, so that the settler PXE can run its
// authwit check.
export function keysFromEnv(prefix: string, type?: AccountType): AccountKeys {
  const accountType = type ?? (process.env[`${prefix}_ACCOUNT_TYPE`] ?? 'schnorr');
  if (accountType !== 'schnorr' && accountType !== 'schnorr_initializerless') {
    throw new Error(`unsupported ${prefix}_ACCOUNT_TYPE ${accountType}`);
  }
  return {
    type: accountType,
    signingKey: Fq.fromHexString(envOf(`${prefix}_SIGNING_KEY`)),
    salt: Fr.fromHexString(process.env[`${prefix}_SALT`] ?? '0x0'),
  };
}

// Gives the same address as `aztec-wallet create-account` with the same keys: the CLI derives the secret key from
// the signing key.
export async function accountOf(wallet: EmbeddedWallet, keys: AccountKeys) {
  const secret = await deriveSecretKeyFromSigningKey(keys.signingKey);
  return keys.type === 'schnorr'
    ? wallet.createSchnorrAccount(secret, keys.salt, keys.signingKey)
    : wallet.createSchnorrInitializerlessAccount(secret, keys.salt, keys.signingKey);
}

// The SponsoredFPC has the same address on the local network and on the testnet:
// 0x2d8fff82a3b0c15d0a89169e7d8d043e079ab94d52031f1de1e4972ebad169d3 for Aztec 6.0.0.
export async function sponsoredFpcIn(...wallets: EmbeddedWallet[]) {
  const fpc = await getContractInstanceFromInstantiationParams(SponsoredFPCContract.artifact, { salt: new Fr(0) });
  for (const wallet of wallets) await wallet.registerContract(fpc, SponsoredFPCContract.artifact);
  return { address: fpc.address, fee: { paymentMethod: new SponsoredFeePaymentMethod(fpc.address) } };
}

// The registry of the environment `DEPLOY_SALT_LABEL` on the network of `node`, as `deployments.ts` records it.
// `deploy.ts` deploys and records it.
async function recordedRegistryInstance(node: ReturnType<typeof createAztecNodeClient>) {
  const label = envOf('DEPLOY_SALT_LABEL');
  const { l1ChainId } = await node.getNodeInfo();
  const recorded = NETWORKS[l1ChainId]?.deployments[label]?.registry;
  if (!recorded) {
    throw new Error(`deployments.ts has no registry for ${label} on L1 chain id ${l1ChainId}. Run deploy.ts first`);
  }
  const instance = await node.getContract(AztecAddress.fromStringUnsafe(recorded));
  if (!instance) throw new Error(`no contract instance at ${recorded}`);
  return instance;
}

// Starts the four wallets and onboards Alice and Bob.
//
// With `SETTLER_SIGNING_KEY` set, for example on the testnet, the accounts come from the env (`SETTLER_*`,
// `ALICE_*`, `BOB_*`). Without it, the local network test accounts are used. The registry is the one that
// `deployments.ts` records for `DEPLOY_SALT_LABEL` on the network.
export async function startPoc(nodeUrl: string) {
  const node = createAztecNodeClient(nodeUrl, nodeClientOptions());
  await waitForNode(node);
  const fromEnv = process.env.SETTLER_SIGNING_KEY !== undefined;

  const aliceWallet = await walletAt(nodeUrl);
  const bobWallet = await walletAt(nodeUrl);
  const settlerWallet = await walletAt(nodeUrl);
  const auditorWallet = await walletAt(nodeUrl);

  const [aliceKeys, bobKeys] = fromEnv
    ? [keysFromEnv('ALICE', 'schnorr_initializerless'), keysFromEnv('BOB', 'schnorr_initializerless')]
    : [];
  const [aliceData, bobData, settlerData] = fromEnv ? [] : await getInitialTestAccountsData();
  const [aliceAccount, bobAccount, settlerAccount] = fromEnv
    ? [
        await accountOf(aliceWallet, aliceKeys!),
        await accountOf(bobWallet, bobKeys!),
        await accountOf(settlerWallet, keysFromEnv('SETTLER')),
      ]
    : [
        (await createFundedInitializerlessAccounts(aliceWallet, [aliceData]))[0],
        (await createFundedInitializerlessAccounts(bobWallet, [bobData]))[0],
        (await createFundedInitializerlessAccounts(settlerWallet, [settlerData]))[0],
      ];
  const alice = aliceAccount.address;
  const bob = bobAccount.address;
  const settler = settlerAccount.address;
  const metalex = new MetaLeXServices();

  // The public account data of each party. Onboarding gives it to MetaLeX. The party also puts it in its evidence.
  const publicAccountOf = async (account: typeof aliceAccount, signingKey: Fq) => ({
    address: account.address,
    instance: account.getInstance(),
    signingPublicKey: await new Schnorr().computePublicKey(signingKey),
  });
  const aliceAccountData = await publicAccountOf(aliceAccount, aliceKeys?.signingKey ?? aliceData.signingKey);
  const bobAccountData = await publicAccountOf(bobAccount, bobKeys?.signingKey ?? bobData.signingKey);
  metalex.onboard(aliceAccountData);
  metalex.onboard(bobAccountData);

  // On mainnet, MetaLeX runs its own fee payer. The parties need the FPC only to withdraw a consent.
  const sponsored = await sponsoredFpcIn(settlerWallet, aliceWallet, bobWallet);

  // MetaLeX deploys the registry once with `deploy.ts`. Any wallet can then register it.
  const instance = await recordedRegistryInstance(node);
  await settlerWallet.registerContract(instance, CyberAgreementRegistryContract.artifact);
  const registry = await CyberAgreementRegistryContract.at(instance.address, settlerWallet);
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
      .send({ from: settler, additionalScopes: parties, fee: sponsored.fee });
  };

  // A party withdraws its consent with its own tx. The FPC pays the fee.
  const withdraw = (reg: CyberAgreementRegistryContract, party: AztecAddress, agreement: Agreement) =>
    reg.methods.withdraw_consent(agreement).send({ from: party, fee: sponsored.fee });

  return {
    node,
    fpc: sponsored.address,
    registry: registry.address,
    metalex,
    alice: { ...aliceAccountData, wallet: aliceWallet, registry: aliceRegistry },
    bob: { ...bobAccountData, wallet: bobWallet, registry: bobRegistry },
    auditor: { wallet: auditorWallet, registry: auditorRegistry },
    settler,
    sign,
    settle,
    withdraw,
  };
}
