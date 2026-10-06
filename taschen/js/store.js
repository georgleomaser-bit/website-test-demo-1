// Arbeitstaschen – Datenhaltung: Zustand, Speichern (IndexedDB → localStorage → Speicher), Rückgängig, Sync-Zusammenführung, Backup
import { DB, DEFAULT_PROFILE, LIMITS, REPEATS, COLORS } from "./config.js";
import { uid, safeUrl, fmtSize } from "./util.js";
import { todayISO, addDays, nextOccurrence, isISO, parseTime, toTime, normName } from "./dates.js";

// ---------- Grundlagen ----------
export const STATE_VERSION = 1;
const DAY = 86400000;
const COLLS = ["bags", "tasks", "notes", "links", "files", "milestones", "accounts"];
const KIND = { bags: "bag", tasks: "task", notes: "note", links: "link", files: "file", milestones: "milestone", accounts: "account" };
const PROJECT_COLLS = COLLS.filter((c) => c !== "accounts"); // Projektdaten (ohne verbundene Konten)
const REPEAT_IDS = new Set(REPEATS.map((r) => r.id).filter(Boolean));
const STATUSES = ["aktiv", "pausiert", "fertig"];
const LOG_KINDS = new Set(["done", "add", "move", "bag", "note", "link", "file", "review", "sync", "import", "seed"]);

const clone = (o) => (o === undefined ? undefined : typeof structuredClone === "function" ? structuredClone(o) : JSON.parse(JSON.stringify(o)));
const str = (v) => (v === null || v === undefined ? "" : String(v));
const num = (v, def = 0) => (typeof v === "number" && Number.isFinite(v) ? v : def);
const int = (v, lo, hi, def) => {
  const n = Math.round(Number(v));
  return Number.isFinite(n) && v !== null && v !== "" && v !== undefined ? Math.min(hi, Math.max(lo, n)) : def;
};
const msOrNull = (v, fallback) => (typeof v === "number" && Number.isFinite(v) && v > 0 ? v : v === true ? fallback : null);
const timeOrNull = (v) => {
  const m = parseTime(v);
  return m === null ? null : toTime(m);
};
const live = (arr) => arr.filter((e) => e && !e.deleted);
const byOrder = (a, b) => num(a.order) - num(b.order) || num(a.created) - num(b.created) || (a.id < b.id ? -1 : 1);
const quote = (s) => `„${str(s).length > 60 ? str(s).slice(0, 59) + "…" : str(s)}“`;

function fresh() {
  const now = Date.now();
  return { v: STATE_VERSION, profile: { ...clone(DEFAULT_PROFILE), updated: 0 }, bags: [], tasks: [], notes: [], links: [], files: [], milestones: [], accounts: [], log: [], meta: { lastReview: null, lastBackup: null, lastSync: null, createdAt: now, seeded: false } };
}

// Monotone Zeitstempel: jede Änderung ist echt neuer als die vorige Fassung (wichtig für Last-Writer-Wins)
const stamp = (e) => Math.max(Date.now(), num(e?.updated) + 1);

