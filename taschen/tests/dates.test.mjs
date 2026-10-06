// Tests für dates.js – Kalenderrechnung, Formatierung und deutsche Schnellerfassung (feste Zeitzone Europe/Berlin)
process.env.TZ = "Europe/Berlin";
import { test, describe } from "node:test";
import assert from "node:assert/strict";

const d = await import("../js/dates.js");

// Di., 6. Oktober 2026, 10:00 – KW 41 (Mo. 5.10. – So. 11.10.)
const NOW = new Date(2026, 9, 6, 10, 0);
const PROFILE = { dayStart: "08:00", dayEnd: "18:00", defaultRemind: 15, weekStart: 1 };
const BAGS = [
  { id: "b-firma", name: "Firmengründung", status: "aktiv", sections: ["Notar", "Bank"] },
  { id: "b-mkt", name: "Marketing & Clips", status: "aktiv" },
  { id: "b-trade", name: "Trading-Akademie", status: "aktiv" },
  { id: "b-aky", name: "AKYTEX Plattform & Go-Live", status: "aktiv" },
  { id: "b-nova", name: "NOVA – KI-Assistent", status: "aktiv" },
  { id: "b-pay", name: "Zahlungen & Stripe", status: "aktiv", sections: ["Stripe-Konto", "Kaufprüfung"] },
  { id: "b-old", name: "Marktanalyse", status: "fertig" },
];
const pq = (text, now = NOW, profile = PROFILE) => d.parseQuick(text, { bags: BAGS, now, profile });

// ---------- Grundlagen ----------
describe("Kalender-Grundlagen", () => {
  test("toISO/fromISO/todayISO arbeiten mit lokalen Kalendertagen", () => {
    assert.equal(d.todayISO(NOW), "2026-10-06");
    assert.equal(d.toISO(new Date(2026, 0, 1, 0, 0)), "2026-01-01");
    assert.equal(d.toISO(new Date(2026, 11, 31, 23, 59)), "2026-12-31");
    assert.equal(d.toISO("2026-10-06"), "2026-10-06");
    assert.equal(d.toISO(NOW.getTime()), "2026-10-06");
    assert.equal(d.toISO("Quatsch"), null);
    assert.equal(d.toISO(new Date(NaN)), null);
    const f = d.fromISO("2026-03-29");
    assert.equal(f.getHours(), 0);
    assert.equal(f.getDate(), 29);
    assert.ok(Number.isNaN(d.fromISO("2026-02-30").getTime()));
  });

  test("isISO prüft echte Kalendertage (Schaltjahre, Monatsenden)", () => {
    assert.equal(d.isISO("2028-02-29"), true);
    assert.equal(d.isISO("2026-02-29"), false);
    assert.equal(d.isISO("2026-04-31"), false);
    assert.equal(d.isISO("2026-13-01"), false);
    assert.equal(d.isISO("26-10-06"), false);
    assert.equal(d.isISO(null), false);
  });

  test("addDays über Monats-, Jahres- und Sommerzeitgrenzen", () => {
    assert.equal(d.addDays("2026-01-31", 1), "2026-02-01");
    assert.equal(d.addDays("2026-12-31", 1), "2027-01-01");
    assert.equal(d.addDays("2026-03-01", -1), "2026-02-28");
    assert.equal(d.addDays("2028-03-01", -1), "2028-02-29");
    assert.equal(d.addDays("2026-03-28", 1), "2026-03-29"); // Sommerzeit beginnt
    assert.equal(d.addDays("2026-03-29", 1), "2026-03-30");
    assert.equal(d.addDays("2026-10-24", 2), "2026-10-26"); // Sommerzeit endet am 25.10.
    assert.equal(d.addDays("2026-10-06", 0), "2026-10-06");
    assert.equal(d.addDays("kaputt", 1), null);
  });

  test("diffDays zählt Kalendertage, nicht 24-Stunden-Blöcke", () => {
    assert.equal(d.diffDays("2026-03-28", "2026-03-30"), 2);
    assert.equal(d.diffDays("2026-10-25", "2026-10-26"), 1);
    assert.equal(d.diffDays("2026-10-06", "2026-10-01"), -5);
    assert.equal(d.diffDays("2028-02-28", "2028-03-01"), 2);
    assert.equal(d.diffDays("2026-12-31", "2027-01-01"), 1);
    assert.equal(d.diffDays(new Date(2026, 9, 6, 23, 59), new Date(2026, 9, 7, 0, 1)), 1);
  });

  test("weekday, startOfWeek, isoWeek, isWeekend", () => {
    assert.equal(d.weekday("2026-10-06"), 2);
    assert.equal(d.weekday("2026-10-11"), 0);
    assert.equal(d.startOfWeek("2026-10-06"), "2026-10-05");
    assert.equal(d.startOfWeek("2026-10-11"), "2026-10-05");
    assert.equal(d.startOfWeek("2026-10-06", 0), "2026-10-04");
    assert.equal(d.isoWeek("2026-10-06"), 41);
    assert.equal(d.isoWeek("2026-12-31"), 53);
    assert.equal(d.isoWeek("2027-01-01"), 53);
    assert.equal(d.isoWeek("2027-01-04"), 1);
    assert.equal(d.isoWeekStart(2026, 42), "2026-10-12");
    assert.equal(d.isWeekend("2026-10-10"), true);
    assert.equal(d.isWeekend("2026-10-09"), false);
  });

  test("addMonths klammert ans Monatsende, endOfMonth", () => {
    assert.equal(d.addMonths("2026-01-31", 1), "2026-02-28");
    assert.equal(d.addMonths("2028-01-31", 1), "2028-02-29");
    assert.equal(d.addMonths("2026-12-15", 2), "2027-02-15");
    assert.equal(d.addMonths("2026-02-28", 1, 31), "2026-03-31");
    assert.equal(d.endOfMonth("2026-02-10"), "2026-02-28");
    assert.equal(d.endOfMonth("2028-02-10"), "2028-02-29");
  });
});

