// Arbeitstaschen – geführter Wochenrückblick: Erfolge, Eingang, Überfälliges, Taschen-Check, nächste Woche
import * as store from "../store.js";
import * as dates from "../dates.js";
import * as pm from "../pm.js";
import { esc } from "../util.js";
import { icon } from "./icons.js";
import { app, on, safe, bagVars, today, tomorrow, nextWeekISO, setPref } from "./core.js";
import { taskRow, ring, healthPill, empty, largeTitle, bar } from "./components.js";
import { haptic, toast, confetti, sound } from "./fx.js";
import { moveTo, deleteTask } from "./actions.js";
import { askAI } from "./aiui.js";

const STEPS = [
  { id: "wins", label: "Erfolge", icon: "trophy" },
  { id: "inbox", label: "Eingang", icon: "tray" },
  { id: "overdue", label: "Überfällig", icon: "flag" },
  { id: "bags", label: "Taschen", icon: "bag" },
  { id: "next", label: "Nächste Woche", icon: "target" },
];

let rv = { step: 0, picked: new Set(), cheered: false };

export function title() {
  return "Wochenrückblick";
}

function data() {
  return safe(() => pm.weeklyReview(store.get(), app.now), null) || { range: { from: today(), to: today() }, done: [], created: 0, perBag: [], stalled: [], overdue: [], noDate: 0, inbox: 0, wins: [], questions: [] };
}

export function render() {
  const w = data();
  const step = STEPS[rv.step] || STEPS[0];
  const from = safe(() => dates.fmtDay(w.range.from, { weekday: false }), w.range.from);
  const to = safe(() => dates.fmtDay(w.range.to, { weekday: false }), w.range.to);
  let h = largeTitle("Wochenrückblick", { sub: `${esc(from)} – ${esc(to)}`, key: "lt-rv" });
  h += `<nav class="rv-dots" data-key="rv-dots" aria-label="Schritte">${STEPS.map((s, i) => `<button type="button" class="rv-dot${i === rv.step ? " on" : i < rv.step ? " done" : ""}" data-act="rv-go" data-i="${i}" aria-label="${esc(s.label)}"${i === rv.step ? ' aria-current="step"' : ""}><span>${i < rv.step ? icon("check") : icon(s.icon)}</span><small>${esc(s.label)}</small></button>`).join("")}</nav>`;
  let body = "";
  try {
    body = { wins, inbox, overdue, bags, next }[step.id](w);
  } catch (e) {
    console.error(e);
    body = `<div class="note-box red">${esc(e.message)}</div>`;
  }
  const last = rv.step === STEPS.length - 1;
  h += `<div class="rv-body" data-key="rv-${step.id}">${body}</div>`;
  h += `<div class="rv-nav" data-key="rv-nav">${rv.step ? `<button type="button" class="btn" data-act="rv-prev">${icon("chevronLeft")}<span>Zurück</span></button>` : `<span></span>`}${last ? `<button type="button" class="btn primary" data-act="rv-finish">${icon("check")}<span>Rückblick abschließen</span></button>` : `<button type="button" class="btn primary" data-act="rv-next"><span>Weiter</span>${icon("chevronRight")}</button>`}</div>`;
  return `<div class="view view-review" data-key="view-review">${h}</div>`;
}

// ---------- Schritte ----------
function wins(w) {
  const done = w.done || [];
  if (done.length && !rv.cheered) {
    rv.cheered = true;
    setTimeout(() => confetti({ count: 110 }), 350);
  }
  const per = (w.perBag || []).filter((x) => x.done);
  const max = Math.max(1, ...per.map((x) => x.done));
  return `<section class="rv-hero"><div class="rv-big">${done.length}</div><div><h2>${done.length ? (done.length === 1 ? "Aufgabe erledigt" : "Aufgaben erledigt") : "Diese Woche war ruhig"}</h2><p>${w.created ? `${w.created} neu dazugekommen · ` : ""}${done.length ? "Stark – nimm dir einen Moment, das zu sehen." : "Kein Problem – nächste Woche packen wir’s an."}</p></div></section>
${(w.wins || []).length ? `<div class="card list rv-wins">${w.wins.map((x) => `<div class="win">${icon("trophy")}<span>${esc(x)}</span></div>`).join("")}</div>` : ""}
${per.length ? `<h3 class="ov-h">Nach Taschen</h3><div class="card rv-bars">${per.map((x) => { const b = x.bag && typeof x.bag === "object" ? x.bag : store.bag(x.bag); return b ? `<div class="rv-bar" style="${bagVars(b)}"><span>${esc(b.emoji)} ${esc(b.name)}</span>${bar((x.done / max) * 100, "bagc")}<b>${x.done}</b></div>` : ""; }).join("")}</div>` : ""}
${done.length ? `<h3 class="ov-h">Erledigt</h3><div class="card list">${done.slice(0, 12).map((t) => taskRow(t)).join("")}${done.length > 12 ? `<p class="fine center">… und ${done.length - 12} weitere</p>` : ""}</div>` : ""}`;
}

