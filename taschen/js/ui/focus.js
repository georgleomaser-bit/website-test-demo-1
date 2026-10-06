// Arbeitstaschen – Fokus-Timer: Vollbild-Glas mit großem Ring-Countdown; Startzeit liegt im Speicher und überlebt Neustarts
import * as store from "../store.js";
import { esc } from "../util.js";
import { icon, CHECK } from "./icons.js";
import { app, on, render, bagVars, prefs, setPref } from "./core.js";
import { haptic, sound, toast, confetti } from "./fx.js";

let timer = null; // { taskId, start, minutes, pausedAt, pausedMs, finished }
let tick = 0;
let wake = null;
const R = 120, C = 2 * Math.PI * R;

const el = () => document.getElementById("focus");

// ---------- Zustand ----------
function save() {
  store.kvSet("timer", timer).catch(() => {});
}

function remaining() {
  if (!timer) return 0;
  const now = timer.pausedAt || Date.now();
  return Math.max(0, timer.minutes * 60000 - (now - timer.start - (timer.pausedMs || 0)));
}

export async function restoreFocus() {
  try {
    const t = await store.kvGet("timer");
    if (t && t.taskId && store.task(t.taskId) && !store.task(t.taskId).done) {
      timer = t;
      show();
    }
  } catch (_) {
    /* kein Timer gespeichert */
  }
}

export function startFocus(id, minutes) {
  const t = store.task(id);
  if (!t) return;
  minutes = minutes || prefs.focusMin || 25;
  timer = { taskId: id, start: Date.now(), minutes, pausedAt: null, pausedMs: 0, finished: false };
  save();
  haptic();
  show();
}

export const focusActive = () => !!timer;

function stop() {
  timer = null;
  store.kvSet("timer", null).catch(() => {});
  clearInterval(tick);
  releaseWake();
  const f = el();
  if (!f) return;
  f.classList.remove("open");
  setTimeout(() => {
    if (!timer) {
      f.hidden = true;
      f._html = null;
      f.innerHTML = "";
    }
  }, 420);
  document.documentElement.classList.remove("focus-on");
}

