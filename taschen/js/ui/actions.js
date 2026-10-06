// Arbeitstaschen – gemeinsame Aktionen für Aufgaben: abhaken (mit Animation), verschieben, löschen, Kontextmenü, Sammelaktionen
import * as store from "../store.js";
import * as dates from "../dates.js";
import * as pm from "../pm.js";
import { PRIOS } from "../config.js";
import { app, on, today, tomorrow, weekendISO, nextWeekISO, toggleCollapsed, safe } from "./core.js";
import { pending } from "./components.js";
import { haptic, sound, toast, toastUndo, toastError, confetti } from "./fx.js";
import { openMenu, closeSheet, confirmBox } from "./sheet.js";
import { openTask, closeTaskIfOpen } from "./task.js";
import { startFocus } from "./focus.js";
import { COLORS } from "../config.js";

// ---------- Abhaken mit Feder-Animation ----------
export function toggleTask(id) {
  const t = store.task(id);
  if (!t) return;
  if (t.done) {
    haptic();
    sound("soft");
    try {
      store.reopenTask(id);
    } catch (e) {
      toastError(e);
    }
    return;
  }
  if (pending.has(id)) {
    // zweites Tippen während der Animation = doch nicht erledigt
    clearTimeout(pending.get(id));
    pending.delete(id);
    document.querySelectorAll(`[data-task="${CSS.escape(id)}"]`).forEach((r) => {
      r.removeAttribute("data-hold");
      r.classList.remove("leaving");
    });
    app.render();
    return;
  }
  haptic();
  sound("done");
  pending.set(
    id,
    setTimeout(() => {
      document.querySelectorAll(`[data-task="${CSS.escape(id)}"]`).forEach((r) => {
        if (r.closest(".sheet, .inspector")) return;
        r.setAttribute("data-hold", "");
        r.style.setProperty("--h", r.offsetHeight + "px");
        r.classList.add("leaving");
      });
      pending.set(id, setTimeout(() => commitDone(id), 300));
    }, 560),
  );
  app.render();
}

function commitDone(id) {
  pending.delete(id);
  const s0 = store.get();
  const badgeBefore = safe(() => pm.badgeCount(s0, new Date()), 0);
  const t = store.task(id);
  let r = null;
  try {
    r = store.completeTask(id);
  } catch (e) {
    toastError(e);
  }
  document.querySelectorAll(`[data-task="${CSS.escape(id)}"][data-hold]`).forEach((row) => row.removeAttribute("data-hold"));
  if (!r || !t) return;
  const s1 = store.get();
  const now = new Date();
  let sub = t.title;
  if (r.next?.due) sub = `Nächstes Mal: ${safe(() => dates.relDay(r.next.due, now), r.next.due)}`;
  toastUndo("Erledigt", { sub });
  // Feiern: Tag geschafft oder Tasche komplett
  const badgeAfter = safe(() => pm.badgeCount(s1, now), 1);
  if (badgeBefore > 0 && badgeAfter === 0) {
    setTimeout(() => {
      confetti();
      sound("all");
      toast("Alles für heute erledigt!", { icon: "trophy", sub: "Stark – genieß den Feierabend 🎉", ms: 4200 });
    }, 250);
  } else if (t.bag) {
    const st = safe(() => pm.bagStats(s1, t.bag, now), null);
    if (st && st.total > 2 && st.open === 0) {
      const bag = store.bag(t.bag);
      const c = COLORS[bag?.color] || COLORS.blue;
      setTimeout(() => {
        confetti({ colors: [c[0], c[1], "#FFFFFF", "#FFCC00"] });
        sound("all");
        toast(`${bag?.emoji || "👜"} ${bag?.name || "Tasche"}: 100 %`, { icon: "trophy", sub: "Alle Aufgaben erledigt!", ms: 4200 });
      }, 250);
    }
  }
}

// ---------- Einzelaktionen ----------
export function planToday(id) {
  const t = store.task(id);
  if (!t) return;
  const on = t.plan === today();
  store.planTask(id, on ? null : today());
  haptic();
  toast(on ? "Aus Heute entfernt" : "Für heute eingeplant", { icon: on ? "star" : "starFill" });
}

export function setDue(id, iso, label) {
  const t = store.task(id);
  if (!t) return;
  const patch = { due: iso, someday: iso ? false : t.someday };
  if (t.plan && iso && t.plan < iso) patch.plan = null;
  store.updateTask(id, patch);
  haptic();
  toastUndo(label || (iso ? `Fällig: ${safe(() => dates.relDay(iso, app.now), iso)}` : "Datum entfernt"), { icon: "calendar" });
}

export function deleteTask(id) {
  const t = store.task(id);
  if (!t) return;
  store.removeTask(id);
  closeTaskIfOpen(id);
  haptic(true);
  toastUndo("Aufgabe gelöscht", { icon: "trash", tone: "red", sub: t.title });
}

export function duplicateTask(id) {
  const t = store.task(id);
  if (!t) return null;
  const copy = store.addTask({
    bag: t.bag, title: t.title, notes: t.notes, prio: t.prio, due: t.due, time: t.time, remind: t.remind, repeat: t.repeat, section: t.section,
    tags: [...(t.tags || [])], plan: t.plan, someday: t.someday, est: t.est, waiting: t.waiting, milestone: t.milestone,
  });
  for (const s of t.subtasks || []) safe(() => store.addSubtask(copy.id, s.title));
  toastUndo("Dupliziert", { icon: "copy", sub: t.title });
  return copy;
}

export function moveTo(id, bagId, section = "") {
  const t = store.task(id);
  if (!t) return;
  store.moveTask(id, bagId, section);
  const bag = bagId ? store.bag(bagId) : null;
  haptic();
  toastUndo(bag ? `→ ${bag.emoji} ${bag.name}` : "→ Eingang", { icon: "arrowRight", sub: t.title });
}

