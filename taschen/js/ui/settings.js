// Arbeitstaschen – Einstellungen: Profil, Tagesrhythmus, Erinnerungen, Apple Erinnerungen, Sync auf allen Geräten, KI, Darstellung, Daten
import * as store from "../store.js";
import * as dates from "../dates.js";
import * as remind from "../remind.js";
import * as sync from "../sync.js";
import * as ai from "../ai.js";
import { BRAND, COLORS, COLOR_NAMES, SERVER } from "../config.js";
import { esc, fmtSize } from "../util.js";
import { icon } from "./icons.js";
import { app, on, safe, prefs, setPref, colorVars, relTime, today, isStandalone, modKey } from "./core.js";
import { seg, toggle, sq, largeTitle } from "./components.js";
import { confirmBox, chooseBox } from "./sheet.js";
import { haptic, toast, toastError, confetti } from "./fx.js";
import { exportCalendar } from "./today.js";
import { platform } from "./install.js";
import { checkAvail } from "./connectui.js";
import { isPage, renderPage, settingsEntry } from "./integrationsui.js";

const WD = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"];
const WD_LONG = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"];
const SHORTCUT = "Taschen → Erinnerungen";

// Zustand nur für diese Ansicht
const ui = { code: "", codeShown: false, joining: false, joinCode: "", server: "", busy: "", push: null, persisted: null, estimate: null, aiAvail: false, aiOn: false, checked: false };

export function title(r) {
  return isPage(r) ? "Verbindungen" : "Einstellungen";
}

// Asynchrone Infos einmal pro Öffnen nachladen
let infoBusy = false;
export async function refreshInfo() {
  if (infoBusy) return;
  infoBusy = true;
  try {
    ui.persisted = navigator.storage?.persisted ? await navigator.storage.persisted() : null;
    ui.estimate = navigator.storage?.estimate ? await navigator.storage.estimate() : null;
  } catch (_) {
    /* Speicher-API fehlt */
  }
  try {
    const st = sync.status();
    ui.server ||= st.server || app.server || SERVER.url || "";
    if (st.enabled) {
      const kv = await store.kvGet("sync");
      ui.code = kv?.code || "";
    }
  } catch (_) {
    /* kein Sync */
  }
  try {
    const srv = app.server || sync.status().server;
    if (srv) ui.push = await remind.pushState(srv);
  } catch (_) {
    ui.push = null;
  }
  try {
    const kv = await store.kvGet("ai");
    ui.aiOn = !!kv?.enabled;
  } catch (_) {
    /* egal */
  }
  ui.aiAvail = !!app.aiAvailable;
  await checkAvail(true).catch(() => {});
  ui.checked = true;
  infoBusy = false;
  app.render();
}

// ---------- Bausteine ----------
const group = (id, title, rows, foot = "") => `<section class="set" id="set-${id}" data-key="set-${id}"><h3 class="set-h">${esc(title)}</h3><div class="card form">${rows.filter(Boolean).join("")}</div>${foot ? `<p class="set-foot">${foot}</p>` : ""}</section>`;
const inputRow = (ic, col, label, control, sub = "") => `<label class="frow input">${sq(ic, col)}<span class="frow-l">${esc(label)}${sub ? `<small>${sub}</small>` : ""}</span><span class="frow-c">${control}</span></label>`;
const ctlRow = (ic, col, label, control, sub = "") => `<div class="frow">${sq(ic, col)}<span class="frow-l">${esc(label)}${sub ? `<small>${sub}</small>` : ""}</span><span class="frow-c">${control}</span></div>`;
const btnRow = (ic, col, label, act, { sub = "", attrs = "", right = "", danger = false } = {}) => `<button type="button" class="frow btnrow${danger ? " danger" : ""}" data-act="${act}" ${attrs}>${sq(ic, col)}<span class="frow-l">${esc(label)}${sub ? `<small>${sub}</small>` : ""}</span><span class="frow-c">${right}${icon("chevronRight")}</span></button>`;
const opt = (v, l, sel) => `<option value="${esc(v)}"${sel ? " selected" : ""}>${esc(l)}</option>`;

