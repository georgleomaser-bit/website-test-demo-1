// Arbeitstaschen – „Taschen“: Raster mit Fortschrittsringen, Gesundheit und nächstem Schritt; Neue Tasche mit Vorlagen
import * as store from "../store.js";
import * as dates from "../dates.js";
import * as pm from "../pm.js";
import { COLORS, COLOR_NAMES, EMOJIS } from "../config.js";
import { esc } from "../util.js";
import { icon } from "./icons.js";
import { app, on, safe, bagVars, colorVars, today, isCollapsed } from "./core.js";
import { ring, healthPill, largeTitle, empty, seg, toggle } from "./components.js";
import { openSheet, sheetHead, getSheet, closeSheet, openMenu, confirmBox } from "./sheet.js";
import { haptic, toast, toastUndo, toastError, confetti, sound } from "./fx.js";
import { TEMPLATES, template } from "./templates.js";
import { openCapture } from "./capture.js";

// ---------- Raster ----------
export function title() {
  return "Taschen";
}

export function stats(bagId) {
  return safe(() => pm.bagStats(store.get(), bagId, app.now), null);
}

function card(b, i) {
  const st = stats(b.id) || { pct: 0, open: 0, overdue: 0, total: 0, health: "gut" };
  const next = st.next;
  const dl = st.deadlineIn;
  const dlTxt = dl == null ? "" : dl < 0 ? `${-dl} T drüber` : dl === 0 ? "Deadline heute" : `noch ${dl} T`;
  return `<article class="bcard tilt" data-key="b-${b.id}" data-menu="bag" data-id="${b.id}" style="${bagVars(b)};--k:${i}">
<button type="button" class="bcard-hit" data-act="go" data-to="#tasche/${b.id}" aria-label="Tasche öffnen: ${esc(b.name)}"></button>
<span class="bcard-glare" aria-hidden="true"></span>
<div class="bcard-top"><span class="bsq lg"><span>${esc(b.emoji)}</span></span>${ring(st.pct, { size: 48, stroke: 5, cls: "bag-ring" })}</div>
<h3 class="bcard-name">${esc(b.name)}${b.pinned ? `<span class="pin">${icon("pin")}</span>` : ""}</h3>
${b.goal ? `<p class="bcard-goal">${esc(b.goal)}</p>` : `<p class="bcard-goal muted">Noch kein Ziel</p>`}
<div class="bcard-health">${healthPill(st)}${dlTxt ? `<span class="bcard-dl${dl != null && dl <= 3 ? " red" : ""}">${icon("flag")}${esc(dlTxt)}</span>` : ""}</div>
${next ? `<p class="bcard-next">${icon("arrowRight")}<span>${esc(next.title)}</span></p>` : st.total && !st.open ? `<p class="bcard-next done">${icon("checkCircle")}<span>Alles erledigt</span></p>` : `<p class="bcard-next muted">${icon("plus")}<span>Erste Aufgabe anlegen</span></p>`}
<footer class="bcard-foot"><span><b>${st.open}</b> offen</span>${st.overdue ? `<span class="red"><b>${st.overdue}</b> überfällig</span>` : ""}${st.waiting ? `<span class="purple"><b>${st.waiting}</b> wartet</span>` : ""}</footer>
</article>`;
}

export function render() {
  const bags = store.bags();
  const groups = { aktiv: [], pausiert: [], fertig: [] };
  for (const b of bags) (groups[b.status] || groups.aktiv).push(b);
  const openTotal = store.tasks().filter((t) => !t.done && t.bag).length;
  let html = largeTitle("Taschen", { sub: bags.length ? `${groups.aktiv.length} aktiv · ${openTotal} offene Aufgaben` : "Deine Projekte an einem Ort", key: "lt-bags" });
  if (!bags.length) {
    html += empty({
      emoji: "👜",
      title: "Pack deine erste Tasche",
      text: "Eine Tasche ist ein Projekt: Aufgaben, Notizen, Links, Dateien und Meilensteine an einem Ort – und ich behalte den Überblick.",
      action: `<button type="button" class="btn primary" data-act="bag-new">${icon("plus")}<span>Neue Tasche</span></button>`,
      cls: "big",
    });
    return `<div class="view view-bags" data-key="view-bags">${html}</div>`;
  }
  html += `<div class="bgrid" data-key="grid-aktiv">${groups.aktiv.map(card).join("")}<button type="button" class="bcard new" data-key="b-new" data-act="bag-new"><span class="new-ic">${icon("plus")}</span><b>Neue Tasche</b><small>Leer oder aus Vorlage</small></button></div>`;
  for (const [k, label, ic] of [["pausiert", "Pausiert", "pause"], ["fertig", "Fertig", "checkCircle"]]) {
    if (!groups[k].length) continue;
    const col = isCollapsed("bags-" + k, true);
    html += `<section class="sec${col ? " collapsed" : ""}" data-key="sec-bags-${k}"><header class="sec-h"><button class="sec-toggle" type="button" data-act="collapse" data-k="bags-${k}" data-def="1" aria-expanded="${!col}"><span class="sec-title"><span class="sec-ic gray">${icon(ic)}</span><h2>${label}</h2><span class="sec-count">${groups[k].length}</span><span class="sec-chev${col ? "" : " open"}">${icon("chevronRight")}</span></span></button></header>${col ? "" : `<div class="bgrid dim">${groups[k].map(card).join("")}</div>`}</section>`;
  }
  return `<div class="view view-bags" data-key="view-bags">${html}</div>`;
}

