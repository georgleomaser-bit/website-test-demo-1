// Tests für connect.js – Normalisierung Google/Microsoft Graph, Telefonnummern, Beitreten-Links, Kalender- und Mail-Links,
// Erinnerungen für Termine, Zugangs-Token und Laden (mit nachgebautem Server und nachgebauten APIs), Rückkehr aus der Anmeldung
process.env.TZ = "Europe/Berlin";
import { test, describe, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";

const C = await import("../js/connect.js");
const store = await import("../js/store.js");

const H = 3600000;
const MIN = 60000;
const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

// ---------- Normalisierung ----------
describe("Google Kalender → Event", () => {
  test("Termin mit Uhrzeit, Meet-Link und HTML-Beschreibung", () => {
    const e = C.normGoogleEvent(
      { id: "abc", status: "confirmed", summary: "  Jour fixe  ", start: { dateTime: "2026-10-06T09:30:00+02:00" }, end: { dateTime: "2026-10-06T10:15:00+02:00" }, location: "Büro", hangoutLink: "https://meet.google.com/abc-defg-hij", htmlLink: "https://www.google.com/calendar/event?eid=abc", description: "Agenda:<br><b>Punkt 1</b> &amp; mehr" },
      { account: "acc1", calendar: "Arbeit", calId: "primary" },
    );
    assert.equal(e.id, "g:primary:abc");
    assert.equal(e.account, "acc1");
    assert.equal(e.provider, "google");
    assert.equal(e.title, "Jour fixe");
    assert.equal(e.start, Date.parse("2026-10-06T09:30:00+02:00"));
    assert.equal(e.end - e.start, 45 * MIN);
    assert.equal(e.allDay, false);
    assert.equal(e.date, "2026-10-06");
    assert.equal(e.time, "09:30");
    assert.equal(e.join, "https://meet.google.com/abc-defg-hij");
    assert.equal(e.web, "https://www.google.com/calendar/event?eid=abc");
    assert.equal(e.calendar, "Arbeit");
    assert.equal(e.cancelled, false);
    assert.equal(e.notes, "Agenda:\nPunkt 1 & mehr");
  });

  test("ganztägig (auch mehrtägig), Video aus conferenceData, abgelehnt = abgesagt", () => {
    const a = C.normGoogleEvent({ id: "x", summary: "Messe", start: { date: "2026-10-14" }, end: { date: "2026-10-16" } });
    assert.equal(a.allDay, true);
    assert.equal(a.time, null);
    assert.equal(a.date, "2026-10-14");
    assert.equal(new Date(a.start).getHours(), 0);
    assert.equal(Math.round((a.end - a.start) / H), 48);
    const v = C.normGoogleEvent({ id: "v", summary: "Call", start: { dateTime: "2026-10-06T12:00:00Z" }, end: { dateTime: "2026-10-06T12:30:00Z" }, conferenceData: { entryPoints: [{ entryPointType: "phone", uri: "tel:+49301234" }, { entryPointType: "video", uri: "https://meet.google.com/aaa-bbbb-ccc" }] } });
    assert.equal(v.join, "https://meet.google.com/aaa-bbbb-ccc");
    const d = C.normGoogleEvent({ id: "d", summary: "Nein", start: { dateTime: "2026-10-06T12:00:00Z" }, end: { dateTime: "2026-10-06T13:00:00Z" }, attendees: [{ email: "a", self: true, responseStatus: "declined" }] });
    assert.equal(d.cancelled, true);
    assert.equal(C.normGoogleEvent({ id: "c", status: "cancelled", start: { dateTime: "2026-10-06T12:00:00Z" } }).cancelled, true);
  });

  test("Müll und gefährliche Links werden aussortiert", () => {
    assert.equal(C.normGoogleEvent(null), null);
    assert.equal(C.normGoogleEvent({ summary: "ohne id" }), null);
    assert.equal(C.normGoogleEvent({ id: "k", start: { dateTime: "kaputt" } }), null);
    const e = C.normGoogleEvent({ id: "j", summary: "\u0007Titel‮", start: { dateTime: "2026-10-06T08:00:00Z" }, htmlLink: "javascript:alert(1)", hangoutLink: "http://meet.google.com/x" });
    assert.equal(e.web, "");
    assert.equal(e.join, null);
    assert.equal(e.title, "Titel");
    assert.equal(e.end - e.start, 30 * MIN); // ohne Ende: 30 Minuten
    assert.equal(C.normGoogleEvent({ id: "o", start: { dateTime: "2026-10-06T08:00:00Z" } }).title, "(Ohne Titel)");
  });
});

describe("Microsoft Graph → Event", () => {
  test("Ortszeit (Prefer-Header), Teams-Link, Ort, Vorschau", () => {
    const e = C.normGraphEvent(
      { id: "AAMk1", subject: "Baubesprechung", start: { dateTime: "2026-10-06T08:00:00.0000000", timeZone: "Europe/Berlin" }, end: { dateTime: "2026-10-06T09:00:00.0000000", timeZone: "Europe/Berlin" }, isAllDay: false, location: { displayName: "Container 2" }, onlineMeeting: { joinUrl: "https://teams.microsoft.com/l/meetup-join/19%3a1" }, webLink: "https://outlook.office365.com/owa/?itemid=1", isCancelled: false, bodyPreview: "Bitte Pläne mitbringen" },
      { account: "m1" },
    );
    assert.equal(e.id, "m:AAMk1");
    assert.equal(e.provider, "microsoft");
    assert.equal(e.start, Date.parse("2026-10-06T08:00:00+02:00"));
    assert.equal(e.time, "08:00");
    assert.equal(e.location, "Container 2");
    assert.equal(e.join, "https://teams.microsoft.com/l/meetup-join/19%3a1");
    assert.equal(e.web, "https://outlook.office365.com/owa/?itemid=1");
    assert.equal(e.notes, "Bitte Pläne mitbringen");
    assert.equal(e.calendar, "Outlook");
  });

  test("UTC und fremde Zeitzone werden umgerechnet; ganztägig; abgesagt", () => {
    assert.equal(C.graphTime({ dateTime: "2026-10-06T07:00:00.0000000", timeZone: "UTC" }), Date.parse("2026-10-06T07:00:00Z"));
    assert.equal(C.graphTime({ dateTime: "2026-10-06T03:00:00", timeZone: "America/New_York" }), Date.parse("2026-10-06T03:00:00-04:00"));
    assert.equal(C.graphTime({ dateTime: "2026-01-10T12:00:00", timeZone: "Europe/Berlin" }), Date.parse("2026-01-10T12:00:00+01:00"));
    assert.ok(Number.isNaN(C.graphTime({ dateTime: "" })));
    const a = C.normGraphEvent({ id: "a", subject: "Urlaub", isAllDay: true, start: { dateTime: "2026-10-20T00:00:00.0000000", timeZone: "Europe/Berlin" }, end: { dateTime: "2026-10-23T00:00:00.0000000", timeZone: "Europe/Berlin" } });
    assert.equal(a.allDay, true);
    assert.equal(a.date, "2026-10-20");
    assert.equal(Math.round((a.end - a.start) / H), 72);
    assert.equal(C.normGraphEvent({ id: "s", subject: "x", isCancelled: true, start: { dateTime: "2026-10-06T08:00:00", timeZone: "UTC" } }).cancelled, true);
  });

  test("Zoom-Link aus der Vorschau, Webex aus dem Ort", () => {
    assert.equal(C.normGraphEvent({ id: "z", subject: "Lieferant", start: { dateTime: "2026-10-06T08:00:00", timeZone: "UTC" }, bodyPreview: "Zoom: https://us02web.zoom.us/j/8123456?pwd=abc." }).join, "https://us02web.zoom.us/j/8123456?pwd=abc");
    assert.equal(C.normGraphEvent({ id: "w", subject: "W", start: { dateTime: "2026-10-06T08:00:00", timeZone: "UTC" }, location: { displayName: "https://firma.webex.com/meet/mueller" } }).join, "https://firma.webex.com/meet/mueller");
  });
});

describe("Mails", () => {
  test("Gmail: Kopfzeilen (auch RFC 2047), Vorschau mit Entities, Link zum Öffnen", () => {
    const m = C.normGmail(
      { id: "m1", threadId: "t1", internalDate: "1791270000000", snippet: "Rechnung f&uuml;r Oktober &amp; Belege &#39;neu&#39;", payload: { headers: [{ name: "From", value: "=?UTF-8?Q?J=C3=BCrgen_Sch=C3=A4fer?= <Juergen@Schaefer.de>" }, { name: "Subject", value: "=?UTF-8?B?S8O8Y2hlIE5vcmQ=?=" }] } },
      { account: "g1", email: "papa@gmail.com" },
    );
    assert.equal(m.id, "g:m1");
    assert.equal(m.from, "Jürgen Schäfer");
    assert.equal(m.fromEmail, "juergen@schaefer.de");
    assert.equal(m.subject, "Küche Nord");
    assert.equal(m.snippet, "Rechnung für Oktober & Belege 'neu'");
    assert.equal(m.date, 1791270000000);
    assert.equal(m.web, "https://mail.google.com/mail/?authuser=papa%40gmail.com#all/t1");
    assert.equal(C.normGmail({ id: "m2", payload: { headers: [{ name: "From", value: "info@bank.de" }] } }).from, "info@bank.de");
    assert.equal(C.normGmail({ id: "m3" }).subject, "(Kein Betreff)");
  });

  test("Outlook: Absender, Datum, Link nur https", () => {
    const m = C.normGraphMail({ id: "o1", subject: "Angebot", from: { emailAddress: { name: "Huber GmbH", address: "Angebote@Huber.de" } }, receivedDateTime: "2026-10-06T06:55:00Z", webLink: "https://outlook.office365.com/owa/?ItemID=o1", bodyPreview: "  Sehr geehrter\nHerr Müller " }, { account: "m1" });
    assert.deepEqual([m.id, m.from, m.fromEmail, m.date, m.snippet], ["m:o1", "Huber GmbH", "angebote@huber.de", Date.parse("2026-10-06T06:55:00Z"), "Sehr geehrter Herr Müller"]);
    assert.equal(C.normGraphMail({ id: "o2", webLink: "javascript:alert(1)" }).web, "");
    assert.equal(C.parseFrom('"Müller, Hans" <hans@x.de>').name, "Müller, Hans");
  });
});

// ---------- Telefonnummern, Meetings, Links ----------
describe("Telefonnummern", () => {
  test("erkennt deutsche und internationale Schreibweisen", () => {
    const t = "Ruf an: +49 171 1234567 oder (0711) 12 34 56, Büro 030/1234567, Zentrale 0049 30 123456, Durchwahl +49 (0)89 123456-0, Handy 0171-7654321";
    assert.deepEqual(C.phones(t), ["+491711234567", "0711123456", "0301234567", "+4930123456", "+49891234560", "01717654321"]);
    assert.equal(C.phoneList("Tel. 0711 / 98 76 54")[0].label, "0711 / 98 76 54");
    assert.equal(C.telHref("+49 171 1234567"), "tel:+491711234567");
  });
  test("keine Fehlalarme: Datum, Uhrzeit, PLZ, IBAN, Preise, kurze Zahlen", () => {
    for (const t of ["am 06.10.2026 um 09:00", "09:00-17:00 Uhr", "70173 Stuttgart", "IBAN DE89 3704 0044 0532 0130 00", "kostet 0,50 €", "Raum 012", "Version 1.2.0", "Rechnung 2026-10-06"]) assert.deepEqual(C.phones(t), [], t);
  });
  test("„Anruf“, „anrufen“, „Call“ → Anruf-Aufgabe", () => {
    for (const t of ["Steuerberater anrufen", "Anruf bei Huber", "Call mit Müller", "Rückruf Herr Maier", "Kunde zurückrufen", "Telefonat Bank"]) assert.equal(C.isCall(t), true, t);
    for (const t of ["Recall prüfen", "Callcenter kündigen", "Rufbereitschaft planen", "Telefonnummer ändern"]) assert.equal(C.isCall(t), false, t);
  });
  test("E-Mail-Adressen finden", () => {
    assert.deepEqual(C.emails("an Hans@Firma.de, cc: b@c.org."), ["hans@firma.de", "b@c.org"]);
  });
});

describe("Beitreten-Links", () => {
  test("aus join, Ort oder Notizen – nur https, Art erkennen", () => {
    assert.equal(C.joinLink({ join: "https://meet.google.com/abc-defg-hij" }), "https://meet.google.com/abc-defg-hij");
    assert.equal(C.joinLink({ location: "Teams: https://teams.microsoft.com/l/meetup-join/19%3aabc/0?context=x)" }), "https://teams.microsoft.com/l/meetup-join/19%3aabc/0?context=x");
    assert.equal(C.joinLink({ notes: "Einwahl https://firma.zoom.us/j/9876543210, Kenncode 1" }), "https://firma.zoom.us/j/9876543210");
    assert.equal(C.joinLink({ notes: "https://evil.example.com/teams.microsoft.com" }), null);
    assert.equal(C.joinLink({ join: "javascript:alert(1)" }), null);
    assert.equal(C.joinLink(null), null);
    assert.equal(C.joinKind("https://teams.microsoft.com/l/x"), "Teams");
    assert.equal(C.joinKind("https://teams.live.com/meet/1"), "Teams");
    assert.equal(C.joinKind("https://meet.google.com/a"), "Meet");
    assert.equal(C.joinKind("https://us02web.zoom.us/j/1"), "Zoom");
    assert.equal(C.joinKind("https://x.webex.com/a"), "Webex");
  });
});

describe("Kalender-Links ohne Anmeldung", () => {
  const task = { id: "t_1", title: "Baubesprechung & Pläne", due: "2026-10-07", time: "14:30", est: 60, notes: "Mit Plänen" };
  test("Termin mit Uhrzeit: Google (UTC), Outlook.com und Microsoft 365", () => {
    const l = C.calendarLinks(task, {}, { appUrl: "https://taschen.example.de/taschen/" });
    const g = new URL(l.google);
    assert.equal(g.origin + g.pathname, "https://calendar.google.com/calendar/render");
    assert.equal(g.searchParams.get("action"), "TEMPLATE");
    assert.equal(g.searchParams.get("text"), "Baubesprechung & Pläne");
    assert.equal(g.searchParams.get("dates"), "20261007T123000Z/20261007T133000Z");
    assert.match(g.searchParams.get("details"), /Mit Plänen\n\nIn Arbeitstaschen öffnen: https:\/\/taschen\.example\.de\/taschen\/\?task=t_1/);
    const o = new URL(l.outlook);
    assert.equal(o.origin + o.pathname, "https://outlook.live.com/calendar/0/deeplink/compose");
    assert.equal(o.searchParams.get("subject"), "Baubesprechung & Pläne");
    assert.equal(o.searchParams.get("startdt"), "2026-10-07T14:30:00+02:00");
    assert.equal(o.searchParams.get("enddt"), "2026-10-07T15:30:00+02:00");
    assert.equal(o.searchParams.get("body").split("\n")[0], "Mit Plänen");
    assert.equal(new URL(l.office365).origin, "https://outlook.office.com");
    assert.equal(new URL(l.office365).searchParams.get("startdt"), "2026-10-07T14:30:00+02:00");
  });
  test("ganztägig ohne Uhrzeit; ohne Datum keine Links", () => {
    const l = C.calendarLinks({ title: "Messe", due: "2026-10-31" });
    assert.equal(new URL(l.google).searchParams.get("dates"), "20261031/20261101");
    assert.equal(new URL(l.outlook).searchParams.get("allday"), "true");
    assert.equal(new URL(l.outlook).searchParams.get("enddt"), "2026-11-01");
    assert.deepEqual(C.calendarLinks({ title: "x" }), { google: null, outlook: null, office365: null });
  });
});

describe("E-Mail-Links", () => {
  test("Gmail, Outlook.com, Microsoft 365 und mailto – sauber kodiert", () => {
    const l = C.composeLinks({ to: "Hans@Firma.de", subject: "Angebot Nord & Süd", body: "Hallo Hans,\nanbei?", from: "papa@gmail.com" });
    const g = new URL(l.gmail);
    assert.equal(g.origin + g.pathname, "https://mail.google.com/mail/");
    assert.deepEqual([g.searchParams.get("view"), g.searchParams.get("fs"), g.searchParams.get("to"), g.searchParams.get("su"), g.searchParams.get("body"), g.searchParams.get("authuser")], ["cm", "1", "hans@firma.de", "Angebot Nord & Süd", "Hallo Hans,\nanbei?", "papa@gmail.com"]);
    const o = new URL(l.outlook);
    assert.equal(o.origin + o.pathname, "https://outlook.live.com/mail/0/deeplink/compose");
    assert.equal(o.searchParams.get("subject"), "Angebot Nord & Süd");
    assert.equal(new URL(l.office365).origin + new URL(l.office365).pathname, "https://outlook.office.com/mail/deeplink/compose");
    assert.equal(l.mailto, "mailto:hans@firma.de?subject=Angebot%20Nord%20%26%20S%C3%BCd&body=Hallo%20Hans%2C%0Aanbei%3F");
    assert.equal(C.composeLinks({ to: "kein Empfänger", subject: "x" }).mailto, "mailto:?subject=x&body=");
    assert.equal(C.msPersonal("papa@outlook.de"), true);
    assert.equal(C.msPersonal("t.mueller@mueller-bau.de"), false);
  });
});

// ---------- Erinnerungen & Tage ----------
describe("Erinnerungen für Termine", () => {
  afterEach(() => C._reset());
  test("Termine mit Uhrzeit: defaultRemind Minuten vorher, ohne ganztägige, abgesagte und vergangene", () => {
    const now = Date.parse("2026-10-06T09:00:00+02:00");
    const ev = (id, start, extra = {}) => ({ id, account: "a", provider: "google", title: "Termin " + id, start, end: start + H, allDay: false, date: iso(new Date(start)), time: `${String(new Date(start).getHours()).padStart(2, "0")}:00`, location: "", join: null, web: "", calendar: "", cancelled: false, notes: "", ...extra });
    C._reset({ data: { events: [ev("a", now + 2 * H, { join: "https://teams.microsoft.com/l/meetup-join/1", location: "Büro" }), ev("b", now - H), ev("c", now + 3 * H, { cancelled: true }), ev("d", now + 4 * H, { allDay: true, time: null }), ev("e", now + 9 * 24 * H)] } });
    const r = C.eventReminders(new Date(now), { defaultRemind: 10 });
    assert.equal(r.length, 1);
    assert.equal(r[0].kind, "event");
    assert.equal(r[0].at, now + 2 * H - 10 * MIN);
    assert.equal(r[0].eventId, "a");
    assert.match(r[0].title, /^📅 Termin a$/);
    assert.match(r[0].body, /^11:00 Uhr \(in 10 Min\.\) · Büro · Teams-Call$/);
    assert.match(r[0].tag, /^event-\w+-\d+$/);
    assert.equal(r[0].join, "https://teams.microsoft.com/l/meetup-join/1");
    assert.equal(C.eventReminders(new Date(now), { defaultRemind: 10 })[0].tag, r[0].tag); // stabil
    assert.equal(C.eventReminders(new Date(now), {})[0].at, now + 2 * H - 15 * MIN); // Standard 15 Min.
  });

  test("eventsOn: mehrtägige Termine an jedem Tag, ganztägige zuerst; eventSummary", () => {
    const d = (s) => Date.parse(s);
    C._reset({ data: { events: [
      { id: "m", account: "a", title: "Messe", start: d("2026-10-14T00:00:00+02:00"), end: d("2026-10-16T00:00:00+02:00"), allDay: true, date: "2026-10-14", time: null, cancelled: false },
      { id: "k", account: "a", title: "Kunde", start: d("2026-10-15T09:00:00+02:00"), end: d("2026-10-15T10:00:00+02:00"), allDay: false, date: "2026-10-15", time: "09:00", cancelled: false },
      { id: "x", account: "a", title: "Abgesagt", start: d("2026-10-15T11:00:00+02:00"), end: d("2026-10-15T12:00:00+02:00"), allDay: false, date: "2026-10-15", time: "11:00", cancelled: true },
    ] } });
    assert.deepEqual(C.eventsOn("2026-10-14").map((e) => e.id), ["m"]);
    assert.deepEqual(C.eventsOn("2026-10-15").map((e) => e.id), ["m", "k"]);
    assert.deepEqual(C.eventsOn("2026-10-16").map((e) => e.id), []);
    assert.equal(C.eventSummary("2026-10-15"), "📅 2 Termine – erster um 9:00: Kunde");
    assert.equal(C.eventSummary("2026-10-14"), "📅 1 Termin");
    assert.equal(C.eventSummary("2026-10-20"), "");
  });

  test("Aufgabe aus Mail und Termin", () => {
    const t = C.taskFromMail({ id: "m:1", provider: "microsoft", from: "Huber GmbH", fromEmail: "a@huber.de", subject: "Angebot", web: "https://outlook.office365.com/x" });
    assert.equal(t.title, "Angebot");
    assert.equal(t.notes, "Von Huber GmbH <a@huber.de> · https://outlook.office365.com/x");
    assert.deepEqual(t.src, { kind: "mail", id: "m:1", provider: "microsoft", web: "https://outlook.office365.com/x", email: "a@huber.de" });
    const e = C.taskFromEvent({ id: "g:p:1", provider: "google", title: "Call", date: "2026-10-06", time: "11:00", start: 0, end: 30 * MIN, allDay: false, location: "Büro", join: "https://meet.google.com/a", web: "https://www.google.com/calendar/event?eid=1" });
    assert.deepEqual([e.title, e.due, e.time, e.est, e.remind], ["Call", "2026-10-06", "11:00", 30, -1]);
    assert.match(e.notes, /📍 Büro\nMeet: https:\/\/meet\.google\.com\/a/);
  });
});

// ---------- Token, Laden, Eintragen (nachgebauter Server + APIs) ----------
const SRV = "https://taschen.test";
function mockFetch(handlers) {
  const calls = [];
  const orig = globalThis.fetch;
  globalThis.fetch = async (url, opts = {}) => {
    const u = String(url);
    const method = opts.method || "GET";
    const body = opts.body ? JSON.parse(opts.body) : null;
    const headers = opts.headers || {};
    calls.push({ url: u, method, body, headers });
    for (const [re, fn] of handlers) {
      if (re.test(u)) {
        const r = await fn({ url: u, method, body, headers, calls });
        if (r === "netz") throw new TypeError("Failed to fetch");
        const [status, data] = Array.isArray(r) ? r : [200, r];
        return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
      }
    }
    return new Response(JSON.stringify({ error: { message: "unbekannt" } }), { status: 404 });
  };
  return { calls, restore: () => (globalThis.fetch = orig) };
}

const GACC = { id: "a".repeat(32), provider: "google", email: "papa@gmail.com", secret: "s".repeat(43), server: SRV };
const MACC = { id: "b".repeat(32), provider: "microsoft", email: "t@firma.de", secret: "m".repeat(43), server: SRV };

describe("Token und Laden", () => {
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

  const tokenHandler = (state = {}) => [
    /\/api\/connect\/token$/,
    ({ body }) => {
      state.n = (state.n || 0) + 1;
      if (state.gone?.includes(body.account)) return [410, { ok: false, msg: "Die Verbindung zu x ist abgelaufen – bitte neu verbinden." }];
      const p = body.account === GACC.id ? "google" : "microsoft";
      return { ok: true, access_token: `tok-${p}-${state.n}`, expires_at: Date.now() + H, provider: p };
    },
  ];

  test("token: holt beim Server, merkt sich bis kurz vor Ablauf, 410 → Konto abgelaufen", async () => {
    const st = {};
    mock = mockFetch([tokenHandler(st)]);
    const a = store.addAccount(GACC);
    assert.equal(await C.token(a), "tok-google-1");
    assert.equal(await C.token(a), "tok-google-1"); // aus dem Speicher
    assert.equal(st.n, 1);
    assert.equal(mock.calls[0].url, SRV + "/api/connect/token");
    assert.deepEqual(mock.calls[0].body, { account: GACC.id, secret: GACC.secret });
    assert.equal(await C.token(a, { force: true }), "tok-google-2");
    st.gone = [GACC.id];
    await assert.rejects(C.token(a, { force: true }), (e) => e.expired && /abgelaufen/.test(e.message));
    assert.equal(store.account(a.id).broken, true);
    assert.equal(C.accountState(a.id).kind, "expired");
  });

  test("refresh: Google und Microsoft – Termine, markierte Mails, Paging, Cache", async () => {
    const graphPage2 = "https://graph.microsoft.com/v1.0/me/calendarView?$skip=250";
    mock = mockFetch([
      tokenHandler(),
      [/calendarList/, () => ({ items: [{ id: "primary", primary: true, selected: true, summary: "papa@gmail.com" }, { id: "aus", selected: false, summary: "Feiertage" }] })],
      [/calendars\/primary\/events/, () => ({ items: [{ id: "e1", summary: "Mittag", start: { dateTime: "2026-10-06T12:30:00+02:00" }, end: { dateTime: "2026-10-06T13:30:00+02:00" } }] })],
      [/calendars\/aus\/events/, () => ({ items: [{ id: "nein", summary: "darf nicht kommen", start: { date: "2026-10-06" } }] })],
      [/gmail\.googleapis\.com\/gmail\/v1\/users\/me\/messages\?/, ({ url }) => (assert.match(decodeURIComponent(url), /q=is:starred/), { messages: [{ id: "g1", threadId: "t1" }] })],
      [/gmail\.googleapis\.com\/gmail\/v1\/users\/me\/messages\/g1/, () => ({ id: "g1", threadId: "t1", internalDate: "1791270000000", payload: { headers: [{ name: "From", value: "Bank <b@bank.de>" }, { name: "Subject", value: "Auszug" }] } })],
      [/\$skip=250/, () => ({ value: [{ id: "p2", subject: "Seite 2", start: { dateTime: "2026-10-07T08:00:00", timeZone: "Europe/Berlin" }, end: { dateTime: "2026-10-07T09:00:00", timeZone: "Europe/Berlin" } }], "@odata.nextLink": "https://evil.example.com/steal" })],
      [/graph\.microsoft\.com\/v1\.0\/me\/calendarView/, ({ headers }) => (assert.equal(headers.Prefer, 'outlook.timezone="Europe/Berlin"'), { value: [{ id: "jf", subject: "Jour fixe", start: { dateTime: "2026-10-06T09:30:00", timeZone: "Europe/Berlin" }, end: { dateTime: "2026-10-06T10:15:00", timeZone: "Europe/Berlin" }, onlineMeeting: { joinUrl: "https://teams.microsoft.com/l/meetup-join/1" } }, { id: "x", subject: "storniert", isCancelled: true, start: { dateTime: "2026-10-06T11:00:00", timeZone: "Europe/Berlin" } }], "@odata.nextLink": graphPage2 })],
      [/graph\.microsoft\.com\/v1\.0\/me\/messages/, ({ url }) => (assert.match(decodeURIComponent(url), /\$filter=flag\/flagStatus eq 'flagged'/), { value: [{ id: "o1", subject: "Angebot", from: { emailAddress: { name: "Huber", address: "a@huber.de" } }, receivedDateTime: "2026-10-06T07:00:00Z", webLink: "https://outlook.office365.com/x" }] })],
    ]);
    store.addAccount(GACC);
    store.addAccount(MACC);
    const r = await C.refresh(store, { force: true });
    assert.deepEqual(r.errors, []);
    assert.deepEqual(r.events.map((e) => e.title), ["Jour fixe", "Mittag", "Seite 2"]); // nach Beginn sortiert, ohne abgesagte
    assert.equal(r.events[0].join, "https://teams.microsoft.com/l/meetup-join/1");
    assert.deepEqual(r.mails.map((m) => m.subject).sort(), ["Angebot", "Auszug"]);
    assert.ok(!mock.calls.some((c) => c.url.includes("evil.example.com")), "Token nie an fremde Adressen");
    assert.ok(mock.calls.filter((c) => /googleapis|graph\.microsoft/.test(c.url)).every((c) => /^Bearer tok-/.test(c.headers.Authorization)));
    assert.equal(C.events({ all: true }).length, 4);
    // binnen 5 Minuten aus dem Cache
    const n = mock.calls.length;
    await C.refresh(store);
    assert.equal(mock.calls.length, n);
    // Schalter „Termine anzeigen“ aus → keine Termine dieses Kontos
    store.updateAccount(MACC.id, { calendars: false });
    assert.deepEqual(C.events().map((e) => e.title), ["Mittag"]);
    // übernommene Mail wird nicht mehr angeboten
    C.markTaken("m:o1", "t_123");
    assert.deepEqual(C.mails().map((m) => m.id), ["g:g1"]);
    assert.equal(C.isTaken("m:o1"), true);
    C.markTaken("m:o1", false);
    assert.equal(C.mails().length, 2);
  });

  test("401 → Token einmal neu holen und wiederholen; Ausfall eines Kontos lässt die anderen laden", async () => {
    let first = true;
    mock = mockFetch([
      tokenHandler(),
      [/calendarList/, ({ headers }) => (first ? ((first = false), [401, { error: { message: "Invalid Credentials" } }]) : { items: [{ id: "primary", selected: true }] })],
      [/calendars\/primary\/events/, () => ({ items: [{ id: "e1", summary: "Mittag", start: { dateTime: "2026-10-06T12:30:00+02:00" }, end: { dateTime: "2026-10-06T13:30:00+02:00" } }] })],
      [/gmail/, () => ({ messages: [] })],
      [/graph/, () => "netz"],
    ]);
    store.addAccount(GACC);
    store.addAccount(MACC);
    const r = await C.refresh(store, { force: true });
    assert.deepEqual(r.events.map((e) => e.title), ["Mittag"]);
    const tokens = mock.calls.filter((c) => c.url.endsWith("/api/connect/token") && c.body.account === GACC.id);
    assert.equal(tokens.length, 2, "nach 401 genau ein neues Token");
    assert.ok(r.errors.length >= 1);
    assert.ok(r.errors.every((e) => e.account === MACC.id && e.network));
    assert.equal(C.accountState(GACC.id).kind, "ok");
    assert.equal(C.accountState(MACC.id).kind, "network");
  });

  test("Konto ohne Schlüssel (z. B. nach Backup-Import) → „neu verbinden“, ohne Anfrage", async () => {
    mock = mockFetch([tokenHandler()]);
    store.addAccount({ ...GACC, secret: "" });
    const r = await C.refresh(store, { force: true });
    assert.equal(mock.calls.length, 0);
    assert.equal(r.errors[0].expired, true);
    assert.equal(C.accountState(GACC.id).kind, "expired");
  });

  test("createEvent: Google mit Uhrzeit und Erinnerung, Microsoft ganztägig und mit Uhrzeit", async () => {
    const posted = [];
    mock = mockFetch([
      tokenHandler(),
      [/calendars\/primary\/events$/, ({ body, method }) => (posted.push({ p: "g", method, body }), { id: "n1", htmlLink: "https://www.google.com/calendar/event?eid=n1" })],
      [/graph\.microsoft\.com\/v1\.0\/me\/events$/, ({ body, method }) => (posted.push({ p: "m", method, body }), [201, { id: "n2", webLink: "https://outlook.office365.com/owa/?itemid=n2" }])],
      [/./, () => ({ items: [], value: [], messages: [] })],
    ]);
    const g = store.addAccount(GACC);
    const m = store.addAccount(MACC);
    const task = { id: "t1", title: "Baubesprechung", due: "2026-10-07", time: "14:30", est: 90, notes: "Pläne", remind: 30 };
    const rg = await C.createEvent(g, task, { defaultRemind: 15 }, { appUrl: "https://x.de/taschen/" });
    assert.equal(rg.web, "https://www.google.com/calendar/event?eid=n1");
    const gb = posted[0].body;
    assert.equal(posted[0].method, "POST");
    assert.equal(gb.summary, "Baubesprechung");
    assert.deepEqual(gb.start, { dateTime: "2026-10-07T14:30:00+02:00", timeZone: "Europe/Berlin" });
    assert.deepEqual(gb.end, { dateTime: "2026-10-07T16:00:00+02:00", timeZone: "Europe/Berlin" });
    assert.deepEqual(gb.reminders, { useDefault: false, overrides: [{ method: "popup", minutes: 30 }] });
    assert.match(gb.description, /^Pläne\n\nIn Arbeitstaschen öffnen: https:\/\/x\.de\/taschen\/\?task=t1$/);
    const rm = await C.createEvent(m, { ...task, remind: null }, { defaultRemind: 15 });
    assert.equal(rm.web, "https://outlook.office365.com/owa/?itemid=n2");
    const mb = posted[1].body;
    assert.deepEqual([mb.subject, mb.start, mb.end, mb.isAllDay, mb.isReminderOn, mb.reminderMinutesBeforeStart], ["Baubesprechung", { dateTime: "2026-10-07T14:30:00", timeZone: "Europe/Berlin" }, { dateTime: "2026-10-07T16:00:00", timeZone: "Europe/Berlin" }, false, true, 15]);
    await C.createEvent(m, { id: "t2", title: "Messe", due: "2026-10-20" }, {});
    assert.deepEqual([posted[2].body.isAllDay, posted[2].body.start.dateTime, posted[2].body.end.dateTime], [true, "2026-10-20T00:00:00", "2026-10-21T00:00:00"]);
    await C.createEvent(g, { id: "t3", title: "Feiertag", due: "2026-10-03" }, {});
    assert.deepEqual([posted[3].body.start, posted[3].body.end], [{ date: "2026-10-03" }, { date: "2026-10-04" }]);
    await assert.rejects(C.createEvent(g, { id: "t4", title: "ohne Datum" }, {}), /Datum/);
  });

  test("disconnect: beim Server entfernen, hier löschen (Grabstein ohne Schlüssel)", async () => {
    mock = mockFetch([[/\/api\/connect\/remove$/, ({ body }) => (assert.deepEqual(body, { account: GACC.id, secret: GACC.secret }), { ok: true, revoked: true })]]);
    store.addAccount(GACC);
    const r = await C.disconnect(GACC.id);
    assert.deepEqual(r, { ok: true, remote: true });
    assert.equal(store.account(GACC.id), null);
    const raw = store.get().accounts.find((a) => a.id === GACC.id);
    assert.ok(raw.deleted);
    assert.equal(raw.secret, "");
  });
});

// ---------- Rückkehr aus der Anmeldung ----------
describe("handleReturn", () => {
  const saved = {};
  let ss;
  beforeEach(async () => {
    await store.load({ memory: true });
    await store.resetAll();
    await store.load({ memory: true });
    C._reset({ store });
    ss = new Map();
    for (const k of ["location", "history", "sessionStorage"]) saved[k] = Object.getOwnPropertyDescriptor(globalThis, k);
    const loc = { hash: "", pathname: "/taschen/", search: "", href: "https://app.test/taschen/" };
    Object.defineProperty(globalThis, "location", { value: loc, configurable: true, writable: true });
    Object.defineProperty(globalThis, "history", { value: { replaceState: (_s, _t, url) => (loc.hash = url.slice(url.indexOf("#"))) }, configurable: true, writable: true });
    Object.defineProperty(globalThis, "sessionStorage", { value: { getItem: (k) => ss.get(k) ?? null, setItem: (k, v) => ss.set(k, String(v)), removeItem: (k) => ss.delete(k) }, configurable: true, writable: true });
  });
  afterEach(() => {
    for (const k of Object.keys(saved)) {
      if (saved[k]) Object.defineProperty(globalThis, k, saved[k]);
      else delete globalThis[k];
    }
    C._reset();
  });
  const pending = (provider, at = Date.now()) => ss.set("taschen-connect-pending", JSON.stringify({ provider, server: SRV, back: "#einstellungen/konten", at }));

  test("selbst gestartet: Konto anlegen, Schlüssel sofort aus der Adresse", () => {
    pending("microsoft");
    location.hash = `#connect=microsoft&account=${MACC.id}&secret=${MACC.secret}&email=${encodeURIComponent("T@Firma.de")}`;
    assert.equal(C.handleReturn(store), true);
    assert.equal(location.hash, "#einstellungen/konten");
    const r = C.lastReturn();
    assert.deepEqual([r.ok, r.provider, r.email], [true, "microsoft", "T@Firma.de"]);
    const a = store.account(MACC.id);
    assert.deepEqual([a.provider, a.email, a.secret, a.server, a.calendars, a.mail], ["microsoft", "T@Firma.de", MACC.secret, SRV, true, true]);
    assert.ok(a.color);
    assert.equal(ss.size, 0, "Merker ist verbraucht");
  });

  test("dasselbe Postfach erneut verbunden → altes Konto ersetzt (Farbe & Schalter bleiben)", () => {
    const old = store.addAccount({ ...MACC, id: "e".repeat(32), email: "t@firma.de", color: "purple", mail: false });
    pending("microsoft");
    location.hash = `#connect=microsoft&account=${MACC.id}&secret=${MACC.secret}&email=t%40firma.de`;
    C.handleReturn(store);
    assert.deepEqual(store.accounts().map((a) => a.id), [MACC.id]);
    assert.equal(store.account(old.id), null);
    assert.equal(store.account(MACC.id).color, "purple");
    assert.equal(store.account(MACC.id).mail, false);
    assert.equal(C.lastReturn().replaced, true);
  });

  test("fremder Link ohne Merker (oder zu alt / anderer Anbieter) wird ignoriert und entfernt", () => {
    location.hash = `#connect=google&account=${GACC.id}&secret=${GACC.secret}&email=x%40y.de`;
    assert.equal(C.handleReturn(store), false);
    assert.equal(location.hash, "#heute");
    assert.equal(store.accounts().length, 0);
    pending("google", Date.now() - 16 * MIN);
    location.hash = `#connect=google&account=${GACC.id}&secret=${GACC.secret}&email=x%40y.de`;
    assert.equal(C.handleReturn(store), false);
    pending("microsoft");
    location.hash = `#connect=google&account=${GACC.id}&secret=${GACC.secret}&email=x%40y.de`;
    assert.equal(C.handleReturn(store), false);
    assert.equal(store.accounts().length, 0);
  });

  test("Fehler vom Server freundlich durchreichen; unvollständige Antwort", () => {
    pending("microsoft");
    location.hash = `#connect=microsoft&error=${encodeURIComponent("Deine Firma erlaubt diese App noch nicht – bitte die IT um Freigabe")}`;
    assert.equal(C.handleReturn(store), true);
    assert.deepEqual(C.lastReturn(), { ok: false, provider: "microsoft", error: "Deine Firma erlaubt diese App noch nicht – bitte die IT um Freigabe" });
    pending("google");
    location.hash = `#connect=google&account=kurz&secret=x`;
    assert.equal(C.handleReturn(store), true);
    assert.match(C.lastReturn().error, /unvollständig/);
    assert.equal(store.accounts().length, 0);
    assert.equal(C.handleReturn(store), false); // kein #connect mehr
  });

  test("startConnect: Navigation zum Server mit Rücksprung-Adresse und Merker", () => {
    const url = C.startConnect("google", SRV, { back: "#einstellungen/konten" });
    assert.equal(url, `${SRV}/api/connect/google/start?return=${encodeURIComponent("https://app.test/taschen/")}`);
    assert.equal(location.href, url);
    const p = JSON.parse(ss.get("taschen-connect-pending"));
    assert.deepEqual([p.provider, p.server, p.back], ["google", SRV, "#einstellungen/konten"]);
    assert.throws(() => C.startConnect("yahoo", SRV), /Unbekannter Anbieter/);
  });
});

describe("Anbieter", () => {
  test("providers()", () => {
    assert.deepEqual(C.providers(), [
      { id: "google", name: "Google", sub: "Gmail · Google Kalender · Workspace" },
      { id: "microsoft", name: "Microsoft", sub: "Outlook · Microsoft 365 · Outlook.com" },
    ]);
  });
  test("status(): aus /api/health → connect", async () => {
    const orig = globalThis.fetch;
    globalThis.fetch = async (url) => new Response(JSON.stringify({ ok: true, service: "taschen", connect: { google: true, microsoft: false } }), { status: 200 });
    try {
      const s = await C.status("https://status.test");
      assert.deepEqual([s.google, s.microsoft, s.server], [true, false, "https://status.test"]);
      assert.deepEqual(await C.status(""), { google: false, microsoft: false, server: "", ok: false });
    } finally {
      globalThis.fetch = orig;
    }
  });
});
