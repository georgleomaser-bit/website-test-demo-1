// Arbeitstaschen – Erinnerungen für iPhone, iPad und Mac: Mitteilungen, Zähler am App-Symbol, Kalender (.ics), Kurzbefehle und Push über deinen Server
import { BRAND, DEFAULT_PROFILE, PRIOS, SERVER } from "./config.js";
import { isISO, addDays, weekday, parseTime, atLocal, toISO, todayISO, fmtDuration } from "./dates.js";
import { checkServer, normServer, detectServer, request, status as syncStatus } from "./sync.js";
import { eventReminders, eventSummary } from "./connect.js";

// ---------- Grundlagen ----------
// Beim Import nichts von window/document/navigator anfassen – der ICS-Teil läuft auch in Node (Tests).
const MIN = 60000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;
const CATCHUP = 15 * MIN; // verpasste Erinnerungen so lange nachholen (z. B. nach dem Zurückkehren in die App)
const HORIZON_DAYS = 8; // so weit reicht der Plan für den Service Worker und den Push-Server
const BRIEF_DAYS = 7; // Tagesbriefings im Voraus (für Push bei geschlossener App)
const TIMER_AHEAD = DAY; // Zeitgeber nur für die nächsten 24 Stunden

const hasWin = () => typeof window !== "undefined" && typeof document !== "undefined";
const hasNav = () => typeof navigator !== "undefined";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const pad = (n) => String(n).padStart(2, "0");
const hhmm = (min) => `${pad(Math.floor(min / 60) % 24)}:${pad(min % 60)}`;
const trunc = (s, n) => {
  const t = String(s ?? "")
    .replace(/\s+/g, " ")
    .trim();
  return t.length > n ? t.slice(0, n - 1).trimEnd() + "…" : t;
};
const profileOf = (p) => ({ ...DEFAULT_PROFILE, ...(p && typeof p === "object" ? p : {}) });
const validWorkdays = (w) => [...new Set((Array.isArray(w) ? w : []).map(Number).filter((d) => Number.isInteger(d) && d >= 0 && d <= 6))].sort((a, b) => a - b);
const localTz = () => {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "Europe/Berlin";
  } catch (_) {
    return "Europe/Berlin";
  }
};
function randomHex(bytes) {
  const a = new Uint8Array(bytes);
  if (globalThis.crypto?.getRandomValues) globalThis.crypto.getRandomValues(a);
  else for (let i = 0; i < a.length; i++) a[i] = Math.floor(Math.random() * 256);
  return Array.from(a, (b) => b.toString(16).padStart(2, "0")).join("");
}

// Store & PM: über start() gesetzt, sonst bei Bedarf nachgeladen (gleiche Modul-Instanz wie in der App)
let ST = null;
let PM = null;
const storeRef = async () => ST || (ST = await import("./store.js"));
const pmRef = async () => PM || (PM = await import("./pm.js"));

// ---------- Umgebung ----------
let envCache = null;

// Was kann dieses Gerät? (iPad meldet sich als „Macintosh“ mit Touch)
export function env() {
  if (envCache) return envCache;
  const nav = hasNav() ? navigator : {};
  const ua = String(nav.userAgent || "");
  const touchMac = /Macintosh/.test(ua) && (nav.maxTouchPoints || 0) > 1;
  const ipad = /iPad/.test(ua) || touchMac;
  const ios = /iP(hone|od|ad)/.test(ua) || touchMac;
  const mac = /Macintosh|Mac OS X/.test(ua) && !ios;
  let standalone = nav.standalone === true;
  try {
    if (typeof matchMedia === "function") standalone ||= ["standalone", "fullscreen", "minimal-ui", "window-controls-overlay"].some((m) => matchMedia(`(display-mode: ${m})`).matches);
  } catch (_) {
    /* ältere Browser */
  }
  const sw = "serviceWorker" in nav;
  const notifications = sw && typeof Notification !== "undefined"; // iOS: nur in der installierten App vorhanden
  const push = notifications && typeof window !== "undefined" && "PushManager" in window;
  const badge = typeof nav.setAppBadge === "function";
  const share = typeof nav.share === "function";
  let shareFiles = false;
  try {
    shareFiles = share && typeof nav.canShare === "function" && typeof File === "function" && nav.canShare({ files: [new File(["x"], "test.txt", { type: "text/plain" })] });
  } catch (_) {
    shareFiles = false;
  }
  const out = { ios, ipad, mac, standalone, notifications, push, badge, share, shareFiles, sw };
  // erst merken, wenn das Dokument geparst ist (ganz früh kennt Safari den Anzeigemodus manchmal noch nicht)
  if (!hasWin() || document.readyState !== "loading") envCache = out;
  return out;
}

export function permission() {
  if (typeof Notification === "undefined" || !hasNav() || !("serviceWorker" in navigator)) return "unsupported";
  const p = Notification.permission;
  return p === "granted" || p === "denied" ? p : "default";
}

// Erlaubnis anfragen – Promise- und alte Callback-Variante (Safari < 15). Läuft synchron an, damit die Nutzergeste gilt.
function requestPerm() {
  return new Promise((resolve) => {
    let r;
    try {
      r = Notification.requestPermission((p) => resolve(p));
    } catch (_) {
      return resolve(permission());
    }
    if (r && typeof r.then === "function") r.then(resolve, () => resolve(permission()));
  }).then((p) => (p === "granted" || p === "denied" ? p : permission()));
}

// Mitteilungen erlauben – NUR direkt aus einem Tipp/Klick aufrufen (iOS verlangt die Nutzergeste, kein await davor!)
export function enable() {
  if (typeof Notification === "undefined" || typeof Notification.requestPermission !== "function") return Promise.resolve("unsupported");
  const asked = requestPerm(); // ← muss der erste Aufruf sein
  if (!hasNav() || !("serviceWorker" in navigator)) return asked.then(() => "unsupported");
  return asked.then((p) => {
    if (p === "granted") {
      lastBadge = -1; // Zähler am Symbol jetzt erlaubt → neu setzen
      refresh().catch(() => {});
      autoPush().catch(() => {});
    }
    return p;
  });
}

