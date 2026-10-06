// Tests für connect.js – Anmelde-Adressen, Rückkehr lesen, PKCE, Termine und Mails von Google und Microsoft umwandeln, Mail → Aufgabe
process.env.TZ = "Europe/Berlin";
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";

const C = await import("../js/connect.js");
const APP = "https://georgleomaser-bit.github.io/website-test-demo-1/taschen/";

describe("Anmeldung", () => {
  test("redirectUri: ohne Abfrage und Anker", () => {
    assert.equal(C.redirectUri(APP + "?x=1#einstellungen"), APP);
  });

  test("Google: Token-Weg, nur Lese-Rechte, Kontoauswahl", () => {
    const u = new URL(C.authUrl("google", { clientId: "cid", redirect: APP, state: "s1" }));
    assert.equal(u.origin + u.pathname, C.PROVIDERS.google.auth);
    assert.equal(u.searchParams.get("response_type"), "token");
    assert.equal(u.searchParams.get("redirect_uri"), APP);
    assert.equal(u.searchParams.get("state"), "s1");
    assert.equal(u.searchParams.get("prompt"), "select_account");
    const scope = u.searchParams.get("scope");
    assert.match(scope, /gmail\.readonly/);
    assert.match(scope, /calendar\.events\.readonly/);
    assert.doesNotMatch(scope, /gmail\.(send|modify|compose)|auth\/calendar(\s|$)/, "nur lesen");
  });

  test("Google: stille Neuanmeldung mit login_hint", () => {
    const u = new URL(C.authUrl("google", { clientId: "cid", redirect: APP, state: "s", loginHint: "a@b.de" }));
    assert.equal(u.searchParams.get("prompt"), "none");
    assert.equal(u.searchParams.get("login_hint"), "a@b.de");
  });

  test("Microsoft: Code-Weg mit PKCE, Rückkehr per Abfrage, nur Lese-Rechte", () => {
    const u = new URL(C.authUrl("microsoft", { clientId: "cid", redirect: APP, state: "s2", codeChallenge: "abc" }));
    assert.equal(u.searchParams.get("response_type"), "code");
    assert.equal(u.searchParams.get("response_mode"), "query");
    assert.equal(u.searchParams.get("code_challenge"), "abc");
    assert.equal(u.searchParams.get("code_challenge_method"), "S256");
    const scope = u.searchParams.get("scope").split(" ");
    assert.ok(scope.includes("Mail.Read") && scope.includes("Calendars.Read") && scope.includes("offline_access"));
    assert.ok(!scope.some((s) => /ReadWrite|Send/.test(s)), "nur lesen");
  });

  test("PKCE: challenge = base64url(SHA-256(verifier))", async () => {
    const v = C.randomString(48);
    assert.match(v, /^[A-Za-z0-9_-]{64}$/);
    const want = createHash("sha256").update(v).digest("base64url");
    assert.equal(await C.challenge(v), want);
  });

  test("ohne Client-ID wird kein Anbieter angeboten", () => {
    assert.equal(C.available("google"), false);
    assert.equal(C.available("microsoft"), false);
    assert.equal(C.anyAvailable(), false);
  });
});

describe("Rückkehr lesen", () => {
  test("Google-Token im Anker", () => {
    const r = C.parseReturn(APP + "#access_token=tok&token_type=Bearer&expires_in=3599&state=s1&scope=x");
    assert.deepEqual(r, { kind: "token", state: "s1", token: "tok", expiresIn: 3599, error: "" });
  });
  test("Google-Fehler im Anker", () => {
    const r = C.parseReturn(APP + "#error=interaction_required&state=s1");
    assert.equal(r.kind, "token");
    assert.equal(r.error, "interaction_required");
  });
  test("Microsoft-Code in der Abfrage", () => {
    const r = C.parseReturn(APP + "?code=c0de&state=s2");
    assert.equal(r.kind, "code");
    assert.equal(r.code, "c0de");
    assert.equal(r.state, "s2");
  });
  test("normale App-Adressen sind keine Rückkehr", () => {
    for (const h of [APP, APP + "#heute", APP + "#tasche/b_1/aufgaben", APP + "?view=heute", APP + "?neu=Test"]) assert.equal(C.parseReturn(h), null, h);
  });
});

