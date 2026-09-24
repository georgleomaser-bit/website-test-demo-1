// Jarvis: der Sprachmodus von AKYTEX AI (Tarif Ultra) – im Stil eines modernen Sprachassistenten.
// Leuchtende, atmende Bildschirmränder, unten eine gläserne Leiste mit schillernder Kugel, darüber
// Antwortkarten. Zuhören mit Pausen-Toleranz, Männerstimme, Untertitel, „mehr“ für ausführliche
// Antworten und Vorschläge per Tipp oder „Ja“. Geld bewegt Jarvis nie per Sprache.
const $ = (s, r = document) => r.querySelector(s);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
const IOS = /iP(hone|ad|od)/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
const REDUCED = matchMedia("(prefers-reduced-motion: reduce)").matches;
// Safari (auch als installierte App): Mikrofon nur direkt nach einem Tipp – dort sofort zuhören statt erst zu begrüßen
const SAFARI = IOS || (/safari/i.test(navigator.userAgent) && !/(chrome|chromium|crios|fxios|edg|android)/i.test(navigator.userAgent));
const VOICE_KEY = "akytex-jarvis-voice";
const TRIAL_KEY = "akytex-jarvis-trial";
const TITLE_KEY = "akytex-jarvis-title";
export const TRIAL_TURNS = 3;

const J = { deps: null, on: false, state: "off", rec: null, lvl: 0, kick: 0, raf: 0, mic: null, an: null, ctx: null, buf: null, silent: 0, pending: null, rest: "", greeted: false, idleTimer: 0, sayTimer: 0, endTimer: 0, muted: false, thinkGlow: false };

// Jarvis läuft überall: mit Spracherkennung per Stimme, sonst per Schreiben/Diktieren über die Tastatur
export const jarvisSupported = () => true;
export function trialLeft() {
  try {
    return Math.max(0, TRIAL_TURNS - (+localStorage.getItem(TRIAL_KEY) || 0));
  } catch (_) {
    return 0;
  }
}
function useTrial() {
  try {
    localStorage.setItem(TRIAL_KEY, String(TRIAL_TURNS - trialLeft() + 1));
  } catch (_) {
    /* ohne Speicher keine Zählung */
  }
}
// Anrede: Standard „Master“, änderbar per Sprache („Nenn mich Leo“)
export function jarvisTitle() {
  try {
    return localStorage.getItem(TITLE_KEY) || "Master";
  } catch (_) {
    return "Master";
  }
}
function setTitle(t) {
  try {
    localStorage.setItem(TITLE_KEY, t);
  } catch (_) {
    /* gilt dann nur für diese Sitzung */
  }
}

// ---------- Emotionen: Grundstimmung und Reaktionen – frei wählbar ----------
const MOOD_KEY = "akytex-jarvis-mood";
const REACT_KEY = "akytex-jarvis-react";
const MEM_KEY = "akytex-jarvis-memory";
// rgb: Farbe von Kugel und HUD · rate/pitch: Stimme · pace: Bewegung der Kugel · tone: Anweisung fürs Sprachmodell
export const MOODS = {
  jarvis: { label: "Klassisch", icon: "🎩", rgb: [255, 176, 72], rate: 1, pitch: 0, pace: 1, tone: "souverän und höflich wie ein britischer Butler, mit trockenem Humor", sample: "Sehr wohl. Klassisch, souverän, zu Diensten." },
  ruhig: { label: "Ruhig", icon: "🌊", rgb: [70, 186, 255], rate: 0.93, pitch: -0.04, pace: 0.55, tone: "ruhig, gelassen und beruhigend, ohne Hektik – auch wenn der Markt wackelt", sample: "Ganz ruhig. Ich bin entspannt für dich da." },
  motiviert: { label: "Motiviert", icon: "🔥", rgb: [255, 98, 44], rate: 1.1, pitch: 0.05, pace: 1.7, tone: "energisch und motivierend wie ein Coach, voller Tatendrang, aber diszipliniert", sample: "Los geht's! Volle Energie, wir holen das Maximum raus!" },
  herzlich: { label: "Herzlich", icon: "💛", rgb: [255, 128, 168], rate: 1, pitch: 0.03, pace: 0.85, tone: "herzlich, warm und ermutigend – du freust dich ehrlich mit dem Nutzer", sample: "Schön, dass du da bist. Ich kümmere mich gern um dich." },
  witzig: { label: "Witzig", icon: "😎", rgb: [176, 112, 255], rate: 1.04, pitch: 0.02, pace: 1.25, tone: "locker und witzig mit kurzen, charmanten Sprüchen – in der Sache aber präzise", sample: "Witzig-Modus an. Keine Sorge, die Zahlen nehme ich trotzdem ernst." },
  ernst: { label: "Fokus", icon: "🎯", rgb: [150, 220, 255], rate: 0.98, pitch: -0.03, pace: 0.8, tone: "sachlich, knapp und fokussiert, ohne Floskeln und ohne Witze", sample: "Fokus-Modus. Nur Fakten, keine Floskeln." },
};
export const REACTIONS = {
  joy: { label: "Freude", icon: "🎉", desc: "bei Gewinnen" },
  worry: { label: "Sorge", icon: "🫣", desc: "bei Verlusten und Risiken" },
  hype: { label: "Begeisterung", icon: "⚡", desc: "bei starken Signalen" },
  humor: { label: "Humor", icon: "😄", desc: "kleine Sprüche" },
};
const load = (k, d) => {
  try {
    const v = localStorage.getItem(k);
    return v == null ? d : JSON.parse(v);
  } catch (_) {
    return d;
  }
};
const keep = (k, v) => {
  try {
    localStorage.setItem(k, JSON.stringify(v));
  } catch (_) {
    /* nur für diese Sitzung */
  }
};
export const moodSetting = () => {
  const m = load(MOOD_KEY, "auto");
  return m === "auto" || MOODS[m] ? m : "auto";
};
// „Auto“: Jarvis passt seine Stimmung an Tageszeit, Depot und Markt an
function autoMood() {
  const h = new Date().getHours();
  const c = J.deps?.moodHint?.() || {};
  if (h >= 22 || h < 6) return "ruhig";
  if (c.day <= -1.5) return "ernst";
  if (c.day >= 1.5 || c.market >= 1) return "motiviert";
  return "jarvis";
}
export function jarvisMood() {
  const set = moodSetting();
  const key = set === "auto" ? autoMood() : set;
  return { key, auto: set === "auto", ...MOODS[key] };
}
function setMood(k) {
  keep(MOOD_KEY, k);
  updateMoodBox();
  updateHud();
}
export const reactions = () => ({ joy: true, worry: true, hype: true, humor: true, ...load(REACT_KEY, {}) });
function setReactions(r) {
  keep(REACT_KEY, r);
  updateMoodBox();
}
export const jarvisMemory = () => (Array.isArray(load(MEM_KEY, [])) ? load(MEM_KEY, []) : []).slice(-30);
// Für das Sprachmodell: Tonfall, erlaubte Emotionen und was Jarvis sich gemerkt hat
export function jarvisPersona() {
  const m = jarvisMood();
  const r = reactions();
  const shown = Object.entries(REACTIONS)
    .filter(([k]) => r[k] && k !== "humor")
    .map(([, v]) => `${v.label} ${v.desc}`);
  const mem = jarvisMemory();
  return `Tonfall: ${m.tone}. ${shown.length ? `Zeige passende Gefühle: ${shown.join(", ")}.` : "Bleib emotional neutral."}${r.humor && m.key !== "ernst" ? "" : " Keine Witze."}${mem.length ? ` Das hat dir der Nutzer anvertraut (nutze es, wenn es passt): ${mem.map((x) => `„${x.t}“`).join("; ")}.` : ""}`;
}
// Ich-Form in Du-Form, damit Jarvis Gemerktes natürlich wiedergibt („ich mag Tesla“ → „du magst Tesla“)
const PRON = { ich: "du", mich: "dich", mir: "dir", mein: "dein", meine: "deine", meinen: "deinen", meinem: "deinem", meiner: "deiner", meines: "deines" };
const VERB = { bin: "bist", habe: "hast", hab: "hast", mag: "magst", kann: "kannst", will: "willst", muss: "musst", darf: "darfst", soll: "sollst", möchte: "möchtest", weiß: "weißt", werde: "wirst", hätte: "hättest", wäre: "wärst" };
const NOT_VERB = /^(k?eine|gerne?|heute|morgen|immer|lieber|diese|jede|alle|welche|seine|ihre|unsere|deine|meine|viele|wenige|ganze|große|kleine|nie|ohne|halbe|ganze)$/i;
function toYou(t) {
  const w = t.split(/\s+/);
  const hasIch = w.some((x) => x.toLowerCase() === "ich");
  return w
    .map((x, i) => {
      const lw = x.toLowerCase();
      if (PRON[lw]) return PRON[lw];
      if (!hasIch) return x;
      if (VERB[lw]) return VERB[lw];
      // regelmäßige Verben direkt nach „ich“ oder am Satzende („… Tesla kaufe“): -e → -st
      const verbSpot = (i > 0 && w[i - 1].toLowerCase() === "ich") || i === w.length - 1;
      if (!verbSpot || !/^[a-zäöüß]{3,}e$/.test(x) || /(che|ie)$/.test(x) || NOT_VERB.test(x)) return x;
      if (/[^aeiouäöü]le$/.test(x)) return x.slice(0, -2) + "elst"; // handle → handelst
      return x.slice(0, -1) + (/[dt]e$/.test(x) ? "est" : "st");
      return x;
    })
    .join(" ");
}
const pick = (a) => a[Math.floor(Math.random() * a.length)];
const FILLERS = {
  jarvis: ["Einen Moment, ich prüfe das.", "Sehr wohl – ich rechne kurz nach.", "Ich sehe mir die Zahlen an."],
  ruhig: ["Ganz in Ruhe – ich schaue nach.", "Einen Augenblick."],
  motiviert: ["Sekunde, ich hol dir die Zahlen!", "Bin dran!"],
  herzlich: ["Gern, ich schaue kurz für dich nach.", "Einen Moment, ich kümmere mich darum."],
  witzig: ["Moment, meine Schaltkreise glühen kurz.", "Ich frag kurz die Glaskugel … Spaß, ich rechne."],
  ernst: ["Analyse läuft.", "Prüfe."],
};
const OPENERS = {
  joy: { jarvis: ["Ausgezeichnet."], ruhig: ["Schön."], motiviert: ["Stark!", "Ja, so läuft das!"], herzlich: ["Oh, das freut mich!"], witzig: ["Na bitte, läuft bei dir!"], ernst: [] },
  worry: { jarvis: ["Hm, Vorsicht."], ruhig: ["Kein Grund zur Panik."], motiviert: ["Kopf hoch, das drehen wir."], herzlich: ["Keine Sorge, ich bin bei dir."], witzig: ["Autsch. Aber wir bleiben cool."], ernst: ["Achtung."] },
  hype: { jarvis: ["Interessant."], ruhig: ["Das ist spannend."], motiviert: ["Jetzt wird's spannend!"], herzlich: ["Oh, schau mal!"], witzig: ["Ui, da ist Musik drin!"], ernst: ["Relevantes Signal."] },
};
const QUIPS = ["Und nein, ich kann keine Lottozahlen vorhersagen.", "Das Depot und ich sind übrigens beste Freunde.", "Ich hätte Kaffee angeboten, aber ich bin eine KI.", "Das war jetzt schneller als jeder Börsenbrief."];
// Grobe Stimmung einer Antwort: grüne/rote Zahlen und Signalwörter
function feeling(html) {
  const s = String(html);
  if (/(kaufsignal|top-setup|starkes signal|ausbruch|breakout|beste chance)/i.test(s)) return "hype";
  const up = (s.match(/class="[^"]*\bup\b/g) || []).length + (s.match(/(gewinn|im plus|gestiegen|zugelegt|rekord)/gi) || []).length;
  const down = (s.match(/class="[^"]*\bdown\b/g) || []).length + (s.match(/(verlust|im minus|gefallen|eingebrochen|warnung|vorsicht)/gi) || []).length;
  if (up >= down + 2) return "joy";
  if (down >= up + 2) return "worry";
  return null;
}
const FLASH = { joy: [110, 255, 150], worry: [255, 70, 55], hype: [255, 236, 140] };
function emote(kind) {
  if (!FLASH[kind]) return;
  J.flash = { rgb: FLASH[kind], at: performance.now(), dur: kind === "worry" ? 2200 : 1600 };
  if (kind !== "worry") J.burst = 1;
  J.kick = 1;
  J.voiceMod = kind === "joy" || kind === "hype" ? { rate: 1.04, pitch: 0.04 } : { rate: 0.95, pitch: -0.04 };
}