// ---------- Ansicht ----------
export function render(r) {
  if (isPage(r)) return renderPage(r); // Unterseite „Verbindungen“ (#einstellungen/verbindungen)
  const s = store.get();
  const p = s.profile;
  const env = safe(() => remind.env(), {});
  const perm = safe(() => remind.permission(), "unsupported");
  const sy = safe(() => sync.status(), { enabled: false, state: "off" });
  if (!ui.checked) setTimeout(refreshInfo, 0);
  const pf = platform();
  let h = largeTitle("Einstellungen", { sub: `${esc(BRAND.name)} · Version ${esc(BRAND.version)}`, key: "lt-set" });

  // Verbindungen: Kalender, E-Mail, Nachrichten, Siri & Zapier, Excel – ganz oben
  h += safe(() => settingsEntry(), "");

  // Profil
  h += group("profil", "Profil", [inputRow("person", "blue", "Name", `<input type="text" class="in-text" value="${esc(p.name || "")}" placeholder="Wie soll ich dich nennen?" data-change="set-name" data-key-act="blur-enter" autocomplete="given-name" enterkeyhint="done" />`)]);


  // Tagesrhythmus
  h += group("rhythmus", "Tagesrhythmus", [
    inputRow("sunrise", "orange", "Tagesbriefing", `<input type="time" class="in-time" value="${esc(p.dayStart || "08:00")}" data-change="set-prof" data-f="dayStart" />`, "Arbeitsbeginn & Morgen-Erinnerung"),
    inputRow("sunset", "indigo", "Feierabend", `<input type="time" class="in-time" value="${esc(p.dayEnd || "18:00")}" data-change="set-prof" data-f="dayEnd" />`, "Tagesabschluss"),
    `<div class="frow col">${sq("calendar", "red")}<span class="frow-l">Arbeitstage</span><div class="days">${[1, 2, 3, 4, 5, 6, 0].map((d) => `<button type="button" class="day${(p.workdays || []).includes(d) ? " on" : ""}" data-act="set-day" data-d="${d}" aria-pressed="${(p.workdays || []).includes(d)}">${WD[d]}</button>`).join("")}</div></div>`,
    ctlRow("target", "pink", "Fokus pro Tag", seg([1, 2, 3, 4, 5].map((n) => ({ id: String(n), label: String(n) })), String(p.focusCount || 3), { act: "set-focus", cls: "mini", label: "Fokus-Anzahl" })),
    ctlRow("calendar", "teal", "Wochenstart", seg([{ id: "1", label: "Montag" }, { id: "0", label: "Sonntag" }], String(p.weekStart ?? 1), { act: "set-weekstart", cls: "mini", label: "Wochenstart" })),
    inputRow("chart", "purple", "Wochenrückblick", `<select data-change="set-prof-num" data-f="reviewDay">${[1, 2, 3, 4, 5, 6, 0].map((d) => opt(String(d), WD_LONG[d], (p.reviewDay ?? 5) === d)).join("")}</select>`),
  ]);

  // Erinnerungen
  const permTxt = { granted: "Erlaubt", denied: "Blockiert", default: "Noch nicht erlaubt", unsupported: env.ios && !env.standalone ? "Nur in der installierten App" : "Nicht verfügbar" }[perm] || perm;
  const permBtn = perm === "granted" ? `<button type="button" class="pill" data-act="set-test">Test</button>` : perm === "default" ? `<button type="button" class="pill accent" data-act="enable-notify">Erlauben</button>` : env.ios && !env.standalone ? `<button type="button" class="pill accent" data-act="install-help">Installieren</button>` : "";
  const pushOk = ui.push && ui.push.available && ui.push.supported;
  h += group(
    "erinnerungen",
    "Erinnerungen",
    [
      ctlRow("bell", "red", "Mitteilungen", `<span class="status ${perm === "granted" ? "green" : perm === "denied" ? "red" : "gray"}">${esc(permTxt)}</span>${permBtn}`),
      ctlRow("sunrise", "orange", "Morgen-Briefing", toggle(p.briefing !== false, `data-change="set-bool" data-f="briefing"`, "Morgen-Briefing"), `um ${esc(safe(() => dates.fmtTime(p.dayStart || "08:00"), p.dayStart))} Uhr: was heute ansteht`),
      ctlRow("moon", "indigo", "Feierabend-Erinnerung", toggle(p.evening !== false, `data-change="set-bool" data-f="evening"`, "Feierabend"), `um ${esc(safe(() => dates.fmtTime(p.dayEnd || "18:00"), p.dayEnd))} Uhr, wenn noch etwas offen ist`),
      inputRow("clock", "blue", "Standard-Erinnerung", `<select data-change="set-prof-num" data-f="defaultRemind">${[0, 5, 10, 15, 30, 60, 120].map((m) => opt(String(m), m ? (m >= 60 ? `${m / 60} Std. vorher` : `${m} Min. vorher`) : "Zum Termin", (p.defaultRemind ?? 15) === m)).join("")}</select>`, "für Aufgaben mit Uhrzeit"),
      ctlRow("squarePlus", "red", "Zähler am App-Symbol", `<span class="status ${env.badge && perm === "granted" ? "green" : "gray"}">${env.badge ? (perm === "granted" ? "Aktiv" : "Braucht Mitteilungen") : "Nicht verfügbar"}</span>`, "überfällig + heute fällig"),
      btnRow("calendarPlus", "red", "Tagesbriefing in den Kalender", "ics-daily", { sub: "plus alle Termine mit Weckern – klingelt auch bei geschlossener App" }),
      btnRow("calendar", "orange", "Alle Termine in den Kalender", "set-ics-tasks", { sub: `${store.tasks().filter((t) => !t.done && t.due).length} Aufgaben mit Datum` }),
      app.server
        ? pushOk
          ? ctlRow("cloud", "cyan", "Push über deinen Server", `${ui.push.subscribed ? `<button type="button" class="pill" data-act="set-push-test">Test</button>` : ""}${toggle(!!ui.push.subscribed, `data-change="set-push"`, "Push")}`, "Erinnerungen auch bei geschlossener App")
          : ctlRow("cloud", "gray", "Push über deinen Server", `<span class="status gray">${ui.push && !ui.push.supported ? "Gerät unterstützt kein Push" : perm !== "granted" ? "Erst Mitteilungen erlauben" : "Server bietet kein Push"}</span>`)
        : "",
    ],
    `Solange die App offen ist, erinnere ich dich direkt. Bei geschlossener App klingeln: <b>Kalender-Wecker</b>, <b>Apple Erinnerungen</b> per Kurzbefehl (unten) oder <b>Push über deinen Server</b>. Auf iPhone und iPad gibt es Mitteilungen nur in der installierten App.`,
  );

  // Apple Erinnerungen & Kurzbefehle
  const tdy = today();
  const todayTasks = store.tasks().filter((t) => !t.done && ((t.due && t.due <= tdy) || t.plan === tdy));
  const dated = store.tasks().filter((t) => !t.done && t.due);
  h += group(
    "apple",
    "Apple Erinnerungen & Kurzbefehle",
    [
      btnRow("checklist", "orange", "Heute in Erinnerungen übernehmen", "set-reminders", { sub: `${todayTasks.length} Aufgaben · öffnet die Kurzbefehle-App`, attrs: `data-v="today"` }),
      btnRow("calendarCheck", "blue", "Alle Termine übernehmen", "set-reminders", { sub: `${dated.length} Aufgaben mit Datum`, attrs: `data-v="all"` }),
      `<div class="frow col guide${prefs.guideOpen ? " open" : ""}"><button type="button" class="guide-t" data-act="set-guide">${sq("wand", "purple")}<span class="frow-l">Kurzbefehl einmalig anlegen<small>2 Minuten, danach klingeln Apple-Erinnerungen nativ</small></span>${icon(prefs.guideOpen ? "chevronUp" : "chevronDown")}</button>${
        prefs.guideOpen
          ? `<ol class="guide-steps">
<li>Öffne die App <b>Kurzbefehle</b> und tippe auf <b>+</b>. Nenne den Kurzbefehl genau <b>„${esc(SHORTCUT)}“</b>.</li>
<li>Füge <b>„Text teilen“</b> hinzu: Eingabe = <i>Kurzbefehl-Eingabe</i>, trennen bei <b>Neue Zeilen</b>.</li>
<li>Füge <b>„Wiederholen mit jedem Objekt“</b> hinzu.</li>
<li>Darin: <b>„Text teilen“</b> mit eigenem Trennzeichen <b>|</b> – Teil 1 ist das Datum, Teil 2 der Titel, Teil 3 die Tasche.</li>
<li>Darin: <b>„Erinnerung hinzufügen“</b> mit Titel = Teil 2, <b>Fällig</b> = Teil 1 (als Datum), Liste nach Wunsch. Optional Notiz = Teil 3.</li>
<li>In den Kurzbefehl-Details <b>„Text“ als Eingabe</b> erlauben. Fertig – tippe hier oben auf „übernehmen“.</li>
</ol><p class="fine">Ehrlich: Auf iPhone und iPad öffnen Links aus anderen Apps (Kalender, Kurzbefehle) Safari – nicht die Home-Bildschirm-App mit deinen Daten. Auf dem Mac öffnen sie die Dock-App direkt.</p>`
          : ""
      }</div>`,
    ],
  );

  // Sync
  const syncState = { off: ["Aus", "gray"], idle: ["Bereit", "green"], syncing: ["Synchronisiere …", "blue"], error: ["Fehler", "red"], offline: ["Offline", "orange"] }[sy.state] || ["–", "gray"];
  const syncRows = [];
  syncRows.push(ctlRow("devices", "cyan", "Status", `<span class="status ${syncState[1]}">${syncState[0]}</span>`, sy.enabled ? (sy.lastSync ? `zuletzt ${esc(relTime(sy.lastSync))}` : "noch nicht synchronisiert") + (sy.error ? ` · <span class="red">${esc(sy.error)}</span>` : "") : "iPhone, iPad und Mac auf dem gleichen Stand"));
  if (!sy.enabled) {
    syncRows.push(inputRow("cloud", "blue", "Server", `<input type="url" class="in-text" value="${esc(ui.server)}" placeholder="https://taschen.…sslip.io" data-input="set-server" data-change="set-server-save" data-key-act="blur-enter" autocapitalize="off" autocorrect="off" inputmode="url" enterkeyhint="done" />`, app.server ? "automatisch gefunden" : "Adresse deines Taschen-Servers"));
    if (ui.joining) {
      syncRows.push(inputRow("key", "orange", "Sync-Code", `<input type="text" class="in-text mono" value="${esc(ui.joinCode)}" placeholder="ABCD-EFGH-…" data-input="set-joincode" autocapitalize="characters" autocorrect="off" spellcheck="false" />`, "vom anderen Gerät"));
      syncRows.push(`<div class="frow btns"><button type="button" class="btn sm" data-act="set-join-cancel">Abbrechen</button><button type="button" class="btn primary sm" data-act="set-join"${ui.busy ? " disabled" : ""}>${ui.busy === "join" ? `<span class="spinner sm"></span>` : icon("link")}<span>Verbinden</span></button></div>`);
    } else {
      syncRows.push(`<div class="frow btns"><button type="button" class="btn sm" data-act="set-join-start">${icon("key")}<span>Ich habe schon einen Code</span></button><button type="button" class="btn primary sm" data-act="set-sync-new"${ui.busy ? " disabled" : ""}>${ui.busy === "new" ? `<span class="spinner sm"></span>` : icon("sync")}<span>Sync einrichten</span></button></div>`);
    }
  } else {
    syncRows.push(ctlRow("cloud", "blue", "Server", `<span class="status gray mono-s">${esc((sy.server || "").replace(/^https?:\/\//, ""))}</span>`));
    syncRows.push(`<div class="frow col">${sq("key", "orange")}<span class="frow-l">Sync-Code<small>Gib ihn auf deinen anderen Geräten ein</small></span>${ui.codeShown && ui.code ? `<div class="code-box"><code>${esc(ui.code)}</code><button type="button" class="btn sm" data-act="set-copy-code">${icon("copy")}<span>Kopieren</span></button></div><p class="fine">Auf dem Mac kopieren, auf dem iPhone einfügen – dank Universeller Zwischenablage. Behandle den Code wie ein Passwort.</p>` : `<button type="button" class="btn sm" data-act="set-show-code">${icon("eye")}<span>Code anzeigen</span></button>`}</div>`);
    syncRows.push(`<div class="frow btns"><button type="button" class="btn sm danger" data-act="set-sync-off">${icon("cloudOff")}<span>Sync ausschalten</span></button><button type="button" class="btn primary sm" data-act="set-sync-now"${sy.state === "syncing" ? " disabled" : ""}>${sy.state === "syncing" ? `<span class="spinner sm"></span>` : icon("refresh")}<span>Jetzt synchronisieren</span></button></div>`);
  }
  h += group("sync", "Sync auf allen Geräten", syncRows, `${icon("shield")} <b>Ende-zu-Ende-verschlüsselt:</b> Der Server sieht nur verschlüsselte Daten. Der Code ist dein Schlüssel – er verlässt deine Geräte nie.`);

  // KI
  if (ui.aiAvail) {
    h += group("ki", "KI-Projektmanager", [ctlRow("sparkle", "purple", "KI-Funktionen", toggle(ui.aiOn, `data-change="set-ai"`, "KI-Funktionen"), "Tagesplan, Schritte zerlegen, Fragen an den PM")], "Läuft über deinen Server mit Claude. Gesendet werden nur Titel, Termine, Prioritäten und Taschennamen – keine Dateien, keine Notizen.");
  }

  // Darstellung
  h += group("darstellung", "Darstellung", [
    `<div class="frow col">${sq("palette", "pink")}<span class="frow-l">Akzentfarbe</span><div class="colors">${Object.keys(COLORS).filter((c) => c !== "gray").map((c) => `<button type="button" class="color${(p.accent || "blue") === c ? " on" : ""}" style="${colorVars(c)}" data-act="set-accent" data-v="${c}" aria-label="${esc(COLOR_NAMES[c])}" title="${esc(COLOR_NAMES[c])}"></button>`).join("")}</div></div>`,
    ctlRow("moon", "indigo", "Modus", seg([{ id: "auto", label: "Auto" }, { id: "light", label: "Hell" }, { id: "dark", label: "Dunkel" }], p.theme || "auto", { act: "set-theme", cls: "mini", label: "Erscheinungsbild" })),
    ctlRow("phone", "gray", "Haptik", toggle(p.haptics !== false, `data-change="set-bool" data-f="haptics"`, "Haptik"), "Fühlbares Feedback beim Abhaken"),
    ctlRow("bell", "orange", "Töne", toggle(p.sounds !== false, `data-change="set-bool" data-f="sounds"`, "Töne"), "Leiser Klang beim Erledigen"),
  ]);

  // Daten
  const est = ui.estimate;
  h += group(
    "daten",
    "Daten",
    [
      `<a class="frow btnrow" href="#einstellungen/verbindungen/datenx">${sq("table", "teal")}<span class="frow-l">Excel & CSV<small>Aufgaben als Tabelle exportieren oder aus Excel, Todoist, Trello, Asana holen</small></span><span class="frow-c">${icon("chevronRight")}</span></a>`,
      btnRow("download", "green", "Backup exportieren", "set-backup", { sub: s.meta?.lastBackup ? `zuletzt ${esc(relTime(s.meta.lastBackup))} · in iCloud Drive sichern` : "Noch nie – am besten jetzt in iCloud Drive sichern" }),
      `<label class="frow btnrow">${sq("upload", "blue")}<span class="frow-l">Backup importieren<small>JSON-Datei aus einem Export</small></span><span class="frow-c">${icon("chevronRight")}</span><input type="file" accept=".json,application/json" class="hidden-file" data-change="set-import" /></label>`,
      ctlRow("lock", ui.persisted ? "green" : "orange", "Dauerhafter Speicher", ui.persisted ? `<span class="status green">Geschützt</span>` : `<button type="button" class="pill accent" data-act="set-persist">Anfordern</button>`, ui.persisted ? "Safari löscht deine Daten nicht automatisch" : isStandalone() ? "Schützt vor automatischem Löschen" : "Installiere die App, damit deine Daten sicher bleiben"),
      est && est.usage != null ? ctlRow("archive", "gray", "Belegter Speicher", `<span class="status gray">${esc(fmtSize(est.usage))}</span>`, `${store.tasks().length} Aufgaben · ${store.files().length} Dateien`) : "",
      btnRow("trash", "red", "Alles löschen", "set-reset", { sub: "Alle Taschen, Aufgaben und Dateien auf diesem Gerät", danger: true }),
    ],
    `Deine Daten liegen lokal auf diesem Gerät (IndexedDB). Ein Backup ist eine JSON-Datei mit allem – auch Dateien.${store.accounts().length ? " Verbindungen kommen aus Sicherheitsgründen ohne Schlüssel hinein (Konten, Kalender-Links, Webhooks) – nach einem Import auf einem neuen Gerät einfach neu verbinden." : ""}`,
  );

  // Über
  h += group("ueber", "Über", [
    btnRow("download", "blue", "Als App installieren", "install-help", { sub: { iphone: "iPhone: Teilen → Zum Home-Bildschirm", ipad: "iPad: Teilen → Zum Home-Bildschirm", "mac-safari": "Mac: Ablage → Zum Dock hinzufügen", mac: "Mac: In Safari Ablage → Zum Dock hinzufügen" }[pf] || "Anleitung für iPhone, iPad und Mac", right: isStandalone() ? `<span class="status green">Installiert</span>` : "" }),
    `<div class="frow col">${sq("keyboard", "gray")}<span class="frow-l">Tastaturkürzel</span><div class="kbd-list"><span><kbd>N</kbd> Neue Aufgabe</span><span><kbd>${modKey()}K</kbd> / <kbd>/</kbd> Suche & Befehle</span><span><kbd>1</kbd>–<kbd>5</kbd> Bereiche</span><span><kbd>${modKey()}Z</kbd> Rückgängig</span><span><kbd>${modKey()}↵</kbd> Speichern & schließen</span><span><kbd>Esc</kbd> Schließen</span></div></div>`,
    ctlRow("info", "gray", "Version", `<span class="status gray">${esc(BRAND.version)}</span>`, "Arbeitstaschen – Dein persönlicher Projektmanager"),
  ], `Keine Werbung, kein Tracking – deine Daten gehören dir.`);

  if (r?.id) {
    setTimeout(() => {
      const t = document.getElementById("set-" + r.id);
      if (t && !t._scrolled) {
        t._scrolled = true;
        window.scrollTo({ top: t.getBoundingClientRect().top + window.scrollY - (app.wide ? 70 : 100), behavior: "smooth" });
      }
    }, 120);
  }
  return `<div class="view view-settings" data-key="view-settings">${h}</div>`;
}

