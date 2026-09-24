// NOVA-Fähigkeiten, die ohne Server und ohne KI funktionieren – sofort und kostenlos:
// Wetter (Open-Meteo), Uhrzeit & Datum, Timer & Erinnerungen, Ziel-Planer („Mach mir 10k“), Rechner, Gedächtnis.
// Das Sprachmodell (Server) nutzt dieselben Funktionen als Werkzeuge.
const store = {
  get(k, d) {
    try {
      const v = localStorage.getItem("nova-" + k);
      return v == null ? d : JSON.parse(v);
    } catch (_) {
      return d;
    }
  },
  set(k, v) {
    try {
      localStorage.setItem("nova-" + k, JSON.stringify(v));
    } catch (_) {
      /* nur für diese Sitzung */
    }
  },
};
export { store };
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const eur = (v, d = 0) => new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR", maximumFractionDigits: d }).format(v);
const n1 = (v) => v.toLocaleString("de-DE", { maximumFractionDigits: 1 });
const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);

// ---------- Profil & Gedächtnis ----------
export const profile = () => store.get("profile", { name: "", city: "" });
export const setProfile = (p) => store.set("profile", { ...profile(), ...p });
export const memory = () => store.get("memory", []);
export function remember(fact) {
  const f = String(fact || "").trim().replace(/[.!]+$/, "").slice(0, 200);
  if (f.length < 3) return false;
  const list = memory().filter((x) => x.t.toLowerCase() !== f.toLowerCase());
  list.push({ t: f, at: Date.now() });
  store.set("memory", list.slice(-50));
  return true;
}
export const forget = (i) => store.set("memory", i == null ? [] : memory().filter((_, j) => j !== i));
// „ich mag Pizza“ → „du magst Pizza“
const PRON = { ich: "du", mich: "dich", mir: "dir", mein: "dein", meine: "deine", meinen: "deinen", meinem: "deinem", meiner: "deiner", meines: "deines" };
const VERB = { bin: "bist", habe: "hast", hab: "hast", mag: "magst", kann: "kannst", will: "willst", muss: "musst", darf: "darfst", soll: "sollst", möchte: "möchtest", weiß: "weißt", werde: "wirst" };
export function toYou(t) {
  const w = String(t).split(/\s+/);
  const ich = w.some((x) => x.toLowerCase() === "ich");
  return w
    .map((x, i) => {
      const l = x.toLowerCase();
      if (PRON[l]) return PRON[l];
      if (!ich) return x;
      if (VERB[l]) return VERB[l];
      const spot = (i > 0 && w[i - 1].toLowerCase() === "ich") || i === w.length - 1;
      if (spot && /^[a-zäöüß]{3,}e$/.test(x) && !/(che|ie)$/.test(x) && !/^(k?eine|gerne?|heute|morgen|immer|lieber|nie|ohne)$/i.test(x)) return /[^aeiouäöü]le$/.test(x) ? x.slice(0, -2) + "elst" : x.slice(0, -1) + (/[dt]e$/.test(x) ? "est" : "st");
      return x;
    })
    .join(" ");
}