// ---------- Stimme: bevorzugt eine deutsche Männerstimme ----------
const MALE = /(markus|yannick|martin|viktor|conrad|killian|florian|bernd|christoph|kasper|ralf|klaus|jonas|stefan|hans|eddy|reed|rocko|grandpa|opa|male|mann|männlich|x-deg|-deg-)/i;
const FEMALE = /(anna|helena|petra|katja|amala|seraphina|katharina|marlene|vicki|hedda|elke|louisa|tanja|gisela|female|frau|x-deb|x-dea|x-nfh)/i;
let bestVoice = null;
const germanVoices = () => ("speechSynthesis" in window ? speechSynthesis.getVoices().filter((v) => /^de([-_]|$)/i.test(v.lang)) : []);
export const hasMaleVoice = () => germanVoices().some((v) => MALE.test(v.name));
export function pickVoice() {
  if (!("speechSynthesis" in window)) return null;
  const vs = germanVoices();
  let saved = "";
  try {
    saved = localStorage.getItem(VOICE_KEY) || "";
  } catch (_) {
    /* ohne Speicher */
  }
  if (saved && vs.some((v) => v.name === saved)) return (bestVoice = vs.find((v) => v.name === saved));
  const score = (v) => (MALE.test(v.name) ? 8 : 0) - (FEMALE.test(v.name) ? 4 : 0) + (/(premium|enhanced|neural|natural|online)/i.test(v.name) ? 3 : 0) + (v.localService ? 0 : 1);
  bestVoice = vs.sort((a, b) => score(b) - score(a))[0] || null;
  return bestVoice;
}
const isMale = (v) => !!v && MALE.test(v.name);
// Stimme wechseln: geht der Reihe nach durch alle deutschen Stimmen des Geräts (Männerstimmen zuerst)
function cycleVoice() {
  const vs = germanVoices().sort((a, b) => MALE.test(b.name) - MALE.test(a.name) || a.name.localeCompare(b.name));
  if (!vs.length) return J.deps.toast("Auf diesem Gerät ist keine deutsche Stimme installiert.", "info", "🗣 Stimme");
  const i = (vs.findIndex((v) => v.name === (bestVoice || {}).name) + 1) % vs.length;
  bestVoice = vs[i];
  try {
    localStorage.setItem(VOICE_KEY, bestVoice.name);
  } catch (_) {
    /* nur für diese Sitzung */
  }
  speakOut(`So klinge ich als ${bestVoice.name.split(/[ (]/)[0]}.`).then(() => J.on && !J.typing && !J.rec && listen());
}
// Hinweis, wie man eine Männerstimme installiert (Browser können nur Stimmen des Geräts nutzen)
function maleHint() {
  if (hasMaleVoice()) return "";
  const ua = navigator.userAgent;
  if (IOS) return "Für eine Männerstimme: iPhone-Einstellungen → Bedienungshilfen → Gesprochene Inhalte → Stimmen → Deutsch → „Yannick“ oder „Martin“ laden. Danach wählt Jarvis sie automatisch.";
  if (/Mac/.test(ua)) return "Für eine Männerstimme: Systemeinstellungen → Bedienungshilfen → Gesprochene Inhalte → Systemstimme → Stimme verwalten → Deutsch → „Yannick“ oder „Martin“ laden.";
  if (/Android/.test(ua)) return "Für eine Männerstimme: Einstellungen → Bedienungshilfen → Text-in-Sprache → Google-Sprachausgabe → Deutsch → eine männliche Stimme wählen.";
  if (/Windows/.test(ua)) return "Für eine Männerstimme: Microsoft Edge nutzen (dort gibt es „Conrad“ und „Killian“) oder in Windows unter Zeit und Sprache → Sprachausgabe die Stimme „Stefan“ installieren.";
  return "";
}
if ("speechSynthesis" in window) {
  pickVoice();
  speechSynthesis.addEventListener?.("voiceschanged", pickVoice);
}
// HTML-Antwort in sprechbaren Text verwandeln und in Häppchen teilen (Rest per „mehr“)
export function toSpeech(html, max = 700) {
  const text = String(html)
    .replace(/<\/(li|p|h\d)>/g, ". ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&[a-z]+;/g, " ")
    .replace(/\p{Extended_Pictographic}|️/gu, "")
    .replace(/\s*·\s*/g, ", ")
    .replace(/\s+/g, " ")
    .replace(/\s+([.,!?:;])/g, "$1")
    .replace(/([.!?:])(\s*\.)+/g, "$1")
    .replace(/\.{2,}/g, ".")
    .replace(/^[.\s]+/, "")
    .trim();
  const sentences = text.match(/[^.!?]+[.!?]+|[^.!?]+$/g) || [text];
  let out = "";
  let i = 0;
  for (; i < sentences.length; i++) {
    if (out && (out + sentences[i]).length > max) break;
    out += sentences[i];
  }
  return { text: out.trim(), rest: sentences.slice(i).join("").trim(), cut: i < sentences.length };
}
// Füllwörter und Anrede am Anfang weglassen, damit Befehle sicher erkannt werden
export function cleanUtterance(t) {
  return String(t)
    .replace(/^\s*(hey|hi|okay|ok|hallo)?\s*(jarvis|akytex)[,!.]?\s*/i, "")
    .replace(/(?<![\p{L}])(äh+m?|ähm|öhm|hm+|sag mal|mal eben|kannst du( mir)?( bitte)?|könntest du( mir)?( bitte)?|würdest du( bitte)?|bitte)(?![\p{L}])/giu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

// ---------- Oberfläche: HUD wie im Film ----------
function build() {
  const el = document.createElement("div");
  el.className = "jv";
  el.id = "jv";
  el.hidden = true;
  el.innerHTML = `<div class="jv-edge" aria-hidden="true"></div><div class="jv-edge jv-soft" aria-hidden="true"></div><div class="jv-edge jv-wide" aria-hidden="true"></div>
    <div class="jv-hud" aria-hidden="true">
      <i class="jv-fr tl"></i><i class="jv-fr tr"></i><i class="jv-fr bl"></i><i class="jv-fr br"></i>
      <div class="jv-top"><span class="jv-brand">J.A.R.V.I.S. <em>· AKYTEX</em></span><span class="jv-meter">${"<i></i>".repeat(24)}</span><span class="jv-clock" data-hud="clock"></span></div>
      <div class="jv-side jv-left"><p>DEPOT<b data-hud="depot">–</b></p><p>MARKT<b data-hud="market">–</b></p><p>MODUS<b data-hud="mode">–</b></p><p>TRADER-DNA<b data-hud="dna">–</b></p></div>
      <div class="jv-side jv-right"><p>STIMME<b data-hud="voice">–</b></p><p>EMOTION<b data-hud="mood">–</b></p><p>ANREDE<b data-hud="title">–</b></p><p>STATUS<b data-hud="state">ONLINE</b></p></div>
      <i class="jv-reticle"></i>
    </div>
    <div class="jv-stage" role="dialog" aria-label="Jarvis – Sprachmodus">
      <div class="jv-core"><canvas class="jv-orb" aria-hidden="true"></canvas></div>
      <div class="jv-txt"><span class="jv-state" aria-live="polite">HÖRE ZU</span><span class="jv-you"></span></div>
      <p class="jv-say" aria-live="polite"></p>
      <div class="jv-acts"></div>
    </div>
    <div class="jv-moodbox" hidden role="dialog" aria-label="Emotionen von Jarvis">
      <p class="jv-mb-h">STIMMUNG</p><div class="jv-mb-row" data-mb="mood"></div>
      <p class="jv-mb-h">EMOTIONEN ZEIGEN</p><div class="jv-mb-row" data-mb="react"></div>
    </div>
    <p class="jv-keys" aria-hidden="true">LEERTASTE · SPRECHEN &nbsp; ESC · BEENDEN &nbsp; ALT+J · JARVIS</p>
    <div class="jv-controls">
      <form class="jv-type" hidden><input type="text" enterkeyhint="send" autocomplete="off" placeholder="Frag Jarvis … (🎤 auf der Tastatur zum Diktieren)" aria-label="Frage an Jarvis" /></form>
      <button class="jv-btn" data-jv="mood" title="Emotionen wählen" aria-label="Emotionen wählen">🎭</button>
      <button class="jv-btn" data-jv="voice" title="Stimme wechseln" aria-label="Stimme wechseln">🗣</button>
      <button class="jv-btn jv-micbtn" data-jv="mic" title="Mikrofon an/aus" aria-label="Mikrofon an oder aus">🎙</button>
      <button class="jv-btn" data-jv="chat" title="Im Chat weiterlesen" aria-label="Chat öffnen">💬</button>
      <button class="jv-btn jv-end" data-jv="close" title="Jarvis beenden (Esc)" aria-label="Jarvis beenden">✕</button>
    </div>`;
  document.body.appendChild(el);
  el.addEventListener("click", onClick);
  el.querySelector(".jv-type").addEventListener("submit", (e) => {
    e.preventDefault();
    const inp = e.target.querySelector("input");
    const text = cleanUtterance(inp.value);
    inp.value = "";
    if (text) handle(text);
  });
  return el;
}
const root = () => $("#jv") || build();
const LABELS = { listen: "HÖRE ZU", think: "ANALYSIERE", speak: "JARVIS", idle: "TIPPE AUF DEN KERN UND SPRICH", muted: "MIKROFON AUS", upsell: "JARVIS", type: "SCHREIB ODER DIKTIERE" };
function setState(s, label) {
  J.state = s;
  const el = root();
  el.dataset.state = s;
  el.querySelector(".jv-state").textContent = label ? label.toUpperCase() : LABELS[s] || "";
  const st = el.querySelector('[data-hud="state"]');
  if (st) st.textContent = { listen: "HÖRT", think: "RECHNET", speak: "SPRICHT", idle: "BEREIT", type: "TEXT", muted: "STUMM" }[s] || "ONLINE";
}
// HUD-Anzeigen: Uhr, Depot, Markt, Modus – einmal pro Sekunde
function updateHud() {
  const el = root();
  const set = (k, v) => {
    const n = el.querySelector(`[data-hud="${k}"]`);
    if (n && n.textContent !== v) n.textContent = v;
  };
  set("clock", new Date().toLocaleTimeString("de-DE"));
  const h = J.deps?.hud?.() || {};
  set("depot", h.depot || "–");
  set("market", h.market || "–");
  set("mode", h.mode || "BEREIT");
  set("dna", h.dna || "LERNT");
  set("voice", ((bestVoice || pickVoice())?.name || "System").split(/[ (]/)[0].toUpperCase());
  set("title", jarvisTitle().toUpperCase());
  const m = jarvisMood();
  set("mood", J.tintLabel || (m.auto ? "AUTO · " : "") + m.label.toUpperCase());
}
// Auswahl der Emotionen: Grundstimmung (eine) und Reaktionen (beliebig viele)
function updateMoodBox() {
  const box = $("#jv")?.querySelector(".jv-moodbox");
  if (!box) return;
  const cur = moodSetting();
  const r = reactions();
  box.querySelector('[data-mb="mood"]').innerHTML =
    `<button class="jv-mchip ${cur === "auto" ? "on" : ""}" data-mood="auto" style="--mc:255,210,140"><i>✨</i>Auto</button>` +
    Object.entries(MOODS)
      .map(([k, m]) => `<button class="jv-mchip ${cur === k ? "on" : ""}" data-mood="${k}" style="--mc:${m.rgb.join(",")}"><i>${m.icon}</i>${m.label}</button>`)
      .join("");
  box.querySelector('[data-mb="react"]').innerHTML = Object.entries(REACTIONS)
    .map(([k, v]) => `<button class="jv-mchip ${r[k] ? "on" : ""}" data-react="${k}" aria-pressed="${!!r[k]}" title="${v.label} ${v.desc}"><i>${v.icon}</i>${v.label}</button>`)
    .join("");
}
function toggleMoodBox(show) {
  const box = root().querySelector(".jv-moodbox");
  const on = show ?? box.hidden;
  box.hidden = !on;
  root().querySelector('[data-jv="mood"]').classList.toggle("on", on);
  if (on) updateMoodBox();
}
// Neue Stimmung vorführen: Farbe, Tempo und Stimme wechseln sofort
async function previewMood(k) {
  setMood(k);
  const m = jarvisMood();
  J.kick = 1;
  J.burst = 0.8;
  await speakOut(k === "auto" ? `Auto-Modus. Ich passe meine Stimmung an Markt, Depot und Tageszeit an. Gerade bin ich ${m.label.toLowerCase()}.` : m.sample);
  if (J.on && !J.typing && !J.rec) listen();
}
// Leiser Ton wie bei einem Assistenten: hoch = ich höre, runter = verstanden
function chime(up) {
  if (IOS || !J.ac) return;
  try {
    const c = J.ac;
    const t = c.currentTime;
    const o = c.createOscillator();
    const g = c.createGain();
    o.type = "sine";
    o.frequency.setValueAtTime(up ? 520 : 820, t);
    o.frequency.exponentialRampToValueAtTime(up ? 880 : 460, t + 0.14);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.05, t + 0.02);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.2);
    o.connect(g).connect(c.destination);
    o.start(t);
    o.stop(t + 0.22);
  } catch (_) {
    /* ohne Web Audio kein Ton */
  }
}
// Sprachausgabe im Moment eines Tipps freischalten (iOS/Safari sprechen sonst später nicht)
function unlockVoice() {
  try {
    const u = new SpeechSynthesisUtterance(" ");
    u.volume = 0;
    speechSynthesis.speak(u);
  } catch (_) {
    /* ohne Sprachausgabe */
  }
}
// iOS/Safari: zum Sprechen den Lautsprecher nutzen (sonst landet die Stimme nach dem Zuhören leise im Hörer),
// fürs Zuhören wieder dem Browser die Wahl lassen
function audioMode(type) {
  try {
    if (navigator.audioSession && navigator.audioSession.type !== type) navigator.audioSession.type = type;
  } catch (_) {
    /* ältere Browser */
  }
}
function stopRec() {
  const r = J.rec;
  if (!r) return;
  J.rec = null;
  clearTimeout(J.endTimer);
  try {
    r.abort();
  } catch (_) {
    /* schon beendet */
  }
}
function onClick(e) {
  if (!J.voiceOk) unlockVoice();
  const b = e.target.closest("[data-jv], [data-jv-act]");
  if (b?.dataset.jv === "close") return stopJarvis();
  if (b?.dataset.jv === "chat") {
    stopJarvis();
    return J.deps.openChat();
  }
  if (b?.dataset.jv === "plans") {
    stopJarvis();
    return J.deps.upsell();
  }
  if (b?.dataset.jv === "mic") return toggleMute();
  if (b?.dataset.jv === "voice") return cycleVoice();
  if (b?.dataset.jv === "mood") return toggleMoodBox();
  const mc = e.target.closest("[data-mood], [data-react]");
  if (mc?.dataset.mood) return previewMood(mc.dataset.mood);
  if (mc?.dataset.react) {
    const r = reactions();
    r[mc.dataset.react] = !r[mc.dataset.react];
    setReactions(r);
    if (r[mc.dataset.react] && FLASH[mc.dataset.react]) emote(mc.dataset.react);
    return;
  }
  if (b?.dataset.jvAct != null) {
    const a = J.actions?.[+b.dataset.jvAct];
    if (a) J.deps.runAction(a, b);
    return;
  }
  // Kern oder Text antippen: unterbrechen und zuhören
  if (e.target.closest(".jv-core, .jv-txt, .jv-say") && ["speak", "idle"].includes(J.state)) {
    // Sprechen beenden (die laufende Antwort gilt als fertig) und sofort zuhören – noch im Tipp
    J.speakToken = (J.speakToken || 0) + 1;
    speechSynthesis?.cancel();
    listen(true);
    J.finishSpeak?.();
  }
}
// Schreib-/Diktiermodus: ohne Spracherkennung (Firefox, In-App-Browser) oder bei stummem Mikro
function typeMode(on) {
  J.typing = on;
  const f = root().querySelector(".jv-type");
  f.hidden = !on;
  root().classList.toggle("typing", on);
  if (on) {
    setState("type");
    setTimeout(() => f.querySelector("input").focus(), 80);
  }
}
function toggleMute() {
  if (!SR) return typeMode(true);
  J.muted = !J.muted;
  root().querySelector(".jv-micbtn").classList.toggle("off", J.muted);
  if (J.muted) {
    try {
      J.rec?.abort();
    } catch (_) {
      /* schon aus */
    }
    J.rec = null;
    typeMode(true);
  } else {
    typeMode(false);
    listen();
  }
}
const showYou = (t) => (root().querySelector(".jv-you").textContent = t ? `„${t}“` : "");
function showSay(text) {
  const box = root().querySelector(".jv-say");
  let pos = 0;
  box.innerHTML = text
    .split(/(\s+)/)
    .map((w) => {
      if (!w.trim()) return w;
      const at = text.indexOf(w, pos);
      pos = at + w.length;
      return `<span data-i="${at}">${esc(w)}</span>`;
    })
    .join("");
  root().classList.toggle("has-card", !!text);
}
function revealTo(ci) {
  root()
    .querySelectorAll(".jv-say span:not(.on)")
    .forEach((sp) => +sp.dataset.i <= ci && sp.classList.add("on"));
}
function showActions(actions) {
  J.actions = actions || [];
  root().querySelector(".jv-acts").innerHTML = J.actions
    .slice(0, 3)
    .map((a, i) => `<button class="jv-chip ${a.primary ? "primary" : ""}" data-jv-act="${i}">${esc(a.label)}</button>`)
    .join("");
}

// ---------- Der Kern: goldene Partikel-Kugel in 3D (Canvas, 60 fps) ----------
const MOBILE = matchMedia("(max-width: 700px)").matches;
const N = MOBILE ? 700 : 1100;
const GOLD = Math.PI * (3 - Math.sqrt(5));
// Partikel einmal erzeugen: Hülle (Fibonacci-Kugel), leuchtende Bänder, innere Wirbel und Umlaufbahnen
const BANDS = [
  [0.5, 0.2],
  [-0.6, 1.1],
  [1.2, 2.2],
  [0.15, 2.9],
  [-1.1, 0.6],
];
const PTS = Array.from({ length: N }, (_, i) => {
  const m = i % 20;
  const kind = m < 9 ? 0 : m < 15 ? 3 : m < 18 ? 1 : 2;
  const seed = (i * 12.9898) % 6.283;
  let x;
  let y;
  let z;
  if (kind === 3) {
    // Punkt auf einem geneigten Großkreis (wie die Bögen im Film)
    const [tx, ty] = BANDS[i % BANDS.length];
    const a = (i * 0.61803) % 6.283;
    const j = 0.04 * Math.sin(i * 7.1);
    const x0 = Math.cos(a);
    const z0 = Math.sin(a);
    const y1 = j * Math.cos(tx) - z0 * Math.sin(tx);
    const z1 = j * Math.sin(tx) + z0 * Math.cos(tx);
    x = x0 * Math.cos(ty) + z1 * Math.sin(ty);
    z = -x0 * Math.sin(ty) + z1 * Math.cos(ty);
    y = y1;
  } else {
    y = 1 - (2 * (i + 0.5)) / N;
    const r = Math.sqrt(1 - y * y);
    const ph = i * GOLD;
    x = Math.cos(ph) * r;
    z = Math.sin(ph) * r;
  }
  return { kind, x, y, z, rad: kind === 0 ? 0.9 + ((i * 37) % 19) / 100 : kind === 3 ? 0.97 + ((i * 11) % 9) / 100 : kind === 1 ? 0.2 + ((i * 53) % 50) / 100 : 1.12 + ((i * 29) % 30) / 100, seed, sp: 0.3 + ((i * 7) % 10) / 12 };
});
// Leuchtpunkte in festen Größen vorrendern – ohne Skalierung zeichnet der Browser sie am schnellsten.
// Farbe folgt der Stimmung: bei jedem Farbwechsel werden die fünf kleinen Vorlagen neu gemalt (billig).
const mixc = (c, w, k) => c.map((v, i) => Math.round(v + ((w[i] ?? w) - v) * k));
function makeSprites(rgb) {
  const hi = mixc(rgb, 255, 0.86);
  const mid = mixc(rgb, 255, 0.3);
  return [3, 5, 7, 10, 14].map((n) => {
    const c = document.createElement("canvas");
    c.width = c.height = n;
    const g = c.getContext("2d");
    const h = n / 2;
    const gr = g.createRadialGradient(h, h, 0, h, h, h);
    gr.addColorStop(0, `rgba(${hi},1)`);
    gr.addColorStop(0.25, `rgba(${mid},0.95)`);
    gr.addColorStop(0.6, `rgba(${rgb},0.3)`);
    gr.addColorStop(1, `rgba(${mixc(rgb, 0, 0.3)},0)`);
    g.fillStyle = gr;
    g.fillRect(0, 0, n, n);
    return { n, c };
  });
}
let SPRITES = makeSprites([255, 176, 72]);
let spriteRgb = [255, 176, 72];
const spriteFor = (size) => SPRITES[size < 4 ? 0 : size < 6 ? 1 : size < 8.5 ? 2 : size < 12 ? 3 : 4];
const ARCS = Array.from({ length: 7 }, (_, i) => ({ r: 1.02 + i * 0.045, len: 0.5 + ((i * 3) % 5) * 0.28, off: i * 1.7, sp: (i % 2 ? -1 : 1) * (0.2 + i * 0.07), w: i % 3 === 0 ? 2.2 : 1.1 }));
let heat = [255, 176, 72]; // aktuelle Farbe (gleitet weich zur Zielfarbe)
// Helligkeit je Zustand – die Farbe selbst kommt aus der Stimmung
const TINT = { listen: 1, think: 0.86, speak: 1.12, idle: 0.86, muted: 0.7, upsell: 1, type: 0.92 };
function targetColor(now) {
  const base = J.tint || jarvisMood().rgb;
  const f = TINT[J.state] ?? 1;
  let c = base.map((v) => Math.min(255, v * f));
  const fl = J.flash;
  if (fl) {
    const p = (now - fl.at) / fl.dur;
    if (p >= 1) J.flash = null;
    else c = mixc(c, fl.rgb, Math.sin(Math.PI * Math.min(1, p * 1.4)) * 0.85);
  }
  return c;
}
function drawOrb(t, dt) {
  const cv = root().querySelector(".jv-orb");
  if (!cv || root().classList.contains("glow-only")) return;
  const dpr = Math.min(MOBILE ? 1.5 : 1.35, devicePixelRatio || 1) * (J.stride > 2 ? 0.85 : 1);
  const css = cv.clientWidth || 300;
  const S = Math.round(css * dpr);
  if (cv.width !== S) cv.width = cv.height = S;
  const x = cv.getContext("2d");
  const [hr, hg, hb] = heat.map((v) => v | 0);
  const L = J.lvl;
  const B = J.burst || 0;
  const pace = jarvisMood().pace;
  const c = S / 2;
  const R = S * 0.3 * (1 + 0.07 * B);
  const spin = (J.state === "think" ? 1.4 : J.state === "speak" ? 0.7 : 0.4) * (0.6 + 0.4 * pace) + B * 1.6;
  J.ay = (J.ay || 0) + dt * (spin + L * 0.8);
  const ax = 0.42 + 0.12 * Math.sin(t * 0.33);
  const cy = Math.cos(J.ay);
  const sy = Math.sin(J.ay);
  const cx = Math.cos(ax);
  const sx = Math.sin(ax);
  x.clearRect(0, 0, S, S);
  // weiches Glühen hinter der Kugel
  const glow = x.createRadialGradient(c, c, 0, c, c, R * (1.7 + 0.4 * L));
  glow.addColorStop(0, `rgba(${hr},${hg},${hb},${0.28 + 0.3 * L})`);
  glow.addColorStop(0.45, `rgba(${hr},${(hg * 0.7) | 0},${(hb * 0.5) | 0},${0.1 + 0.12 * L})`);
  glow.addColorStop(1, "rgba(0,0,0,0)");
  x.fillStyle = glow;
  x.fillRect(0, 0, S, S);
  x.globalCompositeOperation = "lighter";
  // Partikel (bei schwacher Hardware nur jeder 2./3. – die Kugel bleibt vollständig, nur lichter)
  const f = 3.2;
  const st = J.stride || 1;
  const boost = 1 + 0.22 * (st - 1);
  const wobK = (0.1 + 0.04 * pace) * (1 + B * 1.5);
  for (let i = 0; i < N; i += st) {
    const p = PTS[i];
    const wob = 1 + (L + B * 0.6) * wobK * Math.sin(p.seed * 3 + t * (2 + p.sp * 3 * pace)) + (p.kind === 1 ? 0.08 * Math.sin(t * p.sp + p.seed) : 0);
    let px = p.x;
    let py = p.y;
    let pz = p.z;
    if (p.kind === 2) {
      // Umlaufbahn: flache Ringe um den Äquator
      const a = p.seed + t * p.sp * 0.5;
      px = Math.cos(a);
      pz = Math.sin(a);
      py = 0.08 * Math.sin(p.seed * 5);
    }
    const r = p.rad * wob;
    const X = px * cy + pz * sy;
    const Z0 = -px * sy + pz * cy;
    const Y = py * cx - Z0 * sx;
    const Z = py * sx + Z0 * cx;
    const s = f / (f + Z * r);
    const sxp = c + X * r * R * s;
    const syp = c + Y * r * R * s;
    const depth = (1 - Z) / 2;
    const a = ((p.kind === 1 ? 0.5 : p.kind === 3 ? 0.4 : 0.22) + 0.6 * depth * (0.6 + 0.4 * L)) * boost;
    const size = (p.kind === 3 ? 4.2 : p.kind === 1 ? 5 : 3.2) * (0.55 + 0.9 * depth) * dpr * (0.9 + 0.45 * L);
    const sp = spriteFor(size);
    x.globalAlpha = a > 1 ? 1 : a;
    x.drawImage(sp.c, (sxp - sp.n / 2) | 0, (syp - sp.n / 2) | 0);
  }
  x.globalAlpha = 1;
  // Bögen um die Kugel
  x.lineCap = "round";
  for (const A of ARCS) {
    const from = A.off + t * A.sp * (1 + L);
    x.strokeStyle = `rgba(${hr},${(hg * 0.85) | 0},${(hb * 0.6) | 0},${0.22 + 0.35 * L})`;
    x.lineWidth = A.w * dpr;
    x.beginPath();
    x.ellipse(c, c, R * A.r, R * A.r * (0.94 + 0.06 * Math.sin(t + A.off)), ax * 0.2, from, from + A.len + L * 0.6);
    x.stroke();
  }
  // heller Kern mit Wirbel
  const core = x.createRadialGradient(c, c, 0, c, c, R * (0.42 + 0.22 * L));
  core.addColorStop(0, `rgba(255,248,225,${0.85 + 0.15 * L})`);
  core.addColorStop(0.35, `rgba(${hr},${hg},${(hb * 0.8) | 0},${0.55 + 0.3 * L})`);
  core.addColorStop(1, "rgba(0,0,0,0)");
  x.fillStyle = core;
  x.beginPath();
  x.arc(c, c, R * (0.42 + 0.22 * L), 0, Math.PI * 2);
  x.fill();
  for (let j = 0; j < 3; j++) {
    const a0 = t * (1.1 + j * 0.4) * (j % 2 ? -1 : 1) + j * 2.1;
    x.strokeStyle = `rgba(255,${200 + j * 15},${120 + j * 30},${0.35 + 0.4 * L})`;
    x.lineWidth = (1.2 + L * 1.5) * dpr;
    x.beginPath();
    x.ellipse(c, c, R * (0.2 + j * 0.07), R * (0.09 + j * 0.05), a0, 0, Math.PI * (1.1 + L * 0.6));
    x.stroke();
  }
  x.globalCompositeOperation = "source-over";
}
function loop(now) {
  J.raf = requestAnimationFrame(loop);
  const dt = Math.min(0.05, (now - (J.last || now)) / 1000) || 0.016;
  J.last = now;
  const t = now / 1000;
  let target = 0.14;
  if (J.state === "listen") {
    let mic = 0;
    if (J.an) {
      J.an.getByteTimeDomainData(J.buf);
      let sum = 0;
      for (const v of J.buf) sum += (v - 128) ** 2;
      mic = Math.min(1, Math.sqrt(sum / J.buf.length) / 20);
    }
    target = 0.3 + mic * 0.7 + J.kick * 0.35 + 0.05 * Math.sin(t * 2.2);
  } else if (J.state === "think") target = 0.42 + 0.16 * Math.sin(t * 4.5);
  else if (J.state === "speak") target = 0.46 + 0.22 * Math.abs(Math.sin(t * 6.1) * Math.sin(t * 2.3)) + J.kick * 0.3;
  else if (J.state === "idle" || J.state === "muted") target = 0.12 + 0.04 * Math.sin(t * 1.3);
  if (J.thinkGlow && !J.on) target = 0.3 + 0.12 * Math.sin(t * 4);
  J.kick *= Math.pow(0.02, dt);
  J.burst = (J.burst || 0) * Math.pow(0.08, dt);
  // Farbe weich zur Stimmung gleiten lassen; HUD und Leuchtpunkte folgen
  const tc = targetColor(now);
  const kc = 1 - Math.pow(0.04, dt);
  heat = heat.map((v, i) => v + (tc[i] - v) * kc);
  if (heat.some((v, i) => Math.abs(v - spriteRgb[i]) > 3) && now - (J.spriteAt || 0) > 60) {
    spriteRgb = heat.map((v) => v | 0);
    SPRITES = makeSprites(spriteRgb);
    J.spriteAt = now;
    const el = root();
    el.style.setProperty("--jv-c", spriteRgb.join(", "));
    el.style.setProperty("--jv-hi", mixc(spriteRgb, 255, 0.55).join(", "));
    el.style.setProperty("--jv-bg", mixc(spriteRgb, 0, 0.84).join(", "));
  }
  // Bildratenunabhängig glätten – gleich weich bei 60 und 120 Hz
  J.lvl += (Math.max(0, Math.min(1, target)) - J.lvl) * (1 - Math.pow(0.0008, dt));
  root().style.setProperty("--lvl", J.lvl.toFixed(3));
  if (!REDUCED || !J.drawn) {
    const t0 = performance.now();
    drawOrb(t, dt);
    tune(performance.now() - t0, dt * 1000, now);
  }
  J.drawn = true;
  if (J.on && now - (J.hudAt || 0) > 1000) {
    J.hudAt = now;
    updateHud();
  }
}
// Flüssig auf jedem Gerät: ruckelt es (unter ~40 Bildern/s), zeichnet Jarvis weniger Partikel – und wieder
// alle, sobald Luft ist. Nach einem Rückfall wartet er länger, damit die Qualität nicht hin und her springt.
function tune(cost, frame, now) {
  J.cost = (J.cost ?? cost) * 0.92 + cost * 0.08;
  J.frame = (J.frame ?? frame) * 0.92 + frame * 0.08;
  if (now - (J.tunedAt || 0) < 1500) return;
  J.tunedAt = now;
  const st = J.stride || 1;
  if (J.frame > 25 && st < 3) {
    J.stride = st + 1;
    if (now - (J.upAt || 0) < 5000) J.lockUntil = now + 20000; // gerade erst hochgeschaltet und wieder zu langsam
  } else if (J.frame < 19 && st > 1 && now > (J.lockUntil || 0)) {
    J.stride = st - 1;
    J.upAt = now;
  }
}
function startLoop() {
  if (!J.raf) {
    J.last = 0;
    J.raf = requestAnimationFrame(loop);
  }
}
function stopLoop() {
  cancelAnimationFrame(J.raf);
  J.raf = 0;
}
async function startMeter() {
  if (IOS || J.an || !navigator.mediaDevices?.getUserMedia) return; // iOS: Mikro nicht doppelt öffnen, sonst stoppt die Erkennung
  try {
    J.mic = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true } });
    J.ctx = new (window.AudioContext || window.webkitAudioContext)();
    const src = J.ctx.createMediaStreamSource(J.mic);
    J.an = J.ctx.createAnalyser();
    J.an.fftSize = 512;
    J.buf = new Uint8Array(J.an.fftSize);
    src.connect(J.an);
  } catch (_) {
    J.an = null;
  }
}
function stopMeter() {
  J.mic?.getTracks().forEach((t) => t.stop());
  J.ctx?.close().catch(() => {});
  Object.assign(J, { mic: null, ctx: null, an: null });
}
// Sanftes Leuchten an den Rändern, während AKYTEX AI im Chat nachdenkt
export function thinkGlow(on) {
  if (J.on) return;
  J.thinkGlow = on;
  const el = root();
  if (on) {
    el.hidden = false;
    el.classList.add("glow-only");
    requestAnimationFrame(() => el.classList.add("on"));
    startLoop();
  } else {
    el.classList.remove("on");
    setTimeout(() => {
      if (J.on || J.thinkGlow) return;
      el.hidden = true;
      el.classList.remove("glow-only");
      stopLoop();
    }, 500);
  }
}

