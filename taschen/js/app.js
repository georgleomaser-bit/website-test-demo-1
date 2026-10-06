// Arbeitstaschen – App-Start, Navigation, Rendering (rAF-entprellt) und globale Ereignisse
import * as store from "./store.js";
import * as dates from "./dates.js";
import * as pm from "./pm.js";
import * as remind from "./remind.js";
import * as sync from "./sync.js";
import * as ai from "./ai.js";
import * as connect from "./connect.js";
import { COLORS, SERVER } from "./config.js";
import { app, handle, runMenu, render, on, safe, reducedMotion, isStandalone } from "./ui/core.js";
import { placeSegPills } from "./ui/components.js";
import { initGestures, gestureBusy } from "./ui/gestures.js";
import { topSheet, closeSheet, refreshSheets, menuOpen, closeMenu, openMenu, infoBox, confirmBox } from "./ui/sheet.js";
import { toast, toastUndo, banner, sound, haptic } from "./ui/fx.js";
import { openTask, taskDetail, inspectorToSheet, growAll, flushSaves } from "./ui/task.js";
import { openCapture } from "./ui/capture.js";
import { openSearch } from "./ui/search.js";
import { openOnboarding, onboardingOpen, paint as paintOnboarding } from "./ui/onboarding.js";
import { restoreFocus, refreshFocus, focusActive } from "./ui/focus.js";
import { sidebar, tabbar, topbar, counts } from "./ui/nav.js";
import { openNote, openLink, openMilestone, pickFiles } from "./ui/bag.js";
import { openBagEditor } from "./ui/bags.js";
import { toggleTask } from "./ui/actions.js";
import * as vToday from "./ui/today.js";
import * as vUpcoming from "./ui/upcoming.js";
import * as vInbox from "./ui/inbox.js";
import * as vBags from "./ui/bags.js";
import * as vBag from "./ui/bag.js";
import * as vReview from "./ui/review.js";
import * as vSettings from "./ui/settings.js";
import { openEvent, openExternal, checkAvail } from "./ui/connectui.js";
import * as integrationsUI from "./ui/integrationsui.js";

// ---------- Ansichten ----------
const VIEWS = {
  heute: { mod: vToday },
  demnaechst: { mod: vUpcoming },
  eingang: { mod: vInbox },
  taschen: { mod: vBags },
  tasche: { mod: vBag, back: ["Taschen", "#taschen"] },
  rueckblick: { mod: vReview, back: ["Heute", "#heute"] },
  einstellungen: { mod: vSettings, back: (r) => (r?.id === "verbindungen" || r?.id === "konten" ? ["Einstellungen", "#einstellungen"] : ["Heute", "#heute"]) },
};
// Zurück-Ziel einer Ansicht (Unterseiten wie „Verbindungen“ führen zu den Einstellungen)
const backOf = (v, r) => (typeof v?.back === "function" ? v.back(r) : v?.back) || null;

const $ = (id) => document.getElementById(id);

// ---------- Erscheinungsbild ----------
const mqDark = matchMedia("(prefers-color-scheme: dark)");
function isDark() {
  const t = document.documentElement.dataset.theme;
  return t === "dark" || (!t && mqDark.matches);
}

function applyTheme(p = safe(() => store.get().profile, null)) {
  const root = document.documentElement;
  const theme = p?.theme || "auto";
  if (theme === "light" || theme === "dark") root.dataset.theme = theme;
  else delete root.dataset.theme;
  const [l, d] = COLORS[p?.accent] || COLORS.blue;
  root.style.setProperty("--al", l);
  root.style.setProperty("--ad", d);
  const dp = safe(() => dates.daypart(new Date()), "day");
  root.dataset.daypart = dp;
  const dark = isDark();
  document.querySelectorAll('meta[name="theme-color"]').forEach((m) => {
    const media = m.getAttribute("media") || "";
    if (theme === "auto") m.setAttribute("content", media.includes("dark") ? "#000000" : "#F2F2F7");
    else m.setAttribute("content", dark ? "#000000" : "#F2F2F7");
  });
  try {
    localStorage.setItem("taschen-theme", JSON.stringify({ theme, accent: p?.accent || "blue" }));
  } catch (_) {
    /* egal */
  }
}

