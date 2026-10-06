// Arbeitstaschen – Konten & Kalender in der Oberfläche: Termine (Heute, Zeitplan, Demnächst), markierte Mails (Eingang),
// Kalender/E-Mail/Anrufen an Aufgaben und die Einstellungen „Konten & Kalender“ (Google, Microsoft)
import * as store from "../store.js";
import * as dates from "../dates.js";
import * as pm from "../pm.js";
import * as remind from "../remind.js";
import * as connect from "../connect.js";
import { esc, safeUrl } from "../util.js";
import { icon } from "./icons.js";
import { app, on, today, safe, colorVars, relTime, appUrl, prefs, setPref, slug } from "./core.js";
import { sec, sq, toggle } from "./components.js";
import { openSheet, sheetHead, getSheet, openMenu, confirmBox, infoBox } from "./sheet.js";
import { toast, toastError, haptic } from "./fx.js";

const MIN = 60000;

// ---------- Kleine Bausteine ----------
// Schlichte Anbieter-Symbole (keine Logo-Kopien): farbiger Kreis mit „G“ bzw. vier neutrale Quadrate
export function glyph(provider, cls = "") {
  if (provider === "google")
    return `<span class="pglyph google${cls ? " " + cls : ""}" aria-hidden="true"><svg viewBox="0 0 24 24" focusable="false"><path d="M16.1 8.5a5.4 5.4 0 1 0 1.3 3.5h-4.9" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/></svg></span>`;
  if (provider === "microsoft")
    return `<span class="pglyph microsoft${cls ? " " + cls : ""}" aria-hidden="true"><svg viewBox="0 0 24 24" focusable="false"><rect x="4" y="4" width="7.3" height="7.3" rx="1.4" fill="currentColor" opacity=".92"/><rect x="12.7" y="4" width="7.3" height="7.3" rx="1.4" fill="currentColor" opacity=".62"/><rect x="4" y="12.7" width="7.3" height="7.3" rx="1.4" fill="currentColor" opacity=".48"/><rect x="12.7" y="12.7" width="7.3" height="7.3" rx="1.4" fill="currentColor" opacity=".78"/></svg></span>`;
  return `<span class="pglyph${cls ? " " + cls : ""}" aria-hidden="true">${icon("person")}</span>`;
}

const accOf = (id) => store.account(id);
const accVars = (a) => colorVars(a?.color || "blue");
const evVars = (e) => accVars(accOf(e.account));

// Externe Adresse in neuem Fenster/Tab (innerhalb des Tipps – kein Pop-up-Blocker)
export function openExternal(url) {
  const u = String(url || "");
  if (/^(mailto|tel):/i.test(u)) {
    location.href = u;
    return;
  }
  const s = safeUrl(u);
  if (!s || !/^https?:/i.test(s)) return;
  // echter Link-Klick statt window.open(…, "noopener") – der liefert immer null und ließe sich nicht prüfen
  const a = document.createElement("a");
  a.href = s;
  a.target = "_blank";
  a.rel = "noopener noreferrer";
  a.hidden = true;
  document.body.append(a);
  a.click();
  a.remove();
}

const extLink = (url, cls, inner, label = "") => {
  const s = safeUrl(url);
  return s ? `<a class="${cls}" href="${esc(s)}" target="_blank" rel="noopener noreferrer"${label ? ` aria-label="${esc(label)}"` : ""}>${inner}</a>` : "";
};

const fmtT = (ms) => {
  const d = new Date(ms);
  return `${d.getHours()}:${String(d.getMinutes()).padStart(2, "0")}`;
};
const evEnded = (e, now = Date.now()) => e.end <= now;
const evLive = (e, now = Date.now()) => !e.allDay && e.start - 10 * MIN <= now && now < e.end;

// Zeit-Spalte: „9:00 / 10:00“, „ganztägig“, bei mehrtägigen „bis 11:00“
function whenParts(e, iso) {
  if (e.allDay) return { a: "ganztägig", b: "" };

  if (e.date !== iso) return { a: "bis", b: fmtT(e.end) };
  return { a: fmtT(e.start), b: dates.toISO(e.end) === iso ? fmtT(e.end) : "" };
}

function evMeta(e, { cal = true } = {}) {
  const a = accOf(e.account);
  const kind = e.join ? connect.joinKind(e.join) : "";
  const m = [];
  if (kind) m.push(`<span class="m">${icon("video")}${esc(kind)}</span>`);
  if (e.location && !(kind && /teams|zoom|meet|webex|http/i.test(e.location))) m.push(`<span class="m">${icon("location")}<span class="mt">${esc(e.location)}</span></span>`);
  if (cal) m.push(`<span class="m evcal" title="${esc(a?.email || "")}"><i class="bdot"></i><span class="mt">${esc(calLabel(e))}</span></span>`);
  return m.join("");
}

// Kalendername kurz: „Familie“, sonst „Google“ bzw. „Outlook“
const calLabel = (e) => (e.calendar && !/^(kalender|outlook|calendar)$/i.test(e.calendar) && !e.calendar.includes("@") ? e.calendar : e.provider === "google" ? "Google" : "Outlook");

