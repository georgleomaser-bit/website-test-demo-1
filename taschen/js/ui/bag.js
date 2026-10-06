// Arbeitstaschen – Tasche im Detail: Hero, Segmente (Übersicht, Aufgaben, Board, Notizen, Links, Dateien, Meilensteine, Verlauf) und ihre Sheets
import * as store from "../store.js";
import * as dates from "../dates.js";
import * as pm from "../pm.js";
import * as remind from "../remind.js";
import * as sync from "../sync.js";
import { LIMITS } from "../config.js";
import { esc, safeUrl, fmtSize, debounce } from "../util.js";
import { icon } from "./icons.js";
import { app, on, safe, bagVars, today, relTime, isCollapsed, hostOf, appUrl, slug, clockStr, dayTitle } from "./core.js";
import { taskRow, ring, healthPill, empty, seg, toggle, sq } from "./components.js";
import { openSheet, sheetHead, getSheet, closeSheet, openMenu, confirmBox, promptBox } from "./sheet.js";
import { haptic, toast, toastUndo, toastError, sound, confetti } from "./fx.js";
import { onDrop } from "./gestures.js";
import { openTask } from "./task.js";
import { openBagEditor, stats } from "./bags.js";
import { askAI } from "./aiui.js";
import { markdown, plain, toggleCheckLine, checkStats } from "./markdown.js";
import { mergeIcs } from "./today.js";
import { COLORS } from "../config.js";

export const TABS = [
  { id: "uebersicht", label: "Übersicht", icon: "overview" },
  { id: "aufgaben", label: "Aufgaben", icon: "checklist" },
  { id: "board", label: "Board", icon: "board" },
  { id: "notizen", label: "Notizen", icon: "note" },
  { id: "links", label: "Links", icon: "link" },
  { id: "dateien", label: "Dateien", icon: "clip" },
  { id: "meilensteine", label: "Meilensteine", icon: "diamond" },
  { id: "verlauf", label: "Verlauf", icon: "history" },
];

const tabOf = (r) => (TABS.some((t) => t.id === r.tab) ? r.tab : "uebersicht");

export function title(r) {
  return store.bag(r.id)?.name || "Tasche";
}

// ---------- Ansicht ----------
export function render(r) {
  const b = store.bag(r.id);
  if (!b) return `<div class="view" data-key="view-bag-missing">${empty({ emoji: "🫥", title: "Tasche nicht gefunden", text: "Vielleicht wurde sie gelöscht oder auf einem anderen Gerät entfernt.", action: `<button type="button" class="btn primary" data-act="go" data-to="#taschen">${icon("bag")}<span>Zu den Taschen</span></button>` })}</div>`;
  const tab = tabOf(r);
  const st = stats(b.id) || { pct: 0, open: 0, done: 0, total: 0, overdue: 0, health: "gut", waiting: 0 };
  const all = store.tasksOf(b.id);
  const notes = store.notes().filter((n) => n.bag === b.id);
  const links = store.links().filter((l) => l.bag === b.id);
  const files = store.files().filter((f) => f.bag === b.id);
  const ms = safe(() => store.milestones(b.id), []);
  const counts = { aufgaben: st.open, notizen: notes.length, links: links.length, dateien: files.length, meilensteine: ms.filter((m) => !m.done).length };
  const dl = st.deadlineIn;
  const dlTxt = b.deadline ? `${dl == null ? "" : dl < 0 ? `Deadline vor ${-dl} T · ` : dl === 0 ? "Deadline heute · " : `Deadline in ${dl} T · `}${esc(safe(() => dates.fmtDay(b.deadline, { weekday: false }), b.deadline))}` : "";

  const hero = `<section class="bhero" data-key="bhero-${b.id}" style="${bagVars(b)}">
<div class="bhero-art" aria-hidden="true"><i></i><i></i></div>
<div class="bhero-top"><span class="bhero-emoji">${esc(b.emoji)}</span><div class="bhero-acts">
<button type="button" class="btn-glass round" data-act="bag-edit" data-id="${b.id}" aria-label="Bearbeiten" title="Bearbeiten">${icon("pencil")}</button>
<button type="button" class="btn-glass round" data-act="bag-ics" data-id="${b.id}" aria-label="In den Kalender" title="In den Kalender">${icon("calendarPlus")}</button>
<button type="button" class="btn-glass round" data-act="bag-share" data-id="${b.id}" aria-label="Teilen" title="Teilen">${icon("share")}</button>
<button type="button" class="btn-glass round" data-act="bag-menu" data-id="${b.id}" aria-label="Mehr" title="Mehr">${icon("ellipsis")}</button>
</div></div>
<h1 class="bhero-name">${esc(b.name)}</h1>
${b.goal ? `<p class="bhero-goal">${esc(b.goal)}</p>` : `<button type="button" class="bhero-goal add" data-act="bag-edit" data-id="${b.id}">${icon("plus")} Ziel festlegen</button>`}
<div class="bhero-stats">${ring(st.pct, { size: 64, stroke: 6, cls: "hero-ring" })}<div class="bhero-meta"><div class="bhero-pills">${healthPill(st)}${b.status !== "aktiv" ? `<span class="health gray"><i></i>${b.status === "pausiert" ? "Pausiert" : "Fertig"}</span>` : ""}</div>${st.healthReason ? `<p>${esc(st.healthReason)}</p>` : ""}${dlTxt ? `<p class="bhero-dl">${icon("flag")}${dlTxt}</p>` : ""}${/erledigt/.test(st.healthReason || "") ? "" : `<p class="bhero-count"><b>${st.done}</b> von <b>${st.total}</b> erledigt</p>`}</div></div>
</section>`;

  const tabs = `<div class="tabs-wrap" data-key="tabs">${seg(TABS.map((t) => ({ id: t.id, label: t.label, count: counts[t.id] || "" })), tab, { act: "bag-tab", attrs: `data-id="${b.id}"`, cls: "tabs", label: "Bereiche der Tasche" })}</div>`;

  let body = "";
  try {
    body = { uebersicht: overview, aufgaben: tasksTab, board, notizen: notesTab, links: linksTab, dateien: filesTab, meilensteine: milestonesTab, verlauf: historyTab }[tab](b, { st, all, notes, links, files, ms });
  } catch (e) {
    console.error(e);
    body = `<div class="note-box red">${icon("info")}<span>Dieser Bereich konnte nicht angezeigt werden: ${esc(e.message)}</span></div>`;
  }
  return `<div class="view view-bag" data-key="view-bag-${b.id}" style="${bagVars(b)}">${hero}${tabs}<div class="tabc tab-${tab}" data-key="tab-${tab}">${body}</div></div>`;
}

export function actions(r) {
  const b = store.bag(r.id);
  if (!b) return "";
  return `<button type="button" class="btn-round" data-act="new-task" data-bag="${b.id}" aria-label="Neue Aufgabe in dieser Tasche" title="Neue Aufgabe">${icon("plus")}</button><button type="button" class="btn-round" data-act="bag-menu" data-id="${b.id}" aria-label="Mehr">${icon("ellipsis")}</button>`;
}

