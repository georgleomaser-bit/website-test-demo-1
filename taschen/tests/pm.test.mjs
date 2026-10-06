// Tests für pm.js – der Projektmanager: Gesundheit, Fokus, Briefing, Planung, Rückblick und Erinnerungsplan (feste Zeitpunkte)
process.env.TZ = "Europe/Berlin";
import { test, describe } from "node:test";
import assert from "node:assert/strict";

const pm = await import("../js/pm.js");
const { DEFAULT_PROFILE } = await import("../js/config.js");

const DAY = 86400000;
const at = (d, h = 9, m = 0) => new Date(2026, 9, d, h, m); // Oktober 2026
const NOW = at(6, 9); // Di., 6. Oktober 2026, 9:00
const T0 = NOW.getTime();

let seq = 0;
const task = (o = {}) => {
  seq++;
  return { id: "t" + seq, created: T0, updated: T0, deleted: null, bag: null, title: "Aufgabe " + seq, notes: "", done: null, prio: 0, due: null, time: null, remind: null, repeat: null, section: "", tags: [], subtasks: [], plan: null, someday: false, order: seq, est: null, waiting: "", milestone: null, ...o };
};
const bag = (o = {}) => {
  seq++;
  return { id: "b" + seq, created: T0 - 3 * DAY, updated: T0 - DAY, deleted: null, name: "Tasche " + seq, emoji: "👜", color: "blue", goal: "", status: "aktiv", deadline: null, sections: [], order: seq, pinned: false, ...o };
};
const ms = (o = {}) => {
  seq++;
  return { id: "m" + seq, created: T0 - 10 * DAY, updated: T0 - 10 * DAY, deleted: null, bag: null, title: "Meilenstein " + seq, date: null, done: null, ...o };
};
const state = ({ profile, meta, ...rest } = {}) => ({
  v: 1,
  bags: [], tasks: [], notes: [], links: [], files: [], milestones: [], log: [],
  ...rest,
  profile: { ...DEFAULT_PROFILE, name: "Leo", updated: 1, ...(profile || {}) },
  meta: { lastReview: null, lastBackup: T0, lastSync: null, createdAt: T0 - 30 * DAY, seeded: false, ...(meta || {}) },
});
const titles = (arr) => arr.map((t) => t.title);

