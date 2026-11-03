const app = document.getElementById('app');
const role = location.pathname.split('/')[1] || 'alice';
let state;
let pollTimer;

const esc = s =>
  String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const short = hex => (hex ? `${hex.slice(0, 10)}…${hex.slice(-6)}` : '');
// `#invite=` is a link that the user got. `#stored=` opens an agreement with the salt from the data key store.
const hashParams = () => new URLSearchParams(location.hash.slice(1));
// A link to the tx in the block explorer, or the short hash when the network has no explorer.
const txLink = hash =>
  state.explorerUrl
    ? `<a class="mono" href="${esc(`${state.explorerUrl}/tx-effects/${hash}`)}" target="_blank" rel="noopener">${esc(short(hash))}</a>`
    : `<span class="mono">${esc(short(hash))}</span>`;
const inviteFromHash = () => hashParams().get('invite') ?? hashParams().get('stored');
const userOf = key => state.users.find(u => u.key === key);

async function api(path, body) {
  const res = await fetch(path, body ? { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) } : {});
  const json = await res.json();
  if (!res.ok) throw new Error(json.error);
  return json;
}

function poll(fn, ms = 3000) {
  clearTimeout(pollTimer);
  pollTimer = setTimeout(fn, ms);
}

async function busy(button, label, fn) {
  const text = button.textContent;
  button.disabled = true;
  button.textContent = label;
  try {
    await fn();
  } catch (err) {
    button.insertAdjacentHTML('afterend', `<p class="error">${esc(err.message)}</p>`);
  } finally {
    button.disabled = false;
    button.textContent = text;
  }
}

function roleHeader(title, tag, kind, detail) {
  return `<div class="role"><h1>${esc(title)}</h1><span class="tag ${kind}">${esc(tag)}</span>
    ${detail ? `<span class="muted mono">${esc(detail)}</span>` : ''}</div>`;
}

function statusOf(view) {
  if (view.finalized) return '<span class="status finalized">Finalized</span>';
  if (view.settlement?.status === 'failed') return '<span class="status failed">Settlement failed</span>';
  return '<span class="status pending">Pending</span>';
}

function documentHtml(doc) {
  const names = doc.partyValues.map(([address, [name]]) => `<b>${esc(name)}</b> (<span class="mono">${esc(short(address))}</span>)`);
  return `<div class="doc">
    <h3>${esc(doc.template.title)}</h3>
    <p>This ${esc(doc.template.title)} is made on <b>${esc(doc.globalValues[0])}</b> (the "Effective Date") between
      ${names.join(' and ')}.</p>
    <ol>${doc.template.text.map(clause => `<li>${esc(clause)}</li>`).join('')}</ol>
  </div>`;
}

// Invite links stay in this browser only. MetaLeX never gets them.
const inviteKey = `invites:${role}`;
function savedInvites() {
  try {
    return JSON.parse(localStorage.getItem(inviteKey) ?? '[]');
  } catch {
    return [];
  }
}
function saveInvite(invite, agreementId) {
  const list = savedInvites().filter(i => i.agreementId !== agreementId);
  try {
    localStorage.setItem(inviteKey, JSON.stringify([{ invite, agreementId }, ...list]));
  } catch {}
}
const counterpartyRole = () => (role === 'alice' ? 'bob' : 'alice');