// Terminzeile (Heute: mit Aktionen; Demnächst: kompakt – Antippen öffnet die Details)
export function eventRow(e, { iso = today(), acts = false, now = Date.now() } = {}) {
  const w = whenParts(e, iso);
  const ended = evEnded(e, now);
  const live = evLive(e, now);
  const tid = connect.takenTask(e.id);
  const k = e.id.length > 60 ? e.id.slice(-60) : e.id;
  const tel = acts && !e.join ? connect.phoneList(`${e.location}\n${e.notes || ""}`)[0] || null : null;
  const join = e.join && !ended && (acts || e.date === today() || live) ? extLink(e.join, `ev-join${live ? " now" : ""}`, `${icon("video")}<span>Beitreten</span>`, `${connect.joinKind(e.join) || "Call"} beitreten: ${e.title}`) : "";
  const chips = acts && !ended
    ? `<div class="ev-acts">${tel ? `<a class="sg green" href="${esc(connect.telHref(tel.tel))}" aria-label="Anrufen: ${esc(tel.label)}">${icon("call")}<span>Anrufen</span></a>` : ""}${e.web ? extLink(e.web, `sg ghost${tel ? " icon-only" : ""}`, tel ? icon("arrowUpRight") : `${icon("arrowUpRight")}<span>Öffnen</span>`, `Im Kalender öffnen: ${e.title}`) : ""}${tid && store.task(tid) ? `<button type="button" class="sg green" data-act="task" data-id="${esc(tid)}">${icon("checkCircle")}<span>Aufgabe</span></button>` : `<button type="button" class="sg ghost" data-act="ev-task" data-id="${esc(e.id)}">${icon("plus")}<span>Als Aufgabe</span></button>`}</div>`
    : "";
  return `<div class="ev${ended ? " past" : ""}${live ? " live" : ""}${e.allDay ? " allday" : ""}${acts ? " with-acts" : ""}" data-key="ev-${esc(k)}" style="${evVars(e)}">
<button type="button" class="ev-in" data-act="ev-open" data-id="${esc(e.id)}"><span class="ev-when"><b>${esc(w.a)}</b>${w.b ? `<small>${esc(w.b)}</small>` : ""}</span><span class="ev-bar" aria-hidden="true"></span><span class="ev-main"><span class="ev-title">${esc(e.title)}</span><span class="task-meta">${evMeta(e)}</span></span></button>${join}${chips}
</div>`;
}

// Zeitplan: Termin als eigene Art Eintrag (Kalender-Symbol statt Häkchen)
export function timelineEvent(e, now = Date.now()) {
  const ended = evEnded(e, now);
  const live = evLive(e, now);
  const kind = e.join ? connect.joinKind(e.join) : "";
  const k = e.id.length > 60 ? e.id.slice(-60) : e.id;
  const sub = [`bis ${fmtT(e.end)}`, kind ? `${kind}-Call` : "", e.location && !kind ? e.location : ""].filter(Boolean).join(" · ");
  return `<div class="tl-item tl-ev${ended ? " past" : ""}${live ? " live" : ""}" data-key="tl-ev-${esc(k)}" style="${evVars(e)}">
<time>${esc(fmtT(e.start))}</time><span class="tl-dot"></span>
<div class="tl-body"><span class="tl-evic" aria-hidden="true">${icon(kind ? "video" : "calendar")}</span><button type="button" class="tl-main" data-act="ev-open" data-id="${esc(e.id)}"><b>${esc(e.title)}</b><small>${esc(sub)}</small></button>${e.join && !ended ? extLink(e.join, `tl-join${live ? " now" : ""}`, `${icon("video")}<span class="tl-join-l">Beitreten</span>`, `Beitreten: ${e.title}`) : ""}</div>
</div>`;
}

// ---------- Heute ----------
export const todayEvents = (iso = today()) => safe(() => connect.eventsOn(iso), []);

export function eventsSection(iso = today(), now = Date.now()) {
  const accs = connect.accounts().filter((a) => a.calendars !== false);
  if (!accs.length) return "";
  const list = todayEvents(iso);
  const errs = connect.info().errors.filter((e) => e.expired);
  let body;
  if (list.length) body = list.map((e) => eventRow(e, { iso, acts: true, now })).join("");
  else {
    const next = safe(() => connect.events().find((e) => e.start >= now && e.date > iso), null);
    body = `<div class="ev-empty">${icon("calendarCheck")}<span><b>Heute keine Termine</b>${next ? `<small>Nächster: ${esc(safe(() => dates.relDay(next.date, app.now), next.date))}${next.allDay ? "" : `, ${esc(fmtT(next.start))}`} – ${esc(next.title)}</small>` : ""}</span></div>`;
  }
  if (errs.length) body += `<button type="button" class="ev-warn" data-act="go" data-to="#einstellungen/konten">${icon("info")}<span>${esc(errs[0].email || "Ein Konto")}: Verbindung abgelaufen – neu verbinden</span>${icon("chevronRight")}</button>`;
  const info = connect.info();
  return sec({
    key: "events",
    title: "Termine",
    icon: "calendar",
    tone: "red",
    count: list.length || "",
    note: info.busy ? `<span class="spinner xs"></span>` : "",
    actions: `<button type="button" class="btn-round sm ghost" data-act="cx-refresh" aria-label="Termine aktualisieren" title="Aktualisieren">${icon("refresh")}</button>`,
    body,
  });
}