// ---------- Mitteilungen anzeigen ----------
async function swReg(timeout = 4000) {
  if (!hasNav() || !("serviceWorker" in navigator)) return null;
  try {
    const reg = await Promise.race([navigator.serviceWorker.ready, sleep(timeout).then(() => null)]);
    return reg || (await navigator.serviceWorker.getRegistration?.()) || null;
  } catch (_) {
    return null;
  }
}

function itemPath(it) {
  if (it?.taskId) return `./?task=${encodeURIComponent(it.taskId)}`;
  if (it?.kind === "review") return "./?view=rueckblick";
  return "./?view=heute";
}
const absUrl = (rel, base) => {
  try {
    return new URL(rel, base).href;
  } catch (_) {
    return rel;
  }
};

// Echte System-Mitteilung über den Service Worker (new Notification gibt es auf iOS nicht)
async function showSystem(it, { sounds = true } = {}) {
  if (permission() !== "granted") return false;
  const reg = await swReg();
  if (!reg || typeof reg.showNotification !== "function") return false;
  const url = absUrl(itemPath(it), reg.scope);
  const tag = String(it.tag || "taschen");
  try {
    // macOS ersetzt Mitteilungen mit gleichem tag nicht zuverlässig → alte selbst schließen
    for (const n of (await reg.getNotifications?.({ tag })) || []) n.close();
  } catch (_) {
    /* egal */
  }
  try {
    await reg.showNotification(it.title || BRAND.name, {
      body: it.body || "",
      tag,
      renotify: true,
      lang: "de-DE",
      dir: "ltr",
      icon: absUrl("icons/icon-192.png", reg.scope),
      silent: !sounds,
      data: { url, tag, kind: it.kind || null, taskId: it.taskId || null },
      navigate: url,
    });
    return true;
  } catch (_) {
    return false;
  }
}

function inApp(it) {
  if (!hasWin() || typeof CustomEvent !== "function") return;
  try {
    window.dispatchEvent(new CustomEvent("taschen:reminder", { detail: it }));
  } catch (_) {
    /* ohne Fenster */
  }
}

// Test-Mitteilung (aus den Einstellungen)
export async function test() {
  if (permission() !== "granted") throw new Error(permission() === "unsupported" ? "Mitteilungen gibt es hier nicht – auf iPhone und iPad nur in der installierten App." : "Mitteilungen sind nicht erlaubt.");
  const sounds = (ST?.get?.()?.profile?.sounds ?? true) !== false;
  const ok = await showSystem({ kind: "test", tag: "taschen-test", title: "🔔 So erinnere ich dich", body: "Morgens dein Tagesbriefing und kurz vor Terminen ein Hinweis – auch auf dem Sperrbildschirm." }, { sounds });
  if (!ok) throw new Error("Die Mitteilung ließ sich nicht zeigen – lade die App einmal neu und versuch es noch mal.");
  return true;
}

// ---------- Plan, Zeitgeber, Zähler ----------
let started = false;
let plan = { at: 0, items: [], badge: 0, briefings: {} };
let planSig = "";
let planWritten = 0;
let timer = null;
let lastBadge = -1;
const shown = new Map(); // Schlüssel → Zeitpunkt der Anzeige (auch vom Service Worker gezeigte, kv "notified")
let recomputeTimer = null;
let pushTimer = null;

// Erinnerungs-Plan neu berechnen: Einträge (mit den letzten 15 Min. zum Nachholen), Zähler und Tagesbriefings der nächsten 7 Tage
export function computePlan(state, pm, now = Date.now()) {
  const s = state || {};
  let items = [];
  try {
    items = pm.reminderPlan(s, new Date(now - CATCHUP), { days: HORIZON_DAYS }) || [];
  } catch (e) {
    if (typeof console !== "undefined") console.warn("[taschen] Erinnerungsplan", e);
  }
  // Termine aus verbundenen Kalendern (Google, Microsoft) – profile.defaultRemind Minuten vorher
  let evItems = [];
  try {
    evItems = eventReminders(new Date(now - CATCHUP), profileOf(s.profile)) || [];
  } catch (_) {
    evItems = [];
  }
  items = [...items, ...evItems]
    .filter((it) => it && Number.isFinite(it.at) && it.tag)
    .map((it) => ({ at: it.at, kind: it.kind, ...(it.taskId ? { taskId: it.taskId } : {}), ...(it.eventId ? { eventId: String(it.eventId) } : {}), ...(it.join ? { join: String(it.join) } : {}), ...(it.web ? { web: String(it.web) } : {}), title: String(it.title || ""), body: String(it.body || ""), tag: String(it.tag) }))
    .sort((a, b) => a.at - b.at);
  // Morgen-Briefing nennt die Termine des Tages
  for (const it of items) {
    if (it.kind !== "briefing") continue;
    const line = safeSummary(toISO(new Date(it.at)));
    if (line) it.body = it.body ? `${it.body}\n${line}` : line;
  }
  let badge = 0;
  try {
    badge = Math.max(0, Math.round(pm.badgeCount(s, new Date(now)) || 0));
  } catch (_) {
    badge = 0;
  }
  // Briefings für jeden der nächsten 7 Tage – auch wenn das Briefing in den Einstellungen aus ist (der Service Worker braucht für jeden Push einen Text)
  const briefings = {};
  try {
    const d0 = new Date(now);
    const morning = new Date(d0.getFullYear(), d0.getMonth(), d0.getDate(), 0, 0, 1);
    const forced = { ...s, profile: { ...profileOf(s.profile), briefing: true, evening: false } };
    const last = addDays(toISO(morning), BRIEF_DAYS - 1);
    for (const it of pm.reminderPlan(forced, morning, { days: BRIEF_DAYS }) || []) {
      if (it?.kind !== "briefing") continue;
      const d = toISO(new Date(it.at));
      if (d && d <= last && !briefings[d]) {
        const line = safeSummary(d);
        briefings[d] = { title: String(it.title || ""), body: [String(it.body || ""), line].filter(Boolean).join("\n") };
      }
    }
  } catch (_) {
    /* ohne Briefings – der Service Worker baut dann selbst einen Text */
  }
  return { at: now, items, badge, briefings };
}

