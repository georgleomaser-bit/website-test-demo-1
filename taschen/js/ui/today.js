// Arbeitstaschen – „Heute“: das Projektmanager-Cockpit mit Briefing, Fokus, Zeitplan, Überfälligem und Tagesritualen
import * as store from "../store.js";
import * as dates from "../dates.js";
import * as pm from "../pm.js";
import * as remind from "../remind.js";
import { esc } from "../util.js";
import { icon } from "./icons.js";
import { app, on, today, tomorrow, safe, prefs, setPref, bagVars, isoWeek, appUrl, isStandalone } from "./core.js";
import { taskRow, taskMeta, ring, bar, sec, empty, largeTitle, pending, bagSquircle } from "./components.js";
import { allToToday, rescheduleMenu, batch } from "./actions.js";
import { openSheet, sheetHead, getSheet } from "./sheet.js";
import { openTask } from "./task.js";
import { haptic, toast, toastError, confetti, sound } from "./fx.js";
import { openCapture } from "./capture.js";
import { askAI } from "./aiui.js";
import { openInstallHelp, installHint } from "./install.js";
import { CHECK } from "./icons.js";

const asBag = (x) => (x && typeof x === "object" ? x : x ? store.bag(x) : null);

// ---------- Briefing (mit Rückfallebene, falls pm.js ausfällt) ----------
function getBriefing(s, now) {
  return safe(() => pm.briefing(s, now, { permission: safe(() => remind.permission(), "unsupported") }), null) || {
    greeting: safe(() => dates.greeting(now), "Hallo"), name: s.profile.name, daypart: "day", dateLabel: now.toLocaleDateString("de-DE", { weekday: "long", day: "numeric", month: "long" }),
    headline: "Dein Tag", summary: "", counts: { overdue: 0, today: 0, planned: 0, inbox: 0, doneToday: 0, upcoming: 0 }, progress: 0,
    overdue: [], today: [], timeline: [], focus: [], doneToday: [], stalled: [], deadlines: [], tips: [],
  };
}

// ---------- Ansicht ----------
export function title() {
  return "Heute";
}

