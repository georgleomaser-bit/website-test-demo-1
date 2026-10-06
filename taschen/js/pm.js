// Arbeitstaschen – der Projektmanager: feste Regeln für Fokus, Briefing, Gesundheit, Rückblick und Erinnerungsplan (reine Funktionen, kein DOM)
import { DEFAULT_PROFILE } from "./config.js";
import { todayISO, toISO, addDays, diffDays, weekday, startOfWeek, nextOccurrence, remindAt, relDay, dateLabel, greeting, daypart, fmtTime, fmtDuration, fmtNumber, parseTime, atLocal, isISO, matchBag } from "./dates.js";

// ---------- Grundlagen ----------
const DAY = 86400000;
export const DEFAULT_EST = 30; // Aufgaben ohne Schätzung zählen bei Auslastung/Kapazität mit 30 Min.
const live = (arr) => (Array.isArray(arr) ? arr.filter((e) => e && !e.deleted) : []);
const clamp01 = (x) => Math.max(0, Math.min(1, x));
const est = (t) => (Number.isFinite(t?.est) && t.est > 0 ? t.est : DEFAULT_EST);

// Texthelfer: „3 Aufgaben“, „eine Aufgabe“, Titel in deutschen Anführungszeichen, gekürzt auf 40 Zeichen
export const plural = (n, sg, pl) => `${n} ${n === 1 ? sg : pl}`;
const trunc = (s, max = 40) => {
  const t = String(s ?? "").trim();
  return t.length > max ? t.slice(0, max - 1).trimEnd() + "…" : t;
};
const q = (s, max = 40) => `„${trunc(s, max)}“`;
const joinDe = (arr) => (arr.length <= 1 ? arr.join("") : arr.slice(0, -1).join(", ") + " und " + arr[arr.length - 1]);
const hours = (min) => {
  const h = Math.round((min / 60) * 2) / 2;
  return h < 1 ? fmtDuration(Math.round(min)) : `${fmtNumber(h)} Std.`;
};
// "heute fällig", "morgen fällig", "fällig am Freitag", "seit 3 Tagen überfällig"
function dueText(iso, now) {
  const d = diffDays(todayISO(now), iso);
  if (d < 0) return d === -1 ? "seit gestern überfällig" : `seit ${-d} Tagen überfällig`;
  if (d <= 2) return `${["heute", "morgen", "übermorgen"][d]} fällig`;
  return `fällig am ${relDay(iso, now)}`;
}
const relDeadline = (n) => (n === 0 ? "heute" : n === 1 ? "morgen" : `in ${n} Tagen`);
const daysText = (n) => (n === 0 ? "heute" : n === 1 ? "morgen" : n === -1 ? "seit gestern" : n < 0 ? `seit ${-n} Tagen` : `in ${n} Tagen`);

// Kontext für einen Aufruf: alles einmal vorberechnen (Zustand wird vom Store in place geändert – daher kein Cache über Aufrufe hinweg)
function makeCtx(state, now = new Date()) {
  const n = now instanceof Date && !Number.isNaN(now.getTime()) ? now : new Date();
  const profile = { ...DEFAULT_PROFILE, ...(state?.profile || {}) };
  const tasks = live(state?.tasks);
  const bags = live(state?.bags);
  const C = {
    state: state || {},
    now: n,
    nowMs: n.getTime(),
    today: todayISO(n),
    profile,
    bags,
    bagsById: new Map(bags.map((b) => [b.id, b])),
    tasks,
    open: tasks.filter((t) => !t.done),
    milestones: live(state?.milestones),
    msById: null,
    stats: new Map(),
  };
  C.msById = new Map(C.milestones.map((m) => [m.id, m]));
  return C;
}
const bagOf = (C, t) => (t?.bag ? C.bagsById.get(t.bag) || null : null);
const bagActive = (C, t) => {
  const b = bagOf(C, t);
  return !b || b.status === "aktiv";
};
const isWorkday = (C, iso) => (Array.isArray(C.profile.workdays) ? C.profile.workdays : [1, 2, 3, 4, 5]).includes(weekday(iso));
const isPlanned = (C, t) => !!t.plan && t.plan <= C.today;
const isOverdue = (C, t) => !t.done && !!t.due && t.due < C.today;
const bagName = (b) => (b ? `${b.emoji || "👜"} ${b.name}` : "Eingang");

// Reihenfolge innerhalb eines Tages: Uhrzeit, dann Priorität, dann Sortierung
const byDay = (a, b) => (a.time || "99").localeCompare(b.time || "99") || (b.prio || 0) - (a.prio || 0) || (a.order || 0) - (b.order || 0);
const byDue = (a, b) => (a.due || "9999").localeCompare(b.due || "9999") || (b.prio || 0) - (a.prio || 0) || (a.created || 0) - (b.created || 0);

// ---------- Taschen-Statistik & Gesundheit ----------
// Gesundheit (nur aktive Taschen) – Start bei 100 Punkten, Abzüge:
//   Fristen überschritten          15 je Aufgabe, max. 45
//   Liegengeblieben (plan ≥ 3 T.)   5 je Aufgabe, max. 20
//   Meilenstein-Verzug             (Zeitanteil − Erledigt-Anteil − 10 %) · 80, max. 40 (nur mit verknüpften Aufgaben)
//   Deadline-Verzug der Tasche     (Zeitanteil − Erledigt-Anteil − 15 %) · 60, max. 30
//   Stillstand                     3 je Tag über 7 Tage ohne Aktivität, max. 45
//   Kein nächster Schritt          15 (offene Aufgaben, aber alle warten/irgendwann)
// ≥ 70 „gut“, 40–69 „achtung“, < 40 „kritisch“; eine überschrittene Frist bedeutet mindestens „achtung“.
// Harte Regeln: Meilenstein oder Deadline überschritten → „kritisch“;
// pausiert, leer oder ≥ 30 Tage ruhig ohne Druck → „ruhend“; Status „fertig“ → „fertig“.
function nextStepOf(C, bagId, b) {
  const secIdx = (s) => {
    const i = (b?.sections || []).indexOf(s || "");
    return i < 0 ? (s ? 999 : -1) : i;
  };
  const avail = C.open.filter((t) => (t.bag || null) === (bagId || null) && !t.waiting && !t.someday);
  avail.sort((x, y) => (x.due || "9999").localeCompare(y.due || "9999") || (x.plan || "9999").localeCompare(y.plan || "9999") || (y.prio || 0) - (x.prio || 0) || secIdx(x.section) - secIdx(y.section) || (x.order || 0) - (y.order || 0));
  return avail[0] || null;
}