// ---------- Ablauf ----------
export function initJarvis(deps) {
  J.deps = deps;
  // Tastatur im Browser: Alt+J öffnet Jarvis, Leertaste = sprechen (bzw. fertig), Esc schließt
  addEventListener("keydown", (e) => {
    if (e.key === "Escape" && J.on) {
      if (!root().querySelector(".jv-moodbox").hidden) return toggleMoodBox(false);
      return stopJarvis();
    }
    if (e.altKey && e.code === "KeyJ" && !e.ctrlKey && !e.metaKey) {
      e.preventDefault();
      if (J.on || J.deps.allowed() || trialLeft()) startJarvis();
      else J.deps.upsell();
      return;
    }
    const typing = e.target.closest?.("input, textarea, select, [contenteditable]");
    if (!J.on || typing || e.code !== "Space" || e.repeat || e.ctrlKey || e.metaKey || e.altKey) return;
    e.preventDefault();
    if (J.state === "listen" && J.rec) {
      // Leertaste beim Zuhören: „Ich bin fertig“ – sofort auswerten
      clearTimeout(J.endTimer);
      try {
        J.rec.stop();
      } catch (_) {
        /* schon beendet */
      }
      return;
    }
    if (["speak", "idle"].includes(J.state)) {
      if (!J.voiceOk) unlockVoice();
      J.speakToken = (J.speakToken || 0) + 1;
      speechSynthesis?.cancel();
      listen(true);
      J.finishSpeak?.();
    }
  });
}
// opts.say: statt der Begrüßung diesen Text sprechen (z. B. dein Zukunfts-Ich) · opts.free: auch ohne Ultra
// opts.tint: eigene Farbe · opts.voice: Stimme färben · opts.acts: Knöpfe danach
export async function startJarvis(opts = {}) {
  const d = J.deps;
  if (J.on && !opts.say) return stopJarvis();
  if (J.on) stopJarvis();
  if (!opts.free && !d.allowed() && !trialLeft()) return upsellCard(true);
  J.tint = opts.tint || null;
  J.tintLabel = opts.label || "";
  // Töne nur außerhalb von iOS (dort würde Web Audio die Sprachausgabe stumm schalten)
  if (!IOS) {
    try {
      J.ac ||= new (window.AudioContext || window.webkitAudioContext)();
      J.ac.resume?.();
    } catch (_) {
      /* ohne Web Audio */
    }
  }
  Object.assign(J, { on: true, silent: 0, muted: false, rest: "", pending: null });
  const el = root();
  el.hidden = false;
  el.classList.remove("glow-only", "has-card");
  el.querySelector(".jv-micbtn").classList.remove("off");
  document.documentElement.classList.add("jv-open");
  requestAnimationFrame(() => el.classList.add("on"));
  showYou("");
  showActions([]);
  updateHud();
  startLoop();
  d.haptic?.([10, 40, 10]);
  const title = jarvisTitle();
  const h = new Date().getHours();
  const daypart = h < 5 ? "Noch wach" : h < 11 ? "Guten Morgen" : h < 18 ? "Willkommen zurück" : "Guten Abend";
  const first = !J.greeted;
  const hi = first ? `${daypart}, ${title}. Alle Systeme online. ${d.quickStatus?.() || ""} Was kann ich für dich tun?` : `Zu Diensten, ${title}.`;
  J.greeted = true;
  const trial = !d.allowed() ? ` Du hast ${trialLeft()} Gratis-Fragen.` : "";
  const hint = maleHint();
  const greet = (hi + trial).replace(/\s+/g, " ").trim();
  const showHint = () => {
    if (!hint || !J.on) return;
    showSay(hint);
    revealTo(1e9);
  };
  // Eigener Text (Zukunfts-Ich): sprechen, dann Knöpfe – zuhören nur mit Jarvis-Zugang
  if (opts.say) {
    typeMode(false);
    J.voiceMod = opts.voice || null;
    await speakOut(opts.say);
    if (!J.on) return;
    showActions(opts.acts || []);
    if (d.allowed() || trialLeft()) {
      if (!SR) return typeMode(true);
      if (!J.rec) listen();
    } else idle();
    return;
  }
  // Die Begrüßung startet noch im Tipp – so dürfen iPhone und Safari danach sprechen
  typeMode(!SR);
  if (!SR) {
    await speakOut(greet);
    if (J.on && J.typing) setState("type");
    return showHint();
  }
  if (SAFARI) {
    // Safari/iPhone: kurz begrüßen, dann zuhören (klappt das ohne neuen Tipp nicht, reicht ein Tipp auf den Kern)
    await speakOut(first ? `${daypart}, ${title}. Was kann ich für dich tun?${trial}` : `Ja, ${title}?`);
    showHint();
    if (J.on && !J.rec) listen();
    return;
  }
  startMeter();
  await speakOut(greet);
  showHint();
  if (J.on && !J.rec) listen();
}
export function stopJarvis() {
  if (!J.on) return;
  J.on = false;
  J.tint = null;
  J.tintLabel = "";
  stopRec();
  J.speakToken = (J.speakToken || 0) + 1;
  speechSynthesis?.cancel();
  J.finishSpeak?.();
  audioMode("auto");
  for (const k of ["sayTimer", "idleTimer", "endTimer", "voiceDog"]) clearTimeout(J[k]);
  stopMeter();
  const el = root();
  el.classList.remove("on");
  document.documentElement.classList.remove("jv-open");
  setTimeout(() => {
    if (J.on || J.thinkGlow) return;
    el.hidden = true;
    stopLoop();
  }, 600);
}