export function render() {
  const s = store.get();
  const now = app.now;
  const tdy = today();
  const b = getBriefing(s, now);
  const p = s.profile;
  const dp = b.daypart || safe(() => dates.daypart(now), "day");
  const name = (p.name || "").trim();
  const kw = isoWeek(tdy);
  const open = store.tasks().filter((t) => !t.done);

  // Listen ohne Doppelte
  const focus = (b.focus || []).filter(Boolean);
  const focusIds = new Set(focus.map((t) => t.id));
  const timeline = (b.timeline || []).filter((t) => t && (!t.done || pending.has(t.id)));
  const tlIds = new Set(timeline.map((t) => t.id));
  const overdue = (b.overdue || []).filter((t) => !focusIds.has(t.id));
  const planned = open.filter((t) => t.plan === tdy);
  const todaySet = new Map();
  for (const t of [...(b.today || []), ...planned]) if (t && !t.done && !focusIds.has(t.id) && !tlIds.has(t.id) && !todaySet.has(t.id)) todaySet.set(t.id, t);
  for (const id of pending.keys()) {
    const t = store.task(id);
    if (t && !focusIds.has(id) && !tlIds.has(id) && (t.due === tdy || t.plan === tdy) && !todaySet.has(id)) todaySet.set(id, t);
  }
  const todayList = [...todaySet.values()].filter((t) => !overdue.some((o) => o.id === t.id));
  const doneToday = (b.doneToday || []).filter((t) => !pending.has(t.id));
  const pct = Math.round((b.progress || 0) * 100);
  const c = b.counts || {};

  // Kopf
  const avatar = `<button type="button" class="avatar only-phone" data-act="go" data-to="#einstellungen" aria-label="Einstellungen">${name ? esc(name[0].toUpperCase()) : icon("person")}</button>`;
  let html = largeTitle("Heute", { sub: `${esc(b.dateLabel || "")} · KW ${kw}`, right: avatar, key: "lt-heute" });

  // Hero-Briefing
  const chips = [
    c.overdue ? `<button type="button" class="hchip red" data-act="scroll-to" data-to="sec-overdue">${icon("flag")}<b>${c.overdue}</b> überfällig</button>` : "",
    `<button type="button" class="hchip" data-act="scroll-to" data-to="${focus.length ? "sec-focus" : "sec-today"}">${icon("sun")}<b>${(c.today || 0) + (c.planned || 0)}</b> heute</button>`,
    c.inbox ? `<button type="button" class="hchip" data-act="go" data-to="#eingang">${icon("tray")}<b>${c.inbox}</b> im Eingang</button>` : "",
    `<button type="button" class="hchip" data-act="scroll-to" data-to="sec-done">${icon("check")}<b>${c.doneToday || 0}</b> erledigt</button>`,
  ].join("");
  const tips = (b.tips || []).slice(0, 3);
  html += `<section class="hero dp-${esc(dp)}" data-key="hero">
<div class="hero-art" aria-hidden="true"><i></i><i></i><i></i></div>
<div class="hero-top"><div class="hero-text"><p class="hero-greet">${esc(b.greeting || "Hallo")}${name ? `, ${esc(name)}` : ""}</p><h2 class="hero-head">${esc(b.headline || "")}</h2></div>${ring(pct, { size: 76, stroke: 7, cls: "hero-ring", sub: "geschafft" })}</div>
${b.summary ? `<p class="hero-sum">${esc(b.summary)}</p>` : ""}
<div class="hero-chips">${chips}</div>
${tips.length ? `<div class="hero-tips">${tips.map((tp, i) => `<button type="button" class="tip" data-act="tip" data-i="${i}"><span class="tip-e">${esc(tp.icon || "💡")}</span><span>${esc(tp.text)}</span>${icon("chevronRight")}</button>`).join("")}</div>` : ""}
${app.ai ? `<button type="button" class="hero-ai" data-act="ai-plan">${icon("sparkle")}<span>Frag deinen KI-PM, wie du heute vorgehst</span></button>` : ""}
</section>`;

  // Morgens: Tag planen
  const dayStartH = Number(String(p.dayStart || "08:00").split(":")[0]) || 8;
  if (now.getHours() < Math.max(12, dayStartH + 3) && prefs.plannedDay !== tdy && !planned.length && open.length) {
    html += `<button type="button" class="banner plan" data-key="plan-banner" data-act="plan-day"><span class="banner-ic">${icon("sunrise")}</span><span class="banner-t"><b>Tag planen</b><small>In 60 Sekunden festlegen, was heute zählt</small></span>${icon("chevronRight")}</button>`;
  }

  // Fokus
  if (focus.length) {
    html += sec({
      key: "focus", title: "Dein Fokus", icon: "target", tone: "accent", plain: true,
      note: `${icon("sparkle")} vom PM`,
      body: `<div class="focus-list">${focus.map((t, i) => focusCard(t, i)).join("")}</div>`,
    });
  } else if (doneToday.length && !overdue.length && !todayList.length) {
    html += `<section class="sec" data-key="sec-focus" id="sec-focus"><div class="alldone"><div class="alldone-ic">🎉</div><h3>Alles erledigt!</h3><p>${doneToday.length === 1 ? "Eine Aufgabe" : doneToday.length + " Aufgaben"} geschafft. Gönn dir den Feierabend – oder hol dir etwas für morgen vor.</p><button type="button" class="btn" data-act="go" data-to="#demnaechst">${icon("calendar")}<span>Was kommt als Nächstes?</span></button></div></section>`;
    if (prefs.confettiDay !== tdy) {
      setPref("confettiDay", tdy);
      setTimeout(() => confetti(), 400);
    }
  } else if (!open.length) {
    html += empty({ emoji: "🌤️", title: "Ein freier Tag", text: "Keine offenen Aufgaben. Leg los mit deiner ersten – oder genieß die Ruhe.", action: `<button type="button" class="btn primary" data-act="new-task">${icon("plus")}<span>Aufgabe hinzufügen</span></button>` });
  }

  // Zeitplan
  if (timeline.length) html += sec({ key: "timeline", title: "Zeitplan", icon: "clock", tone: "indigo", plain: true, body: timelineHTML(timeline, now) });

  // Überfällig
  if (overdue.length) {
    html += sec({
      key: "overdue", title: "Überfällig", icon: "flag", tone: "red", count: overdue.length,
      actions: `<button type="button" class="pill red" data-act="overdue-today">Alle auf heute</button><button type="button" class="pill" data-act="overdue-menu">Neu planen …</button>`,
      body: overdue.map((t) => taskRow(t)).join(""),
    });
  }

  // Heute fällig & eingeplant
  if (todayList.length) {
    html += sec({ key: "today", title: "Außerdem heute", icon: "sun", tone: "orange", count: todayList.length, body: todayList.map((t) => taskRow(t, { plan: false })).join("") + addRow() });
  } else if (focus.length || timeline.length) {
    html += `<div class="add-line" data-key="add-line">${addRow(true)}</div>`;
  }

  // Installations-Hinweis / Erinnerungs-Karte (nach den Aufgaben – zuerst zählt, was ansteht)
  const inst = installHint();
  html += inst;
  html += reminderCard(!!inst);

  // Im Blick
  const stalled = (b.stalled || []).map((x) => ({ ...x, bag: asBag(x.bag) })).filter((x) => x.bag);
  const deadlines = (b.deadlines || []).map((x) => ({ ...x, bag: asBag(x.bag) })).filter((x) => x.bag);
  if (stalled.length || deadlines.length) {
    const rows = [
      ...deadlines.map((x) => `<button type="button" class="watch" data-act="go" data-to="#tasche/${x.bag.id}" style="${bagVars(x.bag)}">${bagSquircle(x.bag, "sm")}<span class="watch-t"><b>${esc(x.bag.name)}</b><small>${x.days < 0 ? `Deadline seit ${-x.days} ${-x.days === 1 ? "Tag" : "Tagen"} vorbei` : x.days === 0 ? "Deadline ist heute" : `Deadline in ${x.days} ${x.days === 1 ? "Tag" : "Tagen"}`}</small></span><span class="watch-badge ${x.days <= 3 ? "red" : "orange"}">${icon("flag")}${x.days < 0 ? "vorbei" : x.days + " T"}</span></button>`),
      ...stalled.map((x) => `<button type="button" class="watch" data-act="go" data-to="#tasche/${x.bag.id}" style="${bagVars(x.bag)}">${bagSquircle(x.bag, "sm")}<span class="watch-t"><b>${esc(x.bag.name)}</b><small>Seit ${x.idleDays} Tagen nichts passiert</small></span><span class="watch-badge gray">${icon("zzz")}ruhig</span></button>`),
    ];
    html += sec({ key: "watch", title: "Im Blick", icon: "eye", tone: "purple", body: rows.join("") });
  }

  // Wochenrückblick am Rückblick-Tag
  const wd = safe(() => dates.weekday(tdy), -1);
  const weekStart = safe(() => dates.startOfWeek(tdy, p.weekStart ?? 1), tdy);
  if (wd === (p.reviewDay ?? 5) && !(s.meta?.lastReview && s.meta.lastReview >= weekStart)) {
    html += `<button type="button" class="banner review" data-key="review-banner" data-act="go" data-to="#rueckblick"><span class="banner-ic">${icon("chart")}</span><span class="banner-t"><b>Wochenrückblick starten</b><small>ca. 5 Minuten · Erfolge feiern, aufräumen, nächste Woche planen</small></span>${icon("chevronRight")}</button>`;
  }

  // Abends: Tagesabschluss
  if ((dp === "evening" || dp === "night") && p.evening !== false && prefs.eveningDone !== tdy) html += eveningCard(s, now);

  // Erledigt heute
  if (doneToday.length) {
    html += sec({ key: "done", title: "Erledigt heute", icon: "checkCircle", tone: "green", count: doneToday.length, collapsible: true, collapsed: true, body: doneToday.map((t) => taskRow(t)).join("") });
  }

  html += `<footer class="view-foot" data-key="foot"><button type="button" class="link-btn" data-act="go" data-to="#rueckblick">${icon("chart")}<span>Wochenrückblick</span></button><span>·</span><button type="button" class="link-btn" data-act="plan-day">${icon("sunrise")}<span>Tag planen</span></button>${!app.wide ? `<span>·</span><button type="button" class="link-btn" data-act="go" data-to="#einstellungen">${icon("gear")}<span>Einstellungen</span></button>` : ""}</footer>`;
  return `<div class="view view-heute" data-key="view-heute">${html}</div>`;
}

