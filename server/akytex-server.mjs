// AKYTEX-Server: liefert die Website aus und betreibt die Community-API für Clips
// (Videos hochladen und abspielen, Likes, Kommentare, Meldungen, Moderation).
// Ohne Abhängigkeiten, nur Node.js ≥ 20. Start: node server/akytex-server.mjs  (Anleitung: SERVER.md)
//
// Umgebungsvariablen:
//   PORT         Port (Standard 8080)
//   DATA_DIR     Ordner für Datenbank und Videos (Standard ./data)
//   ADMIN_TOKEN  Geheimes Passwort für die Moderation (mindestens 24 Zeichen, Pflicht für /api/admin)
//   TRUST_PROXY  "1", wenn der Server hinter Cloudflare/Nginx läuft (echte IP aus X-Forwarded-For)
import http from "node:http";
import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const PORT = +process.env.PORT || 8080;
const DATA = path.resolve(process.env.DATA_DIR || path.join(ROOT, "data"));
const VIDEOS = path.join(DATA, "videos");
const DB_FILE = path.join(DATA, "db.json");
const ADMIN_TOKEN = process.env.ADMIN_TOKEN || "";
const TRUST_PROXY = process.env.TRUST_PROXY === "1";

const MAX_VIDEO = 60 * 1024 * 1024;
const MAX_JSON = 16 * 1024;
const UPLOADS_PER_DAY = 10;
const HIDE_AFTER_REPORTS = 3;
const PAGE = 20;

// ---------- Datenbank (JSON-Datei, atomar geschrieben) ----------
fs.mkdirSync(VIDEOS, { recursive: true });
let db = { users: {}, clips: {}, comments: {}, likes: {}, reports: {} };
try {
  db = { ...db, ...JSON.parse(fs.readFileSync(DB_FILE, "utf8")) };
} catch (_) {
  /* neue Datenbank */
}
let saveTimer = null;
function save() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(async () => {
    const tmp = DB_FILE + ".tmp";
    await fsp.writeFile(tmp, JSON.stringify(db));
    await fsp.rename(tmp, DB_FILE);
  }, 200);
}
const id = (n = 12) => crypto.randomBytes(n).toString("base64url");
const sha = (s) => crypto.createHash("sha256").update(s).digest("hex");
const now = () => Date.now();

// ---------- Schutz: Rate-Limits pro IP ----------
const buckets = new Map();
function limited(key, max, windowMs) {
  const t = now();
  const b = buckets.get(key) || { n: 0, reset: t + windowMs };
  if (t > b.reset) Object.assign(b, { n: 0, reset: t + windowMs });
  b.n++;
  buckets.set(key, b);
  return b.n > max;
}
setInterval(() => {
  const t = now();
  for (const [k, b] of buckets) if (t > b.reset) buckets.delete(k);
}, 60000).unref();
const ipOf = (req) => (TRUST_PROXY && (req.headers["cf-connecting-ip"] || String(req.headers["x-forwarded-for"] || "").split(",")[0].trim())) || req.socket.remoteAddress || "?";

// ---------- Hilfen ----------
const SECURITY = {
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Permissions-Policy": "camera=(), geolocation=(), payment=()",
  "Cross-Origin-Opener-Policy": "same-origin",
  "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data: blob:; media-src 'self' blob:; connect-src 'self'; worker-src 'self'; manifest-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'",
};
function send(res, status, body, headers = {}) {
  const json = typeof body !== "string" && !Buffer.isBuffer(body);
  res.writeHead(status, { ...SECURITY, "Cache-Control": "no-store", ...(json ? { "Content-Type": "application/json; charset=utf-8" } : {}), ...headers });
  res.end(json ? JSON.stringify(body) : body);
}
const fail = (res, status, msg) => send(res, status, { ok: false, msg });
async function readJson(req) {
  if (!/^application\/json/.test(req.headers["content-type"] || "")) throw Object.assign(new Error("JSON erwartet."), { status: 415 });
  let size = 0;
  const chunks = [];
  for await (const c of req) {
    size += c.length;
    if (size > MAX_JSON) throw Object.assign(new Error("Anfrage zu groß."), { status: 413 });
    chunks.push(c);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
  } catch (_) {
    throw Object.assign(new Error("Ungültiges JSON."), { status: 400 });
  }
}
// Text säubern: Steuerzeichen raus, Länge begrenzen (HTML-Escaping macht der Client beim Anzeigen)
const clean = (s, max) =>
  String(s ?? "")
    .replace(/[\u0000-\u001f\u007f‪-‮⁦-⁩]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, max);