// Vor dem Laden: letztes Erscheinungsbild sofort setzen (kein Aufblitzen)
try {
  const t = JSON.parse(localStorage.getItem("taschen-theme") || "null");
  if (t) applyTheme({ theme: t.theme, accent: t.accent });
} catch (_) {
  /* erster Start */
}

// ---------- Layout-Modus ----------
function layout() {
  const w = window.innerWidth;
  const wide = w >= 760, insp = w >= 1100;
  const changed = wide !== app.wide || insp !== app.inspector;
  app.wide = wide;
  app.inspector = insp;
  const root = document.documentElement;
  root.classList.toggle("wide", wide);
  root.classList.toggle("insp-mode", insp);
  if (changed && !insp) inspectorToSheet();
  return changed;
}

// ---------- Route ----------
function parseHash() {
  let h = "";
  try {
    h = decodeURIComponent(location.hash.replace(/^#\/?/, ""));
  } catch (_) {
    h = location.hash.slice(1);
  }
  const [view, id, tab] = h.split("/");
  if (view === "suche") return { view: "suche" };
  if (!VIEWS[view]) return { view: "heute", id: null, tab: null };
  if (view === "einstellungen") return { view, id: id || null, tab: id === "verbindungen" ? tab || null : null };
  return { view, id: id || null, tab: tab || null };
}

const scrollMem = new Map();
const routeKey = (r) => `${r.view}/${r.id || ""}`;
let lastKey = "";

function route({ transition = true } = {}) {
  const r = parseHash();
  if (r.view === "suche") {
    history.replaceState(null, "", location.pathname + location.search + "#" + (app.route.view || "heute") + (app.route.id ? "/" + app.route.id : ""));
    openSearch();
    return;
  }
  const prevKey = lastKey;
  const key = routeKey(r);
  if (prevKey) scrollMem.set(prevKey, window.scrollY);
  if (app.route.view === "einstellungen" && r.view !== "einstellungen") vSettings.leaveSettings();
  app.route = r;
  if (key === prevKey) {
    app.render();
    return;
  }
  lastKey = key;
  const top = r.view === "tasche" && !scrollMem.has(key) ? 0 : scrollMem.get(key) || 0;
  const doPaint = () => {
    paint();
    window.scrollTo(0, top);
    updateScroll();
  };
  if (transition && app.booted && document.startViewTransition && !reducedMotion() && prevKey) {
    const prevView = parseKeyView(prevKey);
    const sub = r.view === "einstellungen" && prevView === "einstellungen";
    document.documentElement.dataset.vt = sub ? (r.id ? "push" : "pop") : r.view === "tasche" || (VIEWS[r.view]?.back && !VIEWS[prevView]?.back) ? "push" : VIEWS[prevView]?.back && !VIEWS[r.view]?.back ? "pop" : "fade";
    try {
      const vt = document.startViewTransition(doPaint);
      vt.finished.finally(() => delete document.documentElement.dataset.vt).catch(() => {});
    } catch (_) {
      doPaint();
    }
  } else doPaint();
  // Fokus für Screenreader/Tastatur auf den Inhalt – aber nie aus einem offenen Sheet oder Eingabefeld reißen
  if (!topSheet() && !/^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement?.nodeName || "")) $("main")?.focus({ preventScroll: true });
}
const parseKeyView = (k) => k.split("/")[0];

app.go = (hash, { replace = false } = {}) => {
  if (!hash) return;
  closeMenu();
  if (topSheet()?.key === "search") closeSheet(topSheet());
  if (("#" + location.hash.replace(/^#/, "")) === hash) {
    window.scrollTo({ top: 0, behavior: "smooth" });
    return;
  }
  if (replace) {
    history.replaceState(null, "", location.pathname + location.search + hash);
    route({ transition: false });
  } else location.hash = hash;
};

app.back = () => {
  const b = backOf(VIEWS[app.route.view], app.route);
  if (history.length > 1 && document.referrer !== undefined && app.navCount > 0) history.back();
  else app.go(b?.[1] || "#heute");
};

// ---------- Zeichnen ----------
let raf = 0;
app.render = () => {
  if (!raf) raf = requestAnimationFrame(() => {
    raf = 0;
    paint();
  });
};

function paint() {
  if (!app.booted) return;
  app.now = new Date();
  const r = app.route;
  const v = VIEWS[r.view] || VIEWS.heute;
  let html = "";
  try {
    html = v.mod.render(r);
  } catch (e) {
    console.error(e);
    html = `<div class="view" data-key="view-error"><div class="empty"><div class="empty-emoji">😵‍💫</div><h3>Hier ist etwas schiefgelaufen</h3><p>${String(e?.message || e).replace(/[<>&]/g, "")}</p><button type="button" class="btn" data-act="go" data-to="#heute">Zu Heute</button></div></div>`;
  }
  render($("view"), html);
  // Kopfzeile
  const title = safe(() => v.mod.title(r), "");
  const acts = safe(() => (v.mod.actions ? v.mod.actions(r) : ""), "");
  const bk = backOf(v, r);
  const sub = r.view === "einstellungen" && !!r.id && bk?.[1] === "#einstellungen";
  // iPhone: „‹ Einstellungen“ passt neben dem Titel nicht → wie iOS kurz „Zurück“
  render($("topbar"), topbar(title, { back: !app.wide && bk ? (sub ? "Zurück" : bk[0]) : app.wide && (r.view === "tasche" || sub) ? bk?.[0] || "Taschen" : null, actions: acts }));
  // Navigation
  if (app.wide) render($("sidebar"), sidebar());
  else render($("tabbar"), tabbar());
  // Inspektor
  const insp = $("inspector");
  const showInsp = app.inspector && app.selected && store.task(app.selected);
  if (showInsp) {
    insp.hidden = false;
    render(insp, taskDetail(app.selected, { inspector: true }));
  } else if (!insp.hidden) {
    if (app.selected && !store.task(app.selected)) app.selected = null;
    insp.hidden = true;
    render(insp, "");
  }
  document.documentElement.classList.toggle("has-insp", !!showInsp);
  refreshSheets();
  refreshFocus();
  if (onboardingOpen()) paintOnboarding();
  placeSegPills();
  growAll();
  updateScroll();
  updateBadgeTitle();
}

function updateBadgeTitle() {
  const c = safe(() => counts(), null);
  if (!c || focusActive()) return;
  document.title = c.today ? `(${c.today}) Arbeitstaschen` : "Arbeitstaschen";
}

// ---------- Kopfzeile beim Scrollen (Large Title → kompakt) ----------
let scrollRaf = 0;
function updateScroll() {
  const y = window.scrollY;
  const tb = $("topbar");
  if (!tb) return;
  const lt = document.querySelector("#view .lt-title, #view .bhero-name");
  const limit = lt ? lt.getBoundingClientRect().bottom + y - tb.offsetHeight + 4 : 40;
  tb.classList.toggle("scrolled", y > 4);
  tb.classList.toggle("titled", y > limit);
}
window.addEventListener(
  "scroll",
  () => {
    if (scrollRaf) return;
    scrollRaf = requestAnimationFrame(() => {
      scrollRaf = 0;
      updateScroll();
    });
  },
  { passive: true },
);

// ---------- Globale Ereignisse ----------
function bind() {
  document.addEventListener("click", (e) => {
    if (gestureBusy()) return;
    const a = e.target.closest?.("a[href^='#']");
    if (a && !e.metaKey && !e.ctrlKey) {
      e.preventDefault();
      app.go(a.getAttribute("href"));
      return;
    }
    handle("click", e);
  });
  document.addEventListener("input", (e) => handle("input", e));
  document.addEventListener("change", (e) => handle("change", e));
  document.addEventListener("submit", (e) => {
    if (e.target.matches("[data-submit]")) {
      e.preventDefault();
      handle("submit", e);
    }
  });
  document.addEventListener("contextmenu", (e) => {
    const el = e.target.closest?.("[data-menu]");
    if (!el || e.target.closest("input, textarea, select, a[href^='http']")) return;
    e.preventDefault();
    if (gestureBusy()) return;
    runMenu(el, { x: e.clientX, y: e.clientY });
  });
  // Backdrop-Klicks: nur schließen, wenn der Tipp auch dort begann
  let backdropDown = false;
  document.addEventListener("pointerdown", (e) => (backdropDown = !!e.target.closest?.("[data-backdrop]")), true);
  document.addEventListener("click", (e) => {
    if (e.target.closest?.("[data-backdrop]") && backdropDown) {
      const s = topSheet();
      if (s && s.wrap.contains(e.target)) closeSheet(s);
    }
  });
  document.addEventListener("keydown", onKey);
  window.addEventListener("hashchange", () => {
    app.navCount = (app.navCount || 0) + 1;
    route();
  });
  window.addEventListener("resize", () => {
    if (layout()) {
      render($("sidebar"), "");
      render($("tabbar"), "");
    }
    app.render();
  });
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      applyTheme();
      app.render();
    } else flushSaves();
  });
  window.addEventListener("pageshow", () => app.render());
  window.addEventListener("online", () => toast("Wieder online", { icon: "cloud", ms: 1800 }));
  window.addEventListener("offline", () => toast("Offline – alles bleibt gespeichert", { icon: "cloudOff", ms: 2600 }));
  mqDark.addEventListener?.("change", () => applyTheme());
  window.addEventListener("taschen:reminder", (e) => showReminder(e.detail));
  // Tastatur auf iOS überlagert Inhalte → Sheets darüber halten
  const vv = window.visualViewport;
  if (vv) {
    const upd = () => {
      const kb = Math.max(0, window.innerHeight - vv.height - vv.offsetTop);
      document.documentElement.style.setProperty("--kb", (kb > 60 ? kb : 0) + "px");
    };
    vv.addEventListener("resize", upd);
    vv.addEventListener("scroll", upd);
  }
  initGestures();
  // Mitternacht: neuer Tag
  const armMidnight = () => {
    const n = new Date();
    const next = new Date(n.getFullYear(), n.getMonth(), n.getDate() + 1, 0, 0, 5);
    setTimeout(() => {
      applyTheme();
      app.render();
      armMidnight();
    }, next - n);
  };
  armMidnight();
  setInterval(() => {
    applyTheme();
    if (app.route.view === "heute" && document.visibilityState === "visible" && !document.activeElement?.matches?.("input, textarea")) app.render();
  }, 60000);
}

