// Arbeitstaschen – Schnellerfassung: ein Feld, deutsche Kurzschrift, live erkannte Bausteine als farbige Chips
import * as store from "../store.js";
import * as dates from "../dates.js";
import * as pm from "../pm.js";
import { PRIOS, REPEATS } from "../config.js";
import { esc } from "../util.js";
import { icon } from "./icons.js";
import { app, on, today, tomorrow, safe, bagVars, prefs, setPref } from "./core.js";
import { openSheet, getSheet, closeSheet, openMenu } from "./sheet.js";
import { haptic, toast, toastError } from "./fx.js";
import { openTask } from "./task.js";
import { isCall } from "../connect.js";

let cap = null; // { text, bag, due, prio, ctx, added, last }

// ---------- Öffnen ----------
// ctx: { text, bag, due, section, plan }
export function openCapture(ctx = {}) {
  const ex = getSheet("capture");
  cap = { text: ctx.text || "", bag: undefined, due: undefined, prio: undefined, ctx: { bag: ctx.bag ?? null, due: ctx.due ?? null, section: ctx.section || "", plan: !!ctx.plan }, added: 0, last: null };
  if (ex) {
    ex.refresh();
    const inp = ex.body.querySelector(".cap-input");
    if (inp) {
      inp.value = cap.text;
      inp.focus();
    }
    return;
  }
  openSheet({ key: "capture", label: "Neue Aufgabe", cls: "cap-sheet", render: view, onClose: () => (cap = null) });
  const inp = getSheet("capture")?.body.querySelector(".cap-input");
  if (inp && cap.text) {
    inp.value = cap.text;
    inp.setSelectionRange(inp.value.length, inp.value.length);
    getSheet("capture").refresh();
  }
}

// ---------- Erkennen ----------
function parse(text) {
  const s = store.get();
  return safe(() => dates.parseQuick(text, { bags: store.bags(), now: new Date(), profile: s.profile }), null) || { title: text.trim(), due: null, time: null, prio: 0, bag: null, tags: [], remind: null, repeat: null, someday: false, est: null, plan: false, tokens: [] };
}

function resolve(p) {
  const c = cap;
  const due = p.due ?? (c.due !== undefined ? c.due : c.ctx.due) ?? null;
  const bag = p.bag ?? (c.bag !== undefined ? c.bag : c.ctx.bag) ?? null;
  const tags = [...(p.tags || [])];
  if (isCall(p.title) && !tags.includes("anruf")) tags.push("anruf"); // „Anruf …“, „anrufen“, „Call“ → Telefon-Symbol
  return {
    title: p.title,
    due: p.someday ? null : due,
    time: p.time ?? null,
    prio: p.prio || c.prio || 0,
    bag,
    tags,
    remind: p.remind ?? null,
    repeat: p.repeat ?? null,
    someday: !!p.someday,
    est: p.est ?? null,
    plan: p.plan || c.ctx.plan ? today() : null,
    section: bag && bag === c.ctx.bag ? c.ctx.section : "",
  };
}

function suggestion(title, data) {
  if (data.bag || title.length < 3) return null;
  const r = safe(() => pm.suggestBag(title, store.get()), null);
  if (!r || !r.bag) return null;
  const b = typeof r.bag === "string" ? store.bag(r.bag) : r.bag;
  return b && b.id ? b : null;
}

// ---------- Darstellung ----------
const TK = { date: "blue", time: "indigo", prio: "orange", bag: "bag", tag: "gray", repeat: "green", remind: "purple", est: "teal", someday: "gray" };

function mirror(text, tokens, bag = null) {
  const tks = (tokens || []).filter((t) => Number.isFinite(t.start) && t.end > t.start).sort((a, b) => a.start - b.start);
  let out = "", pos = 0;
  for (const t of tks) {
    if (t.start < pos) continue;
    out += esc(text.slice(pos, t.start)) + `<mark class="tk tk-${TK[t.type] || "gray"}"${t.type === "bag" && bag ? ` style="${bagVars(bag)}"` : ""}>${esc(text.slice(t.start, t.end))}</mark>`;
    pos = t.end;
  }
  return out + esc(text.slice(pos)) + "​";
}

function chip(cls, ic, label, act = "", extra = "") {
  return `<span class="tchip ${cls}"${extra}>${ic}<span>${label}</span></span>`;
}

