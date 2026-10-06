// Arbeitstaschen – Rückmeldung: Haptik, leise Töne, Insel-Toasts (Dynamic Island), Erinnerungs-Banner und Konfetti
import * as store from "../store.js";
import { esc } from "../util.js";
import { icon } from "./icons.js";
import { reducedMotion } from "./core.js";

// ---------- Haptik ----------
// iOS 17.4+: ein verstecktes <input type="checkbox" switch> per label.click() löst das Taptic-Feedback aus (nur in einer Nutzergeste)
export function haptic(strong = false) {
  const p = store.get()?.profile;
  if (p && p.haptics === false) return;
  try {
    if (typeof navigator.vibrate === "function" && !/iP(hone|ad|od)|Macintosh/.test(navigator.userAgent)) navigator.vibrate(strong ? 16 : 8);
    else document.getElementById("haptic")?.click();
  } catch (_) {
    /* ohne Haptik */
  }
}

// ---------- Töne (sehr kurz und leise, per Web Audio) ----------
let ac = null;
export function sound(kind = "done") {
  const p = store.get()?.profile;
  if (p && p.sounds === false) return;
  try {
    if (!ac) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return;
      try {
        if (navigator.audioSession) navigator.audioSession.type = "ambient"; // Stummschalter respektieren, Musik nicht unterbrechen
      } catch (_) {
        /* ältere Safari */
      }
      ac = new AC();
    }
    if (ac.state === "suspended") ac.resume().catch(() => {});
    const notes = kind === "all" ? [784, 988, 1175, 1568] : kind === "soft" ? [660] : kind === "timer" ? [880, 660, 880] : [1046.5, 1568];
    const t0 = ac.currentTime + 0.01;
    notes.forEach((f, i) => {
      const t = t0 + i * (kind === "timer" ? 0.22 : 0.075);
      const o = ac.createOscillator();
      const g = ac.createGain();
      o.type = "sine";
      o.frequency.setValueAtTime(f, t);
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(kind === "soft" ? 0.03 : 0.05, t + 0.012);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 0.24);
      o.connect(g).connect(ac.destination);
      o.start(t);
      o.stop(t + 0.26);
    });
  } catch (_) {
    /* ohne Ton */
  }
}

// ---------- Insel (Toast oben in der Mitte) ----------
let hideT = 0;
let current = null;
const island = () => document.getElementById("island");

export function toast(text, { icon: ic = "check", action = null, ms = 3200, tone = "", sub = "" } = {}) {
  const el = island();
  if (!el) return;
  clearTimeout(hideT);
  current = { kind: "toast" };
  el.className = "island";
  el.innerHTML = `<span class="isl-ico ${tone}">${icon(ic)}</span><span class="isl-text"><b>${esc(text)}</b>${sub ? `<small>${esc(sub)}</small>` : ""}</span>${action ? `<button class="isl-btn" type="button">${esc(action.label)}</button>` : ""}`;
  if (action) {
    el.querySelector(".isl-btn").addEventListener("click", (e) => {
      e.stopPropagation();
      hideToast();
      try {
        action.fn();
      } catch (err) {
        console.error(err);
      }
    });
  }
  el.hidden = false;
  requestAnimationFrame(() => requestAnimationFrame(() => el.classList.add("show")));
  hideT = setTimeout(hideToast, action ? Math.max(ms, 5200) : ms);
}

export function hideToast() {
  const el = island();
  if (!el) return;
  clearTimeout(hideT);
  el.classList.remove("show");
  el.classList.add("hide");
  const me = current;
  setTimeout(() => {
    if (current === me && !el.classList.contains("show")) {
      el.hidden = true;
      el.className = "island";
      current = null;
    }
  }, 420);
}

// Fehler freundlich anzeigen
export function toastError(err, prefix = "") {
  const msg = (err && (err.message || String(err))) || "Unbekannter Fehler";
  toast(prefix ? `${prefix}: ${msg}` : msg, { icon: "info", tone: "red", ms: 5200 });
}

// Toast mit „Rückgängig“ (store.undo)
export function toastUndo(text, { icon: ic = "check", tone = "", sub = "", undo = null } = {}) {
  toast(text, {
    icon: ic,
    tone,
    sub,
    action: {
      label: "Rückgängig",
      fn: () => {
        if (undo) {
          undo();
          toast("Rückgängig gemacht", { icon: "undo" });
          return;
        }
        const l = store.undo();
        if (l) toast(`Rückgängig: ${l}`, { icon: "undo" });
      },
    },
  });
}