// ---------- Taschen-Statistik & Gesundheit ----------
describe("bagStats", () => {
  test("Zähler, Fortschritt, nächster Schritt", () => {
    const b = bag({ name: "AKYTEX", sections: ["Technik", "Recht"] });
    const tasks = [
      task({ bag: b.id, title: "erledigt 1", done: T0 - DAY }),
      task({ bag: b.id, title: "erledigt 2", done: T0 - 2 * DAY }),
      task({ bag: b.id, title: "überfällig", due: "2026-10-04" }),
      task({ bag: b.id, title: "heute", due: "2026-10-06" }),
      task({ bag: b.id, title: "wartet", waiting: "Paul" }),
      task({ bag: b.id, title: "diese Woche", due: "2026-10-10" }),
      task({ bag: b.id, title: "irgendwann", someday: true }),
      task({ bag: "andere", title: "fremd" }),
    ];
    const s = pm.bagStats(state({ bags: [b], tasks }), b.id, NOW);
    assert.equal(s.total, 7);
    assert.equal(s.open, 5);
    assert.equal(s.done, 2);
    assert.equal(s.pct, 33); // 2 von 6 (Irgendwann zählt nicht mit)
    assert.equal(s.overdue, 1);
    assert.equal(s.dueToday, 1);
    assert.equal(s.dueWeek, 2);
    assert.equal(s.waiting, 1);
    assert.equal(s.next.title, "überfällig");
    assert.equal(s.idleDays, 0);
    assert.equal(s.lastActivity, T0);
  });

  test("gut: aktiv, nichts überfällig", () => {
    const b = bag();
    const s = pm.bagStats(state({ bags: [b], tasks: [task({ bag: b.id, done: T0 - DAY }), task({ bag: b.id })] }), b.id, NOW);
    assert.equal(s.health, "gut");
    assert.equal(s.healthLabel, "Gut");
    assert.equal(s.healthReason, "Läuft – 1 von 2 erledigt");
  });

  test("achtung: eine überschrittene Frist reicht", () => {
    const b = bag();
    const s = pm.bagStats(state({ bags: [b], tasks: [task({ bag: b.id, due: "2026-10-05" }), task({ bag: b.id })] }), b.id, NOW);
    assert.equal(s.health, "achtung");
    assert.equal(s.healthReason, "1 Frist überschritten");
  });

  test("kritisch: viele Fristen + lange nichts passiert", () => {
    const b = bag({ updated: T0 - 20 * DAY, created: T0 - 40 * DAY });
    const old = { created: T0 - 20 * DAY, updated: T0 - 20 * DAY };
    const tasks = [task({ bag: b.id, due: "2026-10-01", ...old }), task({ bag: b.id, due: "2026-10-02", ...old }), task({ bag: b.id, due: "2026-10-03", ...old })];
    const s = pm.bagStats(state({ bags: [b], tasks }), b.id, NOW);
    assert.equal(s.idleDays, 20);
    assert.equal(s.health, "kritisch");
    assert.equal(s.healthLabel, "Kritisch");
    assert.equal(s.healthReason, "3 Fristen überschritten");
    assert.deepEqual(s.reasons, ["3 Fristen überschritten", "Seit 20 Tagen nichts passiert"]);
  });

  test("kritisch: Meilenstein überfällig bzw. Deadline überschritten", () => {
    const b = bag();
    const m = ms({ bag: b.id, title: "Beta", date: "2026-10-01" });
    const s = pm.bagStats(state({ bags: [b], tasks: [task({ bag: b.id })], milestones: [m] }), b.id, NOW);
    assert.equal(s.health, "kritisch");
    assert.equal(s.healthReason, "Meilenstein „Beta“ überfällig");
    assert.equal(s.nextMilestone.id, m.id);
    const b2 = bag({ deadline: "2026-10-04" });
    const s2 = pm.bagStats(state({ bags: [b2], tasks: [task({ bag: b2.id })] }), b2.id, NOW);
    assert.equal(s2.health, "kritisch");
    assert.equal(s2.deadlineIn, -2);
    assert.equal(s2.healthReason, "Deadline seit 2 Tagen überschritten");
  });

  test("Meilenstein-Verzug: Zeit läuft davon, Aufgaben nicht erledigt", () => {
    const b = bag();
    const m = ms({ bag: b.id, title: "Launch", date: "2026-10-08", created: T0 - 20 * DAY });
    const tasks = [task({ bag: b.id, milestone: m.id }), task({ bag: b.id, milestone: m.id }), task({ bag: b.id, milestone: m.id, done: T0 - DAY })];
    const s = pm.bagStats(state({ bags: [b], tasks, milestones: [m] }), b.id, NOW);
    assert.equal(s.health, "achtung");
    assert.match(s.healthReason, /^Meilenstein „Launch“: 33 % erledigt, 91 % der Zeit vorbei$/);
  });

  test("ruhend: pausiert, leer, lange ruhig; fertig", () => {
    const p = bag({ status: "pausiert" });
    const e = bag();
    const q = bag({ updated: T0 - 40 * DAY, created: T0 - 60 * DAY });
    const f = bag({ status: "fertig" });
    const st = state({ bags: [p, e, q, f], tasks: [task({ bag: p.id }), task({ bag: q.id, created: T0 - 40 * DAY, updated: T0 - 40 * DAY }), task({ bag: f.id, done: T0 - 5 * DAY })] });
    assert.deepEqual([pm.bagStats(st, p.id, NOW).health, pm.bagStats(st, p.id, NOW).healthLabel], ["ruhend", "Pausiert"]);
    assert.deepEqual([pm.bagStats(st, e.id, NOW).health, pm.bagStats(st, e.id, NOW).healthLabel], ["ruhend", "Noch leer"]);
    assert.equal(pm.bagStats(st, q.id, NOW).health, "ruhend");
    assert.match(pm.bagStats(st, q.id, NOW).healthReason, /Seit 40 Tagen ruhig/);
    assert.equal(pm.bagStats(st, f.id, NOW).health, "fertig");
    assert.equal(pm.bagStats(st, f.id, NOW).pct, 100);
  });

  test("alles wartet → kein nächster Schritt", () => {
    const b = bag();
    const s = pm.bagStats(state({ bags: [b], tasks: [task({ bag: b.id, waiting: "Notar" })] }), b.id, NOW);
    assert.equal(s.next, null);
    assert.equal(s.waiting, 1);
  });

  test("Grabsteine zählen nicht mit", () => {
    const b = bag();
    const s = pm.bagStats(state({ bags: [b], tasks: [task({ bag: b.id, deleted: T0 }), task({ bag: b.id })] }), b.id, NOW);
    assert.equal(s.total, 1);
  });
});

