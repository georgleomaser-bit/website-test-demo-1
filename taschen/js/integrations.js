// Arbeitstaschen – „Mit allem verbinden“: Kalender-Abos (ICS/webcal), E-Mail per IMAP (GMX, WEB.DE, T-Online, iCloud …),
// Webhooks (Siri & Kurzbefehle, Zapier, Make, n8n, IFTTT – rein und raus), Nachrichten & Anrufe (WhatsApp, SMS, FaceTime,
// Teams, Karten) und CSV/Excel-Export und -Import (Excel, Todoist, Trello, Asana).
// Beim Import nichts von window/document/location anfassen – Parser, Links und CSV laufen auch in Node (Tests).
import { request, normServer, checkServer } from "./sync.js";
import { safeUrl } from "./util.js";
import { toISO, addDays, atLocal, isISO, parseTime, toTime, parseQuick, matchBag, normName, fmtDay, fmtTime } from "./dates.js";
import * as connect from "./connect.js";

const MIN = 60000;
const DAY = 86400000;
const enc = encodeURIComponent;
const pad = (n) => String(n).padStart(2, "0");
const str = (v) => (v === null || v === undefined ? "" : String(v));
const hasWin = () => typeof window !== "undefined" && typeof document !== "undefined";
const online = () => typeof navigator === "undefined" || navigator.onLine !== false;

// Text aus fremden Quellen: Steuer- und Richtungszeichen weg, Leerraum zusammenfassen, Länge begrenzen
const CTRL = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f​-‏‪-‮⁦-⁩]/g;
export function clean(s, max = 500) {
  return str(s).replace(CTRL, "").replace(/\s+/g, " ").trim().slice(0, max);
}
// … mit Zeilenumbrüchen (Notizen, Beschreibungen)
export function cleanText(s, max = 4000) {
  return str(s)
    .replace(/\r\n?/g, "\n")
    .replace(CTRL, "")
    .replace(/[ \t ]+/g, " ")
    .replace(/ *\n */g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim()
    .slice(0, max);
}
// Links aus fremden Daten: nur http(s)
export function webUrl(u) {
  const s = str(u).trim();
  if (!/^https?:\/\//i.test(s)) return "";
  const x = safeUrl(s);
  return /^https?:\/\//.test(x) ? x : "";
}
// Deep-Links (Telefon, SMS, FaceTime): nur diese Schemata – alles andere fällt weg
export const LINK_SCHEMES = ["tel:", "sms:", "facetime:", "facetime-audio:"];
export const safeLink = (u) => safeUrl(u, { schemes: LINK_SCHEMES });

let devTz = "";
let devTzAt = 0;
const deviceTz = () => {
  // teuer (Intl) → kurz merken; Reisen/Zeitzonenwechsel greift nach einer Minute
  if (devTz && Date.now() - devTzAt < 60000) return devTz;
  try {
    devTz = Intl.DateTimeFormat().resolvedOptions().timeZone || "Europe/Berlin";
  } catch (_) {
    devTz = "Europe/Berlin";
  }
  devTzAt = Date.now();
  return devTz;
};
const hhmm = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;
const startOfDay = (ms) => {
  const d = new Date(ms);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
};
function fnv(s) {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(36);
}

// =====================================================================================================================
// Zeitzonen
// =====================================================================================================================
// Windows-Zonennamen (Outlook, Exchange) → IANA (Auszug aus CLDR windowsZones)
export const WINDOWS_TZ = {
  "W. Europe Standard Time": "Europe/Berlin",
  "Central Europe Standard Time": "Europe/Budapest",
  "Central European Standard Time": "Europe/Warsaw",
  "Romance Standard Time": "Europe/Paris",
  "GMT Standard Time": "Europe/London",
  "Greenwich Standard Time": "Atlantic/Reykjavik",
  "UTC": "UTC",
  "Coordinated Universal Time": "UTC",
  "E. Europe Standard Time": "Europe/Chisinau",
  "FLE Standard Time": "Europe/Kiev",
  "GTB Standard Time": "Europe/Bucharest",
  "Russian Standard Time": "Europe/Moscow",
  "Turkey Standard Time": "Europe/Istanbul",
  "Israel Standard Time": "Asia/Jerusalem",
  "Egypt Standard Time": "Africa/Cairo",
  "South Africa Standard Time": "Africa/Johannesburg",
  "Arabian Standard Time": "Asia/Dubai",
  "India Standard Time": "Asia/Kolkata",
  "China Standard Time": "Asia/Shanghai",
  "Singapore Standard Time": "Asia/Singapore",
  "Tokyo Standard Time": "Asia/Tokyo",
  "Korea Standard Time": "Asia/Seoul",
  "AUS Eastern Standard Time": "Australia/Sydney",
  "New Zealand Standard Time": "Pacific/Auckland",
  "Eastern Standard Time": "America/New_York",
  "Central Standard Time": "America/Chicago",
  "Mountain Standard Time": "America/Denver",
  "US Mountain Standard Time": "America/Phoenix",
  "Pacific Standard Time": "America/Los_Angeles",
  "Alaskan Standard Time": "America/Anchorage",
  "Hawaiian Standard Time": "Pacific/Honolulu",
  "Atlantic Standard Time": "America/Halifax",
  "Canada Central Standard Time": "America/Regina",
  "E. South America Standard Time": "America/Sao_Paulo",
  "Argentina Standard Time": "America/Buenos_Aires",
  "Mexico Standard Time": "America/Mexico_City",
  "Central Standard Time (Mexico)": "America/Mexico_City",
};
const WINDOWS_LC = Object.fromEntries(Object.entries(WINDOWS_TZ).map(([k, v]) => [k.toLowerCase(), v]));
// Outlook-Anzeigenamen („(UTC+01:00) Amsterdam, Berlin, Bern, Rom …“, „Mitteleuropäische Zeit“) → Zone
const TZ_WORDS = [
  [/berlin|amsterdam|wien|vienna|\bbern\b|z[üu]rich|\brom\b|\brome\b|stockholm|paris|br[üu]ssel|brussels|madrid|kopenhagen|copenhagen|\boslo\b|prag|prague|warschau|warsaw|budapest|mitteleurop|central europe|w\. europe|romance|\bcet\b|\bcest\b|\bmez\b|\bmesz\b/i, "Europe/Berlin"],
  [/london|dublin|lissabon|lisbon|edinburgh|westeurop|gmt standard|\bwet\b/i, "Europe/London"],
  [/athen|athens|helsinki|kiew|kyiv|kiev|bukarest|bucharest|\briga\b|tallinn|vilnius|sofia|osteurop|eastern europe|\beet\b/i, "Europe/Helsinki"],
  [/moskau|moscow/i, "Europe/Moscow"],
  [/istanbul/i, "Europe/Istanbul"],
  [/new york|eastern time|us eastern/i, "America/New_York"],
  [/chicago|central time/i, "America/Chicago"],
  [/denver|mountain time/i, "America/Denver"],
  [/los angeles|pacific time/i, "America/Los_Angeles"],
];
// Standard-/Sommerzeit-Versatz aus VTIMEZONE → bekannte Regeln
const TZ_OFFSETS = { "60/120": "Europe/Berlin", "0/60": "Europe/London", "120/180": "Europe/Helsinki", "-300/-240": "America/New_York", "-360/-300": "America/Chicago", "-420/-360": "America/Denver", "-480/-420": "America/Los_Angeles", "600/660": "Australia/Sydney" };

const fmtCache = new Map();
function tzFormat(tz) {
  let f = fmtCache.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", { timeZone: tz, hourCycle: "h23", year: "numeric", month: "numeric", day: "numeric", hour: "numeric", minute: "numeric", second: "numeric" });
    if (fmtCache.size > 64) fmtCache.clear();
    fmtCache.set(tz, f);
  }
  return f;
}
const badTz = new Set();
export function validTz(tz) {
  if (!tz || typeof tz !== "string" || badTz.has(tz)) return false;
  try {
    tzFormat(tz);
    return true;
  } catch (_) {
    if (badTz.size > 500) badTz.clear();
    badTz.add(tz);
    return false;
  }
}
const isUtc = (tz) => typeof tz === "string" && /^(utc|etc\/utc|etc\/gmt|gmt|z|zulu|etc\/zulu|universal|etc\/universal)$/i.test(tz);

// Wanduhrzeit in einer Zone → Zeitpunkt (ms). zone: IANA-Name | "UTC" | { fixed: Minuten } | null (= Gerätezeit)
export function wallToMs(y, mo, d, h = 0, mi = 0, s = 0, zone = null) {
  if (!zone) return new Date(y, mo - 1, d, h, mi, s).getTime();
  if (typeof zone === "object") return Date.UTC(y, mo - 1, d, h, mi, s) - (Number(zone.fixed) || 0) * MIN;
  if (isUtc(zone)) return Date.UTC(y, mo - 1, d, h, mi, s);
  if (zone === deviceTz()) return new Date(y, mo - 1, d, h, mi, s).getTime();
  try {
    const f = tzFormat(zone);
    const want = Date.UTC(y, mo - 1, d, h, mi, s);
    let t = want;
    for (let i = 0; i < 3; i++) {
      const p = {};
      for (const x of f.formatToParts(new Date(t))) if (x.type !== "literal") p[x.type] = +x.value;
      const shown = Date.UTC(p.year, p.month - 1, p.day, p.hour % 24, p.minute, p.second);
      if (shown === want) break;
      t += want - shown;
    }
    return t;
  } catch (_) {
    return new Date(y, mo - 1, d, h, mi, s).getTime();
  }
}

// TZID → Zone (IANA, Windows, Outlook-Anzeigename, VTIMEZONE-Angaben, „UTC+1“); unbekannt → null (Gerätezeit)
const tzMemo = new Map();
export function resolveTz(tzid, vtzs = new Map()) {
  const t = str(tzid).trim().replace(/^"(.*)"$/, "$1");
  if (!t) return null;
  if (!vtzs.has(t)) {
    if (!tzMemo.has(t)) {
      if (tzMemo.size > 200) tzMemo.clear();
      tzMemo.set(t, resolveTzRaw(t, vtzs));
    }
    return tzMemo.get(t);
  }
  return resolveTzRaw(t, vtzs);
}
function resolveTzRaw(t, vtzs) {
  if (isUtc(t)) return "UTC";
  if (validTz(t) && t.includes("/")) return t;
  if (WINDOWS_LC[t.toLowerCase()]) return WINDOWS_LC[t.toLowerCase()];
  // /mozilla.org/20050126_1/Europe/Berlin · /citadel.org/20210210_1/Europe/Berlin
  const segs = t.split("/").filter(Boolean);
  for (let n = Math.min(3, segs.length); n >= 2; n--) {
    const cand = segs.slice(-n).join("/");
    if (validTz(cand)) return cand;
  }
  const v = vtzs.get(t);
  if (v?.lic && validTz(v.lic)) return v.lic;
  for (const [re, z] of TZ_WORDS) if (re.test(t)) return z;
  if (v && Number.isFinite(v.std) && Number.isFinite(v.dst) && TZ_OFFSETS[`${v.std}/${v.dst}`]) return TZ_OFFSETS[`${v.std}/${v.dst}`];
  const o = /(?:UTC|GMT)\s*([+-])\s*(\d{1,2})(?::?(\d{2}))?/i.exec(t);
  if (o) return { fixed: (o[1] === "-" ? -1 : 1) * (+o[2] * 60 + (+o[3] || 0)) };
  if (v && Number.isFinite(v.std)) return { fixed: v.std };
  if (validTz(t)) return t;
  return null;
}

// =====================================================================================================================
// ICS (Kalender-Abos)
// =====================================================================================================================
// Zeilen entfalten (Fortsetzungszeilen beginnen mit Leerzeichen oder Tab)
export function unfoldICS(text) {
  return str(text).replace(/\r\n?/g, "\n").replace(/\n[ \t]/g, "").split("\n");
}

// NAME;PARAM=WERT;PARAM="mit:doppelpunkt":WERT
export function parseLine(line) {
  let inQ = false;
  let colon = -1;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '"') inQ = !inQ;
    else if (c === ":" && !inQ) {
      colon = i;
      break;
    }
  }
  if (colon < 1) return null;
  const head = line.slice(0, colon);
  const parts = [];
  let cur = "";
  let q = false;
  for (const c of head) {
    if (c === '"') {
      q = !q;
      cur += c;
    } else if (c === ";" && !q) {
      parts.push(cur);
      cur = "";
    } else cur += c;
  }
  parts.push(cur);
  const name = parts.shift().trim().toUpperCase().replace(/^[A-Z0-9-]+\.(?=[A-Z])/, "");
  const params = {};
  for (const p of parts) {
    const e = p.indexOf("=");
    if (e > 0) params[p.slice(0, e).trim().toUpperCase()] = p.slice(e + 1).trim().replace(/^"(.*)"$/, "$1");
  }
  return { name, params, value: line.slice(colon + 1) };
}