function statsFor(C, bagId) {
  const key = bagId || null;
  if (C.stats.has(key)) return C.stats.get(key);
  const { today } = C;
  const b = key ? C.bagsById.get(key) || null : null;
  const ts = C.tasks.filter((t) => (t.bag || null) === key);
  const open = ts.filter((t) => !t.done);
  const done = ts.filter((t) => t.done);
  const counted = ts.filter((t) => t.done || !t.someday);
  const pct = counted.length ? Math.round((done.length / counted.length) * 100) : b?.status === "fertig" ? 100 : 0;
  const overdue = open.filter((t) => t.due && t.due < today);
  const dueToday = open.filter((t) => t.due === today);
  const weekEnd = addDays(today, 7);
  const dueWeek = open.filter((t) => t.due && t.due >= today && t.due <= weekEnd);
  const waiting = open.filter((t) => t.waiting).length;

  // Letzte Aktivität: jüngste Änderung an Tasche, Aufgaben, Notizen, Links, Dateien, Meilensteinen
  let last = 0;
  const bump = (e) => (last = Math.max(last, e.updated || 0, e.created || 0, typeof e.done === "number" ? e.done : 0));
  for (const c of ["tasks", "notes", "links", "files", "milestones"]) for (const e of live(C.state[c])) if ((e.bag || null) === key) bump(e);
  if (b) bump(b);
  const lastActivity = last || null;
  const idleDays = last ? Math.max(0, diffDays(toISO(last), today)) : 0;

  const next = nextStepOf(C, key, b);
  const deadlineIn = b?.deadline ? diffDays(today, b.deadline) : null;
  const ms = C.milestones.filter((m) => (m.bag || null) === key && !m.done).sort((x, y) => (x.date || "9999").localeCompare(y.date || "9999") || (x.created || 0) - (y.created || 0));
  const nextMilestone = ms[0] || null;

  // Abzüge sammeln (Text + Punkte)
  const pen = [];
  if (overdue.length) pen.push({ p: Math.min(45, 15 * overdue.length), text: `${plural(overdue.length, "Frist", "Fristen")} überschritten` });
  const stale = open.filter((t) => !(t.due && t.due < today) && t.plan && diffDays(t.plan, today) >= 3).length;
  if (stale) pen.push({ p: Math.min(20, 5 * stale), text: `${plural(stale, "Aufgabe liegt", "Aufgaben liegen")} seit Tagen` });
  let msLate = false;
  if (nextMilestone?.date) {
    if (nextMilestone.date < today) msLate = true;
    const linked = ts.filter((t) => t.milestone === nextMilestone.id && !t.someday);
    if (linked.length && !msLate) {
      const actual = linked.filter((t) => t.done).length / linked.length;
      const start = toISO(nextMilestone.created || C.nowMs);
      const elapsed = clamp01(diffDays(start, today) / Math.max(1, diffDays(start, nextMilestone.date)));
      const p = Math.min(40, Math.round(Math.max(0, elapsed - actual - 0.1) * 80));
      if (p > 0) pen.push({ p, text: `Meilenstein ${q(nextMilestone.title, 30)}: ${Math.round(actual * 100)} % erledigt, ${Math.round(elapsed * 100)} % der Zeit vorbei` });
    }
  }
  const deadlineLate = deadlineIn !== null && deadlineIn < 0 && open.length > 0;
  if (deadlineIn !== null && deadlineIn >= 0 && counted.length && b) {
    const start = toISO(b.created || C.nowMs);
    const elapsed = clamp01(diffDays(start, today) / Math.max(1, diffDays(start, b.deadline)));
    const p = Math.min(30, Math.round(Math.max(0, elapsed - pct / 100 - 0.15) * 60));
    if (p > 0) pen.push({ p, text: `Deadline ${daysText(deadlineIn)}, erst ${pct} % erledigt` });
  }
  if (open.length && idleDays > 7) pen.push({ p: Math.min(45, 3 * (idleDays - 7)), text: `Seit ${idleDays} Tagen nichts passiert` });
  if (open.length && !next) pen.push({ p: 15, text: waiting ? "Alles wartet auf andere – Zeit nachzuhaken" : "Kein nächster Schritt festgelegt" });
  pen.sort((x, y) => y.p - x.p);
  const score = Math.max(0, 100 - pen.reduce((s, x) => s + x.p, 0));

  let health, healthLabel, healthReason;
  const status = b?.status || "aktiv";
  if (status === "fertig") {
    health = "fertig";
    healthLabel = "Fertig";
    healthReason = done.length ? `Abgeschlossen – ${plural(done.length, "Aufgabe", "Aufgaben")} erledigt 🎉` : "Abgeschlossen 🎉";
  } else if (status === "pausiert") {
    health = "ruhend";
    healthLabel = "Pausiert";
    healthReason = overdue.length ? `Pausiert – aber ${plural(overdue.length, "Frist", "Fristen")} überschritten` : "Pausiert – nichts drängt";
  } else if (!ts.length) {
    health = "ruhend";
    healthLabel = "Noch leer";
    healthReason = "Leg den ersten Schritt fest";
  } else if (msLate || deadlineLate) {
    health = "kritisch";
    healthLabel = "Kritisch";
    healthReason = msLate ? `Meilenstein ${q(nextMilestone.title, 30)} überfällig` : `Deadline seit ${plural(-deadlineIn, "Tag", "Tagen")} überschritten`;
  } else if (!open.length) {
    health = idleDays >= 21 ? "ruhend" : "gut";
    healthLabel = idleDays >= 21 ? "Ruhend" : "Gut";
    healthReason = idleDays >= 21 ? "Keine offenen Aufgaben – pausieren oder nächsten Schritt festlegen?" : "Alles erledigt – nächstes Ziel oder „Fertig“?";
  } else if (idleDays >= 30 && !overdue.length && !(deadlineIn !== null && deadlineIn <= 14)) {
    health = "ruhend";
    healthLabel = "Ruhend";
    healthReason = `Seit ${idleDays} Tagen ruhig – pausieren oder kleinen Schritt planen?`;
  } else {
    health = score >= 70 && !overdue.length ? "gut" : score >= 40 ? "achtung" : "kritisch";
    healthLabel = { gut: "Gut", achtung: "Achtung", kritisch: "Kritisch" }[health];
    if (health !== "gut") healthReason = pen[0].text;
    else if (deadlineIn !== null && deadlineIn >= 0 && deadlineIn <= 14) healthReason = `Deadline ${relDeadline(deadlineIn)} – du liegst im Plan`;
    else healthReason = done.length ? `Läuft – ${done.length} von ${counted.length} erledigt` : `Startklar – ${plural(open.length, "Aufgabe", "Aufgaben")} geplant`;
  }

  const out = {
    total: ts.length, open: open.length, done: done.length, pct, overdue: overdue.length, dueToday: dueToday.length, dueWeek: dueWeek.length,
    lastActivity, idleDays, health, healthLabel, healthReason, next, deadlineIn, nextMilestone, waiting,
    score, reasons: pen.slice(0, 2).map((x) => x.text),
  };
  C.stats.set(key, out);
  return out;
}

export function bagStats(state, bagId, now = new Date()) {
  return statsFor(makeCtx(state, now), bagId);
}

// ---------- Fokus ----------
/*
 * Fokus-Score – je höher, desto eher gehört die Aufgabe heute in den Fokus:
 *   Frist      überfällig 100 + 5·min(Tage, 10) | heute 90 | morgen 70 | in 2–3 Tagen 50 | in 4–7 Tagen 30 | später 10 | ohne 0
 *   Eingeplant plan ≤ heute: 40 + 3·min(Tage seit Einplanung, 10)
 *   Priorität  hoch 30 | mittel 18 | niedrig 8
 *   Meilenstein verknüpfter Meilenstein in ≤ 7 Tagen +20 | ≤ 14 Tagen +10
 *   Tasche     Gesundheit kritisch +10 | achtung +5; Tasche pausiert/fertig −20
 *   Größe      ≤ 15 Min. +5 (schneller Erfolg) | > 180 Min. −10 (erst zerlegen)
 *   Schwung    Unteraufgaben teilweise erledigt +5
 *   Alter      +1 je Woche seit Anlage, max. +5 (nichts verstaubt ewig)
 *   Dämpfer    wartet auf jemanden −40 | irgendwann −30
 */