export function actions() {
  return `<button type="button" class="btn-round" data-act="bag-new" aria-label="Neue Tasche" title="Neue Tasche">${icon("plus")}</button>`;
}

// ---------- Kontextmenü einer Tasche ----------
export function bagMenuItems(id) {
  const b = store.bag(id);
  if (!b) return [];
  return [
    { label: "Öffnen", icon: "arrowUpRight", run: () => app.go("#tasche/" + id) },
    { label: "Neue Aufgabe hier", icon: "plus", run: () => openCapture({ bag: id }) },
    { label: "Bearbeiten", icon: "pencil", run: () => openBagEditor(id) },
    { label: b.pinned ? "Nicht mehr anpinnen" : "Anpinnen", icon: "pin", run: () => { store.updateBag(id, { pinned: !b.pinned }); haptic(); } },
    {
      label: "Status", icon: "layers", sub: [
        { label: "Aktiv", check: b.status === "aktiv", run: () => setStatus(id, "aktiv") },
        { label: "Pausiert", check: b.status === "pausiert", run: () => setStatus(id, "pausiert") },
        { label: "Fertig", check: b.status === "fertig", run: () => setStatus(id, "fertig") },
      ],
    },
    "-",
    { label: "Löschen", icon: "trash", danger: true, run: () => deleteBag(id) },
  ];
}

export function setStatus(id, status) {
  const b = store.bag(id);
  if (!b || b.status === status) return;
  store.updateBag(id, { status });
  haptic();
  if (status === "fertig") {
    const c = COLORS[b.color] || COLORS.blue;
    confetti({ colors: [c[0], c[1], "#FFCC00", "#FFFFFF"] });
    sound("all");
    toastUndo(`${b.emoji} ${b.name} ist fertig!`, { icon: "trophy" });
  } else toastUndo(status === "pausiert" ? "Tasche pausiert" : "Tasche wieder aktiv", { icon: status === "pausiert" ? "pause" : "play" });
}

export async function deleteBag(id) {
  const b = store.bag(id);
  if (!b) return;
  const n = store.tasksOf(id).length;
  const ok = await confirmBox({ title: `„${b.name}“ löschen?`, text: n ? `Die Tasche und ${n} ${n === 1 ? "Aufgabe" : "Aufgaben"}, Notizen, Links und Dateien werden gelöscht. Du kannst es direkt danach rückgängig machen.` : "Die Tasche wird gelöscht.", ok: "Löschen", danger: true });
  if (!ok) return;
  store.removeBag(id);
  haptic(true);
  if (app.route.view === "tasche" && app.route.id === id) app.go("#taschen");
  toastUndo("Tasche gelöscht", { icon: "trash", tone: "red", sub: b.name });
}

// ---------- Neue Tasche / Bearbeiten ----------
let ed = null;

export function openBagEditor(id = null, preset = {}) {
  const b = id ? store.bag(id) : null;
  ed = b
    ? { id, tpl: null, name: b.name, emoji: b.emoji, color: b.color, goal: b.goal || "", deadline: b.deadline || "", status: b.status || "aktiv", pinned: !!b.pinned }
    : { id: null, tpl: "empty", name: preset.name || "", emoji: preset.emoji || "👜", color: preset.color || nextColor(), goal: "", deadline: "", status: "aktiv", pinned: false };
  openSheet({ key: "bag-edit", label: b ? "Tasche bearbeiten" : "Neue Tasche", size: "large", render: editorView, onClose: () => (ed = null) });
}