// ---------- Wiederholungen ----------
describe("nextOccurrence", () => {
  test("täglich: echt nach max(iso, after)", () => {
    assert.equal(d.nextOccurrence("2026-10-06", "daily"), "2026-10-07");
    assert.equal(d.nextOccurrence("2026-10-01", "daily", "2026-10-06"), "2026-10-07");
    assert.equal(d.nextOccurrence("2026-10-10", "daily", "2026-10-06"), "2026-10-11");
  });

  test("werktags überspringt Samstag und Sonntag", () => {
    assert.equal(d.nextOccurrence("2026-10-09", "weekdays"), "2026-10-12"); // Fr → Mo
    assert.equal(d.nextOccurrence("2026-10-10", "weekdays"), "2026-10-12"); // Sa → Mo
    assert.equal(d.nextOccurrence("2026-10-06", "weekdays"), "2026-10-07");
  });

  test("wöchentlich/zweiwöchentlich bleibt im Rhythmus, auch wenn überfällig", () => {
    assert.equal(d.nextOccurrence("2026-10-05", "weekly"), "2026-10-12");
    assert.equal(d.nextOccurrence("2026-09-07", "weekly", "2026-10-06"), "2026-10-12"); // Montags-Serie
    assert.equal(d.nextOccurrence("2026-09-28", "weekly", "2026-10-05"), "2026-10-12"); // genau auf after → nächste
    assert.equal(d.nextOccurrence("2026-10-01", "biweekly"), "2026-10-15");
    assert.equal(d.nextOccurrence("2026-09-03", "biweekly", "2026-10-06"), "2026-10-15");
  });

  test("monatlich: Monatsende-Klammer und Ankertag", () => {
    assert.equal(d.nextOccurrence("2026-01-31", "monthly"), "2026-02-28");
    assert.equal(d.nextOccurrence("2028-01-31", "monthly"), "2028-02-29");
    assert.equal(d.nextOccurrence("2026-02-28", "monthly", undefined, 31), "2026-03-31");
    assert.equal(d.nextOccurrence("2026-03-31", "monthly"), "2026-04-30");
    assert.equal(d.nextOccurrence("2026-06-15", "monthly", "2026-10-06"), "2026-10-15");
    assert.equal(d.nextOccurrence("2026-06-15", "monthly", "2026-10-15"), "2026-11-15");
  });

  test("jährlich: 29. Februar → 28. Februar in Nicht-Schaltjahren", () => {
    assert.equal(d.nextOccurrence("2028-02-29", "yearly"), "2029-02-28");
    assert.equal(d.nextOccurrence("2029-02-28", "yearly", undefined, 29), "2030-02-28");
    assert.equal(d.nextOccurrence("2031-02-28", "yearly", undefined, 29), "2032-02-29");
    assert.equal(d.nextOccurrence("2020-05-03", "yearly", "2026-10-06"), "2027-05-03");
  });

  test("unbekannte Wiederholung oder kaputtes Datum → null", () => {
    assert.equal(d.nextOccurrence("2026-10-06", null), null);
    assert.equal(d.nextOccurrence("2026-10-06", "stündlich"), null);
    assert.equal(d.nextOccurrence("kaputt", "daily"), null);
    assert.equal(d.nextOccurrence("kaputt", "daily", "2026-10-06"), "2026-10-07");
  });
});