// ---------- Sammelaktionen mit eigenem Rückgängig ----------
export function batch(tasks, patchFn, label, ic = "calendar") {
  const prev = [];
  for (const t of tasks) {
    const patch = patchFn(t);
    if (!patch) continue;
    const old = {};
    for (const k of Object.keys(patch)) old[k] = t[k] ?? null;
    prev.push([t.id, old]);
    safe(() => store.updateTask(t.id, patch));
  }
  if (!prev.length) return;
  haptic();
  toastUndo(label.replace("{n}", prev.length), { icon: ic, undo: () => prev.forEach(([id, old]) => safe(() => store.updateTask(id, old))) });
}

export function allToToday(tasks) {
  batch(tasks, (t) => ({ due: today(), someday: false }), "{n} auf heute geholt");
}

export function rescheduleMenu(tasks, opts = {}) {
  const items = [
    { label: "Heute", icon: "starFill", run: () => batch(tasks, () => ({ due: today(), someday: false }), "{n} auf heute") },
    { label: "Morgen", icon: "sunrise", run: () => batch(tasks, () => ({ due: tomorrow(), someday: false }), "{n} auf morgen") },
    { label: "Am Wochenende", icon: "calendar", run: () => batch(tasks, () => ({ due: weekendISO(), someday: false }), "{n} aufs Wochenende") },
    { label: "Nächste Woche", icon: "calendarPlus", run: () => batch(tasks, () => ({ due: nextWeekISO(), someday: false }), "{n} auf nächste Woche") },
    "-",
    { label: "Irgendwann", icon: "moon", run: () => batch(tasks, () => ({ due: null, time: null, someday: true, plan: null }), "{n} auf irgendwann") },
    { label: "Datum entfernen", icon: "x", run: () => batch(tasks, () => ({ due: null, time: null }), "{n} ohne Datum") },
  ];
  openMenu(items, { ...opts, title: tasks.length > 1 ? `${tasks.length} Aufgaben verschieben` : "Verschieben" });
}

// ---------- Kontextmenü einer Aufgabe ----------
export function taskMenuItems(id) {
  const t = store.task(id);
  if (!t) return [];
  const isToday = t.plan === today();
  const bags = store.bags();
  return [
    { label: t.done ? "Wieder öffnen" : "Erledigt", icon: t.done ? "undo" : "checkCircle", run: () => toggleTask(id) },
    { label: isToday ? "Aus Heute entfernen" : "Für heute einplanen", icon: isToday ? "star" : "starFill", run: () => planToday(id) },
    "-",
    { label: "Heute fällig", icon: "sun", run: () => setDue(id, today(), "Heute fällig") },
    { label: "Morgen", icon: "sunrise", run: () => setDue(id, tomorrow(), "Auf morgen verschoben") },
    { label: "Nächste Woche", icon: "calendarPlus", run: () => setDue(id, nextWeekISO(), "Auf nächste Woche verschoben") },
    { label: "Irgendwann", icon: "moon", run: () => { store.updateTask(id, { someday: true, due: null, time: null, plan: null }); toastUndo("Auf irgendwann verschoben", { icon: "moon" }); } },
    "-",
    { label: "Priorität", icon: "flag", sub: PRIOS.slice().reverse().map((p) => ({ label: p.label + (p.mark ? "  " + p.mark : ""), check: t.prio === p.id, run: () => { store.updateTask(id, { prio: p.id }); haptic(); } })) },
    { label: "Verschieben nach", icon: "bag", sub: [{ label: "Eingang", emoji: "📥", check: !t.bag, run: () => moveTo(id, null) }, ...bags.map((b) => ({ label: b.name, emoji: b.emoji, check: t.bag === b.id, run: () => moveTo(id, b.id) }))] },
    !t.done ? { label: "Fokus starten", icon: "target", run: () => startFocus(id) } : null,
    { label: "Duplizieren", icon: "copy", run: () => duplicateTask(id) },
    "-",
    { label: "Löschen", icon: "trash", danger: true, run: () => deleteTask(id) },
  ].filter(Boolean);
}

export function taskMenu(id, pos = {}) {
  const t = store.task(id);
  if (!t) return;
  openMenu(taskMenuItems(id), { ...pos, title: t.title.length > 42 ? t.title.slice(0, 40) + " …" : t.title });
}

// ---------- Registrierung ----------
on("click", {
  toggle: (el) => toggleTask(el.dataset.id),
  task: (el) => openTask(el.dataset.id),
  "task-plan": (el) => planToday(el.dataset.id),
  "task-tomorrow": (el) => setDue(el.dataset.id, tomorrow(), "Auf morgen verschoben"),
  "task-delete": (el) => deleteTask(el.dataset.id),
  "task-menu": (el) => taskMenu(el.dataset.id, { el }),
  "task-focus": (el) => startFocus(el.dataset.id),
  collapse: (el) => toggleCollapsed(el.dataset.k, el.dataset.def === "1"),
  "sheet-close": () => closeSheet(),
  go: (el) => app.go(el.dataset.to),
  back: () => app.back(),
  undo: () => {
    const l = store.undo();
    toast(l ? `Rückgängig: ${l}` : "Nichts zum Rückgängigmachen", { icon: "undo" });
  },
});

on("menu", {
  task: (el, pos) => taskMenu(el.dataset.id, pos),
});

// Bestätigtes Löschen (z. B. aus dem Detail)
export async function confirmDelete(id) {
  const t = store.task(id);
  if (!t) return;
  if (await confirmBox({ title: "Aufgabe löschen?", text: t.title, ok: "Löschen", danger: true })) deleteTask(id);
}