// ---------- Bausteine ----------
function addRow(standalone = false) {
  return `<button type="button" class="add-row${standalone ? " solo" : ""}" data-act="new-task" data-plan="1">${icon("plus")}<span>Aufgabe für heute</span></button>`;
}

function focusCard(t, i) {
  const bag = t.bag ? store.bag(t.bag) : null;
  const done = !!t.done || pending.has(t.id);
  const meta = taskMeta(t, { bag: false });
  return `<article class="fcard${done ? " done checking" : ""}" data-key="f-${t.id}" data-task="${t.id}" data-menu="task" data-id="${t.id}" style="${bagVars(bag)}">
<span class="fnum" aria-hidden="true">${i + 1}</span>
<button class="check big" type="button" data-act="toggle" data-id="${t.id}" aria-label="Erledigen: ${esc(t.title)}" aria-pressed="${done}">${CHECK}</button>
<button type="button" class="fmain" data-act="task" data-id="${t.id}"><span class="fbag">${bag ? `${esc(bag.emoji)} ${esc(bag.name)}` : "📥 Eingang"}</span><span class="ftitle">${esc(t.title)}</span>${meta ? `<span class="task-meta">${meta}</span>` : ""}</button>
<button type="button" class="fplay" data-act="task-focus" data-id="${t.id}" aria-label="Fokus-Timer starten" title="Fokus-Timer">${icon("play")}</button>
</article>`;
}

