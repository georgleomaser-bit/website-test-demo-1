// Tests für den Kalender-Teil von remind.js – RFC 5545: Format, Faltung, Escaping, Ganztag, Wecker, UID, Tagesbriefing, Meilensteine, Kurzbefehl
process.env.TZ = "Europe/Berlin";
import { test, describe } from "node:test";
import assert from "node:assert/strict";

const { icsForTasks, icsDaily, icsForMilestones, icsFold, icsText, icsDuration, icsRrule, remindersShortcutUrl } = await import("../js/remind.js");
const { DEFAULT_PROFILE } = await import("../js/config.js");

// ---------- Helfer ----------
const NOW = new Date(2026, 9, 6, 10, 0, 0); // Di., 6. Oktober 2026, 10:00 (Sommerzeit)
const APP = "https://georgleomaser-bit.github.io/website-test-demo-1/taschen/";
const unfold = (s) => s.replace(/\r\n[ \t]/g, "");
const lines = (s) => unfold(s).split("\r\n").filter(Boolean);
// Eigenschaften außerhalb der VALARM-Blöcke (dort gibt es eine eigene DESCRIPTION)
const outside = (s) => {
  let inAlarm = false;
  return lines(s).filter((l) => (l === "BEGIN:VALARM" ? ((inAlarm = true), false) : l === "END:VALARM" ? ((inAlarm = false), false) : !inAlarm));
};
const prop = (s, name) => outside(s).filter((l) => l.startsWith(name + ":") || l.startsWith(name + ";"));
const one = (s, name) => {
  const p = prop(s, name);
  assert.equal(p.length, 1, `genau eine ${name}-Zeile erwartet, gefunden: ${p.length}`);
  return p[0].slice(p[0].indexOf(":") + 1);
};
const bytes = (s) => Buffer.byteLength(s, "utf8");
const LONE = /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/;
const task = (patch = {}) => ({
  id: "t_abc123",
  created: 1759700000000,
  updated: 1759740000000,
  deleted: null,
  bag: "b_1",
  title: "Pitch-Deck fertig",
  notes: "",
  done: null,
  prio: 0,
  due: "2026-10-15",
  time: null,
  remind: null,
  repeat: null,
  section: "",
  tags: [],
  subtasks: [],
  plan: null,
  someday: false,
  order: 1,
  est: null,
  waiting: "",
  milestone: null,
  ...patch,
});
const bagsById = { b_1: { id: "b_1", name: "AKYTEX", emoji: "📈" } };
const profile = { ...DEFAULT_PROFILE };

function assertWellFormed(ics) {
  assert.ok(ics.startsWith("BEGIN:VCALENDAR\r\n"), "beginnt mit BEGIN:VCALENDAR");
  assert.ok(ics.endsWith("END:VCALENDAR\r\n"), "endet mit END:VCALENDAR + CRLF");
  assert.ok(!/[^\r]\n/.test(ics) && !/\r(?!\n)/.test(ics), "nur CRLF als Zeilenende");
  for (const l of ics.split("\r\n")) {
    assert.ok(bytes(l) <= 75, `Zeile länger als 75 Oktette (${bytes(l)}): ${l}`);
    assert.ok(!LONE.test(l), "kein halbes UTF-16-Zeichen in einer Zeile");
  }
  const L = lines(ics);
  for (const k of ["VCALENDAR", "VEVENT", "VALARM"]) assert.equal(L.filter((l) => l === `BEGIN:${k}`).length, L.filter((l) => l === `END:${k}`).length, `BEGIN/END:${k} ausgeglichen`);
}