const typing = (el) => !!el && (el.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(el.nodeName));

function trapTab(e) {
  const s = topSheet();
  const root = document.querySelector(".alert-wrap .alert") || document.querySelector(".menu-wrap .menu") || s?.box || (onboardingOpen() ? $("onboarding") : null);
  if (!root) return;
  const items = [...root.querySelectorAll('button:not([disabled]), [href], input:not([type="hidden"]):not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])')].filter((n) => n.offsetParent !== null);
  if (!items.length) return;
  const first = items[0], last = items[items.length - 1];
  if (!root.contains(document.activeElement)) {
    e.preventDefault();
    first.focus();
  } else if (e.shiftKey && document.activeElement === first) {
    e.preventDefault();
    last.focus();
  } else if (!e.shiftKey && document.activeElement === last) {
    e.preventDefault();
    first.focus();
  }
}

function onKey(e) {
  const mod = e.metaKey || e.ctrlKey;
  const k = e.key;
  if (k === "Tab") return trapTab(e);
  if (k !== "Escape" && handle("keydown", e)) return;
  if (k === "Escape") {
    if (menuOpen()) return closeMenu();
    if (document.querySelector(".alert-wrap")) return;
    const s = topSheet();
    if (s) {
      e.preventDefault();
      return closeSheet(s);
    }
    if (app.inspector && app.selected) {
      flushSaves();
      app.selected = null;
      return app.render();
    }
    if (typing(document.activeElement)) document.activeElement.blur();
    return;
  }
  if (mod && (k === "k" || k === "K")) {
    e.preventDefault();
    return openSearch();
  }
  if (mod && k === "Enter") {
    const s = topSheet();
    if (s && s.key !== "capture") {
      e.preventDefault();
      flushSaves();
      return closeSheet(s);
    }
    return;
  }
  if (mod && k === ",") {
    e.preventDefault();
    return app.go("#einstellungen");
  }
  if (typing(document.activeElement) || onboardingOpen()) return;
  if (mod && (k === "z" || k === "Z") && !e.shiftKey) {
    e.preventDefault();
    const l = store.undo();
    toast(l ? `Rückgängig: ${l}` : "Nichts zum Rückgängigmachen", { icon: "undo" });
    return;
  }
  if (mod || e.altKey || topSheet() || menuOpen()) return;
  if (k === "n" || k === "N") {
    e.preventDefault();
    return newTask();
  }
  if (k === "/") {
    e.preventDefault();
    return openSearch();
  }
  const map = { 1: "#heute", 2: "#demnaechst", 3: "#eingang", 4: "#taschen", 5: "#rueckblick" };
  if (map[k]) {
    e.preventDefault();
    return app.go(map[k]);
  }
}