function scoreParts(C, t) {
  const { today } = C;
  const parts = { deadline: 0, planned: 0, prio: 0, milestone: 0, bag: 0, size: 0, momentum: 0, age: 0, damp: 0 };
  if (t.due) {
    const dd = diffDays(today, t.due);
    parts.deadline = dd < 0 ? 100 + 5 * Math.min(-dd, 10) : dd === 0 ? 90 : dd === 1 ? 70 : dd <= 3 ? 50 : dd <= 7 ? 30 : 10;
  }
  if (isPlanned(C, t)) parts.planned = 40 + 3 * Math.min(diffDays(t.plan, today), 10);
  parts.prio = [0, 8, 18, 30][t.prio || 0] || 0;
  const m = t.milestone ? C.msById.get(t.milestone) : null;
  if (m && !m.done && m.date) {
    const md = diffDays(today, m.date);
    parts.milestone = md <= 7 ? 20 : md <= 14 ? 10 : 0;
  }
  const b = bagOf(C, t);
  if (b) {
    if (b.status !== "aktiv") parts.bag = -20;
    else {
      const h = statsFor(C, b.id).health;
      parts.bag = h === "kritisch" ? 10 : h === "achtung" ? 5 : 0;
    }
  }
  if (Number.isFinite(t.est)) parts.size = t.est <= 15 ? 5 : t.est > 180 ? -10 : 0;
  const subs = Array.isArray(t.subtasks) ? t.subtasks : [];
  if (subs.some((s) => s.done) && subs.some((s) => !s.done)) parts.momentum = 5;
  if (t.created) parts.age = Math.min(5, Math.floor((C.nowMs - t.created) / (7 * DAY)));
  if (t.waiting) parts.damp -= 40;
  if (t.someday) parts.damp -= 30;
  return parts;
}
const sumParts = (p) => Object.values(p).reduce((s, x) => s + x, 0);

export function focusScore(task, state, now = new Date()) {
  if (!task) return 0;
  return sumParts(scoreParts(makeCtx(state, now), task));
}

// Kann die Aufgabe heute in den Fokus? (offen, nicht wartend, keine feste Uhrzeit in der Zukunft, Tasche aktiv oder Frist nah)
function focusable(C, t) {
  if (t.done || t.waiting) return false;
  const planned = isPlanned(C, t);
  if (t.someday && !planned && !(t.due && t.due <= C.today)) return false;
  if (t.time && t.due && t.due >= C.today && !planned) return false; // Termine gehören in den Zeitplan
  if (!bagActive(C, t) && !planned && !(t.due && t.due <= addDays(C.today, 3))) return false;
  return true;
}
const tieBreak = (a, b) => (a.due || "9999").localeCompare(b.due || "9999") || (b.prio || 0) - (a.prio || 0) || (a.created || 0) - (b.created || 0) || (a.id < b.id ? -1 : 1);

function focusIn(C, n) {
  const count = Math.max(0, Math.min(20, Number.isFinite(n) ? Math.floor(n) : Number(C.profile.focusCount) || 3));
  if (!count) return [];
  const scored = C.open.filter((t) => focusable(C, t)).map((t) => ({ t, s: sumParts(scoreParts(C, t)) }));
  const sortFn = (a, b) => b.s - a.s || tieBreak(a.t, b.t);
  const planned = scored.filter((x) => isPlanned(C, x.t)).sort(sortFn);
  const rest = scored.filter((x) => !isPlanned(C, x.t));
  const soon = addDays(C.today, 7);
  const near = (t) => {
    const m = t.milestone ? C.msById.get(t.milestone) : null;
    return (t.due && t.due <= soon) || t.prio === 3 || (m && !m.done && m.date && m.date <= addDays(C.today, 14));
  };
  let cands = rest.filter((x) => near(x.t)).sort(sortFn);
  if (planned.length + cands.length < count) cands = [...cands, ...rest.filter((x) => !near(x.t)).sort(sortFn)];
  const pick = planned.slice(0, count).map((x) => x.t);
  // Vielfalt: höchstens zwei Aufgaben aus derselben Tasche, solange es Alternativen gibt
  const perBag = new Map();
  for (const t of pick) perBag.set(t.bag || null, (perBag.get(t.bag || null) || 0) + 1);
  const skipped = [];
  for (const x of cands) {
    if (pick.length >= count) break;
    const k = x.t.bag || null;
    if ((perBag.get(k) || 0) >= 2) {
      skipped.push(x.t);
      continue;
    }
    pick.push(x.t);
    perBag.set(k, (perBag.get(k) || 0) + 1);
  }
  for (const t of skipped) if (pick.length < count) pick.push(t);
  return pick;
}

export function focus(state, now = new Date(), n) {
  const C = makeCtx(state, now);
  return focusIn(C, n ?? C.profile.focusCount);
}

// Warum diese Aufgabe zuerst? (für den Satz „Fang mit … an – …“)
function whyFirst(C, t) {
  const { today } = C;
  if (t.due && t.due < today) {
    const d = diffDays(t.due, today);
    return d === 1 ? "das ist seit gestern überfällig" : `das ist seit ${d} Tagen überfällig`;
  }
  const m = t.milestone ? C.msById.get(t.milestone) : null;
  if (m && !m.done && m.date && diffDays(today, m.date) <= 14) return `davon hängt ${q(m.title, 30)} ab`;
  if (t.due === today) return t.time ? `um ${fmtTime(t.time)} ist es fällig` : "das ist heute fällig";
  const b = bagOf(C, t);
  if (b?.deadline && diffDays(today, b.deadline) >= 0 && diffDays(today, b.deadline) <= 14) return `die Deadline von ${b.name} ist ${relDeadline(diffDays(today, b.deadline))}`;
  if (t.due && diffDays(today, t.due) === 1) return "das ist morgen fällig";
  if (t.prio === 3) return "das hat höchste Priorität";
  if (isPlanned(C, t)) return t.plan < today ? "das schiebst du schon seit ein paar Tagen" : "das hast du dir für heute vorgenommen";
  if (Number.isFinite(t.est) && t.est <= 15) return "das ist in ein paar Minuten erledigt";
  if (t.due) {
    const r = relDay(t.due, C.now);
    return `das ist ${/^(Heute|Morgen|Übermorgen)$/.test(r) ? r.toLowerCase() : "am " + r} fällig`;
  }
  return b ? `das bringt ${b.name} voran` : "ein guter Start in den Tag";
}

// ---------- Tagesbriefing ----------
function dayLists(C) {
  const { today, open } = C;
  const overdue = open.filter((t) => t.due && t.due < today).sort(byDue);
  const dueToday = open.filter((t) => t.due === today).sort(byDay);
  const planned = open.filter((t) => isPlanned(C, t) && !(t.due && t.due <= today)).sort((a, b) => (a.plan || "").localeCompare(b.plan || "") || byDay(a, b));
  const inbox = open.filter((t) => !t.bag && !t.someday);
  const doneToday = C.tasks.filter((t) => t.done && toISO(t.done) === today).sort((a, b) => b.done - a.done);
  const weekEnd = addDays(today, 7);
  const upcoming = open.filter((t) => t.due && t.due > today && t.due <= weekEnd).sort(byDue);
  const timeline = C.tasks.filter((t) => t.due === today && t.time).sort((a, b) => a.time.localeCompare(b.time));
  return { overdue, dueToday, planned, inbox, doneToday, upcoming, timeline };
}

