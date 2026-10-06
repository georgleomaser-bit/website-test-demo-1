// Arbeitstaschen – „Verbindungen“: eine Seite für alles (Kalender, E-Mail, Nachrichten & Anrufe, Automatisierung, Daten),
// Sheets (Kalender-Link, IMAP-Postfach, ausgehender Webhook, CSV-Import), die Kontakt-Leiste im Aufgaben-Detail
// (Anrufen · WhatsApp · SMS · FaceTime · Teams · Karten · Teilen) und die Karte „Mit allem verbinden“ im leeren Heute.
import * as store from "../store.js";
import * as dates from "../dates.js";
import * as remind from "../remind.js";
import * as connect from "../connect.js";
import * as I from "../integrations.js";
import { COLOR_NAMES } from "../config.js";
import { esc } from "../util.js";
import { icon, logo } from "./icons.js";
import { app, on, safe, prefs, setPref, colorVars, relTime, today } from "./core.js";
import { sq, toggle, largeTitle } from "./components.js";
import { openSheet, sheetHead, getSheet, openMenu, confirmBox, infoBox, promptBox } from "./sheet.js";
import { toast, toastError, toastUndo, haptic, sound } from "./fx.js";
import { glyph, openExternal, availState, checkAvail, flagHint } from "./connectui.js";

const ACC_COLORS = ["red", "orange", "green", "teal", "blue", "indigo", "purple", "pink", "brown"];

// ---------- Kleine Helfer ----------
const ext = (url, cls, inner, label = "") => {
  const s = I.safeLink(url);
  if (!s) return "";
  const web = /^https?:/i.test(s);
  return `<a class="${cls}" href="${esc(s)}"${web ? ` target="_blank" rel="noopener noreferrer"` : ""}${label ? ` aria-label="${esc(label)}"` : ""}>${inner}</a>`;
};
const n = (k, one, many) => `${k} ${k === 1 ? one : many}`;
const srv = () => app.server || "";
const avail = () => availState();
// Funktion auf dem Server verfügbar? null = wird geprüft
function can(feature) {
  if (!srv()) return false;
  const a = avail();
  return a ? !!a[feature] : null;
}
const FEATURE = {
  feeds: { title: "Kalender-Links", what: "Fremde Kalender (iCloud, Google, Outlook …) lassen Browser nicht direkt laden – dein Arbeitstaschen-Server holt sie und reicht sie verschlüsselt weiter." },
  imap: { title: "E-Mail per IMAP", what: "Die Anmeldung bei GMX, WEB.DE & Co. läuft über deinen Arbeitstaschen-Server – er bewahrt den Zugang verschlüsselt auf und liest nur markierte Mails." },
  inbox: { title: "Eingangs-Adresse", what: "Siri, Zapier & Co. brauchen eine Adresse im Internet, an die sie neue Aufgaben schicken können – die stellt dein Arbeitstaschen-Server bereit." },
};
function offInfo(feature) {
  const f = FEATURE[feature];
  const has = !!srv();
  const a = avail();
  if (has && a && !a.ok) {
    checkAvail(true).catch(() => {});
    return infoBox({ title: "Server nicht erreichbar", text: `${f.title}: Dein Arbeitstaschen-Server antwortet gerade nicht. Prüf die Internetverbindung oder versuch es gleich noch einmal.` });
  }
  infoBox({
    title: has ? "Dein Server kann das noch nicht" : "Dafür braucht es den Server",
    text: has ? `${f.title}: Dein Arbeitstaschen-Server ist älter oder hat die Funktion ausgeschaltet. Mit „taschen-update“ auf dem Server holst du die neueste Version.` : `${f.what} Trag deinen Server unter Einstellungen → „Sync auf allen Geräten“ ein. Alles andere hier (Nachrichten & Anrufe, Excel/CSV, Kalender-Eintrag per Link) geht auch ohne.`,
  });
}
function copyText(text, what = "Kopiert") {
  const done = () => toast(what, { icon: "copy" });
  try {
    if (navigator.clipboard?.writeText) return navigator.clipboard.writeText(text).then(done, () => toast("Kopieren nicht möglich", { icon: "info", sub: text.slice(0, 80) }));
  } catch (_) {
    /* unten */
  }
  toast("Kopieren nicht möglich", { icon: "info", sub: text.slice(0, 80) });
  return Promise.resolve();
}
const nextColor = (provider) => {
  const used = new Set(store.accounts().filter((a) => a.provider === provider).map((a) => a.color));
  return ACC_COLORS.find((c) => !used.has(c)) || "blue";
};
const guideOpen = (k) => !!(prefs.ixGuides || {})[k];
function guideToggle(k) {
  setPref("ixGuides", { ...(prefs.ixGuides || {}), [k]: !guideOpen(k) });
  app.render();
}

// =====================================================================================================================
// Seite „Verbindungen“
// =====================================================================================================================
export const isPage = (r) => r?.view === "einstellungen" && (r.id === "verbindungen" || r.id === "konten");

// Zähler für den Einstieg in den Einstellungen und die Kopfzeile
export function activeCount() {
  return safe(() => store.accounts().filter((a) => ["google", "microsoft", "ics", "imap", "hook-in", "hook-out"].includes(a.provider)).length, 0);
}

let checkedFor = null;
export function renderPage(r) {
  if (srv() && checkedFor !== srv()) {
    checkedFor = srv();
    setTimeout(() => checkAvail(true).catch(() => {}), 0);
  }
  const accs = store.accounts();
  const active = activeCount();
  const a = avail();
  let h = largeTitle("Verbindungen", { sub: "Kalender · E-Mail · Nachrichten · Siri · Excel", key: "lt-ix" });
  // Kopf: alles an einem Ort
  const srvPill = !srv() ? `<a class="ix-pill orange" href="#einstellungen/sync">${icon("cloudOff")}<span>Ohne Server</span></a>` : a === null ? `<span class="ix-pill">${`<span class="spinner xs"></span>`}<span>Server wird geprüft …</span></span>` : a.ok ? `<span class="ix-pill green">${icon("cloud")}<span>Server verbunden</span></span>` : `<a class="ix-pill orange" href="#einstellungen/sync">${icon("cloudOff")}<span>Server nicht erreichbar</span></a>`;
  h += `<section class="ix-hero" data-key="ix-hero">
<div class="ix-orbit" aria-hidden="true"><span class="ix-o o1">${icon("calendar")}</span><span class="ix-o o2">${icon("mail")}</span><span class="ix-o o3">${icon("message")}</span><span class="ix-o o4">${icon("waveform")}</span><span class="ix-o o5">${icon("table")}</span><span class="ix-core">${logo()}</span></div>
<div class="ix-hero-t"><h2>Alles an einem Ort</h2><p>Termine, markierte Mails, Nachrichten und Automationen laufen in deinen Taschen zusammen – verbinde, was du schon nutzt.</p>
<div class="ix-pills"><span class="ix-pill accent"><b>${active}</b><span>aktiv</span></span>${srvPill}</div></div>
</section>`;
  const jump = [
    ["kalender", "calendar", "Kalender"],
    ["email", "mail", "E-Mail"],
    ["nachrichten", "message", "Nachrichten"],
    ["automatisierung", "bolt", "Automatisierung"],
    ["datenx", "table", "Excel & CSV"],
  ];
  h += `<nav class="ix-jump hscroll" data-key="ix-jump" aria-label="Bereiche">${jump.map(([id, ic, l]) => `<button type="button" class="chip" data-act="scroll-to" data-to="set-${id}">${icon(ic)}<span>${l}</span></button>`).join("")}</nav>`;

  h += calendarGroup(accs);
  h += mailGroup(accs);
  h += messagesGroup();
  h += automationGroup(accs);
  h += dataGroup();
  h += `<p class="set-foot ix-foot" data-key="ix-foot">${icon("shield")} <b>Ehrlich und privat:</b> Kalender-Links lädt dein eigener Server für dich (kurz zwischengespeichert), markierte Mails von GMX & Co. laufen über ihn, IMAP-Zugänge liegen dort verschlüsselt. Briefkasten-Einträge liegen mit dem Server-Schlüssel verschlüsselt auf dem Server – nicht Ende-zu-Ende – und nur, bis die App sie abholt. Links und Schlüssel kommen nie ins Backup. Arbeitstaschen liest nur: Es löscht, verschiebt oder verschickt nichts in deinen Postfächern und Kalendern.</p>`;

  const target = r?.tab || (r?.id === "konten" ? "kalender" : "");
  if (target) {
    setTimeout(() => {
      const t = document.getElementById("set-" + target);
      if (t && !t._scrolled) {
        t._scrolled = true;
        window.scrollTo({ top: t.getBoundingClientRect().top + window.scrollY - (app.wide ? 70 : 100), behavior: "smooth" });
      }
    }, 140);
  }
  return `<div class="view view-settings view-ix" data-key="view-ix">${h}</div>`;
}

const groupHead = (id, ic, col, title, sub = "") => `<h3 class="ix-h"><span class="sq" style="${colorVars(col)}">${icon(ic)}</span><span class="ix-h-t">${esc(title)}</span>${sub ? `<small>${sub}</small>` : ""}</h3>`;
const group = (id, ic, col, title, sub, body, foot = "") => `<section class="set ix-set" id="set-${id}" data-key="set-${id}">${groupHead(id, ic, col, title, sub)}${body}${foot ? `<p class="set-foot">${foot}</p>` : ""}</section>`;

// Zeile für ein verbundenes Konto (Google/Microsoft öffnen das bekannte Menü, Kalender-Link/IMAP ihr eigenes)
function accRow(a, kind) {
  const s = connect.accountState(a.id) || { kind: "ok" };
  let act, sub;
  const err = s.kind === "expired" ? `<span class="red">${esc(s.msg || "Abgelaufen – neu verbinden")}</span>` : s.kind === "error" ? `<span class="orange">${esc(s.msg)}</span>` : s.kind === "network" ? `<span class="orange">${esc(s.msg)}</span>` : "";
  if (a.provider === "google" || a.provider === "microsoft") {
    act = `data-act="cx-acc" data-id="${esc(a.id)}"`;
    const on = kind === "calendar" ? a.calendars !== false : a.mail !== false;
    const what = kind === "calendar" ? connect.providerInfo(a.provider)?.calendar : connect.providerInfo(a.provider)?.mail;
    sub = err || `${esc(what || connect.providerName(a.provider))} · ${on ? (kind === "calendar" ? "Termine an" : "markierte Mails an") : "ausgeblendet"}`;
  } else if (a.provider === "ics") {
    act = `data-act="ix-feed" data-id="${esc(a.id)}"`;
    const k = safe(() => connect.events({ all: false }).filter((e) => e.account === a.id).length, 0);
    sub = err || `${esc(a.host || "Kalender-Link")} · ${a.calendars === false ? "ausgeblendet" : n(k, "Termin", "Termine")}`;
  } else {
    act = `data-act="ix-imap" data-id="${esc(a.id)}"`;
    const m = I.mailStyle(a);
    const k = safe(() => connect.mails().filter((x) => x.account === a.id).length, 0);
    sub = err || `${esc(m.name)} · ${a.mail === false ? "ausgeblendet" : `${k} markiert`}`;
  }
  const right = s.kind === "expired" ? `<i class="acc-dot warn"></i>` : `<i class="acc-dot" style="${colorVars(a.color || "blue")}"></i>`;
  return `<button type="button" class="frow btnrow acc" ${act} data-key="ix-acc-${kind}-${esc(a.id)}">${glyph(a.provider, "", a)}<span class="frow-l"><span class="acc-mail">${esc(connect.accountName(a))}</span><small>${sub}</small></span><span class="frow-c">${right}${icon("chevronRight")}</span></button>`;
}