function newTask(extra = {}) {
  const r = app.route;
  openCapture({ bag: r.view === "tasche" ? r.id : null, ...extra });
}

// ---------- Plus-Knopf und Suche ----------
on("click", {
  fab: () => {
    haptic();
    newTask();
  },
  search: () => openSearch(),
});

on("menu", {
  fab: (el, pos) => {
    const r = app.route;
    const bagId = r.view === "tasche" ? r.id : null;
    const bags = store.bags();
    const fileItems = bags.map((b) => ({ label: b.name, emoji: b.emoji, run: () => pickFiles(b.id) }));
    openMenu(
      [
        { label: "Neue Aufgabe", icon: "checkCircle", run: () => newTask() },
        { label: "Für heute", icon: "starFill", run: () => newTask({ plan: true }) },
        "-",
        { label: "Notiz", icon: "note", run: () => openNote(null, { bag: bagId }) },
        { label: "Link", icon: "link", run: () => openLink(null, { bag: bagId }) },
        bagId ? { label: "Datei", icon: "clip", run: () => pickFiles(bagId) } : { label: "Datei", icon: "clip", sub: fileItems, disabled: !bags.length },
        { label: "Meilenstein", icon: "diamond", run: () => openMilestone(null, { bag: bagId }) },
        "-",
        { label: "Neue Tasche", icon: "bag", run: () => openBagEditor() },
      ],
      { ...pos, el: pos?.x == null ? el : null, title: "Hinzufügen" },
    );
  },
});

