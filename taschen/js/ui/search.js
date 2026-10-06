// Arbeitstaschen – Suche & Befehle (⌘K): Spotlight-Panel für Aufgaben, Taschen, Notizen, Links, Dateien und Befehle
import * as store from "../store.js";
import * as dates from "../dates.js";
import * as remind from "../remind.js";
import * as sync from "../sync.js";
import { esc } from "../util.js";
import { icon } from "./icons.js";
import { app, on, safe, norm, mark, bagVars, today, isStandalone, modKey } from "./core.js";
import { openSheet, getSheet, closeSheet } from "./sheet.js";
import { toast, toastError, haptic } from "./fx.js";
import { openTask } from "./task.js";
import { openCapture } from "./capture.js";
import { openBagEditor } from "./bags.js";
import { openNote, openLink } from "./bag.js";
import { openPlanDay, exportCalendar, enableNotify } from "./today.js";
import { openInstallHelp } from "./install.js";
import { askAI } from "./aiui.js";

let st = null; // { q, sel, smart }
let flat = [];

const SMART = [
  { id: "wichtig", label: "Wichtig", icon: "flag", tone: "red", test: (t) => !t.done && t.prio === 3 },
  { id: "geplant", label: "Geplant", icon: "calendar", tone: "blue", test: (t) => !t.done && !!t.due },
  { id: "wartet", label: "Wartet", icon: "hourglass", tone: "purple", test: (t) => !t.done && !!t.waiting },
  { id: "ohne", label: "Ohne Datum", icon: "tray", tone: "gray", test: (t) => !t.done && !t.due && !t.someday },
  { id: "irgendwann", label: "Irgendwann", icon: "moon", tone: "indigo", test: (t) => !t.done && t.someday },
  { id: "erledigt", label: "Logbuch", icon: "checkCircle", tone: "green", test: (t) => !!t.done },
];

// ---------- Öffnen ----------
export function openSearch(q = "") {
  st = { q, sel: 0, smart: null };
  const ex = getSheet("search");
  if (ex) {
    ex.refresh();
    ex.body.querySelector(".spot-in")?.focus();
    return;
  }
  openSheet({ key: "search", label: "Suche und Befehle", cls: "spot", render: view, onClose: () => (st = null) });
}

// ---------- Befehle ----------
function commands() {
  const s = store.get();
  const dark = document.documentElement.dataset.theme === "dark" || (!document.documentElement.dataset.theme && matchMedia("(prefers-color-scheme: dark)").matches);
  const sy = safe(() => sync.status(), { enabled: false });
  const perm = safe(() => remind.permission(), "unsupported");
  return [
    { label: "Neue Aufgabe", icon: "plus", tone: "blue", kbd: "N", run: () => openCapture() },
    { label: "Neue Tasche", icon: "bag", tone: "orange", run: () => openBagEditor() },
    { label: "Heute", icon: "sun", tone: "orange", kbd: "1", run: () => app.go("#heute") },
    { label: "Demnächst", icon: "calendar", tone: "red", kbd: "2", run: () => app.go("#demnaechst") },
    { label: "Eingang", icon: "tray", tone: "blue", kbd: "3", run: () => app.go("#eingang") },
    { label: "Taschen", icon: "bag", tone: "indigo", kbd: "4", run: () => app.go("#taschen") },
    { label: "Wochenrückblick", icon: "chart", tone: "purple", kbd: "5", run: () => app.go("#rueckblick") },
    { label: "Tag planen", icon: "sunrise", tone: "orange", run: () => openPlanDay() },
    { label: "Neue Notiz", icon: "note", tone: "yellow", run: () => openNote(null, { bag: app.route.view === "tasche" ? app.route.id : null }) },
    { label: "Neuer Link", icon: "link", tone: "teal", run: () => openLink(null, { bag: app.route.view === "tasche" ? app.route.id : null }) },
    { label: "Einstellungen", icon: "gear", tone: "gray", kbd: ",", run: () => app.go("#einstellungen") },
    { label: dark ? "Hell-Modus" : "Dunkelmodus", icon: dark ? "sun" : "moon", tone: "indigo", run: () => import("./settings.js").then((m) => m.setTheme(dark ? "light" : "dark")) },
    { label: "Zum Kalender hinzufügen", icon: "calendarPlus", tone: "red", run: () => exportCalendar({ daily: true }) },
    { label: "Backup exportieren", icon: "download", tone: "green", run: () => import("./settings.js").then((m) => m.doBackup()) },
    sy.enabled ? { label: "Jetzt synchronisieren", icon: "sync", tone: "cyan", run: () => sync.syncNow().then(() => toast("Synchronisiert", { icon: "sync" })).catch((e) => toastError(e, "Sync")) } : { label: "Sync auf allen Geräten einrichten", icon: "devices", tone: "cyan", run: () => app.go("#einstellungen/sync") },
    perm === "default" ? { label: "Mitteilungen erlauben", icon: "bell", tone: "red", run: () => enableNotify() } : null,
    !isStandalone() ? { label: "Als App installieren", icon: "download", tone: "blue", run: () => openInstallHelp() } : null,
    safe(() => store.canUndo(), false) ? { label: "Rückgängig", icon: "undo", tone: "gray", kbd: modKey() + "Z", run: () => { const l = store.undo(); toast(l ? `Rückgängig: ${l}` : "Nichts zum Rückgängigmachen", { icon: "undo" }); } } : null,
    ...store.bags().map((b) => ({ label: `${b.emoji} ${b.name}`, sub: "Tasche öffnen", bag: b, run: () => app.go("#tasche/" + b.id) })),
  ].filter(Boolean);
  void s;
}