// ---------- Fokus ----------
describe("focusScore", () => {
  const st = state();
  const score = (o) => pm.focusScore(task(o), st, NOW);
  test("Fristen, Planung, Priorität (Formel laut Kommentar)", () => {
    assert.equal(score({ due: "2026-10-04", prio: 3 }), 140); // 100 + 5·2 + 30
    assert.equal(score({ due: "2026-10-06" }), 90);
    assert.equal(score({ due: "2026-10-07", prio: 2 }), 88);
    assert.equal(score({ due: "2026-10-08" }), 50);
    assert.equal(score({ due: "2026-10-12" }), 30);
    assert.equal(score({ due: "2026-11-01" }), 10);
    assert.equal(score({ due: "2026-09-01" }), 150); // Überfälligkeit gedeckelt bei 10 Tagen
    assert.equal(score({ plan: "2026-10-06" }), 40);
    assert.equal(score({ plan: "2026-10-04" }), 46);
    assert.equal(score({ prio: 1 }), 8);
  });
  test("Größe, Schwung, Alter, Dämpfer, Meilenstein", () => {
    assert.equal(score({ est: 10 }), 5);
    assert.equal(score({ est: 240 }), -10);
    assert.equal(score({ subtasks: [{ id: "a", title: "a", done: true }, { id: "b", title: "b", done: false }] }), 5);
    assert.equal(score({ created: T0 - 21 * DAY }), 3);
    assert.equal(score({ created: T0 - 100 * DAY }), 5);
    assert.equal(score({ waiting: "Paul" }), -40);
    assert.equal(score({ someday: true }), -30);
    const m = ms({ date: "2026-10-10" });
    assert.equal(pm.focusScore(task({ milestone: m.id }), state({ milestones: [m] }), NOW), 20);
    assert.equal(pm.focusScore(null, st, NOW), 0);
  });
});

describe("focus", () => {
  test("eingeplante zuerst, dann nach Score", () => {
    const tasks = [task({ title: "überfällig", due: "2026-10-01" }), task({ title: "eingeplant", plan: "2026-10-06" }), task({ title: "heute", due: "2026-10-06" }), task({ title: "später", due: "2026-10-30" })];
    assert.deepEqual(titles(pm.focus(state({ tasks }), NOW)), ["eingeplant", "überfällig", "heute"]);
  });

  test("nicht im Fokus: erledigt, wartend, irgendwann, Termine mit Uhrzeit, pausierte Taschen", () => {
    const p = bag({ status: "pausiert" });
    const tasks = [
      task({ title: "erledigt", due: "2026-10-06", done: T0 }),
      task({ title: "wartet", due: "2026-10-06", waiting: "Bank" }),
      task({ title: "irgendwann", prio: 3, someday: true }),
      task({ title: "Termin", due: "2026-10-06", time: "14:00" }),
      task({ title: "pausiert", bag: p.id, prio: 3 }),
      task({ title: "pausiert, Frist morgen", bag: p.id, due: "2026-10-07" }),
      task({ title: "ok", prio: 1 }),
    ];
    assert.deepEqual(titles(pm.focus(state({ bags: [p], tasks }), NOW)), ["pausiert, Frist morgen", "ok"]);
  });

  test("Vielfalt: höchstens zwei aus derselben Tasche, solange es Alternativen gibt", () => {
    const a = bag({ name: "A" });
    const b = bag({ name: "B" });
    const tasks = [task({ bag: a.id, title: "a1", due: "2026-10-01" }), task({ bag: a.id, title: "a2", due: "2026-10-02" }), task({ bag: a.id, title: "a3", due: "2026-10-03" }), task({ bag: b.id, title: "b1", due: "2026-10-09" })];
    assert.deepEqual(titles(pm.focus(state({ bags: [a, b], tasks }), NOW)), ["a1", "a2", "b1"]);
    assert.deepEqual(titles(pm.focus(state({ bags: [a], tasks: tasks.slice(0, 3) }), NOW)), ["a1", "a2", "a3"]);
  });

  test("Anzahl aus profile.focusCount oder Parameter; ohne Fristen wird aufgefüllt", () => {
    const tasks = [task({ title: "x" }), task({ title: "y", created: T0 - 30 * DAY }), task({ title: "z", prio: 2 })];
    const st = state({ tasks, profile: { focusCount: 2 } });
    assert.deepEqual(titles(pm.focus(st, NOW)), ["z", "y"]);
    assert.equal(pm.focus(st, NOW, 1).length, 1);
    assert.equal(pm.focus(st, NOW, 0).length, 0);
    assert.equal(pm.focus(state(), NOW).length, 0);
  });
});

