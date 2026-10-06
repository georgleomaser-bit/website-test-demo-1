// Arbeitstaschen – Oberflächen-Kern: gemeinsamer Zustand, Ereignis-Delegation, DOM-Abgleich und kleine Helfer
import * as store from "../store.js";
import * as dates from "../dates.js";
import { COLORS } from "../config.js";
import { esc } from "../util.js";

// ---------- Zustand der Oberfläche ----------
export const app = {
  route: { view: "heute", id: null, tab: null },
  wide: false, // ≥ 760 px: Seitenleiste statt Tab-Leiste
  inspector: false, // ≥ 1100 px: Aufgabe als Inspektor-Spalte
  selected: null, // im Inspektor geöffnete Aufgabe
  ai: false, // KI-Projektmanager verfügbar und eingeschaltet
  server: null, // erkannter Server (Sync, Push, KI)
  now: new Date(),
  booted: false,
  // werden von app.js gesetzt
  render: () => {},
  go: (_hash) => {},
  back: () => {},
};

// ---------- Ereignis-Delegation (CSP-sicher, keine Inline-Handler) ----------
const H = { click: {}, input: {}, change: {}, keydown: {}, menu: {}, submit: {} };
const ATTR = { click: "data-act", input: "data-input", change: "data-change", keydown: "data-key-act", menu: "data-menu", submit: "data-submit" };

export function on(type, map) {
  Object.assign(H[type], map);
}

export function handle(type, e) {
  const attr = ATTR[type];
  const el = e.target?.closest?.(`[${attr}]`);
  if (!el || el.disabled || el.getAttribute("aria-disabled") === "true") return false;
  const fn = H[type][el.getAttribute(attr)];
  if (!fn) return false;
  try {
    fn(el, e);
  } catch (err) {
    console.error(err);
  }
  return true;
}

export function hasMenu(name) {
  return !!H.menu[name];
}

// Kontextmenü für ein Element mit data-menu öffnen (pos = { x, y } oder { el })
export function runMenu(el, pos = {}) {
  const fn = H.menu[el?.getAttribute?.("data-menu")];
  if (!fn) return false;
  try {
    fn(el, pos);
  } catch (err) {
    console.error(err);
  }
  return true;
}

// ---------- Kleine Vorlieben nur für dieses Gerät (eingeklappte Bereiche, Hinweise) ----------
const PKEY = "taschen-ui";
export const prefs = (() => {
  try {
    return JSON.parse(localStorage.getItem(PKEY)) || {};
  } catch (_) {
    return {};
  }
})();

export function setPref(k, v) {
  if (v === undefined) delete prefs[k];
  else prefs[k] = v;
  try {
    localStorage.setItem(PKEY, JSON.stringify(prefs));
  } catch (_) {
    /* nur für diese Sitzung */
  }
}

export function isCollapsed(key, def = false) {
  const c = prefs.collapsed || {};
  return key in c ? !!c[key] : def;
}

export function toggleCollapsed(key, def = false) {
  const c = { ...(prefs.collapsed || {}) };
  c[key] = !isCollapsed(key, def);
  setPref("collapsed", c);
  app.render();
}

// ---------- DOM-Abgleich: nur ändern, was sich geändert hat (Fokus, Scroll und Animationen bleiben) ----------
export function render(el, html) {
  if (!el) return;
  if (el._html === html) return;
  el._html = html;
  const t = document.createElement("template");
  t.innerHTML = html;
  if (!el.firstChild) {
    el.append(t.content);
    return;
  }
  morphChildren(el, t.content);
}

const keyOf = (n) => (n.nodeType === 1 ? n.getAttribute("data-key") : null);
const same = (a, b) => a.nodeType === b.nodeType && a.nodeName === b.nodeName && (a.nodeType !== 1 || (a.getAttribute("type") === b.getAttribute("type") && keyOf(a) === keyOf(b)));

function morphChildren(a, b) {
  const keyed = new Map();
  for (let n = a.firstChild; n; n = n.nextSibling) {
    const k = keyOf(n);
    if (k) keyed.set(k, n);
  }
  let cur = a.firstChild;
  let nb = b.firstChild;
  while (nb) {
    const nextB = nb.nextSibling;
    const k = keyOf(nb);
    let m = null;
    if (k) {
      m = keyed.get(k) || null;
      if (m) {
        keyed.delete(k);
        if (!same(m, nb)) m = null;
      }
    } else if (cur && !keyOf(cur) && same(cur, nb)) m = cur;
    if (m) {
      if (m === cur) cur = cur.nextSibling;
      else a.insertBefore(m, cur);
      patch(m, nb);
    } else {
      a.insertBefore(nb, cur);
    }
    nb = nextB;
  }
  while (cur) {
    const nx = cur.nextSibling;
    a.removeChild(cur);
    cur = nx;
  }
}