// ---------- Zeitpunkte ----------
describe("dueAt / remindAt", () => {
  test("dueAt mit und ohne Uhrzeit", () => {
    assert.equal(d.dueAt({ due: "2026-10-07", time: "14:30" }, PROFILE).getTime(), new Date(2026, 9, 7, 14, 30).getTime());
    assert.equal(d.dueAt({ due: "2026-10-07", time: null }, PROFILE).getTime(), new Date(2026, 9, 7, 8, 0).getTime());
    assert.equal(d.dueAt({ due: null }, PROFILE), null);
  });

  test("remindAt: Standard, eigene Minuten, 0, −1 und ohne Uhrzeit", () => {
    const base = { due: "2026-10-07", time: "14:30" };
    assert.equal(d.remindAt({ ...base, remind: null }, PROFILE).getTime(), new Date(2026, 9, 7, 14, 15).getTime());
    assert.equal(d.remindAt({ ...base, remind: 60 }, PROFILE).getTime(), new Date(2026, 9, 7, 13, 30).getTime());
    assert.equal(d.remindAt({ ...base, remind: 0 }, PROFILE).getTime(), new Date(2026, 9, 7, 14, 30).getTime());
    assert.equal(d.remindAt({ ...base, remind: -1 }, PROFILE), null);
    assert.equal(d.remindAt({ due: "2026-10-07", time: null, remind: 30 }, PROFILE), null);
  });

  test("remindAt über die Sommerzeit-Umstellung (lokale Uhrzeit bleibt richtig)", () => {
    const r = d.remindAt({ due: "2026-03-29", time: "09:00", remind: null }, PROFILE);
    assert.equal(r.getHours(), 8);
    assert.equal(r.getMinutes(), 45);
    const r2 = d.remindAt({ due: "2026-10-25", time: "09:00", remind: 1440 }, PROFILE);
    assert.equal(d.toISO(r2), "2026-10-24");
    assert.equal(r2.getHours(), 9);
  });
});