// ---------- Suche ----------
function score(text, q) {
  const t = norm(text);
  if (!t || !q) return 0;
  if (t.startsWith(q)) return 3;
  if (t.includes(" " + q) || t.includes("-" + q) || t.includes("#" + q)) return 2;
  return t.includes(q) ? 1 : 0;
}

function search(q) {
  const n = norm(q.trim());
  const out = { cmds: [], bags: [], tasks: [], notes: [], links: [], files: [] };
  if (!n) return out;
  out.cmds = commands().filter((c) => !c.bag && norm(c.label).includes(n)).slice(0, 4);
  out.bags = store.bags().map((b) => [b, Math.max(score(b.name, n) * 2, score(b.goal, n))]).filter((x) => x[1]).sort((a, b) => b[1] - a[1]).slice(0, 5).map((x) => x[0]);
  out.tasks = store
    .tasks()
    .map((t) => [t, Math.max(score(t.title, n) * 2, score(t.notes, n), score((t.tags || []).join(" "), n), score(t.waiting, n)) + (t.done ? 0 : 1.5) + (t.updated || 0) / 1e14])
    .filter((x) => x[1] >= 1.5 + 0.0001 || (x[0].done && x[1] > 0.0001))
    .filter((x) => x[1] - (x[0].done ? 0 : 1.5) - (x[0].updated || 0) / 1e14 > 0)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10)
    .map((x) => x[0]);
  out.notes = store.notes().filter((x) => score(x.title, n) || score(x.body, n)).slice(0, 5);
  out.links = store.links().filter((x) => score(x.title, n) || score(x.url, n)).slice(0, 5);
  out.files = store.files().filter((x) => score(x.name, n)).slice(0, 5);
  return out;
}

function snippet(text, q) {
  const s = String(text || "").replace(/\s+/g, " ");
  const i = norm(s).indexOf(norm(q));
  if (i < 0) return esc(s.slice(0, 80));
  const a = Math.max(0, i - 30);
  return (a ? "…" : "") + mark(s.slice(a, i + q.length + 60), q);
}

