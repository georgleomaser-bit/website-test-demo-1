// Arbeitstaschen – Onboarding beim ersten Start: Willkommen, Name, Bereiche des Jobs, Tagesrhythmus & Erinnerungen, Fertig
import * as store from "../store.js";
import * as remind from "../remind.js";
import { AREAS } from "./templates.js";
import { esc } from "../util.js";
import { icon, logo } from "./icons.js";
import { app, on, render, safe, colorVars } from "./core.js";
import { haptic, toast, toastError, confetti, sound } from "./fx.js";
import { enableNotify } from "./today.js";

let ob = null;
const el = () => document.getElementById("onboarding");

export function openOnboarding() {
  const p = store.get().profile;
  ob = { step: 0, name: p.name || "", areas: [], custom: [], customText: "", dayStart: p.dayStart || "08:00", dayEnd: p.dayEnd || "18:00" };
  const o = el();
  if (!o) return;
  o.hidden = false;
  document.documentElement.classList.add("ob-on");
  paint();
  requestAnimationFrame(() => requestAnimationFrame(() => o.classList.add("open")));
}

export const onboardingOpen = () => !!ob;

export function paint() {
  const o = el();
  if (!o || !ob) return;
  render(o, view());
}

function dots() {
  return `<div class="ob-dots" aria-hidden="true">${[0, 1, 2, 3].map((i) => `<i class="${i === ob.step ? "on" : i < ob.step ? "done" : ""}"></i>`).join("")}</div>`;
}

