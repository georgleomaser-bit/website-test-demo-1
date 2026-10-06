// Arbeitstaschen – wiederverwendbare Bausteine: Aufgabenzeile, Fortschrittsring, Abschnitte, Leerzustände, Segmente
import * as store from "../store.js";
import * as dates from "../dates.js";
import { PRIOS, REPEATS } from "../config.js";
import { esc, clamp } from "../util.js";
import { icon, CHECK } from "./icons.js";
import { app, today, bagVars, colorVars, isCollapsed, safe } from "./core.js";
import { phoneList, telHref } from "../connect.js";

// Aufgaben, die gerade abgehakt werden (Animation läuft, Speichern folgt gleich)
export const pending = new Map();

// ---------- Datum als Chip ----------
export function dueInfo(t) {
  if (!t.due) return null;
  const d = safe(() => dates.diffDays(today(), t.due), 0);
  const label = safe(() => dates.relDay(t.due, app.now), t.due);
  return { label, cls: t.done ? "" : d < 0 ? "red" : d === 0 ? "orange" : "", days: d };
}

export function repeatLabel(r) {
  return REPEATS.find((x) => x.id === r)?.label || "";
}

// ---------- Meta-Zeile einer Aufgabe ----------
export function taskMeta(t, o = {}) {
  const m = [];
  const bag = t.bag ? store.bag(t.bag) : null;
  const di = dueInfo(t);
  if (di && o.date !== false) m.push(`<span class="m ${di.cls}">${icon("calendar")}${esc(di.label)}</span>`);
  if (t.time && o.time !== false) m.push(`<span class="m${di && di.cls ? " " + di.cls : ""}">${icon("clock")}${esc(safe(() => dates.fmtTime(t.time), t.time))}</span>`);
  if (t.plan === today() && !t.done && o.plan !== false && t.due !== today()) m.push(`<span class="m accent">${icon("starFill")}Heute</span>`);
  if (o.bag !== false) {
    if (bag) m.push(`<span class="m bagm" style="${bagVars(bag)}"><i class="bdot"></i>${esc(bag.emoji)} ${esc(bag.name)}</span>`);
    else if (o.inbox) m.push(`<span class="m">${icon("tray")}Eingang</span>`);
  }
  if (o.section && t.section) m.push(`<span class="m">${esc(t.section)}</span>`);
  const subs = t.subtasks || [];
  if (subs.length) m.push(`<span class="m${subs.every((s) => s.done) ? " green" : ""}">${icon("checklist")}${subs.filter((s) => s.done).length}/${subs.length}</span>`);
  if (t.repeat) m.push(`<span class="m" title="${esc(repeatLabel(t.repeat))}">${icon("repeat")}</span>`);
  if (t.notes && t.notes.trim()) m.push(`<span class="m" title="Notiz">${icon("note")}</span>`);
  if (t.waiting) m.push(`<span class="m purple">${icon("hourglass")}${esc(t.waiting)}</span>`);
  if (t.someday && !t.due) m.push(`<span class="m">${icon("moon")}Irgendwann</span>`);
  if (t.est && o.est !== false) m.push(`<span class="m">${esc(safe(() => dates.fmtDuration(t.est), t.est + " Min."))}</span>`);
  if (t.milestone && o.milestone !== false) {
    const ms = store.milestones?.().find?.((x) => x.id === t.milestone);
    if (ms) m.push(`<span class="m">${icon("diamond")}${esc(ms.title)}</span>`);
  }
  const tags = t.tags || [];
  if (tags.includes("anruf") && !o.phone) m.push(`<span class="m green">${icon("call")}Anruf</span>`);
  if (t.src?.kind === "mail") m.push(`<span class="m" title="Aus einer Mail">${icon("mail")}</span>`);
  else if (t.src?.kind === "event") m.push(`<span class="m" title="Aus dem Kalender">${icon("calendar")}Termin</span>`);
  else if (t.src?.kind === "hook") m.push(`<span class="m via" title="Über deine Eingangs-Adresse gekommen">${icon("inboxIn")}via ${esc(String(t.src.via || "Webhook").slice(0, 24))}</span>`);
  for (const tag of tags.filter((x) => x !== "anruf").slice(0, 4)) m.push(`<span class="m tag">#${esc(tag)}</span>`);
  return m.join("");
}

