// Arbeitstaschen – Datum, Uhrzeit und deutsche Schnellerfassung (reine Funktionen, immer lokale Kalendertage)
import { DEFAULT_PROFILE, REPEATS } from "./config.js";

// ---------- Grundlagen ----------
// Kalendertage werden als „Tagesnummer“ über UTC gerechnet – so gibt es keine Sommerzeit-Sprünge (23/25-Stunden-Tage).
const DAY = 86400000;
const pad = (n) => String(n).padStart(2, "0");
const ISO_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const TIME_RE = /^(\d{1,2}):(\d{2})$/;
const REPEAT_IDS = new Set(REPEATS.map((r) => r.id).filter(Boolean));

export const WEEKDAYS = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"];
export const WEEKDAYS_SHORT = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"];
export const MONTHS = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"];

// Tage im Monat (m = 1..12)
export const daysInMonth = (y, m) => new Date(Date.UTC(y, m, 0)).getUTCDate();

function ymd(iso) {
  const m = ISO_RE.exec(typeof iso === "string" ? iso : "");
  if (!m) return null;
  const y = +m[1], mo = +m[2], d = +m[3];
  if (y < 1000 || mo < 1 || mo > 12 || d < 1 || d > daysInMonth(y, mo)) return null;
  return [y, mo, d];
}
const fromParts = (y, m, d) => `${String(y).padStart(4, "0")}-${pad(m)}-${pad(d)}`;
function validParts(y, m, d) {
  return Number.isInteger(y) && Number.isInteger(m) && Number.isInteger(d) && m >= 1 && m <= 12 && d >= 1 && d <= daysInMonth(y, m);
}
function dayNum(iso) {
  const p = ymd(iso);
  return p ? Math.round(Date.UTC(p[0], p[1] - 1, p[2]) / DAY) : NaN;
}
function fromDayNum(n) {
  const d = new Date(n * DAY);
  return fromParts(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate());
}

// Gültiges "YYYY-MM-DD" (auch 31.02. wird abgelehnt)
export const isISO = (s) => ymd(s) !== null;

// Date | ms | "YYYY-MM-DD" → "YYYY-MM-DD" (lokaler Kalendertag), sonst null
export function toISO(date) {
  if (typeof date === "string" && isISO(date)) return date;
  const d = date instanceof Date ? date : typeof date === "number" ? new Date(date) : null;
  if (!d || Number.isNaN(d.getTime())) return null;
  return fromParts(d.getFullYear(), d.getMonth() + 1, d.getDate());
}

export const todayISO = (now = new Date()) => toISO(now);

// "YYYY-MM-DD" → Date um 00:00 Ortszeit (ungültig → Invalid Date)
export function fromISO(iso) {
  const p = ymd(iso);
  return p ? new Date(p[0], p[1] - 1, p[2]) : new Date(NaN);
}

export function addDays(iso, n) {
  const k = dayNum(toISO(iso));
  return Number.isFinite(k) ? fromDayNum(k + Math.trunc(Number(n) || 0)) : null;
}

// Ganze Kalendertage von a bis b (b − a); nimmt ISO-Strings oder Dates
export function diffDays(a, b) {
  return dayNum(toISO(b)) - dayNum(toISO(a));
}

// 0 = Sonntag … 6 = Samstag
export function weekday(iso) {
  const n = dayNum(toISO(iso));
  return Number.isFinite(n) ? (((n + 4) % 7) + 7) % 7 : NaN;
}

export function startOfWeek(iso, weekStart = 1) {
  const wd = weekday(iso);
  return Number.isFinite(wd) ? addDays(iso, -((wd - weekStart + 7) % 7)) : null;
}

// Monate addieren; Tag wird ans Monatsende geklammert (31.01. + 1 → 28./29.02.). day = gewünschter Ankertag.
export function addMonths(iso, n, day) {
  const p = ymd(toISO(iso));
  if (!p) return null;
  const total = p[0] * 12 + (p[1] - 1) + Math.trunc(Number(n) || 0);
  const y = Math.floor(total / 12), m = (total % 12) + 1;
  return fromParts(y, m, Math.min(day || p[2], daysInMonth(y, m)));
}

export function endOfMonth(iso) {
  const p = ymd(toISO(iso));
  return p ? fromParts(p[0], p[1], daysInMonth(p[0], p[1])) : null;
}

export const isWeekend = (iso) => {
  const wd = weekday(iso);
  return wd === 0 || wd === 6;
};

// ISO-Kalenderwoche (KW, Montag als Wochenstart)
export function isoWeek(iso) {
  const n = dayNum(toISO(iso));
  if (!Number.isFinite(n)) return NaN;
  const thu = n - ((weekday(iso) + 6) % 7) + 3;
  const y = new Date(thu * DAY).getUTCFullYear();
  return Math.floor((thu - Math.round(Date.UTC(y, 0, 1) / DAY)) / 7) + 1;
}

// Montag der ISO-Woche week im Jahr year
export function isoWeekStart(year, week) {
  const jan4 = fromParts(year, 1, 4);
  return addDays(jan4, -((weekday(jan4) + 6) % 7) + (week - 1) * 7);
}

// ---------- Wiederholungen ----------
// Nächster Termin echt nach max(iso, after). Monatlich/jährlich bleibt am Ankertag (day, sonst Tag von iso) und klammert ans Monatsende.
export function nextOccurrence(iso, repeat, after, day) {
  const base = isISO(iso) ? iso : isISO(after) ? after : null;
  if (!base || !REPEAT_IDS.has(repeat)) return null;
  const ref = isISO(after) && after > base ? after : base;
  if (repeat === "daily") return addDays(ref, 1);
  if (repeat === "weekdays") {
    let d = addDays(ref, 1);
    while (isWeekend(d)) d = addDays(d, 1);
    return d;
  }
  if (repeat === "weekly" || repeat === "biweekly") {
    const step = repeat === "weekly" ? 7 : 14;
    return addDays(base, (Math.floor(diffDays(base, ref) / step) + 1) * step);
  }
  // monthly / yearly
  const months = repeat === "monthly" ? 1 : 12;
  const anchor = Number.isInteger(day) && day >= 1 && day <= 31 ? day : ymd(base)[2];
  const b = ymd(base), r = ymd(ref);
  let k = Math.max(1, Math.floor(((r[0] - b[0]) * 12 + (r[1] - b[1])) / months));
  for (let i = 0; i < 400; i++, k++) {
    const d = addMonths(base, k * months, anchor);
    if (d > ref) return d;
  }
  return null;
}

// ---------- Uhrzeiten & Zeitpunkte ----------
// "HH:MM" → Minuten seit Mitternacht (ungültig → null)
export function parseTime(t) {
  const m = TIME_RE.exec(String(t ?? "").trim());
  if (!m) return null;
  const h = +m[1], mi = +m[2];
  return h > 23 || mi > 59 ? null : h * 60 + mi;
}
export const isTime = (t) => parseTime(t) !== null;
export const toTime = (min) => `${pad(Math.floor(min / 60) % 24)}:${pad(min % 60)}`;