// ---------- Übersicht ----------
function overview(b, { st, all, notes, ms }) {
  const now = app.now;
  const steps = safe(() => pm.nextSteps(store.get(), b.id, now), []) || [];
  const waiting = all.filter((t) => !t.done && t.waiting);
  const pinned = notes.filter((n) => n.pinned).slice(0, 4);
  const log = safe(() => store.logEntries(4, b.id), []);
  let h = "";
  if (st.next) h += `<section class="ov-next" data-key="ov-next"><h3 class="ov-h">${icon("arrowRight")} Nächster Schritt</h3><div class="card list">${taskRow(st.next, { bag: false })}</div></section>`;
  else if (!st.open) h += `<div class="ov-done" data-key="ov-done">${st.total ? `<span>🏆</span><b>Alles erledigt!</b><p>Setz die Tasche auf „Fertig“ oder plane den nächsten Schritt.</p>` : `<span>✨</span><b>Leg los</b><p>Was ist der erste Schritt in diesem Projekt?</p>`}<button type="button" class="btn primary sm" data-act="new-task" data-bag="${b.id}">${icon("plus")}<span>Aufgabe</span></button></div>`;

  h += `<div class="tiles" data-key="tiles">
<button type="button" class="tile" data-act="bag-tab" data-id="${b.id}" data-v="aufgaben"><b>${st.open}</b><small>offen</small></button>
<div class="tile green"><b>${st.done}</b><small>erledigt</small></div>
<div class="tile${st.overdue ? " red" : ""}"><b>${st.overdue}</b><small>überfällig</small></div>
<div class="tile${st.dueWeek ? " orange" : ""}"><b>${st.dueWeek || 0}</b><small>diese Woche</small></div>
</div>`;

  if (steps.length || app.ai) {
    h += `<section class="ov-steps" data-key="ov-steps"><h3 class="ov-h">${icon("sparkle")} Nächste Schritte <small>vom PM</small></h3><div class="card list">${steps
      .slice(0, 5)
      .map((s, i) => `<div class="step"><span class="step-n">${i + 1}</span><span class="step-t">${esc(s.text)}</span>${s.action ? `<button type="button" class="pill accent" data-act="step-act" data-id="${b.id}" data-i="${i}">${esc(stepLabel(s.action))}</button>` : ""}</div>`)
      .join("")}${app.ai ? `<button type="button" class="step ai" data-act="bag-ai" data-id="${b.id}">${icon("sparkle")}<span>KI-PM fragen: Was jetzt?</span>${icon("chevronRight")}</button>` : ""}</div></section>`;
  }

  if (ms.length) {
    const tdy = today();
    const items = ms.slice(0, 8);
    h += `<section class="ov-ms" data-key="ov-ms"><h3 class="ov-h">${icon("diamond")} Meilensteine <button type="button" class="link-btn" data-act="bag-tab" data-id="${b.id}" data-v="meilensteine">Alle</button></h3><div class="mini-tl hscroll">${items
      .map((m) => {
        const d = m.date ? safe(() => dates.diffDays(tdy, m.date), 0) : null;
        return `<button type="button" class="mtl${m.done ? " done" : d != null && d < 0 ? " late" : ""}" data-act="ms-open" data-id="${m.id}"><span class="mtl-d">${icon(m.done ? "checkCircle" : "diamondFill")}</span><b>${esc(m.title)}</b><small>${m.done ? "erreicht" : m.date ? esc(safe(() => dates.relDay(m.date, app.now), m.date)) : "ohne Datum"}</small></button>`;
      })
      .join("")}</div></section>`;
  }

  if (waiting.length) h += `<section class="ov-wait" data-key="ov-wait"><h3 class="ov-h">${icon("hourglass")} Wartet auf</h3><div class="card list">${waiting.map((t) => taskRow(t, { bag: false })).join("")}</div></section>`;

  if (pinned.length) h += `<section data-key="ov-notes"><h3 class="ov-h">${icon("pin")} Angepinnte Notizen</h3><div class="ngrid">${pinned.map(noteCard).join("")}</div></section>`;

  if (log.length) h += `<section data-key="ov-log"><h3 class="ov-h">${icon("history")} Zuletzt <button type="button" class="link-btn" data-act="bag-tab" data-id="${b.id}" data-v="verlauf">Verlauf</button></h3><div class="card list log">${log.map(logRow).join("")}</div></section>`;
  return h;
}

function stepLabel(a) {
  return { "open-task": "Öffnen", "plan-task": "Heute", "open-bag": "Öffnen", "add-task": "Anlegen", "open-inbox": "Eingang", "review": "Rückblick", "set-deadline": "Deadline", "add-milestone": "Meilenstein", "plan-overdue": "Heute" }[a.type] || a.label || "Los";
}

function runStep(bagId, i) {
  const steps = safe(() => pm.nextSteps(store.get(), bagId, new Date()), []) || [];
  const a = steps[i]?.action;
  if (!a) return;
  switch (a.type) {
    case "open-task":
      return a.id && openTask(a.id);
    case "plan-task":
      if (a.id) {
        store.planTask(a.id, today());
        toast("Für heute eingeplant", { icon: "starFill" });
      }
      return;
    case "plan-overdue": {
      const ts = store.tasksOf(bagId).filter((t) => !t.done && t.due && t.due < today());
      for (const t of ts) store.updateTask(t.id, { due: today() });
      return toast(`${ts.length} auf heute geholt`, { icon: "sun" });
    }
    case "add-task":
      return import("./capture.js").then((m) => m.openCapture({ bag: bagId, text: a.title || "" }));
    case "set-deadline":
      return openBagEditor(bagId);
    case "add-milestone":
      return openMilestone(null, { bag: bagId });
    case "open-inbox":
      return app.go("#eingang");
    case "review":
      return app.go("#rueckblick");
    case "open-bag":
      return app.go("#tasche/" + (a.id || bagId));
    default:
      if (a.id && store.task(a.id)) openTask(a.id);
  }
}

// ---------- Aufgaben ----------
const byOrder = (a, b) => (a.order ?? 0) - (b.order ?? 0) || (a.created || 0) - (b.created || 0);