function nextColor() {
  const used = new Set(store.bags().map((b) => b.color));
  return Object.keys(COLORS).find((c) => !used.has(c) && c !== "gray") || "blue";
}

function editorView() {
  if (!ed) return "";
  const tpl = ed.tpl ? template(ed.tpl) : null;
  const preview = `<div class="be-preview" style="${colorVars(ed.color)}"><span class="bsq xl"><span>${esc(ed.emoji || "👜")}</span></span><div><b>${esc(ed.name || "Neue Tasche")}</b><small>${tpl && tpl.id !== "empty" ? `Vorlage: ${esc(tpl.name)} · ${tpl.tasks.length} Aufgaben · ${tpl.milestones.length} Meilensteine` : esc(ed.goal || "Ziel, Aufgaben, Notizen, Links und Dateien")}</small></div></div>`;
  return `${sheetHead(ed.id ? "Tasche bearbeiten" : "Neue Tasche", { left: `<button type="button" class="btn-text" data-act="sheet-close">Abbrechen</button>`, right: `<button type="button" class="btn-text bold" data-act="be-save"${ed.name.trim() ? "" : " disabled"}>${ed.id ? "Fertig" : "Anlegen"}</button>` })}
<div class="sheet-pad be">
${preview}
${!ed.id ? `<h3 class="form-h">Vorlage</h3><div class="tpl-row hscroll">${TEMPLATES.map((t) => `<button type="button" class="tpl${ed.tpl === t.id ? " on" : ""}" data-act="be-tpl" data-v="${t.id}" style="${colorVars(t.color)}"><span class="tpl-e">${esc(t.emoji)}</span><b>${esc(t.name)}</b><small>${t.tasks.length ? `${t.tasks.length} Aufgaben` : "Ohne Inhalt"}</small></button>`).join("")}</div>${tpl && tpl.id !== "empty" ? `<p class="fine">${icon("info")} Checkliste als Startpunkt – keine Rechts- oder Steuerberatung.</p>` : ""}` : ""}
<h3 class="form-h">Name & Ziel</h3>
<div class="card form">
<label class="frow input"><span class="frow-l">Name</span><input type="text" class="in-text" value="${esc(ed.name)}" placeholder="z. B. Kunde Müller oder Büro" data-input="be-field" data-f="name" maxlength="80" ${ed.id ? "" : "autofocus"} enterkeyhint="next" /></label>
<label class="frow input col"><span class="frow-l">Ziel</span><textarea class="in-text grow" rows="2" placeholder="Was soll am Ende erreicht sein?" data-input="be-field" data-f="goal" maxlength="400">${esc(ed.goal)}</textarea></label>
<label class="frow input"><span class="frow-l">Deadline</span><input type="date" class="in-date" value="${esc(ed.deadline)}" data-input="be-field" data-f="deadline" /></label>
</div>
<h3 class="form-h">Farbe</h3>
<div class="colors">${Object.keys(COLORS).map((c) => `<button type="button" class="color${ed.color === c ? " on" : ""}" style="${colorVars(c)}" data-act="be-color" data-v="${c}" aria-label="${esc(COLOR_NAMES[c] || c)}" title="${esc(COLOR_NAMES[c] || c)}"></button>`).join("")}</div>
<h3 class="form-h">Symbol</h3>
<div class="emojis">${EMOJIS.map((e) => `<button type="button" class="emo${ed.emoji === e ? " on" : ""}" data-act="be-emoji" data-v="${esc(e)}" style="${colorVars(ed.color)}">${esc(e)}</button>`).join("")}<label class="emo custom" title="Eigenes Emoji"><input type="text" value="${EMOJIS.includes(ed.emoji) ? "" : esc(ed.emoji)}" placeholder="＋" data-input="be-emoji-in" maxlength="8" aria-label="Eigenes Emoji" /></label></div>
${ed.id ? `<h3 class="form-h">Status</h3><div class="card form"><div class="frow"><span class="frow-l">Status</span><span class="frow-c">${seg([{ id: "aktiv", label: "Aktiv" }, { id: "pausiert", label: "Pausiert" }, { id: "fertig", label: "Fertig" }], ed.status, { act: "be-status", cls: "mini", label: "Status" })}</span></div><div class="frow"><span class="frow-l">Oben anpinnen</span><span class="frow-c">${toggle(ed.pinned, `data-change="be-pin"`, "Anpinnen")}</span></div></div>
<button type="button" class="btn danger wide" data-act="be-delete">${icon("trash")}<span>Tasche löschen</span></button>` : ""}
<button type="button" class="btn primary wide" data-act="be-save"${ed.name.trim() ? "" : " disabled"}>${icon(ed.id ? "check" : "plus")}<span>${ed.id ? "Speichern" : "Tasche anlegen"}</span></button>
</div>`;
}