// Lokaler Zeitpunkt aus Kalendertag + Minuten (Sommerzeit-sicher, weil über Ortszeit-Bestandteile gebaut)
export function atLocal(iso, minutes = 0) {
  const p = ymd(toISO(iso));
  return p ? new Date(p[0], p[1] - 1, p[2], Math.floor(minutes / 60), minutes % 60) : null;
}

// Fälligkeit als Date: due + time; ohne Uhrzeit → due um profile.dayStart
export function dueAt(task, profile = DEFAULT_PROFILE) {
  if (!task || !isISO(task.due)) return null;
  let m = parseTime(task.time);
  if (m === null) m = parseTime(profile?.dayStart) ?? 480;
  return atLocal(task.due, m);
}

// Erinnerung nur bei Aufgaben mit Uhrzeit: dueAt − (remind ?? defaultRemind) Minuten; remind −1 = keine
export function remindAt(task, profile = DEFAULT_PROFILE) {
  if (!task || !isISO(task.due) || parseTime(task.time) === null) return null;
  const r = task.remind ?? profile?.defaultRemind ?? DEFAULT_PROFILE.defaultRemind;
  if (typeof r !== "number" || !Number.isFinite(r) || r < 0) return null;
  return new Date(dueAt(task, profile).getTime() - r * 60000);
}

// ---------- Deutsche Formatierung ----------
const fmtCache = new Map();
function dtf(opts) {
  const k = JSON.stringify(opts);
  let f = fmtCache.get(k);
  if (!f) fmtCache.set(k, (f = new Intl.DateTimeFormat("de-DE", opts)));
  return f;
}
const nf = new Intl.NumberFormat("de-DE", { maximumFractionDigits: 1 });
export const fmtNumber = (n) => nf.format(n);

// "Heute" | "Morgen" | "Übermorgen" | "Gestern" | "Donnerstag" | "vor 3 Tagen" | "12. Okt." | "12. Okt. 2027"
export function relDay(iso, now = new Date()) {
  const n = diffDays(todayISO(now), iso);
  if (!Number.isFinite(n)) return "";
  if (n === 0) return "Heute";
  if (n === 1) return "Morgen";
  if (n === 2) return "Übermorgen";
  if (n === -1) return "Gestern";
  if (n > 2 && n < 7) return WEEKDAYS[weekday(iso)];
  if (n < -1 && n > -7) return `vor ${-n} Tagen`;
  const d = fromISO(iso);
  return dtf(d.getFullYear() === now.getFullYear() ? { day: "numeric", month: "short" } : { day: "numeric", month: "short", year: "numeric" }).format(d);
}

// "Mo., 13. Oktober" bzw. "13. Oktober" (Jahr nur, wenn es nicht das aktuelle ist)
export function fmtDay(iso, { weekday: wd = true, now = new Date() } = {}) {
  const d = fromISO(iso);
  if (Number.isNaN(d.getTime())) return "";
  const o = { day: "numeric", month: "long" };
  if (wd) o.weekday = "short";
  if (d.getFullYear() !== now.getFullYear()) o.year = "numeric";
  return dtf(o).format(d);
}

// "Dienstag, 6. Oktober"
export const dateLabel = (now = new Date()) => dtf({ weekday: "long", day: "numeric", month: "long" }).format(now);

// "09:05" → "9:05"
export function fmtTime(t) {
  const m = parseTime(t);
  return m === null ? "" : `${Math.floor(m / 60)}:${pad(m % 60)}`;
}

// 90 → "1 Std. 30 Min."; 45 → "45 Min."; 120 → "2 Std."
export function fmtDuration(min) {
  if (min === null || min === undefined || !Number.isFinite(Number(min))) return "";
  const t = Math.max(0, Math.round(Number(min)));
  const h = Math.floor(t / 60), m = t % 60;
  if (!h) return `${m} Min.`;
  return m ? `${h} Std. ${m} Min.` : `${h} Std.`;
}

// Relativ zu jetzt: "gerade eben", "vor 5 Min.", "vor 2 Std.", "gestern", "vor 3 Tagen", "12. Okt."
export function fmtAgo(ms, now = new Date()) {
  if (!Number.isFinite(ms)) return "";
  const nowMs = now instanceof Date ? now.getTime() : now;
  const s = Math.round((nowMs - ms) / 1000);
  if (s < 45) return "gerade eben";
  if (s < 3600) return `vor ${Math.max(1, Math.round(s / 60))} Min.`;
  const days = diffDays(toISO(ms), toISO(nowMs));
  if (days === 0) return `vor ${Math.round(s / 3600)} Std.`;
  if (days === 1) return "gestern";
  if (days < 7) return `vor ${days} Tagen`;
  return relDay(toISO(ms), new Date(nowMs));
}

// Tageszeit: 5–11 Morgen, 11–17 Tag, 17–22 Abend, sonst Nacht
export function daypart(now = new Date()) {
  const h = now.getHours();
  if (h >= 5 && h < 11) return "morning";
  if (h >= 11 && h < 17) return "day";
  if (h >= 17 && h < 22) return "evening";
  return "night";
}
export function greeting(now = new Date()) {
  return { morning: "Guten Morgen", day: "Guten Tag", evening: "Guten Abend", night: "Gute Nacht" }[daypart(now)];
}

// ---------- Schnellerfassung: Wortlisten ----------
const B = "(?<![\\p{L}\\p{N}])"; // Wortanfang (Umlaut-fest)
const E = "(?![\\p{L}\\p{N}])"; // Wortende
const R = (src) => new RegExp(src, "giu");

const WD_MAP = { montag: 1, mo: 1, dienstag: 2, di: 2, mittwoch: 3, mi: 3, donnerstag: 4, do: 4, freitag: 5, fr: 5, samstag: 6, sonnabend: 6, sa: 6, sonntag: 0, so: 0 };
const WD_ALT = "montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonnabend|sonntag|mo|di|mi|do|fr|sa|so";
const WD_PLURAL = "montags|dienstags|mittwochs|donnerstags|freitags|samstags|sonnabends|sonntags";
const MONTH_MAP = {
  januar: 1, jänner: 1, jaenner: 1, jan: 1, februar: 2, feb: 2, märz: 3, maerz: 3, mär: 3, mrz: 3, april: 4, apr: 4, mai: 5, juni: 6, jun: 6, juli: 7, jul: 7,
  august: 8, aug: 8, september: 9, sept: 9, sep: 9, oktober: 10, okt: 10, november: 11, nov: 11, dezember: 12, dez: 12,
};
const MONTH_ALT = "januar|jänner|jaenner|februar|märz|maerz|april|mai|juni|juli|august|september|oktober|november|dezember|jan|feb|mär|mrz|apr|jun|jul|aug|sept|sep|okt|nov|dez";
const NUM_MAP = { ein: 1, eine: 1, einen: 1, einem: 1, einer: 1, eins: 1, zwei: 2, drei: 3, vier: 4, fünf: 5, fuenf: 5, sechs: 6, sieben: 7, acht: 8, neun: 9, zehn: 10, elf: 11, zwölf: 12, zwoelf: 12 };
const NUM_ALT = "einem|einen|einer|eine|eins|ein|zwei|drei|vier|fünf|fuenf|sechs|sieben|acht|neun|zehn|elf|zwölf|zwoelf";
const NEXT = "(?:nächste[nrs]?|naechste[nrs]?|kommende[nrs]?)";
const UE = "(?:ü|ue)";
const AE = "(?:ä|ae)";
const OE = "(?:ö|oe)";

