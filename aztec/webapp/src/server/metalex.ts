// MetaLeX services: the document vault, the signature collector, the settler and the data key store. They see the
// party addresses, ciphertext and authwits, never a salt or a document in plaintext, except that the data key store
// can decrypt a stored salt until the retention period ends.

import { createServerFn } from '@tanstack/react-start';
import type { AgreementJson, PublicAccount } from '../shared/agreement';
import { NDA_TEMPLATE } from '../shared/template';

const RETENTION_MS = 30 * 24 * 3600 * 1000;
// A settlement that is still `settling` after this time failed without a record, so the next poll retries it.
const STALE_SETTLEMENT_MS = 5 * 60 * 1000;

const input = <T,>(data: T) => data;

async function services() {
  const [{ database }, schema, orm] = await Promise.all([
    import('./db/client'),
    import('./db/schema'),
    import('drizzle-orm'),
  ]);
  return { db: database(), ...schema, ...orm };
}

// The data key store encrypts each salt with ENCRYPTION_KEY. In production this key belongs in a KMS.
async function dataKeyCipher() {
  const [{ encrypt, decrypt, fromHex }, { env }] = await Promise.all([import('../shared/crypto'), import('./env')]);
  const key = fromHex(env('ENCRYPTION_KEY'));
  if (key.length !== 32) throw new Error('ENCRYPTION_KEY must be 32 bytes of hex');
  return {
    seal: async (salt: string) => Buffer.from(await encrypt(key, salt)).toString('base64'),
    open: (ciphertext: string) => decrypt(key, Buffer.from(ciphertext, 'base64')),
  };
}

export const getConfig = createServerFn({ method: 'GET' }).handler(async () => ({
  nodeUrl: process.env.AZTEC_NODE_URL ?? '',
  maxBatchSize: process.env.AZTEC_NODE_MAX_BATCH_SIZE ? Number(process.env.AZTEC_NODE_MAX_BATCH_SIZE) : undefined,
  registry: process.env.REGISTRY_ADDRESS ?? '',
  explorerUrl: process.env.EXPLORER_URL,
  template: NDA_TEMPLATE,
}));

// Onboarding: the user gives MetaLeX its public account data and a display name.
export const onboard = createServerFn({ method: 'POST' })
  .validator(input<{ name: string; account: PublicAccount }>)
  .handler(async ({ data }) => {
    const { db, accounts } = await services();
    await db
      .insert(accounts)
      .values({ address: data.account.address, name: data.name, account: data.account })
      .onConflictDoUpdate({ target: accounts.address, set: { name: data.name } });
    return {};
  });

export const listAccounts = createServerFn({ method: 'GET' }).handler(async () => {
  const { db, accounts, desc } = await services();
  const rows = await db.select().from(accounts).orderBy(desc(accounts.createdAt)).limit(50);
  return rows.map(r => ({ address: r.address, name: r.name }));
});

export const putBlob = createServerFn({ method: 'POST' })
  .validator(input<{ locator: string; blob: string }>)
  .handler(async ({ data }) => {
    const { db, vault } = await services();
    await db.insert(vault).values(data).onConflictDoUpdate({ target: vault.locator, set: { blob: data.blob } });
    return {};
  });

export const getBlob = createServerFn({ method: 'POST' })
  .validator(input<{ locator: string }>)
  .handler(async ({ data }) => {
    const { db, vault, eq } = await services();
    const [row] = await db.select().from(vault).where(eq(vault.locator, data.locator));
    return { blob: row?.blob ?? null };
  });

// The data key store gets the salt in plaintext over TLS and keeps it encrypted.
export const putDataKey = createServerFn({ method: 'POST' })
  .validator(input<{ agreementId: string; salt: string; parties: string[] }>)
  .handler(async ({ data }) => {
    const { db, dataKeys } = await services();
    const cipher = await dataKeyCipher();
    await db
      .insert(dataKeys)
      .values({
        agreementId: data.agreementId,
        ciphertext: await cipher.seal(data.salt),
        parties: data.parties,
        retainUntil: new Date(Date.now() + RETENTION_MS),
      })
      .onConflictDoNothing();
    return {};
  });

