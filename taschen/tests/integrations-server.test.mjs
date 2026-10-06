// Tests für „Mit allem verbinden“ am Arbeitstaschen-Server: Kalender-Abo-Proxy (inkl. SSRF-Schutz), IMAP gegen einen
// Mock-IMAP-Server (Klartext im Test) und den Webhook-Eingang (create/in/pull/ack/reset/remove, CORS * nur für /api/in)
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import net from "node:net";
import zlib from "node:zlib";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  start,
  openToken,
  parseConnectKey,
  blockedIp,
  feedUrl,
  allowList,
  decodeWords,
  decodeText,
  parseHeaders,
  parseFrom,
  mailSnippet,
  htmlToText,
  imapString,
  imapTokens,
  imapDate,
  imapLoginHelp,
  mailProvider,
  hookSource,
  inboxItem,
} from "../server/taschen-server.mjs";

const TMP = fs.mkdtempSync(path.join(os.tmpdir(), "taschen-integrations-test-"));
const GH = "https://georgleomaser-bit.github.io";
const MB = 1024 * 1024;
const sha = (s) => crypto.createHash("sha256").update(s).digest("hex");
const dataDir = (name) => path.join(TMP, name);
const keyOf = (name) => parseConnectKey(fs.readFileSync(path.join(dataDir(name), "connect.key"), "utf8"));

// ---------- Helfer ----------
async function call(base, method, p, { json, body, headers = {} } = {}) {
  const init = { method, headers: { ...headers } };
  if (json !== undefined) {
    init.headers["Content-Type"] = "application/json";
    init.body = JSON.stringify(json);
  } else if (body !== undefined) init.body = body;
  const res = await fetch(base + p, init);
  const text = await res.text();
  let data = null;
  try {
    data = JSON.parse(text);
  } catch (_) {
    data = null;
  }
  return { status: res.status, headers: res.headers, data, text };
}
function raw(port, method, p, { headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: "127.0.0.1", port, method, path: p, headers }, (res) => {
      const parts = [];
      res.on("data", (c) => parts.push(c));
      res.on("end", () => {
        const text = Buffer.concat(parts).toString("utf8");
        let data = null;
        try {
          data = JSON.parse(text);
        } catch (_) {
          data = null;
        }
        resolve({ status: res.statusCode, headers: res.headers, text, data });
      });
    });
    req.on("error", reject);
    req.end(body);
  });
}
const servers = [];
async function boot(name, env = {}) {
  const s = await start({ env: { PORT: "0", HOST: "127.0.0.1", DATA_DIR: dataDir(name), ...env }, quiet: true });
  servers.push(s);
  return { ...s, base: `http://127.0.0.1:${s.port}` };
}

// ---------- Attrappe eines Webservers mit Kalendern ----------
const ICS = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//DE\r\nBEGIN:VEVENT\r\nUID:1@test\r\nDTSTART:20261007T090000Z\r\nDTEND:20261007T100000Z\r\nSUMMARY:Teammeeting\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
const padded = (bytes) => Buffer.from(`BEGIN:VCALENDAR\r\n${"X-PAD:".padEnd(70, "x")}\r\n`.repeat(Math.ceil(bytes / 78)).slice(0, bytes));
function mockWeb() {
  const m = { hits: [], sockets: new Set() };
  const srv = http.createServer((req, res) => {
    const u = new URL(req.url, "http://x");
    m.hits.push({ path: u.pathname, search: u.search, headers: req.headers });
    res.on("error", () => {});
    const p = u.pathname;
    const ok = (body, headers = {}) => {
      res.writeHead(200, { "Content-Type": "text/calendar; charset=utf-8", ...headers });
      res.end(body);
    };
    if (p === "/cal.ics") return ok(ICS);
    if (p === "/bom.ics") return ok("\ufeff" + ICS.replace("Teammeeting", "Grüße mit BOM"));
    if (p === "/latin.ics") return ok(Buffer.concat([Buffer.from("BEGIN:VCALENDAR\r\nSUMMARY:Gr"), Buffer.from([0xfc]), Buffer.from("n "), Buffer.from([0x80]), Buffer.from("\r\nEND:VCALENDAR\r\n")]), { "Content-Type": "text/calendar; charset=windows-1252" });
    if (p === "/gzip.ics") return ok(zlib.gzipSync(ICS), { "Content-Encoding": "gzip" });
    if (p === "/br.ics") return ok(zlib.brotliCompressSync(ICS), { "Content-Encoding": "br" });
    if (p === "/bomb.ics") return ok(zlib.gzipSync(padded(6 * MB)), { "Content-Encoding": "gzip" });
    if (p === "/redirect") {
      res.writeHead(302, { Location: "/cal.ics" });
      return res.end();
    }
    if (p === "/redirect-abs") {
      res.writeHead(301, { Location: `http://127.0.0.1:${m.port}/cal.ics?abs=1` });
      return res.end();
    }
    if (p === "/loop") {
      res.writeHead(302, { Location: `/loop?n=${(+u.searchParams.get("n") || 0) + 1}` });
      return res.end();
    }
    if (p === "/to") {
      res.writeHead(307, { Location: u.searchParams.get("to") });
      return res.end();
    }
    if (p === "/html") {
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      return res.end("<!doctype html><html><body>Kalender-Ansicht</body></html>");
    }
    if (p === "/text") {
      res.writeHead(200, { "Content-Type": "text/plain" });
      return res.end("Hallo Welt");
    }
    if (p === "/missing") {
      res.writeHead(404);
      return res.end("nicht da");
    }
    if (p === "/forbidden") {
      res.writeHead(403);
      return res.end("nein");
    }
    if (p === "/big") {
      const n = 5 * MB + 1;
      res.writeHead(200, { "Content-Type": "text/calendar", "Content-Length": String(n) });
      return res.end(padded(n));
    }
    if (p === "/chunked") {
      // ohne Content-Length: der Server muss beim Lesen abbrechen
      res.writeHead(200, { "Content-Type": "text/calendar" });
      const total = +u.searchParams.get("n");
      let sent = 0;
      const more = () => {
        while (sent < total) {
          const c = padded(Math.min(64 * 1024, total - sent));
          sent += c.length;
          if (!res.write(c)) return res.once("drain", more);
        }
        res.end();
      };
      return more();
    }
    if (p === "/redirect-stream" || p === "/error-stream") {
      // Weiterleitung bzw. Fehler mit endlosem Körper – der Server bricht ab und darf dabei nicht abstürzen
      res.writeHead(p === "/redirect-stream" ? 302 : 500, p === "/redirect-stream" ? { Location: "/cal.ics?stream=1" } : { "Content-Type": "text/html" });
      const t = setInterval(() => res.write("x".repeat(4096)), 2);
      res.on("close", () => clearInterval(t));
      return;
    }
    if (p === "/slow") return; // antwortet nie
    res.writeHead(404);
    res.end();
  });
  srv.on("connection", (s) => {
    m.sockets.add(s);
    s.on("close", () => m.sockets.delete(s));
  });
  srv.on("clientError", (e, s) => s.destroy());
  return new Promise((resolve) =>
    srv.listen(0, "127.0.0.1", () => {
      m.srv = srv;
      m.port = srv.address().port;
      m.base = `http://127.0.0.1:${m.port}`;
      resolve(m);
    }),
  );
}