// ---------- Wetter (Open-Meteo, kostenlos, ohne Schlüssel) ----------
const WMO = { 0: ["klar", "☀️"], 1: ["überwiegend klar", "🌤️"], 2: ["teils bewölkt", "⛅"], 3: ["bedeckt", "☁️"], 45: ["neblig", "🌫️"], 48: ["neblig mit Reif", "🌫️"], 51: ["leichter Nieselregen", "🌦️"], 53: ["Nieselregen", "🌦️"], 55: ["starker Nieselregen", "🌧️"], 56: ["gefrierender Niesel", "🌧️"], 57: ["gefrierender Niesel", "🌧️"], 61: ["leichter Regen", "🌦️"], 63: ["Regen", "🌧️"], 65: ["starker Regen", "🌧️"], 66: ["gefrierender Regen", "🌧️"], 67: ["gefrierender Regen", "🌧️"], 71: ["leichter Schneefall", "🌨️"], 73: ["Schneefall", "🌨️"], 75: ["starker Schneefall", "❄️"], 77: ["Schneegriesel", "🌨️"], 80: ["Regenschauer", "🌦️"], 81: ["kräftige Schauer", "🌧️"], 82: ["heftige Schauer", "⛈️"], 85: ["Schneeschauer", "🌨️"], 86: ["starke Schneeschauer", "❄️"], 95: ["Gewitter", "⛈️"], 96: ["Gewitter mit Hagel", "⛈️"], 99: ["schweres Gewitter mit Hagel", "⛈️"] };
const wmo = (c) => WMO[c] || ["wechselhaft", "🌡️"];
async function getJSON(url) {
  const r = await fetch(url, { signal: AbortSignal.timeout(9000) });
  if (!r.ok) throw new Error("Wetterdienst nicht erreichbar.");
  return r.json();
}
async function locate(city) {
  if (city) {
    const g = await getJSON(`https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(city)}&count=1&language=de&format=json`);
    const r = g.results?.[0];
    if (!r) throw Object.assign(new Error(`Ich finde keinen Ort namens „${city}“.`), { user: true });
    return { lat: r.latitude, lon: r.longitude, name: r.name };
  }
  // Standort des Geräts (fragt einmal um Erlaubnis)
  const pos = await new Promise((ok, no) => {
    if (!navigator.geolocation) return no(new Error("no-geo"));
    navigator.geolocation.getCurrentPosition(ok, no, { timeout: 8000, maximumAge: 30 * 60000 });
  }).catch(() => null);
  if (!pos) throw Object.assign(new Error("Für welchen Ort? Sag zum Beispiel „Wetter in Hamburg“ – oder „Ich wohne in Hamburg“, dann merke ich es mir."), { user: true });
  return { lat: pos.coords.latitude, lon: pos.coords.longitude, name: "" };
}
export async function weather({ city, day = 0 } = {}) {
  const place = await locate(city || profile().city);
  const w = await getJSON(`https://api.open-meteo.com/v1/forecast?latitude=${place.lat}&longitude=${place.lon}&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,relative_humidity_2m&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=3`);
  const d = Math.max(0, Math.min(2, day));
  const where = place.name ? `in ${place.name}` : "bei dir";
  const [txt, icon] = wmo(d === 0 ? w.current.weather_code : w.daily.weather_code[d]);
  const hi = Math.round(w.daily.temperature_2m_max[d]);
  const lo = Math.round(w.daily.temperature_2m_min[d]);
  const rain = w.daily.precipitation_probability_max[d] ?? 0;
  const tip = rain >= 60 ? " Nimm besser einen Schirm mit." : hi >= 26 ? " Denk an Sonnencreme." : hi <= 3 ? " Zieh dich warm an." : "";
  const text =
    d === 0
      ? `${cap(where)} sind es gerade ${Math.round(w.current.temperature_2m)} Grad, ${txt}. Heute ${lo} bis ${hi} Grad, Regenrisiko ${rain} Prozent.${tip}`
      : `${d === 1 ? "Morgen" : "Übermorgen"} ${where}: ${txt}, ${lo} bis ${hi} Grad, Regenrisiko ${rain} Prozent.${tip}`;
  const days = [0, 1, 2].map((i) => `<div><small>${i === 0 ? "Heute" : i === 1 ? "Morgen" : new Date(w.daily.time[i]).toLocaleDateString("de-DE", { weekday: "short" })}</small><span>${wmo(w.daily.weather_code[i])[1]}</span><b>${Math.round(w.daily.temperature_2m_max[i])}°</b><small>${Math.round(w.daily.temperature_2m_min[i])}° · ${w.daily.precipitation_probability_max[i] ?? 0} %</small></div>`).join("");
  const card = `<div class="wx"><div class="wx-now"><span class="wx-ic">${icon}</span><div><b>${Math.round(w.current.temperature_2m)}°</b><small>${esc(cap(txt))} · gefühlt ${Math.round(w.current.apparent_temperature)}° · Wind ${Math.round(w.current.wind_speed_10m)} km/h</small><small>${esc(place.name || "Dein Standort")}</small></div></div><div class="wx-days">${days}</div></div>`;
  return { text, card, data: { place: place.name, now: w.current.temperature_2m, code: w.current.weather_code, hi, lo, rain, day: d } };
}

// ---------- Uhrzeit & Datum ----------
export function timeInfo() {
  const d = new Date();
  return {
    time: d.toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" }),
    date: d.toLocaleDateString("de-DE", { weekday: "long", day: "numeric", month: "long", year: "numeric" }),
    iso: d.toISOString(),
  };
}