// Hinweis auf Heute, solange noch kein Konto verbunden ist (nur wenn der Server es anbietet)
export function connectBanner() {
  const av = app.connectAvail;
  if (!av || !(av.google || av.microsoft) || connect.accounts().length || prefs.cxBanner === "hidden") return "";
  return `<section class="rcard cx" data-key="cx-banner"><span class="rcard-ic cx">${icon("calendar")}</span><div class="rcard-b"><h3>Kalender & Mails verbinden</h3><p>Termine und Calls aus Outlook oder Google hier sehen, markierte Mails als Aufgaben übernehmen.</p><div class="rcard-btns">${av.microsoft ? `<button type="button" class="btn sm prov" data-act="cx-connect" data-p="microsoft">${glyph("microsoft", "sm")}<span>Microsoft</span></button>` : ""}${av.google ? `<button type="button" class="btn sm prov" data-act="cx-connect" data-p="google">${glyph("google", "sm")}<span>Google</span></button>` : ""}</div></div><button type="button" class="rcard-x" data-act="cx-banner-hide" aria-label="Ausblenden">${icon("x")}</button></section>`;
}

// ---------- Demnächst ----------
export function stripDots(iso) {
  const evs = safe(() => connect.eventsOn(iso), []);
  const cols = [...new Set(evs.map((e) => accOf(e.account)?.color || "blue"))].slice(0, 2);
  return { n: evs.length, html: cols.map((c) => `<i class="wev" style="${colorVars(c)}"></i>`).join("") };
}

// ---------- Eingang: markierte Mails ----------
function mailSuggest(m) {
  const r = safe(() => pm.suggestBag(`${m.subject} ${m.from} ${m.snippet}`, store.get()), null);
  const b = r?.bag ? (typeof r.bag === "string" ? store.bag(r.bag) : store.bag(r.bag.id)) : null;
  return b || null;
}

function mailRow(m) {
  const a = accOf(m.account);
  const sg = mailSuggest(m);
  const initial = (m.from || m.fromEmail || "?").trim().charAt(0).toUpperCase();
  const k = m.id.length > 60 ? m.id.slice(-60) : m.id;
  return `<div class="mrow" data-key="m-${esc(k)}" style="${accVars(a)}">
<div class="mrow-in"><span class="mav" aria-hidden="true">${esc(initial)}${glyph(m.provider, "pbadge")}</span><div class="mmain"><div class="mtop"><b>${esc(m.from)}</b><time>${esc(relTime(m.date))}</time></div><span class="msubj">${esc(m.subject)}</span>${m.snippet ? `<span class="msnip">${esc(m.snippet)}</span>` : ""}</div></div>
<div class="in-sug m-acts">${sg ? `<button type="button" class="sg" data-act="mail-task" data-id="${esc(m.id)}" data-bag="${esc(sg.id)}" style="${colorVars(sg.color)}" aria-label="Als Aufgabe in ${esc(sg.name)}" title="Als Aufgabe in ${esc(sg.emoji)} ${esc(sg.name)}">${icon("plus")}<span>Als Aufgabe → ${esc(sg.emoji)}</span></button>` : `<button type="button" class="sg accent" data-act="mail-task" data-id="${esc(m.id)}">${icon("plus")}<span>Als Aufgabe</span></button>`}<button type="button" class="sg ghost icon-only" data-act="mail-pick" data-id="${esc(m.id)}" aria-label="Als Aufgabe in eine Tasche …" title="In Tasche …">${icon("bag")}</button>${m.web ? extLink(m.web, "sg ghost icon-only", icon("arrowUpRight"), `Mail öffnen: ${m.subject}`) : ""}<button type="button" class="sg ghost icon-only" data-act="mail-hide" data-id="${esc(m.id)}" aria-label="Ausblenden" title="Ausblenden">${icon("x")}</button></div>
</div>`;
}

export function mailsSection() {
  const accs = connect.accounts().filter((a) => a.mail !== false);
  if (!accs.length) return "";
  const list = safe(() => connect.mails(), []);
  const hasG = accs.some((a) => a.provider === "google"), hasM = accs.some((a) => a.provider === "microsoft");
  const how = hasG && hasM ? "Gmail: Stern · Outlook: Fahne" : hasG ? "In Gmail mit Stern markiert" : "In Outlook mit Fahne markiert";
  const body = list.length ? list.map(mailRow).join("") : `<div class="ev-empty">${icon("mail")}<span><b>Keine markierten Mails</b><small>${esc(how)} – dann erscheinen sie hier.</small></span></div>`;
  return sec({ key: "mails", title: "Markierte Mails", icon: "mail", tone: "blue", count: list.length || "", body }) + (list.length ? `<p class="fine m-hint" data-key="m-hint">${esc(how)} · Ausblenden ändert nichts im Postfach.</p>` : "");
}