// Zuhören: lässt dich ausreden (kurze Pause beendet) und wählt die sinnvollste Erkennungs-Variante
function listen(fromTap = false) {
  if (!J.on || J.muted) return;
  clearTimeout(J.idleTimer);
  audioMode("auto");
  setState("listen");
  const finals = [];
  const alts = [];
  let interim = "";
  const rec = new SR();
  rec.lang = "de-DE";
  rec.interimResults = true;
  rec.continuous = !IOS; // iOS beendet „continuous“ unzuverlässig – dort Standardmodus
  rec.maxAlternatives = 3;
  const armEnd = (ms) => {
    clearTimeout(J.endTimer);
    J.endTimer = setTimeout(() => {
      try {
        rec.stop();
      } catch (_) {
        /* schon beendet */
      }
    }, ms);
  };
  rec.onsoundstart = () => (J.kick = 0.6);
  rec.onstart = () => {
    J.heard = true;
    chime(true);
  };
  rec.onresult = (e) => {
    interim = "";
    for (let i = e.resultIndex; i < e.results.length; i++) {
      const res = e.results[i];
      if (res.isFinal) {
        finals[i] = res[0].transcript;
        alts[i] = Array.from(res, (a) => a.transcript);
      } else interim += res[0].transcript;
    }
    J.kick = 1;
    showYou((finals.join(" ") + " " + interim).replace(/\s+/g, " ").trim());
    armEnd(interim ? 1400 : 850);
  };
  rec.onerror = (e) => {
    if (e.error === "not-allowed" || e.error === "service-not-allowed") {
      // Schon einmal zugehört oder ohne Tipp gestartet? Dann will der Browser nur einen neuen Tipp (Safari) –
      // erst wenn es auch direkt nach einem Tipp nicht klappt, fehlt wirklich die Erlaubnis
      if (J.heard || (SAFARI && !fromTap)) {
        if (J.rec === rec) J.rec = null;
        return idle();
      }
      J.deps.toast("Bitte erlaube den Zugriff aufs Mikrofon – oder schreib Jarvis einfach.", "error", "🎙 Mikrofon");
      J.rec = null;
      typeMode(true);
    }
  };
  rec.onend = () => {
    clearTimeout(J.endTimer);
    if (J.rec !== rec) return;
    J.rec = null;
    if (!J.on || J.muted) return;
    let text = finals.filter(Boolean).join(" ").trim() || interim.trim();
    const only = alts.filter(Boolean);
    if (only.length === 1 && only[0].length > 1 && J.deps.score) text = only[0].map((a) => [a, J.deps.score(cleanUtterance(a))]).sort((a, b) => b[1] - a[1])[0][0];
    text = cleanUtterance(text);
    if (text) {
      J.silent = 0;
      chime(false);
      return handle(text);
    }
    if (++J.silent >= 2) return idle();
    listen();
  };
  J.rec = rec;
  armEnd(9000);
  try {
    rec.start();
  } catch (_) {
    J.rec = null;
    idle();
  }
}
function idle() {
  if (J.typing) return;
  setState("idle");
  clearTimeout(J.idleTimer);
  J.idleTimer = setTimeout(stopJarvis, 30000);
}

