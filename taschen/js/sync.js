// Arbeitstaschen – Sync auf iPhone, iPad und Mac: Ende-zu-Ende-verschlüsselt (AES-GCM-256, Schlüssel nur aus deinem Code), der Server sieht nur Chiffretext
import { SERVER, LIMITS } from "./config.js";

// ---------- Grundlagen ----------
// Wichtig: Beim Import nichts von window/document/indexedDB anfassen – die Krypto-Funktionen laufen auch in Node (Tests).
const MIN = 60000;
const DAY = 86400000;
const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"; // Crockford-Base32: ohne I, L, O, U
const SALT = "arbeitstaschen-sync-v1";
const INFO_ID = "taschen/sync-id/v1";
const INFO_KEY = "taschen/aes-gcm-256/v1";
const AAD_STATE = "taschen/state/v1";
const COLLS = ["bags", "tasks", "notes", "links", "files", "milestones"];
const STATIC_HOSTS = /(^|\.)(github\.io|netlify\.app|vercel\.app)$/i;
const FID = /^[A-Za-z0-9_-]{1,64}$/;

const te = new TextEncoder();
const td = new TextDecoder();
const utf8 = (s) => te.encode(String(s));
const num = (v, d = 0) => (typeof v === "number" && Number.isFinite(v) ? v : d);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const online = () => typeof navigator === "undefined" || navigator.onLine !== false;
const hasDoc = () => typeof document !== "undefined" && typeof window !== "undefined";

function cryptoApi() {
  const c = globalThis.crypto;
  if (!c || !c.subtle || typeof c.getRandomValues !== "function") throw new Error("Verschlüsselung ist hier nicht verfügbar – öffne die App über HTTPS.");
  return c;
}

export function randomBytes(n) {
  const a = new Uint8Array(n);
  cryptoApi().getRandomValues(a);
  return a;
}
export const toHex = (buf) => Array.from(buf instanceof Uint8Array ? buf : new Uint8Array(buf), (b) => b.toString(16).padStart(2, "0")).join("");

// Base64 (Standard) – in großen Stücken, damit auch Megabytes nicht den Stack sprengen
export function toB64(bytes) {
  const u = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let s = "";
  for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode.apply(null, u.subarray(i, i + 0x8000));
  return btoa(s);
}
// Nimmt auch base64url und Zeilenumbrüche an
export function fromB64(str) {
  let s = String(str ?? "")
    .replace(/\s+/g, "")
    .replace(/-/g, "+")
    .replace(/_/g, "/");
  if (s.length % 4) s += "=".repeat(4 - (s.length % 4));
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
const concat = (a, b) => {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
};

// ---------- Sync-Code (24 Zeichen Crockford-Base32 = 120 Bit) ----------
function base32(bytes) {
  let out = "";
  let acc = 0;
  let bits = 0;
  for (const b of bytes) {
    acc = (acc << 8) | b;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out += ALPHABET[(acc >> bits) & 31];
    }
    acc &= (1 << bits) - 1;
  }
  if (bits) out += ALPHABET[(acc << (5 - bits)) & 31];
  return out;
}
function unbase32(str) {
  const out = [];
  let acc = 0;
  let bits = 0;
  for (const ch of str) {
    const v = ALPHABET.indexOf(ch);
    if (v < 0) return null;
    acc = (acc << 5) | v;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.push((acc >> bits) & 255);
    }
    acc &= (1 << bits) - 1;
  }
  return new Uint8Array(out);
}
const group = (s) => s.match(/.{1,4}/g).join("-");

// Neuer zufälliger Code, z. B. "7K2M-QX9D-…" (6 Gruppen à 4)
export function newCode() {
  return group(base32(randomBytes(15)));
}

// Eingabe tolerant lesen: Leerzeichen, Bindestriche, Kleinbuchstaben; O → 0, I/L → 1. Ungültig → null
export function normalizeCode(input) {
  if (typeof input !== "string") return null;
  const s = input
    .normalize("NFKC")
    .toUpperCase()
    .replace(/[\s\-_.·–—:/]+/g, "")
    .replace(/O/g, "0")
    .replace(/[IL]/g, "1");
  if (s.length !== 24) return null;
  for (const ch of s) if (!ALPHABET.includes(ch)) return null;
  return group(s);
}