// ---------- Normalisieren (Laden, Sync, Import – unbekannte Felder bleiben erhalten) ----------
function base(e, now = Date.now()) {
  const created = num(e.created, 0) || num(e.updated, 0) || now;
  return { id: str(e.id), created, updated: num(e.updated, created), deleted: msOrNull(e.deleted, now) };
}
function strList(v, strip = null) {
  const out = [];
  const seen = new Set();
  for (const x of Array.isArray(v) ? v : []) {
    const s = strip ? str(x).trim().replace(strip, "").trim() : str(x).trim();
    if (s && !seen.has(s.toLowerCase())) seen.add(s.toLowerCase()), out.push(s);
  }
  return out;
}
export function normBag(b) {
  return {
    ...b,
    ...base(b),
    name: str(b.name).trim() || "Tasche",
    emoji: str(b.emoji).trim() || "👜",
    color: COLORS[b.color] ? b.color : "blue",
    goal: str(b.goal),
    status: STATUSES.includes(b.status) ? b.status : "aktiv",
    deadline: isISO(b.deadline) ? b.deadline : null,
    sections: strList(b.sections),
    order: num(b.order, 0),
    pinned: !!b.pinned,
  };
}
function normSub(s) {
  if (typeof s === "string") return { id: uid("s_"), title: s.trim(), done: false };
  return { ...s, id: str(s?.id) || uid("s_"), title: str(s?.title).trim(), done: !!s?.done };
}
export function normTask(t) {
  const b = base(t);
  const repeat = REPEAT_IDS.has(t.repeat) ? t.repeat : null;
  const out = {
    ...t,
    ...b,
    bag: typeof t.bag === "string" && t.bag ? t.bag : null,
    title: str(t.title).trim() || "Ohne Titel",
    notes: str(t.notes),
    done: msOrNull(t.done, b.updated),
    prio: int(t.prio, 0, 3, 0),
    due: isISO(t.due) ? t.due : null,
    time: timeOrNull(t.time),
    remind: t.remind === null || t.remind === undefined || t.remind === "" ? null : int(t.remind, -1, 525600, null),
    repeat,
    section: str(t.section).trim(),
    tags: strList(t.tags, /^[#@]+/),
    subtasks: (Array.isArray(t.subtasks) ? t.subtasks : []).map(normSub).filter((s) => s.title),
    plan: isISO(t.plan) ? t.plan : null,
    someday: !!t.someday,
    order: num(t.order, 0),
    est: t.est === null || t.est === undefined || t.est === "" ? null : int(t.est, 1, 14400, null),
    waiting: str(t.waiting).trim(),
    milestone: typeof t.milestone === "string" && t.milestone ? t.milestone : null,
  };
  if (out.remind !== null && out.remind < -1) out.remind = -1;
  if (!repeat || !Number.isInteger(out.repeatDay)) delete out.repeatDay;
  return out;
}
export function normNote(n) {
  return { ...n, ...base(n), bag: typeof n.bag === "string" && n.bag ? n.bag : null, title: str(n.title), body: str(n.body), pinned: !!n.pinned };
}
export function normLink(l) {
  return { ...l, ...base(l), bag: typeof l.bag === "string" && l.bag ? l.bag : null, title: str(l.title), url: str(l.url) };
}
export function normFile(f) {
  return { ...f, ...base(f), bag: typeof f.bag === "string" && f.bag ? f.bag : null, name: str(f.name) || "Datei", type: str(f.type), size: Math.max(0, num(f.size, 0)), synced: !!f.synced };
}
export function normMilestone(m) {
  const b = base(m);
  return { ...m, ...b, bag: typeof m.bag === "string" && m.bag ? m.bag : null, title: str(m.title).trim() || "Meilenstein", date: isISO(m.date) ? m.date : null, done: msOrNull(m.done, b.updated) };
}
// Verbundenes Konto (Google/Microsoft): secret ist der Schlüssel zum Refresh-Token auf dem eigenen Server
export function normAccount(a) {
  const b = base(a);
  const provider = str(a.provider).trim().toLowerCase() || "google";
  return {
    ...a,
    ...b,
    provider,
    email: str(a.email).trim().slice(0, 254),
    secret: b.deleted ? "" : str(a.secret).trim(),
    server: str(a.server).trim().replace(/\/+$/, ""),
    color: COLORS[a.color] ? a.color : null,
    calendars: a.calendars !== false,
    mail: a.mail !== false,
    broken: !!a.broken,
  };
}
const NORM = { bags: normBag, tasks: normTask, notes: normNote, links: normLink, files: normFile, milestones: normMilestone, accounts: normAccount };

export function normProfile(p) {
  const d = DEFAULT_PROFILE;
  const x = { ...clone(d), ...(p && typeof p === "object" ? p : {}) };
  const days = [...new Set((Array.isArray(x.workdays) ? x.workdays : d.workdays).map(Number).filter((n) => Number.isInteger(n) && n >= 0 && n <= 6))].sort();
  return {
    ...x,
    name: str(x.name).trim().slice(0, 80),
    updated: num(x.updated, 0),
    dayStart: timeOrNull(x.dayStart) || d.dayStart,
    dayEnd: timeOrNull(x.dayEnd) || d.dayEnd,
    focusCount: int(x.focusCount, 1, 10, d.focusCount),
    weekStart: int(x.weekStart, 0, 6, d.weekStart),
    reviewDay: int(x.reviewDay, 0, 6, d.reviewDay),
    workdays: days,
    defaultRemind: int(x.defaultRemind, 0, 10080, d.defaultRemind),
    accent: COLORS[x.accent] ? x.accent : d.accent,
    theme: ["auto", "light", "dark"].includes(x.theme) ? x.theme : d.theme,
    haptics: x.haptics !== false,
    sounds: x.sounds !== false,
    briefing: x.briefing !== false,
    evening: x.evening !== false,
    onboarded: !!x.onboarded,
  };
}
function normLog(e) {
  if (!e || typeof e !== "object" || !e.id) return null;
  return { ...e, id: str(e.id), t: num(e.t, 0), kind: LOG_KINDS.has(e.kind) ? e.kind : "add", text: str(e.text), bag: e.bag ? str(e.bag) : null, task: e.task ? str(e.task) : null };
}
function normMeta(m, prev) {
  const x = { ...(prev || {}), ...(m && typeof m === "object" ? m : {}) };
  return { ...x, lastReview: isISO(x.lastReview) ? x.lastReview : null, lastBackup: msOrNull(x.lastBackup, null), lastSync: msOrNull(x.lastSync, null), createdAt: num(x.createdAt, 0) || Date.now(), seeded: !!x.seeded };
}
const validEntity = (e) => e && typeof e === "object" && typeof e.id === "string" && e.id.length > 0 && e.id.length <= 200;

export function normalizeState(raw) {
  const s = raw && typeof raw === "object" ? raw : {};
  const out = { ...s, v: Math.max(STATE_VERSION, num(s.v, STATE_VERSION)), profile: normProfile(s.profile), meta: normMeta(s.meta) };
  for (const c of COLLS) {
    const seen = new Map();
    for (const e of Array.isArray(s[c]) ? s[c] : []) {
      if (!validEntity(e)) continue;
      const n = NORM[c](e);
      const prev = seen.get(n.id);
      if (!prev || n.updated > prev.updated) seen.set(n.id, n); // doppelte ids: neuere Fassung gewinnt
    }
    out[c] = [...seen.values()];
  }
  out.log = (Array.isArray(s.log) ? s.log : []).map(normLog).filter(Boolean).sort((a, b) => a.t - b.t).slice(-LIMITS.logMax);
  return out;
}

// ---------- Migration ----------
// Für spätere Versionen: MIGRATIONS[n] hebt einen Zustand von Version n−1 auf n an (z. B. 2: (s) => ({ ...s, neuesFeld: … })).
export const MIGRATIONS = {};
export function migrate(raw) {
  if (!raw || typeof raw !== "object") return fresh();
  let s = { ...raw };
  let v = Math.max(1, Math.floor(num(s.v, 1)));
  while (v < STATE_VERSION && typeof MIGRATIONS[v + 1] === "function") {
    s = MIGRATIONS[v + 1](s) || s;
    v++;
    s.v = v;
  }
  return normalizeState(s);
}

// ---------- Speicher-Adapter ----------
function memoryAdapter() {
  const kv = new Map();
  const files = new Map();
  return {
    kind: "memory",
    files: true,
    get: async (k) => clone(kv.get(k)),
    set: async (k, v) => void kv.set(k, clone(v)),
    del: async (k) => void kv.delete(k),
    keys: async () => [...kv.keys()],
    fileGet: async (id) => files.get(id) ?? null,
    filePut: async (id, blob) => void files.set(id, blob),
    fileDel: async (id) => void files.delete(id),
    fileClear: async () => files.clear(),
    fileKeys: async () => [...files.keys()],
  };
}

function localAdapter() {
  const P = "taschen-";
  const noFiles = async () => {
    throw new Error("Dateien kann dieser Browser gerade nicht speichern (kein IndexedDB – z. B. im privaten Modus).");
  };
  return {
    kind: "local",
    files: false,
    get: async (k) => {
      try {
        const v = localStorage.getItem(P + k);
        return v === null ? undefined : JSON.parse(v);
      } catch (_) {
        return undefined; // kaputter Eintrag zählt als leer
      }
    },
    set: async (k, v) => localStorage.setItem(P + k, JSON.stringify(v)),
    del: async (k) => localStorage.removeItem(P + k),
    keys: async () => Object.keys(localStorage).filter((k) => k.startsWith(P)).map((k) => k.slice(P.length)),
    fileGet: async () => null,
    filePut: noFiles,
    fileDel: async () => {},
    fileClear: async () => {},
    fileKeys: async () => [],
  };
}

function openIDB(timeout = 4000) {
  return new Promise((resolve, reject) => {
    let done = false;
    const finish = (fn, v) => {
      if (!done) (done = true), fn(v);
    };
    // Safari hängt beim ersten open() nach dem App-Start gelegentlich – dann neu versuchen bzw. auf localStorage ausweichen
    const timer = setTimeout(() => finish(reject, new Error("IndexedDB antwortet nicht")), timeout);
    let r;
    try {
      r = indexedDB.open(DB.name, DB.version);
    } catch (e) {
      clearTimeout(timer);
      return finish(reject, e);
    }
    r.onupgradeneeded = () => {
      const db = r.result;
      if (!db.objectStoreNames.contains(DB.kv)) db.createObjectStore(DB.kv);
      if (!db.objectStoreNames.contains(DB.files)) db.createObjectStore(DB.files);
    };
    r.onsuccess = () => {
      clearTimeout(timer);
      const db = r.result;
      if (done) return db.close();
      db.onversionchange = () => db.close();
      finish(resolve, db);
    };
    r.onerror = () => {
      clearTimeout(timer);
      finish(reject, r.error || new Error("IndexedDB nicht verfügbar"));
    };
  });
}

function idbAdapter(db0) {
  let db = db0;
  const run = (store, mode, fn) =>
    new Promise((resolve, reject) => {
      const t = db.transaction(store, mode);
      const req = fn(t.objectStore(store));
      t.oncomplete = () => resolve(req?.result);
      t.onerror = () => reject(t.error || req?.error);
      t.onabort = () => reject(t.error || new Error("Speichern abgebrochen"));
    });
  // iOS trennt die Verbindung manchmal im Hintergrund („Connection lost“) – dann einmal neu öffnen
  const op = async (store, mode, fn) => {
    try {
      return await run(store, mode, fn);
    } catch (e) {
      if (!/InvalidState|Unknown|closing|lost/i.test(`${e?.name} ${e?.message}`)) throw e;
      db = await openIDB();
      return run(store, mode, fn);
    }
  };
  return {
    kind: "idb",
    files: true,
    get: (k) => op(DB.kv, "readonly", (s) => s.get(k)),
    set: (k, v) => op(DB.kv, "readwrite", (s) => s.put(v, k)),
    del: (k) => op(DB.kv, "readwrite", (s) => s.delete(k)),
    keys: () => op(DB.kv, "readonly", (s) => s.getAllKeys()),
    fileGet: async (id) => (await op(DB.files, "readonly", (s) => s.get(id))) ?? null,
    filePut: (id, blob) => op(DB.files, "readwrite", (s) => s.put(blob, id)),
    fileDel: (id) => op(DB.files, "readwrite", (s) => s.delete(id)),
    fileClear: () => op(DB.files, "readwrite", (s) => s.clear()),
    fileKeys: () => op(DB.files, "readonly", (s) => s.getAllKeys()),
  };
}

function hasLocalStorage() {
  try {
    if (typeof localStorage === "undefined") return false;
    localStorage.setItem("taschen-probe", "1");
    localStorage.removeItem("taschen-probe");
    return true;
  } catch (_) {
    return false;
  }
}

// ---------- Interner Zustand ----------
let S = fresh();
const memStore = memoryAdapter(); // bleibt im Prozess erhalten (Tests: Speichern → neu laden)
let adapter = null;
let adapterReady = null;
let device = null;
let loading = null;
const listeners = new Set();
let undoStack = [];
let txCur = null;
let saveTimer = null;
let dirty = false;
let writing = Promise.resolve();
let saveError = null;
let lifecycle = false;
let channel = null;
const instance = uid("i_");

async function pickAdapter(memory) {
  if (memory || typeof indexedDB === "undefined") {
    if (!memory && typeof window !== "undefined" && hasLocalStorage()) return localAdapter();
    return memStore;
  }
  for (let i = 0; i < 2; i++) {
    try {
      return idbAdapter(await openIDB(i ? 6000 : 3500));
    } catch (_) {
      /* zweiter Versuch, danach localStorage */
    }
  }
  return hasLocalStorage() ? localAdapter() : memStore;
}
function ensureAdapter(memory = false) {
  if (memory) {
    adapter = memStore;
    adapterReady = Promise.resolve(adapter);
  }
  if (!adapterReady) adapterReady = pickAdapter(false).then((a) => (adapter = a));
  return adapterReady;
}

// ---------- Ereignisse ----------
export function subscribe(fn) {
  if (typeof fn !== "function") return () => {};
  listeners.add(fn);
  return () => listeners.delete(fn);
}
function emit(change) {
  for (const fn of [...listeners]) {
    try {
      fn(S, change);
    } catch (e) {
      // ein kaputter Listener darf die anderen nicht blockieren
      if (typeof console !== "undefined") console.error("[taschen] Fehler in einem Store-Listener:", e);
    }
  }
}

// ---------- Speichern (entprellt 300 ms) ----------
function markDirty() {
  dirty = true;
  if (saveTimer) clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    saveTimer = null;
    flush();
  }, 300);
  saveTimer?.unref?.(); // Node: Tests nicht aufhalten
}