// ---------- Darstellung ----------
function fmt(ms) {
  const s = Math.ceil(ms / 1000);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

function html() {
  if (!timer) return "";
  const t = store.task(timer.taskId);
  if (!t) return "";
  const bag = t.bag ? store.bag(t.bag) : null;
  const rem = remaining();
  const frac = rem / (timer.minutes * 60000);
  const subs = t.subtasks || [];
  const paused = !!timer.pausedAt;
  return `<div class="fx-in" style="${bagVars(bag)}" data-key="fx-${t.id}">
<div class="fx-bg" aria-hidden="true"><i></i><i></i></div>
<header class="fx-top"><button type="button" class="btn-glass" data-act="focus-close">${icon("x")}<span>Beenden</span></button><div class="fx-mins" role="group" aria-label="Dauer">${[15, 25, 50].map((m) => `<button type="button" class="${timer.minutes === m ? "on" : ""}" data-act="focus-min" data-m="${m}">${m}</button>`).join("")}</div></header>
<div class="fx-mid">
<p class="fx-bag">${bag ? `${esc(bag.emoji)} ${esc(bag.name)}` : "📥 Eingang"}</p>
<h2 class="fx-title">${esc(t.title)}</h2>
<div class="fx-ring${paused ? " paused" : ""}${timer.finished ? " finished" : ""}"><svg viewBox="0 0 260 260" aria-hidden="true"><circle class="fx-track" cx="130" cy="130" r="${R}"/><circle class="fx-prog" cx="130" cy="130" r="${R}" stroke-dasharray="${C.toFixed(1)}" stroke-dashoffset="${(C * (1 - frac)).toFixed(1)}" transform="rotate(-90 130 130)"/></svg><div class="fx-time"><b data-fx-time>${timer.finished ? "Zeit!" : fmt(rem)}</b><small>${timer.finished ? "Gut gemacht" : paused ? "Pausiert" : "Fokus"}</small></div></div>
<div class="fx-ctrl">
${timer.finished ? `<button type="button" class="btn-glass" data-act="focus-more">${icon("plus")}<span>+5 Min.</span></button>` : `<button type="button" class="btn-glass" data-act="focus-pause">${icon(paused ? "play" : "pause")}<span>${paused ? "Weiter" : "Pause"}</span></button>`}
<button type="button" class="btn-glass primary" data-act="focus-done">${icon("check")}<span>Erledigt</span></button>
</div>
${subs.length ? `<div class="fx-subs">${subs.map((x) => `<button type="button" class="fx-sub${x.done ? " done" : ""}" data-key="fs-${x.id}" data-act="focus-sub" data-sub="${x.id}"><span class="check small">${CHECK}</span><span>${esc(x.title)}</span></button>`).join("")}</div>` : ""}
</div>
</div>`;
}

function paint() {
  const f = el();
  if (!f || !timer) return;
  render(f, html());
}

function show() {
  const f = el();
  if (!f) return;
  f.hidden = false;
  paint();
  document.documentElement.classList.add("focus-on");
  requestAnimationFrame(() => requestAnimationFrame(() => f.classList.add("open")));
  clearInterval(tick);
  tick = setInterval(update, 1000);
  update();
  requestWake();
}

// Jede Sekunde nur Zeit und Ring aktualisieren (kein komplettes Neuzeichnen)
function update() {
  if (!timer) return;
  const f = el();
  const rem = remaining();
  if (rem <= 0 && !timer.finished) {
    timer.finished = true;
    save();
    sound("timer");
    paint();
    toast("Fokuszeit vorbei", { icon: "target", sub: "Erledigt? Dann abhaken!", ms: 5000 });
    notifyIfHidden();
    return;
  }
  const b = f?.querySelector("[data-fx-time]");
  if (b && !timer.finished) b.textContent = fmt(rem);
  const prog = f?.querySelector(".fx-prog");
  if (prog) prog.setAttribute("stroke-dashoffset", (C * (1 - rem / (timer.minutes * 60000))).toFixed(1));
  document.title = timer.finished || timer.pausedAt ? "Arbeitstaschen" : `${fmt(rem)} · Fokus`;
}

function notifyIfHidden() {
  try {
    if (document.visibilityState === "visible" || typeof Notification === "undefined" || Notification.permission !== "granted") return;
    const t = store.task(timer?.taskId);
    navigator.serviceWorker?.ready.then((r) => r.showNotification("Fokuszeit vorbei", { body: t ? t.title : "", tag: "taschen-focus", icon: "icons/icon-192.png" })).catch(() => {});
  } catch (_) {
    /* keine Mitteilung */
  }
}

// ---------- Bildschirm wach halten ----------
async function requestWake() {
  try {
    if ("wakeLock" in navigator && document.visibilityState === "visible" && !wake) {
      wake = await navigator.wakeLock.request("screen");
      wake.addEventListener?.("release", () => (wake = null));
    }
  } catch (_) {
    wake = null;
  }
}
function releaseWake() {
  try {
    wake?.release?.();
  } catch (_) {
    /* schon frei */
  }
  wake = null;
}
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && timer) {
    requestWake();
    update();
  }
});

// Speicher-Änderungen (z. B. Unteraufgabe abgehakt) spiegeln
export function refreshFocus() {
  if (!timer) return;
  const t = store.task(timer.taskId);
  if (!t) {
    stop();
    return;
  }
  paint();
}

// ---------- Ereignisse ----------
on("click", {
  "focus-close": () => {
    stop();
    document.title = "Arbeitstaschen";
  },
  "focus-pause": () => {
    if (!timer) return;
    if (timer.pausedAt) {
      timer.pausedMs = (timer.pausedMs || 0) + (Date.now() - timer.pausedAt);
      timer.pausedAt = null;
    } else timer.pausedAt = Date.now();
    haptic();
    save();
    paint();
    update();
  },
  "focus-min": (b) => {
    if (!timer) return;
    const m = Number(b.dataset.m);
    setPref("focusMin", m);
    timer.minutes = m;
    timer.start = Date.now();
    timer.pausedAt = null;
    timer.pausedMs = 0;
    timer.finished = false;
    haptic();
    save();
    paint();
    update();
  },
  "focus-more": () => {
    if (!timer) return;
    timer.minutes += 5;
    timer.finished = false;
    save();
    paint();
    update();
  },
  "focus-done": () => {
    if (!timer) return;
    const id = timer.taskId;
    haptic(true);
    sound("all");
    try {
      const t = store.task(id);
      if (t && !t.done) store.completeTask(id);
      confetti();
      toast("Erledigt – stark!", { icon: "trophy", sub: t ? t.title : "" });
    } catch (e) {
      console.error(e);
    }
    stop();
    document.title = "Arbeitstaschen";
  },
  "focus-sub": (b) => {
    if (!timer) return;
    store.toggleSubtask(timer.taskId, b.dataset.sub);
    haptic();
  },
});

export const focusTaskId = () => timer?.taskId || null;
void app;