// Kachel (Anbieter, Kalender-Link …) – „off“: Server fehlt → erklärt statt zu verbinden
function tile({ act, attrs = "", ic, label, sub = "", off = false, cls = "" }) {
  return `<button type="button" class="ix-tile${off ? " off" : ""}${cls ? " " + cls : ""}" data-act="${off ? "ix-off" : act}" ${attrs}><span class="ix-tile-i">${ic}</span><span class="ix-tile-t"><b>${esc(label)}</b>${sub ? `<small>${esc(sub)}</small>` : ""}</span><span class="ix-tile-x">${off ? icon("info") : icon("plus")}</span></button>`;
}

function calendarGroup(accs) {
  const cals = accs.filter((a) => a.provider === "google" || a.provider === "microsoft" || a.provider === "ics");
  const rows = cals.map((a) => accRow(a, "calendar"));
  const feedsOff = can("feeds") === false;
  const tiles = [
    tile({ act: "cx-connect", attrs: `data-p="microsoft"`, ic: glyph("microsoft"), label: "Microsoft", sub: "Outlook · Microsoft 365" }),
    tile({ act: "cx-connect", attrs: `data-p="google"`, ic: glyph("google"), label: "Google", sub: "Google Kalender" }),
    tile({ act: "ix-feed-add", attrs: `data-f="feeds"`, ic: `<span class="ix-gi red">${icon("link")}</span>`, label: "Kalender-Link", sub: "iCloud, Outlook, Schule", off: feedsOff }),
    tile({ act: "ix-feed-add", attrs: `data-f="feeds" data-v="de-feiertage"`, ic: `<span class="ix-gi green">${icon("sun")}</span>`, label: "Feiertage", sub: "Deutschland, ein Tipp", off: feedsOff }),
  ];
  const body = `<div class="card form">${rows.join("")}<div class="frow col ix-tiles-row"><div class="ix-tiles">${tiles.join("")}</div>${oauthGuide()}</div>${cals.length ? refreshRow() : ""}</div>`;
  return group("kalender", "calendar", "red", "Kalender", cals.length ? n(cals.length, "verbunden", "verbunden") : "", body, `Termine erscheinen in <b>Heute</b>, <b>Demnächst</b> und als Erinnerung. Kalender-Links (ICS/webcal) aus iCloud, Google, Outlook, Schule, Verein oder Calendly – nur lesen.`);
}

function oauthGuide() {
  const a = avail();
  if (srv() && a && a.google && a.microsoft) return "";
  if (srv() && a === null) return "";
  return `<p class="fine ix-note">${icon("info")} ${!srv() ? "Microsoft, Google, Kalender-Links und IMAP laufen über deinen Arbeitstaschen-Server – ohne ihn gehen trotzdem: Aufgaben per Link in Google/Outlook eintragen, Nachrichten, Anrufe und Excel." : "Für Microsoft/Google braucht dein Server noch Zugangsdaten – "}${srv() ? `<button type="button" class="link-btn" data-act="cx-guide">Anleitung ${prefs.cxGuide ? "ausblenden" : "zeigen"}</button>` : ""}</p>${
    prefs.cxGuide && srv()
      ? `<ol class="guide-steps ix-steps">
<li><b>Microsoft:</b> Im Microsoft-Entra-Admin-Center unter „App-Registrierungen“ eine App anlegen (Konten in allen Organisationen <i>und</i> private Microsoft-Konten), Umleitungs-URI <code>…/api/connect/microsoft/callback</code>, geheimen Clientschlüssel erzeugen.</li>
<li><b>Google:</b> In der Google Cloud Console einen OAuth-Client (Webanwendung) anlegen, Weiterleitungs-URI <code>…/api/connect/google/callback</code>, Kalender- und Gmail-API aktivieren.</li>
<li>Die Zugangsdaten fragt <code>install.sh</code> ab. Danach hier auf „Microsoft“ bzw. „Google“ tippen.</li>
</ol>`
      : ""
  }`;
}

function refreshRow() {
  const info = connect.info();
  const nE = safe(() => connect.events().length, 0), nM = safe(() => connect.mails({ all: true }).length, 0);
  return `<button type="button" class="frow btnrow" data-act="cx-refresh" data-all="1"${info.busy ? " disabled" : ""} data-key="ix-refresh">${sq("refresh", "blue")}<span class="frow-l">Jetzt aktualisieren<small>${info.at ? `zuletzt ${esc(relTime(info.at))} · ${n(nE, "Termin", "Termine")} · ${n(nM, "Mail", "Mails")}` : "noch nicht geladen"}</small></span><span class="frow-c">${info.busy ? `<span class="spinner xs"></span>` : icon("chevronRight")}</span></button>`;
}

function mailGroup(accs) {
  const ms = accs.filter((a) => a.provider === "google" || a.provider === "microsoft" || a.provider === "imap");
  const rows = ms.map((a) => accRow(a, "mail"));
  const imapOff = can("imap") === false;
  const big = [tile({ act: "cx-connect", attrs: `data-p="microsoft"`, ic: glyph("microsoft"), label: "Microsoft", sub: "Outlook · Microsoft 365" }), tile({ act: "cx-connect", attrs: `data-p="google"`, ic: glyph("google"), label: "Google", sub: "Gmail · Workspace" })];
  const small = I.MAIL_PROVIDERS.map((p) => `<button type="button" class="ix-mt${imapOff ? " off" : ""}" data-act="${imapOff ? "ix-off" : "ix-imap-add"}" data-f="imap" data-p="${p.id}" aria-label="${esc(p.id === "other" ? "Anderer Anbieter (IMAP)" : p.name + " verbinden")}"><span class="ix-mono${p.short.length > 2 ? " long" : ""}" style="--pg:${esc(p.color)};--pgf:${esc(p.fg)}">${p.id === "other" ? icon("at") : esc(p.short)}</span><span class="ix-mt-l">${esc(p.id === "other" ? "Andere" : p.name)}</span></button>`);
  const body = `<div class="card form">${rows.join("")}<div class="frow col ix-tiles-row"><div class="ix-tiles two">${big.join("")}</div><p class="ix-sub">Weitere Postfächer (IMAP)${imapOff ? ` <button type="button" class="link-btn" data-act="ix-off" data-f="imap">${icon("info")} braucht den Server</button>` : ""}</p><div class="ix-mtiles">${small.join("")}</div></div></div>`;
  const how = ms.length ? flagHint(ms, { list: true }) : "Gmail: Stern · Outlook: Fahne · GMX/WEB.DE: „Wichtig“";
  return group("email", "mail", "blue", "E-Mail", ms.length ? n(ms.length, "Postfach", "Postfächer") : "", body, `Markierst du eine Mail (${esc(how)}), erscheint sie im <b>Eingang</b> – ein Tipp macht daraus eine Aufgabe. Nur lesen: Im Postfach ändert sich nichts.`);
}

function messagesGroup() {
  const apps = [
    ["call", "green", "Telefon"],
    ["message", "wa", "WhatsApp"],
    ["msgDots", "green", "SMS"],
    ["video", "green", "FaceTime"],
    ["people", "indigo", "Teams"],
    ["video", "blue", "Zoom & Meet"],
    ["map", "red", "Karten"],
    ["share", "gray", "Teilen"],
  ];
  const demo = `<div class="ix-demo" aria-hidden="true"><div class="cxr-h"><span class="sq" style="${colorVars("green")}">${icon("call")}</span><span class="cxr-t"><b>0171 234 56 78</b><small>Mobil · aus der Notiz erkannt</small></span></div><div class="cxr-b"><span class="cxb call">${icon("call")}<span>Anrufen</span></span><span class="cxb wa">${icon("message")}<span>WhatsApp</span></span><span class="cxb sms">${icon("msgDots")}<span>SMS</span></span><span class="cxb ft">${icon("video")}<span>FaceTime</span></span></div></div>`;
  const body = `<div class="card ix-msg"><div class="ix-apps">${apps.map(([ic, col, l]) => `<span class="ix-app"><span class="ix-app-i ${col}">${icon(ic)}</span><span>${esc(l)}</span></span>`).join("")}</div><p class="ix-msg-t">Steht in einer Aufgabe eine <b>Telefonnummer</b>, <b>E-Mail-Adresse</b> oder <b>Adresse</b>, erscheinen im Aufgaben-Detail unter „Kontakt & Kalender“ die passenden Knöpfe. Links zu Teams, Zoom oder Meet werden zu „Beitreten“.</p>${demo}<p class="ix-ok">${icon("checkCircle")}<span>Geht sofort – keine Einrichtung nötig</span></p></div>`;
  return group("nachrichten", "message", "green", "Nachrichten & Anrufe", "automatisch", body);
}

function maskUrl(u) {
  const m = /^(.*\/api\/in\/)([0-9a-f]{32})\/(.+)$/.exec(u);
  return m ? `${m[1]}${m[2].slice(0, 6)}…/${m[3].slice(0, 4)}••••••` : u;
}