export function flush() {
  if (saveTimer) clearTimeout(saveTimer), (saveTimer = null);
  if (!dirty || !adapter) return writing;
  dirty = false;
  const a = adapter;
  writing = writing
    .then(() => a.set("state", S))
    .then(() => {
      saveError = null;
      try {
        channel?.postMessage({ type: "saved", from: instance });
      } catch (_) {
        /* andere Tabs erfahren es beim nächsten Mal */
      }
    })
    .catch((e) => {
      saveError = e;
      dirty = true; // beim nächsten Anlass erneut versuchen
      if (typeof console !== "undefined") console.warn("[taschen] Speichern fehlgeschlagen:", e);
    });
  return writing;
}

// Wo und wie gespeichert wird (für die Einstellungen)
export async function storageInfo() {
  const out = { kind: adapter?.kind || "memory", error: saveError ? String(saveError.message || saveError) : null, persisted: null, usage: null, quota: null };
  try {
    if (typeof navigator !== "undefined" && navigator.storage) {
      out.persisted = (await navigator.storage.persisted?.()) ?? null;
      const est = await navigator.storage.estimate?.();
      if (est) (out.usage = est.usage ?? null), (out.quota = est.quota ?? null);
    }
  } catch (_) {
    /* nicht überall verfügbar */
  }
  return out;
}

function installLifecycle() {
  if (lifecycle || typeof window === "undefined" || typeof window.addEventListener !== "function") return;
  lifecycle = true;
  window.addEventListener("pagehide", () => flush());
  if (typeof document !== "undefined") document.addEventListener("visibilitychange", () => document.visibilityState === "hidden" && flush());
  // Mehrere offene Fenster (z. B. Safari-Tab + Dock-App) gleichen sich über die gemeinsame Datenbank ab
  if (typeof BroadcastChannel === "function") {
    try {
      channel = new BroadcastChannel("taschen-store");
      channel.unref?.(); // nur Node: hält den Prozess nicht am Leben
      channel.onmessage = (e) => {
        if (e?.data?.type !== "saved" || e.data.from === instance || !adapter) return;
        adapter
          .get("state")
          .then((raw) => {
            if (!raw) return;
            const other = migrate(raw);
            const m = other.meta || {};
            const meta = { ...S.meta };
            for (const k of ["lastBackup", "lastSync"]) if (num(m[k]) > num(meta[k])) meta[k] = m[k];
            if (m.lastReview && (!meta.lastReview || m.lastReview > meta.lastReview)) meta.lastReview = m.lastReview;
            meta.seeded = !!(meta.seeded || m.seeded);
            S.meta = meta;
            merge(other);
          })
          .catch(() => {});
      };
    } catch (_) {
      channel = null;
    }
  }
}

// ---------- Laden ----------
export function load({ memory = false } = {}) {
  if (loading) return loading;
  loading = (async () => {
    if (saveTimer) clearTimeout(saveTimer), (saveTimer = null);
    await writing.catch(() => {});
    if (memory) ensureAdapter(true);
    await ensureAdapter();
    let raw;
    try {
      raw = await adapter.get("state");
    } catch (_) {
      raw = undefined;
    }
    try {
      S = migrate(raw);
    } catch (e) {
      // Unlesbarer Zustand: Rohdaten zur Rettung beiseitelegen, dann leer starten
      try {
        await adapter.set("state-defekt-" + Date.now(), raw);
      } catch (_) {
        /* nichts mehr zu retten */
      }
      S = fresh();
    }
    dirty = false;
    undoStack = [];
    if (purgeTombstones() || (raw && num(raw.v, 1) < STATE_VERSION)) markDirty();
    try {
      device = await adapter.get("device");
      if (typeof device !== "string" || !/^d_[\w-]{6,}$/.test(device)) {
        device = "d_" + randomHex(16);
        await adapter.set("device", device);
      }
    } catch (_) {
      device = device || "d_" + randomHex(16);
    }
    installLifecycle();
    emit({ type: "all", action: "load", local: false });
    return S;
  })().finally(() => {
    loading = null;
  });
  return loading;
}

function randomHex(n) {
  const a = new Uint8Array(Math.ceil(n / 2));
  if (typeof crypto !== "undefined" && crypto.getRandomValues) crypto.getRandomValues(a);
  else for (let i = 0; i < a.length; i++) a[i] = Math.floor(Math.random() * 256);
  return [...a].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, n);
}

// ---------- Lesen ----------
export const get = () => S;
export const bags = () => live(S.bags).sort((a, b) => Number(!!b.pinned) - Number(!!a.pinned) || byOrder(a, b));
export const tasks = () => live(S.tasks).sort(byOrder);
export const notes = () => live(S.notes).sort((a, b) => Number(!!b.pinned) - Number(!!a.pinned) || b.updated - a.updated);
export const links = () => live(S.links).sort((a, b) => a.created - b.created);
export const files = () => live(S.files).sort((a, b) => b.created - a.created);
export function milestones(bagId) {
  return live(S.milestones)
    .filter((m) => bagId === undefined || m.bag === bagId)
    .sort((a, b) => (a.date || "9999").localeCompare(b.date || "9999") || a.created - b.created);
}
const findRaw = (coll, id) => (id ? S[coll].find((e) => e.id === id) || null : null);
const findLive = (coll, id) => {
  const e = findRaw(coll, id);
  return e && !e.deleted ? e : null;
};
export const bag = (id) => findLive("bags", id);
export const task = (id) => findLive("tasks", id);
export const note = (id) => findLive("notes", id);
export const link = (id) => findLive("links", id);
export const file = (id) => findLive("files", id);
export const milestone = (id) => findLive("milestones", id);
export function tasksOf(bagId) {
  const want = bagId || null;
  return live(S.tasks).filter((t) => (t.bag || null) === want).sort(byOrder);
}
export const notesOf = (bagId) => notes().filter((n) => (n.bag || null) === (bagId || null));
export const linksOf = (bagId) => links().filter((l) => (l.bag || null) === (bagId || null));
export const filesOf = (bagId) => files().filter((f) => (f.bag || null) === (bagId || null));

// ---------- Transaktionen & Rückgängig ----------
// Jede Nutzeraktion merkt sich die Vorher-Fassungen der berührten Einträge. undo() stellt sie mit NEUEM
// Zeitstempel wieder her – so gewinnt das Rückgängigmachen auch gegen eine inzwischen synchronisierte Fassung.
function tx(label, ev, fn, { coalesce = null } = {}) {
  if (txCur) return fn();
  const top = undoStack[undoStack.length - 1];
  const reuse = coalesce && top && top.coalesce === coalesce && Date.now() - top.at < 4000;
  const step = reuse ? top : { label, at: Date.now(), coalesce, items: new Map(), logIds: [] };
  const sizeBefore = step.items.size, logBefore = step.logIds.length;
  txCur = step;
  let out;
  try {
    out = fn();
  } catch (e) {
    rollback(step, sizeBefore, logBefore);
    txCur = null;
    throw e;
  }
  txCur = null;
  if (step.items.size === sizeBefore && step.logIds.length === logBefore && !step.touched) return out;
  step.touched = false;
  step.at = Date.now();
  if (label && !reuse) {
    undoStack.push(step);
    if (undoStack.length > LIMITS.undoMax) undoStack.splice(0, undoStack.length - LIMITS.undoMax);
  }
  markDirty();
  emit({ local: true, ...(typeof ev === "function" ? ev(out) : ev) });
  return out;
}
function rollback(step, sizeBefore, logBefore) {
  const items = [...step.items.entries()].slice(sizeBefore);
  for (const [k, it] of items) {
    const arr = S[it.coll];
    const i = arr.findIndex((e) => e.id === it.id);
    if (it.before) i >= 0 ? replaceInPlace(arr[i], clone(it.before)) : arr.push(clone(it.before));
    else if (i >= 0) arr.splice(i, 1);
    step.items.delete(k);
  }
  const ids = new Set(step.logIds.splice(logBefore));
  if (ids.size) S.log = S.log.filter((e) => !ids.has(e.id));
}
function remember(coll, e) {
  if (!txCur) return;
  const k = coll + ":" + e.id;
  if (!txCur.items.has(k)) txCur.items.set(k, { coll, id: e.id, before: clone(e) });
  txCur.touched = true;
}
function rememberNew(coll, id) {
  if (!txCur) return;
  const k = coll + ":" + id;
  if (!txCur.items.has(k)) txCur.items.set(k, { coll, id, before: null });
  txCur.touched = true;
}
function replaceInPlace(target, src) {
  for (const k of Object.keys(target)) if (!(k in src)) delete target[k];
  Object.assign(target, src);
  return target;
}
// Änderung an einem Eintrag: nur wenn sich wirklich etwas ändert (sonst kein Rückgängig-Schritt, kein Speichern)
function change(coll, e, next) {
  const keys = new Set([...Object.keys(e), ...Object.keys(next)]);
  keys.delete("updated");
  let diff = false;
  for (const k of keys) if (JSON.stringify(e[k]) !== JSON.stringify(next[k])) diff = true;
  if (!diff) return false;
  remember(coll, e);
  const u = stamp(e);
  replaceInPlace(e, { ...next, updated: u });
  return true;
}
function tombstone(coll, e, now = Date.now()) {
  if (!e || e.deleted) return false;
  remember(coll, e);
  e.deleted = now;
  e.updated = stamp(e);
  return true;
}
function insert(coll, e) {
  rememberNew(coll, e.id);
  S[coll].push(e);
  return e;
}