function tasksTab(b, { all, st }) {
  const open = all.filter((t) => !t.done).sort(byOrder);
  const done = all.filter((t) => t.done).sort((x, y) => (y.done || 0) - (x.done || 0));
  const sections = ["", ...(b.sections || [])];
  for (const t of open) if (t.section && !sections.includes(t.section)) sections.push(t.section);
  const steps = (safe(() => pm.nextSteps(store.get(), b.id, app.now), []) || []).slice(0, 3);
  let h = "";
  if (steps.length && !isCollapsed("steps-" + b.id, false)) {
    h += `<div class="steps-bar" data-key="steps-bar">${icon("sparkle")}<div>${steps.map((s, i) => `<p><b>${i + 1}.</b> ${esc(s.text)}${s.action ? ` <button type="button" class="link-btn" data-act="step-act" data-id="${b.id}" data-i="${i}">${esc(stepLabel(s.action))}</button>` : ""}</p>`).join("")}</div><button type="button" class="mini-x" data-act="collapse" data-k="steps-${b.id}" aria-label="Ausblenden">${icon("x")}</button></div>`;
  }
  for (const s of sections) {
    const list = open.filter((t) => (t.section || "") === s);
    if (!s && !list.length && sections.length > 1) continue;
    const key = `bsec-${b.id}-${s}`;
    const col = isCollapsed(key, false);
    h += `<section class="tsec${col ? " collapsed" : ""}" data-key="ts-${esc(s || "_")}">
<header class="tsec-h"><button type="button" class="sec-toggle" data-act="collapse" data-k="${esc(key)}" aria-expanded="${!col}"><span class="sec-chev${col ? "" : " open"}">${icon("chevronRight")}</span><h3>${esc(s || (sections.length > 1 ? "Ohne Abschnitt" : "Aufgaben"))}</h3><span class="sec-count">${list.length}</span></button>${s ? `<button type="button" class="btn-round sm ghost" data-act="sec-menu" data-id="${b.id}" data-sec="${esc(s)}" aria-label="Abschnitt bearbeiten">${icon("ellipsis")}</button>` : ""}</header>
${col ? "" : `<div class="card list" data-drop="section" data-drop-list data-bag="${b.id}" data-sec="${esc(s)}">${list.map((t) => taskRow(t, { bag: false, drag: true })).join("")}<form class="inline-add" data-submit="inline-add" data-bag="${b.id}" data-sec="${esc(s)}" data-key="ia-${esc(s || "_")}" autocomplete="off"><span class="ia-ic">${icon("plus")}</span><input type="text" placeholder="Aufgabe hinzufügen" aria-label="Neue Aufgabe${s ? " in " + esc(s) : ""}" enterkeyhint="done" data-focus="ia-${esc(s || "_")}" /></form></div>`}
</section>`;
  }
  h += `<button type="button" class="add-row solo" data-key="add-sec" data-act="sec-add" data-id="${b.id}">${icon("plus")}<span>Abschnitt hinzufügen</span></button>`;
  if (done.length) {
    const key = "bdone-" + b.id;
    const col = isCollapsed(key, true);
    h += `<section class="tsec done-sec${col ? " collapsed" : ""}" data-key="ts-done"><header class="tsec-h"><button type="button" class="sec-toggle" data-act="collapse" data-k="${key}" data-def="1" aria-expanded="${!col}"><span class="sec-chev${col ? "" : " open"}">${icon("chevronRight")}</span><h3>Erledigt</h3><span class="sec-count">${done.length}</span></button></header>${col ? "" : `<div class="card list">${done.slice(0, 100).map((t) => taskRow(t, { bag: false })).join("")}</div>`}</section>`;
  }
  if (!all.length) h = empty({ emoji: "📝", title: "Noch keine Aufgaben", text: "Was ist der erste Schritt? Schreib ihn einfach auf – Datum und Priorität erkenne ich mit.", action: `<button type="button" class="btn primary" data-act="new-task" data-bag="${b.id}">${icon("plus")}<span>Erste Aufgabe</span></button>` }) + h;
  return h;
}

// ---------- Board ----------
function board(b, { all }) {
  const open = all.filter((t) => !t.done).sort(byOrder);
  const cols = [...(b.sections || [])];
  for (const t of open) if (t.section && !cols.includes(t.section)) cols.push(t.section);
  const loose = open.filter((t) => !t.section);
  if (loose.length || !cols.length) cols.unshift("");
  const doneN = all.filter((t) => t.done).length;
  return `<div class="board-scroll hscroll" data-key="board"><div class="board">${cols
    .map((s) => {
      const list = open.filter((t) => (t.section || "") === s);
      return `<section class="kcol" data-key="kc-${esc(s || "_")}"><header class="kcol-h"><h3>${esc(s || "Ohne Abschnitt")}</h3><span class="sec-count">${list.length}</span>${s ? `<button type="button" class="btn-round sm ghost" data-act="sec-menu" data-id="${b.id}" data-sec="${esc(s)}" aria-label="Spalte bearbeiten">${icon("ellipsis")}</button>` : ""}</header>
<div class="kcol-list" data-drop="section" data-drop-list data-bag="${b.id}" data-sec="${esc(s)}">${list.map(kcard).join("")}</div>
<form class="inline-add k" data-submit="inline-add" data-bag="${b.id}" data-sec="${esc(s)}" data-key="kia-${esc(s || "_")}" autocomplete="off"><span class="ia-ic">${icon("plus")}</span><input type="text" placeholder="Karte hinzufügen" aria-label="Neue Karte" enterkeyhint="done" /></form>
</section>`;
    })
    .join("")}<button type="button" class="kcol add" data-key="kc-add" data-act="sec-add" data-id="${b.id}">${icon("plus")}<span>Spalte</span></button></div></div>${doneN ? `<p class="fine center" data-key="board-fine">${doneN} erledigte Aufgaben findest du unter „Aufgaben“. Karten per Ziehen verschieben – auf dem iPhone lange drücken.</p>` : `<p class="fine center" data-key="board-fine">Karten per Ziehen verschieben – auf dem iPhone lange drücken.</p>`}`;
}

function kcard(t) {
  const subs = t.subtasks || [];
  const di = t.due ? { label: safe(() => dates.relDay(t.due, app.now), t.due), cls: t.due < today() ? "red" : t.due === today() ? "orange" : "" } : null;
  return `<div class="kcard${t.prio === 3 ? " p3" : ""}" data-key="k-${t.id}" data-drag="task" data-id="${t.id}" data-task="${t.id}" data-menu="task">
<button type="button" class="check small" data-act="toggle" data-id="${t.id}" aria-label="Erledigen: ${esc(t.title)}">${`<svg class="ck" viewBox="0 0 26 26" aria-hidden="true"><circle class="ck-ring" cx="13" cy="13" r="11"/><circle class="ck-fill" cx="13" cy="13" r="11"/><path class="ck-mark" d="M8 13.4l3.4 3.4 6.8-7.2"/></svg>`}</button>
<button type="button" class="kmain" data-act="task" data-id="${t.id}"><span class="ktitle">${t.prio ? `<span class="prio p${t.prio}">${"!".repeat(t.prio)}</span>` : ""}${esc(t.title)}</span><span class="task-meta">${di ? `<span class="m ${di.cls}">${icon("calendar")}${esc(di.label)}</span>` : ""}${t.time ? `<span class="m">${icon("clock")}${esc(t.time)}</span>` : ""}${subs.length ? `<span class="m">${icon("checklist")}${subs.filter((x) => x.done).length}/${subs.length}</span>` : ""}${t.waiting ? `<span class="m purple">${icon("hourglass")}${esc(t.waiting)}</span>` : ""}${t.notes ? `<span class="m">${icon("note")}</span>` : ""}</span></button>
</div>`;
}

// ---------- Notizen ----------
function noteCard(n) {
  const cs = checkStats(n.body);
  return `<button type="button" class="ncard${n.pinned ? " pinned" : ""}" data-key="n-${n.id}" data-act="note-open" data-id="${n.id}"><b>${n.pinned ? icon("pin") : ""}${esc(n.title || "Ohne Titel")}</b><p>${esc(plain(n.body, 180)) || "<i>Leer</i>"}</p><small>${cs.total ? `${icon("checklist")} ${cs.done}/${cs.total} · ` : ""}${esc(relTime(n.updated))}</small></button>`;
}

function notesTab(b, { notes }) {
  const list = notes.slice().sort((x, y) => (y.pinned ? 1 : 0) - (x.pinned ? 1 : 0) || (y.updated || 0) - (x.updated || 0));
  if (!list.length) return empty({ emoji: "🗒️", title: "Noch keine Notizen", text: "Ideen, Protokolle, Checklisten – mit einfachem Markdown: # Überschrift, **fett**, - [ ] Checkbox.", action: `<button type="button" class="btn primary" data-act="note-new" data-bag="${b.id}">${icon("plus")}<span>Neue Notiz</span></button>` });
  return `<div class="ngrid" data-key="ngrid"><button type="button" class="ncard new" data-key="n-new" data-act="note-new" data-bag="${b.id}">${icon("plus")}<b>Neue Notiz</b></button>${list.map(noteCard).join("")}</div>`;
}