function automationGroup(accs) {
  const box = accs.find((a) => a.provider === "hook-in") || null;
  const outs = accs.filter((a) => a.provider === "hook-out");
  const inboxOff = can("inbox") === false;
  const rows = [];
  if (box) {
    const url = I.hookUrl(box);
    const st = I.inboxState(box.id);
    const stTxt = st?.expired ? `<span class="red">${esc(st.error)}</span>` : st?.error ? `<span class="orange">${esc(st.error)}</span>` : st ? `zuletzt abgeholt ${esc(relTime(st.at))}${st.n ? ` · ${n(st.n, "neue Aufgabe", "neue Aufgaben")}` : ""}` : "wird beim Öffnen der App und alle 2 Minuten abgeholt";
    rows.push(`<div class="frow col ix-box" data-key="ix-box">${sq("inboxIn", "indigo")}<span class="frow-l">Deine Eingangs-Adresse<small>Was hier ankommt, landet als Aufgabe im Eingang.</small></span>
<div class="ix-url"><code class="mono">${esc(prefs.ixShowUrl ? url : maskUrl(url))}</code><button type="button" class="btn-round sm ghost" data-act="ix-hook-show" aria-label="${prefs.ixShowUrl ? "Adresse verbergen" : "Adresse ganz anzeigen"}">${icon("eye")}</button></div>
<div class="ix-btns"><button type="button" class="btn sm primary" data-act="ix-hook-copy">${icon("copy")}<span>Kopieren</span></button><button type="button" class="btn sm" data-act="ix-hook-test">${icon("send")}<span>Test schicken</span></button><button type="button" class="btn sm" data-act="ix-pull">${icon("refresh")}<span>Abholen</span></button><button type="button" class="btn-round" data-act="ix-hook-menu" aria-label="Mehr">${icon("ellipsis")}</button></div>
<p class="fine">${stTxt}</p></div>`);
  } else {
    rows.push(`<button type="button" class="frow btnrow${inboxOff ? " soft" : ""}" data-act="${inboxOff || !srv() ? "ix-off" : "ix-hook-create"}" data-f="inbox" data-key="ix-box-new">${sq("inboxIn", "indigo")}<span class="frow-l">Eingangs-Adresse erstellen<small>${srv() ? (inboxOff ? (avail()?.ok === false ? "Server gerade nicht erreichbar" : "Dein Server kann das noch nicht – bitte aktualisieren") : "Deine geheime Adresse für Siri, Zapier, Make, n8n, IFTTT, Formulare") : "braucht den Arbeitstaschen-Server"}</small></span><span class="frow-c">${inboxOff || !srv() ? icon("info") : icon("plus")}</span></button>`);
  }
  // Siri & Kurzbefehle
  rows.push(`<div class="frow col guide${guideOpen("siri") ? " open" : ""}" data-key="ix-g-siri"><button type="button" class="guide-t" data-act="ix-guide" data-k="siri" aria-expanded="${guideOpen("siri")}"><span class="sq siri">${icon("waveform")}</span><span class="frow-l">Siri & Kurzbefehle<small>„Hey Siri, neue Aufgabe“ – in 3 Minuten eingerichtet</small></span>${icon(guideOpen("siri") ? "chevronUp" : "chevronDown")}</button>${
    guideOpen("siri")
      ? `<ol class="guide-steps">
<li>${box ? `Oben auf <b>„Kopieren“</b> tippen – die Eingangs-Adresse ist jetzt in der Zwischenablage.` : `Oben die <b>Eingangs-Adresse erstellen</b> und auf <b>„Kopieren“</b> tippen.`}</li>
<li>Die App <b>Kurzbefehle</b> öffnen → <b>＋</b> (neuer Kurzbefehl) → oben als Name <b>„Neue Aufgabe“</b> eintragen.</li>
<li>Aktion <b>„Nach Eingabe fragen“</b> hinzufügen. Frage: <i>„Was soll ich notieren?“</i></li>
<li>Aktion <b>„Inhalte von URL abrufen“</b> hinzufügen. Als URL die kopierte Adresse einfügen. Auf den Pfeil <b>›</b> tippen: Methode <b>POST</b>, Anfragetext <b>JSON</b>, neues Feld <b>Text</b> mit Schlüssel <code>title</code> und Wert <i>„Angefragte Eingabe“</i>.</li>
<li>Optional weitere Felder: <code>due</code> = „heute“, <code>bag</code> = Name einer Tasche.</li>
<li>Fertig – sag <b>„Hey Siri, neue Aufgabe“</b>. Die Aufgabe landet im Eingang, „via Siri“. Geht auch auf Apple Watch, iPad und Mac.</li>
</ol><p class="fine">Tipp: Wie in der Schnellerfassung wird mitgedacht – „Steuerberater anrufen morgen 10 Uhr #Büro !!“ bekommt Datum, Uhrzeit, Tasche und Priorität.</p>`
      : ""
  }</div>`);
  // Zapier & Co.
  const due = dates.addDays(today(), 3);
  rows.push(`<div class="frow col guide${guideOpen("zap") ? " open" : ""}" data-key="ix-g-zap"><button type="button" class="guide-t" data-act="ix-guide" data-k="zap" aria-expanded="${guideOpen("zap")}"><span class="sq zap">${icon("bolt")}</span><span class="frow-l">Zapier · Make · n8n · IFTTT<small>Aufgaben aus 6000 Apps – und Ereignisse zurück</small></span>${icon(guideOpen("zap") ? "chevronUp" : "chevronDown")}</button>${
    guideOpen("zap")
      ? `<div class="ix-guide-b"><p><b>Rein – neue Aufgaben:</b> In Zapier „Webhooks by Zapier → POST“, in Make „HTTP → Eine Anfrage stellen“, in n8n „HTTP Request“, in IFTTT „Webhooks → Make a web request“. URL = deine Eingangs-Adresse, Methode POST, Inhalt JSON:</p>
<pre class="ix-code">{
  "title": "Rechnung Huber prüfen",
  "notes": "kam per Mail",
  "due": "${esc(due)}",
  "time": "09:00",
  "bag": "Büro",
  "prio": "hoch",
  "url": "https://…"
}</pre>
<p>Nur <code>title</code> ist Pflicht. Formulare dürfen auch <code>name=…</code>, Lesezeichen einfach <code>…?text=Milch kaufen</code> schicken.</p>
<p><b>Raus – wenn etwas passiert:</b> In Zapier „Webhooks by Zapier → Catch Hook“ (Make: „Webhooks → Custom webhook“, n8n: „Webhook“) anlegen und die Adresse unten als ausgehenden Webhook eintragen. Bei „neu“ und „erledigt“ schickt die App:</p>
<pre class="ix-code">{ "event": "task.done",
  "task": { "title": "…", "due": "…",
            "bag": "Büro", "prio": 3 } }</pre></div>`
      : ""
  }</div>`);
  for (const o of outs) rows.push(`<button type="button" class="frow btnrow" data-act="ix-out" data-id="${esc(o.id)}" data-key="ix-out-${esc(o.id)}">${sq("send", "orange")}<span class="frow-l"><span class="acc-mail">${esc(o.name || o.host || "Webhook")}</span><small>${esc(o.host || "")} · bei ${(Array.isArray(o.on) ? o.on : []).map((x) => (x === "add" ? "neu" : "erledigt")).join(" & ") || "–"}</small></span><span class="frow-c">${icon("chevronRight")}</span></button>`);
  rows.push(`<button type="button" class="frow btnrow" data-act="ix-out-add" data-key="ix-out-new">${sq("send", "orange")}<span class="frow-l">Ausgehenden Webhook hinzufügen<small>bei „Aufgabe neu“ und „erledigt“ an Zapier, Make, n8n …</small></span><span class="frow-c">${icon("plus")}</span></button>`);
  return group("automatisierung", "bolt", "purple", "Automatisierung", box || outs.length ? "aktiv" : "", `<div class="card form">${rows.join("")}</div>`, `Einträge liegen verschlüsselt (Server-Schlüssel, nicht Ende-zu-Ende) auf deinem Server – nur so lange, bis die App sie abholt. Wer die Eingangs-Adresse kennt, kann dir Aufgaben schicken: Teile sie nicht öffentlich; „Neue Adresse“ macht die alte ungültig.`);
}

function dataGroup() {
  const nT = safe(() => store.tasks().length, 0);
  const rows = [
    `<button type="button" class="frow btnrow" data-act="ix-csv-export" data-key="ix-csv-out">${sq("table", "green")}<span class="frow-l">Als Excel/CSV exportieren<small>${n(nT, "Aufgabe", "Aufgaben")} · öffnet sich in Excel, Numbers und Google Tabellen</small></span><span class="frow-c">${icon("chevronRight")}</span></button>`,
    `<label class="frow btnrow" data-key="ix-csv-in">${sq("download", "teal")}<span class="frow-l">CSV importieren<small>Eigene Listen, Excel, Todoist, Trello, Asana – mit Vorschau</small></span><span class="frow-c">${icon("chevronRight")}</span><input type="file" accept=".csv,.tsv,.txt,text/csv,text/tab-separated-values,text/plain" class="hidden-file" data-change="ix-csv-file" aria-label="CSV-Datei wählen" /></label>`,
    `<button type="button" class="frow btnrow" data-act="go" data-to="#einstellungen/daten" data-key="ix-backup">${sq("archive", "gray")}<span class="frow-l">Backup (alles)<small>Taschen, Notizen, Links, Dateien – als JSON-Datei</small></span><span class="frow-c">${icon("chevronRight")}</span></button>`,
  ];
  return group("datenx", "table", "green", "Excel & CSV", "", `<div class="card form">${rows.join("")}</div>`, `Excel öffnet die Datei direkt (Semikolon, UTF-8). Zum Importieren in Excel „Datei → Speichern unter → CSV UTF-8“ wählen.`);
}

// Einstieg ganz oben in den Einstellungen
export function settingsEntry() {
  const k = activeCount();
  return `<a class="ix-entry card" href="#einstellungen/verbindungen" data-key="set-ix-entry"><span class="ix-stack" aria-hidden="true"><span class="sq" style="${colorVars("red")}">${icon("calendar")}</span><span class="sq" style="${colorVars("blue")}">${icon("mail")}</span><span class="sq" style="${colorVars("green")}">${icon("message")}</span><span class="sq siri">${icon("waveform")}</span></span><span class="frow-l"><b>Verbindungen</b><small>Kalender, E-Mail, WhatsApp, Siri, Excel${k ? ` · ${k} aktiv` : ""}</small></span>${icon("chevronRight")}</a>`;
}

// =====================================================================================================================
// Heute: „Mit allem verbinden“ (wenn noch nichts verbunden ist und der Tag leer ist)
// =====================================================================================================================
export function todayCard({ emptyDay = false } = {}) {
  if (prefs.ixCard === "hidden" || activeCount() > 0 || !emptyDay) return "";
  return `<section class="ix-card" data-key="ix-card"><div class="ix-card-art ix-stack" aria-hidden="true"><span class="ix-o o1">${icon("calendar")}</span><span class="ix-o o2">${icon("mail")}</span><span class="ix-o o3">${icon("message")}</span><span class="ix-o o4">${icon("waveform")}</span><span class="ix-o o5">${icon("table")}</span></div><div class="ix-card-b"><h3>Mit allem verbinden</h3><p>Kalender, E-Mail, WhatsApp, Siri und Excel – an einem Ort. Deine Termine und markierten Mails erscheinen dann direkt hier.</p><div class="rcard-btns"><a class="btn primary sm" href="#einstellungen/verbindungen">${icon("plug")}<span>Verbindungen</span></a></div></div><button type="button" class="rcard-x" data-act="ix-card-hide" aria-label="Ausblenden">${icon("x")}</button></section>`;
}

// Eingang: Knopf „Aktualisieren“ in der Kopfzeile (Briefkasten + markierte Mails)
export function inboxAction() {
  const has = safe(() => store.accounts().some((a) => a.provider === "hook-in") || connect.mailAccounts().length > 0, false);
  return has ? `<button type="button" class="btn-round" data-act="ix-pull" data-mails="1" aria-label="Eingang aktualisieren" title="Aktualisieren">${icon("refresh")}</button>` : "";
}

// =====================================================================================================================
// Aufgaben-Detail: Kontakt & Kalender
// =====================================================================================================================
const KIND_L = { mobil: "Mobil", festnetz: "Festnetz" };
function btn(url, cls, ic, label) {
  return ext(url, `cxb${cls ? " " + cls : ""}`, `${icon(ic)}<span>${esc(label)}</span>`, label);
}

export function contactBlock(t) {
  const text = `${t.title}\n${t.notes || ""}\n${t.waiting || ""}`;
  const nums = connect.phoneList(text).slice(0, 3);
  const src = t.src && typeof t.src === "object" ? t.src : null;
  const mails = [...new Set([...(src?.kind === "mail" && src.email ? [String(src.email).toLowerCase()] : []), ...connect.emails(text)])].slice(0, 2);
  const addrs = safe(() => I.addresses(`${t.title}\n${t.notes || ""}`), []).slice(0, 2);
  const join = (src?.join && connect.httpsUrl(src.join)) || safe(() => connect.joinLink({ notes: t.notes || "" }), null);
  const parts = [];
  const msg = `Hallo, wegen „${t.title.length > 60 ? t.title.slice(0, 59) + "…" : t.title}“: `;
  for (const p of nums) {
    const kind = I.phoneKind(p.tel);
    const btns = [btn(connect.telHref(p.tel), "call", "call", "Anrufen"), btn(I.whatsappLink(p.tel, msg), "wa", "message", "WhatsApp"), btn(I.smsLink(p.tel, msg), "sms", "msgDots", "SMS")];
    if (kind !== "festnetz") btns.push(btn(I.facetimeLink(p.tel), "ft", "video", "FaceTime"));
    parts.push(`<div class="cxr" data-key="cxr-p-${esc(p.tel)}"><div class="cxr-h">${sq("call", "green")}<span class="cxr-t"><b>${esc(p.label)}</b><small>${esc(KIND_L[kind] || "Telefon")}</small></span><button type="button" class="cxr-copy" data-act="cx-copy" data-v="${esc(p.label)}" aria-label="Nummer kopieren" title="Kopieren">${icon("copy")}</button></div><div class="cxr-b">${btns.join("")}</div></div>`);
  }
  for (const m of mails) {
    const btns = [`<button type="button" class="cxb mail" data-act="cx-mail" data-id="${esc(t.id)}" data-to="${esc(m)}" aria-label="E-Mail an ${esc(m)}">${icon("mail")}<span>E-Mail</span></button>`, btn(I.teamsChatLink(m, msg), "teams", "chat", "Teams-Chat"), btn(I.teamsCallLink(m), "teams", "people", "Teams-Anruf")];
    parts.push(`<div class="cxr" data-key="cxr-m-${esc(m)}"><div class="cxr-h">${sq("at", "blue")}<span class="cxr-t"><b>${esc(m)}</b><small>E-Mail-Adresse</small></span><button type="button" class="cxr-copy" data-act="cx-copy" data-v="${esc(m)}" aria-label="Adresse kopieren" title="Kopieren">${icon("copy")}</button></div><div class="cxr-b">${btns.join("")}</div></div>`);
  }
  for (const a of addrs) {
    const L = I.mapsLinks(a.query);
    const btns = [btn(L.apple, "maps", "map", "Apple Karten"), btn(L.google, "gmaps", "location", "Google Maps"), btn(`https://maps.apple.com/?daddr=${encodeURIComponent(a.query)}`, "route", "route", "Route")];
    parts.push(`<div class="cxr" data-key="cxr-a-${esc(a.label.slice(0, 40))}"><div class="cxr-h">${sq("location", "red")}<span class="cxr-t"><b>${esc(a.label)}</b><small>Adresse</small></span><button type="button" class="cxr-copy" data-act="cx-copy" data-v="${esc(a.label)}" aria-label="Adresse kopieren" title="Kopieren">${icon("copy")}</button></div><div class="cxr-b">${btns.join("")}</div></div>`);
  }
  if (join) parts.push(ext(join, "frow btnrow", `${sq("video", "teal")}<span class="frow-l">Beitreten<small>${esc(connect.joinKind(join) || "Online-Meeting")}</small></span><span class="frow-c">${icon("arrowUpRight")}</span>`));
  // Kalender
  const cal = Array.isArray(t.cal) ? t.cal.filter((c) => c && c.account) : [];
  const calAcc = cal.map((c) => store.account(c.account)).filter(Boolean)[0];
  const calSub = !t.due ? "Erst ein Datum wählen" : cal.length ? `✓ eingetragen${calAcc ? ` in ${esc(calAcc.email)}` : ""}` : connect.accounts().some((a) => a.secret && !a.broken && a.calendars !== false) ? "direkt in deinen Kalender" : "Google, Outlook oder Kalender-Datei";
  parts.push(`<button type="button" class="frow btnrow${t.due ? "" : " soft"}" data-act="cx-cal" data-id="${esc(t.id)}">${sq("calendarPlus", "red")}<span class="frow-l">In Kalender eintragen<small>${calSub}</small></span><span class="frow-c">${icon("chevronRight")}</span></button>`);
  if (!mails.length) parts.push(`<button type="button" class="frow btnrow" data-act="cx-mail" data-id="${esc(t.id)}">${sq("mail", "blue")}<span class="frow-l">E-Mail schreiben<small>Gmail, Outlook oder Mail-App</small></span><span class="frow-c">${icon("chevronRight")}</span></button>`);
  // Teilen
  const bag = t.bag ? store.bag(t.bag) : null;
  const shareText = I.taskShareText(t, { bag });
  const mailto = connect.composeLinks({ subject: t.title, body: shareText }).mailto;
  parts.push(`<div class="cxr share" data-key="cxr-share"><div class="cxr-h">${sq("share", "gray")}<span class="cxr-t"><b>Aufgabe teilen</b><small>mit Kollegen, Familie, Handwerkern …</small></span></div><div class="cxr-b"><button type="button" class="cxb" data-act="ix-share" data-id="${esc(t.id)}" aria-label="Teilen">${icon("share")}<span>Teilen</span></button>${btn(I.whatsappLink("", shareText), "wa", "message", "WhatsApp")}${btn(mailto, "mail", "mail", "E-Mail")}<button type="button" class="cxb" data-act="ix-share-copy" data-id="${esc(t.id)}" aria-label="Als Text kopieren">${icon("copy")}<span>Kopieren</span></button></div></div>`);
  if (src?.web) parts.push(ext(src.web, "frow btnrow", `${sq(src.kind === "mail" ? "mail" : "calendar", "gray")}<span class="frow-l">${src.kind === "mail" ? (src.provider === "imap" ? "Im Webmailer öffnen" : "Original-Mail öffnen") : "Termin im Kalender öffnen"}</span><span class="frow-c">${icon("arrowUpRight")}</span>`));
  return `<section class="td-block" data-key="td-cx"><h3 class="td-h">Kontakt & Kalender</h3><div class="card form cxc">${parts.join("")}</div></section>`;
}