const HANDLE = /^[a-z0-9._]{3,20}$/;
function uniqueHandle(want) {
  let base = clean(want, 20).toLowerCase().replace(/[^a-z0-9._]/g, "").slice(0, 16);
  if (base.length < 3) base = "trader";
  const taken = new Set(Object.values(db.users).map((u) => u.handle));
  if (!taken.has(base) && !/^(akytex|admin|support|official)/.test(base)) return base;
  for (let i = 0; i < 50; i++) {
    const h = `${base.slice(0, 15)}${Math.floor(1000 + Math.random() * 9000)}`;
    if (!taken.has(h)) return h;
  }
  return "user" + id(4).toLowerCase().replace(/[^a-z0-9]/g, "");
}
function userOf(req) {
  const m = /^Bearer ([A-Za-z0-9_-]{20,})$/.exec(req.headers.authorization || "");
  if (!m) return null;
  const h = sha(m[1]);
  const u = Object.values(db.users).find((x) => x.tokenHash === h);
  return u && !u.banned ? u : null;
}
function isAdmin(req) {
  if (ADMIN_TOKEN.length < 24) return false;
  const m = /^Bearer (.+)$/.exec(req.headers.authorization || "");
  if (!m) return false;
  const a = Buffer.from(sha(m[1]));
  const b = Buffer.from(sha(ADMIN_TOKEN));
  return crypto.timingSafeEqual(a, b);
}
function clipView(c, me) {
  const u = db.users[c.author];
  return {
    id: c.id,
    author: c.author,
    handle: u?.handle || "gelöscht",
    sym: c.sym,
    caption: c.caption,
    tags: c.tags,
    created: c.created,
    likes: Object.keys(db.likes[c.id] || {}).length,
    liked: !!(me && db.likes[c.id]?.[me.id]),
    comments: (db.comments[c.id] || []).length,
    mine: !!(me && c.author === me.id),
    type: c.type,
  };
}
const visible = (c) => !c.hidden && !c.deleted && !db.users[c.author]?.banned;

// Videos anhand der Datei-Signatur prüfen, nicht nur am angegebenen Typ
function sniffVideo(buf) {
  if (buf.length >= 12 && buf.toString("latin1", 4, 8) === "ftyp") return buf.toString("latin1", 8, 10) === "qt" ? "video/quicktime" : "video/mp4";
  if (buf.length >= 4 && buf.readUInt32BE(0) === 0x1a45dfa3) return "video/webm";
  return null;
}