export function briefing(state, now = new Date(), { permission } = {}) {
  const C = makeCtx(state, now);
  const { today, profile } = C;
  const L = dayLists(C);
  const focusList = focusIn(C, profile.focusCount);
  const n = L.dueToday.length + L.planned.length;
  const termine = L.dueToday.filter((t) => t.time).length;
  const dayEndMin = parseTime(profile.dayEnd) ?? 1080;
  const nowMin = C.now.getHours() * 60 + C.now.getMinutes();
  const afterWork = nowMin >= dayEndMin;
  const workday = isWorkday(C, today);
  const doneN = L.doneToday.length;
  const denom = n + doneN;
  const progress = denom ? doneN / denom : 0;

  // Überschrift
  let headline;
  if (afterWork && doneN) headline = `Heute geschafft: ${doneN} von ${doneN + n + L.overdue.length}`;
  else if (!n && !L.overdue.length) headline = doneN ? "Alles erledigt 🎉" : "Heute ist nichts fällig";
  else if (!n) headline = `${plural(L.overdue.length, "Aufgabe ist", "Aufgaben sind")} überfällig`;
  else headline = n === 1 ? "Eine Sache steht heute an" : `${n} Dinge stehen heute an`;

  // Zusammenfassung im PM-Ton
  const lead = focusList[0] || L.overdue[0] || L.dueToday.find((t) => !t.time) || null;
  let summary;
  const left = n + L.overdue.length;
  if (afterWork) {
    const tomorrow = C.open.filter((t) => t.due === addDays(today, 1) || t.plan === addDays(today, 1)).length;
    if (doneN && !left) summary = `Stark – ${plural(doneN, "Aufgabe", "Aufgaben")} erledigt und nichts mehr offen. Feierabend!`;
    else if (left) summary = `Heute erledigt: ${doneN} von ${doneN + left}. Schieb den Rest bewusst auf morgen – dann ist der Kopf frei.`;
    else summary = tomorrow ? `Feierabend! Morgen ${tomorrow === 1 ? "steht eine Sache" : `stehen ${tomorrow} Dinge`} an – du startest vorbereitet.` : "Feierabend! Morgen ist noch nichts geplant – genieß den Abend.";
  } else if (!workday && !left) {
    summary = weekday(today) === 6 || weekday(today) === 0 ? "Wochenende – nichts fällig. Lad die Akkus auf, Montag geht's weiter." : "Heute ist frei – nichts fällig. Genieß den Tag.";
  } else if (!left) {
    if (doneN) summary = `Alles erledigt – ${plural(doneN, "Aufgabe", "Aufgaben")} geschafft. Stark!`;
    else {
      const pickBag = C.bags.filter((b) => b.status === "aktiv").map((b) => ({ b, s: statsFor(C, b.id) })).filter((x) => x.s.next).sort((x, y) => x.s.score - y.s.score || y.s.idleDays - x.s.idleDays)[0];
      summary = pickBag ? `Heute ist nichts fällig. Perfekt für einen Schritt bei ${bagName(pickBag.b)}: ${q(pickBag.s.next.title)}.` : "Heute ist nichts fällig – Zeit, neue Ziele festzulegen.";
    }
  } else {
    const items = [];
    if (termine) items.push(plural(termine, "Termin", "Termine"));
    if (n - termine) items.push(plural(n - termine, "Aufgabe", "Aufgaben"));
    if (L.overdue.length) items.push(plural(L.overdue.length, "überfällige Aufgabe", "überfällige Aufgaben"));
    summary = workday ? `Du hast heute ${joinDe(items)}.` : `Eigentlich hast du heute frei – trotzdem ${left === 1 ? "wartet" : "warten"} ${joinDe(items)}.`;
    if (lead) summary += ` Fang mit ${q(lead.title)} an – ${whyFirst(C, lead)}.`;
  }

  // Im Blick: ruhende Taschen und nahe Deadlines
  const active = C.bags.filter((b) => b.status === "aktiv");
  const stalled = active.map((b) => ({ bag: b, s: statsFor(C, b.id) })).filter((x) => x.s.open > 0 && x.s.idleDays >= 10).sort((a, b) => b.s.idleDays - a.s.idleDays).map((x) => ({ bag: x.bag, idleDays: x.s.idleDays }));
  const deadlines = C.bags.filter((b) => b.status !== "fertig" && b.deadline).map((b) => ({ bag: b, days: diffDays(today, b.deadline) })).filter((x) => x.days <= 14).sort((a, b) => a.days - b.days);

  return {
    greeting: greeting(C.now),
    name: profile.name || "",
    daypart: daypart(C.now),
    dateLabel: dateLabel(C.now),
    headline,
    summary,
    counts: { overdue: L.overdue.length, today: L.dueToday.length, planned: L.planned.length, inbox: L.inbox.length, doneToday: doneN, upcoming: L.upcoming.length },
    progress,
    overdue: L.overdue,
    today: L.dueToday,
    planned: L.planned,
    timeline: L.timeline,
    focus: focusList,
    doneToday: L.doneToday,
    upcoming: L.upcoming,
    stalled,
    deadlines,
    tips: tipsFor(C, L, { permission, stalled, deadlines }),
  };
}