// \\ \; \, \n → Zeichen
export const unescapeText = (v) => str(v).replace(/\\([\\;,nN])/g, (_, c) => (c === "n" || c === "N" ? "\n" : c));

// Datumswert: 20261006 · 20261006T090000 · 20261006T070000Z (TZID aus den Parametern)
function dtParts(v, params = {}, vtzs) {
  const m = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$/i.exec(str(v).trim());
  if (!m) return null;
  const y = +m[1], mo = +m[2], d = +m[3];
  if (mo < 1 || mo > 12 || d < 1 || d > 31 || new Date(Date.UTC(y, mo - 1, d)).getUTCDate() !== d) return null;
  if (!m[4] || params.VALUE === "DATE") return { date: true, y, mo, d };
  const h = +m[4], mi = +m[5], s = +(m[6] || 0);
  if (h > 24 || mi > 59 || s > 60) return null;
  return { date: false, y, mo, d, h, mi, s, zone: m[7] ? "UTC" : params.TZID ? resolveTz(params.TZID, vtzs) : null };
}
const isoOf = (p) => `${p.y}-${pad(p.mo)}-${pad(p.d)}`;
function partsMs(p, floatZone) {
  if (p.date) return atLocal(isoOf(p), 0).getTime();
  return wallToMs(p.y, p.mo, p.d, p.h, p.mi, p.s, p.zone ?? floatZone);
}

// P1W · P2D · PT1H30M · -PT15M → { days, ms }
export function parseDuration(v) {
  const m = /^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/i.exec(str(v).trim());
  if (!m || str(v).trim().toUpperCase() === "P" || /T$/i.test(str(v).trim())) return null;
  const sign = m[1] === "-" ? -1 : 1;
  const days = (+m[2] || 0) * 7 + (+m[3] || 0);
  const ms = ((+m[4] || 0) * 60 + (+m[5] || 0)) * MIN + (+m[6] || 0) * 1000;
  return { days: sign * days, ms: sign * ms, total: sign * (days * DAY + ms) };
}