function safeSummary(iso) {
  try {
    return eventSummary(iso) || "";
  } catch (_) {
    return "";
  }
}

function setBadge(n) {
  if (!hasNav() || typeof navigator.setAppBadge !== "function") return;
  if (n === lastBadge) return;
  lastBadge = n;
  try {
    const p = n > 0 ? navigator.setAppBadge(n) : typeof navigator.clearAppBadge === "function" ? navigator.clearAppBadge() : navigator.setAppBadge(0);
    p?.catch?.(() => (lastBadge = -1)); // z. B. ohne Mitteilungs-Erlaubnis (iOS) – später erneut versuchen
  } catch (_) {
    lastBadge = -1;
  }
}

async function loadShown() {
  try {
    const st = await storeRef();
    const v = await st.kvGet("notified");
    if (v && typeof v === "object") for (const [tag, t] of Object.entries(v)) if (Number.isFinite(t) && (shown.get(tag) || 0) < t) shown.set(tag, t);
  } catch (_) {
    /* ohne Speicher: nur für diese Sitzung */
  }
}
async function saveShown() {
  const cut = Date.now() - 3 * DAY;
  for (const [tag, t] of shown) if (t < cut) shown.delete(tag);
  try {
    const st = await storeRef();
    // mit dem vergleichen, was der Service Worker inzwischen notiert hat
    const v = (await st.kvGet("notified")) || {};
    for (const [tag, t] of Object.entries(v)) if (Number.isFinite(t) && t >= cut && !shown.has(tag)) shown.set(tag, t);
    await st.kvSet("notified", Object.fromEntries(shown));
  } catch (_) {
    /* nur für diese Sitzung */
  }
}

// Schlüssel für „schon gezeigt“: Aufgaben mit Zeitpunkt (verschobene Erinnerungen kommen neu), Briefings & Co. je Tag – gleiche Regel in sw.js
export const noteKey = (it) => (it?.kind === "task" && Number.isFinite(it.at) ? `${it.tag}@${it.at}` : String(it?.tag || ""));

// Fällige Einträge zeigen: jeder nur einmal, verpasste höchstens 15 Min. rückwirkend
async function fireDue(now = Date.now()) {
  const due = plan.items.filter((it) => it.at <= now + 1000 && it.at > now - CATCHUP && !shown.has(noteKey(it)));
  if (!due.length) return;
  for (const it of due) shown.set(noteKey(it), now);
  await saveShown();
  // Aufgaben, die du nach dem Erinnerungszeitpunkt angelegt oder geändert hast, kennst du schon – kein Banner
  const fresh = due.filter((it) => {
    if (!it.taskId) return true;
    try {
      return !((ST?.task?.(it.taskId)?.updated || 0) > it.at);
    } catch (_) {
      return true;
    }
  });
  if (!fresh.length) return;
  const sounds = (ST?.get?.()?.profile?.sounds ?? true) !== false;
  // Bei offener, aktiver App reicht das Banner in der App; sonst (Mac: anderes Fenster vorne) zusätzlich eine System-Mitteilung
  const away = hasWin() && (document.visibilityState === "hidden" || (typeof document.hasFocus === "function" && !document.hasFocus()));
  for (const it of fresh.slice(-3)) {
    inApp(it);
    if (away) await showSystem(it, { sounds });
  }
}

function armTimer(now = Date.now()) {
  clearTimeout(timer);
  const next = plan.items.find((it) => it.at > now && it.at <= now + TIMER_AHEAD && !shown.has(noteKey(it)));
  const d = new Date(now);
  const midnight = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1, 0, 0, 2).getTime(); // neuer Tag → Zähler & Briefings neu
  const wake = Math.min(next ? next.at : Infinity, midnight, now + HOUR);
  timer = setTimeout(() => refresh().catch(() => {}), Math.max(250, wake - now + 50));
  timer?.unref?.();
}

// Alles neu: Plan berechnen, speichern (für den Service Worker), Zähler setzen, Fälliges zeigen, Zeitgeber stellen, Push-Server informieren
async function refresh({ write = true } = {}) {
  if (!ST) return;
  const pm = await pmRef();
  const now = Date.now();
  plan = computePlan(ST.get(), pm, now);
  setBadge(plan.badge);
  if (write) {
    const sig = JSON.stringify([plan.items, plan.badge, plan.briefings]);
    if (sig !== planSig || now - planWritten > HOUR) {
      planSig = sig;
      planWritten = now;
      ST.kvSet("plan", plan).catch(() => {});
      clearTimeout(pushTimer);
      pushTimer = setTimeout(() => pushSync().catch(() => {}), 4000);
    }
  }
  await fireDue(now);
  armTimer(now);
}

function scheduleRefresh(ms = 1000) {
  clearTimeout(recomputeTimer);
  recomputeTimer = setTimeout(() => refresh().catch(() => {}), ms);
}