// ---------- Links ----------
function linksTab(b, { links }) {
  const list = links.slice().sort((x, y) => (y.created || 0) - (x.created || 0));
  if (!list.length) return empty({ emoji: "🔗", title: "Noch keine Links", text: "Dokumente, Tools, Ansprechpartner – alles, was zu diesem Projekt gehört, mit einem Tipp erreichbar.", action: `<button type="button" class="btn primary" data-act="link-new" data-bag="${b.id}">${icon("plus")}<span>Link hinzufügen</span></button>` });
  return `<div class="card list links" data-key="links">${list
    .map((l) => {
      const u = safeUrl(l.url);
      const host = hostOf(u) || l.url;
      const letter = (host || "?").replace(/^www\./, "")[0]?.toUpperCase() || "?";
      return `<div class="lrow" data-key="l-${l.id}"><span class="lav" style="--h:${hash(host) % 360}">${esc(letter)}</span>${u ? `<a class="lmain" href="${esc(u)}" target="_blank" rel="noopener noreferrer"><b>${esc(l.title || host)}</b><small>${esc(host)}</small></a>` : `<span class="lmain"><b>${esc(l.title)}</b><small class="red">Ungültige Adresse</small></span>`}<button type="button" class="btn-round sm ghost" data-act="link-menu" data-id="${l.id}" aria-label="Link bearbeiten">${icon("ellipsis")}</button></div>`;
    })
    .join("")}<button type="button" class="add-row" data-key="l-add" data-act="link-new" data-bag="${b.id}">${icon("plus")}<span>Link hinzufügen</span></button></div>`;
}

function hash(s) {
  let h = 0;
  for (const c of String(s)) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return h;
}