// ---------- API ----------
async function api(req, res, url) {
  const ip = ipOf(req);
  const write = req.method !== "GET" && req.method !== "HEAD";
  if (limited("all:" + ip, 300, 60000)) return fail(res, 429, "Zu viele Anfragen. Bitte kurz warten.");
  if (write && limited("w:" + ip, 40, 60000)) return fail(res, 429, "Zu viele Aktionen. Bitte kurz warten.");
  // Schreibende Anfragen nur von der eigenen Seite (Schutz gegen fremde Webseiten)
  if (write && req.headers.origin) {
    let host = "";
    try {
      host = new URL(req.headers.origin).host;
    } catch (_) {
      /* ungültig */
    }
    const own = [req.headers.host, TRUST_PROXY && req.headers["x-forwarded-host"]].filter(Boolean);
    if (!own.includes(host)) return fail(res, 403, "Fremde Herkunft.");
  }
  const p = url.pathname.replace(/^\/api/, "");
  const me = userOf(req);
  let m;

  if (p === "/health") return send(res, 200, { ok: true, service: "akytex", clips: Object.values(db.clips).filter(visible).length });

  // Anonymes Konto: Handle + geheimer Schlüssel (nur als Hash gespeichert)
  if (p === "/session" && req.method === "POST") {
    if (limited("session:" + ip, 5, 3600000)) return fail(res, 429, "Zu viele neue Konten von dieser Verbindung.");
    const b = await readJson(req);
    const token = id(32);
    const u = { id: id(8), handle: uniqueHandle(b.handle), tokenHash: sha(token), created: now(), uploads: [] };
    db.users[u.id] = u;
    save();
    return send(res, 201, { ok: true, token, user: { id: u.id, handle: u.handle } });
  }
  if (p === "/me" && req.method === "GET") return me ? send(res, 200, { ok: true, user: { id: me.id, handle: me.handle } }) : fail(res, 401, "Nicht angemeldet.");
  if (p === "/me" && req.method === "PATCH") {
    if (!me) return fail(res, 401, "Nicht angemeldet.");
    const b = await readJson(req);
    const h = clean(b.handle, 20).toLowerCase();
    if (!HANDLE.test(h)) return fail(res, 400, "Name: 3–20 Zeichen, nur a–z, 0–9, Punkt und Unterstrich.");
    if (Object.values(db.users).some((u) => u.handle === h && u.id !== me.id) || /^(akytex|admin|support|official)/.test(h)) return fail(res, 409, "Dieser Name ist schon vergeben.");
    me.handle = h;
    save();
    return send(res, 200, { ok: true, user: { id: me.id, handle: me.handle } });
  }
  // Konto und alle eigenen Inhalte löschen (DSGVO Art. 17)
  if (p === "/me" && req.method === "DELETE") {
    if (!me) return fail(res, 401, "Nicht angemeldet.");
    for (const c of Object.values(db.clips)) if (c.author === me.id) await removeClip(c);
    for (const list of Object.values(db.comments)) for (let i = list.length - 1; i >= 0; i--) if (list[i].author === me.id) list.splice(i, 1);
    for (const l of Object.values(db.likes)) delete l[me.id];
    delete db.users[me.id];
    save();
    return send(res, 200, { ok: true });
  }

  // Feed
  if (p === "/clips" && req.method === "GET") {
    const tag = clean(url.searchParams.get("tag"), 40).toLowerCase();
    const author = clean(url.searchParams.get("author"), 20);
    const before = +url.searchParams.get("before") || Infinity;
    const list = Object.values(db.clips)
      .filter((c) => visible(c) && c.created < before && (!tag || c.tags.includes(tag)) && (!author || c.author === author))
      .sort((a, b) => b.created - a.created)
      .slice(0, PAGE)
      .map((c) => clipView(c, me));
    return send(res, 200, { ok: true, clips: list });
  }

  // Upload: Rohdaten des Videos im Body, Angaben in Kopfzeilen
  if (p === "/clips" && req.method === "POST") {
    if (!me) return fail(res, 401, "Nicht angemeldet.");
    const len = +req.headers["content-length"] || 0;
    if (!len) return fail(res, 411, "Größe fehlt.");
    if (len > MAX_VIDEO) return fail(res, 413, "Das Video ist größer als 60 MB.");
    me.uploads = (me.uploads || []).filter((t) => now() - t < 86400000);
    if (me.uploads.length >= UPLOADS_PER_DAY) return fail(res, 429, `Maximal ${UPLOADS_PER_DAY} Clips pro Tag.`);
    if (req.headers["x-rights"] !== "1") return fail(res, 400, "Bitte bestätige die Rechte am Video.");
    let caption;
    try {
      caption = clean(decodeURIComponent(req.headers["x-caption"] || ""), 150);
    } catch (_) {
      return fail(res, 400, "Beschreibung ungültig.");
    }
    const sym = clean(req.headers["x-symbol"], 8).toUpperCase().replace(/[^A-Z0-9.]/g, "");
    if (!caption) return fail(res, 400, "Bitte eine Beschreibung angeben.");
    const cid = id(9);
    const tmp = path.join(VIDEOS, cid + ".part");
    const out = fs.createWriteStream(tmp, { flags: "wx" });
    let size = 0;
    let head = Buffer.alloc(0);
    try {
      for await (const c of req) {
        size += c.length;
        if (size > MAX_VIDEO) throw Object.assign(new Error("Das Video ist größer als 60 MB."), { status: 413 });
        if (head.length < 16) head = Buffer.concat([head, c.subarray(0, 16)]);
        if (!out.write(c)) await new Promise((r) => out.once("drain", r));
      }
      await new Promise((r, j) => out.end((e) => (e ? j(e) : r())));
      const type = sniffVideo(head);
      if (!type) throw Object.assign(new Error("Bitte ein MP4-, WebM- oder MOV-Video hochladen."), { status: 415 });
      await fsp.rename(tmp, path.join(VIDEOS, cid));
      const tags = [...new Set((caption.match(/#[\p{L}\p{N}_]{2,30}/gu) || []).map((t) => t.toLowerCase()))].slice(0, 6);
      if (sym) tags.unshift("#" + sym.toLowerCase());
      const clip = { id: cid, author: me.id, sym: sym || "AKYTEX", caption, tags: [...new Set(tags)], created: now(), size, type, reports: 0 };
      db.clips[cid] = clip;
      me.uploads.push(now());
      save();
      return send(res, 201, { ok: true, clip: clipView(clip, me) });
    } catch (e) {
      out.destroy();
      await fsp.rm(tmp, { force: true });
      throw e;
    }
  }

  // Video abspielen (mit Range-Anfragen für Vorspulen und iOS)
  if ((m = /^\/videos\/([A-Za-z0-9_-]{6,20})$/.exec(p)) && (req.method === "GET" || req.method === "HEAD")) {
    const c = db.clips[m[1]];
    if (!c || !visible(c)) return fail(res, 404, "Nicht gefunden.");
    const file = path.join(VIDEOS, c.id);
    const size = (await fsp.stat(file).catch(() => null))?.size;
    if (!size) return fail(res, 404, "Nicht gefunden.");
    const r = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range || "");
    const base = { ...SECURITY, "Content-Type": c.type, "Accept-Ranges": "bytes", "Cache-Control": "public, max-age=86400", "Content-Disposition": "inline" };
    if (r) {
      let start = r[1] ? +r[1] : size - +r[2];
      let end = r[1] && r[2] ? Math.min(+r[2], size - 1) : size - 1;
      if (!(start >= 0 && start <= end && end < size)) return send(res, 416, "", { "Content-Range": `bytes */${size}` });
      res.writeHead(206, { ...base, "Content-Range": `bytes ${start}-${end}/${size}`, "Content-Length": end - start + 1 });
      if (req.method === "HEAD") return res.end();
      return fs.createReadStream(file, { start, end }).pipe(res);
    }
    res.writeHead(200, { ...base, "Content-Length": size });
    if (req.method === "HEAD") return res.end();
    return fs.createReadStream(file).pipe(res);
  }

  if ((m = /^\/clips\/([A-Za-z0-9_-]{6,20})(?:\/(like|comments|report))?$/.exec(p))) {
    const c = db.clips[m[1]];
    if (!c || c.deleted) return fail(res, 404, "Clip nicht gefunden.");
    const action = m[2];
    if (!action && req.method === "DELETE") {
      if (!me || me.id !== c.author) return fail(res, 403, "Nur eigene Clips können gelöscht werden.");
      await removeClip(c);
      save();
      return send(res, 200, { ok: true });
    }
    if (!visible(c)) return fail(res, 404, "Clip nicht gefunden.");
    if (action === "comments" && req.method === "GET") {
      const list = (db.comments[c.id] || []).filter((x) => !db.users[x.author]?.banned).map((x) => ({ id: x.id, who: db.users[x.author]?.handle || "gelöscht", text: x.text, ts: x.ts, mine: !!(me && x.author === me.id) }));
      return send(res, 200, { ok: true, comments: list });
    }
    if (!me) return fail(res, 401, "Nicht angemeldet.");
    if (action === "like" && req.method === "POST") {
      const l = (db.likes[c.id] ||= {});
      if (l[me.id]) delete l[me.id];
      else l[me.id] = 1;
      save();
      return send(res, 200, { ok: true, liked: !!l[me.id], likes: Object.keys(l).length });
    }
    if (action === "comments" && req.method === "POST") {
      if (limited("cmt:" + me.id, 10, 60000)) return fail(res, 429, "Bitte etwas langsamer kommentieren.");
      const b = await readJson(req);
      const text = clean(b.text, 200);
      if (!text) return fail(res, 400, "Kommentar ist leer.");
      const list = (db.comments[c.id] ||= []);
      const x = { id: id(6), author: me.id, text, ts: now() };
      list.push(x);
      if (list.length > 500) list.shift();
      save();
      return send(res, 201, { ok: true, comment: { id: x.id, who: me.handle, text, ts: x.ts, mine: true } });
    }
    // Meldung nach dem Digital Services Act: ab 3 Meldungen automatisch ausgeblendet bis zur Prüfung
    if (action === "report" && req.method === "POST") {
      const b = await readJson(req);
      const r = (db.reports[c.id] ||= []);
      if (!r.some((x) => x.by === me.id)) r.push({ by: me.id, reason: clean(b.reason, 300) || "ohne Angabe", ts: now() });
      if (r.length >= HIDE_AFTER_REPORTS && !c.reviewed) c.hidden = true;
      save();
      return send(res, 200, { ok: true });
    }
  }

  // ---------- Moderation (nur mit ADMIN_TOKEN) ----------
  if (p.startsWith("/admin/")) {
    if (limited("admin:" + ip, 30, 60000) || !isAdmin(req)) return fail(res, 403, "Kein Zugriff.");
    if (p === "/admin/reports" && req.method === "GET") {
      const out = Object.entries(db.reports)
        .filter(([cid]) => db.clips[cid] && !db.clips[cid].deleted)
        .map(([cid, r]) => ({ clip: { ...clipView(db.clips[cid]), hidden: !!db.clips[cid].hidden }, reports: r }));
      return send(res, 200, { ok: true, reports: out });
    }
    if (p === "/admin/clips" && req.method === "GET") return send(res, 200, { ok: true, clips: Object.values(db.clips).filter((c) => !c.deleted).map((c) => ({ ...clipView(c), hidden: !!c.hidden })) });
    if ((m = /^\/admin\/clips\/([A-Za-z0-9_-]{6,20})\/(hide|restore|delete)$/.exec(p)) && req.method === "POST") {
      const c = db.clips[m[1]];
      if (!c) return fail(res, 404, "Clip nicht gefunden.");
      if (m[2] === "hide") c.hidden = true;
      if (m[2] === "restore") Object.assign(c, { hidden: false, reviewed: true });
      if (m[2] === "delete") await removeClip(c);
      delete db.reports[c.id];
      save();
      return send(res, 200, { ok: true });
    }
    if ((m = /^\/admin\/users\/([A-Za-z0-9_-]{6,20})\/(ban|unban)$/.exec(p)) && req.method === "POST") {
      const u = db.users[m[1]];
      if (!u) return fail(res, 404, "Nutzer nicht gefunden.");
      u.banned = m[2] === "ban";
      save();
      return send(res, 200, { ok: true });
    }
  }
  return fail(res, 404, "Unbekannte Anfrage.");
}
async function removeClip(c) {
  c.deleted = true;
  c.caption = "";
  delete db.likes[c.id];
  delete db.comments[c.id];
  await fsp.rm(path.join(VIDEOS, c.id), { force: true });
}

// ---------- Website ausliefern ----------
const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".mjs": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".json": "application/json", ".webmanifest": "application/manifest+json", ".svg": "image/svg+xml", ".png": "image/png", ".jpg": "image/jpeg", ".ico": "image/x-icon", ".woff2": "font/woff2", ".txt": "text/plain; charset=utf-8", ".xml": "application/xml" };
// Nur diese Ordner/Dateien sind öffentlich – Server-Code, Daten und Dokumente bleiben privat
const PUBLIC = /^\/(?:$|index\.html$|404\.html$|sw\.js$|manifest\.webmanifest$|robots\.txt$|sitemap\.xml$|CNAME$|(?:css|js|fonts|icons)\/[A-Za-z0-9._\/-]+$)/;
async function serveStatic(req, res, url) {
  let p;
  try {
    p = decodeURIComponent(url.pathname);
  } catch (_) {
    return fail(res, 400, "Ungültiger Pfad.");
  }
  if (p.includes("..") || p.includes("\0") || !PUBLIC.test(p)) return serve404(res);
  const file = path.join(ROOT, p === "/" ? "index.html" : p);
  if (!file.startsWith(ROOT + path.sep)) return serve404(res);
  const st = await fsp.stat(file).catch(() => null);
  if (!st?.isFile()) return serve404(res);
  const ext = path.extname(file);
  const cache = p === "/" || ext === ".html" || p === "/sw.js" ? "no-cache" : /^\/(fonts|icons)\//.test(p) ? "public, max-age=604800" : "public, max-age=3600";
  res.writeHead(200, { ...SECURITY, "Content-Type": TYPES[ext] || "application/octet-stream", "Content-Length": st.size, "Cache-Control": cache });
  if (req.method === "HEAD") return res.end();
  fs.createReadStream(file).pipe(res);
}
async function serve404(res) {
  const html = await fsp.readFile(path.join(ROOT, "404.html")).catch(() => "Nicht gefunden");
  send(res, 404, html, { "Content-Type": "text/html; charset=utf-8" });
}

const server = http.createServer(async (req, res) => {
  let url;
  try {
    url = new URL(req.url, "http://x");
  } catch (_) {
    return fail(res, 400, "Ungültige Adresse.");
  }
  if (TRUST_PROXY && req.headers["x-forwarded-proto"] === "https") res.setHeader("Strict-Transport-Security", "max-age=63072000; includeSubDomains");
  try {
    if (url.pathname === "/api" || url.pathname.startsWith("/api/")) return await api(req, res, url);
    if (req.method !== "GET" && req.method !== "HEAD") return fail(res, 405, "Nicht erlaubt.");
    return await serveStatic(req, res, url);
  } catch (e) {
    if (!res.headersSent) fail(res, e.status || 500, e.status ? e.message : "Serverfehler.");
    if (!e.status) console.error(e);
  }
});
server.requestTimeout = 10 * 60000; // große Uploads über langsame Leitungen
server.headersTimeout = 30000;
server.listen(PORT, () => console.log(`AKYTEX-Server läuft auf http://localhost:${PORT}  (Daten: ${DATA}${ADMIN_TOKEN.length >= 24 ? ", Moderation aktiv" : ", Moderation AUS – ADMIN_TOKEN setzen"})`));