// Startet die Erinnerungen: abonniert den Store, plant neu (entprellt 1 s), hält Zähler & Push aktuell
export function start(store, pm) {
  if (store) ST = store;
  if (pm) PM = pm;
  if (!ST) return;
  if (started) return scheduleRefresh(50);
  started = true;
  ST.subscribe?.((_s, ch) => {
    if (ch?.action === "reset") onReset();
    scheduleRefresh(1000);
  });
  loadShown()
    .then(() => refresh())
    .catch(() => {});
  if (!hasWin()) return;
  const onVisible = () => {
    // zurück in der App: was der Service Worker inzwischen gezeigt hat, nicht doppelt zeigen; Verpasstes nachholen
    loadShown()
      .then(() => refresh())
      .catch(() => {});
  };
  const onHidden = () => {
    clearTimeout(recomputeTimer);
    try {
      if (ST && PM) {
        plan = computePlan(ST.get(), PM, Date.now());
        setBadge(plan.badge);
        planSig = JSON.stringify([plan.items, plan.badge, plan.briefings]);
        planWritten = Date.now();
        ST.kvSet("plan", plan).catch(() => {});
        // iOS friert die App gleich ein – geänderte Zeitpunkte jetzt noch an den Push-Server
        clearTimeout(pushTimer);
        pushSync().catch(() => {});
      }
    } catch (_) {
      /* nächstes Mal */
    }
  };
  document.addEventListener("visibilitychange", () => (document.visibilityState === "visible" ? onVisible() : onHidden()));
  window.addEventListener("pageshow", (e) => e.persisted && onVisible());
  window.addEventListener("pagehide", onHidden);
  // Zeitgeber werden im Hintergrund gedrosselt – solange sichtbar, einmal pro halber Minute nachsehen
  setInterval(() => {
    if (document.visibilityState === "visible") fireDue().catch(() => {});
  }, 30000);
  setTimeout(() => healPush().catch(() => {}), 5000);
}

// „Alles löschen“: kv ist schon leer – den Push-Server bitten, dieses Gerät zu vergessen (sonst kämen weiter Mitteilungen)
function onReset() {
  const cur = pushCache;
  pushCache = null;
  tokenPromise = null;
  shown.clear();
  planSig = "";
  if (!cur?.subscribed || !cur.server || !cur.device || typeof fetch !== "function") return;
  try {
    fetch(cur.server + "/api/push/unsubscribe", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ device: cur.device }), keepalive: true, credentials: "omit" }).catch(() => {});
  } catch (_) {
    /* dann eben nicht */
  }
}

// Aktueller Plan (z. B. für eine Vorschau in den Einstellungen)
export const currentPlan = () => plan;

// ---------- Kalender (.ics nach RFC 5545) ----------
const CRLF = "\r\n";
const PRODID = "-//Arbeitstaschen//Projektmanager//DE";
const BYDAY = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];

// Oktette einer Zeichenkette in UTF-8
function utf8Len(s) {
  let n = 0;
  for (const ch of s) {
    const c = ch.codePointAt(0);
    n += c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4;
  }
  return n;
}

// Zeilen über 75 Oktette falten (CRLF + Leerzeichen) – nie mitten in einem UTF-8-Zeichen
export function icsFold(line) {
  if (line.length <= 75 && !/[^\x00-\x7f]/.test(line)) return line;
  const out = [];
  let cur = "";
  let bytes = 0;
  let limit = 75;
  for (const ch of line) {
    const n = utf8Len(ch);
    if (bytes + n > limit) {
      out.push(cur);
      cur = "";
      bytes = 0;
      limit = 74; // Folgezeilen: 1 Oktett geht für das Leerzeichen drauf
    }
    cur += ch;
    bytes += n;
  }
  out.push(cur);
  return out.join(CRLF + " ");
}

// TEXT-Werte: \ ; , und Zeilenumbrüche maskieren, Steuerzeichen entfernen
export function icsText(s) {
  return String(s ?? "")
    .replace(/\r\n?/g, "\n")
    .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "")
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\n/g, "\\n");
}

const icsUtc = (ms) =>
  new Date(ms)
    .toISOString()
    .replace(/[-:]/g, "")
    .replace(/\.\d{3}/, "");
const icsDate = (iso) => iso.replace(/-/g, "");
const icsLocal = (d) => `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}T${pad(d.getHours())}${pad(d.getMinutes())}00`;
const uidPart = (s) => String(s ?? "").replace(/[^A-Za-z0-9_.-]/g, "") || "x";

// Dauer für TRIGGER: 480 → "PT8H", 450 → "PT7H30M", 1440 → "P1D", 0 → "PT0M"
export function icsDuration(min) {
  const m0 = Math.max(0, Math.round(min));
  const d = Math.floor(m0 / 1440);
  const h = Math.floor((m0 % 1440) / 60);
  const m = m0 % 60;
  let s = "P" + (d ? d + "D" : "");
  if (h || m || !d) s += "T" + (h ? h + "H" : "") + (m || !h ? m + "M" : "");
  return s;
}

function alarm(trigger, text) {
  return ["BEGIN:VALARM", "ACTION:DISPLAY", `DESCRIPTION:${icsText(trunc(text, 200) || BRAND.name)}`, `TRIGGER:${trigger}`, "END:VALARM"];
}

function calendar(events, calName) {
  const L = ["BEGIN:VCALENDAR", "VERSION:2.0", `PRODID:${PRODID}`, "CALSCALE:GREGORIAN", "METHOD:PUBLISH"];
  if (calName) L.push(`X-WR-CALNAME:${icsText(calName)}`);
  for (const ev of events) if (ev) L.push(...ev);
  L.push("END:VCALENDAR");
  return L.map(icsFold).join(CRLF) + CRLF;
}

const bagFrom = (bagsById, id) => (!id || !bagsById ? null : (bagsById instanceof Map ? bagsById.get(id) : bagsById[id]) || null);

function appLink(appUrl, params) {
  if (!appUrl) return "";
  try {
    const u = new URL(appUrl);
    u.hash = "";
    for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v);
    return u.href;
  } catch (_) {
    return "";
  }
}