export function canUndo() {
  return undoStack.length > 0;
}
export function undoLabel() {
  return undoStack[undoStack.length - 1]?.label ?? null;
}

export function undo() {
  const step = undoStack.pop();
  if (!step) return null;
  const now = Date.now();
  for (const it of [...step.items.values()].reverse()) {
    const arr = S[it.coll];
    const cur = arr.find((e) => e.id === it.id) || null;
    if (it.before) {
      const restored = clone(it.before);
      restored.updated = Math.max(now, num(cur?.updated) + 1, num(it.before.updated) + 1);
      cur ? replaceInPlace(cur, restored) : arr.push(restored);
    } else if (cur && !cur.deleted) {
      cur.deleted = now;
      cur.updated = Math.max(now, num(cur.updated) + 1);
    }
  }
  if (step.logIds.length) {
    const ids = new Set(step.logIds);
    S.log = S.log.filter((e) => !ids.has(e.id));
  }
  markDirty();
  emit({ type: "all", action: "undo", local: true });
  return step.label;
}

// ---------- Logbuch ----------
function addLogRaw(kind, text, { bag = null, task = null } = {}) {
  const e = { id: uid("e_"), t: Date.now(), kind: LOG_KINDS.has(kind) ? kind : "add", text: str(text), bag: bag || null, task: task || null };
  S.log.push(e);
  if (S.log.length > LIMITS.logMax) S.log.splice(0, S.log.length - LIMITS.logMax);
  if (txCur) txCur.logIds.push(e.id);
  return e;
}
// Eigener Logbuch-Eintrag (z. B. sync.js: „sync“, Rückblick: „review“)
export function addLog(kind, text, { bag = null, task = null } = {}) {
  const e = addLogRaw(kind, text, { bag, task });
  markDirty();
  emit({ type: "all", action: "update", local: kind !== "sync" }); // Sync-Einträge lösen keinen neuen Sync aus
  return e;
}
export function logEntries(limit = 50, bagId) {
  const out = [];
  for (let i = S.log.length - 1; i >= 0 && out.length < limit; i--) {
    const e = S.log[i];
    if (bagId === undefined || e.bag === bagId) out.push(e);
  }
  return out;
}

// ---------- Profil & Meta ----------
export function setProfile(patch = {}) {
  const next = normProfile({ ...S.profile, ...patch, updated: S.profile.updated });
  if (JSON.stringify(next) === JSON.stringify(S.profile)) return S.profile;
  next.updated = stamp(S.profile);
  S.profile = next;
  markDirty();
  emit({ type: "profile", action: "update", local: true });
  return S.profile;
}
// Meta ist nur lokal (wird nicht synchronisiert) → local: false, damit kein Sync ausgelöst wird
export function setMeta(patch = {}) {
  const next = normMeta(patch, S.meta);
  if (JSON.stringify(next) === JSON.stringify(S.meta)) return S.meta;
  S.meta = next;
  markDirty();
  emit({ type: "meta", action: "update", local: false });
  return S.meta;
}

// ---------- Taschen ----------
const maxOrder = (arr) => arr.reduce((m, e) => Math.max(m, num(e.order)), 0);
const PROTECTED = ["id", "created", "updated", "deleted"];
const cleanPatch = (patch) => {
  const p = { ...(patch && typeof patch === "object" ? patch : {}) };
  for (const k of PROTECTED) delete p[k];
  return p;
};

export function addBag(data = {}) {
  const name = str(data.name).trim();
  if (!name) throw new Error("Bitte gib der Tasche einen Namen.");
  return tx("Tasche angelegt", (b) => ({ type: "bag", id: b.id, action: "add" }), () => {
    const now = Date.now();
    const b = normBag({ emoji: "👜", color: "blue", status: "aktiv", sections: [], goal: "", deadline: null, pinned: false, ...cleanPatch(data), name, id: uid("b_"), created: now, updated: now, deleted: null, order: Number.isFinite(data.order) ? data.order : maxOrder(live(S.bags)) + 1 });
    insert("bags", b);
    addLogRaw("bag", `Tasche ${quote(name)} angelegt`, { bag: b.id });
    return b;
  });
}

export function updateBag(id, patch = {}) {
  const b = findLive("bags", id);
  if (!b) return null;
  return tx("Tasche geändert", { type: "bag", id, action: "update" }, () => {
    const p = cleanPatch(patch);
    if ("name" in p && !str(p.name).trim()) delete p.name;
    const wasDone = b.status === "fertig";
    if (change("bags", b, normBag({ ...b, ...p }))) {
      if (!wasDone && b.status === "fertig") addLogRaw("bag", `Tasche ${quote(b.name)} ist fertig 🎉`, { bag: b.id });
    }
    return b;
  }, { coalesce: "bag:" + id });
}

export function removeBag(id) {
  const b = findLive("bags", id);
  if (!b) return false;
  return tx("Tasche gelöscht", { type: "bag", id, action: "remove" }, () => {
    const now = Date.now();
    for (const c of ["tasks", "notes", "links", "files", "milestones"]) for (const e of S[c]) if (e.bag === id) tombstone(c, e, now);
    tombstone("bags", b, now);
    return true;
  });
}

export function reorderBags(ids = []) {
  return tx("Reihenfolge geändert", { type: "bag", action: "update" }, () => {
    ids.forEach((id, i) => {
      const b = findLive("bags", id);
      if (b && b.order !== i + 1) change("bags", b, { ...b, order: i + 1 });
    });
    return true;
  });
}

// Abschnitt bei Bedarf in der Tasche anlegen
function ensureSection(bagId, section) {
  const b = findLive("bags", bagId);
  if (!b || !section || b.sections.some((s) => s.toLowerCase() === section.toLowerCase())) return;
  change("bags", b, { ...b, sections: [...b.sections, section] });
}
// Gleichnamigen Abschnitt in der Schreibweise der Tasche verwenden
function sectionName(bagId, section) {
  const s = str(section).trim();
  const b = findLive("bags", bagId);
  return (b && b.sections.find((x) => x.toLowerCase() === s.toLowerCase())) || s;
}

// ---------- Aufgaben ----------
function taskFields(data, today) {
  const d = cleanPatch(data);
  if (d.plan === true) d.plan = today;
  else if (d.plan === false) d.plan = null;
  if (d.done === true) d.done = Date.now();
  else if (d.done === false) d.done = null;
  if ("bag" in d && d.bag && !findLive("bags", d.bag)) d.bag = null;
  if (Array.isArray(d.subtasks)) d.subtasks = d.subtasks.map(normSub).filter((s) => s.title);
  delete d.tokens;
  delete d.bagName;
  return d;
}

export function addTask(data = {}) {
  const title = str(data.title).trim();
  if (!title) throw new Error("Bitte gib einen Titel für die Aufgabe ein.");
  return tx("Aufgabe hinzugefügt", (t) => ({ type: "task", id: t.id, action: "add" }), () => {
    const now = Date.now();
    const d = taskFields(data, todayISO(new Date(now)));
    const bagId = d.bag || null;
    const t = normTask({
      notes: "", done: null, prio: 0, due: null, time: null, remind: null, repeat: null, section: "", tags: [], subtasks: [], plan: null, someday: false, est: null, waiting: "", milestone: null,
      ...d,
      title,
      bag: bagId,
      section: sectionName(bagId, d.section),
      id: uid("t_"),
      created: now,
      updated: now,
      deleted: null,
      order: Number.isFinite(d.order) ? d.order : maxOrder(live(S.tasks).filter((x) => (x.bag || null) === bagId)) + 1,
    });
    if (t.bag && t.section) ensureSection(t.bag, t.section);
    insert("tasks", t);
    addLogRaw("add", `${quote(t.title)} hinzugefügt`, { bag: t.bag, task: t.id });
    return t;
  });
}

export function duplicateTask(id) {
  const t = findLive("tasks", id);
  if (!t) return null;
  const { id: _i, created: _c, updated: _u, deleted: _d, done: _done, ...rest } = clone(t);
  return addTask({ ...rest, title: t.title, order: t.order + 0.001, subtasks: t.subtasks.map((s) => ({ title: s.title, done: false })) });
}