// =====================================================================================================================
// Sheet: Kalender-Link
// =====================================================================================================================
const FS = { name: "", url: "", color: "red", src: "icloud", busy: false, result: null, error: "" };
const FEED_SRC = [
  { id: "icloud", label: "iCloud", steps: ["Auf dem iPhone die App <b>Kalender</b> öffnen und unten auf <b>Kalender</b> tippen.", "Beim gewünschten Kalender auf <b>ⓘ</b> tippen.", "<b>„Öffentlicher Kalender“</b> einschalten → <b>„Link teilen …“</b> → <b>„Kopieren“</b>.", "Hier oben bei „Link“ einfügen. (Am Mac: Kalender → Rechtsklick → Teilen → Öffentlicher Kalender.)"] },
  { id: "google", label: "Google", steps: ["Am Computer <b>calendar.google.com</b> öffnen.", "Links beim Kalender auf <b>⋮</b> → <b>„Einstellungen und Freigabe“</b>.", "Ganz unten die <b>„Privatadresse im iCal-Format“</b> (geheime Adresse) kopieren.", "Hier einfügen. Tipp: Mit Google verbinden (oben) zeigt alle Kalender auf einmal."] },
  { id: "outlook", label: "Outlook", steps: ["<b>outlook.office.com</b> (Firma) bzw. <b>outlook.com</b> (privat) öffnen → <b>⚙︎ Einstellungen</b> → <b>Kalender</b> → <b>Freigegebene Kalender</b>.", "Unter <b>„Kalender veröffentlichen“</b> den Kalender wählen, „Kann alle Details anzeigen“ → <b>Veröffentlichen</b>.", "Den <b>ICS-Link</b> kopieren und hier einfügen.", "Sperrt die Firma das Veröffentlichen, nimm „Mit Microsoft verbinden“."] },
  { id: "feiertage", label: "Feiertage", steps: ["Ein Tipp genügt: <b>„Feiertage Deutschland einfügen“</b> unten.", "Schulferien: z. B. auf schulferien.org dein Bundesland wählen und den <b>iCal/ICS-Link</b> kopieren."] },
  { id: "andere", label: "Andere", steps: ["Calendly, Doodle, Schule, Verein, Firmen-Intranet: nach <b>„Abonnieren“</b>, <b>„iCal“</b>, <b>„ICS“</b> oder <b>„webcal“</b> suchen und den Link kopieren.", "Links mit <code>webcal://</code> gehen genauso wie <code>https://</code>."] },
];
export function openFeedSheet({ preset = "" } = {}) {
  Object.assign(FS, { name: "", url: "", color: nextColor("ics"), src: "icloud", busy: false, result: null, error: "" });
  if (preset) {
    const p = I.PUBLIC_FEEDS.find((x) => x.id === preset);
    if (p) Object.assign(FS, { name: p.name, url: p.url, color: p.color, src: "feiertage" });
  }
  openSheet({ key: "ix-feed", label: "Kalender-Link hinzufügen", size: "large", render: feedView });
  if (preset && FS.url) feedTest(); // Feiertage: gleich zeigen, was kommt
}
function feedView() {
  const src = FEED_SRC.find((x) => x.id === FS.src) || FEED_SRC[0];
  const r = FS.result;
  const res = FS.busy === "test" ? `<div class="ix-res"><span class="spinner xs"></span><span>Kalender wird geladen …</span></div>` : FS.error ? `<div class="ix-res red">${icon("info")}<span>${esc(FS.error)}</span></div>` : r ? `<div class="ix-res green">${icon("checkCircle")}<span><b>${r.count === 1 ? "1 Termin" : `${r.count} Termine`} gefunden</b>${r.next ? `<small>Nächster: ${esc(safe(() => dates.relDay(r.next.date, app.now), r.next.date))}${r.next.allDay ? "" : `, ${esc(r.next.time ? safe(() => dates.fmtTime(r.next.time), r.next.time) : "")}`} – ${esc(r.next.title)}</small>` : r.total ? `<small>${r.total} Einträge insgesamt, in den nächsten 30 Tagen keiner</small>` : ""}</span></div>` : "";
  return `${sheetHead("Kalender-Link", { sub: "nur lesen", left: `<button type="button" class="btn-text" data-act="sheet-close">Abbrechen</button>`, right: `<button type="button" class="btn-text bold" data-act="ix-feed-save"${FS.busy ? " disabled" : ""}>Hinzufügen</button>` })}
<div class="sheet-pad ixs">
<div class="ixs-src hscroll" role="tablist" aria-label="Woher kommt der Kalender?">${FEED_SRC.map((x) => `<button type="button" class="chip${x.id === FS.src ? " on" : ""}" role="tab" aria-selected="${x.id === FS.src}" data-act="ix-feed-src" data-v="${x.id}">${esc(x.label)}</button>`).join("")}</div>
<ol class="guide-steps ixs-steps" data-key="ixs-steps-${src.id}">${src.steps.map((s) => `<li>${s}</li>`).join("")}</ol>
${src.id === "feiertage" ? `<button type="button" class="btn sm ixs-preset" data-act="ix-feed-preset" data-v="de-feiertage">${icon("sun")}<span>Feiertage Deutschland einfügen</span></button>` : ""}
<div class="card form">
<label class="frow col input"><span class="frow-l">Link</span><input type="url" class="in-text" value="${esc(FS.url)}" placeholder="webcal://… oder https://…" data-input="ix-in" data-f="FS.url" autocapitalize="off" autocorrect="off" spellcheck="false" inputmode="url" enterkeyhint="next" /></label>
<label class="frow col input"><span class="frow-l">Name</span><input type="text" class="in-text" value="${esc(FS.name)}" placeholder="z. B. Familie, Firma, Schule" data-input="ix-in" data-f="FS.name" maxlength="80" enterkeyhint="done" /></label>
<div class="frow col"><span class="frow-l ix-lab">Farbe</span><div class="colors">${ACC_COLORS.map((c) => `<button type="button" class="color${FS.color === c ? " on" : ""}" style="${colorVars(c)}" data-act="ix-feed-color" data-v="${c}" aria-label="${esc(COLOR_NAMES[c])}" aria-pressed="${FS.color === c}"></button>`).join("")}</div></div>
</div>
<div class="ixs-test"><button type="button" class="btn sm" data-act="ix-feed-test"${FS.busy ? " disabled" : ""}>${icon("refresh")}<span>Testen</span></button>${res}</div>
<button type="button" class="btn primary wide" data-act="ix-feed-save"${FS.busy ? " disabled" : ""}>${FS.busy === "save" ? `<span class="spinner sm"></span>` : icon("plus")}<span>Kalender hinzufügen</span></button>
<p class="fine">Der Link ist wie ein Schlüssel: Er wird verschlüsselt mit deinen Geräten synchronisiert und nur von deinem Server zum Laden benutzt – nicht ins Backup geschrieben. Aktualisiert wird alle paar Minuten.</p>
</div>`;
}
const refreshFeed = () => getSheet("ix-feed")?.refresh();
async function feedTest() {
  if (!FS.url.trim()) {
    FS.error = "Bitte zuerst den Link einfügen.";
    return refreshFeed();
  }
  FS.busy = "test";
  FS.error = "";
  FS.result = null;
  refreshFeed();
  try {
    FS.result = await I.testFeed(srv(), FS.url);
    if (!FS.name.trim() && FS.result.name) FS.name = FS.result.name;
  } catch (e) {
    FS.error = e.message || "Das hat nicht geklappt.";
  }
  FS.busy = false;
  refreshFeed();
}
async function feedSave() {
  if (FS.busy) return;
  if (!FS.url.trim()) {
    FS.error = "Bitte den Link einfügen.";
    return refreshFeed();
  }
  FS.busy = "save";
  FS.error = "";
  refreshFeed();
  try {
    // erst laden – ein falscher Link soll gar nicht erst gespeichert werden
    const r = FS.result && !FS.error ? FS.result : await I.testFeed(srv(), FS.url);
    const a = I.addFeed(store, { name: FS.name.trim() || r.name, url: FS.url, color: FS.color, server: srv() });
    FS.busy = false;
    getSheet("ix-feed")?.close();
    haptic();
    sound("soft");
    toast(`„${a.name}“ ist verbunden`, { icon: "calendarCheck", sub: r.count ? `${r.count === 1 ? "1 Termin" : `${r.count} Termine`} in den nächsten 30 Tagen` : "Termine erscheinen in Heute und Demnächst" });
    connect.refresh(store, { force: true }).catch(() => {});
  } catch (e) {
    FS.busy = false;
    FS.error = e.message || "Das hat nicht geklappt.";
    refreshFeed();
  }
}
function feedMenu(id, el) {
  const a = store.account(id);
  if (!a) return;
  const s = connect.accountState(id) || { kind: "ok" };
  const items = [];
  if (s.kind !== "ok") items.push({ label: !a.secret ? "Link neu eintragen" : "Erneut laden", hint: s.msg, icon: "refresh", run: () => (!a.secret ? relinkFeed(id) : connect.refresh(store, { force: true, retryBroken: true }).catch((e) => toastError(e))) });
  items.push(
    { label: "Termine anzeigen", check: a.calendars !== false, run: () => store.updateAccount(id, { calendars: a.calendars === false }) },
    { label: "Umbenennen …", icon: "pencil", run: () => renameAcc(id) },
    { label: "Farbe", icon: "palette", sub: ACC_COLORS.map((c) => ({ label: COLOR_NAMES[c], check: a.color === c, run: () => store.updateAccount(id, { color: c }) })) },
    { label: "Link ändern …", icon: "link", run: () => relinkFeed(id) },
    "-",
    { label: "Entfernen", icon: "trash", danger: true, run: () => removeFeedAsk(id) },
  );
  openMenu(items, { el, title: connect.accountName(a) });
}
async function renameAcc(id) {
  const a = store.account(id);
  if (!a) return;
  const v = (await promptBox({ title: "Name", value: a.name || a.label || "", ok: "Sichern" }))?.trim();
  if (v) store.updateAccount(id, { name: v.slice(0, 80), label: v.slice(0, 80) });
}
async function relinkFeed(id) {
  const a = store.account(id);
  if (!a) return;
  const v = (await promptBox({ title: "Kalender-Link", text: "Den neuen Link (https:// oder webcal://) einfügen.", value: "", placeholder: "webcal://…", ok: "Sichern", type: "url" }))?.trim();
  if (!v) return;
  const u = I.feedUrl(v);
  if (!u) return toast("Das ist kein gültiger Kalender-Link", { icon: "info", tone: "red" });
  store.updateAccount(id, { secret: u, host: new URL(u).hostname.replace(/^www\./, ""), broken: false });
  connect.refresh(store, { force: true }).catch(() => {});
  toast("Link gespeichert", { icon: "link" });
}
async function removeFeedAsk(id) {
  const a = store.account(id);
  if (!a) return;
  if (!(await confirmBox({ title: "Kalender entfernen?", text: `„${connect.accountName(a)}“ verschwindet aus Arbeitstaschen – auf allen Geräten. Der Kalender selbst bleibt, wie er ist.`, ok: "Entfernen", danger: true }))) return;
  I.removeFeed(store, id);
  toast("Kalender entfernt", { icon: "checkCircle" });
}

