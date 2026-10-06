// Arbeitstaschen – Verbindung zu Google (Gmail, Google Kalender, Workspace) und Microsoft (Outlook, Microsoft 365, Outlook.com)
// Der eigene Arbeitstaschen-Server vermittelt nur die Anmeldung (OAuth) und gibt kurzlebige Zugangs-Tokens aus.
// Termine und Mails holt die App direkt bei Google bzw. Microsoft (beide erlauben CORS) – sie laufen nie über den Server.
// Ohne Server gehen trotzdem: Kalender-Links, E-Mail schreiben (Gmail, Outlook, Mail-App) und Anrufen (tel:).
import { SERVER } from "./config.js";
import { normServer, request, checkServer, status as syncStatus } from "./sync.js";
import { safeUrl } from "./util.js";
import { toISO, addDays, parseTime, atLocal, isISO, fmtTime, fmtDuration } from "./dates.js";

// Beim Import nichts von window/document/location anfassen – Normalisierung, Links und Telefonnummern laufen auch in Node (Tests).
const MIN = 60000;
const DAY = 24 * 60 * MIN;
const STALE = 5 * MIN; // höchstens alle 5 Minuten neu laden (außer „Jetzt aktualisieren“)
const PENDING_KEY = "taschen-connect-pending";
const CACHE_KEY = "connect-cache";
const TAKEN_KEY = "connect-taken";

export const API = {
  gcal: "https://www.googleapis.com/calendar/v3",
  gmail: "https://gmail.googleapis.com/gmail/v1/users/me",
  graph: "https://graph.microsoft.com/v1.0",
};

const PROVIDERS = [
  { id: "google", name: "Google", sub: "Gmail · Google Kalender · Workspace", calendar: "Google Kalender", mail: "Gmail" },
  { id: "microsoft", name: "Microsoft", sub: "Outlook · Microsoft 365 · Outlook.com", calendar: "Outlook-Kalender", mail: "Outlook" },
];
export const providers = () => PROVIDERS.map((p) => ({ id: p.id, name: p.name, sub: p.sub }));
export const providerInfo = (id) => PROVIDERS.find((p) => p.id === id) || null;
export const providerName = (id) => providerInfo(id)?.name || "Konto";

const hasWin = () => typeof window !== "undefined" && typeof document !== "undefined";
const online = () => typeof navigator === "undefined" || navigator.onLine !== false;
const pad = (n) => String(n).padStart(2, "0");
const enc = encodeURIComponent;
const str = (v) => (v === null || v === undefined ? "" : String(v));

// Nur echte https-Adressen aus fremden Daten (Kalender, Mail) – keine relativen oder javascript:-Links
export function httpsUrl(u) {
  const s = str(u).trim();
  if (!/^https:\/\//i.test(s)) return "";
  const x = safeUrl(s);
  return x.startsWith("https://") ? x : "";
}

// Text aus fremden Quellen: Steuerzeichen weg, Leerraum zusammenfassen, Länge begrenzen
function clean(s, max = 500) {
  return str(s)
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f​-‏‪-‮⁦-⁩]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, max);
}
const ENT = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", auml: "ä", ouml: "ö", uuml: "ü", Auml: "Ä", Ouml: "Ö", Uuml: "Ü", szlig: "ß", euro: "€", ndash: "–", mdash: "—", hellip: "…", bdquo: "„", ldquo: "“", rdquo: "”", lsquo: "‘", rsquo: "’" };
export function decodeEntities(s) {
  return str(s).replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e) => {
    if (e[0] === "#") {
      const n = e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      return Number.isFinite(n) && n > 0 && n < 0x110000 ? String.fromCodePoint(n) : m;
    }
    return ENT[e] ?? m;
  });
}
// HTML (Google-Beschreibungen) → schlichter Text
function plain(html, max = 600) {
  const t = str(html)
    .replace(/<\s*br\s*\/?>/gi, "\n")
    .replace(/<\/(p|div|li|h\d)>/gi, "\n")
    .replace(/<a\s[^>]*href\s*=\s*"([^"]+)"[^>]*>(.*?)<\/a>/gi, (_, href, txt) => (txt && !txt.includes(href) ? `${txt} ${href}` : href))
    .replace(/<[^>]+>/g, "");
  return decodeEntities(t)
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "")
    .replace(/[ \t]+/g, " ")
    .replace(/\s*\n\s*/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim()
    .slice(0, max);
}

// RFC 2047 („=?UTF-8?B?…?=“) in Mail-Kopfzeilen
export function decodeHeader(s) {
  return str(s).replace(/=\?([\w-]+)\?([bq])\?([^?]*)\?=(\s+(?==\?))?/gi, (m, cs, kind, data) => {
    try {
      let bytes;
      if (kind.toLowerCase() === "b") {
        const bin = atob(data.replace(/\s+/g, ""));
        bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
      } else {
        const t = data.replace(/_/g, " ");
        const out = [];
        for (let i = 0; i < t.length; i++) {
          if (t[i] === "=" && /^[0-9a-f]{2}$/i.test(t.slice(i + 1, i + 3))) {
            out.push(parseInt(t.slice(i + 1, i + 3), 16));
            i += 2;
          } else out.push(t.charCodeAt(i));
        }
        bytes = Uint8Array.from(out);
      }
      return new TextDecoder(/^(utf-?8|us-ascii)$/i.test(cs) ? "utf-8" : cs.toLowerCase()).decode(bytes);
    } catch (_) {
      return m;
    }
  });
}