// ---------- Erinnerungen bei offener App ----------
function snooze(id, min) {
  const t = store.task(id);
  if (!t) return;
  const d = new Date(Date.now() + min * 60000);
  d.setMinutes(Math.ceil(d.getMinutes() / 5) * 5, 0, 0);
  store.updateTask(id, { due: dates.toISO(d), time: `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`, remind: 0 });
  toastUndo(`Erinnere dich um ${d.toLocaleTimeString("de-DE", { hour: "numeric", minute: "2-digit" })}`, { icon: "bell" });
}

function showReminder(it) {
  if (!it) return;
  sound("soft");
  if (it.kind === "task" && it.taskId && store.task(it.taskId)) {
    const t = store.task(it.taskId);
    banner({
      title: it.title || t.title,
      body: it.body || "",
      emoji: store.bag(t.bag)?.emoji || "🔔",
      buttons: [
        { label: "Erledigt", primary: true, fn: () => !store.task(it.taskId)?.done && toggleTask(it.taskId) },
        { label: "+1 Std.", fn: () => snooze(it.taskId, 60) },
        { label: "Öffnen", fn: () => openTask(it.taskId) },
      ],
    });
  } else if (it.kind === "briefing") {
    banner({ title: it.title || "Dein Tag", body: it.body || "", emoji: "☀️", buttons: [{ label: "Mein Tag", primary: true, fn: () => app.go("#heute") }, { label: "Tag planen", fn: () => vToday.openPlanDay() }] });
  } else if (it.kind === "evening") {
    banner({ title: it.title || "Feierabend?", body: it.body || "", emoji: "🌙", buttons: [{ label: "Tag abschließen", primary: true, fn: () => app.go("#heute") }] });
  } else if (it.kind === "event") {
    const btns = [];
    if (it.join) btns.push({ label: "Beitreten", primary: true, fn: () => openExternal(it.join) });
    if (it.eventId && connect.event(it.eventId)) btns.push({ label: "Details", fn: () => openEvent(it.eventId) });
    else if (it.web) btns.push({ label: "Öffnen", fn: () => openExternal(it.web) });
    banner({ title: it.title || "Termin", body: it.body || "", emoji: "📅", buttons: btns });
  } else if (it.kind === "review") {
    banner({ title: it.title || "Wochenrückblick", body: it.body || "", emoji: "📊", buttons: [{ label: "Starten", primary: true, fn: () => app.go("#rueckblick") }] });
  } else banner({ title: it.title || "Erinnerung", body: it.body || "", emoji: "🔔" });
}