// Handlungs-Tipps (höchstens 4, nach Gewicht)
function tipsFor(C, L, { permission, stalled, deadlines }) {
  const { today, profile, state } = C;
  const out = [];
  const add = (w, tip) => out.push({ w, ...tip });
  if (L.overdue.length) add(100, { id: "overdue", icon: "⏰", text: L.overdue.length === 1 ? `${q(L.overdue[0].title, 30)} ist überfällig – heute erledigen oder neu planen` : `${L.overdue.length} überfällige Aufgaben neu planen`, action: { type: "plan-overdue" } });
  const nextTimed = L.timeline.find((t) => !t.done && parseTime(t.time) > C.now.getHours() * 60 + C.now.getMinutes());
  if (nextTimed) {
    const mins = parseTime(nextTimed.time) - (C.now.getHours() * 60 + C.now.getMinutes());
    if (mins <= 120) add(95, { id: "next:" + nextTimed.id, icon: "📍", text: `In ${fmtDuration(mins)}: ${q(nextTimed.title, 30)}`, action: { type: "open-task", id: nextTimed.id } });
  }
  const crit = C.bags.filter((b) => b.status === "aktiv").map((b) => ({ b, s: statsFor(C, b.id) })).filter((x) => x.s.health === "kritisch").sort((x, y) => x.s.score - y.s.score)[0];
  if (crit) add(80, { id: "critical:" + crit.b.id, icon: "🚨", text: `${bagName(crit.b)}: ${crit.s.healthReason}`, action: { type: "open-bag", id: crit.b.id } });
  const dl = deadlines.find((x) => x.days >= 0 && x.days <= 7);
  if (dl) {
    const s = statsFor(C, dl.bag.id);
    add(75, { id: "deadline:" + dl.bag.id, icon: "🎯", text: `Deadline ${bagName(dl.bag)} ${relDeadline(dl.days)} – ${s.pct} % erledigt`, action: { type: "open-bag", id: dl.bag.id } });
  }
  const ms = C.milestones.filter((m) => !m.done && m.date && m.date >= today && diffDays(today, m.date) <= 7 && (!m.bag || C.bagsById.get(m.bag)?.status !== "fertig")).sort((a, b) => a.date.localeCompare(b.date))[0];
  if (ms) add(70, { id: "milestone:" + ms.id, icon: "🏁", text: `Meilenstein ${q(ms.title, 30)} ${relDeadline(diffDays(today, ms.date))}`, action: ms.bag ? { type: "open-bag", id: ms.bag } : { type: "open-upcoming" } });
  const leftover = C.open.filter((t) => t.plan && diffDays(t.plan, today) >= 3 && !(t.due && t.due < today));
  if (leftover.length) add(60, { id: "leftover", icon: "🧹", text: `${plural(leftover.length, "Aufgabe liegt", "Aufgaben liegen")} seit Tagen – neu planen?`, action: { type: "plan-overdue" } });
  const oldestInbox = L.inbox.reduce((m, t) => Math.min(m, t.created || C.nowMs), C.nowMs);
  if (L.inbox.length >= 5 || (L.inbox.length && C.nowMs - oldestInbox >= 2 * DAY)) add(50, { id: "inbox", icon: "📥", text: `${plural(L.inbox.length, "Eintrag", "Einträge")} im Eingang einsortieren`, action: { type: "open-inbox" } });
  if (stalled.length) {
    const s = stalled[0];
    const nx = statsFor(C, s.bag.id).next;
    add(45, { id: "stalled:" + s.bag.id, icon: "😴", text: nx ? `${bagName(s.bag)} ruht seit ${s.idleDays} Tagen – kleiner Schritt: ${q(nx.title, 30)}?` : `${bagName(s.bag)} ruht seit ${s.idleDays} Tagen`, action: { type: "open-bag", id: s.bag.id } });
  }
  const reviewDone = state.meta?.lastReview && state.meta.lastReview >= startOfWeek(today, profile.weekStart ?? 1);
  if (weekday(today) === profile.reviewDay && !reviewDone) add(40, { id: "review", icon: "🧭", text: "Heute ist Wochenrückblick – 10 Minuten für einen klaren Kopf", action: { type: "review" } });
  if (permission === "default") add(35, { id: "reminders", icon: "🔔", text: "Lass dich erinnern – Mitteilungen für Briefing und Termine erlauben", action: { type: "enable-reminders" } });
  const weekLoad = L.upcoming.length;
  if (weekLoad >= 8) add(30, { id: "week-load", icon: "📅", text: `${weekLoad} Aufgaben in den nächsten 7 Tagen – verteil sie rechtzeitig`, action: { type: "open-upcoming" } });
  const lastBackup = state.meta?.lastBackup || 0;
  const lastSync = state.meta?.lastSync || 0;
  if (C.tasks.length >= 5 && C.nowMs - lastBackup > 14 * DAY && C.nowMs - lastSync > 3 * DAY) add(20, { id: "backup", icon: "💾", text: lastBackup ? `Letztes Backup vor ${Math.floor((C.nowMs - lastBackup) / DAY)} Tagen – kurz sichern?` : "Sichere deine Daten – ein Backup dauert 5 Sekunden", action: { type: "backup" } });
  return out.sort((a, b) => b.w - a.w).slice(0, 4).map(({ w, ...t }) => t);
}

// ---------- Demnächst ----------
export function upcoming(state, now = new Date(), days = 14) {
  const C = makeCtx(state, now);
  const out = [];
  const span = Math.max(1, Math.min(366, Math.floor(days) || 14));
  const end = addDays(C.today, span - 1);
  const byDate = new Map();
  const push = (d, key, x) => {
    if (!byDate.has(d)) byDate.set(d, { tasks: [], milestones: [] });
    byDate.get(d)[key].push(x);
  };
  for (const t of C.open) {
    if (t.due && t.due >= C.today && t.due <= end) push(t.due, "tasks", t);
    else if (!t.due && t.plan && t.plan >= C.today && t.plan <= end) push(t.plan, "tasks", t);
  }
  for (const m of C.milestones) if (!m.done && m.date && m.date >= C.today && m.date <= end) push(m.date, "milestones", m);
  for (let i = 0; i < span; i++) {
    const d = addDays(C.today, i);
    const e = byDate.get(d);
    if (!e) continue;
    e.tasks.sort(byDay);
    out.push({ date: d, label: relDay(d, C.now), tasks: e.tasks, milestones: e.milestones, load: e.tasks.reduce((s, t) => s + est(t), 0) });
  }
  return out;
}

// ---------- Tag planen (Morgen-Ritual) ----------
export function planDay(state, now = new Date()) {
  const C = makeCtx(state, now);
  const { today, profile } = C;
  const L = dayLists(C);
  const seen = new Set();
  const candidates = [];
  const add = (t) => {
    if (t && !seen.has(t.id)) seen.add(t.id), candidates.push(t);
  };
  L.overdue.forEach(add);
  L.dueToday.forEach(add);
  L.planned.forEach(add);
  C.open.filter((t) => t.prio === 3 && focusable(C, t)).sort((a, b) => sumParts(scoreParts(C, b)) - sumParts(scoreParts(C, a)) || tieBreak(a, b)).forEach(add);
  // Vorschläge: nächster Schritt jeder aktiven Tasche (die mit Druck zuerst)
  C.bags
    .filter((b) => b.status === "aktiv")
    .map((b) => ({ b, s: statsFor(C, b.id) }))
    .filter((x) => x.s.next && !x.s.next.time)
    .sort((x, y) => x.s.score - y.s.score || (x.s.deadlineIn ?? 999) - (y.s.deadlineIn ?? 999))
    .slice(0, 6)
    .forEach((x) => add(x.s.next));

  const startMin = parseTime(profile.dayStart) ?? 480;
  const endMin = parseTime(profile.dayEnd) ?? 1080;
  const nowMin = C.now.getHours() * 60 + C.now.getMinutes();
  const capacity = Math.max(0, endMin - Math.max(nowMin, startMin));
  // Auslastung: eingeplante Kandidaten (auch liegengebliebene) plus heutige Termine, die noch bevorstehen
  const planned = candidates.filter((t) => isPlanned(C, t) || (t.due === today && t.time && parseTime(t.time) >= nowMin));
  const load = planned.reduce((s, t) => s + est(t), 0);

  let warning = null;
  const workday = isWorkday(C, today);
  if (nowMin >= endMin) warning = load ? "Feierabend ist schon durch – plan den Rest lieber für morgen." : null;
  else if (!workday && load) warning = "Heute ist eigentlich frei – nimm dir nur vor, was wirklich sein muss.";
  else if (load > capacity) {
    let over = load - capacity;
    let k = 0;
    const movable = planned.filter((t) => !t.time && !(t.due && t.due <= today)).sort((a, b) => sumParts(scoreParts(C, a)) - sumParts(scoreParts(C, b)));
    for (const t of movable) {
      if (over <= 0) break;
      over -= est(t);
      k++;
    }
    warning = `Du hast ${hours(load)} eingeplant, aber nur noch ${hours(capacity)} bis Feierabend` + (k ? ` – schieb ${k === 1 ? "eine Aufgabe" : `${k} Aufgaben`} auf morgen.` : " – setz Prioritäten.");
  } else if (planned.filter((t) => !t.time).length > 7) warning = "Mehr als 7 Dinge an einem Tag schafft kaum jemand – konzentrier dich auf die wichtigsten 3.";
  return { candidates, capacity, load, warning, planned };
}