function patch(a, b) {
  if (a.nodeType !== 1) {
    if (a.nodeValue !== b.nodeValue) a.nodeValue = b.nodeValue;
    return;
  }
  if (a.hasAttribute("data-hold")) return; // gerade gewischt/gezogen – nicht anfassen
  const focused = a === document.activeElement;
  for (const at of [...a.attributes]) if (!b.hasAttribute(at.name)) a.removeAttribute(at.name);
  for (const at of [...b.attributes]) if (a.getAttribute(at.name) !== at.value) a.setAttribute(at.name, at.value);
  const tag = a.nodeName;
  if (tag === "INPUT") {
    if (a.type === "checkbox" || a.type === "radio") a.checked = b.hasAttribute("checked");
    else if (!focused && a.type !== "file") {
      const v = b.getAttribute("value") ?? "";
      if (a.value !== v) a.value = v;
    }
    return;
  }
  if (tag === "TEXTAREA") {
    if (!focused && a.value !== b.textContent) a.value = b.textContent;
    return;
  }
  if (a.hasAttribute("data-morph-skip")) return;
  morphChildren(a, b);
  if (tag === "SELECT" && !focused) {
    const sel = b.querySelector("option[selected]");
    const v = sel ? sel.getAttribute("value") ?? sel.textContent : a.options[0]?.value;
    if (v != null && a.value !== v) a.value = v;
  }
}

// ---------- Datum & Zeit ----------
export const today = () => dates.todayISO(app.now);
export const tomorrow = () => dates.addDays(today(), 1);

// nächster Samstag (heute zählt nicht, außer es ist schon Wochenende → heute)
export function weekendISO() {
  const t = today();
  const wd = dates.weekday(t);
  if (wd === 6 || wd === 0) return t;
  return dates.addDays(t, 6 - wd);
}

export function nextWeekISO() {
  const p = store.get().profile;
  const start = dates.startOfWeek(today(), p.weekStart ?? 1);
  return dates.addDays(start, 7);
}

export function relTime(ms) {
  if (!ms) return "";
  const s = Math.round((Date.now() - ms) / 1000);
  if (s < 45) return "gerade eben";
  const m = Math.round(s / 60);
  if (m < 60) return `vor ${m} Min.`;
  const h = Math.round(m / 60);
  if (h < 24) return `vor ${h} Std.`;
  const d = Math.round(h / 24);
  if (d === 1) return "gestern";
  if (d < 7) return `vor ${d} Tagen`;
  try {
    return dates.relDay(dates.toISO(new Date(ms)), app.now);
  } catch (_) {
    return new Date(ms).toLocaleDateString("de-DE");
  }
}

export function clockStr(ms) {
  return new Date(ms).toLocaleTimeString("de-DE", { hour: "numeric", minute: "2-digit" });
}

// Kalenderwoche nach ISO 8601
export function isoWeek(iso) {
  const d = dates.fromISO(iso);
  const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  const day = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - day);
  const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  return Math.ceil(((t - y0) / 86400000 + 1) / 7);
}

// ---------- Farben ----------
export function colorVars(name) {
  const c = COLORS[name] || COLORS.gray;
  return `--bl:${c[0]};--bd:${c[1]}`;
}

export function bagVars(bag) {
  return colorVars(bag ? bag.color : "gray");
}

// ---------- Texte ----------
export function plural(n, one, many) {
  return `${n} ${n === 1 ? one : many}`;
}

export function hostOf(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch (_) {
    return "";
  }
}

// Treffer hervorheben (Text ist bereits roh – wird hier escaped)
export function norm(s) {
  return String(s || "")
    .toLowerCase()
    .replace(/ä/g, "ae")
    .replace(/ö/g, "oe")
    .replace(/ü/g, "ue")
    .replace(/ß/g, "ss");
}

export function mark(text, q) {
  const s = String(text || "");
  if (!q) return esc(s);
  const i = s.toLowerCase().indexOf(q.toLowerCase());
  if (i < 0) return esc(s);
  return esc(s.slice(0, i)) + "<mark>" + esc(s.slice(i, i + q.length)) + "</mark>" + esc(s.slice(i + q.length));
}

// ---------- Sicherheitsnetz für Berechnungen anderer Module ----------
export function safe(fn, fallback) {
  try {
    const v = fn();
    return v === undefined ? fallback : v;
  } catch (e) {
    console.warn("[taschen]", e);
    return fallback;
  }
}

// ---------- Plattform ----------
export const isTouch = () => matchMedia("(pointer: coarse)").matches;
export const reducedMotion = () => matchMedia("(prefers-reduced-motion: reduce)").matches;
export const isStandalone = () => matchMedia("(display-mode: standalone)").matches || navigator.standalone === true;
export const isMacUA = () => /Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints < 2;
export const modKey = () => (isMacUA() ? "⌘" : "Strg+");

// Adresse der App (für Kalender-Links und Kurzbefehle)
export const appUrl = () => new URL("./", location.href).href;

// Dateiname aus Text
export const slug = (s) => String(s || "export").toLowerCase().replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/ß/g, "ss").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40) || "export";