// ---------- Briefing ----------
describe("briefing", () => {
  const scene = () => {
    const b = bag({ name: "AKYTEX", emoji: "🚀", deadline: "2026-10-11" });
    const tasks = [
      task({ bag: b.id, title: "Stripe-Links eintragen", due: "2026-10-04" }),
      task({ bag: b.id, title: "Domain verbinden", due: "2026-10-06" }),
      task({ bag: b.id, title: "Call mit Notar", due: "2026-10-06", time: "14:00" }),
      task({ bag: b.id, title: "Pitch üben", plan: "2026-10-06" }),
      task({ bag: b.id, title: "Logo fertig", done: T0 - 3600000, due: "2026-10-06" }),
      task({ bag: b.id, title: "Newsletter", due: "2026-10-09" }),
      task({ title: "Eingang-Idee" }),
    ];
    return { b, st: state({ bags: [b], tasks }) };
  };

  test("Zähler, Überschrift, Fortschritt, Listen", () => {
    const { st } = scene();
    const br = pm.briefing(st, NOW);
    assert.deepEqual(br.counts, { overdue: 1, today: 2, planned: 1, inbox: 1, doneToday: 1, upcoming: 1 });
    assert.equal(br.greeting, "Guten Morgen");
    assert.equal(br.name, "Leo");
    assert.equal(br.daypart, "morning");
    assert.equal(br.dateLabel, "Dienstag, 6. Oktober");
    assert.equal(br.headline, "3 Dinge stehen heute an");
    assert.equal(br.progress, 0.25);
    assert.deepEqual(titles(br.overdue), ["Stripe-Links eintragen"]);
    assert.deepEqual(titles(br.today), ["Call mit Notar", "Domain verbinden"]);
    assert.deepEqual(titles(br.planned), ["Pitch üben"]);
    assert.deepEqual(titles(br.timeline), ["Call mit Notar"]);
    assert.deepEqual(titles(br.doneToday), ["Logo fertig"]);
    assert.equal(br.focus[0].title, "Pitch üben");
  });

  test("Zusammenfassung im PM-Ton", () => {
    const { st } = scene();
    // Die nahe Deadline der Tasche ist der stärkere Grund als „eingeplant“
    assert.equal(pm.briefing(st, NOW).summary, "Du hast heute 1 Termin, 2 Aufgaben und 1 überfällige Aufgabe. Fang mit „Pitch üben“ an – die Deadline von AKYTEX ist in 5 Tagen.");
    st.bags[0].deadline = null;
    assert.match(pm.briefing(st, NOW).summary, /Fang mit „Pitch üben“ an – das hast du dir für heute vorgenommen\.$/);
    st.tasks.find((t) => t.title === "Pitch üben").plan = null;
    assert.match(pm.briefing(st, NOW).summary, /Fang mit „Stripe-Links eintragen“ an – das ist seit 2 Tagen überfällig\.$/);
  });

  test("Meilenstein als Grund: „davon hängt … ab“", () => {
    const m = ms({ title: "Go-Live", date: "2026-10-09" });
    const st = state({ milestones: [m], tasks: [task({ title: "Stripe-Links eintragen", due: "2026-10-06", milestone: m.id, prio: 3 })] });
    assert.equal(pm.briefing(st, NOW).summary, "Du hast heute 1 Aufgabe. Fang mit „Stripe-Links eintragen“ an – davon hängt „Go-Live“ ab.");
  });

  test("Im Blick: nahe Deadlines und ruhende Taschen; Tipps mit Aktionen", () => {
    const { b, st } = scene();
    const idle = bag({ name: "NOVA", emoji: "✨", created: T0 - 30 * DAY, updated: T0 - 15 * DAY });
    st.bags.push(idle);
    st.tasks.push(task({ bag: idle.id, title: "Datenschutz", created: T0 - 15 * DAY, updated: T0 - 15 * DAY }));
    const br = pm.briefing(st, NOW, { permission: "default" });
    assert.deepEqual(br.deadlines.map((x) => [x.bag.id, x.days]), [[b.id, 5]]);
    assert.deepEqual(br.stalled.map((x) => [x.bag.name, x.idleDays]), [["NOVA", 15]]);
    const ids = br.tips.map((t) => t.id);
    assert.equal(ids[0], "overdue");
    assert.deepEqual(br.tips[0].action, { type: "plan-overdue" });
    assert.ok(ids.includes("deadline:" + b.id));
    assert.ok(br.tips.length <= 4);
    for (const t of br.tips) assert.ok(t.icon && t.text && t.action?.type);
  });

  test("Tipps: Mitteilungen, Rückblick am Rückblick-Tag, Backup, nächster Termin", () => {
    const b = bag();
    const tasks = Array.from({ length: 5 }, (_, i) => task({ bag: b.id, title: "T" + i }));
    tasks.push(task({ bag: b.id, title: "Call", due: "2026-10-09", time: "10:00" }));
    const fri = at(9, 9, 15);
    const br = pm.briefing(state({ bags: [b], tasks, meta: { lastBackup: null } }), fri, { permission: "default" });
    const ids = br.tips.map((t) => t.id);
    assert.ok(ids.includes("review"));
    assert.ok(ids.includes("reminders"));
    assert.ok(ids.includes("backup"));
    assert.equal(br.tips.find((t) => t.id.startsWith("next:")).text, "In 45 Min.: „Call“");
    const done = pm.briefing(state({ bags: [b], tasks, meta: { lastReview: "2026-10-05" } }), fri);
    assert.equal(done.tips.some((t) => t.id === "review"), false);
  });

  test("ruhige Tage: nichts fällig, Wochenende, Feierabend", () => {
    const b = bag({ name: "AKYTEX", emoji: "🚀" });
    const st = state({ bags: [b], tasks: [task({ bag: b.id, title: "Domain verbinden" })] });
    const br = pm.briefing(st, NOW);
    assert.equal(br.headline, "Heute ist nichts fällig");
    assert.equal(br.summary, "Heute ist nichts fällig. Perfekt für einen Schritt bei 🚀 AKYTEX: „Domain verbinden“.");
    assert.equal(pm.briefing(st, at(10, 11)).summary, "Wochenende – nichts fällig. Lad die Akkus auf, Montag geht's weiter.");
    st.tasks.push(task({ title: "Erledigt", done: at(6, 12).getTime() }));
    const ev = pm.briefing(st, at(6, 19));
    assert.equal(ev.headline, "Heute geschafft: 1 von 1");
    assert.equal(ev.summary, "Stark – 1 Aufgabe erledigt und nichts mehr offen. Feierabend!");
    assert.equal(ev.daypart, "evening");
  });

  test("leerer Zustand bricht nichts", () => {
    const br = pm.briefing(state(), NOW);
    assert.equal(br.headline, "Heute ist nichts fällig");
    assert.deepEqual(br.focus, []);
    assert.equal(br.progress, 0);
    assert.doesNotThrow(() => pm.briefing({}, NOW));
  });
});

