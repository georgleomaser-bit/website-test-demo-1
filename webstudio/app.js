// Web-Studio: Generator, Angebote/Rechnungen und Kunden-Board, lokal gespeichert
const { PRESETS, BASE, render, check, esc } = window.WS;
const KEY = 'webstudio.v1';
const $ = (id) => document.getElementById(id);
const euro = (n) => n.toLocaleString('de-DE', { style: 'currency', currency: 'EUR' });

const PACKAGES = [
  { id: 'start', name: 'Start', price: 290, items: ['Onepager mit Leistungen, Öffnungszeiten, Kontakt', 'Optimiert fürs Handy', 'Impressum & Datenschutz-Grundgerüst', '1 Änderungsrunde'] },
  { id: 'business', name: 'Business', price: 490, items: ['Alles aus Start', 'Eigene Fotos & Texte eingebaut', 'Google-Unternehmensprofil eingerichtet', '3 Änderungsrunden'] },
  { id: 'premium', name: 'Premium', price: 690, items: ['Alles aus Business', 'Online-Hochladen & Domain-Einrichtung', 'Einweisung vor Ort (1 Std.)', '3 Monate Wartung inklusive'] }
];
const EXTRAS = [
  { id: 'care', name: 'Wartung', price: 19, unit: '/Monat', note: 'Öffnungszeiten, Preise, Texte ändern' },
  { id: 'photo', name: 'Fotos vor Ort', price: 79, note: '15 bearbeitete Handy-Fotos' },
  { id: 'domain', name: 'Domain-Einrichtung', price: 29, note: 'Domain läuft auf den Kunden' },
  { id: 'gmb', name: 'Google-Profil', price: 49, note: 'Eintrag in Google Maps' }
];
const STAGES = [
  { id: 'lead', name: 'Kontakt' }, { id: 'offer', name: 'Angebot' },
  { id: 'won', name: 'Auftrag' }, { id: 'paid', name: 'Bezahlt' }
];
const FIELDS = ['name', 'claim', 'about', 'services', 'hours', 'phone', 'mail', 'addr', 'color', 'style', 'owner'];

function fresh(kind = 'friseur') {
  const p = PRESETS[kind];
  return { kind, ...BASE, name: p.name, claim: p.claim, about: p.about, services: p.services, hours: p.hours, color: p.color, style: p.style };
}
function load() {
  try {
    const s = JSON.parse(localStorage.getItem(KEY));
    if (s && s.site && Array.isArray(s.leads)) return { goal: 1299, docNo: 1, ...s };
  } catch (e) { /* kein Speicher verfügbar */ }
  return { site: fresh(), offer: { pkg: 'start', extras: [], client: '', me: '', type: 'Angebot' }, leads: [], goal: 1299, docNo: 1 };
}
let saveTimer;
function save() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => { try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) { /* ignorieren */ } }, 150);
}
const state = load();

/* ---------- Tabs ---------- */
function showTab(t) {
  document.querySelectorAll('nav [data-tab]').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.tab === t)));
  document.querySelectorAll('main > section').forEach((s) => { s.hidden = s.id !== 'tab-' + t; });
  if (t === 'offer') renderDoc();
  if (t === 'crm') renderBoard();
  window.scrollTo(0, 0);
}
document.querySelectorAll('nav [data-tab]').forEach((b) => b.addEventListener('click', () => showTab(b.dataset.tab)));

/* ---------- Builder ---------- */
const kindSel = $('f-kind');
Object.entries(PRESETS).forEach(([k, p]) => kindSel.add(new Option(p.label, k)));

function fillForm() {
  kindSel.value = state.site.kind;
  FIELDS.forEach((f) => { $('f-' + f).value = state.site[f] ?? ''; });
}
let pvTimer;
function updatePreview() {
  clearTimeout(pvTimer);
  pvTimer = setTimeout(() => {
    $('pv').srcdoc = render(state.site);
    const ul = $('checks');
    ul.textContent = '';
    check(state.site).forEach(({ ok, t }) => {
      const li = document.createElement('li');
      li.textContent = t;
      if (!ok) li.className = 'bad';
      ul.append(li);
    });
  }, 120);
}
FIELDS.forEach((f) => $('f-' + f).addEventListener('input', (e) => { state.site[f] = e.target.value; save(); updatePreview(); }));
kindSel.addEventListener('change', () => {
  const keep = { phone: state.site.phone, mail: state.site.mail, addr: state.site.addr, owner: state.site.owner };
  state.site = { ...fresh(kindSel.value), ...keep };
  fillForm(); save(); updatePreview();
});
$('resetSite').addEventListener('click', () => { state.site = fresh(kindSel.value); fillForm(); save(); updatePreview(); });
document.querySelectorAll('[data-w]').forEach((b) => b.addEventListener('click', () => {
  $('pv').style.maxWidth = b.dataset.w ? b.dataset.w + 'px' : '100%';
}));