function timelineHTML(list, now) {
  const nowMin = now.getHours() * 60 + now.getMinutes();
  const items = list.slice().sort((a, b) => String(a.time).localeCompare(String(b.time)));
  let html = `<div class="timeline card">`;
  let nowPlaced = false;
  const nowLine = `<div class="tl-now" data-key="tl-now"><time>${esc(now.toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" }))}</time><i></i></div>`;
  for (const t of items) {
    const [h, m] = String(t.time || "0:0").split(":").map(Number);
    const min = h * 60 + m;
    if (!nowPlaced && min > nowMin) {
      html += nowLine;
      nowPlaced = true;
    }
    const bag = t.bag ? store.bag(t.bag) : null;
    const past = min + (t.est || 30) < nowMin && !t.done;
    const done = !!t.done || pending.has(t.id);
    html += `<div class="tl-item${done ? " done" : ""}${past && !done ? " missed" : ""}" data-key="tl-${t.id}" data-task="${t.id}" data-menu="task" data-id="${t.id}" style="${bagVars(bag)}">
<time>${esc(safe(() => dates.fmtTime(t.time), t.time))}</time><span class="tl-dot"></span>
<div class="tl-body"><button class="check" type="button" data-act="toggle" data-id="${t.id}" aria-label="Erledigen: ${esc(t.title)}" aria-pressed="${done}">${CHECK}</button><button type="button" class="tl-main" data-act="task" data-id="${t.id}"><b>${esc(t.title)}</b><small>${bag ? `${esc(bag.emoji)} ${esc(bag.name)}` : "Eingang"}${t.est ? " · " + esc(safe(() => dates.fmtDuration(t.est), "")) : ""}${past && !done ? ` · <em>verpasst</em>` : ""}</small></button></div>
</div>`;
  }
  if (!nowPlaced) html += nowLine;
  return html + `</div>`;
}