// Wiederholung als RRULE (Monatsende wie in der App: 31. → letzter Tag des Monats)
export function icsRrule(repeat, iso) {
  const day = +iso.slice(8, 10);
  const month = +iso.slice(5, 7);
  const lastDays = (from) => Array.from({ length: day - from + 1 }, (_, i) => from + i).join(",");
  switch (repeat) {
    case "daily":
      return "FREQ=DAILY";
    case "weekdays":
      return "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR";
    case "weekly":
      return "FREQ=WEEKLY";
    case "biweekly":
      return "FREQ=WEEKLY;INTERVAL=2";
    case "monthly":
      return day > 28 ? `FREQ=MONTHLY;BYMONTHDAY=${lastDays(28)};BYSETPOS=-1` : "FREQ=MONTHLY";
    case "yearly":
      return month === 2 && day === 29 ? "FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=28,29;BYSETPOS=-1" : "FREQ=YEARLY";
    default:
      return null;
  }
}

function taskDescription(t, bag, link) {
  const head = [bag ? `${bag.emoji || "👜"} ${bag.name}` : "📥 Eingang"];
  const prio = PRIOS.find((p) => p.id === t.prio);
  if (t.prio > 0 && prio) head.push(`Priorität ${prio.label.toLowerCase()}`);
  if (Number.isFinite(t.est) && t.est > 0) head.push(`ca. ${fmtDuration(t.est)}`);
  const parts = [head.join(" · ")];
  if (t.waiting) parts.push(`Wartet auf: ${trunc(t.waiting, 120)}`);
  const notes = String(t.notes || "").trim();
  if (notes) parts.push(notes.length > 1500 ? notes.slice(0, 1499) + "…" : notes);
  const subs = Array.isArray(t.subtasks) ? t.subtasks.filter((s) => s && String(s.title || "").trim()) : [];
  if (subs.length)
    parts.push(
      subs
        .slice(0, 40)
        .map((s) => `${s.done ? "☑" : "☐"} ${trunc(s.title, 120)}`)
        .join("\n"),
    );
  if (link) parts.push(`In Arbeitstaschen öffnen: ${link}`);
  return parts.join("\n\n");
}

function taskEvent(t, { bagsById, profile, appUrl, stamp }) {
  if (!t || t.deleted || !isISO(t.due) || !String(t.title || "").trim()) return null;
  const P = profileOf(profile);
  const bag = bagFrom(bagsById, t.bag);
  const link = appLink(appUrl, { task: t.id });
  const rrule = icsRrule(t.repeat, t.due);
  const tm = parseTime(t.time);
  const title = String(t.title).trim();
  const L = ["BEGIN:VEVENT", `UID:${uidPart(t.id)}-r${Math.round(Number(t.updated) || 0)}@arbeitstaschen`, `DTSTAMP:${stamp}`];
  if (Number(t.updated) > 0) L.push(`LAST-MODIFIED:${icsUtc(Number(t.updated))}`);
  if (tm !== null) {
    const est = Number.isFinite(t.est) && t.est > 0 ? Math.min(Math.round(t.est), 1440) : 30;
    const start = atLocal(t.due, tm);
    const end = new Date(start.getTime() + est * MIN);
    // Einzeltermine in UTC; Serien in lokaler „floating“ Zeit, sonst wandert die Serie bei der Zeitumstellung um eine Stunde
    if (rrule) L.push(`DTSTART:${icsLocal(start)}`, `DTEND:${icsLocal(end)}`);
    else L.push(`DTSTART:${icsUtc(start.getTime())}`, `DTEND:${icsUtc(end.getTime())}`);
  } else {
    L.push(`DTSTART;VALUE=DATE:${icsDate(t.due)}`, `DTEND;VALUE=DATE:${icsDate(addDays(t.due, 1))}`, "TRANSP:TRANSPARENT");
  }
  if (rrule) L.push(`RRULE:${rrule}`);
  L.push(`SUMMARY:${icsText(title)}`, `DESCRIPTION:${icsText(taskDescription(t, bag, link))}`);
  if (bag?.name) L.push(`CATEGORIES:${icsText(bag.name)}`);
  if (t.prio > 0) L.push(`PRIORITY:${{ 1: 9, 2: 5, 3: 1 }[t.prio] || 0}`);
  if (link) L.push(`URL:${link}`);
  if (!t.done) {
    if (tm !== null) {
      const r = t.remind ?? P.defaultRemind;
      if (Number.isFinite(r) && r >= 0) L.push(...alarm(r > 0 ? `-PT${Math.round(r)}M` : "PT0M", `${title}${bag?.name ? ` · ${bag.name}` : ""}`));
    } else if (t.remind !== -1) {
      L.push(...alarm(icsDuration(parseTime(P.dayStart) ?? 480), `Heute fällig: ${title}`));
    }
  }
  L.push("END:VEVENT");
  return L;
}

// Aufgaben als Kalender: mit Uhrzeit als Termin (+ Wecker vor Beginn), ohne Uhrzeit ganztägig (+ Wecker um dayStart)
export function icsForTasks(tasks, { bagsById, profile, calName = "Arbeitstaschen", appUrl, now = new Date() } = {}) {
  const stamp = icsUtc(now instanceof Date ? now.getTime() : Number(now) || Date.now());
  const events = (Array.isArray(tasks) ? tasks : []).map((t) => taskEvent(t, { bagsById, profile, appUrl, stamp }));
  return calendar(events, calName);
}