// ---------- Aktionen (auch von außen genutzt) ----------
export function setTheme(theme) {
  store.setProfile({ theme });
  haptic();
}

export async function doBackup() {
  try {
    toast("Backup wird erstellt …", { icon: "download", ms: 1600 });
    const blob = await store.exportBackup({ includeFiles: true });
    const name = `arbeitstaschen-backup-${today()}.json`;
    const how = await remind.deliverFile(name, "application/json", blob);
    store.setMeta({ lastBackup: Date.now() });
    toast(how === "shared" ? "Backup geteilt" : "Backup gespeichert", { icon: "checkCircle", sub: name });
  } catch (e) {
    if (e?.name === "AbortError") return;
    toastError(e, "Backup");
  }
}


async function importFile(file) {
  if (!file) return;
  const mode = await chooseBox({ title: "Backup importieren", text: `„${file.name}“ – zusammenführen behält deine aktuellen Daten, ersetzen überschreibt alles.`, options: [{ label: "Zusammenführen", value: "merge", bold: true }, { label: "Ersetzen", value: "replace", danger: true }] });
  if (!mode) return;
  if (mode === "replace" && !(await confirmBox({ title: "Wirklich ersetzen?", text: "Alle aktuellen Daten auf diesem Gerät werden durch das Backup ersetzt.", ok: "Ersetzen", danger: true }))) return;
  try {
    const r = await store.importBackup(file, { mode });
    toast("Backup importiert", { icon: "checkCircle", sub: `${r?.bags ?? 0} Taschen · ${r?.tasks ?? 0} Aufgaben · ${r?.files ?? 0} Dateien` });
  } catch (e) {
    toastError(e, "Import");
  }
}