// ---------- Schlüssel (HKDF-SHA-256 aus dem Code) ----------
// id: 64 hex für den Server (verrät nichts über den Schlüssel); key: AES-GCM-256, nicht exportierbar
export async function derive(code) {
  const c = normalizeCode(code);
  if (!c) throw new Error("Der Sync-Code ist ungültig.");
  const { subtle } = cryptoApi();
  const ikm = unbase32(c.replace(/-/g, ""));
  const base = await subtle.importKey("raw", ikm, "HKDF", false, ["deriveBits", "deriveKey"]);
  const salt = utf8(SALT);
  const bits = await subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt, info: utf8(INFO_ID) }, base, 256);
  const key = await subtle.deriveKey({ name: "HKDF", hash: "SHA-256", salt, info: utf8(INFO_KEY) }, base, { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
  return { id: toHex(bits), key };
}

// ---------- Ver- und Entschlüsseln ----------
async function pipe(bytes, stream) {
  const s = new Blob([bytes]).stream().pipeThrough(stream);
  return new Uint8Array(await new Response(s).arrayBuffer());
}
const canGzip = () => typeof CompressionStream === "function" && typeof Blob === "function" && typeof Response === "function";

// Rohe Bytes → iv(12) || Chiffretext (inkl. 16 Byte Prüfsumme)
export async function encryptBytes(key, bytes, aad = AAD_STATE) {
  const iv = randomBytes(12);
  const ct = await cryptoApi().subtle.encrypt({ name: "AES-GCM", iv, additionalData: utf8(aad) }, key, bytes);
  return concat(iv, new Uint8Array(ct));
}
export async function decryptBytes(key, bytes, aad = AAD_STATE) {
  const u = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  if (u.length < 12 + 16) throw new Error("Die Sync-Daten sind unvollständig.");
  try {
    const pt = await cryptoApi().subtle.decrypt({ name: "AES-GCM", iv: u.subarray(0, 12), additionalData: utf8(aad) }, key, u.subarray(12));
    return new Uint8Array(pt);
  } catch (_) {
    const e = new Error("Entschlüsseln fehlgeschlagen – stimmt der Sync-Code?");
    e.crypto = true;
    throw e;
  }
}

// Objekt → base64(iv || Chiffretext); größere Daten werden vorher mit gzip gepackt (erkennbar am gzip-Kopf 1F 8B)
export async function encrypt(key, obj) {
  let data = utf8(JSON.stringify(obj ?? null));
  if (data.length > 2048 && canGzip()) {
    try {
      data = await pipe(data, new CompressionStream("gzip"));
    } catch (_) {
      /* dann eben ungepackt */
    }
  }
  return toB64(await encryptBytes(key, data, AAD_STATE));
}

export async function decrypt(key, b64) {
  let bytes;
  try {
    bytes = fromB64(b64);
  } catch (_) {
    throw new Error("Die Sync-Daten sind beschädigt.");
  }
  let plain = await decryptBytes(key, bytes, AAD_STATE);
  if (plain[0] === 0x1f && plain[1] === 0x8b) {
    if (typeof DecompressionStream !== "function") throw new Error("Dieses Gerät kann die Sync-Daten nicht entpacken – bitte iOS bzw. macOS aktualisieren.");
    plain = await pipe(plain, new DecompressionStream("gzip"));
  }
  try {
    return JSON.parse(td.decode(plain));
  } catch (_) {
    throw new Error("Die Sync-Daten sind beschädigt.");
  }
}

// ---------- Server-Adresse ----------
const isLocalHost = (h) => /^(localhost|127\.0\.0\.1|\[::1\]|::1)$/i.test(h) || /\.localhost$/i.test(h);

// "taschen.example.com/" → "https://taschen.example.com"; nur https (http nur für localhost oder die eigene Herkunft)
export function normServer(input) {
  let s = String(input ?? "").trim();
  if (!s) return "";
  if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(s)) s = "https://" + s.replace(/^\/+/, "");
  let u;
  try {
    u = new URL(s);
  } catch (_) {
    return "";
  }
  if (u.username || u.password) return "";
  const sameOrigin = typeof location !== "undefined" && location.origin === u.origin;
  if (u.protocol !== "https:" && !(u.protocol === "http:" && (isLocalHost(u.hostname) || sameOrigin))) return "";
  let path = u.pathname
    .replace(/\/api(\/.*)?$/i, "")
    .replace(/\/(index\.html)?$/i, "")
    .replace(/\/+$/, "");
  return u.origin + path;
}