// ---------- Aufgaben-Detail: Anrufen, Kalender, E-Mail ----------
export function taskActions(t) {
  const nums = connect.phoneList(`${t.title}\n${t.notes || ""}\n${t.waiting || ""}`);
  const to = recipient(t);
  const cal = Array.isArray(t.cal) ? t.cal.filter((c) => c && c.account) : [];
  const calAcc = cal.map((c) => accOf(c.account)).filter(Boolean)[0];
  const calSub = !t.due ? "Erst ein Datum wählen" : cal.length ? `✓ eingetragen${calAcc ? ` in ${esc(calAcc.email)}` : ""}` : connect.accounts().some((a) => a.secret && !a.broken && a.calendars !== false) ? "direkt in deinen Kalender" : "Google, Outlook oder Kalender-Datei";
  const src = t.src && typeof t.src === "object" ? t.src : null;
  const rows = [];
  for (const p of nums) rows.push(`<a class="frow btnrow call" href="${esc(connect.telHref(p.tel))}" data-key="call-${esc(p.tel)}">${sq("call", "green")}<span class="frow-l">Anrufen<small>${esc(p.label)}</small></span><span class="frow-c">${icon("chevronRight")}</span></a>`);
  if (src?.join) rows.push(extLink(src.join, "frow btnrow", `${sq("video", "teal")}<span class="frow-l">Beitreten<small>${esc(connect.joinKind(src.join) || "Online-Meeting")}</small></span><span class="frow-c">${icon("arrowUpRight")}</span>`));
  rows.push(`<button type="button" class="frow btnrow${t.due ? "" : " soft"}" data-act="cx-cal" data-id="${t.id}">${sq("calendarPlus", "red")}<span class="frow-l">In Kalender eintragen<small>${calSub}</small></span><span class="frow-c">${icon("chevronRight")}</span></button>`);
  rows.push(`<button type="button" class="frow btnrow" data-act="cx-mail" data-id="${t.id}">${sq("mail", "blue")}<span class="frow-l">E-Mail schreiben<small>${to ? `an ${esc(to)}` : "Gmail, Outlook oder Mail-App"}</small></span><span class="frow-c">${icon("chevronRight")}</span></button>`);
  if (src?.web) rows.push(extLink(src.web, "frow btnrow", `${sq(src.kind === "mail" ? "mail" : "calendar", "gray")}<span class="frow-l">${src.kind === "mail" ? "Original-Mail öffnen" : "Termin im Kalender öffnen"}</span><span class="frow-c">${icon("arrowUpRight")}</span>`));
  return `<section class="td-block" data-key="td-cx"><h3 class="td-h">Kontakt & Kalender</h3><div class="card form">${rows.join("")}</div></section>`;
}

function recipient(t) {
  if (t.src?.kind === "mail" && t.src.email) return String(t.src.email);
  return connect.emails(`${t.notes || ""} ${t.waiting || ""} ${t.title}`)[0] || "";
}

function calendarMenu(id, el) {
  const t = store.task(id);
  if (!t) return;
  if (!t.due) {
    toast("Erst ein Datum wählen", { icon: "calendar", sub: "Dann kommt die Aufgabe in deinen Kalender" });
    return;
  }
  const p = store.get().profile;
  const accs = connect.accounts().filter((a) => a.secret && !a.broken && a.calendars !== false);
  const links = connect.calendarLinks(t, p, { appUrl: appUrl() });
  const items = accs.map((a) => ({ label: a.email || connect.providerName(a.provider), hint: `${connect.providerInfo(a.provider)?.calendar} · direkt eintragen`, icon: "calendarPlus", run: () => addToCalendar(a.id, id) }));
  if (items.length) items.push("-");
  items.push(
    { label: "Google Kalender", hint: "im Browser eintragen", icon: "arrowUpRight", run: () => openExternal(links.google) },
    { label: "Outlook.com", hint: "privates Microsoft-Konto", icon: "arrowUpRight", run: () => openExternal(links.outlook) },
    { label: "Microsoft 365", hint: "Firmen-Outlook im Browser", icon: "arrowUpRight", run: () => openExternal(links.office365) },
    { label: "Kalender-Datei (.ics)", hint: "Apple Kalender, Outlook am Mac …", icon: "download", run: () => icsFor(id) },
  );
  openMenu(items, { el, title: "In Kalender eintragen" });
}

async function addToCalendar(accId, taskId) {
  const a = accOf(accId);
  const t = store.task(taskId);
  if (!a || !t) return;
  toast("Wird eingetragen …", { icon: "calendarPlus", ms: 2500, sub: a.email });
  try {
    const r = await connect.createEvent(a, t, store.get().profile, { appUrl: appUrl() });
    const cur = store.task(taskId);
    if (cur) store.updateTask(taskId, { cal: [...(Array.isArray(cur.cal) ? cur.cal : []).filter((c) => c && c.account !== a.id), { account: a.id, provider: a.provider, web: r.web || "", at: Date.now() }] });
    haptic();
    toast(`In ${connect.providerInfo(a.provider)?.calendar || "den Kalender"} eingetragen`, { icon: "calendarCheck", sub: a.email, action: r.web ? { label: "Öffnen", fn: () => openExternal(r.web) } : null });
  } catch (e) {
    toastError(e, "Kalender");
  }
}

