// Tests für „Konten verbinden“ am Arbeitstaschen-Server: OAuth mit Google und Microsoft gegen Attrappen der Anbieter
// (start → Consent → callback → token → remove, Open-Redirect-Schutz, verschlüsselte Refresh-Tokens, invalid_grant, Rotation)
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
import { start, connectErrorText, sealToken, openToken, parseConnectKey } from "../server/taschen-server.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SERVER_FILE = path.join(HERE, "..", "server", "taschen-server.mjs");
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), "taschen-connect-test-"));
const GH = "https://georgleomaser-bit.github.io";
const APP_URL = `${GH}/website-test-demo-1/taschen/`;
const CREDS = {
  google: { id: "1234-test.apps.googleusercontent.com", secret: "GOCSPX-test_Secret-123" },
  microsoft: { id: "11111111-2222-3333-4444-555555555555", secret: "Ms8Q~test.Secret_value-123" },
};
const GOOGLE_SCOPE = "openid email https://www.googleapis.com/auth/calendar.readonly https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.readonly";
const MS_SCOPE = "offline_access openid email User.Read Calendars.ReadWrite Mail.Read";
const FIRM = "Deine Firma erlaubt diese App noch nicht – bitte die IT um Freigabe";

// ---------- Helfer ----------
const dataDir = (name) => path.join(TMP, name);
const b64u = (b) => Buffer.from(b).toString("base64url");
const sha = (s) => crypto.createHash("sha256").update(s).digest("hex");
const s256 = (v) => crypto.createHash("sha256").update(v).digest("base64url");
const fakeJwt = (claims) => `${b64u(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.${b64u(JSON.stringify(claims))}.${b64u("sig")}`;

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

