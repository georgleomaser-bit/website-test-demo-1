// Tests für integrations.js – Kalender-Abos (ICS: Zeitzonen, Ganztag, Serien, Ausnahmen, Faltung, Escapes, Abbruch),
// IMAP-Mails und Kalender-Links in connect.refresh, Webhook-Eingang und -Ausgang, Deep-Links, Adressen, CSV-Export/-Import
process.env.TZ = "Europe/Berlin";
import { test, describe, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";

const I = await import("../js/integrations.js");
const C = await import("../js/connect.js");
const store = await import("../js/store.js");

const MIN = 60000;
const H = 60 * MIN;
const DAY = 24 * H;
const RANGE = { from: Date.parse("2026-10-01T00:00:00+02:00"), to: Date.parse("2026-12-01T00:00:00+01:00") };
const ics = (...events) => ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Test//DE", "X-WR-CALNAME:Firma", ...events.flat(), "END:VCALENDAR"].join("\r\n");
const ev = (...lines) => ["BEGIN:VEVENT", ...lines, "END:VEVENT"];
const parse = (text, o = {}) => I.parseICS(text, { ...RANGE, account: "acc", ...o });
const loc = (ms) => {
  const d = new Date(ms);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
};

// ---------- ICS ----------
describe("parseICS: Zeiten und Zonen", () => {
  test("UTC, TZID (IANA), floating = Gerätezeit, Form wie connect-Events", () => {
    const list = parse(
      ics(
        ev("UID:u1", "DTSTART:20261006T070000Z", "DTEND:20261006T080000Z", "SUMMARY:Jour fixe"),
        ev("UID:u2", "DTSTART;TZID=America/New_York:20261006T090000", "DTEND;TZID=America/New_York:20261006T093000", "SUMMARY:Call New York"),
        ev("UID:u3", "DTSTART:20261007T090000", "DURATION:PT45M", "SUMMARY:Floating"),
      ),
    );
    assert.equal(list.length, 3);
    const [a, b, c] = list;
    assert.deepEqual(Object.keys(a).sort(), ["account", "allDay", "calendar", "cancelled", "date", "end", "id", "join", "location", "notes", "provider", "start", "time", "title", "web"].sort());
    assert.equal(a.id, `i:acc:u1:${Date.parse("2026-10-06T07:00:00Z")}`);
    assert.equal(a.provider, "ics");
    assert.equal(a.account, "acc");
    assert.equal(a.calendar, "Firma"); // aus X-WR-CALNAME
    assert.equal(a.time, "09:00");
    assert.equal(a.date, "2026-10-06");
    assert.equal(a.end - a.start, H);
    assert.equal(b.title, "Call New York");
    assert.equal(b.start, Date.parse("2026-10-06T13:00:00Z")); // 9:00 EDT = 15:00 Berlin
    assert.equal(b.time, "15:00");
    assert.equal(b.end - b.start, 30 * MIN);
    assert.equal(c.time, "09:00");
    assert.equal(c.start, new Date(2026, 9, 7, 9, 0).getTime());
    assert.equal(c.end - c.start, 45 * MIN);
  });

  test("Windows-Zonennamen, Outlook-Anzeigenamen, Mozilla-Pfade, VTIMEZONE-Versatz, unbekannt → Gerätezeit", () => {
    assert.equal(I.resolveTz("W. Europe Standard Time"), "Europe/Berlin");
    assert.equal(I.resolveTz("Pacific Standard Time"), "America/Los_Angeles");
    assert.equal(I.resolveTz("(UTC+01:00) Amsterdam, Berlin, Bern, Rom, Stockholm, Wien"), "Europe/Berlin");
    assert.equal(I.resolveTz("Mitteleuropäische Zeit"), "Europe/Berlin");
    assert.equal(I.resolveTz("/mozilla.org/20050126_1/Europe/Berlin"), "Europe/Berlin");
    assert.equal(I.resolveTz("Europe/Vienna"), "Europe/Vienna");
    assert.equal(I.resolveTz("UTC"), "UTC");
    assert.deepEqual(I.resolveTz("GMT+0530 Irgendwo"), { fixed: 330 });
    assert.equal(I.resolveTz("Firmenzone", new Map([["Firmenzone", { std: 60, dst: 120 }]])), "Europe/Berlin");
    assert.equal(I.resolveTz("Quatsch-Zone"), null);
    const list = parse(
      ics(
        ["BEGIN:VTIMEZONE", "TZID:Firmenzone", "BEGIN:STANDARD", "DTSTART:19701025T030000", "TZOFFSETFROM:+0200", "TZOFFSETTO:+0100", "END:STANDARD", "BEGIN:DAYLIGHT", "DTSTART:19700329T020000", "TZOFFSETFROM:+0100", "TZOFFSETTO:+0200", "END:DAYLIGHT", "END:VTIMEZONE"],
        ev("UID:w1", 'DTSTART;TZID="W. Europe Standard Time":20261008T100000', 'DTEND;TZID="W. Europe Standard Time":20261008T110000', "SUMMARY:Outlook"),
        ev("UID:w2", "DTSTART;TZID=Firmenzone:20261009T100000", "DTEND;TZID=Firmenzone:20261009T103000", "SUMMARY:Eigene Zone"),
        ev("UID:w3", "DTSTART;TZID=Quatsch-Zone:20261009T120000", "SUMMARY:Unbekannt"),
      ),
    );
    assert.deepEqual(list.map((e) => [e.title, loc(e.start)]), [["Outlook", "2026-10-08 10:00"], ["Eigene Zone", "2026-10-09 10:00"], ["Unbekannt", "2026-10-09 12:00"]]);
    assert.equal(list[2].end - list[2].start, 30 * MIN); // ohne Ende: 30 Minuten
  });

  test("ganztägig: ein Tag, mehrtägig, ohne DTEND, mit DURATION; Bereich schneidet mehrtägige Termine an", () => {
    const list = parse(
      ics(
        ev("UID:a1", "DTSTART;VALUE=DATE:20261006", "DTEND;VALUE=DATE:20261007", "SUMMARY:Geburtstag"),
        ev("UID:a2", "DTSTART;VALUE=DATE:20261014", "DTEND;VALUE=DATE:20261017", "SUMMARY:Messe"),
        ev("UID:a3", "DTSTART;VALUE=DATE:20261020", "SUMMARY:Ohne Ende"),
        ev("UID:a4", "DTSTART:20261021", "DURATION:P2D", "SUMMARY:Zwei Tage"),
        ev("UID:a5", "DTSTART;VALUE=DATE:20260928", "DTEND;VALUE=DATE:20261003", "SUMMARY:Urlaub über den Rand"),
        ev("UID:a6", "DTSTART;VALUE=DATE:20260901", "DTEND;VALUE=DATE:20260902", "SUMMARY:Vorbei"),
      ),
    );
    const by = Object.fromEntries(list.map((e) => [e.title, e]));
    assert.ok(!by.Vorbei);
    assert.equal(by.Geburtstag.allDay, true);
    assert.equal(by.Geburtstag.time, null);
    assert.equal(by.Geburtstag.date, "2026-10-06");
    assert.equal(by.Geburtstag.start, new Date(2026, 9, 6).getTime());
    assert.equal(by.Geburtstag.end, new Date(2026, 9, 7).getTime());
    assert.equal(by.Messe.end, new Date(2026, 9, 17).getTime());
    assert.equal(by["Ohne Ende"].end - by["Ohne Ende"].start, DAY);
    assert.equal(by["Zwei Tage"].allDay, true);
    assert.equal(by["Zwei Tage"].end, new Date(2026, 9, 23).getTime());
    assert.equal(by["Urlaub über den Rand"].date, "2026-09-28");
    // Termine an einem Tag (connect.eventsOn) zählen den Urlaub am 1.10. mit
    assert.ok(C.eventsOn("2026-10-01", list).some((e) => e.title === "Urlaub über den Rand"));
  });
});

describe("parseICS: Text, Faltung, Links, Abbruch", () => {
  test("Zeilen-Entfaltung, Escapes, Parameter in Anführungszeichen, VALARM stört nicht", () => {
    const text = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "BEGIN:VEVENT",
      "UID:f1",
      "DTSTART:20261012T080000Z",
      "DTEND:20261012T090000Z",
      "SUMMARY:Baubesprechung mit sehr langem Titel\\, der über mehrere Zeil",
      " en gefaltet wurde",
      'ATTENDEE;CN="Müller: Hans";ROLE=REQ-PARTICIPANT:mailto:hans@firma.de',
      "LOCATION:Nordstraße 12\\, 70191 Stuttgart",
      "DESCRIPTION:Agenda:\\n1. Rohbau\\n2. Fenster\\; Türen\\nBackslash: \\\\ Ende",
      "BEGIN:VALARM",
      "ACTION:DISPLAY",
      "DESCRIPTION:Erinnerung",
      "TRIGGER:-PT15M",
      "END:VALARM",
      "END:VEVENT",
      "END:VCALENDAR",
    ].join("\n"); // auch nur LF
    const [e] = parse(text);
    assert.equal(e.title, "Baubesprechung mit sehr langem Titel, der über mehrere Zeilen gefaltet wurde");
    assert.equal(e.location, "Nordstraße 12, 70191 Stuttgart");
    assert.equal(e.notes, "Agenda:\n1. Rohbau\n2. Fenster; Türen\nBackslash: \\ Ende");
    assert.equal(e.calendar, "Kalender");
    assert.equal(I.unescapeText("a\\,b\\;c\\nd\\\\e\\Nf"), "a,b;c\nd\\e\nf");
    assert.deepEqual(I.parseLine('ATTENDEE;CN="A: B";X=1:mailto:a@b.de'), { name: "ATTENDEE", params: { CN: "A: B", X: "1" }, value: "mailto:a@b.de" });
  });

  test("Beitreten-Link (Teams, Zoom, Meet) und Web-Link; gefährliche Links fallen weg", () => {
    const list = parse(
      ics(
        ev("UID:j1", "DTSTART:20261012T080000Z", "SUMMARY:Teams", "DESCRIPTION:Besprechung beitreten: https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=x\\nMehr Infos"),
        ev("UID:j2", "DTSTART:20261012T100000Z", "SUMMARY:Zoom", "LOCATION:https://us02web.zoom.us/j/81234567890?pwd=abc"),
        ev("UID:j3", "DTSTART:20261012T120000Z", "SUMMARY:Exchange", "X-MICROSOFT-SKYPETEAMSMEETINGURL:https://teams.microsoft.com/l/meetup-join/xyz", "URL:https://outlook.office365.com/owa/?itemid=1"),
        ev("UID:j4", "DTSTART:20261012T140000Z", "SUMMARY:Böse", "URL:javascript:alert(1)", "LOCATION:javascript:alert(2)"),
      ),
    );
    const by = Object.fromEntries(list.map((e) => [e.title, e]));
    assert.match(by.Teams.join, /^https:\/\/teams\.microsoft\.com\/l\/meetup-join\//);
    assert.equal(by.Zoom.join, "https://us02web.zoom.us/j/81234567890?pwd=abc");
    assert.equal(by.Exchange.join, "https://teams.microsoft.com/l/meetup-join/xyz");
    assert.equal(by.Exchange.web, "https://outlook.office365.com/owa/?itemid=1");
    assert.equal(by["Böse"].join, null);
    assert.equal(by["Böse"].web, "");
  });

  test("abgesagt: STATUS:CANCELLED und „Abgesagt:“-Titel", () => {
    const list = parse(ics(ev("UID:c1", "DTSTART:20261012T080000Z", "SUMMARY:Messe", "STATUS:CANCELLED"), ev("UID:c2", "DTSTART:20261012T090000Z", "SUMMARY:Abgesagt: Jour fixe"), ev("UID:c3", "DTSTART:20261012T100000Z", "SUMMARY:Bleibt", "STATUS:CONFIRMED")));
    assert.deepEqual(list.map((e) => [e.title, e.cancelled]), [["Messe", true], ["Abgesagt: Jour fixe", true], ["Bleibt", false]]);
  });

  test("Abbruch: abgeschnittene Datei, Müll, kein Kalender, fehlende Pflichtfelder", () => {
    const cut = ["BEGIN:VCALENDAR", ...ev("UID:ok", "DTSTART:20261012T080000Z", "SUMMARY:Vollständig"), "BEGIN:VEVENT", "UID:halb", "DTSTART:20261013T080000Z", "SUMMARY:Abgeschnit"].join("\r\n");
    assert.deepEqual(parse(cut).map((e) => e.title), ["Vollständig"]);
    assert.deepEqual(parse("<html><body>Login</body></html>"), []);
    assert.deepEqual(parse(""), []);
    assert.deepEqual(parse(null), []);
    assert.deepEqual(parse(ics(ev("UID:x", "SUMMARY:Ohne Start"), ev("UID:y", "DTSTART:2026-10-12", "SUMMARY:Kaputtes Datum"), ev("UID:z", "DTSTART:20261399T080000Z"))), []);
    assert.deepEqual(I.icsInfo(cut), { ok: true, name: "", count: 1 });
    assert.equal(I.icsInfo("Hallo").ok, false);
    // ohne Titel und ohne UID
    const [n] = parse(ics(ev("DTSTART:20261012T080000Z")));
    assert.equal(n.title, "(Ohne Titel)");
    assert.match(n.id, /^i:acc:x/);
  });
});

describe("parseICS: Serien", () => {
  const titles = (list, t) => list.filter((e) => e.title === t).map((e) => loc(e.start));

  test("WEEKLY mit BYDAY und COUNT; Wanduhrzeit bleibt über die Zeitumstellung (25.10.)", () => {
    const list = parse(
      ics(
        ev("UID:r1", "DTSTART;TZID=Europe/Berlin:20261012T090000", "DTEND;TZID=Europe/Berlin:20261012T093000", "RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=6", "SUMMARY:Team"),
        ev("UID:r2", "DTSTART:20261019T070000Z", "RRULE:FREQ=WEEKLY;COUNT=3", "SUMMARY:UTC-Serie"),
      ),
    );
    assert.deepEqual(titles(list, "Team"), ["2026-10-12 09:00", "2026-10-14 09:00", "2026-10-19 09:00", "2026-10-21 09:00", "2026-10-26 09:00", "2026-10-28 09:00"]);
    assert.ok(list.filter((e) => e.title === "Team").every((e) => e.end - e.start === 30 * MIN));
    // UTC-Serie bleibt in UTC: nach der Umstellung eine Stunde früher in Berlin
    assert.deepEqual(titles(list, "UTC-Serie"), ["2026-10-19 09:00", "2026-10-26 08:00", "2026-11-02 08:00"]);
    // ids eindeutig je Termin
    assert.equal(new Set(list.map((e) => e.id)).size, list.length);
  });

  test("DAILY mit INTERVAL und UNTIL; alte Serie (Start 2015) wird vorgespult", () => {
    const list = parse(
      ics(
        ev("UID:d1", "DTSTART;TZID=Europe/Berlin:20261001T070000", "RRULE:FREQ=DAILY;INTERVAL=2;UNTIL=20261009T050000Z", "SUMMARY:Alle 2 Tage"),
        ev("UID:d2", "DTSTART;TZID=Europe/Berlin:20150105T080000", "DTEND;TZID=Europe/Berlin:20150105T081500", "RRULE:FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR", "SUMMARY:Werktags"),
      ),
    );
    assert.deepEqual(titles(list, "Alle 2 Tage"), ["2026-10-01 07:00", "2026-10-03 07:00", "2026-10-05 07:00", "2026-10-07 07:00", "2026-10-09 07:00"]);
    const w = list.filter((e) => e.title === "Werktags");
    assert.equal(w[0].date, "2026-10-01");
    assert.equal(w.length, 43); // Werktage 1.10.–30.11.2026
    assert.ok(w.every((e) => ![0, 6].includes(new Date(e.start).getDay()) && e.time === "08:00"));
  });

  test("MONTHLY: 1MO, -1FR, BYMONTHDAY=31 (Monate ohne 31. fallen aus), BYSETPOS (letzter Werktag)", () => {
    const list = I.parseICS(
      ics(
        ev("UID:m1", "DTSTART;TZID=Europe/Berlin:20260105T100000", "RRULE:FREQ=MONTHLY;BYDAY=1MO", "SUMMARY:Erster Montag"),
        ev("UID:m2", "DTSTART;TZID=Europe/Berlin:20260130T150000", "RRULE:FREQ=MONTHLY;BYDAY=-1FR", "SUMMARY:Letzter Freitag"),
        ev("UID:m3", "DTSTART;VALUE=DATE:20260131", "RRULE:FREQ=MONTHLY;BYMONTHDAY=31", "SUMMARY:Am 31."),
        ev("UID:m4", "DTSTART;TZID=Europe/Berlin:20260130T120000", "RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", "SUMMARY:Monatsabschluss"),
        ev("UID:m5", "DTSTART;TZID=Europe/Berlin:20260115T080000", "RRULE:FREQ=MONTHLY;INTERVAL=3", "SUMMARY:Quartal"),
      ),
      { from: Date.parse("2026-09-01T00:00:00+02:00"), to: Date.parse("2027-01-01T00:00:00+01:00"), account: "acc" },
    );
    const t = (x) => list.filter((e) => e.title === x).map((e) => e.date);
    assert.deepEqual(t("Erster Montag"), ["2026-09-07", "2026-10-05", "2026-11-02", "2026-12-07"]);
    assert.deepEqual(t("Letzter Freitag"), ["2026-09-25", "2026-10-30", "2026-11-27", "2026-12-25"]);
    assert.deepEqual(t("Am 31."), ["2026-10-31", "2026-12-31"]);
    assert.deepEqual(t("Monatsabschluss"), ["2026-09-30", "2026-10-30", "2026-11-30", "2026-12-31"]);
    assert.deepEqual(t("Quartal"), ["2026-10-15"]);
  });

  test("YEARLY: Geburtstag (ganztägig) und letzter Sonntag im Oktober", () => {
    const list = I.parseICS(
      ics(
        ev("UID:y1", "DTSTART;VALUE=DATE:19650312", "RRULE:FREQ=YEARLY", "SUMMARY:Geburtstag Mama"),
        ev("UID:y2", "DTSTART;TZID=Europe/Berlin:20201025T030000", "RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU", "SUMMARY:Zeitumstellung"),
      ),
      { from: Date.parse("2026-01-01T00:00:00+01:00"), to: Date.parse("2028-01-01T00:00:00+01:00"), account: "acc" },
    );
    assert.deepEqual(list.filter((e) => e.title === "Geburtstag Mama").map((e) => [e.date, e.allDay]), [["2026-03-12", true], ["2027-03-12", true]]);
    assert.deepEqual(list.filter((e) => e.title === "Zeitumstellung").map((e) => e.date), ["2026-10-25", "2027-10-31"]);
  });

  test("EXDATE (mit TZID, mehrere Werte, ganztägig) und RDATE", () => {
    const list = parse(
      ics(
        ev("UID:e1", "DTSTART;TZID=Europe/Berlin:20261005T090000", "RRULE:FREQ=WEEKLY;COUNT=4", "EXDATE;TZID=Europe/Berlin:20261012T090000,20261026T090000", "RDATE;TZID=Europe/Berlin:20261030T140000", "SUMMARY:Montagsrunde"),
        ev("UID:e2", "DTSTART;VALUE=DATE:20261005", "RRULE:FREQ=DAILY;COUNT=5", "EXDATE;VALUE=DATE:20261007", "EXDATE;VALUE=DATE:20261008", "SUMMARY:Urlaub"),
      ),
    );
    assert.deepEqual(titles(list, "Montagsrunde"), ["2026-10-05 09:00", "2026-10-19 09:00", "2026-10-30 14:00"]);
    assert.deepEqual(list.filter((e) => e.title === "Urlaub").map((e) => e.date), ["2026-10-05", "2026-10-06", "2026-10-09"]);
  });

  test("RECURRENCE-ID: verschobener Termin mit neuem Titel, abgesagter Einzeltermin", () => {
    const list = parse(
      ics(
        ev("UID:s1", "DTSTART;TZID=Europe/Berlin:20261006T100000", "DTEND;TZID=Europe/Berlin:20261006T110000", "RRULE:FREQ=WEEKLY;COUNT=4", "SUMMARY:Jour fixe"),
        ev("UID:s1", "RECURRENCE-ID;TZID=Europe/Berlin:20261013T100000", "DTSTART;TZID=Europe/Berlin:20261014T150000", "DTEND;TZID=Europe/Berlin:20261014T160000", "SUMMARY:Jour fixe (verschoben)"),
        ev("UID:s1", "RECURRENCE-ID:20261020T080000Z", "DTSTART:20261020T080000Z", "STATUS:CANCELLED", "SUMMARY:Jour fixe"),
      ),
    );
    const s = list.filter((e) => e.id.includes(":s1:"));
    assert.deepEqual(s.map((e) => [loc(e.start), e.title, e.cancelled]), [
      ["2026-10-06 10:00", "Jour fixe", false],
      ["2026-10-14 15:00", "Jour fixe (verschoben)", false],
      ["2026-10-20 10:00", "Jour fixe", true],
      ["2026-10-27 10:00", "Jour fixe", false],
    ]);
  });

  test("RRULE-Regeln und Dauer einzeln", () => {
    assert.deepEqual(I.parseRRule("FREQ=MONTHLY;BYDAY=1MO,-1FR;INTERVAL=2").byday, [{ n: 1, wd: 1 }, { n: -1, wd: 5 }]);
    assert.equal(I.parseRRule("FREQ=HOURLY"), null);
    assert.equal(I.parseRRule("FREQ=WEEKLY;INTERVAL=0").interval, 1);
    assert.deepEqual(I.parseDuration("PT1H30M"), { days: 0, ms: 90 * MIN, total: 90 * MIN });
    assert.deepEqual(I.parseDuration("P1W"), { days: 7, ms: 0, total: 7 * DAY });
    assert.equal(I.parseDuration("P"), null);
    assert.equal(I.parseDuration("quatsch"), null);
  });
});

// ---------- Deep-Links & Adressen ----------
describe("Nachrichten & Anrufe", () => {
  test("WhatsApp, SMS, FaceTime, Teams, Karten", () => {
    assert.equal(I.whatsappLink("0171 123 45 67", "Hallo Klaus, kurze Frage"), "https://wa.me/491711234567?text=Hallo%20Klaus%2C%20kurze%20Frage");
    assert.equal(I.whatsappLink("+43 664 1234567"), "https://wa.me/436641234567");
    assert.equal(I.whatsappLink("0049 (0)171-1234567"), "https://wa.me/491711234567");
    assert.equal(I.whatsappLink("", "Nur Text"), "https://wa.me/?text=Nur%20Text");
    assert.equal(I.smsLink("0171/1234567", "Bin gleich da"), "sms:+491711234567&body=Bin%20gleich%20da");
    assert.equal(I.smsLink("+41 79 123 45 67"), "sms:+41791234567");
    assert.equal(I.facetimeLink("0171 1234567"), "facetime:+491711234567");
    assert.equal(I.facetimeLink("0171 1234567", true), "facetime-audio:+491711234567");
    assert.equal(I.facetimeLink("Klaus@Firma.de"), "facetime:klaus@firma.de");
    assert.equal(I.facetimeLink("kein Ziel"), "");
    assert.equal(I.teamsCallLink("t.mueller@mueller-bau.de"), "https://teams.microsoft.com/l/call/0/0?users=t.mueller@mueller-bau.de");
    assert.equal(I.teamsChatLink("t.mueller@mueller-bau.de", "Hallo & tschüss"), "https://teams.microsoft.com/l/chat/0/0?users=t.mueller@mueller-bau.de&message=Hallo%20%26%20tsch%C3%BCss");
    assert.equal(I.teamsCallLink("keine-mail"), "");
    assert.deepEqual(I.mapsLinks("Königstraße 12, 70173 Stuttgart"), {
      apple: "https://maps.apple.com/?q=K%C3%B6nigstra%C3%9Fe%2012%2C%2070173%20Stuttgart",
      google: "https://www.google.com/maps/search/?api=1&query=K%C3%B6nigstra%C3%9Fe%2012%2C%2070173%20Stuttgart",
    });
    assert.equal(I.phoneKind("0171 1234567"), "mobil");
    assert.equal(I.phoneKind("0711 987654"), "festnetz");
    assert.equal(I.phoneKind("+44 20 7946 0958"), "");
  });

  test("safeLink lässt nur tel/sms/facetime zusätzlich zu", () => {
    assert.equal(I.safeLink("sms:+491711234567&body=Hi"), "sms:+491711234567&body=Hi");
    assert.equal(I.safeLink("facetime-audio:+491711234567"), "facetime-audio:+491711234567");
    assert.equal(I.safeLink("tel:+49711"), "tel:+49711");
    assert.equal(I.safeLink("javascript:alert(1)"), "");
    assert.equal(I.safeLink("data:text/html,x"), "");
    assert.equal(I.safeLink("https://wa.me/49171"), "https://wa.me/49171");
  });

  test("Adressen erkennen (deutsch)", () => {
    const a = (t) => I.addresses(t).map((x) => x.label);
    assert.deepEqual(a("Treffen Königstraße 12, 70173 Stuttgart um 9"), ["Königstraße 12, 70173 Stuttgart"]);
    assert.deepEqual(a("Baustelle: Berliner Str. 5a, 10115 Berlin\nDanach Am Markt 3, 01067 Dresden"), ["Berliner Str. 5a, 10115 Berlin", "Am Markt 3, 01067 Dresden"]);
    assert.deepEqual(a("Kunde in der Konrad-Adenauer-Straße 7"), ["Konrad-Adenauer-Straße 7"]);
    assert.deepEqual(a("Lieferung an Mühlweg 4-6, Esslingen."), ["Mühlweg 4-6, Esslingen"]);
    assert.deepEqual(a("Termin in 60311 Frankfurt am Main"), ["60311 Frankfurt am Main"]);
    assert.deepEqual(a("Hauptstraße 5, Bitte klingeln"), ["Hauptstraße 5"]);
    assert.deepEqual(a("Rechnung über 12500 Euro bis 15.10."), []);
    assert.deepEqual(a("auf dem Weg 2 Mal anrufen, Tel. 0711 123456"), []);
    assert.deepEqual(a("Kosten 1.234,50 EUR, 3 Stück"), []);
    assert.deepEqual(a(""), []);
  });

  test("Teilen-Text", () => {
    const t = { title: "Angebot prüfen", due: "2026-10-07", time: "09:30", notes: "Fenster Nord", subtasks: [{ title: "Preise", done: true }, { title: "Termine", done: false }] };
    assert.equal(I.taskShareText(t, { bag: { name: "Baustelle Nord", emoji: "🏗️" } }), "Angebot prüfen\n📅 Mi., 7. Oktober, 9:30 Uhr\n🏗️ Baustelle Nord\n\nFenster Nord\n\n✓ Preise\n○ Termine");
  });
});

// ---------- CSV ----------
describe("CSV / Excel", () => {
  const bagsById = { b1: { id: "b1", name: "Baustelle Nord" }, b2: { id: "b2", name: "Büro" } };
  const tasks = [
    { id: "t1", title: 'Angebot "Fenster" prüfen', bag: "b1", section: "Planung", due: "2026-10-07", time: "09:30", prio: 3, done: null, notes: "Zeile 1\nZeile 2; mit Semikolon", tags: ["kunde", "fenster"], created: new Date(2026, 9, 1, 8, 5).getTime() },
    { id: "t2", title: "=HYPERLINK(\"http://böse\")", bag: null, due: null, prio: 0, done: new Date(2026, 9, 5, 17, 0).getTime(), notes: "-Minus vorn", tags: [], created: new Date(2026, 9, 2, 9, 0).getTime() },
    { id: "t3", title: "Rückruf Steuerberater", bag: "b2", due: "2026-10-09", prio: 1, notes: "- Liste", tags: [], created: 0 },
  ];

  test("Export: BOM, Semikolon, Anführungszeichen, CRLF, Formel-Schutz, deutsche Datumsangaben", () => {
    const csv = I.exportCSV(tasks, { bagsById });
    assert.ok(csv.startsWith("﻿"));
    const lines = csv.slice(1).split("\r\n");
    assert.equal(lines[0], '"Titel";"Tasche";"Abschnitt";"Fällig";"Uhrzeit";"Priorität";"Status";"Notizen";"Tags";"Erstellt";"Erledigt"');
    assert.equal(lines[1], '"Angebot ""Fenster"" prüfen";"Baustelle Nord";"Planung";"07.10.2026";"09:30";"Hoch";"Offen";"Zeile 1\nZeile 2; mit Semikolon";"kunde, fenster";"01.10.2026 08:05";""');
    assert.match(csv, /"'=HYPERLINK\(""http:\/\/böse""\)";"";"";"";"";"";"Erledigt";"'-Minus vorn";"";"02\.10\.2026 09:00";"05\.10\.2026 17:00"/);
    assert.match(csv, /"- Liste"/); // Aufzählung bleibt
    assert.ok(csv.endsWith("\r\n"));
  });

  test("Rundreise: Export → parseCSV → mapColumns → csvTasks (Tasche aus Spalte)", () => {
    const parsed = I.parseCSV(I.exportCSV(tasks, { bagsById }));
    assert.equal(parsed.sep, ";");
    assert.equal(parsed.rows.length, 3);
    const map = I.mapColumns(parsed.headers);
    assert.equal(map.format, "arbeitstaschen");
    assert.deepEqual([map.title, map.bag, map.section, map.due, map.time, map.prio, map.done, map.notes, map.tags], [0, 1, 2, 3, 4, 5, 6, 7, 8]);
    const bags = [{ id: "b2", name: "Büro" }];
    const r = I.csvTasks(parsed, map, { bagMode: "column", bags, skipDone: true });
    assert.deepEqual(r.newBags, ["Baustelle Nord"]);
    assert.equal(r.tasks.length, 2); // erledigte übersprungen
    const [a, b] = r.tasks;
    assert.deepEqual([a.title, a.bag, a.bagName, a.section, a.due, a.time, a.prio, a.notes, a.tags], ['Angebot "Fenster" prüfen', null, "Baustelle Nord", "Planung", "2026-10-07", "09:30", 3, "Zeile 1\nZeile 2; mit Semikolon", ["kunde", "fenster"]]);
    assert.deepEqual([b.title, b.bag, b.prio, b.notes], ["Rückruf Steuerberater", "b2", 1, "- Liste"]);
    const all = I.csvTasks(parsed, map, { bagMode: "fixed", bagId: "b9", skipDone: false });
    assert.equal(all.tasks.length, 3);
    assert.equal(all.tasks[1].title, '=HYPERLINK("http://böse")'); // Apostroph wieder weg
    assert.equal(all.tasks[1].done, true);
    assert.ok(all.tasks.every((t) => t.bag === "b9"));
  });

  test("parseCSV: Komma, Tab, sep=-Zeile, Zeilenumbrüche in Feldern, leere Zeilen, BOM", () => {
    const p1 = I.parseCSV('﻿Title,Notes,Due\r\n"Hallo, Welt","Zeile 1\r\nZeile 2",2026-10-07\r\n\r\nZweite,,\n');
    assert.equal(p1.sep, ",");
    assert.deepEqual(p1.headers, ["Title", "Notes", "Due"]);
    assert.deepEqual(p1.rows, [["Hallo, Welt", "Zeile 1\r\nZeile 2", "2026-10-07"], ["Zweite", "", ""]]);
    const p2 = I.parseCSV("Aufgabe\tFällig\nRechnung\t15.10.2026");
    assert.equal(p2.sep, "\t");
    assert.deepEqual(p2.rows, [["Rechnung", "15.10.2026"]]);
    const p3 = I.parseCSV("sep=;\nTitel;Notiz\nA;B, C");
    assert.equal(p3.sep, ";");
    assert.deepEqual(p3.rows, [["A", "B, C"]]);
    assert.deepEqual(I.parseCSV("").headers, []);
  });

  test("Excel (deutsch, Windows-1252), Datumsformate", () => {
    const bytes = Uint8Array.from([0x54, 0x69, 0x74, 0x65, 0x6c, 0x3b, 0x46, 0xe4, 0x6c, 0x6c, 0x69, 0x67, 0x0d, 0x0a, 0x42, 0xfc, 0x72, 0x6f, 0x3b, 0x30, 0x37, 0x2e, 0x31, 0x30, 0x2e, 0x32, 0x36]); // „Titel;Fällig\r\nBüro;07.10.26“ in Windows-1252
    const text = I.decodeText(bytes);
    assert.equal(text, "Titel;Fällig\r\nBüro;07.10.26");
    const parsed = I.parseCSV(text);
    const r = I.csvTasks(parsed, I.mapColumns(parsed.headers));
    assert.deepEqual(r.tasks.map((t) => [t.title, t.due]), [["Büro", "2026-10-07"]]);
    assert.equal(I.decodeText(new TextEncoder().encode("Grüße")), "Grüße");
    const now = new Date(2026, 9, 6, 10, 0);
    assert.deepEqual(I.parseDateText("2026-10-07T10:00:00.000Z", { now }), { due: "2026-10-07", time: "12:00" });
    assert.deepEqual(I.parseDateText("07.10.2026 14:30", { now }), { due: "2026-10-07", time: "14:30" });
    assert.deepEqual(I.parseDateText("10/07/2026", { now }), { due: "2026-10-07", time: null });
    assert.deepEqual(I.parseDateText("46301", { now }), { due: "2026-10-06", time: null }); // Excel-Seriennummer
    assert.deepEqual(I.parseDateText("morgen", { now }), { due: "2026-10-07", time: null });
    assert.deepEqual(I.parseDateText("every day", { now }), { due: null, time: null });
    assert.deepEqual(I.parseDateText("3.1.", { now }), { due: "2027-01-03", time: null });
  });

  test("Todoist-Export (TYPE/CONTENT/PRIORITY/DATE, Abschnitte, Notizen)", () => {
    const csv = [
      "TYPE,CONTENT,DESCRIPTION,PRIORITY,INDENT,AUTHOR,RESPONSIBLE,DATE,DATE_LANG,TIMEZONE",
      "section,Vorbereitung,,,,,,,,",
      "task,Gerüst bestellen @bau,Bei Firma Maier,1,1,Thomas (1),,tomorrow,en,Europe/Berlin",
      "note,Angebot liegt vor,,,,,,,,",
      "task,Website-Idee,,4,1,Thomas (1),,every day,en,Europe/Berlin",
      ",,,,,,,,,",
    ].join("\n");
    const parsed = I.parseCSV(csv);
    const map = I.mapColumns(parsed.headers);
    assert.equal(map.format, "todoist");
    const r = I.csvTasks(parsed, map, { now: new Date(2026, 9, 6, 10) });
    assert.deepEqual(r.tasks.map((t) => [t.title, t.section, t.prio]), [["Gerüst bestellen", "Vorbereitung", 3], ["Website-Idee", "Vorbereitung", 0]]);
    assert.equal(r.tasks[0].notes, "Bei Firma Maier\n\nFällig (Import): tomorrow\n\nAngebot liegt vor");
    assert.equal(r.tasks[1].due, null);
  });

  test("Trello- und Asana-Export", () => {
    const trello = I.parseCSV(
      ["Card ID,Card Name,Card URL,Card Description,Labels,Members,Due Date,List ID,List Name,Board Name,Archived", 'c1,Fliesen bestellen,https://trello.com/c/1,"Bad oben, 20 m²","Einkauf (green), Dringend (red)",,2026-10-09T08:00:00.000Z,l1,Baustelle Nord,Bau,false', "c2,Alt,https://trello.com/c/2,,,,,l2,Erledigt,Bau,true"].join("\n"),
    );
    const tm = I.mapColumns(trello.headers);
    assert.equal(tm.format, "trello");
    assert.equal(trello.headers[tm.bag], "List Name");
    const t = I.csvTasks(trello, tm, { bagMode: "column", bags: [] });
    assert.deepEqual(t.tasks.map((x) => [x.title, x.due, x.time, x.bagName, x.tags, x.notes]), [["Fliesen bestellen", "2026-10-09", "10:00", "Baustelle Nord", ["Einkauf", "Dringend"], "Bad oben, 20 m²"]]);
    const asana = I.parseCSV(
      ["Task ID,Created At,Completed At,Last Modified,Name,Section/Column,Assignee,Assignee Email,Start Date,Due Date,Tags,Notes,Projects,Parent task", "1,2026-10-01,,2026-10-02,Statik prüfen,In Arbeit,Thomas,t@x.de,,2026-10-12,,Mit Ingenieur abstimmen,Halle 3,", "2,2026-10-01,2026-10-03,2026-10-03,Fertig,Erledigt,,,,2026-10-02,,,Halle 3,"].join("\n"),
    );
    const am = I.mapColumns(asana.headers);
    assert.equal(am.format, "asana");
    const a = I.csvTasks(asana, am, { bagMode: "column", bags: [{ id: "h3", name: "Halle 3" }] });
    assert.deepEqual(a.tasks.map((x) => [x.title, x.due, x.section, x.bag, x.notes]), [["Statik prüfen", "2026-10-12", "In Arbeit", "h3", "Mit Ingenieur abstimmen"]]);
    assert.deepEqual(a.newBags, []);
  });

  test("Priorität und Status aus Text", () => {
    assert.deepEqual(["hoch", "High", "!!!", "p1", "mittel", "!!", "niedrig", "low", "", "3", "7"].map((x) => I.parsePrio(x)), [3, 3, 3, 3, 2, 2, 1, 1, 0, 3, 3]);
    assert.deepEqual([1, 2, 3, 4].map((x) => I.parsePrio(String(x), { todoist: true })), [3, 2, 1, 0]);
    assert.deepEqual(["x", "Erledigt", "TRUE", "offen", "false", "", "2026-10-03"].map(I.parseDone), [true, true, true, false, false, false, true]);
  });
});

// ---------- Webhooks ----------
describe("Webhook-Eingang", () => {
  const bags = [{ id: "b1", name: "Kunden", status: "aktiv" }, { id: "b2", name: "Baustelle Nord", status: "aktiv" }];
  const now = new Date(2026, 9, 6, 10, 0);

  test("itemToTask: Titel wie Schnellerfassung, Fälligkeit, Tasche per Name, Notiz + Link, Herkunft", () => {
    const a = I.itemToTask({ id: "i1", title: "Angebot schicken morgen 9 Uhr #Kunden !!!", source: "Kurzbefehle/1.0 CFNetwork/1568 Darwin/24.0.0" }, { bags, now });
    assert.deepEqual([a.title, a.due, a.time, a.bag, a.prio], ["Angebot schicken", "2026-10-07", "09:00", "b1", 3]);
    assert.deepEqual(a.src, { kind: "hook", id: "h:i1", via: "Siri", at: a.src.at });
    const b = I.itemToTask({ id: "i2", title: "Fliesen nachbestellen", notes: "Bad oben\nweiß", due: "2026-10-09", time: "14.30", bag: "baustelle nord", prio: "hoch", url: "https://shop.example.de/fliese", source: "Zapier" }, { bags, now });
    assert.deepEqual([b.title, b.due, b.time, b.bag, b.prio], ["Fliesen nachbestellen", "2026-10-09", "14:30", "b2", 3]);
    assert.equal(b.notes, "Bad oben\nweiß\n\nhttps://shop.example.de/fliese");
    assert.equal(b.src.via, "Zapier");
    const c = I.itemToTask({ id: "i3", title: "Steuerberater anrufen", due: "Freitag", url: "javascript:alert(1)" }, { bags, now });
    assert.equal(c.due, "2026-10-09");
    assert.ok(c.tags.includes("anruf"));
    assert.equal(c.notes, "");
    assert.equal(c.src.via, "Webhook");
    assert.equal(I.itemToTask({ id: "i4", title: "   " }, { bags, now }), null);
    assert.equal(I.itemToTask(null), null);
    const d = I.itemToTask({ id: "i5", title: "Nur Uhrzeit", time: "16" }, { bags, now });
    assert.deepEqual([d.due, d.time], ["2026-10-06", "16:00"]);
  });

  test("Herkunft und Toast-Text", () => {
    assert.deepEqual(["Zapier", "Make/production", "n8n", "IFTTT-Protocol/v1", "Mozilla/5.0 (compatible; Google-Apps-Script)", "Mozilla/5.0 (iPhone) Safari", "curl/8.4", "", "Kurzbefehle"].map(I.viaLabel), ["Zapier", "Make", "n8n", "IFTTT", "Google", "Browser", "Skript", "Webhook", "Siri"]);
    assert.equal(I.inboxToast({ added: [1, 2], vias: ["Siri"] }), "2 neue Aufgaben von Siri");
    assert.equal(I.inboxToast({ added: [1], vias: ["Siri", "Zapier"] }), "1 neue Aufgabe von Siri & Zapier");
    assert.equal(I.inboxToast({ added: [1, 2, 3], vias: ["Webhook"] }), "3 neue Aufgaben");
    assert.equal(I.inboxToast({ added: [] }), "");
  });
});

// ---------- Mit nachgebautem Server ----------
const SRV = "https://taschen.test";
function mockFetch(handlers) {
  const calls = [];
  const orig = globalThis.fetch;
  globalThis.fetch = async (url, opts = {}) => {
    const u = String(url);
    const method = opts.method || "GET";
    let body = null;
    try {
      body = opts.body ? JSON.parse(opts.body) : null;
    } catch (_) {
      body = opts.body;
    }
    calls.push({ url: u, method, body, opts });
    for (const [re, fn] of handlers) {
      if (re.test(u)) {
        const r = await fn({ url: u, method, body, calls, opts });
        if (r === "netz") throw new TypeError("Failed to fetch");
        const [status, data] = Array.isArray(r) ? r : [200, r];
        return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
      }
    }
    return new Response(JSON.stringify({ ok: false, msg: "Unbekannte Anfrage." }), { status: 404 });
  };
  return { calls, restore: () => (globalThis.fetch = orig) };
}

describe("Kalender-Links und IMAP in connect.refresh", () => {
  let mock = null;
  beforeEach(async () => {
    await store.load({ memory: true });
    await store.resetAll();
    await store.load({ memory: true });
    C._reset({ store });
  });
  afterEach(() => {
    mock?.restore();
    mock = null;
    C._reset();
  });

  const today = new Date();
  const ymd = (d) => `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, "0")}${String(d.getDate()).padStart(2, "0")}`;
  const tomorrow = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1);
  const FEED = ics(ev("UID:k1", `DTSTART;TZID=Europe/Berlin:${ymd(tomorrow)}T100000`, `DTEND;TZID=Europe/Berlin:${ymd(tomorrow)}T110000`, "SUMMARY:Kundentermin", "LOCATION:Nordstraße 12\\, 70191 Stuttgart"), ev("UID:k2", `DTSTART;VALUE=DATE:${ymd(today)}`, "SUMMARY:Tag der Einheit"));
  const IMAP_ID = "e".repeat(32);

  test("Termine aus dem Link und markierte Mails aus IMAP landen im selben Cache", async () => {
    mock = mockFetch([
      [/\/api\/feeds\/fetch$/, ({ body }) => (body.url === "https://p01-caldav.icloud.com/published/2/abc" ? { ok: true, ics: FEED, fetched: Date.now() } : [400, { ok: false, msg: "Kein Kalender unter dieser Adresse." }])],
      [/\/api\/imap\/flagged$/, ({ body }) => (body.account === IMAP_ID && body.secret === "s".repeat(30) ? { ok: true, mails: [{ uid: 42, subject: "=?UTF-8?Q?Rechnung_f=C3=BCr_Oktober?=", from: "Sparkasse", fromEmail: "info@sparkasse.de", date: Date.now() - H, snippet: "Ihr Kontoauszug" }, { uid: "x1", subject: "kaputt" }] } : [403, { ok: false, msg: "Falscher Schlüssel." }])],
    ]);
    const feed = I.addFeed(store, { name: "Familie (iCloud)", url: "webcal://p01-caldav.icloud.com/published/2/abc", color: "green", server: SRV });
    assert.equal(feed.secret, "https://p01-caldav.icloud.com/published/2/abc");
    assert.equal(feed.host, "p01-caldav.icloud.com");
    assert.equal(feed.mail, false);
    assert.throws(() => I.addFeed(store, { url: "webcal://p01-caldav.icloud.com/published/2/abc", server: SRV }), /schon/);
    I.addImapAccount(store, { account: IMAP_ID, secret: "s".repeat(30), email: "papa@gmx.de", label: "GMX", host: "imap.gmx.net", port: 993, server: SRV, kind: "gmx", webmail: "https://www.gmx.net/" });
    const r = await C.refresh(store, { force: true });
    assert.deepEqual(r.errors, []);
    const k = r.events.find((e) => e.title === "Kundentermin");
    assert.equal(k.provider, "ics");
    assert.equal(k.account, feed.id);
    assert.equal(k.calendar, "Familie (iCloud)");
    assert.equal(k.time, "10:00");
    assert.ok(r.events.some((e) => e.title === "Tag der Einheit" && e.allDay));
    assert.equal(r.mails.length, 1);
    assert.deepEqual(r.mails[0], { id: `x:${IMAP_ID}:42`, account: IMAP_ID, provider: "imap", from: "Sparkasse", fromEmail: "info@sparkasse.de", subject: "Rechnung für Oktober", snippet: "Ihr Kontoauszug", date: r.mails[0].date, web: "https://www.gmx.net/" });
    assert.deepEqual(C.calendarAccounts().map((a) => a.provider), ["ics"]);
    assert.deepEqual(C.mailAccounts().map((a) => a.provider), ["imap"]);
    assert.deepEqual(C.accounts(), []); // Google/Microsoft-Liste bleibt unberührt
    // Kalender ausblenden → keine Termine; entfernen → aus dem Cache
    store.updateAccount(feed.id, { calendars: false });
    assert.ok(!C.events().some((e) => e.account === feed.id));
    I.removeFeed(store, feed.id);
    assert.ok(!C.events({ all: true }).some((e) => e.account === feed.id));
    // Mail als Aufgabe: Link zum Webmailer
    assert.equal(C.taskFromMail(r.mails[0]).src.web, "https://www.gmx.net/");
  });

  test("Fehler je Konto: falscher Schlüssel bei IMAP → abgelaufen, Feed-Fehler → Meldung, alte Daten bleiben", async () => {
    let feedOk = true;
    mock = mockFetch([
      [/\/api\/feeds\/fetch$/, () => (feedOk ? { ok: true, ics: FEED } : [502, { ok: false, msg: "Der Kalender-Server antwortet nicht." }])],
      [/\/api\/imap\/flagged$/, () => [403, { ok: false, msg: "Der Zugang gilt nicht mehr – bitte neu verbinden." }]],
    ]);
    const feed = I.addFeed(store, { name: "Firma", url: "https://outlook.office365.com/owa/calendar/abc/reachcalendar.ics", server: SRV });
    I.addImapAccount(store, { account: IMAP_ID, secret: "s".repeat(30), email: "papa@web.de", label: "WEB.DE", host: "imap.web.de", port: 993, server: SRV, kind: "webde", webmail: "https://web.de/" });
    let r = await C.refresh(store, { force: true });
    assert.equal(r.events.filter((e) => e.account === feed.id).length, 2);
    assert.equal(r.errors.length, 1);
    assert.equal(r.errors[0].account, IMAP_ID);
    assert.equal(r.errors[0].expired, true);
    assert.equal(store.account(IMAP_ID).broken, true);
    assert.equal(C.accountState(IMAP_ID).kind, "expired");
    feedOk = false;
    r = await C.refresh(store, { force: true, retryBroken: true });
    assert.equal(r.events.filter((e) => e.account === feed.id).length, 2, "zuletzt geladene Termine bleiben");
    const fe = r.errors.find((e) => e.account === feed.id);
    assert.equal(fe.network, true);
    assert.match(fe.msg, /antwortet nicht/);
    // Kalender-Link ohne Schlüssel (nach Backup) → „neu eintragen“, ohne Anfrage
    const n = mock.calls.length;
    store.updateAccount(feed.id, { secret: "" });
    r = await C.refresh(store, { force: true });
    assert.match(r.errors.find((e) => e.account === feed.id).msg, /Kalender-Link/);
    assert.ok(mock.calls.slice(n).every((c) => !c.url.endsWith("/api/feeds/fetch")));
  });

  test("Server ohne Kalender-Links (alte Version) → klarer Hinweis; testFeed zählt Termine", async () => {
    mock = mockFetch([[/\/api\/feeds\/fetch$/, ({ body }) => (body.url.includes("neu") ? { ok: true, ics: FEED } : [404, { ok: false, msg: "Unbekannte Anfrage." }])]]);
    await assert.rejects(I.fetchFeed(SRV, "https://alt.example.de/cal.ics"), /aktualisieren/);
    await assert.rejects(I.fetchFeed("", "https://alt.example.de/cal.ics"), /Arbeitstaschen-Server/);
    await assert.rejects(I.fetchFeed(SRV, "ftp://x"), /gültiger Kalender-Link/);
    const t = await I.testFeed(SRV, "https://neu.example.de/cal.ics");
    assert.equal(t.count, 2);
    assert.equal(t.name, "Firma");
    assert.equal(t.next.title, "Tag der Einheit");
  });

  test("imapConnect: prüft Eingaben, schickt Zugang an den Server, Fehlertext vom Server", async () => {
    mock = mockFetch([[/\/api\/imap\/add$/, ({ body }) => (body.password === "richtig" ? { ok: true, account: IMAP_ID, secret: "k".repeat(43), email: body.user } : [401, { ok: false, msg: "Anmeldung fehlgeschlagen – bei GMX/WEB.DE musst du IMAP erst in den Einstellungen erlauben." }])]]);
    await assert.rejects(I.imapConnect({ server: SRV, email: "", password: "x", host: "imap.gmx.net" }), /E-Mail-Adresse/);
    await assert.rejects(I.imapConnect({ server: SRV, email: "a@gmx.de", password: "x", host: "kein host" }), /IMAP-Server/);
    await assert.rejects(I.imapConnect({ server: SRV, provider: "gmx", email: "a@gmx.de", password: "falsch", host: "imap.gmx.net" }), /IMAP erst in den Einstellungen erlauben/);
    const res = await I.imapConnect({ server: SRV, provider: "gmx", email: "a@gmx.de", password: "richtig", host: "imap.gmx.net" });
    assert.deepEqual(mock.calls.at(-1).body, { host: "imap.gmx.net", port: 993, user: "a@gmx.de", password: "richtig", label: "GMX" });
    const acc = I.addImapAccount(store, res);
    assert.deepEqual([acc.provider, acc.email, acc.label, acc.webmail, acc.mail, acc.calendars], ["imap", "a@gmx.de", "GMX", "https://www.gmx.net/", true, false]);
    assert.equal(I.mailStyle(acc).short, "GMX");
    assert.equal(I.guessMailProvider("x@t-online.de").id, "tonline");
    // Backup ohne Schlüssel
    const backup = JSON.parse(await (await store.exportBackup({ includeFiles: false })).text());
    assert.equal(backup.state.accounts.find((a) => a.id === IMAP_ID).secret, "");
  });

  test("availability: Server bietet Kalender-Links, IMAP und Briefkasten an", async () => {
    mock = mockFetch([[/\/api\/health$/, () => ({ ok: true, service: "taschen", connect: { google: true, microsoft: false }, feeds: true, imap: true, inbox: false })]]);
    assert.deepEqual(await I.availability("https://avail.test"), { google: true, microsoft: false, feeds: true, imap: true, inbox: false, server: "https://avail.test", ok: true });
    assert.deepEqual(await I.availability(""), { google: false, microsoft: false, feeds: false, imap: false, inbox: false, server: "", ok: false });
  });
});