// The agreements that the data key store lets `requester` open. The PoC has no login, so the request names its user.
export const listMyAgreements = createServerFn({ method: 'POST' })
  .validator(input<{ requester: string }>)
  .handler(async ({ data }) => {
    const { db, dataKeys, agreements, eq, lte } = await services();
    await db.delete(dataKeys).where(lte(dataKeys.retainUntil, new Date()));
    const cipher = await dataKeyCipher();
    const rows = await db
      .select()
      .from(dataKeys)
      .innerJoin(agreements, eq(agreements.id, dataKeys.agreementId));
    const mine = rows.filter(r => r.data_keys.parties.includes(data.requester));
    return Promise.all(
      mine.map(async r => ({
        agreementId: r.agreements.id,
        salt: await cipher.open(r.data_keys.ciphertext),
        expiry: r.agreements.agreement.expiry,
        parties: r.agreements.agreement.parties,
      })),
    );
  });

export const endRetention = createServerFn({ method: 'POST' })
  .validator(input<{ agreementId: string }>)
  .handler(async ({ data }) => {
    const { db, dataKeys, eq } = await services();
    await db.delete(dataKeys).where(eq(dataKeys.agreementId, data.agreementId));
    return {};
  });

// The settler claims an agreement once. A second claim fails unless the first one went stale.
async function claimSettlement(agreementId: string) {
  const { db, settlements, and, eq, lt, sql } = await services();
  const fresh = await db
    .insert(settlements)
    .values({ agreementId, status: 'settling' })
    .onConflictDoNothing()
    .returning();
  if (fresh.length > 0) return true;
  const stale = await db
    .update(settlements)
    .set({ status: 'settling', attempts: sql`${settlements.attempts} + 1`, updatedAt: new Date() })
    .where(
      and(
        eq(settlements.agreementId, agreementId),
        eq(settlements.status, 'settling'),
        lt(settlements.updatedAt, new Date(Date.now() - STALE_SETTLEMENT_MS)),
      ),
    )
    .returning();
  return stale.length > 0;
}

async function runSettlement(agreementId: string) {
  const { db, agreements, signatures, accounts, settlements, eq, inArray } = await services();
  try {
    const [row] = await db.select().from(agreements).where(eq(agreements.id, agreementId));
    const sigs = await db.select().from(signatures).where(eq(signatures.agreementId, agreementId));
    const parties = await db.select().from(accounts).where(inArray(accounts.address, row.agreement.parties));
    const authwits = row.agreement.parties.map(p => sigs.find(s => s.signer === p)!.authwit);
    const accountsOf = row.agreement.parties.map(p => parties.find(a => a.address === p)!.account);
    const { sendFinalize } = await import('./settler');
    const txHash = await sendFinalize(row.agreement, authwits, accountsOf);
    await db
      .update(settlements)
      .set({ status: 'sent', txHash, error: null, updatedAt: new Date() })
      .where(eq(settlements.agreementId, agreementId));
  } catch (err) {
    await db
      .update(settlements)
      .set({ status: 'failed', error: (err as Error).message.split('\n')[0], updatedAt: new Date() })
      .where(eq(settlements.agreementId, agreementId));
  }
}

// Starts the settlement in the background, so the request returns at once. On Vercel, `waitUntil` keeps the
// function alive until it ends.
async function settleInBackground(agreementId: string) {
  if (!(await claimSettlement(agreementId))) return;
  const { waitUntil } = await import('@vercel/functions');
  waitUntil(runSettlement(agreementId));
}

async function signersOf(agreementId: string) {
  const { db, agreements, signatures, settlements, eq } = await services();
  const [row] = await db.select().from(agreements).where(eq(agreements.id, agreementId));
  if (!row) return undefined;
  const signed = (await db.select().from(signatures).where(eq(signatures.agreementId, agreementId))).map(
    s => s.signer,
  );
  const [settlement] = await db.select().from(settlements).where(eq(settlements.agreementId, agreementId));
  return {
    parties: row.agreement.parties,
    signed,
    pending: row.agreement.parties.filter(p => !signed.includes(p)),
    settlement: settlement && {
      status: settlement.status,
      txHash: settlement.txHash,
      error: settlement.error,
      stale: settlement.status === 'settling' && Date.now() - settlement.updatedAt.getTime() > STALE_SETTLEMENT_MS,
    },
  };
}

