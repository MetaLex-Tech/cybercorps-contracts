// The user device. It runs in the browser: the signing key, the salt and the document never leave it, except as
// ciphertext, authwits and public account data.

import { getSchnorrInitializerlessAccountContractAddress } from '@aztec-labs/accounts/schnorr';
import { deriveSecretKeyFromSigningKey } from '@aztec-labs/accounts/utils';
import { NO_FROM } from '@aztec-labs/aztec.js/account';
import { AztecAddress } from '@aztec-labs/aztec.js/addresses';
import { computeAuthWitMessageHash } from '@aztec-labs/aztec.js/authorization';
import { getContractClassFromArtifact } from '@aztec-labs/aztec.js/contracts';
import { Fq, Fr, GrumpkinScalar, Point } from '@aztec-labs/aztec.js/fields';
import { createAztecNodeClient } from '@aztec-labs/aztec.js/node';
import { TxHash } from '@aztec-labs/aztec.js/tx';
import { poseidon2Hash } from '@aztec-labs/foundation/crypto/poseidon';
import { Schnorr, SchnorrSignature } from '@aztec-labs/foundation/crypto/schnorr';
import { SchnorrInitializerlessAccountContract } from '@aztec-labs/noir-contracts.js/SchnorrInitializerlessAccount';
import { computeContractAddressFromInstance } from '@aztec-labs/stdlib/contract';
import { openTmpStore } from '@aztec-labs/kv-store/sqlite-opfs';
import { EmbeddedWallet } from '@aztec-labs/wallets/embedded';
import { CyberAgreementRegistryContract } from '../artifacts/CyberAgreementRegistry';
import {
  type AgreementDocument,
  agreementOf,
  agreementToJson,
  decodeInvite,
  decryptWithSalt,
  docKeysOf,
  documentOf,
  type Evidence,
  encodeInvite,
  encryptWithSalt,
  evidenceLocatorOf,
  type PublicAccount,
  termsHashOf,
} from '../shared/agreement';
import { instanceOf, publicAccountOf } from '../shared/instance';
import {
  getBlob,
  getConfig,
  getSigners,
  listMyAgreements,
  onboard,
  putBlob,
  putDataKey,
  submitSignature,
} from '../server/metalex';

export type Role = 'alice' | 'bob' | 'auditor';
export const ROLE_NAMES: Record<Role, string> = { alice: 'Alice', bob: 'Bob', auditor: 'Auditor' };

const base64 = (bytes: Uint8Array) => Buffer.from(bytes).toString('base64');
const fromBase64 = (text: string) => new Uint8Array(Buffer.from(text, 'base64'));

// Each role keeps its own signing key in this browser. A party account is initializerless, so it needs no deploy.
const keyName = (role: Role) => `signing-key:${role}`;

export function storedSigningKey(role: Role): string | null {
  try {
    return localStorage.getItem(keyName(role));
  } catch {
    return null;
  }
}

// The address of a role's account in this browser. It makes the role's key if the role's page has not run yet, so
// the address is the one that the role's page uses.
export async function addressOf(role: Role) {
  return (await getSchnorrInitializerlessAccountContractAddress(signingKeyOf(role), Fr.ZERO)).toString();
}

export function setSigningKey(role: Role, key: string) {
  Fq.fromHexString(key);
  localStorage.setItem(keyName(role), key);
}

function signingKeyOf(role: Role): Fq {
  const stored = storedSigningKey(role);
  if (stored) return Fq.fromHexString(stored);
  const key = GrumpkinScalar.random();
  setSigningKey(role, key.toString());
  return key;
}

export type Device = Awaited<ReturnType<typeof startDevice>>;

// The wallet runs one operation at a time.
function serial() {
  let queue: Promise<unknown> = Promise.resolve();
  return <T,>(fn: () => Promise<T>): Promise<T> => {
    const run = queue.then(fn);
    queue = run.catch(() => undefined);
    return run;
  };
}

async function startDevice(role: Role) {
  const config = await getConfig();
  const nodeClientOptions = config.maxBatchSize ? { maxBatchSize: config.maxBatchSize } : {};
  const node = createAztecNodeClient(config.nodeUrl, nodeClientOptions);
  // Each tab gets its own in-memory PXE store. The default store is named after the chain only, so a second tab of
  // this origin (Alice and Bob) could not open it. The keys stay in localStorage, so nothing is lost on reload.
  const wallet = await EmbeddedWallet.create(config.nodeUrl, {
    ephemeral: true,
    nodeClientOptions,
    pxe: { store: await openTmpStore(true) },
  });
  const registryAddress = AztecAddress.fromStringUnsafe(config.registry);
  const instance = await node.getContract(registryAddress);
  if (!instance) throw new Error(`no registry at ${registryAddress}`);
  await wallet.registerContract(instance, CyberAgreementRegistryContract.artifact);
  const registry = CyberAgreementRegistryContract.at(registryAddress, wallet);

  let address: AztecAddress | undefined;
  let publicAccount: PublicAccount | undefined;
  if (role !== 'auditor') {
    const signingKey = signingKeyOf(role);
    const secret = await deriveSecretKeyFromSigningKey(signingKey);
    const account = await wallet.createSchnorrInitializerlessAccount(secret, Fr.ZERO, signingKey);
    address = account.address;
    publicAccount = publicAccountOf(account.getInstance(), await new Schnorr().computePublicKey(signingKey));
    await onboard({ data: { name: ROLE_NAMES[role], account: publicAccount } });
  }
  return { role, config, node, wallet, registry, address, publicAccount, run: serial() };
}