// ---------- Tasche vorschlagen (Eingang einsortieren) ----------
const STOP = new Set(
  ("der die das den dem des und oder mit fuer von vom zu zum zur im in am an auf aus bei ein eine einen einem einer ist sind noch mal neu neue neuen bitte mich mir ich du wir es nicht nur auch fertig machen " +
    "heute morgen uebermorgen gestern montag dienstag mittwoch donnerstag freitag samstag sonntag woche wochen tag tage tagen uhr naechste naechsten naechster bis um ab dann wieder schon " +
    "erledigen checken check todo aufgabe aufgaben sache dinge ding " +
    // allgemeine Verben sagen wenig über die Tasche aus
    "kaufen machen schreiben anrufen erstellen pruefen senden schicken bauen planen testen fixen klaeren vorbereiten besorgen holen lesen einrichten anlegen eintragen aktualisieren ueberarbeiten anfragen fragen suchen finden")
    .split(/\s+/),
);
const SHORT_OK = new Set(["ki", "ai", "ug", "seo", "ads", "api", "ux", "ui", "pr", "hr", "it", "app", "ag"]);
export function keywords(text) {
  const n = String(text ?? "").toLowerCase().replace(/https?:\/\/\S+/g, " ").replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/ß/g, "ss").normalize("NFD").replace(/[̀-ͯ]/g, "");
  return n.split(/[^a-z0-9]+/).filter((w) => w && (w.length >= 3 || SHORT_OK.has(w)) && !STOP.has(w) && !/^\d+$/.test(w));
}
const kwMatch = (a, b) => {
  if (a === b) return 1;
  const [s, l] = a.length <= b.length ? [a, b] : [b, a];
  if (s.length >= 4 && l.startsWith(s)) return 0.7;
  if (s.length >= 5 && l.length >= s.length + 4 && l.endsWith(s)) return 0.5; // Komposita: „steuerberater“ ↔ „berater“ (nicht „verkaufen“ ↔ „kaufen“)
  return 0;
};

export function suggestBag(text, state) {
  const bags = live(state?.bags).filter((b) => b.status !== "fertig");
  if (!bags.length || !String(text ?? "").trim()) return null;
  // Ausdrückliches #Tasche gewinnt immer
  const hash = /(?:^|\s)#(\p{L}[\p{L}\p{N}_\-]*)/u.exec(String(text));
  if (hash) {
    const b = matchBag(hash[1], bags);
    if (b) return { bag: b, score: 10, confident: true };
  }
  const toks = [...new Set(keywords(text))];
  if (!toks.length) return null;
  const tasks = live(state?.tasks);
  const kws = new Map();
  for (const b of bags) {
    const m = new Map();
    const put = (w, weight) => m.set(w, Math.max(m.get(w) || 0, weight));
    keywords(b.name).forEach((w) => put(w, 3));
    (Array.isArray(b.keywords) ? b.keywords : []).flatMap(keywords).forEach((w) => put(w, 3));
    (b.sections || []).flatMap(keywords).forEach((w) => put(w, 2));
    keywords(b.goal).forEach((w) => put(w, 1.5));
    const freq = new Map();
    for (const t of tasks.filter((x) => x.bag === b.id).slice(-200)) for (const w of new Set(keywords(t.title))) freq.set(w, (freq.get(w) || 0) + 1);
    for (const [w, c] of freq) put(w, c >= 2 ? 1.2 : 0.7);
    kws.set(b.id, m);
  }
  const B = bags.length;
  const df = new Map();
  for (const m of kws.values()) for (const w of m.keys()) df.set(w, (df.get(w) || 0) + 1);
  const idf = (w) => Math.log(1 + B / Math.max(1, df.get(w) || 1));
  const scores = bags.map((b) => {
    const m = kws.get(b.id);
    let s = 0;
    for (const tok of toks) {
      let best = 0;
      for (const [w, weight] of m) {
        const x = kwMatch(tok, w);
        if (x) best = Math.max(best, weight * x * idf(w));
      }
      s += best;
    }
    if (b.status === "pausiert") s *= 0.8;
    return { bag: b, score: Math.round(s * 100) / 100 };
  });
  scores.sort((a, b) => b.score - a.score || (a.bag.order || 0) - (b.bag.order || 0));
  const [s1, s2] = scores;
  if (!s1 || s1.score < 1 || (s2 && s1.score < s2.score * 1.15)) return null;
  return { bag: s1.bag, score: s1.score, confident: s1.score >= 1.5 && (!s2 || s1.score >= 1.5 * s2.score) };
}

// ---------- Wochenrückblick ----------
export function weeklyReview(state, now = new Date()) {
  const C = makeCtx(state, now);
  const { today } = C;
  const from = addDays(today, -6);
  const inRange = (ms, a, b) => {
    const d = toISO(ms);
    return d && d >= a && d <= b;
  };
  const done = C.tasks.filter((t) => t.done && inRange(t.done, from, today)).sort((a, b) => b.done - a.done);
  const doneBefore = C.tasks.filter((t) => t.done && inRange(t.done, addDays(from, -7), addDays(from, -1))).length;
  const created = C.tasks.filter((t) => t.created && inRange(t.created, from, today)).length;
  const perBag = C.bags
    .filter((b) => b.status !== "fertig" || done.some((t) => t.bag === b.id))
    .map((b) => {
      const stats = statsFor(C, b.id);
      return { bag: b, done: done.filter((t) => t.bag === b.id).length, open: stats.open, stats };
    })
    .sort((a, b) => b.done - a.done || (a.bag.order || 0) - (b.bag.order || 0));
  const stalled = perBag.filter((x) => x.bag.status === "aktiv" && x.open > 0 && x.stats.idleDays >= 10).sort((a, b) => b.stats.idleDays - a.stats.idleDays).map((x) => ({ bag: x.bag, idleDays: x.stats.idleDays }));
  const overdue = C.open.filter((t) => t.due && t.due < today).sort(byDue);
  const noDate = C.open.filter((t) => !t.due && !t.plan && !t.someday && !t.waiting).length;
  const inbox = C.open.filter((t) => !t.bag && !t.someday).length;
  const msDone = C.milestones.filter((m) => m.done && inRange(m.done, from, today));

  const wins = [];
  if (done.length) {
    const diff = done.length - doneBefore;
    wins.push(`${plural(done.length, "Aufgabe", "Aufgaben")} erledigt` + (doneBefore && diff > 0 ? ` – ${diff} mehr als in der Woche davor 💪` : diff > 0 && !doneBefore ? " 💪" : ""));
  }
  for (const m of msDone) wins.push(`Meilenstein ${q(m.title)} erreicht 🏁`);
  for (const x of perBag.filter((x) => x.done >= 2).slice(0, 2)) wins.push(`${bagName(x.bag)}: ${x.done} erledigt`);
  const activeDays = new Set(done.map((t) => toISO(t.done))).size;
  if (activeDays >= 5) wins.push(`An ${activeDays} von 7 Tagen etwas geschafft – starke Konstanz`);
  if (!overdue.length && C.open.length) wins.push("Keine überfälligen Aufgaben – alles im Griff");
  if (!inbox && C.tasks.length) wins.push("Eingang leer – sauber sortiert");
  if (!wins.length) wins.push("Neue Woche, neue Chance – ein kleiner Schritt reicht für den Anfang");

  const questions = [];
  if (inbox) questions.push(`${plural(inbox, "Eintrag", "Einträge")} im Eingang – wohin gehören sie?`);
  for (const t of overdue.slice(0, 2)) questions.push(`${q(t.title)} ist ${daysText(diffDays(today, t.due))} überfällig – noch wichtig, neu planen oder streichen?`);
  for (const x of perBag.filter((x) => x.bag.status === "aktiv" && !x.stats.next && x.stats.health !== "fertig").slice(0, 2)) questions.push(`Was ist der nächste Schritt für ${bagName(x.bag)}?`);
  for (const s of stalled.slice(0, 1)) questions.push(`${bagName(s.bag)} ruht seit ${s.idleDays} Tagen – pausieren oder einen kleinen Schritt planen?`);
  const waitOld = C.open.filter((t) => t.waiting && C.nowMs - (t.updated || 0) >= 5 * DAY)[0];
  if (waitOld) questions.push(`Wartest du noch auf ${trunc(waitOld.waiting, 30)}? Vielleicht kurz nachhaken.`);
  const msSoon = C.milestones.filter((m) => !m.done && m.date && m.date >= today && diffDays(today, m.date) <= 14).sort((a, b) => a.date.localeCompare(b.date))[0];
  if (msSoon) questions.push(`Ist ${q(msSoon.title)} (${relDay(msSoon.date, C.now)}) noch realistisch?`);
  questions.push("Welche 3 Ergebnisse würden nächste Woche zu einem Erfolg machen?");

  return { range: { from, to: today }, done, created, perBag, stalled, overdue, noDate, inbox, wins, questions: questions.slice(0, 6), doneBefore, milestonesDone: msDone };
}