// ---------- HTTP ----------
// Wirft nur bei Netzfehlern (err.network/timeout/offline); HTTP-Fehler kommen als { ok: false, status, data } zurück
export async function request(base, path, { method = "GET", json, body, type, timeout = 30000, as = "json" } = {}) {
  const ctrl = typeof AbortController === "function" ? new AbortController() : null;
  const timer = ctrl ? setTimeout(() => ctrl.abort(), timeout) : null;
  const headers = {};
  let payload;
  if (json !== undefined) {
    headers["Content-Type"] = "application/json";
    payload = JSON.stringify(json);
  } else if (body !== undefined) {
    headers["Content-Type"] = type || "application/octet-stream";
    payload = body;
  }
  try {
    const res = await fetch(base + path, { method, headers, body: payload, signal: ctrl?.signal, cache: "no-store", credentials: "omit", redirect: "follow" });
    let data = null;
    if (as === "bytes" && res.ok) data = new Uint8Array(await res.arrayBuffer());
    else {
      const txt = await res.text().catch(() => "");
      try {
        data = txt ? JSON.parse(txt) : null;
      } catch (_) {
        data = null;
      }
    }
    return { ok: res.ok, status: res.status, data };
  } catch (e) {
    const timeoutHit = e?.name === "AbortError";
    const err = new Error(timeoutHit ? "Der Server antwortet nicht." : online() ? "Der Server ist nicht erreichbar." : "Du bist offline.");
    err.network = true;
    err.timeout = timeoutHit;
    err.offline = !online();
    throw err;
  } finally {
    if (timer) clearTimeout(timer);
  }
}

function httpError(r, what) {
  const msg = r.data?.msg || r.data?.error || "";
  let text;
  if (r.status === 413) text = "Deine Daten sind zu groß für den Server.";
  else if (r.status === 429) text = "Der Server bremst gerade – gleich geht's weiter.";
  else if (r.status === 403) text = msg || "Der Server lässt diese App nicht zu (Herkunft nicht freigegeben).";
  else if (r.status === 507) text = "Der Speicher auf dem Server ist voll.";
  else if (r.status >= 500) text = `Serverfehler (${r.status}) – ich versuche es gleich noch mal.`;
  else text = msg || `${what} fehlgeschlagen (${r.status}).`;
  const e = new Error(text);
  e.status = r.status;
  return e;
}

// ---------- Server prüfen & finden ----------
const healthCache = new Map(); // Basis-URL → { at, value }

export async function checkServer(url) {
  const base = normServer(url);
  const fail = (error) => ({ ok: false, version: null, sync: false, push: false, ai: false, error });
  if (!base) return fail("Ungültige Adresse – sie muss mit https:// beginnen.");
  const hit = healthCache.get(base);
  if (hit && Date.now() - hit.at < (hit.value.ok ? 60000 : 5000)) return hit.value;
  let value;
  try {
    const r = await request(base, "/api/health", { timeout: 8000 });
    if (!r.ok || r.data?.service !== "taschen") value = fail("Unter dieser Adresse läuft kein Taschen-Server.");
    else value = { ok: r.data.ok !== false, version: r.data.version || null, sync: r.data.sync !== false, push: !!r.data.push, ai: !!r.data.ai };
  } catch (e) {
    value = fail(e.message);
  }
  healthCache.set(base, { at: Date.now(), value });
  return value;
}

// Fester Server aus config.js, sonst ein gespeicherter, sonst die eigene Herkunft (wenn die App auf dem Taschen-Server läuft)
export async function detectServer() {
  await ready().catch(() => {});
  if (cfg.server) return cfg.server;
  const fixed = normServer(SERVER.url);
  if (fixed) return fixed;
  if (!hasDoc() || typeof location === "undefined") return null;
  if (!/^https?:$/.test(location.protocol) || STATIC_HOSTS.test(location.hostname)) return null; // statische Hosts haben keine API
  try {
    const base = normServer(new URL(".", document.baseURI).href);
    if (!base) return null;
    const chk = await checkServer(base);
    return chk.ok ? base : null;
  } catch (_) {
    return null;
  }
}