// =====================================================================================================================
// Sheet: E-Mail per IMAP
// =====================================================================================================================
const MS = { provider: null, email: "", password: "", host: "", port: "993", label: "", adv: false, busy: false, error: "" };
export function openImapSheet(provider = null) {
  const p = provider ? I.mailProvider(provider) : null;
  Object.assign(MS, { provider: p ? p.id : null, email: "", password: "", host: p?.host || "", port: String(p?.port || 993), label: p && p.id !== "other" ? p.name : "", adv: p?.id === "other", busy: false, error: "" });
  openSheet({ key: "ix-imap", label: "E-Mail-Postfach verbinden", size: "large", render: imapView, onClose: () => (MS.password = "") });
}
function imapView() {
  const p = MS.provider ? I.mailProvider(MS.provider) : null;
  if (!p)
    return `${sheetHead("E-Mail verbinden", { sub: "markierte Mails im Eingang" })}<div class="sheet-pad ixs"><p class="ixs-lead">Welcher Anbieter? Gmail und Outlook verbindest du am besten direkt über Google bzw. Microsoft.</p><div class="ix-mtiles big">${I.MAIL_PROVIDERS.map((x) => `<button type="button" class="ix-mt" data-act="ix-imap-pick" data-p="${x.id}"><span class="ix-mono${x.short.length > 2 ? " long" : ""}" style="--pg:${esc(x.color)};--pgf:${esc(x.fg)}">${x.id === "other" ? icon("at") : esc(x.short)}</span><span class="ix-mt-l">${esc(x.id === "other" ? "Andere" : x.name)}</span></button>`).join("")}</div></div>`;
  const other = p.id === "other";
  return `${sheetHead(p.id === "other" ? "Anderer Anbieter" : p.name, { sub: "E-Mail per IMAP · nur lesen", left: `<button type="button" class="btn-text" data-act="ix-imap-back">${icon("chevronLeft")}Anbieter</button>`, right: `<button type="button" class="btn-text bold" data-act="ix-imap-save"${MS.busy ? " disabled" : ""}>Verbinden</button>` })}
<div class="sheet-pad ixs">
<div class="ixs-prov"><span class="ix-mono xl${p.short.length > 2 ? " long" : ""}" style="--pg:${esc(p.color)};--pgf:${esc(p.fg)}">${other ? icon("at") : esc(p.short)}</span><div><b>${esc(other ? "Postfach per IMAP" : p.name)}</b><small>Markiert = ${esc(p.flag)} → erscheint im Eingang</small></div></div>
<div class="note-box">${icon("info")}<span>${esc(p.hint)}</span></div>
<div class="card form ixs-form">
<label class="frow col input"><span class="frow-l">E-Mail-Adresse</span><input type="email" class="in-text" value="${esc(MS.email)}" placeholder="${esc(p.domains[0] ? `name@${p.domains[0]}` : "name@firma.de")}" data-input="ix-in" data-f="MS.email" autocomplete="username" autocapitalize="off" autocorrect="off" spellcheck="false" inputmode="email" enterkeyhint="next" /></label>
<label class="frow col input"><span class="frow-l">${p.id === "icloud" || p.id === "yahoo" ? "App-Passwort" : "Passwort"}</span><input type="password" class="in-text" value="${esc(MS.password)}" placeholder="${p.id === "icloud" || p.id === "yahoo" ? "xxxx-xxxx-xxxx-xxxx" : "Passwort"}" data-input="ix-in" data-f="MS.password" autocomplete="current-password" enterkeyhint="go" data-key-act="ix-imap-enter" /></label>
${
  MS.adv
    ? `<label class="frow col input"><span class="frow-l">IMAP-Server</span><input type="text" class="in-text" value="${esc(MS.host)}" placeholder="imap.example.de" data-input="ix-in" data-f="MS.host" autocapitalize="off" autocorrect="off" spellcheck="false" inputmode="url" /></label>
<div class="frow ixs-two"><label class="input"><span class="frow-l">Port</span><input type="number" class="in-text" value="${esc(MS.port)}" min="1" max="65535" data-input="ix-in" data-f="MS.port" inputmode="numeric" /></label><label class="input"><span class="frow-l">Name</span><input type="text" class="in-text" value="${esc(MS.label)}" placeholder="z. B. Privat" data-input="ix-in" data-f="MS.label" maxlength="40" /></label></div>`
    : `<button type="button" class="frow btnrow ixs-adv" data-act="ix-imap-adv">${sq("gear", "gray")}<span class="frow-l">Server & Port<small>${esc(MS.host || "–")} · ${esc(MS.port)} · SSL/TLS</small></span><span class="frow-c">${icon("chevronDown")}</span></button>`
}
</div>
${MS.error ? `<div class="ix-res red">${icon("info")}<span>${esc(MS.error)}</span></div>` : ""}
<button type="button" class="btn primary wide" data-act="ix-imap-save"${MS.busy ? " disabled" : ""}>${MS.busy ? `<span class="spinner sm"></span><span>Anmeldung wird geprüft …</span>` : `${icon("lock")}<span>Verbinden</span>`}</button>
<p class="fine">Dein Passwort geht einmal verschlüsselt an deinen eigenen Arbeitstaschen-Server und liegt dort verschlüsselt – nicht auf diesem Gerät, nicht im Backup. Die markierten Mails holt der Server und reicht sie an die App weiter. Gelesen wird nur – nichts wird gelöscht oder verschickt.</p>
</div>`;
}
const refreshImap = () => getSheet("ix-imap")?.refresh();
async function imapSave() {
  if (MS.busy) return;
  const p = I.mailProvider(MS.provider);
  if (!p) return;
  if (!MS.host && p.id === "other") MS.adv = true;
  MS.busy = true;
  MS.error = "";
  refreshImap();
  try {
    const res = await I.imapConnect({ server: srv(), provider: p.id, email: MS.email, password: MS.password, host: MS.host || p.host, port: MS.port || p.port, label: MS.label });
    const a = I.addImapAccount(store, { ...res, webmail: res.webmail || p.web });
    MS.password = "";
    MS.busy = false;
    getSheet("ix-imap")?.close();
    haptic();
    sound("soft");
    toast(`${I.mailStyle(a).name} ist verbunden`, { icon: "checkCircle", sub: `${a.email} · markierte Mails kommen in den Eingang`, ms: 4200 });
    connect.refresh(store, { force: true }).catch(() => {});
  } catch (e) {
    MS.busy = false;
    MS.error = e.message || "Die Anmeldung hat nicht geklappt.";
    refreshImap();
  }
}
function imapMenu(id, el) {
  const a = store.account(id);
  if (!a) return;
  const s = connect.accountState(id) || { kind: "ok" };
  const st = I.mailStyle(a);
  const items = [];
  if (s.kind !== "ok") items.push({ label: s.kind === "expired" ? "Neu verbinden" : "Erneut versuchen", hint: s.msg, icon: "refresh", run: () => (s.kind === "expired" ? reconnectImap(a) : connect.refresh(store, { force: true, retryBroken: true }).catch((e) => toastError(e))) });
  items.push({ label: "Markierte Mails im Eingang", check: a.mail !== false, run: () => store.updateAccount(id, { mail: a.mail === false }) });
  if (a.webmail) items.push({ label: `${st.name} im Browser öffnen`, icon: "arrowUpRight", run: () => openExternal(a.webmail) });
  items.push({ label: "Farbe", icon: "palette", sub: ACC_COLORS.map((c) => ({ label: COLOR_NAMES[c], check: a.color === c, run: () => store.updateAccount(id, { color: c }) })) }, "-", { label: "Trennen", icon: "trash", danger: true, run: () => removeImapAsk(id) });
  openMenu(items, { el, title: a.email || st.name });
}
function reconnectImap(a) {
  openImapSheet(I.mailStyle(a).id);
  Object.assign(MS, { email: a.email || "", host: a.host || MS.host, port: String(a.port || 993), label: a.label || "" });
  refreshImap();
}
async function removeImapAsk(id) {
  const a = store.account(id);
  if (!a) return;
  if (!(await confirmBox({ title: `${I.mailStyle(a).name} trennen?`, text: `${a.email}: Markierte Mails verschwinden aus Arbeitstaschen – auf allen Geräten. Der Zugang wird auch auf deinem Server gelöscht. Im Postfach bleibt alles, wie es ist.`, ok: "Trennen", danger: true }))) return;
  const r = await I.removeImap(store, id);
  toast("Postfach getrennt", { icon: "checkCircle", sub: r.remote ? a.email : "Der Server war nicht erreichbar – der Zugang wird dort beim nächsten Mal nicht mehr benutzt." });
}