describe("Briefkasten abholen und Webhooks senden", () => {
  let mock = null;
  beforeEach(async () => {
    await store.load({ memory: true });
    await store.resetAll();
    await store.load({ memory: true });
    I._reset();
  });
  afterEach(() => {
    mock?.restore();
    mock = null;
    I._reset();
  });
  const HOOK = "f".repeat(32);
  const KEY = "K".repeat(43);

  test("erstellen → abholen → Aufgaben anlegen (ein Rückgängig-Schritt) → quittieren; doppelt nie", async () => {
    const box = [
      { id: "a1", at: Date.now(), title: "Neue Aufgabe von Siri", source: "Kurzbefehle/1.0 CFNetwork Darwin" },
      { id: "a2", at: Date.now(), title: "Rechnung Huber prüfen", notes: "aus Zapier", due: "2026-10-12", bag: "Büro", prio: "2", url: "https://mail.example.de/1", source: "Zapier" },
    ];
    const acked = [];
    let ackFail = false;
    mock = mockFetch([
      [/\/api\/inbox\/create$/, () => ({ ok: true, hook: HOOK, key: KEY, url: `${SRV}/api/in/${HOOK}/${KEY}` })],
      [/\/api\/inbox\/pull$/, ({ body }) => (body.hook === HOOK && body.key === KEY ? { ok: true, items: box } : [403, { ok: false, msg: "Falscher Schlüssel." }])],
      [/\/api\/inbox\/ack$/, ({ body }) => (ackFail ? "netz" : (acked.push(...body.ids), { ok: true }))],
      [/\/api\/inbox\/reset$/, () => ({ ok: true, key: "N".repeat(43), url: "x" })],
    ]);
    const buero = store.addBag({ name: "Büro" });
    const acc = await I.hookCreate(store, SRV);
    assert.deepEqual([acc.id, acc.provider, acc.hook, acc.secret], [HOOK, "hook-in", HOOK, KEY]);
    assert.equal(I.hookUrl(acc), `${SRV}/api/in/${HOOK}/${KEY}`);
    assert.equal((await I.hookCreate(store, SRV)).id, HOOK, "nur ein Briefkasten");
    const events = [];
    I.onInbox((r) => events.push(r));
    const r = await I.pullInbox(store, { force: true });
    assert.deepEqual(r.added.map((t) => t.title), ["Neue Aufgabe von Siri", "Rechnung Huber prüfen"]);
    assert.deepEqual(r.vias, ["Siri", "Zapier"]);
    assert.deepEqual(acked, ["a1", "a2"]);
    assert.equal(events.length, 1);
    const t2 = store.tasks().find((t) => t.title === "Rechnung Huber prüfen");
    assert.deepEqual([t2.bag, t2.due, t2.prio, t2.src.via, t2.notes], [buero.id, "2026-10-12", 2, "Zapier", "aus Zapier\n\nhttps://mail.example.de/1"]);
    assert.equal(store.undoLabel(), "Neue Aufgaben (Briefkasten)");
    // Quittung ging verloren → beim nächsten Mal dieselben Einträge: keine Doppelten
    ackFail = true;
    const r2 = await I.pullInbox(store, { force: true });
    assert.equal(r2.added.length, 0);
    assert.equal(store.tasks().length, 2);
    // ohne force höchstens alle 2 Minuten
    const n = mock.calls.length;
    assert.equal((await I.pullInbox(store)).skipped, true);
    assert.equal(mock.calls.length, n);
    // Rückgängig nimmt beide auf einmal weg
    store.undo();
    assert.equal(store.tasks().length, 0);
    // neuer Schlüssel
    const reset = await I.hookReset(store, store.account(HOOK));
    assert.equal(reset.secret, "N".repeat(43));
    assert.match(I.hookUrl(reset), /\/NNNN/);
  });

  test("falscher Schlüssel → Fehler am Konto, keine Aufgaben", async () => {
    mock = mockFetch([[/\/api\/inbox\/pull$/, () => [403, { ok: false, msg: "Falscher Schlüssel." }]]]);
    store.addAccount({ id: HOOK, provider: "hook-in", hook: HOOK, secret: KEY, server: SRV });
    const r = await I.pullInbox(store, { force: true });
    assert.equal(r.added.length, 0);
    assert.equal(r.errors[0].expired, true);
    assert.equal(I.inboxState(HOOK).expired, true);
  });

  test("ausgehend: bei neu/erledigt JSON per no-cors an Zapier, entprellt; Briefkasten-Aufgaben lösen nichts aus", async () => {
    mock = mockFetch([[/hooks\.zapier\.com/, () => ({ ok: true })]]);
    const bag = store.addBag({ name: "Kunden" });
    const out = I.addOutHook(store, { url: "https://hooks.zapier.com/hooks/catch/1/abc/", name: "Zapier", on: ["add", "done"] });
    assert.deepEqual([out.provider, out.secret, out.on], ["hook-out", "https://hooks.zapier.com/hooks/catch/1/abc/", ["add", "done"]]);
    assert.throws(() => I.addOutHook(store, { url: "http://unsicher.de" }), /https/);
    I.start(store);
    const t = store.addTask({ title: "Angebot schicken", bag: bag.id, due: "2026-10-07", time: "09:00", prio: 3 });
    store.addTask({ title: "Vom Briefkasten", src: { kind: "hook", id: "h:z", via: "Zapier" } });
    store.completeTask(t.id);
    await new Promise((r) => setTimeout(r, 1500));
    const sent = mock.calls.filter((c) => c.url.includes("zapier"));
    assert.equal(sent.length, 2);
    assert.ok(sent.every((c) => c.method === "POST" && c.opts.mode === "no-cors" && c.opts.headers["Content-Type"] === "text/plain"));
    const [added, done] = sent.map((c) => c.body);
    assert.equal(added.event, "task.added");
    assert.deepEqual(added.task, { id: t.id, title: "Angebot schicken", notes: "", due: "2026-10-07", time: "09:00", bag: "Kunden", prio: 3, done: true }); // beim Senden schon erledigt
    assert.equal(done.event, "task.done");
    assert.equal(done.task.done, true);
    // nur „erledigt“ abonniert
    store.updateAccount(out.id, { on: ["done"] });
    store.addTask({ title: "Noch eine" });
    await new Promise((r) => setTimeout(r, 1500));
    assert.equal(mock.calls.filter((c) => c.url.includes("zapier")).length, 2);
    await I.testHook(out.secret);
    assert.equal(mock.calls.at(-1).body.event, "test");
  });
});