function inbox() {
  const items = store.tasks().filter((t) => !t.bag && !t.done);
  if (!items.length) return empty({ emoji: "📭", title: "Eingang ist leer", text: "Perfekt – nichts zu sortieren. Weiter geht’s." });
  const s = store.get();
  return `<p class="rv-lead">${items.length} ${items.length === 1 ? "Eintrag wartet" : "Einträge warten"}. Sortiere ein, plane oder lösche – in 2 Minuten ist der Kopf frei.</p><div class="card list">${items
    .map((t) => {
      const r = safe(() => pm.suggestBag(t.title, s), null);
      const b = r && r.bag ? (typeof r.bag === "string" ? store.bag(r.bag) : store.bag(r.bag.id)) : null;
      const extra = `<div class="in-sug">${b ? `<button type="button" class="sg" data-act="rv-move" data-id="${t.id}" data-bag="${b.id}" style="${bagVars(b)}">${icon("arrowRight")}<span>${esc(b.emoji)} ${esc(b.name)}</span></button>` : ""}<button type="button" class="sg ghost" data-act="inbox-pick" data-id="${t.id}">${icon("bag")}<span>Tasche</span></button><button type="button" class="sg ghost" data-act="rv-del" data-id="${t.id}">${icon("trash")}<span>Weg</span></button></div>`;
      return taskRow(t, { bag: false, extra, cls: "in-row" });
    })
    .join("")}</div>`;
}

function overdue() {
  const items = store.tasks().filter((t) => !t.done && t.due && t.due < today());
  if (!items.length) return empty({ emoji: "✅", title: "Nichts überfällig", text: "Alles im Plan. Sehr gut." });
  const btn = (id, v, l, cls = "") => `<button type="button" class="sg${cls ? " " + cls : ""}" data-act="rv-re" data-id="${id}" data-v="${v}">${l}</button>`;
  return `<p class="rv-lead">Entscheide für jede Aufgabe neu – ehrlich und schnell.</p><div class="card list">${items
    .map((t) => taskRow(t, { extra: `<div class="in-sug wrap">${btn(t.id, "today", "Heute")}${btn(t.id, "tomorrow", "Morgen")}${btn(t.id, "week", "Nächste Woche")}${btn(t.id, "someday", "Irgendwann", "ghost")}${btn(t.id, "done", "Erledigt", "green")}${btn(t.id, "delete", "Löschen", "red")}</div>`, cls: "in-row" }))
    .join("")}</div>`;
}

function bags(w) {
  const list = store.bags().filter((b) => b.status === "aktiv");
  if (!list.length) return empty({ emoji: "👜", title: "Keine aktiven Taschen", text: "Leg eine Tasche an, damit ich sie für dich im Blick behalte." });
  const s = store.get();
  return `<p class="rv-lead">Wie steht jedes Projekt? Ein Blick genügt – tippe auf eine Tasche, um nachzuschärfen.</p><div class="rv-bags">${list
    .map((b) => {
      const st = safe(() => pm.bagStats(s, b.id, app.now), null) || { pct: 0, open: 0, overdue: 0 };
      const steps = safe(() => pm.nextSteps(s, b.id, app.now), []) || [];
      return `<button type="button" class="rv-bag" data-act="go" data-to="#tasche/${b.id}" style="${bagVars(b)}"><div class="rv-bag-top"><span class="bsq"><span>${esc(b.emoji)}</span></span><span class="rv-bag-t"><b>${esc(b.name)}</b><span>${healthPill(st)}</span></span>${ring(st.pct, { size: 42, stroke: 4.5 })}</div>${st.healthReason ? `<p class="rv-reason">${esc(st.healthReason)}</p>` : ""}${steps[0] ? `<p class="rv-step">${icon("arrowRight")}<span>${esc(steps[0].text)}</span></p>` : ""}<small>${st.open} offen${st.overdue ? ` · <span class="red">${st.overdue} überfällig</span>` : ""}</small></button>`;
    })
    .join("")}</div>${(w.stalled || []).length ? `<p class="fine">${icon("zzz")} Ruhig geworden: ${w.stalled.map((x) => esc((typeof x.bag === "object" ? x.bag : store.bag(x.bag))?.name || "")).filter(Boolean).join(", ")}</p>` : ""}`;
}