// ---------- Formatierung ----------
describe("Deutsche Formatierung", () => {
  test("relDay: alle Fälle", () => {
    assert.equal(d.relDay("2026-10-06", NOW), "Heute");
    assert.equal(d.relDay("2026-10-07", NOW), "Morgen");
    assert.equal(d.relDay("2026-10-08", NOW), "Übermorgen");
    assert.equal(d.relDay("2026-10-05", NOW), "Gestern");
    assert.equal(d.relDay("2026-10-09", NOW), "Freitag");
    assert.equal(d.relDay("2026-10-12", NOW), "Montag");
    assert.equal(d.relDay("2026-10-03", NOW), "vor 3 Tagen");
    assert.equal(d.relDay("2026-09-30", NOW), "vor 6 Tagen");
    assert.equal(d.relDay("2026-10-13", NOW), "13. Okt.");
    assert.equal(d.relDay("2027-10-12", NOW), "12. Okt. 2027");
    assert.equal(d.relDay("2026-09-29", NOW), "29. Sept.");
  });

  test("fmtDay, dateLabel", () => {
    assert.equal(d.fmtDay("2026-10-13", { now: NOW }), "Di., 13. Oktober");
    assert.equal(d.fmtDay("2026-10-13", { weekday: false, now: NOW }), "13. Oktober");
    assert.equal(d.fmtDay("2027-01-05", { now: NOW }), "Di., 5. Januar 2027");
    assert.equal(d.fmtDay("kaputt"), "");
    assert.equal(d.dateLabel(NOW), "Dienstag, 6. Oktober");
  });

  test("fmtTime, fmtDuration, fmtAgo", () => {
    assert.equal(d.fmtTime("09:05"), "9:05");
    assert.equal(d.fmtTime("14:30"), "14:30");
    assert.equal(d.fmtTime("25:00"), "");
    assert.equal(d.fmtDuration(90), "1 Std. 30 Min.");
    assert.equal(d.fmtDuration(45), "45 Min.");
    assert.equal(d.fmtDuration(120), "2 Std.");
    assert.equal(d.fmtDuration(null), "");
    assert.equal(d.fmtAgo(NOW.getTime() - 20000, NOW), "gerade eben");
    assert.equal(d.fmtAgo(NOW.getTime() - 5 * 60000, NOW), "vor 5 Min.");
    assert.equal(d.fmtAgo(NOW.getTime() - 3 * 3600000, NOW), "vor 3 Std.");
    assert.equal(d.fmtAgo(new Date(2026, 9, 5, 22).getTime(), NOW), "gestern");
  });

  test("greeting und daypart an den Grenzen", () => {
    const at = (h, m = 0) => new Date(2026, 9, 6, h, m);
    assert.equal(d.greeting(at(4, 59)), "Gute Nacht");
    assert.equal(d.greeting(at(5)), "Guten Morgen");
    assert.equal(d.greeting(at(10, 59)), "Guten Morgen");
    assert.equal(d.greeting(at(11)), "Guten Tag");
    assert.equal(d.greeting(at(16, 59)), "Guten Tag");
    assert.equal(d.greeting(at(17)), "Guten Abend");
    assert.equal(d.greeting(at(21, 59)), "Guten Abend");
    assert.equal(d.greeting(at(22)), "Gute Nacht");
    assert.equal(d.daypart(at(8)), "morning");
    assert.equal(d.daypart(at(13)), "day");
    assert.equal(d.daypart(at(19)), "evening");
    assert.equal(d.daypart(at(2)), "night");
  });
});

// ---------- Taschen-Abgleich ----------
describe("matchBag", () => {
  test("exakt, Präfix, Wortpräfix, Teilwort; aktive vor fertigen", () => {
    assert.equal(d.matchBag("Firmengründung", BAGS).id, "b-firma");
    assert.equal(d.matchBag("firm", BAGS).id, "b-firma");
    assert.equal(d.matchBag("gründ", BAGS).id, "b-firma"); // Teilwort im Kompositum
    assert.equal(d.matchBag("stripe", BAGS).id, "b-pay");
    assert.equal(d.matchBag("golive", BAGS).id, "b-aky");
    assert.equal(d.matchBag("ki", BAGS).id, "b-nova");
    assert.equal(d.matchBag("mark", BAGS).id, "b-mkt"); // aktiv schlägt „Marktanalyse“ (fertig)
    assert.equal(d.matchBag("x", BAGS), null);
    assert.equal(d.matchBag("zzz", BAGS), null);
  });
});

// ---------- Schnellerfassung ----------
const pick = (r) => Object.fromEntries(Object.entries(r).filter(([k, v]) => k !== "tokens" && !(v === null || v === "" || v === false || (Array.isArray(v) && !v.length) || (k === "prio" && v === 0))));