// =====================================================================================================================
// Briefkasten (Webhook rein) & ausgehende Webhooks
// =====================================================================================================================
const inbox = () => store.accounts().find((a) => a.provider === "hook-in") || null;
async function hookCreate() {
  try {
    toast("Adresse wird erstellt …", { icon: "inboxIn", ms: 1600 });
    const a = await I.hookCreate(store, srv());
    haptic();
    sound("soft");
    toast("Deine Eingangs-Adresse ist da", { icon: "checkCircle", sub: "Jetzt kopieren und in Siri oder Zapier einfügen", action: { label: "Kopieren", fn: () => copyText(I.hookUrl(a), "Adresse kopiert") } });
    setPref("ixGuides", { ...(prefs.ixGuides || {}), siri: true });
    app.render();
  } catch (e) {
    toastError(e, "Eingangs-Adresse");
  }
}
async function hookTest() {
  const a = inbox();
  const url = a ? I.hookUrl(a) : "";
  if (!url) return;
  try {
    // wie Siri/Zapier: einfacher POST an die eigene Adresse, danach sofort abholen
    const r = await fetch(`${url}?source=Test`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ title: "Test: Der Briefkasten funktioniert 🎉", notes: "Diese Aufgabe kam über deine Eingangs-Adresse. Du kannst sie löschen." }), credentials: "omit", cache: "no-store" });
    if (!r.ok) throw new Error(r.status === 429 ? "Zu viele Versuche – gleich noch einmal." : `Der Server hat abgelehnt (${r.status}).`);
    await pull({ force: true, quietEmpty: false });
  } catch (e) {
    toastError(e, "Test");
  }
}
async function pull({ force = true, quietEmpty = false, mails = false } = {}) {
  if (mails) connect.refresh(store, { force: true }).catch(() => {});
  if (!inbox()) {
    if (mails) toast("Wird aktualisiert …", { icon: "refresh", ms: 1400 });
    return;
  }
  try {
    const r = await I.pullInbox(store, { force });
    if (r.errors?.length && !r.added.length) toast(r.errors[0].message || "Abholen fehlgeschlagen", { icon: "info", tone: "red" });
    else if (!r.added.length && !quietEmpty) toast("Nichts Neues im Briefkasten", { icon: "inboxIn", ms: 1800 });
    app.render();
  } catch (e) {
    toastError(e);
  }
}
function hookMenu(el) {
  const a = inbox();
  if (!a) return;
  openMenu(
    [
      { label: "Neue Adresse", hint: "die alte wird sofort ungültig", icon: "refresh", run: () => hookResetAsk() },
      { label: "Adresse ganz anzeigen", check: !!prefs.ixShowUrl, run: () => (setPref("ixShowUrl", !prefs.ixShowUrl), app.render()) },
      "-",
      { label: "Briefkasten entfernen", icon: "trash", danger: true, run: () => hookRemoveAsk() },
    ],
    { el, title: "Eingangs-Adresse" },
  );
}
async function hookResetAsk() {
  const a = inbox();
  if (!a) return;
  if (!(await confirmBox({ title: "Neue Adresse erstellen?", text: "Die bisherige Adresse funktioniert dann nicht mehr – Siri-Kurzbefehle und Zaps musst du mit der neuen Adresse aktualisieren.", ok: "Neue Adresse", danger: true }))) return;
  try {
    const b = await I.hookReset(store, a);
    toast("Neue Adresse erstellt", { icon: "checkCircle", sub: "Die alte gilt nicht mehr", action: { label: "Kopieren", fn: () => copyText(I.hookUrl(b), "Adresse kopiert") } });
  } catch (e) {
    toastError(e);
  }
}
async function hookRemoveAsk() {
  const a = inbox();
  if (!a) return;
  if (!(await confirmBox({ title: "Briefkasten entfernen?", text: "Die Eingangs-Adresse wird gelöscht – Siri und Zapier können dann keine Aufgaben mehr schicken. Bereits angelegte Aufgaben bleiben.", ok: "Entfernen", danger: true }))) return;
  await I.hookRemove(store, a);
  toast("Briefkasten entfernt", { icon: "checkCircle" });
}