function reminderCard(installShown = false) {
  if (prefs.remindCard === "hidden") return "";
  const perm = safe(() => remind.permission(), "unsupported");
  if (perm === "granted") return "";
  const env = safe(() => remind.env(), {});
  if (installShown && env.ios && !env.standalone) return ""; // die Installations-Karte sagt schon alles
  let text, btns;
  if (env.ios && !env.standalone) {
    text = "Auf dem iPhone und iPad gibt es Mitteilungen nur in der installierten App. Bis dahin: Termine mit Wecker in deinen Kalender.";
    btns = `<button type="button" class="btn primary sm" data-act="install-help">${icon("share")}<span>App installieren</span></button><button type="button" class="btn sm" data-act="ics-daily">${icon("calendarPlus")}<span>Kalender</span></button>`;
  } else if (perm === "denied") {
    text = "Mitteilungen sind blockiert. Erlaube sie in den Systemeinstellungen – oder hol dir die Termine mit Wecker in den Kalender.";
    btns = `<button type="button" class="btn sm" data-act="ics-daily">${icon("calendarPlus")}<span>Kalender</span></button>`;
  } else if (perm === "unsupported" || !env.notifications) {
    text = "Hol dir dein Tagesbriefing und alle Termine mit Wecker in den Kalender – das klingelt auch, wenn die App zu ist.";
    btns = `<button type="button" class="btn primary sm" data-act="ics-daily">${icon("calendarPlus")}<span>In den Kalender</span></button>`;
  } else {
    text = "Ich erinnere dich morgens an deinen Tag und kurz vor Terminen. Für Wecker bei geschlossener App: Kalender.";
    btns = `<button type="button" class="btn primary sm" data-act="enable-notify">${icon("bell")}<span>Erlauben</span></button><button type="button" class="btn sm" data-act="ics-daily">${icon("calendarPlus")}<span>Kalender</span></button>`;
  }
  return `<section class="rcard" data-key="rcard"><span class="rcard-ic">${icon("bell")}</span><div class="rcard-b"><h3>Lass dich erinnern</h3><p>${esc(text)}</p><div class="rcard-btns">${btns}</div></div><button type="button" class="rcard-x" data-act="rcard-hide" aria-label="Ausblenden">${icon("x")}</button></section>`;
}

function eveningCard(s, now) {
  const ev = safe(() => pm.evening(s, now), null);
  if (!ev) return "";
  const left = ev.left || [], done = ev.done || [], tmw = ev.tomorrow || [];
  return `<section class="evening" data-key="evening">
<div class="ev-head"><span class="ev-ic">${icon("moon")}</span><div><h3>Tagesabschluss</h3><p>${esc(ev.text || "")}</p></div></div>
<div class="ev-stats"><span><b>${done.length}</b> erledigt</span><span><b>${left.length}</b> offen</span><span><b>${tmw.length}</b> morgen</span></div>
${tmw.length ? `<div class="ev-tmw"><small>Morgen</small>${tmw.slice(0, 3).map((t) => `<button type="button" data-act="task" data-id="${t.id}">${esc(t.title)}</button>`).join("")}</div>` : ""}
<div class="ev-btns">${left.length ? `<button type="button" class="btn primary sm" data-act="ev-move">${icon("sunrise")}<span>Rest auf morgen (${left.length})</span></button>` : ""}<button type="button" class="btn sm" data-act="ev-done">${icon("check")}<span>Feierabend</span></button></div>
</section>`;
}

// ---------- Tag planen (Morgen-Ritual) ----------
export function openPlanDay() {
  openSheet({ key: "plan", label: "Tag planen", size: "large", render: planView });
}