// Tagesbriefing als wiederkehrender Termin an deinen Arbeitstagen um dayStart (lokale Zeit, damit die Serie die Zeitumstellung überlebt)
export function icsDaily(profile, { appUrl, now = new Date(), calName = "Arbeitstaschen" } = {}) {
  const P = profileOf(profile);
  const startMin = parseTime(P.dayStart) ?? 480;
  let days = validWorkdays(P.workdays);
  if (!days.length) days = [0, 1, 2, 3, 4, 5, 6];
  const today = todayISO(now instanceof Date ? now : new Date(now));
  let first = today;
  for (let i = 0; i < 7 && !days.includes(weekday(first)); i++) first = addDays(first, 1);
  const start = atLocal(first, startMin);
  const end = new Date(start.getTime() + 15 * MIN);
  const link = appLink(appUrl, { view: "heute" });
  const order = [1, 2, 3, 4, 5, 6, 0].filter((d) => days.includes(d)); // Montag zuerst
  const desc = ["Dein Projektmanager: Was steht heute an? Fokus, Termine und Überfälliges auf einen Blick.", link ? `Öffnen: ${link}` : ""].filter(Boolean).join("\n\n");
  const ev = [
    "BEGIN:VEVENT",
    `UID:briefing-${hhmm(startMin).replace(":", "")}-${order.join("")}@arbeitstaschen`,
    `DTSTAMP:${icsUtc((now instanceof Date ? now : new Date(now)).getTime())}`,
    `DTSTART:${icsLocal(start)}`,
    `DTEND:${icsLocal(end)}`,
    `RRULE:FREQ=WEEKLY;BYDAY=${order.map((d) => BYDAY[d]).join(",")}`,
    `SUMMARY:${icsText(`☀️ Tagesbriefing${P.name ? ` für ${P.name}` : ""}`)}`,
    `DESCRIPTION:${icsText(desc)}`,
    "TRANSP:TRANSPARENT",
  ];
  if (link) ev.push(`URL:${link}`);
  ev.push(...alarm("PT0M", "Dein Tag wartet – was steht heute an?"), "END:VEVENT");
  return calendar([ev], calName);
}

// Meilensteine als ganztägige Termine – mit Wecker am Vortag und am Tag selbst (jeweils um dayStart)
export function icsForMilestones(milestones, { bagsById, profile, appUrl, calName = "Arbeitstaschen", now = new Date() } = {}) {
  const P = profileOf(profile);
  const startMin = parseTime(P.dayStart) ?? 480;
  const stamp = icsUtc(now instanceof Date ? now.getTime() : Number(now) || Date.now());
  const events = (Array.isArray(milestones) ? milestones : []).map((m) => {
    if (!m || m.deleted || !isISO(m.date) || !String(m.title || "").trim()) return null;
    const bag = bagFrom(bagsById, m.bag);
    const title = `🏁 ${String(m.title).trim()}${bag?.name ? ` · ${bag.name}` : ""}`;
    const link = bag ? appLink(appUrl, { view: `tasche/${bag.id}` }) : appLink(appUrl, { view: "demnaechst" });
    const L = [
      "BEGIN:VEVENT",
      `UID:${uidPart(m.id)}-r${Math.round(Number(m.updated) || 0)}@arbeitstaschen`,
      `DTSTAMP:${stamp}`,
      `DTSTART;VALUE=DATE:${icsDate(m.date)}`,
      `DTEND;VALUE=DATE:${icsDate(addDays(m.date, 1))}`,
      "TRANSP:TRANSPARENT",
      `SUMMARY:${icsText(title)}`,
      `DESCRIPTION:${icsText([`Meilenstein${bag ? ` in ${bag.emoji || "👜"} ${bag.name}` : ""}`, link ? `Öffnen: ${link}` : ""].filter(Boolean).join("\n\n"))}`,
    ];
    if (bag?.name) L.push(`CATEGORIES:${icsText(bag.name)}`);
    if (link) L.push(`URL:${link}`);
    if (!m.done) L.push(...alarm(`-${icsDuration(1440 - startMin)}`, `Morgen: ${title}`), ...alarm(icsDuration(startMin), `Heute: ${title}`));
    L.push("END:VEVENT");
    return L;
  });
  return calendar(events, calName);
}

// ---------- Kurzbefehl → Apple Erinnerungen ----------
// shortcuts://run-shortcut?name=…&input=text&text=<Zeilen "YYYY-MM-DDTHH:MM|Titel|Tasche"> (ohne Datum: Feld leer)
export function remindersShortcutUrl(tasks, { name = "Taschen → Erinnerungen", bagsById, profile } = {}) {
  const P = profileOf(profile || ST?.get?.()?.profile);
  const dayStart = hhmm(parseTime(P.dayStart) ?? 480);
  const clean = (s, n) => trunc(String(s ?? "").replace(/[|\r\n\t]+/g, " "), n);
  const rows = [];
  for (const t of Array.isArray(tasks) ? tasks : []) {
    if (!t || t.deleted || t.done || !String(t.title || "").trim()) continue;
    const tm = parseTime(t.time);
    const when = isISO(t.due) ? `${t.due}T${tm !== null ? hhmm(tm) : dayStart}` : "";
    let bag = bagFrom(bagsById, t.bag);
    if (!bag && t.bag) {
      try {
        bag = ST?.bag?.(t.bag) || null;
      } catch (_) {
        bag = null;
      }
    }
    rows.push({ key: when || "9999", line: [when, clean(t.title, 200), clean(bag?.name || "", 60)].join("|") });
  }
  rows.sort((a, b) => a.key.localeCompare(b.key));
  return `shortcuts://run-shortcut?name=${encodeURIComponent(name)}&input=text&text=${encodeURIComponent(rows.map((r) => r.line).join("\n"))}`;
}

// ---------- Dateien weitergeben (Kalender, Backup, Anhänge) ----------
const safeName = (s) =>
  String(s ?? "")
    .replace(/[\\/:*?"<>|\x00-\x1f]+/g, "-")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 120) || "datei";

function blobToDataUrl(blob) {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(r.result);
    r.onerror = () => reject(r.error || new Error("Lesen fehlgeschlagen"));
    r.readAsDataURL(blob);
  });
}