function slug(s) {
  return String(s || 'webseite').toLowerCase().replace(/ä/g, 'ae').replace(/ö/g, 'oe').replace(/ü/g, 'ue').replace(/ß/g, 'ss').normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'webseite';
}
$('dl').addEventListener('click', () => {
  const blob = new Blob([render(state.site)], { type: 'text/html;charset=utf-8' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = slug(state.site.name) + '.html';
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
});
$('toOffer').addEventListener('click', () => {
  if (!state.offer.client) state.offer.client = state.site.name;
  $('o-client').value = state.offer.client;
  save(); showTab('offer');
});

/* ---------- Angebot / Rechnung ---------- */
function pkgCard(list, type, name) {
  const wrap = $(type === 'radio' ? 'packages' : 'extras');
  list.forEach((p) => {
    const l = document.createElement('label');
    l.className = 'pkg';
    const inp = document.createElement('input');
    inp.type = type; inp.name = name; inp.value = p.id;
    inp.checked = type === 'radio' ? state.offer.pkg === p.id : state.offer.extras.includes(p.id);
    inp.addEventListener('change', () => {
      if (type === 'radio') state.offer.pkg = p.id;
      else state.offer.extras = [...document.querySelectorAll('#extras input:checked')].map((i) => i.value);
      save(); renderDoc();
    });
    const t = document.createElement('span');
    t.innerHTML = `${esc(p.name)}<strong>${euro(p.price)}${p.unit ? esc(p.unit) : ''}</strong><span class="small muted">${esc(p.note || p.items.join(' · '))}</span>`;
    l.append(inp, t);
    wrap.append(l);
  });
}
pkgCard(PACKAGES, 'radio', 'pkg');
pkgCard(EXTRAS, 'checkbox', 'extra');
['client', 'me', 'type'].forEach((f) => {
  const el = $('o-' + f);
  el.value = state.offer[f] || (f === 'type' ? 'Angebot' : '');
  el.addEventListener('input', () => { state.offer[f] = el.value; save(); renderDoc(); });
});

function offerLines() {
  const p = PACKAGES.find((x) => x.id === state.offer.pkg) || PACKAGES[0];
  const rows = [{ name: `Webseite „${p.name}“`, detail: p.items.join(', '), price: p.price, once: true }];
  EXTRAS.filter((e) => state.offer.extras.includes(e.id)).forEach((e) => rows.push({ name: e.name, detail: e.note, price: e.price, once: !e.unit, unit: e.unit }));
  return rows;
}
function offerTotal() { return offerLines().filter((r) => r.once).reduce((a, r) => a + r.price, 0); }

function renderDoc() {
  const o = state.offer;
  const rows = offerLines();
  const once = offerTotal();
  const monthly = rows.filter((r) => !r.once).reduce((a, r) => a + r.price, 0);
  const d = new Date();
  const valid = new Date(d); valid.setDate(d.getDate() + 14);
  const no = `${o.type === 'Rechnung' ? 'RE' : 'AN'}-${d.getFullYear()}-${String(state.docNo).padStart(3, '0')}`;
  const isInv = o.type === 'Rechnung';
  $('doc').innerHTML = `
    <p class="small">${esc(o.me || 'Dein Name')} · Web-Studio</p>
    <p>An: <strong>${esc(o.client || 'Kunde')}</strong></p>
    <h2>${esc(o.type)} ${no}</h2>
    <p class="small">Datum: ${d.toLocaleDateString('de-DE')}${isInv ? '' : ` · gültig bis ${valid.toLocaleDateString('de-DE')}`}</p>
    <table><thead><tr><th>Leistung</th><th class="n">Preis</th></tr></thead><tbody>
    ${rows.map((r) => `<tr><td><strong>${esc(r.name)}</strong><br><span class="small">${esc(r.detail)}</span></td><td class="n">${euro(r.price)}${r.unit ? esc(r.unit) : ''}</td></tr>`).join('')}
    <tr><td><strong>Summe einmalig</strong></td><td class="n"><strong>${euro(once)}</strong></td></tr>
    ${monthly ? `<tr><td>Laufend</td><td class="n">${euro(monthly)}/Monat, monatlich kündbar</td></tr>` : ''}
    </tbody></table>
    <p class="small" style="margin-top:14px">Gemäß § 19 UStG wird keine Umsatzsteuer berechnet (Kleinunternehmerregelung).</p>
    <p class="small">${isInv ? 'Bitte innerhalb von 14 Tagen bar oder per Überweisung zahlen.' : 'Zahlung: 50 % bei Auftrag, 50 % bei Übergabe. Domain und Hosting laufen auf den Namen des Kunden.'}</p>
    <p class="small">Vielen Dank – ${esc(o.me || '')}</p>`;
}
$('print').addEventListener('click', () => { window.print(); state.docNo += 1; save(); renderDoc(); });
$('toLead').addEventListener('click', () => {
  const name = state.offer.client || state.site.name;
  state.leads.push({ id: Date.now(), name, contact: state.site.phone || '', value: offerTotal(), stage: 'offer' });
  save(); showTab('crm');
});

/* ---------- Kunden-Board ---------- */
$('leadForm').addEventListener('submit', (e) => {
  e.preventDefault();
  state.leads.push({ id: Date.now(), name: $('l-name').value.trim(), contact: $('l-contact').value.trim(), value: Number($('l-value').value) || 290, stage: 'lead' });
  e.target.reset(); save(); renderBoard();
});
$('goalInput').value = state.goal;
$('goalInput').addEventListener('input', () => { const g = Number($('goalInput').value); if (g > 0) { state.goal = g; save(); renderBoard(); } });

function renderBoard() {
  const board = $('board');
  board.textContent = '';
  STAGES.forEach((st, i) => {
    const col = document.createElement('div');
    col.className = 'col';
    const items = state.leads.filter((l) => l.stage === st.id);
    col.innerHTML = `<h3><span>${st.name}</span><span class="muted small">${items.length} · ${euro(items.reduce((a, l) => a + l.value, 0))}</span></h3>`;
    items.forEach((l) => {
      const card = document.createElement('div');
      card.className = 'lead';
      card.innerHTML = `<b>${esc(l.name)}</b><span class="small muted">${esc(l.contact)} · ${euro(l.value)}</span>`;
      const acts = document.createElement('div');
      acts.className = 'acts';
      const btn = (txt, fn, ghost = true) => { const b = document.createElement('button'); b.type = 'button'; b.textContent = txt; if (ghost) b.className = 'ghost'; b.addEventListener('click', fn); acts.append(b); };
      if (i > 0) btn('←', () => { l.stage = STAGES[i - 1].id; save(); renderBoard(); });
      if (i < STAGES.length - 1) btn(STAGES[i + 1].name + ' →', () => { l.stage = STAGES[i + 1].id; save(); renderBoard(); }, false);
      btn('Löschen', () => { if (confirm(`„${l.name}“ löschen?`)) { state.leads = state.leads.filter((x) => x.id !== l.id); save(); renderBoard(); } });
      card.append(acts);
      col.append(card);
    });
    board.append(col);
  });
  renderStats();
}
function renderStats() {
  const sum = (st) => state.leads.filter((l) => st.includes(l.stage)).reduce((a, l) => a + l.value, 0);
  const paid = sum(['paid']);
  const left = Math.max(0, state.goal - paid);
  const closed = state.leads.filter((l) => l.stage === 'won' || l.stage === 'paid').length;
  const avg = state.leads.length ? state.leads.reduce((a, l) => a + l.value, 0) / state.leads.length : 390;
  $('c-paid').textContent = euro(paid);
  $('c-open').textContent = euro(sum(['won']));
  $('c-rate').textContent = state.leads.length ? Math.round((closed / state.leads.length) * 100) + ' %' : '–';
  $('c-need').textContent = left ? String(Math.ceil(left / Math.max(1, avg))) : 'Geschafft 🎉';
  $('goalText').textContent = left ? `iPhone 18 Pro: ${euro(paid)} von ${euro(state.goal)}` : 'iPhone 18 Pro: geschafft! 🎉';
  $('goalBar').style.width = Math.min(100, (paid / state.goal) * 100) + '%';
}

fillForm();
updatePreview();
renderStats();