// ---------- Demnächst & Tag planen ----------
describe("upcoming", () => {
  test("nur Tage mit Einträgen, ohne Überfälliges, mit Meilensteinen und Auslastung", () => {
    const m = ms({ title: "Beta", date: "2026-10-11" });
    const tasks = [
      task({ title: "überfällig", due: "2026-10-05" }),
      task({ title: "heute", due: "2026-10-06", est: 60 }),
      task({ title: "morgen 1", due: "2026-10-07", time: "15:00" }),
      task({ title: "morgen 2", due: "2026-10-07", time: "09:00" }),
      task({ title: "eingeplant Do", plan: "2026-10-08" }),
      task({ title: "Fr", due: "2026-10-09" }),
      task({ title: "erledigt", due: "2026-10-09", done: T0 }),
      task({ title: "weit weg", due: "2026-12-24" }),
    ];
    const up = pm.upcoming(state({ tasks, milestones: [m] }), NOW, 14);
    assert.deepEqual(up.map((d) => [d.date, d.label]), [["2026-10-06", "Heute"], ["2026-10-07", "Morgen"], ["2026-10-08", "Übermorgen"], ["2026-10-09", "Freitag"], ["2026-10-11", "Sonntag"]]);
    assert.deepEqual(titles(up[1].tasks), ["morgen 2", "morgen 1"]);
    assert.equal(up[0].load, 60);
    assert.equal(up[1].load, 60); // ohne Schätzung je 30 Min.
    assert.equal(up[4].milestones[0].title, "Beta");
    assert.equal(up[4].tasks.length, 0);
    assert.equal(pm.upcoming(state({ tasks }), NOW, 1).length, 1);
  });
});

describe("planDay", () => {
  test("Kandidaten-Reihenfolge und Kapazität", () => {
    const b = bag({ name: "AKYTEX" });
    const tasks = [
      task({ title: "heute", due: "2026-10-06" }),
      task({ title: "überfällig", due: "2026-10-02" }),
      task({ title: "eingeplant", plan: "2026-10-06" }),
      task({ title: "wichtig", prio: 3 }),
      task({ bag: b.id, title: "nächster Schritt" }),
      task({ title: "wartet", prio: 3, waiting: "X" }),
    ];
    const r = pm.planDay(state({ bags: [b], tasks }), NOW);
    assert.deepEqual(titles(r.candidates), ["überfällig", "heute", "eingeplant", "wichtig", "nächster Schritt"]);
    assert.equal(r.capacity, 540);
    assert.equal(r.load, 30);
    assert.equal(r.warning, null);
    assert.equal(pm.planDay(state({ tasks }), at(6, 6)).capacity, 600); // vor Tagesstart zählt ab dayStart
  });

  test("Warnung bei Überlast und nach Feierabend", () => {
    const tasks = [task({ title: "groß 1", plan: "2026-10-06", est: 300 }), task({ title: "groß 2", plan: "2026-10-06", est: 300 })];
    assert.equal(pm.planDay(state({ tasks }), NOW).warning, "Du hast 10 Std. eingeplant, aber nur noch 9 Std. bis Feierabend – schieb eine Aufgabe auf morgen.");
    const late = pm.planDay(state({ tasks }), at(6, 19));
    assert.equal(late.capacity, 0);
    assert.equal(late.warning, "Feierabend ist schon durch – plan den Rest lieber für morgen.");
    assert.equal(pm.planDay(state({ tasks }), at(10, 9)).warning, "Heute ist eigentlich frei – nimm dir nur vor, was wirklich sein muss.");
  });
});

