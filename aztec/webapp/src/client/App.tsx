// The web app. Each role page stands in for one user's device. The PoC has no login.

import { type FormEvent, type ReactNode, useCallback, useEffect, useRef, useState } from 'react';
import { endRetention, listAccounts, metalexView } from '../server/metalex';
import type { AgreementDocument } from '../shared/agreement';
import {
  type AgreementView,
  createAgreement,
  type Device,
  addressOf,
  deviceOf,
  type Draft,
  myAgreements,
  openInvite,
  type Proofs,
  ROLE_NAMES,
  type Role,
  setSigningKey,
  signInvite,
  storedSigningKey,
  txStatusOf,
  verifyTerms,
} from './aztec';

const short = (hex?: string | null) => (hex ? `${hex.slice(0, 10)}…${hex.slice(-6)}` : '');
const message = (err: unknown) => (err as Error).message.split('\n')[0];

function useHash() {
  const [hash, setHash] = useState(() => new URLSearchParams(location.hash.slice(1)));
  useEffect(() => {
    const update = () => setHash(new URLSearchParams(location.hash.slice(1)));
    window.addEventListener('hashchange', update);
    return () => window.removeEventListener('hashchange', update);
  }, []);
  return hash;
}

// `#invite=` is a link that the user got. `#stored=` opens an agreement with the salt from the data key store.
function inviteOf(hash: URLSearchParams) {
  return hash.get('invite') ?? hash.get('stored');
}

// Calls the newest `fn` every `ms` while `active`.
function usePoll(fn: () => void, active: boolean, ms = 3000) {
  const latest = useRef(fn);
  latest.current = fn;
  useEffect(() => {
    if (!active) return;
    const timer = setInterval(() => latest.current(), ms);
    return () => clearInterval(timer);
  }, [active, ms]);
}

function TxLink({ hash, explorerUrl }: { hash: string; explorerUrl?: string }) {
  if (!explorerUrl) return <span className="mono">{short(hash)}</span>;
  return (
    <a className="mono" href={`${explorerUrl}/tx-effects/${hash}`} target="_blank" rel="noopener noreferrer">
      {short(hash)}
    </a>
  );
}

// Shows that work is still running.
function Spinner() {
  return <span className="spinner" role="status" aria-label="In progress" />;
}

function Status({ view }: { view: Pick<AgreementView, 'finalized' | 'signers'> }) {
  if (view.finalized) return <span className="status finalized">Finalized</span>;
  if (view.signers?.settlement?.status === 'failed') return <span className="status failed">Settlement failed</span>;
  return <span className="status pending">Pending</span>;
}

function Busy({ label, busyLabel, onClick, secondary }: { label: string; busyLabel: string; onClick: () => Promise<void>; secondary?: boolean }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  return (
    <>
      <button
        type="button"
        className={secondary ? 'secondary' : undefined}
        disabled={busy}
        onClick={async () => {
          setBusy(true);
          setError(undefined);
          try {
            await onClick();
          } catch (err) {
            setError(message(err));
          } finally {
            setBusy(false);
          }
        }}
      >
        {busy ? busyLabel : label}
      </button>
      {error && <p className="error">{error}</p>}
    </>
  );
}

function DocumentText({ doc }: { doc: AgreementDocument }) {
  return (
    <div className="doc">
      <h3>{doc.template.title}</h3>
      <p>
        This {doc.template.title} is made on <b>{doc.globalValues[0]}</b> (the "Effective Date") between{' '}
        {doc.partyValues.map(([address, [name]], i) => (
          <span key={address}>
            {i > 0 && ' and '}
            <b>{name}</b> (<span className="mono">{short(address)}</span>)
          </span>
        ))}
        .
      </p>
      <ol>
        {doc.template.text.map((clause, i) => (
          <li key={i}>{clause}</li>
        ))}
      </ol>
    </div>
  );
}