// iPhone/iPad: Teilen-Menü mit der Datei („Sichern in Dateien“, Mail, AirDrop …); sonst Download. Rückgabe: "shared" | "downloaded" | "opened"
export async function deliverFile(filename, mime, content) {
  if (!hasWin()) throw new Error("Dateien weitergeben geht nur im Browser.");
  const name = safeName(filename);
  const type = String(mime || (content instanceof Blob && content.type) || "application/octet-stream");
  const textual = /^text\/|json|xml|calendar/.test(type);
  const blob = content instanceof Blob ? content : new Blob([String(content ?? "")], { type: textual && !/charset/i.test(type) ? `${type};charset=utf-8` : type });
  const E = env();
  // Datei VOR jedem await bauen – das Teilen-Menü braucht die frische Nutzergeste (WebKit: 5 s)
  if (E.ios && typeof navigator.share === "function" && typeof navigator.canShare === "function" && typeof File === "function") {
    let file = null;
    try {
      file = new File([blob], name, { type: type.split(";")[0] });
    } catch (_) {
      file = null;
    }
    let ok = false;
    try {
      ok = !!file && navigator.canShare({ files: [file] });
    } catch (_) {
      ok = false;
    }
    if (ok) {
      try {
        await navigator.share({ files: [file], title: name });
        return "shared";
      } catch (e) {
        if (e?.name === "AbortError") return "shared"; // abgebrochen – nichts weiter tun
        /* z. B. Geste abgelaufen → herunterladen */
      }
    }
  }
  try {
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = name;
    a.rel = "noopener";
    a.style.display = "none";
    document.body.appendChild(a);
    a.click();
    setTimeout(() => {
      URL.revokeObjectURL(url);
      a.remove();
    }, 60000);
    return "downloaded";
  } catch (e) {
    if (!E.standalone) throw new Error("Die Datei ließ sich nicht speichern.");
    // letzte Rettung in der installierten App: als Daten-Adresse öffnen
    const dataUrl = await blobToDataUrl(blob);
    const w = window.open(dataUrl, "_blank");
    if (!w) location.href = dataUrl;
    return "opened";
  }
}

// ---------- Push über deinen Server (ohne Inhalt – der Service Worker baut die Mitteilung selbst) ----------
let pushCache = null;
let tokenPromise = null;

async function loadPush() {
  if (pushCache) return pushCache;
  try {
    const st = await storeRef();
    const v = await st.kvGet("push");
    pushCache = v && typeof v === "object" ? { ...v } : {};
  } catch (_) {
    pushCache = {};
  }
  return pushCache;
}
async function savePush(patch) {
  const cur = await loadPush();
  pushCache = { ...cur, ...patch };
  try {
    const st = await storeRef();
    await st.kvSet("push", pushCache);
  } catch (_) {
    /* nur für diese Sitzung */
  }
  return pushCache;
}

// Zufälliges Geräte-Token (64 hex) für Push und KI – keine Rückschlüsse auf dich oder deine Daten
export function deviceToken() {
  if (!tokenPromise) {
    tokenPromise = (async () => {
      const cur = await loadPush();
      if (/^[0-9a-f]{64}$/.test(cur.device || "")) return cur.device;
      const device = randomHex(32);
      await savePush({ device });
      return device;
    })().catch((e) => {
      tokenPromise = null;
      throw e;
    });
  }
  return tokenPromise;
}

// Was der Server wissen muss – nur Zeitpunkte, keine Inhalte
function pushPrefs() {
  const P = profileOf(ST?.get?.()?.profile);
  const wd = validWorkdays(P.workdays);
  const now = Date.now();
  const times = [];
  for (const it of plan.items) {
    if (it.at <= now) continue;
    // Briefings an Arbeitstagen schickt der Server ohnehin täglich (briefing: "HH:MM"); an freien Tagen nur, wenn etwas ansteht
    if (it.kind === "briefing" && P.briefing && wd.includes(new Date(it.at).getDay())) continue;
    if (!times.includes(it.at)) times.push(it.at);
  }
  times.sort((a, b) => a - b);
  // evening: null – Feierabend-Erinnerungen kommen nur an Tagen mit offenen Aufgaben (stehen schon in times)
  return { tz: localTz(), times: times.slice(0, 200), briefing: P.briefing ? hhmm(parseTime(P.dayStart) ?? 480) : null, evening: null, workdays: wd };
}

function b64urlBytes(s) {
  let t = String(s || "")
    .replace(/-/g, "+")
    .replace(/_/g, "/")
    .replace(/\s+/g, "");
  if (t.length % 4) t += "=".repeat(4 - (t.length % 4));
  const bin = atob(t);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
function sameKey(buf, bytes) {
  if (!buf) return true; // unbekannt → behalten
  const a = new Uint8Array(buf);
  return a.length === bytes.length && a.every((v, i) => v === bytes[i]);
}

async function api(base, path, body) {
  const r = await request(base, path, body === undefined ? { timeout: 15000 } : { method: "POST", json: body, timeout: 15000 });
  if (!r.ok) {
    const e = new Error(r.data?.msg || r.data?.error || (r.status === 404 ? "Der Server kennt dieses Gerät nicht." : r.status === 503 ? "Push ist auf deinem Server nicht eingerichtet." : `Serverfehler (${r.status}).`));
    e.status = r.status;
    throw e;
  }
  return r.data || {};
}

// Abonnieren (Erlaubnis muss da sein) und beim Server anmelden
async function doSubscribe(base) {
  const { key } = await api(base, "/api/push/key");
  if (typeof key !== "string" || key.length < 40) throw new Error("Der Server hat keinen gültigen Push-Schlüssel.");
  const reg = await swReg(8000);
  if (!reg?.pushManager) throw new Error("Der Service Worker läuft noch nicht – lade die App einmal neu und versuch es dann noch mal.");
  const appKey = b64urlBytes(key);
  let sub = await reg.pushManager.getSubscription().catch(() => null);
  if (sub && !sameKey(sub.options?.applicationServerKey, appKey)) {
    await sub.unsubscribe().catch(() => {});
    sub = null;
  }
  if (!sub) sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: appKey });
  const device = await deviceToken();
  const prefs = pushPrefs();
  await api(base, "/api/push/subscribe", { device, subscription: sub.toJSON(), ...prefs });
  await savePush({ server: base, device, subscribed: true, endpoint: sub.endpoint, off: false, pendingOff: false, prefs, sent: Date.now() });
  return sub;
}