describe("Store: batch und Konten-Typen", () => {
  beforeEach(async () => {
    await store.load({ memory: true });
    await store.resetAll();
    await store.load({ memory: true });
  });
  test("batch: viele Aufgaben = ein Rückgängig, ein Ereignis; Fehler rollt zurück", () => {
    const seen = [];
    const off = store.subscribe((s, ch) => seen.push(ch));
    store.batch("CSV-Import", () => {
      for (let i = 0; i < 5; i++) store.addTask({ title: "Import " + i });
    });
    off();
    assert.equal(store.tasks().length, 5);
    assert.equal(seen.length, 1);
    assert.deepEqual([seen[0].type, seen[0].action, seen[0].local], ["all", "import", true]);
    assert.equal(store.undoLabel(), "CSV-Import");
    store.undo();
    assert.equal(store.tasks().length, 0);
    assert.throws(() => store.batch("kaputt", () => {
      store.addTask({ title: "a" });
      store.addTask({ title: "" });
    }));
    assert.equal(store.tasks().length, 0);
  });
  test("Konten-Typen behalten ihre Felder; Backup ohne Geheimnisse", async () => {
    store.addAccount({ provider: "ics", name: "Feiertage", secret: "https://x.de/a.ics", host: "x.de", calendars: true, mail: false, color: "green" });
    store.addAccount({ provider: "hook-out", name: "Zapier", secret: "https://hooks.zapier.com/1", on: ["done"], calendars: false, mail: false });
    const [a, b] = store.accounts();
    assert.deepEqual([a.provider, a.name, a.host, a.color, a.mail], ["ics", "Feiertage", "x.de", "green", false]);
    assert.deepEqual([b.provider, b.on], ["hook-out", ["done"]]);
    const backup = JSON.parse(await (await store.exportBackup({ includeFiles: false })).text());
    assert.ok(backup.state.accounts.every((x) => x.secret === ""));
  });
});
