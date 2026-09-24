// NOVA-Stimme: Sprechen (Sprachausgabe) und Zuhören (Spracherkennung) – robust auf iPhone, Android und Desktop.
// Erfahrungen aus Jarvis: im Tipp freischalten, Lautsprecher statt Hörer (iOS), Wachhund bei stummer Stimme,
// defekte Stimmen überspringen, Sätze einzeln sprechen.
import { store } from "./skills.js";

const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
export const IOS = /iP(hone|ad|od)/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
export const SAFARI = IOS || (/safari/i.test(navigator.userAgent) && !/(chrome|chromium|crios|fxios|edg|android)/i.test(navigator.userAgent));
export const canListen = !!SR;
export const canSpeak = "speechSynthesis" in window;

// ---------- Stimmen ----------
const HD = /(premium|enhanced|neural|natural|online)/i;
const MALE = /(markus|yannick|martin|viktor|conrad|killian|florian|bernd|christoph|kasper|ralf|klaus|jonas|stefan|hans|reed|rocko|eddy|male|mann)/i;
export const prefs = () => ({ voice: "", rate: 1, pitch: 1, ...store.get("voice", {}) });
export const setPrefs = (p) => store.set("voice", { ...prefs(), ...p });
export function voices() {
  if (!canSpeak) return [];
  return speechSynthesis
    .getVoices()
    .filter((v) => /^de([-_]|$)/i.test(v.lang))
    .sort((a, b) => HD.test(b.name) - HD.test(a.name) || a.name.localeCompare(b.name));
}
export const isHD = (v) => HD.test(v?.name || "");
export const isMale = (v) => MALE.test(v?.name || "");
let broken = "";
export function currentVoice() {
  const vs = voices().filter((v) => v.name !== broken);
  const want = prefs().voice;
  return vs.find((v) => v.name === want) || vs.find(isHD) || vs[0] || null;
}
if (canSpeak) speechSynthesis.addEventListener?.("voiceschanged", () => document.dispatchEvent(new Event("nova-voices")));

// iOS/Safari: Lautsprecher zum Sprechen, zum Zuhören entscheidet der Browser
function audioMode(type) {
  try {
    if (navigator.audioSession && navigator.audioSession.type !== type) navigator.audioSession.type = type;
  } catch (_) {
    /* ältere Browser */
  }
}
// Im Moment eines Tipps aufrufen – danach darf die Seite sprechen
export function unlock() {
  if (!canSpeak || S.ok) return;
  try {
    const u = new SpeechSynthesisUtterance(" ");
    u.volume = 0;
    speechSynthesis.speak(u);
  } catch (_) {
    /* ohne Sprachausgabe */
  }
}