// Manuell eingetragene Adresse merken (auch ohne Sync – für Push und KI)
export async function setServer(url) {
  const base = normServer(url);
  if (!base) throw new Error("Bitte eine gültige Server-Adresse eintragen (https://…).");
  await ready();
  cfg.server = base;
  await saveCfg();
  emit();
  return base;
}

// ---------- Zustand ----------
let ST = null; // store.js (über start() oder bei Bedarf nachgeladen)
let cfg = { enabled: false, server: "", code: "", rev: 0, lastSync: null, lastError: null, gone: [] };
let cfgReady = null;
let phase = "off"; // idle | syncing | error | offline
let errMsg = null;
let lastEmitted = "";
const listeners = new Set();
let keyCache = null;
let running = null;
let again = false;
let started = false;
let pendingLocal = false;
let retryTimer = null;
let retryN = 0;
let localTimer = null;
let blockedUntil = 0;
let lastMeta = 0;
const haveLocal = new Set(); // Dateien, deren Inhalt hier liegt
const fileWait = new Map(); // Datei-id → frühester neuer Versuch

async function storeRef() {
  if (!ST) ST = await import("./store.js");
  return ST;
}

function ready() {
  if (!cfgReady) {
    cfgReady = (async () => {
      try {
        const st = await storeRef();
        const v = await st.kvGet("sync");
        if (v && typeof v === "object") cfg = { ...cfg, ...v };
      } catch (_) {
        /* ohne Speicher: Sync bleibt aus */
      }
      cfg.server = normServer(cfg.server) || "";
      cfg.code = normalizeCode(cfg.code) || "";
      cfg.rev = num(cfg.rev, 0);
      cfg.gone = Array.isArray(cfg.gone) ? cfg.gone : [];
      if (!cfg.code || !cfg.server) cfg.enabled = false;
      cfg.enabled = !!cfg.enabled;
      phase = cfg.enabled ? (online() ? "idle" : "offline") : "off";
    })();
  }
  return cfgReady;
}

async function saveCfg() {
  try {
    const st = await storeRef();
    await st.kvSet("sync", { enabled: cfg.enabled, server: cfg.server, code: cfg.code, rev: cfg.rev, lastSync: cfg.lastSync, lastError: cfg.lastError, gone: cfg.gone });
  } catch (_) {
    /* nächstes Mal */
  }
}

export function status() {
  return { enabled: !!cfg.enabled, server: cfg.server || "", state: cfg.enabled ? phase : "off", lastSync: cfg.lastSync || null, error: cfg.enabled ? errMsg : null };
}

function emit(force = false) {
  const s = status();
  const sig = `${s.enabled}|${s.server}|${s.state}|${s.error}`; // lastSync allein löst kein Neuzeichnen aus (stille Abgleiche jede Minute)
  if (!force && sig === lastEmitted) return;
  lastEmitted = sig;
  for (const fn of [...listeners]) {
    try {
      fn(s);
    } catch (e) {
      if (typeof console !== "undefined") console.error("[taschen] Fehler in einem Sync-Listener:", e);
    }
  }
}
function setPhase(p, err = null) {
  phase = p;
  errMsg = err;
  emit();
}

export function onStatus(fn) {
  if (typeof fn !== "function") return () => {};
  listeners.add(fn);
  return () => listeners.delete(fn);
}

async function keys() {
  if (keyCache && keyCache.code === cfg.code) return keyCache;
  const k = await derive(cfg.code);
  keyCache = { code: cfg.code, ...k };
  return keyCache;
}