function icsFor(id) {
  const t = store.task(id);
  if (!t || !t.due) return;
  try {
    const bagsById = Object.fromEntries(store.bags().map((b) => [b.id, b]));
    const ics = remind.icsForTasks([t], { bagsById, profile: store.get().profile, calName: "Arbeitstaschen", appUrl: appUrl() });
    remind
      .deliverFile(`${slug(t.title)}.ics`, "text/calendar", ics)
      .then((how) => how === "downloaded" && toast("Kalender-Datei geladen", { icon: "calendarCheck", sub: "Öffnen → „Hinzufügen“" }))
      .catch((e) => toastError(e));
  } catch (e) {
    toastError(e);
  }
}

function mailMenu(id, el) {
  const t = store.task(id);
  if (!t) return;
  const to = recipient(t);
  const subject = t.title;
  const accs = connect.accounts().filter((a) => a.secret);
  const g = accs.filter((a) => a.provider === "google");
  const m = accs.filter((a) => a.provider === "microsoft");
  const items = [];
  for (const a of g) items.push({ label: "Gmail", hint: a.email, icon: "mail", run: () => openExternal(connect.composeLinks({ to, subject, from: a.email }).gmail) });
  for (const a of m) {
    const personal = connect.msPersonal(a.email);
    items.push({ label: personal ? "Outlook.com" : "Outlook (Microsoft 365)", hint: a.email, icon: "mail", run: () => openExternal(connect.composeLinks({ to, subject })[personal ? "outlook" : "office365"]) });
  }
  if (!g.length) items.push({ label: "Gmail", hint: "im Browser", icon: "arrowUpRight", run: () => openExternal(connect.composeLinks({ to, subject }).gmail) });
  if (!m.length) {
    items.push({ label: "Outlook.com", hint: "privat, im Browser", icon: "arrowUpRight", run: () => openExternal(connect.composeLinks({ to, subject }).outlook) });
    items.push({ label: "Microsoft 365", hint: "Firmen-Outlook im Browser", icon: "arrowUpRight", run: () => openExternal(connect.composeLinks({ to, subject }).office365) });
  }
  items.push("-", { label: "Mail-App", hint: "Apple Mail, Outlook-App …", icon: "share", run: () => openExternal(connect.composeLinks({ to, subject }).mailto) });
  openMenu(items, { el, title: to ? `E-Mail an ${to}` : "E-Mail schreiben" });
}

// ---------- Termin-Details ----------
let openEv = null;
export function openEvent(id) {
  if (!connect.event(id)) return;
  openEv = id;
  if (getSheet("event")) return getSheet("event").refresh();
  openSheet({ key: "event", label: "Termin", render: eventView, onClose: () => (openEv = null) });
}

function eventView() {
  const e = openEv ? connect.event(openEv) : null;
  if (!e) return `${sheetHead("Termin")}<div class="sheet-pad"><p class="muted">Diesen Termin gibt es nicht mehr.</p></div>`;
  const a = accOf(e.account);
  const now = Date.now();
  const day = safe(() => dates.fmtDay(e.date), e.date);
  const lastDay = dates.toISO(e.end - 1);
  const when = e.allDay ? (lastDay > e.date ? `${day} – ${safe(() => dates.fmtDay(lastDay), lastDay)} · ganztägig` : `${day} · ganztägig`) : `${day} · ${fmtT(e.start)}–${fmtT(e.end)} Uhr`;
  const kind = e.join ? connect.joinKind(e.join) : "";
  const nums = connect.phoneList(`${e.location}\n${e.notes}`);
  const tid = connect.takenTask(e.id);
  const rows = [];
  rows.push(`<div class="frow">${glyph(e.provider)}<span class="frow-l">${esc(e.calendar || "Kalender")}<small>${esc(a?.email || connect.providerName(e.provider))}</small></span></div>`);
  if (e.location) {
    const placeLike = !/https?:|teams|zoom|webex|meet\b|^(telefon\w*|online|virtuell|anruf)$/i.test(e.location.trim()) && (/\d|,/.test(e.location) || e.location.trim().split(/\s+/).length >= 2);
    rows.push(placeLike ? extLink(`https://maps.apple.com/?q=${encodeURIComponent(e.location)}`, "frow btnrow", `${sq("location", "red")}<span class="frow-l">${esc(e.location)}<small>In Karten öffnen</small></span><span class="frow-c">${icon("arrowUpRight")}</span>`) : `<div class="frow">${sq("location", "gray")}<span class="frow-l">${esc(e.location)}</span></div>`);
  }
  for (const p of nums) rows.push(`<a class="frow btnrow call" href="${esc(connect.telHref(p.tel))}">${sq("call", "green")}<span class="frow-l">Anrufen<small>${esc(p.label)}</small></span><span class="frow-c">${icon("chevronRight")}</span></a>`);
  if (e.notes) rows.push(`<div class="frow col evd-notes">${sq("note", "gray")}<span class="frow-l">Notizen</span><p class="evd-text">${esc(e.notes)}</p></div>`);
  return `${sheetHead("Termin")}
<div class="sheet-pad evd" style="${evVars(e)}">
<div class="evd-head"><span class="evd-bar" aria-hidden="true"></span><div class="evd-t"><h2>${esc(e.title)}</h2><p>${esc(when)}</p>${evLive(e, now) ? `<span class="evd-live">läuft gerade</span>` : evEnded(e, now) ? `<span class="evd-past">vorbei</span>` : ""}</div></div>
${e.join && !evEnded(e, now) ? extLink(e.join, "btn primary wide evd-join", `${icon("video")}<span>${esc(kind && kind !== "Video" ? kind + " beitreten" : "Beitreten")}</span>`) : ""}
<div class="card form evd-rows">${rows.join("")}</div>
<div class="td-actions evd-acts">
${e.web ? extLink(e.web, "act", `${icon("arrowUpRight")}<span>Im Kalender</span>`) : ""}
${tid && store.task(tid) ? `<button type="button" class="act" data-act="ev-taskopen" data-id="${esc(tid)}">${icon("checkCircle")}<span>Aufgabe öffnen</span></button>` : `<button type="button" class="act" data-act="ev-task" data-id="${esc(e.id)}">${icon("plus")}<span>Als Aufgabe</span></button>`}
</div>
</div>`;
}