// Rohe Anfrage ohne automatisches Folgen von Weiterleitungen (für Location, Set-Cookie und Cookie)
function raw(port, method, p, { headers = {} } = {}) {
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

// Fragment der Rücksprung-Adresse lesen: "…#connect=google&account=…" → { url, connect, account, … }
function fragOf(loc) {
  const i = loc.indexOf("#");
  assert.ok(i > 0, `Fragment fehlt: ${loc}`);
  return { url: loc.slice(0, i), ...Object.fromEntries(new URLSearchParams(loc.slice(i + 1))) };
}

// ---------- Attrappe von Google und Microsoft ----------
// Google:    /google/auth · /google/token · /google/userinfo · /google/revoke
// Microsoft: /ms/common/oauth2/v2.0/authorize · /ms/common/oauth2/v2.0/token · /graph/v1.0/me
function mockProviders() {
  const m = {
    hits: [],
    codes: new Map(), // Code → { provider, challenge, method, redirect, email }
    refresh: new Map(), // gültige Refresh-Tokens → { provider, email }
    access: new Map(), // Access-Token → E-Mail
    revoked: [],
    issued: { google: [], microsoft: [] }, // ausgegebene Refresh-Tokens in Reihenfolge
    refreshSeen: { google: [], microsoft: [] }, // vorgelegte Refresh-Tokens
    opts: { google: {}, microsoft: {} },
  };
  let n = 0;
  const tok = (prefix) => `${prefix}-${++n}-${crypto.randomBytes(16).toString("hex")}`;
  const srv = http.createServer((req, res) => {
    const parts = [];
    req.on("data", (c) => parts.push(c));
    req.on("end", () => {
      const u = new URL(req.url, "http://x");
      const body = Object.fromEntries(new URLSearchParams(Buffer.concat(parts).toString("utf8")));
      m.hits.push({ method: req.method, path: u.pathname, query: Object.fromEntries(u.searchParams), body, headers: req.headers });
      const json = (status, obj) => {
        res.writeHead(status, { "Content-Type": "application/json" });
        res.end(JSON.stringify(obj));
      };
      const provider = u.pathname.startsWith("/google/") ? "google" : "microsoft";
      const o = m.opts[provider];
      const bearer = /^Bearer (.+)$/.exec(req.headers.authorization || "")?.[1];

      // Consent-Seite: stimmt sofort zu (oder lehnt mit o.deny ab) und leitet zum Server zurück
      if (u.pathname === "/google/auth" || u.pathname === "/ms/common/oauth2/v2.0/authorize") {
        const q = u.searchParams;
        const to = new URL(q.get("redirect_uri"));
        if (o.deny) for (const [k, v] of Object.entries(o.deny)) to.searchParams.set(k, v);
        else {
          const code = tok(`${provider}-code`);
          m.codes.set(code, { provider, challenge: q.get("code_challenge"), method: q.get("code_challenge_method"), redirect: q.get("redirect_uri"), email: o.email });
          to.searchParams.set("code", code);
        }
        to.searchParams.set("state", q.get("state"));
        res.writeHead(302, { Location: to.href });
        return res.end();
      }

      if (u.pathname === "/google/token" || u.pathname === "/ms/common/oauth2/v2.0/token") {
        if (req.method !== "POST" || !/application\/x-www-form-urlencoded/.test(req.headers["content-type"] || "")) return json(400, { error: "invalid_request" });
        const C = CREDS[provider];
        if (body.client_id !== C.id || body.client_secret !== C.secret) return json(401, { error: "invalid_client", error_description: provider === "microsoft" ? "AADSTS7000215: Invalid client secret provided." : "Unauthorized" });
        if (body.grant_type === "authorization_code") {
          const c = m.codes.get(body.code);
          m.codes.delete(body.code);
          if (!c || c.provider !== provider || c.redirect !== body.redirect_uri || c.method !== "S256" || s256(body.code_verifier || "") !== c.challenge)
            return json(400, { error: "invalid_grant", error_description: provider === "microsoft" ? "AADSTS70008: The provided authorization code has expired." : "Bad Request" });
          if (o.codeError) return json(400, o.codeError);
          const at = tok(`${provider}-at`);
          m.access.set(at, c.email);
          const out = { access_token: at, token_type: "Bearer", expires_in: o.codeExpires ?? 3599, scope: provider === "google" ? GOOGLE_SCOPE : "openid email profile User.Read Calendars.ReadWrite Mail.Read", id_token: fakeJwt({ email: c.email, preferred_username: c.email }) };
          if (!o.noRefresh) {
            const rt = tok(`${provider}-rt`);
            m.refresh.set(rt, { provider, email: c.email });
            m.issued[provider].push(rt);
            out.refresh_token = rt;
          }
          return json(200, out);
        }
        if (body.grant_type === "refresh_token") {
          m.refreshSeen[provider].push(body.refresh_token);
          const r = m.refresh.get(body.refresh_token);
          if (o.refreshError) return json(o.refreshError.status || 400, o.refreshError.body);
          if (!r || r.provider !== provider) return json(400, { error: "invalid_grant", error_description: provider === "microsoft" ? "AADSTS70000: The provided grant has expired." : "Token has been expired or revoked." });
          const at = tok(`${provider}-at`);
          m.access.set(at, r.email);
          const out = { access_token: at, token_type: "Bearer", expires_in: provider === "microsoft" ? 120 : 3599, scope: provider === "google" ? GOOGLE_SCOPE : "User.Read Calendars.ReadWrite Mail.Read" };
          if (provider === "microsoft") {
            // Microsoft rotiert: neuer Refresh-Token, der alte gilt hier sofort nicht mehr (strenger als in echt)
            m.refresh.delete(body.refresh_token);
            const rt = tok("microsoft-rt");
            m.refresh.set(rt, r);
            m.issued.microsoft.push(rt);
            out.refresh_token = rt;
          }
          return json(200, out);
        }
        return json(400, { error: "unsupported_grant_type" });
      }

      if (u.pathname === "/google/userinfo") return m.access.has(bearer) ? json(200, { sub: "1", email: m.access.get(bearer), email_verified: true }) : json(401, { error: "invalid_token" });
      if (u.pathname === "/google/revoke") {
        const t = body.token || u.searchParams.get("token");
        m.revoked.push(t);
        m.refresh.delete(t);
        return json(200, {});
      }
      if (u.pathname === "/graph/v1.0/me") return m.access.has(bearer) ? json(200, { mail: null, userPrincipalName: m.access.get(bearer), displayName: "Papa" }) : json(401, { error: { code: "InvalidAuthenticationToken" } });
      return json(404, { error: "not_found" });
    });
  });
  return new Promise((resolve) =>
    srv.listen(0, "127.0.0.1", () => {
      m.srv = srv;
      m.port = srv.address().port;
      m.base = `http://127.0.0.1:${m.port}`;
      resolve(m);
    }),
  );
}

let mock;
let main;
const servers = [];
const connectEnv = (extra = {}) => ({
  GOOGLE_CLIENT_ID: CREDS.google.id,
  GOOGLE_CLIENT_SECRET: CREDS.google.secret,
  MS_CLIENT_ID: CREDS.microsoft.id,
  MS_CLIENT_SECRET: CREDS.microsoft.secret,
  CONNECT_GOOGLE_AUTH: `${mock.base}/google/auth`,
  CONNECT_GOOGLE_TOKEN: `${mock.base}/google/token`,
  CONNECT_GOOGLE_USERINFO: `${mock.base}/google/userinfo`,
  CONNECT_GOOGLE_REVOKE: `${mock.base}/google/revoke`,
  CONNECT_MS_AUTHORITY: `${mock.base}/ms/common`,
  CONNECT_MS_GRAPH: `${mock.base}/graph/v1.0/`,
  ...extra,
});
async function boot(name, env = {}) {
  const s = await start({ env: { PORT: "0", HOST: "127.0.0.1", DATA_DIR: dataDir(name), ...env }, quiet: true });
  servers.push(s);
  return { ...s, base: `http://127.0.0.1:${s.port}` };
}

// Kompletter Ablauf wie im Browser: start → Consent-Seite der Attrappe → callback (mit Cookie) → zurück zur App
async function connectFlow(s, provider, { ret = APP_URL, email, cookie = true, opts = {} } = {}) {
  const saved = mock.opts[provider];
  mock.opts[provider] = { email: email || (provider === "google" ? `papa.${crypto.randomBytes(3).toString("hex")}@gmail.com` : `papa.${crypto.randomBytes(3).toString("hex")}@firma.de`), ...opts };
  try {
    const st = await raw(s.port, "GET", `/api/connect/${provider}/start?return=${encodeURIComponent(ret)}`);
    assert.equal(st.status, 302, st.text);
    const auth = new URL(st.headers.location);
    assert.equal(auth.origin, mock.base, "weiter zum Anbieter");
    const jar = (st.headers["set-cookie"] || []).map((c) => c.split(";")[0]).join("; ");
    const consent = await raw(mock.port, "GET", auth.pathname + auth.search);
    assert.equal(consent.status, 302);
    const cb = new URL(consent.headers.location);
    assert.equal(cb.pathname, `/api/connect/${provider}/callback`);
    const back = await raw(s.port, "GET", cb.pathname + cb.search, { headers: cookie && jar ? { Cookie: jar } : {} });
    assert.equal(back.status, 302, back.text);
    return { email: mock.opts[provider].email, auth, cb, jar, back, location: back.headers.location, frag: fragOf(back.headers.location) };
  } finally {
    mock.opts[provider] = saved;
  }
}
const token = (s, account, secret, headers = {}) => call(s.base, "POST", "/api/connect/token", { json: { account, secret }, headers });
const remove = (s, account, secret) => call(s.base, "POST", "/api/connect/remove", { json: { account, secret } });
const accountsOf = (name) => {
  const f = path.join(dataDir(name), "connect.json");
  return fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, "utf8")).accounts : {};
};
const keyOf = (name) => parseConnectKey(fs.readFileSync(path.join(dataDir(name), "connect.key"), "utf8"));
const aad = (id, provider) => `taschen-connect:${id}:${provider}`;

before(async () => {
  mock = await mockProviders();
  main = await boot("main", connectEnv({ TASCHEN_RATE_CONNECT: "1000" })); // viele Abläufe hintereinander – Grenzen prüft ein eigener Test
});

after(async () => {
  for (const s of servers) await s.close().catch(() => {});
  await new Promise((r) => mock.srv.close(r));
  mock.srv.closeAllConnections?.();
  fs.rmSync(TMP, { recursive: true, force: true });
});

