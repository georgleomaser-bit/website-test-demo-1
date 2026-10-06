// Arbeitstaschen – „Demnächst“: Wochenstreifen, Agenda nach Tagen mit Meilensteinen, Ohne Datum, Wartet auf, Irgendwann
import * as store from "../store.js";
import * as dates from "../dates.js";
import * as pm from "../pm.js";
import { esc } from "../util.js";
import { icon } from "./icons.js";
import { app, on, today, safe, bagVars, isoWeek } from "./core.js";
import { taskRow, sec, empty, largeTitle } from "./components.js";
import { onDrop } from "./gestures.js";
import { openMenu } from "./sheet.js";
import { toastUndo, haptic } from "./fx.js";
import { exportCalendar } from "./today.js";
import { openMilestone } from "./bag.js";

const WD = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"];

function minutes(hhmm, def) {
  const [h, m] = String(hhmm || def).split(":").map(Number);
  return (h || 0) * 60 + (m || 0);
}

export function title() {
  return "Demnächst";
}

export function render() {
  const s = store.get();
  const now = app.now;
  const tdy = today();
  const p = s.profile;
  const days = safe(() => pm.upcoming(s, now, 60), []) || [];
  const byDate = new Map(days.map((d) => [d.date, d]));
  const capDay = Math.max(60, minutes(p.dayEnd, "18:00") - minutes(p.dayStart, "08:00"));

  // Wochenstreifen (14 Tage)
  let strip = "";
  for (let i = 0; i < 14; i++) {
    const iso = dates.addDays(tdy, i);
    const d = byDate.get(iso);
    const wd = dates.weekday(iso);
    const n = d ? d.tasks.length : 0;
    const bagsOf = d ? [...new Set(d.tasks.map((t) => t.bag))].slice(0, 3).map((id) => store.bag(id)) : [];
    const ms = d && d.milestones && d.milestones.length;
    const heavy = d && d.load > capDay ? " heavy" : "";
    const workday = (p.workdays || [1, 2, 3, 4, 5]).includes(wd);
    strip += `<button type="button" class="wday${i === 0 ? " today" : ""}${n || ms ? "" : " free"}${workday ? "" : " weekend"}${heavy}" data-act="up-day" data-iso="${iso}" data-drop="day" data-day="${iso}" aria-label="${esc(safe(() => dates.fmtDay(iso), iso))}: ${n} Aufgaben"><small>${WD[wd]}</small><b>${Number(iso.slice(8))}</b><span class="wdots">${ms ? `<i class="wms">${icon("diamondFill")}</i>` : ""}${bagsOf.map((b) => `<i style="${bagVars(b)}"></i>`).join("")}</span>${n ? `<em>${n}</em>` : ""}</button>`;
    if (i === 6) strip += `<span class="wsep" aria-hidden="true"></span>`;
  }

  // Agenda
  let agenda = "";
  let lastWeek = null;
  for (const d of days) {
    const wk = isoWeek(d.date);
    const diff = safe(() => dates.diffDays(tdy, d.date), 0);
    if (diff > 7 && wk !== lastWeek) agenda += `<div class="wk-sep" data-key="wk-${wk}-${d.date.slice(0, 4)}"><span>KW ${wk}</span></div>`;
    lastWeek = wk;
    const load = (d.tasks || []).some((t) => t.est) ? d.load || 0 : 0;
    const loadCls = load > capDay ? "red" : load > capDay * 0.8 ? "orange" : "";
    const ms = (d.milestones || []).map((m) => {
      const bag = store.bag(m.bag);
      return `<button type="button" class="ms-row${m.done ? " done" : ""}" data-key="m-${m.id}" data-act="ms-open" data-id="${m.id}" style="${bagVars(bag)}"><span class="ms-dia">${icon("diamondFill")}</span><span class="ms-t"><b>${esc(m.title)}</b><small>Meilenstein · ${bag ? esc(bag.emoji + " " + bag.name) : ""}</small></span>${icon("chevronRight")}</button>`;
    });
    const tasks = (d.tasks || []).slice().sort((a, b) => (a.time ? 0 : 1) - (b.time ? 0 : 1) || String(a.time || "").localeCompare(String(b.time || "")) || (b.prio || 0) - (a.prio || 0));
    agenda += `<section class="aday${diff === 0 ? " is-today" : ""}" id="day-${d.date}" data-key="day-${d.date}" data-drop="day" data-day="${d.date}">
<header class="aday-h"><div class="aday-t"><h3>${esc(d.label || safe(() => dates.relDay(d.date, now), d.date))}</h3><small>${esc(safe(() => dates.fmtDay(d.date), d.date))}</small></div>${load ? `<span class="load ${loadCls}" title="Geschätzte Arbeitszeit">${icon("hourglass")}${esc(safe(() => dates.fmtDuration(load), load + " Min."))}${loadCls === "red" ? " · zu voll" : ""}</span>` : ""}<button type="button" class="btn-round sm" data-act="new-task" data-due="${d.date}" aria-label="Aufgabe für diesen Tag">${icon("plus")}</button></header>
<div class="card list">${ms.join("")}${tasks.map((t) => taskRow(t, { date: false, drag: true })).join("")}</div>
</section>`;
  }

  // Ohne Datum / Wartet auf / Irgendwann
  const open = store.tasks().filter((t) => !t.done);
  const active = (t) => !t.bag || (store.bag(t.bag)?.status || "aktiv") === "aktiv";
  const nodate = open.filter((t) => !t.due && !t.someday && !t.waiting && active(t));
  const waiting = open.filter((t) => t.waiting);
  const someday = open.filter((t) => t.someday && !t.due);
  const overdueN = open.filter((t) => t.due && t.due < tdy).length;

  let html = largeTitle("Demnächst", { sub: `${days.length ? `${days.reduce((n, d) => n + d.tasks.length, 0)} Termine in den nächsten Wochen` : "Die nächsten Wochen"}`, key: "lt-up" });
  html += `<div class="wstrip-wrap" data-key="wstrip"><div class="wstrip hscroll">${strip}</div></div>`;
  if (overdueN) html += `<button type="button" class="banner overdue" data-key="up-overdue" data-act="go" data-to="#heute"><span class="banner-ic">${icon("flag")}</span><span class="banner-t"><b>${overdueN} überfällig</b><small>Auf „Heute“ neu planen</small></span>${icon("chevronRight")}</button>`;
  html += days.length ? `<div class="agenda" data-key="agenda">${agenda}</div>` : empty({ emoji: "🗓️", title: "Nichts terminiert", text: "In den nächsten Wochen steht nichts mit Datum an. Gib Aufgaben ein Datum – oder zieh sie auf einen Tag im Streifen.", action: `<button type="button" class="btn primary" data-act="new-task" data-due="${dates.addDays(tdy, 1)}">${icon("plus")}<span>Aufgabe für morgen</span></button>` });

  if (nodate.length) {
    const groups = new Map();
    for (const t of nodate) {
      const k = t.bag || "";
      if (!groups.has(k)) groups.set(k, []);
      groups.get(k).push(t);
    }
    const body = [...groups.entries()]
      .sort((a, b) => (store.bag(a[0])?.order ?? -1) - (store.bag(b[0])?.order ?? -1))
      .map(([k, list]) => {
        const bag = k ? store.bag(k) : null;
        return `<div class="grp-h" data-key="g-${k || "inbox"}" style="${bagVars(bag)}"><span>${bag ? esc(bag.emoji + " " + bag.name) : "📥 Eingang"}</span><small>${list.length}</small></div>${list.sort((a, b) => (b.prio || 0) - (a.prio || 0)).map((t) => taskRow(t, { bag: false, drag: true })).join("")}`;
      })
      .join("");
    html += sec({ key: "nodate", title: "Ohne Datum", icon: "tray", tone: "gray", count: nodate.length, collapsible: true, collapsed: true, body, note: "Zum Planen auf einen Tag ziehen" });
  }
  if (waiting.length) html += sec({ key: "waiting", title: "Wartet auf", icon: "hourglass", tone: "purple", count: waiting.length, collapsible: true, collapsed: false, body: waiting.map((t) => taskRow(t, { drag: true })).join("") });
  if (someday.length) html += sec({ key: "someday", title: "Irgendwann", icon: "moon", tone: "indigo", count: someday.length, collapsible: true, collapsed: true, body: someday.map((t) => taskRow(t, { drag: true })).join("") });
  return `<div class="view view-up" data-key="view-up">${html}</div>`;
}