function sendReminders(which) {
  const tdy = today();
  const tasks = store.tasks().filter((t) => !t.done && (which === "today" ? (t.due && t.due <= tdy) || t.plan === tdy : !!t.due));
  if (!tasks.length) return toast("Keine passenden Aufgaben", { icon: "info" });
  try {
    const url = remind.remindersShortcutUrl(tasks, { name: SHORTCUT, bagsById: Object.fromEntries(store.bags().map((b) => [b.id, b])), profile: store.get().profile });
    if (url.length > 7800) toast("Sehr viele Aufgaben – evtl. kürzt iOS die Liste", { icon: "info" });
    location.href = url;
  } catch (e) {
    toastError(e);
  }
}

async function startSync(code, join = false) {
  const server = (ui.server || "").trim().replace(/\/+$/, "");
  if (!/^https?:\/\//.test(server)) {
    toast("Bitte die Server-Adresse eintragen", { icon: "cloud", sub: "z. B. https://taschen.1-2-3-4.sslip.io" });
    return false;
  }
  try {
    const chk = await sync.checkServer(server);
    if (!chk || !chk.ok || chk.sync === false) throw new Error("Unter dieser Adresse läuft kein Taschen-Server.");
    await sync.configure({ server, code, join });
    ui.code = code;
    app.server = server;
    checkAvail(true).catch(() => {});
    return true;
  } catch (e) {
    toastError(e, "Sync");
    return false;
  }
}