// ---------- Gesundheit ----------
test("health meldet connect.google/microsoft nur bei gesetzter Client-ID und Secret", async () => {
  const h = await call(main.base, "GET", "/api/health");
  assert.deepEqual(h.data.connect, { google: true, microsoft: true });
  const half = await boot("half", { GOOGLE_CLIENT_ID: CREDS.google.id, MS_CLIENT_ID: CREDS.microsoft.id, MS_CLIENT_SECRET: CREDS.microsoft.secret });
  assert.deepEqual((await call(half.base, "GET", "/api/health")).data.connect, { google: false, microsoft: true });
  const none = await boot("none");
  assert.deepEqual((await call(none.base, "GET", "/api/health")).data.connect, { google: false, microsoft: false });
  // Nicht eingerichteter Anbieter → ehrliche Meldung zurück an die App statt Fehlerseite
  const st = await raw(half.port, "GET", `/api/connect/google/start?return=${encodeURIComponent(APP_URL)}`);
  assert.equal(st.status, 302);
  const f = fragOf(st.headers.location);
  assert.equal(f.url, APP_URL);
  assert.equal(f.connect, "google");
  assert.match(f.error, /nicht eingerichtet/);
});

// ---------- start ----------
test("start (Google): Weiterleitung mit PKCE S256, Scopes, offline-Zugriff und state", async () => {
  const st = await raw(main.port, "GET", `/api/connect/google/start?return=${encodeURIComponent(APP_URL)}`);
  assert.equal(st.status, 302);
  assert.equal(st.headers["cache-control"], "no-store");
  assert.equal(st.headers["referrer-policy"], "no-referrer");
  const u = new URL(st.headers.location);
  assert.equal(u.origin + u.pathname, `${mock.base}/google/auth`);
  const q = u.searchParams;
  assert.equal(q.get("client_id"), CREDS.google.id);
  assert.equal(q.get("response_type"), "code");
  assert.equal(q.get("access_type"), "offline");
  assert.equal(q.get("prompt"), "consent select_account");
  assert.equal(q.get("include_granted_scopes"), "true");
  assert.equal(q.get("scope"), GOOGLE_SCOPE);
  assert.equal(q.get("code_challenge_method"), "S256");
  assert.match(q.get("code_challenge"), /^[A-Za-z0-9_-]{43}$/);
  assert.match(q.get("state"), /^[A-Za-z0-9_-]{32}$/);
  assert.equal(q.get("redirect_uri"), `http://127.0.0.1:${main.port}/api/connect/google/callback`, "ohne PUBLIC_URL/ALLOWED_HOSTS: Adresse der Anfrage (lokal)");
  assert.equal(q.get("client_secret"), null, "Secret nie im Browser");
  assert.equal(q.get("code_verifier"), null);
  // Cookie bindet die Anmeldung an diesen Browser
  const cookie = st.headers["set-cookie"][0];
  assert.match(cookie, /^taschen-connect-[0-9a-f]{12}=[A-Za-z0-9_-]+;/);
  assert.match(cookie, /HttpOnly/);
  assert.match(cookie, /SameSite=Lax/);
  assert.match(cookie, /Max-Age=600/);
  // Jeder Start hat eigenen state und eigene Challenge
  const st2 = await raw(main.port, "GET", `/api/connect/google/start?return=${encodeURIComponent(APP_URL)}`);
  const q2 = new URL(st2.headers.location).searchParams;
  assert.notEqual(q2.get("state"), q.get("state"));
  assert.notEqual(q2.get("code_challenge"), q.get("code_challenge"));
});

test("start (Microsoft): authorize an der Authority mit response_mode=query, select_account und PKCE", async () => {
  const st = await raw(main.port, "GET", `/api/connect/microsoft/start?return=${encodeURIComponent(APP_URL)}`);
  assert.equal(st.status, 302);
  const u = new URL(st.headers.location);
  assert.equal(u.origin + u.pathname, `${mock.base}/ms/common/oauth2/v2.0/authorize`);
  const q = u.searchParams;
  assert.equal(q.get("client_id"), CREDS.microsoft.id);
  assert.equal(q.get("response_type"), "code");
  assert.equal(q.get("response_mode"), "query");
  assert.equal(q.get("prompt"), "select_account");
  assert.equal(q.get("scope"), MS_SCOPE);
  assert.equal(q.get("code_challenge_method"), "S256");
  assert.match(q.get("code_challenge"), /^[A-Za-z0-9_-]{43}$/);
  assert.equal(q.get("redirect_uri"), `http://127.0.0.1:${main.port}/api/connect/microsoft/callback`);
  assert.equal(q.get("access_type"), null);
});