// "Hans Müller" <hans@firma.de> → { name, address }
export function parseFrom(v) {
  const s = decodeHeader(str(v)).trim();
  const m = /^(.*?)\s*<([^<>\s]+@[^<>\s]+)>\s*$/.exec(s);
  if (m) return { name: clean(m[1].replace(/^"(.*)"$/, "$1").replace(/\\"/g, '"'), 120), address: clean(m[2], 254).toLowerCase() };
  const a = /[^\s<>"]+@[^\s<>"]+/.exec(s);
  return { name: "", address: a ? clean(a[0], 254).toLowerCase() : "" };
}

const deviceTz = () => {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "Europe/Berlin";
  } catch (_) {
    return "Europe/Berlin";
  }
};
const hhmm = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;
const startOfDay = (ms) => {
  const d = new Date(ms);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
};

// Wanduhrzeit in einer IANA-Zeitzone → Zeitpunkt (ms); unbekannte Zone → Ortszeit des Geräts
function zoned(y, mo, d, h, mi, s, tz) {
  if (!tz || tz === deviceTz()) return new Date(y, mo - 1, d, h, mi, s).getTime();
  if (/^(utc|etc\/utc|gmt|z)$/i.test(tz)) return Date.UTC(y, mo - 1, d, h, mi, s);
  try {
    const f = new Intl.DateTimeFormat("en-US", { timeZone: tz, hourCycle: "h23", year: "numeric", month: "numeric", day: "numeric", hour: "numeric", minute: "numeric", second: "numeric" });
    const want = Date.UTC(y, mo - 1, d, h, mi, s);
    let t = want;
    for (let i = 0; i < 2; i++) {
      const p = Object.fromEntries(f.formatToParts(new Date(t)).map((x) => [x.type, +x.value]));
      const shown = Date.UTC(p.year, p.month - 1, p.day, p.hour % 24, p.minute, p.second);
      t += want - shown;
    }
    return t;
  } catch (_) {
    return new Date(y, mo - 1, d, h, mi, s).getTime();
  }
}
// Microsoft Graph: { dateTime: "2026-10-06T09:00:00.0000000", timeZone: "Europe/Berlin" }
export function graphTime(t) {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?/.exec(str(t?.dateTime));
  if (!m) return NaN;
  const [, y, mo, d, h, mi, s] = m.map(Number);
  const tz = /Z$/i.test(str(t.dateTime)) ? "UTC" : str(t.timeZone);
  return zoned(y, mo, d, h, mi, s || 0, tz);
}

// ---------- Online-Meetings ----------
const JOIN_RE = /https:\/\/(?:teams\.microsoft\.com\/l\/meetup-join\/[^\s<>"')\]]+|teams\.live\.com\/meet\/[^\s<>"')\]]+|meet\.google\.com\/[a-z]{3}-[a-z]{4}-[a-z]{3}[^\s<>"')\]]*|(?:[\w-]+\.)*zoom\.us\/(?:j|my|w|s)\/[^\s<>"')\]]+|(?:[\w-]+\.)+webex\.com\/[^\s<>"')\]]+|whereby\.com\/[^\s<>"')\]]+|meet\.jit\.si\/[^\s<>"')\]]+)/i;

export function joinKind(url) {
  let h = "";
  try {
    h = new URL(url).hostname.toLowerCase();
  } catch (_) {
    return null;
  }
  if (/(^|\.)teams\.(microsoft|live)\.com$/.test(h)) return "Teams";
  if (h === "meet.google.com") return "Meet";
  if (/(^|\.)zoom\.us$/.test(h)) return "Zoom";
  if (/(^|\.)webex\.com$/.test(h)) return "Webex";
  if (h === "whereby.com") return "Whereby";
  if (h === "meet.jit.si") return "Jitsi";
  return "Video";
}

function findJoin(text) {
  const m = JOIN_RE.exec(str(text));
  return m ? httpsUrl(m[0].replace(/[.,;:!?]+$/, "")) || null : null;
}

// Beitreten-Link eines Termins: vom Anbieter oder aus Ort/Beschreibung (Teams, Meet, Zoom, Webex)
export function joinLink(event) {
  if (!event || typeof event !== "object") return null;
  const direct = httpsUrl(event.join);
  if (direct) return direct;
  return findJoin(`${str(event.location)}\n${str(event.notes)}\n${str(event.description)}`);
}

// ---------- Normalisieren ----------
// Event = { id, account, provider, title, start, end, allDay, date, time, location, join, web, calendar, cancelled, notes }
export function normGoogleEvent(ev, { account = "", calendar = "", calId = "primary" } = {}) {
  if (!ev || typeof ev !== "object" || !ev.id) return null;
  const allDay = !!ev.start?.date && !ev.start?.dateTime;
  let start, end;
  if (allDay) {
    if (!isISO(ev.start.date)) return null;
    start = atLocal(ev.start.date, 0).getTime();
    end = isISO(ev.end?.date) ? atLocal(ev.end.date, 0).getTime() : start + DAY;
  } else {
    start = Date.parse(ev.start?.dateTime);
    end = Date.parse(ev.end?.dateTime);
  }
  if (!Number.isFinite(start)) return null;
  if (!Number.isFinite(end) || end < start) end = start + (allDay ? DAY : 30 * MIN);
  const video = (ev.conferenceData?.entryPoints || []).find((p) => (p?.entryPointType || p?.type) === "video");
  const notes = plain(ev.description);
  const location = clean(ev.location, 300);
  const self = (Array.isArray(ev.attendees) ? ev.attendees : []).find((a) => a?.self);
  const d = new Date(start);
  return {
    id: `g:${calId}:${ev.id}`,
    account,
    provider: "google",
    title: clean(ev.summary, 300) || "(Ohne Titel)",
    start,
    end,
    allDay,
    date: toISO(d),
    time: allDay ? null : hhmm(d),
    location,
    join: httpsUrl(ev.hangoutLink) || httpsUrl(video?.uri) || findJoin(`${location}\n${notes}`),
    web: httpsUrl(ev.htmlLink),
    calendar: clean(calendar, 120),
    cancelled: ev.status === "cancelled" || self?.responseStatus === "declined",
    notes,
  };
}

export function normGraphEvent(ev, { account = "", calendar = "Outlook" } = {}) {
  if (!ev || typeof ev !== "object" || !ev.id) return null;
  const allDay = !!ev.isAllDay;
  let start, end;
  if (allDay) {
    const sd = str(ev.start?.dateTime).slice(0, 10);
    const ed = str(ev.end?.dateTime).slice(0, 10);
    if (!isISO(sd)) return null;
    start = atLocal(sd, 0).getTime();
    end = isISO(ed) && ed > sd ? atLocal(ed, 0).getTime() : start + DAY;
  } else {
    start = graphTime(ev.start);
    end = graphTime(ev.end);
  }
  if (!Number.isFinite(start)) return null;
  if (!Number.isFinite(end) || end < start) end = start + (allDay ? DAY : 30 * MIN);
  const location = clean(ev.location?.displayName, 300);
  const notes = clean(ev.bodyPreview, 600);
  const d = new Date(start);
  return {
    id: `m:${ev.id}`,
    account,
    provider: "microsoft",
    title: clean(ev.subject, 300) || "(Ohne Titel)",
    start,
    end,
    allDay,
    date: toISO(d),
    time: allDay ? null : hhmm(d),
    location,
    join: httpsUrl(ev.onlineMeeting?.joinUrl) || httpsUrl(ev.onlineMeetingUrl) || findJoin(`${location}\n${notes}`),
    web: httpsUrl(ev.webLink),
    calendar: clean(calendar, 120),
    cancelled: !!ev.isCancelled || ev.responseStatus?.response === "declined",
    notes,
  };
}

// Mail = { id, account, provider, from, fromEmail, subject, snippet, date, web }
export function normGmail(m, { account = "", email = "" } = {}) {
  if (!m || typeof m !== "object" || !m.id) return null;
  const H = {};
  for (const h of m.payload?.headers || []) if (h && h.name) H[String(h.name).toLowerCase()] = str(h.value);
  const f = parseFrom(H.from);
  const thread = str(m.threadId || m.id);
  return {
    id: `g:${m.id}`,
    account,
    provider: "google",
    from: f.name || f.address || "Unbekannt",
    fromEmail: f.address,
    subject: clean(decodeHeader(H.subject), 300) || "(Kein Betreff)",
    snippet: clean(decodeEntities(m.snippet), 300),
    date: Number(m.internalDate) || Date.parse(H.date) || 0,
    web: `https://mail.google.com/mail/?authuser=${enc(email)}#all/${enc(thread)}`,
  };
}

export function normGraphMail(m, { account = "" } = {}) {
  if (!m || typeof m !== "object" || !m.id) return null;
  const a = m.from?.emailAddress || m.sender?.emailAddress || {};
  const address = clean(a.address, 254).toLowerCase();
  return {
    id: `m:${m.id}`,
    account,
    provider: "microsoft",
    from: clean(a.name, 120) || address || "Unbekannt",
    fromEmail: address,
    subject: clean(m.subject, 300) || "(Kein Betreff)",
    snippet: clean(m.bodyPreview, 300),
    date: Date.parse(m.receivedDateTime) || 0,
    web: httpsUrl(m.webLink),
  };
}

// ---------- Telefonnummern ----------
// +49 171 1234567 · 0171-1234567 · (0711) 12 34 56 · 030/1234567 · +49 (0)89 123456 · 0049 30 1234567
const PHONE_RE = /(?<![\p{L}\p{N}+])(?:\+\s?\d|00[1-9]|\(?0\d)[\d  ()/.\-–]{4,24}\d/gu;

function phoneOf(raw) {
  const s = raw.replace(/\(0\)/g, "").trim();
  if (/^\d{1,2}\.\d{1,2}\.(\d{2}|\d{4})?$/.test(s) || /\d{1,2}\.\d{1,2}\.\d{2,4}/.test(s)) return null; // Datum
  if ((s.match(/\./g) || []).length > 3) return null;
  let digits = s.replace(/\D/g, "");
  let intl = s.startsWith("+");
  if (!intl && digits.startsWith("00")) (digits = digits.slice(2)), (intl = true);
  if (intl) return digits.length >= 8 && digits.length <= 15 && digits[0] !== "0" ? "+" + digits : null;
  if (digits[0] !== "0" || digits[1] === "0") return null;
  return digits.length >= 7 && digits.length <= 14 ? digits : null;
}

// [{ label: "0171 1234567", tel: "01711234567" }]
export function phoneList(text) {
  const t = str(text);
  const out = [];
  const seen = new Set();
  for (const m of t.matchAll(PHONE_RE)) {
    const before = t.slice(Math.max(0, m.index - 10), m.index);
    if (/[A-Z]{2}\d{2}[\d ]*$/.test(before)) continue; // IBAN (DE89 3704 0044 …)
    const tel = phoneOf(m[0]);
    if (!tel || seen.has(tel)) continue;
    seen.add(tel);
    out.push({ label: m[0].replace(/[\s ]+/g, " ").trim(), tel });
  }
  return out.slice(0, 6);
}
export const phones = (text) => phoneList(text).map((p) => p.tel);
export const telHref = (tel) => "tel:" + str(tel).replace(/[^\d+]/g, "");

// E-Mail-Adressen (z. B. Empfänger aus den Notizen)
export function emails(text) {
  const out = [];
  for (const m of str(text).matchAll(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g)) {
    const e = m[0].replace(/\.+$/, "").toLowerCase();
    if (!out.includes(e)) out.push(e);
  }
  return out.slice(0, 5);
}

// „Anruf …“, „anrufen“, „Call“, „Rückruf“, „telefonieren“ → Tag „anruf“
const CALL_RE = /(?<![\p{L}\p{N}])(anruf\p{L}*|an(?:ge)?rufen|anrufe|r[üu]ckruf\p{L}*|zur[üu]ckrufen|telefonat\p{L}*|telefonier\p{L}*|call|calls)(?![\p{L}\p{N}])/iu;
export const isCall = (text) => CALL_RE.test(str(text));

// ---------- Links ohne Anmeldung ----------
const ymdC = (iso) => iso.replace(/-/g, "");
const utcC = (ms) => new Date(ms).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
function isoLocal(ms) {
  const d = new Date(ms);
  const off = -d.getTimezoneOffset();
  const sign = off >= 0 ? "+" : "-";
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}:00${sign}${pad(Math.floor(Math.abs(off) / 60))}:${pad(Math.abs(off) % 60)}`;
}
const wallClock = (ms) => isoLocal(ms).slice(0, 19); // ohne Zone (Graph mit timeZone)

function taskTimes(task) {
  const m = parseTime(task.time);
  if (m === null) return { allDay: true, start: atLocal(task.due, 0).getTime(), end: atLocal(addDays(task.due, 1), 0).getTime() };
  const start = atLocal(task.due, m).getTime();
  const est = Number.isFinite(task.est) && task.est > 0 ? Math.min(task.est, 1440) : 30;
  return { allDay: false, start, end: start + est * MIN };
}

function taskDetails(task, appUrl) {
  const parts = [];
  const notes = str(task.notes).trim();
  if (notes) parts.push(notes.length > 1500 ? notes.slice(0, 1499) + "…" : notes);
  const subs = (Array.isArray(task.subtasks) ? task.subtasks : []).filter((s) => s && str(s.title).trim());
  if (subs.length) parts.push(subs.slice(0, 30).map((s) => `${s.done ? "☑" : "☐"} ${str(s.title).trim()}`).join("\n"));
  if (appUrl && task.id) {
    try {
      const u = new URL(appUrl);
      u.hash = "";
      u.searchParams.set("task", task.id);
      parts.push(`In Arbeitstaschen öffnen: ${u.href}`);
    } catch (_) {
      /* ohne Link */
    }
  }
  return parts.join("\n\n");
}

// „In Google Kalender / Outlook eintragen“ ohne Konto – öffnet den Eintragen-Dialog im Browser
export function calendarLinks(task, profile = {}, { appUrl = "" } = {}) {
  if (!task || !isISO(task.due) || !str(task.title).trim()) return { google: null, outlook: null, office365: null };
  const { allDay, start, end } = taskTimes(task);
  const title = str(task.title).trim();
  const details = taskDetails(task, appUrl);
  const dates = allDay ? `${ymdC(task.due)}/${ymdC(addDays(task.due, 1))}` : `${utcC(start)}/${utcC(end)}`;
  const google = `https://calendar.google.com/calendar/render?action=TEMPLATE&text=${enc(title)}&dates=${dates}&details=${enc(details)}${allDay ? "" : `&ctz=${enc(deviceTz())}`}`;
  const q = allDay
    ? `subject=${enc(title)}&startdt=${task.due}&enddt=${addDays(task.due, 1)}&allday=true&body=${enc(details)}`
    : `subject=${enc(title)}&startdt=${enc(isoLocal(start))}&enddt=${enc(isoLocal(end))}&body=${enc(details)}`;
  const tail = "&path=%2Fcalendar%2Faction%2Fcompose&rru=addevent";
  return {
    google,
    outlook: `https://outlook.live.com/calendar/0/deeplink/compose?${q}${tail}`,
    office365: `https://outlook.office.com/calendar/0/deeplink/compose?${q}${tail}`,
  };
}

// „E-Mail schreiben“: Gmail, Outlook.com, Microsoft 365 und die Mail-App des Geräts
export function composeLinks({ to = "", subject = "", body = "", from = "" } = {}) {
  const rcpt = emails(Array.isArray(to) ? to.join(" ") : to).join(",");
  const su = str(subject).trim().slice(0, 300);
  const bd = str(body).trim().slice(0, 1800);
  const mailtoTo = rcpt
    .split(",")
    .filter(Boolean)
    .map((e) => enc(e).replace(/%40/g, "@"))
    .join(",");
  return {
    gmail: `https://mail.google.com/mail/?view=cm&fs=1${from ? `&authuser=${enc(from)}` : ""}&to=${enc(rcpt)}&su=${enc(su)}&body=${enc(bd)}`,
    outlook: `https://outlook.live.com/mail/0/deeplink/compose?to=${enc(rcpt)}&subject=${enc(su)}&body=${enc(bd)}`,
    office365: `https://outlook.office.com/mail/deeplink/compose?to=${enc(rcpt)}&subject=${enc(su)}&body=${enc(bd)}`,
    mailto: `mailto:${mailtoTo}?subject=${enc(su)}&body=${enc(bd)}`,
  };
}

// Privates Microsoft-Konto (Outlook.com) oder Firma (Microsoft 365)?
export const msPersonal = (email) => /@(outlook|hotmail|live|msn|passport)\.[a-z.]+$/i.test(str(email));

// ---------- Zustand ----------
let ST = null; // store.js (über start/refresh/handleReturn gesetzt)
let cache = { at: 0, events: [], mails: [], errors: [] };
let cacheReady = null;
let taken = {}; // Mail-/Termin-id → Aufgaben-id (kv „connect-taken“)
const tokens = new Map(); // Konto-id → { token, exp }
const tokenWait = new Map();
const listeners = new Set();
let running = null;
let again = false;
let busy = false;
let started = false;
let lastRet = null;

export function onChange(fn) {
  if (typeof fn !== "function") return () => {};
  listeners.add(fn);
  return () => listeners.delete(fn);
}
function emit() {
  for (const fn of [...listeners]) {
    try {
      fn();
    } catch (e) {
      if (typeof console !== "undefined") console.error("[taschen] Fehler in einem Konten-Listener:", e);
    }
  }
}

const liveAccounts = () => {
  try {
    return (ST?.accounts?.() || []).filter((a) => PROVIDERS.some((p) => p.id === a.provider));
  } catch (_) {
    return [];
  }
};
const accountById = (id) => liveAccounts().find((a) => a.id === id) || null;
export const accounts = () => liveAccounts();

async function loadCache() {
  if (!cacheReady) {
    cacheReady = (async () => {
      if (!ST?.kvGet) return;
      try {
        const v = await ST.kvGet(CACHE_KEY);
        if (v && typeof v === "object" && Array.isArray(v.events) && Array.isArray(v.mails) && !cache.at) cache = { at: Number(v.at) || 0, sig: str(v.sig), events: v.events, mails: v.mails, errors: Array.isArray(v.errors) ? v.errors : [] };
        const t = await ST.kvGet(TAKEN_KEY);
        if (t && typeof t === "object") taken = { ...t, ...taken };
      } catch (_) {
        /* ohne Speicher: nur für diese Sitzung */
      }
    })();
  }
  return cacheReady;
}
function saveCache() {
  try {
    ST?.kvSet?.(CACHE_KEY, cache)?.catch?.(() => {});
  } catch (_) {
    /* nur im Speicher */
  }
}

// Zuletzt geladene Termine (ohne abgesagte, nur Konten mit „Termine anzeigen“)
export function events({ all = false } = {}) {
  const accs = ST ? new Map(liveAccounts().map((a) => [a.id, a])) : null;
  return cache.events.filter((e) => e && (all || !e.cancelled) && (!accs || (accs.has(e.account) && accs.get(e.account).calendars !== false)));
}
// Termine an einem Tag (auch mehrtägige, die über den Tag laufen)
export function eventsOn(iso, list = events()) {
  if (!isISO(iso)) return [];
  const a = atLocal(iso, 0).getTime();
  const b = atLocal(addDays(iso, 1), 0).getTime();
  return list.filter((e) => e.start < b && (e.end > a || (e.end === e.start && e.start >= a))).sort((x, y) => Number(y.allDay) - Number(x.allDay) || x.start - y.start || x.title.localeCompare(y.title));
}
export function mails({ all = false } = {}) {
  const accs = ST ? new Map(liveAccounts().map((a) => [a.id, a])) : null;
  const done = all ? null : takenSet();
  return cache.mails.filter((m) => m && (!accs || (accs.has(m.account) && accs.get(m.account).mail !== false)) && (!done || !done.has(m.id)));
}
export const event = (id) => cache.events.find((e) => e.id === id) || null;
export const mail = (id) => cache.mails.find((m) => m.id === id) || null;
export const info = () => ({ at: cache.at, busy, errors: cache.errors.filter((e) => accountById(e.account)) });

// Fehler je Konto (für die Einstellungen): { kind: "expired"|"error"|"network", msg }
export function accountState(id) {
  const a = accountById(id);
  if (!a) return null;
  if (!a.secret) return { kind: "expired", msg: "Schlüssel fehlt (z. B. nach einem Backup) – bitte neu verbinden." };
  if (a.broken) return { kind: "expired", msg: "Die Verbindung ist abgelaufen – bitte neu verbinden." };
  const e = cache.errors.find((x) => x.account === id);
  if (e) return { kind: e.expired ? "expired" : e.network ? "network" : "error", msg: e.msg };
  return { kind: "ok", msg: "" };
}

// Übernommene Mails/Termine (als Aufgabe) – lokal gemerkt und an der Aufgabe selbst (src), damit es auf allen Geräten gilt
function takenSet() {
  const s = new Set();
  try {
    for (const t of ST?.get?.()?.tasks || []) if (t?.src?.id) s.add(t.src.id); // auch gelöschte: einmal übernommen bleibt übernommen
  } catch (_) {
    /* ohne Store */
  }
  for (const [k, v] of Object.entries(taken)) v === false ? s.delete(k) : s.add(k); // false = ausdrücklich wieder anbieten (Rückgängig)
  return s;
}
export function takenTask(id) {
  try {
    const t = (ST?.get?.()?.tasks || []).find((x) => x?.src?.id === id && !x.deleted);
    if (t) return t.id;
  } catch (_) {
    /* ohne Store */
  }
  return typeof taken[id] === "string" ? taken[id] : null;
}
export const isTaken = (id) => takenSet().has(id);
// taskId: Aufgaben-id | true (nur ausgeblendet) | false (wieder anbieten)
export function markTaken(id, taskId = true) {
  if (!id) return;
  taken[id] = taskId === false ? false : typeof taskId === "string" && taskId ? taskId : true;
  const keys = Object.keys(taken);
  if (keys.length > 500) for (const k of keys.slice(0, keys.length - 500)) delete taken[k];
  try {
    ST?.kvSet?.(TAKEN_KEY, taken)?.catch?.(() => {});
  } catch (_) {
    /* nur für diese Sitzung */
  }
  emit();
}

// ---------- Server ----------
function defaultServer() {
  const fixed = normServer(SERVER.url);
  if (fixed) return fixed;
  try {
    const s = normServer(syncStatus().server);
    if (s) return s;
  } catch (_) {
    /* kein Sync */
  }
  return "";
}

// Bietet der Server Google/Microsoft an? (aus /api/health → connect)
export async function status(server) {
  const base = normServer(server);
  if (!base) return { google: false, microsoft: false, server: "", ok: false };
  const chk = await checkServer(base);
  return { google: !!(chk.ok && chk.connect?.google), microsoft: !!(chk.ok && chk.connect?.microsoft), server: chk.ok ? base : "", ok: !!chk.ok };
}

const appAddress = () => {
  const u = new URL("./", location.href);
  u.hash = "";
  u.search = "";
  return u.href;
};

// Anmeldung beginnen: weiter zum Server → Google/Microsoft → zurück zur App mit #connect=…
// Merker „diese App hat die Anmeldung selbst gestartet“ (sessionStorage, gilt 15 Min.) – ein fremder Link mit #connect=… wird ignoriert
const PENDING_MAX = 15 * MIN;
function pendingStore() {
  try {
    if (typeof sessionStorage !== "undefined") return sessionStorage;
  } catch (_) {
    /* gesperrt */
  }
  return null;
}
function takePending() {
  const st = pendingStore();
  if (!st) return null;
  try {
    const v = JSON.parse(st.getItem(PENDING_KEY) || "null");
    st.removeItem(PENDING_KEY);
    return v && typeof v === "object" && Date.now() - Number(v.at || 0) <= PENDING_MAX && Date.now() >= Number(v.at || 0) - 60000 ? v : null;
  } catch (_) {
    return null;
  }
}

// Anmeldung beginnen: Navigation auf oberster Ebene (kein Pop-up – der Server setzt ein Cookie für start → callback)
export function startConnect(provider, server, { back = "#einstellungen/konten" } = {}) {
  if (!PROVIDERS.some((p) => p.id === provider)) throw new Error("Unbekannter Anbieter.");
  const base = normServer(server) || defaultServer();
  if (!base) throw new Error("Dafür braucht es den Arbeitstaschen-Server – trag ihn in den Einstellungen unter „Sync“ ein.");
  const st = pendingStore();
  if (!st) throw new Error("Dieser Browser erlaubt keinen Zwischenspeicher (privater Modus?) – so kann die Anmeldung nicht sicher zurückkehren.");
  st.setItem(PENDING_KEY, JSON.stringify({ provider, server: base, back: /^#[\w/-]*$/.test(back) ? back : "", at: Date.now() }));
  const url = `${base}/api/connect/${provider}/start?return=${enc(appAddress())}`;
  location.href = url;
  return url;
}

export const lastReturn = () => lastRet;

// Rückkehr aus der Anmeldung: #connect=<provider>&account=<32 hex>&secret=<base64url>&email=<…> oder #connect=<provider>&error=<…>
// → true, wenn eine (selbst gestartete) Rückkehr verarbeitet wurde; Ergebnis über lastReturn()
export function handleReturn(store) {
  if (store) ST = store;
  if (typeof location === "undefined") return false;
  const h = str(location.hash);
  if (!/^#connect=/.test(h)) return false;
  const q = new URLSearchParams(h.slice(1));
  const pending = takePending();
  const provider = q.get("connect");
  const ours = !!pending && pending.provider === provider;
  const back = (ours && pending.back) || (ours ? "#einstellungen/konten" : "#heute");
  // Schlüssel sofort aus der Adresszeile (und dem Verlauf) entfernen
  try {
    history.replaceState(null, "", location.pathname + location.search + back);
  } catch (_) {
    location.hash = back;
  }
  if (!ours) {
    lastRet = null; // nicht von hier gestartet (z. B. fremder Link) → nichts übernehmen
    return false;
  }
  if (!PROVIDERS.some((p) => p.id === provider)) {
    lastRet = { ok: false, provider: null, error: "Der Server hat unverständlich geantwortet – bitte noch einmal verbinden." };
    return true;
  }
  const err = q.get("error");
  if (err) {
    lastRet = { ok: false, provider, error: clean(err, 300) || "Die Anmeldung hat nicht geklappt." };
    return true;
  }
  const id = str(q.get("account")).toLowerCase();
  const secret = str(q.get("secret"));
  const email = clean(q.get("email"), 254);
  if (!/^[0-9a-f]{32}$/.test(id) || !/^[A-Za-z0-9_-]{16,200}$/.test(secret)) {
    lastRet = { ok: false, provider, error: "Die Antwort des Servers war unvollständig – bitte noch einmal verbinden." };
    return true;
  }
  const server = normServer(pending.server) || defaultServer();
  try {
    // Dasselbe Postfach schon verbunden? Der Server hat den alten Eintrag ersetzt → hier ebenfalls ersetzen (Farbe & Schalter bleiben)
    const same = liveAccounts().filter((a) => a.id !== id && a.provider === provider && email && a.email.toLowerCase() === email.toLowerCase());
    const keep = same[0] ? { color: same[0].color, calendars: same[0].calendars, mail: same[0].mail } : {};
    for (const a of same) {
      ST.removeAccount(a.id);
      dropAccount(a.id);
    }
    const acc = ST.addAccount({ ...keep, id, provider, email, secret, server });
    tokens.delete(acc.id);
    lastRet = { ok: true, provider, email, account: acc.id, replaced: same.length > 0 };
  } catch (e) {
    lastRet = { ok: false, provider, error: e?.message || "Das Konto konnte nicht gespeichert werden." };
  }
  return true;
}

function removeRemote(a) {
  if (!a?.secret || !a.server) return Promise.resolve(false);
  return request(a.server, "/api/connect/remove", { method: "POST", json: { account: a.id, secret: a.secret }, timeout: 15000 })
    .then((r) => r.ok || r.status === 404 || r.status === 410 || r.status === 403)
    .catch(() => false);
}

function dropAccount(id) {
  tokens.delete(id);
  const n = cache.events.length + cache.mails.length + cache.errors.length;
  cache = { ...cache, events: cache.events.filter((e) => e.account !== id), mails: cache.mails.filter((m) => m.account !== id), errors: cache.errors.filter((e) => e.account !== id) };
  if (cache.events.length + cache.mails.length + cache.errors.length !== n) saveCache();
}

// Trennen: beim Server widerrufen und löschen, dann hier (und per Sync überall) entfernen
export async function disconnect(id) {
  const a = accountById(id) || ST?.account?.(id);
  if (!a) return { ok: false, remote: false };
  const remote = await removeRemote(a);
  ST.removeAccount(a.id);
  dropAccount(a.id);
  emit();
  return { ok: true, remote };
}

// ---------- Zugangs-Token (vom Server, im Speicher bis kurz vor Ablauf) ----------
function expiredError(a, msg) {
  const e = new Error(msg || `Die Verbindung zu ${a.email || providerName(a.provider)} ist abgelaufen – bitte neu verbinden.`);
  e.expired = true;
  return e;
}

export async function token(account, { force = false } = {}) {
  const a = typeof account === "string" ? accountById(account) : account;
  if (!a || !a.id) throw new Error("Dieses Konto gibt es nicht mehr.");
  if (!a.secret) throw expiredError(a, `Für ${a.email || providerName(a.provider)} fehlt der Schlüssel (z. B. nach einem Backup-Import) – bitte neu verbinden.`);
  const server = normServer(a.server) || defaultServer();
  if (!server) throw new Error("Kein Arbeitstaschen-Server eingetragen.");
  const c = tokens.get(a.id);
  if (!force && c && c.exp - 60000 > Date.now()) return c.token;
  if (tokenWait.has(a.id)) return tokenWait.get(a.id);
  const p = (async () => {
    const r = await request(server, "/api/connect/token", { method: "POST", json: { account: a.id, secret: a.secret }, timeout: 15000 });
    if (r.ok && typeof r.data?.access_token === "string" && r.data.access_token) {
      const exp = Number(r.data.expires_at) > Date.now() ? Number(r.data.expires_at) : Date.now() + 50 * MIN;
      tokens.set(a.id, { token: r.data.access_token, exp });
      if (a.broken) safeCall(() => ST.updateAccount(a.id, { broken: false }));
      return r.data.access_token;
    }
    if (r.status === 410 || r.status === 403 || r.status === 404) {
      tokens.delete(a.id);
      if (!a.broken) safeCall(() => ST.updateAccount(a.id, { broken: true }));
      throw expiredError(a, r.data?.msg);
    }
    if (r.status === 429) throw quiet(new Error("Der Server bremst gerade – gleich geht’s weiter."));
    if (r.status === 502 || r.status === 504) throw quiet(new Error(r.data?.msg || `${providerName(a.provider)} ist gerade nicht erreichbar – ich zeige die zuletzt geladenen Daten.`));
    if (r.status === 501 || r.status === 503) throw new Error(r.data?.msg || `Der Server bietet die Verbindung zu ${providerName(a.provider)} gerade nicht an.`);
    throw new Error(r.data?.msg || `Serverfehler (${r.status}).`);
  })().finally(() => tokenWait.delete(a.id));
  tokenWait.set(a.id, p);
  return p;
}
// Vorübergehende Störung: still aus dem Cache weiter, Fehler nur leise anzeigen
function quiet(e) {
  e.network = true;
  return e;
}
function safeCall(fn) {
  try {
    fn();
  } catch (_) {
    /* nur Kür */
  }
}

// Anfrage an Google/Microsoft mit Zugangs-Token; 401 → Token einmal neu holen und wiederholen
async function api(a, url, { method = "GET", body, headers = {} } = {}, retried = false) {
  const tk = await token(a, { force: retried });
  const ctrl = typeof AbortController === "function" ? new AbortController() : null;
  const timer = ctrl ? setTimeout(() => ctrl.abort(), 20000) : null;
  let res;
  try {
    res = await fetch(url, {
      method,
      headers: { Authorization: `Bearer ${tk}`, Accept: "application/json", ...(body !== undefined ? { "Content-Type": "application/json" } : {}), ...headers },
      body: body !== undefined ? JSON.stringify(body) : undefined,
      cache: "no-store",
      credentials: "omit",
      signal: ctrl?.signal,
    });
  } catch (e) {
    const x = new Error(!online() ? "Du bist offline." : e?.name === "AbortError" ? `${providerName(a.provider)} antwortet nicht.` : `${providerName(a.provider)} ist gerade nicht erreichbar.`);
    x.network = true;
    throw x;
  } finally {
    if (timer) clearTimeout(timer);
  }
  if (res.status === 401 && !retried) {
    tokens.delete(a.id);
    return api(a, url, { method, body, headers }, true);
  }
  const data = await res.json().catch(() => null);
  if (!res.ok) {
    const e = new Error(apiMessage(a, res.status, data));
    e.status = res.status;
    if (res.status === 401) e.expired = true;
    throw e;
  }
  return data;
}

function apiMessage(a, status, data) {
  const who = providerName(a.provider);
  const raw = clean(data?.error?.message || data?.error_description || "", 160);
  if (status === 401) return `${who} hat die Anmeldung für ${a.email} nicht angenommen – bitte neu verbinden.`;
  if (status === 403) return /insufficient|scope|permission|Access is denied|not have/i.test(raw) ? `Es fehlen Berechtigungen für ${a.email} – bitte neu verbinden und alle Häkchen setzen.` : `${who} verweigert den Zugriff${raw ? `: ${raw}` : "."}`;
  if (status === 404) return `${who} kennt den Kalender bzw. das Postfach nicht.`;
  if (status === 429) return `${who} bremst gerade – gleich geht’s weiter.`;
  if (status >= 500) return `${who} hat gerade Probleme (${status}).`;
  return raw ? `${who}: ${raw}` : `${who} meldet Fehler ${status}.`;
}

// ---------- Laden ----------
async function googleEvents(a, from, to) {
  const list = await api(a, `${API.gcal}/users/me/calendarList?maxResults=250`);
  let cals = (Array.isArray(list?.items) ? list.items : []).filter((c) => c && c.id && c.selected && !c.deleted && !c.hidden);
  if (!cals.length) cals = [{ id: "primary", summary: "Kalender" }];
  const q = `timeMin=${enc(new Date(from).toISOString())}&timeMax=${enc(new Date(to).toISOString())}&singleEvents=true&orderBy=startTime&maxResults=250`;
  const res = await Promise.allSettled(
    cals.slice(0, 25).map(async (c) => {
      const d = await api(a, `${API.gcal}/calendars/${enc(c.id)}/events?${q}`);
      const name = c.summaryOverride || (c.primary ? "Kalender" : c.summary) || "Kalender";
      return (Array.isArray(d?.items) ? d.items : []).map((ev) => normGoogleEvent(ev, { account: a.id, calendar: name, calId: c.id })).filter(Boolean);
    }),
  );
  const ok = res.filter((r) => r.status === "fulfilled");
  if (!ok.length && res.length) throw res[0].reason;
  return ok.flatMap((r) => r.value);
}

async function graphEvents(a, from, to) {
  const sel = "subject,start,end,isAllDay,location,onlineMeeting,onlineMeetingUrl,webLink,isCancelled,bodyPreview,responseStatus";
  let url = `${API.graph}/me/calendarView?startDateTime=${enc(new Date(from).toISOString())}&endDateTime=${enc(new Date(to).toISOString())}&$top=250&$select=${sel}`;
  const out = [];
  for (let page = 0; url && page < 8; page++) {
    const d = await api(a, url, { headers: { Prefer: `outlook.timezone="${deviceTz()}"` } });
    for (const ev of Array.isArray(d?.value) ? d.value : []) {
      const n = normGraphEvent(ev, { account: a.id, calendar: "Outlook" });
      if (n) out.push(n);
    }
    const next = str(d?.["@odata.nextLink"]);
    url = next.startsWith(API.graph + "/") ? next : ""; // Token nie an fremde Adressen schicken
  }
  return out;
}

async function googleMails(a) {
  const d = await api(a, `${API.gmail}/messages?q=${enc("is:starred")}&maxResults=25`);
  const ids = (Array.isArray(d?.messages) ? d.messages : []).filter((m) => m && m.id).slice(0, 25);
  const res = await Promise.allSettled(ids.map((m) => api(a, `${API.gmail}/messages/${enc(m.id)}?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Date`)));
  return res.filter((r) => r.status === "fulfilled").map((r) => normGmail(r.value, { account: a.id, email: a.email })).filter(Boolean);
}

async function graphMails(a) {
  const d = await api(a, `${API.graph}/me/messages?$filter=${enc("flag/flagStatus eq 'flagged'")}&$top=25&$select=subject,from,receivedDateTime,webLink,bodyPreview`);
  return (Array.isArray(d?.value) ? d.value : []).map((m) => normGraphMail(m, { account: a.id })).filter(Boolean);
}

function errInfo(a, e, what) {
  return { account: a.id, email: a.email, provider: a.provider, what, msg: clean(e?.message || "Unbekannter Fehler", 240), expired: !!e?.expired, network: !!e?.network, at: Date.now() };
}

const result = () => ({ events: events(), mails: mails(), errors: info().errors });

// Alle Konten: Termine (gestern bis +30 Tage) und markierte Mails – höchstens alle 5 Min. (außer force), offline still aus dem Cache
export function refresh(store, { force = false, retryBroken = false } = {}) {
  if (store) ST = store;
  if (running) {
    if (force) again = true;
    return running;
  }
  running = (async () => {
    await loadCache();
    const accs = liveAccounts();
    if (!accs.length) {
      if (cache.events.length || cache.mails.length || cache.errors.length) {
        cache = { at: 0, events: [], mails: [], errors: [] };
        saveCache();
        emit();
      }
      return result();
    }
    const sig = accSig();
    const fresh = Date.now() - cache.at < STALE && cache.sig === sig;
    if ((!force && fresh) || !online()) return result();
    busy = true;
    emit();
    const now = Date.now();
    const from = startOfDay(now) - DAY;
    const to = startOfDay(now) + 31 * DAY;
    const evs = [];
    const ms = [];
    const errors = [];
    await Promise.all(
      accs.map(async (a) => {
        const prevE = cache.events.filter((e) => e.account === a.id);
        const prevM = cache.mails.filter((m) => m.account === a.id);
        if (!a.secret || (a.broken && !retryBroken)) {
          errors.push(errInfo(a, expiredError(a, !a.secret ? `Für ${a.email} fehlt der Schlüssel – bitte neu verbinden.` : undefined), "Konto"));
          evs.push(...prevE);
          ms.push(...prevM);
          return;
        }
        const g = a.provider === "google";
        const jobs = [];
        if (a.calendars !== false)
          jobs.push(
            (g ? googleEvents(a, from, to) : graphEvents(a, from, to)).then(
              (list) => evs.push(...list),
              (e) => {
                errors.push(errInfo(a, e, "Termine"));
                evs.push(...prevE);
              },
            ),
          );
        if (a.mail !== false)
          jobs.push(
            (g ? googleMails(a) : graphMails(a)).then(
              (list) => ms.push(...list),
              (e) => {
                if (!errors.some((x) => x.account === a.id && x.expired)) errors.push(errInfo(a, e, "Mails"));
                ms.push(...prevM);
              },
            ),
          );
        await Promise.all(jobs);
      }),
    );
    // Gleicher Termin in zwei Kalendern (z. B. geteilt) nur einmal
    const seen = new Set();
    const events1 = evs
      .sort((x, y) => x.start - y.start || x.title.localeCompare(y.title))
      .filter((e) => {
        const k = `${e.account}|${e.title}|${e.start}|${e.end}`;
        if (seen.has(k)) return false;
        seen.add(k);
        return true;
      });
    cache = { at: now, sig, events: events1, mails: ms.sort((x, y) => y.date - x.date), errors };
    saveCache();
    return result();
  })().finally(() => {
    running = null;
    busy = false;
    emit();
    if (again) {
      again = false;
      refresh(ST, { force: true }).catch(() => {});
    }
  });
  return running;
}

// ---------- In den Kalender eintragen (über das verbundene Konto) ----------
export async function createEvent(account, task, profile = {}, { appUrl = "" } = {}) {
  const a = typeof account === "string" ? accountById(account) : account;
  if (!a) throw new Error("Dieses Konto gibt es nicht mehr.");
  if (!task || !isISO(task.due)) throw new Error("Gib der Aufgabe zuerst ein Datum.");
  const { allDay, start, end } = taskTimes(task);
  const r = task.remind ?? profile?.defaultRemind ?? 15;
  const remindMin = Number.isFinite(r) && r >= 0 ? Math.min(Math.round(r), 40320) : null; // −1 = keine Erinnerung
  const title = str(task.title).trim() || "Aufgabe";
  const desc = taskDetails(task, appUrl);
  const tz = deviceTz();
  let web = "", id = null;
  if (a.provider === "google") {
    const body = {
      summary: title,
      description: desc,
      start: allDay ? { date: task.due } : { dateTime: isoLocal(start), timeZone: tz },
      end: allDay ? { date: addDays(task.due, 1) } : { dateTime: isoLocal(end), timeZone: tz },
      reminders: allDay ? { useDefault: true } : remindMin === null ? { useDefault: false, overrides: [] } : { useDefault: false, overrides: [{ method: "popup", minutes: remindMin }] },
    };
    if (allDay) body.transparency = "transparent";
    const d = await api(a, `${API.gcal}/calendars/primary/events`, { method: "POST", body });
    web = httpsUrl(d?.htmlLink);
    id = d?.id || null;
  } else if (a.provider === "microsoft") {
    const body = {
      subject: title,
      body: { contentType: "text", content: desc },
      start: { dateTime: allDay ? `${task.due}T00:00:00` : wallClock(start), timeZone: tz },
      end: { dateTime: allDay ? `${addDays(task.due, 1)}T00:00:00` : wallClock(end), timeZone: tz },
      isAllDay: allDay,
    };
    if (allDay) body.showAs = "free";
    else Object.assign(body, { isReminderOn: remindMin !== null, reminderMinutesBeforeStart: remindMin ?? 0 });
    const d = await api(a, `${API.graph}/me/events`, { method: "POST", body });
    web = httpsUrl(d?.webLink);
    id = d?.id || null;
  } else throw new Error("Unbekannter Anbieter.");
  refresh(ST, { force: true }).catch(() => {});
  return { web, id };
}

// ---------- Aufgaben aus Mails und Terminen ----------
export function taskFromMail(m) {
  const who = m.fromEmail && m.from !== m.fromEmail ? `${m.from} <${m.fromEmail}>` : m.from || m.fromEmail;
  return { title: m.subject || `Mail von ${m.from}`, notes: [`Von ${who}`, m.web].filter(Boolean).join(" · "), src: { kind: "mail", id: m.id, provider: m.provider, web: m.web || "", email: m.fromEmail || "" } };
}
export function taskFromEvent(e) {
  const dur = Math.round((e.end - e.start) / MIN);
  return {
    title: e.title,
    due: e.date,
    time: e.allDay ? null : e.time,
    est: !e.allDay && dur > 0 && dur <= 720 ? dur : null,
    remind: -1, // der Termin erinnert schon selbst
    notes: [e.location ? `📍 ${e.location}` : "", e.join ? `${joinKind(e.join)}: ${e.join}` : "", e.web ? `Im Kalender: ${e.web}` : ""].filter(Boolean).join("\n"),
    src: { kind: "event", id: e.id, provider: e.provider, web: e.web || "", join: e.join || "" },
  };
}

// ---------- Erinnerungen für remind.js ----------
function fnv(s) {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(36);
}
// Termine mit Uhrzeit: profile.defaultRemind Minuten vorher (kind "event")
export function eventReminders(now = new Date(), profile = {}) {
  const nowMs = now instanceof Date ? now.getTime() : Number(now) || Date.now();
  const r0 = Number(profile?.defaultRemind);
  const r = Number.isFinite(r0) && r0 >= 0 ? r0 : 15;
  const out = [];
  for (const e of events()) {
    if (e.allDay || e.cancelled || !Number.isFinite(e.start)) continue;
    const at = e.start - r * MIN;
    if (at <= nowMs - 60000 || at > nowMs + 8 * DAY) continue;
    const when = `${fmtTime(e.time)} Uhr${r > 0 ? ` (in ${fmtDuration(r)})` : ""}`;
    const kind = e.join ? joinKind(e.join) : "";
    out.push({ at, kind: "event", eventId: e.id, title: `📅 ${e.title.length > 56 ? e.title.slice(0, 55) + "…" : e.title}`, body: [when, e.location, kind ? `${kind}-Call` : ""].filter(Boolean).join(" · "), tag: `event-${fnv(e.id)}-${e.start}`, join: e.join || null, web: e.web || null });
  }
  return out.sort((a, b) => a.at - b.at);
}

// Kurzfassung für das Briefing: „📅 3 Termine – erster um 9:00: Call mit Müller“
export function eventSummary(iso) {
  const list = eventsOn(iso);
  if (!list.length) return "";
  const timed = list.filter((e) => !e.allDay && e.date === iso);
  const first = timed[0];
  return `📅 ${list.length === 1 ? "1 Termin" : `${list.length} Termine`}${first ? ` – ${list.length === 1 ? "um" : "erster um"} ${fmtTime(first.time)}: ${first.title.length > 40 ? first.title.slice(0, 39) + "…" : first.title}` : ""}`;
}

// ---------- Start ----------
const accSig = () =>
  liveAccounts()
    .map((a) => `${a.id}:${a.secret ? 1 : 0}${a.calendars !== false ? 1 : 0}${a.mail !== false ? 1 : 0}`)
    .join("|");

export function start(store) {
  if (store) ST = store;
  if (started || !ST) return;
  started = true;
  loadCache().then(() => {
    emit();
    refresh(ST).catch(() => {});
  });
  let sig = accSig();
  let t = null;
  ST.subscribe?.(() => {
    const s2 = accSig();
    if (s2 === sig) return;
    sig = s2;
    clearTimeout(t);
    t = setTimeout(() => refresh(ST, { force: true }).catch(() => {}), 300);
  });
  if (!hasWin()) return;
  document.addEventListener("visibilitychange", () => document.visibilityState === "visible" && refresh(ST).catch(() => {}));
  window.addEventListener("online", () => refresh(ST).catch(() => {}));
  setInterval(() => {
    if (document.visibilityState === "visible") refresh(ST).catch(() => {});
  }, STALE + 5000);
}

// Nur für Tests: Zustand zurücksetzen bzw. Daten setzen
export function _reset({ store = null, data = null } = {}) {
  ST = store;
  cache = data ? { at: Date.now(), events: data.events || [], mails: data.mails || [], errors: data.errors || [] } : { at: 0, events: [], mails: [], errors: [] };
  cacheReady = Promise.resolve();
  taken = {};
  tokens.clear();
  tokenWait.clear();
  running = null;
  lastRet = null;
}