// ---------- Einrichten & Ausschalten ----------
export async function configure({ server, code, join = false } = {}) {
  const base = normServer(server);
  if (!base) throw new Error("Bitte eine gültige Server-Adresse eintragen (https://…).");
  const c = normalizeCode(code);
  if (!c) throw new Error("Der Sync-Code ist ungültig – 24 Zeichen, z. B. ABCD-EFGH-…");
  cryptoApi();
  await ready();
  if (join) {
    // „Ich habe schon einen Code“: Gibt es dazu Daten? Sonst ist es vermutlich ein Tippfehler.
    const { id } = await derive(c);
    const r = await request(base, `/api/sync/${id}`, { timeout: 15000 });
    if (r.status === 404) throw new Error("Zu diesem Code gibt es auf dem Server noch keine Daten – stimmt der Code?");
    if (!r.ok) throw httpError(r, "Prüfen");
  }
  const same = cfg.code === c && cfg.server === base;
  cfg = { ...cfg, enabled: true, server: base, code: c, rev: same ? cfg.rev : 0, lastError: null, gone: same ? cfg.gone : [] };
  blockedUntil = 0;
  retryN = 0;
  const st = await storeRef();
  if (!same) {
    keyCache = null;
    haveLocal.clear();
    fileWait.clear();
    // anderer Sync-Raum: alle Dateien müssen dort neu hochgeladen werden
    for (const f of st.files?.() || []) if (f.synced) st.markFileSynced?.(f.id, false);
  }
  await saveCfg();
  setPhase(online() ? "idle" : "offline");
  if (!same) {
    try {
      st.addLog?.("sync", "Sync auf diesem Gerät eingerichtet");
    } catch (_) {
      /* Logbuch ist nur Kür */
    }
  }
  // Ersten Abgleich anstoßen – Fehler zeigt der Status; länger als 15 s warten wir hier nicht
  const first = syncNow().catch(() => {});
  await Promise.race([first, sleep(15000)]);
}

export async function disable() {
  await ready();
  cfg = { ...cfg, enabled: false, code: "", rev: 0, lastError: null, gone: [] };
  keyCache = null;
  clearTimeout(retryTimer);
  clearTimeout(localTimer);
  await saveCfg();
  setPhase("off");
}

// Alle Daten dieses Sync-Raums auf dem Server löschen (Gerät behält seine Daten)
export async function wipeRemote() {
  await ready();
  if (!cfg.code || !cfg.server) return false;
  const { id } = await keys();
  const r = await request(cfg.server, `/api/sync/${id}`, { method: "DELETE" });
  if (!r.ok && r.status !== 404) throw httpError(r, "Löschen");
  cfg.rev = 0;
  await saveCfg();
  return true;
}

// ---------- Abgleich ----------
// Hat das Gerät etwas, das der Server (noch) nicht hat?
export function ahead(local, remote) {
  if (!remote || typeof remote !== "object") return true;
  for (const c of COLLS) {
    const known = new Map((Array.isArray(remote[c]) ? remote[c] : []).map((e) => [e?.id, num(e?.updated)]));
    for (const e of Array.isArray(local?.[c]) ? local[c] : []) {
      if (!e?.id) continue;
      const u = known.get(e.id);
      if (u === undefined || num(e.updated) > u) return true;
    }
  }
  if (num(local?.profile?.updated) > num(remote.profile?.updated)) return true;
  const logIds = new Set((Array.isArray(remote.log) ? remote.log : []).map((e) => e?.id));
  return (Array.isArray(local?.log) ? local.log : []).some((e) => e?.id && !logIds.has(e.id));
}

async function pull(path, key) {
  const r = await request(cfg.server, path);
  if (r.status === 404) return { rev: 0, remote: null, missing: true };
  if (!r.ok) throw httpError(r, "Abrufen");
  const rev = num(r.data?.rev, 0);
  if (typeof r.data?.data !== "string" || !r.data.data) return { rev, remote: null };
  return { rev, remote: await decrypt(key, r.data.data) };
}