test("start: PUBLIC_URL bzw. ALLOWED_HOSTS bestimmen Weiterleitungs-URI und erlaubte Rücksprünge", async () => {
  const pub = await boot("public", connectEnv({ PUBLIC_URL: "https://taschen.example/" }));
  const st = await raw(pub.port, "GET", `/api/connect/google/start?return=${encodeURIComponent("https://taschen.example/?von=einstellungen")}`);
  assert.equal(st.status, 302, st.text);
  assert.equal(new URL(st.headers.location).searchParams.get("redirect_uri"), "https://taschen.example/api/connect/google/callback");
  const cookie = st.headers["set-cookie"][0];
  assert.match(cookie, /^__Host-taschen-connect-/, "über https: __Host-Cookie");
  assert.match(cookie, /; Secure/);
  assert.match(cookie, /Path=\//);
  // Mit fester Adresse zählt die Adresse der Anfrage nicht als eigene Herkunft
  assert.equal((await raw(pub.port, "GET", `/api/connect/google/start?return=${encodeURIComponent(`http://127.0.0.1:${pub.port}/`)}`)).status, 400);
  assert.equal((await raw(pub.port, "GET", `/api/connect/google/start?return=${encodeURIComponent(APP_URL)}`)).status, 302, "ALLOWED_ORIGINS");
  // Ganzer Ablauf mit __Host-Cookie
  const f = await connectFlow(pub, "google", { ret: "https://taschen.example/" });
  assert.equal(f.frag.url, "https://taschen.example/");
  assert.match(f.frag.account, /^[0-9a-f]{32}$/);

  const hosts = await boot("hosts", connectEnv({ ALLOWED_HOSTS: "taschen.example" }));
  const st2 = await raw(hosts.port, "GET", `/api/connect/microsoft/start?return=${encodeURIComponent("https://taschen.example/")}`);
  assert.equal(st2.status, 302);
  assert.equal(new URL(st2.headers.location).searchParams.get("redirect_uri"), "https://taschen.example/api/connect/microsoft/callback");
  assert.equal((await raw(hosts.port, "GET", `/api/connect/microsoft/start?return=${encodeURIComponent("http://taschen.example/")}`)).status, 400, "nur https für ALLOWED_HOSTS");
});

test("start: kein Open Redirect – Rücksprung nur zu erlaubten Herkünften", async () => {
  const bad = [
    null,
    "",
    "https://evil.example/",
    "javascript:alert(1)",
    "data:text/html,<script>alert(1)</script>",
    "//evil.example/x",
    "/relativ",
    `${GH}.evil.example/`,
    "https://georgleomaser-bit.github.io@evil.example/",
    "https://user:pw@georgleomaser-bit.github.io/",
    "http://georgleomaser-bit.github.io/",
    "https://georgleomaser-bit.github.io:8443/",
    `https://evil.example/?next=${GH}`,
    `${GH}/${"x".repeat(2100)}`,
  ];
  for (const ret of bad) {
    const q = ret === null ? "" : `?return=${encodeURIComponent(ret)}`;
    const r = await raw(main.port, "GET", `/api/connect/google/start${q}`);
    assert.equal(r.status, 400, String(ret).slice(0, 80));
    assert.equal(r.headers.location, undefined);
    assert.match(r.data.msg, /Rücksprung/);
  }
  for (const ret of [APP_URL, `${GH}/anderer/pfad?x=1#alt`, `http://127.0.0.1:${main.port}/`]) assert.equal((await raw(main.port, "GET", `/api/connect/google/start?return=${encodeURIComponent(ret)}`)).status, 302, ret);
  // Unbekannter Anbieter, falsche Methoden
  assert.equal((await raw(main.port, "GET", `/api/connect/yahoo/start?return=${encodeURIComponent(APP_URL)}`)).status, 404);
  assert.equal((await raw(main.port, "POST", `/api/connect/google/start?return=${encodeURIComponent(APP_URL)}`)).status, 405);
  assert.equal((await call(main.base, "GET", "/api/connect/token")).status, 405);
  assert.equal((await call(main.base, "GET", "/api/connect/nichts")).status, 404);
});

// ---------- callback ----------
test("callback (Google): tauscht den Code mit Secret und code_verifier, speichert nur verschlüsselt, Fragment mit account/secret/email", async () => {
  const email = "papa.callback@gmail.com";
  const f = await connectFlow(main, "google", { email, ret: `${APP_URL}?ansicht=einstellungen#alt` });
  assert.ok(f.location.startsWith(`${APP_URL}?ansicht=einstellungen#connect=google&`), f.location);
  assert.ok(!f.location.includes("#alt"), "altes Fragment wird ersetzt");
  assert.equal(f.back.headers["referrer-policy"], "no-referrer");
  assert.match(f.back.headers["set-cookie"][0], /Max-Age=0/, "Cookie wird gelöscht");
  const fr = f.frag;
  assert.equal(fr.connect, "google");
  assert.match(fr.account, /^[0-9a-f]{32}$/);
  assert.match(fr.secret, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(fr.email, email);
  assert.match(f.location, /email=papa\.callback%40gmail\.com/);
  assert.equal(fr.error, undefined);

  // Beim Anbieter: Code-Tausch mit Client-Secret, passendem code_verifier und derselben redirect_uri
  const ex = mock.hits.filter((h) => h.path === "/google/token" && h.body.grant_type === "authorization_code").at(-1);
  assert.equal(ex.body.client_id, CREDS.google.id);
  assert.equal(ex.body.client_secret, CREDS.google.secret);
  assert.match(ex.body.code_verifier, /^[A-Za-z0-9_-]{43,128}$/);
  assert.equal(s256(ex.body.code_verifier), f.auth.searchParams.get("code_challenge"));
  assert.equal(ex.body.redirect_uri, f.auth.searchParams.get("redirect_uri"));
  assert.ok(mock.hits.some((h) => h.path === "/google/userinfo" && /^Bearer google-at-/.test(h.headers.authorization || "")), "E-Mail über userinfo");

  // connect.json: Konto mit Hash des Secrets und verschlüsseltem Refresh-Token – kein Klartext
  const rt = mock.issued.google.at(-1);
  const file = path.join(dataDir("main"), "connect.json");
  const text = fs.readFileSync(file, "utf8");
  const acc = JSON.parse(text).accounts[fr.account];
  assert.equal(acc.id, fr.account);
  assert.equal(acc.provider, "google");
  assert.equal(acc.email, email);
  assert.equal(acc.broken, false);
  assert.equal(acc.secretHash, sha(fr.secret));
  assert.equal(typeof acc.created, "number");
  assert.match(acc.scope, /gmail\.readonly/);
  assert.match(acc.refreshEnc, /^v1\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/);
  assert.ok(!text.includes(rt), "kein Klartext-Refresh-Token");
  assert.ok(!text.includes(fr.secret), "kein Klartext-Secret");
  assert.ok(!text.includes("google-at-"), "keine Access-Tokens auf der Platte");
  assert.equal(openToken(keyOf("main"), acc.refreshEnc, aad(fr.account, "google")), rt, "entschlüsselt zum Refresh-Token");
  if (process.platform !== "win32") {
    assert.equal(fs.statSync(file).mode & 0o077, 0, "connect.json nur für den Dienst lesbar");
    assert.equal(fs.statSync(path.join(dataDir("main"), "connect.key")).mode & 0o077, 0, "connect.key 0600");
  }

  // state gilt nur einmal
  const replay = await raw(main.port, "GET", f.cb.pathname + f.cb.search, { headers: { Cookie: f.jar } });
  assert.equal(replay.status, 400);
  assert.match(replay.headers["content-type"], /text\/html/);
  assert.match(replay.text, /abgelaufen/);
  // Unbekannter state
  assert.equal((await raw(main.port, "GET", `/api/connect/google/callback?code=x&state=${"A".repeat(32)}`)).status, 400);
  assert.equal((await raw(main.port, "GET", "/api/connect/google/callback?code=x")).status, 400);
});

test("callback: ohne das Cookie des startenden Browsers wird kein Konto angelegt", async () => {
  const before = Object.keys(accountsOf("main")).length;
  const f = await connectFlow(main, "google", { cookie: false });
  assert.match(f.frag.error, /anderen Browser/);
  assert.equal(f.frag.account, undefined);
  assert.equal(f.frag.secret, undefined);
  assert.equal(Object.keys(accountsOf("main")).length, before);
});

test("callback (Microsoft): E-Mail aus Graph /me (userPrincipalName), Code-Tausch mit Scope, Secret und code_verifier", async () => {
  const f = await connectFlow(main, "microsoft", { email: "Papa.Chef@firma.de" });
  assert.equal(f.frag.connect, "microsoft");
  assert.equal(f.frag.email, "Papa.Chef@firma.de");
  const ex = mock.hits.filter((h) => h.path === "/ms/common/oauth2/v2.0/token" && h.body.grant_type === "authorization_code").at(-1);
  assert.equal(ex.body.client_secret, CREDS.microsoft.secret);
  assert.equal(s256(ex.body.code_verifier), f.auth.searchParams.get("code_challenge"));
  assert.equal(ex.body.scope, MS_SCOPE);
  const me = mock.hits.filter((h) => h.path === "/graph/v1.0/me").at(-1);
  assert.match(me.headers.authorization, /^Bearer microsoft-at-/);
  assert.match(me.query.$select, /mail/);
  const acc = accountsOf("main")[f.frag.account];
  assert.equal(acc.provider, "microsoft");
  assert.ok(!JSON.stringify(acc).includes(mock.issued.microsoft.at(-1)));
});

test("callback: Fehler landen als verständliche deutsche Meldung im Fragment", async () => {
  const cases = [
    ["google", { deny: { error: "access_denied" } }, /^Anmeldung abgebrochen\.$/],
    ["google", { deny: { error: "admin_policy_enforced" } }, /Workspace-Administrator.*freizugeben/],
    ["microsoft", { deny: { error: "consent_required", error_description: "AADSTS65001: The user or administrator has not consented to use the application with ID '1111' named 'Arbeitstaschen'." } }, new RegExp(FIRM)],
    ["microsoft", { deny: { error: "access_denied", error_description: "AADSTS90094: The grant requires admin permission." } }, new RegExp(FIRM)],
    ["microsoft", { deny: { error: "access_denied", error_subcode: "cancel", error_description: "AADSTS65004: User declined to consent to access the app." } }, /^Anmeldung abgebrochen\..*IT um Freigabe/],
    ["microsoft", { codeError: { error: "invalid_grant", error_description: "AADSTS65001: The user or administrator has not consented to use the application." } }, new RegExp(FIRM)],
    ["microsoft", { deny: { error: "access_denied", error_description: "AADSTS50105: Your administrator has configured the application to block users unless they are specifically granted access." } }, /nicht freigeschaltet/],
    ["google", { noRefresh: true }, /myaccount\.google\.com.*Drittanbieter-Zugriff/],
    ["google", { deny: { error: "seltsam_neu" } }, /hat nicht geklappt \(seltsam_neu\)/],
  ];
  for (const [provider, opts, re] of cases) {
    const before = Object.keys(accountsOf("main")).length;
    const f = await connectFlow(main, provider, { opts });
    assert.equal(f.frag.url, APP_URL);
    assert.equal(f.frag.connect, provider);
    assert.match(f.frag.error, re, JSON.stringify(opts));
    assert.equal(f.frag.account, undefined);
    assert.equal(f.frag.secret, undefined);
    assert.ok(!/AADSTS\d+:/.test(f.frag.error), "keine rohe Fehlerbeschreibung");
    assert.equal(Object.keys(accountsOf("main")).length, before, "kein Konto angelegt");
  }
});

// ---------- token ----------
test("token: liefert Access-Token, cacht es im Speicher und prüft das Secret (403)", async () => {
  const { frag: g } = await connectFlow(main, "google");
  const seen = mock.refreshSeen.google.length;
  const t0 = Date.now();
  const t1 = await token(main, g.account, g.secret);
  assert.equal(t1.status, 200, t1.text);
  assert.equal(t1.data.ok, true);
  assert.equal(t1.data.provider, "google");
  assert.equal(t1.data.email, g.email);
  assert.match(t1.data.access_token, /^google-at-/);
  assert.ok(t1.data.expires_at > t0 + 55 * 60000 && t1.data.expires_at <= Date.now() + 3600 * 1000, "expires_at in ms");
  assert.match(t1.data.scope, /calendar\.events/);
  assert.equal(t1.headers.get("cache-control"), "no-store");
  // Das Access-Token aus dem Code-Tausch reicht noch – kein Refresh nötig, auch nicht beim zweiten Mal
  const t2 = await token(main, g.account, g.secret);
  assert.equal(t2.data.access_token, t1.data.access_token);
  assert.equal(mock.refreshSeen.google.length, seen, "aus dem Speicher");
  // Falsches Secret → 403, kaputte Eingaben → 400, unbekanntes Konto → 410
  const bad = await token(main, g.account, b64u(crypto.randomBytes(32)));
  assert.equal(bad.status, 403);
  assert.equal(bad.data.ok, false);
  assert.equal(bad.data.access_token, undefined);
  assert.equal((await token(main, g.account, "kurz")).status, 400);
  assert.equal((await token(main, "xyz", g.secret)).status, 400);
  assert.equal((await call(main.base, "POST", "/api/connect/token", { json: { account: g.account } })).status, 400);
  const gone = await token(main, crypto.randomBytes(16).toString("hex"), g.secret);
  assert.equal(gone.status, 410);
  assert.match(gone.data.msg, /neu verbinden/);
  assert.equal((await call(main.base, "POST", "/api/connect/token", { body: JSON.stringify({ account: g.account, secret: g.secret }), headers: { "Content-Type": "text/plain" } })).status, 415);
  // CORS wie bei den übrigen POST-Endpunkten
  const cors = await token(main, g.account, g.secret, { Origin: GH });
  assert.equal(cors.status, 200);
  assert.equal(cors.headers.get("access-control-allow-origin"), GH);
  assert.equal((await token(main, g.account, g.secret, { Origin: "https://evil.example" })).status, 403);
  const pre = await raw(main.port, "OPTIONS", "/api/connect/token", { headers: { Origin: GH, "Access-Control-Request-Method": "POST", "Access-Control-Request-Headers": "content-type" } });
  assert.equal(pre.status, 204);
  assert.equal(pre.headers["access-control-allow-origin"], GH);
});

test("token: nach Neustart einmal erneuern, dann aus dem Speicher (Google)", async () => {
  const s1 = await boot("restart-g", connectEnv());
  const { frag: g } = await connectFlow(s1, "google");
  await s1.close();
  const s2 = await boot("restart-g", connectEnv());
  const seen = mock.refreshSeen.google.length;
  const t1 = await token(s2, g.account, g.secret);
  assert.equal(t1.status, 200, t1.text);
  assert.equal(mock.refreshSeen.google.length, seen + 1, "einmal erneuert");
  assert.equal(mock.refreshSeen.google.at(-1), mock.issued.google.at(-1));
  const r = mock.hits.filter((h) => h.path === "/google/token" && h.body.grant_type === "refresh_token").at(-1);
  assert.equal(r.body.client_secret, CREDS.google.secret);
  const t2 = await token(s2, g.account, g.secret);
  assert.equal(t2.data.access_token, t1.data.access_token);
  assert.equal(mock.refreshSeen.google.length, seen + 1, "danach aus dem Speicher");
});

test("token: invalid_grant → Konto broken → 410 mit deutscher Meldung", async () => {
  // Kurzlebiges Access-Token aus dem Code-Tausch → der erste Abruf muss erneuern
  const { frag: g } = await connectFlow(main, "google", { email: "papa.abgelaufen@gmail.com", opts: { codeExpires: 60 } });
  mock.refresh.delete(mock.issued.google.at(-1)); // z. B. Passwort geändert oder Zugriff entzogen
  const r = await token(main, g.account, g.secret);
  assert.equal(r.status, 410);
  assert.equal(r.data.ok, false);
  assert.equal(r.data.msg, "Die Verbindung zu papa.abgelaufen@gmail.com ist abgelaufen – bitte neu verbinden.");
  assert.equal(accountsOf("main")[g.account].broken, true);
  const seen = mock.refreshSeen.google.length;
  assert.equal((await token(main, g.account, g.secret)).status, 410);
  assert.equal(mock.refreshSeen.google.length, seen, "kaputtes Konto fragt den Anbieter nicht mehr");
  // Falsches Secret bleibt 403 – auch bei kaputtem Konto
  assert.equal((await token(main, g.account, b64u(crypto.randomBytes(32)))).status, 403);
});

test("token: Microsoft rotiert Refresh-Tokens – der neue wird verschlüsselt gespeichert und überlebt den Neustart", async () => {
  const s1 = await boot("ms-rotation", connectEnv());
  const { frag: m } = await connectFlow(s1, "microsoft", { opts: { codeExpires: 60 } });
  const rt1 = mock.issued.microsoft.at(-1);
  const t1 = await token(s1, m.account, m.secret);
  assert.equal(t1.status, 200, t1.text);
  assert.equal(t1.data.provider, "microsoft");
  assert.equal(mock.refreshSeen.microsoft.at(-1), rt1);
  const ex = mock.hits.filter((h) => h.path === "/ms/common/oauth2/v2.0/token" && h.body.grant_type === "refresh_token").at(-1);
  assert.equal(ex.body.client_secret, CREDS.microsoft.secret);
  assert.equal(ex.body.scope, MS_SCOPE);
  const rt2 = mock.issued.microsoft.at(-1);
  assert.notEqual(rt2, rt1);
  let acc = accountsOf("ms-rotation")[m.account];
  assert.equal(openToken(keyOf("ms-rotation"), acc.refreshEnc, aad(m.account, "microsoft")), rt2, "neuer Refresh-Token gespeichert");
  // Access-Token gilt nur 2 Min. (< 5 Min. Puffer) → nächster Abruf erneuert mit dem neuen Refresh-Token
  const t2 = await token(s1, m.account, m.secret);
  assert.equal(t2.status, 200);
  assert.notEqual(t2.data.access_token, t1.data.access_token);
  assert.equal(mock.refreshSeen.microsoft.at(-1), rt2);
  const rt3 = mock.issued.microsoft.at(-1);
  const text = fs.readFileSync(path.join(dataDir("ms-rotation"), "connect.json"), "utf8");
  for (const rt of [rt1, rt2, rt3]) assert.ok(!text.includes(rt), "kein Klartext-Refresh-Token");
  acc = JSON.parse(text).accounts[m.account];
  assert.equal(openToken(keyOf("ms-rotation"), acc.refreshEnc, aad(m.account, "microsoft")), rt3);
  assert.equal(typeof acc.rotated, "number");
  // Neustart: der zuletzt gespeicherte Refresh-Token wird benutzt (die Attrappe lehnt alte ab)
  await s1.close();
  const s2 = await boot("ms-rotation", connectEnv());
  const t3 = await token(s2, m.account, m.secret);
  assert.equal(t3.status, 200, t3.text);
  assert.equal(mock.refreshSeen.microsoft.at(-1), rt3);
});

test("token: Firmenrichtlinie entzieht den Zugriff (Microsoft) → 410 mit Hinweis auf die IT", async () => {
  const { frag: m } = await connectFlow(main, "microsoft", { email: "papa.it@firma.de", opts: { codeExpires: 60 } });
  mock.opts.microsoft.refreshError = { status: 400, body: { error: "invalid_grant", error_description: "AADSTS65001: The user or administrator has not consented to use the application." } };
  try {
    const r = await token(main, m.account, m.secret);
    assert.equal(r.status, 410);
    assert.match(r.data.msg, /^Die Verbindung zu papa\.it@firma\.de ist abgelaufen – bitte neu verbinden\./);
    assert.match(r.data.msg, new RegExp(FIRM));
  } finally {
    delete mock.opts.microsoft.refreshError;
  }
});

test("token: Anbieter nicht erreichbar oder Server-Zugangsdaten falsch → 502, Konto bleibt heil", async () => {
  const { frag: g } = await connectFlow(main, "google", { opts: { codeExpires: 60 } });
  mock.opts.google.refreshError = { status: 503, body: { error: "temporarily_unavailable" } };
  try {
    const r = await token(main, g.account, g.secret);
    assert.equal(r.status, 502);
    assert.match(r.data.msg, /Google ist gerade nicht erreichbar/);
    mock.opts.google.refreshError = { status: 401, body: { error: "invalid_client" } };
    const c = await token(main, g.account, g.secret);
    assert.equal(c.status, 502);
    assert.match(c.data.msg, /Zugangsdaten des Servers für Google/);
  } finally {
    delete mock.opts.google.refreshError;
  }
  assert.equal(accountsOf("main")[g.account].broken, false);
  assert.equal((await token(main, g.account, g.secret)).status, 200);
});

test("Dasselbe Konto erneut verbunden: der neue Eintrag ersetzt den alten", async () => {
  const email = "papa.doppelt@gmail.com";
  const a = (await connectFlow(main, "google", { email })).frag;
  const b = (await connectFlow(main, "google", { email: email.toUpperCase() })).frag;
  assert.notEqual(a.account, b.account);
  const accs = accountsOf("main");
  assert.equal(accs[a.account], undefined);
  assert.ok(accs[b.account]);
  assert.equal((await token(main, a.account, a.secret)).status, 410);
  assert.equal((await token(main, b.account, b.secret)).status, 200);
});

// ---------- remove ----------
test("remove (Google): widerruft beim Anbieter und löscht das Konto; falsches Secret → 403", async () => {
  const { frag: g } = await connectFlow(main, "google");
  const rt = mock.issued.google.at(-1);
  const wrong = await remove(main, g.account, b64u(crypto.randomBytes(32)));
  assert.equal(wrong.status, 403);
  assert.ok(accountsOf("main")[g.account], "bleibt bei falschem Secret");
  assert.ok(!mock.revoked.includes(rt));
  const r = await remove(main, g.account, g.secret);
  assert.equal(r.status, 200);
  assert.deepEqual(r.data, { ok: true, revoked: true });
  assert.ok(mock.revoked.includes(rt), "Refresh-Token beim Anbieter widerrufen");
  const hit = mock.hits.filter((h) => h.path === "/google/revoke").at(-1);
  assert.equal(hit.method, "POST");
  assert.equal(hit.query.token, undefined, "Token im Körper statt in der Adresse");
  assert.equal(accountsOf("main")[g.account], undefined, "aus connect.json gelöscht");
  assert.equal((await token(main, g.account, g.secret)).status, 410);
  assert.deepEqual((await remove(main, g.account, g.secret)).data, { ok: true, revoked: false }, "zweites Mal: nichts mehr da");
  assert.equal((await call(main.base, "POST", "/api/connect/remove", { json: { account: g.account, secret: g.secret }, headers: { Origin: "https://evil.example" } })).status, 403);
});

test("remove (Microsoft): kein Widerruf, nur löschen", async () => {
  const { frag: m } = await connectFlow(main, "microsoft");
  const revokes = mock.revoked.length;
  const r = await remove(main, m.account, m.secret);
  assert.deepEqual(r.data, { ok: true, revoked: false });
  assert.equal(mock.revoked.length, revokes);
  assert.equal(accountsOf("main")[m.account], undefined);
  assert.equal((await token(main, m.account, m.secret)).status, 410);
});

// ---------- Schlüssel ----------
test("CONNECT_KEY aus der Umgebung (keine Schlüsseldatei); anderer Schlüssel → Konto muss neu verbunden werden", async () => {
  const key1 = crypto.randomBytes(32).toString("hex");
  const s1 = await boot("envkey", connectEnv({ CONNECT_KEY: key1 }));
  const { frag: g } = await connectFlow(s1, "google", { opts: { codeExpires: 60 } });
  assert.equal(fs.existsSync(path.join(dataDir("envkey"), "connect.key")), false);
  const acc = accountsOf("envkey")[g.account];
  assert.equal(openToken(parseConnectKey(key1), acc.refreshEnc, aad(g.account, "google")), mock.issued.google.at(-1));
  assert.equal((await token(s1, g.account, g.secret)).status, 200);
  await s1.close();
  const s2 = await boot("envkey", connectEnv({ CONNECT_KEY: crypto.randomBytes(32).toString("base64") }));
  const r = await token(s2, g.account, g.secret);
  assert.equal(r.status, 410);
  assert.match(r.data.msg, /abgelaufen – bitte neu verbinden/);
});

test("Verschlüsselung der Refresh-Tokens (AES-256-GCM) und Schlüsselformat", () => {
  const key = crypto.randomBytes(32);
  const box = sealToken(key, "1//geheimer-refresh-token", "taschen-connect:abc:google");
  assert.ok(!box.includes("geheimer"));
  assert.notEqual(sealToken(key, "1//geheimer-refresh-token", "taschen-connect:abc:google"), box, "zufälliger IV");
  assert.equal(openToken(key, box, "taschen-connect:abc:google"), "1//geheimer-refresh-token");
  assert.throws(() => openToken(key, box, "taschen-connect:xyz:google"), "an Konto gebunden");
  assert.throws(() => openToken(crypto.randomBytes(32), box, "taschen-connect:abc:google"), "falscher Schlüssel");
  const [v, iv, ct, tag] = box.split(".");
  const flipped = Buffer.from(ct, "base64url");
  flipped[0] ^= 1;
  assert.throws(() => openToken(key, [v, iv, b64u(flipped), tag].join("."), "taschen-connect:abc:google"), "manipuliert");
  assert.deepEqual(parseConnectKey(key.toString("hex")), key);
  assert.deepEqual(parseConnectKey(key.toString("base64")), key);
  assert.deepEqual(parseConnectKey(key.toString("base64url")), key);
  assert.equal(parseConnectKey(crypto.randomBytes(16).toString("hex")), null);
  assert.equal(parseConnectKey("kein schlüssel"), null);
  assert.equal(parseConnectKey(""), null);
});

test("Fehlertexte für Firmenkonten (connectErrorText)", () => {
  assert.match(connectErrorText("microsoft", "invalid_request", "AADSTS90094: The grant requires admin permission."), new RegExp(FIRM));
  assert.match(connectErrorText("microsoft", "access_denied", "AADSTS900941: Administrator consent is required."), new RegExp(FIRM));
  assert.match(connectErrorText("microsoft", "consent_required", ""), new RegExp(FIRM));
  assert.match(connectErrorText("microsoft", "interaction_required", "AADSTS53003: Access has been blocked by Conditional Access policies."), /Sicherheitsregeln deiner Firma/);
  assert.match(connectErrorText("microsoft", "invalid_client", "AADSTS7000222: The provided client secret keys are expired."), /Client-Secret.*abgelaufen/);
  assert.match(connectErrorText("microsoft", "invalid_request", "AADSTS50194: Application is not configured as a multi-tenant application."), /persönliche Microsoft-Konten/);
  assert.equal(connectErrorText("google", "access_denied"), "Anmeldung abgebrochen.");
  assert.match(connectErrorText("google", "admin_policy_enforced"), /Workspace-Administrator/);
  assert.match(connectErrorText("google", "consent_required"), /Google hat nicht geklappt/, "Microsoft-Text nur für Microsoft");
  assert.match(connectErrorText("google", "temporarily_unavailable"), /nicht erreichbar/);
  // Codes werden für die Meldung bereinigt
  assert.equal(connectErrorText("microsoft", "<script>", "AADSTS99999: x"), "Die Anmeldung bei Microsoft hat nicht geklappt (script AADSTS99999).");
});

// ---------- Ratenbegrenzung ----------
test("Ratenbegrenzung für start, callback, token und remove", async () => {
  const s = await boot("rate", connectEnv({ TASCHEN_RATE_CONNECT: "3" }));
  const start3 = () => raw(s.port, "GET", `/api/connect/google/start?return=${encodeURIComponent(APP_URL)}`);
  for (let i = 0; i < 3; i++) assert.equal((await start3()).status, 302);
  const limited = await start3();
  assert.equal(limited.status, 429);
  assert.ok(+limited.headers["retry-after"] > 0);
  for (let i = 0; i < 3; i++) assert.equal((await raw(s.port, "GET", `/api/connect/google/callback?state=${"A".repeat(32)}`)).status, 400);
  assert.equal((await raw(s.port, "GET", `/api/connect/google/callback?state=${"A".repeat(32)}`)).status, 429);
  // Pro Konto
  const acc = crypto.randomBytes(16).toString("hex");
  const sec = b64u(crypto.randomBytes(32));
  for (let i = 0; i < 3; i++) assert.equal((await token(s, acc, sec)).status, 410);
  assert.equal((await token(s, acc, sec)).status, 429);
  for (let i = 0; i < 3; i++) assert.equal((await remove(s, crypto.randomBytes(16).toString("hex"), sec)).status, 200);
  assert.equal((await remove(s, crypto.randomBytes(16).toString("hex"), sec)).status, 429);
});

// ---------- Logs ----------
test("Logs enthalten keine Tokens, Secrets, Codes oder E-Mail-Adressen (eigener Prozess)", async () => {
  const dir = dataDir("proc");
  const env = { PATH: process.env.PATH, PORT: "0", HOST: "127.0.0.1", DATA_DIR: dir, ...connectEnv() };
  const child = spawn(process.execPath, [SERVER_FILE], { env, stdio: ["ignore", "pipe", "pipe"] });
  let out = "";
  child.stdout.on("data", (c) => (out += c));
  child.stderr.on("data", (c) => (out += c));
  try {
    const port = +(await until(() => /läuft auf http:\/\/127\.0\.0\.1:(\d+)/.exec(out)?.[1], 8000, "Startmeldung"));
    assert.match(out, /Konten: Google \+ Microsoft/);
    const s = { port, base: `http://127.0.0.1:${port}` };
    const issued = { google: mock.issued.google.length, microsoft: mock.issued.microsoft.length };
    const secrets = [];
    const flows = [];
    // Google: verbinden und Token holen
    const g = await connectFlow(s, "google", { email: "geheim.papa@gmail.com" });
    flows.push(g);
    assert.equal((await token(s, g.frag.account, g.frag.secret)).status, 200);
    // Google: Refresh-Token beim Anbieter ungültig → invalid_grant → 410
    const g2 = await connectFlow(s, "google", { email: "geheim.oma@gmail.com", opts: { codeExpires: 60 } });
    flows.push(g2);
    mock.refresh.delete(mock.issued.google.at(-1));
    assert.equal((await token(s, g2.frag.account, g2.frag.secret)).status, 410);
    // Microsoft: verbinden, Token mit Rotation
    const m = await connectFlow(s, "microsoft", { email: "geheim.chef@firma.de", opts: { codeExpires: 60 } });
    flows.push(m);
    assert.equal((await token(s, m.frag.account, m.frag.secret)).status, 200);
    // Fehlerfall mit E-Mail-Adresse in der Fehlerbeschreibung
    await connectFlow(s, "microsoft", { opts: { deny: { error: "access_denied", error_description: "AADSTS50020: User account 'fremd.konto@andere-firma.de' from identity provider does not exist in tenant." } } });
    assert.equal((await remove(s, m.frag.account, m.frag.secret)).status, 200);
    assert.equal((await remove(s, g.frag.account, g.frag.secret)).status, 200);
    const code = new Promise((r) => child.on("exit", r));
    child.kill("SIGTERM");
    assert.equal(await code, 0);
    for (const f of flows) secrets.push(f.frag.secret, f.frag.account, f.email, ...f.cb.searchParams.values());
    secrets.push(...mock.issued.google.slice(issued.google), ...mock.issued.microsoft.slice(issued.microsoft), CREDS.google.secret, CREDS.microsoft.secret, "fremd.konto@andere-firma.de");
    assert.equal(mock.issued.microsoft.length - issued.microsoft, 2, "Rotation stattgefunden");
    for (const [at] of mock.access) secrets.push(at);
    for (const x of secrets.filter((v) => v && v.length > 6)) assert.ok(!out.includes(x), `Log enthält Vertrauliches: ${x.slice(0, 12)}…`);
    assert.ok(!/@(gmail\.com|firma\.de|andere-firma\.de)/.test(out), "keine E-Mail-Adressen");
    assert.match(out, /Konto verbunden \(Google\)/);
    assert.match(out, /Token-Erneuerung fehlgeschlagen \(400 invalid_grant\)/);
  } finally {
    if (child.exitCode === null) child.kill("SIGKILL");
  }
});