// ---------- Dateien ----------
const thumbs = new Map(); // id → blob-URL | "loading" | "none"
function thumb(f) {
  if (!/^image\//.test(f.type || "")) return null;
  const t = thumbs.get(f.id);
  if (t && t !== "loading" && t !== "none") return t;
  if (!t) {
    thumbs.set(f.id, "loading");
    store
      .fileBlob(f.id)
      .then((blob) => {
        if (blob) {
          thumbs.set(f.id, URL.createObjectURL(blob));
          app.render();
        } else thumbs.set(f.id, "none");
      })
      .catch(() => thumbs.set(f.id, "none"));
  }
  return null;
}

function fileIcon(f) {
  const t = f.type || "", n = (f.name || "").toLowerCase();
  if (t.startsWith("image/")) return ["image", "teal"];
  if (t === "application/pdf" || n.endsWith(".pdf")) return ["file", "red"];
  if (/sheet|excel|csv/.test(t) || /\.(xlsx?|csv|numbers)$/.test(n)) return ["chart", "green"];
  if (/word|text|rtf/.test(t) || /\.(docx?|pages|txt|md)$/.test(n)) return ["note", "blue"];
  if (t.startsWith("video/")) return ["play", "purple"];
  return ["clip", "gray"];
}

function filesTab(b, { files }) {
  const syncOn = safe(() => sync.status().enabled, false);
  const list = files.slice().sort((x, y) => (y.created || 0) - (x.created || 0));
  const up = `<label class="upload" data-key="upload"><input type="file" multiple data-change="file-upload" data-bag="${b.id}" aria-label="Dateien hochladen" />${icon("upload")}<span><b>Dateien hinzufügen</b><small>Fotos, PDFs, Dokumente · bis ${fmtSize(LIMITS.fileMax)} pro Datei</small></span></label>`;
  if (!list.length) return up + empty({ emoji: "📎", title: "Noch keine Dateien", text: "Verträge, Screenshots, Präsentationen – sicher auf deinem Gerät gespeichert und per Sync auf deinen anderen Geräten." });
  return `${up}<div class="fgrid" data-key="fgrid">${list
    .map((f) => {
      const th = thumb(f);
      const [ic, col] = fileIcon(f);
      return `<div class="filec" data-key="f-${f.id}"><button type="button" class="fprev" data-act="file-open" data-id="${f.id}" aria-label="Öffnen: ${esc(f.name)}">${th ? `<img src="${esc(th)}" alt="" loading="lazy" />` : sq(ic, col)}</button><div class="finfo"><b title="${esc(f.name)}">${esc(f.name)}</b><small>${esc(fmtSize(f.size))}${f.size > LIMITS.syncFileMax ? ` · <span class="orange">nur auf diesem Gerät</span>` : syncOn && !f.synced ? ` · <span class="muted">wartet auf Sync</span>` : ""}</small></div><button type="button" class="btn-round sm ghost" data-act="file-menu" data-id="${f.id}" aria-label="Datei-Aktionen">${icon("ellipsis")}</button></div>`;
    })
    .join("")}</div>`;
}

async function uploadFiles(bagId, fileList) {
  const filesArr = [...(fileList || [])];
  if (!filesArr.length || !store.bag(bagId)) return;
  let ok = 0;
  for (const f of filesArr) {
    try {
      await store.addFile(bagId, f);
      ok++;
    } catch (e) {
      toastError(e, f.name);
    }
  }
  if (ok) {
    haptic();
    toast(ok === 1 ? "Datei hinzugefügt" : `${ok} Dateien hinzugefügt`, { icon: "clip", sub: store.bag(bagId)?.name || "" });
  }
}

export function pickFiles(bagId) {
  const inp = document.getElementById("file-in");
  if (!inp) return;
  inp.dataset.bag = bagId;
  inp.value = "";
  inp.click();
}

async function openFile(id, share = false) {
  const f = store.file(id);
  if (!f) return;
  try {
    const blob = await store.fileBlob(id);
    if (!blob) {
      toast("Datei ist auf diesem Gerät nicht vorhanden", { icon: "cloudOff", sub: "Sie liegt nur auf einem anderen Gerät" });
      return;
    }
    if (share) {
      const how = await remind.deliverFile(f.name, f.type || "application/octet-stream", blob);
      if (how === "downloaded") toast("Gespeichert", { icon: "download", sub: f.name });
      return;
    }
    const url = URL.createObjectURL(new Blob([blob], { type: f.type || blob.type || "application/octet-stream" }));
    const w = window.open(url, "_blank", "noopener");
    if (!w) await remind.deliverFile(f.name, f.type || "application/octet-stream", blob);
    setTimeout(() => URL.revokeObjectURL(url), 60000);
  } catch (e) {
    toastError(e);
  }
}

// ---------- Meilensteine ----------
function milestonesTab(b, { ms, all }) {
  const tdy = today();
  const items = ms.slice().sort((x, y) => (x.done ? 1 : 0) - (y.done ? 1 : 0) || String(x.date || "9999").localeCompare(String(y.date || "9999")));
  const head = `<div class="ms-head" data-key="ms-head"><button type="button" class="btn primary sm" data-act="ms-new" data-bag="${b.id}">${icon("plus")}<span>Meilenstein</span></button>${ms.some((m) => m.date && !m.done) ? `<button type="button" class="btn sm" data-act="ms-ics" data-bag="${b.id}">${icon("calendarPlus")}<span>In den Kalender</span></button>` : ""}</div>`;
  if (!items.length) return head + empty({ emoji: "🏁", title: "Noch keine Meilensteine", text: "Meilensteine sind die großen Etappen: Beta, Launch, Notartermin. Aufgaben kannst du ihnen zuordnen." });
  let nowPlaced = false;
  let h = `<div class="ms-tl" data-key="ms-tl">`;
  for (const m of items) {
    if (!nowPlaced && !m.done && (!m.date || m.date >= tdy)) {
      h += `<div class="ms-now" data-key="ms-now"><span>Heute</span></div>`;
      nowPlaced = true;
    }
    const linked = all.filter((t) => t.milestone === m.id);
    const ld = linked.filter((t) => t.done).length;
    const d = m.date ? safe(() => dates.diffDays(tdy, m.date), 0) : null;
    const late = !m.done && d != null && d < 0;
    h += `<div class="ms-item${m.done ? " done" : ""}${late ? " late" : ""}" data-key="ms-${m.id}">
<button type="button" class="ms-dot" data-act="ms-toggle" data-id="${m.id}" aria-pressed="${!!m.done}" aria-label="${m.done ? "Wieder öffnen" : "Als erreicht markieren"}">${icon(m.done ? "check" : "diamondFill")}</button>
<button type="button" class="ms-body" data-act="ms-open" data-id="${m.id}"><b>${esc(m.title)}</b><small>${m.done ? `Erreicht ${esc(relTime(m.done))}` : m.date ? esc([dayTitle(m.date).title, dayTitle(m.date).sub].filter(Boolean).join(" · ")) : "Ohne Datum"}${linked.length ? ` · ${ld}/${linked.length} Aufgaben` : ""}</small>${linked.length ? `<span class="bar sm"><i style="width:${Math.round((ld / linked.length) * 100)}%"></i></span>` : ""}</button>
</div>`;
  }
  return head + h + `</div>`;
}

// ---------- Verlauf ----------
const LOGI = { done: ["check", "green"], add: ["plus", "blue"], move: ["arrowRight", "indigo"], bag: ["bag", "orange"], note: ["note", "yellow"], link: ["link", "teal"], file: ["clip", "gray"], review: ["chart", "purple"], sync: ["sync", "cyan"], import: ["download", "gray"], seed: ["sparkle", "pink"] };
function logRow(e) {
  const [ic, col] = LOGI[e.kind] || ["dot", "gray"];
  return `<div class="logrow" data-key="lg-${e.id}">${sq(ic, col)}<span class="log-t">${esc(e.text)}</span><time>${esc(clockStr(e.t))}</time></div>`;
}

function historyTab(b) {
  const log = safe(() => store.logEntries(200, b.id), []);
  if (!log.length) return empty({ emoji: "🕰️", title: "Noch kein Verlauf", text: "Hier siehst du, was in dieser Tasche passiert ist." });
  const groups = new Map();
  for (const e of log) {
    const d = dates.toISO(new Date(e.t));
    if (!groups.has(d)) groups.set(d, []);
    groups.get(d).push(e);
  }
  return [...groups.entries()].map(([d, list]) => `<section class="log-day" data-key="ld-${d}"><h3 class="ov-h">${esc(safe(() => dates.relDay(d, app.now), d))} <small>${esc(safe(() => dates.fmtDay(d), d))}</small></h3><div class="card list log">${list.map(logRow).join("")}</div></section>`).join("");
}

// ---------- Notiz-Editor ----------
let ne = null;
const saveNote = debounce(() => {
  if (!ne) return;
  try {
    if (!ne.id) {
      if (!ne.title.trim() && !ne.body.trim()) return;
      const n = store.addNote({ bag: ne.bag, title: ne.title.trim() || firstLine(ne.body), body: ne.body, pinned: ne.pinned });
      ne.id = n.id;
    } else store.updateNote(ne.id, { title: ne.title.trim() || firstLine(ne.body), body: ne.body });
  } catch (e) {
    toastError(e);
  }
}, 450);
const firstLine = (s) => plain(String(s || "").split("\n")[0], 60) || "Notiz";

export function openNote(id, { bag = null } = {}) {
  const n = id ? store.note(id) : null;
  if (id && !n) return;
  ne = n ? { id: n.id, bag: n.bag, title: n.title || "", body: n.body || "", pinned: !!n.pinned, mode: n.body ? "view" : "edit" } : { id: null, bag: bag || store.bags()[0]?.id || null, title: "", body: "", pinned: false, mode: "edit" };
  if (!ne.bag) {
    toast("Lege zuerst eine Tasche an", { icon: "bag" });
    ne = null;
    return;
  }
  openSheet({
    key: "note",
    label: "Notiz",
    size: "large",
    render: noteView,
    onClose: () => {
      saveNote.flush();
      ne = null;
    },
  });
}

function noteView() {
  if (!ne) return "";
  const bag = store.bag(ne.bag);
  const cur = ne.id ? store.note(ne.id) : null;
  if (cur && !ne.dirty) {
    ne.pinned = !!cur.pinned;
  }
  return `${sheetHead(ne.id ? "Notiz" : "Neue Notiz", { sub: bag ? `${bag.emoji} ${bag.name}` : "", left: `<button type="button" class="btn-text bold" data-act="sheet-close">Fertig</button>`, right: `<span class="sh-btns">${ne.id ? `<button type="button" class="btn-round${ne.pinned ? " on" : ""}" data-act="note-pin" aria-label="Anpinnen" aria-pressed="${ne.pinned}">${icon("pin")}</button><button type="button" class="btn-round" data-act="note-del" aria-label="Löschen">${icon("trash")}</button>` : ""}</span>` })}
<div class="sheet-pad note-ed">
<input type="text" class="ne-title" value="${esc(ne.title)}" placeholder="Titel" data-input="ne-field" data-f="title" aria-label="Titel" ${ne.id ? "" : "autofocus"} enterkeyhint="next" />
<div class="ne-bar">${seg([{ id: "edit", label: "Schreiben", icon: "pencil" }, { id: "view", label: "Ansehen", icon: "eye" }], ne.mode, { act: "ne-mode", cls: "mini", label: "Modus" })}${ne.mode === "edit" ? `<span class="ne-tools"><button type="button" data-act="ne-ins" data-v="# " aria-label="Überschrift">H</button><button type="button" data-act="ne-ins" data-v="**" aria-label="Fett"><b>B</b></button><button type="button" data-act="ne-ins" data-v="- " aria-label="Liste">${icon("list")}</button><button type="button" data-act="ne-ins" data-v="- [ ] " aria-label="Checkbox">${icon("checklist")}</button></span>` : ""}</div>
${ne.mode === "edit" ? `<textarea class="ne-body grow" data-input="ne-field" data-f="body" placeholder="Schreib los … # Überschrift, **fett**, - Liste, - [ ] Checkbox" aria-label="Text">${esc(ne.body)}</textarea>` : `<div class="prose md" data-note="${ne.id || ""}">${ne.body.trim() ? markdown(ne.body, { checkAct: "ne-check" }) : `<p class="muted">Leer – tippe auf „Schreiben“.</p>`}</div>`}
${cur ? `<p class="fine">Geändert ${esc(relTime(cur.updated))}</p>` : ""}
</div>`;
}

// ---------- Link-Sheet ----------
let le = null;
export function openLink(id, { bag = null } = {}) {
  const l = id ? store.link(id) : null;
  le = l ? { id: l.id, bag: l.bag, url: l.url, title: l.title, touched: true } : { id: null, bag: bag || store.bags()[0]?.id || null, url: "", title: "", touched: false };
  if (!le.bag) {
    toast("Lege zuerst eine Tasche an", { icon: "bag" });
    le = null;
    return;
  }
  openSheet({ key: "link", label: "Link", render: linkView, onClose: () => (le = null) });
}

function autoTitle() {
  if (!le || le.touched) return;
  const u = safeUrl(/^[a-z]+:/i.test(le.url) ? le.url : "https://" + le.url);
  try {
    const x = new URL(u);
    const seg1 = x.pathname.split("/").filter(Boolean)[0] || "";
    const host = x.hostname.replace(/^www\./, "");
    le.title = seg1 ? `${host} › ${decodeURIComponent(seg1).replace(/[-_]+/g, " ")}` : host;
  } catch (_) {
    le.title = "";
  }
}

function linkView() {
  if (!le) return "";
  const u = safeUrl(/^[a-z]+:/i.test(le.url) ? le.url : le.url ? "https://" + le.url : "");
  return `${sheetHead(le.id ? "Link bearbeiten" : "Neuer Link", { left: `<button type="button" class="btn-text" data-act="sheet-close">Abbrechen</button>`, right: `<button type="button" class="btn-text bold" data-act="link-save"${u ? "" : " disabled"}>Sichern</button>` })}
<div class="sheet-pad">
<div class="card form">
<label class="frow input"><span class="frow-l">Adresse</span><input type="url" class="in-text" value="${esc(le.url)}" placeholder="https://…" data-input="le-field" data-f="url" ${le.id ? "" : "autofocus"} autocapitalize="off" autocorrect="off" inputmode="url" enterkeyhint="next" /></label>
<label class="frow input"><span class="frow-l">Titel</span><input type="text" class="in-text" value="${esc(le.title)}" placeholder="Name des Links" data-input="le-field" data-f="title" enterkeyhint="done" /></label>
<label class="frow input"><span class="frow-l">Tasche</span><select data-change="le-bag" aria-label="Tasche">${store.bags().map((b) => `<option value="${b.id}"${le.bag === b.id ? " selected" : ""}>${esc(b.emoji + " " + b.name)}</option>`).join("")}</select></label>
</div>
${le.url && !u ? `<p class="fine red">Nur http-, https- und mailto-Adressen sind erlaubt.</p>` : ""}
<button type="button" class="btn primary wide" data-act="link-save"${u ? "" : " disabled"}>${icon("link")}<span>${le.id ? "Speichern" : "Link hinzufügen"}</span></button>
</div>`;
}

// ---------- Meilenstein-Sheet ----------
let me = null;
export function openMilestone(id, { bag = null } = {}) {
  const m = id ? safe(() => store.milestones().find((x) => x.id === id), null) : null;
  me = m ? { id: m.id, bag: m.bag, title: m.title, date: m.date || "", done: !!m.done } : { id: null, bag: bag || store.bags()[0]?.id || null, title: "", date: "", done: false };
  if (!me.bag) {
    toast("Lege zuerst eine Tasche an", { icon: "bag" });
    me = null;
    return;
  }
  openSheet({ key: "milestone", label: "Meilenstein", size: me.id ? "large" : "", render: msView, onClose: () => (me = null) });
}

function msView() {
  if (!me) return "";
  const tasks = store.tasksOf(me.bag).filter((t) => !t.done || t.milestone === me.id).sort(byOrder);
  return `${sheetHead(me.id ? "Meilenstein" : "Neuer Meilenstein", { left: `<button type="button" class="btn-text" data-act="sheet-close">${me.id ? "Fertig" : "Abbrechen"}</button>`, right: me.id ? `<button type="button" class="btn-round" data-act="ms-del" aria-label="Löschen">${icon("trash")}</button>` : `<button type="button" class="btn-text bold" data-act="ms-save"${me.title.trim() ? "" : " disabled"}>Anlegen</button>` })}
<div class="sheet-pad">
<div class="card form">
<label class="frow input"><span class="frow-l">Titel</span><input type="text" class="in-text" value="${esc(me.title)}" placeholder="z. B. Go-Live" data-input="me-field" data-f="title" ${me.id ? "" : "autofocus"} enterkeyhint="done" /></label>
<label class="frow input"><span class="frow-l">Datum</span><input type="date" class="in-date" value="${esc(me.date)}" data-input="me-field" data-f="date" /></label>
${!me.id ? `<label class="frow input"><span class="frow-l">Tasche</span><select data-change="me-bag" aria-label="Tasche">${store.bags().map((b) => `<option value="${b.id}"${me.bag === b.id ? " selected" : ""}>${esc(b.emoji + " " + b.name)}</option>`).join("")}</select></label>` : `<div class="frow"><span class="frow-l">Erreicht</span><span class="frow-c">${toggle(me.done, `data-change="me-done"`, "Erreicht")}</span></div>`}
</div>
${me.id ? `<h3 class="form-h">Aufgaben zuordnen</h3>${tasks.length ? `<div class="card list">${tasks.map((t) => `<button type="button" class="pick${t.milestone === me.id ? " on" : ""}" data-key="pk-${t.id}" data-act="ms-assign" data-id="${t.id}" aria-pressed="${t.milestone === me.id}"><span class="pick-box">${icon("check")}</span><span class="pick-t">${esc(t.title)}${t.done ? " <small>· erledigt</small>" : ""}</span></button>`).join("")}</div>` : `<p class="fine">Diese Tasche hat noch keine offenen Aufgaben.</p>`}` : `<button type="button" class="btn primary wide" data-act="ms-save"${me.title.trim() ? "" : " disabled"}>${icon("diamond")}<span>Meilenstein anlegen</span></button>`}
</div>`;
}

const saveMs = debounce(() => {
  if (!me || !me.id) return;
  if (me.title.trim()) store.updateMilestone(me.id, { title: me.title.trim(), date: me.date || null });
}, 400);

// ---------- Kalender & Teilen ----------
function bagIcs(id) {
  const b = store.bag(id);
  if (!b) return;
  try {
    const s = store.get();
    const bagsById = { [b.id]: b };
    const tasks = store.tasksOf(id).filter((t) => !t.done && t.due);
    const ms = safe(() => store.milestones(id).filter((m) => !m.done && m.date), []);
    if (!tasks.length && !ms.length) {
      toast("Keine Termine in dieser Tasche", { icon: "calendar", sub: "Gib Aufgaben oder Meilensteinen ein Datum" });
      return;
    }
    let ics = tasks.length ? remind.icsForTasks(tasks, { bagsById, profile: s.profile, calName: b.name, appUrl: appUrl() }) : "";
    if (ms.length) ics = mergeIcs(ics, remind.icsForMilestones(ms, { bagsById, profile: s.profile, appUrl: appUrl() }));
    remind.deliverFile(`${slug(b.name)}.ics`, "text/calendar", ics).then((how) => how === "downloaded" && toast("Kalender-Datei geladen", { icon: "calendarCheck" })).catch((e) => toastError(e));
  } catch (e) {
    toastError(e);
  }
}

async function bagShare(id) {
  const b = store.bag(id);
  if (!b) return;
  const st = stats(id);
  const open = store.tasksOf(id).filter((t) => !t.done).sort(byOrder);
  const lines = [`${b.emoji} ${b.name}`, b.goal ? b.goal : "", st ? `Fortschritt: ${st.pct} % (${st.done}/${st.total})` : "", "", "Offen:", ...open.slice(0, 30).map((t) => `○ ${t.title}${t.due ? ` (${safe(() => dates.relDay(t.due, new Date()), t.due)})` : ""}`)].filter((x, i) => x || i === 3);
  const text = lines.join("\n");
  try {
    if (navigator.share) await navigator.share({ title: b.name, text });
    else {
      await navigator.clipboard.writeText(text);
      toast("Zusammenfassung kopiert", { icon: "copy" });
    }
  } catch (e) {
    if (e?.name !== "AbortError") toastError(e);
  }
}

// ---------- Ereignisse ----------
on("click", {
  "bag-tab": (el) => {
    const id = el.dataset.id, v = el.dataset.v;
    if (!id || !v) return;
    haptic();
    app.go(`#tasche/${id}/${v}`, { replace: true });
  },
  "bag-ics": (el) => bagIcs(el.dataset.id),
  "bag-share": (el) => bagShare(el.dataset.id),
  "bag-ai": (el) => {
    const b = store.bag(el.dataset.id);
    if (!b) return;
    askAI({
      kind: "next",
      title: `${b.emoji} ${b.name}: Was jetzt?`,
      question: `Was sind die nächsten sinnvollen Schritte für „${b.name}“?`,
      bagId: b.id,
      applyLabel: "Als Aufgaben anlegen",
      apply: (items) => {
        for (const it of items) store.addTask({ bag: b.id, title: it.title, due: it.due || null, prio: it.prio || 0 });
        toast(`${items.length} Aufgaben angelegt`, { icon: "sparkle" });
      },
    });
  },
  "step-act": (el) => runStep(el.dataset.id, +el.dataset.i),
  "sec-add": async (el) => {
    const b = store.bag(el.dataset.id);
    if (!b) return;
    const name = (await promptBox({ title: "Neuer Abschnitt", placeholder: "z. B. Vorbereitung", ok: "Anlegen" }))?.trim();
    if (!name) return;
    if ((b.sections || []).includes(name)) return toast("Den Abschnitt gibt es schon", { icon: "info" });
    store.updateBag(b.id, { sections: [...(b.sections || []), name] });
    haptic();
  },
  "sec-menu": (el) => {
    const b = store.bag(el.dataset.id);
    const s = el.dataset.sec;
    if (!b) return;
    const secs = b.sections || [];
    const i = secs.indexOf(s);
    openMenu(
      [
        { label: "Umbenennen", icon: "pencil", run: () => renameSection(b.id, s) },
        { label: "Nach vorn", icon: "chevronLeft", disabled: i <= 0, run: () => moveSection(b.id, s, -1) },
        { label: "Nach hinten", icon: "chevronRight", disabled: i < 0 || i >= secs.length - 1, run: () => moveSection(b.id, s, 1) },
        { label: "Aufgabe hinzufügen", icon: "plus", run: () => import("./capture.js").then((m) => m.openCapture({ bag: b.id, section: s })) },
        "-",
        { label: "Abschnitt löschen", icon: "trash", danger: true, hint: "Aufgaben bleiben erhalten", run: () => deleteSection(b.id, s) },
      ],
      { el, title: s },
    );
  },
  "note-new": (el) => openNote(null, { bag: el.dataset.bag }),
  "note-open": (el) => openNote(el.dataset.id),
  "note-pin": () => {
    if (!ne?.id) return;
    ne.pinned = !ne.pinned;
    store.updateNote(ne.id, { pinned: ne.pinned });
    haptic();
  },
  "note-del": async () => {
    if (!ne?.id) return;
    const id = ne.id;
    if (!(await confirmBox({ title: "Notiz löschen?", text: ne.title || "", ok: "Löschen", danger: true }))) return;
    saveNote.flush();
    ne = null;
    closeSheet(getSheet("note"));
    store.removeNote(id);
    toastUndo("Notiz gelöscht", { icon: "trash", tone: "red" });
  },
  "ne-mode": (el) => {
    if (!ne) return;
    saveNote.flush();
    ne.mode = el.dataset.v;
    getSheet("note")?.refresh();
    if (ne.mode === "edit") getSheet("note")?.body.querySelector(".ne-body")?.focus();
  },
  "ne-ins": (el) => {
    const ta = getSheet("note")?.body.querySelector(".ne-body");
    if (!ta || !ne) return;
    const v = el.dataset.v;
    const s = ta.selectionStart, e = ta.selectionEnd;
    const val = ta.value;
    let nv, pos;
    if (v === "**") {
      nv = val.slice(0, s) + "**" + val.slice(s, e) + "**" + val.slice(e);
      pos = e + 4;
    } else {
      const ls = val.lastIndexOf("\n", s - 1) + 1;
      nv = val.slice(0, ls) + v + val.slice(ls);
      pos = s + v.length;
    }
    ta.value = nv;
    ne.body = nv;
    ta.focus();
    ta.setSelectionRange(pos, pos);
    saveNote();
  },
  "ne-check": (el) => {
    if (!ne) return;
    ne.body = toggleCheckLine(ne.body, +el.dataset.line);
    haptic();
    saveNote();
    saveNote.flush();
    getSheet("note")?.refresh();
  },
  "link-new": (el) => openLink(null, { bag: el.dataset.bag }),
  "link-menu": (el) => {
    const l = store.link(el.dataset.id);
    if (!l) return;
    const u = safeUrl(l.url);
    openMenu(
      [
        u ? { label: "Öffnen", icon: "arrowUpRight", run: () => window.open(u, "_blank", "noopener") } : null,
        { label: "Adresse kopieren", icon: "copy", run: () => navigator.clipboard?.writeText(l.url).then(() => toast("Kopiert", { icon: "copy" })).catch(() => {}) },
        { label: "Bearbeiten", icon: "pencil", run: () => openLink(l.id) },
        "-",
        { label: "Löschen", icon: "trash", danger: true, run: () => { store.removeLink(l.id); toastUndo("Link gelöscht", { icon: "trash", tone: "red" }); } },
      ].filter(Boolean),
      { el, title: l.title },
    );
  },
  "link-save": () => {
    if (!le) return;
    const u = safeUrl(/^[a-z]+:/i.test(le.url) ? le.url : "https://" + le.url);
    if (!u) return;
    const title = le.title.trim() || hostOf(u) || u;
    try {
      if (le.id) store.updateLink(le.id, { url: u, title, bag: le.bag });
      else store.addLink({ bag: le.bag, url: u, title });
      haptic();
      closeSheet(getSheet("link"));
      toast(le?.id ? "Gespeichert" : "Link hinzugefügt", { icon: "link", sub: title });
    } catch (e) {
      toastError(e);
    }
  },
  "file-open": (el) => openFile(el.dataset.id),
  "file-menu": (el) => {
    const f = store.file(el.dataset.id);
    if (!f) return;
    openMenu(
      [
        { label: "Öffnen", icon: "eye", run: () => openFile(f.id) },
        { label: "Teilen / Sichern", icon: "share", run: () => openFile(f.id, true) },
        { label: "Umbenennen", icon: "pencil", run: async () => { const n = (await promptBox({ title: "Datei umbenennen", value: f.name, ok: "Sichern" }))?.trim(); if (n && store.updateFile) store.updateFile(f.id, { name: n }); else if (n) toast("Umbenennen wird hier nicht unterstützt", { icon: "info" }); } },
        "-",
        { label: "Löschen", icon: "trash", danger: true, run: async () => { if (await confirmBox({ title: "Datei löschen?", text: f.name, ok: "Löschen", danger: true })) { const u = thumbs.get(f.id); if (u && u.startsWith("blob:")) URL.revokeObjectURL(u); thumbs.delete(f.id); store.removeFile(f.id); toast("Datei gelöscht", { icon: "trash", tone: "red" }); } } },
      ],
      { el, title: f.name },
    );
  },
  "ms-new": (el) => openMilestone(null, { bag: el.dataset.bag }),
  "ms-open": (el) => openMilestone(el.dataset.id),
  "ms-toggle": (el) => {
    const m = safe(() => store.milestones().find((x) => x.id === el.dataset.id), null);
    if (!m) return;
    store.toggleMilestone(m.id);
    haptic();
    if (!m.done) {
      const b = store.bag(m.bag);
      const c = COLORS[b?.color] || COLORS.blue;
      confetti({ colors: [c[0], c[1], "#FFCC00", "#FFFFFF"], count: 110 });
      sound("all");
      toastUndo("Meilenstein erreicht!", { icon: "trophy", sub: m.title });
    }
  },
  "ms-save": () => {
    if (!me || !me.title.trim()) return;
    try {
      store.addMilestone({ bag: me.bag, title: me.title.trim(), date: me.date || null });
      haptic();
      closeSheet(getSheet("milestone"));
      toast("Meilenstein angelegt", { icon: "diamond", sub: me?.title || "" });
    } catch (e) {
      toastError(e);
    }
  },
  "ms-del": async () => {
    if (!me?.id) return;
    const id = me.id;
    if (!(await confirmBox({ title: "Meilenstein löschen?", text: me.title, ok: "Löschen", danger: true }))) return;
    closeSheet(getSheet("milestone"));
    store.removeMilestone(id);
    toastUndo("Meilenstein gelöscht", { icon: "trash", tone: "red" });
  },
  "ms-assign": (el) => {
    if (!me?.id) return;
    const t = store.task(el.dataset.id);
    if (!t) return;
    store.updateTask(t.id, { milestone: t.milestone === me.id ? null : me.id });
    haptic();
  },
  "ms-ics": (el) => {
    const bagsById = Object.fromEntries(store.bags().map((b) => [b.id, b]));
    const ms = safe(() => store.milestones(el.dataset.bag).filter((m) => !m.done && m.date), []);
    if (!ms.length) return;
    try {
      remind.deliverFile(`meilensteine-${slug(store.bag(el.dataset.bag)?.name)}.ics`, "text/calendar", remind.icsForMilestones(ms, { bagsById, profile: store.get().profile, appUrl: appUrl() })).catch((e) => toastError(e));
    } catch (e) {
      toastError(e);
    }
  },
});

on("input", {
  "ne-field": (el) => {
    if (!ne) return;
    ne[el.dataset.f] = el.value;
    if (el.nodeName === "TEXTAREA") {
      el.style.height = "auto";
      el.style.height = Math.max(220, el.scrollHeight) + "px";
    }
    saveNote();
  },
  "le-field": (el) => {
    if (!le) return;
    le[el.dataset.f] = el.value;
    if (el.dataset.f === "title") le.touched = !!el.value.trim();
    if (el.dataset.f === "url") autoTitle();
    getSheet("link")?.refresh();
  },
  "me-field": (el) => {
    if (!me) return;
    me[el.dataset.f] = el.value;
    if (me.id) saveMs();
    getSheet("milestone")?.refresh();
  },
});

on("change", {
  "file-upload": (el) => {
    uploadFiles(el.dataset.bag, el.files);
    el.value = "";
  },
  "le-bag": (el) => le && (le.bag = el.value),
  "me-bag": (el) => me && (me.bag = el.value),
  "me-done": (el) => {
    if (!me?.id) return;
    const m = safe(() => store.milestones().find((x) => x.id === me.id), null);
    if (m && !!m.done !== el.checked) store.toggleMilestone(me.id);
    me.done = el.checked;
  },
});

on("submit", {
  "inline-add": (form, e) => {
    e.preventDefault();
    const inp = form.querySelector("input");
    const v = inp.value.trim();
    if (!v) return;
    const bagId = form.dataset.bag, section = form.dataset.sec || "";
    try {
      const pq = safe(() => dates.parseQuick(v, { bags: store.bags(), now: new Date(), profile: store.get().profile }), null);
      const t = pq
        ? { title: pq.title || v, due: pq.due, time: pq.time, prio: pq.prio || 0, bag: pq.bag || bagId, tags: pq.tags || [], remind: pq.remind, repeat: pq.repeat, someday: !!pq.someday, est: pq.est, plan: pq.plan ? today() : null, section: pq.bag && pq.bag !== bagId ? "" : section }
        : { title: v, bag: bagId, section };
      store.addTask(t);
      inp.value = "";
      haptic();
    } catch (err) {
      toastError(err);
    }
  },
});

// Datei-Eingabe aus dem Plus-Menü
document.addEventListener("change", (e) => {
  if (e.target?.id === "file-in") {
    uploadFiles(e.target.dataset.bag, e.target.files);
    e.target.value = "";
  }
});

// ---------- Abschnitte ----------
async function renameSection(bagId, s) {
  const b = store.bag(bagId);
  if (!b) return;
  const name = (await promptBox({ title: "Abschnitt umbenennen", value: s, ok: "Sichern" }))?.trim();
  if (!name || name === s) return;
  store.updateBag(bagId, { sections: (b.sections || []).map((x) => (x === s ? name : x)) });
  for (const t of store.tasksOf(bagId)) if (t.section === s) store.updateTask(t.id, { section: name });
}

function moveSection(bagId, s, dir) {
  const b = store.bag(bagId);
  if (!b) return;
  const secs = [...(b.sections || [])];
  const i = secs.indexOf(s), j = i + dir;
  if (i < 0 || j < 0 || j >= secs.length) return;
  [secs[i], secs[j]] = [secs[j], secs[i]];
  store.updateBag(bagId, { sections: secs });
}

async function deleteSection(bagId, s) {
  const b = store.bag(bagId);
  if (!b) return;
  const n = store.tasksOf(bagId).filter((t) => t.section === s).length;
  if (n && !(await confirmBox({ title: `„${s}“ löschen?`, text: `${n} ${n === 1 ? "Aufgabe wandert" : "Aufgaben wandern"} nach „Ohne Abschnitt“.`, ok: "Löschen", danger: true }))) return;
  for (const t of store.tasksOf(bagId)) if (t.section === s) store.updateTask(t.id, { section: "" });
  store.updateBag(bagId, { sections: (b.sections || []).filter((x) => x !== s) });
}

// ---------- Ziehen: Board-Spalten und Abschnitte ----------
onDrop("section", (id, zone, beforeId) => {
  const t = store.task(id);
  if (!t) return;
  const bagId = zone.dataset.bag, section = zone.dataset.sec || "";
  if (t.bag !== bagId || (t.section || "") !== section) store.moveTask(id, bagId, section);
  if (beforeId !== id) store.reorderTask(id, beforeId || null);
});