// ---------- Tasche vorschlagen ----------
describe("suggestBag", () => {
  const firma = bag({ name: "Firma & Beteiligung", goal: "GmbH gründen und Investoren vorbereiten", sections: ["Gründung", "Notar"] });
  const pay = bag({ name: "Zahlungen & Stripe", sections: ["Stripe-Konto"] });
  const mkt = bag({ name: "Marketing & Clips", goal: "Gründer-Plätze verkaufen" });
  const old = bag({ name: "Steuer 2025", status: "fertig" });
  const st = state({
    bags: [firma, pay, mkt, old],
    tasks: [task({ bag: firma.id, title: "Notar in Hamburg anfragen" }), task({ bag: firma.id, title: "Notartermin wahrnehmen" }), task({ bag: pay.id, title: "Stripe Webhook einrichten" }), task({ bag: mkt.id, title: "Instagram Reel schneiden" }), task({ bag: mkt.id, title: "Clip drehen" }), task({ bag: old.id, title: "Steuer abgeben" })],
  });
  test("passende Tasche über Name, Abschnitte, Ziel und Aufgaben", () => {
    assert.equal(pm.suggestBag("Notartermin vereinbaren", st).bag.id, firma.id);
    assert.equal(pm.suggestBag("GmbH Unterlagen", st).bag.id, firma.id);
    assert.equal(pm.suggestBag("Stripe Checkout testen", st).bag.id, pay.id);
    assert.equal(pm.suggestBag("Neues Reel für Instagram", st).bag.id, mkt.id);
    const r = pm.suggestBag("Stripe Zahlungen prüfen", st);
    assert.equal(r.confident, true);
    assert.ok(r.score > 1);
  });
  test("ausdrückliches #Tasche gewinnt; nichts Passendes → null; fertige Taschen nie", () => {
    assert.equal(pm.suggestBag("irgendwas #stripe", st).bag.id, pay.id);
    assert.equal(pm.suggestBag("Milch kaufen", st), null);
    assert.equal(pm.suggestBag("Steuer abgeben", st), null);
    assert.equal(pm.suggestBag("", st), null);
    assert.equal(pm.suggestBag("Notar", state()), null);
  });
});

// ---------- Rückblick & Abschluss ----------
describe("weeklyReview", () => {
  test("Zeitraum, Erledigtes, Taschen, Erfolge, Fragen", () => {
    const a = bag({ name: "AKYTEX", emoji: "🚀" });
    const b = bag({ name: "NOVA", emoji: "✨" });
    const m = ms({ bag: a.id, title: "Beta", done: T0 - 2 * DAY });
    const tasks = [
      task({ bag: a.id, title: "a1", done: T0 - DAY }),
      task({ bag: a.id, title: "a2", done: T0 - 3 * DAY }),
      task({ bag: b.id, title: "b1", done: T0 - 2 * DAY }),
      task({ bag: b.id, title: "alt", done: T0 - 10 * DAY, created: T0 - 20 * DAY }),
      task({ bag: a.id, title: "offen ohne Datum" }),
      task({ title: "Eingang 1" }),
      task({ bag: b.id, title: "überfällig", due: "2026-10-01" }),
    ];
    const r = pm.weeklyReview(state({ bags: [a, b], tasks, milestones: [m] }), NOW);
    assert.deepEqual(r.range, { from: "2026-09-30", to: "2026-10-06" });
    assert.deepEqual(titles(r.done), ["a1", "b1", "a2"]);
    assert.equal(r.doneBefore, 1);
    assert.equal(r.created, 6);
    assert.deepEqual(r.perBag.map((x) => [x.bag.name, x.done, x.open]), [["AKYTEX", 2, 1], ["NOVA", 1, 1]]);
    assert.equal(r.noDate, 2);
    assert.equal(r.inbox, 1);
    assert.deepEqual(titles(r.overdue), ["überfällig"]);
    assert.equal(r.wins[0], "3 Aufgaben erledigt – 2 mehr als in der Woche davor 💪");
    assert.ok(r.wins.includes("Meilenstein „Beta“ erreicht 🏁"));
    assert.ok(r.wins.includes("🚀 AKYTEX: 2 erledigt"));
    assert.equal(r.questions[0], "1 Eintrag im Eingang – wohin gehören sie?");
    assert.ok(r.questions.some((x) => x.startsWith("„überfällig“ ist seit 5 Tagen überfällig")));
    assert.equal(r.questions[r.questions.length - 1], "Welche 3 Ergebnisse würden nächste Woche zu einem Erfolg machen?");
  });
  test("leere Woche: aufmunternder Erfolg statt leerer Liste", () => {
    const r = pm.weeklyReview(state(), NOW);
    assert.deepEqual(r.wins, ["Neue Woche, neue Chance – ein kleiner Schritt reicht für den Anfang"]);
    assert.equal(r.done.length, 0);
  });
});