function view() {
  const s = ob.step;
  let body = "";
  if (s === 0) {
    body = `<div class="ob-hero"><div class="ob-logo">${logo()}</div><h1>Arbeitstaschen</h1><p class="ob-sub">Dein persönlicher Projektmanager</p></div>
<ul class="ob-feats">
<li><span class="sq" style="${colorVars("blue")}">${icon("bag")}</span><span><b>Jedes Projekt in seiner Tasche</b><small>Aufgaben, Notizen, Links, Dateien und Meilensteine</small></span></li>
<li><span class="sq" style="${colorVars("orange")}">${icon("sunrise")}</span><span><b>Jeden Morgen dein Briefing</b><small>Was heute zählt – und Erinnerungen im richtigen Moment</small></span></li>
<li><span class="sq" style="${colorVars("green")}">${icon("devices")}</span><span><b>iPhone, iPad und Mac</b><small>Offline, privat und verschlüsselt synchron</small></span></li>
</ul>
<button type="button" class="btn primary xl" data-act="ob-next">Los geht’s ${icon("arrowRight")}</button>`;
  } else if (s === 1) {
    body = `${dots()}<div class="ob-q"><span class="ob-emoji">👋</span><h2>Wie soll ich dich nennen?</h2><p>Für dein Briefing am Morgen.</p></div>
<input class="ob-input" type="text" value="${esc(ob.name)}" placeholder="Dein Vorname" data-input="ob-name" data-key-act="ob-enter" autocomplete="given-name" autocapitalize="words" enterkeyhint="next" aria-label="Dein Name" />
<button type="button" class="btn primary xl" data-act="ob-next">${ob.name.trim() ? `Weiter, ${esc(ob.name.trim())}` : "Weiter"} ${icon("arrowRight")}</button>
<button type="button" class="btn-text" data-act="ob-skip-name">Überspringen</button>`;
  } else if (s === 2) {
    const n = ob.areas.length + ob.custom.length;
    body = `${dots()}<div class="ob-q"><span class="ob-emoji">👜</span><h2>Was gehört zu deiner Arbeit?</h2><p>Für jeden Bereich lege ich eine leere Tasche an. Alles lässt sich später ändern.</p></div>
<div class="ob-areas">${AREAS.map((a, i) => `<button type="button" class="ob-area${ob.areas.includes(a.id) ? " on" : ""}" data-act="ob-area" data-v="${a.id}" style="${colorVars(a.color)};--k:${i}" aria-pressed="${ob.areas.includes(a.id)}"><span class="ob-area-e">${esc(a.emoji)}</span><span class="ob-area-n">${esc(a.name)}</span><span class="ob-area-c">${icon("check")}</span></button>`).join("")}${ob.custom.map((c, i) => `<button type="button" class="ob-area on" data-act="ob-custom-del" data-i="${i}" style="${colorVars("purple")};--k:0" aria-label="${esc(c)} entfernen"><span class="ob-area-e">👜</span><span class="ob-area-n">${esc(c)}</span><span class="ob-area-c">${icon("check")}</span></button>`).join("")}</div>
<div class="ob-custom"><input class="ob-input small" type="text" value="${esc(ob.customText)}" placeholder="Eigene Tasche, z. B. Baustelle Nord" data-input="ob-custom" data-key-act="ob-custom-enter" maxlength="80" enterkeyhint="done" aria-label="Eigene Tasche" /><button type="button" class="btn" data-act="ob-custom-add" ${ob.customText.trim() ? "" : "disabled"}>${icon("plus")}<span>Dazu</span></button></div>
<button type="button" class="btn primary xl" data-act="ob-areas-go">${n ? `${n} ${n === 1 ? "Tasche" : "Taschen"} anlegen` : "Leer starten"} ${icon("arrowRight")}</button>`;
  } else if (s === 3) {
    const env = safe(() => remind.env(), {});
    const perm = safe(() => remind.permission(), "unsupported");
    let rem;
    if (perm === "granted") rem = `<div class="ob-ok">${icon("checkCircle")}<span>Mitteilungen sind an – ich melde mich morgens und vor Terminen.</span></div>`;
    else if (env.ios && !env.standalone) rem = `<div class="ob-note"><span>${icon("info")}</span><span>Mitteilungen gibt es auf iPhone und iPad nur in der <b>installierten App</b>: Teilen → „Zum Home-Bildschirm“.</span></div><div class="ob-row"><button type="button" class="btn" data-act="install-help">${icon("share")}<span>So geht’s</span></button><button type="button" class="btn" data-act="ics-daily">${icon("calendarPlus")}<span>Kalender-Wecker</span></button></div>`;
    else if (perm === "default" && env.notifications) rem = `<button type="button" class="btn primary wide" data-act="ob-notify">${icon("bell")}<span>Mitteilungen erlauben</span></button><button type="button" class="btn wide" data-act="ics-daily">${icon("calendarPlus")}<span>Tagesbriefing in den Kalender</span></button>`;
    else rem = `<button type="button" class="btn wide" data-act="ics-daily">${icon("calendarPlus")}<span>Tagesbriefing in den Kalender</span></button><p class="fine">Der Kalender weckt dich auch, wenn die App geschlossen ist.</p>`;
    body = `${dots()}<div class="ob-q"><span class="ob-emoji">☀️</span><h2>Dein Tag</h2><p>Wann soll ich dich briefen – und wann ist Feierabend?</p></div>
<div class="card form ob-times"><label class="frow input"><span class="sq" style="${colorVars("orange")}">${icon("sunrise")}</span><span class="frow-l">Briefing</span><span class="frow-c"><input type="time" class="in-time" value="${esc(ob.dayStart)}" data-input="ob-time" data-f="dayStart" /></span></label><label class="frow input"><span class="sq" style="${colorVars("indigo")}">${icon("sunset")}</span><span class="frow-l">Feierabend</span><span class="frow-c"><input type="time" class="in-time" value="${esc(ob.dayEnd)}" data-input="ob-time" data-f="dayEnd" /></span></label></div>
<div class="ob-rem">${rem}</div>
<button type="button" class="btn primary xl" data-act="ob-next">Weiter ${icon("arrowRight")}</button>`;
  } else {
    const nb = store.bags().length, nt = store.tasks().filter((t) => !t.done).length;
    body = `<div class="ob-hero done"><div class="ob-check">${icon("check")}</div><h1>Alles bereit${ob.name.trim() ? `, ${esc(ob.name.trim())}` : ""}!</h1><p class="ob-sub">${nb ? `${nb} ${nb === 1 ? "Tasche" : "Taschen"} · ${nt} offene Aufgaben` : "Deine erste Tasche wartet"} · Briefing um ${esc(ob.dayStart)} Uhr</p></div>
<ul class="ob-feats tips"><li><span class="sq" style="${colorVars("blue")}">${icon("plus")}</span><span><b>Schnell erfassen</b><small>„Angebot schicken morgen 10 Uhr #Kunden !!!“ – ich erkenne alles</small></span></li><li><span class="sq" style="${colorVars("green")}">${icon("check")}</span><span><b>Wischen</b><small>Nach rechts erledigt, nach links verschieben oder löschen</small></span></li><li><span class="sq" style="${colorVars("purple")}">${icon("devices")}</span><span><b>Auf allen Geräten</b><small>Einstellungen → Sync einrichten</small></span></li></ul>
<button type="button" class="btn primary xl" data-act="ob-finish">Zu deinem Tag ${icon("arrowRight")}</button>`;
  }
  return `<div class="ob-card" data-key="ob-${s}"><div class="ob-step">${body}</div></div>`;
}