export function updateTask(id, patch = {}) {
  const t = findLive("tasks", id);
  if (!t) return null;
  return tx("Aufgabe geändert", { type: "task", id, action: "update" }, () => {
    const today = todayISO();
    const p = taskFields(patch, today);
    if ("title" in p && !str(p.title).trim()) delete p.title;
    const next = normTask({ ...t, ...p });
    if ("bag" in p && next.bag !== t.bag && !("section" in p)) next.section = ""; // Abschnitt gehört zur alten Tasche
    if ("section" in p || "bag" in p) next.section = next.bag ? sectionName(next.bag, next.section) : "";
    if ("due" in p && p.due !== t.due && !("repeatDay" in p)) delete next.repeatDay; // Datum von Hand geändert → neuer Anker
    if ("bag" in p && next.bag !== t.bag && !("order" in p)) next.order = maxOrder(live(S.tasks).filter((x) => (x.bag || null) === next.bag && x.id !== t.id)) + 1;
    const movedTo = "bag" in p && next.bag !== t.bag ? next.bag : undefined;
    if (change("tasks", t, next)) {
      if (t.bag && t.section) ensureSection(t.bag, t.section);
      if (movedTo !== undefined) addLogRaw("move", `${quote(t.title)} → ${movedTo ? bagLabel(movedTo) : "Eingang"}`, { bag: movedTo, task: t.id });
    }
    return t;
  }, { coalesce: "task:" + id + ":" + Object.keys(patch || {}).sort().join(",") });
}

const bagLabel = (id) => {
  const b = findRaw("bags", id);
  return b ? `${b.emoji} ${b.name}` : "Tasche";
};

export function completeTask(id) {
  const t = findLive("tasks", id);
  if (!t) return { task: null, next: null };
  if (t.done) return { task: t, next: null };
  return tx("Aufgabe erledigt", (r) => ({ type: "task", id, action: "update", next: r.next?.id }), () => {
    const now = Date.now();
    const today = todayISO(new Date(now));
    change("tasks", t, { ...t, done: now, subtasks: t.subtasks.map((s) => ({ ...s, done: true })) });
    let next = null;
    if (t.repeat) {
      const monthly = t.repeat === "monthly" || t.repeat === "yearly";
      const anchor = monthly ? (Number.isInteger(t.repeatDay) ? t.repeatDay : t.due ? +t.due.slice(8, 10) : undefined) : undefined;
      const due = nextOccurrence(t.due || today, t.repeat, today, anchor);
      const src = clone(t);
      next = normTask({ ...src, id: uid("t_"), created: now, updated: now, deleted: null, done: null, due, plan: null, subtasks: src.subtasks.map((s) => ({ id: uid("s_"), title: s.title, done: false })), repeatDay: undefined });
      if (monthly && anchor && due && +due.slice(8, 10) !== anchor) next.repeatDay = anchor; // 31. bleibt Anker, auch wenn der Februar nur 28 Tage hat
      insert("tasks", next);
    }
    addLogRaw("done", `${quote(t.title)} erledigt`, { bag: t.bag, task: t.id });
    return { task: t, next };
  });
}

export function reopenTask(id) {
  const t = findLive("tasks", id);
  if (!t || !t.done) return t;
  return tx("Aufgabe wieder geöffnet", { type: "task", id, action: "update" }, () => {
    const doneAt = t.done;
    let repeat = t.repeat;
    if (t.repeat) {
      // Die beim Erledigen erzeugte Folge-Aufgabe wieder entfernen – sonst gäbe es die Serie doppelt
      const spawned = live(S.tasks).filter((x) => x.id !== t.id && !x.done && x.repeat === t.repeat && x.title === t.title && (x.bag || null) === (t.bag || null) && x.created >= doneAt - 2000);
      const untouched = spawned.find((x) => x.updated === x.created);
      if (untouched) tombstone("tasks", untouched);
      else if (spawned.length) repeat = null; // Serie läuft in der bearbeiteten Folge-Aufgabe weiter
    }
    change("tasks", t, { ...t, done: null, repeat });
    return t;
  });
}

export function toggleTask(id) {
  const t = findLive("tasks", id);
  if (!t) return { task: null, next: null, done: false };
  if (t.done) {
    reopenTask(id);
    return { task: t, next: null, done: false };
  }
  const r = completeTask(id);
  return { ...r, done: true };
}

export function removeTask(id) {
  const t = findLive("tasks", id);
  if (!t) return false;
  return tx("Aufgabe gelöscht", { type: "task", id, action: "remove" }, () => tombstone("tasks", t));
}

export function moveTask(id, bagId = null, section = "") {
  const t = findLive("tasks", id);
  if (!t) return null;
  const target = bagId && findLive("bags", bagId) ? bagId : null;
  return tx("Aufgabe verschoben", { type: "task", id, action: "update" }, () => {
    const sec = target ? sectionName(target, section) : "";
    const sameBag = (t.bag || null) === target;
    const order = sameBag ? t.order : maxOrder(live(S.tasks).filter((x) => (x.bag || null) === target && x.id !== t.id)) + 1;
    if (change("tasks", t, { ...t, bag: target, section: sec, order })) {
      if (target && sec) ensureSection(target, sec);
      if (!sameBag) addLogRaw("move", `${quote(t.title)} → ${target ? bagLabel(target) : "Eingang"}`, { bag: target, task: t.id });
    }
    return t;
  });
}

// Vor beforeId einsortieren (null = ans Ende); Kommazahlen, bei Bedarf neu durchnummerieren
export function reorderTask(id, beforeId = null) {
  const t = findLive("tasks", id);
  if (!t || id === beforeId) return null;
  return tx("Reihenfolge geändert", { type: "task", id, action: "update" }, () => {
    const sibs = live(S.tasks).filter((x) => (x.bag || null) === (t.bag || null) && x.id !== t.id).sort(byOrder);
    const before = beforeId ? sibs.find((x) => x.id === beforeId) : null;
    if (!before) {
      change("tasks", t, { ...t, order: (sibs.length ? num(sibs[sibs.length - 1].order) : 0) + 1 });
      return t;
    }
    let i = sibs.indexOf(before);
    let prev = sibs[i - 1];
    let o = prev ? (num(prev.order) + num(before.order)) / 2 : num(before.order) - 1;
    if (prev && (o <= num(prev.order) || o >= num(before.order))) {
      sibs.forEach((x, k) => x.order !== k + 1 && change("tasks", x, { ...x, order: k + 1 }));
      o = i + 0.5;
    }
    change("tasks", t, { ...t, order: o });
    return t;
  });
}

export function planTask(id, iso = null) {
  const t = findLive("tasks", id);
  if (!t) return null;
  const plan = iso === true ? todayISO() : isISO(iso) ? iso : null;
  return tx(plan ? "Eingeplant" : "Einplanung entfernt", { type: "task", id, action: "update" }, () => {
    change("tasks", t, { ...t, plan, someday: plan ? false : t.someday });
    return t;
  });
}

// ---------- Unteraufgaben ----------
export function addSubtask(taskId, title) {
  const t = findLive("tasks", taskId);
  const s = str(title).trim();
  if (!t) return null;
  if (!s) throw new Error("Bitte gib einen Titel ein.");
  return tx("Unteraufgabe hinzugefügt", { type: "task", id: taskId, action: "update" }, () => {
    const sub = { id: uid("s_"), title: s, done: false };
    change("tasks", t, { ...t, subtasks: [...t.subtasks, sub] });
    return sub;
  });
}
export function toggleSubtask(taskId, subId) {
  const t = findLive("tasks", taskId);
  if (!t || !t.subtasks.some((s) => s.id === subId)) return null;
  return tx("Unteraufgabe abgehakt", { type: "task", id: taskId, action: "update" }, () => {
    change("tasks", t, { ...t, subtasks: t.subtasks.map((s) => (s.id === subId ? { ...s, done: !s.done } : s)) });
    return t.subtasks.find((s) => s.id === subId);
  });
}
export function updateSubtask(taskId, subId, title) {
  const t = findLive("tasks", taskId);
  const s = str(title).trim();
  if (!t || !s || !t.subtasks.some((x) => x.id === subId)) return null;
  return tx("Unteraufgabe geändert", { type: "task", id: taskId, action: "update" }, () => {
    change("tasks", t, { ...t, subtasks: t.subtasks.map((x) => (x.id === subId ? { ...x, title: s } : x)) });
    return t.subtasks.find((x) => x.id === subId);
  }, { coalesce: "sub:" + subId });
}
export function removeSubtask(taskId, subId) {
  const t = findLive("tasks", taskId);
  if (!t || !t.subtasks.some((x) => x.id === subId)) return false;
  return tx("Unteraufgabe gelöscht", { type: "task", id: taskId, action: "update" }, () => change("tasks", t, { ...t, subtasks: t.subtasks.filter((x) => x.id !== subId) }));
}
export function reorderSubtasks(taskId, ids = []) {
  const t = findLive("tasks", taskId);
  if (!t) return null;
  const pos = new Map(ids.map((id, i) => [id, i]));
  return tx("Reihenfolge geändert", { type: "task", id: taskId, action: "update" }, () => {
    change("tasks", t, { ...t, subtasks: [...t.subtasks].sort((a, b) => (pos.get(a.id) ?? 1e9) - (pos.get(b.id) ?? 1e9)) });
    return t;
  });
}