function next(w) {
  const tdy = today();
  const nw = nextWeekISO();
  const horizon = dates.addDays(tdy, 14);
  const cands = store
    .tasks()
    .filter((t) => !t.done && !t.someday && !t.waiting && (t.prio >= 2 || (t.due && t.due <= horizon)))
    .sort((a, b) => (b.prio || 0) - (a.prio || 0) || String(a.due || "9999").localeCompare(String(b.due || "9999")))
    .slice(0, 14);
  return `<p class="rv-lead">Wähle bis zu 3 Dinge, die nächste Woche wirklich zählen. Ich plane sie dir für ${esc(safe(() => dates.fmtDay(nw), nw))} ein.</p>
<div class="card list rv-pick">${cands
    .map((t) => {
      const on = rv.picked.has(t.id) || t.plan === nw;
      const bag = t.bag ? store.bag(t.bag) : null;
      return `<button type="button" class="pick${on ? " on" : ""}" data-key="rp-${t.id}" data-act="rv-pick" data-id="${t.id}" aria-pressed="${on}" style="${bagVars(bag)}"><span class="pick-box">${icon("starFill")}</span><span class="pick-t">${esc(t.title)}<small>${bag ? esc(bag.emoji + " " + bag.name) : "Eingang"}${t.due ? " · " + esc(safe(() => dates.relDay(t.due, app.now), t.due)) : ""}</small></span></button>`;
    })
    .join("") || `<p class="fine center">Keine dringenden Kandidaten – nimm dir etwas aus deinen Taschen vor.</p>`}</div>
${(w.questions || []).length ? `<h3 class="ov-h">${icon("sparkle")} Fragen an dich</h3><div class="card list rv-q">${w.questions.map((q) => `<p>${esc(q)}</p>`).join("")}</div>` : ""}
${app.ai ? `<button type="button" class="btn ai wide" data-act="rv-ai">${icon("sparkle")}<span>KI-PM: Wochenplan vorschlagen</span></button>` : ""}`;
}

// ---------- Ereignisse ----------
function go(i) {
  rv.step = Math.max(0, Math.min(STEPS.length - 1, i));
  haptic();
  app.render();
  window.scrollTo({ top: 0, behavior: "smooth" });
}

export function resetReview() {
  rv = { step: 0, picked: new Set(), cheered: false };
}

on("click", {
  "rv-go": (el) => go(+el.dataset.i),
  "rv-next": () => go(rv.step + 1),
  "rv-prev": () => go(rv.step - 1),
  "rv-move": (el) => moveTo(el.dataset.id, el.dataset.bag),
  "rv-del": (el) => deleteTask(el.dataset.id),
  "rv-re": (el) => {
    const id = el.dataset.id, v = el.dataset.v;
    const t = store.task(id);
    if (!t) return;
    haptic();
    if (v === "done") return store.completeTask(id);
    if (v === "delete") return deleteTask(id);
    const patch = v === "today" ? { due: today() } : v === "tomorrow" ? { due: tomorrow() } : v === "week" ? { due: nextWeekISO() } : { due: null, time: null, someday: true, plan: null };
    store.updateTask(id, patch);
  },
  "rv-pick": (el) => {
    const id = el.dataset.id;
    const nw = nextWeekISO();
    const t = store.task(id);
    if (rv.picked.has(id) || t?.plan === nw) {
      rv.picked.delete(id);
      if (t?.plan === nw) store.planTask(id, null);
    } else {
      if (rv.picked.size >= 3) {
        toast("Maximal 3 – Fokus heißt weglassen", { icon: "target" });
        return;
      }
      rv.picked.add(id);
    }
    haptic();
    app.render();
  },
  "rv-ai": () => askAI({ kind: "weekly", title: "Wochenplan", question: "Was sollte ich nächste Woche angehen? Gib mir einen fokussierten Plan." }),
  "rv-finish": () => {
    const nw = nextWeekISO();
    for (const id of rv.picked) if (store.task(id)) store.planTask(id, nw);
    const n = rv.picked.size;
    store.setMeta({ lastReview: today() });
    safe(() => (typeof store.addLog === "function" ? store.addLog("review", n ? `Wochenrückblick abgeschlossen · ${n} Fokus-Aufgaben für nächste Woche` : "Wochenrückblick abgeschlossen") : null));
    setPref("lastReviewDone", today());
    resetReview();
    confetti();
    sound("all");
    toast("Rückblick abgeschlossen", { icon: "trophy", sub: n ? `${n} Fokus-Aufgaben für nächste Woche geplant` : "Gutes Wochenende!", ms: 4200 });
    app.go("#heute");
  },
});

