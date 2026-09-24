// Jarvis: der Sprachmodus von AKYTEX AI (Tarif Ultra).
// Leuchtende Bildschirmränder, Zuhören per Spracherkennung, gesprochene Antworten mit Untertiteln
// und Vorschläge, die man antippt oder mit „Ja“ bestätigt. Geld bewegt Jarvis nie per Sprache.
const $ = (s, r = document) => r.querySelector(s);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
const IOS = /iP(hone|ad|od)/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
const TRIAL_KEY = "akytex-jarvis-trial";
export const TRIAL_TURNS = 3;

const J = { deps: null, on: false, state: "off", rec: null, lvl: 0, kick: 0, raf: 0, mic: null, an: null, ctx: null, buf: null, silent: 0, pending: null, greeted: false, idleTimer: 0, sayTimer: 0, words: [], thinkGlow: false };

export const jarvisSupported = () => !!SR;
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

// ---------- Stimme ----------
let bestVoice = null;
export function pickVoice() {
  if (!("speechSynthesis" in window)) return null;
  const vs = speechSynthesis.getVoices().filter((v) => /^de([-_]|$)/i.test(v.lang));
  const score = (v) => (/(premium|enhanced|neural|natural|online)/i.test(v.name) ? 4 : 0) + (/google/i.test(v.name) ? 3 : 0) + (/(anna|helena|petra|markus|yannick|katja|conrad|amala|seraphina|florian|katharina)/i.test(v.name) ? 2 : 0) + (v.localService ? 0 : 1);
  bestVoice = vs.sort((a, b) => score(b) - score(a))[0] || null;
  return bestVoice;
}
if ("speechSynthesis" in window) {
  pickVoice();
  speechSynthesis.addEventListener?.("voiceschanged", pickVoice);
}
// HTML-Antwort in gut sprechbaren Text verwandeln (kurz halten – Details stehen im Chat)
export function toSpeech(html, max = 420) {
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
  for (const s of sentences) {
    if (out && (out + s).length > max) return { text: out.trim(), cut: true };
    out += s;
  }
  return { text: out.trim(), cut: false };
}

