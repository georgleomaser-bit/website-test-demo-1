// Arbeitstaschen – Installation als App: Hinweis-Karte (iPhone/iPad/Mac) und bebilderte Anleitung
import * as remind from "../remind.js";
import { icon, logo } from "./icons.js";
import { app, on, prefs, setPref, safe, isStandalone } from "./core.js";
import { openSheet, sheetHead } from "./sheet.js";
import { toast } from "./fx.js";

let promptEvent = null;
window.addEventListener("beforeinstallprompt", (e) => {
  e.preventDefault();
  promptEvent = e;
  app.render();
});
window.addEventListener("appinstalled", () => {
  promptEvent = null;
  toast("Installiert", { icon: "checkCircle", sub: "Arbeitstaschen ist jetzt eine App" });
});

const ua = () => navigator.userAgent;
export const isMacSafari = () => /Macintosh/.test(ua()) && navigator.maxTouchPoints < 2 && /Safari/.test(ua()) && !/Chrome|Chromium|Edg|Firefox|OPR/.test(ua());
export function platform() {
  const env = safe(() => remind.env(), {});
  if (env.ipad || (/Macintosh/.test(ua()) && navigator.maxTouchPoints > 1)) return "ipad";
  if (env.ios || /iP(hone|od)/.test(ua())) return "iphone";
  if (env.mac || /Macintosh/.test(ua())) return isMacSafari() ? "mac-safari" : "mac";
  return "other";
}

// ---------- Hinweis-Karte auf „Heute“ ----------
export function installHint() {
  if (isStandalone() || prefs.installHidden || window.top !== window) return "";
  const pf = platform();
  let text = "", btn = "";
  if (pf === "iphone" || pf === "ipad") {
    text = `Tippe auf <b>Teilen</b> ${icon("share")} und dann auf <b>„Zum Home-Bildschirm“</b>. Erst dann gibt’s Mitteilungen, den Zähler am App-Symbol und sicheren Speicher.`;
    btn = `<button type="button" class="btn primary sm" data-act="install-help">${icon("info")}<span>So geht’s</span></button><button type="button" class="btn sm" data-act="ics-daily">${icon("calendarPlus")}<span>Wecker im Kalender</span></button>`;
  } else if (pf === "mac-safari") {
    text = `In Safari: <b>Ablage → Zum Dock hinzufügen</b>. Dann startet Arbeitstaschen wie eine echte Mac-App – mit Mitteilungen.`;
    btn = `<button type="button" class="btn sm" data-act="install-help">${icon("info")}<span>So geht’s</span></button>`;
  } else if (promptEvent) {
    text = "Installiere Arbeitstaschen als App – eigenes Fenster, schneller Start, Mitteilungen.";
    btn = `<button type="button" class="btn primary sm" data-act="install-now">${icon("download")}<span>Installieren</span></button>`;
  } else return "";
  return `<section class="inst" data-key="inst"><div class="inst-logo">${logo()}</div><div class="inst-b"><h3>Als App installieren</h3><p>${text}</p><div class="inst-btns">${btn}</div></div><button type="button" class="rcard-x" data-act="inst-hide" aria-label="Ausblenden">${icon("x")}</button></section>`;
}

// ---------- Anleitung ----------
function steps(pf) {
  if (pf === "iphone" || pf === "ipad")
    return [
      ["share", `Öffne diese Seite in <b>Safari</b> und tippe auf <b>Teilen</b> (${pf === "ipad" ? "oben rechts" : "unten in der Mitte"}).`],
      ["squarePlus", `Wähle <b>„Zum Home-Bildschirm“</b> – ggf. etwas nach unten scrollen.`],
      ["check", `Lass <b>„Als Web-App öffnen“</b> eingeschaltet und tippe auf <b>Hinzufügen</b>.`],
      ["bell", `Öffne <b>Taschen</b> vom Home-Bildschirm und erlaube Mitteilungen in den Einstellungen.`],
    ];
  if (pf === "mac-safari" || pf === "mac")
    return [
      ["dock", `Öffne die Seite in <b>Safari</b> (macOS Sonoma oder neuer).`],
      ["squarePlus", `Menü <b>Ablage → Zum Dock hinzufügen …</b> und bestätigen.`],
      ["bell", `Starte <b>Taschen</b> aus dem Dock und erlaube Mitteilungen.`],
      ["link", `Links aus Kalender und Kurzbefehlen öffnen dann direkt die App.`],
    ];
  return [
    ["download", `In Chrome oder Edge: Symbol <b>Installieren</b> in der Adressleiste.`],
    ["phone", `Auf Android: Menü <b>⋮ → App installieren</b>.`],
    ["bell", `Danach Mitteilungen in den Einstellungen erlauben.`],
  ];
}

export function openInstallHelp() {
  const pf = platform();
  const tabs = [["iphone", "iPhone"], ["ipad", "iPad"], ["mac", "Mac"]];
  let cur = pf === "mac-safari" ? "mac" : pf === "other" ? "iphone" : pf;
  const view = () => `${sheetHead("Als App installieren", { sub: "Einmal einrichten, fertig" })}
<div class="sheet-pad inst-help">
<div class="inst-tabs">${tabs.map(([id, l]) => `<button type="button" class="chip${cur === id ? " on" : ""}" data-act="inst-tab" data-v="${id}">${icon(id === "mac" ? "laptop" : "phone")}<span>${l}</span></button>`).join("")}</div>
<div class="inst-art inst-${cur}" aria-hidden="true"><div class="ia-dev"><div class="ia-screen"><div class="ia-app">${logo()}</div><div class="ia-bar">${cur === "mac" ? `<span class="ia-menu">Ablage › <b>Zum Dock hinzufügen …</b></span>` : `<span class="ia-share">${icon("share")}</span>`}</div></div></div></div>
<ol class="inst-steps">${steps(cur).map(([ic, t], i) => `<li><span class="is-n">${i + 1}</span><span class="is-ic">${icon(ic)}</span><span class="is-t">${t}</span></li>`).join("")}</ol>
<div class="note-box">${icon("info")}<span>${cur === "mac" ? "Auf dem Mac öffnen Links aus Kalender und Kurzbefehlen die Dock-App direkt." : "Wichtig: Die installierte App hat ihren eigenen Speicher. Daten aus einem Safari-Tab holst du per Sync oder Backup hinüber."}</span></div>
${promptEvent ? `<button type="button" class="btn primary wide" data-act="install-now">${icon("download")}<span>Jetzt installieren</span></button>` : ""}
</div>`;
  const sh = openSheet({ key: "install", label: "Als App installieren", render: view });
  on("click", {
    "inst-tab": (el) => {
      cur = el.dataset.v;
      sh.refresh();
    },
  });
}

on("click", {
  "inst-hide": () => {
    setPref("installHidden", true);
    app.render();
  },
  "install-now": async () => {
    if (!promptEvent) return openInstallHelp();
    try {
      promptEvent.prompt();
      await promptEvent.userChoice;
    } catch (_) {
      /* abgebrochen */
    }
    promptEvent = null;
    app.render();
  },
});

export const canPromptInstall = () => !!promptEvent;
