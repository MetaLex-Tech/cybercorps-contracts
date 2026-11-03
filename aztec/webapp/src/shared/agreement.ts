// The agreement model that the browser (the user device) and the server share. The browser holds the salt and the
// document. The server holds only what MetaLeX may see.

import { AztecAddress } from '@aztec-labs/aztec.js/addresses';
import { Fr } from '@aztec-labs/aztec.js/fields';
import { decrypt, encrypt, fromBase64Url, hkdf, sha256, toBase64Url, toHex } from './crypto';
import { NDA_TEMPLATE } from './template';

export const MAX_PARTIES = 4;

export { NDA_TEMPLATE };

export type AgreementDocument = {
  template: typeof NDA_TEMPLATE;
  globalValues: string[];
  partyValues: [string, string[]][];
};

export function documentOf(effectiveDate: string, parties: [string, string][]): AgreementDocument {
  return {
    template: NDA_TEMPLATE,
    globalValues: [effectiveDate],
    partyValues: parties.map(([address, name]) => [address, [name]]),
  };
}

// RFC 8785 (JCS) for strings, numbers, arrays and objects: keys sorted, no white space.
export function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value && typeof value === 'object') {
    const entries = Object.entries(value).sort(([a], [b]) => (a < b ? -1 : 1));
    return `{${entries.map(([k, v]) => `${JSON.stringify(k)}:${canonicalJson(v)}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

export async function termsHashOf(document: object): Promise<Fr> {
  return Fr.fromBufferReduce(Buffer.from(await sha256(canonicalJson(document))));
}

// The salt gives the vault locator and the document key. MetaLeX sees only the locator.
export async function docKeysOf(salt: Fr) {
  const ikm = salt.toBuffer();
  return {
    locator: toHex(await hkdf(ikm, 'metalex.doc.locator.v1')),
    key: await hkdf(ikm, 'metalex.doc.key.v1'),
  };
}

export async function evidenceLocatorOf(salt: Fr, signer: string) {
  return toHex(await hkdf(salt.toBuffer(), `metalex.evidence.locator.v1:${signer}`));
}

export async function encryptWithSalt(salt: Fr, plaintext: string) {
  return encrypt((await docKeysOf(salt)).key, plaintext);
}

export async function decryptWithSalt(salt: Fr, blob: Uint8Array) {
  return decrypt((await docKeysOf(salt)).key, blob);
}

// The invite is what a party shares with a counterparty or an auditor. The app puts it in the URL fragment, so a
// shared link does not send it to MetaLeX.
export type Invite = { salt: Fr; expiry: bigint; parties: AztecAddress[] };

export function encodeInvite(invite: Invite): string {
  return toBase64Url(
    JSON.stringify({
      salt: invite.salt.toString(),
      expiry: invite.expiry.toString(),
      parties: invite.parties.map(p => p.toString()),
    }),
  );
}

// An invite is untrusted input, so each party address must be a valid address.
export async function decodeInvite(encoded: string): Promise<Invite> {
  const raw = JSON.parse(fromBase64Url(encoded));
  const parties = (raw.parties as string[]).map(p => AztecAddress.fromStringUnsafe(p));
  for (const p of parties) {
    if (!(await p.isValid())) throw new Error(`invalid party address ${p}`);
  }
  return { salt: Fr.fromString(raw.salt), expiry: BigInt(raw.expiry), parties };
}

// The `Agreement` struct of the contract.
export type Agreement = { terms_commitment: Fr; expiry: bigint; party_count: number; parties: AztecAddress[] };

// The agreement as MetaLeX stores it. It holds no salt and no terms.
export type AgreementJson = { termsCommitment: string; expiry: string; parties: string[] };

export function agreementOf(termsCommitment: Fr, expiry: bigint, parties: AztecAddress[]): Agreement {
  const padded = [...parties, ...Array(MAX_PARTIES - parties.length).fill(AztecAddress.ZERO)];
  return { terms_commitment: termsCommitment, expiry, party_count: parties.length, parties: padded };
}

export function agreementToJson(agreement: Agreement): AgreementJson {
  return {
    termsCommitment: agreement.terms_commitment.toString(),
    expiry: agreement.expiry.toString(),
    parties: agreement.parties.slice(0, agreement.party_count).map(p => p.toString()),
  };
}

export function agreementFromJson(json: AgreementJson): Agreement {
  return agreementOf(
    Fr.fromString(json.termsCommitment),
    BigInt(json.expiry),
    json.parties.map(p => AztecAddress.fromStringUnsafe(p)),
  );
}

// The public data of an account that a user gives MetaLeX at onboarding. The settler needs it to run the authwit
// check of the account. An auditor needs it to tie the signing key to the address.
export type PublicAccount = {
  address: string;
  signingPublicKey: { x: string; y: string };
  instance: {
    salt: string;
    deployer: string;
    originalContractClassId: string;
    currentContractClassId: string;
    initializationHash: string;
    immutablesHash: string;
    publicKeys: string;
  };
};

// The proof of one party's signature: its authwit and its public account data. The party's device stores it in the
// vault, encrypted with the document key, so each holder of the invite can check it without MetaLeX.
export type Evidence = PublicAccount & { authwit: string };