function refreshEditor() {
  getSheet("bag-edit")?.refresh();
}

function saveBag() {
  if (!ed || !ed.name.trim()) return;
  const data = { name: ed.name.trim(), emoji: ed.emoji || "👜", color: ed.color, goal: ed.goal.trim(), deadline: ed.deadline || null };
  try {
    if (ed.id) {
      store.updateBag(ed.id, { ...data, status: ed.status, pinned: ed.pinned });
      closeSheet(getSheet("bag-edit"));
      toast("Gespeichert", { icon: "check" });
      return;
    }
    const tpl = template(ed.tpl) || template("empty");
    const bag = store.addBag({ ...data, sections: [...tpl.sections] });
    const tdy = today();
    for (const t of tpl.tasks) {
      const task = store.addTask({ bag: bag.id, title: t.title, section: t.section || "", prio: t.prio || 0, due: t.dueIn != null ? dates.addDays(tdy, t.dueIn) : t.repeat ? tdy : null, repeat: t.repeat || null });
      for (const st of t.subtasks || []) safe(() => store.addSubtask(task.id, st));
    }
    for (const m of tpl.milestones) safe(() => store.addMilestone({ bag: bag.id, title: m.title, date: m.dueIn != null ? dates.addDays(tdy, m.dueIn) : null }));
    closeSheet(getSheet("bag-edit"));
    haptic();
    sound("done");
    toast(`${bag.emoji} ${bag.name} ist bereit`, { icon: "bag", sub: tpl.tasks.length ? `${tpl.tasks.length} Aufgaben aus der Vorlage` : "Leg los mit der ersten Aufgabe" });
    app.go("#tasche/" + bag.id);
  } catch (e) {
    toastError(e);
  }
}

// ---------- Ereignisse ----------
on("click", {
  "bag-new": () => openBagEditor(),
  "bag-edit": (el) => openBagEditor(el.dataset.id),
  "bag-menu": (el) => openMenu(bagMenuItems(el.dataset.id), { el, title: store.bag(el.dataset.id)?.name }),
  "be-tpl": (el) => {
    if (!ed) return;
    const t = template(el.dataset.v);
    if (!t) return;
    const prevTpl = template(ed.tpl);
    ed.tpl = t.id;
    if (t.id !== "empty") {
      if (!ed.name.trim() || ed.name === prevTpl?.name) ed.name = t.name;
      if (!ed.goal.trim() || ed.goal === prevTpl?.goal) ed.goal = t.goal;
      ed.emoji = t.emoji;
      ed.color = t.color;
    }
    haptic();
    refreshEditor();
  },
  "be-color": (el) => {
    if (!ed) return;
    ed.color = el.dataset.v;
    haptic();
    refreshEditor();
  },
  "be-emoji": (el) => {
    if (!ed) return;
    ed.emoji = el.dataset.v;
    haptic();
    refreshEditor();
  },
  "be-status": (el) => {
    if (!ed) return;
    ed.status = el.dataset.v;
    refreshEditor();
  },
  "be-save": () => saveBag(),
  "be-delete": () => {
    const id = ed?.id;
    if (!id) return;
    closeSheet(getSheet("bag-edit"));
    deleteBag(id);
  },
});

on("input", {
  "be-field": (el) => {
    if (!ed) return;
    ed[el.dataset.f] = el.value;
    if (el.nodeName === "TEXTAREA") {
      el.style.height = "auto";
      el.style.height = el.scrollHeight + "px";
    }
    refreshEditor();
  },
  "be-emoji-in": (el) => {
    if (!ed) return;
    const raw = el.value.trim();
    const v = typeof Intl !== "undefined" && Intl.Segmenter ? [...new Intl.Segmenter("de", { granularity: "grapheme" }).segment(raw)].pop()?.segment || "" : [...raw].slice(-2).join("");
    if (v) {
      ed.emoji = v;
      refreshEditor();
    }
  },
});

on("change", {
  "be-pin": (el) => {
    if (ed) ed.pinned = el.checked;
  },
});

on("menu", {
  bag: (el, pos) => openMenu(bagMenuItems(el.dataset.id), { ...pos, title: store.bag(el.dataset.id)?.name }),
});