// Präposition direkt vor einem Datum wird mit verschluckt („am“, „bis“, „spätestens“ …)
const PRE = `(?<pre>(?:bis\\s+(?:zum\\s+|sp${AE}testens\\s+(?:am\\s+|zum\\s+)?)?|sp${AE}testens\\s+(?:am\\s+|zum\\s+|bis\\s+)?|f${AE}llig\\s+(?:am\\s+|bis\\s+)?|(?:frist|deadline)\\s*:?\\s+|ab\\s+(?:dem\\s+)?|am\\s+|zum\\s+|f${UE}r\\s+|an\\s+|gegen\\s+)?)`;
const PRE_STRICT = `(?<pre>am|bis(?:\\s+zum)?|ab(?:\\s+dem)?|zum|sp${AE}testens(?:\\s+am)?|(?:frist|deadline)\\s*:?|f${AE}llig\\s+am)\\s+`;

const num = (s) => {
  const k = String(s ?? "").toLowerCase();
  if (/^\d+$/.test(k)) return +k;
  return NUM_MAP[k] ?? NaN;
};
const unitMinutes = (u) => {
  const k = String(u ?? "").toLowerCase().replace(/\.$/, "");
  if (/^(m|min|mins|minute|minuten)$/.test(k)) return 1;
  if (/^(h|std|stunde|stunden)$/.test(k)) return 60;
  if (/^(t|tag|tage|tagen)$/.test(k)) return 1440;
  if (/^(w|woche|wochen)$/.test(k)) return 10080;
  return NaN;
};
const decimal = (s) => Number(String(s).replace(",", "."));

// Text für Taschen-Abgleich: klein, Umlaute ausgeschrieben, nur Buchstaben/Ziffern
export function normName(s) {
  return String(s ?? "").toLowerCase().replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/ß/g, "ss").normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, "");
}
const nameWords = (name) => [...new Set([...String(name).split(/\s+/), ...String(name).split(/[\s\-–—&+/,.:()]+/)])].map(normName).filter(Boolean);

// #Token → Tasche: exakt → Präfix des Namens → Präfix eines Wortes → Teilwort (aktive bevorzugt)
export function matchBag(token, bags = []) {
  const q = normName(token);
  if (!q) return null;
  let best = null, bestKey = null;
  const better = (a, b) => {
    for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return a[i] > b[i];
    return false;
  };
  for (const b of bags || []) {
    if (!b || b.deleted || !b.name) continue;
    const n = normName(b.name);
    // exakt → Präfix → Wortpräfix → Teilwort in Komposita („#Gründ“ → „Firmengründung“, ab 4 Zeichen)
    const s = n === q ? 4 : q.length >= 2 && n.startsWith(q) ? 3 : q.length >= 2 && nameWords(b.name).some((w) => w.startsWith(q)) ? 2 : q.length >= 4 && n.includes(q) ? 1 : 0;
    if (!s) continue;
    // Rang: Trefferart, aktive Taschen, kürzerer Name, kleinere Sortiernummer
    const key = [s, b.status === "aktiv" || !b.status ? 1 : 0, -n.length, -(Number(b.order) || 0)];
    if (!bestKey || better(key, bestKey)) {
      best = b;
      bestKey = key;
    }
  }
  return best;
}

// ---------- Schnellerfassung: Scanner ----------
// Hält fest, welche Zeichen geschützt (Zitate, URLs, E-Mails) oder schon als Token verbraucht sind.
class Scanner {
  constructor(text) {
    this.text = text;
    this.mask = new Uint8Array(text.length);
    this.tokens = [];
    this.work = text;
  }
  refresh() {
    const a = [];
    for (let i = 0; i < this.text.length; i++) a.push(this.mask[i] ? "\u0000" : this.text[i]);
    this.work = a.join("");
  }
  protect(re) {
    for (const m of this.text.matchAll(re)) for (let i = m.index; i < m.index + m[0].length; i++) this.mask[i] = 1;
    this.refresh();
  }
  // Alle Treffer eines Musters im freien Text; fn liefert einen Wert oder null (ablehnen)
  find(re, type, fn, prio = 0) {
    const out = [];
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(this.work))) {
      if (!m[0]) {
        re.lastIndex++;
        continue;
      }
      let v = null;
      try {
        v = fn(m);
      } catch (_) {
        v = null; // unsinnige Eingabe bleibt einfach Text
      }
      if (v) out.push({ type, start: m.index + (v.skip || 0), end: m.index + m[0].length - (v.trim || 0), value: v, prio });
    }
    return out;
  }
  // Überlappungen auflösen: längere Treffer gewinnen, dann frühere Muster
  static resolve(cands) {
    const sorted = [...cands].sort((a, b) => b.end - b.start - (a.end - a.start) || a.prio - b.prio || a.start - b.start);
    const kept = [];
    for (const c of sorted) if (!kept.some((k) => c.start < k.end && k.start < c.end)) kept.push(c);
    return kept.sort((a, b) => a.start - b.start);
  }
  take(c, type = c.type) {
    for (let i = c.start; i < c.end; i++) this.mask[i] = 2;
    this.tokens.push({ type, text: this.text.slice(c.start, c.end), start: c.start, end: c.end });
    this.refresh();
  }
  // Rest hinter pos besteht nur noch aus Leerraum, Satzzeichen oder Steuer-Tokens (#, @, !, ~, *)?
  restIsEmpty(pos) {
    return /^(?:[\s\u0000.,;:!?)]|[#@~*!][^\s\u0000]*)*$/u.test(this.work.slice(pos));
  }
}

const isCap = (s) => {
  const c = String(s)[0] || "";
  return c !== c.toLowerCase() && c === c.toUpperCase();
};

// ---------- Schnellerfassung ----------
export function parseQuick(text, { bags = [], now = new Date(), profile } = {}) {
  const original = String(text ?? "");
  const empty = { title: original.trim(), due: null, time: null, prio: 0, bag: null, bagName: null, tags: [], remind: null, repeat: null, someday: false, est: null, plan: false, tokens: [], notes: "", section: "", waiting: "" };
  try {
    return parseQuickInner(original, { bags: Array.isArray(bags) ? bags : [], now: now instanceof Date && !Number.isNaN(now.getTime()) ? now : new Date(), profile: { ...DEFAULT_PROFILE, ...(profile || {}) } }) || empty;
  } catch (_) {
    return empty; // die Schnellerfassung wirft nie – im Zweifel bleibt alles Titel
  }
}

