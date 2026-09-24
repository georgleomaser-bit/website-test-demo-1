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
  speechSynthesis.cancel();
  speakOut(`So klinge ich als ${bestVoice.name.split(/[ (]/)[0]}.`).then(() => J.on && !J.typing && listen());
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

// ---------- Oberfläche ----------
function build() {
  const el = document.createElement("div");
  el.className = "jv";
  el.id = "jv";
  el.hidden = true;
  el.innerHTML = `<div class="jv-shade" aria-hidden="true"></div>
    <div class="jv-edge" aria-hidden="true"></div><div class="jv-edge jv-soft" aria-hidden="true"></div><div class="jv-edge jv-wide" aria-hidden="true"></div>
    <div class="jv-card" role="status" aria-live="polite"><p class="jv-say"></p><div class="jv-acts"></div></div>
    <div class="jv-pill" role="dialog" aria-label="Jarvis – Sprachmodus">
      <canvas class="jv-orb" aria-hidden="true"></canvas>
      <div class="jv-txt"><span class="jv-state">Ich höre zu …</span><span class="jv-you"></span></div>
      <form class="jv-type" hidden><input type="text" enterkeyhint="send" autocomplete="off" placeholder="Frag Jarvis … (🎤 auf der Tastatur zum Diktieren)" aria-label="Frage an Jarvis" /></form>
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
function setState(s, label) {
  J.state = s;
  const el = root();
  el.dataset.state = s;
  el.querySelector(".jv-state").textContent = label || { listen: "Ich höre zu …", think: "Einen Moment …", speak: "Jarvis", idle: "Tippe auf die Kugel", muted: "Mikrofon aus", upsell: "Jarvis" }[s] || "";
}
function onClick(e) {
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
  if (b?.dataset.jvAct != null) {
    const a = J.actions?.[+b.dataset.jvAct];
    if (a) J.deps.runAction(a, b);
    return;
  }
  // Kugel oder Text antippen: unterbrechen und zuhören
  if (e.target.closest(".jv-orb, .jv-txt, .jv-say") && ["speak", "idle"].includes(J.state)) {
    speechSynthesis?.cancel();
    clearTimeout(J.sayTimer);
    listen();
  }
}
// Schreib-/Diktiermodus: ohne Spracherkennung (Firefox, In-App-Browser) oder bei stummem Mikro
function typeMode(on) {
  J.typing = on;
  const f = root().querySelector(".jv-type");
  f.hidden = !on;
  root().querySelector(".jv-txt").hidden = on;
  root().classList.toggle("typing", on);
  if (on) {
    setState("type", "Schreib oder diktiere deine Frage");
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
    .map((a, i) => `<button class="${a.primary ? "btn primary small" : "mini-btn"}" data-jv-act="${i}">${esc(a.label)}</button>`)
    .join("");
}

// ---------- Schillernde Kugel (Canvas, 60 fps, bildratenunabhängig) ----------
const PAL = {
  listen: [
    [90, 170, 255],
    [175, 110, 255],
    [60, 230, 255],
  ],
  think: [
    [255, 170, 90],
    [255, 90, 130],
    [190, 120, 255],
  ],
  speak: [
    [190, 120, 255],
    [255, 110, 180],
    [110, 150, 255],
  ],
  idle: [
    [120, 140, 190],
    [160, 140, 210],
    [110, 170, 210],
  ],
};
PAL.muted = PAL.idle;
PAL.upsell = PAL.speak;
let cur = PAL.listen.map((c) => [...c]);
function drawOrb(t, dt) {
  const cv = root().querySelector(".jv-orb");
  if (!cv || root().classList.contains("glow-only")) return;
  const dpr = Math.min(2, devicePixelRatio || 1);
  const css = cv.clientWidth || 44;
  const S = Math.round(css * dpr);
  if (cv.width !== S) cv.width = cv.height = S;
  const x = cv.getContext("2d");
  const k = 1 - Math.pow(0.03, dt);
  const target = PAL[J.state] || PAL.listen;
  cur = cur.map((c, i) => c.map((v, j) => v + (target[i][j] - v) * k));
  const c = S / 2;
  const R = S / 2;
  const L = J.lvl;
  x.clearRect(0, 0, S, S);
  x.save();
  x.beginPath();
  x.arc(c, c, R * (0.9 + 0.1 * L), 0, Math.PI * 2);
  x.clip();
  x.fillStyle = "#0b0d1a";
  x.fillRect(0, 0, S, S);
  x.globalCompositeOperation = "lighter";
  for (let i = 0; i < 3; i++) {
    const [r, g, b] = cur[i];
    const a = t * (0.9 + i * 0.35 + L * 1.4) + i * 2.1;
    const px = c + Math.cos(a) * R * (0.28 + 0.12 * Math.sin(t * 0.7 + i));
    const py = c + Math.sin(a * 1.13) * R * (0.28 + 0.12 * Math.cos(t * 0.6 + i));
    const gr = x.createRadialGradient(px, py, 0, px, py, R * (0.85 + 0.25 * L));
    gr.addColorStop(0, `rgba(${r | 0},${g | 0},${b | 0},0.95)`);
    gr.addColorStop(1, `rgba(${r | 0},${g | 0},${b | 0},0)`);
    x.fillStyle = gr;
    x.fillRect(0, 0, S, S);
  }
  x.globalCompositeOperation = "source-over";
  // Glanzlicht wie bei einer Glaskugel
  const hl = x.createRadialGradient(c - R * 0.35, c - R * 0.4, 0, c - R * 0.35, c - R * 0.4, R * 0.7);
  hl.addColorStop(0, "rgba(255,255,255,0.55)");
  hl.addColorStop(1, "rgba(255,255,255,0)");
  x.fillStyle = hl;
  x.fillRect(0, 0, S, S);
  x.restore();
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
  // Bildratenunabhängig glätten – gleich weich bei 60 und 120 Hz
  J.lvl += (Math.max(0, Math.min(1, target)) - J.lvl) * (1 - Math.pow(0.0008, dt));
  root().style.setProperty("--lvl", J.lvl.toFixed(3));
  if (!REDUCED || !J.drawn) drawOrb(t, dt);
  J.drawn = true;
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
  addEventListener("keydown", (e) => e.key === "Escape" && J.on && stopJarvis());
}
export async function startJarvis() {
  const d = J.deps;
  if (J.on) return stopJarvis();
  if (!d.allowed() && !trialLeft()) return upsellCard(true);
  // Sprachausgabe im Moment des Tippens freischalten (iOS/Safari spielen sonst später nichts ab)
  try {
    const u = new SpeechSynthesisUtterance(" ");
    u.volume = 0;
    speechSynthesis.speak(u);
  } catch (_) {
    /* ohne Sprachausgabe */
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
  startLoop();
  d.haptic?.([10, 40, 10]);
  const title = jarvisTitle();
  const h = new Date().getHours();
  const hi = !J.greeted ? `${h < 5 ? "Noch wach" : h < 11 ? "Guten Morgen" : h < 18 ? "Hey" : "Guten Abend"}, ${title}. ${d.quickStatus?.() || ""} Was kann ich für dich tun?` : `Ja, ${title}?`;
  J.greeted = true;
  const trial = !d.allowed() ? ` Du hast ${trialLeft()} Gratis-Fragen.` : "";
  const hint = maleHint();
  const greet = (hi + trial).replace(/\s+/g, " ").trim();
  typeMode(!SR);
  if (!SR) {
    showSay(greet + (hint ? " " + hint : ""));
    revealTo(1e9);
    return;
  }
  if (SAFARI) {
    // Safari: sofort zuhören (noch im Tipp), Begrüßung nur als Text
    showSay(greet + (hint ? " " + hint : ""));
    revealTo(1e9);
    return listen();
  }
  startMeter();
  await speakOut(greet);
  if (hint) {
    showSay(hint);
    revealTo(1e9);
  }
  if (J.on) listen();
}
export function stopJarvis() {
  if (!J.on) return;
  J.on = false;
  try {
    J.rec?.abort();
  } catch (_) {
    /* schon beendet */
  }
  J.rec = null;
  speechSynthesis?.cancel();
  for (const k of ["sayTimer", "idleTimer", "endTimer"]) clearTimeout(J[k]);
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
function listen() {
  if (!J.on || J.muted) return;
  clearTimeout(J.idleTimer);
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
  rec.onstart = () => (J.heard = true);
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
    armEnd(interim ? 1700 : 1150);
  };
  rec.onerror = (e) => {
    if (e.error === "not-allowed" || e.error === "service-not-allowed") {
      // Schon einmal zugehört? Dann will der Browser nur einen neuen Tipp (Safari) – sonst fehlt die Erlaubnis
      if (J.heard) return idle();
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
  try {
    reply = await d.ask(text);
  } catch (e) {
    reply = { html: `<p>Das hat gerade nicht geklappt: ${esc(e.message)}</p>` };
  }
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
  await speakOut(said + tail);
  if (!J.on) return;
  if (free && !trialLeft()) return upsellCard(false);
  if (J.typing) return setState("type", "Schreib oder diktiere deine Frage");
  listen();
}

function speakOut(text) {
  return new Promise((resolve) => {
    setState("speak");
    showSay(text);
    clearTimeout(J.sayTimer);
    const finish = () => {
      clearTimeout(J.sayTimer);
      clearInterval(J.revealTimer);
      revealTo(1e9);
      resolve();
    };
    if (!("speechSynthesis" in window)) {
      revealTo(1e9);
      return setTimeout(resolve, Math.min(8000, 600 + text.length * 45));
    }
    speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(text);
    const v = bestVoice || pickVoice();
    u.lang = "de-DE";
    u.voice = v;
    // Ohne Männerstimme im System: vorhandene Stimme tiefer stellen
    u.pitch = isMale(v) ? 0.95 : 0.72;
    u.rate = 1.04;
    let bounded = false;
    u.onboundary = (e) => {
      bounded = true;
      J.kick = 0.8;
      revealTo(e.charIndex);
    };
    u.onend = finish;
    u.onerror = finish;
    // Ohne Wort-Ereignisse der Stimme: Untertitel im Sprechtempo einblenden
    let ci = 0;
    clearInterval(J.revealTimer);
    J.revealTimer = setInterval(() => {
      if (bounded) return clearInterval(J.revealTimer);
      ci += 7;
      revealTo(ci);
    }, 120);
    speechSynthesis.speak(u);
    J.sayTimer = setTimeout(finish, 2500 + text.length * 85); // Sicherheitsnetz, falls „end“ nie kommt
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