// ---------- Ereignisse ----------
on("change", {
  "set-name": (el) => store.setProfile({ name: el.value.trim() }),
  "set-prof": (el) => el.value && store.setProfile({ [el.dataset.f]: el.value }),
  "set-prof-num": (el) => store.setProfile({ [el.dataset.f]: Number(el.value) }),
  "set-bool": (el) => {
    store.setProfile({ [el.dataset.f]: el.checked });
    haptic();
  },
  "set-import": (el) => {
    importFile(el.files?.[0]);
    el.value = "";
  },
  "set-push": async (el) => {
    const srv = app.server;
    if (!srv) return;
    try {
      if (el.checked) {
        const ok = await remind.pushSubscribe(srv);
        toast(ok ? "Push ist an" : "Push nicht möglich", { icon: ok ? "bell" : "info", sub: ok ? "Erinnerungen auch bei geschlossener App" : "Mitteilungen erlaubt?" });
      } else {
        await remind.pushUnsubscribe(srv);
        toast("Push ist aus", { icon: "bellOff" });
      }
      ui.push = await remind.pushState(srv);
    } catch (e) {
      toastError(e, "Push");
    }
    app.render();
  },
  "set-server-save": async (el) => {
    const v = el.value.trim();
    if (!v) return;
    try {
      const chk = await sync.checkServer(v);
      if (!chk.ok) throw new Error(chk.error || "Unter dieser Adresse läuft kein Taschen-Server.");
      const base = await sync.setServer(v);
      ui.server = base;
      app.server = base;
      app.aiAvailable = !!(await ai.available(base).catch(() => false));
      toast("Server verbunden", { icon: "cloud", sub: [chk.sync ? "Sync" : "", chk.push ? "Push" : "", chk.ai ? "KI" : "", chk.connect?.google || chk.connect?.microsoft ? "Konten" : ""].filter(Boolean).join(" · ") || base });
      refreshInfo();
    } catch (e) {
      toastError(e, "Server");
    }
  },
  "set-ai": async (el) => {
    ui.aiOn = el.checked;
    try {
      await store.kvSet("ai", { enabled: el.checked });
    } catch (_) {
      /* nur für diese Sitzung */
    }
    app.ai = el.checked && !!app.aiAvailable;
    haptic();
    app.render();
  },
});