export function actions() {
  return `<button type="button" class="btn-round" data-act="up-ics" aria-label="Zum Kalender hinzufügen" title="Zum Kalender hinzufügen">${icon("calendarPlus")}</button>`;
}

// ---------- Ereignisse ----------
on("click", {
  "up-day": (el) => {
    const t = document.getElementById("day-" + el.dataset.iso);
    if (t) {
      const top = t.getBoundingClientRect().top + window.scrollY - (app.wide ? 80 : 110);
      window.scrollTo({ top, behavior: "smooth" });
      t.classList.remove("flash");
      void t.offsetWidth;
      t.classList.add("flash");
    } else {
      import("./capture.js").then((m) => m.openCapture({ due: el.dataset.iso }));
    }
  },
  "up-ics": (el) =>
    openMenu(
      [
        { label: "Termine + Tagesbriefing", icon: "bell", hint: "mit Weckern, auch bei geschlossener App", run: () => exportCalendar({ daily: true }) },
        { label: "Nur Termine & Meilensteine", icon: "calendarPlus", run: () => exportCalendar({ daily: false }) },
      ],
      { el, title: "Zum Kalender hinzufügen" },
    ),
  "ms-open": (el) => openMilestone(el.dataset.id),
});

onDrop("day", (id, zone) => {
  const iso = zone.dataset.day;
  const t = store.task(id);
  if (!t || !iso || t.due === iso) return;
  store.updateTask(id, { due: iso, someday: false });
  haptic();
  toastUndo(`→ ${safe(() => dates.relDay(iso, new Date()), iso)}`, { icon: "calendar", sub: t.title });
});