function useNames() {
  const [names, setNames] = useState(new Map<string, string>());
  useEffect(() => {
    listAccounts().then(rows => setNames(new Map(rows.map(r => [r.address, r.name]))));
  }, []);
  return (address: string) => names.get(address) ?? short(address);
}

// Invite links stay in this browser only. MetaLeX never gets them.
function savedInvites(role: Role): { invite: string; agreementId: string }[] {
  try {
    return JSON.parse(localStorage.getItem(`invites:${role}`) ?? '[]');
  } catch {
    return [];
  }
}

function saveInvite(role: Role, invite: string, agreementId: string) {
  const list = savedInvites(role).filter(i => i.agreementId !== agreementId);
  try {
    localStorage.setItem(`invites:${role}`, JSON.stringify([{ invite, agreementId }, ...list]));
  } catch {}
}

function AgreementSection({ device, invite, onChange }: { device: Device; invite: string; onChange?: () => void }) {
  const [view, setView] = useState<AgreementView>();
  const [error, setError] = useState<string>();
  const [tx, setTx] = useState<{ status: string; block?: number }>();
  const nameOf = useNames();
  const hash = useHash();
  const lastStatus = useRef<string | undefined>(undefined);

  const load = useCallback(async () => {
    try {
      const next = await openInvite(device, invite);
      setView(next);
      if (next.isParty && hash.get('invite') === invite) saveInvite(device.role, invite, next.agreementId);
      const txHash = next.signers?.settlement?.txHash;
      if (txHash) setTx(await txStatusOf(device, txHash));
      const status = next.finalized ? 'finalized' : 'pending';
      if (lastStatus.current && lastStatus.current !== status) onChange?.();
      lastStatus.current = status;
    } catch (err) {
      setError(message(err));
    }
  }, [device, invite, hash, onChange]);

  useEffect(() => {
    setView(undefined);
    setError(undefined);
    lastStatus.current = undefined;
    load();
  }, [load]);
  usePoll(load, !!view && view.isParty && !view.finalized && view.signers?.settlement?.status !== 'failed');

  if (error) return <section id="agreement"><p className="error">{error}</p></section>;
  if (!view) return <section id="agreement"><p className="muted">Opening the agreement…</p></section>;

  const me = device.address?.toString();
  const signers = view.signers;
  const settlement = signers?.settlement;
  const canSign = view.isParty && !view.finalized && !signers?.signed.includes(me!);
  const explorerUrl = device.config.explorerUrl;
  let progress: ReactNode = null;
  if (view.finalized) {
    progress = (
      <p className="callout" id="finalized">
        All parties signed. MetaLeX finalized the agreement on Aztec
        {settlement?.txHash && (
          <>
            {' '}in one transaction: <TxLink hash={settlement.txHash} explorerUrl={explorerUrl} />
          </>
        )}
        .
      </p>
    );
  } else if (settlement?.status === 'failed') {
    progress = <p className="error">Settlement failed: {settlement.error}</p>;
  } else if (settlement?.status === 'sent' && settlement.txHash) {
    progress = (
      <p className="callout" id="sent">
        MetaLeX sent the finalize transaction: <TxLink hash={settlement.txHash} explorerUrl={explorerUrl} />. Status:{' '}
        {tx?.status ?? 'pending'}. Waiting for a block. <Spinner />
      </p>
    );
  } else if (signers && signers.pending.length === 0) {
    progress = (
      <p className="callout">
        All parties signed. MetaLeX is sending the finalize transaction. <Spinner />
      </p>
    );
  } else if (signers) {
    progress = <p className="callout">Waiting for: {signers.pending.map(nameOf).join(', ')}</p>;
  }

  return (
    <section id="agreement">
      <div className="role">
        <h2>Agreement</h2>
        <Status view={view} />
      </div>
      <dl className="facts">
        <dt>Agreement id</dt>
        <dd className="mono">{view.agreementId}</dd>
        <dt>Parties</dt>
        <dd>
          {view.parties.map((p, i) => (
            <span key={p}>
              {i > 0 && ', '}
              {nameOf(p)} <span className="mono">{short(p)}</span>
            </span>
          ))}
        </dd>
        <dt>Expiry</dt>
        <dd>{view.expiry === '0' ? 'None' : new Date(Number(view.expiry) * 1000).toLocaleString()}</dd>
        <dt>Document</dt>
        <dd>
          Encrypted in the MetaLeX vault at locator <span className="mono">{short(view.locator)}</span>. This device
          decrypted it with the salt from the invite.
        </dd>
        {signers && (
          <>
            <dt>Signed</dt>
            <dd>{signers.signed.map(nameOf).join(', ') || 'Nobody yet'}</dd>
          </>
        )}
      </dl>
      <DocumentText doc={view.document} />
      {progress}
      {canSign && (
        <div className="actions">
          <Busy
            label="Sign"
            busyLabel="Signing…"
            onClick={async () => {
              await signInvite(device, invite);
              await load();
            }}
          />
          <span className="muted">Your wallet signs an authwit. You send no transaction.</span>
        </div>
      )}
    </section>
  );
}