// ---------- Tagesabschluss ----------
export function evening(state, now = new Date()) {
  const C = makeCtx(state, now);
  const { today } = C;
  const tomorrowISO = addDays(today, 1);
  const L = dayLists(C);
  const left = [...L.overdue, ...L.dueToday, ...L.planned];
  const tomorrow = C.open.filter((t) => t.due === tomorrowISO || (t.plan === tomorrowISO && !(t.due && t.due <= today))).sort(byDay);
  const d = L.doneToday.length;
  let text;
  if (d && !left.length) text = `Alles erledigt – ${plural(d, "Aufgabe", "Aufgaben")} geschafft. ${tomorrow.length ? `Morgen ${tomorrow.length === 1 ? "wartet eine Sache" : `warten ${tomorrow.length} Dinge`} – du startest vorbereitet.` : "Genieß den Feierabend!"}`;
  else if (d && left.length) text = `Stark – ${plural(d, "Aufgabe", "Aufgaben")} erledigt. ${left.length === 1 ? "Eine ist" : `${left.length} sind`} noch offen: schieb sie auf morgen oder streich, was nicht mehr wichtig ist.`;
  else if (left.length) text = `Heute nichts abgehakt – kein Drama. ${left.length === 1 ? "Die offene Aufgabe" : `Die ${left.length} offenen Aufgaben`} kannst du auf morgen schieben; such dir eine aus, die wirklich zählt.`;
  else text = tomorrow.length ? `Ruhiger Tag. Morgen ${tomorrow.length === 1 ? "steht eine Sache" : `stehen ${tomorrow.length} Dinge`} an.` : "Ruhiger Tag – und morgen ist noch alles offen. Genieß den Abend.";
  return { done: L.doneToday, left, tomorrow, text };
}

// ---------- Nächste Schritte einer Tasche ----------
const BIG = /\b(komplett|alles|gesamte[nmrs]?|fertigstellen|umsetzen|aufbauen|projekt|launch(en)?|einführen|einrichten)\b/i;
export function nextSteps(state, bagId, now = new Date()) {
  const C = makeCtx(state, now);
  const { today } = C;
  const b = bagId ? C.bagsById.get(bagId) || null : null;
  const s = statsFor(C, bagId || null);
  const open = C.open.filter((t) => (t.bag || null) === (bagId || null));
  const out = [];
  const used = new Set();
  const add = (text, action) => {
    if (action?.id && action.type === "open-task") {
      if (used.has(action.id)) return;
      used.add(action.id);
    }
    out.push(action ? { text, action } : { text });
  };
  if (b?.status === "fertig") return [{ text: "Diese Tasche ist fertig 🎉 – archivieren oder ein neues Ziel setzen?", action: { type: "open-bag", id: b.id } }];
  if (!s.total) return [b ? { text: `Was ist der erste Schritt für ${b.name}? Leg ihn jetzt fest – klein reicht.`, action: { type: "open-bag", id: b.id } } : { text: "Hier ist noch nichts – leg den ersten Schritt fest." }];
  if (!s.open) add(`Alles erledigt 🎉 – Tasche als „Fertig“ markieren oder das nächste Ziel festlegen?`, b ? { type: "open-bag", id: b.id } : undefined);

  const overdue = open.filter((t) => t.due && t.due < today).sort(byDue);
  if (overdue.length) add(overdue.length === 1 ? `${q(overdue[0].title)} ist überfällig – erledigen oder neu planen.` : `${overdue.length} Aufgaben sind überfällig – fang mit ${q(overdue[0].title)} an.`, { type: "open-task", id: overdue[0].id });

  const m = s.nextMilestone;
  if (m?.date && diffDays(today, m.date) <= 7) {
    const linkedOpen = open.filter((t) => t.milestone === m.id);
    const undated = linkedOpen.filter((t) => !t.due && !t.plan);
    if (undated.length) add(`Meilenstein ${q(m.title, 30)} ${relDeadline(Math.max(0, diffDays(today, m.date)))}: ${plural(undated.length, "offene Aufgabe", "offene Aufgaben")} ohne Datum – plan sie ein.`, { type: "open-task", id: undated[0].id });
  }
  if (m && (!m.date || diffDays(today, m.date) <= 21) && !C.tasks.some((t) => t.milestone === m.id)) add(`Welche Aufgaben gehören zu ${q(m.title, 30)}? Verknüpf sie, dann sieht man den Fortschritt.`, b ? { type: "open-bag", id: b.id } : undefined);

  if (s.next) {
    if (s.idleDays >= 10) add(`Hier ist seit ${s.idleDays} Tagen nichts passiert. Kleiner Schritt: ${q(s.next.title)} heute einplanen?`, { type: "open-task", id: s.next.id });
    else add(`Nächster Schritt: ${q(s.next.title)}${s.next.due ? ` (${dueText(s.next.due, C.now)})` : ""}.`, { type: "open-task", id: s.next.id });
  } else if (s.open) add(s.waiting ? "Alles wartet gerade auf andere – hak bei einer Sache nach." : `Was ist der nächste konkrete Schritt${b ? ` für ${b.name}` : ""}?`, b ? { type: "open-bag", id: b.id } : undefined);

  const big = open.find((t) => !t.waiting && ((Number.isFinite(t.est) && t.est > 120) || (BIG.test(t.title) && !(t.subtasks || []).length)));
  if (big) add(`Teile ${q(big.title)} in kleinere Schritte – dann geht's leichter los.`, { type: "open-task", id: big.id });

  const wait = open.filter((t) => t.waiting && C.nowMs - (t.updated || 0) >= 5 * DAY).sort((x, y) => (x.updated || 0) - (y.updated || 0))[0];
  if (wait) add(`Seit ${Math.floor((C.nowMs - wait.updated) / DAY)} Tagen wartest du auf ${trunc(wait.waiting, 30)} – nachhaken?`, { type: "open-task", id: wait.id });

  if (s.deadlineIn !== null && s.deadlineIn >= 0 && s.deadlineIn <= 14 && s.pct < 60) add(`Deadline ${relDeadline(s.deadlineIn)} und erst ${s.pct} % erledigt – was kannst du streichen oder abgeben?`, b ? { type: "open-bag", id: b.id } : undefined);

  const vague = open.find((t) => !used.has(t.id) && t.title.trim().split(/\s+/).length <= 2 && !/(en|ern|eln)$/i.test(t.title.trim()) && !t.subtasks?.length);
  if (vague && out.length < 4) add(`Mach ${q(vague.title)} konkret: Was genau ist zu tun?`, { type: "open-task", id: vague.id });

  return out.slice(0, 4).map((x) => (x.action ? x : { text: x.text }));
}