// ---------- Aufgabenzeile ----------
// o: { bag: false (Taschen-Chip weglassen), inbox, compact, drag, cls, extra (HTML unter der Zeile), section }
export function taskRow(t, o = {}) {
  const pend = pending.has(t.id);
  const done = !!t.done || pend;
  const bag = t.bag ? store.bag(t.bag) : null;
  // Telefonnummer in Titel/Notizen → kleiner Anrufen-Knopf direkt in der Zeile
  const tel = !done && !o.compact ? safe(() => phoneList(`${t.title}\n${t.notes || ""}`)[0], null) : null;
  const meta = taskMeta(t, { ...o, phone: !!tel });
  const prio = t.prio > 0 && !done ? (t.prio === 3 ? `<span class="pflag" aria-label="Priorität hoch">${icon("flag")}</span>` : `<span class="prio p${t.prio}" aria-label="Priorität ${esc(PRIOS[t.prio]?.label || "")}">${esc(PRIOS[t.prio]?.mark || "")}</span>`) : "";
  return `<div class="task${done ? " done" : ""}${pend ? " checking" : ""}${t.prio === 3 ? " p3" : ""}${o.compact ? " compact" : ""}${o.cls ? " " + o.cls : ""}" data-key="t-${t.id}" data-task="${t.id}" data-menu="task" data-id="${t.id}"${o.drag ? ` data-drag="task"` : ""} style="${bagVars(bag)}">
<div class="swipe-bg" aria-hidden="true"><span class="sw-done">${icon("check")}<b>${t.done ? "Öffnen" : "Erledigt"}</b></span><span class="sw-acts"><button type="button" tabindex="-1" class="sw-btn orange" data-act="task-tomorrow" data-id="${t.id}">${icon("sunrise")}<b>Morgen</b></button><button type="button" tabindex="-1" class="sw-btn red" data-act="task-delete" data-id="${t.id}">${icon("trash")}<b>Löschen</b></button></span></div>
<div class="task-in">
<button class="check" type="button" data-act="toggle" data-id="${t.id}" aria-label="${done ? "Wieder öffnen" : "Erledigen"}: ${esc(t.title)}" aria-pressed="${done}">${CHECK}</button>
<button class="task-main" type="button" data-act="task" data-id="${t.id}"><span class="task-title">${prio}${esc(t.title)}</span>${meta ? `<span class="task-meta">${meta}</span>` : ""}</button>${tel ? `<a class="tcall" href="${esc(telHref(tel.tel))}" aria-label="Anrufen: ${esc(tel.label)}" title="Anrufen: ${esc(tel.label)}">${icon("call")}</a>` : ""}
<span class="task-hover"><button type="button" class="hv" data-act="task-plan" data-id="${t.id}" title="${t.plan === today() ? "Aus Heute entfernen" : "Für heute einplanen"}" aria-label="Für heute einplanen">${icon(t.plan === today() ? "starFill" : "star")}</button><button type="button" class="hv" data-act="task-menu" data-id="${t.id}" title="Mehr" aria-label="Mehr Aktionen">${icon("ellipsis")}</button></span>
</div>${o.extra || ""}
</div>`;
}

// ---------- Fortschrittsring ----------
export function ring(pct, { size = 44, stroke = 4.5, cls = "", label = true, sub = "" } = {}) {
  const p = clamp(Math.round(pct || 0), 0, 100);
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const off = c * (1 - p / 100);
  return `<span class="ring${cls ? " " + cls : ""}" style="--sz:${size}px" role="img" aria-label="${p} Prozent erledigt"><svg viewBox="0 0 ${size} ${size}" aria-hidden="true"><circle class="ring-bg" cx="${size / 2}" cy="${size / 2}" r="${r}" stroke-width="${stroke}"/><circle class="ring-fg" cx="${size / 2}" cy="${size / 2}" r="${r}" stroke-width="${stroke}" stroke-dasharray="${c.toFixed(2)}" stroke-dashoffset="${off.toFixed(2)}" transform="rotate(-90 ${size / 2} ${size / 2})"/></svg>${label ? `<b class="ring-l"><span>${p}<small>%</small></span>${sub ? `<i>${esc(sub)}</i>` : ""}</b>` : ""}</span>`;
}

export function bar(pct, cls = "") {
  const p = clamp(Math.round(pct || 0), 0, 100);
  return `<span class="bar${cls ? " " + cls : ""}" role="img" aria-label="${p} Prozent"><i style="width:${p}%"></i></span>`;
}

// ---------- Gesundheit ----------
const HEALTH = { gut: ["Gut", "green"], achtung: ["Achtung", "orange"], kritisch: ["Kritisch", "red"], ruhend: ["Ruhend", "gray"], fertig: ["Fertig", "blue"] };
export function healthPill(st, { reason = false } = {}) {
  if (!st) return "";
  const [lab, col] = HEALTH[st.health] || ["–", "gray"];
  return `<span class="health ${col}"><i></i>${esc(st.healthLabel || lab)}</span>${reason && st.healthReason ? `<span class="health-reason">${esc(st.healthReason)}</span>` : ""}`;
}