describe("parseQuick – Beispiele", () => {
  const cases = [
    ["Notar anrufen morgen 9 Uhr #Gründ !!", { title: "Notar anrufen", due: "2026-10-07", time: "09:00", prio: 2, bag: "b-firma", bagName: "Firmengründung" }],
    ["Reel schneiden heute abend #mark", { title: "Reel schneiden", due: "2026-10-06", time: "19:00", bag: "b-mkt", bagName: "Marketing & Clips" }],
    ["Lektion 4 aufnehmen bis Freitag #Trading ~2h", { title: "Lektion 4 aufnehmen", due: "2026-10-09", bag: "b-trade", bagName: "Trading-Akademie", est: 120 }],
    ["Unterlagen an Steuerberater übermorgen um 14:30 erinnere 1 Stunde vorher", { title: "Unterlagen an Steuerberater", due: "2026-10-08", time: "14:30", remind: 60 }],
    ["Wochenplanung jeden Montag 8 Uhr", { title: "Wochenplanung", due: "2026-10-12", time: "08:00", repeat: "weekly" }],
    ["Newsletter schreiben Freitag", { title: "Newsletter schreiben", due: "2026-10-09" }],
    ["Newsletter schreiben nächsten Freitag", { title: "Newsletter schreiben", due: "2026-10-16" }],
    ["Newsletter am Fr", { title: "Newsletter", due: "2026-10-09" }],
    ["Domain verlängern 15.10.", { title: "Domain verlängern", due: "2026-10-15" }],
    ["Domain verlängern 3.1.", { title: "Domain verlängern", due: "2027-01-03" }],
    ["Jahresabschluss 31.03.2027 !!!", { title: "Jahresabschluss", due: "2027-03-31", prio: 3 }],
    ["Vertrag 15.10.26 prüfen", { title: "Vertrag prüfen", due: "2026-10-15" }],
    ["Launch 2026-11-02", { title: "Launch", due: "2026-11-02" }],
    ["Pitch 15. Oktober", { title: "Pitch", due: "2026-10-15" }],
    ["Messe 1. Januar 2027", { title: "Messe", due: "2027-01-01" }],
    ["Deploy am 20.10 um 9:30", { title: "Deploy", due: "2026-10-20", time: "09:30" }],
    ["API-Kosten prüfen in 3 Tagen @Mac", { title: "API-Kosten prüfen", due: "2026-10-09", tags: ["Mac"] }],
    ["Review in 2 Wochen", { title: "Review", due: "2026-10-20" }],
    ["Steuer in einem Monat", { title: "Steuer", due: "2026-11-06" }],
    ["Sprint nächste Woche", { title: "Sprint", due: "2026-10-12" }],
    ["Sprint übernächste Woche", { title: "Sprint", due: "2026-10-19" }],
    ["Review Ende nächster Woche", { title: "Review", due: "2026-10-16" }],
    ["Präsentation Ende der Woche", { title: "Präsentation", due: "2026-10-09" }],
    ["Urlaub planen am Wochenende", { title: "Urlaub planen", due: "2026-10-10" }],
    ["Bericht Monatsende", { title: "Bericht", due: "2026-10-31" }],
    ["Steuer KW 42", { title: "Steuer", due: "2026-10-12" }],
    ["Rechnung schreiben am 15.", { title: "Rechnung schreiben", due: "2026-10-15" }],
    ["Kündigen bis 30.11.", { title: "Kündigen", due: "2026-11-30" }],
    ["Steuer bis spätestens Freitag", { title: "Steuer", due: "2026-10-09" }],
    ["Abgabe übermorgen", { title: "Abgabe", due: "2026-10-08" }],
    ["Abgabe uebermorgen", { title: "Abgabe", due: "2026-10-08" }],
    ["Webinar Do 19 Uhr", { title: "Webinar", due: "2026-10-08", time: "19:00" }],
    ["Gym Sa", { title: "Gym", due: "2026-10-10" }],
  ];
  for (const [input, want] of cases) test(`„${input}“`, () => assert.deepEqual(pick(pq(input)), want));
});

