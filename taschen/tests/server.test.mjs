// Tests für den Arbeitstaschen-Server: Auslieferung, CORS, Sync, Dateien, Grenzen, Web Push (VAPID) und KI
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { setTimeout as sleep } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import { start, vapidJwt, vapidKeys, pushHostAllowed, localParts, normalizeAnswer, validTz } from "../server/taschen-server.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const APP = path.resolve(HERE, "..");
const SERVER_FILE = path.join(APP, "server", "taschen-server.mjs");
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), "taschen-server-test-"));
const GH = "https://georgleomaser-bit.github.io";
const KB = 1024;

// ---------- Helfer ----------
const hex = (n = 32) => crypto.randomBytes(n).toString("hex");
const b64 = (n) => crypto.randomBytes(n).toString("base64");
const dataDir = (name) => path.join(TMP, name);

async function call(base, method, p, { json, body, headers = {} } = {}) {
  const init = { method, headers: { ...headers } };
  if (json !== undefined) {
    init.headers["Content-Type"] = "application/json";
    init.body = JSON.stringify(json);
  } else if (body !== undefined) {
    init.body = body;
    if (!Object.keys(init.headers).some((k) => k.toLowerCase() === "content-type")) init.headers["Content-Type"] = "application/octet-stream";
  }
  const res = await fetch(base + p, init);
  const buf = Buffer.from(await res.arrayBuffer());
  let data = null;
  try {
    data = JSON.parse(buf.toString("utf8"));
  } catch (_) {
    data = null;
  }
  return { status: res.status, headers: res.headers, data, text: buf.toString("utf8"), buf };
}

// Rohe Anfrage (Pfad wird nicht normalisiert, optional „chunked“ ohne Content-Length)
function raw(port, method, p, { headers = {}, chunks = null } = {}) {
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
    for (const c of chunks || []) req.write(c);
    req.end();
  });
}

async function until(fn, ms = 4000, what = "Bedingung") {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const v = await fn();
    if (v) return v;
    await sleep(20);
  }
  throw new Error(`Zeitüberschreitung: ${what}`);
}

// Attrappe eines Push-Dienstes: /gone/… → 410, /err/… → 500, sonst 201
function mockPush() {
  const hits = [];
  const srv = http.createServer((req, res) => {
    const parts = [];
    req.on("data", (c) => parts.push(c));
    req.on("end", () => {
      hits.push({ path: req.url, method: req.method, headers: req.headers, body: Buffer.concat(parts), t: Date.now() });
      if (req.url.startsWith("/gone/")) res.writeHead(410).end();
      else if (req.url.startsWith("/err/")) res.writeHead(500, { "Content-Type": "application/json" }).end('{"reason":"InternalServerError"}');
      else res.writeHead(201, { "apns-id": "x" }).end();
    });
  });
  return new Promise((resolve) => srv.listen(0, "127.0.0.1", () => resolve({ srv, hits, port: srv.address().port, at: (p) => hits.filter((h) => h.path === p) })));
}

const servers = [];
async function boot(name, env = {}, opts = {}) {
  const s = await start({ env: { PORT: "0", HOST: "127.0.0.1", DATA_DIR: dataDir(name), ...env }, quiet: true, ...opts });
  servers.push(s);
  return { ...s, base: `http://127.0.0.1:${s.port}` };
}

let main; // Hauptserver mit kleinen Grenzen
let push; // Attrappe des Push-Dienstes

before(async () => {
  push = await mockPush();
  main = await boot("main", {
    TASCHEN_PUSH_HOSTS: "127.0.0.1",
    TASCHEN_TICK_MS: "100",
    ALLOWED_HOSTS: "taschen.example",
    TASCHEN_STATE_MAX: String(64 * KB),
    TASCHEN_FILE_MAX: String(256 * KB),
    TASCHEN_QUOTA: String(600 * KB),
  });
});

after(async () => {
  for (const s of servers) await s.close().catch(() => {});
  await new Promise((r) => push.srv.close(r));
  push.srv.closeAllConnections?.();
  fs.rmSync(TMP, { recursive: true, force: true });
});

// ---------- Gesundheit ----------
test("GET /api/health meldet den Taschen-Server", async () => {
  const r = await call(main.base, "GET", "/api/health");
  assert.equal(r.status, 200);
  assert.equal(r.data.ok, true);
  assert.equal(r.data.service, "taschen");
  assert.equal(r.data.version, "1.0.0");
  assert.equal(r.data.sync, true);
  assert.equal(r.data.push, true);
  assert.equal(r.data.ai, false);
  assert.equal(r.headers.get("cache-control"), "no-store");
  assert.match(r.headers.get("content-type"), /application\/json/);
});

test("Unbekannte API-Pfade und falsche Methoden", async () => {
  assert.equal((await call(main.base, "GET", "/api/nichts")).status, 404);
  assert.equal((await call(main.base, "POST", "/api/push/key", { json: {} })).status, 405);
  assert.equal((await call(main.base, "PATCH", `/api/sync/${hex()}`, { json: {} })).status, 405);
});

