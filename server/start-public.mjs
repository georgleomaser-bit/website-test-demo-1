// AKYTEX mit einem Klick öffentlich starten: Server + kostenloser Cloudflare-Tunnel.
// Aufruf per Doppelklick auf „AKYTEX-starten.bat“ (Windows) bzw. „AKYTEX-starten.command“ (Mac)
// oder im Terminal: node server/start-public.mjs
// Ergebnis: eine öffentliche https-Adresse (…trycloudflare.com), über die alle AKYTEX samt Clips nutzen können.
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import crypto from "node:crypto";
import { spawn, execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DATA = path.resolve(process.env.DATA_DIR || path.join(ROOT, "data"));
const BIN = path.join(DATA, "bin");
const PORT = +process.env.PORT || 8080;
fs.mkdirSync(BIN, { recursive: true });

const say = (...a) => console.log(...a);
const line = "─".repeat(64);

// 1) Geheimes Moderations-Passwort einmalig erzeugen und merken
const tokenFile = path.join(DATA, "admin-token.txt");
if (!fs.existsSync(tokenFile)) fs.writeFileSync(tokenFile, crypto.randomBytes(24).toString("hex"), { mode: 0o600 });
process.env.ADMIN_TOKEN ||= fs.readFileSync(tokenFile, "utf8").trim();
process.env.TRUST_PROXY = "1";
process.env.PORT = String(PORT);
process.env.DATA_DIR = DATA;

// 2) Cloudflare-Tunnel-Programm besorgen (einmalig, offizielle Datei von Cloudflare auf GitHub)
function cloudflaredAsset() {
  const arch = os.arch() === "arm64" ? "arm64" : "amd64";
  if (process.platform === "win32") return { file: "cloudflared.exe", url: `cloudflared-windows-${arch === "arm64" ? "amd64" : arch}.exe` };
  if (process.platform === "darwin") return { file: "cloudflared", url: `cloudflared-darwin-${arch}.tgz`, tgz: true };
  return { file: "cloudflared", url: `cloudflared-linux-${arch}` };
}
function onPath(cmd) {
  try {
    execFileSync(process.platform === "win32" ? "where" : "which", [cmd], { stdio: "ignore" });
    return true;
  } catch (_) {
    return false;
  }
}
async function getCloudflared() {
  if (process.env.CLOUDFLARED) return process.env.CLOUDFLARED;
  if (onPath("cloudflared")) return "cloudflared";
  const a = cloudflaredAsset();
  const target = path.join(BIN, a.file);
  if (fs.existsSync(target)) return target;
  say("⬇️  Lade Cloudflare Tunnel herunter (einmalig, ca. 40 MB) …");
  const res = await fetch("https://github.com/cloudflare/cloudflared/releases/latest/download/" + a.url);
  if (!res.ok) throw new Error(`Download fehlgeschlagen (${res.status}). Installiere cloudflared von https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/`);
  const buf = Buffer.from(await res.arrayBuffer());
  if (a.tgz) {
    const tgz = path.join(BIN, "cloudflared.tgz");
    fs.writeFileSync(tgz, buf);
    execFileSync("tar", ["-xzf", tgz, "-C", BIN]);
    fs.rmSync(tgz);
  } else fs.writeFileSync(target, buf);
  fs.chmodSync(target, 0o755);
  return target;
}

function openBrowser(url) {
  const [cmd, args] = process.platform === "win32" ? ["cmd", ["/c", "start", "", url]] : process.platform === "darwin" ? ["open", [url]] : ["xdg-open", [url]];
  try {
    const c = spawn(cmd, args, { stdio: "ignore", detached: true });
    c.on("error", () => {}); // kein Browser-Programm vorhanden: Link steht ja im Fenster
    c.unref();
  } catch (_) {
    /* Browser bitte selbst öffnen */
  }
}

// 2b) KI: Schlüssel aus data/anthropic-key.txt übernehmen und das Anthropic-SDK bei Bedarf einmalig installieren
const keyFile = path.join(DATA, "anthropic-key.txt");
if (!process.env.ANTHROPIC_API_KEY && fs.existsSync(keyFile)) process.env.ANTHROPIC_API_KEY = fs.readFileSync(keyFile, "utf8").trim();
if (process.env.ANTHROPIC_API_KEY && !fs.existsSync(path.join(ROOT, "node_modules", "@anthropic-ai", "sdk"))) {
  say("📦 Installiere die KI-Anbindung (einmalig) …");
  try {
    execFileSync(process.platform === "win32" ? "npm.cmd" : "npm", ["install", "--omit=dev", "--no-audit", "--no-fund"], { cwd: ROOT, stdio: "inherit", shell: process.platform === "win32" });
  } catch (_) {
    say("⚠️  Installation fehlgeschlagen – AKYTEX läuft ohne Sprachmodell weiter.");
  }
}

// 3) Server starten (im selben Prozess)
await import("./akytex-server.mjs");

// 4) Tunnel starten und die öffentliche Adresse herausfischen
let exe;
try {
  exe = await getCloudflared();
} catch (e) {
  say(`\n⚠️  ${e.message}\n   AKYTEX läuft trotzdem lokal: http://localhost:${PORT}`);
  process.exitCode = 1;
}
if (exe) {
  say("🌍 Verbinde mit Cloudflare …");
  const tunnel = spawn(exe, ["tunnel", "--no-autoupdate", "--url", `http://localhost:${PORT}`], { stdio: ["ignore", "pipe", "pipe"] });
  let shown = false;
  const scan = (chunk) => {
    const m = /https:\/\/[a-z0-9-]+\.trycloudflare\.com/.exec(String(chunk));
    if (!m || shown) return;
    shown = true;
    process.env.ALLOWED_HOSTS = new URL(m[0]).host;
    fs.writeFileSync(path.join(DATA, "public-url.txt"), m[0]);
    say(`\n${line}\n  ✅ AKYTEX ist LIVE – mit Clips für alle:\n\n     ${m[0]}\n\n  Diesen Link an Freunde schicken. Er gilt, solange dieses Fenster offen ist.\n  Moderations-Passwort: ${tokenFile}\n  Beenden: dieses Fenster schließen (oder Strg+C).\n${line}\n`);
    setTimeout(() => openBrowser(m[0]), 1500);
  };
  tunnel.stdout.on("data", scan);
  tunnel.stderr.on("data", scan);
  tunnel.on("exit", (code) => {
    say(`\n⚠️  Der Cloudflare-Tunnel wurde beendet (Code ${code}). AKYTEX läuft lokal weiter: http://localhost:${PORT}`);
  });
  const stop = () => {
    tunnel.kill();
    process.exit(0);
  };
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
  setTimeout(() => !shown && say("… das dauert etwas länger als sonst. Prüfe deine Internetverbindung."), 30000);
}