describe("parseQuick – Uhrzeiten", () => {
  const cases = [
    ["Call mit Investor um 3", { title: "Call mit Investor", due: "2026-10-06", time: "15:00" }], // PM-Regel
    ["Backup machen 8 Uhr", { title: "Backup machen", due: "2026-10-07", time: "08:00" }], // heute schon vorbei → morgen
    ["heute 8 Uhr Backup", { title: "Backup", due: "2026-10-06", time: "08:00" }], // ausdrücklich heute bleibt heute
    ["Call 14.30 Uhr", { title: "Call", due: "2026-10-06", time: "14:30" }],
    ["um 14.30 Call", { title: "Call", due: "2026-10-06", time: "14:30" }],
    ["Standup 9:15", { title: "Standup", due: "2026-10-07", time: "09:15" }],
    ["Notar morgen 9", { title: "Notar", due: "2026-10-07", time: "09:00" }],
    ["Treffen halb 3", { title: "Treffen", due: "2026-10-06", time: "14:30" }],
    ["Treffen viertel nach 4", { title: "Treffen", due: "2026-10-06", time: "16:15" }],
    ["Meeting 14-15 Uhr", { title: "Meeting", due: "2026-10-06", time: "14:00", est: 60 }],
    ["Meeting in 30 min", { title: "Meeting", due: "2026-10-06", time: "10:30" }],
    ["in einer halben Stunde Pause", { title: "Pause", due: "2026-10-06", time: "10:30" }],
    ["Joggen morgen früh", { title: "Joggen", due: "2026-10-07", time: "08:00" }],
    ["Lesen abends", { title: "Lesen", due: "2026-10-06", time: "19:00" }],
    ["Lesen abends um 8", { title: "Lesen", due: "2026-10-06", time: "20:00" }],
    ["um 3 Uhr nachts Backup", { title: "Backup", due: "2026-10-07", time: "03:00" }],
    ["Call um 06:00", { title: "Call", due: "2026-10-07", time: "06:00" }], // führende Null: keine PM-Regel
  ];
  for (const [input, want] of cases) test(`„${input}“`, () => assert.deepEqual(pick(pq(input)), want));

  test("Uhrzeit ohne Datum kurz vor Mitternacht → morgen", () => {
    const r = pq("Meeting 23:30", new Date(2026, 9, 6, 23, 45));
    assert.equal(r.due, "2026-10-07");
    assert.equal(r.time, "23:30");
  });
  test("„in 30 min“ über Mitternacht → morgen", () => {
    const r = pq("Pause in 30 min", new Date(2026, 9, 6, 23, 50));
    assert.equal(r.due, "2026-10-07");
    assert.equal(r.time, "00:20");
  });
});

describe("parseQuick – Priorität, Tasche, Tags", () => {
  const cases = [
    ["Steuer zahlen!!", { title: "Steuer zahlen", prio: 2 }],
    ["!!!Steuer zahlen", { title: "Steuer zahlen", prio: 3 }],
    ["Bug ! fixen", { title: "Bug fixen", prio: 1 }],
    ["Bug !hoch", { title: "Bug", prio: 3 }],
    ["Bug !wichtig", { title: "Bug", prio: 3 }],
    ["Bug !mittel", { title: "Bug", prio: 2 }],
    ["Bug !niedrig", { title: "Bug", prio: 1 }],
    ["Wichtig: Vertrag lesen", { title: "Vertrag lesen", prio: 3 }],
    ["Steuer dringend zahlen", { title: "Steuer zahlen", prio: 3 }],
    ["p1 Bug fixen", { title: "Bug fixen", prio: 3 }],
    ["Bug ! fixen !!!", { title: "Bug fixen", prio: 3 }], // höchste gewinnt
    ["#nova Feature bauen", { title: "Feature bauen", bag: "b-nova", bagName: "NOVA – KI-Assistent" }],
    ["#Zahlungen & Stripe Links eintragen", { title: "Links eintragen", bag: "b-pay", bagName: "Zahlungen & Stripe" }],
    ["Webhook testen #stripe/kauf", { title: "Webhook testen", bag: "b-pay", bagName: "Zahlungen & Stripe", section: "Kaufprüfung" }],
    ["Idee #foo #bar @home #foo", { title: "Idee", tags: ["foo", "bar", "home"] }],
    ["Post #AKYTEX #nova", { title: "Post", bag: "b-aky", bagName: "AKYTEX Plattform & Go-Live", tags: ["nova"] }], // nur das erste # ist eine Tasche
    ["Mail an max@firma.de schicken", { title: "Mail an max@firma.de schicken" }],
    ["Kurs-Idee: Optionen erklären irgendwann #Trading", { title: "Kurs-Idee: Optionen erklären", bag: "b-trade", bagName: "Trading-Akademie", someday: true }],
  ];
  for (const [input, want] of cases) test(`„${input}“`, () => assert.deepEqual(pick(pq(input)), want));
});