// ---------- Attrappe eines IMAP-Servers (Klartext) ----------
// Versteht LOGIN (quoted und synchronisierende Literale), SELECT/EXAMINE, UID SEARCH FLAGGED, UID FETCH, LOGOUT.
// Antworten gehen auf Wunsch in kleinen Stücken raus (chunk), damit der Client wirklich puffern muss.
const H_FIELDS = "BODY[HEADER.FIELDS (SUBJECT FROM DATE CONTENT-TYPE CONTENT-TRANSFER-ENCODING)]";
function mockImap() {
  const m = { users: {}, messages: [], logins: [], commands: [], sessions: 0, chunk: 0, silent: false };
  const args = (segs) => {
    const out = [];
    for (const s of segs) {
      if (Buffer.isBuffer(s)) {
        out.push(s.toString("utf8"));
        continue;
      }
      const re = /"((?:[^"\\]|\\.)*)"|(\S+)/g;
      let x;
      while ((x = re.exec(s))) out.push(x[1] !== undefined ? x[1].replace(/\\(.)/g, "$1") : x[2]);
    }
    return out;
  };
  const fetchLine = (seq, msg) => {
    const B = (s) => Buffer.from(s, "utf8");
    const hdr = Buffer.isBuffer(msg.header) ? msg.header : B(msg.header);
    const body = msg.body == null ? null : (Buffer.isBuffer(msg.body) ? msg.body : B(msg.body)).subarray(0, 2000);
    const hv = msg.headerQuoted ? [B(`"${hdr.toString("utf8").replace(/[\\"]/g, "\\$&")}"`)] : [B(`{${hdr.length}}\r\n`), hdr];
    const bv = body == null ? [B("NIL")] : [B(`{${body.length}}\r\n`), body];
    const items = {
      uid: [B(`UID ${msg.uid}`)],
      flags: [B(`FLAGS (\\Seen${msg.flagged ? " \\Flagged" : ""})`)],
      date: [B(`INTERNALDATE "${msg.date}"`)],
      header: [B(`${H_FIELDS} `), ...hv],
      text: [B("BODY[TEXT]<0> "), ...bv],
    };
    const order = msg.reversed ? ["text", "flags", "header", "date", "uid"] : ["uid", "flags", "date", "header", "text"];
    const parts = [B(`* ${seq} FETCH (`)];
    order.forEach((k, i) => parts.push(...(i ? [B(" ")] : []), ...items[k]));
    parts.push(B(")\r\n"));
    return Buffer.concat(parts);
  };
  const srv = net.createServer((sock) => {
    m.sessions++;
    sock.on("error", () => {});
    if (m.silent) return; // keine Begrüßung → Zeitüberschreitung
    let out = Promise.resolve();
    const send = (data) => {
      const b = Buffer.isBuffer(data) ? data : Buffer.from(data, "utf8");
      out = out.then(async () => {
        if (!m.chunk) return void sock.write(b);
        for (let i = 0; i < b.length; i += m.chunk) {
          sock.write(b.subarray(i, i + m.chunk));
          await new Promise((r) => setImmediate(r));
        }
      });
      return out;
    };
    send("* OK [CAPABILITY IMAP4rev1 AUTH=PLAIN] Mock-IMAP bereit\r\n");
    let buf = Buffer.alloc(0);
    let segs = [];
    let need = -1;
    let authed = false;
    const handle = (cmd) => {
      const a = args(cmd);
      const [tag, name = "", ...rest] = a;
      const text = cmd.filter((x) => typeof x === "string").join("");
      m.commands.push({ name: name.toUpperCase(), args: rest, segs: cmd, text });
      const N = name.toUpperCase();
      if (N === "LOGIN") {
        const [user, pass] = rest;
        m.logins.push({ user, pass, segs: cmd });
        if (Object.hasOwn(m.users, user) && m.users[user] === pass) {
          authed = true;
          return send(`${tag} OK [CAPABILITY IMAP4rev1] Angemeldet\r\n`);
        }
        return send(`${tag} NO [AUTHENTICATIONFAILED] Authentication failed.\r\n`);
      }
      if (N === "LOGOUT") return send(`* BYE Tschüss\r\n${tag} OK LOGOUT fertig\r\n`).then(() => sock.end());
      if (!authed) return send(`${tag} BAD Bitte erst anmelden\r\n`);
      if (N === "EXAMINE" || N === "SELECT") return send(`* ${m.messages.length} EXISTS\r\n* OK [UIDVALIDITY 42] UIDs gültig\r\n* FLAGS (\\Seen \\Flagged)\r\n${tag} OK [READ-ONLY] fertig\r\n`);
      if (N === "UID" && rest[0]?.toUpperCase() === "SEARCH") {
        const uids = m.messages.filter((x) => x.flagged).map((x) => x.uid);
        return send(`* SEARCH${uids.map((u) => ` ${u}`).join("")}\r\n${tag} OK SEARCH fertig\r\n`);
      }
      if (N === "UID" && rest[0]?.toUpperCase() === "FETCH") {
        const want = new Set(rest[1].split(",").map(Number));
        const lines = m.messages.map((msg, i) => (want.has(msg.uid) ? fetchLine(i + 1, msg) : null)).filter(Boolean);
        return send(Buffer.concat([...lines, Buffer.from(`${tag} OK FETCH fertig\r\n`)]));
      }
      return send(`${tag} BAD Unbekannter Befehl\r\n`);
    };
    sock.on("data", (c) => {
      buf = Buffer.concat([buf, c]);
      for (;;) {
        if (need >= 0) {
          if (buf.length < need) return;
          segs.push(Buffer.from(buf.subarray(0, need)));
          buf = buf.subarray(need);
          need = -1;
          continue;
        }
        const i = buf.indexOf("\r\n");
        if (i < 0) return;
        const line = buf.toString("utf8", 0, i);
        buf = buf.subarray(i + 2);
        const lit = /\{(\d+)(\+?)\}$/.exec(line);
        if (lit) {
          segs.push(line.slice(0, lit.index));
          need = +lit[1];
          if (!lit[2]) send("+ Bereit\r\n");
          continue;
        }
        segs.push(line);
        const cmd = segs;
        segs = [];
        handle(cmd);
      }
    });
  });
  return new Promise((resolve) =>
    srv.listen(0, "127.0.0.1", () => {
      m.srv = srv;
      m.port = srv.address().port;
      resolve(m);
    }),
  );
}

// Postfach mit markierten Mails in allen Spielarten (kodierte Betreffs, Literale, quoted, NIL, multipart, HTML)
const b64 = (s, enc = "utf8") => Buffer.from(s, enc).toString("base64");
const MAILS = [
  {
    uid: 3,
    flagged: true,
    date: " 1-Oct-2026 08:00:00 +0200",
    header: "Subject: =?UTF-8?B?UmVjaG51bmcgZsO8ciBNw6Ry?=\r\n =?UTF-8?Q?z_=F0=9F=92=B6?=\r\nFrom: =?ISO-8859-1?Q?J=FCrgen_M=FCller?= <juergen@example.de>\r\nDate: Thu, 01 Oct 2026 08:00:00 +0200\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n",
    body: "Hallo Papa,\r\nanbei die Rechnung f=C3=BCr M=C3=A4rz. Viele Gr=C3=BC=C3=9Fe=\r\n, J=C3=BCrgen\r\n\r\n> alte Nachricht\r\n",
  },
  {
    uid: 7,
    flagged: true,
    date: "05-Oct-2026 17:30:00 +0000",
    header: Buffer.from('Subject: =?windows-1252?Q?Angebot_=80_100_f=FCr_Sie?=\r\nFrom: "Müller, Anna" <anna@firma.de>\r\nContent-Type: multipart/alternative; boundary="b1"\r\n\r\n', "utf8"),
    // Text-Teil: Base64 in Windows-1252 (als ISO-8859-1 deklariert, € = 0x80) – steht absichtlich nach dem HTML-Teil
    body: `--b1\r\nContent-Type: text/html; charset=utf-8\r\n\r\n<p>HTML-Version</p>\r\n--b1\r\nContent-Type: text/plain; charset=iso-8859-1\r\nContent-Transfer-Encoding: base64\r\n\r\n${Buffer.concat([Buffer.from("Guten Tag, hier das Angebot \xfcber 100 ", "latin1"), Buffer.from([0x80]), Buffer.from(".")]).toString("base64")}\r\n--b1--\r\n`,
  },
  {
    uid: 9,
    flagged: true,
    date: "03-Oct-2026 12:00:00 +0200",
    header: Buffer.from("Subject: Übergabe Büro\r\nFrom: Chef <chef@firma.de>\r\nContent-Type: text/plain\r\n\r\n", "utf8"),
    body: `Liebe Kollegen, ${"bitte alles für die Übergabe vorbereiten. ".repeat(80)}`,
  },
  {
    uid: 12,
    flagged: true,
    reversed: true,
    date: "06-Oct-2026 09:15:00 +0200",
    header: `Subject: =?UTF-8?B?${b64(Buffer.from([0x47, 0x72, 0xc3]))}?= =?UTF-8?B?${b64(Buffer.from([0xbc, 0xc3, 0x9f, 0x65]))}?= aus Berlin\r\nFrom: Anna Schmidt <anna@example.org>\r\nContent-Type: text/html; charset=utf-8\r\n\r\n`,
    body: "<html><head><style>p{color:red}</style><title>Titel</title></head><body><p>Termin&nbsp;am <b>Freitag</b> &amp; Samstag &#8211; bitte best&auml;tigen</p><!-- Kommentar --></body></html>",
  },
  { uid: 15, flagged: true, date: "06-Oct-2026 10:00:00 +0200", header: "Subject: Nur kurz", headerQuoted: true, body: null },
  { uid: 20, flagged: false, date: "06-Oct-2026 11:00:00 +0200", header: "Subject: Nicht markiert\r\n\r\n", body: "egal" },
];
let web;
let imap;
let silentImap;
let main; // ohne Ausnahmen: SSRF-Schutz greift, PUBLIC_URL gesetzt
let open; // TASCHEN_FEEDS_ALLOW_PRIVATE=1 – lokale Kalender erlaubt
let mail; // IMAP gegen den Mock (Klartext, interne Adressen erlaubt)