on("input", {
  "set-server": (el) => (ui.server = el.value),
  "set-joincode": (el) => (ui.joinCode = el.value),
});

on("click", {
  "set-day": (el) => {
    const d = Number(el.dataset.d);
    const cur = new Set(store.get().profile.workdays || []);
    if (cur.has(d)) cur.delete(d);
    else cur.add(d);
    store.setProfile({ workdays: [...cur].sort() });
    haptic();
  },
  "set-focus": (el) => store.setProfile({ focusCount: Number(el.dataset.v) }),
  "set-weekstart": (el) => store.setProfile({ weekStart: Number(el.dataset.v) }),
  "set-theme": (el) => setTheme(el.dataset.v),
  "set-accent": (el) => {
    store.setProfile({ accent: el.dataset.v });
    haptic();
  },
  "set-test": () => {
    Promise.resolve(safe(() => remind.test()))
      .then(() => toast("Test-Mitteilung gesendet", { icon: "bell" }))
      .catch((e) => toastError(e));
  },
  "set-push-test": () => {
    remind.pushTest(app.server).then(() => toast("Push-Test angefordert", { icon: "bell", sub: "Kommt in wenigen Sekunden" })).catch((e) => toastError(e, "Push"));
  },
  "set-ics-tasks": () => exportCalendar({ daily: false }),
  "set-reminders": (el) => sendReminders(el.dataset.v),
  "set-guide": () => {
    setPref("guideOpen", !prefs.guideOpen);
    app.render();
  },
  "set-backup": () => doBackup(),
  "set-persist": async () => {
    try {
      const ok = await store.requestPersist();
      ui.persisted = ok;
      toast(ok ? "Speicher ist geschützt" : "Nicht gewährt", { icon: ok ? "lock" : "info", sub: ok ? "" : isStandalone() ? "Der Browser hat abgelehnt" : "Installiere die App – dann klappt es" });
    } catch (e) {
      toastError(e);
    }
    app.render();
  },
  "set-reset": async () => {
    if (!(await confirmBox({ title: "Alles löschen?", text: "Alle Taschen, Aufgaben, Notizen, Links und Dateien auf diesem Gerät werden gelöscht. Mach vorher ein Backup!", ok: "Weiter", danger: true }))) return;
    if (!(await confirmBox({ title: "Wirklich alles?", text: "Das lässt sich nicht rückgängig machen.", ok: "Endgültig löschen", danger: true }))) return;
    try {
      try {
        if (sync.status().enabled) await sync.disable();
      } catch (_) {
        /* Sync war aus */
      }
      await store.resetAll();
      try {
        Object.keys(localStorage).filter((k) => k.startsWith("taschen-")).forEach((k) => localStorage.removeItem(k));
      } catch (_) {
        /* kein localStorage */
      }
      location.replace(location.pathname);
    } catch (e) {
      toastError(e);
    }
  },
  "set-sync-new": async () => {
    ui.busy = "new";
    app.render();
    const code = sync.newCode();
    const ok = await startSync(code);
    ui.busy = "";
    if (ok) {
      ui.codeShown = true;
      haptic();
      toast("Sync ist eingerichtet", { icon: "devices", sub: "Gib den Code auf deinen anderen Geräten ein", ms: 5000 });
      setTimeout(() => document.querySelector(".code-box")?.scrollIntoView({ behavior: "smooth", block: "center" }), 150);
    }
    app.render();
  },
  "set-join-start": () => {
    ui.joining = true;
    app.render();
  },
  "set-join-cancel": () => {
    ui.joining = false;
    ui.joinCode = "";
    app.render();
  },
  "set-join": async () => {
    const code = safe(() => sync.normalizeCode(ui.joinCode), null);
    if (!code) {
      toast("Der Code sieht nicht richtig aus", { icon: "key", tone: "red", sub: "24 Zeichen, z. B. ABCD-EFGH-…" });
      return;
    }
    ui.busy = "join";
    app.render();
    const ok = await startSync(code, true);
    ui.busy = "";
    if (ok) {
      ui.joining = false;
      ui.joinCode = "";
      toast("Verbunden", { icon: "devices", sub: "Deine Daten werden abgeglichen" });
    }
    app.render();
  },
  "set-sync-now": () => {
    sync
      .syncNow()
      .then(() => toast("Synchronisiert", { icon: "sync" }))
      .catch((e) => toastError(e, "Sync"));
  },
  "set-show-code": async () => {
    try {
      const kv = await store.kvGet("sync");
      ui.code = kv?.code || ui.code;
    } catch (_) {
      /* egal */
    }
    ui.codeShown = true;
    app.render();
  },
  "set-copy-code": () => {
    navigator.clipboard
      ?.writeText(ui.code)
      .then(() => toast("Code kopiert", { icon: "copy", sub: "Jetzt auf dem anderen Gerät einfügen" }))
      .catch(() => toast("Kopieren nicht möglich", { icon: "info" }));
  },
  "set-sync-off": async () => {
    if (!(await confirmBox({ title: "Sync ausschalten?", text: "Deine Daten bleiben auf diesem Gerät. Andere Geräte bekommen keine Änderungen mehr von hier.", ok: "Ausschalten", danger: true }))) return;
    try {
      await sync.disable();
      ui.code = "";
      ui.codeShown = false;
      toast("Sync ist aus", { icon: "cloudOff" });
    } catch (e) {
      toastError(e);
    }
    app.render();
  },
});

// Beim Verlassen der Einstellungen den Code wieder verbergen
export function leaveSettings() {
  ui.codeShown = false;
  ui.checked = false;
}

