// The PoC parts that `e2e.ts` and the web app share: four separate wallets (four PXEs) for Alice, Bob, the MetaLeX
// settler and an auditor, the registry, and `MetaLeXServices`. `MetaLeXServices` stands in for the MetaLeX document
// vault, signature collector and data key store.

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

// Starts the four wallets, onboards Alice and Bob, and deploys the registry with the settler.
export async function startPoc(nodeUrl: string) {
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

  return {
    node,
    fpc: fpc.address,
    registry: registry.address,
    metalex,
    alice: { address: alice, wallet: aliceWallet, registry: aliceRegistry },
    bob: { address: bob, wallet: bobWallet, registry: bobRegistry },
    auditor: { wallet: auditorWallet, registry: auditorRegistry },
    settler,
    sign,
    settle,
  };
}