// ---------- RRULE ----------
const WDN = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 };
export function parseRRule(v, vtzs) {
  const r = {};
  for (const part of str(v).split(";")) {
    const i = part.indexOf("=");
    if (i > 0) r[part.slice(0, i).trim().toUpperCase()] = part.slice(i + 1).trim();
  }
  const freq = str(r.FREQ).toUpperCase();
  if (!["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].includes(freq)) return null;
  const ints = (s, lo, hi) => str(s).split(",").map((x) => parseInt(x, 10)).filter((n) => Number.isInteger(n) && n !== 0 && Math.abs(n) >= lo && Math.abs(n) <= hi);
  const byday = r.BYDAY
    ? r.BYDAY.split(",")
        .map((x) => /^([+-]?\d{1,2})?(MO|TU|WE|TH|FR|SA|SU)$/i.exec(x.trim()))
        .filter(Boolean)
        .map((m) => ({ n: m[1] ? parseInt(m[1], 10) : 0, wd: WDN[m[2].toUpperCase()] }))
    : null;
  const count = parseInt(r.COUNT, 10);
  return {
    freq,
    interval: Math.max(1, Math.min(1000, parseInt(r.INTERVAL, 10) || 1)),
    count: Number.isInteger(count) && count > 0 ? count : null,
    until: r.UNTIL ? dtParts(r.UNTIL, {}, vtzs) : null,
    byday: byday && byday.length ? byday : null,
    bymonthday: r.BYMONTHDAY ? ints(r.BYMONTHDAY, 1, 31) : null,
    bymonth: r.BYMONTH ? ints(r.BYMONTH, 1, 12).filter((n) => n > 0) : null,
    bysetpos: r.BYSETPOS ? ints(r.BYSETPOS, 1, 366) : null,
    wkst: WDN[str(r.WKST).toUpperCase()] ?? 1,
  };
}

// Kalendertage als Tagesnummern (UTC-Mitternacht / Tag) – unabhängig von Sommerzeit
const dnum = (y, m, d) => Math.floor(Date.UTC(y, m - 1, d) / DAY);
const fromDnum = (n) => {
  const x = new Date(n * DAY);
  return { y: x.getUTCFullYear(), mo: x.getUTCMonth() + 1, d: x.getUTCDate() };
};
const wdOf = (n) => (((n + 4) % 7) + 7) % 7; // 1.1.1970 war ein Donnerstag
const dim = (y, m) => new Date(Date.UTC(y, m, 0)).getUTCDate();

// Alle Kalendertage einer Serie bis lastDay (inklusive DTSTART als erstem Termin); fromDay erlaubt das Vorspulen ohne COUNT
export function recurDays(start, rule, { fromDay = -Infinity, lastDay, max = 3000 } = {}) {
  const s = dnum(start.y, start.mo, start.d);
  const sWd = wdOf(s);
  const out = [];
  // UNTIL mit Uhrzeit (UTC) kann auf den Vortag fallen → einen Tag Luft, genau prüft parseICS über die Uhrzeit
  const untilDay = rule.until ? dnum(rule.until.y, rule.until.mo, rule.until.d) + (rule.until.date ? 0 : 1) : Infinity;
  const months = (y, m) => !rule.bymonth || rule.bymonth.includes(m);
  const inMonth = (y, m) => {
    const n = dim(y, m);
    let days = null;
    if (rule.bymonthday) days = rule.bymonthday.map((x) => (x > 0 ? x : n + x + 1)).filter((x) => x >= 1 && x <= n);
    if (rule.byday) {
      const hit = [];
      for (const b of rule.byday) {
        const all = [];
        for (let d = 1; d <= n; d++) if (wdOf(dnum(y, m, d)) === b.wd) all.push(d);
        if (!b.n) hit.push(...all);
        else {
          const pick = b.n > 0 ? all[b.n - 1] : all[all.length + b.n];
          if (pick) hit.push(pick);
        }
      }
      days = days ? days.filter((d) => hit.includes(d)) : hit;
    }
    if (!days) days = start.d <= n ? [start.d] : []; // 31. im Februar gibt es nicht → übersprungen
    return days.map((d) => dnum(y, m, d));
  };
  const inYear = (y) => {
    if (!rule.bymonth && rule.byday && rule.byday.some((b) => b.n) && !rule.bymonthday) {
      // BYDAY mit Ordnungszahl im ganzen Jahr (z. B. 20MO)
      const first = dnum(y, 1, 1), last = dnum(y, 12, 31);
      const hit = [];
      for (const b of rule.byday) {
        const all = [];
        for (let d = first; d <= last; d++) if (wdOf(d) === b.wd) all.push(d);
        if (!b.n) hit.push(...all);
        else {
          const pick = b.n > 0 ? all[b.n - 1] : all[all.length + b.n];
          if (pick !== undefined) hit.push(pick);
        }
      }
      return hit;
    }
    const ms = rule.bymonth || [start.mo];
    return ms.flatMap((m) => (rule.bymonthday || rule.byday ? inMonth(y, m) : start.d <= dim(y, m) ? [dnum(y, m, start.d)] : []));
  };
  const setpos = (list) => {
    if (!rule.bysetpos) return list;
    const out2 = [];
    for (const p of rule.bysetpos) {
      const v = p > 0 ? list[p - 1] : list[list.length + p];
      if (v !== undefined) out2.push(v);
    }
    return [...new Set(out2)].sort((a, b) => a - b);
  };
  const ws0 = s - ((sWd - rule.wkst + 7) % 7);
  const iv = rule.interval;
  // Vorspulen (nur ohne COUNT – dort zählt jeder Termin ab DTSTART)
  let i = 0;
  if (!rule.count && Number.isFinite(fromDay) && fromDay > s) {
    if (rule.freq === "DAILY") i = Math.max(0, Math.floor((fromDay - s) / iv) - 1);
    else if (rule.freq === "WEEKLY") i = Math.max(0, Math.floor((fromDay - ws0) / (7 * iv)) - 1);
    else if (rule.freq === "MONTHLY") {
      const f = fromDnum(fromDay);
      i = Math.max(0, Math.floor((f.y * 12 + f.mo - (start.y * 12 + start.mo)) / iv) - 1);
    } else {
      const f = fromDnum(fromDay);
      i = Math.max(0, Math.floor((f.y - start.y) / iv) - 1);
    }
  }
  let n = 0;
  if (s <= untilDay) {
    n = 1;
    if (s <= lastDay) out.push(s); // DTSTART ist immer der erste Termin
  }
  if (rule.count && n >= rule.count) return out;
  for (let guard = 0; guard < 20000 && out.length < max; guard++, i++) {
    let cand;
    let periodStart;
    if (rule.freq === "DAILY") {
      const d = s + i * iv;
      periodStart = d;
      const p = fromDnum(d);
      const ok = months(p.y, p.mo) && (!rule.bymonthday || rule.bymonthday.some((x) => (x > 0 ? x : dim(p.y, p.mo) + x + 1) === p.d)) && (!rule.byday || rule.byday.some((b) => b.wd === wdOf(d)));
      cand = ok ? [d] : [];
    } else if (rule.freq === "WEEKLY") {
      const ws = ws0 + i * 7 * iv;
      periodStart = ws;
      cand = (rule.byday ? rule.byday.map((b) => ws + ((b.wd - rule.wkst + 7) % 7)) : [ws + ((sWd - rule.wkst + 7) % 7)]).filter((d) => {
        const p = fromDnum(d);
        return months(p.y, p.mo);
      });
    } else if (rule.freq === "MONTHLY") {
      const mi = start.y * 12 + (start.mo - 1) + i * iv;
      const y = Math.floor(mi / 12), m = (mi % 12) + 1;
      periodStart = dnum(y, m, 1);
      cand = months(y, m) ? inMonth(y, m) : [];
    } else {
      const y = start.y + i * iv;
      periodStart = dnum(y, 1, 1);
      cand = inYear(y);
    }
    if (periodStart > lastDay || periodStart > untilDay) break;
    cand = setpos([...new Set(cand)].sort((a, b) => a - b));
    for (const d of cand) {
      if (d <= s) continue;
      if (d > untilDay) return out;
      n++;
      if (rule.count && n > rule.count) return out;
      if (d > lastDay) return out;
      out.push(d);
    }
  }
  return out;
}

// ---------- Komponenten lesen ----------
function readCalendar(text) {
  const lines = unfoldICS(text);
  const events = [];
  const vtzs = new Map();
  let calName = "";
  const stack = [];
  let ev = null;
  let tz = null;
  let sub = "";
  let seenCal = false;
  for (let li = 0; li < lines.length && li < 400000; li++) {
    const raw = lines[li];
    if (!raw || raw.length > 200000) continue;
    const L = parseLine(raw);
    if (!L) continue;
    if (L.name === "BEGIN") {
      const k = L.value.trim().toUpperCase();
      stack.push(k);
      if (k === "VCALENDAR") seenCal = true;
      if (k === "VEVENT" && !ev) ev = { props: new Map(), depth: stack.length };
      else if (k === "VTIMEZONE") tz = { id: "", lic: "", std: NaN, dst: NaN };
      else if (tz && (k === "STANDARD" || k === "DAYLIGHT")) sub = k;
      continue;
    }
    if (L.name === "END") {
      const k = L.value.trim().toUpperCase();
      // bis zur passenden Komponente zurück (kaputte Dateien: fehlende END-Zeilen)
      const at = stack.lastIndexOf(k);
      if (at >= 0) stack.length = at;
      if (k === "VEVENT" && ev && stack.length < ev.depth) {
        events.push(ev.props);
        ev = null;
        if (events.length > 20000) break;
      } else if (k === "VTIMEZONE" && tz) {
        if (tz.id) vtzs.set(tz.id, tz);
        tz = null;
      } else if (k === "STANDARD" || k === "DAYLIGHT") sub = "";
      continue;
    }
    const top = stack[stack.length - 1];
    if (ev && top === "VEVENT") {
      if (!ev.props.has(L.name)) ev.props.set(L.name, []);
      if (ev.props.get(L.name).length < 200) ev.props.get(L.name).push(L);
    } else if (tz && top === "VTIMEZONE") {
      if (L.name === "TZID") tz.id = L.value.trim();
      else if (L.name === "X-LIC-LOCATION") tz.lic = L.value.trim();
    } else if (tz && sub && L.name === "TZOFFSETTO") {
      const m = /^([+-])(\d{2})(\d{2})/.exec(L.value.trim());
      if (m) tz[sub === "STANDARD" ? "std" : "dst"] = (m[1] === "-" ? -1 : 1) * (+m[2] * 60 + +m[3]);
    } else if (top === "VCALENDAR" && L.name === "X-WR-CALNAME") calName = unescapeText(L.value);
  }
  return { events, vtzs, calName: clean(calName, 120), seenCal };
}

// Ist das überhaupt eine Kalender-Datei? → { ok, name, count }
export function icsInfo(text) {
  const s = str(text);
  if (!/BEGIN:VCALENDAR/i.test(s.slice(0, 4096))) return { ok: false, name: "", count: 0 };
  const cal = readCalendar(s);
  return { ok: cal.seenCal, name: cal.calName, count: cal.events.length };
}

// Gestern bis +30 Tage (wie Google/Microsoft)
export function feedRange(now = Date.now()) {
  const s = startOfDay(typeof now === "number" ? now : now.getTime());
  return { from: s - DAY, to: s + 31 * DAY };
}

// ICS-Text → normalisierte Termine { id: "i:<acc>:<uid>:<start>", account, provider: "ics", title, start, end, allDay, date, time,
// location, join, web, calendar, cancelled, notes } im Zeitraum [from, to); Serien (RRULE, RDATE, EXDATE, RECURRENCE-ID) aufgelöst
export function parseICS(text, { from, to, tz = null, account = "", calendar = "", max = 1500 } = {}) {
  const s = str(text);
  if (!s || !/BEGIN:VCALENDAR/i.test(s.slice(0, 4096))) return [];
  const range = feedRange();
  const A = Number.isFinite(from) ? from : range.from;
  const B = Number.isFinite(to) ? to : range.to;
  const floatZone = tz && tz !== deviceTz() ? tz : null; // „floating“: Wanduhrzeit des Geräts
  const cal = readCalendar(s.length > 6e6 ? s.slice(0, 6e6) : s);
  const calName = clean(calendar, 120) || cal.calName || "Kalender";
  const one = (P, k) => P.get(k)?.[0] || null;
  const textOf = (P, k) => (one(P, k) ? unescapeText(one(P, k).value) : "");
  const masters = new Map();
  const overrides = new Map(); // uid → Map(original-ms → props)
  for (const P of cal.events) {
    const uid = clean(one(P, "UID")?.value, 300) || "x" + fnv(`${one(P, "SUMMARY")?.value}|${one(P, "DTSTART")?.value}`);
    const rid = one(P, "RECURRENCE-ID");
    if (rid) {
      const p = dtParts(rid.value, rid.params, cal.vtzs);
      if (!p) continue;
      if (!overrides.has(uid)) overrides.set(uid, new Map());
      overrides.get(uid).set(partsMs(p, floatZone), P);
    } else if (!masters.has(uid)) masters.set(uid, P);
  }
  const out = [];
  const HARD = Math.max(max, 5000); // Schutz vor riesigen Abos – sortiert und gekürzt wird am Ende
  const lastDay = Math.floor((B + 2 * DAY) / DAY) + 1;

  const build = (P, uid, startMs, endMs, allDay) => {
    const location = clean(textOf(P, "LOCATION"), 300);
    const notes = cleanText(textOf(P, "DESCRIPTION"), 600);
    const urlRaw = clean(one(P, "URL")?.value, 2000);
    const conf = clean(one(P, "X-MICROSOFT-SKYPETEAMSMEETINGURL")?.value || one(P, "X-GOOGLE-CONFERENCE")?.value || one(P, "X-MICROSOFT-ONLINEMEETINGEXTERNALLINK")?.value, 2000);
    const join = connect.joinLink({ join: connect.httpsUrl(conf) ? conf : "", location, notes: `${urlRaw}\n${notes}` });
    const web = connect.httpsUrl(urlRaw);
    const d = new Date(startMs);
    const status = clean(one(P, "STATUS")?.value, 40).toUpperCase();
    const transp = clean(one(P, "X-MICROSOFT-CDO-BUSYSTATUS")?.value, 40).toUpperCase();
    return {
      id: `i:${account}:${uid}:${startMs}`,
      account,
      provider: "ics",
      title: clean(textOf(P, "SUMMARY"), 300) || "(Ohne Titel)",
      start: startMs,
      end: endMs,
      allDay,
      date: toISO(d),
      time: allDay ? null : hhmm(d),
      location,
      join: join || null,
      web: web && web !== join ? web : "",
      calendar: calName,
      cancelled: status === "CANCELLED" || transp === "CANCELLED" || /^(abgesagt|cancel+ed|canceled)\s*:/i.test(textOf(P, "SUMMARY")),
      notes,
    };
  };
  const span = (P, st) => {
    // Dauer: DTEND > DURATION > ganztägig 1 Tag / sonst 30 Min.
    const e = one(P, "DTEND") || one(P, "DUE");
    const ep = e ? dtParts(e.value, e.params, cal.vtzs) : null;
    const du = parseDuration(one(P, "DURATION")?.value);
    if (st.date) {
      let days = 1;
      if (ep) days = Math.max(1, dnum(ep.y, ep.mo, ep.d) - dnum(st.y, st.mo, st.d));
      else if (du) days = Math.max(1, du.days + Math.round(du.ms / DAY));
      return { days, ms: 0 };
    }
    const s0 = partsMs(st, floatZone);
    let ms = ep ? partsMs(ep.date ? { ...ep, date: false, h: 0, mi: 0, s: 0, zone: st.zone } : ep, floatZone) - s0 : du ? du.total : NaN;
    if (!Number.isFinite(ms) || ms < 0) ms = 30 * MIN;
    if (ms === 0) ms = ep || du ? 0 : 30 * MIN;
    return { days: 0, ms: Math.min(ms, 400 * DAY) };
  };
  const inRange = (sm, em) => sm < B && (em > A || (em === sm && sm >= A));
  const push = (ev) => {
    if (inRange(ev.start, ev.end)) out.push(ev);
  };
  const instance = (P, uid, st, dayN, len) => {
    const p = fromDnum(dayN);
    const parts = st.date ? { date: true, ...p } : { ...st, ...p };
    const startMs = partsMs(parts, floatZone);
    const endMs = st.date ? atLocal(addDays(isoOf(parts), len.days), 0).getTime() : startMs + len.ms;
    return { startMs, endMs, iso: isoOf(parts) };
  };

  for (const [uid, P] of masters) {
    if (out.length >= HARD) break;
    const ds = one(P, "DTSTART");
    const st = ds ? dtParts(ds.value, ds.params, cal.vtzs) : null;
    if (!st) continue;
    const len = span(P, st);
    const ov = overrides.get(uid);
    const rr = one(P, "RRULE") ? parseRRule(one(P, "RRULE").value, cal.vtzs) : null;
    const exMs = new Set();
    const exDay = new Set();
    for (const L of P.get("EXDATE") || [])
      for (const v of L.value.split(",")) {
        const p = dtParts(v, L.params, cal.vtzs);
        if (!p) continue;
        if (p.date) exDay.add(isoOf(p));
        else exMs.add(partsMs(p.zone || !st.zone ? p : { ...p, zone: st.zone }, floatZone));
      }
    let days = [dnum(st.y, st.mo, st.d)];
    // mehrtägige Termine dürfen vor dem Bereich beginnen
    const firstDay = Math.floor((A - (st.date ? len.days * DAY : len.ms)) / DAY) - 2;
    if (rr) {
      // UNTIL mit Uhrzeit (meist UTC): als Zeitpunkt vergleichen
      const untilMs = rr.until && !rr.until.date ? partsMs(rr.until, floatZone) : null;
      days = recurDays(st, rr, { fromDay: firstDay, lastDay, max: 2000 });
      if (untilMs !== null) days = days.filter((d) => instance(P, uid, st, d, len).startMs <= untilMs);
    }
    const seen = new Set();
    const emit = (dayN, extra = null) => {
      const it = extra || instance(P, uid, st, dayN, len);
      if (seen.has(it.startMs)) return;
      seen.add(it.startMs);
      if (exMs.has(it.startMs) || exDay.has(it.iso)) return;
      if (ov && ov.has(it.startMs)) return; // Ausnahme ersetzt diesen Termin
      if (inRange(it.startMs, it.endMs) && out.length < HARD) out.push(build(P, uid, it.startMs, it.endMs, st.date));
    };
    for (const d of days) emit(d);
    // RDATE: zusätzliche Termine
    for (const L of P.get("RDATE") || [])
      for (const v of L.value.split(",")) {
        const p = dtParts(v.split("/")[0], L.params, cal.vtzs);
        if (!p) continue;
        if (st.date || p.date) emit(dnum(p.y, p.mo, p.d));
        else {
          const sm = partsMs(p.zone || !st.zone ? p : { ...p, zone: st.zone }, floatZone);
          emit(0, { startMs: sm, endMs: sm + len.ms, iso: isoOf(p) });
        }
      }
  }
  // Ausnahmen (RECURRENCE-ID): eigene Zeit, eigener Titel – oder abgesagt
  for (const [uid, map] of overrides) {
    for (const P of map.values()) {
      if (out.length >= HARD) break;
      const ds = one(P, "DTSTART");
      const st = ds ? dtParts(ds.value, ds.params, cal.vtzs) : null;
      if (!st) continue;
      const len = span(P, st);
      const sm = partsMs(st, floatZone);
      const em = st.date ? atLocal(addDays(isoOf(st), len.days), 0).getTime() : sm + len.ms;
      push(build(P, uid, sm, em, st.date));
    }
  }
  return out.sort((a, b) => a.start - b.start || a.title.localeCompare(b.title)).slice(0, max);
}

// ---------- Kalender-Links (über den Server laden – fremde Server erlauben kein CORS) ----------
// webcal://… → https://…; ohne Schema → https://; nur http(s)
export function feedUrl(input) {
  let s = str(input).trim().replace(/^<|>$/g, "");
  if (!s) return "";
  s = s.replace(/^webcals?:\/\//i, "https://").replace(/^feed:\/\//i, "https://");
  if (!/^[a-z][a-z0-9+.-]*:/i.test(s)) s = "https://" + s.replace(/^\/+/, "");
  try {
    const u = new URL(s);
    if (u.protocol !== "https:" && u.protocol !== "http:") return "";
    if (!u.hostname || (!u.hostname.includes(".") && u.hostname !== "localhost")) return "";
    return u.href;
  } catch (_) {
    return "";
  }
}
const hostOf = (u) => {
  try {
    return new URL(u).hostname.replace(/^www\./, "");
  } catch (_) {
    return "";
  }
};

function srvError(r, what) {
  const msg = clean(r.data?.msg || r.data?.error || "", 300);
  let e;
  if (r.status === 404 && !msg) e = new Error(`Dein Arbeitstaschen-Server kennt ${what} noch nicht – bitte aktualisieren (taschen-update).`);
  else if (r.status === 404 && /unbekannte anfrage/i.test(msg)) e = new Error(`Dein Arbeitstaschen-Server kennt ${what} noch nicht – bitte aktualisieren (taschen-update).`);
  else if (r.status === 429) {
    e = new Error(msg || "Der Server bremst gerade – gleich geht’s weiter.");
    e.network = true;
  } else if (r.status === 502 || r.status === 504) {
    e = new Error(msg || "Der Anbieter ist gerade nicht erreichbar – ich zeige die zuletzt geladenen Daten.");
    e.network = true;
  } else e = new Error(msg || `Serverfehler (${r.status}).`);
  e.status = r.status;
  return e;
}
const needServer = (what) => new Error(`Für ${what} braucht es den Arbeitstaschen-Server – trag ihn in den Einstellungen unter „Sync“ ein.`);

export async function fetchFeed(server, url) {
  const base = normServer(server);
  if (!base) throw needServer("Kalender-Links");
  const u = feedUrl(url);
  if (!u) throw new Error("Das ist kein gültiger Kalender-Link – er beginnt mit https:// oder webcal://.");
  const r = await request(base, "/api/feeds/fetch", { method: "POST", json: { url: u }, timeout: 30000 });
  if (r.ok && r.data?.ok !== false && typeof r.data?.ics === "string") return { ics: r.data.ics, fetched: Number(r.data.fetched) || Date.now() };
  throw srvError(r, "Kalender-Links");
}

// „Testen“ im Sheet: Termine zählen, Name vorschlagen, nächsten Termin nennen
export async function testFeed(server, url, now = Date.now()) {
  const { ics } = await fetchFeed(server, url);
  const info = icsInfo(ics);
  if (!info.ok) throw new Error("Unter diesem Link liegt kein Kalender (keine ICS-Datei).");
  const r = feedRange(now);
  const list = parseICS(ics, { ...r, account: "test" }).filter((e) => !e.cancelled);
  const next = list.find((e) => e.end > now) || null;
  return { name: info.name, total: info.count, count: list.length, next };
}

export async function loadFeed(a, { from, to } = {}) {
  if (!a?.secret) throw new Error("Der Kalender-Link fehlt – bitte neu eintragen.");
  const { ics } = await fetchFeed(connect.serverFor(a), a.secret);
  if (!icsInfo(ics).ok) throw new Error(`„${connect.accountName(a)}“: Unter dem Link liegt kein Kalender mehr.`);
  return parseICS(ics, { from, to, account: a.id, calendar: a.name || a.label || hostOf(a.secret) });
}

export function addFeed(store, { name = "", url = "", color = null, server = "" } = {}) {
  const u = feedUrl(url);
  if (!u) throw new Error("Bitte einen gültigen Kalender-Link eintragen (https:// oder webcal://).");
  if (store.accounts().some((a) => a.provider === "ics" && a.secret === u)) throw new Error("Diesen Kalender hast du schon verbunden.");
  const host = hostOf(u);
  const nm = clean(name, 80) || host || "Kalender";
  return store.addAccount({ provider: "ics", name: nm, label: nm, host, secret: u, color, server: normServer(server) || "", calendars: true, mail: false });
}

export function removeFeed(store, id) {
  const a = store.account(id);
  if (!a || a.provider !== "ics") return false;
  store.removeAccount(id);
  connect.forgetAccount(id);
  return true;
}

// Bekannte öffentliche Kalender (Feiertage)
export const PUBLIC_FEEDS = [{ id: "de-feiertage", name: "Feiertage Deutschland", url: "https://calendar.google.com/calendar/ical/de.german%23holiday%40group.v.calendar.google.com/public/basic.ics", color: "green" }];

// =====================================================================================================================
// E-Mail per IMAP (markierte Mails)
// =====================================================================================================================
export const MAIL_PROVIDERS = [
  { id: "gmx", name: "GMX", short: "GMX", color: "#1C449B", fg: "#fff", host: "imap.gmx.net", port: 993, web: "https://www.gmx.net/", domains: ["gmx.de", "gmx.net", "gmx.at", "gmx.ch", "gmx.com"], flag: "Fahne „Wichtig“", hint: "Einmal in GMX erlauben: E-Mail → Einstellungen → POP3/IMAP Abruf → „E-Mails per POP3 und IMAP senden und empfangen“ einschalten. Dann hier deine GMX-Adresse und dein normales Passwort." },
  { id: "webde", name: "WEB.DE", short: "WEB", color: "#FFD800", fg: "#1d1d1f", host: "imap.web.de", port: 993, web: "https://web.de/", domains: ["web.de"], flag: "Fahne „Wichtig“", hint: "Einmal in WEB.DE erlauben: E-Mail → Einstellungen → POP3/IMAP Abruf → „E-Mails per POP3 und IMAP senden und empfangen“ einschalten. Dann deine WEB.DE-Adresse und dein normales Passwort." },
  { id: "tonline", name: "T-Online", short: "T", color: "#E20074", fg: "#fff", host: "secureimap.t-online.de", port: 993, web: "https://email.t-online.de/", domains: ["t-online.de", "magenta.de"], flag: "Markierung (Fahne)", hint: "Du brauchst das E-Mail-Passwort – nicht das Passwort fürs Telekom-Login. Anlegen: Telekom Kundencenter → E-Mail → E-Mail-Passwort." },
  { id: "icloud", name: "iCloud", short: "iC", color: "#3693F3", fg: "#fff", host: "imap.mail.me.com", port: 993, web: "https://www.icloud.com/mail", domains: ["icloud.com", "me.com", "mac.com"], flag: "Fahne", hint: "Apple verlangt ein app-spezifisches Passwort: account.apple.com → Anmeldung und Sicherheit → App-spezifische Passwörter → „+“. Als Anmeldename deine @icloud.com-Adresse." },
  { id: "yahoo", name: "Yahoo", short: "Y!", color: "#6001D2", fg: "#fff", host: "imap.mail.yahoo.com", port: 993, web: "https://mail.yahoo.com/", domains: ["yahoo.com", "yahoo.de", "ymail.com", "rocketmail.com"], flag: "Stern", hint: "Yahoo verlangt ein App-Passwort: Kontoinfo → Kontosicherheit → „App-Passwort generieren“." },
  { id: "ionos", name: "IONOS", short: "IO", color: "#003D8F", fg: "#fff", host: "imap.ionos.de", port: 993, web: "https://mail.ionos.de/", domains: [], flag: "Markierung", hint: "Die E-Mail-Adresse und das Passwort deines IONOS-Postfachs." },
  { id: "strato", name: "Strato", short: "ST", color: "#F28C00", fg: "#fff", host: "imap.strato.de", port: 993, web: "https://webmail.strato.de/", domains: [], flag: "Markierung", hint: "Die E-Mail-Adresse und das Passwort deines Strato-Postfachs." },
  { id: "freenet", name: "freenet", short: "fn", color: "#3E9A34", fg: "#fff", host: "mx.freenet.de", port: 993, web: "https://webmail.freenet.de/", domains: ["freenet.de"], flag: "Markierung", hint: "IMAP einmal freischalten: freenet Mail → Einstellungen → POP3/IMAP → aktivieren. Dann Adresse und Passwort." },
  { id: "other", name: "Anderer Anbieter", short: "@", color: "#8E8E93", fg: "#fff", host: "", port: 993, web: "", domains: [], flag: "Markierung", hint: "Server und Port stehen in der Hilfe deines Anbieters (IMAP, meist Port 993 mit SSL/TLS). Manche Anbieter verlangen ein eigenes App-Passwort." },
];
export const mailProvider = (id) => MAIL_PROVIDERS.find((p) => p.id === id) || null;
export function guessMailProvider(email) {
  const dom = str(email).toLowerCase().split("@")[1] || "";
  return MAIL_PROVIDERS.find((p) => p.domains.includes(dom)) || null;
}
// Plakette für ein IMAP-Konto (Kürzel + Farbe)
export function mailStyle(a) {
  const p = mailProvider(a?.kind) || MAIL_PROVIDERS.find((x) => x.host && x.host === a?.host) || MAIL_PROVIDERS.find((x) => x.name.toLowerCase() === str(a?.label).toLowerCase()) || guessMailProvider(a?.email) || mailProvider("other");
  return { id: p.id, short: p.short, color: p.color, fg: p.fg, name: p.id === "other" ? clean(a?.label, 40) || hostOf("https://" + str(a?.host)) || "E-Mail" : p.name, flag: p.flag };
}

const HOST_RE = /^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/i;
export async function imapConnect({ server, provider = "other", email = "", password = "", host = "", port = 993, label = "" } = {}) {
  const base = normServer(server);
  if (!base) throw needServer("E-Mail per IMAP");
  const user = str(email).trim();
  if (!user) throw new Error("Bitte deine E-Mail-Adresse (bzw. den Anmeldenamen) eintragen.");
  if (!str(password)) throw new Error("Bitte das Passwort eintragen.");
  const h = str(host).trim().toLowerCase();
  if (!HOST_RE.test(h)) throw new Error("Bitte den IMAP-Server eintragen, z. B. imap.example.de.");
  const pt = Math.round(Number(port) || 993);
  if (pt < 1 || pt > 65535) throw new Error("Der Port muss eine Zahl sein (meist 993).");
  const p = mailProvider(provider);
  const lb = clean(label, 40) || (p && p.id !== "other" ? p.name : hostOf("https://" + h));
  const r = await request(base, "/api/imap/add", { method: "POST", json: { host: h, port: pt, user, password: str(password), label: lb }, timeout: 45000 });
  if (!r.ok || r.data?.ok === false) throw srvError(r, "E-Mail per IMAP");
  const account = str(r.data?.account).toLowerCase();
  const secret = str(r.data?.secret);
  if (!/^[0-9a-f]{32}$/.test(account) || !/^[A-Za-z0-9_-]{16,200}$/.test(secret)) throw new Error("Die Antwort des Servers war unvollständig – bitte noch einmal versuchen.");
  return { account, secret, email: clean(r.data?.email, 254) || user, label: lb, host: h, port: pt, server: base, kind: p?.id || "other", webmail: p?.web || "" };
}

export function addImapAccount(store, res) {
  // dasselbe Postfach schon da? → ersetzen (Farbe bleibt)
  const same = store.accounts().filter((a) => a.provider === "imap" && a.id !== res.account && str(a.email).toLowerCase() === str(res.email).toLowerCase() && a.host === res.host);
  const keep = same[0] ? { color: same[0].color } : {};
  for (const a of same) {
    store.removeAccount(a.id);
    connect.forgetAccount(a.id);
  }
  return store.addAccount({ ...keep, id: res.account, provider: "imap", email: res.email, label: res.label, host: res.host, port: res.port, kind: res.kind, secret: res.secret, server: res.server, webmail: webUrl(res.webmail), mail: true, calendars: false });
}

export function normImapMail(m, a) {
  if (!m || typeof m !== "object") return null;
  const uid = str(m.uid).trim();
  if (!/^\d{1,12}$/.test(uid)) return null;
  const f = connect.parseFrom(str(m.fromEmail) && str(m.from) && !str(m.from).includes("@") ? `"${str(m.from)}" <${str(m.fromEmail)}>` : str(m.from) || str(m.fromEmail));
  const fromEmail = clean(m.fromEmail, 254).toLowerCase() || f.address;
  return {
    id: `x:${a.id}:${uid}`,
    account: a.id,
    provider: "imap",
    from: clean(connect.decodeHeader(f.name || m.from), 120) || fromEmail || "Unbekannt",
    fromEmail: /^[^\s@<>"]+@[^\s@<>"]+$/.test(fromEmail) ? fromEmail : "",
    subject: clean(connect.decodeHeader(m.subject), 300) || "(Kein Betreff)",
    snippet: clean(m.snippet, 300),
    date: Number(m.date) || Date.parse(m.date) || 0,
    web: webUrl(a.webmail) || "",
  };
}

function expired(msg) {
  const e = new Error(msg);
  e.expired = true;
  return e;
}

export async function loadImap(a, { limit = 25 } = {}) {
  if (!a?.secret) throw expired(`Für ${connect.accountName(a)} fehlt der Zugang (z. B. nach einem Backup) – bitte neu verbinden.`);
  const base = connect.serverFor(a);
  if (!base) throw needServer("E-Mail per IMAP");
  const r = await request(base, "/api/imap/flagged", { method: "POST", json: { account: a.id, secret: a.secret, limit }, timeout: 40000 });
  if (r.ok && Array.isArray(r.data?.mails)) {
    if (a.broken) safe(() => connect.storeRef()?.updateAccount(a.id, { broken: false }));
    return r.data.mails.map((m) => normImapMail(m, a)).filter(Boolean);
  }
  // 401: Anmeldung beim Anbieter klappt nicht mehr (Passwort geändert) · 403/410: Schlüssel falsch bzw. Zugang gelöscht
  if (r.status === 401 || r.status === 403 || r.status === 404 || r.status === 410) {
    if (!a.broken) safe(() => connect.storeRef()?.updateAccount(a.id, { broken: true }));
    throw expired(clean(r.data?.msg, 240) || `Der Zugang zu ${connect.accountName(a)} gilt nicht mehr – bitte neu verbinden.`);
  }
  throw srvError(r, "E-Mail per IMAP");
}

export async function removeImap(store, id) {
  const a = store.account(id);
  if (!a || a.provider !== "imap") return { ok: false, remote: false };
  let remote = false;
  const base = connect.serverFor(a);
  if (a.secret && base)
    remote = await request(base, "/api/imap/remove", { method: "POST", json: { account: a.id, secret: a.secret }, timeout: 15000 })
      .then((r) => r.ok || r.status === 404 || r.status === 410 || r.status === 403)
      .catch(() => false);
  store.removeAccount(id);
  connect.forgetAccount(id);
  return { ok: true, remote };
}

function safe(fn) {
  try {
    return fn();
  } catch (_) {
    return undefined;
  }
}

// Was bietet der Server an? (Google/Microsoft wie bisher, dazu Kalender-Links, IMAP, Eingangs-Briefkasten)
export async function availability(server) {
  const base = normServer(server);
  const none = { google: false, microsoft: false, feeds: false, imap: false, inbox: false, server: "", ok: false };
  if (!base) return none;
  const chk = await checkServer(base);
  if (!chk.ok) return none;
  return { google: !!chk.connect?.google, microsoft: !!chk.connect?.microsoft, feeds: !!chk.feeds, imap: !!chk.imap, inbox: !!chk.inbox, server: base, ok: true };
}

// =====================================================================================================================
// Webhooks: Eingang (Siri, Zapier, Make, n8n, IFTTT, Formulare …) und Ausgang (bei neu/erledigt)
// =====================================================================================================================
export function hookUrl(a) {
  const base = connect.serverFor(a);
  const hook = str(a?.hook || a?.id);
  return base && /^[0-9a-f]{32}$/.test(hook) && a?.secret ? `${base}/api/in/${hook}/${a.secret}` : "";
}
export const inboxAccount = (store) => (safe(() => store.accounts()) || []).find((a) => a.provider === "hook-in") || null;
export const outHooks = (store) => (safe(() => store.accounts()) || []).filter((a) => a.provider === "hook-out");

export async function hookCreate(store, server) {
  const base = normServer(server);
  if (!base) throw needServer("den Eingangs-Briefkasten");
  const ex = inboxAccount(store);
  if (ex) return ex;
  const r = await request(base, "/api/inbox/create", { method: "POST", json: {}, timeout: 15000 });
  if (!r.ok || r.data?.ok === false) throw srvError(r, "den Eingangs-Briefkasten");
  const hook = str(r.data?.hook).toLowerCase();
  const key = str(r.data?.key);
  if (!/^[0-9a-f]{32}$/.test(hook) || !/^[A-Za-z0-9_-]{16,200}$/.test(key)) throw new Error("Die Antwort des Servers war unvollständig – bitte noch einmal versuchen.");
  return store.addAccount({ id: hook, provider: "hook-in", hook, secret: key, server: base, name: "Eingangs-Briefkasten", calendars: false, mail: false });
}

async function hookCall(a, path, json = {}) {
  const base = connect.serverFor(a);
  if (!base) throw needServer("den Eingangs-Briefkasten");
  if (!a?.secret) throw expired("Der Schlüssel des Briefkastens fehlt (z. B. nach einem Backup) – bitte die Adresse neu erstellen.");
  const r = await request(base, path, { method: "POST", json: { hook: a.hook || a.id, key: a.secret, ...json }, timeout: 20000 });
  if (r.ok && r.data?.ok !== false) return r.data || {};
  if (r.status === 403 || r.status === 404 || r.status === 410) {
    const e = expired(clean(r.data?.msg, 240) || "Diese Briefkasten-Adresse gilt nicht mehr – bitte neu erstellen.");
    e.status = r.status;
    throw e;
  }
  throw srvError(r, "den Eingangs-Briefkasten");
}

export async function hookPull(a) {
  const d = await hookCall(a, "/api/inbox/pull");
  return (Array.isArray(d.items) ? d.items : []).filter((x) => x && typeof x === "object" && /^[\w-]{1,80}$/.test(str(x.id)));
}
export const hookAck = (a, ids) => hookCall(a, "/api/inbox/ack", { ids: ids.slice(0, 500) });
export async function hookReset(store, a) {
  const d = await hookCall(a, "/api/inbox/reset");
  const key = str(d.key);
  if (!/^[A-Za-z0-9_-]{16,200}$/.test(key)) throw new Error("Die Antwort des Servers war unvollständig.");
  store.updateAccount(a.id, { secret: key, broken: false });
  return store.account(a.id);
}
export async function hookRemove(store, a) {
  const remote = await hookCall(a, "/api/inbox/remove")
    .then(() => true)
    .catch(() => false);
  store.removeAccount(a.id);
  return { ok: true, remote };
}

// Herkunft aus „source“ (Server: Angabe des Absenders oder User-Agent) → „Siri“, „Zapier“ …
const VIA = [
  [/siri|shortcut|kurzbefehl|workflowkit|cfnetwork|darwin/i, "Siri"],
  [/zapier/i, "Zapier"],
  [/integromat|make\.com|^make\b|\bmake\//i, "Make"],
  [/n8n/i, "n8n"],
  [/ifttt/i, "IFTTT"],
  [/pipedream/i, "Pipedream"],
  [/power ?automate|logic ?apps|azure|microsoft[ -]?flow/i, "Power Automate"],
  [/apps ?script|google/i, "Google"],
  [/typeform|tally|jotform|formular|\bforms?\b/i, "Formular"],
  [/^test$|arbeitstaschen/i, "Test"],
  [/lesezeichen|bookmark/i, "Lesezeichen"],
  [/mozilla|safari|chrome|firefox|browser/i, "Browser"],
  [/curl|wget|httpie|python|node-fetch|axios|postman/i, "Skript"],
];
export function viaLabel(source) {
  const s = clean(source, 300);
  if (!s) return "Webhook";
  for (const [re, l] of VIA) if (re.test(s)) return l;
  return /^[\p{L}\d .&+-]{2,24}$/u.test(s) ? s : "Webhook";
}

// Priorität aus Text/Zahl: „hoch“, „!!!“, „p1“, 3 → 3 … (Todoist: 1 = höchste)
export function parsePrio(v, { todoist = false } = {}) {
  const s = str(v).trim().toLowerCase();
  if (!s) return 0;
  if (/^\d$/.test(s)) {
    const n = +s;
    if (todoist) return n >= 1 && n <= 4 ? 4 - n : 0;
    return Math.max(0, Math.min(3, n));
  }
  if (/^(p1|!!!|hoch|high|sehr hoch|dringend|urgent|kritisch|critical|wichtig|important)$/.test(s)) return 3;
  if (/^(p2|!!|mittel|medium|normal|mid)$/.test(s)) return 2;
  if (/^(p3|!|niedrig|low|gering|klein)$/.test(s)) return 1;
  if (/^(p4|keine|none|-)$/.test(s)) return 0;
  return 0;
}

// Datum aus fremden Daten: ISO, 06.10.2026, 6.10., 10/06/2026, Excel-Seriennummer, „morgen“, „Freitag“ … → { due, time }
export function parseDateText(v, { now = new Date(), profile } = {}) {
  const s = str(v).trim();
  if (!s) return { due: null, time: null };
  let m = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?$/.exec(s);
  if (m) {
    if (!m[4]) return isISO(`${m[1]}-${m[2]}-${m[3]}`) ? { due: `${m[1]}-${m[2]}-${m[3]}`, time: null } : { due: null, time: null };
    if (!m[7] && m[4] === "00" && m[5] === "00") return { due: `${m[1]}-${m[2]}-${m[3]}`, time: null };
    const ms = m[7] ? Date.parse(s.replace(" ", "T")) : new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]).getTime();
    if (!Number.isFinite(ms)) return { due: null, time: null };
    const d = new Date(ms);
    return { due: toISO(d), time: m[7] && d.getHours() === 0 && d.getMinutes() === 0 ? null : hhmm(d) };
  }
  m = /^(\d{1,2})\.(\d{1,2})\.(\d{2}|\d{4})?(?:,?\s+(\d{1,2})[:.](\d{2})(?:\s*Uhr)?)?$/.exec(s);
  if (m) {
    const d = +m[1], mo = +m[2];
    let y = m[3] ? +m[3] : now.getFullYear();
    if (y < 100) y += 2000;
    const iso = `${y}-${pad(mo)}-${pad(d)}`;
    if (!isISO(iso)) return { due: null, time: null };
    const t = m[4] ? parseTime(`${m[4]}:${m[5]}`) : null;
    // ohne Jahr und schon vorbei → nächstes Jahr
    const due = !m[3] && isISO(iso) && iso < addDays(toISO(now), -30) ? `${y + 1}-${pad(mo)}-${pad(d)}` : iso;
    return { due: isISO(due) ? due : iso, time: t === null ? null : toTime(t) };
  }
  m = /^(\d{1,2})\/(\d{1,2})\/(\d{2}|\d{4})(?:,?\s+(\d{1,2}):(\d{2})\s*(am|pm)?)?$/i.exec(s);
  if (m) {
    let a = +m[1], b = +m[2];
    const mo = a > 12 ? b : a, d = a > 12 ? a : b; // US: Monat/Tag
    let y = +m[3];
    if (y < 100) y += 2000;
    const iso = `${y}-${pad(mo)}-${pad(d)}`;
    let t = null;
    if (m[4]) {
      let h = +m[4];
      if (m[6]) h = (h % 12) + (/pm/i.test(m[6]) ? 12 : 0);
      t = parseTime(`${h}:${m[5]}`);
    }
    return isISO(iso) ? { due: iso, time: t === null ? null : toTime(t) } : { due: null, time: null };
  }
  if (/^\d{5}(?:[.,]\d+)?$/.test(s)) {
    const n = parseFloat(s.replace(",", "."));
    if (n > 30000 && n < 80000) {
      const base = Date.UTC(1899, 11, 30) + Math.floor(n) * DAY;
      const x = new Date(base);
      const iso = `${x.getUTCFullYear()}-${pad(x.getUTCMonth() + 1)}-${pad(x.getUTCDate())}`;
      const frac = n - Math.floor(n);
      return { due: iso, time: frac > 0 ? toTime(Math.round(frac * 1440) % 1440) : null };
    }
  }
  const pq = parseQuick(s, { now, profile });
  if (pq && pq.due) return { due: pq.due, time: pq.time || null };
  const t = parseTime(s.replace(/\s*uhr$/i, "").replace(".", ":"));
  return { due: null, time: t === null ? null : toTime(t) };
}

// Bag-Name → id (genau, sonst wie #Tasche in der Schnellerfassung)
function bagByName(name, bags) {
  const n = normName(name);
  if (!n) return null;
  const exact = bags.find((b) => b && !b.deleted && normName(b.name) === n);
  if (exact) return exact;
  return matchBag(name, bags);
}

// Ein Eintrag aus dem Briefkasten → Daten für store.addTask (null = unbrauchbar)
export function itemToTask(item, { bags = [], now = new Date(), profile } = {}) {
  if (!item || typeof item !== "object") return null;
  const raw = clean(item.title, 300);
  if (!raw) return null;
  // Titel wie in der Schnellerfassung auswerten: „Steuerberater anrufen morgen 10 Uhr #Büro !!“
  const pq = parseQuick(raw, { bags, now, profile });
  const title = clean(pq?.title, 300) || raw;
  const due0 = parseDateText(item.due, { now, profile });
  const t0 = parseTime(str(item.time).trim().replace(/\s*uhr$/i, "").replace(/^(\d{1,2})$/, "$1:00").replace(".", ":"));
  const bag = item.bag ? bagByName(clean(item.bag, 80), bags) : null;
  const tags = [...(pq?.tags || [])];
  if (connect.isCall(raw) && !tags.includes("anruf")) tags.push("anruf");
  const url = webUrl(item.url);
  const notes = [cleanText(item.notes, 4000), pq?.notes || "", url && !str(item.notes).includes(url) ? url : ""].filter(Boolean).join("\n\n");
  const due = due0.due || pq?.due || null;
  const time = t0 !== null ? toTime(t0) : due0.time || pq?.time || null;
  return {
    title,
    notes,
    due: time && !due ? toISO(now) : due,
    time,
    bag: bag ? bag.id : pq?.bag || null,
    prio: parsePrio(item.prio) || pq?.prio || 0,
    tags,
    remind: pq?.remind ?? null,
    repeat: pq?.repeat || null,
    est: pq?.est || null,
    someday: !!pq?.someday && !due,
    src: { kind: "hook", id: `h:${str(item.id)}`, via: viaLabel(item.source), at: Number(item.at) || Date.now() },
  };
}

// ---------- Abholen (Start, Sichtbarkeit max. alle 2 Min., Knopf) ----------
const PULL_EVERY = 2 * MIN;
let ST = null;
let pulling = null;
let lastPull = 0;
const hookState = new Map(); // Konto-id → { at, error, n }
export const inboxState = (id) => hookState.get(id) || null;
const listeners = new Set();
export function onInbox(fn) {
  if (typeof fn !== "function") return () => {};
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export function pullInbox(store = ST, { force = false } = {}) {
  if (!store) return Promise.resolve({ added: [], vias: [], errors: [] });
  if (pulling) return pulling;
  const accs = (safe(() => store.accounts()) || []).filter((a) => a.provider === "hook-in");
  if (!accs.length || (!force && Date.now() - lastPull < PULL_EVERY) || (!force && !online())) return Promise.resolve({ added: [], vias: [], errors: [], skipped: true });
  lastPull = Date.now();
  pulling = (async () => {
    const added = [];
    const errors = [];
    for (const a of accs) {
      let items;
      try {
        items = await hookPull(a);
      } catch (e) {
        errors.push(e);
        hookState.set(a.id, { at: Date.now(), error: e.message, expired: !!e.expired, n: 0 });
        continue;
      }
      const made = [];
      if (items.length) {
        const have = new Set((store.get()?.tasks || []).map((t) => t?.src?.id).filter(Boolean)); // schon übernommen (auch gelöscht, auch von anderem Gerät)
        const ctx = { bags: store.bags(), now: new Date(), profile: store.get()?.profile };
        try {
          store.batch("Neue Aufgaben (Briefkasten)", () => {
            for (const it of items) {
              const k = `h:${str(it.id)}`;
              if (have.has(k)) continue;
              const data = itemToTask(it, ctx);
              if (!data) continue;
              try {
                made.push(store.addTask(data));
                have.add(k);
              } catch (_) {
                /* ungültiger Eintrag – überspringen */
              }
            }
          });
        } catch (e) {
          errors.push(e);
          continue; // nichts quittieren – beim nächsten Mal noch einmal
        }
        // Erst sicher speichern, dann beim Server quittieren – sonst gingen Aufgaben verloren, wenn die App genau dazwischen beendet wird
        if (made.length) {
          try {
            await store.flush?.();
          } catch (e) {
            errors.push(e);
            continue; // nicht quittieren – beim nächsten Abholen kommen sie wieder (src.id verhindert Doppelte)
          }
        }
        try {
          await hookAck(a, items.map((x) => str(x.id)));
        } catch (e) {
          errors.push(e); // Doppelte verhindert src.id beim nächsten Abholen
        }
      }
      added.push(...made);
      hookState.set(a.id, { at: Date.now(), error: "", n: made.length });
    }
    const res = { added, vias: [...new Set(added.map((t) => t.src?.via).filter(Boolean))], errors };
    for (const fn of [...listeners]) safe(() => fn(res));
    return res;
  })().finally(() => (pulling = null));
  return pulling;
}

// „2 neue Aufgaben von Siri“ · „von Siri & Zapier“
export function inboxToast(res) {
  const n = res?.added?.length || 0;
  if (!n) return "";
  const v = (res.vias || []).filter((x) => x !== "Webhook");
  const from = v.length ? ` von ${v.length > 2 ? v.slice(0, 2).join(", ") + " …" : v.join(" & ")}` : "";
  return `${n === 1 ? "1 neue Aufgabe" : `${n} neue Aufgaben`}${from}`;
}

// ---------- Ausgang: bei „neu“ und „erledigt“ JSON an Zapier/Make/n8n schicken ----------
export function hookPayload(event, t, { bagsById = {} } = {}) {
  const bag = t?.bag ? bagsById[t.bag] : null;
  return {
    event,
    at: new Date().toISOString(),
    task: { id: str(t?.id), title: str(t?.title), notes: str(t?.notes), due: t?.due || null, time: t?.time || null, bag: bag ? bag.name : null, prio: Number(t?.prio) || 0, done: !!t?.done },
  };
}
// „no-cors“ + text/plain: kein Vorab-Check nötig, Antwort bleibt unlesbar – Fehler leise
export function sendHook(url, payload) {
  const u = webUrl(url);
  if (!u || !u.startsWith("https://") || typeof fetch !== "function") return Promise.resolve(false);
  return fetch(u, { method: "POST", mode: "no-cors", headers: { "Content-Type": "text/plain" }, body: JSON.stringify(payload), credentials: "omit", keepalive: true, cache: "no-store" })
    .then(() => true)
    .catch(() => false);
}
export function testHook(url, { title = "Test aus Arbeitstaschen" } = {}) {
  return sendHook(url, { event: "test", at: new Date().toISOString(), task: { id: "test", title, notes: "Wenn du das siehst, klappt die Verbindung.", due: toISO(new Date()), time: null, bag: null, prio: 0, done: false } });
}

let queue = new Map();
let qTimer = null;
const sentDone = new Set();
function flushHooks(store) {
  qTimer = null;
  const q = queue;
  queue = new Map();
  if (!online()) return;
  const hooks = outHooks(store).filter((a) => a.secret);
  if (!hooks.length) return;
  const bagsById = Object.fromEntries((safe(() => store.bags()) || []).map((b) => [b.id, b]));
  for (const { event, id } of q.values()) {
    const t = store.task(id);
    if (!t) continue;
    const payload = hookPayload(event, t, { bagsById });
    const kind = event === "task.added" ? "add" : "done";
    for (const h of hooks) if ((Array.isArray(h.on) ? h.on : ["add", "done"]).includes(kind)) sendHook(h.secret, payload);
  }
}
export function onStoreChange(store, ch) {
  if (!ch || !ch.local || ch.type !== "task" || !ch.id) return;
  if (!outHooks(store).length) return;
  const t = store.task(ch.id);
  if (!t) return;
  if (ch.action === "add") {
    if (t.src?.kind === "hook") return; // kein Ping-Pong: Briefkasten → Zapier → Briefkasten …
    queue.set(`a:${t.id}`, { event: "task.added", id: t.id });
  } else if (ch.action === "update" && t.done && Date.now() - t.done < 15000) {
    const k = `${t.id}:${t.done}`;
    if (sentDone.has(k)) return;
    sentDone.add(k);
    if (sentDone.size > 500) sentDone.clear();
    queue.set(`d:${t.id}`, { event: "task.done", id: t.id });
  } else return;
  clearTimeout(qTimer);
  qTimer = setTimeout(() => flushHooks(store), 1200);
  qTimer?.unref?.();
}
export function addOutHook(store, { url = "", name = "", on = ["add", "done"] } = {}) {
  const u = webUrl(url);
  if (!u || !u.startsWith("https://")) throw new Error("Bitte eine https://-Adresse eintragen (z. B. von Zapier „Catch Hook“).");
  const ev = ["add", "done"].filter((x) => on.includes(x));
  if (!ev.length) throw new Error("Wähle mindestens ein Ereignis.");
  return store.addAccount({ provider: "hook-out", name: clean(name, 60) || hostOf(u) || "Webhook", label: hostOf(u), host: hostOf(u), secret: u, on: ev, calendars: false, mail: false });
}

// =====================================================================================================================
// Nachrichten & Anrufe (Deep-Links – reine Funktionen)
// =====================================================================================================================
// Telefonnummer → nur Ziffern international (0171 … → 49171 …, 0049 … → 49 …, +43 … → 43 …)
export function intlDigits(phone, cc = "49") {
  const s = str(phone).replace(/\(0\)/g, "").trim();
  const d = s.replace(/\D/g, "");
  if (!d) return "";
  if (s.startsWith("+")) return d;
  if (d.startsWith("00")) return d.slice(2);
  if (d.startsWith("0")) return cc + d.slice(1);
  return d;
}
const plusNum = (p) => {
  const d = intlDigits(p);
  return d ? "+" + d : "";
};
// Mobilnummer? (Deutschland: 015x, 016x, 017x) – Festnetz bekommt kein WhatsApp/SMS/FaceTime
export function phoneKind(phone) {
  const d = intlDigits(phone);
  if (/^491[5-7]\d{7,10}$/.test(d)) return "mobil";
  if (/^49[2-9]/.test(d)) return "festnetz";
  if (/^43(6[5-9]|66)/.test(d) || /^417[5-9]/.test(d)) return "mobil";
  return "";
}
export const whatsappLink = (phone, text = "") => {
  const d = phone ? intlDigits(phone) : "";
  return `https://wa.me/${d}${text ? `?text=${enc(str(text).slice(0, 1500))}` : ""}`;
};
export const smsLink = (phone, body = "") => `sms:${plusNum(phone)}${body ? `&body=${enc(str(body).slice(0, 1000))}` : ""}`;
const EMAIL_RE = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;
export function facetimeLink(target, audio = false) {
  const t = str(target).trim();
  const who = EMAIL_RE.test(t) ? t.toLowerCase() : plusNum(t);
  return who ? `${audio ? "facetime-audio" : "facetime"}:${who}` : "";
}
const mailEnc = (e) => enc(str(e).trim().toLowerCase()).replace(/%40/g, "@");
export const teamsCallLink = (email) => (EMAIL_RE.test(str(email).trim()) ? `https://teams.microsoft.com/l/call/0/0?users=${mailEnc(email)}` : "");
export const teamsChatLink = (email, msg = "") => (EMAIL_RE.test(str(email).trim()) ? `https://teams.microsoft.com/l/chat/0/0?users=${mailEnc(email)}${msg ? `&message=${enc(str(msg).slice(0, 500))}` : ""}` : "");
export function mapsLinks(address) {
  const q = clean(address, 300);
  return { apple: `https://maps.apple.com/?q=${enc(q)}`, google: `https://www.google.com/maps/search/?api=1&query=${enc(q)}` };
}

// ---------- Adressen erkennen ----------
// „Königstraße 12, 70173 Stuttgart“ · „Am Markt 3, 01067 Dresden“ · „Berliner Str. 5“ · „70191 Stuttgart“
const L_ = "a-zäöüß";
const U_ = "A-ZÄÖÜ";
const WORD = `[${U_}][${L_}]+`;
const SUFFIX_LOW = "(?:straße|strasse|str\\.|weg|allee|platz|ring|gasse|damm|ufer|chaussee|steig|stieg|pfad|markt|graben|kai|promenade|zeile|wall|anger|feld|hof|berg|bogen|park|brücke|tor)";
const SUFFIX_CAP = "(?:Straße|Strasse|Str\\.|Weg|Allee|Platz|Ring|Gasse|Damm|Ufer|Chaussee|Steig|Pfad|Markt|Graben|Kai|Promenade|Anger|Hof|Berg|Bogen|Park|Brücke|Tor)";
const PREFIX = `(?:Am|An der|An den|Auf dem|Auf der|Im|In der|Zum|Zur|Unter den|Hinter dem|Vor dem|Alte[rn]?|Neue[rn]?|Große[rn]?|Kleine[rn]?|Lange[rn]?|Hohe[rn]?|Obere[rn]?|Untere[rn]?|Sankt|St\\.|[${U_}][${L_}]+er)`;
const STREET = `(?:(?:${WORD}-)*[${U_}][${L_}]*${SUFFIX_LOW}|(?:${WORD}-)+${SUFFIX_CAP}|(?:${PREFIX}\\s){1,2}${SUFFIX_CAP}|${PREFIX}\\s${WORD}(?=\\s\\d{1,4}[a-zA-Z]?\\s*,\\s*\\d{5}\\s))`;
const NUM = "\\d{1,4}(?:\\s?[a-zA-Z](?![a-zA-Z]))?(?:\\s?[-–/]\\s?\\d{1,4}[a-zA-Z]?)?(?![\\d.,:%]\\d|\\d)";
const CITY = `(?:(?:Bad|Sankt|St\\.)\\s)?${WORD}(?:-${WORD})*(?:\\s(?:am|an der|im|in der|ob der|bei|vor der)\\s${WORD})?(?:\\s\\([${U_}][\\p{L}.\\s]{1,30}\\))?`;
const ADDR_RE = new RegExp(`(${STREET})\\s(${NUM})(?:\\s*,?\\s*(\\d{5})\\s+(${CITY})|\\s*,\\s*(${CITY})(?=\\s*(?:$|[\\n.;!?)]|,\\s)))?`, "gu");
const PLZ_RE = new RegExp(`(?<![\\d,.\\-/])(\\d{5})\\s+(${CITY})`, "gu");
const NOT_CITY = /^(Euro|EUR|Stück|Stk|Mitarbeiter|Kunden|Teilnehmer|Seiten|Meter|Liter|Kilo|Tonnen|Einwohner|Exemplare|Besucher|Punkte|Zeichen|Mal|Uhr|Bitte|Danke|Termin|Treffen|Raum|Etage|Eingang|Hinterhaus|Tel|Telefon|Mobil|Fax|Mail|Ab|Bis|Und|Oder|Dann|Danach|Heute|Morgen|Ticket|Rechnung|Auftrag|Bestellung|Artikel|Nummer|Kundennummer|Teile|Dollar|Franken|Std|Minuten|Stunden|Tage|Wochen|Monate|Jahre)$/;
export function addresses(text) {
  const t = str(text).slice(0, 5000);
  const out = [];
  const taken = [];
  const add = (label, at, end) => {
    const l = clean(label, 200).replace(/[,\s]+$/, "");
    if (!l || out.some((x) => x.label === l)) return;
    out.push({ label: l, query: l, at });
    taken.push([at, end]);
  };
  for (const m of t.matchAll(ADDR_RE)) {
    const [all, street, num, plz, city1, city2] = m;
    if (city2 && NOT_CITY.test(city2.split(/\s/)[0])) {
      add(`${street} ${num}`, m.index, m.index + street.length + 1 + num.length);
      continue;
    }
    if (city1 && NOT_CITY.test(city1.split(/\s/)[0])) {
      add(`${street} ${num}`, m.index, m.index + street.length + 1 + num.length);
      continue;
    }
    const label = plz ? `${street} ${num}, ${plz} ${city1}` : city2 ? `${street} ${num}, ${city2}` : `${street} ${num}`;
    add(label, m.index, m.index + all.length);
  }
  for (const m of t.matchAll(PLZ_RE)) {
    if (taken.some(([a, b]) => m.index >= a && m.index < b)) continue;
    const plz = +m[1];
    if (plz < 1001 || plz > 99998 || NOT_CITY.test(m[2].split(/\s/)[0])) continue;
    add(`${m[1]} ${m[2]}`, m.index, m.index + m[0].length);
  }
  return out
    .sort((a, b) => a.at - b.at)
    .slice(0, 3)
    .map(({ label, query }) => ({ label, query }));
}

// ---------- Teilen ----------
export function taskShareText(t, { bag = null } = {}) {
  if (!t) return "";
  const lines = [str(t.title)];
  if (t.due) lines.push(`📅 ${safe(() => fmtDay(t.due)) || t.due}${t.time ? `, ${safe(() => fmtTime(t.time)) || t.time} Uhr` : ""}`);
  if (bag) lines.push(`${bag.emoji || "👜"} ${bag.name}`);
  if (str(t.notes).trim()) lines.push("", str(t.notes).trim());
  const subs = Array.isArray(t.subtasks) ? t.subtasks.filter((s) => s && str(s.title).trim()) : [];
  if (subs.length) lines.push("", ...subs.map((s) => `${s.done ? "✓" : "○"} ${s.title}`));
  return lines.join("\n").slice(0, 4000);
}
export async function shareTask(t, { bag = null } = {}) {
  const text = taskShareText(t, { bag });
  if (typeof navigator !== "undefined" && typeof navigator.share === "function") {
    try {
      await navigator.share({ title: str(t?.title), text });
      return "shared";
    } catch (e) {
      if (e?.name === "AbortError") return "cancelled";
    }
  }
  if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(text);
    return "copied";
  }
  throw new Error("Teilen ist hier nicht möglich.");
}

// =====================================================================================================================
// CSV / Excel
// =====================================================================================================================
export const CSV_COLUMNS = ["Titel", "Tasche", "Abschnitt", "Fällig", "Uhrzeit", "Priorität", "Status", "Notizen", "Tags", "Erstellt", "Erledigt"];
const PRIO_WORD = ["", "Niedrig", "Mittel", "Hoch"];
const deDate = (iso) => (isISO(iso) ? `${iso.slice(8, 10)}.${iso.slice(5, 7)}.${iso.slice(0, 4)}` : "");
const deStamp = (ms) => {
  if (!ms || !Number.isFinite(Number(ms))) return "";
  const d = new Date(Number(ms));
  return `${deDate(toISO(d))} ${hhmm(d)}`;
};
// Formel-Schutz: Excel führt =, +, @ (und -Text) am Zellanfang aus → Apostroph davor
function csvCell(v) {
  let s = str(v).replace(/\r\n?/g, "\n");
  if (/^[=+@\t\r]/.test(s) || /^-[^\s\d.,]/.test(s)) s = "'" + s;
  return `"${s.replace(/"/g, '""')}"`;
}
// Excel-tauglich: UTF-8 mit BOM, Semikolon, alles in Anführungszeichen, CRLF
export function exportCSV(tasks, { bagsById = {}, sep = ";" } = {}) {
  const rows = [CSV_COLUMNS];
  for (const t of Array.isArray(tasks) ? tasks : []) {
    if (!t || t.deleted) continue;
    const b = t.bag ? bagsById[t.bag] : null;
    rows.push([t.title, b ? b.name : "", t.section || "", deDate(t.due), t.time || "", PRIO_WORD[t.prio] || "", t.done ? "Erledigt" : "Offen", t.notes || "", (t.tags || []).join(", "), deStamp(t.created), deStamp(t.done)]);
  }
  return "﻿" + rows.map((r) => r.map(csvCell).join(sep)).join("\r\n") + "\r\n";
}

function detectSep(s) {
  const counts = { ";": 0, ",": 0, "\t": 0 };
  let q = false;
  for (let i = 0; i < s.length && i < 20000; i++) {
    const c = s[i];
    if (c === '"') q = !q;
    else if (!q && (c === "\n" || c === "\r")) break;
    else if (!q && c in counts) counts[c]++;
  }
  if (counts["\t"] > counts[";"] && counts["\t"] > counts[","]) return "\t";
  if (counts[";"] >= counts[","] && counts[";"] > 0) return ";";
  return counts[","] > 0 ? "," : ";";
}
// CSV lesen: Trennzeichen automatisch (; , Tab), Anführungszeichen, Zeilenumbrüche in Feldern, BOM, „sep=;“-Zeile
export function parseCSV(text, { sep = null, maxRows = 5000 } = {}) {
  let s = str(text).replace(/^﻿/, "");
  const sepLine = /^sep=(.)\r?\n/i.exec(s);
  if (sepLine) s = s.slice(sepLine[0].length);
  const d = sep || sepLine?.[1] || detectSep(s);
  const rows = [];
  let row = [];
  let cell = "";
  let q = false;
  let i = 0;
  const n = s.length;
  while (i < n) {
    const c = s[i];
    if (q) {
      if (c === '"') {
        if (s[i + 1] === '"') {
          cell += '"';
          i += 2;
          continue;
        }
        q = false;
        i++;
        continue;
      }
      cell += c;
      i++;
      continue;
    }
    if (c === '"' && cell.trim() === "") {
      cell = "";
      q = true;
      i++;
      continue;
    }
    if (c === d) {
      row.push(cell);
      cell = "";
      i++;
      continue;
    }
    if (c === "\n" || c === "\r") {
      row.push(cell);
      rows.push(row);
      if (rows.length > maxRows) break;
      row = [];
      cell = "";
      if (c === "\r" && s[i + 1] === "\n") i++;
      i++;
      continue;
    }
    cell += c;
    i++;
  }
  if (cell !== "" || row.length) {
    row.push(cell);
    rows.push(row);
  }
  const unguard = (v) => (/^'[=+@\t\r-]/.test(v) ? v.slice(1) : v);
  const all = rows.filter((r) => r.some((x) => x.trim() !== "")).map((r) => r.map(unguard));
  const headers = (all[0] || []).map((h) => h.replace(CTRL, "").trim());
  return { sep: d, headers, rows: all.slice(1, maxRows + 1) };
}

const COLS = {
  title: ["titel", "aufgabe", "aufgabenname", "taskname", "task", "title", "name", "cardname", "content", "betreff", "subject", "summary", "todo", "bezeichnung"],
  notes: ["notizen", "notiz", "beschreibung", "description", "notes", "note", "carddescription", "details", "kommentar", "kommentare", "bemerkung", "bemerkungen", "inhalt"],
  due: ["faellig", "faelligam", "faelligkeit", "faelligkeitsdatum", "duedate", "due", "date", "datum", "termin", "deadline", "enddatum", "enddate", "zieldatum", "bis"],
  time: ["uhrzeit", "zeit", "time", "startzeit"],
  prio: ["prioritaet", "prio", "priority", "wichtigkeit", "dringlichkeit"],
  bag: ["tasche", "projekt", "project", "projects", "listname", "liste", "list", "kategorie", "category", "bereich", "ordner"],
  section: ["abschnitt", "section", "sectioncolumn", "spalte", "column", "gruppe", "phase"],
  tags: ["tags", "tag", "labels", "label", "schlagwoerter", "etiketten", "stichwoerter"],
  done: ["status", "erledigt", "erledigtam", "completed", "completedat", "done", "closed", "archived", "abgeschlossen"],
  type: ["type"],
};
export const COLUMN_LABELS = { title: "Titel", notes: "Notizen", due: "Fällig", time: "Uhrzeit", prio: "Priorität", bag: "Tasche", section: "Abschnitt", tags: "Tags", done: "Erledigt/Status" };
// Spalten zuordnen (deutsch/englisch, Todoist, Trello, Asana) → { title: 0, due: 3, …, format }
export function mapColumns(headers) {
  const H = (Array.isArray(headers) ? headers : []).map((h) => normName(h));
  const raw = (Array.isArray(headers) ? headers : []).map((h) => str(h).trim());
  const map = {};
  const used = new Set();
  for (const k of Object.keys(COLS)) {
    map[k] = -1;
    for (const cand of COLS[k]) {
      const i = H.findIndex((h, j) => h === cand && !used.has(j));
      if (i >= 0) {
        map[k] = i;
        used.add(i);
        break;
      }
    }
  }
  let format = "csv";
  if (raw.includes("TYPE") && raw.includes("CONTENT")) format = "todoist";
  else if (H.includes("cardname") && H.includes("listname")) format = "trello";
  else if (H.includes("taskid") && (H.includes("sectioncolumn") || H.includes("projects"))) format = "asana";
  else if (H.includes("titel") && H.includes("tasche") && H.includes("faellig")) format = "arbeitstaschen";
  // Asana: „Completed At“ statt Status; Trello: „Archived“ bzw. „Closed“
  if (format === "asana") {
    const ca = H.indexOf("completedat");
    if (ca >= 0) map.done = ca;
  }
  return { ...map, format };
}
export const FORMAT_LABELS = { todoist: "Todoist", trello: "Trello", asana: "Asana", arbeitstaschen: "Arbeitstaschen / Excel", csv: "Excel / CSV" };

export function parseDone(v) {
  const s = str(v).trim().toLowerCase();
  if (!s) return false;
  if (/^(x|✓|✔|ja|yes|y|true|wahr|1|erledigt|done|completed|complete|abgeschlossen|fertig|closed|archiviert|archived|geschlossen)$/.test(s)) return true;
  if (/^(nein|no|n|false|falsch|0|offen|open|todo|to do|in arbeit|in progress|not started|nicht begonnen|aktiv|active)$/.test(s)) return false;
  return /^\d{4}-\d{2}-\d{2}|^\d{1,2}\.\d{1,2}\.\d{2,4}/.test(s); // „Completed At“ mit Datum
}

// Zeilen → Aufgaben-Daten; bagMode: "inbox" | "fixed" (bagId) | "column" (Spalte „Tasche“, fehlende werden neu angelegt)
export function csvTasks(parsed, map, { bagMode = "inbox", bagId = null, bags = [], skipDone = true, now = new Date(), profile, max = 2000 } = {}) {
  const out = [];
  const newBags = new Map();
  const todo = map?.format === "todoist";
  let section = "";
  const at = (row, k) => (map && Number.isInteger(map[k]) && map[k] >= 0 ? str(row[map[k]]).trim() : "");
  for (const row of parsed?.rows || []) {
    if (out.length >= max) break;
    if (todo) {
      const type = at(row, "type").toLowerCase();
      if (type === "section") {
        section = clean(at(row, "title"), 80);
        continue;
      }
      if (type === "note") {
        const last = out[out.length - 1];
        const note = cleanText(at(row, "title"), 2000);
        if (last && note) last.notes = [last.notes, note].filter(Boolean).join("\n\n");
        continue;
      }
      if (type && type !== "task") continue;
    }
    let title = clean(at(row, "title"), 300);
    if (todo) title = clean(title.replace(/\s@[\p{L}\d_-]+/gu, ""), 300);
    if (!title) continue;
    const done = parseDone(at(row, "done"));
    if (done && skipDone) continue;
    const dueRaw = at(row, "due");
    const dt = parseDateText(dueRaw, { now, profile });
    const tm = parseTime(at(row, "time").replace(/\s*uhr$/i, "").replace(".", ":"));
    const notes = [cleanText(at(row, "notes"), 8000), dueRaw && !dt.due ? `Fällig (Import): ${clean(dueRaw, 120)}` : ""].filter(Boolean).join("\n\n");
    const tags = at(row, "tags")
      .split(/[,;|]+/)
      .map((x) => clean(x, 40).replace(/^[#@]+/, "").replace(/\s*\(.*\)$/, ""))
      .filter(Boolean)
      .slice(0, 12);
    if (connect.isCall(title) && !tags.includes("anruf")) tags.push("anruf"); // wie in der Schnellerfassung
    let bag = null;
    let bagName = "";
    if (bagMode === "fixed") bag = bagId || null;
    else if (bagMode === "column") {
      bagName = clean(at(row, "bag").split(/[,;|]/)[0], 80);
      if (bagName) {
        const b = bags.find((x) => x && !x.deleted && normName(x.name) === normName(bagName));
        if (b) bag = b.id;
        else newBags.set(normName(bagName), bagName);
      }
    }
    out.push({
      title,
      notes,
      due: dt.due,
      time: tm !== null ? toTime(tm) : dt.time,
      prio: parsePrio(at(row, "prio"), { todoist: todo }),
      tags,
      section: clean(at(row, "section"), 80) || section,
      bag,
      bagName: bag ? "" : bagName,
      done: done ? true : null,
    });
  }
  return { tasks: out, newBags: [...newBags.values()] };
}

// Text einer Datei (UTF-8, sonst Windows-1252 – so speichert Excel unter Windows „CSV (Trennzeichen-getrennt)“)
export function decodeText(bytes) {
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(u8);
  } catch (_) {
    try {
      return new TextDecoder("windows-1252").decode(u8);
    } catch (__) {
      return new TextDecoder("utf-8").decode(u8);
    }
  }
}

// =====================================================================================================================
// Start (Browser): Briefkasten abholen, Webhooks senden
// =====================================================================================================================
let started = false;
export function start(store) {
  if (store) ST = store;
  if (started || !ST) return;
  started = true;
  ST.subscribe?.((s, ch) => onStoreChange(ST, ch));
  if (!hasWin()) return;
  const tick = () => {
    if (document.visibilityState === "visible") pullInbox(ST).catch(() => {});
  };
  setTimeout(tick, 1200);
  document.addEventListener("visibilitychange", tick);
  window.addEventListener("online", tick);
  setInterval(tick, PULL_EVERY + 2000);
}

// Nur für Tests
export function _reset() {
  ST = null;
  pulling = null;
  lastPull = 0;
  hookState.clear();
  queue = new Map();
  clearTimeout(qTimer);
  qTimer = null;
  sentDone.clear();
  listeners.clear();
  started = false;
}