const OS = { id: null, name: "", url: "", add: true, done: true, error: "" };
function openOutSheet(id = null) {
  const a = id ? store.account(id) : null;
  Object.assign(OS, { id: a?.id || null, name: a?.name || "", url: a?.secret || "", add: a ? (a.on || []).includes("add") : true, done: a ? (a.on || []).includes("done") : true, error: "" });
  openSheet({ key: "ix-out", label: "Ausgehender Webhook", render: outView });
}
function outView() {
  return `${sheetHead(OS.id ? "Webhook" : "Ausgehender Webhook", { sub: "Zapier · Make · n8n · eigene Adresse", left: `<button type="button" class="btn-text" data-act="sheet-close">Abbrechen</button>`, right: `<button type="button" class="btn-text bold" data-act="ix-out-save">Sichern</button>` })}
<div class="sheet-pad ixs">
<p class="ixs-lead">Wenn eine Aufgabe <b>neu</b> ist oder <b>erledigt</b> wird, schickt die App eine kurze JSON-Nachricht an diese Adresse – z. B. an „Catch Hook“ in Zapier.</p>
<div class="card form">
<label class="frow col input"><span class="frow-l">Adresse (https)</span><input type="url" class="in-text" value="${esc(OS.url)}" placeholder="https://hooks.zapier.com/hooks/catch/…" data-input="ix-in" data-f="OS.url" autocapitalize="off" autocorrect="off" spellcheck="false" inputmode="url" /></label>
<label class="frow col input"><span class="frow-l">Name</span><input type="text" class="in-text" value="${esc(OS.name)}" placeholder="z. B. Zapier – Buchhaltung" data-input="ix-in" data-f="OS.name" maxlength="60" /></label>
<div class="frow">${sq("plus", "blue")}<span class="frow-l">Aufgabe neu</span><span class="frow-c">${toggle(OS.add, `data-change="ix-out-ev" data-v="add"`, "Bei neuer Aufgabe")}</span></div>
<div class="frow">${sq("checkCircle", "green")}<span class="frow-l">Aufgabe erledigt</span><span class="frow-c">${toggle(OS.done, `data-change="ix-out-ev" data-v="done"`, "Bei erledigter Aufgabe")}</span></div>
</div>
${OS.error ? `<div class="ix-res red">${icon("info")}<span>${esc(OS.error)}</span></div>` : ""}
<div class="ixs-test"><button type="button" class="btn sm" data-act="ix-out-test">${icon("send")}<span>Test senden</span></button>${OS.id ? `<button type="button" class="btn sm danger" data-act="ix-out-del">${icon("trash")}<span>Entfernen</span></button>` : ""}</div>
<p class="fine">Gesendet werden Titel, Notiz, Datum, Uhrzeit, Taschenname, Priorität und Status – nur von dem Gerät, auf dem du die Aufgabe anlegst oder abhakst. Aufgaben aus dem Briefkasten lösen nichts aus (kein Ping-Pong).</p>
</div>`;
}
function outSave() {
  try {
    const on = [OS.add ? "add" : "", OS.done ? "done" : ""].filter(Boolean);
    if (OS.id) {
      const u = I.webUrl(OS.url);
      if (!u || !u.startsWith("https://")) throw new Error("Bitte eine https://-Adresse eintragen.");
      if (!on.length) throw new Error("Wähle mindestens ein Ereignis.");
      store.updateAccount(OS.id, { name: OS.name.trim() || new URL(u).hostname, secret: u, host: new URL(u).hostname, on });
    } else I.addOutHook(store, { url: OS.url, name: OS.name, on });
    getSheet("ix-out")?.close();
    haptic();
    toast("Webhook gespeichert", { icon: "send", sub: "Bei neuen und erledigten Aufgaben geht eine Nachricht raus" });
  } catch (e) {
    OS.error = e.message;
    getSheet("ix-out")?.refresh();
  }
}
function outMenu(id, el) {
  const a = store.account(id);
  if (!a) return;
  openMenu(
    [
      { label: "Test senden", icon: "send", run: () => I.testHook(a.secret).then(() => toast("Test gesendet", { icon: "send", sub: "In Zapier/Make sollte er gleich auftauchen" })) },
      { label: "Bearbeiten …", icon: "pencil", run: () => openOutSheet(id) },
      "-",
      { label: "Entfernen", icon: "trash", danger: true, run: () => (store.removeAccount(id), toast("Webhook entfernt", { icon: "checkCircle" })) },
    ],
    { el, title: a.name || a.host },
  );
}

// =====================================================================================================================
// Excel & CSV
// =====================================================================================================================
function exportMenu(el) {
  const all = store.tasks();
  const open = all.filter((t) => !t.done);
  const bags = store.bags();
  openMenu(
    [
      { label: "Offene Aufgaben", hint: n(open.length, "Aufgabe", "Aufgaben"), icon: "checklist", run: () => doExport(open, "offen"), disabled: !open.length },
      { label: "Alle Aufgaben", hint: `${n(all.length, "Aufgabe", "Aufgaben")}, auch erledigte`, icon: "table", run: () => doExport(all, "alle"), disabled: !all.length },
      { label: "Eine Tasche …", icon: "bag", disabled: !bags.length, sub: bags.map((b) => ({ label: b.name, emoji: b.emoji, hint: n(store.tasksOf(b.id).length, "Aufgabe", "Aufgaben"), run: () => doExport(store.tasksOf(b.id), b.name) })) },
    ],
    { el, title: "Als Excel/CSV exportieren" },
  );
}
function doExport(tasks, tag) {
  try {
    const bagsById = Object.fromEntries(store.bags().map((b) => [b.id, b]));
    const csv = I.exportCSV(tasks, { bagsById });
    const name = `arbeitstaschen-${String(tag).toLowerCase().replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/ß/g, "ss").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "aufgaben"}-${today()}.csv`;
    remind
      .deliverFile(name, "text/csv", csv)
      .then((how) => toast(how === "shared" ? "Tabelle geteilt" : "Tabelle gespeichert", { icon: "table", sub: `${n(tasks.length, "Aufgabe", "Aufgaben")} · ${name}` }))
      .catch((e) => toastError(e));
  } catch (e) {
    toastError(e, "Export");
  }
}

const CS = { name: "", parsed: null, map: null, bagMode: "inbox", bagId: "", skipDone: true, busy: false, mapOpen: false };
let csvMemo = { key: "", res: null };
async function csvFile(file) {
  if (!file) return;
  if (file.size > 8 * 1024 * 1024) return toast("Die Datei ist zu groß", { icon: "info", tone: "red", sub: "Höchstens 8 MB" });
  try {
    const text = I.decodeText(new Uint8Array(await file.arrayBuffer()));
    const parsed = I.parseCSV(text);
    if (!parsed.headers.length || !parsed.rows.length) throw new Error("In der Datei stehen keine Zeilen – ist es wirklich eine CSV-Datei?");
    const map = I.mapColumns(parsed.headers);
    if (map.title < 0) map.title = 0;
    Object.assign(CS, { name: file.name, parsed, map, bagMode: map.bag >= 0 ? "column" : "inbox", bagId: "", skipDone: true, busy: false, mapOpen: false });
    csvMemo = { key: "", res: null };
    openSheet({ key: "ix-csv", label: "CSV importieren", size: "large", render: csvView });
  } catch (e) {
    toastError(e, "Import");
  }
}
function csvResult() {
  const key = JSON.stringify([CS.map, CS.bagMode, CS.bagId, CS.skipDone, CS.name, store.bags().length]);
  if (csvMemo.key !== key) csvMemo = { key, res: I.csvTasks(CS.parsed, CS.map, { bagMode: CS.bagMode, bagId: CS.bagId || null, bags: store.bags(), skipDone: CS.skipDone, now: new Date(), profile: store.get().profile }) };
  return csvMemo.res;
}
function csvView() {
  if (!CS.parsed) return `${sheetHead("CSV importieren")}<div class="sheet-pad"><p class="muted">Keine Datei gewählt.</p></div>`;
  const H = CS.parsed.headers;
  const res = csvResult();
  const fields = ["title", "due", "time", "notes", "prio", "bag", "section", "tags", "done"];
  const sel = (k) => `<select data-change="ix-csv-map" data-k="${k}" aria-label="Spalte für ${esc(I.COLUMN_LABELS[k])}"><option value="-1"${CS.map[k] < 0 ? " selected" : ""}>${k === "title" ? "– bitte wählen –" : "–"}</option>${H.map((h, i) => `<option value="${i}"${CS.map[k] === i ? " selected" : ""}>${esc(h || `Spalte ${i + 1}`)}</option>`).join("")}</select>`;
  const bags = store.bags();
  const target = `<select data-change="ix-csv-target" aria-label="Zieltasche"><option value="inbox"${CS.bagMode === "inbox" ? " selected" : ""}>📥 Eingang</option>${CS.map.bag >= 0 ? `<option value="column"${CS.bagMode === "column" ? " selected" : ""}>Tasche aus Spalte „${esc(H[CS.map.bag] || "")}“</option>` : ""}${bags.map((b) => `<option value="b:${esc(b.id)}"${CS.bagMode === "fixed" && CS.bagId === b.id ? " selected" : ""}>${esc(b.emoji)} ${esc(b.name)}</option>`).join("")}</select>`;
  const prev = res.tasks.slice(0, 6);
  const prio = ["", "!", "!!", "!!!"];
  const bagName = (t) => (t.bag ? store.bag(t.bag)?.name : t.bagName ? `${t.bagName} (neu)` : CS.bagMode === "inbox" ? "" : "");
  const k = res.tasks.length;
  const mapOpen = CS.mapOpen || CS.map.title < 0 || !k;
  const mapped = fields.filter((f) => CS.map[f] >= 0).map((f) => `${I.COLUMN_LABELS[f]} ← ${H[CS.map[f]] || "?"}`).slice(0, 4).join(" · ") || "noch nichts zugeordnet";
  return `${sheetHead("CSV importieren", { sub: CS.name, left: `<button type="button" class="btn-text" data-act="sheet-close">Abbrechen</button>`, right: `<button type="button" class="btn-text bold" data-act="ix-csv-go"${k && !CS.busy ? "" : " disabled"}>Importieren</button>` })}
<div class="sheet-pad ixs">
<div class="ixs-prov"><span class="ix-gi teal big">${icon("table")}</span><div><b>${esc(I.FORMAT_LABELS[CS.map.format] || "CSV")} erkannt</b><small>${n(CS.parsed.rows.length, "Zeile", "Zeilen")} · ${n(H.length, "Spalte", "Spalten")} · Trennzeichen „${CS.parsed.sep === "\t" ? "Tab" : esc(CS.parsed.sep)}“</small></div></div>
<h4 class="form-h">Ziel</h4>
<div class="card form">
<div class="frow">${sq("bag", "orange")}<span class="frow-l">In Tasche</span><span class="frow-c">${target}</span></div>
<div class="frow">${sq("checkCircle", "green")}<span class="frow-l">Erledigte überspringen</span><span class="frow-c">${toggle(CS.skipDone, `data-change="ix-csv-skip"`, "Erledigte überspringen")}</span></div>
</div>
${res.newBags.length ? `<p class="fine">${icon("info")} Neue ${res.newBags.length === 1 ? "Tasche" : "Taschen"}: ${res.newBags.slice(0, 6).map((x) => `<b>${esc(x)}</b>`).join(", ")}${res.newBags.length > 6 ? " …" : ""}</p>` : ""}
<h4 class="form-h">Vorschau</h4>
${
  prev.length
    ? `<div class="card list ixs-prev">${prev.map((t) => `<div class="ixs-row"><span class="ixs-dot${t.done ? " done" : ""}"></span><span class="ixs-t"><b>${esc(t.title)}</b><span class="task-meta">${t.due ? `<span class="m">${icon("calendar")}${esc(safe(() => dates.relDay(t.due, app.now), t.due))}${t.time ? " " + esc(t.time) : ""}</span>` : ""}${t.prio ? `<span class="m red">${esc(prio[t.prio])}</span>` : ""}${bagName(t) ? `<span class="m">${icon("bag")}${esc(bagName(t))}</span>` : ""}${t.section ? `<span class="m">${esc(t.section)}</span>` : ""}${t.notes ? `<span class="m">${icon("note")}</span>` : ""}</span></span></div>`).join("")}${k > prev.length ? `<div class="ixs-more">+ ${k - prev.length} weitere</div>` : ""}</div>`
    : `<p class="muted center">Keine Aufgaben – ist die Spalte „Titel“ richtig gewählt?</p>`
}
<button type="button" class="btn primary wide" data-act="ix-csv-go"${k && !CS.busy ? "" : " disabled"}>${icon("download")}<span>${k === 1 ? "1 Aufgabe importieren" : `${k} Aufgaben importieren`}</span></button>
<div class="card form ixs-map${mapOpen ? " open" : ""}"><button type="button" class="frow btnrow" data-act="ix-csv-cols" aria-expanded="${mapOpen}">${sq("table", "teal")}<span class="frow-l">Spalten zuordnen<small>${esc(mapped)}</small></span><span class="frow-c">${icon(mapOpen ? "chevronUp" : "chevronDown")}</span></button>${mapOpen ? fields.map((f) => `<div class="frow"><span class="frow-l">${esc(I.COLUMN_LABELS[f])}${f === "title" ? ` <i class="req">Pflicht</i>` : ""}</span><span class="frow-c">${sel(f)}</span></div>`).join("") : ""}</div>
<p class="fine">Nichts wird überschrieben – es kommen nur neue Aufgaben dazu. Danach kannst du alles mit einem Tipp rückgängig machen.</p>
</div>`;
}
function csvImport() {
  if (CS.busy || !CS.parsed) return;
  const res = csvResult();
  if (!res.tasks.length) return;
  CS.busy = true;
  const made = { tasks: [], bags: [] };
  const cols = ["blue", "orange", "green", "purple", "teal", "pink", "indigo", "red", "mint", "brown"];
  try {
    store.batch("CSV-Import", () => {
      const byName = new Map();
      res.newBags.forEach((name, i) => {
        const b = store.addBag({ name, emoji: "📁", color: cols[(store.bags().length + i) % cols.length] });
        made.bags.push(b.id);
        byName.set(dates.normName(name), b.id);
      });
      for (const t of res.tasks) {
        const { bagName, ...data } = t;
        const bag = t.bag || (bagName ? byName.get(dates.normName(bagName)) : null) || null;
        made.tasks.push(store.addTask({ ...data, bag, src: { kind: "import", via: I.FORMAT_LABELS[CS.map.format] || "CSV" } }).id);
      }
    });
  } catch (e) {
    CS.busy = false;
    return toastError(e, "Import");
  }
  CS.busy = false;
  getSheet("ix-csv")?.close();
  haptic();
  sound("done");
  toastUndo(`${n(made.tasks.length, "Aufgabe", "Aufgaben")} importiert`, {
    icon: "table",
    sub: made.bags.length ? `${n(made.bags.length, "neue Tasche", "neue Taschen")} angelegt` : CS.bagMode === "inbox" ? "im Eingang" : "",
    undo: () =>
      store.batch("Import rückgängig", () => {
        made.tasks.forEach((id) => store.removeTask(id));
        made.bags.forEach((id) => store.removeBag(id));
      }),
  });
}