// ---------- Server, Sync, KI ----------
async function detectServices() {
  try {
    let srv = safe(() => sync.status().server, null) || SERVER.url || null;
    if (!srv) srv = await sync.detectServer();
    if (!srv) return;
    app.server = srv;
    checkAvail(true).catch(() => {}); // bietet der Server Google/Microsoft an?
    app.aiAvailable = !!(await ai.available(srv));
    const kv = await store.kvGet("ai").catch(() => null);
    app.ai = app.aiAvailable && !!kv?.enabled;
    app.render();
  } catch (_) {
    /* ohne Server – alles lokal */
  }
}

// ---------- Start ----------
function fatal(e) {
  console.error(e);
  const v = $("view");
  if (v) v.innerHTML = `<div class="empty big"><div class="empty-emoji">😵‍💫</div><h3>Arbeitstaschen konnte nicht starten</h3><p>${String(e?.message || e).replace(/[<>&]/g, "")}</p><p class="fine">Tipp: Privates Surfen verhindert manchmal den Speicher. Lade die Seite neu.</p><button type="button" class="btn primary">Neu laden</button></div>`;
  v?.querySelector("button")?.addEventListener("click", () => location.reload());
  document.documentElement.classList.add("booted");
}

// ---------- Alte Beispiel-Projekte aus Version 1.0 ----------
// Die erste Version konnte AKYTEX-Projekte als Startdaten laden. Liegen die noch auf dem Gerät, einmal anbieten, sie zu entfernen.
const OLD_SEED = new Set(["AKYTEX Plattform & Go-Live", "Firma & Beteiligung", "Broker-Partner & Echtgeld", "Zahlungen & Stripe", "Marketing & Clips", "Server & Betrieb", "NOVA – KI-Assistent"]);
async function offerCleanup() {
  const old = store.bags().filter((b) => OLD_SEED.has(b.name));
  if (!old.length) return false;
  let keep = false;
  try {
    keep = localStorage.getItem("taschen-keep-old") === "1";
  } catch (_) {
    /* ohne Speicher: fragen */
  }
  if (keep) return false;
  const ok = await confirmBox({
    title: "Alte Beispiel-Projekte entfernen?",
    text: `Auf diesem Gerät liegen noch ${old.length} ${old.length === 1 ? "Tasche" : "Taschen"} aus der ersten Version (AKYTEX, NOVA …). Sollen sie weg, damit du die App leer und neu einrichten kannst?`,
    ok: "Entfernen",
    cancel: "Behalten",
    danger: true,
  });
  if (!ok) {
    try {
      localStorage.setItem("taschen-keep-old", "1");
    } catch (_) {
      /* nur für diese Sitzung */
    }
    return false;
  }
  for (const b of old) safe(() => store.removeBag(b.id));
  safe(() => store.setMeta({ seeded: false }));
  if (!store.bags().length) store.setProfile({ onboarded: false });
  toast("Alte Projekte entfernt", { icon: "checkCircle", sub: store.bags().length ? "Deine eigenen Taschen bleiben" : "Jetzt neu einrichten" });
  return true;
}