// ---------- Format ----------
describe("Kalender-Grundformat", () => {
  test("VCALENDAR mit VERSION, PRODID, METHOD:PUBLISH und Kalendername; CRLF überall", () => {
    const ics = icsForTasks([task()], { bagsById, profile, calName: "Meine, Taschen; neu", appUrl: APP, now: NOW });
    assertWellFormed(ics);
    const L = lines(ics);
    assert.equal(L[1], "VERSION:2.0");
    assert.ok(L.some((l) => /^PRODID:.+/.test(l)));
    assert.ok(L.includes("METHOD:PUBLISH"));
    assert.ok(L.includes("CALSCALE:GREGORIAN"));
    assert.equal(one(ics, "X-WR-CALNAME"), "Meine\\, Taschen\\; neu");
    assert.ok(!/TZID|VTIMEZONE/.test(ics), "kein TZID/VTIMEZONE");
  });

  test("DTSTAMP in UTC, stabile UID mit Revision", () => {
    const t = task();
    const ics = icsForTasks([t], { bagsById, profile, appUrl: APP, now: NOW });
    assert.equal(one(ics, "DTSTAMP"), "20261006T080000Z");
    assert.equal(one(ics, "UID"), "t_abc123-r1759740000000@arbeitstaschen");
    // gleiche Fassung → gleiche UID; neue Fassung → neue UID (Apple aktualisiert gleiche UIDs beim Import nicht zuverlässig)
    assert.equal(one(icsForTasks([t], { now: new Date() }), "UID"), "t_abc123-r1759740000000@arbeitstaschen");
    assert.equal(one(icsForTasks([task({ updated: 1759740009999 })], { now: NOW }), "UID"), "t_abc123-r1759740009999@arbeitstaschen");
  });

  test("Aufgaben ohne Datum, gelöschte und leere werden übersprungen", () => {
    const ics = icsForTasks([task({ id: "a", due: null }), task({ id: "b", deleted: 1 }), task({ id: "c", title: "  " }), task({ id: "d", due: "2026-02-31" }), task({ id: "e" })], { now: NOW });
    assertWellFormed(ics);
    assert.equal(prop(ics, "UID").length, 1);
    assert.match(one(ics, "UID"), /^e-r/);
  });

  test("leere Liste ergibt einen gültigen, leeren Kalender", () => {
    const ics = icsForTasks([], { now: NOW });
    assertWellFormed(ics);
    assert.ok(!ics.includes("BEGIN:VEVENT"));
  });

  test("URL öffnet die Aufgabe in der App, Tasche als Kategorie, Priorität", () => {
    const ics = icsForTasks([task({ prio: 3 })], { bagsById, profile, appUrl: APP + "#heute", now: NOW });
    assert.equal(one(ics, "URL"), APP + "?task=t_abc123");
    assert.equal(one(ics, "CATEGORIES"), "AKYTEX");
    assert.equal(one(ics, "PRIORITY"), "1");
    assert.match(one(ics, "DESCRIPTION"), /📈 AKYTEX · Priorität hoch/);
    assert.match(one(ics, "DESCRIPTION"), /In Arbeitstaschen öffnen: https:\/\/georgleomaser-bit\.github\.io\/website-test-demo-1\/taschen\/\?task=t_abc123/);
    assert.equal(prop(icsForTasks([task()], { now: NOW }), "URL").length, 0, "ohne appUrl keine URL");
  });
});

// ---------- Faltung ----------
describe("Zeilenfaltung (75 Oktette, UTF-8-sicher)", () => {
  test("ASCII: erste Zeile 75, Folgezeilen 1 + 74 Oktette", () => {
    const line = "DESCRIPTION:" + "x".repeat(300);
    const f = icsFold(line);
    const parts = f.split("\r\n");
    assert.equal(bytes(parts[0]), 75);
    for (const p of parts.slice(1)) {
      assert.ok(p.startsWith(" "));
      assert.ok(bytes(p) <= 75);
    }
    assert.equal(unfold(f), line);
  });

  test("kurze Zeilen bleiben unverändert", () => {
    assert.equal(icsFold("SUMMARY:Kurz"), "SUMMARY:Kurz");
    const exact = "X:" + "a".repeat(73);
    assert.equal(icsFold(exact), exact);
  });

  test("Umlaute, Emojis und Zeichen mit 3 bzw. 4 Oktetten werden nie zerteilt", () => {
    for (let shift = 0; shift < 6; shift++) {
      const line = "SUMMARY:" + "a".repeat(shift) + "Größe ä ö ü ß – „Zitat“ 🚀👜💼 €".repeat(8);
      const f = icsFold(line);
      for (const p of f.split("\r\n")) {
        assert.ok(bytes(p) <= 75, `zu lang: ${bytes(p)}`);
        assert.ok(!LONE.test(p), "Surrogat-Paar getrennt");
        assert.equal(Buffer.from(p, "utf8").toString("utf8"), p, "gültiges UTF-8");
      }
      assert.equal(unfold(f), line, "Entfalten ergibt das Original");
    }
  });

  test("lange Titel und Notizen in einer echten Datei", () => {
    const t = task({ title: "Größter Kunde – „Q4-Angebot“ für die Expansion nach Österreich & Schweiz 🚀 mit allen Details", notes: "Zeile 1: Präsentation 📊\nZeile 2: Zahlen, Fakten; Ausblick\n\n" + "Lang ".repeat(60) });
    const ics = icsForTasks([t], { bagsById, profile, appUrl: APP, now: NOW });
    assertWellFormed(ics);
    assert.equal(one(ics, "SUMMARY"), icsText(t.title));
  });
});