// ---------- Einstellungen: Konten & Kalender ----------
const ui = { status: null, checking: false, server: "" };

export async function checkAvail(force = false) {
  const srv = app.server;
  if (!srv) {
    ui.status = { google: false, microsoft: false, server: "", ok: false };
    app.connectAvail = ui.status;
    return ui.status;
  }
  if (ui.checking || (!force && ui.status && ui.server === srv)) return ui.status;
  ui.checking = true;
  try {
    ui.status = await connect.status(srv);
  } catch (_) {
    ui.status = { google: false, microsoft: false, server: "", ok: false };
  }
  ui.server = srv;
  ui.checking = false;
  app.connectAvail = ui.status;
  app.render();
  return ui.status;
}

export function settingsGroup() {
  if (app.server && ui.server !== app.server && !ui.checking) setTimeout(() => checkAvail(), 0);
  const st = app.server ? ui.status : { google: false, microsoft: false };
  const accs = connect.accounts();
  const info = connect.info();
  const rows = [];
  for (const a of accs) {
    const s = connect.accountState(a.id) || { kind: "ok" };
    const what = [a.calendars !== false ? "Termine" : "", a.mail !== false ? (a.provider === "google" ? "markierte Mails" : "markierte Mails") : ""].filter(Boolean).join(" & ") || "nichts eingeblendet";
    const sub = s.kind === "expired" ? `<span class="red">Abgelaufen – zum Neu-Verbinden antippen</span>` : s.kind === "error" ? `<span class="orange">${esc(s.msg)}</span>` : `${esc(connect.providerName(a.provider))} · ${esc(what)}`;
    const right = s.kind === "expired" ? `<i class="acc-dot warn"></i>` : `<i class="acc-dot" style="${accVars(a)}"></i>`;
    rows.push(`<button type="button" class="frow btnrow acc" data-act="cx-acc" data-id="${esc(a.id)}" data-key="acc-${esc(a.id)}">${glyph(a.provider)}<span class="frow-l"><span class="acc-mail">${esc(a.email || connect.providerName(a.provider))}</span><small>${sub}</small></span><span class="frow-c">${right}${icon("chevronRight")}</span></button>`);
  }
  if (!accs.length) rows.push(`<div class="frow cx-intro">${sq("calendar", "red")}<span class="frow-l">Termine, Calls und markierte Mails<small>Outlook, Microsoft 365, Gmail und Google Kalender – direkt in Heute, Demnächst und im Eingang.</small></span></div>`);
  const provBtn = (p) => {
    const off = st ? !st[p.id] : !app.server;
    const more = accs.some((a) => a.provider === p.id);
    return `<button type="button" class="prov-btn${off ? " off" : ""}${accs.length ? " compact" : ""}" data-act="cx-connect" data-p="${p.id}"${off ? ` data-off="1"` : ""}>${glyph(p.id)}<span class="prov-t"><b>${more ? `Weiteres ${esc(p.name)}-Konto` : `Mit ${esc(p.name)} verbinden`}</b>${accs.length ? "" : `<small>${esc(p.sub)}</small>`}</span>${off ? icon("info") : icon(accs.length ? "plus" : "chevronRight")}</button>`;
  };
  const provs = connect.providers();
  rows.push(`<div class="frow col prov-row"><div class="prov-grid">${provs.filter((p) => p.id === "microsoft").concat(provs.filter((p) => p.id === "google")).map(provBtn).join("")}</div>${!app.server ? `<p class="fine prov-note">${icon("info")} Dafür braucht es den Arbeitstaschen-Server – siehe Anleitung unten. Ohne Server gehen trotzdem: Termine per Link in Google/Outlook eintragen, E-Mails schreiben und Anrufen.</p>` : st && !st.google && !st.microsoft && ui.status ? `<p class="fine prov-note">${icon("info")} Dein Server ist noch nicht für Google/Microsoft eingerichtet – siehe Anleitung unten.</p>` : ""}</div>`);
  if (accs.length) {
    const anyCal = accs.some((a) => a.calendars !== false), anyMail = accs.some((a) => a.mail !== false);
    rows.push(`<div class="frow">${sq("calendar", "red")}<span class="frow-l">Termine anzeigen<small>in Heute, Demnächst und als Erinnerung</small></span><span class="frow-c">${toggle(anyCal, `data-change="cx-all" data-f="calendars"`, "Termine anzeigen")}</span></div>`);
    rows.push(`<div class="frow">${sq("flag", "orange")}<span class="frow-l">Markierte Mails im Eingang<small>Gmail: Stern · Outlook: Fahne</small></span><span class="frow-c">${toggle(anyMail, `data-change="cx-all" data-f="mail"`, "Markierte Mails im Eingang")}</span></div>`);
    const nE = connect.events().length, nM = connect.mails({ all: true }).length;
    rows.push(`<button type="button" class="frow btnrow" data-act="cx-refresh" data-all="1"${info.busy ? " disabled" : ""}>${sq("refresh", "blue")}<span class="frow-l">Jetzt aktualisieren<small>${info.at ? `zuletzt ${esc(relTime(info.at))} · ${nE} ${nE === 1 ? "Termin" : "Termine"} · ${nM} ${nM === 1 ? "Mail" : "Mails"}` : "noch nicht geladen"}</small></span><span class="frow-c">${info.busy ? `<span class="spinner xs"></span>` : icon("chevronRight")}</span></button>`);
  }
  const needGuide = !app.server || (ui.status && (!ui.status.google || !ui.status.microsoft));
  if (needGuide) rows.push(`<div class="frow col guide${prefs.cxGuide ? " open" : ""}"><button type="button" class="guide-t" data-act="cx-guide">${sq("wand", "purple")}<span class="frow-l">Anleitung: Server einrichten<small>einmalig, ca. 15 Minuten – danach verbindest du hier mit einem Tipp</small></span>${icon(prefs.cxGuide ? "chevronUp" : "chevronDown")}</button>${
    prefs.cxGuide
      ? `<ol class="guide-steps">
<li>Den <b>Arbeitstaschen-Server</b> installieren (siehe <code>server/install.sh</code>) – er läuft z. B. unter <code>https://taschen.…sslip.io</code>. Unter „Sync“ seine Adresse eintragen.</li>
<li><b>Microsoft:</b> Im Microsoft-Entra-Admin-Center (früher Azure-Portal) unter „App-Registrierungen“ eine App anlegen (Konten in allen Organisationen <i>und</i> private Microsoft-Konten), Umleitungs-URI <code>…/api/connect/microsoft/callback</code>, einen geheimen Clientschlüssel erzeugen.</li>
<li><b>Google:</b> In der Google Cloud Console einen OAuth-Client (Webanwendung) anlegen, Weiterleitungs-URI <code>…/api/connect/google/callback</code>, Kalender- und Gmail-API aktivieren.</li>
<li>Die Zugangsdaten fragt <code>install.sh</code> ab (oder du setzt sie als <code>MS_CLIENT_ID</code>, <code>MS_CLIENT_SECRET</code>, <code>GOOGLE_CLIENT_ID</code>, <code>GOOGLE_CLIENT_SECRET</code>). Fertig – oben auf „Verbinden“ tippen.</li>
</ol>`
      : ""
  }</div>`);
  const ios = safe(() => remind.env().ios, false);
  const foot = `${icon("shield")} <b>Privat:</b> Termine und Mails gehen direkt von Google bzw. Microsoft auf dein Gerät – der Server vermittelt nur die Anmeldung. Firmenkonto gesperrt? Dann muss die IT die App einmal freigeben.${ios && !accs.length ? " Tipp: Am besten einmal am Mac oder in Safari verbinden – über den Sync ist das Konto dann überall da." : ""}`;
  return `<section class="set" id="set-konten" data-key="set-konten"><h3 class="set-h">Konten & Kalender</h3><div class="card form">${rows.join("")}</div><p class="set-foot">${foot}</p></section>`;
}

