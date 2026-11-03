// A local web app for the PoC. One process stands in for each user's device (wallet, PXE and document encryption)
// and for the MetaLeX services. The device code reaches MetaLeX only through the `MetaLeXServices` methods that a
// real app calls over the network.
//
// Usage: AZTEC_NODE_URL=http://localhost:8090 PORT=8091 node app/server.ts

import { readFile } from 'node:fs/promises';
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { extname, join } from 'node:path';
import { NO_FROM } from '@aztec-labs/aztec.js/account';
import { AztecAddress } from '@aztec-labs/aztec.js/addresses';
import { Fr } from '@aztec-labs/aztec.js/fields';
import type { CyberAgreementRegistryContract } from '../artifacts/CyberAgreementRegistry.ts';
import {
  agreementOf,
  canonicalJson,
  docKeysOf,
  documentOf,
  encrypt,
  inviteOf,
  NDA_TEMPLATE,
  openInvite,
  startPoc,
  termsHashOf,
} from '../poc.ts';

const RETENTION_MS = 30 * 24 * 3600 * 1000;
const PUBLIC_DIR = join(import.meta.dirname, 'public');
const TYPES: Record<string, string> = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' };

const nodeUrl = process.env.AZTEC_NODE_URL ?? 'http://localhost:8080';
const port = Number(process.env.PORT ?? 8091);

console.log(`starting wallets and deploying the registry on ${nodeUrl}`);
const poc = await startPoc(nodeUrl);
const { metalex } = poc;
console.log(`registry deployed at ${poc.registry}`);

type Settlement = {
  status: 'settling' | 'finalized' | 'failed';
  txHash?: string;
  block?: number;
  nullifiers?: number;
  noteHashes?: number;
  logs?: number;
  feePayer?: string;
  error?: string;
};
const settlements = new Map<string, Settlement>();

type Device = { name: string; address?: AztecAddress; registry: CyberAgreementRegistryContract; wallet?: typeof poc.alice.wallet };
const devices: Record<string, Device> = {
  alice: { name: 'Alice', ...poc.alice },
  bob: { name: 'Bob', ...poc.bob },
  auditor: { name: 'Auditor', ...poc.auditor },
};
const nameOf = (address: string) =>
  Object.values(devices).find(d => d.address?.toString() === address)?.name ?? 'Unknown';

// The PXEs share one node and one process, so the app runs one wallet operation at a time.
let queue: Promise<unknown> = Promise.resolve();
function serial<T>(fn: () => Promise<T>): Promise<T> {
  const run = queue.then(fn);
  queue = run.catch(() => undefined);
  return run;
}

// MetaLeX: the signature collector state of one agreement, for a party of that agreement only.
function signersOf(agreementId: string, requester: AztecAddress) {
  const entry = metalex.collector.get(agreementId);
  if (!entry) return undefined;
  const parties = entry.agreement.parties.slice(0, entry.agreement.party_count).map(p => p.toString());
  if (!parties.includes(requester.toString())) throw new Error(`access denied for ${requester}`);
  const signed = entry.signatures.map(s => s.signer.toString());
  return { signed, pending: parties.filter(p => !signed.includes(p)) };
}

// MetaLeX: the settler sends `finalize` when the collector has a signature from each party.
function settleWhenComplete(agreementId: Fr) {
  const id = agreementId.toString();
  if (metalex.pendingSigners(agreementId).length > 0 || settlements.has(id)) return;
  settlements.set(id, { status: 'settling' });
  const { agreement, signatures } = metalex.collector.get(id)!;
  serial(async () => {
    const { receipt } = await poc.settle(agreement, signatures);
    const tx = await poc.node.getTxByHash(receipt.txHash);
    const effect = (await poc.node.getTxEffect(receipt.txHash))!.data;
    settlements.set(id, {
      status: 'finalized',
      txHash: receipt.txHash.toString(),
      block: Number(receipt.blockNumber),
      nullifiers: effect.nullifiers.length,
      noteHashes: effect.noteHashes.length,
      logs: effect.privateLogs.length + effect.publicLogs.length,
      feePayer: tx?.data.feePayer.toString(),
    });
  }).catch(err => settlements.set(id, { status: 'failed', error: (err as Error).message.split('\n')[0] }));
}

// MetaLeX: the agreements that the data key store lets `requester` open, as invites.
function invitesOf(requester: AztecAddress) {
  metalex.deleteExpiredDataKeys(Date.now());
  return [...metalex.dataKeys]
    .filter(([, row]) => row.parties.includes(requester.toString()))
    .map(([id]) => {
      const { agreement } = metalex.collector.get(id)!;
      const salt = metalex.getDataKey(Fr.fromString(id), requester);
      return inviteOf(salt, agreement.expiry, agreement.parties.slice(0, agreement.party_count));
    });
}

function metalexView() {
  const hex = (b: Buffer) => b.toString('hex');
  return {
    registry: poc.registry.toString(),
    fpc: poc.fpc.toString(),
    collector: [...metalex.collector].map(([id, entry]) => {
      const parties = entry.agreement.parties.slice(0, entry.agreement.party_count).map(p => p.toString());
      const signed = entry.signatures.map(s => s.signer.toString());
      return {
        agreementId: id,
        parties: parties.map(address => ({ address, name: nameOf(address) })),
        expiry: entry.agreement.expiry.toString(),
        signed: signed.map(nameOf),
        pending: parties.filter(p => !signed.includes(p)).map(nameOf),
        termsCommitment: entry.agreement.terms_commitment.toString(),
        settlement: settlements.get(id),
      };
    }),
    vault: [...metalex.vault].map(([locator, blob]) => ({ locator, bytes: blob.length, ciphertext: hex(blob) })),
    dataKeys: [...metalex.dataKeys].map(([id, row]) => ({
      agreementId: id,
      parties: row.parties.map(nameOf),
      retainUntil: row.retainUntil,
      ciphertext: hex(row.ciphertext),
    })),
  };
}