function parseQuickInner(original, { bags, now, profile }) {
  const T = todayISO(now);
  const nowMin = now.getHours() * 60 + now.getMinutes();
  const weekStart = Number.isInteger(profile.weekStart) ? profile.weekStart : 1;
  const dayStartMin = parseTime(profile.dayStart) ?? 480;
  const res = { title: "", due: null, time: null, prio: 0, bag: null, bagName: null, tags: [], remind: null, repeat: null, someday: false, est: null, plan: false, tokens: [], notes: "", section: "", waiting: "" };

  // Notizen: alles nach „ // “ wird nicht ausgewertet
  let main = original;
  const cut = original.indexOf(" // ");
  if (cut >= 0) {
    res.notes = original.slice(cut + 4).trim();
    main = original.slice(0, cut);
  }
  const S = new Scanner(main);
  S.protect(/„[^“”"\n]*[“”"]|"[^"\n]*"|“[^”\n]*”|https?:\/\/\S+|www\.\S+|[^\s@]+@[^\s@]+\.[^\s@]+/giu);

  // Wartet auf …: Titel bleibt vollständig, nur das Feld wird gesetzt
  const wm = /^\s*(?:warte|wartet|warten)\s+auf\s+(.+)$/iu.exec(main);

  // Hilfen für Datumswerte
  const nextWeekday = (wd, strict = true) => {
    let d = strict ? addDays(T, 1) : T;
    while (weekday(d) !== wd) d = addDays(d, 1);
    return d;
  };
  const weekBase = (offsetWeeks) => addDays(startOfWeek(T, weekStart), 7 * offsetWeeks);
  const inWeek = (start, wd) => addDays(start, (wd - weekStart + 7) % 7);
  const futureYear = (d, m, y) => {
    if (y !== undefined) return validParts(y, m, d) ? fromParts(y, m, d) : null;
    const y0 = +T.slice(0, 4);
    if (!validParts(y0, m, d)) return validParts(y0 + 1, m, d) && fromParts(y0 + 1, m, d) >= T ? fromParts(y0 + 1, m, d) : null;
    const iso = fromParts(y0, m, d);
    if (iso >= T) return iso;
    return validParts(y0 + 1, m, d) ? fromParts(y0 + 1, m, d) : null;
  };
  const fullYear = (s) => (s === undefined ? undefined : s.length === 2 ? 2000 + +s : +s);

  const take = (cands, type) => {
    const kept = Scanner.resolve(cands);
    if (!kept.length) return null;
    const c = kept[kept.length - 1]; // rechtester Treffer gewinnt, die anderen bleiben Text
    S.take(c, type);
    return c;
  };
  const takeAll = (cands, type) => {
    const kept = Scanner.resolve(cands);
    for (const c of kept) S.take(c, type);
    return kept;
  };

  // 1) „heute einplanen“ und „*“ → für heute einplanen
  {
    const c = [
      ...S.find(R(`${B}(?:f${UE}r\\s+)?heute\\s+einplanen${E}|${B}einplanen\\s+f${UE}r\\s+heute${E}`), "plan", () => ({})),
      ...S.find(/(?<![^\s\u0000])\*(?![^\s\u0000])/gu, "plan", () => ({})),
    ];
    if (takeAll(c, "plan").length) res.plan = true;
  }

  // 2) Wiederholung
  let rep = null;
  {
    const c = [
      ...S.find(R(`${B}(?:jeden\\s+tag|t${AE}glich|tagt${AE}glich)${E}`), "repeat", () => ({ repeat: "daily" })),
      ...S.find(R(`${B}jeden\\s+(?<dp>morgen|abend|mittag|vormittag|nachmittag)${E}`), "repeat", (m) => ({ repeat: "daily", dp: m.groups.dp.toLowerCase() })),
      ...S.find(R(`${B}(?:werktags|wochentags|jeden\\s+werktag|mo\\s*[-–]\\s*fr|montags?\\s+bis\\s+freitags?)${E}`), "repeat", () => ({ repeat: "weekdays" })),
      ...S.find(R(`${B}(?:w${OE}chentlich|jede\\s+woche|einmal\\s+(?:die|pro|in\\s+der)\\s+woche)${E}`), "repeat", () => ({ repeat: "weekly" })),
      ...S.find(R(`${B}(?:(?:alle|jede)\\s+(?:2|zwei)\\s+wochen|jede\\s+zweite\\s+woche|zweiw${OE}chentlich|(?:14|vierzehn)-?t${AE}gig|alle\\s+14\\s+tage)(?:\\s+(?:am\\s+)?(?<wd>${WD_PLURAL}|${WD_ALT}))?${E}`), "repeat", (m) => ({ repeat: "biweekly", wd: m.groups.wd ? WD_MAP[m.groups.wd.toLowerCase().replace(/s$/, "")] : undefined })),
      ...S.find(R(`${B}(?:monatlich|jeden\\s+monat|einmal\\s+(?:im|pro)\\s+monat)(?:\\s+(?:am|zum)\\s+(?<d>\\d{1,2})\\.(?!\\p{N}))?${E}`), "repeat", (m) => ({ repeat: "monthly", md: m.groups.d ? +m.groups.d : undefined })),
      ...S.find(R(`${B}(?:jeden|am)\\s+(?<d>\\d{1,2})\\.(?:\\s+(?:jeden|des|eines)\\s+monats|(?=\\s|$))(?!\\s*(?:${MONTH_ALT}|\\d))`), "repeat", (m) => (/^jeden/i.test(m[0]) || /monats/i.test(m[0]) ? { repeat: "monthly", md: +m.groups.d } : null)),
      ...S.find(R(`${B}(?:j${AE}hrlich|jedes\\s+jahr|einmal\\s+(?:im|pro)\\s+jahr)${E}`), "repeat", () => ({ repeat: "yearly" })),
      ...S.find(R(`${B}(?:jeden|immer)\\s+(?<wd>${WD_ALT})\\.?${E}`), "repeat", (m) => ({ repeat: "weekly", wd: WD_MAP[m.groups.wd.toLowerCase()] })),
      ...S.find(R(`${B}(?<wd>${WD_PLURAL})${E}`), "repeat", (m) => ({ repeat: "weekly", wd: WD_MAP[m.groups.wd.toLowerCase().replace(/s$/, "")] })),
    ];
    const t = take(c, "repeat");
    if (t) {
      rep = t.value;
      if (rep.md !== undefined && (rep.md < 1 || rep.md > 31)) rep.md = undefined;
      res.repeat = rep.repeat;
    }
  }

  // 3) Erinnerung („erinnere 30 min vorher“, „1 Std vorher“, „ohne Erinnerung“)
  {
    const TRIG = `(?:(?:erinnere?|erinner)\\s+(?:mich\\s+)?|erinnerung\\s*:?\\s+|reminder\\s*:?\\s+|wecker\\s*:?\\s+)?`;
    const c = [
      ...S.find(R(`${B}${TRIG}(?<n>\\d{1,4}(?:[.,]5)?|${NUM_ALT})?\\s*(?<half>halbe\\s+)?(?<u>min\\.?|minuten?|m|std\\.?|stunden?|h|tage?n?|t|wochen?)\\s+(?:vorher|davor|fr${UE}her|zuvor)${E}`), "remind", (m) => {
        const u = unitMinutes(m.groups.u);
        if (!Number.isFinite(u)) return null;
        let n = m.groups.n === undefined ? 1 : /[.,]/.test(m.groups.n) ? decimal(m.groups.n) : num(m.groups.n);
        if (m.groups.half) n = n * 0.5;
        if (!Number.isFinite(n) || n < 0) return null;
        return { min: Math.round(n * u) };
      }),
      ...S.find(R(`${B}(?:ohne|keine)\\s+(?:erinnerung(?:en)?|wecker|reminder)${E}`), "remind", () => ({ min: -1 })),
      ...S.find(R(`${B}(?:erinnere?|erinner|erinnerung)\\s+(?:mich\\s+)?(?:am\\s+)?vortag${E}`), "remind", () => ({ min: 1440 })),
    ];
    const t = take(c, "remind");
    if (t) res.remind = t.value.min;
  }

  // 4) Dauer / Schätzung („~30m“, „~2h“, „dauert 45 min“, „(30 min)“)
  {
    const UNIT = `(?<u>min\\.?|minuten?|mins?|m|std\\.?|stunden?|h)`;
    const est = (m, fallbackUnit) => {
      const g = m.groups;
      let n = g.n === undefined ? 1 : /^\d/.test(g.n) ? decimal(g.n) : /halb/i.test(g.n) ? 1.5 : num(g.n);
      if (g.half) n = n * 0.5;
      let u = g.u ? unitMinutes(g.u) : fallbackUnit(n);
      if (!Number.isFinite(n) || !Number.isFinite(u) || n <= 0) return null;
      const v = Math.round(n * u);
      return v > 0 && v <= 14400 ? { min: v } : null;
    };
    const c = [
      ...S.find(R(`(?<![\\p{L}\\p{N}])~\\s*(?<n>\\d{1,4}(?:[.,]\\d{1,2})?)(?:\\s*${UNIT})?${E}`), "est", (m) => est(m, (n) => (n <= 12 ? 60 : 1))),
      ...S.find(R(`${B}(?:dauert|dauer\\s*:?|aufwand\\s*:?)\\s+(?:ca\\.?\\s+|etwa\\s+|circa\\s+|rund\\s+)?(?<n>\\d{1,4}(?:[.,]\\d{1,2})?|${NUM_ALT}|anderthalb|eineinhalb)\\s*(?<half>halbe\\s+)?${UNIT}${E}`), "est", (m) => est(m, () => NaN)),
      ...S.find(R(`\\(\\s*(?:ca\\.?\\s*|~\\s*)?(?<n>\\d{1,4}(?:[.,]\\d{1,2})?)\\s*${UNIT}\\s*\\)`), "est", (m) => est(m, () => NaN)),
      ...S.find(R(`${B}f${UE}r\\s+(?:ca\\.?\\s+|etwa\\s+)?(?<n>\\d{1,4}(?:[.,]\\d{1,2})?|${NUM_ALT}|anderthalb|eineinhalb)\\s*(?<half>halbe\\s+)?${UNIT}${E}`), "est", (m) => est(m, () => NaN)),
    ];
    const t = take(c, "est");
    if (t) res.est = t.value.min;
  }

  // 5) Datum
  let date = null;
  {
    const c = [];
    // heute / morgen / übermorgen / gestern (+ Tageszeit: „morgen früh“, „heute Abend“)
    c.push(
      ...S.find(R(`${B}${PRE}(?<w>${UE}bermorgen|morgen|heute|gestern)(?:\\s+(?<dp>fr${UE}h|morgen|vormittag|mittag|nachmittag|abend|nacht))?${E}`), "date", (m) => {
        const w = m.groups.w.toLowerCase().replace("ue", "ü");
        const pre = (m.groups.pre || "").trim().toLowerCase();
        if (w === "morgen" && /^(am|gegen)$/.test(pre)) return null; // „am Morgen“ ist eine Tageszeit
        if (/guten\s*$/i.test(S.text.slice(0, m.index))) return null; // „Guten Morgen“
        const off = { heute: 0, morgen: 1, übermorgen: 2, gestern: -1 }[w];
        return { due: addDays(T, off), dp: m.groups.dp ? m.groups.dp.toLowerCase().replace("ue", "ü") : null };
      }, 1),
    );
    // in 3 Tagen / in einer Woche / in 2 Monaten
    c.push(
      ...S.find(R(`${B}${PRE}in\\s+(?<n>\\d{1,3}|${NUM_ALT})\\s+(?<u>tagen?|tag|wochen?|monaten?|monat|jahren?|jahr)${E}`), "date", (m) => {
        const n = num(m.groups.n);
        const u = m.groups.u.toLowerCase();
        if (!Number.isFinite(n)) return null;
        if (u.startsWith("tag")) return { due: addDays(T, n) };
        if (u.startsWith("woche")) return { due: addDays(T, 7 * n) };
        if (u.startsWith("monat")) return { due: addMonths(T, n) };
        return { due: addMonths(T, 12 * n) };
      }),
    );
    // (Anfang/Mitte/Ende) nächste(r) Woche, übernächste Woche
    c.push(
      ...S.find(R(`${B}${PRE}(?:(?<pos>anfang|mitte|ende)\\s+(?:der\\s+)?)?(?<ue>${UE}ber)?${NEXT}\\s+woche${E}`), "date", (m) => {
        const start = weekBase(m.groups.ue ? 2 : 1);
        const wd = { anfang: 1, mitte: 3, ende: 5 }[(m.groups.pos || "anfang").toLowerCase()];
        return { due: inWeek(start, wd) };
      }),
    );
    // Ende der Woche / diese Woche → Freitag; Wochenmitte → Mittwoch
    c.push(
      ...S.find(R(`${B}${PRE}(?<w>ende\\s+(?:der|dieser)\\s+woche|ende\\s+woche|diese\\s+woche|wochenmitte|mitte\\s+der\\s+woche)${E}`), "date", (m) => {
        const d = inWeek(weekBase(0), /mitte/i.test(m.groups.w) ? 3 : 5);
        return { due: d < T ? T : d };
      }),
    );
    // Wochenende → nächster Samstag (am Wochenende selbst: heute)
    c.push(
      ...S.find(R(`${B}${PRE}(?:${UE}bers?\\s+|(?<mod>${NEXT}|${UE}bern${AE}chste[ns]?|diese[ns]?)\\s+)?wochenende${E}`), "date", (m) => {
        const mod = (m.groups.mod || "").toLowerCase();
        if (/^(ü|ue)bern/.test(mod)) return { due: inWeek(weekBase(2), 6) };
        if (/^n/.test(mod)) return { due: inWeek(weekBase(1), 6) };
        const wd = weekday(T);
        return { due: wd === 6 || wd === 0 ? T : nextWeekday(6) };
      }),
    );
    // Monatsende, Monatsmitte, (Anfang/Mitte/Ende) nächsten Monat(s), Jahresende
    c.push(
      ...S.find(R(`${B}${PRE}(?:monatsende|ende\\s+(?:des|dieses|diesen)\\s+monats|ende\\s+monat|monatsletzte[nr]?)${E}`), "date", () => ({ due: endOfMonth(T) })),
      ...S.find(R(`${B}${PRE}(?:monatsmitte|mitte\\s+(?:des|dieses|diesen)\\s+monats|mitte\\s+monat)${E}`), "date", () => {
        const d = fromParts(+T.slice(0, 4), +T.slice(5, 7), 15);
        return { due: d >= T ? d : addMonths(d, 1) };
      }),
      ...S.find(R(`${B}${PRE}(?:(?<pos>anfang|mitte|ende)\\s+(?:des\\s+)?)?(?:${NEXT}|n${AE}chster)\\s+monats?${E}`), "date", (m) => {
        const first = addMonths(fromParts(+T.slice(0, 4), +T.slice(5, 7), 1), 1);
        const pos = (m.groups.pos || "anfang").toLowerCase();
        return { due: pos === "ende" ? endOfMonth(first) : pos === "mitte" ? addDays(first, 14) : first };
      }),
      ...S.find(R(`${B}${PRE}(?:jahresende|ende\\s+(?:des|dieses)\\s+jahres)${E}`), "date", () => ({ due: `${T.slice(0, 4)}-12-31` })),
    );
    // KW 42
    c.push(
      ...S.find(R(`${B}${PRE}(?:kw|kalenderwoche)\\s*(?<w>\\d{1,2})${E}`), "date", (m) => {
        const w = +m.groups.w;
        if (w < 1 || w > 53) return null;
        let y = +T.slice(0, 4);
        for (let i = 0; i < 2; i++, y++) {
          const mon = isoWeekStart(y, w);
          if (isoWeek(mon) === w && addDays(mon, 6) >= T) return { due: mon };
        }
        return null;
      }),
    );
    // Wochentage: „Freitag“, „am Fr“, „nächsten Montag“, „diesen Donnerstag“
    c.push(
      ...S.find(R(`${B}${PRE}(?:(?<mod>${UE}bern${AE}chste[nrs]?|${NEXT}|diese[nrs]?)\\s+)?(?<wd>${WD_ALT})(?<dot>\\.)?${E}`), "date", (m) => {
        const raw = m.groups.wd;
        const wd = WD_MAP[raw.toLowerCase()];
        const mod = (m.groups.mod || "").toLowerCase();
        const pre = (m.groups.pre || "").trim();
        if (raw.length <= 2) {
          // Abkürzungen nur mit Präposition/Zusatz, oder groß geschrieben am Ende bzw. vor Datum/Uhrzeit („Webinar Do 19 Uhr“)
          const end = m.index + m[0].length;
          const ok = pre || mod || (isCap(raw) && (S.restIsEmpty(end) || /^\s*\d/.test(S.work.slice(end))));
          if (!ok) return null;
        }
        if (/^(ü|ue)bern/.test(mod)) return { due: inWeek(weekBase(2), wd) };
        if (/^n/.test(mod)) return { due: inWeek(weekBase(1), wd) }; // „nächsten Freitag“ = Freitag der nächsten Kalenderwoche
        return { due: nextWeekday(wd) };
      }),
    );
    // 2026-10-15
    c.push(...S.find(R(`${B}${PRE}(?<y>\\d{4})-(?<m>\\d{2})-(?<d>\\d{2})${E}`), "date", (m) => (isISO(`${m.groups.y}-${m.groups.m}-${m.groups.d}`) ? { due: `${m.groups.y}-${m.groups.m}-${m.groups.d}` } : null)));
    // 15.10. / 15.10.26 / 15.10.2026
    c.push(
      ...S.find(R(`(?<![\\p{L}\\p{N}.,:/])${PRE}(?<d>\\d{1,2})\\.(?<m>\\d{1,2})\\.(?<y>\\d{4}|\\d{2})?(?![\\p{L}\\p{N}]|[.,:]\\p{N})(?!\\s*uhr)`), "date", (m) => {
        const due = futureYear(+m.groups.d, +m.groups.m, fullYear(m.groups.y));
        return due ? { due } : null;
      }),
    );
    // „am 15.10“ (ohne Schlusspunkt nur mit Präposition – „Version 1.5“ bleibt Text)
    c.push(
      ...S.find(R(`${B}${PRE_STRICT}(?<d>\\d{1,2})\\.(?<m>\\d{1,2})(?![\\p{L}\\p{N}.:])(?!\\s*uhr)`), "date", (m) => {
        const due = futureYear(+m.groups.d, +m.groups.m);
        return due ? { due } : null;
      }),
    );
    // 15. Oktober / 15 Okt / 1. Januar 2027
    c.push(
      ...S.find(R(`${B}${PRE}(?<d>\\d{1,2})\\.?\\s*(?<mn>${MONTH_ALT})\\.?(?:\\s+(?<y>\\d{4}))?${E}`), "date", (m) => {
        const due = futureYear(+m.groups.d, MONTH_MAP[m.groups.mn.toLowerCase()], m.groups.y ? +m.groups.y : undefined);
        return due ? { due } : null;
      }),
    );
    // „am 15.“ → nächster 15. (dieser oder kommender Monat)
    c.push(
      ...S.find(R(`${B}${PRE_STRICT}(?<d>\\d{1,2})\\.(?!\\p{N})`), "date", (m) => {
        const d = +m.groups.d;
        if (d < 1 || d > 31) return null;
        let base = fromParts(+T.slice(0, 4), +T.slice(5, 7), 1);
        for (let i = 0; i < 13; i++, base = addMonths(base, 1)) {
          const p = ymd(base);
          if (d <= daysInMonth(p[0], p[1])) {
            const iso = fromParts(p[0], p[1], d);
            if (iso >= T) return { due: iso };
          }
        }
        return null;
      }),
    );
    date = take(c, "date");
  }

  // 6) Uhrzeit
  let time = null;
  {
    const NOT_UNIT = `(?!\\s*(?:tage?n?|wochen?|monate?n?|jahre?n?|min(?:uten?)?|std|stunden?|h|%|€|euro|prozent|st${UE}ck|mal|leute|personen|seiten|folien)${E})`;
    const mk = (h, mi, o = {}) => {
      if (!Number.isInteger(h) || !Number.isInteger(mi) || h < 0 || h > 23 || mi < 0 || mi > 59) return null;
      return { h, mi, ...o };
    };
    const c = [
      // 14–15 Uhr → 14:00 und 60 Min. Dauer
      ...S.find(R(`${B}(?:von\\s+|zwischen\\s+)?(?<h1>\\d{1,2})(?:[:.](?<m1>\\d{2}))?(?<u1>\\s*uhr)?\\s*(?:-|–|bis|und)\\s*(?<h2>\\d{1,2})(?:[:.](?<m2>\\d{2}))?(?<u2>\\s*uhr)?${E}`), "time", (m) => {
        const g = m.groups;
        if (!g.u1 && !g.u2 && !(g.m1 && g.m2)) return null; // „Folien 3-7“ ist keine Uhrzeit
        const a = mk(+g.h1, +(g.m1 || 0), { exact: !!g.m1, zero: /^0/.test(g.h1) });
        const b = mk(+g.h2, +(g.m2 || 0));
        if (!a || !b) return null;
        return { ...a, until: b };
      }),
      // um 9 / gegen 10 / um 14:30 / ab 8 Uhr
      ...S.find(R(`${B}(?<pre>um|gegen|ab|bis|so\\s+um|ca\\.?\\s+um)\\s+(?<h>\\d{1,2})(?:[:.](?<m>\\d{2}))?(?<uhr>\\s*uhr)?${E}${NOT_UNIT}`), "time", (m) => {
        const g = m.groups;
        if (/^(ab|bis)$/i.test(g.pre) && !g.m && !g.uhr) return null; // „bis 5“ ist zu unsicher
        return mk(+g.h, +(g.m || 0), { exact: !!g.m, zero: /^0/.test(g.h) });
      }),
      // 9 Uhr / 14.30 Uhr / 9:30 Uhr
      ...S.find(R(`${B}(?<h>\\d{1,2})(?:[:.](?<m>\\d{2}))?\\s*uhr${E}`), "time", (m) => mk(+m.groups.h, +(m.groups.m || 0), { exact: !!m.groups.m, zero: /^0/.test(m.groups.h) })),
      // 9:30 / 14:30 (Doppelpunkt steht für sich)
      ...S.find(R(`(?<![\\p{L}\\p{N}:.,])(?<h>\\d{1,2}):(?<m>\\d{2})(?![\\p{N}:])(?:\\s*h(?![\\p{L}]))?`), "time", (m) => mk(+m.groups.h, +m.groups.m, { exact: true, zero: /^0/.test(m.groups.h) })),
      // halb 3 / viertel nach 3 / viertel vor 3 / dreiviertel 3
      ...S.find(R(`${B}(?:um\\s+|gegen\\s+)?(?<k>halb|viertel\\s+nach|viertel\\s+vor|dreiviertel|drei\\s+viertel)\\s+(?<h>\\d{1,2}|${NUM_ALT})(?:\\s*uhr)?${E}`), "time", (m) => {
        const k = m.groups.k.toLowerCase().replace(/\s+/g, " ");
        const h = num(m.groups.h);
        if (!Number.isInteger(h) || h < 1 || h > 24) return null;
        if (k === "viertel nach") return mk(h % 24, 15);
        const hb = h - 1 === 0 ? 12 : h - 1; // „halb eins“ = 12:30
        return mk(hb, k === "halb" ? 30 : 45);
      }),
      // in 30 Min. / in 2 Std. / in einer halben Stunde → heute, aufgerundet auf 5 Minuten
      ...S.find(R(`${B}in\\s+(?<n>\\d{1,3}|${NUM_ALT})?\\s*(?<half>halben?\\s+)?(?<u>min\\.?|minuten?|std\\.?|stunden?|h)${E}`), "time", (m) => {
        const u = unitMinutes(m.groups.u);
        let n = m.groups.n === undefined ? (m.groups.half ? 1 : NaN) : num(m.groups.n);
        if (m.groups.half) n *= 0.5;
        if (!Number.isFinite(n) || !Number.isFinite(u) || n <= 0) return null;
        const at = new Date(now.getTime() + n * u * 60000);
        at.setSeconds(0, 0);
        const r = at.getMinutes() % 5;
        if (r) at.setMinutes(at.getMinutes() + 5 - r);
        return mk(at.getHours(), at.getMinutes(), { exact: true, relDue: toISO(at) });
      }),
    ];
    // Nackte Zahl direkt nach dem Datum ist eine Stunde („morgen 9“, „Freitag 14“) – aber nur am Ende oder vor Steuer-Tokens
    if (date) {
      const rest = S.work.slice(date.end);
      const bm = /^\s+(\d{1,2})(?::(\d{2}))?(?=\s*$|\s+[#!@~*(]|\s*[,;]\s)/u.exec(rest);
      if (bm) {
        const v = mk(+bm[1], +(bm[2] || 0), { exact: !!bm[2], zero: /^0/.test(bm[1]) });
        const lead = bm[0].length - bm[0].trimStart().length;
        if (v) c.push({ type: "time", start: date.end + lead, end: date.end + bm[0].length, value: v, prio: 9 });
      }
    }
    time = take(c, "time");
  }

  // 7) Tageszeiten (morgens, mittags, abends, am Abend …)
  let dp = date?.value?.dp || rep?.dp || null;
  {
    const c = S.find(R(`${B}(?<pre>am\\s+|in\\s+der\\s+|gegen\\s+)?(?<dp>morgens|vormittags|mittags|nachmittags|abends|nachts|morgen|vormittag|mittag|nachmittag|abend|nacht|fr${UE}h)${E}`), "time", (m) => {
      const w = m.groups.dp.toLowerCase().replace("ue", "ü");
      if (!/s$/.test(w) && !m.groups.pre) return null; // „Abend“ allein / „früh“ allein bleibt Text
      if (w === "früh" && !/in\s+der/i.test(m.groups.pre || "")) return null;
      return { dp: w.replace(/s$/, "") };
    });
    const t = take(c, "time");
    if (t) dp = t.value.dp;
  }
  const DP = {
    früh: { am: true, def: dayStartMin }, morgen: { am: true, def: dayStartMin }, vormittag: { am: true, def: 600 }, mittag: { def: 720 },
    nachmittag: { pm: true, def: 900 }, abend: { pm: true, def: 1140 }, nacht: { am: true, def: 1320 },
  }[dp] || null;

  // Uhrzeit festlegen (PM-Regel: 1–6 Uhr ohne Minuten und ohne „morgens“ → nachmittags, „um 3“ = 15:00)
  if (time) {
    const v = time.value;
    let { h } = v;
    const { mi } = v;
    if (!v.relDue) {
      if (!v.zero && !v.exact && h >= 1 && h <= 6 && !DP?.am) h += 12;
      else if (DP?.pm && h < 12) h += 12;
    }
    res.time = toTime(h * 60 + mi);
    if (v.until) {
      let h2 = v.until.h;
      if (h2 < h && h2 + 12 > h && h2 + 12 <= 23) h2 += 12;
      const dur = h2 * 60 + v.until.mi - (h * 60 + mi);
      if (dur > 0 && res.est === null) res.est = dur;
    }
  } else if (DP) {
    res.time = toTime(DP.def);
  }
  const timeMin = res.time ? parseTime(res.time) : null;

  // 8) Priorität („!“, „!!“, „!!!“, „!hoch“, „dringend“, „p1“) – die höchste gewinnt
  {
    const c = [
      ...S.find(/(?<![^\s\u0000])(!{1,3})(?![^\s\u0000])/gu, "prio", (m) => ({ p: m[1].length })),
      ...S.find(/^(\s*)(!{1,3})(?=\p{L})/gu, "prio", (m) => ({ p: m[2].length, skip: m[1].length })),
      ...S.find(/(?<=[\p{L}\p{N})])(!{2,3})(?![\p{L}\p{N}!])/gu, "prio", (m) => ({ p: m[1].length })),
      ...S.find(R(`(?<![\\p{L}\\p{N}!])!(?<w>hoch|wichtig|dringend|high|mittel|medium|niedrig|low)${E}`), "prio", (m) => ({ p: { hoch: 3, wichtig: 3, dringend: 3, high: 3, mittel: 2, medium: 2, niedrig: 1, low: 1 }[m.groups.w.toLowerCase()] })),
      ...S.find(R(`${B}(?:dringend|wichtig|asap)${E}`), "prio", () => ({ p: 3 })),
      ...S.find(R(`${B}p(?<n>[1-3])${E}`), "prio", (m) => ({ p: 4 - +m.groups.n })),
    ];
    for (const t of takeAll(c, "prio")) res.prio = Math.max(res.prio, t.value.p);
  }

  // 9) Tasche (#Name, #Name/Abschnitt) und Tags (#wort ohne Taschentreffer, @kontext)
  {
    const c = S.find(/(?<![\p{L}\p{N}#&/])#(?<n>\p{L}[\p{L}\p{N}_\-.]*)(?:\/(?<s>[\p{L}\p{N}][\p{L}\p{N}_\-.]*))?/gu, "tag", (m) => {
      const name = m.groups.n.replace(/[.\-]+$/, "");
      const section = m.groups.s ? m.groups.s.replace(/[.\-]+$/, "") : "";
      return { name, section, trim: m.groups.s ? m.groups.s.length - section.length : m.groups.n.length - name.length };
    });
    for (const t of Scanner.resolve(c)) {
      if (S.mask.slice(t.start, t.end).some(Boolean)) continue; // schon von einem Mehrwort-Namen verschluckt
      if (!res.bag) {
        const b = matchBag(t.value.name, bags);
        if (b) {
          // Mehrwortnamen: „#Zahlungen & Stripe“ wird ganz verschluckt, wenn es den Namen exakt ergibt
          let end = t.end;
          if (!t.value.section && normName(b.name) !== normName(t.value.name)) {
            const re = /^\s+([^\s\u0000]+)/u;
            let acc = t.value.name, pos = t.end;
            for (let i = 0; i < 6; i++) {
              const w = re.exec(S.work.slice(pos));
              if (!w) break;
              acc += " " + w[1];
              pos += w[0].length;
              const n = normName(acc);
              if (n === normName(b.name)) {
                end = pos;
                break;
              }
              if (!normName(b.name).startsWith(n)) break;
            }
          }
          S.take({ ...t, end }, "bag");
          res.bag = b.id ?? null;
          res.bagName = b.name;
          if (t.value.section) {
            const want = normName(t.value.section);
            const sec = (b.sections || []).find((s) => normName(s) === want) || (b.sections || []).find((s) => normName(s).startsWith(want));
            res.section = sec || t.value.section;
          }
          continue;
        }
      }
      S.take(t, "tag");
      res.tags.push(t.value.name + (t.value.section ? "/" + t.value.section : ""));
    }
    const at = S.find(/(?<![^\s\u0000(])@(?<n>\p{L}[\p{L}\p{N}_\-]*)/gu, "tag", (m) => {
      const name = m.groups.n.replace(/[\-]+$/, "");
      return { name, trim: m.groups.n.length - name.length };
    });
    for (const t of takeAll(at, "tag")) res.tags.push(t.value.name);
    const seen = new Set();
    res.tags = res.tags.filter((x) => {
      const k = x.toLowerCase();
      return seen.has(k) ? false : (seen.add(k), true);
    });
  }

  // 10) Irgendwann
  {
    const c = S.find(R(`${B}(?:irgendwann(?:\\s+mal)?|sp${AE}ter\\s+mal|eines\\s+tages|someday|bei\\s+gelegenheit)${E}`), "someday", () => ({}));
    if (takeAll(c, "someday").length) res.someday = true;
  }

  // ---------- Ableitungen ----------
  if (date) res.due = date.value.due;
  else if (time?.value?.relDue) res.due = time.value.relDue;
  if (!res.due && rep) {
    // Wiederholung ohne Datum → erster Termin ab heute (ist er heute schon vorbei, der nächste)
    const passed = (iso) => iso === T && timeMin !== null && timeMin <= nowMin;
    let d;
    if (rep.wd !== undefined) {
      d = nextWeekday(rep.wd, false);
      if (passed(d)) d = nextWeekday(rep.wd, true);
    } else if (rep.md !== undefined) {
      d = futureMonthDay(T, rep.md);
      if (passed(d)) d = nextOccurrence(d, "monthly", T, rep.md);
    } else {
      d = rep.repeat === "weekdays" && isWeekend(T) ? nextOccurrence(T, "weekdays", T) : T;
      if (passed(d)) d = nextOccurrence(d, rep.repeat, T);
    }
    res.due = d;
  }
  if (!res.due && timeMin !== null) res.due = timeMin > nowMin ? T : addDays(T, 1); // „9 Uhr“ ohne Datum → heute oder morgen
  if (res.due) res.someday = false; // ein Datum gewinnt gegen „irgendwann“
  if (wm) {
    const startW = main.length - wm[1].length;
    let endW = main.length;
    for (const tk of S.tokens) if (tk.start >= startW && tk.start < endW) endW = tk.start;
    res.waiting = main.slice(startW, endW).replace(/[\s,;:–-]+$/u, "").trim();
  }

  // Titel: Tokens entfernen, Leerraum zusammenfassen, Satzzeichen an den Rändern kappen
  const keep = [];
  for (let i = 0; i < main.length; i++) keep.push(S.mask[i] === 2 ? " " : main[i]);
  let title = keep.join("").replace(/\s+/g, " ").replace(/\s+([,;:.!?])/g, "$1").replace(/^[\s,;:\-–—]+|[\s,;:\-–—]+$/g, "").trim();
  res.title = title || original.trim();
  res.tokens = S.tokens.sort((a, b) => a.start - b.start);
  return res;
}

// Nächster Tag mit Monatstag md ab heute (überspringt Monate ohne diesen Tag)
function futureMonthDay(T, md) {
  let base = `${T.slice(0, 7)}-01`;
  for (let i = 0; i < 13; i++, base = addMonths(base, 1)) {
    const p = ymd(base);
    if (md <= daysInMonth(p[0], p[1])) {
      const iso = fromParts(p[0], p[1], md);
      if (iso >= T) return iso;
    }
  }
  return T;
}