describe("parseQuick – Wiederholung, Erinnerung, Dauer, Planung", () => {
  const cases = [
    ["Wasser täglich", { title: "Wasser", due: "2026-10-06", repeat: "daily" }],
    ["Wasser jeden Tag 9 Uhr", { title: "Wasser", due: "2026-10-07", time: "09:00", repeat: "daily" }], // 9 Uhr heute vorbei
    ["Sport werktags 7 Uhr", { title: "Sport", due: "2026-10-07", time: "07:00", repeat: "weekdays" }],
    ["Retro jede Woche", { title: "Retro", due: "2026-10-06", repeat: "weekly" }],
    ["Retro wöchentlich", { title: "Retro", due: "2026-10-06", repeat: "weekly" }],
    ["Sync alle 2 Wochen", { title: "Sync", due: "2026-10-06", repeat: "biweekly" }],
    ["Miete monatlich", { title: "Miete", due: "2026-10-06", repeat: "monthly" }],
    ["Miete zahlen monatlich am 1.", { title: "Miete zahlen", due: "2026-11-01", repeat: "monthly" }],
    ["Abo jeden 15.", { title: "Abo", due: "2026-10-15", repeat: "monthly" }],
    ["Steuererklärung jährlich", { title: "Steuererklärung", due: "2026-10-06", repeat: "yearly" }],
    ["Instagram posten montags 18 Uhr ohne Erinnerung", { title: "Instagram posten", due: "2026-10-12", time: "18:00", remind: -1, repeat: "weekly" }],
    ["Tabletten jeden Morgen", { title: "Tabletten", due: "2026-10-07", time: "08:00", repeat: "daily" }],
    ["Call 30 min vorher", { title: "Call", remind: 30 }],
    ["Call morgen 14 Uhr erinnere mich 2 Std vorher", { title: "Call", due: "2026-10-07", time: "14:00", remind: 120 }],
    ["Call morgen 14 Uhr eine halbe Stunde vorher", { title: "Call", due: "2026-10-07", time: "14:00", remind: 30 }],
    ["Flug morgen 14 Uhr 1 Tag vorher", { title: "Flug", due: "2026-10-07", time: "14:00", remind: 1440 }],
    ["Doku ~30m", { title: "Doku", est: 30 }],
    ["Doku ~1,5h", { title: "Doku", est: 90 }],
    ["Doku (45 min)", { title: "Doku", est: 45 }],
    ["Doku dauert 2 Std", { title: "Doku", est: 120 }],
    ["Plan dauert eine halbe Stunde", { title: "Plan", est: 30 }],
    ["Doku für 45 min", { title: "Doku", est: 45 }],
    ["Lesen ~45 *", { title: "Lesen", est: 45, plan: true }],
    ["Steuer heute einplanen", { title: "Steuer", plan: true }],
    ["Pitch Deck fertig // Folien 3-7 überarbeiten, Zahlen Q3", { title: "Pitch Deck fertig", notes: "Folien 3-7 überarbeiten, Zahlen Q3" }],
    ["Wartet auf Steuernummer vom Finanzamt #Gründ", { title: "Wartet auf Steuernummer vom Finanzamt", bag: "b-firma", bagName: "Firmengründung", waiting: "Steuernummer vom Finanzamt" }],
  ];
  for (const [input, want] of cases) test(`„${input}“`, () => assert.deepEqual(pick(pq(input)), want));
});