// ---------- Escaping ----------
describe("Escaping von TEXT-Werten", () => {
  test("Komma, Semikolon, Backslash und Zeilenumbrüche; Doppelpunkt bleibt", () => {
    assert.equal(icsText("a,b;c\\d:e"), "a\\,b\\;c\\\\d:e");
    assert.equal(icsText("Zeile 1\nZeile 2\r\nZeile 3\rZeile 4"), "Zeile 1\\nZeile 2\\nZeile 3\\nZeile 4");
    assert.equal(icsText("Tab\tok\u0000\u0007weg"), "Tab\tokweg");
    assert.equal(icsText(null), "");
  });

  test("in SUMMARY und DESCRIPTION angewendet", () => {
    const ics = icsForTasks([task({ title: "Angebot, Preis; Pfad C:\\Daten", notes: "Erste Zeile\nZweite, mit Komma" })], { bagsById, profile, now: NOW });
    assert.equal(one(ics, "SUMMARY"), "Angebot\\, Preis\\; Pfad C:\\\\Daten");
    assert.match(one(ics, "DESCRIPTION"), /Erste Zeile\\nZweite\\, mit Komma/);
    // keine echten Zeilenumbrüche in Werten
    for (const l of lines(ics)) assert.ok(!l.includes("\n"));
  });
});

// ---------- Termine mit Uhrzeit ----------
describe("Aufgaben mit Uhrzeit", () => {
  test("DTSTART/DTEND in UTC (Sommerzeit), Dauer aus est, Wecker remind Minuten vorher", () => {
    const ics = icsForTasks([task({ time: "09:30", est: 45, remind: 20 })], { bagsById, profile, now: NOW });
    assert.equal(one(ics, "DTSTART"), "20261015T073000Z");
    assert.equal(one(ics, "DTEND"), "20261015T081500Z");
    const L = lines(ics);
    const a = L.indexOf("BEGIN:VALARM");
    assert.ok(a > 0, "VALARM vorhanden");
    const block = L.slice(a, L.indexOf("END:VALARM", a) + 1);
    assert.ok(block.includes("ACTION:DISPLAY"));
    assert.ok(
      block.some((l) => /^DESCRIPTION:.+/.test(l)),
      "DISPLAY braucht DESCRIPTION",
    );
    assert.ok(block.includes("TRIGGER:-PT20M"));
    assert.ok(!L.includes("TRANSP:TRANSPARENT"), "Termine mit Uhrzeit blockieren Zeit");
  });

  test("Winterzeit: 09:30 Ortszeit = 08:30 UTC; ohne est 30 Minuten", () => {
    const ics = icsForTasks([task({ due: "2026-11-15", time: "09:30" })], { profile, now: NOW });
    assert.equal(one(ics, "DTSTART"), "20261115T083000Z");
    assert.equal(one(ics, "DTEND"), "20261115T090000Z");
  });

  test("remind null → Standard aus dem Profil; 0 → zur Startzeit; −1 → kein Wecker", () => {
    assert.ok(lines(icsForTasks([task({ time: "14:00" })], { profile: { ...profile, defaultRemind: 10 }, now: NOW })).includes("TRIGGER:-PT10M"));
    assert.ok(lines(icsForTasks([task({ time: "14:00", remind: 0 })], { profile, now: NOW })).includes("TRIGGER:PT0M"));
    assert.ok(!icsForTasks([task({ time: "14:00", remind: -1 })], { profile, now: NOW }).includes("VALARM"));
    assert.ok(lines(icsForTasks([task({ time: "14:00", remind: 1440 })], { profile, now: NOW })).includes("TRIGGER:-PT1440M"));
  });

  test("erledigte Aufgaben ohne Wecker", () => {
    assert.ok(!icsForTasks([task({ time: "14:00", done: 1759750000000 })], { profile, now: NOW }).includes("VALARM"));
  });

  test("über Mitternacht und Jahreswechsel", () => {
    const ics = icsForTasks([task({ due: "2026-12-31", time: "23:30", est: 90 })], { profile, now: NOW });
    assert.equal(one(ics, "DTSTART"), "20261231T223000Z");
    assert.equal(one(ics, "DTEND"), "20270101T000000Z");
  });
});