before(async () => {
  web = await mockWeb();
  imap = await mockImap();
  imap.messages = MAILS;
  imap.chunk = 7;
  imap.users = { "papa@gmx.de": 'ge"heim\\pw', "papa@web.de": "Grüße-2026!", "papa@icloud.com": "abcd-efgh-ijkl-mnop" };
  silentImap = await mockImap();
  silentImap.silent = true;
  main = await boot("main", { PUBLIC_URL: "https://taschen.example", TASCHEN_RATE_FEEDS: "1000" });
  open = await boot("open", { TASCHEN_FEEDS_ALLOW_PRIVATE: "1", TASCHEN_RATE_FEEDS: "1000" });
  mail = await boot("mail", { TASCHEN_IMAP_ALLOW_PRIVATE: "1", TASCHEN_IMAP_ALLOW_PLAIN: "1", TASCHEN_IMAP_CACHE_MS: "0", TASCHEN_RATE_IMAP: "1000" });
});

after(async () => {
  for (const s of servers) await s.close().catch(() => {});
  for (const m of [web, imap, silentImap]) {
    if (!m) continue;
    for (const s of m.sockets || []) s.destroy();
    m.srv.closeAllConnections?.();
    await new Promise((r) => m.srv.close(r));
  }
  fs.rmSync(TMP, { recursive: true, force: true });
});

const feed = (s, url, headers) => call(s.base, "POST", "/api/feeds/fetch", { json: { url }, headers });

// ---------- Gesundheit ----------
test("health meldet feeds, imap und inbox", async () => {
  const h = await call(main.base, "GET", "/api/health");
  assert.equal(h.status, 200);
  assert.equal(h.data.feeds, true);
  assert.equal(h.data.imap, true);
  assert.equal(h.data.inbox, true);
});

// ---------- SSRF-Schutz (reine Funktionen) ----------
test("blockedIp: privat, Loopback, Link-local, CGNAT, Multicast, ULA, IPv4-mapped gesperrt – öffentlich frei", () => {
  const blocked = ["127.0.0.1", "127.255.255.254", "0.0.0.0", "10.1.2.3", "100.64.0.1", "100.127.255.255", "169.254.169.254", "172.16.0.1", "172.31.255.255", "192.168.1.1", "192.0.2.5", "198.18.0.1", "224.0.0.1", "239.255.255.250", "255.255.255.255", "::", "::1", "::ffff:127.0.0.1", "::ffff:8.8.8.8", "::ffff:7f00:1", "fc00::1", "fd12:3456::1", "fe80::1", "fe80::1%eth0", "ff02::1", "2001:db8::1", "64:ff9b::a00:1", "2002:c0a8:0101::1", "kein-ip", ""];
  for (const ip of blocked) assert.equal(blockedIp(ip), true, ip);
  const open_ = ["8.8.8.8", "1.1.1.1", "100.63.255.255", "100.128.0.1", "172.15.255.255", "172.32.0.1", "192.169.0.1", "2606:4700:4700::1111", "2a00:1450:4001:80b::200e", "64:ff9b::808:808", "2002:0808:0808::1"];
  for (const ip of open_) assert.equal(blockedIp(ip), false, ip);
  assert.equal(allowList(""), null);
  assert.equal(allowList("0"), null);
  assert.equal(allowList("1"), true);
  assert.deepEqual([...allowList("127.0.0.1, [::1]")], ["127.0.0.1", "::1"]);
});

test("feedUrl: webcal:// → https://, nur http(s), keine Zugangsdaten, nur Port 80/443", () => {
  assert.equal(feedUrl("webcal://p52-caldav.icloud.com/published/2/abc").href, "https://p52-caldav.icloud.com/published/2/abc");
  assert.equal(feedUrl("WEBCALS://kalender.example/x.ics#frag").href, "https://kalender.example/x.ics");
  assert.equal(feedUrl("  https://calendar.google.com/calendar/ical/x%40group/private-1/basic.ics ").hostname, "calendar.google.com");
  assert.equal(feedUrl("https://kalender.example:443/a.ics").port, "");
  assert.equal(feedUrl("http://kalender.example:80/a.ics").port, "");
  assert.equal(feedUrl("http://kalender.example:443/a.ics").port, "443");
  for (const [bad, re] of [
    ["", /Kalender-Link/],
    ["kein link", /gültiger Link/],
    ["ftp://kalender.example/a.ics", /Nur Links/],
    ["file:///etc/passwd", /Nur Links/],
    ["javascript:alert(1)", /Nur Links/],
    ["https://user:pw@kalender.example/a.ics", /Benutzername/],
    ["https://kalender.example:8443/a.ics", /Port/],
    ["http://kalender.example:22/", /Port/],
  ]) {
    assert.throws(() => feedUrl(bad), (e) => e.status === 400 && re.test(e.message), bad);
  }
  assert.equal(feedUrl("http://127.0.0.1:8080/a.ics", { anyPort: true }).port, "8080");
});