// ---------- Abschnitt ----------
// sec({ key, title, icon, tone, count, note, actions, body, collapsible, collapsed, cls, plain })
export function sec(o) {
  const col = o.collapsible ? isCollapsed(o.key, !!o.collapsed) : false;
  const head = `<span class="sec-title">${o.icon ? `<span class="sec-ic ${o.tone || ""}">${icon(o.icon)}</span>` : ""}<h2>${esc(o.title)}</h2>${o.count != null && o.count !== "" ? `<span class="sec-count">${esc(String(o.count))}</span>` : ""}${o.collapsible ? `<span class="sec-chev${col ? "" : " open"}">${icon("chevronRight")}</span>` : ""}</span>`;
  return `<section class="sec${o.cls ? " " + o.cls : ""}${col ? " collapsed" : ""}" data-key="sec-${esc(o.key)}" id="sec-${esc(o.key)}">
<header class="sec-h">${o.collapsible ? `<button class="sec-toggle" type="button" data-act="collapse" data-k="${esc(o.key)}" data-def="${o.collapsed ? 1 : 0}" aria-expanded="${!col}">${head}</button>` : head}${o.note ? `<span class="sec-note">${o.note}</span>` : ""}${o.actions ? `<span class="sec-act">${o.actions}</span>` : ""}</header>
${col ? "" : o.plain ? o.body : `<div class="card list">${o.body}</div>`}
</section>`;
}

// ---------- Leerzustand ----------
export function empty({ emoji = "✨", title, text = "", action = "", cls = "" }) {
  return `<div class="empty${cls ? " " + cls : ""}"><div class="empty-emoji" aria-hidden="true">${esc(emoji)}</div><h3>${esc(title)}</h3>${text ? `<p>${esc(text)}</p>` : ""}${action ? `<div class="empty-act">${action}</div>` : ""}</div>`;
}

// ---------- Segmente (iOS Segmented Control mit gleitender Pille) ----------
// items: [{ id, label, count, icon }]
export function seg(items, active, { act = "seg", attrs = "", cls = "", label = "Auswahl" } = {}) {
  return `<div class="seg${cls ? " " + cls : ""}" role="tablist" aria-label="${esc(label)}"><span class="seg-pill" aria-hidden="true"></span>${items
    .map((it) => `<button type="button" role="tab" class="seg-b${it.id === active ? " on" : ""}" aria-selected="${it.id === active}" data-act="${act}" data-v="${esc(it.id)}" ${attrs}>${it.icon ? icon(it.icon) : ""}<span>${esc(it.label)}</span>${it.count ? `<small>${esc(String(it.count))}</small>` : ""}</button>`)
    .join("")}</div>`;
}

// Gleitende Pillen nach dem Rendern ausrichten
export function placeSegPills(root = document) {
  root.querySelectorAll(".seg").forEach((s) => {
    const on = s.querySelector(".seg-b.on");
    const pill = s.querySelector(".seg-pill");
    if (!pill) return;
    if (!on) {
      pill.style.opacity = "0";
      return;
    }
    const x = on.offsetLeft, w = on.offsetWidth;
    if (pill._x === x && pill._w === w) return;
    const first = pill._x == null;
    if (first) pill.style.transition = "none";
    pill.style.opacity = "1";
    pill.style.width = w + "px";
    pill.style.transform = `translateX(${x}px)`;
    pill._x = x;
    pill._w = w;
    if (first) requestAnimationFrame(() => (pill.style.transition = ""));
    // aktive Schaltfläche in Sicht scrollen (iPhone)
    if (s.scrollWidth > s.clientWidth + 2) {
      const l = x - s.clientWidth / 2 + w / 2;
      if (Math.abs(s.scrollLeft - l) > 4) s.scrollTo({ left: l, behavior: first ? "auto" : "smooth" });
    }
  });
}

// ---------- Schalter, Squircle, Chips ----------
export function toggle(checked, attrs = "", label = "") {
  return `<input class="switch" type="checkbox" switch role="switch" ${checked ? "checked" : ""} ${attrs} aria-label="${esc(label)}" />`;
}

export function sq(ic, color = "blue", { emoji = "" } = {}) {
  return `<span class="sq" style="${colorVars(color)}">${emoji ? `<span class="sq-e">${esc(emoji)}</span>` : icon(ic)}</span>`;
}

export function bagSquircle(bag, size = "") {
  return `<span class="bsq${size ? " " + size : ""}" style="${bagVars(bag)}"><span>${esc(bag?.emoji || "📥")}</span></span>`;
}

export function bagLabel(bag) {
  return bag ? `${esc(bag.emoji)} ${esc(bag.name)}` : `📥 Eingang`;
}

// Kopf mit großem Titel (iOS Large Title)
export function largeTitle(title, { sub = "", right = "", key = "lt" } = {}) {
  return `<header class="lt" data-key="${key}"><div class="lt-row"><div class="lt-text">${sub ? `<p class="lt-sub">${sub}</p>` : ""}<h1 class="lt-title">${esc(title)}</h1></div>${right ? `<div class="lt-right">${right}</div>` : ""}</div></header>`;
}

export function btn(label, act, { ic = "", cls = "", attrs = "" } = {}) {
  return `<button type="button" class="btn${cls ? " " + cls : ""}" data-act="${act}" ${attrs}>${ic ? icon(ic) : ""}<span>${esc(label)}</span></button>`;
}

export function iconBtn(ic, act, label, { cls = "", attrs = "" } = {}) {
  return `<button type="button" class="btn-round${cls ? " " + cls : ""}" data-act="${act}" aria-label="${esc(label)}" title="${esc(label)}" ${attrs}>${icon(ic)}</button>`;
}