function MyAgreements({ device, version }: { device: Device; version: number }) {
  const [rows, setRows] = useState<AgreementView[]>();
  useEffect(() => {
    setRows(undefined);
    myAgreements(device)
      .then(invites => Promise.all(invites.map(i => openInvite(device, i))))
      .then(setRows);
  }, [device, version]);
  return (
    <section id="mine">
      <h2>Your agreements</h2>
      <p className="muted">
        The MetaLeX data key store gives the salt of each agreement to its parties during the retention period. So you
        can open them without the invite link.
      </p>
      {!rows && <p className="muted">Loading…</p>}
      {rows?.length === 0 && <p id="no-agreements">No agreements in the data key store.</p>}
      {rows && rows.length > 0 && (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Title</th>
                <th>Agreement id</th>
                <th>Status</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {rows.map(v => (
                <tr key={v.agreementId}>
                  <td>{v.document.template.title}</td>
                  <td className="mono">{short(v.agreementId)}</td>
                  <td>
                    <Status view={v} />
                  </td>
                  <td>
                    <a className="button secondary" href={`#stored=${v.invite}`}>
                      Open
                    </a>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

function SavedInvites({ role, version }: { role: Role; version: number }) {
  const [list, setList] = useState(() => savedInvites(role));
  useEffect(() => setList(savedInvites(role)), [role, version]);
  const other = role === 'alice' ? 'bob' : 'alice';
  return (
    <section id="saved">
      <h2>Invite links on this device</h2>
      <p className="muted">
        Your browser keeps a copy of each invite link. MetaLeX does not have it. You can send a link again to your
        counterparty.
      </p>
      {list.length === 0 ? (
        <p id="no-invites">No invite links on this device.</p>
      ) : (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Agreement id</th>
                <th>Invite link</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {list.map(i => (
                <tr key={i.agreementId}>
                  <td className="mono">{short(i.agreementId)}</td>
                  <td>
                    <input
                      className="mono"
                      readOnly
                      aria-label={`Invite link ${short(i.agreementId)}`}
                      value={`${location.origin}/${other}#invite=${i.invite}`}
                    />
                  </td>
                  <td>
                    <a className="button secondary" href={`#invite=${i.invite}`}>
                      Open
                    </a>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

function DraftSection({ device, onCreated }: { device: Device; onCreated: () => void }) {
  const [draft, setDraft] = useState<Draft>();
  const [result, setResult] = useState<{ invite: string; agreementId: string }>();
  // The last draft, so that "Edit" returns to the values that the user typed.
  const [last, setLast] = useState<Draft>();
  const [title, setTitle] = useState(device.config.template.title);
  const nextId = useRef(0);
  const clauseOf = (text: string) => ({ id: nextId.current++, text });
  const [clauses, setClauses] = useState(() => device.config.template.text.map(clauseOf));
  // The counterparty is the Bob of this browser: the account that the Bob tab uses.
  const [bob, setBob] = useState<string>();
  const me = device.address!.toString();
  useEffect(() => {
    addressOf('bob').then(setBob);
  }, []);

  if (result) {
    const link = `${location.origin}/bob#invite=${result.invite}`;
    return (
      <section id="invite">
        <h2>Signed. Send the invite to your counterparty</h2>
        <p className="muted">
          The invite holds the salt, the expiry and the parties. It is in the URL fragment, so the link does not send it
          to MetaLeX.
        </p>
        <div className="invite">
          <input id="invite-link" className="mono" readOnly value={link} aria-label="Invite link" />
        </div>
        <dl className="facts">
          <dt>Agreement id</dt>
          <dd className="mono">{result.agreementId}</dd>
        </dl>
        <div className="actions">
          <a className="button" href={`/bob#invite=${result.invite}`}>
            Open as Bob
          </a>
          <a className="button secondary" href={`/auditor#invite=${result.invite}`}>
            Open as auditor
          </a>
          <a className="button secondary" href={`#invite=${result.invite}`}>
            Open as Alice
          </a>
        </div>
      </section>
    );
  }

  if (draft) {
    const doc = {
      template: { ...device.config.template, title: draft.title, text: draft.clauses },
      globalValues: [draft.effectiveDate],
      partyValues: [
        [me, [draft.myName]],
        [draft.counterparty, [draft.theirName]],
      ],
    } as AgreementDocument;
    return (
      <section id="review-step">
        <h2>Review and sign</h2>
        <p className="muted">
          Your wallet signs an authwit for this agreement. MetaLeX collects the signatures and sends one private
          transaction when all parties signed.
        </p>
        <DocumentText doc={doc} />
        <div className="actions">
          <Busy
            label="Sign"
            busyLabel="Signing…"
            onClick={async () => {
              const created = await createAgreement(device, draft);
              saveInvite(device.role, created.invite, created.agreementId);
              setResult(created);
              onCreated();
            }}
          />
          <button
            type="button"
            className="secondary"
            onClick={() => {
              setLast(draft);
              setDraft(undefined);
            }}
          >
            Edit
          </button>
        </div>
      </section>
    );
  }

  const submit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    setDraft({
      title: title.trim(),
      clauses: clauses.map(c => c.text.trim()).filter(c => c.length > 0),
      effectiveDate: String(form.get('effectiveDate')),
      myName: String(form.get('myName')),
      counterparty: bob!,
      theirName: String(form.get('theirName')),
      expiry: String(form.get('expiry')),
    });
  };
  return (
    <section id="draft">
      <h2>New agreement</h2>
      <p className="muted">
        Write any terms: the title and every clause. The document, with its full text, stays on your device. MetaLeX
        gets it only as ciphertext in its document vault.
      </p>
      <form id="draft-form" onSubmit={submit}>
        <label className="wide">
          Title
          <input name="title" value={title} onChange={e => setTitle(e.target.value)} required />
        </label>
        <label>
          Effective date
          <input
            name="effectiveDate"
            type="date"
            defaultValue={last?.effectiveDate ?? new Date().toISOString().slice(0, 10)}
            required
          />
        </label>
        <label>
          Your legal name
          <input name="myName" defaultValue={last?.myName ?? 'Alice Corp'} required />
        </label>
        <label>
          Counterparty
          <input id="counterparty" className="mono" readOnly value={bob ? `Bob (${short(bob)})` : 'Loading…'} />
        </label>
        <label>
          Counterparty legal name
          <input name="theirName" defaultValue={last?.theirName ?? 'Bob LLC'} required />
        </label>
        <label>
          Expiry (optional)
          <input name="expiry" type="datetime-local" defaultValue={last?.expiry} />
        </label>
      </form>
      <div className="clauses" id="draft-clauses">
        {clauses.map((clause, i) => (
          <div className="clause" key={clause.id}>
            <label>
              Clause {i + 1}
              <textarea
                rows={2}
                value={clause.text}
                onChange={e =>
                  setClauses(list => list.map(c => (c.id === clause.id ? { ...c, text: e.target.value } : c)))
                }
              />
            </label>
            <button
              type="button"
              className="secondary"
              aria-label={`Remove clause ${i + 1}`}
              onClick={() => setClauses(list => list.filter(c => c.id !== clause.id))}
            >
              Remove
            </button>
          </div>
        ))}
        <div>
          <button type="button" className="secondary" onClick={() => setClauses(list => [...list, clauseOf('')])}>
            Add clause
          </button>
        </div>
      </div>
      <div className="actions">
        <button form="draft-form" disabled={!bob}>
          Review
        </button>
      </div>
    </section>
  );
}

function KeySection({ role, device }: { role: Role; device: Device }) {
  const [shown, setShown] = useState(false);
  return (
    <details id="signing-key">
      <summary>Signing key of this device</summary>
      <p className="muted">
        The key stays in this browser. Copy it to back up the account, or paste a backed-up key to restore it on this
        device. The page reloads after a restore.
      </p>
      <div className="actions">
        <button type="button" className="secondary" onClick={() => setShown(!shown)}>
          {shown ? 'Hide key' : 'Show key'}
        </button>
        {shown && <span className="mono" id="signing-key-value">{storedSigningKey(role)}</span>}
      </div>
      <form
        className="actions"
        onSubmit={e => {
          e.preventDefault();
          setSigningKey(role, String(new FormData(e.currentTarget).get('key')));
          location.hash = '';
          location.reload();
        }}
      >
        <label>
          Restore a signing key
          <input name="key" className="mono" placeholder="0x…" required />
        </label>
        <button className="secondary">Restore</button>
      </form>
      <p className="muted mono">Account {device.address?.toString()}</p>
    </details>
  );
}

function RoleHeader({ title, tag, kind, detail }: { title: string; tag: string; kind: string; detail?: string }) {
  return (
    <div className="role">
      <h1>{title}</h1>
      <span className={`tag ${kind}`}>{tag}</span>
      {detail && <span className="muted mono">{detail}</span>}
    </div>
  );
}

function useDevice(role: Role) {
  const [device, setDevice] = useState<Device>();
  const [error, setError] = useState<string>();
  useEffect(() => {
    deviceOf(role).then(setDevice, err => setError(message(err)));
  }, [role]);
  return { device, error };
}

function PartyPage({ role }: { role: 'alice' | 'bob' }) {
  const { device, error } = useDevice(role);
  const hash = useHash();
  const invite = inviteOf(hash);
  const [version, setVersion] = useState(0);
  const refresh = useCallback(() => setVersion(v => v + 1), []);
  // Opening another agreement can change what the data key store and this device hold.
  useEffect(refresh, [invite, refresh]);
  if (error) return <p className="error">{error}</p>;
  if (!device) return <p className="muted">Starting your wallet…</p>;
  return (
    <>
      <RoleHeader title={ROLE_NAMES[role]} tag="User device" kind="device" detail={device.address?.toString()} />
      {invite && <AgreementSection key={invite} device={device} invite={invite} onChange={refresh} />}
      {!invite && role === 'alice' && <DraftSection device={device} onCreated={refresh} />}
      <MyAgreements device={device} version={version} />
      <SavedInvites role={role} version={version} />
      <KeySection role={role} device={device} />
    </>
  );
}

function VerifyPanel({ device, view }: { device: Device; view: AgreementView }) {
  const initial = useCallback(
    () => ({ parties: [...view.parties] as string[], expiry: view.expiry, document: structuredClone(view.document) }),
    [view],
  );
  const [terms, setTerms] = useState(initial);
  const [result, setResult] = useState<Proofs | { error: string }>();
  const request = useRef(0);
  const nameOf = useNames();

  useEffect(() => {
    const mine = ++request.current;
    setResult(undefined);
    const timer = setTimeout(async () => {
      try {
        const r = await verifyTerms(device, view.invite, terms.expiry, terms.parties, terms.document);
        if (mine === request.current) setResult(r);
      } catch (err) {
        if (mine === request.current) setResult({ error: message(err) });
      }
    }, 400);
    return () => clearTimeout(timer);
  }, [device, view.invite, terms]);

  const update = (change: (t: ReturnType<typeof initial>) => void) =>
    setTerms(t => {
      const next = { ...t, parties: [...t.parties], document: structuredClone(t.document) };
      change(next);
      return next;
    });
  const mark = (ok: boolean) => (ok ? <span className="ok">✓</span> : <span className="bad">✗</span>);

  return (
    <section id="verify">
      <h2>Verify the signatures</h2>
      <p className="muted">
        Change a party address, the expiry or any part of the document. This device checks two proofs at once. Path 1:
        the registry recorded this exact agreement as finalized. Path 2: each party's stored signature is valid for these
        exact terms, by a key that the party address commits to.
      </p>
      <form className="grid" onSubmit={e => e.preventDefault()}>
        {terms.parties.map((p, i) => (
          <label key={`party-${i}`}>
            Party {i + 1} address ({nameOf(view.parties[i])})
            <input className="mono" value={p} onChange={e => update(t => (t.parties[i] = e.target.value))} />
          </label>
        ))}
        <label>
          Expiry (Unix seconds, 0 = none)
          <input value={terms.expiry} onChange={e => update(t => (t.expiry = e.target.value))} />
        </label>
        <label>
          Effective date
          <input
            value={terms.document.globalValues[0]}
            onChange={e => update(t => (t.document.globalValues[0] = e.target.value))}
          />
        </label>
        {terms.document.partyValues.map(([, [name]], i) => (
          <label key={`name-${i}`}>
            Party {i + 1} legal name
            <input value={name} onChange={e => update(t => (t.document.partyValues[i][1][0] = e.target.value))} />
          </label>
        ))}
      </form>
      <div className="clauses">
        {terms.document.template.text.map((clause, i) => (
          <label key={`clause-${i}`}>
            Clause {i + 1}
            <textarea
              rows={2}
              value={clause}
              onChange={e => update(t => (t.document.template.text[i] = e.target.value))}
            />
          </label>
        ))}
      </div>
      <div className="actions">
        <button type="button" className="secondary" onClick={() => setTerms(initial())}>
          Reset to the invite
        </button>
      </div>
      <div id="verify-result" aria-live="polite">
        {!result && <p className="muted">Checking…</p>}
        {result && 'error' in result && <p className="verdict bad-bg">✗ {result.error}</p>}
        {result && !('error' in result) && (
          <>
            {result.finalized && result.signed ? (
              <p className="verdict ok-bg">✓ These are the exact terms that the parties signed and that MetaLeX finalized.</p>
            ) : (
              <p className="verdict bad-bg">✗ These terms were not signed and finalized.</p>
            )}
            <dl className="facts">
              <dt>Agreement id</dt>
              <dd className="mono">
                {result.agreementId}{' '}
                {result.agreementId === view.agreementId ? '(same as the invite)' : '(different from the invite)'}
              </dd>
              <dt>Path 1 · chain</dt>
              <dd>{mark(result.finalized)} finalized nullifier of this agreement id onchain</dd>
              <dt>Path 2 · signatures</dt>
              <dd>
                <ul className="checks">
                  {result.signatures.map((s, i) => (
                    <li key={`${s.party}-${i}`}>
                      {nameOf(s.party)}:{' '}
                      {s.evidenceFound ? (
                        <>
                          {mark(s.addressMatches)} address commits to the key {mark(s.schnorrAccount)} Schnorr account{' '}
                          {mark(s.keyMatches)} key in the account {mark(s.signatureValid)} signature over these terms
                        </>
                      ) : (
                        <>{mark(false)} no stored signature for this address</>
                      )}
                    </li>
                  ))}
                </ul>
              </dd>
            </dl>
          </>
        )}
      </div>
    </section>
  );
}

function AuditorPage() {
  const { device, error } = useDevice('auditor');
  const hash = useHash();
  const invite = inviteOf(hash);
  const [view, setView] = useState<AgreementView>();
  useEffect(() => {
    setView(undefined);
    if (device && invite) openInvite(device, invite).then(setView, () => undefined);
  }, [device, invite]);
  if (error) return <p className="error">{error}</p>;
  if (!device) return <p className="muted">Starting your wallet…</p>;
  return (
    <>
      <RoleHeader title="Auditor" tag="User device" kind="device" detail="No Aztec account" />
      <section>
        <h2>Open an invite link</h2>
        <p className="muted">A party shares the invite link with you. You read the status from the chain. You send no transaction.</p>
        <form
          id="open-form"
          onSubmit={e => {
            e.preventDefault();
            location.hash = new URL(String(new FormData(e.currentTarget).get('link'))).hash;
          }}
        >
          <label>
            Invite link
            <input name="link" placeholder="https://…#invite=…" required />
          </label>
        </form>
        <div className="actions">
          <button form="open-form">Open</button>
        </div>
      </section>
      {invite && <AgreementSection key={invite} device={device} invite={invite} />}
      {invite && view && <VerifyPanel key={`verify-${invite}`} device={device} view={view} />}
    </>
  );
}

type MetalexData = Awaited<ReturnType<typeof metalexView>>;

function MetalexPage({ explorerUrl }: { explorerUrl?: string }) {
  const [data, setData] = useState<MetalexData>();
  const [error, setError] = useState<string>();
  const load = useCallback(() => {
    metalexView().then(setData, err => setError(message(err)));
  }, []);
  useEffect(load, [load]);
  const busy = !!data?.collector.some(
    c => c.pending.length > 0 || c.settlement?.status === 'settling' || (c.onchain && c.onchain.status === 'proposed'),
  );
  usePoll(load, busy && !!data);
  if (error) return <p className="error">{error}</p>;
  if (!data) return <p className="muted">Loading…</p>;
  return (
    <>
      <RoleHeader title="MetaLeX services" tag="What MetaLeX sees" kind="metalex" detail={`registry ${short(data.registry)}`} />
      <p className="callout metalex">
        MetaLeX sees no document and no terms hash. The vault and the data key store hold only ciphertext. During the
        retention period, MetaLeX can decrypt a salt with ENCRYPTION_KEY. That is the accepted trust.
      </p>
      <section id="collector">
        <h2>Signature collector and settler</h2>
        <p className="muted">The agreement without the salt, and one authwit for each party.</p>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Agreement id</th>
                <th>Parties</th>
                <th>Signed</th>
                <th>Waiting for</th>
                <th>Onchain</th>
              </tr>
            </thead>
            <tbody>
              {data.collector.length === 0 && (
                <tr>
                  <td colSpan={5} className="muted">
                    No agreements yet
                  </td>
                </tr>
              )}
              {data.collector.map(c => (
                <tr key={c.agreementId}>
                  <td className="mono">{short(c.agreementId)}</td>
                  <td>{c.parties.join(', ')}</td>
                  <td>{c.signed.join(', ')}</td>
                  <td>{c.pending.join(', ') || '–'}</td>
                  <td>
                    {!c.settlement && <span className="muted">Waiting for signatures</span>}
                    {c.settlement?.status === 'settling' && <span className="status pending">Sending finalize</span>}
                    {c.settlement?.status === 'failed' && (
                      <>
                        <span className="status failed">Settlement failed</span>
                        <br />
                        <span className="muted">{c.settlement.error}</span>
                      </>
                    )}
                    {c.settlement?.status === 'sent' && c.settlement.txHash && (
                      <>
                        <span className={`status ${c.onchain?.block ? 'finalized' : 'pending'}`}>
                          {c.onchain?.block ? 'Finalized' : 'Sent'}
                        </span>
                        <br />
                        tx <TxLink hash={c.settlement.txHash} explorerUrl={explorerUrl} />
                        <br />
                        {c.onchain?.status}
                        {c.onchain?.block !== undefined && (
                          <>
                            , block {c.onchain.block}
                            <br />
                            {c.onchain.nullifiers} nullifiers, {c.onchain.noteHashes} note hashes, {c.onchain.logs} logs
                          </>
                        )}
                      </>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
      <section id="vault">
        <h2>Document vault</h2>
        <p className="muted">
          Each blob is the whole agreement, with its legal text, or a party's signature evidence, as AES-256-GCM
          ciphertext under a key that only the salt gives.
        </p>
        <p className="callout metalex">
          The vault keeps each blob after the retention period. Without the salt, MetaLeX cannot read it. A party with the
          invite link can still fetch and decrypt it.
        </p>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Locator</th>
                <th>Size</th>
                <th>Content</th>
              </tr>
            </thead>
            <tbody>
              {data.vault.map(b => (
                <tr key={b.locator}>
                  <td className="mono">{short(b.locator)}</td>
                  <td>{b.bytes} bytes</td>
                  <td className="mono">{b.ciphertext.slice(0, 64)}…</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
      <section id="data-keys">
        <h2>Data key store</h2>
        <p className="muted">
          Each salt is encrypted with ENCRYPTION_KEY. Only a party gets it, and only until the retention period ends.
          Then the store deletes the salt only. The encrypted document stays in the vault.
        </p>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Agreement id</th>
                <th>Access</th>
                <th>Retain until</th>
                <th>Encrypted salt</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {data.dataKeys.length === 0 && (
                <tr>
                  <td colSpan={5} className="muted" id="no-data-keys">
                    No data keys. MetaLeX cannot decrypt the documents in the vault.
                  </td>
                </tr>
              )}
              {data.dataKeys.map(k => (
                <tr key={k.agreementId}>
                  <td className="mono">{short(k.agreementId)}</td>
                  <td>{k.parties.join(', ')}</td>
                  <td>{new Date(k.retainUntil).toLocaleDateString()}</td>
                  <td className="mono">{k.ciphertext.slice(0, 40)}…</td>
                  <td>
                    <Busy
                      label="End retention now"
                      busyLabel="Deleting…"
                      secondary
                      onClick={async () => {
                        await endRetention({ data: { agreementId: k.agreementId } });
                        load();
                      }}
                    />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </>
  );
}

const ROLES = ['alice', 'bob', 'auditor', 'metalex'] as const;

export default function App({ role }: { role: string }) {
  const [explorerUrl, setExplorerUrl] = useState<string>();
  useEffect(() => {
    import('../server/metalex').then(m => m.getConfig()).then(c => setExplorerUrl(c.explorerUrl));
  }, []);
  return (
    <>
      <header className="top">
        <div className="brand">
          Private Agreements <span className="muted">· Aztec PoC</span>
        </div>
        <nav aria-label="Roles">
          {ROLES.map(r => (
            <a key={r} href={`/${r}`} className={r === role ? 'active' : undefined} aria-current={r === role ? 'page' : undefined}>
              {r === 'metalex' ? 'MetaLeX' : ROLE_NAMES[r]}
            </a>
          ))}
        </nav>
      </header>
      <main>
        {role === 'alice' || role === 'bob' ? (
          <PartyPage role={role} />
        ) : role === 'auditor' ? (
          <AuditorPage />
        ) : role === 'metalex' ? (
          <MetalexPage explorerUrl={explorerUrl} />
        ) : (
          <p>Page not found.</p>
        )}
      </main>
    </>
  );
}