const devices = new Map<Role, Promise<Device>>();

export function deviceOf(role: Role) {
  if (!devices.has(role)) devices.set(role, startDevice(role));
  return devices.get(role)!;
}

const from = (device: Device) => device.address ?? NO_FROM;

async function agreementIdOf(device: Device, document: object, salt: Fr, expiry: bigint, parties: AztecAddress[]) {
  const { result: commitment } = await device.registry.methods
    .terms_commitment_of(await termsHashOf(document), salt)
    .simulate({ from: from(device) });
  const agreement = agreementOf(new Fr(commitment), expiry, parties);
  const { result: id } = await device.registry.methods.agreement_id(agreement).simulate({ from: from(device) });
  return { agreement, agreementId: new Fr(id) };
}

// The party signs with an authwit and stores the proof of its signature in the vault.
async function signAgreement(device: Device, salt: Fr, agreementId: Fr, agreement: ReturnType<typeof agreementOf>) {
  const signer = device.address!;
  const { result: innerHash } = await device.registry.methods
    .consent_hash_of(agreement, signer)
    .simulate({ from: signer });
  const authwit = await device.wallet.createAuthWit(signer, {
    consumer: device.registry.address,
    innerHash: new Fr(innerHash),
  });
  const evidence: Evidence = { ...device.publicAccount!, authwit: authwit.toString() };
  await putBlob({
    data: {
      locator: await evidenceLocatorOf(salt, signer.toString()),
      blob: base64(await encryptWithSalt(salt, JSON.stringify(evidence))),
    },
  });
  await submitSignature({
    data: {
      agreementId: agreementId.toString(),
      agreement: agreementToJson(agreement),
      signer: signer.toString(),
      authwit: authwit.toString(),
    },
  });
}

export type Draft = {
  title: string;
  clauses: string[];
  effectiveDate: string;
  myName: string;
  counterparty: string;
  theirName: string;
  expiry: string;
};

// Draft, encrypt, upload and sign a new agreement. Only this device sees the salt and the document in plaintext.
export function createAgreement(device: Device, draft: Draft) {
  return device.run(async () => {
    const me = device.address!;
    const counterparty = AztecAddress.fromStringUnsafe(draft.counterparty);
    if (!(await counterparty.isValid())) throw new Error(`invalid party address ${counterparty}`);
    const parties = [me, counterparty];
    const document = documentOf(
      draft.effectiveDate,
      [
        [me.toString(), draft.myName],
        [counterparty.toString(), draft.theirName],
      ],
      { title: draft.title, text: draft.clauses },
    );
    const expiry = draft.expiry ? BigInt(Math.floor(new Date(draft.expiry).getTime() / 1000)) : 0n;
    const salt = Fr.random();
    const { agreement, agreementId } = await agreementIdOf(device, document, salt, expiry, parties);
    const { locator } = await docKeysOf(salt);
    await putBlob({ data: { locator, blob: base64(await encryptWithSalt(salt, JSON.stringify(document))) } });
    await putDataKey({
      data: { agreementId: agreementId.toString(), salt: salt.toString(), parties: parties.map(p => p.toString()) },
    });
    await signAgreement(device, salt, agreementId, agreement);
    return { invite: encodeInvite({ salt, expiry, parties }), agreementId: agreementId.toString() };
  });
}

export type AgreementView = Awaited<ReturnType<typeof openInvite>>;

// Fetch and decrypt the document, compute the agreement id and read the status from the chain.
export function openInvite(device: Device, encoded: string) {
  return device.run(async () => {
    const invite = await decodeInvite(encoded);
    const { locator } = await docKeysOf(invite.salt);
    const { blob } = await getBlob({ data: { locator } });
    if (!blob) throw new Error(`no document at ${locator}`);
    const document: AgreementDocument = JSON.parse(await decryptWithSalt(invite.salt, fromBase64(blob)));
    const { agreement, agreementId } = await agreementIdOf(device, document, invite.salt, invite.expiry, invite.parties);
    const { result: finalized } = await device.registry.methods.is_finalized(agreement).simulate({ from: from(device) });
    const parties = invite.parties.map(p => p.toString());
    const isParty = device.address !== undefined && parties.includes(device.address.toString());
    const signers = isParty
      ? await getSigners({ data: { agreementId: agreementId.toString(), requester: device.address!.toString() } })
      : null;
    return {
      invite: encoded,
      agreementId: agreementId.toString(),
      document,
      finalized: finalized as boolean,
      expiry: invite.expiry.toString(),
      parties,
      locator,
      isParty,
      signers,
    };
  });
}