// The collector stores a party's authwit. When each party has signed, the settler sends `finalize`.
export const submitSignature = createServerFn({ method: 'POST' })
  .validator(input<{ agreementId: string; agreement: AgreementJson; signer: string; authwit: string }>)
  .handler(async ({ data }) => {
    const { db, agreements, signatures } = await services();
    if (!data.agreement.parties.includes(data.signer)) throw new Error(`${data.signer} is not a party`);
    await db.insert(agreements).values({ id: data.agreementId, agreement: data.agreement }).onConflictDoNothing();
    await db
      .insert(signatures)
      .values({ agreementId: data.agreementId, signer: data.signer, authwit: data.authwit })
      .onConflictDoNothing();
    const state = (await signersOf(data.agreementId))!;
    if (state.pending.length === 0) await settleInBackground(data.agreementId);
    return {};
  });

// The collector state of one agreement, for a party of it only. A stale settlement starts again.
export const getSigners = createServerFn({ method: 'POST' })
  .validator(input<{ agreementId: string; requester: string }>)
  .handler(async ({ data }) => {
    const state = await signersOf(data.agreementId);
    if (!state) return null;
    if (!state.parties.includes(data.requester)) throw new Error(`access denied for ${data.requester}`);
    if (state.pending.length === 0 && (!state.settlement || state.settlement.stale)) {
      await settleInBackground(data.agreementId);
    }
    return state;
  });

// What MetaLeX holds, for the MetaLeX page. The onchain columns come from the node.
export const metalexView = createServerFn({ method: 'GET' }).handler(async () => {
  const { db, agreements, accounts, vault, dataKeys, desc } = await services();
  const names = new Map((await db.select().from(accounts)).map(a => [a.address, a.name]));
  const nameOf = (address: string) => names.get(address) ?? 'Unknown';
  const rows = await db.select().from(agreements).orderBy(desc(agreements.createdAt)).limit(20);
  const collector = await Promise.all(
    rows.map(async r => {
      const state = (await signersOf(r.id))!;
      return {
        agreementId: r.id,
        parties: state.parties.map(nameOf),
        signed: state.signed.map(nameOf),
        pending: state.pending.map(nameOf),
        settlement: state.settlement,
        onchain: state.settlement?.txHash ? await onchainOf(state.settlement.txHash) : undefined,
      };
    }),
  );
  const blobs = await db.select().from(vault).orderBy(desc(vault.createdAt)).limit(20);
  const keys = await db.select().from(dataKeys);
  return {
    registry: process.env.REGISTRY_ADDRESS ?? '',
    collector,
    vault: blobs.map(b => ({ locator: b.locator, bytes: Buffer.from(b.blob, 'base64').length, ciphertext: b.blob })),
    dataKeys: keys.map(k => ({
      agreementId: k.agreementId,
      parties: k.parties.map(nameOf),
      retainUntil: k.retainUntil.toISOString(),
      ciphertext: k.ciphertext,
    })),
  };
});

// The receipt and the public effects of a tx, from the node.
async function onchainOf(txHash: string) {
  const [{ createAztecNodeClient }, { TxHash }, { env, nodeClientOptions }] = await Promise.all([
    import('@aztec-labs/aztec.js/node'),
    import('@aztec-labs/aztec.js/tx'),
    import('./env'),
  ]);
  const node = createAztecNodeClient(env('AZTEC_NODE_URL'), nodeClientOptions());
  const hash = TxHash.fromString(txHash);
  const receipt = await node.getTxReceipt(hash);
  const effect = receipt.blockNumber ? (await node.getTxEffect(hash))?.data : undefined;
  return {
    status: receipt.status as string,
    block: receipt.blockNumber ? Number(receipt.blockNumber) : undefined,
    nullifiers: effect?.nullifiers.length,
    noteHashes: effect?.noteHashes.length,
    logs: effect ? effect.privateLogs.length + effect.publicLogs.length : undefined,
  };
}