// ---------- Oberfläche ----------
function build() {
  const el = document.createElement("div");
  el.className = "jv";
  el.id = "jv";
  el.hidden = true;
  el.innerHTML = `<div class="jv-edge" aria-hidden="true"></div><div class="jv-edge jv-soft" aria-hidden="true"></div>
    <div class="jv-card" role="dialog" aria-label="Jarvis – Sprachmodus">
      <div class="jv-top"><span class="jv-orb" aria-hidden="true"><i></i><i></i><i></i></span><span class="jv-state" aria-live="polite">Ich höre zu …</span><button class="jv-chat" data-jv="chat" title="Im Chat weiterlesen">Chat</button><button class="jv-x" data-jv="close" aria-label="Jarvis beenden">✕</button></div>
      <p class="jv-you"></p>
      <p class="jv-say" aria-live="polite"></p>
      <div class="jv-acts"></div>
      <p class="jv-hint">Sag z. B. „Was soll ich heute tun?“, „Zeig mir Nvidia“ oder „Wie steht mein Depot?“</p>
    </div>`;
  document.body.appendChild(el);
  el.querySelector(".jv-card").addEventListener("click", onCard);
  return el;
}
const root = () => $("#jv") || build();
function setState(s, label) {
  J.state = s;
  const el = root();
  el.dataset.state = s;
  el.querySelector(".jv-state").textContent = label || { listen: "Ich höre zu …", think: "Denke nach …", speak: "Jarvis", idle: "Tippe hier, um weiterzusprechen", upsell: "Jarvis" }[s] || "";
}
function onCard(e) {
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
  if (b?.dataset.jvAct != null) {
    const a = J.actions?.[+b.dataset.jvAct];
    if (a) J.deps.runAction(a, b);
    return;
  }
  // Antippen: unterbrechen und zuhören (oder aus dem Ruhezustand weitermachen)
  if (J.state === "speak" || J.state === "idle") {
    speechSynthesis?.cancel();
    clearTimeout(J.sayTimer);
    listen();
  }
}
function showYou(t) {
  root().querySelector(".jv-you").textContent = t ? `„${t}“` : "";
}
function showSay(text) {
  const box = root().querySelector(".jv-say");
  let i = 0;
  J.words = [];
  box.innerHTML = text
    .split(/(\s+)/)
    .map((w) => {
      if (!w.trim()) return w;
      J.words.push(i);
      const s = `<span data-i="${i}">${esc(w)}</span>`;
      i += w.length + 1;
      return s;
    })
    .join("");
  // Wortpositionen im Originaltext für die Synchronisierung mit der Stimme
  let pos = 0;
  box.querySelectorAll("span").forEach((sp) => {
    const at = text.indexOf(sp.textContent, pos);
    sp.dataset.i = at;
    pos = at + sp.textContent.length;
  });
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

// ---------- Leuchten ----------
function loop(now) {
  J.raf = requestAnimationFrame(loop);
  if (now - (J.last || 0) < 33) return;
  J.last = now;
  const t = now / 1000;
  let target = 0.12;
  if (J.state === "listen") {
    let mic = 0;
    if (J.an) {
      J.an.getByteTimeDomainData(J.buf);
      let sum = 0;
      for (const v of J.buf) sum += (v - 128) ** 2;
      mic = Math.min(1, Math.sqrt(sum / J.buf.length) / 22);
    }
    target = 0.3 + mic * 0.7 + J.kick * 0.4 + 0.05 * Math.sin(t * 2.2);
  } else if (J.state === "think") target = 0.42 + 0.18 * Math.sin(t * 5);
  else if (J.state === "speak") target = 0.45 + 0.2 * Math.sin(t * 7.3) * Math.sin(t * 2.1) + J.kick * 0.35;
  else if (J.state === "idle") target = 0.14;
  if (J.thinkGlow && !J.on) target = 0.3 + 0.12 * Math.sin(t * 4);
  J.kick *= 0.86;
  J.lvl += (Math.max(0, Math.min(1, target)) - J.lvl) * 0.22;
  root().style.setProperty("--lvl", J.lvl.toFixed(3));
}
function startLoop() {
  if (!J.raf) J.raf = requestAnimationFrame(loop);
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
// Sanftes Leuchten, während AKYTEX AI im Chat nachdenkt
export function thinkGlow(on) {
  if (J.on) return;
  J.thinkGlow = on;
  const el = root();
  if (on) {
    el.hidden = false;
    el.classList.add("glow-only");
    requestAnimationFrame(() => el.classList.add("on"));
    startLoop();
  } else if (!J.on) {
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
  if (!SR) {
    d.toast("Der Sprachmodus braucht Spracherkennung – nutze Chrome, Edge oder Safari. Du kannst Jarvis im Chat auch schreiben.", "info", "🎙 Jarvis");
    return d.openChat();
  }
  if (!d.allowed() && !trialLeft()) return upsellCard(true);
  J.on = true;
  J.silent = 0;
  const el = root();
  el.hidden = false;
  el.classList.remove("glow-only");
  document.documentElement.classList.add("jv-open");
  requestAnimationFrame(() => el.classList.add("on"));
  showYou("");
  showActions([]);
  startLoop();
  d.haptic?.([10, 40, 10]);
  const name = d.name();
  const hi = !J.greeted ? `${new Date().getHours() < 11 ? "Guten Morgen" : new Date().getHours() < 18 ? "Hallo" : "Guten Abend"}${name ? " " + name : ""}. Was kann ich für dich tun?` : "Ich höre.";
  J.greeted = true;
  const trial = !d.allowed() ? ` Du hast ${trialLeft()} Gratis-Fragen.` : "";
  startMeter();
  await speakOut(hi + trial, hi + trial);
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
  clearTimeout(J.sayTimer);
  clearTimeout(J.idleTimer);
  stopMeter();
  const el = root();
  el.classList.remove("on");
  document.documentElement.classList.remove("jv-open");
  setTimeout(() => {
    if (J.on || J.thinkGlow) return;
    el.hidden = true;
    stopLoop();
  }, 550);
}

function listen() {
  if (!J.on) return;
  clearTimeout(J.idleTimer);
  setState("listen");
  let final = "";
  let interim = "";
  const rec = new SR();
  rec.lang = "de-DE";
  rec.interimResults = true;
  rec.maxAlternatives = 1;
  rec.onsoundstart = () => (J.kick = 0.6);
  rec.onresult = (e) => {
    interim = "";
    for (let i = e.resultIndex; i < e.results.length; i++) {
      if (e.results[i].isFinal) final += e.results[i][0].transcript;
      else interim += e.results[i][0].transcript;
    }
    J.kick = 1;
    showYou((final + interim).trim());
  };
  rec.onerror = (e) => {
    if (e.error === "not-allowed" || e.error === "service-not-allowed") {
      J.deps.toast("Bitte erlaube den Zugriff aufs Mikrofon, damit Jarvis dich hören kann.", "error", "🎙 Mikrofon");
      stopJarvis();
    }
  };
  rec.onend = () => {
    if (J.rec !== rec) return;
    J.rec = null;
    if (!J.on) return;
    const text = (final || interim).trim();
    if (text) {
      J.silent = 0;
      return handle(text);
    }
    if (++J.silent >= 2) return idle();
    listen();
  };
  J.rec = rec;
  try {
    rec.start();
  } catch (_) {
    setTimeout(listen, 300);
  }
}
function idle() {
  setState("idle");
  clearTimeout(J.idleTimer);
  J.idleTimer = setTimeout(stopJarvis, 25000);
}

const YES = /^(ja|jo|jep|jap|klar|gerne|gern|ok(ay)?|mach( das| es)?|los|bitte|genau|auf jeden)\b/i;
const NO = /^(nein|nee|ne|nö|lieber nicht|abbrechen)\b/i;
const BYE = /^(stopp?|danke( dir| schön)?|tschüss|tschau|ciao|ende|beenden|schließen|das wars?|das war's|bis später)\b/i;
// Was per Sprache bestätigt werden darf: nichts, was Geld bewegt oder handelt
export const voiceSafe = (a) => !!a && !(a.side || a.fund || a.schedule || /kauf|verkauf|order|zahl|einzahl|auszahl|abo|bestell|handel|ausführ/i.test(a.label || ""));

async function handle(text) {
  const d = J.deps;
  const t = text.toLowerCase().trim();
  if (BYE.test(t)) {
    await speakOut("Gern geschehen. Ich bin da, wenn du mich brauchst.");
    return stopJarvis();
  }
  if (J.pending && YES.test(t)) {
    const a = J.pending;
    J.pending = null;
    const btn = root().querySelector(`[data-jv-act="${J.actions.indexOf(a)}"]`) || document.createElement("button");
    d.runAction(a, btn);
    await speakOut("Erledigt.");
    return J.on && listen();
  }
  if (J.pending && NO.test(t)) {
    J.pending = null;
    await speakOut("Alles klar.");
    return J.on && listen();
  }
  J.pending = null;
  const free = !d.allowed();
  if (free && !trialLeft()) return upsellCard(false);
  setState("think");
  showActions([]);
  root().querySelector(".jv-say").textContent = "";
  let reply;
  try {
    reply = await d.ask(text);
  } catch (e) {
    reply = { html: `<p>Das hat gerade nicht geklappt: ${esc(e.message)}</p>` };
  }
  if (!J.on) return;
  if (free) useTrial();
  const { text: said, cut } = toSpeech(reply?.html || "Dazu habe ich gerade keine Antwort.");
  const acts = (reply?.actions || []).filter((a) => a.label);
  showActions(acts);
  const offerable = (a) => voiceSafe(a) && !/rückgängig/i.test(a.label);
  const offer = acts.find((a) => a.primary && offerable(a)) || acts.find(offerable);
  J.pending = offer || null;
  const money = acts.find((a) => !voiceSafe(a));
  const tail = offer ? ` Sag „ja“, und ich mache: ${offer.label}.` : money ? " Bestätige das bitte per Tipp auf den Button." : cut ? " Mehr steht im Chat." : "";
  await speakOut(said + tail);
  if (!J.on) return;
  if (free && !trialLeft()) return upsellCard(false);
  listen();
}

function speakOut(text, caption = text) {
  return new Promise((resolve) => {
    setState("speak");
    showSay(caption);
    clearTimeout(J.sayTimer);
    const finish = () => {
      clearTimeout(J.sayTimer);
      clearInterval(J.revealTimer);
      revealTo(1e9);
      resolve();
    };
    if (!("speechSynthesis" in window)) {
      revealTo(1e9);
      return setTimeout(resolve, Math.min(6000, 600 + text.length * 45));
    }
    speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(text);
    u.lang = "de-DE";
    u.voice = bestVoice || pickVoice();
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
  const d = J.deps;
  const el = root();
  el.hidden = false;
  el.classList.remove("glow-only");
  requestAnimationFrame(() => el.classList.add("on"));
  J.on = true;
  startLoop();
  setState("upsell");
  showYou("");
  root().querySelector(".jv-say").innerHTML = `<b>${fromStart ? "Jarvis gehört zu AKYTEX Ultra." : "Das waren deine Gratis-Fragen."}</b> Mit Ultra sprichst du unbegrenzt mit mir: Lagebericht, nächste Schritte und die ganze App per Stimme.`;
  root().querySelector(".jv-acts").innerHTML = `<button class="btn primary small" data-jv="plans">✦ Ultra ansehen</button>`;
  if (!fromStart) speakOut("Das waren deine Gratis-Fragen. Mit AKYTEX Ultra sprichst du unbegrenzt mit mir.", root().querySelector(".jv-say").textContent).then(() => J.on && idle());
  else idle();
}