async function runSync({ quiet = false } = {}) {
  await ready();
  if (!cfg.enabled || !cfg.code || !cfg.server) return { pulled: false, pushed: false };
  if (!online()) {
    setPhase("offline");
    const e = new Error("Du bist offline – ich gleiche ab, sobald du wieder online bist.");
    e.offline = true;
    throw e;
  }
  if (!quiet || phase !== "idle") setPhase("syncing");
  const st = await storeRef();
  const { id, key } = await keys();
  const path = `/api/sync/${id}`;
  let pulled = false;
  let pushed = false;
  try {
    let snap = await pull(path, key);
    // Server hat nichts mehr, obwohl wir schon synchronisiert hatten → Dateien neu hochladen
    if (snap.missing && cfg.rev > 0) for (const f of st.files?.() || []) if (f.synced) st.markFileSynced?.(f.id, false);
    let done = false;
    for (let attempt = 0; attempt < 3 && !done; attempt++) {
      if (snap.remote && st.merge(snap.remote).changed) pulled = true;
      pendingLocal = false;
      const local = st.syncPayload();
      if (snap.remote && !ahead(local, snap.remote)) {
        cfg.rev = snap.rev;
        done = true;
        break;
      }
      // Was eine neuere App-Version zusätzlich speichert, bleibt erhalten (nicht mit einem älteren Stand überschreiben)
      if (snap.remote && typeof snap.remote === "object") for (const k of Object.keys(snap.remote)) if (!(k in local)) local[k] = snap.remote[k];
      const data = await encrypt(key, local);
      const r = await request(cfg.server, path, { method: "PUT", json: { rev: snap.rev, data } });
      if (r.ok) {
        cfg.rev = num(r.data?.rev, snap.rev + 1);
        pushed = true;
        done = true;
      } else if (r.status === 409) {
        // Ein anderes Gerät war schneller: dessen Stand übernehmen, zusammenführen, erneut versuchen
        snap = typeof r.data?.data === "string" && r.data.data ? { rev: num(r.data.rev, 0), remote: await decrypt(key, r.data.data) } : await pull(path, key);
      } else throw httpError(r, "Hochladen");
    }
    if (!done) {
      const e = new Error("Gerade ändern mehrere Geräte gleichzeitig – ich versuche es gleich noch mal.");
      e.conflict = true;
      throw e;
    }
    let note = null;
    try {
      note = await syncFiles(st, id, key);
    } catch (e) {
      note = e?.message || null;
    }
    cfg.lastSync = Date.now();
    cfg.lastError = null;
    retryN = 0;
    blockedUntil = 0;
    await saveCfg();
    if (pulled || pushed || Date.now() - lastMeta > 10 * MIN) {
      lastMeta = Date.now();
      try {
        st.setMeta?.({ lastSync: cfg.lastSync });
      } catch (_) {
        /* nur Anzeige */
      }
    }
    setPhase("idle", note);
    if (!quiet || pulled || pushed) emit(true);
    return { pulled, pushed };
  } catch (e) {
    failed(e);
    throw e;
  }
}

function failed(e) {
  const msg = e?.message || "Sync fehlgeschlagen.";
  cfg.lastError = msg;
  saveCfg();
  if (e?.offline || !online()) return setPhase("offline");
  setPhase("error", msg);
  const retryable = e?.network || e?.conflict || e?.status === 429 || num(e?.status) >= 500;
  if (retryable) {
    clearTimeout(retryTimer);
    const delay = Math.min(5 * MIN, 5000 * 3 ** retryN++) * (0.8 + Math.random() * 0.4);
    retryTimer = setTimeout(() => syncNow({ quiet: true }).catch(() => {}), delay);
  } else blockedUntil = Date.now() + 10 * MIN; // z. B. falscher Code, zu groß, nicht erlaubt: nicht jede Minute neu versuchen
}

export function syncNow(opts = {}) {
  if (running) {
    again = true;
    return running;
  }
  clearTimeout(retryTimer);
  running = runSync(opts).finally(() => {
    running = null;
    if (again) {
      again = false;
      setTimeout(() => syncNow({ quiet: true }).catch(() => {}), 300);
    }
  });
  return running;
}

// ---------- Dateien (verschlüsselt, ≤ LIMITS.syncFileMax) ----------
const fileAad = (fid) => `taschen/file/v1/${fid}`;