function savedInvitesHtml() {
  const list = savedInvites();
  const rows = list
    .map(
      i => `<tr><td class="mono">${esc(short(i.agreementId))}</td>
        <td><input class="mono" readonly aria-label="Invite link ${esc(short(i.agreementId))}" value="${esc(`${location.origin}/${counterpartyRole()}#invite=${i.invite}`)}"></td>
        <td><a class="button secondary" href="#invite=${esc(i.invite)}">Open</a></td></tr>`,
    )
    .join('');
  return `<h2>Invite links on this device</h2>
    <p class="muted">Your browser keeps a copy of each invite link. MetaLeX does not have it. You can send a link again
      to your counterparty.</p>
    ${list.length ? `<div class="table-wrap"><table><thead><tr><th>Agreement id</th><th>Invite link</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>` : '<p id="no-invites">No invite links on this device.</p>'}`;
}

function agreementHtml(view, me) {
  const name = address => view.parties.find(p => p.address === address)?.name;
  const iSigned = view.signers?.signed.includes(me);
  let progress = '';
  if (view.finalized) {
    const tx = view.settlement?.txHash ? ` in one transaction: ${txLink(view.settlement.txHash)}` : '';
    progress = `<p class="callout" id="finalized">All parties signed. MetaLeX finalized the agreement on Aztec${tx}.</p>`;
  } else if (view.settlement?.status === 'failed') {
    progress = `<p class="error">Settlement failed: ${esc(view.settlement.error)}</p>`;
  } else if (view.signers && view.signers.pending.length === 0) {
    progress = '<p class="callout">All parties signed. MetaLeX is sending the finalize transaction.</p>';
  } else if (view.signers) {
    progress = `<p class="callout">Waiting for: ${view.signers.pending.map(name).map(esc).join(', ')}</p>`;
  }
  const canSign = view.isParty && !view.finalized && !iSigned;
  return `<section id="agreement">
    <div class="role"><h2>Agreement</h2>${statusOf(view)}</div>
    <dl class="facts">
      <dt>Agreement id</dt><dd class="mono">${esc(view.agreementId)}</dd>
      <dt>Parties</dt><dd>${view.parties.map(p => `${esc(p.name)} <span class="mono">${esc(short(p.address))}</span>`).join(', ')}</dd>
      <dt>Expiry</dt><dd>${view.expiry === '0' ? 'None' : esc(new Date(Number(view.expiry) * 1000).toLocaleString())}</dd>
      <dt>Document</dt><dd>Encrypted in the MetaLeX vault at locator <span class="mono">${esc(short(view.locator))}</span>. This device decrypted it with the salt from the invite.</dd>
      ${view.signers ? `<dt>Signed</dt><dd>${view.signers.signed.map(name).map(esc).join(', ') || 'Nobody yet'}</dd>` : ''}
    </dl>
    ${documentHtml(view.document)}
    ${progress}
    ${canSign ? '<div class="actions"><button id="sign">Sign</button><span class="muted">Your wallet signs an authwit. You send no transaction.</span></div>' : ''}
  </section>`;
}

// The status that the agreement section shows. A change also refreshes "Your agreements".
let shownStatus;

// `view` is the result of a sign call. Without it, the device opens the invite again.
async function renderAgreement(device, invite, view) {
  view ??= await api(`/api/device/${device}/open`, { invite });
  if (view.isParty && hashParams().get('invite') === invite) saveInvite(invite, view.agreementId);
  const me = userOf(device)?.address;
  const holder = document.getElementById('agreement-slot');
  holder.innerHTML = agreementHtml(view, me);
  const status = statusOf(view);
  if (shownStatus !== undefined && status !== shownStatus && document.getElementById('mine')) {
    await renderMyAgreements(device);
  }
  shownStatus = status;
  document.getElementById('sign')?.addEventListener('click', e =>
    busy(e.target, 'Signing…', async () => {
      await renderAgreement(device, invite, await api(`/api/device/${device}/sign`, { invite }));
    }),
  );
  if (view.isParty && !view.finalized && view.settlement?.status !== 'failed') poll(() => renderAgreement(device, invite));
  return view;
}

async function renderMyAgreements(device) {
  const holder = document.getElementById('mine');
  const views = await api(`/api/device/${device}/agreements`);
  const rows = views
    .map(
      v => `<tr><td>${esc(v.document.template.title)}</td><td class="mono">${esc(short(v.agreementId))}</td>
        <td>${statusOf(v)}</td><td><a class="button secondary" href="#stored=${esc(v.invite)}">Open</a></td></tr>`,
    )
    .join('');
  holder.innerHTML = `<h2>Your agreements</h2>
    <p class="muted">The MetaLeX data key store gives the salt of each agreement to its parties during the retention
      period. So you can open them without the invite link.</p>
    ${views.length ? `<div class="table-wrap"><table><thead><tr><th>Title</th><th>Agreement id</th><th>Status</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>` : '<p id="no-agreements">No agreements in the data key store.</p>'}`;
}

function draftHtml(me) {
  const others = state.users.filter(u => u.address && u.key !== role);
  const today = new Date().toISOString().slice(0, 10);
  return `<section id="draft">
    <h2>New ${esc(state.template.title)}</h2>
    <p class="muted">The document, with the full legal text, stays on your device. MetaLeX gets it only as ciphertext
      in its document vault.</p>
    <form id="draft-form">
      <label>Effective date<input name="effectiveDate" type="date" value="${today}" required></label>
      <label>Your legal name<input name="myName" value="${esc(me.name)} Corp" required></label>
      <label>Counterparty<select name="counterparty">${others.map(u => `<option value="${esc(u.address)}">${esc(u.name)} · ${esc(short(u.address))}</option>`).join('')}</select></label>
      <label>Counterparty legal name<input name="theirName" value="Bob LLC" required></label>
      <label>Expiry (optional)<input name="expiry" type="datetime-local"></label>
    </form>
    <div class="actions"><button id="review" form="draft-form">Review</button></div>
  </section>`;
}

function readDraft(me) {
  const form = new FormData(document.getElementById('draft-form'));
  const counterparty = form.get('counterparty');
  return {
    effectiveDate: form.get('effectiveDate'),
    counterparty,
    names: { [me.address]: form.get('myName'), [counterparty]: form.get('theirName') },
    expiry: form.get('expiry'),
  };
}

function reviewHtml(me, draft) {
  const doc = {
    template: state.template,
    globalValues: [draft.effectiveDate],
    partyValues: Object.entries(draft.names).map(([address, name]) => [address, [name]]),
  };
  return `<section id="review-step">
    <h2>Review and sign</h2>
    <p class="muted">Your wallet signs an authwit for this agreement. MetaLeX collects the signatures and sends one
      private transaction when all parties signed.</p>
    ${documentHtml(doc)}
    <div class="actions"><button id="sign-new">Sign</button><button class="secondary" id="edit">Edit</button></div>
  </section>`;
}

function inviteHtml(result) {
  const link = `${location.origin}/bob#invite=${result.invite}`;
  return `<section id="invite">
    <h2>Signed. Send the invite to your counterparty</h2>
    <p class="muted">The invite holds the salt, the expiry and the parties. It is in the URL fragment, so the link does
      not send it to MetaLeX.</p>
    <div class="invite"><input id="invite-link" class="mono" readonly value="${esc(link)}" aria-label="Invite link"></div>
    <dl class="facts"><dt>Agreement id</dt><dd class="mono">${esc(result.agreementId)}</dd></dl>
    <div class="actions">
      <a class="button" href="/bob#invite=${esc(result.invite)}">Open as Bob</a>
      <a class="button secondary" href="/auditor#invite=${esc(result.invite)}">Open as auditor</a>
      <a class="button secondary" href="#invite=${esc(result.invite)}">Open as Alice</a>
    </div>
  </section>`;
}

async function renderParty() {
  const me = userOf(role);
  const invite = inviteFromHash();
  app.innerHTML = `${roleHeader(me.name, 'User device', 'device', me.address)}
    <div id="agreement-slot"></div><div id="draft-slot"></div><section id="mine"><p class="muted">Loading…</p></section>
    <section id="saved"></section>`;
  if (invite) await renderAgreement(role, invite);
  else if (role === 'alice') showDraft(me);
  document.getElementById('saved').innerHTML = savedInvitesHtml();
  await renderMyAgreements(role);
}

function showDraft(me, draft) {
  const slot = document.getElementById('draft-slot');
  slot.innerHTML = draftHtml(me);
  if (draft) for (const [k, v] of Object.entries({ effectiveDate: draft.effectiveDate, expiry: draft.expiry })) slot.querySelector(`[name=${k}]`).value = v;
  document.getElementById('draft-form').addEventListener('submit', e => {
    e.preventDefault();
    const next = readDraft(me);
    slot.innerHTML = reviewHtml(me, next);
    document.getElementById('edit').addEventListener('click', () => showDraft(me, next));
    document.getElementById('sign-new').addEventListener('click', e =>
      busy(e.target, 'Signing…', async () => {
        const result = await api(`/api/device/${role}/create`, next);
        saveInvite(result.invite, result.agreementId);
        slot.innerHTML = inviteHtml(result);
        document.getElementById('saved').innerHTML = savedInvitesHtml();
        await renderMyAgreements(role);
      }),
    );
  });
}

async function renderAuditor() {
  const invite = inviteFromHash();
  app.innerHTML = `${roleHeader('Auditor', 'User device', 'device', 'No Aztec account')}
    <section><h2>Open an invite link</h2>
      <p class="muted">A party shares the invite link with you. You read the status from the chain. You send no transaction.</p>
      <form id="open-form"><label>Invite link<input name="link" placeholder="http://…#invite=…" required></label></form>
      <div class="actions"><button form="open-form">Open</button></div>
    </section>
    <div id="agreement-slot"></div><div id="verify-slot"></div>`;
  document.getElementById('open-form').addEventListener('submit', e => {
    e.preventDefault();
    location.hash = new URL(new FormData(e.target).get('link')).hash;
  });
  if (invite) renderVerify(invite, await renderAgreement('auditor', invite));
}

function verifyFormHtml(view) {
  const doc = view.document;
  const field = (label, name, value, attrs = '') =>
    `<label>${esc(label)}<input data-field="${name}" value="${esc(value)}" ${attrs}></label>`;
  return `<section id="verify">
    <h2>Verify the signatures</h2>
    <p class="muted">Change a party address, the expiry or any part of the document. This device checks two proofs
      at once. Path 1: the registry recorded this exact agreement as finalized. Path 2: each party's stored signature
      is valid for these exact terms, by a key that the party address commits to.</p>
    <form id="verify-form" class="grid">
      ${view.parties.map((p, i) => field(`Party ${i + 1} address (${p.name})`, `party:${i}`, p.address, 'class="mono"')).join('')}
      ${field('Expiry (Unix seconds, 0 = none)', 'expiry', view.expiry)}
      ${field('Effective date', 'date', doc.globalValues[0])}
      ${doc.partyValues.map(([, [name]], i) => field(`Party ${i + 1} legal name`, `name:${i}`, name)).join('')}
    </form>
    <div class="clauses">${doc.template.text
      .map((c, i) => `<label>Clause ${i + 1}<textarea data-field="clause:${i}" rows="2">${esc(c)}</textarea></label>`)
      .join('')}</div>
    <div class="actions"><button class="secondary" id="verify-reset">Reset to the invite</button></div>
    <div id="verify-result" aria-live="polite"><p class="muted">Checking…</p></div>
  </section>`;
}

// The terms in the form: the invite's terms with the user's changes.
function editedTerms(view) {
  const value = name => document.querySelector(`[data-field="${name}"]`).value;
  const doc = structuredClone(view.document);
  doc.globalValues[0] = value('date');
  doc.partyValues.forEach((entry, i) => (entry[1][0] = value(`name:${i}`)));
  doc.template.text = doc.template.text.map((_, i) => value(`clause:${i}`));
  return { expiry: value('expiry'), parties: view.parties.map((_, i) => value(`party:${i}`)), document: doc };
}

function verifyResultHtml(view, r) {
  const mark = ok => (ok ? '<span class="ok">✓</span>' : '<span class="bad">✗</span>');
  const nameOf = address => view.parties.find(p => p.address === address)?.name ?? short(address);
  const verdict =
    r.finalized && r.signed
      ? '<p class="verdict ok-bg">✓ These are the exact terms that the parties signed and that MetaLeX finalized.</p>'
      : '<p class="verdict bad-bg">✗ These terms were not signed and finalized.</p>';
  const signatures = r.signatures
    .map(s =>
      s.evidenceFound
        ? `<li>${esc(nameOf(s.party))}: ${mark(s.addressMatches)} address commits to the key
            ${mark(s.schnorrAccount)} Schnorr account ${mark(s.keyMatches)} key in the account
            ${mark(s.signatureValid)} signature over these terms</li>`
        : `<li>${esc(nameOf(s.party))}: ${mark(false)} no stored signature for this address</li>`,
    )
    .join('');
  return `${verdict}
    <dl class="facts">
      <dt>Agreement id</dt><dd class="mono">${esc(r.agreementId)} ${r.agreementId === view.agreementId ? '(same as the invite)' : '(different from the invite)'}</dd>
      <dt>Path 1 · chain</dt><dd>${mark(r.finalized)} finalized nullifier of this agreement id onchain</dd>
      <dt>Path 2 · signatures</dt><dd><ul class="checks">${signatures}</ul></dd>
    </dl>`;
}

// Checks the terms again after each change. Only the answer to the newest request is shown.
function renderVerify(invite, view) {
  document.getElementById('verify-slot').innerHTML = verifyFormHtml(view);
  const result = document.getElementById('verify-result');
  let request = 0;
  let timer;
  const check = async () => {
    const mine = ++request;
    result.innerHTML = '<p class="muted">Checking…</p>';
    try {
      const r = await api('/api/device/auditor/verify', { invite, ...editedTerms(view) });
      if (mine === request) result.innerHTML = verifyResultHtml(view, r);
    } catch (err) {
      if (mine === request) result.innerHTML = `<p class="verdict bad-bg">✗ ${esc(err.message)}</p>`;
    }
  };
  document.getElementById('verify').addEventListener('input', () => {
    clearTimeout(timer);
    timer = setTimeout(check, 400);
  });
  document.getElementById('verify-reset').addEventListener('click', () => renderVerify(invite, view));
  check();
}

async function renderMetalex() {
  const v = await api('/api/metalex');
  const settlement = s => {
    if (!s) return '<span class="muted">Waiting for signatures</span>';
    if (s.status === 'settling') return '<span class="status pending">Sending finalize</span>';
    if (s.status === 'failed') return `<span class="error">${esc(s.error)}</span>`;
    return `<span class="status finalized">Finalized</span><br>Block ${s.block}<br>
      tx ${txLink(s.txHash)}<br>${s.nullifiers} nullifiers, ${s.noteHashes} note hashes, ${s.logs} logs<br>
      Fee payer: ${s.feePayer === v.fpc ? 'MetaLeX FPC' : esc(short(s.feePayer))}`;
  };
  app.innerHTML = `${roleHeader('MetaLeX services', 'What MetaLeX sees', 'metalex', `registry ${short(v.registry)}`)}
    <p class="callout metalex">MetaLeX sees no document and no terms hash. The vault and the data key store hold only
      ciphertext. During the retention period, MetaLeX can decrypt a salt with ENCRYPTION_KEY. That is the accepted trust.</p>
    <section id="collector"><h2>Signature collector and settler</h2>
      <p class="muted">The agreement without the salt, and one authwit for each party.</p>
      <div class="table-wrap"><table><thead><tr><th>Agreement id</th><th>Parties</th><th>Signed</th><th>Waiting for</th><th>Onchain</th></tr></thead><tbody>
      ${v.collector.map(c => `<tr><td class="mono">${esc(short(c.agreementId))}</td><td>${c.parties.map(p => esc(p.name)).join(', ')}</td>
        <td>${c.signed.map(esc).join(', ')}</td><td>${c.pending.map(esc).join(', ') || '–'}</td><td>${settlement(c.settlement)}</td></tr>`).join('') || '<tr><td colspan="5" class="muted">No agreements yet</td></tr>'}
      </tbody></table></div></section>
    <section id="vault"><h2>Document vault</h2>
      <p class="muted">Each blob is the whole agreement, with its legal text, as AES-256-GCM ciphertext under a key
        that only the salt gives.</p>
      <p class="callout metalex">The vault keeps each blob after the retention period. Without the salt, MetaLeX cannot
        read it. A party with the invite link can still fetch and decrypt it.</p>
      <div class="table-wrap"><table><thead><tr><th>Locator</th><th>Size</th><th>Content</th></tr></thead><tbody>
      ${v.vault.map(b => `<tr><td class="mono">${esc(short(b.locator))}</td><td>${b.bytes} bytes</td><td class="mono">${esc(b.ciphertext.slice(0, 64))}…</td></tr>`).join('') || '<tr><td colspan="3" class="muted">Empty</td></tr>'}
      </tbody></table></div></section>
    <section id="data-keys"><h2>Data key store</h2>
      <p class="muted">Each salt is encrypted with ENCRYPTION_KEY. Only a party gets it, and only until the retention
        period ends. Then the store deletes the salt only. The encrypted document stays in the vault.</p>
      <div class="table-wrap"><table><thead><tr><th>Agreement id</th><th>Access</th><th>Retain until</th><th>Encrypted salt</th><th></th></tr></thead><tbody>
      ${v.dataKeys.map(r => `<tr><td class="mono">${esc(short(r.agreementId))}</td><td>${r.parties.map(esc).join(', ')}</td>
        <td>${esc(new Date(r.retainUntil).toLocaleDateString())}</td><td class="mono">${esc(r.ciphertext.slice(0, 40))}…</td>
        <td><button class="secondary" data-end="${esc(r.agreementId)}">End retention now</button></td></tr>`).join('') || '<tr><td colspan="5" class="muted" id="no-data-keys">No data keys. MetaLeX cannot decrypt the documents in the vault.</td></tr>'}
      </tbody></table></div></section>`;
  for (const button of app.querySelectorAll('[data-end]')) {
    button.addEventListener('click', () => busy(button, 'Deleting…', async () => {
      await api('/api/metalex/end-retention', { agreementId: button.dataset.end });
      await renderMetalex();
    }));
  }
  if (v.collector.some(c => c.settlement?.status === 'settling' || c.pending.length > 0)) poll(renderMetalex);
}

async function render() {
  clearTimeout(pollTimer);
  shownStatus = undefined;
  for (const a of document.querySelectorAll('nav a')) {
    if (a.dataset.role === role) a.setAttribute('aria-current', 'page');
    else a.removeAttribute('aria-current');
  }
  try {
    if (role === 'metalex') await renderMetalex();
    else if (role === 'auditor') await renderAuditor();
    else await renderParty();
  } catch (err) {
    app.insertAdjacentHTML('beforeend', `<p class="error">${esc(err.message)}</p>`);
  }
}

state = await api('/api/state');
window.addEventListener('hashchange', render);
render();
