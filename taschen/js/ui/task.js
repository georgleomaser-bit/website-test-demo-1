// Arbeitstaschen – Aufgaben-Detail: Sheet auf dem iPhone, Inspektor-Spalte auf breiten Bildschirmen; alles speichert sofort
import * as store from "../store.js";
import * as dates from "../dates.js";
import * as remind from "../remind.js";
import { PRIOS, REPEATS } from "../config.js";
import { esc, debounce } from "../util.js";
import { icon, CHECK } from "./icons.js";
import { app, on, today, tomorrow, weekendISO, nextWeekISO, relTime, safe, appUrl, slug, bagVars, autoGrow, growAll } from "./core.js";
import { pending, seg, sq } from "./components.js";
import { openSheet, closeSheet, getSheet, promptBox, openMenu } from "./sheet.js";
import { haptic, toast, toastError } from "./fx.js";
import { confirmDelete, duplicateTask } from "./actions.js";
import { askAI } from "./aiui.js";

let currentId = null; // Aufgabe im Sheet

// ---------- Öffnen / Schließen ----------
export function openTask(id) {
  const t = store.task(id);
  if (!t) {
    toast("Aufgabe nicht gefunden", { icon: "info" });
    return;
  }
  if (app.inspector) {
    flushSaves();
    app.selected = id;
    app.render();
    requestAnimationFrame(() => document.querySelector("#inspector .td")?.scrollTo?.({ top: 0 }));
    return;
  }
  flushSaves();
  currentId = id;
  const ex = getSheet("task");
  if (ex) {
    ex.refresh();
    ex.box.scrollTop = 0;
    return;
  }
  openSheet({
    key: "task",
    label: "Aufgabe",
    size: "large",
    render: () => taskDetail(currentId),
    onClose: () => {
      flushSaves();
      currentId = null;
    },
  });
}

export function closeTaskIfOpen(id) {
  if (app.selected === id) {
    app.selected = null;
    app.render();
  }
  if (currentId === id) {
    const s = getSheet("task");
    if (s) closeSheet(s);
  }
}

function closeDetail() {
  flushSaves();
  if (app.inspector && app.selected) {
    app.selected = null;
    app.render();
    return;
  }
  const s = getSheet("task");
  if (s) closeSheet(s);
}

// Wenn das Fenster schmal wird, Inspektor-Aufgabe ins Sheet übernehmen
export function inspectorToSheet() {
  if (app.selected && !app.inspector) {
    const id = app.selected;
    app.selected = null;
    openTask(id);
  }
}

// ---------- Text speichern (entprellt) ----------
const savers = new Map();
function saver(field, id) {
  const k = field + ":" + id;
  if (!savers.has(k))
    savers.set(
      k,
      debounce((v) => {
        if (!store.task(id)) return;
        if (field === "title") {
          const t = v.replace(/\s*\n+\s*/g, " ").trim();
          if (t) store.updateTask(id, { title: t });
        } else store.updateTask(id, { [field]: v });
      }, 400),
    );
  return savers.get(k);
}
export function flushSaves() {
  for (const [k, d] of savers) {
    const el = document.querySelector(`[data-save="${CSS.escape(k)}"]`);
    if (el) d.flush(el.value);
  }
  savers.clear();
}

// ---------- Darstellung ----------
const REMINDS = [
  { v: "", l: "Standard" },
  { v: "-1", l: "Keine" },
  { v: "0", l: "Zum Termin" },
  { v: "5", l: "5 Min. vorher" },
  { v: "15", l: "15 Min. vorher" },
  { v: "30", l: "30 Min. vorher" },
  { v: "60", l: "1 Std. vorher" },
  { v: "120", l: "2 Std. vorher" },
  { v: "1440", l: "1 Tag vorher" },
];
const ESTS = [null, 5, 10, 15, 30, 45, 60, 90, 120, 180, 240, 480];

const opt = (v, l, sel) => `<option value="${esc(v)}"${sel ? " selected" : ""}>${esc(l)}</option>`;