// ---------- Notizen ----------
const bagOrNull = (id) => (id && findLive("bags", id) ? id : null);

export function addNote(data = {}) {
  return tx("Notiz angelegt", (n) => ({ type: "note", id: n.id, action: "add" }), () => {
    const now = Date.now();
    const n = normNote({ title: "", body: "", pinned: false, ...cleanPatch(data), bag: bagOrNull(data.bag), id: uid("n_"), created: now, updated: now, deleted: null });
    insert("notes", n);
    addLogRaw("note", `Notiz ${quote(n.title || "Ohne Titel")} angelegt`, { bag: n.bag });
    return n;
  });
}
export function updateNote(id, patch = {}) {
  const n = findLive("notes", id);
  if (!n) return null;
  return tx("Notiz geändert", { type: "note", id, action: "update" }, () => {
    const p = cleanPatch(patch);
    if ("bag" in p) p.bag = bagOrNull(p.bag);
    change("notes", n, normNote({ ...n, ...p }));
    return n;
  }, { coalesce: "note:" + id });
}
export function removeNote(id) {
  const n = findLive("notes", id);
  if (!n) return false;
  return tx("Notiz gelöscht", { type: "note", id, action: "remove" }, () => tombstone("notes", n));
}

// ---------- Links ----------
// "notar.de/termin" → "https://notar.de/termin"; relative Angaben werden abgelehnt
function normUrl(raw) {
  const s = str(raw).trim();
  const u = /^[\w-]+(\.[\w-]+)*\.[a-z]{2,}(?::\d+)?(\/|\?|#|$)/i.test(s) ? "https://" + s : s;
  return /^(https?:\/\/|mailto:)/i.test(u) ? safeUrl(u) : "";
}
const hostOf = (u) => {
  try {
    return new URL(u).hostname.replace(/^www\./, "");
  } catch (_) {
    return u;
  }
};
export function addLink(data = {}) {
  const url = normUrl(data.url);
  if (!url) throw new Error("Bitte gib einen gültigen Link ein (https://…).");
  return tx("Link hinzugefügt", (l) => ({ type: "link", id: l.id, action: "add" }), () => {
    const now = Date.now();
    const l = normLink({ ...cleanPatch(data), title: str(data.title).trim() || hostOf(url), url, bag: bagOrNull(data.bag), id: uid("l_"), created: now, updated: now, deleted: null });
    insert("links", l);
    addLogRaw("link", `Link ${quote(l.title)} gespeichert`, { bag: l.bag });
    return l;
  });
}
export function updateLink(id, patch = {}) {
  const l = findLive("links", id);
  if (!l) return null;
  const p = cleanPatch(patch);
  if ("url" in p) {
    const url = normUrl(p.url);
    if (!url) throw new Error("Bitte gib einen gültigen Link ein (https://…).");
    p.url = url;
  }
  if ("bag" in p) p.bag = bagOrNull(p.bag);
  return tx("Link geändert", { type: "link", id, action: "update" }, () => {
    change("links", l, normLink({ ...l, ...p }));
    return l;
  }, { coalesce: "link:" + id });
}
export function removeLink(id) {
  const l = findLive("links", id);
  if (!l) return false;
  return tx("Link gelöscht", { type: "link", id, action: "remove" }, () => tombstone("links", l));
}

// ---------- Meilensteine ----------
export function addMilestone(data = {}) {
  const title = str(data.title).trim();
  if (!title) throw new Error("Bitte gib dem Meilenstein einen Titel.");
  return tx("Meilenstein angelegt", (m) => ({ type: "bag", id: m.bag, action: "add", milestone: m.id }), () => {
    const now = Date.now();
    const m = normMilestone({ date: null, done: null, ...cleanPatch(data), title, bag: bagOrNull(data.bag), id: uid("m_"), created: now, updated: now, deleted: null });
    insert("milestones", m);
    addLogRaw("add", `Meilenstein ${quote(title)} angelegt`, { bag: m.bag });
    return m;
  });
}
export function updateMilestone(id, patch = {}) {
  const m = findLive("milestones", id);
  if (!m) return null;
  return tx("Meilenstein geändert", { type: "bag", id: m.bag, action: "update", milestone: id }, () => {
    const p = cleanPatch(patch);
    if ("title" in p && !str(p.title).trim()) delete p.title;
    if ("bag" in p) p.bag = bagOrNull(p.bag);
    if (p.done === true) p.done = Date.now();
    if (p.done === false) p.done = null;
    change("milestones", m, normMilestone({ ...m, ...p }));
    return m;
  }, { coalesce: "ms:" + id });
}
export function toggleMilestone(id) {
  const m = findLive("milestones", id);
  if (!m) return null;
  return tx(m.done ? "Meilenstein wieder geöffnet" : "Meilenstein erreicht", { type: "bag", id: m.bag, action: "update", milestone: id }, () => {
    const done = m.done ? null : Date.now();
    change("milestones", m, { ...m, done });
    if (done) addLogRaw("done", `Meilenstein ${quote(m.title)} erreicht 🏁`, { bag: m.bag });
    return m;
  });
}
export function removeMilestone(id) {
  const m = findLive("milestones", id);
  if (!m) return false;
  return tx("Meilenstein gelöscht", { type: "bag", id: m.bag, action: "remove", milestone: id }, () => {
    for (const t of S.tasks) if (t.milestone === id && !t.deleted) change("tasks", t, { ...t, milestone: null });
    return tombstone("milestones", m);
  });
}

// ---------- Dateien ----------
export async function addFile(bagId, f) {
  await ensureAdapter();
  if (!f || typeof f.size !== "number") throw new Error("Das ist keine Datei.");
  const name = str(f.name).trim() || "Datei";
  if (f.size > LIMITS.fileMax) throw new Error(`${quote(name)} ist zu groß (${fmtSize(f.size)}) – erlaubt sind höchstens ${Math.round(LIMITS.fileMax / 1048576)} MB pro Datei.`);
  if (!adapter.files) throw new Error("Dateien kann dieser Browser gerade nicht speichern (kein IndexedDB – z. B. im privaten Modus).");
  const id = uid("f_");
  try {
    await adapter.filePut(id, f);
  } catch (e) {
    throw new Error(/quota/i.test(String(e?.name) + String(e?.message)) ? "Der Speicher ist voll – lösche ein paar Dateien und versuch es noch mal." : `${quote(name)} konnte nicht gespeichert werden.`);
  }
  return tx("Datei hinzugefügt", (m) => ({ type: "file", id: m.id, action: "add" }), () => {
    const now = Date.now();
    const meta = normFile({ id, created: now, updated: now, deleted: null, bag: bagOrNull(bagId), name, type: str(f.type) || "application/octet-stream", size: f.size, synced: false });
    insert("files", meta);
    addLogRaw("file", `Datei ${quote(name)} hinzugefügt`, { bag: meta.bag });
    return meta;
  });
}
export async function fileBlob(id) {
  await ensureAdapter();
  try {
    return (await adapter.fileGet(id)) ?? null;
  } catch (_) {
    return null;
  }
}
export async function putFileBlob(id, blob) {
  await ensureAdapter();
  return adapter.filePut(id, blob);
}
export function removeFile(id) {
  const f = findLive("files", id);
  if (!f) return false;
  // Inhalt bleibt bis zum Aufräumen der Grabsteine liegen – so kann man das Löschen rückgängig machen
  return tx("Datei gelöscht", { type: "file", id, action: "remove" }, () => tombstone("files", f));
}
// Datei umbenennen oder in eine andere Tasche legen (Inhalt bleibt unverändert)
export function updateFile(id, patch = {}) {
  const f = findLive("files", id);
  if (!f) return null;
  const p = {};
  if ("name" in patch && str(patch.name).trim()) p.name = str(patch.name).trim();
  if ("bag" in patch) p.bag = bagOrNull(patch.bag);
  return tx("Datei geändert", { type: "file", id, action: "update" }, () => {
    change("files", f, normFile({ ...f, ...p }));
    return f;
  }, { coalesce: "file:" + id });
}

// Für sync.js: Datei als hochgeladen markieren (nur lokal, ändert updated nicht)
export function markFileSynced(id, synced = true) {
  const f = findRaw("files", id);
  if (!f || f.synced === !!synced) return;
  f.synced = !!synced;
  markDirty();
  emit({ type: "file", id, action: "update", local: false });
}

// ---------- Verbundene Konten (Google, Microsoft) ----------
// Kein Rückgängig-Schritt (label null): Verbinden und Trennen passieren auch auf dem Server – ⌘Z soll das nicht still umkehren.
const ACC_COLORS = ["blue", "orange", "green", "purple", "teal", "pink", "indigo", "red", "mint", "brown"];
export const accounts = () => live(S.accounts).sort((a, b) => a.created - b.created || (a.id < b.id ? -1 : 1));
export const account = (id) => findLive("accounts", id);

export function addAccount(data = {}) {
  const d = cleanPatch(data);
  const provider = str(data.provider).trim().toLowerCase();
  if (!provider) throw new Error("Unbekannter Anbieter.");
  const id = str(data.id).trim();
  const existing = id ? findRaw("accounts", id) : null;
  return tx(null, (a) => ({ type: "account", id: a.id, action: existing ? "update" : "add" }), () => {
    const now = Date.now();
    if (existing) {
      // dieselbe Verbindung kommt erneut an (z. B. zweimal zurückgekehrt) → auffrischen, Grabstein aufheben
      change("accounts", existing, normAccount({ ...existing, ...d, provider, deleted: null, broken: false }));
      return existing;
    }
    const used = new Set(live(S.accounts).map((x) => x.color));
    const color = COLORS[d.color] ? d.color : ACC_COLORS.find((c) => !used.has(c)) || "blue";
    const a = normAccount({ calendars: true, mail: true, ...d, provider, color, broken: false, id: id || uid("a_"), created: now, updated: now, deleted: null });
    insert("accounts", a);
    return a;
  });
}

export function updateAccount(id, patch = {}) {
  const a = findLive("accounts", id);
  if (!a) return null;
  return tx(null, { type: "account", id, action: "update" }, () => {
    const p = cleanPatch(patch);
    delete p.provider; // ein Konto wechselt nie den Anbieter
    change("accounts", a, normAccount({ ...a, ...p }));
    return a;
  });
}

export function removeAccount(id) {
  const a = findLive("accounts", id);
  if (!a) return false;
  return tx(null, { type: "account", id, action: "remove" }, () => {
    a.secret = ""; // der Schlüssel verschwindet mit dem Konto (auch aus dem Sync)
    return tombstone("accounts", a);
  });
}

// ---------- Grabsteine aufräumen ----------
function purgeTombstones(now = Date.now()) {
  const cut = now - LIMITS.tombstoneDays * DAY;
  let any = false;
  for (const c of COLLS) {
    const keep = [];
    for (const e of S[c]) {
      if (e.deleted && e.deleted < cut) {
        any = true;
        if (c === "files" && adapter) adapter.fileDel(e.id).catch(() => {});
      } else keep.push(e);
    }
    if (keep.length !== S[c].length) S[c] = keep;
  }
  return any;
}

// ---------- Sync: Nutzlast & Zusammenführen ----------
export function syncPayload() {
  const out = { v: S.v, profile: S.profile, bags: S.bags, tasks: S.tasks, notes: S.notes, links: S.links, files: S.files, milestones: S.milestones, log: S.log };
  if (S.accounts.length) out.accounts = S.accounts; // nur wenn es Konten (oder deren Grabsteine) gibt
  return clone(out);
}

// Last-Writer-Wins pro id (Gleichstand: lokal behalten); Grabsteine sind normale Fassungen mit deleted ≠ null
function mergeInto(remote) {
  let changed = false;
  const cut = Date.now() - LIMITS.tombstoneDays * DAY;
  for (const c of COLLS) {
    const arr = Array.isArray(remote[c]) ? remote[c] : [];
    if (!arr.length) continue;
    const idx = new Map(S[c].map((e, i) => [e.id, i]));
    for (const r0 of arr) {
      if (!validEntity(r0)) continue;
      const r = NORM[c](clone(r0));
      const i = idx.get(r.id);
      if (c === "accounts" && i !== undefined) {
        // Ein Konto ohne Schlüssel (z. B. aus einem Backup) darf einen vorhandenen Schlüssel nie überschreiben – und umgekehrt kommt er dazu
        const cur = S[c][i];
        if (!r.deleted && !r.secret && cur.secret) r.secret = cur.secret;
        if (!cur.deleted && !cur.secret && r.secret && r.updated <= num(cur.updated)) {
          cur.secret = r.secret;
          changed = true;
        }
      }
      if (i === undefined) {
        if (r.deleted && r.deleted < cut) continue;
        S[c].push(r);
        idx.set(r.id, S[c].length - 1);
        changed = true;
      } else if (r.updated > num(S[c][i].updated)) {
        replaceInPlace(S[c][i], r);
        changed = true;
      }
    }
  }
  if (remote.profile && typeof remote.profile === "object" && num(remote.profile.updated) > num(S.profile.updated)) {
    S.profile = normProfile(remote.profile);
    changed = true;
  }
  if (Array.isArray(remote.log) && remote.log.length) {
    const have = new Set(S.log.map((e) => e.id));
    const add = remote.log.map(normLog).filter((e) => e && !have.has(e.id));
    if (add.length) {
      S.log = [...S.log, ...add].sort((a, b) => a.t - b.t).slice(-LIMITS.logMax);
      changed = true;
    }
  }
  if (purgeTombstones()) changed = true;
  return changed;
}

export function merge(remote) {
  if (!remote || typeof remote !== "object") return { changed: false };
  const changed = mergeInto(remote);
  if (changed) {
    markDirty();
    emit({ type: "all", action: "merge", local: false });
  }
  return { changed };
}

// ---------- Backup ----------
async function blobToBase64(blob) {
  const buf = new Uint8Array(await blob.arrayBuffer());
  let s = "";
  for (let i = 0; i < buf.length; i += 0x8000) s += String.fromCharCode.apply(null, buf.subarray(i, i + 0x8000));
  return btoa(s);
}
function base64ToBlob(b64, type) {
  const bin = atob(b64);
  const u = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
  return new Blob([u], { type: type || "application/octet-stream" });
}

export async function exportBackup({ includeFiles = true } = {}) {
  await ensureAdapter();
  const list = [];
  if (includeFiles && adapter.files) {
    for (const f of live(S.files)) {
      const blob = await fileBlob(f.id);
      if (blob) list.push({ id: f.id, name: f.name, type: f.type || blob.type || "", data: await blobToBase64(blob) });
    }
  }
  const state = syncPayload();
  // Verbundene Konten ohne Schlüssel: Ein Backup liegt oft offen in iCloud Drive – nach einem Import einfach neu verbinden
  if (state.accounts) state.accounts = state.accounts.map((a) => ({ ...a, secret: "" }));
  const json = JSON.stringify({ app: "arbeitstaschen", v: STATE_VERSION, exported: new Date().toISOString(), state, meta: clone(S.meta), files: list });
  setMeta({ lastBackup: Date.now() });
  return new Blob([json], { type: "application/json" });
}

export async function importBackup(fileOrText, { mode = "merge" } = {}) {
  if (mode !== "merge" && mode !== "replace") throw new Error("Unbekannter Import-Modus – erlaubt sind „merge“ und „replace“.");
  let data = null;
  if (typeof fileOrText === "string") data = parseJSON(fileOrText);
  else if (fileOrText && typeof fileOrText.text === "function") data = parseJSON(await fileOrText.text());
  else if (fileOrText && typeof fileOrText === "object") data = fileOrText;
  else throw new Error("Bitte wähle eine Backup-Datei aus.");
  if (!data || typeof data !== "object" || data.app !== "arbeitstaschen") throw new Error("Das ist kein Arbeitstaschen-Backup.");
  if (typeof data.v !== "number" || data.v < 1) throw new Error("Das Backup ist beschädigt: Die Versionsangabe fehlt.");
  if (data.v > STATE_VERSION) throw new Error("Dieses Backup stammt aus einer neueren Version der App – bitte aktualisiere die App zuerst.");
  const st = data.state;
  if (!st || typeof st !== "object" || Array.isArray(st)) throw new Error("Das Backup ist beschädigt: Es enthält keine Daten.");
  const names = { bags: "Taschen", tasks: "Aufgaben", notes: "Notizen", links: "Links", files: "Dateien", milestones: "Meilensteine", accounts: "Konten", log: "Logbuch" };
  for (const c of [...COLLS, "log"]) if (st[c] !== undefined && !Array.isArray(st[c])) throw new Error(`Das Backup ist beschädigt: „${names[c]}“ ist keine Liste.`);
  if (data.files !== undefined && !Array.isArray(data.files)) throw new Error("Das Backup ist beschädigt: „Dateien“ ist keine Liste.");
  await ensureAdapter();

  // Datei-Inhalte zuerst, damit die Einträge sofort öffnen
  for (const f of data.files || []) {
    if (!f || typeof f.id !== "string" || typeof f.data !== "string" || !adapter.files) continue;
    try {
      await adapter.filePut(f.id, base64ToBlob(f.data, f.type));
    } catch (_) {
      /* einzelne kaputte Datei überspringen */
    }
  }
  const incoming = normalizeState({ ...st, meta: data.meta });
  // Konten aus dem Backup haben keinen Schlüssel – ist das Konto hier schon verbunden, bleibt dessen Schlüssel erhalten
  for (const a of incoming.accounts) {
    const mine = findRaw("accounts", a.id);
    if (!a.secret && mine?.secret && !a.deleted) a.secret = mine.secret;
  }
  const counts = Object.fromEntries(["bags", "tasks", "notes", "links", "files"].map((c) => [c, live(incoming[c]).length]));

  if (mode === "replace") {
    // Ersetzen: Alles, was nicht im Backup ist, bekommt einen Grabstein; Backup-Einträge bekommen frische Zeitstempel,
    // damit sie auch auf den anderen Geräten gewinnen.
    const now = Date.now();
    for (const c of COLLS) {
      if (c === "accounts" && !Array.isArray(st.accounts)) continue; // älteres Backup ohne Konten: verbundene Konten bleiben
      const ids = new Set(incoming[c].map((e) => e.id));
      for (const e of S[c]) if (!ids.has(e.id) && !e.deleted) (e.deleted = now), (e.updated = stamp(e));
      const idx = new Map(S[c].map((e, i) => [e.id, i]));
      for (const r of incoming[c]) {
        const i = idx.get(r.id);
        r.updated = Math.max(now, num(r.updated) + 1, i === undefined ? 0 : num(S[c][i].updated) + 1);
        i === undefined ? S[c].push(r) : replaceInPlace(S[c][i], r);
      }
    }
    S.profile = { ...incoming.profile, updated: stamp(S.profile) };
    const have = new Set(S.log.map((e) => e.id));
    S.log = [...S.log, ...incoming.log.filter((e) => !have.has(e.id))].sort((a, b) => a.t - b.t).slice(-LIMITS.logMax);
    const m = incoming.meta;
    S.meta = normMeta({ lastReview: [S.meta.lastReview, m.lastReview].filter(Boolean).sort().pop() || null, seeded: S.meta.seeded || m.seeded }, S.meta);
    undoStack = [];
    purgeTombstones();
  } else {
    mergeInto(incoming);
  }
  addLogRaw("import", `Backup importiert: ${counts.bags} ${counts.bags === 1 ? "Tasche" : "Taschen"}, ${counts.tasks} ${counts.tasks === 1 ? "Aufgabe" : "Aufgaben"}`);
  markDirty();
  emit({ type: "all", action: "import", local: true });
  await flush();
  return counts;
}
function parseJSON(text) {
  try {
    return JSON.parse(String(text).replace(/^﻿/, ""));
  } catch (_) {
    throw new Error("Die Datei ist kein gültiges Backup – sie enthält kein lesbares JSON.");
  }
}

// ---------- Beispiel-/Startdaten (seed.js) ----------
const PRIO_WORDS = { hoch: 3, high: 3, mittel: 2, medium: 2, niedrig: 1, low: 1, keine: 0 };
export function applySeed(seed, { mode = "replace" } = {}) {
  const list = Array.isArray(seed?.bags) ? seed.bags : [];
  const now = Date.now();
  const today = todayISO(new Date(now));
  const counts = { bags: 0, tasks: 0, notes: 0, links: 0, milestones: 0 };
  if (mode === "replace") {
    for (const c of PROJECT_COLLS) for (const e of S[c]) if (!e.deleted) (e.deleted = now), (e.updated = stamp(e));
    undoStack = [];
  }
  let order = maxOrder(live(S.bags));
  let doneIdx = 0;
  const due = (n) => (Number.isFinite(n) ? addDays(today, Math.round(n)) : null);
  for (const sb of list) {
    if (!sb || !str(sb.name).trim()) continue;
    const name = str(sb.name).trim();
    const seedTasks = Array.isArray(sb.tasks) ? sb.tasks : [];
    let sections = strList(sb.sections);
    if (!sections.length) sections = strList(seedTasks.map((t) => t?.section)); // Abschnitte aus den Aufgaben ableiten
    let b = mode === "merge" ? live(S.bags).find((x) => normName(x.name) === normName(name)) : null;
    if (!b) {
      b = normBag({ id: uid("b_"), created: now, updated: now, deleted: null, name, emoji: sb.emoji, color: sb.color, goal: sb.goal, status: STATUSES.includes(sb.status) ? sb.status : "aktiv", deadline: Number.isFinite(sb.deadlineIn) ? due(sb.deadlineIn) : isISO(sb.deadline) ? sb.deadline : null, sections, order: ++order, pinned: !!sb.pinned });
      S.bags.push(b);
      counts.bags++;
    } else if (sections.some((s) => !b.sections.includes(s))) {
      b.sections = strList([...b.sections, ...sections]);
      b.updated = stamp(b);
    }
    const has = (coll, title) => live(S[coll]).some((x) => x.bag === b.id && normName(x.title) === normName(title));
    const msIds = new Map();
    for (const sm of Array.isArray(sb.milestones) ? sb.milestones : []) {
      const title = str(sm?.title).trim();
      if (!title || has("milestones", title)) continue;
      const m = normMilestone({ id: uid("m_"), created: now, updated: now, deleted: null, bag: b.id, title, date: Number.isFinite(sm.dueIn) ? due(sm.dueIn) : isISO(sm.date) ? sm.date : null, done: sm.done ? now - DAY : null });
      S.milestones.push(m);
      msIds.set(normName(title), m.id);
      counts.milestones++;
    }
    let tOrder = maxOrder(live(S.tasks).filter((x) => x.bag === b.id));
    for (const st of seedTasks) {
      const title = str(st?.title).trim();
      if (!title || has("tasks", title)) continue;
      const isDone = st.done === true || st.status === "erledigt";
      // Erledigtes liegt ein paar Tage zurück (gestaffelt), damit Fortschritt und Rückblick echt aussehen
      const doneAt = isDone ? now - (2 + (doneIdx++ % 6)) * DAY - (doneIdx % 5) * 3600000 : null;
      const prio = typeof st.prio === "number" ? st.prio : PRIO_WORDS[str(st.prio ?? st.priority).toLowerCase()] ?? 0;
      const t = normTask({
        id: uid("t_"), created: doneAt ? doneAt - 7 * DAY : now, updated: now, deleted: null, bag: b.id, title, notes: str(st.notes), done: doneAt, prio,
        due: isDone ? null : due(st.dueIn), time: isDone ? null : st.time, remind: null, repeat: REPEAT_IDS.has(st.repeat) ? st.repeat : null, section: str(st.section).trim(), tags: st.tags,
        subtasks: (Array.isArray(st.subtasks) ? st.subtasks : []).map((s) => (typeof s === "string" ? { title: s, done: isDone } : { ...s, done: isDone || !!s?.done })),
        plan: null, someday: !!st.someday, order: ++tOrder, est: st.est ?? null, waiting: str(st.waiting), milestone: st.milestone ? msIds.get(normName(st.milestone)) ?? null : null,
      });
      if (t.section && !b.sections.includes(t.section)) b.sections = [...b.sections, t.section];
      S.tasks.push(t);
      counts.tasks++;
    }
    for (const sn of Array.isArray(sb.notes) ? sb.notes : []) {
      const title = str(sn?.title).trim();
      if (!title || has("notes", title)) continue;
      S.notes.push(normNote({ id: uid("n_"), created: now, updated: now, deleted: null, bag: b.id, title, body: str(sn.body), pinned: !!sn.pinned }));
      counts.notes++;
    }
    for (const sl of Array.isArray(sb.links) ? sb.links : []) {
      const url = normUrl(sl?.url);
      const title = str(sl?.title).trim() || hostOf(url);
      if (!url || has("links", title)) continue;
      S.links.push(normLink({ id: uid("l_"), created: now, updated: now, deleted: null, bag: b.id, title, url }));
      counts.links++;
    }
  }
  S.meta = normMeta({ seeded: true }, S.meta);
  addLogRaw("seed", `Deine Projekte sind geladen: ${counts.bags} ${counts.bags === 1 ? "Tasche" : "Taschen"} mit ${counts.tasks} Aufgaben`);
  markDirty();
  emit({ type: "all", action: "seed", local: true });
  return counts;
}

// ---------- Zurücksetzen & Sonstiges ----------
export async function resetAll() {
  if (saveTimer) clearTimeout(saveTimer), (saveTimer = null);
  dirty = false;
  await writing.catch(() => {});
  await ensureAdapter();
  S = fresh();
  undoStack = [];
  try {
    for (const k of await adapter.keys()) if (k !== "device") await adapter.del(k);
  } catch (_) {
    /* weiter mit den Dateien */
  }
  try {
    await adapter.fileClear();
  } catch (_) {
    /* nichts zu löschen */
  }
  emit({ type: "all", action: "reset", local: false });
}

export async function requestPersist() {
  try {
    if (typeof navigator === "undefined" || !navigator.storage?.persist) return false;
    if (await navigator.storage.persisted?.()) return true;
    return !!(await navigator.storage.persist());
  } catch (_) {
    return false;
  }
}

export const deviceId = () => device || "";

export async function kvGet(key) {
  await ensureAdapter();
  try {
    return await adapter.get(key);
  } catch (_) {
    return undefined;
  }
}
export async function kvSet(key, value) {
  await ensureAdapter();
  if (key === "state") throw new Error("Der Zustand wird nur über den Store gespeichert.");
  return adapter.set(key, value);
}