describe("evening", () => {
  const late = at(6, 18, 30);
  test("erledigt, offen, morgen + Text", () => {
    const tasks = [task({ title: "d1", done: at(6, 10).getTime() }), task({ title: "d2", done: at(6, 11).getTime() }), task({ title: "offen", due: "2026-10-06" }), task({ title: "morgen", due: "2026-10-07" })];
    const r = pm.evening(state({ tasks }), late);
    assert.deepEqual(titles(r.done), ["d2", "d1"]);
    assert.deepEqual(titles(r.left), ["offen"]);
    assert.deepEqual(titles(r.tomorrow), ["morgen"]);
    assert.equal(r.text, "Stark – 2 Aufgaben erledigt. Eine ist noch offen: schieb sie auf morgen oder streich, was nicht mehr wichtig ist.");
  });
  test("Varianten: alles erledigt, nichts geschafft, ruhiger Tag", () => {
    const done = [task({ done: at(6, 10).getTime() }), task({ title: "morgen", due: "2026-10-07" })];
    assert.equal(pm.evening(state({ tasks: done }), late).text, "Alles erledigt – 1 Aufgabe geschafft. Morgen wartet eine Sache – du startest vorbereitet.");
    assert.match(pm.evening(state({ tasks: [task({ due: "2026-10-06" })] }), late).text, /^Heute nichts abgehakt – kein Drama\./);
    assert.equal(pm.evening(state(), late).text, "Ruhiger Tag – und morgen ist noch alles offen. Genieß den Abend.");
  });
});

describe("nextSteps", () => {
  test("Überfälliges, nächster Schritt, zu große Aufgabe, Nachhaken", () => {
    const b = bag({ name: "AKYTEX" });
    const tasks = [
      task({ bag: b.id, title: "Stripe-Links eintragen", due: "2026-10-03" }),
      task({ bag: b.id, title: "Plattform komplett umbauen" }),
      task({ bag: b.id, title: "Rückmeldung Steuerberater", waiting: "Steuerberater", updated: T0 - 7 * DAY }),
    ];
    const r = pm.nextSteps(state({ bags: [b], tasks }), b.id, NOW);
    assert.equal(r[0].text, "„Stripe-Links eintragen“ ist überfällig – erledigen oder neu planen.");
    assert.deepEqual(r[0].action, { type: "open-task", id: tasks[0].id });
    assert.ok(r.some((x) => x.text === "Teile „Plattform komplett umbauen“ in kleinere Schritte – dann geht's leichter los."));
    assert.ok(r.some((x) => x.text === "Seit 7 Tagen wartest du auf Steuerberater – nachhaken?"));
    assert.ok(r.length <= 4);
  });
  test("nächster Schritt mit Fälligkeit, leere und fertige Tasche", () => {
    const b = bag({ name: "NOVA" });
    const t = task({ bag: b.id, title: "Datenschutz schreiben", due: "2026-10-09" });
    assert.equal(pm.nextSteps(state({ bags: [b], tasks: [t] }), b.id, NOW)[0].text, "Nächster Schritt: „Datenschutz schreiben“ (fällig am Freitag).");
    const e = bag({ name: "Leer" });
    assert.equal(pm.nextSteps(state({ bags: [e] }), e.id, NOW)[0].text, "Was ist der erste Schritt für Leer? Leg ihn jetzt fest – klein reicht.");
    const f = bag({ name: "Alt", status: "fertig" });
    assert.match(pm.nextSteps(state({ bags: [f] }), f.id, NOW)[0].text, /fertig 🎉/);
  });
});