// ---------- Erinnerungsplan ----------
// ReminderItem = { at, kind: "task"|"briefing"|"evening"|"review", taskId?, title, body, tag }
export function reminderPlan(state, now = new Date(), { days = 3 } = {}) {
  const C = makeCtx(state, now);
  const { profile, today } = C;
  const from = C.nowMs - 60000;
  const to = C.nowMs + Math.max(0, days) * DAY;
  const lastISO = toISO(to);
  const items = [];
  const inWin = (ms) => ms > from && ms <= to;

  // Aufgaben mit Uhrzeit (bei Wiederholungen auch die kommenden Termine der Serie)
  for (const t of C.open) {
    if (t.someday || !t.time || !t.due) continue;
    let d = t.due;
    for (let i = 0; i < 400 && d && d <= lastISO; i++) {
      const at = remindAt({ ...t, due: d }, profile);
      if (at && inWin(at.getTime()) && d >= addDays(today, -1)) {
        const b = bagOf(C, t);
        const r = Math.round((atLocal(d, parseTime(t.time)).getTime() - at.getTime()) / 60000);
        const sameDay = toISO(at) === d;
        const when = sameDay ? `${fmtTime(t.time)} Uhr${r > 0 ? ` (in ${fmtDuration(r)})` : ""}` : `${relDay(d, at)}, ${fmtTime(t.time)} Uhr`;
        items.push({ at: at.getTime(), kind: "task", taskId: t.id, title: trunc(t.title, 60), body: [when, b ? bagName(b) : null].filter(Boolean).join(" · "), tag: d === t.due ? `task-${t.id}` : `task-${t.id}-${d}` });
      }
      if (!t.repeat) break;
      d = nextOccurrence(d, t.repeat);
    }
  }

  const startMin = parseTime(profile.dayStart) ?? 480;
  const endMin = parseTime(profile.dayEnd) ?? 1080;
  const reviewDays = new Set();
  for (let i = 0; i <= Math.ceil(days) + 1; i++) {
    const d = addDays(today, i);
    if (d > lastISO) break;
    const dueD = C.open.filter((t) => t.due === d && !t.someday);
    const overD = C.open.filter((t) => t.due && t.due < d);
    const planD = C.open.filter((t) => (d === today ? isPlanned(C, t) : t.plan === d) && !(t.due && t.due <= d));
    const n = dueD.length + planD.length;

    // Morgen-Briefing
    const atB = atLocal(d, startMin).getTime();
    if (profile.briefing && inWin(atB) && (isWorkday(C, d) || n + overD.length > 0)) {
      const title = n ? `☀️ Dein Tag: ${plural(n, "Aufgabe", "Aufgaben")}${overD.length ? ` + ${overD.length} überfällig` : ""}` : overD.length ? `☀️ Dein Tag: ${plural(overD.length, "überfällige Aufgabe", "überfällige Aufgaben")}` : `☀️ ${greeting(new Date(atB))}${profile.name ? ", " + profile.name : ""}`;
      items.push({ at: atB, kind: "briefing", title, body: briefBody(C, d, { dueD, overD, planD }), tag: `briefing-${d}` });
    }

    // Wochenrückblick am Rückblick-Tag zum Feierabend
    const atE = atLocal(d, endMin).getTime();
    const reviewDone = state?.meta?.lastReview && state.meta.lastReview >= startOfWeek(d, profile.weekStart ?? 1);
    if (weekday(d) === profile.reviewDay && !reviewDone && inWin(atE)) {
      const weekDone = C.tasks.filter((t) => t.done && toISO(t.done) >= addDays(d, -6) && toISO(t.done) <= d).length;
      items.push({ at: atE, kind: "review", title: "🧭 Zeit für deinen Wochenrückblick", body: `10 Minuten: Erfolge feiern, Eingang leeren, nächste Woche planen.${weekDone ? ` Diese Woche schon ${weekDone} erledigt.` : ""}`, tag: `review-${d}` });
      reviewDays.add(d);
    }

    // Feierabend – nur wenn an dem Tag noch etwas offen ist (am Rückblick-Tag übernimmt der Rückblick)
    const leftD = [...overD, ...dueD, ...planD];
    if (profile.evening && leftD.length && inWin(atE) && !reviewDays.has(d)) {
      const top = leftD.slice().sort((a, b) => sumParts(scoreParts(C, b)) - sumParts(scoreParts(C, a))).slice(0, 2).map((t) => q(t.title, 30));
      items.push({ at: atE, kind: "evening", title: `🌙 Feierabend: ${plural(leftD.length, "Aufgabe", "Aufgaben")} offen`, body: `${joinDe(top)}${leftD.length > 2 ? ` und ${leftD.length - 2} weitere` : ""} – erledigen oder auf morgen schieben?`, tag: `evening-${d}` });
    }
  }

  const seen = new Set();
  return items
    .filter((x) => x.at > from && !seen.has(x.tag) && seen.add(x.tag))
    .sort((a, b) => a.at - b.at || a.kind.localeCompare(b.kind));
}

// Briefing-Text: die 2–3 wichtigsten Dinge des Tages, Überfälliges zuerst
function briefBody(C, d, { dueD, overD, planD }) {
  const ranked = [
    ...overD.sort(byDue).map((t) => ({ t, label: `${trunc(t.title, 45)} (überfällig)` })),
    ...dueD.filter((t) => t.time).sort(byDay).map((t) => ({ t, label: `${fmtTime(t.time)} ${trunc(t.title, 45)}` })),
    ...dueD.filter((t) => !t.time).sort((a, b) => (b.prio || 0) - (a.prio || 0) || (a.order || 0) - (b.order || 0)).map((t) => ({ t, label: trunc(t.title, 45) })),
    ...planD.sort((a, b) => (b.prio || 0) - (a.prio || 0)).map((t) => ({ t, label: trunc(t.title, 45) })),
  ];
  if (!ranked.length) {
    const pick = C.bags.filter((b) => b.status === "aktiv").map((b) => ({ b, s: statsFor(C, b.id) })).filter((x) => x.s.next).sort((x, y) => x.s.score - y.s.score)[0];
    return pick ? `Heute ist nichts fällig – Zeit für einen Schritt bei ${bagName(pick.b)}: ${q(pick.s.next.title)}.` : "Heute ist nichts fällig – schau, was dich voranbringt.";
  }
  const top = ranked.slice(0, 3).map((x) => "• " + x.label);
  if (ranked.length > 3) top.push(`+ ${ranked.length - 3} weitere`);
  return top.join("\n");
}

// ---------- Zähler am App-Symbol ----------
export function badgeCount(state, now = new Date()) {
  const C = makeCtx(state, now);
  const ids = new Set();
  for (const t of C.open) {
    if ((t.due && t.due <= C.today) || (isPlanned(C, t) && !t.someday)) ids.add(t.id);
  }
  return ids.size;
}
