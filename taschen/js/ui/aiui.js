// Arbeitstaschen – KI-Projektmanager in der Oberfläche: Anfrage stellen, Antwort zeigen, Vorschläge übernehmen
import * as store from "../store.js";
import * as ai from "../ai.js";
import { esc } from "../util.js";
import { icon } from "./icons.js";
import { app, on, safe } from "./core.js";
import { openSheet, closeSheet, sheetHead } from "./sheet.js";
import { toast, toastError, haptic } from "./fx.js";
import { PRIOS } from "../config.js";

let res = null; // { title, text, items, picked:Set, apply, applyLabel, busy, error }

// Einfache Formatierung der KI-Antwort (nur Absätze und Listen, immer escaped)
function prose(text) {
  const lines = String(text || "").split(/\n/);
  let html = "", list = false;
  for (const raw of lines) {
    const l = raw.trim();
    const li = l.match(/^[-*•]\s+(.*)$/) || l.match(/^\d+[.)]\s+(.*)$/);
    if (li) {
      if (!list) html += "<ul>";
      list = true;
      html += `<li>${esc(li[1]).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>")}</li>`;
      continue;
    }
    if (list) html += "</ul>";
    list = false;
    if (l) html += `<p>${esc(l).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>")}</p>`;
  }
  if (list) html += "</ul>";
  return html;
}

function view() {
  if (!res) return "";
  const items = res.items || [];
  return `${sheetHead(res.title, { left: `<span class="ai-badge">${icon("sparkle")} KI</span>` })}
<div class="sheet-pad ai-res">
${res.busy ? `<div class="ai-think"><span class="spinner"></span><p>Dein Projektmanager denkt nach …</p></div>` : ""}
${res.error ? `<div class="note-box red">${esc(res.error)}</div>` : ""}
${res.text ? `<div class="prose">${prose(res.text)}</div>` : ""}
${items.length ? `<div class="card list ai-items">${items.map((it, i) => `<button type="button" class="ai-item${res.picked.has(i) ? " on" : ""}" data-act="ai-pick" data-i="${i}" aria-pressed="${res.picked.has(i)}"><span class="ai-cb">${icon("check")}</span><span class="ai-t">${esc(it.title)}${it.due || it.prio ? `<small>${[it.due ? esc(it.due) : "", it.prio ? esc(PRIOS[it.prio]?.label || "") : ""].filter(Boolean).join(" · ")}</small>` : ""}</span></button>`).join("")}</div>` : ""}
${items.length && res.apply ? `<button type="button" class="btn primary wide" data-act="ai-apply"${res.picked.size ? "" : " disabled"}>${icon("plus")}<span>${esc(res.applyLabel || "Übernehmen")} (${res.picked.size})</span></button>` : ""}
<p class="fine">Die KI sieht nur Titel, Termine und Prioritäten – keine Dateien. Antworten können danebenliegen.</p>
</div>`;
}

// Anfrage stellen und Ergebnis zeigen
// opts: { kind, title, question, bagId, taskId, apply(items), applyLabel }
export async function askAI(opts) {
  if (!app.ai || !app.server) {
    toast("KI ist nicht eingerichtet", { icon: "sparkle", sub: "Einstellungen → KI-Projektmanager" });
    return;
  }
  res = { title: opts.title || "KI-Projektmanager", text: "", items: [], picked: new Set(), apply: opts.apply, applyLabel: opts.applyLabel, busy: true, error: "" };
  const sh = openSheet({ key: "ai", label: res.title, render: view, onClose: () => (res = null) });
  try {
    const context = safe(() => ai.contextFor(store.get(), { bagId: opts.bagId, taskId: opts.taskId, now: new Date() }), {});
    const r = await ai.ask(app.server, { kind: opts.kind, context, question: opts.question || "" });
    if (!res) return;
    res.busy = false;
    res.text = r?.text || "";
    res.items = Array.isArray(r?.items) ? r.items.filter((x) => x && x.title).slice(0, 20) : [];
    res.picked = new Set(res.items.map((_, i) => i));
  } catch (e) {
    if (!res) return;
    res.busy = false;
    res.error = e?.message || "Die KI ist gerade nicht erreichbar.";
  }
  sh.refresh();
}

on("click", {
  "ai-pick": (el) => {
    if (!res) return;
    const i = +el.dataset.i;
    if (res.picked.has(i)) res.picked.delete(i);
    else res.picked.add(i);
    haptic();
    app.render();
  },
  "ai-apply": () => {
    if (!res?.apply) return;
    const items = res.items.filter((_, i) => res.picked.has(i));
    try {
      res.apply(items);
      closeSheet();
    } catch (e) {
      toastError(e);
    }
  },
});
