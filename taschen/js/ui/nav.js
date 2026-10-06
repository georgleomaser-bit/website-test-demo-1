// Arbeitstaschen – Navigation: Glas-Seitenleiste (iPad/Mac), schwebende Tab-Leiste mit Suche und Plus (iPhone), Kopfzeile
import * as store from "../store.js";
import * as pm from "../pm.js";
import * as dates from "../dates.js";
import { esc } from "../util.js";
import { icon, logo } from "./icons.js";
import { app, safe, bagVars, today, modKey, relTime } from "./core.js";
import { ring } from "./components.js";
import { mails as connectMails } from "../connect.js";

const SYNC = { off: ["", "Lokal auf diesem Gerät"], idle: ["green", "Synchron"], syncing: ["blue", "Synchronisiere …"], error: ["red", "Sync-Fehler"], offline: ["orange", "Offline"] };

export function counts() {
  const s = store.get();
  const tdy = today();
  const open = store.tasks().filter((t) => !t.done);
  return {
    today: safe(() => pm.badgeCount(s, app.now), open.filter((t) => (t.due && t.due <= tdy) || t.plan === tdy).length),
    inbox: open.filter((t) => !t.bag).length,
    overdue: open.filter((t) => t.due && t.due < tdy).length,
    mails: safe(() => connectMails().length, 0), // markierte Mails, die noch nicht übernommen sind
  };
}

function reviewDue() {
  const s = store.get();
  const p = s.profile;
  const tdy = today();
  const wd = safe(() => dates.weekday(tdy), -1);
  const ws = safe(() => dates.startOfWeek(tdy, p.weekStart ?? 1), tdy);
  return wd === (p.reviewDay ?? 5) && !(s.meta?.lastReview && s.meta.lastReview >= ws);
}

// ---------- Seitenleiste ----------
export function sidebar() {
  const c = counts();
  const v = app.route.view;
  const sy = app.syncState || { state: "off" };
  const [dot, label] = SYNC[sy.state] || SYNC.off;
  const item = (hash, ic, color, txt, n, on, extra = "") => `<a class="sb-item${on ? " on" : ""}" href="${hash}" ${on ? 'aria-current="page"' : ""}><span class="sq" style="--bl:var(--${color});--bd:var(--${color})">${icon(ic)}</span><span class="sb-t">${txt}</span>${extra}${n ? `<span class="sb-n">${n}</span>` : ""}</a>`;
  const bags = store.bags();
  const active = bags.filter((b) => b.status === "aktiv");
  const other = bags.filter((b) => b.status !== "aktiv");
  const bagItem = (b) => {
    const st = safe(() => pm.bagStats(store.get(), b.id, app.now), null);
    const on = v === "tasche" && app.route.id === b.id;
    return `<a class="sb-bag${on ? " on" : ""}${b.status !== "aktiv" ? " dim" : ""}" href="#tasche/${b.id}" data-key="sb-${b.id}" data-menu="bag" data-id="${b.id}" style="${bagVars(b)}" ${on ? 'aria-current="page"' : ""}><span class="sb-emoji">${esc(b.emoji)}</span><span class="sb-t">${esc(b.name)}</span>${st && st.overdue ? `<span class="sb-od" title="${st.overdue} überfällig"></span>` : ""}${ring(st ? st.pct : 0, { size: 20, stroke: 3, label: false, cls: "sb-ring" })}${st && st.open ? `<span class="sb-n soft">${st.open}</span>` : ""}</a>`;
  };
  return `<div class="sb-in">
<a class="sb-brand" href="#einstellungen/sync" title="Sync auf allen Geräten">${logo()}<span class="sb-bt"><b>Arbeitstaschen</b><small><i class="sdot ${dot}"></i>${esc(label)}${sy.state === "idle" && sy.lastSync ? ` · ${esc(relTime(sy.lastSync))}` : ""}</small></span></a>
<button type="button" class="sb-search" data-act="search">${icon("search")}<span>Suchen</span><kbd>${modKey()}K</kbd></button>
<button type="button" class="sb-new" data-act="fab">${icon("plus")}<span>Neue Aufgabe</span><kbd>N</kbd></button>
<nav class="sb-nav" aria-label="Bereiche">
${item("#heute", "sun", "orange", "Heute", c.today, v === "heute", c.overdue ? `<span class="sb-od" title="${c.overdue} überfällig"></span>` : "")}
${item("#demnaechst", "calendar", "red", "Demnächst", 0, v === "demnaechst")}
${item("#eingang", "tray", "blue", "Eingang", c.inbox + c.mails, v === "eingang")}
${item("#rueckblick", "chart", "purple", "Rückblick", 0, v === "rueckblick", reviewDue() ? `<span class="sb-due">fällig</span>` : "")}
</nav>
<div class="sb-sec"><a href="#taschen" class="sb-sec-t${v === "taschen" ? " on" : ""}">Taschen</a><button type="button" class="btn-round xs" data-act="bag-new" aria-label="Neue Tasche" title="Neue Tasche">${icon("plus")}</button></div>
<nav class="sb-bags" aria-label="Taschen">${active.map(bagItem).join("")}${other.length ? `<div class="sb-sub">Pausiert & fertig</div>${other.map(bagItem).join("")}` : ""}${!bags.length ? `<button type="button" class="sb-empty" data-act="bag-new">${icon("plus")}<span>Erste Tasche anlegen</span></button>` : ""}</nav>
<div class="sb-foot">${item("#einstellungen", "gear", "gray", "Einstellungen", 0, v === "einstellungen")}</div>
</div>`;
}

// ---------- Tab-Leiste (iPhone) ----------
export function tabbar() {
  const c = counts();
  const v = app.route.view;
  const tab = (hash, id, ic, label, n = 0) => {
    const on = v === id || (id === "taschen" && v === "tasche");
    return `<a class="tb${on ? " on" : ""}" href="${hash}" ${on ? 'aria-current="page"' : ""}><span class="tb-ic">${icon(ic)}${n ? `<b class="badge">${n > 99 ? "99+" : n}</b>` : ""}</span><span class="tb-l">${label}</span></a>`;
  };
  return `<div class="tb-pill">${tab("#heute", "heute", "sun", "Heute", c.today)}${tab("#demnaechst", "demnaechst", "calendar", "Demnächst")}${tab("#taschen", "taschen", "bag", "Taschen")}${tab("#eingang", "eingang", "tray", "Eingang", c.inbox + c.mails)}</div><button type="button" class="tb-search" data-act="search" aria-label="Suchen">${icon("search")}</button>`;
}

// ---------- Kopfzeile ----------
export function topbar(title, { back = null, actions = "" } = {}) {
  return `<div class="tp-l">${back ? `<button type="button" class="tp-back" data-act="back" aria-label="Zurück zu ${esc(back)}">${icon("chevronLeft")}<span>${esc(back)}</span></button>` : ""}</div><div class="tp-c"><span class="tp-title">${esc(title)}</span></div><div class="tp-r">${actions}</div>`;
}