describe("Termine", () => {
  test("Google: mit Uhrzeit", () => {
    const e = C.googleEvent({ id: "e1", summary: "Zahnarzt", location: "Praxis", htmlLink: "https://calendar.google.com/x", start: { dateTime: "2026-10-06T09:00:00+02:00" }, end: { dateTime: "2026-10-06T09:30:00+02:00" } });
    assert.equal(e.id, "g:e1");
    assert.equal(e.title, "Zahnarzt");
    assert.equal(e.allDay, false);
    assert.equal(new Date(e.start).getHours(), 9);
    assert.equal(e.end - e.start, 30 * 60000);
    assert.equal(e.where, "Praxis");
  });
  test("Google: ganztägig und abgesagt", () => {
    const e = C.googleEvent({ id: "e2", start: { date: "2026-10-06" }, end: { date: "2026-10-07" } });
    assert.equal(e.allDay, true);
    assert.equal(e.title, "(ohne Titel)");
    assert.equal(new Date(e.start).getDate(), 6);
    assert.equal(C.googleEvent({ id: "e3", status: "cancelled", start: { date: "2026-10-06" } }), null);
  });
  test("Microsoft: UTC-Zeiten mit 7 Nachkommastellen", () => {
    const e = C.graphEvent({ id: "m1", subject: "Team", start: { dateTime: "2026-10-06T07:00:00.0000000", timeZone: "UTC" }, end: { dateTime: "2026-10-06T08:00:00.0000000", timeZone: "UTC" }, location: { displayName: "Raum 2" }, webLink: "https://outlook.live.com/x" });
    assert.equal(new Date(e.start).getHours(), 9, "07:00 UTC = 09:00 in Berlin (Sommerzeit)");
    assert.equal(e.end - e.start, 3600000);
    assert.equal(e.where, "Raum 2");
  });
  test("Microsoft: ganztägig zählt als Kalendertag", () => {
    const e = C.graphEvent({ id: "m2", subject: "Urlaub", isAllDay: true, start: { dateTime: "2026-10-06T00:00:00.0000000" }, end: { dateTime: "2026-10-07T00:00:00.0000000" } });
    assert.equal(e.allDay, true);
    assert.equal(new Date(e.start).getDate(), 6);
    assert.equal(new Date(e.start).getHours(), 0);
    assert.equal(C.graphEvent({ id: "m3", isCancelled: true, start: {} }), null);
  });
});

describe("Mails", () => {
  test("Absendername", () => {
    assert.equal(C.senderName('"Max Muster" <max@example.com>'), "Max Muster");
    assert.equal(C.senderName("Max Muster <max@example.com>"), "Max Muster");
    assert.equal(C.senderName("<max@example.com>"), "max@example.com");
    assert.equal(C.senderName("max@example.com"), "max@example.com");
  });
  test("Gmail: Kopfzeilen, Vorschau ohne HTML-Zeichen, Link zum Konto", () => {
    const m = C.gmailMessage(
      { id: "abc", internalDate: "1791270000000", snippet: "Hallo &amp; danke, wir sehen uns &quot;morgen&quot;", payload: { headers: [{ name: "Subject", value: "Angebot" }, { name: "From", value: "Anna <anna@x.de>" }] } },
      "ich@gmail.com",
    );
    assert.equal(m.id, "g:abc");
    assert.equal(m.subject, "Angebot");
    assert.equal(m.from, "Anna");
    assert.equal(m.date, 1791270000000);
    assert.equal(m.preview, 'Hallo & danke, wir sehen uns "morgen"');
    assert.equal(m.link, "https://mail.google.com/mail/?authuser=ich%40gmail.com#all/abc");
  });
  test("Outlook: Felder und Leerraum", () => {
    const m = C.graphMessage({ id: "x1", subject: "", from: { emailAddress: { name: "Bob", address: "bob@x.de" } }, receivedDateTime: "2026-10-06T08:00:00Z", bodyPreview: "Zeile 1\r\n\r\nZeile 2", webLink: "https://outlook.live.com/owa/?ItemID=x1" });
    assert.equal(m.subject, "(kein Betreff)");
    assert.equal(m.from, "Bob");
    assert.equal(m.preview, "Zeile 1 Zeile 2");
    assert.equal(m.date, Date.parse("2026-10-06T08:00:00Z"));
  });
  test("Mail → Aufgabe: Betreff als Titel, Absender, Vorschau und Link in der Notiz", () => {
    const t = C.mailToTask({ subject: "Rechnung bezahlen", from: "Stadtwerke", preview: "Bitte bis 15.10.", link: "https://mail.google.com/mail/u/0/#all/1" });
    assert.equal(t.title, "Rechnung bezahlen");
    assert.match(t.notes, /^Von: Stadtwerke/);
    assert.match(t.notes, /> Bitte bis 15\.10\./);
    assert.match(t.notes, /\[Mail öffnen\]\(https:\/\/mail\.google\.com/);
  });
});