// ---------- Ganztägig ----------
describe("Aufgaben ohne Uhrzeit (ganztägig)", () => {
  test("VALUE=DATE, DTEND = Folgetag, Wecker um dayStart", () => {
    const ics = icsForTasks([task({ due: "2026-10-31" })], { profile, now: NOW });
    const L = lines(ics);
    assert.ok(L.includes("DTSTART;VALUE=DATE:20261031"));
    assert.ok(L.includes("DTEND;VALUE=DATE:20261101"));
    assert.ok(L.includes("TRANSP:TRANSPARENT"));
    assert.ok(L.includes("TRIGGER:PT8H"));
    assert.ok(L.includes("ACTION:DISPLAY"));
  });

  test("dayStart 07:30 → PT7H30M; 00:00 → PT0M; Monats- und Jahreswechsel", () => {
    assert.ok(lines(icsForTasks([task()], { profile: { ...profile, dayStart: "07:30" }, now: NOW })).includes("TRIGGER:PT7H30M"));
    assert.ok(lines(icsForTasks([task()], { profile: { ...profile, dayStart: "00:00" }, now: NOW })).includes("TRIGGER:PT0M"));
    const L = lines(icsForTasks([task({ due: "2026-12-31" })], { profile, now: NOW }));
    assert.ok(L.includes("DTEND;VALUE=DATE:20270101"));
    assert.ok(lines(icsForTasks([task({ due: "2028-02-28" })], { profile, now: NOW })).includes("DTEND;VALUE=DATE:20280229"), "Schaltjahr");
  });

  test("remind −1 auch ganztägig: kein Wecker", () => {
    assert.ok(!icsForTasks([task({ remind: -1 })], { profile, now: NOW }).includes("VALARM"));
  });

  test("Dauer-Format für TRIGGER", () => {
    assert.equal(icsDuration(0), "PT0M");
    assert.equal(icsDuration(15), "PT15M");
    assert.equal(icsDuration(480), "PT8H");
    assert.equal(icsDuration(450), "PT7H30M");
    assert.equal(icsDuration(960), "PT16H");
    assert.equal(icsDuration(1440), "P1D");
    assert.equal(icsDuration(1500), "P1DT1H");
  });
});

// ---------- Wiederholungen ----------
describe("Wiederkehrende Aufgaben", () => {
  test("RRULE je Rhythmus", () => {
    assert.equal(icsRrule("daily", "2026-10-15"), "FREQ=DAILY");
    assert.equal(icsRrule("weekdays", "2026-10-15"), "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR");
    assert.equal(icsRrule("weekly", "2026-10-15"), "FREQ=WEEKLY");
    assert.equal(icsRrule("biweekly", "2026-10-15"), "FREQ=WEEKLY;INTERVAL=2");
    assert.equal(icsRrule("monthly", "2026-10-15"), "FREQ=MONTHLY");
    assert.equal(icsRrule("monthly", "2026-10-31"), "FREQ=MONTHLY;BYMONTHDAY=28,29,30,31;BYSETPOS=-1");
    assert.equal(icsRrule("monthly", "2026-10-30"), "FREQ=MONTHLY;BYMONTHDAY=28,29,30;BYSETPOS=-1");
    assert.equal(icsRrule("yearly", "2028-02-29"), "FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=28,29;BYSETPOS=-1");
    assert.equal(icsRrule(null, "2026-10-15"), null);
  });

  test("Serie mit Uhrzeit in lokaler Zeit (übersteht die Zeitumstellung), ganztägige Serie mit DATE", () => {
    const timed = icsForTasks([task({ time: "09:00", repeat: "weekly", est: 60 })], { profile, now: NOW });
    assert.equal(one(timed, "DTSTART"), "20261015T090000");
    assert.equal(one(timed, "DTEND"), "20261015T100000");
    assert.equal(one(timed, "RRULE"), "FREQ=WEEKLY");
    const allDay = icsForTasks([task({ repeat: "daily" })], { profile, now: NOW });
    assert.ok(lines(allDay).includes("DTSTART;VALUE=DATE:20261015"));
    assert.equal(one(allDay, "RRULE"), "FREQ=DAILY");
  });
});