// ---------- Kalender-Abo-Proxy ----------
test("feeds/fetch: lädt ICS (auch nach Weiterleitungen, gzip/br, BOM, Windows-1252) und cacht 10 Minuten", async () => {
  const r = await feed(open, `${web.base}/cal.ics?n=1`);
  assert.equal(r.status, 200, r.text);
  assert.equal(r.data.ok, true);
  assert.equal(r.data.ics, ICS);
  assert.equal(r.data.cached, false);
  assert.ok(Math.abs(r.data.fetched - Date.now()) < 5000);
  const hit = web.hits.find((h) => h.search === "?n=1");
  assert.match(hit.headers["user-agent"], /^Arbeitstaschen\//);
  assert.match(hit.headers.accept, /text\/calendar/);
  // Zweiter Abruf aus dem Cache – der Kalender-Server wird nicht noch einmal gefragt
  const before = web.hits.length;
  const again = await feed(open, `${web.base}/cal.ics?n=1`);
  assert.equal(again.data.cached, true);
  assert.equal(again.data.fetched, r.data.fetched);
  assert.equal(web.hits.length, before);
  // Weiterleitungen (relativ und absolut)
  assert.equal((await feed(open, `${web.base}/redirect`)).data.ics, ICS);
  assert.equal((await feed(open, `${web.base}/redirect-abs`)).data.ics, ICS);
  assert.ok(web.hits.some((h) => h.path === "/cal.ics" && h.search === "?abs=1"));
  // Komprimiert, mit BOM, Windows-1252
  assert.equal((await feed(open, `${web.base}/gzip.ics`)).data.ics, ICS);
  assert.equal((await feed(open, `${web.base}/br.ics`)).data.ics, ICS);
  const bom = await feed(open, `${web.base}/bom.ics`);
  assert.ok(bom.data.ics.startsWith("BEGIN:VCALENDAR"));
  assert.match(bom.data.ics, /Grüße mit BOM/);
  assert.match((await feed(open, `${web.base}/latin.ics`)).data.ics, /SUMMARY:Grün €/);
});

test("feeds/fetch: kein VCALENDAR, Fehlerstatus, zu viele Weiterleitungen → verständliche Fehler", async () => {
  const html = await feed(open, `${web.base}/html`);
  assert.equal(html.status, 422);
  assert.equal(html.data.ok, false);
  assert.match(html.data.msg, /Webseite statt zu einem Kalender/);
  const text = await feed(open, `${web.base}/text`);
  assert.equal(text.status, 422);
  assert.match(text.data.msg, /kein Kalender im iCal-Format/);
  assert.match((await feed(open, `${web.base}/missing`)).data.msg, /keinen Kalender \(mehr\)/);
  assert.match((await feed(open, `${web.base}/forbidden`)).data.msg, /verweigert den Zugriff/);
  const before = web.hits.filter((h) => h.path === "/loop").length;
  const loop = await feed(open, `${web.base}/loop`);
  assert.equal(loop.status, 502);
  assert.match(loop.data.msg, /zu oft weiter/);
  assert.equal(web.hits.filter((h) => h.path === "/loop").length - before, 4, "Start + 3 Weiterleitungen");
  assert.match((await feed(open, `${web.base}/to?to=${encodeURIComponent("ftp://example.com/x.ics")}`)).data.msg, /nicht erlaubte Adresse/);
  // Weiterleitung bzw. Fehlerseite mit endlosem Körper: Abbruch ohne Absturz
  assert.equal((await feed(open, `${web.base}/redirect-stream`)).data.ics, ICS);
  const es = await feed(open, `${web.base}/error-stream`);
  assert.equal(es.status, 502);
  assert.match(es.data.msg, /Fehler gemeldet \(500\)/);
  assert.equal((await call(open.base, "GET", "/api/health")).status, 200, "Server läuft weiter");
  // Fehler werden nicht gecacht
  assert.equal((await feed(open, `${web.base}/html`)).status, 422);
  // Nur die App darf den Proxy nutzen (Herkunftsprüfung wie üblich)
  assert.equal((await feed(open, `${web.base}/cal.ics`, { Origin: "https://evil.example" })).status, 403);
  const cors = await feed(open, `${web.base}/cal.ics`, { Origin: GH });
  assert.equal(cors.status, 200);
  assert.equal(cors.headers.get("access-control-allow-origin"), GH);
  // Ungültige Anfragen
  assert.equal((await call(open.base, "POST", "/api/feeds/fetch", { json: {} })).status, 400);
  assert.equal((await call(open.base, "POST", "/api/feeds/fetch", { body: "url=x", headers: { "Content-Type": "application/x-www-form-urlencoded" } })).status, 415);
  assert.equal((await call(open.base, "GET", "/api/feeds/fetch")).status, 405);
});

test("feeds/fetch: Größenlimit 5 MB (Content-Length, gestreamt, entpackt) und Zeitlimit", async () => {
  const big = await feed(open, `${web.base}/big`);
  assert.equal(big.status, 502);
  assert.match(big.data.msg, /zu groß \(mehr als 5 MB\)/);
  const chunked = await feed(open, `${web.base}/chunked?n=${5 * MB + 100 * 1024}`);
  assert.equal(chunked.status, 502);
  assert.match(chunked.data.msg, /zu groß/);
  const bomb = await feed(open, `${web.base}/bomb.ics`);
  assert.equal(bomb.status, 502, "6 MB nach dem Entpacken");
  assert.match(bomb.data.msg, /zu groß/);
  // Knapp unter dem Limit geht
  const fits = await feed(open, `${web.base}/chunked?n=${4 * MB}`);
  assert.equal(fits.status, 200);
  assert.equal(fits.data.ics.length, 4 * MB);

  const small = await boot("feeds-small", { TASCHEN_FEEDS_ALLOW_PRIVATE: "1", TASCHEN_FEEDS_MAX: String(64 * 1024), TASCHEN_FEEDS_TIMEOUT: "400", TASCHEN_RATE_FEEDS: "4" });
  const s1 = await feed(small, `${web.base}/chunked?n=${100 * 1024}`);
  assert.equal(s1.status, 502);
  assert.match(s1.data.msg, /mehr als 64 KB/);
  const t0 = Date.now();
  const slow = await feed(small, `${web.base}/slow`);
  assert.equal(slow.status, 504);
  assert.match(slow.data.msg, /Zeitüberschreitung/);
  assert.ok(Date.now() - t0 < 3000);
  // Ratenbegrenzung pro Adresse
  await feed(small, `${web.base}/cal.ics`);
  await feed(small, `${web.base}/cal.ics`);
  const limited = await feed(small, `${web.base}/cal.ics`);
  assert.equal(limited.status, 429);
  assert.ok(+limited.headers.get("retry-after") > 0);
});

test("feeds/fetch: SSRF – interne Adressen, fremde Ports und andere Protokolle werden ohne Verbindung abgelehnt", async () => {
  const internal = [
    "http://127.0.0.1/cal.ics",
    "http://localhost/cal.ics",
    "http://127.1/",
    "http://2130706433/",
    "http://0x7f000001/",
    "http://0.0.0.0/",
    "http://10.0.0.1/kalender.ics",
    "http://172.20.1.1/",
    "http://192.168.178.1/",
    "http://169.254.169.254/latest/meta-data/",
    "http://100.64.1.1/",
    "http://224.0.0.251/",
    "http://[::1]/",
    "http://[::]/",
    "http://[fd12:3456::1]/",
    "http://[fe80::1]/",
    "http://[::ffff:127.0.0.1]/",
    "http://[::ffff:a00:1]/",
    "webcal://192.168.0.10/kalender.ics",
    "https://10.0.0.1:443/a.ics",
  ];
  for (const url of internal) {
    const r = await feed(main, url);
    assert.equal(r.status, 400, url);
    assert.match(r.data.msg, /interne Adresse/, url);
  }
  // Fremde Ports – auch der lokale Kalender-Server ist ohne Ausnahme nicht erreichbar
  const port = await feed(main, `${web.base}/cal.ics`);
  assert.equal(port.status, 400);
  assert.match(port.data.msg, /Port/);
  assert.match((await feed(main, "https://kalender.example:8443/a.ics")).data.msg, /Port/);
  assert.match((await feed(main, "file:///etc/passwd")).data.msg, /Nur Links/);
  assert.match((await feed(main, "gopher://kalender.example/")).data.msg, /Nur Links/);
  // Unbekannter Host
  const nx = await feed(main, "https://gibt-es-nicht.invalid/a.ics");
  assert.ok(nx.status === 502 || nx.status === 504, String(nx.status));
  assert.match(nx.data.msg, /gibt es nicht|Zeitüberschreitung/);
});

test("feeds/fetch: SSRF auch nach Weiterleitungen (jede Station wird neu geprüft)", async () => {
  // Nur 127.0.0.1 ist (zum Testen) erlaubt – Weiterleitungen auf andere interne Ziele müssen scheitern
  const s = await boot("feeds-list", { TASCHEN_FEEDS_ALLOW_PRIVATE: "127.0.0.1", TASCHEN_RATE_FEEDS: "1000" });
  assert.equal((await feed(s, `${web.base}/cal.ics`)).status, 200, "erlaubte Adresse");
  assert.equal((await feed(s, `${web.base}/to?to=${encodeURIComponent("/cal.ics?via=to")}`)).status, 200, "Weiterleitung auf dieselbe Adresse");
  for (const to of ["http://10.0.0.1/x.ics", "http://169.254.169.254/latest/meta-data/", `http://[::1]:${web.port}/cal.ics`, "http://192.168.1.1/", "http://[fd00::1]/"]) {
    const r = await feed(s, `${web.base}/to?to=${encodeURIComponent(to)}`);
    assert.equal(r.status, 400, to);
    assert.match(r.data.msg, /interne Adresse/, to);
  }
  assert.equal((await feed(s, `http://[::1]:${web.port}/cal.ics`)).status, 400, "::1 steht nicht auf der Liste");
});

test("feeds/fetch: webcal:// wird über https:// geladen", async () => {
  // Roher TCP-Server: das erste Byte eines TLS-ClientHello ist 0x16 (Handshake) – bei http käme „G“ von „GET“
  const seen = [];
  const tcp = net.createServer((s) => {
    s.once("data", (c) => {
      seen.push(c[0]);
      s.destroy();
    });
    s.on("error", () => {});
  });
  await new Promise((r) => tcp.listen(0, "127.0.0.1", r));
  try {
    const r = await feed(open, `webcal://127.0.0.1:${tcp.address().port}/cal.ics`);
    assert.equal(r.status, 502);
    assert.equal(r.data.ok, false);
    assert.deepEqual(seen, [0x16], "TLS-Handshake statt Klartext");
    const plain = await feed(open, `http://127.0.0.1:${tcp.address().port}/cal.ics`);
    assert.equal(plain.status, 502);
    assert.equal(seen[1], "G".charCodeAt(0), "http bleibt http");
  } finally {
    await new Promise((r) => tcp.close(r));
  }
});

// ---------- IMAP: reine Funktionen ----------
test("RFC 2047, Kopfzeilen, Absender, Snippet und IMAP-Token", () => {
  assert.equal(decodeWords("=?UTF-8?B?UmVjaG51bmcgZsO8ciBNw6Ry?= =?UTF-8?Q?z_=F0=9F=92=B6?="), "Rechnung für März 💶");
  assert.equal(decodeWords("=?iso-8859-1?q?J=FCrgen?= und =?ISO-8859-15?Q?=A4uro?="), "Jürgen und €uro");
  assert.equal(decodeWords("=?windows-1252?Q?Angebot_=80_100?="), "Angebot € 100");
  assert.equal(decodeWords("=?UTF-8*de?Q?Gr=C3=BC=C3=9Fe?="), "Grüße");
  assert.equal(decodeWords("Re: =?utf-8?b?R3LDvMOfZQ==?= aus Köln"), "Re: Grüße aus Köln");
  assert.equal(decodeWords("Ganz normal"), "Ganz normal");
  assert.equal(decodeText(Buffer.from([0x47, 0x72, 0xfc, 0x6e]), "utf-8"), "Grün", "falsch deklariert → Windows-1252");
  assert.equal(decodeText(Buffer.from("Grü", "utf8").subarray(0, 3), "utf-8"), "Gr", "abgeschnittenes Zeichen am Ende");
  assert.deepEqual(parseHeaders("Subject: Hallo\r\n Welt\r\nFROM: a@b.de\r\nSubject: zweiter\r\n\r\n"), { subject: "Hallo Welt", from: "a@b.de" });
  assert.deepEqual(parseFrom('"Müller, Anna" <anna@firma.de>'), { name: "Müller, Anna", email: "anna@firma.de" });
  assert.deepEqual(parseFrom("=?utf-8?Q?J=C3=BCrgen?= <j@x.de>"), { name: "Jürgen", email: "j@x.de" });
  assert.deepEqual(parseFrom("j@x.de (Jürgen)"), { name: "Jürgen", email: "j@x.de" });
  assert.deepEqual(parseFrom("j@x.de"), { name: "j@x.de", email: "j@x.de" });
  assert.deepEqual(parseFrom(""), { name: "", email: "" });
  assert.equal(htmlToText("<p>A&amp;B</p><br>C &#x20AC; &euro; &uuml;"), " A&B\n\nC € € ü");
  assert.equal(mailSnippet({ "content-type": "text/plain", "content-transfer-encoding": "quoted-printable" }, Buffer.from("Gr=C3=BC=C3=9Fe=\r\n aus Berlin=")), "Grüße aus Berlin");
  assert.equal(mailSnippet({ "content-type": "text/plain", "content-transfer-encoding": "base64" }, Buffer.from(`${b64("Hallo Welt, wie geht's?")}\r\n`)), "Hallo Welt, wie geht's?");
  assert.equal(mailSnippet({}, Buffer.from("--xyz\r\nContent-Type: text/plain\r\n\r\nOhne Kopf erkannt\r\n--xyz--")), "Ohne Kopf erkannt");
  assert.equal(mailSnippet({ "content-type": "image/png" }, Buffer.from("PNG")), "");
  assert.equal(mailSnippet({ "content-type": 'multipart/mixed; boundary="a"' }, Buffer.from('--a\r\nContent-Type: multipart/alternative; boundary="b"\r\n\r\n--b\r\nContent-Type: text/html\r\n\r\n<b>fett</b>\r\n--b\r\nContent-Type: text/plain\r\n\r\nverschachtelt\r\n--b--\r\n--a--')), "verschachtelt");
  const long = mailSnippet({}, Buffer.from("x".repeat(500)));
  assert.equal(Array.from(long).length, 200);
  assert.ok(long.endsWith("…"));
  assert.equal(imapString("papa@gmx.de"), '"papa@gmx.de"');
  assert.equal(imapString('a"b\\c'), '"a\\"b\\\\c"');
  assert.deepEqual(imapString("Grüße"), { literal: Buffer.from("Grüße", "utf8") });
  assert.deepEqual(imapString("tab\there"), { literal: Buffer.from("tab\there") });
  const t = imapTokens(['* 2 FETCH (UID 12 FLAGS (\\Seen \\Flagged) BODY[HEADER.FIELDS (SUBJECT FROM)] {5}', Buffer.from("Hallo"), ' BODY[TEXT]<0> NIL INTERNALDATE "06-Oct-2026 09:15:00 +0200")']);
  assert.deepEqual(t.slice(0, 3), ["*", "2", "FETCH"]);
  const l = t[3];
  assert.deepEqual(l.slice(0, 4), ["UID", "12", "FLAGS", ["\\Seen", "\\Flagged"]]);
  assert.equal(l[4], "BODY[HEADER.FIELDS (SUBJECT FROM)]");
  assert.equal(l[5].toString(), "Hallo");
  assert.equal(l[6], "BODY[TEXT]<0>");
  assert.equal(l[7], null);
  assert.equal(imapDate(l[9].toString()), Date.UTC(2026, 9, 6, 7, 15));
  assert.equal(imapDate(" 1-Jan-2026 00:00:00 -0100"), Date.UTC(2026, 0, 1, 1, 0));
  assert.equal(imapDate("kaputt"), null);
  assert.equal(mailProvider("imap.gmx.net"), "GMX");
  assert.equal(mailProvider("127.0.0.1", "x@web.de"), "WEB.DE");
  assert.equal(mailProvider("imap.mail.me.com"), "iCloud");
  assert.match(imapLoginHelp("imap.gmx.net", "p@gmx.de"), /GMX musst du IMAP erst in den Einstellungen erlauben/);
  assert.match(imapLoginHelp("imap.mail.me.com", "p@icloud.com"), /app-spezifisches Passwort/);
  assert.match(imapLoginHelp("imap.mail.yahoo.com", "p@yahoo.de"), /app-spezifisches Passwort/);
  assert.match(imapLoginHelp("outlook.office365.com", "p@outlook.de"), /über „Microsoft“/);
  assert.match(imapLoginHelp("imap.example.org", "p@example.org"), /GMX\/WEB\.DE.*iCloud/);
});

// ---------- IMAP gegen den Mock ----------
const imapAdd = (s, body) => call(s.base, "POST", "/api/imap/add", { json: { host: "127.0.0.1", port: imap.port, ...body } });
const flagged = (s, account, secret, limit) => call(s.base, "POST", "/api/imap/flagged", { json: { account, secret, ...(limit ? { limit } : {}) } });

test("imap/add: LOGIN mit korrektem Quoting, Zugangsdaten nur verschlüsselt gespeichert", async () => {
  const r = await imapAdd(mail, { user: "papa@gmx.de", password: 'ge"heim\\pw', label: "GMX" });
  assert.equal(r.status, 200, r.text);
  assert.equal(r.data.ok, true);
  assert.match(r.data.account, /^[0-9a-f]{32}$/);
  assert.match(r.data.secret, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(r.data.email, "papa@gmx.de");
  assert.equal(r.data.label, "GMX");
  const login = imap.logins.at(-1);
  assert.equal(login.user, "papa@gmx.de");
  assert.equal(login.pass, 'ge"heim\\pw');
  assert.ok(login.segs[0].includes('LOGIN "papa@gmx.de" "ge\\"heim\\\\pw"'), login.segs[0]);
  assert.ok(imap.commands.some((c) => c.name === "LOGOUT"), "sauber abgemeldet");

  // Speicherung: verschlüsselt, Secret nur als Hash
  const file = path.join(dataDir("mail"), "imap.json");
  const text = fs.readFileSync(file, "utf8");
  assert.ok(!text.includes("heim"), "kein Klartext-Passwort");
  assert.ok(!text.includes("papa@gmx.de"), "kein Klartext-Benutzername");
  assert.ok(!text.includes(r.data.secret), "kein Klartext-Secret");
  const acc = JSON.parse(text).accounts[r.data.account];
  assert.equal(acc.secretHash, sha(r.data.secret));
  assert.equal(acc.host, "127.0.0.1");
  assert.equal(acc.port, imap.port);
  assert.match(acc.credEnc, /^v1\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/);
  assert.deepEqual(JSON.parse(openToken(keyOf("mail"), acc.credEnc, `taschen-imap:${acc.id}:${acc.host}:${acc.port}`)), { user: "papa@gmx.de", password: 'ge"heim\\pw' });
  if (process.platform !== "win32") assert.equal(fs.statSync(file).mode & 0o077, 0);

  // Nicht-ASCII-Passwort → synchronisierendes Literal ({n}, „+“ abwarten)
  const lit = await imapAdd(mail, { user: "papa@web.de", password: "Grüße-2026!" });
  assert.equal(lit.status, 200, lit.text);
  assert.equal(lit.data.label, "WEB.DE", "Anbieter aus der Adresse erkannt");
  const l2 = imap.logins.at(-1);
  assert.equal(l2.pass, "Grüße-2026!");
  assert.ok(l2.segs.some((x) => Buffer.isBuffer(x) && x.equals(Buffer.from("Grüße-2026!"))), "Passwort als Literal");
  assert.match(l2.segs[0], /LOGIN "papa@web\.de" $/);

  // Dasselbe Postfach noch einmal → ersetzt den alten Eintrag
  const again = await imapAdd(mail, { user: "papa@web.de", password: "Grüße-2026!" });
  const accounts = JSON.parse(fs.readFileSync(file, "utf8")).accounts;
  assert.ok(accounts[again.data.account]);
  assert.equal(accounts[lit.data.account], undefined);
});

test("imap/add: abgelehnte Anmeldung → Hinweise für GMX/WEB.DE bzw. app-spezifisches Passwort, nichts gespeichert", async () => {
  const before = Object.keys(JSON.parse(fs.readFileSync(path.join(dataDir("mail"), "imap.json"), "utf8")).accounts).length;
  const gmx = await imapAdd(mail, { user: "papa@gmx.de", password: "falsch" });
  assert.equal(gmx.status, 401);
  assert.equal(gmx.data.ok, false);
  assert.match(gmx.data.msg, /^Anmeldung fehlgeschlagen/);
  assert.match(gmx.data.msg, /GMX musst du IMAP erst in den Einstellungen erlauben/);
  const icloud = await imapAdd(mail, { user: "papa@icloud.com", password: "mein-apple-passwort" });
  assert.equal(icloud.status, 401);
  assert.match(icloud.data.msg, /app-spezifisches Passwort/);
  const other = await imapAdd(mail, { user: "papa@example.org", password: "x" });
  assert.match(other.data.msg, /GMX\/WEB\.DE musst du IMAP erst in den Einstellungen erlauben; bei iCloud und Yahoo brauchst du ein app-spezifisches Passwort/);
  const after_ = Object.keys(JSON.parse(fs.readFileSync(path.join(dataDir("mail"), "imap.json"), "utf8")).accounts).length;
  assert.equal(after_, before);
  // Ungültige Eingaben
  for (const [body, re] of [
    [{ host: "", user: "a", password: "b" }, /IMAP-Server/],
    [{ host: "imap gmx", user: "a", password: "b" }, /IMAP-Server/],
    [{ user: "", password: "b" }, /E-Mail-Adresse/],
    [{ user: "a", password: "" }, /Passwort/],
    [{ user: "a", password: "x\r\ny" }, /Passwort/],
    [{ port: 70000, user: "a", password: "b" }, /Port/],
  ]) {
    const r = await imapAdd(mail, body);
    assert.equal(r.status, 400, JSON.stringify(body));
    assert.match(r.data.msg, re);
  }
});

test("imap/flagged: markierte Mails, neueste zuerst – kodierte Betreffs, Literale, quoted, NIL, multipart, HTML", async () => {
  const a = await imapAdd(mail, { user: "papa@icloud.com", password: "abcd-efgh-ijkl-mnop", label: "iCloud" });
  assert.equal(a.status, 200, a.text);
  const r = await flagged(mail, a.data.account, a.data.secret);
  assert.equal(r.status, 200, r.text);
  assert.equal(r.data.ok, true);
  const mails = r.data.mails;
  assert.deepEqual(
    mails.map((m) => m.uid),
    [15, 12, 7, 9, 3],
    "nach Datum, ohne die nicht markierte Mail",
  );
  const by = Object.fromEntries(mails.map((m) => [m.uid, m]));
  assert.deepEqual(by[3], { uid: 3, subject: "Rechnung für März 💶", from: "Jürgen Müller", fromEmail: "juergen@example.de", date: Date.UTC(2026, 9, 1, 6, 0), snippet: "Hallo Papa, anbei die Rechnung für März. Viele Grüße, Jürgen" });
  assert.deepEqual(by[7], { uid: 7, subject: "Angebot € 100 für Sie", from: "Müller, Anna", fromEmail: "anna@firma.de", date: Date.UTC(2026, 9, 5, 17, 30), snippet: "Guten Tag, hier das Angebot über 100 €." });
  assert.equal(by[9].subject, "Übergabe Büro", "8-Bit-Kopfzeile (UTF-8)");
  assert.equal(by[9].from, "Chef");
  assert.equal(Array.from(by[9].snippet).length, 200);
  assert.ok(by[9].snippet.startsWith("Liebe Kollegen, bitte alles für die Übergabe vorbereiten."));
  assert.ok(by[9].snippet.endsWith("…"));
  assert.deepEqual(by[12], { uid: 12, subject: "Grüße aus Berlin", from: "Anna Schmidt", fromEmail: "anna@example.org", date: Date.UTC(2026, 9, 6, 7, 15), snippet: "Termin am Freitag & Samstag – bitte bestätigen" });
  assert.deepEqual(by[15], { uid: 15, subject: "Nur kurz", from: "", fromEmail: "", date: Date.UTC(2026, 9, 6, 8, 0), snippet: "" });

  // Befehle: nur lesend, die richtigen Teile, sauber abgemeldet
  const names = imap.commands.slice(-5).map((c) => c.name + (c.name === "UID" ? ` ${c.args[0].toUpperCase()}` : ""));
  assert.deepEqual(names, ["LOGIN", "EXAMINE", "UID SEARCH", "UID FETCH", "LOGOUT"]);
  const fetchCmd = imap.commands.findLast((c) => c.name === "UID" && /FETCH/i.test(c.args[0]));
  assert.match(fetchCmd.text, /UID FETCH 15,12,9,7,3 \(UID INTERNALDATE BODY\.PEEK\[HEADER\.FIELDS \(SUBJECT FROM DATE CONTENT-TYPE CONTENT-TRANSFER-ENCODING\)\] BODY\.PEEK\[TEXT\]<0\.2000>\)/);
  assert.ok(imap.commands.findLast((c) => c.name === "UID" && /SEARCH/i.test(c.args[0])).text.endsWith("UID SEARCH FLAGGED"));

  // limit: die neuesten UIDs
  const two = await flagged(mail, a.data.account, a.data.secret, 2);
  assert.deepEqual(
    two.data.mails.map((m) => m.uid),
    [15, 12],
  );
  assert.match(imap.commands.findLast((c) => c.name === "UID" && /FETCH/i.test(c.args[0])).text, /UID FETCH 15,12 /);

  // Leeres Postfach
  const saved = imap.messages;
  imap.messages = [];
  assert.deepEqual((await flagged(mail, a.data.account, a.data.secret)).data, { ok: true, mails: [] });
  imap.messages = saved;

  // Passwort inzwischen geändert → 401 mit Bitte um neue Verbindung
  imap.users["papa@icloud.com"] = "neu";
  const broken = await flagged(mail, a.data.account, a.data.secret);
  assert.equal(broken.status, 401);
  assert.match(broken.data.msg, /iCloud klappt nicht mehr.*neu verbinden/);
  imap.users["papa@icloud.com"] = "abcd-efgh-ijkl-mnop";
});

test("imap/flagged + remove: falsches Secret, unbekanntes Konto, Löschen", async () => {
  const a = await imapAdd(mail, { user: "papa@gmx.de", password: 'ge"heim\\pw' });
  assert.equal((await flagged(mail, a.data.account, "A".repeat(43))).status, 403);
  assert.equal((await flagged(mail, crypto.randomBytes(16).toString("hex"), a.data.secret)).status, 410);
  assert.equal((await flagged(mail, "kaputt", a.data.secret)).status, 400);
  const rm = (account, secret) => call(mail.base, "POST", "/api/imap/remove", { json: { account, secret } });
  assert.equal((await rm(a.data.account, "A".repeat(43))).status, 403);
  assert.deepEqual((await rm(a.data.account, a.data.secret)).data, { ok: true, removed: true });
  assert.equal((await flagged(mail, a.data.account, a.data.secret)).status, 410);
  assert.deepEqual((await rm(a.data.account, a.data.secret)).data, { ok: true, removed: false });
  assert.equal(JSON.parse(fs.readFileSync(path.join(dataDir("mail"), "imap.json"), "utf8")).accounts[a.data.account], undefined);
  assert.equal((await call(mail.base, "GET", "/api/imap/flagged")).status, 405);
  // Herkunftsprüfung wie üblich
  assert.equal((await call(mail.base, "POST", "/api/imap/add", { json: { host: "127.0.0.1", port: imap.port, user: "papa@gmx.de", password: "x" }, headers: { Origin: "https://evil.example" } })).status, 403);
});

test("imap: Ergebnis wird kurz gecacht (schont den Mailserver)", async () => {
  const s = await boot("mail-cache", { TASCHEN_IMAP_ALLOW_PRIVATE: "1", TASCHEN_IMAP_ALLOW_PLAIN: "1", TASCHEN_RATE_IMAP: "1000" });
  const a = await imapAdd(s, { user: "papa@gmx.de", password: 'ge"heim\\pw' });
  const n = imap.sessions;
  const r1 = await flagged(s, a.data.account, a.data.secret, 3);
  const r2 = await flagged(s, a.data.account, a.data.secret, 2);
  assert.equal(imap.sessions - n, 1);
  assert.deepEqual(
    r2.data.mails.map((m) => m.uid),
    r1.data.mails.slice(0, 2).map((m) => m.uid),
  );
});

test("imap: SSRF-Schutz, nur Port 993 und Zeitlimit", async () => {
  for (const host of ["127.0.0.1", "localhost", "10.0.0.5", "192.168.178.1", "[::1]", "169.254.169.254"]) {
    const r = await call(main.base, "POST", "/api/imap/add", { json: { host, port: 993, user: "papa@gmx.de", password: "x" } });
    assert.equal(r.status, 400, host);
    assert.match(r.data.msg, /interne Adresse/, host);
  }
  const port = await call(main.base, "POST", "/api/imap/add", { json: { host: "imap.gmx.net", port: 143, user: "papa@gmx.de", password: "x" } });
  assert.equal(port.status, 400);
  assert.match(port.data.msg, /Port 993/);
  const t = await boot("mail-timeout", { TASCHEN_IMAP_ALLOW_PRIVATE: "1", TASCHEN_IMAP_ALLOW_PLAIN: "1", TASCHEN_IMAP_TIMEOUT: "300" });
  const t0 = Date.now();
  const slow = await call(t.base, "POST", "/api/imap/add", { json: { host: "127.0.0.1", port: silentImap.port, user: "papa@gmx.de", password: "x" } });
  assert.equal(slow.status, 504);
  assert.match(slow.data.msg, /Zeitüberschreitung/);
  assert.ok(Date.now() - t0 < 3000);
  // Nichts lauscht → nicht erreichbar
  const closed = await new Promise((resolve) => {
    const srv = net.createServer();
    srv.listen(0, "127.0.0.1", () => {
      const p = srv.address().port;
      srv.close(() => resolve(p));
    });
  });
  const refused = await call(t.base, "POST", "/api/imap/add", { json: { host: "127.0.0.1", port: closed, user: "papa@gmx.de", password: "x" } });
  assert.equal(refused.status, 502);
  assert.match(refused.data.msg, /nicht erreichbar/);
});

// ---------- Webhook-Eingang ----------
const create = (s, headers) => call(s.base, "POST", "/api/inbox/create", { json: {}, headers });
const pull = (s, hook, key, headers) => call(s.base, "POST", "/api/inbox/pull", { json: { hook, key }, headers });
const inPath = (h) => new URL(h.url).pathname;

test("inbox/create: geheime Adresse mit PUBLIC_URL, Schlüssel nur als Hash, Einträge verschlüsselt", async () => {
  const h = await create(main);
  assert.equal(h.status, 200, h.text);
  assert.equal(h.data.ok, true);
  assert.match(h.data.hook, /^[0-9a-f]{32}$/);
  assert.match(h.data.key, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(h.data.url, `https://taschen.example/api/in/${h.data.hook}/${h.data.key}`);
  // Ohne PUBLIC_URL: Adresse der Anfrage
  const local = await create(open);
  assert.equal(local.data.url, `${open.base}/api/in/${local.data.hook}/${local.data.key}`);
  // Herkunftsprüfung wie üblich
  assert.equal((await create(main, { Origin: "https://evil.example" })).status, 403);
  assert.equal((await create(main, { Origin: GH })).headers.get("access-control-allow-origin"), GH);

  const r = await call(main.base, "POST", inPath(h.data), { json: { title: "Geheimer Titel 123", notes: "Vertraulich" } });
  assert.equal(r.status, 200);
  const file = path.join(dataDir("main"), "inbox", `${h.data.hook}.json`);
  const text = fs.readFileSync(file, "utf8");
  assert.ok(!text.includes("Geheimer Titel"), "Titel nicht im Klartext");
  assert.ok(!text.includes("Vertraulich"));
  assert.ok(!text.includes(h.data.key), "Schlüssel nicht im Klartext");
  const d = JSON.parse(text);
  assert.equal(d.keyHash, sha(h.data.key));
  assert.equal(d.items.length, 1);
  assert.match(d.items[0].box, /^v1\./);
  if (process.platform !== "win32") assert.equal(fs.statSync(file).mode & 0o077, 0);
});

test("/api/in: JSON, Formular, Text, multipart und GET ?text= – mit Herkunft (X-Source, ?source, User-Agent)", async () => {
  const h = (await create(main)).data;
  const p = inPath(h);
  const ok = async (r) => {
    assert.equal(r.status, 200, r.text);
    assert.equal(r.data.ok, true);
    assert.match(r.data.id, /^[0-9a-f]{16}$/);
    assert.equal(r.headers.get("access-control-allow-origin"), "*");
    return r.data.id;
  };
  const ids = [];
  ids.push(await ok(await call(main.base, "POST", p, { json: { title: "Angebot schicken", notes: "an Firma X", due: "2026-10-09", time: "9:30", bag: "Firma", prio: "hoch", url: "https://example.com/a" }, headers: { "X-Source": "Formular" } })));
  ids.push(await ok(await call(main.base, "POST", p, { body: "title=Milch+kaufen&project=Privat&due=morgen&prio=1", headers: { "Content-Type": "application/x-www-form-urlencoded", "User-Agent": "Zapier" } })));
  ids.push(await ok(await call(main.base, "POST", p, { body: "Rechnung prüfen\nBetrag 120 €\nbis Freitag", headers: { "Content-Type": "text/plain; charset=utf-8", "User-Agent": "Shortcuts/1146.1 CFNetwork/1490.0.4 Darwin/23.2.0" } })));
  ids.push(await ok(await call(main.base, "POST", p, { body: JSON.stringify({ name: "Aus no-cors", description: "als Text geschickt", tasche: "Haus" }), headers: { "Content-Type": "text/plain;charset=UTF-8", "User-Agent": "n8n" } })));
  const form = new FormData();
  form.set("title", "Kurzbefehl-Formular");
  form.set("notes", "Zeile 1\nZeile 2");
  ids.push(await ok(await call(main.base, "POST", p, { body: form, headers: { "User-Agent": "Make/production" } })));
  ids.push(await ok(await call(main.base, "GET", `${p}?text=${encodeURIComponent("Zahnarzt anrufen")}&due=Freitag&source=Lesezeichen`)));
  ids.push(await ok(await call(main.base, "POST", `${p}?source=Formular-Seite`, { json: { subject: "Von woanders" }, headers: { Origin: "https://evil.example", "User-Agent": "IFTTT-Protocol/v1" } })));
  ids.push(await ok(await call(main.base, "POST", p, { json: { text: "Nur Titel", priority: 2, link: "javascript:alert(1)" }, headers: { "User-Agent": "IFTTT-Protocol/v1" } })));
  ids.push(await ok(await call(main.base, "POST", p, { json: { title: "Neutral" }, headers: { "User-Agent": "curl/8.5.0" } })));

  const r = await pull(main, h.hook, h.key);
  assert.equal(r.status, 200, r.text);
  assert.equal(r.data.ok, true);
  const items = r.data.items;
  assert.deepEqual(
    items.map((x) => x.id),
    ids,
  );
  for (const it of items) {
    assert.deepEqual(Object.keys(it), ["id", "at", "title", "notes", "due", "time", "bag", "prio", "url", "source"]);
    assert.ok(Math.abs(it.at - Date.now()) < 10000);
  }
  assert.deepEqual(items[0], { id: ids[0], at: items[0].at, title: "Angebot schicken", notes: "an Firma X", due: "2026-10-09", time: "09:30", bag: "Firma", prio: 3, url: "https://example.com/a", source: "Formular" });
  assert.deepEqual({ ...items[1], id: 0, at: 0 }, { id: 0, at: 0, title: "Milch kaufen", notes: null, due: "morgen", time: null, bag: "Privat", prio: 1, url: null, source: "Zapier" });
  assert.deepEqual([items[2].title, items[2].notes, items[2].source], ["Rechnung prüfen", "Betrag 120 €\nbis Freitag", "Siri"]);
  assert.deepEqual([items[3].title, items[3].notes, items[3].bag, items[3].source], ["Aus no-cors", "als Text geschickt", "Haus", "n8n"]);
  assert.deepEqual([items[4].title, items[4].notes, items[4].source], ["Kurzbefehl-Formular", "Zeile 1\nZeile 2", "Make"]);
  assert.deepEqual([items[5].title, items[5].due, items[5].source], ["Zahnarzt anrufen", "Freitag", "Lesezeichen"]);
  assert.deepEqual([items[6].title, items[6].source], ["Von woanders", "Formular-Seite"]);
  assert.deepEqual([items[7].title, items[7].prio, items[7].url, items[7].source], ["Nur Titel", 2, null, "IFTTT"]);
  assert.equal(items[8].source, "Webhook");

  // ack löscht – nur die genannten
  const ack = await call(main.base, "POST", "/api/inbox/ack", { json: { hook: h.hook, key: h.key, ids: ids.slice(0, 7) } });
  assert.deepEqual(ack.data, { ok: true, removed: 7, left: 2 });
  assert.deepEqual(
    (await pull(main, h.hook, h.key)).data.items.map((x) => x.id),
    ids.slice(7),
  );
  assert.deepEqual((await call(main.base, "POST", "/api/inbox/ack", { json: { hook: h.hook, key: h.key, ids: ids.slice(7) } })).data, { ok: true, removed: 2, left: 0 });
  assert.deepEqual((await pull(main, h.hook, h.key)).data, { ok: true, items: [] });
});

test("/api/in: falscher Schlüssel 403, Fehler mit CORS *, OPTIONS, Formate und Pflichtfelder", async () => {
  const h = (await create(main)).data;
  const wrong = `/api/in/${h.hook}/${"A".repeat(43)}`;
  const w = await call(main.base, "POST", wrong, { json: { title: "x" } });
  assert.equal(w.status, 403);
  assert.match(w.data.msg, /ungültig/);
  assert.equal(w.headers.get("access-control-allow-origin"), "*");
  assert.equal((await call(main.base, "GET", `${wrong}?text=x`)).status, 403);
  assert.equal((await call(main.base, "POST", `/api/in/${crypto.randomBytes(16).toString("hex")}/${h.key}`, { json: { title: "x" } })).status, 403, "unbekannter Eingang");
  assert.equal((await call(main.base, "POST", "/api/in/abc/def", { json: { title: "x" } })).status, 403);
  assert.equal((await call(main.base, "POST", "/api/in/", { json: { title: "x" } })).status, 404);
  const put = await call(main.base, "PUT", inPath(h), { json: { title: "x" } });
  assert.equal(put.status, 405);
  assert.equal(put.headers.get("access-control-allow-origin"), "*");

  // Preflight von überall
  const pre = await raw(main.port, "OPTIONS", inPath(h), { headers: { Origin: "https://hook.eu1.make.com", "Access-Control-Request-Method": "POST", "Access-Control-Request-Headers": "content-type,x-source" } });
  assert.equal(pre.status, 204);
  assert.equal(pre.headers["access-control-allow-origin"], "*");
  assert.match(pre.headers["access-control-allow-methods"], /POST/);
  assert.match(pre.headers["access-control-allow-headers"], /Content-Type/);
  assert.match(pre.headers["access-control-allow-headers"], /X-Source/);
  // … aber CORS * gibt es NUR für /api/in
  const prePull = await raw(main.port, "OPTIONS", "/api/inbox/pull", { headers: { Origin: "https://evil.example", "Access-Control-Request-Method": "POST" } });
  assert.equal(prePull.status, 403);
  assert.equal(prePull.headers["access-control-allow-origin"], undefined);
  const pl = await pull(main, h.hook, h.key, { Origin: GH });
  assert.equal(pl.headers.get("access-control-allow-origin"), GH);
  assert.equal((await pull(main, h.hook, h.key, { Origin: "https://evil.example" })).status, 403);
  for (const r of [await call(main.base, "GET", "/api/health"), await feed(main, "http://10.0.0.1/"), await pull(main, h.hook, h.key)]) assert.notEqual(r.headers.get("access-control-allow-origin"), "*");

  // Pflichtfelder und Formate
  const noTitle = await call(main.base, "POST", inPath(h), { json: { notes: "ohne Titel" } });
  assert.equal(noTitle.status, 400);
  assert.match(noTitle.data.msg, /Titel fehlt/);
  assert.equal((await call(main.base, "GET", inPath(h))).status, 400);
  assert.equal((await call(main.base, "POST", inPath(h), { body: "{kaputt", headers: { "Content-Type": "application/json" } })).status, 400);
  assert.equal((await call(main.base, "POST", inPath(h), { body: "[1,2]", headers: { "Content-Type": "application/json" } })).status, 400);
  assert.equal((await call(main.base, "POST", inPath(h), { body: Buffer.from([1, 2, 3]), headers: { "Content-Type": "application/octet-stream" } })).status, 415);
  const big = await call(main.base, "POST", inPath(h), { body: "x".repeat(33 * 1024), headers: { "Content-Type": "text/plain" } });
  assert.equal(big.status, 413);
  assert.match(big.data.msg, /32 KB/);
  assert.equal(big.headers.get("access-control-allow-origin"), "*");
  // Lange Notizen werden gekürzt – jeder Eintrag bleibt unter 8 KB
  const long = await call(main.base, "POST", inPath(h), { json: { title: "T".repeat(500), notes: "ä".repeat(12000) } });
  assert.equal(long.status, 200);
  const it = (await pull(main, h.hook, h.key)).data.items.at(-1);
  assert.equal(it.title.length, 300);
  assert.ok(it.notes.length > 1000 && it.notes.length < 6000);
  assert.ok(Buffer.byteLength(JSON.stringify(it)) <= 8 * 1024);
  // pull/ack mit falschem Schlüssel bzw. unbekanntem Eingang
  assert.equal((await pull(main, h.hook, "B".repeat(43))).status, 403);
  assert.equal((await pull(main, crypto.randomBytes(16).toString("hex"), h.key)).status, 410);
  assert.equal((await pull(main, "kaputt", h.key)).status, 400);
  assert.equal((await call(main.base, "POST", "/api/inbox/ack", { json: { hook: h.hook, key: "B".repeat(43), ids: [it.id] } })).status, 403);
  assert.equal((await call(main.base, "GET", "/api/inbox/pull")).status, 405);
});

test("inbox/reset macht die alte Adresse ungültig, inbox/remove löscht den Eingang", async () => {
  const h = (await create(main)).data;
  assert.equal((await call(main.base, "POST", inPath(h), { json: { title: "Vor dem Zurücksetzen" } })).status, 200);
  const r = await call(main.base, "POST", "/api/inbox/reset", { json: { hook: h.hook, key: h.key } });
  assert.equal(r.status, 200, r.text);
  assert.equal(r.data.ok, true);
  assert.match(r.data.key, /^[A-Za-z0-9_-]{43}$/);
  assert.notEqual(r.data.key, h.key);
  assert.equal(r.data.url, `https://taschen.example/api/in/${h.hook}/${r.data.key}`);
  // Alte Adresse und alter Schlüssel gelten nicht mehr
  assert.equal((await call(main.base, "POST", inPath(h), { json: { title: "alt" } })).status, 403);
  assert.equal((await call(main.base, "GET", `${inPath(h)}?text=alt`)).status, 403);
  assert.equal((await pull(main, h.hook, h.key)).status, 403);
  // Neue Adresse geht, schon Eingegangenes bleibt erhalten
  assert.equal((await call(main.base, "POST", inPath(r.data), { json: { title: "Nach dem Zurücksetzen" } })).status, 200);
  assert.deepEqual(
    (await pull(main, h.hook, r.data.key)).data.items.map((x) => x.title),
    ["Vor dem Zurücksetzen", "Nach dem Zurücksetzen"],
  );
  // Löschen
  assert.equal((await call(main.base, "POST", "/api/inbox/remove", { json: { hook: h.hook, key: h.key } })).status, 403);
  assert.deepEqual((await call(main.base, "POST", "/api/inbox/remove", { json: { hook: h.hook, key: r.data.key } })).data, { ok: true, removed: true });
  assert.ok(!fs.existsSync(path.join(dataDir("main"), "inbox", `${h.hook}.json`)));
  assert.equal((await call(main.base, "POST", inPath(r.data), { json: { title: "weg" } })).status, 403);
  assert.equal((await pull(main, h.hook, r.data.key)).status, 410);
  assert.deepEqual((await call(main.base, "POST", "/api/inbox/remove", { json: { hook: h.hook, key: r.data.key } })).data, { ok: true, removed: false });
});

test("inbox: Grenzen – Einträge pro Eingang, Ratenbegrenzung pro Eingang, neue Eingänge pro Adresse", async () => {
  const s = await boot("inbox-limits", { TASCHEN_INBOX_ITEMS: "3", TASCHEN_RATE_INBOX: "5", TASCHEN_INBOX_NEW: "3" });
  const a = (await create(s)).data;
  for (let i = 0; i < 3; i++) assert.equal((await call(s.base, "POST", inPath(a), { json: { title: `Nr. ${i}` } })).status, 200);
  const full = await call(s.base, "POST", inPath(a), { json: { title: "zu viel" } });
  assert.equal(full.status, 507);
  assert.match(full.data.msg, /voll \(3 Einträge\)/);
  // Nach dem Abholen ist wieder Platz
  const items = (await pull(s, a.hook, a.key)).data.items;
  await call(s.base, "POST", "/api/inbox/ack", { json: { hook: a.hook, key: a.key, ids: items.map((x) => x.id) } });
  assert.equal((await call(s.base, "POST", inPath(a), { json: { title: "wieder Platz" } })).status, 200);
  const rate = await call(s.base, "POST", inPath(a), { json: { title: "zu schnell" } });
  assert.equal(rate.status, 429, "5 pro Minute pro Eingang");
  assert.ok(+rate.headers.get("retry-after") > 0);
  assert.equal(rate.headers.get("access-control-allow-origin"), "*");
  // Andere Eingänge sind nicht betroffen
  const b = (await create(s)).data;
  assert.equal((await call(s.base, "POST", inPath(b), { json: { title: "anderer Eingang" } })).status, 200);
  assert.equal((await create(s)).status, 200);
  const many = await create(s);
  assert.equal(many.status, 429);
  assert.match(many.data.msg, /zu viele Eingänge/);
});

test("hookSource und inboxItem (reine Funktionen)", () => {
  assert.equal(hookSource({ header: "Mein Formular" }), "Mein Formular");
  assert.equal(hookSource({ query: "Siri", ua: "Zapier" }), "Siri");
  assert.equal(hookSource({ ua: "Shortcuts/1146.1 CFNetwork/1490.0.4 Darwin/23.2.0" }), "Siri");
  assert.equal(hookSource({ ua: "BackgroundShortcutRunner/1146 CFNetwork/1490 Darwin/23" }), "Siri");
  assert.equal(hookSource({ ua: "Zapier" }), "Zapier");
  assert.equal(hookSource({ ua: "Integromat/production" }), "Make");
  assert.equal(hookSource({ ua: "Make/production" }), "Make");
  assert.equal(hookSource({ ua: "n8n" }), "n8n");
  assert.equal(hookSource({ ua: "IFTTT-Protocol/v1" }), "IFTTT");
  assert.equal(hookSource({ ua: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1" }), "Webhook");
  assert.equal(hookSource({}), "Webhook");
  assert.equal(inboxItem({ notes: "nur Notiz" }), null);
  assert.equal(inboxItem({ title: "   " }), null);
  assert.deepEqual(inboxItem({ Title: "Groß geschrieben", PRIO: "p1", Time: "14.05 Uhr" }), { title: "Groß geschrieben", notes: null, due: null, time: "14:05", bag: null, prio: 3, url: null });
  assert.deepEqual(inboxItem({ text: "Zeile 1\r\nZeile 2", notes: "Notiz" }), { title: "Zeile 1", notes: "Zeile 2\n\nNotiz", due: null, time: null, bag: null, prio: null, url: null });
  assert.equal(inboxItem({ title: "x", prio: "egal" }).prio, null);
  assert.equal(inboxItem({ title: "x", url: "ftp://x" }).url, null);
  assert.equal(inboxItem({ title: { verschachtelt: true } }), null);
});
