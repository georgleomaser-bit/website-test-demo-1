// Handy-Hilfe: Sparziel-Tracker und Flyer, alles lokal im Browser gespeichert
const KEY = 'handyhilfe.v1';
const AVG_JOB = 20;
const $ = (id) => document.getElementById(id);
const euro = (n) => n.toLocaleString('de-DE', { style: 'currency', currency: 'EUR', maximumFractionDigits: 2 });

function load() {
  try {
    const s = JSON.parse(localStorage.getItem(KEY));
    if (s && Array.isArray(s.log)) return { goal: 1299, perWeek: 3, flyer: {}, ...s };
  } catch (e) { /* kein Speicher verfügbar */ }
  return { goal: 1299, perWeek: 3, log: [], flyer: {} };
}
function save() {
  try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) { /* ignorieren */ }
}

const state = load();

function render() {
  const saved = state.log.reduce((a, e) => a + e.amount, 0);
  const left = Math.max(0, state.goal - saved);
  const pct = state.goal > 0 ? Math.min(100, (saved / state.goal) * 100) : 0;
  const avg = state.log.length ? saved / state.log.length : AVG_JOB;
  const jobs = left > 0 ? Math.ceil(left / Math.max(1, avg)) : 0;

  $('goal').value = state.goal;
  $('perWeek').value = state.perWeek;
  $('barFill').style.width = pct + '%';
  $('sSaved').textContent = euro(saved);
  $('sLeft').textContent = euro(left);
  $('sJobs').textContent = left > 0 ? String(jobs) : '0';

  if (left === 0) {
    $('sDate').textContent = 'jetzt';
    $('status').innerHTML = '<span class="done">Geschafft! Du kannst dir das iPhone 18 Pro kaufen. 🎉</span>';
  } else {
    $('status').textContent = `${pct.toFixed(1).replace('.', ',')} % geschafft`;
    if (state.perWeek > 0) {
      const d = new Date();
      d.setDate(d.getDate() + Math.ceil((jobs / state.perWeek) * 7));
      $('sDate').textContent = d.toLocaleDateString('de-DE', { month: 'short', year: 'numeric' });
    } else {
      $('sDate').textContent = '–';
    }
  }

  const log = $('log');
  log.textContent = '';
  state.log.slice().reverse().forEach((e) => {
    const li = document.createElement('li');
    const label = document.createElement('span');
    label.textContent = `${new Date(e.at).toLocaleDateString('de-DE')} · ${e.text} · ${euro(e.amount)}`;
    const del = document.createElement('button');
    del.className = 'ghost';
    del.type = 'button';
    del.textContent = 'Löschen';
    del.addEventListener('click', () => {
      state.log = state.log.filter((x) => x.id !== e.id);
      save(); render();
    });
    li.append(label, del);
    log.append(li);
  });
}

$('goalForm').addEventListener('submit', (ev) => {
  ev.preventDefault();
  const g = Number($('goal').value);
  const w = Number($('perWeek').value);
  if (g > 0) state.goal = g;
  if (w >= 0) state.perWeek = w;
  save(); render();
});

$('kind').addEventListener('change', () => {
  const price = Number($('kind').value.split('|')[1]);
  $('amount').value = price || '';
});

$('addForm').addEventListener('submit', (ev) => {
  ev.preventDefault();
  const [text, preset] = $('kind').value.split('|');
  const amount = Number($('amount').value) || Number(preset);
  if (!(amount > 0)) { $('amount').focus(); return; }
  state.log.push({ id: Date.now() + Math.random(), at: Date.now(), text, amount });
  $('amount').value = '';
  save(); render();
});

document.querySelectorAll('[data-key]').forEach((el) => {
  const k = el.dataset.key;
  if (state.flyer[k]) el.textContent = state.flyer[k];
  el.addEventListener('input', () => { state.flyer[k] = el.textContent.trim(); save(); });
});
$('printBtn').addEventListener('click', () => window.print());

$('amount').value = 25;
render();