// ---------- Darstellung ----------
function view() {
  if (!st) return "";
  flat = [];
  const q = st.q.trim();
  const item = (html, run) => {
    const i = flat.length;
    flat.push(run);
    return html.replace("%I%", String(i)).replace("%SEL%", i === st.sel ? " sel" : "");
  };
  const row = (ic, tone, title, sub, run, { bag = null, kbd = "", right = "" } = {}) =>
    item(`<button type="button" class="res%SEL%" data-act="res" data-i="%I%" data-key="r-%I%"${bag ? ` style="${bagVars(bag)}"` : ""}>${bag ? `<span class="bsq sm"><span>${esc(bag.emoji)}</span></span>` : `<span class="sq" style="--bl:var(--${tone});--bd:var(--${tone})">${icon(ic)}</span>`}<span class="res-t"><b>${title}</b>${sub ? `<small>${sub}</small>` : ""}</span>${kbd ? `<kbd>${esc(kbd)}</kbd>` : right}</button>`, run);
  let body = "";
  if (st.smart) {
    const sm = SMART.find((x) => x.id === st.smart);
    const list = store.tasks().filter(sm.test).sort((a, b) => (sm.id === "erledigt" ? (b.done || 0) - (a.done || 0) : String(a.due || "9999").localeCompare(String(b.due || "9999")))).slice(0, 60);
    body += `<div class="res-g"><h4>${icon(sm.icon)} ${esc(sm.label)} <small>${list.length}</small><button type="button" class="link-btn" data-act="spot-smart" data-v="">Zurück</button></h4>${list.map((t) => taskRes(t, "", row)).join("") || `<p class="fine">Nichts hier.</p>`}</div>`;
  } else if (!q) {
    body += `<div class="smart-row">${SMART.map((x) => `<button type="button" class="smart" data-act="spot-smart" data-v="${x.id}"><span class="sq" style="--bl:var(--${x.tone});--bd:var(--${x.tone})">${icon(x.icon)}</span><span>${esc(x.label)}</span><small>${store.tasks().filter(x.test).length}</small></button>`).join("")}</div>`;
    const cmds = commands();
    body += `<div class="res-g"><h4>Befehle</h4>${cmds.filter((c) => !c.bag).map((c) => row(c.icon, c.tone, esc(c.label), "", c.run, { kbd: c.kbd })).join("")}</div>`;
    const bags = cmds.filter((c) => c.bag);
    if (bags.length) body += `<div class="res-g"><h4>Taschen</h4>${bags.map((c) => row("", "", esc(c.bag.name), esc(c.sub), c.run, { bag: c.bag })).join("")}</div>`;
  } else {
    const r = search(q);
    if (r.cmds.length) body += `<div class="res-g"><h4>Befehle</h4>${r.cmds.map((c) => row(c.icon, c.tone, mark(c.label, q), "", c.run, { kbd: c.kbd })).join("")}</div>`;
    if (r.bags.length) body += `<div class="res-g"><h4>Taschen</h4>${r.bags.map((b) => row("", "", mark(b.name, q), b.goal ? snippet(b.goal, q) : "", () => app.go("#tasche/" + b.id), { bag: b })).join("")}</div>`;
    if (r.tasks.length) body += `<div class="res-g"><h4>Aufgaben</h4>${r.tasks.map((t) => taskRes(t, q, row)).join("")}</div>`;
    if (r.notes.length) body += `<div class="res-g"><h4>Notizen</h4>${r.notes.map((n) => row("note", "yellow", mark(n.title || "Notiz", q), snippet(n.body, q), () => openNote(n.id))).join("")}</div>`;
    if (r.links.length) body += `<div class="res-g"><h4>Links</h4>${r.links.map((l) => row("link", "teal", mark(l.title, q), esc(l.url), () => window.open(l.url, "_blank", "noopener"))).join("")}</div>`;
    if (r.files.length) body += `<div class="res-g"><h4>Dateien</h4>${r.files.map((f) => row("clip", "gray", mark(f.name, q), esc(store.bag(f.bag)?.name || ""), () => app.go(`#tasche/${f.bag}/dateien`))).join("")}</div>`;
    body += `<div class="res-g">${row("plus", "blue", `„${esc(q)}“ als Aufgabe anlegen`, "Mit Datum, #Tasche und !!! – wie in der Schnellerfassung", () => openCapture({ text: q }))}${app.ai ? row("sparkle", "purple", `KI-PM fragen: „${esc(q)}“`, "Antwort auf Basis deiner Aufgaben", () => askAI({ kind: "ask", title: "Frag deinen PM", question: q })) : ""}</div>`;
  }
  if (st.sel >= flat.length) st.sel = Math.max(0, flat.length - 1);
  return `<div class="spot-head"><span class="spot-ic">${icon("search")}</span><input class="spot-in" type="search" value="${esc(st.q)}" placeholder="Suchen oder Befehl …" aria-label="Suchen oder Befehl" data-input="spot" data-key-act="spot-key" autofocus autocomplete="off" autocapitalize="off" spellcheck="false" enterkeyhint="go" /><button type="button" class="btn-text" data-act="sheet-close">Abbrechen</button></div>
<div class="spot-body" role="listbox">${body}</div>
<div class="spot-foot only-fine"><span><kbd>↑</kbd><kbd>↓</kbd> auswählen</span><span><kbd>↵</kbd> öffnen</span><span><kbd>esc</kbd> schließen</span></div>`;
}

function taskRes(t, q, row) {
  const bag = t.bag ? store.bag(t.bag) : null;
  const sub = [bag ? `${esc(bag.emoji)} ${esc(bag.name)}` : "📥 Eingang", t.due ? esc(safe(() => dates.relDay(t.due, app.now), t.due)) : "", t.done ? "erledigt" : "", q && t.notes && norm(t.notes).includes(norm(q)) ? snippet(t.notes, q) : ""].filter(Boolean).join(" · ");
  return row(t.done ? "checkCircle" : "circle", t.done ? "green" : t.prio === 3 ? "red" : "blue", q ? mark(t.title, q) : esc(t.title), sub, () => openTask(t.id), { right: t.plan === today() && !t.done ? `<span class="res-star">${icon("starFill")}</span>` : "" });
}

function run(i) {
  const fn = flat[i];
  if (!fn) return;
  closeSheet(getSheet("search"));
  setTimeout(() => {
    try {
      fn();
    } catch (e) {
      console.error(e);
    }
  }, 30);
}

function moveSel(d) {
  if (!st || !flat.length) return;
  st.sel = (st.sel + d + flat.length) % flat.length;
  const sh = getSheet("search");
  sh?.refresh();
  sh?.body.querySelector(".res.sel")?.scrollIntoView({ block: "nearest" });
}

// ---------- Ereignisse ----------
on("input", {
  spot: (el) => {
    if (!st) return;
    st.q = el.value;
    st.sel = 0;
    st.smart = null;
    getSheet("search")?.refresh();
  },
});

on("keydown", {
  "spot-key": (el, e) => {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      moveSel(1);
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      moveSel(-1);
    } else if (e.key === "Enter" && !e.isComposing) {
      e.preventDefault();
      run(st?.sel || 0);
    }
  },
});

on("click", {
  res: (el) => run(+el.dataset.i),
  "spot-smart": (el) => {
    if (!st) return;
    st.smart = el.dataset.v || null;
    st.sel = 0;
    haptic();
    getSheet("search")?.refresh();
  },
});