function accountMenu(id, el) {
  const a = accOf(id);
  if (!a) return;
  const s = connect.accountState(id) || { kind: "ok" };
  const items = [];
  if (s.kind !== "ok") items.push({ label: s.kind === "expired" ? "Neu verbinden" : "Erneut versuchen", hint: s.msg, icon: "refresh", run: () => (s.kind === "expired" ? connectNow(a.provider) : connect.refresh(store, { force: true, retryBroken: true }).catch((e) => toastError(e))) });
  items.push(
    { label: "Termine anzeigen", check: a.calendars !== false, run: () => store.updateAccount(id, { calendars: a.calendars === false }) },
    { label: a.provider === "google" ? "Markierte Mails (Stern)" : "Markierte Mails (Fahne)", check: a.mail !== false, run: () => store.updateAccount(id, { mail: a.mail === false }) },
    "-",
    { label: "Trennen", icon: "trash", danger: true, run: () => disconnectAcc(id) },
  );
  openMenu(items, { el, title: a.email || connect.providerName(a.provider) });
}

async function disconnectAcc(id) {
  const a = accOf(id);
  if (!a) return;
  if (!(await confirmBox({ title: `${connect.providerName(a.provider)} trennen?`, text: `${a.email}: Termine und Mails verschwinden aus Arbeitstaschen – auf allen Geräten. In deinem Postfach und Kalender bleibt alles, wie es ist.`, ok: "Trennen", danger: true }))) return;
  const r = await connect.disconnect(id);
  toast("Konto getrennt", { icon: "checkCircle", sub: r.remote ? a.email : "Der Server war nicht erreichbar – der Zugang verfällt dort von selbst." });
}