// ---------- Timer & Erinnerungen ----------
export const reminders = () => store.get("reminders", []);
export function addReminder(minutes, text) {
  const m = Math.max(0.1, Math.min(60 * 24 * 7, +minutes || 0));
  const r = { id: Math.random().toString(36).slice(2, 9), at: Date.now() + m * 60000, text: String(text || "Dein Timer ist abgelaufen").slice(0, 120) };
  store.set("reminders", [...reminders(), r].sort((a, b) => a.at - b.at));
  return r;
}
export const removeReminder = (id) => store.set("reminders", reminders().filter((r) => r.id !== id));
// Fällige Erinnerungen melden (App ruft das jede Sekunde auf)
export function dueReminders() {
  const now = Date.now();
  const due = reminders().filter((r) => r.at <= now);
  if (due.length) store.set("reminders", reminders().filter((r) => r.at > now));
  return due;
}
export function fmtIn(ms) {
  const m = Math.round(ms / 60000);
  if (m < 1) return "gleich";
  if (m < 60) return `in ${m} ${m === 1 ? "Minute" : "Minuten"}`;
  const h = Math.floor(m / 60);
  const r = m % 60;
  return `in ${h} ${h === 1 ? "Stunde" : "Stunden"}${r ? ` und ${r} Minuten` : ""}`;
}

// ---------- Ziel-Planer: „Mach mir 10k“ ----------
export const goal = () => store.get("goal", null);
export function planGoal({ target, monthly, months, start = 0 }) {
  target = Math.max(1, +target || 0);
  const saved = +start || goal()?.saved || 0;
  const left = Math.max(0, target - saved);
  const r = Math.pow(1.05, 1 / 12) - 1; // Szenario: 5 % pro Jahr, wenn angelegt
  const monthsFor = (m, rate) => {
    if (m <= 0) return Infinity;
    if (!rate) return Math.ceil(left / m);
    let v = saved;
    for (let i = 1; i <= 1200; i++) {
      v = v * (1 + rate) + m;
      if (v >= target) return i;
    }
    return Infinity;
  };
  const dur = (mo) => (mo === Infinity ? "sehr lange" : mo < 12 ? `${mo} ${mo === 1 ? "Monat" : "Monate"}` : `${n1(mo / 12)} Jahre`);
  const inDur = (mo) => (mo === Infinity ? "sehr langer Zeit" : mo < 12 ? `${mo} ${mo === 1 ? "Monat" : "Monaten"}` : `${n1(mo / 12)} Jahren`);
  let per = +monthly || 0;
  if (!per && months) per = Math.ceil(left / Math.max(1, months));
  const g = { target, monthly: per, saved, created: goal()?.created || Date.now() };
  store.set("goal", g);
  const opts = [50, 100, 200, 500].map((m) => ({ m, save: monthsFor(m, 0), invest: monthsFor(m, r) }));
  let text;
  if (per) {
    const a = monthsFor(per, 0);
    const b = monthsFor(per, r);
    text = `Dein Ziel: ${eur(target)}. Mit ${eur(per)} im Monat hast du es in ${inDur(a)} zusammengespart${b < a ? ` – angelegt mit etwa 5 Prozent im Jahr schon in ${inDur(b)}` : ""}. Ich merke mir das Ziel und zähle mit, wenn du sagst: „Ich habe 50 Euro gespart.“`;
  } else {
    text = `Für ${eur(target)} gilt: Mit 100 Euro im Monat brauchst du ${dur(opts[1].save)}, mit 200 Euro ${dur(opts[2].save)}, mit 500 Euro ${dur(opts[3].save)}. Sag mir, wie viel du im Monat schaffst – dann mache ich dir einen festen Plan.`;
  }
  text += " Ehrlich gesagt: Geld „machen“ kann ich nicht – aber mit einem Plan erreichst du es sicher.";
  const card = `<div class="goal"><div class="goal-top"><b>🎯 ${eur(target)}</b><small>${saved ? `schon ${eur(saved)} gespart` : "neues Ziel"}</small></div><div class="goal-bar"><i style="width:${Math.min(100, (saved / target) * 100).toFixed(1)}%"></i></div>
    <table><tr><th>pro Monat</th><th>nur sparen</th><th>angelegt (5 %)*</th></tr>${opts.map((o) => `<tr class="${o.m === per ? "on" : ""}"><td>${eur(o.m)}</td><td>${dur(o.save)}</td><td>${dur(o.invest)}</td></tr>`).join("")}</table>
    <small class="muted">* Szenario, keine Garantie – Anlagen können schwanken. Keine Anlageberatung.</small></div>`;
  return { text, card, data: { target, monthly: per, saved, monthsSaving: per ? monthsFor(per, 0) : null, options: opts } };
}
export function addSaved(amount) {
  const g = goal();
  if (!g) return null;
  g.saved = Math.max(0, g.saved + (+amount || 0));
  store.set("goal", g);
  const pct = Math.min(100, (g.saved / g.target) * 100);
  return { text: g.saved >= g.target ? `Geschafft! Du hast dein Ziel von ${eur(g.target)} erreicht. Stark!` : `Notiert: Jetzt hast du ${eur(g.saved)} von ${eur(g.target)} – ${n1(pct)} Prozent. Weiter so!`, done: g.saved >= g.target };
}