// Device: open an invite and add the collector state when the user is a party.
async function open(device: Device, invite: string) {
  const view = await openInvite(device.registry, device.address ?? NO_FROM, invite, metalex);
  const id = view.agreementId.toString();
  const parties = view.agreement.parties.slice(0, view.agreement.party_count).map(p => p.toString());
  const isParty = device.address !== undefined && parties.includes(device.address.toString());
  return {
    invite,
    agreementId: id,
    document: view.document,
    locator: view.locator,
    finalized: view.finalized,
    expiry: view.agreement.expiry.toString(),
    parties: parties.map(address => ({ address, name: nameOf(address) })),
    isParty,
    signers: isParty ? signersOf(id, device.address!) : undefined,
    settlement: isParty ? settlements.get(id) : undefined,
  };
}

type Draft = { effectiveDate: string; counterparty: string; names: Record<string, string>; expiry: string };

// Device: draft, encrypt, upload and sign a new agreement. Only the device sees the salt and the document.
async function create(device: Device, draft: Draft) {
  const creator = device.address!;
  const counterparty = AztecAddress.fromStringUnsafe(draft.counterparty);
  if (!(await counterparty.isValid())) throw new Error(`invalid party address ${counterparty}`);
  const parties = [creator, counterparty];
  const document = documentOf(
    draft.effectiveDate,
    parties.map(p => [p, draft.names[p.toString()] ?? ''] as [AztecAddress, string]),
  );
  const expiry = draft.expiry ? BigInt(Math.floor(new Date(draft.expiry).getTime() / 1000)) : 0n;
  const salt = Fr.random();
  const { result: commitment } = await device.registry.methods
    .terms_commitment_of(termsHashOf(document), salt)
    .simulate({ from: creator });
  const agreement = agreementOf(new Fr(commitment), expiry, parties);
  const { result: id } = await device.registry.methods.agreement_id(agreement).simulate({ from: creator });
  const agreementId = new Fr(id);
  const { locator, key } = docKeysOf(salt);
  metalex.putDocument(locator, encrypt(key, canonicalJson(document)));
  metalex.putDataKey(agreementId, salt, parties, Date.now() + RETENTION_MS);
  metalex.submitSignature(agreementId, agreement, await poc.sign(device.wallet!, device.registry, creator, agreement));
  settleWhenComplete(agreementId);
  return { invite: inviteOf(salt, expiry, parties), agreementId: agreementId.toString() };
}

// Device: the user signs the agreement in the invite.
async function sign(device: Device, invite: string) {
  const view = await openInvite(device.registry, device.address!, invite, metalex);
  metalex.submitSignature(
    view.agreementId,
    view.agreement,
    await poc.sign(device.wallet!, device.registry, device.address!, view.agreement),
  );
  settleWhenComplete(view.agreementId);
  return open(device, invite);
}

async function route(method: string, path: string, body: any): Promise<unknown> {
  if (method === 'GET' && path === '/api/state') {
    return {
      nodeUrl,
      registry: poc.registry.toString(),
      template: NDA_TEMPLATE,
      users: Object.entries(devices).map(([key, d]) => ({ key, name: d.name, address: d.address?.toString() })),
    };
  }
  if (method === 'GET' && path === '/api/metalex') return metalexView();
  if (method === 'POST' && path === '/api/metalex/end-retention') {
    const row = metalex.dataKeys.get(body.agreementId);
    if (!row) throw new Error(`no data key for ${body.agreementId}`);
    row.retainUntil = Date.now();
    metalex.deleteExpiredDataKeys(Date.now());
    return {};
  }
  const match = path.match(/^\/api\/device\/(alice|bob|auditor)\/(open|create|sign|agreements)$/);
  if (!match) throw new Error(`no route ${method} ${path}`);
  const device = devices[match[1]];
  const action = match[2];
  if (action === 'open') return serial(() => open(device, body.invite));
  if (!device.address) throw new Error(`${device.name} has no account`);
  if (action === 'create') return serial(() => create(device, body));
  if (action === 'sign') return serial(() => sign(device, body.invite));
  return serial(async () => Promise.all(invitesOf(device.address!).map(invite => open(device, invite))));
}

async function readBody(req: IncomingMessage) {
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  return chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {};
}

function send(res: ServerResponse, status: number, type: string, body: string | Buffer) {
  res.writeHead(status, { 'content-type': type, 'cache-control': 'no-store' });
  res.end(body);
}

createServer(async (req, res) => {
  const path = new URL(req.url!, 'http://localhost').pathname;
  if (path.startsWith('/api/')) {
    try {
      const result = await route(req.method!, path, await readBody(req));
      send(res, 200, 'application/json', JSON.stringify(result));
    } catch (err) {
      send(res, 400, 'application/json', JSON.stringify({ error: (err as Error).message.split('\n')[0] }));
    }
    return;
  }
  const file = TYPES[extname(path)] ? path : '/index.html';
  try {
    send(res, 200, TYPES[extname(file)], await readFile(join(PUBLIC_DIR, file.replace(/^\/+/, '').replace(/\.\./g, ''))));
  } catch {
    send(res, 404, 'text/plain', 'not found');
  }
}).listen(port, () => console.log(`app ready at http://localhost:${port}`));