const YES = /^(ja|jo|jep|jap|klar|gerne|gern|ok(ay)?|mach( das| es)?|los|genau|auf jeden|sicher)\b/i;
const MORE = /^(ja|mehr|weiter|erzähl( mir)? mehr|und( weiter)?|genauer|details?|ausführlicher)\b/i;
const NO = /^(nein|nee|ne|nö|lieber nicht|abbrechen|stopp? das)\b/i;
const BYE = /^(stopp?|danke( dir| schön)?( jarvis)?|tschüss|tschau|ciao|ende|beenden|schließen|das wars?|das war's|bis später|gute nacht)\b/i;
// Was per Sprache bestätigt werden darf: nichts, was Geld bewegt oder handelt
export const voiceSafe = (a) => !!a && !(a.side || a.fund || a.schedule || a.plan || /kauf|verkauf|order|zahl|einzahl|auszahl|abo|bestell|handel|ausführ/i.test(a.label || ""));

const next = () => (J.typing ? setState("type", "Schreib oder diktiere deine Frage") : listen());
// „Sei ruhiger“, „Stimmung motiviert“, „Emotion witzig“, „Modus Auto“
const MOOD_WORDS = [
  [/^(ruhig|gelassen|entspannt|chill)/, "ruhig"],
  [/^(motiviert|energisch|power|hype|gas)/, "motiviert"],
  [/^(herzlich|warm|lieb|nett|freundlich)/, "herzlich"],
  [/^(witzig|lustig|cool|locker)/, "witzig"],
  [/^(ernst|sachlich|fokus|konzentriert|professionell)/, "ernst"],
  [/^(klassisch|normal|butler|jarvis)/, "jarvis"],
  [/^(auto|automatisch)/, "auto"],
];
function moodFromSpeech(t) {
  const m = t.match(/^(?:sei|werd|werde|bleib|klingt?|sprich|stimmung|emotion|modus|laune|stell dich auf|wechsel(?:e)? (?:zu|auf)|sei mal|sei bitte)\s+(?:(?:etwas|mal|bitte|wieder|mehr|jetzt|ab jetzt|so|ein bisschen|auf)\s+)*([\p{L}]+)/u);
  if (!m) return null;
  const hit = MOOD_WORDS.find(([re]) => re.test(m[1]));
  return hit ? hit[1] : null;
}
function reactFromSpeech(t) {
  const r = reactions();
  if (/^(keine|ohne|lass die) (witze|sprüche|humor)/.test(t)) return { r: { ...r, humor: false }, say: "Verstanden. Keine Witze mehr." };
  if (/^(mach (wieder |mehr )?witze|mehr humor|sei wieder lustig|witze an)/.test(t)) return { r: { ...r, humor: true }, say: "Humor ist wieder an. Ich verspreche nichts." };
  if (/^(zeig |zeige )?(keine|ohne) (emotionen|gefühle)/.test(t)) return { r: { joy: false, worry: false, hype: false, humor: false }, say: "In Ordnung. Ab jetzt ganz neutral." };
  if (/^(zeig|zeige) (wieder |deine |alle )?(emotionen|gefühle)/.test(t)) return { r: { joy: true, worry: true, hype: true, humor: true }, say: "Mit Gefühl. Ich freue mich mit dir – und sage dir, wenn es brenzlig wird." };
  return null;
}
// Gedächtnis: „Merk dir, dass ich Tesla mag“ · „Was weißt du über mich?“ · „Vergiss alles“
async function memoryCommand(t, raw) {
  const title = jarvisTitle();
  const add = raw.match(/^(?:merk|merke|speicher|notier|notiere)\s+dir[,:]?\s*(?:bitte\s+)?(?:dass\s+)?(.{3,160})$/i);
  if (add) {
    const note = add[1].replace(/[.!]+$/, "").trim();
    const sub = /\bdass\s/i.test(raw.slice(0, raw.length - add[1].length + 5));
    const list = jarvisMemory().filter((x) => x.t.toLowerCase() !== note.toLowerCase());
    list.push({ t: note, sub, at: Date.now() });
    keep(MEM_KEY, list.slice(-30));
    emote("joy");
    await speakOut(`Alles klar, ${title}. Ich merke mir${sub ? ", dass" : ":"} ${toYou(note)}.`);
    return true;
  }
  if (/(was weißt du (alles )?über mich|was hast du dir gemerkt|was merkst du dir|dein gedächtnis)/.test(t)) {
    const list = jarvisMemory();
    await speakOut(list.length ? `Ich habe mir ${list.length === 1 ? "eine Sache" : list.length + " Dinge"} gemerkt: ${list.slice(-5).map((x) => (x.sub ? "dass " : "") + toYou(x.t)).join(", und ")}.` : `Noch nichts, ${title}. Sag einfach „Merk dir …“.`);
    return true;
  }
  const del = t.match(/^vergiss\s+(alles|das|.{3,80})$/);
  if (del) {
    const list = jarvisMemory();
    let left = list;
    if (del[1] === "alles") left = [];
    else if (del[1] === "das") left = list.slice(0, -1);
    else {
      const words = del[1].replace(/^(dass|das mit)\s+/, "").split(/\s+/).filter((w) => w.length > 2);
      left = list.filter((x) => !words.every((w) => x.t.toLowerCase().includes(w)));
    }
    keep(MEM_KEY, left);
    await speakOut(list.length === left.length ? "Dazu hatte ich mir nichts gemerkt." : del[1] === "alles" ? "Erledigt. Mein Gedächtnis ist leer." : "Vergessen.");
    return true;
  }
  return false;
}
async function handle(text) {
  const d = J.deps;
  const t = text.toLowerCase().trim();
  const title = jarvisTitle();
  if (BYE.test(t)) {
    await speakOut(`Jederzeit, ${title}. Ich bin da, wenn du mich brauchst.`);
    return stopJarvis();
  }
  const call = t.match(/^(?:nenn|nenne|sag zu) (?:mich|mir) (?:ab jetzt |ab sofort |bitte )?(.{2,24})$/);
  if (call) {
    const nt = call[1].replace(/[^\p{L}\p{N} .-]/gu, "").trim().replace(/^./, (ch) => ch.toUpperCase());
    setTitle(nt);
    await speakOut(`Alles klar, ${nt}. So nenne ich dich ab jetzt.`);
    return J.on && next();
  }
  const mood = moodFromSpeech(t);
  if (mood) {
    toggleMoodBox(false);
    await previewMood(mood);
    return;
  }
  if (/^(welche |zeig (mir )?(die |deine )?)?(stimmungen|emotionen|gefühle)( gibt es| hast du| zeigen| wählen)?$/.test(t) || /emotionen (wählen|einstellen|ändern)/.test(t)) {
    toggleMoodBox(true);
    await speakOut(`Wähle meine Stimmung: ${Object.values(MOODS).map((m) => m.label).join(", ")} oder Auto. Darunter legst du fest, welche Gefühle ich zeige.`);
    return J.on && next();
  }
  const rx = reactFromSpeech(t);
  if (rx) {
    setReactions(rx.r);
    await speakOut(rx.say);
    return J.on && next();
  }
  const mem = await memoryCommand(t, text);
  if (mem) return J.on && next();
  if (J.rest && !J.pending && MORE.test(t)) {
    const { text: part, rest } = toSpeech(J.rest);
    J.rest = rest;
    await speakOut(part + (rest ? " Soll ich weitererzählen?" : ""));
    return J.on && next();
  }
  if (J.pending && YES.test(t)) {
    const a = J.pending;
    J.pending = null;
    const btn = root().querySelector(`[data-jv-act="${J.actions.indexOf(a)}"]`) || document.createElement("button");
    d.runAction(a, btn);
    await speakOut(`Erledigt, ${title}.`);
    return J.on && next();
  }
  if ((J.pending || J.rest) && NO.test(t)) {
    J.pending = null;
    J.rest = "";
    await speakOut("Alles klar.");
    return J.on && next();
  }
  J.pending = null;
  J.rest = "";
  const free = !d.allowed();
  if (free && !trialLeft()) return upsellCard(false);
  setState("think");
  showActions([]);
  showSay("");
  let reply;
  let answered = false;
  let filler = null;
  const md = jarvisMood();
  const fillTimer = setTimeout(() => {
    if (!J.on || answered || J.state !== "think") return;
    const list = md.key === "witzig" && !reactions().humor ? FILLERS.jarvis : FILLERS[md.key];
    filler = speakOut(pick(list)).then(() => J.on && !answered && setState("think"));
  }, 1400);
  try {
    reply = await d.ask(text);
  } catch (e) {
    reply = { html: `<p>Das hat gerade nicht geklappt: ${esc(e.message)}</p>` };
  }
  answered = true;
  clearTimeout(fillTimer);
  if (filler) await Promise.race([filler, new Promise((r) => setTimeout(r, 2500))]);
  if (!J.on) return;
  if (free) useTrial();
  const { text: said, rest } = toSpeech(reply?.html || "Dazu habe ich gerade keine Antwort.");
  J.rest = rest;
  const acts = (reply?.actions || []).filter((a) => a.label);
  showActions(acts);
  const offerable = (a) => voiceSafe(a) && !/rückgängig/i.test(a.label);
  const offer = acts.find((a) => a.primary && offerable(a)) || acts.find(offerable);
  J.pending = offer || null;
  const money = acts.find((a) => !voiceSafe(a));
  const tail = offer ? ` Sag „ja“, und ich mache: ${offer.label}.` : money ? " Bestätige das bitte per Tipp auf den Button." : rest ? " Soll ich mehr erzählen?" : "";
  const rs = reactions();
  const feel = feeling(reply?.html);
  let open = "";
  if (feel && rs[feel]) {
    emote(feel);
    const o = OPENERS[feel][md.key] || [];
    if (o.length && Math.random() < 0.6) open = pick(o) + " ";
  }
  const quip = rs.humor && md.key === "witzig" && !offer && !money && Math.random() < 0.3 ? " " + pick(QUIPS) : "";
  await speakOut(open + said + tail + quip);
  if (!J.on || J.rec) return;
  if (free && !trialLeft()) return upsellCard(false);
  if (J.typing) return setState("type", "Schreib oder diktiere deine Frage");
  listen();
}

// Abkürzungen ausschreiben – klingt natürlicher und trennt Sätze nicht mitten im „z. B.“
const ABBR = [
  [/\bz\.\s?B\./g, "zum Beispiel"],
  [/\bd\.\s?h\./g, "das heißt"],
  [/\bu\.\s?a\./g, "unter anderem"],
  [/\bbzw\./g, "beziehungsweise"],
  [/\bca\./g, "circa"],
  [/\binkl\./g, "inklusive"],
  [/\bevtl\./g, "eventuell"],
  [/\bggf\./g, "gegebenenfalls"],
  [/\busw\./g, "und so weiter"],
  [/\betc\./g, "et cetera"],
  [/\bNr\./g, "Nummer"],
  [/\bMio\./g, "Millionen"],
  [/\bMrd\./g, "Milliarden"],
  [/\bTsd\./g, "Tausend"],
];
const speakable = (t) => ABBR.reduce((s, [re, w]) => s.replace(re, w), t);
// Hinweis, wenn der Browser gar nicht sprechen lässt (einmal pro Sitzung)
function voiceHint() {
  if (J.voiceHinted) return;
  J.voiceHinted = true;
  J.deps.toast(
    IOS ? "Ich kann gerade nicht laut sprechen. Stell den Ton lauter und den Stumm-Schalter aus – dann tippe einmal auf den Kern." : "Dein Browser lässt mich gerade nicht sprechen. Tippe einmal auf den Kern oder wechsle mit 🗣 die Stimme.",
    "info",
    "🔈 Stimme"
  );
}
// Sprechen Satz für Satz: natürlichere Pausen, keine Abbrüche bei langen Texten, Untertitel synchron.
// Startet die Stimme nicht (blockiert oder defekte Stimme), versucht Jarvis es mit der Standardstimme
// und zeigt sonst nur Untertitel – er hängt nie stumm fest.
function speakOut(text) {
  text = speakable(text);
  return new Promise((resolve) => {
    setState("speak");
    showSay("");
    for (const k of ["sayTimer", "voiceDog"]) clearTimeout(J[k]);
    clearInterval(J.revealTimer);
    const token = (J.speakToken = (J.speakToken || 0) + 1);
    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      for (const k of ["sayTimer", "voiceDog"]) clearTimeout(J[k]);
      clearInterval(J.revealTimer);
      revealTo(1e9);
      resolve();
    };
    // Nur Untertitel, im Lesetempo
    const showAll = () => {
      showSay(text);
      revealTo(1e9);
    };
    const captions = () => {
      showAll();
      clearTimeout(J.sayTimer);
      J.sayTimer = setTimeout(finish, Math.min(7000, 400 + text.length * 40));
    };
    J.finishSpeak = finish;
    const md = jarvisMood();
    const mod = J.voiceMod || { rate: 1, pitch: 0 };
    J.voiceMod = null;
    if (!("speechSynthesis" in window) || !text.trim()) return captions();
    stopRec();
    audioMode("playback");
    // Sätze bilden, sehr kurze Stücke an den nächsten Satz hängen
    // Satzende nur bei . ! ? mit folgendem Leerzeichen – „1.500“ oder „3,5.“ bleiben ganz
    const parts = [];
    let start = 0;
    const push = (end) => {
      const t = text.slice(start, end);
      if (t.trim()) {
        const last = parts[parts.length - 1];
        if (last && last.text.length < 40) last.text += t;
        else parts.push({ text: t, at: start });
      }
      start = end;
    };
    for (let i = 0; i < text.length; i++) if (".!?".includes(text[i]) && (i + 1 === text.length || /\s/.test(text[i + 1]))) push(i + 1);
    push(text.length);

    const attempt = (v, canRetry) => {
      const run = (J.speakRun = (J.speakRun || 0) + 1);
      const live = () => !done && token === J.speakToken && run === J.speakRun;
      let left = parts.length;
      let started = false;
      let bounded = false;
      const fallback = () => {
        if (!live()) return;
        J.speakRun++;
        clearTimeout(J.voiceDog);
        try {
          speechSynthesis.cancel();
        } catch (_) {
          /* nichts zu stoppen */
        }
        showAll(); // während des zweiten Versuchs schon mitlesen
        if (canRetry && v) {
          J.badVoice = v.name;
          return setTimeout(() => token === J.speakToken && !done && attempt(null, false), 120);
        }
        J.voiceFailed = true;
        voiceHint();
        captions();
      };
      // Referenzen halten: Chrome verliert sonst Ereignisse von Äußerungen, die der Speicher schon aufgeräumt hat
      J.utts = parts.map((p) => {
        const u = new SpeechSynthesisUtterance(p.text.trim());
        u.lang = v?.lang || "de-DE";
        try {
          if (v) u.voice = v;
        } catch (_) {
          /* Stimme nicht mehr vorhanden: Standardstimme */
        }
        u.pitch = Math.max(0.3, (isMale(v) ? 0.95 : 0.72) + md.pitch + mod.pitch); // ohne Männerstimme im System: vorhandene Stimme tiefer
        u.rate = Math.min(1.4, 1.02 * md.rate * mod.rate);
        // Untertitel wie im Film: nur der Satz, der gerade gesprochen wird
        u.onstart = () => {
          if (!live()) return;
          started = true;
          J.voiceOk = true;
          J.voiceFailed = false;
          clearTimeout(J.voiceDog);
          J.kick = 0.7;
          J.partStart = performance.now();
          showSay(p.text.trim());
          revealTo(0);
        };
        u.onboundary = (e) => {
          if (!live()) return;
          bounded = true;
          J.kick = 0.85;
          revealTo(e.charIndex);
        };
        u.onend = () => {
          if (!live()) return;
          revealTo(1e9);
          if (--left <= 0) finish();
        };
        u.onerror = (e) => {
          if (!live()) return;
          // Vor dem ersten Wort gescheitert (blockiert, Stimme fehlt): anders versuchen
          if (!started && !/interrupted|canceled/.test(e.error || "")) return fallback();
          u.onend();
        };
        return u;
      });
      const go = () => {
        if (!live()) return;
        try {
          speechSynthesis.resume?.(); // Chrome bleibt sonst manchmal pausiert
          for (const u of J.utts) speechSynthesis.speak(u);
        } catch (_) {
          fallback();
        }
      };
      // Läuft noch etwas, erst stoppen – direkt danach „speak“ verschlucken manche Browser
      if (speechSynthesis.speaking || speechSynthesis.pending) {
        speechSynthesis.cancel();
        setTimeout(go, 80);
      } else go();
      // Wachhund: kommt kein Ton, nicht stumm hängen bleiben
      J.voiceDog = setTimeout(() => !started && fallback(), 1800);
      // Ohne Wort-Ereignisse der Stimme: Untertitel im Sprechtempo einblenden
      clearInterval(J.revealTimer);
      J.revealTimer = setInterval(() => {
        if (bounded || !started) return bounded && clearInterval(J.revealTimer);
        revealTo(((performance.now() - (J.partStart || performance.now())) / 1000) * 15); // ca. 15 Zeichen pro Sekunde
      }, 110);
      clearTimeout(J.sayTimer);
      J.sayTimer = setTimeout(() => live() && finish(), 5500 + text.length * 85); // Sicherheitsnetz, falls „end“ nie kommt
    };
    // Klappte die Stimme zuletzt gar nicht, gleich mitlesen lassen; eine defekte Stimme nicht noch einmal versuchen
    if (J.voiceFailed) showAll();
    const v = bestVoice || pickVoice();
    attempt(v && v.name !== J.badVoice ? v : null, !J.voiceFailed);
  });
}

function upsellCard(fromStart) {
  const el = root();
  el.hidden = false;
  el.classList.remove("glow-only");
  document.documentElement.classList.add("jv-open");
  requestAnimationFrame(() => el.classList.add("on"));
  J.on = true;
  startLoop();
  setState("upsell");
  showYou("");
  const msg = `${fromStart ? "Jarvis gehört zu AKYTEX Ultra." : "Das waren deine Gratis-Fragen."} Mit Ultra sprichst du unbegrenzt mit mir: Lagebericht, nächste Schritte und die ganze App per Stimme.`;
  const done = () => {
    root().querySelector(".jv-acts").innerHTML = `<button class="btn primary small" data-jv="plans">✦ Ultra ansehen</button>`;
    J.on && idle();
  };
  if (!fromStart) speakOut(msg).then(done);
  else {
    showSay(msg);
    revealTo(1e9);
    done();
  }
}