function view() {
  if (!cap) return "";
  const p = parse(cap.text);
  const d = resolve(p);
  const bag = d.bag ? store.bag(d.bag) : null;
  const chips = [];
  const fromText = (type) => (p.tokens || []).some((t) => t.type === type);
  if (d.due) chips.push(chip(`blue${fromText("date") ? "" : " ctx"}`, icon("calendar"), esc(safe(() => dates.relDay(d.due, app.now), d.due))));
  if (d.time) chips.push(chip("indigo", icon("clock"), esc(safe(() => dates.fmtTime(d.time), d.time))));
  if (d.prio) chips.push(chip(`orange${p.prio ? "" : " ctx"}`, icon("flag"), esc(PRIOS[d.prio]?.label || "") + " " + esc(PRIOS[d.prio]?.mark || "")));
  if (bag) chips.push(`<span class="tchip bagc${p.bag ? "" : " ctx"}" style="${bagVars(bag)}"><span>${esc(bag.emoji)} ${esc(bag.name)}</span></span>`);
  for (const t of d.tags) chips.push(t === "anruf" ? chip("green", icon("call"), "Anruf") : chip("gray", icon("tag"), esc(t)));
  if (d.repeat) chips.push(chip("green", icon("repeat"), esc(REPEATS.find((r) => r.id === d.repeat)?.label || d.repeat)));
  if (d.remind != null) chips.push(chip("purple", icon("bell"), d.remind > 0 ? `${d.remind >= 60 && d.remind % 60 === 0 ? d.remind / 60 + " Std." : d.remind + " Min."} vorher` : "Zum Termin"));
  if (d.est) chips.push(chip("teal", icon("hourglass"), esc(safe(() => dates.fmtDuration(d.est), d.est + " Min."))));
  if (d.someday) chips.push(chip("gray", icon("moon"), "Irgendwann"));
  if (d.plan) chips.push(chip("yellow", icon("starFill"), "Heute einplanen"));
  const sug = suggestion(p.title, d);
  const tdy = today(), tmw = tomorrow();
  const empty = !cap.text.trim();
  return `<header class="sheet-head cap-head"><div class="sh-l"><button type="button" class="btn-text" data-act="sheet-close">Fertig</button></div><div class="sh-t"><h2>Neue Aufgabe</h2>${cap.added ? `<p class="cap-count">${icon("check")} ${cap.added} hinzugefügt</p>` : ""}</div><div class="sh-r"><button type="button" class="btn-add" data-act="cap-add"${empty ? " disabled" : ""} aria-label="Hinzufügen">${icon("arrowRight")}</button></div></header>
<div class="cap">
<div class="cap-field">
<div class="cap-mirror" aria-hidden="true">${mirror(cap.text, p.tokens, p.bag ? store.bag(p.bag) : null)}</div>
<textarea class="cap-input" rows="1" autofocus data-input="cap" data-key-act="cap-key" placeholder="Was steht an?" aria-label="Neue Aufgabe" enterkeyhint="send" autocapitalize="sentences" autocomplete="off" spellcheck="true"></textarea>
</div>
<div class="cap-tokens" aria-live="polite">${chips.join("") || `<span class="cap-hint">Tipp: Datum, Uhrzeit, #Tasche und !!! einfach mitschreiben</span>`}</div>
<div class="cap-quick hscroll">
<button type="button" class="chip${d.due === tdy ? " on" : ""}" data-act="cap-due" data-iso="${tdy}">${icon("sun")}<span>Heute</span></button>
<button type="button" class="chip${d.due === tmw ? " on" : ""}" data-act="cap-due" data-iso="${tmw}">${icon("sunrise")}<span>Morgen</span></button>
<button type="button" class="chip${d.prio ? " on" : ""}" data-act="cap-prio">${icon("flag")}<span>${d.prio ? esc(PRIOS[d.prio].mark) : "Priorität"}</span></button>
<button type="button" class="chip${bag ? " on" : ""}" data-act="cap-bag" style="${bagVars(bag)}">${bag ? `<span>${esc(bag.emoji)}</span><span>${esc(bag.name)}</span>` : `${icon("bag")}<span>Tasche</span>`}${icon("chevronDown")}</button>
${sug ? `<button type="button" class="chip suggest" data-act="cap-sug" data-bag="${sug.id}" style="${bagVars(sug)}">${icon("sparkle")}<span>→ ${esc(sug.emoji)} ${esc(sug.name)}</span></button>` : ""}
</div>
${cap.last ? `<button type="button" class="cap-last" data-act="cap-open" data-id="${cap.last.id}">${icon("checkCircle")}<span>${esc(cap.last.title)}</span><small>${cap.last.where}</small>${icon("chevronRight")}</button>` : ""}
<div class="cap-help${prefs.capHelp === false ? " closed" : ""}">
<button type="button" class="cap-help-t" data-act="cap-help">${icon("info")}<span>So schreibst du schnell</span>${icon(prefs.capHelp === false ? "chevronDown" : "chevronUp")}</button>
${prefs.capHelp === false ? "" : `<ul>
<li><code>Angebot schicken morgen 9 Uhr #Kunden !!!</code></li>
<li><code>Steuerberater anrufen Fr 14:30 erinnere 30 min vorher</code></li>
<li><code>Kennzahlen prüfen jeden Montag ~15m</code></li>
<li><code>Büro neu einrichten irgendwann @ideen</code> · <code>Angebot schicken heute einplanen</code></li>
</ul>`}
</div>
</div>`;
}

// ---------- Hinzufügen ----------
function add(closeAfter = false) {
  if (!cap) return;
  const sh = getSheet("capture");
  const inp = sh?.body.querySelector(".cap-input");
  const text = (inp ? inp.value : cap.text).trim();
  if (!text) {
    if (closeAfter) closeSheet(sh);
    return;
  }
  const p = parse(text);
  const d = resolve(p);
  try {
    const t = store.addTask({
      title: d.title || text,
      bag: d.bag,
      due: d.due,
      time: d.time,
      prio: d.prio,
      tags: d.tags,
      remind: d.remind,
      repeat: d.repeat,
      someday: d.someday,
      est: d.est,
      plan: d.plan,
      section: d.section,
    });
    haptic();
    cap.added++;
    const bag = t.bag ? store.bag(t.bag) : null;
    cap.last = { id: t.id, title: t.title, where: [bag ? `${bag.emoji} ${bag.name}` : "📥 Eingang", t.due ? safe(() => dates.relDay(t.due, app.now), "") : ""].filter(Boolean).join(" · ") };
    cap.text = "";
    cap.prio = undefined;
    if (inp) {
      inp.value = "";
      inp.style.height = "";
    }
    if (closeAfter) {
      closeSheet(sh);
      toast("Hinzugefügt", { icon: "checkCircle", sub: t.title });
    } else sh?.refresh();
  } catch (e) {
    toastError(e);
  }
}

// ---------- Ereignisse ----------
on("input", {
  cap: (el) => {
    if (!cap) return;
    cap.text = el.value;
    el.style.height = "auto";
    el.style.height = el.scrollHeight + "px";
    getSheet("capture")?.refresh();
  },
});

on("keydown", {
  "cap-key": (el, e) => {
    if (e.key === "Enter" && !e.isComposing) {
      e.preventDefault();
      add(e.metaKey || e.ctrlKey);
    }
  },
});

on("click", {
  "cap-add": () => add(false),
  "cap-due": (el) => {
    if (!cap) return;
    const cur = resolve(parse(cap.text)).due;
    cap.due = cur === el.dataset.iso ? null : el.dataset.iso;
    haptic();
    refocus();
  },
  "cap-prio": () => {
    if (!cap) return;
    const cur = cap.prio || 0;
    cap.prio = cur >= 3 ? 0 : cur === 0 ? 3 : cur - 1;
    haptic();
    refocus();
  },
  "cap-bag": (el) => {
    if (!cap) return;
    const cur = resolve(parse(cap.text)).bag;
    openMenu([{ label: "Eingang", emoji: "📥", check: !cur, run: () => setBag(null) }, ...store.bags().map((b) => ({ label: b.name, emoji: b.emoji, check: cur === b.id, run: () => setBag(b.id) }))], { el, title: "Tasche" });
  },
  "cap-sug": (el) => {
    setBag(el.dataset.bag);
    haptic();
  },
  "cap-open": (el) => {
    closeSheet(getSheet("capture"));
    openTask(el.dataset.id);
  },
  "cap-help": () => {
    setPref("capHelp", prefs.capHelp === false);
    getSheet("capture")?.refresh();
  },
});

function setBag(id) {
  if (!cap) return;
  cap.bag = id;
  if (id !== cap.ctx.bag) cap.ctx.section = "";
  refocus();
}

function refocus() {
  const sh = getSheet("capture");
  sh?.refresh();
  if (matchMedia("(pointer: fine)").matches) sh?.body.querySelector(".cap-input")?.focus({ preventScroll: true });
}