// ---------- Sprechen ----------
const S = { token: 0, utts: [], ok: false, finish: null, mod: null };
export const speaking = () => canSpeak && (speechSynthesis.speaking || speechSynthesis.pending);
export function stopSpeaking() {
  S.token++;
  if (canSpeak) speechSynthesis.cancel();
  S.finish?.();
}
const ABBR = [
  [/\bz\.\s?B\./g, "zum Beispiel"],
  [/\bd\.\s?h\./g, "das heißt"],
  [/\bbzw\./g, "beziehungsweise"],
  [/\bca\./g, "circa"],
  [/\busw\./g, "und so weiter"],
  [/\bNr\./g, "Nummer"],
  [/\bMio\./g, "Millionen"],
  [/\bMrd\./g, "Milliarden"],
  [/°C?/g, " Grad"],
  [/(\d)\s?%/g, "$1 Prozent"],
  [/€/g, " Euro"],
];
const speakable = (t) =>
  ABBR.reduce((s, [re, w]) => s.replace(re, w), String(t))
    .replace(/https?:\/\/\S+/g, "")
    .replace(/[*_#`>|]/g, " ")
    .replace(/\p{Extended_Pictographic}|️/gu, "")
    .replace(/\s+/g, " ")
    .trim();
// opts: { onStart(sentence), onBoundary(charIndex), rate, pitch } – liefert ein Promise, das nach dem letzten Satz endet
export function speak(text, opts = {}) {
  text = speakable(text);
  return new Promise((resolve) => {
    const token = ++S.token;
    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      clearTimeout(S.dog);
      clearTimeout(S.net);
      resolve(S.ok);
    };
    S.finish = finish;
    if (!canSpeak || !text) return setTimeout(finish, 0);
    audioMode("playback");
    // Sätze (nur bei . ! ? mit Leerzeichen – „1.500“ bleibt ganz), sehr kurze an den nächsten hängen
    const parts = [];
    let start = 0;
    const push = (end) => {
      const t = text.slice(start, end);
      if (t.trim()) {
        const last = parts[parts.length - 1];
        if (last && last.length < 40) parts[parts.length - 1] = last + t;
        else parts.push(t);
      }
      start = end;
    };
    for (let i = 0; i < text.length; i++) if (".!?".includes(text[i]) && (i + 1 === text.length || /\s/.test(text[i + 1]))) push(i + 1);
    push(text.length);
    const p = prefs();
    const attempt = (v, retry) => {
      const run = (S.run = (S.run || 0) + 1);
      const live = () => !done && token === S.token && run === S.run;
      let left = parts.length;
      let started = false;
      const fallback = () => {
        if (!live()) return;
        S.run++;
        clearTimeout(S.dog);
        try {
          speechSynthesis.cancel();
        } catch (_) {
          /* nichts zu stoppen */
        }
        if (retry && v) {
          broken = v.name; // diese Stimme in der Sitzung meiden
          return setTimeout(() => token === S.token && !done && attempt(null, false), 120);
        }
        opts.onFail?.();
        S.net = setTimeout(finish, Math.min(6000, 400 + text.length * 40)); // Untertitel lesen lassen
      };
      S.utts = parts.map((t) => {
        const u = new SpeechSynthesisUtterance(t.trim());
        u.lang = v?.lang || "de-DE";
        try {
          if (v) u.voice = v;
        } catch (_) {
          /* Standardstimme */
        }
        u.rate = Math.min(1.6, Math.max(0.6, (opts.rate || 1) * p.rate));
        u.pitch = Math.min(2, Math.max(0.3, (opts.pitch || 1) * p.pitch));
        u.onstart = () => {
          if (!live()) return;
          started = true;
          S.ok = true;
          clearTimeout(S.dog);
          opts.onStart?.(t.trim());
        };
        u.onboundary = (e) => live() && opts.onBoundary?.(e.charIndex);
        u.onend = () => {
          if (!live()) return;
          if (--left <= 0) finish();
        };
        u.onerror = (e) => {
          if (!live()) return;
          if (!started && !/interrupted|canceled/.test(e.error || "")) return fallback();
          u.onend();
        };
        return u;
      });
      const go = () => {
        if (!live()) return;
        try {
          speechSynthesis.resume?.();
          for (const u of S.utts) speechSynthesis.speak(u);
        } catch (_) {
          fallback();
        }
      };
      if (speechSynthesis.speaking || speechSynthesis.pending) {
        speechSynthesis.cancel();
        setTimeout(go, 80);
      } else go();
      S.dog = setTimeout(() => !started && fallback(), 1800);
      clearTimeout(S.net);
      S.net = setTimeout(() => live() && finish(), 6000 + text.length * 90);
    };
    attempt(currentVoice(), true);
  });
}

// ---------- Zuhören ----------
// opts: { onInterim(text), fromTap } → Promise<{ text } | { error: "needs-tap" | "denied" | "none" }>
let rec = null;
export const listening = () => !!rec;
export function stopListening(finalize = true) {
  const r = rec;
  if (!r) return;
  try {
    finalize ? r.stop() : (rec = null, r.abort());
  } catch (_) {
    /* schon beendet */
  }
}
export function listen(opts = {}) {
  return new Promise((resolve) => {
    if (!SR) return resolve({ error: "none" });
    stopSpeaking();
    audioMode("auto");
    const r = new SR();
    r.lang = "de-DE";
    r.interimResults = true;
    r.continuous = !IOS;
    r.maxAlternatives = 1;
    let finals = "";
    let interim = "";
    let heard = false;
    let err = "";
    let timer = 0;
    const arm = (ms) => {
      clearTimeout(timer);
      timer = setTimeout(() => {
        try {
          r.stop();
        } catch (_) {
          /* beendet */
        }
      }, ms);
    };
    r.onstart = () => (heard = true);
    r.onresult = (e) => {
      interim = "";
      for (let i = e.resultIndex; i < e.results.length; i++) {
        if (e.results[i].isFinal) finals += e.results[i][0].transcript + " ";
        else interim += e.results[i][0].transcript;
      }
      opts.onInterim?.((finals + interim).trim());
      arm(interim ? 1400 : 850); // kurze Pause = fertig gesprochen
    };
    r.onerror = (e) => (err = e.error || "");
    r.onend = () => {
      clearTimeout(timer);
      if (rec === r) rec = null;
      const text = (finals + interim).trim();
      if (text) return resolve({ text });
      if (/not-allowed|service-not-allowed/.test(err)) return resolve({ error: heard || (SAFARI && !opts.fromTap) ? "needs-tap" : "denied" });
      resolve({ error: "silence" });
    };
    rec = r;
    arm(9000);
    try {
      r.start();
    } catch (_) {
      rec = null;
      resolve({ error: "needs-tap" });
    }
  });
}