export function signInvite(device: Device, encoded: string) {
  return device.run(async () => {
    const invite = await decodeInvite(encoded);
    const { locator } = await docKeysOf(invite.salt);
    const { blob } = await getBlob({ data: { locator } });
    if (!blob) throw new Error(`no document at ${locator}`);
    const document = JSON.parse(await decryptWithSalt(invite.salt, fromBase64(blob)));
    const { agreement, agreementId } = await agreementIdOf(device, document, invite.salt, invite.expiry, invite.parties);
    await signAgreement(device, invite.salt, agreementId, agreement);
  });
}

// The agreements that the data key store lets this party open, as invites.
export async function myAgreements(device: Device) {
  const rows = await listMyAgreements({ data: { requester: device.address!.toString() } });
  return rows.map(r =>
    encodeInvite({
      salt: Fr.fromString(r.salt),
      expiry: BigInt(r.expiry),
      parties: r.parties.map(p => AztecAddress.fromStringUnsafe(p)),
    }),
  );
}

export async function txStatusOf(device: Device, txHash: string) {
  const receipt = await device.node.getTxReceipt(TxHash.fromString(txHash));
  return { status: receipt.status as string, block: receipt.blockNumber ? Number(receipt.blockNumber) : undefined };
}

// The authwit witness holds the 64-byte signature as four 16-byte limbs, in the order of `toLimbFields`.
function signatureOf(witness: Fr[]) {
  const [b, a, d, c] = witness.map(w => w.toBuffer().subarray(16));
  return new SchnorrSignature(Buffer.concat([a, b, c, d]));
}

let schnorrAccountClassId: Fr | undefined;

// Checks one party's evidence against the authwit message hash of the agreement being checked.
async function checkSignature(evidence: Evidence, party: AztecAddress, messageHash: Fr) {
  const { AuthWitness } = await import('@aztec-labs/aztec.js/authorization');
  schnorrAccountClassId ??= (await getContractClassFromArtifact(SchnorrInitializerlessAccountContract.artifact)).id;
  const key = new Point(Fr.fromString(evidence.signingPublicKey.x), Fr.fromString(evidence.signingPublicKey.y));
  const instance = instanceOf(evidence);
  return {
    // The party address commits to the account preimage.
    addressMatches: (await computeContractAddressFromInstance(instance)).equals(party),
    // The initializerless Schnorr account checks signatures with the key in its immutables.
    schnorrAccount: instance.originalContractClassId.equals(schnorrAccountClassId),
    keyMatches: instance.immutablesHash.equals(await poseidon2Hash([key.x, key.y])),
    signatureValid: await new Schnorr().verifySignature(
      messageHash,
      key,
      signatureOf(AuthWitness.fromString(evidence.authwit).witness),
    ),
  };
}

export type Proofs = Awaited<ReturnType<typeof verifyTerms>>;

// Checks two proofs that the parties signed exactly these terms: path 1, the registry recorded the agreement as
// finalized; path 2, each party's stored signature is valid for it. The salt comes from the invite.
export function verifyTerms(device: Device, encoded: string, expiry: string, parties: string[], document: object) {
  return device.run(async () => {
    const { salt } = await decodeInvite(encoded);
    const addresses = parties.map(p => AztecAddress.fromStringUnsafe(p));
    for (const a of addresses) {
      if (!(await a.isValid())) throw new Error(`invalid party address ${a}`);
    }
    const { agreement, agreementId } = await agreementIdOf(device, document, salt, BigInt(expiry), addresses);
    const { result: finalized } = await device.registry.methods.is_finalized(agreement).simulate({ from: NO_FROM });
    const chainInfo = await device.wallet.getChainInfo();
    const signatures = [];
    for (const party of addresses) {
      const { blob } = await getBlob({ data: { locator: await evidenceLocatorOf(salt, party.toString()) } });
      if (!blob) {
        signatures.push({ party: party.toString(), evidenceFound: false as const });
        continue;
      }
      const evidence: Evidence = JSON.parse(await decryptWithSalt(salt, fromBase64(blob)));
      const { result: consent } = await device.registry.methods.consent_hash_of(agreement, party).simulate({
        from: NO_FROM,
      });
      const messageHash = await computeAuthWitMessageHash(
        { consumer: device.registry.address, innerHash: new Fr(consent) },
        chainInfo,
      );
      signatures.push({
        party: party.toString(),
        evidenceFound: true as const,
        ...(await checkSignature(evidence, party, messageHash)),
      });
    }
    const signed = signatures.every(
      s => s.evidenceFound && s.addressMatches && s.schnorrAccount && s.keyMatches && s.signatureValid,
    );
    return { agreementId: agreementId.toString(), finalized: finalized as boolean, signed, signatures };
  });
}