// ---------- Tagesbriefing ----------
describe("Tagesbriefing (icsDaily)", () => {
  test("RRULE BYDAY aus den Arbeitstagen, Start um dayStart, Wecker PT0M", () => {
    const ics = icsDaily({ ...profile, dayStart: "07:45", workdays: [1, 2, 3, 4, 5] }, { appUrl: APP, now: NOW });
    assertWellFormed(ics);
    assert.equal(one(ics, "RRULE"), "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR");
    assert.equal(one(ics, "DTSTART"), "20261006T074500", "heute ist Dienstag (Arbeitstag)");
    assert.equal(one(ics, "DTEND"), "20261006T080000");
    const L = lines(ics);
    assert.ok(L.includes("TRIGGER:PT0M"));
    assert.ok(L.includes("ACTION:DISPLAY"));
    assert.equal(one(ics, "URL"), APP + "?view=heute");
    assert.match(one(ics, "SUMMARY"), /Tagesbriefing/);
  });

  test("Start am nächsten Arbeitstag; Reihenfolge Mo…So", () => {
    const ics = icsDaily({ ...profile, workdays: [6, 0, 3] }, { now: NOW });
    assert.equal(one(ics, "RRULE"), "FREQ=WEEKLY;BYDAY=WE,SA,SU");
    assert.equal(one(ics, "DTSTART"), "20261007T080000", "Mittwoch ist der nächste passende Tag");
  });

  test("ohne Arbeitstage: jeden Tag; stabile UID je Einstellung", () => {
    const a = icsDaily({ ...profile, workdays: [] }, { now: NOW });
    assert.equal(one(a, "RRULE"), "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR,SA,SU");
    const b = icsDaily({ ...profile, workdays: [1, 2, 3, 4, 5] }, { now: NOW });
    const c = icsDaily({ ...profile, workdays: [5, 4, 3, 2, 1] }, { now: new Date(2026, 9, 9) });
    assert.equal(one(b, "UID"), one(c, "UID"));
    assert.notEqual(one(b, "UID"), one(icsDaily({ ...profile, dayStart: "09:00" }, { now: NOW }), "UID"));
  });
});

// ---------- Meilensteine ----------
describe("Meilensteine", () => {
  const ms = (patch = {}) => ({ id: "m_1", created: 1, updated: 1759740000000, deleted: null, bag: "b_1", title: "Launch v2", date: "2026-11-02", done: null, ...patch });

  test("ganztägig mit Wecker am Vortag und am Tag", () => {
    const ics = icsForMilestones([ms()], { bagsById, appUrl: APP, now: NOW });
    assertWellFormed(ics);
    const L = lines(ics);
    assert.ok(L.includes("DTSTART;VALUE=DATE:20261102"));
    assert.ok(L.includes("DTEND;VALUE=DATE:20261103"));
    assert.ok(L.includes("TRIGGER:-PT16H"));
    assert.ok(L.includes("TRIGGER:PT8H"));
    assert.equal(one(ics, "SUMMARY"), "🏁 Launch v2 · AKYTEX");
    assert.equal(one(ics, "UID"), "m_1-r1759740000000@arbeitstaschen");
    assert.equal(one(ics, "URL"), APP + "?view=tasche%2Fb_1");
  });

  test("erledigt ohne Wecker, ohne Datum/gelöscht übersprungen", () => {
    const ics = icsForMilestones([ms({ done: 5 }), ms({ id: "m_2", date: null }), ms({ id: "m_3", deleted: 9 })], { bagsById, now: NOW });
    assert.equal(prop(ics, "UID").length, 1);
    assert.ok(!ics.includes("VALARM"));
  });
});

// ---------- Kurzbefehl ----------
describe("Kurzbefehl → Apple Erinnerungen", () => {
  test("shortcuts://-Adresse mit Zeilen „Datum|Titel|Tasche“, sortiert, ohne Trennzeichen im Titel", () => {
    const url = remindersShortcutUrl(
      [task({ id: "1", title: "Später", due: "2026-10-20", time: "14:15" }), task({ id: "2", title: "A|B\nC", due: "2026-10-10" }), task({ id: "3", title: "Ohne Datum", due: null, bag: null }), task({ id: "4", title: "Erledigt", done: 1 })],
      { bagsById, profile: { ...profile, dayStart: "07:00" } },
    );
    assert.ok(url.startsWith("shortcuts://run-shortcut?name=Taschen%20%E2%86%92%20Erinnerungen&input=text&text="));
    const text = decodeURIComponent(url.split("&text=")[1]);
    assert.deepEqual(text.split("\n"), ["2026-10-10T07:00|A B C|AKYTEX", "2026-10-20T14:15|Später|AKYTEX", "|Ohne Datum|"]);
  });

  test("eigener Name des Kurzbefehls", () => {
    assert.match(remindersShortcutUrl([], { name: "Meine Liste" }), /name=Meine%20Liste&input=text&text=$/);
  });
});