function row(ic, color, label, control, { cls = "", sub = "" } = {}) {
  return `<div class="frow${cls ? " " + cls : ""}">${sq(ic, color)}<span class="frow-l">${esc(label)}${sub ? `<small>${sub}</small>` : ""}</span><span class="frow-c">${control}</span></div>`;
}

export function taskDetail(id, { inspector = false } = {}) {
  const t = id ? store.task(id) : null;
  if (!t) {
    if (!inspector && id) setTimeout(() => closeTaskIfOpen(id), 0);
    return inspector ? "" : `<div class="sheet-pad"><p class="muted">Diese Aufgabe gibt es nicht mehr.</p></div>`;
  }
  const s = store.get();
  const p = s.profile;
  const bag = t.bag ? store.bag(t.bag) : null;
  const bags = store.bags();
  const done = !!t.done || pending.has(t.id);
  const tdy = today();
  const isToday = t.plan === tdy;
  const ms = bag ? safe(() => store.milestones(bag.id), []) : [];
  const sections = bag ? bag.sections || [] : [];
  const defRemind = p.defaultRemind ?? 15;
  const remindVal = t.remind == null ? "" : String(t.remind);
  const remindOpts = REMINDS.map((r) => opt(r.v, r.v === "" ? `Standard (${defRemind ? defRemind + " Min." : "zum Termin"})` : r.l, r.v === remindVal)).join("") + (remindVal && !REMINDS.some((r) => r.v === remindVal) ? opt(remindVal, `${remindVal} Min. vorher`, true) : "");
  const quick = [
    { k: "today", l: "Heute", iso: tdy, ic: "sun" },
    { k: "tomorrow", l: "Morgen", iso: tomorrow(), ic: "sunrise" },
    { k: "weekend", l: "Wochenende", iso: weekendISO(), ic: "calendar" },
    { k: "nextweek", l: "Nächste Woche", iso: nextWeekISO(), ic: "calendarPlus" },
  ];
  const subs = t.subtasks || [];
  const subDone = subs.filter((x) => x.done).length;
  const created = t.created ? relTime(t.created) : "";
  const changed = t.updated ? relTime(t.updated) : "";
  const remAt = safe(() => dates.remindAt(t, p), null);
  const titleKey = "title:" + t.id, notesKey = "notes:" + t.id;

  return `<div class="td${inspector ? " in-insp" : ""}" data-key="td-${t.id}" style="${bagVars(bag)}">
<header class="td-head">
<button type="button" class="td-bag" data-act="td-bag-menu" data-id="${t.id}" aria-label="Tasche ändern"><span class="bdot"></span><span>${bag ? `${esc(bag.emoji)} ${esc(bag.name)}` : "📥 Eingang"}</span>${t.section ? `<span class="td-sec">› ${esc(t.section)}</span>` : ""}${icon("chevronDown")}</button>
<span class="td-head-r"><button type="button" class="btn-round" data-act="task-menu" data-id="${t.id}" aria-label="Mehr">${icon("ellipsis")}</button><button type="button" class="btn-round" data-act="td-close" aria-label="Schließen">${icon(inspector ? "sidebar" : "x")}</button></span>
</header>
<div class="td-main">
<div class="td-title-row${done ? " done" : ""}${t.prio === 3 ? " p3" : ""}">
<button class="check big" type="button" data-act="toggle" data-id="${t.id}" aria-label="${done ? "Wieder öffnen" : "Erledigen"}" aria-pressed="${done}">${CHECK}</button>
<textarea class="td-title" rows="1" data-input="td-text" data-field="title" data-id="${t.id}" data-save="${titleKey}" data-key-act="td-title-key" placeholder="Was ist zu tun?" aria-label="Titel" enterkeyhint="done">${esc(t.title)}</textarea>
</div>
<textarea class="td-notes" rows="2" data-input="td-text" data-field="notes" data-id="${t.id}" data-save="${notesKey}" placeholder="Notizen" aria-label="Notizen">${esc(t.notes || "")}</textarea>
</div>

<div class="td-chips hscroll">
<button type="button" class="chip${isToday ? " on accent" : ""}" data-act="td-plan" data-id="${t.id}">${icon(isToday ? "starFill" : "star")}<span>${isToday ? "Heute eingeplant" : "Heute einplanen"}</span></button>
<span class="chip-lab">Fällig</span>
${quick.map((q) => `<button type="button" class="chip${t.due === q.iso ? " on" : ""}" data-act="td-due" data-id="${t.id}" data-iso="${q.iso}">${icon(q.ic)}<span>${q.l}</span></button>`).join("")}
<button type="button" class="chip${t.someday ? " on" : ""}" data-act="td-someday" data-id="${t.id}">${icon("moon")}<span>Irgendwann</span></button>
${t.due ? `<button type="button" class="chip ghost" data-act="td-due" data-id="${t.id}" data-iso="">${icon("x")}<span>Kein Datum</span></button>` : ""}
</div>

<section class="td-block">
<h3 class="td-h">Unteraufgaben${subs.length ? ` <span>${subDone}/${subs.length}</span>` : ""}</h3>
<div class="card list subs">
${subs.map((x) => `<div class="sub${x.done ? " done" : ""}" data-key="s-${x.id}"><button type="button" class="check small" data-act="sub-toggle" data-id="${t.id}" data-sub="${x.id}" aria-pressed="${x.done}" aria-label="Unteraufgabe erledigen">${CHECK}</button><input class="sub-in" type="text" value="${esc(x.title)}" data-change="sub-title" data-key-act="sub-key" data-id="${t.id}" data-sub="${x.id}" aria-label="Unteraufgabe" enterkeyhint="done" /><button type="button" class="sub-x" data-act="sub-del" data-id="${t.id}" data-sub="${x.id}" aria-label="Unteraufgabe löschen">${icon("x")}</button></div>`).join("")}
<div class="sub add" data-key="sub-add"><span class="sub-plus">${icon("plus")}</span><input class="sub-in" type="text" placeholder="Unteraufgabe hinzufügen" data-key-act="sub-add" data-id="${t.id}" aria-label="Neue Unteraufgabe" enterkeyhint="enter" /></div>
</div>
${app.ai ? `<button type="button" class="btn ai sm" data-act="td-ai" data-id="${t.id}">${icon("sparkle")}<span>In Schritte zerlegen</span></button>` : ""}
</section>

<section class="td-block">
<div class="card form">
${row("calendar", "red", "Datum", `<input type="date" class="in-date" value="${esc(t.due || "")}" data-change="td-date" data-id="${t.id}" aria-label="Fälligkeitsdatum" />`, { sub: t.due ? esc(safe(() => dates.fmtDay(t.due), t.due)) : "" })}
${row("clock", "blue", "Uhrzeit", `<input type="time" class="in-time" value="${esc(t.time || "")}" data-change="td-time" data-id="${t.id}" aria-label="Uhrzeit" />${t.time ? `<button type="button" class="mini-x" data-act="td-notime" data-id="${t.id}" aria-label="Uhrzeit entfernen">${icon("x")}</button>` : ""}`)}
${row("bell", "orange", "Erinnerung", `<select data-change="td-remind" data-id="${t.id}" aria-label="Erinnerung"${t.time ? "" : " disabled"}>${remindOpts}</select>`, { sub: t.time ? (remAt ? `um ${esc(remAt.toLocaleTimeString("de-DE", { hour: "numeric", minute: "2-digit" }))}${t.due !== tdy ? ", " + esc(safe(() => dates.relDay(dates.toISO(remAt), app.now), "")) : ""}` : "aus") : "nur mit Uhrzeit" })}
${row("repeat", "gray", "Wiederholen", `<select data-change="td-repeat" data-id="${t.id}" aria-label="Wiederholung">${REPEATS.map((r) => opt(r.id || "", r.label, (t.repeat || "") === (r.id || ""))).join("")}</select>`)}
</div>
</section>

<section class="td-block">
<div class="card form">
<div class="frow">${sq("flag", "red")}<span class="frow-l">Priorität</span><span class="frow-c">${seg(PRIOS.map((x) => ({ id: String(x.id), label: x.id ? x.mark : "Keine" })), String(t.prio || 0), { act: "td-prio", attrs: `data-id="${t.id}"`, cls: "mini", label: "Priorität" })}</span></div>
${row("hourglass", "indigo", "Dauer", `<select data-change="td-est" data-id="${t.id}" aria-label="Geschätzte Dauer">${ESTS.map((m) => opt(m == null ? "" : String(m), m == null ? "Keine" : safe(() => dates.fmtDuration(m), m + " Min."), (t.est ?? null) === m)).join("")}${t.est && !ESTS.includes(t.est) ? opt(String(t.est), safe(() => dates.fmtDuration(t.est), t.est + " Min."), true) : ""}</select>`)}
</div>
</section>

<section class="td-block">
<div class="card form">
${row("bag", bag ? bag.color : "gray", "Tasche", `<select data-change="td-bag" data-id="${t.id}" aria-label="Tasche">${opt("", "📥 Eingang", !t.bag)}${bags.map((b) => opt(b.id, `${b.emoji} ${b.name}`, t.bag === b.id)).join("")}</select>`)}
${bag ? row("list", "teal", "Abschnitt", `<select data-change="td-section" data-id="${t.id}" aria-label="Abschnitt">${opt("", "Ohne Abschnitt", !t.section)}${sections.map((x) => opt(x, x, t.section === x)).join("")}${t.section && !sections.includes(t.section) ? opt(t.section, t.section, true) : ""}${opt("__new", "Neuer Abschnitt …", false)}</select>`) : ""}
${bag ? row("diamond", "purple", "Meilenstein", `<select data-change="td-milestone" data-id="${t.id}" aria-label="Meilenstein">${opt("", "Keiner", !t.milestone)}${ms.map((m) => opt(m.id, `${m.title}${m.date ? " · " + safe(() => dates.relDay(m.date, app.now), m.date) : ""}`, t.milestone === m.id)).join("")}</select>`) : ""}
${row("person", "pink", "Wartet auf", `<input type="text" class="in-text" value="${esc(t.waiting || "")}" placeholder="Person oder Sache" data-change="td-waiting" data-key-act="blur-enter" data-id="${t.id}" aria-label="Wartet auf" enterkeyhint="done" />`)}
${row("tag", "green", "Tags", `<input type="text" class="in-text" value="${esc((t.tags || []).map((x) => "#" + x).join(" "))}" placeholder="#idee #kunde" data-change="td-tags" data-key-act="blur-enter" data-id="${t.id}" aria-label="Tags" autocapitalize="off" enterkeyhint="done" />`)}
</div>
</section>

<div class="td-actions">
${!t.done ? `<button type="button" class="act" data-act="task-focus" data-id="${t.id}">${icon("target")}<span>Fokus</span></button>` : ""}
<button type="button" class="act" data-act="td-ics" data-id="${t.id}"${t.due ? "" : ` disabled title="Erst ein Datum wählen"`}>${icon("calendarPlus")}<span>Kalender</span></button>
<button type="button" class="act" data-act="td-dup" data-id="${t.id}">${icon("copy")}<span>Duplizieren</span></button>
<button type="button" class="act" data-act="td-share" data-id="${t.id}">${icon("share")}<span>Teilen</span></button>
<button type="button" class="act red" data-act="td-del" data-id="${t.id}">${icon("trash")}<span>Löschen</span></button>
</div>
<p class="td-foot">${t.done ? `Erledigt ${esc(relTime(t.done))} · ` : ""}Erstellt ${esc(created)}${changed && t.updated !== t.created ? ` · geändert ${esc(changed)}` : ""}</p>
</div>`;
}

// ---------- Hilfen ----------
function setDueDate(id, iso) {
  const t = store.task(id);
  if (!t) return;
  const patch = { due: iso || null };
  if (iso) patch.someday = false;
  else patch.time = null;
  store.updateTask(id, patch);
  haptic();
}

function bagMenu(id, el) {
  const t = store.task(id);
  if (!t) return;
  const bags = store.bags();
  openMenu([{ label: "Eingang", emoji: "📥", check: !t.bag, run: () => store.moveTask(id, null, "") }, ...bags.map((b) => ({ label: b.name, emoji: b.emoji, check: t.bag === b.id, run: () => store.moveTask(id, b.id, "") }))], { el, title: "In Tasche verschieben" });
}

function parseTags(v) {
  return [...new Set(String(v || "").split(/[\s,;]+/).map((x) => x.replace(/^[#@]+/, "").trim()).filter(Boolean))].slice(0, 12);
}

// ---------- Ereignisse ----------
on("input", {
  "td-text": (el) => {
    autoGrow(el);
    saver(el.dataset.field, el.dataset.id)(el.value);
  },
});

on("keydown", {
  "td-title-key": (el, e) => {
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      saver("title", el.dataset.id).flush(el.value);
      el.blur();
    }
  },
  "sub-add": (el, e) => {
    if (e.key !== "Enter" || e.isComposing) return;
    e.preventDefault();
    const v = el.value.trim();
    if (!v) return;
    try {
      store.addSubtask(el.dataset.id, v);
      el.value = "";
      haptic();
    } catch (err) {
      toastError(err);
    }
  },
  "sub-key": (el, e) => {
    if (e.key === "Enter" && !e.isComposing) {
      e.preventDefault();
      el.blur();
    } else if (e.key === "Backspace" && !el.value) {
      e.preventDefault();
      store.removeSubtask(el.dataset.id, el.dataset.sub);
    }
  },
  "blur-enter": (el, e) => {
    if (e.key === "Enter" && !e.isComposing) {
      e.preventDefault();
      el.blur();
    }
  },
});

on("change", {
  "td-date": (el) => setDueDate(el.dataset.id, el.value),
  "td-time": (el) => {
    const id = el.dataset.id, t = store.task(id);
    if (!t) return;
    const v = el.value || null;
    const patch = { time: v };
    if (v && !t.due) {
      const now = new Date();
      const [h, m] = v.split(":").map(Number);
      patch.due = h * 60 + m > now.getHours() * 60 + now.getMinutes() ? today() : tomorrow();
      patch.someday = false;
    }
    store.updateTask(id, patch);
  },
  "td-remind": (el) => store.updateTask(el.dataset.id, { remind: el.value === "" ? null : Number(el.value) }),
  "td-repeat": (el) => {
    const t = store.task(el.dataset.id);
    if (!t) return;
    const patch = { repeat: el.value || null };
    if (el.value && !t.due) patch.due = today();
    store.updateTask(t.id, patch);
  },
  "td-est": (el) => store.updateTask(el.dataset.id, { est: el.value ? Number(el.value) : null }),
  "td-plan-sw": (el) => {
    store.planTask(el.dataset.id, el.checked ? today() : null);
    haptic();
  },
  "td-bag": (el) => {
    store.moveTask(el.dataset.id, el.value || null, "");
    haptic();
  },
  "td-section": async (el) => {
    const t = store.task(el.dataset.id);
    if (!t) return;
    if (el.value === "__new") {
      const name = (await promptBox({ title: "Neuer Abschnitt", placeholder: "z. B. Vorbereitung", ok: "Anlegen" }))?.trim();
      if (!name) {
        app.render();
        return;
      }
      const bag = store.bag(t.bag);
      if (bag && !(bag.sections || []).includes(name)) store.updateBag(bag.id, { sections: [...(bag.sections || []), name] });
      store.updateTask(t.id, { section: name });
      return;
    }
    store.updateTask(t.id, { section: el.value });
  },
  "td-milestone": (el) => store.updateTask(el.dataset.id, { milestone: el.value || null }),
  "td-waiting": (el) => store.updateTask(el.dataset.id, { waiting: el.value.trim() }),
  "td-tags": (el) => store.updateTask(el.dataset.id, { tags: parseTags(el.value) }),
  "sub-title": (el) => {
    const v = el.value.trim();
    if (v) store.updateSubtask(el.dataset.id, el.dataset.sub, v);
    else store.removeSubtask(el.dataset.id, el.dataset.sub);
  },
});

on("click", {
  "td-close": () => closeDetail(),
  "td-bag-menu": (el) => bagMenu(el.dataset.id, el),
  "td-plan": (el) => {
    const t = store.task(el.dataset.id);
    if (!t) return;
    store.planTask(t.id, t.plan === today() ? null : today());
    haptic();
  },
  "td-due": (el) => {
    const t = store.task(el.dataset.id);
    if (!t) return;
    setDueDate(t.id, t.due === el.dataset.iso ? "" : el.dataset.iso);
  },
  "td-someday": (el) => {
    const t = store.task(el.dataset.id);
    if (!t) return;
    store.updateTask(t.id, t.someday ? { someday: false } : { someday: true, due: null, time: null, plan: null });
    haptic();
  },
  "td-notime": (el) => store.updateTask(el.dataset.id, { time: null }),
  "td-prio": (el) => {
    store.updateTask(el.dataset.id, { prio: Number(el.dataset.v) });
    haptic();
  },
  "sub-toggle": (el) => {
    store.toggleSubtask(el.dataset.id, el.dataset.sub);
    haptic();
  },
  "sub-del": (el) => store.removeSubtask(el.dataset.id, el.dataset.sub),
  "td-dup": (el) => {
    const c = duplicateTask(el.dataset.id);
    if (c) openTask(c.id);
  },
  "td-del": (el) => confirmDelete(el.dataset.id),
  "td-ics": (el) => exportTaskIcs(el.dataset.id),
  "td-share": (el) => shareTask(el.dataset.id),
  "td-ai": (el) => {
    const t = store.task(el.dataset.id);
    if (!t) return;
    askAI({
      kind: "breakdown",
      title: "In Schritte zerlegen",
      question: t.title + (t.notes ? "\n" + t.notes : ""),
      taskId: t.id,
      bagId: t.bag,
      applyLabel: "Als Unteraufgaben",
      apply: (items) => {
        for (const it of items) safe(() => store.addSubtask(t.id, it.title));
        toast(`${items.length} Unteraufgaben ergänzt`, { icon: "sparkle" });
      },
    });
  },
});

// ---------- Kalender & Teilen ----------
export function exportTaskIcs(id) {
  const t = store.task(id);
  if (!t || !t.due) return;
  try {
    const s = store.get();
    const bagsById = Object.fromEntries(store.bags().map((b) => [b.id, b]));
    const ics = remind.icsForTasks([t], { bagsById, profile: s.profile, calName: "Arbeitstaschen", appUrl: appUrl() });
    remind
      .deliverFile(`${slug(t.title)}.ics`, "text/calendar", ics)
      .then((how) => how === "downloaded" && toast("Kalender-Datei geladen", { icon: "calendarCheck", sub: "Öffnen → „Hinzufügen“" }))
      .catch((e) => toastError(e));
  } catch (e) {
    toastError(e);
  }
}

async function shareTask(id) {
  const t = store.task(id);
  if (!t) return;
  const bag = t.bag ? store.bag(t.bag) : null;
  const lines = [t.title];
  if (t.due) lines.push(`📅 ${safe(() => dates.fmtDay(t.due), t.due)}${t.time ? ", " + t.time + " Uhr" : ""}`);
  if (bag) lines.push(`${bag.emoji} ${bag.name}`);
  if (t.notes) lines.push("", t.notes);
  if ((t.subtasks || []).length) lines.push("", ...t.subtasks.map((x) => `${x.done ? "✓" : "○"} ${x.title}`));
  const text = lines.join("\n");
  try {
    if (navigator.share) await navigator.share({ title: t.title, text });
    else {
      await navigator.clipboard.writeText(text);
      toast("Kopiert", { icon: "copy" });
    }
  } catch (e) {
    if (e?.name !== "AbortError") {
      try {
        await navigator.clipboard.writeText(text);
        toast("Kopiert", { icon: "copy" });
      } catch (_) {
        toastError(e);
      }
    }
  }
}

// ---------- Textfelder wachsen mit (aus core) ----------
export { autoGrow, growAll };

export const currentTask = () => currentId;