async function connectNow(provider) {
  const st = app.server ? (ui.status && ui.server === app.server ? ui.status : await checkAvail(true)) : null;
  if (!st || !st[provider]) {
    infoBox({
      title: app.server ? "Noch nicht eingerichtet" : "Dafür braucht es den Server",
      text: app.server
        ? `Dein Arbeitstaschen-Server kennt noch keine Zugangsdaten für ${connect.providerName(provider)}. Wie das geht, steht in der Anleitung unter „Konten & Kalender“ – danach klappt das Verbinden mit einem Tipp.`
        : `Die Anmeldung bei ${connect.providerName(provider)} läuft über deinen eigenen Arbeitstaschen-Server (er bewahrt den Zugang verschlüsselt auf). Ohne Server gehen trotzdem: Aufgaben per Link in Google/Outlook eintragen, E-Mails schreiben und Anrufen – direkt an jeder Aufgabe.`,
    });
    if (!prefs.cxGuide) {
      setPref("cxGuide", true);
      app.render();
    }
    return;
  }
  try {
    toast(`Weiter zu ${connect.providerName(provider)} …`, { icon: "arrowUpRight", ms: 4000 });
    connect.startConnect(provider, app.server, { back: app.route.view === "einstellungen" ? "#einstellungen/konten" : `#${app.route.view || "heute"}` });
  } catch (e) {
    toastError(e);
  }
}

// ---------- Ereignisse ----------
async function taskFromEventId(id) {
  const e = connect.event(id);
  if (!e) return;
  const tid = connect.takenTask(id);
  if (tid && store.task(tid)) return (await import("./task.js")).openTask(tid);
  try {
    const t = store.addTask(connect.taskFromEvent(e));
    connect.markTaken(e.id, t.id);
    haptic();
    toast("Als Aufgabe übernommen", { icon: "checkCircle", sub: e.title, action: { label: "Öffnen", fn: () => import("./task.js").then((m) => m.openTask(t.id)) } });
  } catch (err) {
    toastError(err);
  }
}

function taskFromMailId(id, bagId = null) {
  const m = connect.mail(id);
  if (!m) return;
  try {
    const t = store.addTask({ ...connect.taskFromMail(m), bag: bagId && store.bag(bagId) ? bagId : null });
    connect.markTaken(m.id, t.id);
    haptic();
    const b = t.bag ? store.bag(t.bag) : null;
    toast(b ? `→ ${b.emoji} ${b.name}` : "Als Aufgabe im Eingang", {
      icon: "checkCircle",
      sub: t.title,
      action: {
        label: "Rückgängig",
        fn: () => {
          store.removeTask(t.id);
          connect.markTaken(m.id, false);
          toast("Rückgängig gemacht", { icon: "undo" });
        },
      },
    });
  } catch (err) {
    toastError(err);
  }
}

on("click", {
  "ev-open": (el) => openEvent(el.dataset.id),
  "ev-task": (el) => taskFromEventId(el.dataset.id),
  "ev-taskopen": (el) => {
    getSheet("event")?.close();
    import("./task.js").then((m) => m.openTask(el.dataset.id));
  },
  "mail-task": (el) => taskFromMailId(el.dataset.id, el.dataset.bag || null),
  "mail-pick": (el) => {
    const id = el.dataset.id;
    openMenu([{ label: "Eingang", emoji: "📥", run: () => taskFromMailId(id, null) }, ...store.bags().map((b) => ({ label: b.name, emoji: b.emoji, run: () => taskFromMailId(id, b.id) }))], { el, title: "Als Aufgabe in …" });
  },
  "mail-hide": (el) => {
    const id = el.dataset.id;
    connect.markTaken(id, true);
    toast("Ausgeblendet", { icon: "eye", sub: "Die Markierung im Postfach bleibt", action: { label: "Rückgängig", fn: () => connect.markTaken(id, false) } });
  },
  "cx-refresh": (el) => {
    connect
      .refresh(store, { force: true, retryBroken: el.dataset.all === "1" })
      .then((r) => {
        const errs = (r?.errors || []).filter((e) => !e.network);
        if (el.dataset.all === "1" || errs.length) toast(errs.length ? "Nicht alles geladen" : "Aktualisiert", { icon: errs.length ? "info" : "refresh", tone: errs.length ? "red" : "", sub: errs.length ? errs[0].msg : `${r.events.length} Termine · ${r.mails.length} Mails` });
      })
      .catch((e) => toastError(e));
    app.render();
  },
  "cx-connect": (el) => connectNow(el.dataset.p),
  "cx-acc": (el) => accountMenu(el.dataset.id, el),
  "cx-guide": () => {
    setPref("cxGuide", !prefs.cxGuide);
    app.render();
  },
  "cx-banner-hide": () => {
    setPref("cxBanner", "hidden");
    app.render();
  },
  "cx-cal": (el) => calendarMenu(el.dataset.id, el),
  "cx-mail": (el) => mailMenu(el.dataset.id, el),
});

on("change", {
  "cx-all": (el) => {
    const f = el.dataset.f;
    for (const a of connect.accounts()) if ((a[f] !== false) !== el.checked) store.updateAccount(a.id, { [f]: el.checked });
    haptic();
  },
});