describe("parseQuick – bleibt Text (Fehlerfälle)", () => {
  const literal = [
    "Release 1.5 vorbereiten",
    "Version 2.0 testen",
    "So wird's gemacht: Pitch üben",
    "Termin 31.02. beim Arzt",
    "am 31.11. Termin",
    "Folien 3-7 überarbeiten",
    "3 Tage Urlaub planen",
    "Anrufen!",
    "Guten Morgen sagen",
    "Test 24 Uhr",
    "Morgenroutine aufschreiben",
    "„Morgen“-Kampagne planen",
    "Termin ansehen https://notar.de/morgen-um-9",
    "#1 Priorität klären",
  ];
  for (const input of literal) {
    test(`„${input}“ bleibt unverändert`, () => {
      const r = pq(input);
      assert.equal(r.title, input);
      assert.equal(r.due, null);
      assert.equal(r.time, null);
      assert.equal(r.prio, 0);
      assert.deepEqual(r.tokens, []);
    });
  }

  test("„irgendwann morgen“: Datum gewinnt, leerer Titel → Originaltext", () => {
    const r = pq("irgendwann morgen");
    assert.equal(r.due, "2026-10-07");
    assert.equal(r.someday, false);
    assert.equal(r.title, "irgendwann morgen");
  });

  test("Leere und kaputte Eingaben werfen nie", () => {
    assert.equal(pq("").title, "");
    assert.equal(d.parseQuick(null).title, "");
    assert.equal(d.parseQuick(undefined, {}).title, "");
    assert.equal(pq("   ").title, "");
    assert.equal(d.parseQuick("morgen 9 Uhr", { bags: null, now: "kaputt" }).time, "09:00");
    assert.doesNotThrow(() => pq("!!!! #### @@@ ~~~ ((( „“ 99:99 32.13. KW 99"));
  });
});

describe("parseQuick – Tokens & Wochentage", () => {
  test("Tokens tragen Typ, Text und Position im Original", () => {
    const text = "Notar anrufen morgen 9 Uhr #Gründ !!";
    const r = pq(text);
    assert.deepEqual(r.tokens.map((t) => t.type), ["date", "time", "bag", "prio"]);
    for (const t of r.tokens) assert.equal(text.slice(t.start, t.end), t.text);
    assert.equal(r.tokens[0].text, "morgen");
    assert.equal(r.tokens[2].text, "#Gründ");
  });

  test("Präposition wird mit verschluckt („bis Freitag“, „am 15.10.“)", () => {
    assert.equal(pq("Bericht bis Freitag").tokens[0].text, "bis Freitag");
    assert.equal(pq("Termin am 15.10.").tokens[0].text, "am 15.10.");
  });

  test("Wochentag am selben Tag zählt nicht – heute Dienstag → nächster Dienstag", () => {
    assert.equal(pq("Meeting Dienstag").due, "2026-10-13");
    assert.equal(pq("Meeting heute").due, "2026-10-06");
  });

  test("„jeden Montag“ an einem Montag vor der Uhrzeit → heute", () => {
    const monday = new Date(2026, 9, 5, 7, 0);
    assert.equal(pq("Wochenplanung jeden Montag 8 Uhr", monday).due, "2026-10-05");
    assert.equal(pq("Wochenplanung jeden Montag 8 Uhr", new Date(2026, 9, 5, 9, 0)).due, "2026-10-12");
  });

  test("am Wochenende selbst bedeutet „Wochenende“ heute", () => {
    assert.equal(pq("Aufräumen am Wochenende", new Date(2026, 9, 10, 10)).due, "2026-10-10");
    assert.equal(pq("Aufräumen am Wochenende", new Date(2026, 9, 11, 10)).due, "2026-10-11");
  });

  test("Ende der Woche am Samstag → heute; Wochenstart Sonntag verschiebt „nächste Woche“", () => {
    assert.equal(pq("Bericht Ende der Woche", new Date(2026, 9, 10, 10)).due, "2026-10-10");
    assert.equal(pq("Sprint nächste Woche", NOW, { ...PROFILE, weekStart: 0 }).due, "2026-10-12");
  });

  test("Monatsende im Februar eines Schaltjahrs, Datum ohne Jahr in der Vergangenheit → nächstes Jahr", () => {
    assert.equal(pq("Bericht Monatsende", new Date(2028, 1, 10, 9)).due, "2028-02-29");
    assert.equal(pq("Party 29.02.", new Date(2027, 5, 1, 9)).due, "2028-02-29");
    assert.equal(pq("Party 5.10.").due, "2027-10-05");
  });
});