async function syncFiles(st, id, key) {
  if (typeof st.files !== "function" || typeof st.fileBlob !== "function") return null;
  const now = Date.now();
  let note = null;
  for (const f of st.files()) {
    if (!f || !FID.test(f.id) || num(f.size) > LIMITS.syncFileMax) continue;
    if ((fileWait.get(f.id) || 0) > now) continue;
    const path = `/api/sync/${id}/files/${f.id}`;
    let blob = null;
    if (!haveLocal.has(f.id)) {
      blob = await st.fileBlob(f.id);
      if (blob) haveLocal.add(f.id);
    }
    if (haveLocal.has(f.id)) {
      if (f.synced) continue;
      blob ||= await st.fileBlob(f.id);
      if (!blob) {
        haveLocal.delete(f.id);
        continue;
      }
      const body = await encryptBytes(key, new Uint8Array(await blob.arrayBuffer()), fileAad(f.id));
      const r = await request(cfg.server, path, { method: "PUT", body, type: "application/octet-stream", timeout: 180000 });
      if (r.ok) st.markFileSynced?.(f.id, true);
      else if (r.status === 413 || r.status === 507) {
        fileWait.set(f.id, now + 6 * 60 * MIN);
        note = r.status === 507 ? "Server-Speicher voll – neue Dateien bleiben vorerst nur auf diesem Gerät." : `„${f.name}“ ist zu groß für den Server und bleibt auf diesem Gerät.`;
      } else if (r.status >= 500 || r.status === 429) {
        fileWait.set(f.id, now + 5 * MIN);
      } else throw httpError(r, "Datei hochladen");
    } else {
      // Inhalt fehlt hier → vom Server holen (falls ein anderes Gerät ihn schon hochgeladen hat)
      const r = await request(cfg.server, path, { as: "bytes", timeout: 180000 });
      if (r.ok && r.data) {
        try {
          const plain = await decryptBytes(key, r.data, fileAad(f.id));
          await st.putFileBlob(f.id, new Blob([plain], { type: f.type || "application/octet-stream" }));
          haveLocal.add(f.id);
          st.markFileSynced?.(f.id, true);
        } catch (_) {
          fileWait.set(f.id, now + 60 * MIN);
        }
      } else fileWait.set(f.id, now + (r.status === 404 ? 5 : 15) * MIN);
    }
  }
  // Gelöschte Dateien nach 2 Tagen auch auf dem Server entfernen (bis dahin bleibt „Rückgängig“ möglich)
  const gone = new Set(cfg.gone);
  for (const f of st.get?.()?.files || []) {
    if (!f?.deleted || gone.has(f.id) || !FID.test(f.id) || now - f.deleted < 2 * DAY) continue;
    const r = await request(cfg.server, `/api/sync/${id}/files/${f.id}`, { method: "DELETE" });
    if (r.ok || r.status === 404) gone.add(f.id);
  }
  cfg.gone = [...gone].slice(-500);
  return note;
}

// ---------- Automatisch abgleichen ----------
const quietSync = () => syncNow({ quiet: true }).catch(() => {});

export function start(store) {
  if (store) ST = store;
  if (started) return;
  started = true;
  ready().then(() => {
    emit(true);
    if (cfg.enabled) quietSync();
  });
  store?.subscribe?.((_s, ch) => {
    // Nur echte Änderungen auf diesem Gerät – Zusammenführungen aus dem Sync (local: false) lösen keinen neuen Sync aus
    if (!ch || ch.local !== true) return;
    pendingLocal = true;
    if (!cfg.enabled) return;
    clearTimeout(localTimer);
    localTimer = setTimeout(quietSync, 2500);
  });
  if (!hasDoc()) return;
  window.addEventListener("online", () => {
    if (!cfg.enabled) return;
    setPhase("idle");
    quietSync();
  });
  window.addEventListener("offline", () => cfg.enabled && setPhase("offline"));
  const flushNow = () => {
    if (!cfg.enabled || !pendingLocal) return;
    clearTimeout(localTimer);
    quietSync();
  };
  document.addEventListener("visibilitychange", () => {
    if (!cfg.enabled) return;
    if (document.visibilityState === "visible") {
      if (Date.now() - num(cfg.lastSync) > 5000) quietSync();
    } else flushNow();
  });
  window.addEventListener("pagehide", flushNow);
  setInterval(() => {
    if (cfg.enabled && document.visibilityState === "visible" && online() && Date.now() >= blockedUntil) quietSync();
  }, 60000);
}
