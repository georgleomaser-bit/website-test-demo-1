// Arbeitstaschen – „Eingang“: schnell Erfasstes ohne Tasche, mit Einsortier-Vorschlägen vom Projektmanager
import * as store from "../store.js";
import * as pm from "../pm.js";
import * as dates from "../dates.js";
import { esc } from "../util.js";
import { icon } from "./icons.js";
import { on, safe, bagVars, today } from "./core.js";
import { taskRow, empty, largeTitle } from "./components.js";
import { moveTo } from "./actions.js";
import { openMenu } from "./sheet.js";
import { haptic, toast, toastUndo, toastError, sound } from "./fx.js";
import { mailsSection } from "./connectui.js";
import { isCall } from "../connect.js";

function suggest(t, s) {
  const r = safe(() => pm.suggestBag(t.title + " " + (t.notes || ""), s), null);
  if (!r || !r.bag) return null;
  const b = typeof r.bag === "string" ? store.bag(r.bag) : r.bag;
  return b && b.id ? { bag: store.bag(b.id) || b, score: r.score || 0 } : null;
}

export function title() {
  return "Eingang";
}

export function render() {
  const s = store.get();
  const items = store.tasks().filter((t) => !t.bag && !t.done).sort((a, b) => (b.created || 0) - (a.created || 0));
  const sugs = new Map(items.map((t) => [t.id, suggest(t, s)]));
  const nSug = [...sugs.values()].filter(Boolean).length;
  let html = largeTitle("Eingang", { sub: items.length ? `${items.length} ${items.length === 1 ? "Gedanke wartet" : "Gedanken warten"} aufs Einsortieren` : "Alles einsortiert", key: "lt-in" });
  html += `<form class="quick-in" data-key="qin" data-submit="inbox-add" autocomplete="off"><span class="qi-ic">${icon("plus")}</span><input type="text" name="t" placeholder="Schnell notieren – landet im Eingang" aria-label="Neuer Eintrag im Eingang" enterkeyhint="done" data-focus="inbox-add" /></form>`;
  // Markierte Mails (Gmail: Stern, Outlook: Fahne) aus verbundenen Konten
  const mails = safe(() => mailsSection(), "");
  html += mails;
  if (!items.length) {
    html += empty({ emoji: "📭", title: "Eingang leer – stark!", text: "Alles hat seinen Platz. Was dir durch den Kopf geht, kommt hier hinein – sortiert wird später.", cls: mails ? "" : "big" });
  } else {
    if (mails) html += `<div class="sec-h in-h" data-key="in-h"><span class="sec-title"><span class="sec-ic gray">${icon("tray")}</span><h2>Zum Einsortieren</h2><span class="sec-count">${items.length}</span></span></div>`;
    if (nSug > 1) html += `<div class="in-bar" data-key="in-bar"><span>${icon("sparkle")} ${nSug} Vorschläge vom PM</span><button type="button" class="pill accent" data-act="inbox-all">Alle einsortieren</button></div>`;
    html += `<div class="card list inbox" data-key="inbox-list">${items
      .map((t) => {
        const sg = sugs.get(t.id);
        const extra = `<div class="in-sug">${sg ? `<button type="button" class="sg" data-act="inbox-move" data-id="${t.id}" data-bag="${sg.bag.id}" style="${bagVars(sg.bag)}">${icon("arrowRight")}<span>${esc(sg.bag.emoji)} ${esc(sg.bag.name)}</span></button>` : ""}<button type="button" class="sg ghost" data-act="inbox-pick" data-id="${t.id}">${icon("bag")}<span>${sg ? "Andere" : "Tasche wählen"}</span></button><button type="button" class="sg ghost" data-act="task-plan" data-id="${t.id}">${icon(t.plan === today() ? "starFill" : "star")}<span>Heute</span></button></div>`;
        return taskRow(t, { bag: false, extra, cls: "in-row" });
      })
      .join("")}</div>`;
    html += `<p class="fine center" data-key="in-fine">Tipp: Nach rechts wischen erledigt, nach links verschiebt oder löscht.</p>`;
  }
  return `<div class="view view-inbox" data-key="view-inbox">${html}</div>`;
}

export function actions() {
  return "";
}

on("click", {
  "inbox-move": (el) => moveTo(el.dataset.id, el.dataset.bag),
  "inbox-pick": (el) => {
    const id = el.dataset.id;
    openMenu(store.bags().map((b) => ({ label: b.name, emoji: b.emoji, run: () => moveTo(id, b.id) })), { el, title: "In Tasche einsortieren" });
  },
  "inbox-all": () => {
    const s = store.get();
    const moves = store
      .tasks()
      .filter((t) => !t.bag && !t.done)
      .map((t) => [t, suggest(t, s)])
      .filter(([, sg]) => sg);
    if (!moves.length) return;
    const prev = moves.map(([t]) => [t.id, t.section || ""]);
    for (const [t, sg] of moves) safe(() => store.moveTask(t.id, sg.bag.id, ""));
    haptic();
    sound("done");
    toastUndo(`${moves.length} einsortiert`, { icon: "sparkle", undo: () => prev.forEach(([id, sec]) => safe(() => store.moveTask(id, null, sec))) });
  },
});

on("submit", {
  "inbox-add": (form, e) => {
    e.preventDefault();
    const inp = form.querySelector("input");
    const v = inp.value.trim();
    if (!v) return;
    try {
      const pq = safe(() => dates.parseQuick(v, { bags: store.bags(), now: new Date(), profile: store.get().profile }), null);
      const tags = [...(pq?.tags || [])];
      if (isCall(v) && !tags.includes("anruf")) tags.push("anruf"); // „Anruf …“, „anrufen“, „Call“ → Telefon-Symbol
      store.addTask(pq ? { title: pq.title || v, due: pq.due, time: pq.time, prio: pq.prio || 0, bag: pq.bag || null, tags, remind: pq.remind, repeat: pq.repeat, someday: !!pq.someday, est: pq.est, plan: pq.plan ? today() : null } : { title: v, bag: null, tags });
      inp.value = "";
      haptic();
      toast("Im Eingang", { icon: "tray", sub: v });
    } catch (err) {
      toastError(err);
    }
  },
});