async function boot() {
  layout();
  bind();
  let state;
  try {
    state = await store.load();
  } catch (e) {
    return fatal(e);
  }
  applyTheme(state.profile);
  // Rückkehr aus der Anmeldung bei Google/Microsoft (#connect=…): Konto anlegen, Schlüssel aus der Adresse entfernen
  let connected = false;
  try {
    connected = connect.handleReturn(store);
  } catch (e) {
    console.warn("[taschen] Konto verbinden", e);
  }
  // URL-Parameter: ?view=, ?neu=, ?task=
  const qs = new URLSearchParams(location.search);
  const qView = qs.get("view"), qNew = qs.get("neu"), qTask = qs.get("task");
  if (qView && VIEWS[qView.split("/")[0]]) history.replaceState(null, "", location.pathname + "#" + qView);
  else if (qs.toString()) history.replaceState(null, "", location.pathname + location.hash);
  app.booted = true;
  route({ transition: false });
  document.documentElement.classList.add("booted");

  store.subscribe((s, ch) => {
    if (!ch || ch.type === "profile" || ch.type === "all") applyTheme(s.profile);
    app.render();
  });
  try {
    remind.start(store, pm);
  } catch (e) {
    console.warn("[taschen] Erinnerungen", e);
  }
  try {
    connect.onChange(() => {
      app.render();
      remind.start(store, pm); // Termine fließen in den Erinnerungsplan
    });
    connect.start(store);
  } catch (e) {
    console.warn("[taschen] Konten", e);
  }
  try {
    integrationsUI.start(); // Briefkasten (Siri, Zapier …) abholen, ausgehende Webhooks
  } catch (e) {
    console.warn("[taschen] Verbindungen", e);
  }
  if (connected) {
    const r = connect.lastReturn();
    if (r?.ok) {
      toast(`${connect.providerName(r.provider)} ist verbunden`, { icon: "checkCircle", sub: r.email || "Termine und Mails werden geladen", ms: 4200 }); // ohne Haptik: nach der Rückkehr gibt es noch keine Nutzergeste
    } else if (r) {
      setTimeout(() => infoBox({ title: `${r.provider ? connect.providerName(r.provider) : "Konto"} nicht verbunden`, text: r.error || "Die Anmeldung hat nicht geklappt." }), 350);
    }
  }
  try {
    sync.onStatus((st) => {
      app.syncState = st;
      app.render();
    });
    app.syncState = sync.status();
    sync.start(store);
  } catch (e) {
    console.warn("[taschen] Sync", e);
  }
  if (store.get().profile.onboarded && (await offerCleanup().catch(() => false))) app.render();
  if (!store.get().profile.onboarded) openOnboarding();
  else {
    if (qNew != null) setTimeout(() => openCapture({ text: qNew }), 250);
    if (qTask) setTimeout(() => (store.task(qTask) ? openTask(qTask) : toast("Aufgabe nicht gefunden", { icon: "info", sub: "Vielleicht auf einem anderen Gerät?" })), 250);
  }
  restoreFocus();
  detectServices();
  if (isStandalone()) safe(() => store.requestPersist()?.catch?.(() => {}));
}

boot();