// ---------- Erinnerungsplan ----------
describe("reminderPlan", () => {
  const scene = () => {
    const b = bag({ name: "AKYTEX", emoji: "🚀" });
    const tasks = [
      task({ id: "call", bag: b.id, title: "Call mit Notar", due: "2026-10-06", time: "14:00" }),
      task({ id: "vorbei", title: "Schon vorbei", due: "2026-10-06", time: "08:30" }),
      task({ id: "still", title: "Ohne Erinnerung", due: "2026-10-07", time: "10:00", remind: -1 }),
      task({ id: "vortag", title: "Flug", due: "2026-10-07", time: "09:00", remind: 1440 }),
      task({ id: "pille", title: "Tabletten", due: "2026-10-06", time: "20:00", repeat: "daily", remind: 0 }),
      task({ id: "fertig", title: "Erledigt", due: "2026-10-06", time: "16:00", done: T0 }),
      task({ id: "ganztag", title: "Domain verbinden", due: "2026-10-07", prio: 3 }),
    ];
    return state({ bags: [b], tasks });
  };

  test("Aufgaben-Erinnerungen: Standard-Vorlauf, −1, Vortag, Vergangenes, Erledigtes", () => {
    const plan = pm.reminderPlan(scene(), NOW);
    const call = plan.find((x) => x.tag === "task-call");
    assert.equal(call.at, at(6, 13, 45).getTime());
    assert.equal(call.kind, "task");
    assert.equal(call.taskId, "call");
    assert.equal(call.title, "Call mit Notar");
    assert.equal(call.body, "14:00 Uhr (in 15 Min.) · 🚀 AKYTEX");
    assert.equal(plan.find((x) => x.tag === "task-vortag").at, T0); // genau jetzt → noch dabei
    assert.equal(plan.find((x) => x.tag === "task-vortag").body, "Morgen, 9:00 Uhr");
    for (const tag of ["task-vorbei", "task-still", "task-fertig"]) assert.equal(plan.some((x) => x.tag === tag), false);
  });

  test("Wiederholungen: kommende Termine im Horizont", () => {
    const tags = pm.reminderPlan(scene(), NOW).filter((x) => x.taskId === "pille").map((x) => x.tag);
    assert.deepEqual(tags, ["task-pille", "task-pille-2026-10-07", "task-pille-2026-10-08"]);
  });

  test("Briefing täglich um dayStart mit den wichtigsten Titeln, Feierabend nur bei offenen Aufgaben", () => {
    const plan = pm.reminderPlan(scene(), NOW);
    const briefs = plan.filter((x) => x.kind === "briefing");
    assert.deepEqual(briefs.map((x) => x.tag), ["briefing-2026-10-07", "briefing-2026-10-08", "briefing-2026-10-09"]);
    assert.equal(briefs[0].at, at(7, 8).getTime());
    assert.equal(briefs[0].title, "☀️ Dein Tag: 3 Aufgaben + 3 überfällig");
    assert.equal(briefs[0].body, "• Call mit Notar (überfällig)\n• Schon vorbei (überfällig)\n• Tabletten (überfällig)\n+ 3 weitere");
    const eve = plan.filter((x) => x.kind === "evening");
    assert.deepEqual(eve.map((x) => x.tag), ["evening-2026-10-06", "evening-2026-10-07", "evening-2026-10-08"]);
    assert.equal(eve[0].at, at(6, 18).getTime());
    assert.match(eve[0].title, /^🌙 Feierabend: 3 Aufgaben offen$/);
    assert.match(eve[0].body, /– erledigen oder auf morgen schieben\?$/);
  });

  test("sortiert, nur Zukunft (−60 s), Horizont über days", () => {
    const plan = pm.reminderPlan(scene(), NOW);
    for (let i = 1; i < plan.length; i++) assert.ok(plan[i - 1].at <= plan[i].at);
    assert.ok(plan.every((x) => x.at > T0 - 60000 && x.at <= T0 + 3 * DAY));
    const short = pm.reminderPlan(scene(), NOW, { days: 1 });
    assert.ok(short.every((x) => x.at <= T0 + DAY));
    assert.ok(short.length < plan.length);
  });

  test("Rückblick am Rückblick-Tag zum Feierabend (ersetzt den Feierabend-Hinweis); nicht, wenn schon erledigt", () => {
    const st = scene();
    const plan = pm.reminderPlan(st, NOW, { days: 4 });
    const rv = plan.find((x) => x.kind === "review");
    assert.equal(rv.tag, "review-2026-10-09");
    assert.equal(rv.at, at(9, 18).getTime());
    assert.equal(rv.title, "🧭 Zeit für deinen Wochenrückblick");
    assert.equal(plan.some((x) => x.tag === "evening-2026-10-09"), false);
    st.meta.lastReview = "2026-10-05";
    assert.equal(pm.reminderPlan(st, NOW, { days: 4 }).some((x) => x.kind === "review"), false);
  });

  test("Briefing/Feierabend abschaltbar; Wochenende ohne Fälliges bleibt still", () => {
    const st = scene();
    st.profile.briefing = false;
    st.profile.evening = false;
    assert.deepEqual([...new Set(pm.reminderPlan(st, NOW).map((x) => x.kind))], ["task"]);
    const fri = at(9, 20);
    const quiet = pm.reminderPlan(state({ profile: { reviewDay: 3 } }), fri, { days: 3 });
    assert.deepEqual(quiet.map((x) => x.tag), ["briefing-2026-10-12"]);
    assert.equal(quiet[0].title, "☀️ Guten Morgen, Leo");
    // Überfälliges allein löst am Wochenende weder Briefing noch Feierabend aus – Fälliges am Samstag schon
    const st2 = state({ profile: { reviewDay: 3 }, tasks: [task({ title: "alt", due: "2026-10-01" }), task({ title: "Sa-Termin", due: "2026-10-10" })] });
    assert.deepEqual(pm.reminderPlan(st2, fri, { days: 3 }).map((x) => x.tag), ["briefing-2026-10-10", "evening-2026-10-10", "briefing-2026-10-12", "evening-2026-10-12"]);
  });
});

// ---------- Zähler ----------
describe("badgeCount", () => {
  test("überfällig + heute fällig + heute eingeplant, ohne Doppelte", () => {
    const tasks = [
      task({ due: "2026-10-01" }),
      task({ due: "2026-10-06" }),
      task({ due: "2026-10-06", plan: "2026-10-06" }),
      task({ plan: "2026-10-06" }),
      task({ plan: "2026-10-04" }), // liegengeblieben zählt weiter
      task({ due: "2026-10-06", done: T0 }),
      task({ due: "2026-10-06", deleted: T0 }),
      task({ plan: "2026-10-06", someday: true }),
      task({ due: "2026-10-07" }),
    ];
    assert.equal(pm.badgeCount(state({ tasks }), NOW), 5);
    assert.equal(pm.badgeCount(state(), NOW), 0);
  });
});