// ---------- Rechner (ohne eval) ----------
export function calc(input) {
  let s = String(input)
    .toLowerCase()
    .replace(/(\d+(?:[.,]\d+)?)\s*(?:%|prozent)\s*von\s*(\d+(?:[.,]\d+)?)/g, "($1/100*$2)")
    .replace(/wurzel\s*(?:aus|von)?\s*(\d+(?:[.,]\d+)?)/g, "sqrt($1)")
    .replace(/\bplus\b|und\b/g, "+")
    .replace(/\bminus\b|weniger\b/g, "-")
    .replace(/\bmal\b|×|x(?=\s*\d)/g, "*")
    .replace(/geteilt\s*durch|durch|÷|:/g, "/")
    .replace(/hoch/g, "^")
    .replace(/(\d)\.(\d{3})(?!\d)/g, "$1$2") // 1.000 → 1000
    .replace(/,/g, ".")
    .replace(/[^0-9.+\-*/^()sqrt ]/g, " ");
  const tok = s.match(/sqrt|\d+(?:\.\d+)?|[+\-*/^()]/g);
  if (!tok || !tok.some((t) => /\d/.test(t)) || !tok.some((t) => /[+\-*/^]|sqrt/.test(t))) return null;
  let i = 0;
  const peek = () => tok[i];
  const expr = () => {
    let v = term();
    while (peek() === "+" || peek() === "-") v = tok[i++] === "+" ? v + term() : v - term();
    return v;
  };
  const term = () => {
    let v = power();
    while (peek() === "*" || peek() === "/") v = tok[i++] === "*" ? v * power() : v / power();
    return v;
  };
  const power = () => {
    const b = unary();
    if (peek() === "^") {
      i++;
      return Math.pow(b, power());
    }
    return b;
  };
  const unary = () => {
    if (peek() === "-") return i++, -unary();
    if (peek() === "sqrt") return i++, Math.sqrt(unary());
    if (peek() === "(") {
      i++;
      const v = expr();
      if (peek() === ")") i++;
      return v;
    }
    const t = tok[i++];
    if (t == null || !/\d/.test(t)) throw new Error("x");
    return parseFloat(t);
  };
  try {
    const v = expr();
    if (i !== tok.length || !Number.isFinite(v)) return null;
    return Math.round(v * 1e8) / 1e8;
  } catch (_) {
    return null;
  }
}

// ---------- Beträge aus Sprache: „10k“, „zehntausend“, „1.500 Euro“ ----------
const WORDS = { eins: 1, ein: 1, eine: 1, zwei: 2, drei: 3, vier: 4, fünf: 5, sechs: 6, sieben: 7, acht: 8, neun: 9, zehn: 10, zwanzig: 20, dreißig: 30, fünfzig: 50, hundert: 100 };
export function amount(t) {
  t = String(t).toLowerCase();
  let m = t.match(/(\d+(?:[.,]\d+)?)\s*(k|tsd|tausend)\b/);
  if (m) return parseFloat(m[1].replace(",", ".")) * 1000;
  m = t.match(/(\d+(?:[.,]\d+)?)\s*(mio|million(en)?)\b/);
  if (m) return parseFloat(m[1].replace(",", ".")) * 1e6;
  m = t.match(/\b(eine?|zwei|drei|vier|fünf|sechs|sieben|acht|neun|zehn|zwanzig|fünfzig|hundert)\s*(tausend|million(en)?)\b/);
  if (m) return WORDS[m[1]] * (m[2].startsWith("tausend") ? 1000 : 1e6);
  m = t.match(/(\d{1,3}(?:\.\d{3})+|\d+)(?:,\d+)?\s*(€|euro)?/);
  if (m) return parseFloat(m[1].replace(/\./g, ""));
  return null;
}