function next() {
  if (!ob) return;
  if (ob.step === 1) store.setProfile({ name: ob.name.trim() });
  if (ob.step === 3) store.setProfile({ dayStart: ob.dayStart, dayEnd: ob.dayEnd });
  ob.step = Math.min(4, ob.step + 1);
  haptic();
  paint();
  if (ob.step === 4) {
    setTimeout(() => {
      confetti();
      sound("all");
    }, 250);
  }
  if (ob.step === 1 && matchMedia("(pointer: fine)").matches) setTimeout(() => el()?.querySelector(".ob-input")?.focus(), 350);
}

// Eigene Tasche aus dem Eingabefeld übernehmen
function addCustom(repaint = true) {
  if (!ob) return;
  const name = ob.customText.trim().slice(0, 80);
  if (name && !ob.custom.some((c) => c.toLowerCase() === name.toLowerCase())) ob.custom.push(name);
  ob.customText = "";
  if (repaint) {
    haptic();
    paint();
    setTimeout(() => el()?.querySelector(".ob-custom .ob-input")?.focus(), 50);
  }
}

function finish() {
  if (!ob) return;
  store.setProfile({ onboarded: true, name: ob.name.trim(), dayStart: ob.dayStart, dayEnd: ob.dayEnd });
  Promise.resolve(safe(() => store.requestPersist())).catch(() => {});
  ob = null;
  const o = el();
  document.documentElement.classList.remove("ob-on");
  if (o) {
    o.classList.remove("open");
    o.classList.add("closing");
    setTimeout(() => {
      o.hidden = true;
      o.classList.remove("closing");
      o.innerHTML = "";
      o._html = null;
    }, 650);
  }
  app.go("#heute");
  app.render();
}

on("click", {
  "ob-next": () => next(),
  "ob-skip-name": () => {
    ob.name = "";
    next();
  },
  "ob-area": (el) => {
    if (!ob) return;
    const id = el.dataset.v;
    ob.areas = ob.areas.includes(id) ? ob.areas.filter((x) => x !== id) : [...ob.areas, id];
    haptic();
    paint();
  },
  "ob-custom-add": () => addCustom(),
  "ob-custom-del": (el) => {
    if (!ob) return;
    ob.custom.splice(+el.dataset.i, 1);
    haptic();
    paint();
  },
  "ob-areas-go": () => {
    if (!ob) return;
    addCustom(false);
    try {
      const have = new Set(store.bags().map((x) => x.name.trim().toLowerCase()));
      const pick = [...AREAS.filter((x) => ob.areas.includes(x.id)), ...ob.custom.map((name, i) => ({ name, emoji: "👜", color: ["purple", "cyan", "red", "yellow", "gray"][i % 5], sections: [] }))];
      let made = 0;
      for (const x of pick) {
        if (have.has(x.name.trim().toLowerCase())) continue;
        store.addBag({ name: x.name, emoji: x.emoji, color: x.color, sections: [...(x.sections || [])] });
        have.add(x.name.trim().toLowerCase());
        made++;
      }
      if (made) toast(`${made} ${made === 1 ? "Tasche" : "Taschen"} angelegt`, { icon: "bag" });
    } catch (e) {
      toastError(e);
    }
    next();
  },
  "ob-notify": () => {
    enableNotify();
    setTimeout(paint, 1200);
  },
  "ob-finish": () => finish(),
});

on("input", {
  "ob-name": (inp) => {
    if (!ob) return;
    ob.name = inp.value;
    paint();
  },
  "ob-custom": (inp) => {
    if (!ob) return;
    ob.customText = inp.value;
    paint();
  },
  "ob-time": (inp) => {
    if (ob && inp.value) ob[inp.dataset.f] = inp.value;
  },
});

on("keydown", {
  "ob-custom-enter": (_, e) => {
    if (e.key === "Enter" && !e.isComposing) {
      e.preventDefault();
      addCustom();
    }
  },
  "ob-enter": (_, e) => {
    if (e.key === "Enter" && !e.isComposing) {
      e.preventDefault();
      next();
    }
  },
});