// =====================================================================================================================
// Start: Briefkasten abholen (Toast „2 neue Aufgaben von Siri“), Webhooks senden
// =====================================================================================================================
let started = false;
export function start() {
  if (started) return;
  started = true;
  I.onInbox((r) => {
    const msg = I.inboxToast(r);
    if (!msg) return;
    sound("soft");
    const titles = r.added.slice(0, 2).map((t) => t.title).join(" · ");
    toast(msg, { icon: "inboxIn", sub: titles + (r.added.length > 2 ? " …" : ""), ms: 5200, action: app.route.view === "eingang" ? null : { label: "Ansehen", fn: () => app.go("#eingang") } });
    app.render();
  });
  I.start(store);
}

// =====================================================================================================================
// Ereignisse
// =====================================================================================================================
const setField = (path, v) => {
  const [o, f] = path.split(".");
  const obj = { FS, MS, OS }[o];
  if (obj && f in obj) obj[f] = v;
};
on("input", {
  "ix-in": (el) => {
    setField(el.dataset.f, el.value);
    if (el.dataset.f === "FS.url") {
      FS.result = null;
      FS.error = "";
    }
  },
});
on("keydown", {
  "ix-imap-enter": (el, e) => {
    if (e.key === "Enter" && !e.isComposing) {
      e.preventDefault();
      setField(el.dataset.f, el.value);
      imapSave();
    }
  },
});
on("change", {
  "ix-out-ev": (el) => {
    OS[el.dataset.v] = el.checked;
    haptic();
  },
  "ix-csv-file": (el) => {
    const f = el.files?.[0];
    el.value = "";
    csvFile(f);
  },
  "ix-csv-map": (el) => {
    CS.map = { ...CS.map, [el.dataset.k]: Number(el.value) };
    if (el.dataset.k === "bag") CS.bagMode = CS.map.bag >= 0 ? "column" : CS.bagMode === "column" ? "inbox" : CS.bagMode;
    getSheet("ix-csv")?.refresh();
  },
  "ix-csv-target": (el) => {
    const v = el.value;
    if (v.startsWith("b:")) Object.assign(CS, { bagMode: "fixed", bagId: v.slice(2) });
    else Object.assign(CS, { bagMode: v, bagId: "" });
    getSheet("ix-csv")?.refresh();
  },
  "ix-csv-skip": (el) => {
    CS.skipDone = el.checked;
    getSheet("ix-csv")?.refresh();
  },
});
on("click", {
  "ix-off": (el) => offInfo(el.dataset.f || "feeds"),
  "ix-guide": (el) => guideToggle(el.dataset.k),
  "ix-card-hide": () => {
    setPref("ixCard", "hidden");
    app.render();
  },
  // Kalender-Link
  "ix-feed-add": (el) => (can("feeds") === false ? offInfo("feeds") : openFeedSheet({ preset: el.dataset.v || "" })),
  "ix-feed-src": (el) => {
    FS.src = el.dataset.v;
    refreshFeed();
  },
  "ix-feed-preset": (el) => {
    const p = I.PUBLIC_FEEDS.find((x) => x.id === el.dataset.v);
    if (!p) return;
    Object.assign(FS, { name: p.name, url: p.url, color: p.color, result: null, error: "" });
    refreshFeed();
    feedTest();
  },
  "ix-feed-color": (el) => {
    FS.color = el.dataset.v;
    haptic();
    refreshFeed();
  },
  "ix-feed-test": () => feedTest(),
  "ix-feed-save": () => feedSave(),
  "ix-feed": (el) => feedMenu(el.dataset.id, el),
  // IMAP
  "ix-imap-add": (el) => openImapSheet(el.dataset.p),
  "ix-imap-pick": (el) => {
    const p = I.mailProvider(el.dataset.p);
    if (!p) return;
    Object.assign(MS, { provider: p.id, host: p.host, port: String(p.port), label: p.id === "other" ? "" : p.name, adv: p.id === "other", error: "" });
    refreshImap();
  },
  "ix-imap-back": () => {
    Object.assign(MS, { provider: null, error: "" });
    refreshImap();
  },
  "ix-imap-adv": () => {
    MS.adv = true;
    refreshImap();
  },
  "ix-imap-save": () => imapSave(),
  "ix-imap": (el) => imapMenu(el.dataset.id, el),
  // Briefkasten
  "ix-hook-create": () => hookCreate(),
  "ix-hook-copy": () => {
    const a = inbox();
    if (a) copyText(I.hookUrl(a), "Adresse kopiert");
  },
  "ix-hook-show": () => {
    setPref("ixShowUrl", !prefs.ixShowUrl);
    app.render();
  },
  "ix-hook-test": () => hookTest(),
  "ix-hook-menu": (el) => hookMenu(el),
  "ix-pull": (el) => pull({ force: true, mails: el.dataset.mails === "1" || !inbox(), quietEmpty: el.dataset.mails === "1" }),
  // Ausgehend
  "ix-out-add": () => openOutSheet(),
  "ix-out": (el) => outMenu(el.dataset.id, el),
  "ix-out-save": () => outSave(),
  "ix-out-test": () => {
    const u = I.webUrl(OS.url);
    if (!u || !u.startsWith("https://")) {
      OS.error = "Bitte zuerst eine https://-Adresse eintragen.";
      return getSheet("ix-out")?.refresh();
    }
    I.testHook(u).then(() => toast("Test gesendet", { icon: "send", sub: "In Zapier/Make sollte er gleich auftauchen" }));
  },
  "ix-out-del": () => {
    if (OS.id) store.removeAccount(OS.id);
    getSheet("ix-out")?.close();
    toast("Webhook entfernt", { icon: "checkCircle" });
  },
  // Excel & CSV
  "ix-csv-export": (el) => exportMenu(el),
  "ix-csv-go": () => csvImport(),
  "ix-csv-cols": () => {
    CS.mapOpen = !CS.mapOpen;
    getSheet("ix-csv")?.refresh();
  },
  // Kontakt-Leiste
  "cx-copy": (el) => copyText(el.dataset.v || "", "Kopiert"),
  "ix-share": (el) => {
    const t = store.task(el.dataset.id);
    if (!t) return;
    I.shareTask(t, { bag: t.bag ? store.bag(t.bag) : null })
      .then((how) => how === "copied" && toast("Als Text kopiert", { icon: "copy", sub: "Jetzt einfügen, wo du willst" }))
      .catch((e) => toastError(e));
  },
  "ix-share-copy": (el) => {
    const t = store.task(el.dataset.id);
    if (t) copyText(I.taskShareText(t, { bag: t.bag ? store.bag(t.bag) : null }), "Als Text kopiert");
  },
});