function planView() {
  const s = store.get();
  const now = new Date();
  const r = safe(() => pm.planDay(s, now), { candidates: [], capacity: 0, load: 0, warning: null });
  const tdy = today();
  const cap = Math.max(0, r.capacity || 0), load = r.load || 0;
  const pct = cap ? Math.min(100, (load / cap) * 100) : load ? 100 : 0;
  const over = cap && load > cap;
  const cands = (r.candidates || []).filter((t) => t && !t.done);
  const n = cands.filter((t) => t.plan === tdy).length;
  return `${sheetHead("Tag planen", { sub: "Tippe an, was heute dran ist" })}
<div class="sheet-pad plan">
<div class="cap-card${over ? " over" : ""}"><div class="cap-row"><span><b>${esc(safe(() => dates.fmtDuration(load), load + " Min."))}</b> geplant</span><span>${cap ? esc(safe(() => dates.fmtDuration(cap), cap + " Min.")) + " frei bis Feierabend" : "Feierabend erreicht"}</span></div>${bar(pct, over ? "red" : pct > 80 ? "orange" : "green")}${r.warning ? `<p class="cap-warn">${icon("info")}${esc(r.warning)}</p>` : `<p class="cap-ok">${n ? `${n} ${n === 1 ? "Aufgabe" : "Aufgaben"} eingeplant` : "Noch nichts eingeplant"} · Aufgaben ohne Dauer zählen 30 Min.</p>`}</div>
${cands.length ? `<div class="card list pd-list">${cands.map((t) => { const on = t.plan === tdy; const bag = t.bag ? store.bag(t.bag) : null; return `<div class="pd-row${on ? " on" : ""}" data-key="pd-${t.id}" style="${bagVars(bag)}"><button type="button" class="pd-tog" data-act="pd-toggle" data-id="${t.id}" aria-pressed="${on}" aria-label="${on ? "Aus Heute entfernen" : "Für heute einplanen"}">${icon(on ? "starFill" : "star")}</button><button type="button" class="task-main" data-act="task" data-id="${t.id}"><span class="task-title">${esc(t.title)}</span><span class="task-meta">${taskMeta(t, { plan: false })}</span></button></div>`; }).join("")}</div>` : empty({ emoji: "🧘", title: "Nichts Dringendes", text: "Keine überfälligen oder fälligen Aufgaben. Plane etwas aus deinen Taschen ein oder genieß den freien Kopf." })}
${app.ai ? `<button type="button" class="btn ai wide" data-act="ai-plan">${icon("sparkle")}<span>Vorschlag vom KI-PM</span></button>` : ""}
<button type="button" class="btn primary wide" data-act="plan-done">${icon("check")}<span>Fertig – los geht’s</span></button>
</div>`;
}

// ---------- Kalender-Export (Tagesbriefing + Termine) ----------
export function exportCalendar({ daily = true } = {}) {
  try {
    const s = store.get();
    const bagsById = Object.fromEntries(store.bags().map((b) => [b.id, b]));
    const tasks = store.tasks().filter((t) => !t.done && t.due);
    const url = appUrl();
    let ics = tasks.length ? remind.icsForTasks(tasks, { bagsById, profile: s.profile, calName: "Arbeitstaschen", appUrl: url }) : "";
    if (daily) {
      const d = remind.icsDaily(s.profile, { appUrl: url });
      ics = ics ? mergeIcs(ics, d) : d;
    }
    const ms = safe(() => store.milestones().filter((m) => !m.done && m.date), []);
    if (ms.length) ics = mergeIcs(ics, remind.icsForMilestones(ms, { bagsById }));
    remind
      .deliverFile(daily ? "arbeitstaschen-wecker.ics" : "arbeitstaschen-termine.ics", "text/calendar", ics)
      .then((how) => {
        if (how === "downloaded") toast("Kalender-Datei geladen", { icon: "calendarCheck", sub: "Öffnen und „Alle hinzufügen“ wählen" });
      })
      .catch((e) => toastError(e));
  } catch (e) {
    toastError(e);
  }
}

// Termine aus b in Kalender a übernehmen (VEVENT-Blöcke)
export function mergeIcs(a, b) {
  if (!a) return b;
  if (!b) return a;
  const ev = b.match(/BEGIN:VEVENT[\s\S]*?END:VEVENT\r?\n/g) || [];
  if (!ev.length) return a;
  const i = a.lastIndexOf("END:VCALENDAR");
  return i < 0 ? a : a.slice(0, i) + ev.join("") + a.slice(i);
}

// ---------- Tipps des PM ----------
function runTip(i) {
  const s = store.get();
  const b = getBriefing(s, new Date());
  const tp = (b.tips || [])[i];
  const a = tp?.action;
  if (!a) return;
  switch (a.type) {
    case "open-bag":
      return app.go("#tasche/" + a.id);
    case "open-inbox":
      return app.go("#eingang");
    case "plan-overdue":
      return allToToday(b.overdue || []);
    case "review":
      return app.go("#rueckblick");
    case "backup":
      return app.go("#einstellungen/daten");
    case "enable-reminders":
      return enableNotify();
    case "open-task":
      return a.id && openTask(a.id);
    case "open-upcoming":
      return app.go("#demnaechst");
  }
}