// ---------- Statische App ----------
test("liefert die App mit Sicherheits-Headern aus", async () => {
  const r = await call(main.base, "GET", "/");
  assert.equal(r.status, 200);
  assert.match(r.headers.get("content-type"), /text\/html/);
  assert.match(r.text, /<!doctype html>/i);
  const csp = r.headers.get("content-security-policy");
  assert.match(csp, /connect-src 'self' https:/);
  assert.match(csp, /frame-ancestors 'none'/);
  assert.equal(r.headers.get("x-frame-options"), "DENY");
  assert.equal(r.headers.get("x-content-type-options"), "nosniff");
  assert.equal(r.headers.get("cache-control"), "no-cache");
  const etag = r.headers.get("etag");
  assert.ok(etag);
  assert.equal((await call(main.base, "GET", "/", { headers: { "If-None-Match": etag } })).status, 304);
  const head = await raw(main.port, "HEAD", "/");
  assert.equal(head.status, 200);
  assert.equal(head.text, "");

  const sw = await call(main.base, "GET", "/sw.js");
  assert.equal(sw.status, 200);
  assert.match(sw.headers.get("content-type"), /text\/javascript/);
  assert.equal(sw.headers.get("cache-control"), "no-cache");
  const cfg = await call(main.base, "GET", "/js/config.js");
  assert.equal(cfg.status, 200);
  assert.match(cfg.text, /Arbeitstaschen/);
  const man = await call(main.base, "GET", "/manifest.webmanifest");
  assert.equal(man.status, 200);
  assert.match(man.headers.get("content-type"), /application\/manifest\+json/);
  const ico = await call(main.base, "GET", "/icons/icon.svg");
  assert.equal(ico.status, 200);
  assert.match(ico.headers.get("content-type"), /image\/svg\+xml/);
  assert.match(ico.headers.get("cache-control"), /max-age=/);
  const ui = fs.existsSync(path.join(APP, "js", "ui")) ? fs.readdirSync(path.join(APP, "js", "ui")).find((f) => f.endsWith(".js")) : null;
  if (ui) {
    const u = await call(main.base, "GET", `/js/ui/${ui}`);
    assert.equal(u.status, 200, `/js/ui/${ui}`);
    assert.match(u.headers.get("content-type"), /text\/javascript/);
  }
  // Seitenaufrufe ohne Endung → App, robots.txt sperrt Suchmaschinen aus
  const nav = await call(main.base, "GET", "/heute");
  assert.equal(nav.status, 200);
  assert.match(nav.text, /<!doctype html>/i);
  assert.match((await call(main.base, "GET", "/robots.txt")).text, /Disallow: \//);
  assert.equal((await call(main.base, "POST", "/", { body: "x" })).status, 405);
});

test("Server-Code, Daten und Tests bleiben privat", async () => {
  const blocked = [
    "/server/taschen-server.mjs",
    "/server/install.sh",
    "/server/",
    "/server",
    "/data/push.json",
    "/data/vapid.json",
    "/data/",
    "/tests/server.test.mjs",
    "/js/../server/taschen-server.mjs",
    "/%2e%2e/taschen/server/taschen-server.mjs",
    "/js/..%2fserver%2ftaschen-server.mjs",
    "/js/%2e%2e/server/install.sh",
    "/css/..%5c..%5cserver%5ctaschen-server.mjs",
    "/.env",
    "/js/.hidden",
    "/node_modules/x/package.json",
    "/package.json",
  ];
  for (const p of blocked) {
    const r = await raw(main.port, "GET", p);
    assert.ok(!/createServer|ANTHROPIC|set -euo pipefail|privateJwk/.test(r.text), `${p} darf keinen Server-Code oder Schlüssel liefern`);
    if (/^\/(server|data|tests)\b/.test(p) || /\.(mjs|sh|json)$/.test(p)) assert.equal(r.status, 404, p);
  }
  // Die echten Daten liegen im Datenordner – auch über Umwege nicht abrufbar
  assert.ok(fs.existsSync(path.join(dataDir("main"), "vapid.json")));
  assert.equal((await raw(main.port, "GET", "/data/vapid.json")).status, 404);
});

// ---------- CORS ----------
test("CORS: Preflight für erlaubte Herkunft, Ablehnung für fremde", async () => {
  const id = hex();
  const pre = await raw(main.port, "OPTIONS", `/api/sync/${id}`, { headers: { Origin: GH, "Access-Control-Request-Method": "PUT", "Access-Control-Request-Headers": "content-type" } });
  assert.equal(pre.status, 204);
  assert.equal(pre.headers["access-control-allow-origin"], GH);
  for (const m of ["GET", "PUT", "POST", "DELETE"]) assert.match(pre.headers["access-control-allow-methods"], new RegExp(m));
  assert.match(pre.headers["access-control-allow-headers"], /Content-Type/i);
  assert.match(pre.headers.vary, /Origin/);

  const evil = await raw(main.port, "OPTIONS", `/api/sync/${id}`, { headers: { Origin: "https://evil.example", "Access-Control-Request-Method": "PUT" } });
  assert.equal(evil.status, 403);
  assert.equal(evil.headers["access-control-allow-origin"], undefined);

  const h1 = await call(main.base, "GET", "/api/health", { headers: { Origin: GH } });
  assert.equal(h1.headers.get("access-control-allow-origin"), GH);
  assert.equal(h1.headers.get("cross-origin-resource-policy"), "cross-origin");
  const h2 = await call(main.base, "GET", "/api/health", { headers: { Origin: "https://evil.example" } });
  assert.equal(h2.headers.get("access-control-allow-origin"), null);

  const data = b64(30);
  assert.equal((await call(main.base, "PUT", `/api/sync/${id}`, { json: { rev: 0, data }, headers: { Origin: "https://evil.example" } })).status, 403);
  assert.equal((await call(main.base, "PUT", `/api/sync/${id}`, { json: { rev: 0, data }, headers: { Origin: "null" } })).status, 403);
  const ok = await call(main.base, "PUT", `/api/sync/${id}`, { json: { rev: 0, data }, headers: { Origin: GH } });
  assert.equal(ok.status, 200);
  assert.equal(ok.headers.get("access-control-allow-origin"), GH);
  // Auch Fehlerantworten (409) sind für die erlaubte Herkunft lesbar
  const conflict = await call(main.base, "PUT", `/api/sync/${id}`, { json: { rev: 0, data }, headers: { Origin: GH } });
  assert.equal(conflict.status, 409);
  assert.equal(conflict.headers.get("access-control-allow-origin"), GH);
  // Gleiche Herkunft und ALLOWED_HOSTS
  assert.equal((await call(main.base, "PUT", `/api/sync/${id}`, { json: { rev: 1, data }, headers: { Origin: `http://127.0.0.1:${main.port}` } })).status, 200);
  const own = await call(main.base, "PUT", `/api/sync/${id}`, { json: { rev: 2, data }, headers: { Origin: "https://taschen.example" } });
  assert.equal(own.status, 200);
  assert.equal(own.headers.get("access-control-allow-origin"), null);
  assert.equal((await call(main.base, "DELETE", `/api/sync/${id}`, { headers: { Origin: "https://evil.example" } })).status, 403);
});

// ---------- Sync ----------
test("Sync: GET/PUT/409/DELETE mit Revisionen", async () => {
  const id = hex();
  const p = `/api/sync/${id}`;
  assert.equal((await call(main.base, "GET", p)).status, 404);
  assert.equal((await call(main.base, "GET", "/api/sync/abc")).status, 404);
  assert.equal((await call(main.base, "GET", `/api/sync/${hex().toUpperCase()}`)).status, 404);

  const d1 = b64(100);
  const put1 = await call(main.base, "PUT", p, { json: { rev: 0, data: d1 } });
  assert.equal(put1.status, 200);
  assert.equal(put1.data.rev, 1);
  const g1 = await call(main.base, "GET", p);
  assert.equal(g1.status, 200);
  assert.deepEqual([g1.data.rev, g1.data.data], [1, d1]);
  assert.equal(typeof g1.data.updated, "number");
  assert.equal(g1.headers.get("etag"), '"r1"');
  assert.equal((await call(main.base, "GET", p, { headers: { "If-None-Match": '"r1"' } })).status, 304);

  // Veralteter Stand → 409 mit dem aktuellen Stand zum Zusammenführen
  const c = await call(main.base, "PUT", p, { json: { rev: 0, data: b64(50) } });
  assert.equal(c.status, 409);
  assert.deepEqual([c.data.rev, c.data.data, c.data.updated], [1, d1, g1.data.updated]);
  const d2 = b64(60);
  const put2 = await call(main.base, "PUT", p, { json: { rev: 1, data: d2 } });
  assert.equal(put2.data.rev, 2);
  assert.equal((await call(main.base, "PUT", p, { json: { rev: 5, data: d2 } })).data.rev, 2);

  // Gleichzeitige Schreibversuche: genau einer gewinnt
  const race = await Promise.all(Array.from({ length: 6 }, () => call(main.base, "PUT", p, { json: { rev: 2, data: b64(40) } })));
  assert.equal(race.filter((r) => r.status === 200).length, 1);
  assert.equal(race.filter((r) => r.status === 409).length, 5);
  assert.equal((await call(main.base, "GET", p)).data.rev, 3);

  const del = await call(main.base, "DELETE", p);
  assert.equal(del.status, 200);
  assert.equal(del.data.deleted, true);
  assert.equal((await call(main.base, "GET", p)).status, 404);
  assert.equal((await call(main.base, "DELETE", p)).data.deleted, false);
  // Neu und rev > 0 → 409 mit rev 0
  const fresh = await call(main.base, "PUT", p, { json: { rev: 3, data: d2 } });
  assert.equal(fresh.status, 409);
  assert.deepEqual([fresh.data.rev, fresh.data.data], [0, null]);
  await call(main.base, "DELETE", p);
});

test("Sync: Eingaben werden streng geprüft", async () => {
  const p = `/api/sync/${hex()}`;
  assert.equal((await call(main.base, "PUT", p, { json: { rev: 0, data: "äöü <script>" } })).status, 400);
  assert.equal((await call(main.base, "PUT", p, { json: { rev: 0 } })).status, 400);
  assert.equal((await call(main.base, "PUT", p, { json: { rev: 0, data: "" } })).status, 400);
  assert.equal((await call(main.base, "PUT", p, { json: { rev: -1, data: b64(9) } })).status, 400);
  assert.equal((await call(main.base, "PUT", p, { json: { rev: "0", data: b64(9) } })).status, 400);
  assert.equal((await call(main.base, "PUT", p, { json: { rev: 1.5, data: b64(9) } })).status, 400);
  assert.equal((await call(main.base, "PUT", p, { body: JSON.stringify({ rev: 0, data: b64(9) }), headers: { "Content-Type": "text/plain" } })).status, 415);
  assert.equal((await call(main.base, "PUT", p, { body: "{kaputt", headers: { "Content-Type": "application/json" } })).status, 400);
  assert.equal((await call(main.base, "PUT", p, { body: "[1,2]", headers: { "Content-Type": "application/json" } })).status, 400);
  assert.equal((await call(main.base, "GET", p)).status, 404);
});

test("Sync: Größenlimit für den Datenstand", async () => {
  const p = `/api/sync/${hex()}`;
  // knapp über der Grenze (Daten selbst zu groß) und weit darüber (Körper zu groß) – die 413 kommt beide Male an
  const big = await call(main.base, "PUT", p, { json: { rev: 0, data: "A".repeat(64 * KB + 4) } });
  assert.equal(big.status, 413);
  assert.match(big.data.msg, /zu groß/);
  const huge = await call(main.base, "PUT", p, { json: { rev: 0, data: "A".repeat(400 * KB) } });
  assert.equal(huge.status, 413);
  const chunked = await raw(main.port, "PUT", p, { headers: { "Content-Type": "application/json", "Transfer-Encoding": "chunked" }, chunks: ['{"rev":0,"data":"', "A".repeat(100 * KB), "A".repeat(100 * KB), '"}'] });
  assert.equal(chunked.status, 413);
  assert.equal((await call(main.base, "GET", p)).status, 404);
  const ok = await call(main.base, "PUT", p, { json: { rev: 0, data: "A".repeat(60 * KB) } });
  assert.equal(ok.status, 200);
  await call(main.base, "DELETE", p);
});

// ---------- Dateien ----------
test("Dateien: hochladen, abrufen, löschen", async () => {
  const id = hex();
  const blob = crypto.randomBytes(100 * KB);
  const p = `/api/sync/${id}/files/f_abc-123`;
  const up = await call(main.base, "PUT", p, { body: blob });
  assert.equal(up.status, 200);
  assert.equal(up.data.size, blob.length);
  const got = await call(main.base, "GET", p);
  assert.equal(got.status, 200);
  assert.equal(got.headers.get("content-type"), "application/octet-stream");
  assert.ok(got.buf.equals(blob));
  // Ersetzen
  const blob2 = crypto.randomBytes(10 * KB);
  assert.equal((await call(main.base, "PUT", p, { body: blob2 })).status, 200);
  assert.ok((await call(main.base, "GET", p)).buf.equals(blob2));
  assert.equal((await call(main.base, "DELETE", p)).status, 200);
  assert.equal((await call(main.base, "GET", p)).status, 404);
  assert.equal((await call(main.base, "DELETE", p)).status, 404);
  // Ungültige Datei-IDs
  assert.equal((await call(main.base, "GET", `/api/sync/${id}/files/a.b`)).status, 404);
  assert.equal((await call(main.base, "PUT", `/api/sync/${id}/files/${"x".repeat(65)}`, { body: blob2 })).status, 404);
  // Löschen der ID nimmt die Dateien mit
  await call(main.base, "PUT", p, { body: blob2 });
  await call(main.base, "DELETE", `/api/sync/${id}`);
  assert.equal((await call(main.base, "GET", p)).status, 404);
  assert.equal(fs.existsSync(path.join(dataDir("main"), "sync", id)), false);
});

test("Dateien: Größenlimit (auch ohne Content-Length)", async () => {
  const id = hex();
  const p = `/api/sync/${id}/files/gross`;
  const r = await call(main.base, "PUT", p, { body: crypto.randomBytes(256 * KB + 1) });
  assert.equal(r.status, 413);
  assert.match(r.data.msg, /zu groß/);
  const chunked = await raw(main.port, "PUT", p, { headers: { "Content-Type": "application/octet-stream", "Transfer-Encoding": "chunked" }, chunks: [crypto.randomBytes(200 * KB), crypto.randomBytes(100 * KB)] });
  assert.equal(chunked.status, 413);
  assert.equal((await call(main.base, "GET", p)).status, 404);
  // Keine Temp-Reste
  const dir = path.join(dataDir("main"), "sync", id, "files");
  assert.deepEqual(fs.existsSync(dir) ? fs.readdirSync(dir) : [], []);
  await call(main.base, "DELETE", `/api/sync/${id}`);
});

test("Dateien: Kontingent pro ID (507)", async () => {
  const id = hex();
  const f = (n) => `/api/sync/${id}/files/f${n}`;
  assert.equal((await call(main.base, "PUT", `/api/sync/${id}`, { json: { rev: 0, data: b64(3000) } })).status, 200);
  assert.equal((await call(main.base, "PUT", f(1), { body: crypto.randomBytes(250 * KB) })).status, 200);
  assert.equal((await call(main.base, "PUT", f(2), { body: crypto.randomBytes(250 * KB) })).status, 200);
  const full = await call(main.base, "PUT", f(3), { body: crypto.randomBytes(250 * KB) });
  assert.equal(full.status, 507);
  assert.match(full.data.msg, /voll/);
  // Auch beim Streamen ohne Content-Length
  const chunked = await raw(main.port, "PUT", f(3), { headers: { "Content-Type": "application/octet-stream", "Transfer-Encoding": "chunked" }, chunks: [crypto.randomBytes(120 * KB), crypto.randomBytes(120 * KB)] });
  assert.equal(chunked.status, 507);
  // Ersetzen durch eine kleinere Datei zählt nur den Unterschied
  assert.equal((await call(main.base, "PUT", f(1), { body: crypto.randomBytes(100 * KB) })).status, 200);
  assert.equal((await call(main.base, "PUT", f(3), { body: crypto.randomBytes(150 * KB) })).status, 200);
  assert.equal((await call(main.base, "PUT", f(4), { body: crypto.randomBytes(100 * KB) })).status, 507);
  assert.equal((await call(main.base, "DELETE", f(2))).status, 200);
  assert.equal((await call(main.base, "PUT", f(4), { body: crypto.randomBytes(100 * KB) })).status, 200);
  // Nach dem Löschen der ID ist wieder Platz
  await call(main.base, "DELETE", `/api/sync/${id}`);
  assert.equal((await call(main.base, "PUT", f(5), { body: crypto.randomBytes(250 * KB) })).status, 200);
  await call(main.base, "DELETE", `/api/sync/${id}`);
});

// ---------- Ratenbegrenzung ----------
test("Ratenbegrenzung pro IP, pro ID und für neue IDs", async () => {
  const s = await boot("rate", { TASCHEN_RATE_IP: "12", TASCHEN_RATE_ID: "3", TASCHEN_NEW_IDS: "2" });
  const a = hex();
  for (let i = 0; i < 3; i++) assert.equal((await call(s.base, "GET", `/api/sync/${a}`)).status, 404);
  const idLimited = await call(s.base, "GET", `/api/sync/${a}`);
  assert.equal(idLimited.status, 429);
  assert.ok(+idLimited.headers.get("retry-after") > 0);
  // Andere ID ist nicht betroffen; neue IDs pro Adresse sind begrenzt
  assert.equal((await call(s.base, "PUT", `/api/sync/${hex()}`, { json: { rev: 0, data: b64(9) } })).status, 200);
  assert.equal((await call(s.base, "PUT", `/api/sync/${hex()}`, { json: { rev: 0, data: b64(9) } })).status, 200);
  const third = await call(s.base, "PUT", `/api/sync/${hex()}`, { json: { rev: 0, data: b64(9) } });
  assert.equal(third.status, 429);
  assert.match(third.data.msg, /Sync-Codes/);
  // Insgesamt pro IP
  let last;
  for (let i = 0; i < 12; i++) last = await call(s.base, "GET", "/api/health");
  assert.equal(last.status, 429);
  assert.ok(+last.headers.get("retry-after") > 0);
  // Die App selbst wird weiter ausgeliefert
  assert.equal((await call(s.base, "GET", "/")).status, 200);
});

// ---------- Web Push ----------
function decodeJwt(t) {
  const [h, c, s] = t.split(".");
  return { header: JSON.parse(Buffer.from(h, "base64url")), claims: JSON.parse(Buffer.from(c, "base64url")), sig: Buffer.from(s, "base64url"), input: `${h}.${c}` };
}
function publicKeyFromRaw(k) {
  const raw = Buffer.from(k, "base64url");
  return crypto.createPublicKey({ key: { kty: "EC", crv: "P-256", x: b64u(raw.subarray(1, 33)), y: b64u(raw.subarray(33, 65)) }, format: "jwk" });
}
const b64u = (b) => Buffer.from(b).toString("base64url");
const sub = (p) => ({ endpoint: `http://127.0.0.1:${push.port}${p}`, keys: { p256dh: b64u(crypto.randomBytes(65)), auth: b64u(crypto.randomBytes(16)) } });
// Zeitzone, in der es gerade etwa Mittag ist – so stört kein Tageswechsel die Briefing-Tests
function noonZone() {
  const off = 12 - new Date().getUTCHours();
  const tz = off === 0 ? "UTC" : `Etc/GMT${off > 0 ? "-" : "+"}${Math.abs(off)}`;
  const hhmm = (ms = Date.now()) => {
    const m = localParts(ms, tz).minutes;
    return `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
  };
  return { tz, hhmm, weekday: localParts(Date.now(), tz).weekday };
}

function checkPushRequest(h, key) {
  assert.equal(h.method, "POST");
  assert.equal(h.body.length, 0, "ohne Nutzlast");
  assert.equal(h.headers["content-length"], "0");
  assert.equal(h.headers.topic, undefined, "kein Topic-Header (Apple antwortet sonst 400)");
  assert.equal(h.headers["content-encoding"], undefined);
  assert.ok(+h.headers.ttl > 0, "TTL positiv");
  const m = /^vapid t=([^,\s]+), k=([A-Za-z0-9_-]+)$/.exec(h.headers.authorization || "");
  assert.ok(m, "Authorization: vapid t=…, k=…");
  assert.equal(m[2], key);
  const jwt = decodeJwt(m[1]);
  assert.deepEqual(jwt.header, { typ: "JWT", alg: "ES256" });
  assert.equal(jwt.claims.aud, `http://127.0.0.1:${push.port}`);
  assert.equal(jwt.claims.sub, "mailto:acytex@outlook.de");
  const now = Math.floor(Date.now() / 1000);
  assert.ok(jwt.claims.exp > now + 3600, "exp in der Zukunft");
  assert.ok(jwt.claims.exp <= now + 12 * 3600 + 5, "exp höchstens 12 Std.");
  assert.equal(jwt.sig.length, 64, "JOSE-Signatur r||s statt DER");
  assert.ok(crypto.verify("sha256", Buffer.from(jwt.input), { key: publicKeyFromRaw(key), dsaEncoding: "ieee-p1363" }, jwt.sig), "Signatur passt zum öffentlichen Schlüssel");
  return jwt;
}

test("Push: öffentlicher VAPID-Schlüssel", async () => {
  const r = await call(main.base, "GET", "/api/push/key");
  assert.equal(r.status, 200);
  const raw = Buffer.from(r.data.key, "base64url");
  assert.equal(raw.length, 65);
  assert.equal(raw[0], 4);
  assert.equal(r.data.key, main.vapidPublicKey);
  const stored = JSON.parse(fs.readFileSync(path.join(dataDir("main"), "vapid.json"), "utf8"));
  assert.equal(stored.publicKey, r.data.key);
  if (process.platform !== "win32") assert.equal(fs.statSync(path.join(dataDir("main"), "vapid.json")).mode & 0o077, 0, "Schlüsseldatei nur für den Dienst lesbar");
});

test("Push: Anmelden prüft Gerät, Abo und Push-Dienst", async () => {
  const dev = hex();
  const bad = (body) => call(main.base, "POST", "/api/push/subscribe", { json: body });
  assert.equal((await bad({ device: "kurz", subscription: sub("/p/x") })).status, 400);
  assert.equal((await bad({ device: dev })).status, 400);
  assert.equal((await bad({ device: dev, subscription: { endpoint: "https://evil.example/push" } })).status, 400);
  assert.equal((await bad({ device: dev, subscription: { endpoint: "http://169.254.169.254/latest" } })).status, 400);
  assert.equal((await bad({ device: dev, subscription: { endpoint: "https://web.push.apple.com.evil.example/x" } })).status, 400);
  assert.equal((await call(main.base, "POST", "/api/push/subscribe", { body: "{}", headers: { "Content-Type": "text/plain" } })).status, 415);
  assert.equal((await call(main.base, "POST", "/api/push/update", { json: { device: hex(), tz: "Europe/Berlin", times: [] } })).status, 404);
  assert.equal((await call(main.base, "POST", "/api/push/test", { json: { device: hex() } })).status, 404);
  assert.equal((await call(main.base, "POST", "/api/push/unsubscribe", { json: { device: hex() } })).status, 404);
});

test("Push: Test-Mitteilung mit gültigem VAPID-JWT (ES256, ohne Nutzlast)", async () => {
  const dev = hex();
  const ep = `/p/test-${hex(4)}`;
  const r = await call(main.base, "POST", "/api/push/subscribe", { json: { device: dev, subscription: sub(ep), tz: "Europe/Berlin", times: [], briefing: null, evening: null, workdays: [1, 2, 3, 4, 5] } });
  assert.equal(r.status, 200);
  assert.equal(r.data.ok, true);
  const t = await call(main.base, "POST", "/api/push/test", { json: { device: dev } });
  assert.equal(t.status, 200);
  const hits = push.at(ep);
  assert.equal(hits.length, 1);
  const jwt = checkPushRequest(hits[0], main.vapidPublicKey);
  assert.equal(hits[0].headers.urgency, "high");
  // JWT wird pro Audience wiederverwendet (Apple: höchstens 1× pro Stunde neu)
  await call(main.base, "POST", "/api/push/test", { json: { device: dev } });
  assert.equal(push.at(ep)[1].headers.authorization.split(" ")[1], `t=${jwt.input}.${b64u(jwt.sig)},`);
  // Abmelden
  assert.equal((await call(main.base, "POST", "/api/push/unsubscribe", { json: { device: dev } })).status, 200);
  assert.equal((await call(main.base, "POST", "/api/push/test", { json: { device: dev } })).status, 404);
  // Geräte-Tokens werden nur gehasht gespeichert
  await call(main.base, "POST", "/api/push/subscribe", { json: { device: dev, subscription: sub(ep), tz: "UTC", times: [] } });
  await until(() => fs.existsSync(path.join(dataDir("main"), "push.json")) && fs.readFileSync(path.join(dataDir("main"), "push.json"), "utf8").includes(ep), 3000, "push.json gespeichert");
  assert.ok(!fs.readFileSync(path.join(dataDir("main"), "push.json"), "utf8").includes(dev));
  await call(main.base, "POST", "/api/push/unsubscribe", { json: { device: dev } });
});

test("Push: Takt schickt fällige Zeitpunkte genau einmal (Urgency high)", async () => {
  const dev = hex();
  const ep = `/p/sched-${hex(4)}`;
  const at = Date.now() + 400;
  assert.equal((await call(main.base, "POST", "/api/push/subscribe", { json: { device: dev, subscription: sub(ep), tz: "Europe/Berlin", times: [at, "quatsch", -5], briefing: null, evening: null, workdays: [] } })).status, 200);
  await until(() => push.at(ep).length === 1, 3000, "Push zum Zeitpunkt");
  assert.ok(push.at(ep)[0].t >= at, "nicht zu früh");
  const h = push.at(ep)[0];
  checkPushRequest(h, main.vapidPublicKey);
  assert.equal(h.headers.urgency, "high");
  await sleep(400);
  assert.equal(push.at(ep).length, 1, "genau einmal");
  // Kommt derselbe Zeitpunkt noch einmal (Uhr des Geräts geht nach), wird er nicht wiederholt
  assert.equal((await call(main.base, "POST", "/api/push/update", { json: { device: dev, tz: "Europe/Berlin", times: [at], briefing: null, evening: null, workdays: [] } })).status, 200);
  await sleep(400);
  assert.equal(push.at(ep).length, 1);
  // Ein neuer Zeitpunkt über update
  await call(main.base, "POST", "/api/push/update", { json: { device: dev, tz: "Europe/Berlin", times: [Date.now() + 200, Date.now() + 3600000], briefing: null, evening: null, workdays: [] } });
  await until(() => push.at(ep).length === 2, 3000, "zweiter Push");
  await sleep(300);
  assert.equal(push.at(ep).length, 2);
  await call(main.base, "POST", "/api/push/unsubscribe", { json: { device: dev } });
});

test("Push: tägliches Briefing in der Zeitzone des Geräts an Arbeitstagen (Urgency normal)", async () => {
  const { tz, hhmm, weekday: wd } = noonZone();
  const dev = hex();
  const ep = `/p/brief-${hex(4)}`;
  await call(main.base, "POST", "/api/push/subscribe", { json: { device: dev, subscription: sub(ep), tz, times: [], briefing: hhmm(), evening: null, workdays: [0, 1, 2, 3, 4, 5, 6] } });
  await until(() => push.at(ep).length === 1, 3000, "Briefing-Push");
  const h = push.at(ep)[0];
  checkPushRequest(h, main.vapidPublicKey);
  assert.equal(h.headers.urgency, "normal");
  await sleep(400);
  assert.equal(push.at(ep).length, 1, "nur einmal am Tag");
  // Kein Briefing an freien Tagen
  const dev2 = hex();
  const ep2 = `/p/frei-${hex(4)}`;
  await call(main.base, "POST", "/api/push/subscribe", { json: { device: dev2, subscription: sub(ep2), tz, times: [], briefing: hhmm(), evening: hhmm(), workdays: [0, 1, 2, 3, 4, 5, 6].filter((d) => d !== wd) } });
  // Kein Nachholen eines längst vergangenen Briefings direkt nach dem Einschalten
  const dev3 = hex();
  const ep3 = `/p/spaet-${hex(4)}`;
  await call(main.base, "POST", "/api/push/subscribe", { json: { device: dev3, subscription: sub(ep3), tz, times: [], briefing: hhmm(Date.now() - 30 * 60000), evening: null, workdays: [0, 1, 2, 3, 4, 5, 6] } });
  // Briefing-Uhrzeit später am Tag umgestellt (schon verstrichen) → kein sofortiger Nachschlag
  const dev4 = hex();
  const ep4 = `/p/umgestellt-${hex(4)}`;
  await call(main.base, "POST", "/api/push/subscribe", { json: { device: dev4, subscription: sub(ep4), tz, times: [], briefing: null, evening: null, workdays: [0, 1, 2, 3, 4, 5, 6] } });
  await call(main.base, "POST", "/api/push/update", { json: { device: dev4, tz, times: [], briefing: hhmm(Date.now() - 20 * 60000), evening: null, workdays: [0, 1, 2, 3, 4, 5, 6] } });
  await sleep(500);
  assert.equal(push.at(ep2).length, 0);
  assert.equal(push.at(ep3).length, 0);
  assert.equal(push.at(ep4).length, 0);
  for (const d of [dev, dev2, dev3, dev4]) await call(main.base, "POST", "/api/push/unsubscribe", { json: { device: d } });
});

test("Push: 410 vom Push-Dienst löscht das Abo", async () => {
  // über die Test-Mitteilung
  const dev = hex();
  await call(main.base, "POST", "/api/push/subscribe", { json: { device: dev, subscription: sub(`/gone/${hex(4)}`), tz: "UTC", times: [] } });
  const t = await call(main.base, "POST", "/api/push/test", { json: { device: dev } });
  assert.equal(t.status, 404);
  assert.match(t.data.msg, /abgelaufen/);
  assert.equal((await call(main.base, "POST", "/api/push/update", { json: { device: dev, tz: "UTC", times: [] } })).status, 404);
  // über den Takt
  const dev2 = hex();
  const ep2 = `/gone/${hex(4)}`;
  await call(main.base, "POST", "/api/push/subscribe", { json: { device: dev2, subscription: sub(ep2), tz: "UTC", times: [Date.now() + 100] } });
  await until(() => push.at(ep2).length === 1, 3000, "Push an abgelaufenes Abo");
  await until(async () => (await call(main.base, "POST", "/api/push/update", { json: { device: dev2, tz: "UTC", times: [] } })).status === 404, 2000, "Abo gelöscht");
});

test("Push: Fehler des Push-Dienstes → Pause statt Dauerfeuer, Zeitpunkt bleibt", async () => {
  const dev = hex();
  const ep = `/err/${hex(4)}`;
  await call(main.base, "POST", "/api/push/subscribe", { json: { device: dev, subscription: sub(ep), tz: "UTC", times: [Date.now() + 100] } });
  await until(() => push.at(ep).length === 1, 3000, "erster Versuch");
  await sleep(600);
  assert.equal(push.at(ep).length, 1, "Backoff statt Wiederholung im Takt");
  const t = await call(main.base, "POST", "/api/push/test", { json: { device: dev } });
  assert.equal(t.status, 502);
  assert.equal((await call(main.base, "POST", "/api/push/update", { json: { device: dev, tz: "UTC", times: [] } })).status, 200, "Abo bleibt bestehen");
  await call(main.base, "POST", "/api/push/unsubscribe", { json: { device: dev } });
});

test("Push: dasselbe Abo unter neuem Geräte-Token ersetzt den alten Eintrag", async () => {
  const [a, b] = [hex(), hex()];
  const s = sub(`/p/dup-${hex(4)}`);
  await call(main.base, "POST", "/api/push/subscribe", { json: { device: a, subscription: s, tz: "UTC", times: [] } });
  await call(main.base, "POST", "/api/push/subscribe", { json: { device: b, subscription: s, tz: "UTC", times: [] } });
  assert.equal((await call(main.base, "POST", "/api/push/update", { json: { device: a, tz: "UTC", times: [] } })).status, 404);
  assert.equal((await call(main.base, "POST", "/api/push/update", { json: { device: b, tz: "UTC", times: [] } })).status, 200);
  await call(main.base, "POST", "/api/push/unsubscribe", { json: { device: b } });
});

test("Push-Hosts: nur bekannte Push-Dienste (Schutz vor SSRF)", () => {
  for (const ok of ["https://web.push.apple.com/QGx", "https://api.push.apple.com/x", "https://fcm.googleapis.com/fcm/send/abc", "https://updates.push.services.mozilla.com/wpush/v2/x", "https://wns2-par02p.notify.windows.com/w/?token=x", "https://web.push.apple.com:443/x"])
    assert.equal(pushHostAllowed(ok), true, ok);
  for (const no of [
    "http://web.push.apple.com/x",
    "https://web.push.apple.com:8443/x",
    "https://push.apple.com.evil.example/x",
    "https://evilpush.apple.com.example/x",
    "https://notify.windows.com.evil/x",
    "https://127.0.0.1/x",
    "https://localhost/x",
    "https://user:pw@web.push.apple.com/x",
    "ftp://fcm.googleapis.com/x",
    "kein-url",
    "https://fcm.googleapis.com.evil.example/",
  ])
    assert.equal(pushHostAllowed(no), false, no);
  assert.equal(pushHostAllowed("http://127.0.0.1:9/x", ["127.0.0.1"]), true);
  assert.equal(pushHostAllowed("http://127.0.0.2:9/x", ["127.0.0.1"]), false);
});

test("VAPID-Helfer: Schlüsselpaar und JWT", () => {
  const v = vapidKeys();
  const jwt = vapidJwt("https://web.push.apple.com", { privateJwk: v.privateJwk, subject: "mailto:a@b.de", ttl: 99 * 3600 });
  const d = decodeJwt(jwt);
  assert.equal(d.claims.aud, "https://web.push.apple.com");
  assert.ok(d.claims.exp <= Math.floor(Date.now() / 1000) + 12 * 3600, "exp wird auf 12 Std. begrenzt");
  assert.ok(crypto.verify("sha256", Buffer.from(d.input), { key: publicKeyFromRaw(v.publicKey), dsaEncoding: "ieee-p1363" }, d.sig));
  assert.equal(validTz("Europe/Berlin"), true);
  assert.equal(validTz("Mars/Olympus"), false);
  const lp = localParts(Date.UTC(2026, 9, 5, 22, 30), "Europe/Berlin"); // 06.10. 00:30 in Berlin (Sommerzeit)
  assert.deepEqual(lp, { date: "2026-10-06", minutes: 30, weekday: 2 });
});

test("Neustart: VAPID-Schlüssel, Abos, Daten und Kontingent bleiben erhalten", async () => {
  const env = { TASCHEN_PUSH_HOSTS: "127.0.0.1", TASCHEN_QUOTA: String(300 * KB), TASCHEN_TICK_MS: "100" };
  const s1 = await boot("restart", env);
  const key = (await call(s1.base, "GET", "/api/push/key")).data.key;
  const dev = hex();
  await call(s1.base, "POST", "/api/push/subscribe", { json: { device: dev, subscription: sub(`/p/rs-${hex(4)}`), tz: "UTC", times: [Date.now() + 3600000] } });
  const id = hex();
  await call(s1.base, "PUT", `/api/sync/${id}`, { json: { rev: 0, data: b64(300) } });
  assert.equal((await call(s1.base, "PUT", `/api/sync/${id}/files/a`, { body: crypto.randomBytes(200 * KB) })).status, 200);
  await s1.close();
  fs.writeFileSync(path.join(dataDir("restart"), "sync", id, "files", "b.1234.tmp"), "rest");
  const s2 = await boot("restart", env);
  assert.equal((await call(s2.base, "GET", "/api/push/key")).data.key, key);
  assert.equal((await call(s2.base, "POST", "/api/push/update", { json: { device: dev, tz: "UTC", times: [] } })).status, 200);
  assert.equal((await call(s2.base, "GET", `/api/sync/${id}`)).data.rev, 1);
  assert.equal((await call(s2.base, "PUT", `/api/sync/${id}/files/b`, { body: crypto.randomBytes(200 * KB) })).status, 507, "Belegung wird beim Start gezählt");
  assert.equal(fs.existsSync(path.join(dataDir("restart"), "sync", id, "files", "b.1234.tmp")), false, "Temp-Reste aufgeräumt");
});

// ---------- KI ----------
test("KI ohne Schlüssel → sauberer Fehler", async () => {
  const r = await call(main.base, "POST", "/api/ai", { json: { device: hex(), kind: "ask", context: {}, question: "Was zuerst?" } });
  assert.equal(r.status, 503);
  assert.equal(r.data.ok, false);
  assert.match(r.data.msg, /nicht eingerichtet/);
});

function fakeClient() {
  const fake = { calls: [], mode: "ok" };
  const answer = {
    text: "Fang mit dem Steuerberater an.",
    items: [
      { title: "Steuerberater anrufen", due: "2026-10-07", prio: 3, est: 15 },
      { title: "   ", due: null, prio: null, est: null },
      { title: "Gesellschaftsvertrag lesen", due: "2026-02-31", prio: 7, est: null },
    ],
  };
  fake.client = {
    beta: {
      messages: {
        create: async (params, opts) => {
          fake.calls.push({ params, opts });
          if (fake.mode === "refusal") return { stop_reason: "refusal", content: [] };
          if (fake.mode === "fallback")
            return {
              stop_reason: "end_turn",
              content: [
                { type: "text", text: '{"text":"abgebr' },
                { type: "fallback", from: { model: "a" }, to: { model: "b" } },
                { type: "text", text: JSON.stringify({ text: "Nach dem Wechsel", items: [] }) },
              ],
            };
          if (fake.mode === "rate") throw Object.assign(new Error("rate"), { status: 429 });
          if (fake.mode === "cut") return { stop_reason: "max_tokens", content: [{ type: "text", text: '{"text":"Erst das, dann' }] };
          if (fake.mode === "auth") throw Object.assign(new Error("auth"), { status: 401 });
          return {
            stop_reason: "end_turn",
            content: [
              { type: "thinking", thinking: "" },
              { type: "text", text: JSON.stringify(answer) },
            ],
          };
        },
      },
    },
  };
  return fake;
}

test("KI: Anfrage an Claude mit strukturierter Ausgabe, Prüfung und Aufbereitung", async () => {
  const fake = fakeClient();
  const s = await boot("ai", { TASCHEN_RATE_AI: "100" }, { aiClient: fake.client });
  assert.equal((await call(s.base, "GET", "/api/health")).data.ai, true);
  const context = { app: "Arbeitstaschen", today: "2026-10-06", tasks: [{ title: "Gewerbe anmelden", due: "2026-10-05", status: "überfällig" }] };
  const r = await call(s.base, "POST", "/api/ai", { json: { device: hex(), kind: "plan-day", context, question: "Wie gehe ich heute vor?" } });
  assert.equal(r.status, 200);
  assert.equal(r.data.ok, true);
  assert.equal(r.data.text, "Fang mit dem Steuerberater an.");
  assert.deepEqual(r.data.items, [{ title: "Steuerberater anrufen", due: "2026-10-07", prio: 3, est: 15 }, { title: "Gesellschaftsvertrag lesen" }]);
  const { params, opts } = fake.calls[0];
  assert.equal(params.model, "claude-opus-5-5");
  assert.deepEqual(params.thinking, { type: "adaptive" });
  assert.equal(params.output_config.effort, "medium");
  assert.equal(params.output_config.format.type, "json_schema");
  assert.deepEqual(params.output_config.format.schema.required, ["text", "items"]);
  assert.equal(params.fallbacks, "default");
  assert.ok(params.betas.includes("server-side-fallback-2026-07-01"));
  assert.equal(params.tool_choice, undefined);
  assert.match(params.system[0].text, /Projektmanager/);
  assert.match(params.system[0].text, /du-Form/);
  const msg = params.messages[0].content;
  assert.equal(params.messages[0].role, "user");
  assert.ok(msg.includes(JSON.stringify(context)));
  assert.match(msg, /Plane seinen heutigen Tag/);
  assert.match(msg, /Wie gehe ich heute vor\?/);
  assert.ok(opts.signal);
  assert.ok(opts.timeout > 0);

  // Alle Arten werden angenommen, unbekannte nicht
  for (const kind of ["breakdown", "next", "weekly", "ask"]) assert.equal((await call(s.base, "POST", "/api/ai", { json: { device: hex(), kind, context: {}, question: "Frage" } })).status, 200, kind);
  assert.match(fake.calls.at(-1).params.messages[0].content, /Beantworte seine Frage/);
  assert.equal((await call(s.base, "POST", "/api/ai", { json: { device: hex(), kind: "hack", context: {} } })).status, 400);
  assert.equal((await call(s.base, "POST", "/api/ai", { json: { device: hex(), kind: "ask", context: {}, question: "  " } })).status, 400);
  // Kontext höchstens 48 KB
  const big = await call(s.base, "POST", "/api/ai", { json: { device: hex(), kind: "next", context: { x: "a".repeat(49 * KB) } } });
  assert.equal(big.status, 413);
  // Ablehnung, Ausweichmodell, Fehler
  fake.mode = "refusal";
  const ref = await call(s.base, "POST", "/api/ai", { json: { device: hex(), kind: "ask", context: {}, question: "x" } });
  assert.equal(ref.status, 200);
  assert.match(ref.data.text, /nicht helfen/);
  fake.mode = "fallback";
  assert.equal((await call(s.base, "POST", "/api/ai", { json: { device: hex(), kind: "ask", context: {}, question: "x" } })).data.text, "Nach dem Wechsel");
  fake.mode = "rate";
  const busy = await call(s.base, "POST", "/api/ai", { json: { device: hex(), kind: "ask", context: {}, question: "x" } });
  assert.equal(busy.status, 503);
  assert.match(busy.data.msg, /ausgelastet/);
  fake.mode = "cut";
  const cut = await call(s.base, "POST", "/api/ai", { json: { device: hex(), kind: "ask", context: {}, question: "x" } });
  assert.equal(cut.status, 502);
  assert.match(cut.data.msg, /zu lang/);
  fake.mode = "auth";
  assert.match((await call(s.base, "POST", "/api/ai", { json: { device: hex(), kind: "ask", context: {}, question: "x" } })).data.msg, /Schlüssel/);
});

test("KI: Tageslimit pro Gerät und insgesamt", async () => {
  const fake = fakeClient();
  const s = await boot("ai-limit", { TASCHEN_AI_DAILY: "4", TASCHEN_AI_DEVICE: "2" }, { aiClient: fake.client });
  const ask = (device) => call(s.base, "POST", "/api/ai", { json: { device, kind: "ask", context: {}, question: "Was zuerst?" } });
  const a = hex();
  assert.equal((await ask(a)).status, 200);
  assert.equal((await ask(a)).data.left, 0);
  const third = await ask(a);
  assert.equal(third.status, 429);
  assert.match(third.data.msg, /Kontingent/);
  // Fehlversuche (Dienst ausgelastet) zählen nicht
  fake.mode = "rate";
  assert.equal((await ask(hex())).status, 503);
  fake.mode = "ok";
  const b = hex();
  assert.equal((await ask(b)).status, 200);
  assert.equal((await ask(b)).status, 200);
  const global = await ask(hex());
  assert.equal(global.status, 429);
  assert.match(global.data.msg, /ausgeschöpft/);
  const file = path.join(dataDir("ai-limit"), "ai-usage.json");
  const saved = await until(() => fs.existsSync(file) && JSON.parse(fs.readFileSync(file, "utf8")).total === 4 && JSON.parse(fs.readFileSync(file, "utf8")), 3000, "ai-usage.json gespeichert");
  assert.ok(!JSON.stringify(saved).includes(a), "Geräte-Tokens nur gehasht");
});

test("KI-Antwort aufbereiten (normalizeAnswer)", () => {
  assert.deepEqual(normalizeAnswer('{"text":" Hallo ","items":[{"title":"A","due":"2026-13-01","prio":2,"est":0}]}'), { text: "Hallo", items: [{ title: "A", prio: 2 }] });
  assert.deepEqual(normalizeAnswer("Kein JSON, nur Text."), { text: "Kein JSON, nur Text.", items: [] });
  assert.deepEqual(normalizeAnswer('Vorspann {"text":"x","items":["Einfach"]} Nachspann'), { text: "x", items: [{ title: "Einfach" }] });
  assert.equal(normalizeAnswer({ text: "t", items: Array.from({ length: 50 }, (_, i) => ({ title: "T" + i })) }).items.length, 30);
});

// Mit installiertem SDK (npm install): echte Anfrage über @anthropic-ai/sdk an eine Attrappe der Messages API
let sdk = false;
try {
  await import("@anthropic-ai/sdk");
  sdk = true;
} catch (_) {
  sdk = false;
}
test("KI über @anthropic-ai/sdk gegen eine Attrappe der Messages API", { skip: !sdk && "@anthropic-ai/sdk nicht installiert (npm install)" }, async () => {
  const seen = [];
  const api = http.createServer((req, res) => {
    const parts = [];
    req.on("data", (c) => parts.push(c));
    req.on("end", () => {
      seen.push({ url: req.url, headers: req.headers, body: JSON.parse(Buffer.concat(parts).toString("utf8")) });
      res.writeHead(200, { "Content-Type": "application/json", "request-id": "req_test" });
      res.end(
        JSON.stringify({
          id: "msg_test",
          type: "message",
          role: "assistant",
          model: "claude-opus-5-5",
          content: [{ type: "text", text: JSON.stringify({ text: "Klar.", items: [{ title: "Angebot schicken", due: null, prio: 2, est: 20 }] }) }],
          stop_reason: "end_turn",
          stop_sequence: null,
          usage: { input_tokens: 10, output_tokens: 10 },
        }),
      );
    });
  });
  await new Promise((r) => api.listen(0, "127.0.0.1", r));
  try {
    const s = await boot("ai-sdk", { ANTHROPIC_API_KEY: "sk-ant-test", ANTHROPIC_BASE_URL: `http://127.0.0.1:${api.address().port}` });
    assert.equal((await call(s.base, "GET", "/api/health")).data.ai, true);
    const r = await call(s.base, "POST", "/api/ai", { json: { device: hex(), kind: "next", context: { bag: { name: "NOVA" } }, question: "Was jetzt?" } });
    assert.equal(r.status, 200, r.text);
    assert.deepEqual(r.data.items, [{ title: "Angebot schicken", prio: 2, est: 20 }]);
    assert.match(seen[0].url, /^\/v1\/messages/);
    assert.equal(seen[0].headers["x-api-key"], "sk-ant-test");
    assert.match(seen[0].headers["anthropic-beta"], /server-side-fallback-2026-07-01/);
    assert.equal(seen[0].body.model, "claude-opus-5-5");
    assert.equal(seen[0].body.fallbacks, "default");
    assert.equal(seen[0].body.output_config.format.type, "json_schema");
    assert.equal(seen[0].body.betas, undefined, "betas gehen als Header, nicht im Körper");
  } finally {
    api.close();
    api.closeAllConnections?.();
  }
});

// ---------- Als eigener Prozess ----------
test("Startet als eigener Prozess mit Standard-Grenzen und beendet sich sauber (SIGTERM)", async () => {
  const dir = dataDir("proc");
  const child = spawn(process.execPath, [SERVER_FILE], { env: { PATH: process.env.PATH, PORT: "0", HOST: "127.0.0.1", DATA_DIR: dir }, stdio: ["ignore", "pipe", "pipe"] });
  let out = "";
  child.stdout.on("data", (c) => (out += c));
  child.stderr.on("data", (c) => (out += c));
  try {
    const port = await until(() => /läuft auf http:\/\/127\.0\.0\.1:(\d+)/.exec(out)?.[1], 8000, "Startmeldung");
    const h = await call(`http://127.0.0.1:${port}`, "GET", "/api/health");
    assert.equal(h.data.service, "taschen");
    assert.deepEqual(h.data.limits, { state: 8 * 1024 * KB, file: 14 * 1024 * KB, quota: 300 * 1024 * KB });
    const id = hex();
    await call(`http://127.0.0.1:${port}`, "PUT", `/api/sync/${id}`, { json: { rev: 0, data: b64(30) } });
    const code = new Promise((r) => child.on("exit", r));
    child.kill("SIGTERM");
    assert.equal(await code, 0);
    assert.ok(!out.includes(id), "Sync-IDs tauchen nie im Log auf");
    assert.match(out, /beendet/);
  } finally {
    if (child.exitCode === null) child.kill("SIGKILL");
  }
});