// ---------- Erinnerungs-Banner (Insel wird größer) ----------
// buttons: [{ label, fn, primary }]
export function banner({ title, body = "", emoji = "🔔", buttons = [], ms = 14000 }) {
  const el = island();
  if (!el) return;
  clearTimeout(hideT);
  current = { kind: "banner" };
  el.className = "island banner";
  el.innerHTML = `<div class="bn-row"><span class="bn-emoji">${esc(emoji)}</span><span class="bn-text"><b>${esc(title)}</b>${body ? `<small>${esc(body)}</small>` : ""}</span><button class="bn-x" type="button" aria-label="Schließen">${icon("x")}</button></div>${buttons.length ? `<div class="bn-btns">${buttons.map((b, i) => `<button type="button" class="bn-btn${b.primary ? " primary" : ""}" data-i="${i}">${esc(b.label)}</button>`).join("")}</div>` : ""}`;
  el.querySelector(".bn-x").addEventListener("click", hideToast);
  el.querySelectorAll(".bn-btn").forEach((btn) =>
    btn.addEventListener("click", () => {
      hideToast();
      try {
        buttons[+btn.dataset.i].fn();
      } catch (err) {
        console.error(err);
      }
    }),
  );
  el.hidden = false;
  requestAnimationFrame(() => requestAnimationFrame(() => el.classList.add("show")));
  hideT = setTimeout(hideToast, ms);
}

// ---------- Konfetti ----------
let confettiRun = 0;
export function confetti({ x = null, y = null, colors = null, count = 150 } = {}) {
  if (reducedMotion()) return;
  const cv = document.getElementById("confetti");
  if (!cv || !cv.getContext) return;
  const ctx = cv.getContext("2d");
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  const W = window.innerWidth, H = window.innerHeight;
  cv.width = W * dpr;
  cv.height = H * dpr;
  cv.hidden = false;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  const cs = getComputedStyle(document.documentElement);
  const accent = cs.getPropertyValue("--accent").trim() || "#007AFF";
  const pal = colors && colors.length ? colors : [accent, "#FF9500", "#34C759", "#FF2D55", "#AF52DE", "#FFCC00", "#5AC8FA"];
  const ox = x ?? W / 2, oy = y ?? H * 0.32;
  const parts = Array.from({ length: count }, (_, i) => {
    const a = -Math.PI / 2 + (Math.random() - 0.5) * Math.PI * 1.15;
    const v = 7 + Math.random() * 11;
    return { x: ox, y: oy, vx: Math.cos(a) * v * (0.6 + Math.random() * 0.6), vy: Math.sin(a) * v - 2, w: 5 + Math.random() * 6, h: 8 + Math.random() * 8, r: Math.random() * Math.PI, vr: (Math.random() - 0.5) * 0.4, c: pal[i % pal.length], round: Math.random() < 0.28, tilt: Math.random() * 6 };
  });
  const run = ++confettiRun;
  const t0 = performance.now();
  const step = (t) => {
    if (run !== confettiRun) return;
    const age = t - t0;
    ctx.clearRect(0, 0, W, H);
    for (const p of parts) {
      p.vy += 0.32;
      p.vx *= 0.985;
      p.vy *= 0.985;
      p.x += p.vx + Math.sin((age / 180) + p.tilt) * 0.6;
      p.y += p.vy;
      p.r += p.vr;
      const fade = age > 2200 ? Math.max(0, 1 - (age - 2200) / 900) : 1;
      ctx.globalAlpha = fade;
      ctx.save();
      ctx.translate(p.x, p.y);
      ctx.rotate(p.r);
      ctx.fillStyle = p.c;
      if (p.round) {
        ctx.beginPath();
        ctx.arc(0, 0, p.w / 2, 0, Math.PI * 2);
        ctx.fill();
      } else ctx.fillRect(-p.w / 2, -p.h / 2, p.w, p.h * Math.abs(Math.cos(p.r * 1.3)) + 2);
      ctx.restore();
    }
    if (age < 3100) requestAnimationFrame(step);
    else {
      ctx.clearRect(0, 0, W, H);
      cv.hidden = true;
    }
  };
  requestAnimationFrame(step);
}