// Mitteilungen erlauben – MUSS synchron im Klick laufen (iOS)
export function enableNotify() {
  let pr;
  try {
    pr = remind.enable();
  } catch (e) {
    toastError(e);
    return;
  }
  Promise.resolve(pr)
    .then((perm) => {
      if (perm === "granted") {
        toast("Mitteilungen sind an", { icon: "bell", sub: "Ich erinnere dich an deinen Tag" });
        safe(() => remind.test());
      } else if (perm === "denied") toast("Mitteilungen blockiert", { icon: "bellOff", tone: "red", sub: "In den Systemeinstellungen erlauben" });
      else if (perm === "unsupported") toast(isStandalone() ? "Mitteilungen werden hier nicht unterstützt" : "Erst als App installieren", { icon: "info" });
      app.render();
    })
    .catch((e) => toastError(e));
}

// ---------- Ereignisse ----------
on("click", {
  tip: (el) => runTip(+el.dataset.i),
  "scroll-to": (el) => {
    const t = document.getElementById(el.dataset.to);
    if (!t) return;
    if (t.classList.contains("collapsed")) t.querySelector(".sec-toggle")?.click();
    const top = t.getBoundingClientRect().top + window.scrollY - (app.wide ? 70 : 100);
    window.scrollTo({ top, behavior: "smooth" });
  },
  "new-task": (el) => openCapture({ plan: el.dataset.plan === "1", bag: el.dataset.bag || null, section: el.dataset.section || "", due: el.dataset.due || null }),
  "overdue-today": () => allToToday(getBriefing(store.get(), new Date()).overdue || []),
  "overdue-menu": (el) => rescheduleMenu(getBriefing(store.get(), new Date()).overdue || [], { el }),
  "plan-day": () => openPlanDay(),
  "pd-toggle": (el) => {
    const t = store.task(el.dataset.id);
    if (!t) return;
    store.planTask(t.id, t.plan === today() ? null : today());
    haptic();
  },
  "plan-done": () => {
    setPref("plannedDay", today());
    getSheet("plan")?.close();
    const n = store.tasks().filter((t) => !t.done && t.plan === today()).length;
    sound("soft");
    toast(n ? `${n} ${n === 1 ? "Aufgabe" : "Aufgaben"} für heute – los geht’s!` : "Tag geplant", { icon: "sunrise" });
    app.render();
  },
  "ai-plan": () =>
    askAI({
      kind: "plan-day",
      title: "Dein Tagesplan",
      question: "Wie gehe ich heute am besten vor? Was zuerst, was kann warten?",
      applyLabel: "Für heute einplanen",
      apply: (items) => {
        let n = 0;
        for (const it of items) {
          const ex = store.tasks().find((t) => !t.done && t.title.trim().toLowerCase() === String(it.title).trim().toLowerCase());
          if (ex) store.planTask(ex.id, today());
          else store.addTask({ title: it.title, plan: today(), due: it.due || null, prio: it.prio || 0 });
          n++;
        }
        toast(`${n} für heute eingeplant`, { icon: "sparkle" });
      },
    }),
  "enable-notify": () => enableNotify(),
  "ics-daily": () => exportCalendar({ daily: true }),
  "install-help": () => openInstallHelp(),
  "rcard-hide": () => {
    setPref("remindCard", "hidden");
    app.render();
  },
  "ev-move": () => {
    const ev = safe(() => pm.evening(store.get(), new Date()), null);
    if (!ev) return;
    const tdy = today(), tmw = tomorrow();
    batch(ev.left || [], (t) => {
      const p = {};
      if (t.plan && t.plan <= tdy) p.plan = tmw;
      if (t.due && t.due <= tdy) p.due = tmw;
      if (!p.plan && !p.due) p.plan = tmw;
      return p;
    }, "{n} auf morgen verschoben", "sunrise");
  },
  "ev-done": () => {
    setPref("eveningDone", today());
    sound("soft");
    toast("Schönen Feierabend!", { icon: "moon", sub: "Morgen früh gibt’s dein Briefing" });
    app.render();
  },
});