export async function pushState(server) {
  const supported = !!env().push;
  const base = normServer(server);
  const [chk, cur] = await Promise.all([base ? checkServer(base) : Promise.resolve(null), loadPush()]);
  const available = !!(chk?.ok && chk.push);
  let subscribed = false;
  if (supported && cur.subscribed && permission() === "granted" && (!base || !cur.server || cur.server === base)) {
    const reg = await swReg(2500);
    subscribed = !!(await reg?.pushManager?.getSubscription().catch(() => null));
  }
  return { supported, subscribed, available };
}

// Push einschalten – aus einem Tipp/Klick aufrufen (fragt bei Bedarf zuerst synchron nach der Erlaubnis)
export async function pushSubscribe(server) {
  const ask = typeof Notification !== "undefined" && Notification.permission === "default" && typeof Notification.requestPermission === "function" ? requestPerm() : null;
  const base = normServer(server);
  if (!base) throw new Error("Kein Server eingerichtet – Push läuft über deinen eigenen Server.");
  if (!env().push) return false;
  const perm = ask ? await ask : permission();
  if (perm !== "granted") return false;
  if (!plan.items.length && ST) await refresh({ write: false }).catch(() => {});
  await doSubscribe(base);
  lastBadge = -1;
  return true;
}

export async function pushUnsubscribe(server) {
  const cur = await loadPush();
  const base = normServer(server) || cur.server;
  // Das Abo im Browser bleibt bestehen (iOS mag kein ständiges Neu-Abonnieren) – der Server vergisst das Gerät
  await savePush({ subscribed: false, off: true, pendingOff: true });
  if (!base || !cur.device) return savePush({ pendingOff: false });
  try {
    await api(base, "/api/push/unsubscribe", { device: cur.device });
  } catch (e) {
    if (e.status !== 404) throw new Error(`Abmelden beim Server fehlgeschlagen – ich versuche es später noch mal. (${e.message})`);
  }
  await savePush({ pendingOff: false });
}

export async function pushTest(server) {
  const cur = await loadPush();
  const base = normServer(server) || cur.server;
  if (!base) throw new Error("Kein Server eingerichtet.");
  if (!cur.subscribed || !cur.device) throw new Error("Push ist auf diesem Gerät noch nicht eingeschaltet.");
  try {
    await api(base, "/api/push/test", { device: cur.device });
  } catch (e) {
    if (e.status !== 404) throw e;
    // Server kennt das Gerät nicht mehr → neu anmelden und noch einmal
    await doSubscribe(base);
    await api(base, "/api/push/test", { device: (await loadPush()).device });
  }
  return true;
}

// Plan-Zeitpunkte an den Server (nur wenn sich etwas Zukünftiges geändert hat oder 12 h vergangen sind)
async function pushSync({ force = false } = {}) {
  const cur = await loadPush();
  if (!cur.subscribed || !cur.server || !cur.device || permission() !== "granted") return false;
  const prefs = pushPrefs();
  const now = Date.now();
  const old = cur.prefs || {};
  const same =
    old.tz === prefs.tz &&
    old.briefing === prefs.briefing &&
    old.evening === prefs.evening &&
    JSON.stringify(old.workdays) === JSON.stringify(prefs.workdays) &&
    JSON.stringify((old.times || []).filter((t) => t > now)) === JSON.stringify(prefs.times);
  if (!force && same && now - (cur.sent || 0) < 12 * HOUR) return false;
  try {
    await api(cur.server, "/api/push/update", { device: cur.device, ...prefs });
    await savePush({ prefs, sent: now });
  } catch (e) {
    if (e.status === 404) await doSubscribe(cur.server).catch(() => {});
  }
  return true;
}

// Beim Start: Abo noch da? (iOS meldet ein verlorenes Abo nicht) – sonst still neu abonnieren und dem Server melden
async function healPush() {
  const cur = await loadPush();
  if (cur.pendingOff && cur.server && cur.device) {
    try {
      await api(cur.server, "/api/push/unsubscribe", { device: cur.device });
      await savePush({ pendingOff: false });
    } catch (e) {
      if (e.status === 404) await savePush({ pendingOff: false });
    }
  }
  if (!cur.subscribed || !cur.server || permission() !== "granted" || !env().push) return;
  const reg = await swReg(8000);
  if (!reg?.pushManager) return;
  const sub = await reg.pushManager.getSubscription().catch(() => null);
  if (!sub || sub.endpoint !== cur.endpoint) await doSubscribe(cur.server);
  else await pushSync();
}

// Nach dem Erlauben: Gibt es einen Server mit Push, gleich mit einschalten (außer du hast Push bewusst ausgeschaltet)
async function autoPush() {
  const cur = await loadPush();
  if (cur.off || cur.subscribed || !env().push) return;
  let server = cur.server || syncStatus().server || normServer(SERVER.url);
  if (!server) server = await detectServer().catch(() => null);
  const base = normServer(server);
  if (!base) return;
  const chk = await checkServer(base);
  if (!chk.ok || !chk.push) return;
  if (!plan.items.length && ST) await refresh({ write: false }).catch(() => {});
  await doSubscribe(base);
}
