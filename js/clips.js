// AKYTEX Clips: Kurzvideo-Feed für Trader.
// Community-Clips werden live aus Kursdaten gerendert (Canvas), eigene Videos liegen in IndexedDB.
import { analyze } from "./analysis.js";
import { aggregate } from "./market.js";

const f2 = (v) => v.toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
export const CLIP_MS = 12000;

// ---------- IndexedDB ----------
function db() {
  return new Promise((res, rej) => {
    const r = indexedDB.open("akytex", 1);
    r.onupgradeneeded = () => r.result.createObjectStore("clips", { keyPath: "id" });
    r.onsuccess = () => res(r.result);
    r.onerror = () => rej(r.error);
  });
}
export async function idbAll() {
  try {
    const d = await db();
    return await new Promise((res, rej) => {
      const q = d.transaction("clips").objectStore("clips").getAll();
      q.onsuccess = () => res(q.result || []);
      q.onerror = () => rej(q.error);
    });
  } catch (_) {
    return [];
  }
}
export async function idbPut(rec) {
  const d = await db();
  return new Promise((res, rej) => {
    const tx = d.transaction("clips", "readwrite");
    tx.objectStore("clips").put(rec);
    tx.oncomplete = () => res(rec);
    tx.onerror = () => rej(tx.error);
  });
}
export async function idbDel(id) {
  const d = await db();
  return new Promise((res) => {
    const tx = d.transaction("clips", "readwrite");
    tx.objectStore("clips").delete(id);
    tx.oncomplete = () => res();
  });
}

// ---------- Demo-Clips aus Marktdaten ----------
const TEMPLATES = [
  (s, a) => [`${s}: Was jetzt passiert 👀`, `RSI ${f2(a.rsi ?? 50)} – ${a.rsi > 65 ? "heiß gelaufen" : a.rsi < 35 ? "ausverkauft" : "neutral"}`, `Mein Ziel: ${f2(a.setup.tp)} 🎯`],
  (s, a) => [`${s} in 12 Sekunden erklärt`, a.trendUp ? "Über dem 50er-Durchschnitt ✅" : "Unter dem 50er-Durchschnitt ⚠️", `Stop: ${f2(a.setup.sl)} – Risiko klein halten`],
  (s, a) => [`Das Level bei ${s}, das alle beobachten`, `Widerstand ${f2(a.levels.resistance)}`, `Unterstützung ${f2(a.levels.support)}`],
  (s, a) => [`${s}: Ausbruch oder Fake? 🤔`, `Volumen ${f2(a.volRatio)}× Durchschnitt`, a.score > 0 ? "Ich bin Long 🟢" : "Ich warte ab 🔴"],
];
export function demoClips(market, traders) {
  const out = [];
  const syms = ["NVDA", "TSLA", "SAP", "RHM", "AAPL", "META", "ASML", "PLTR", "AMZN", "ALV", "NFLX", "MSFT"];
  syms.forEach((sym, i) => {
    const t = traders[i % traders.length];
    const a = analyze(aggregate(market.get(sym).m1.slice(-60 * 24 * 7), "1h"));
    const caps = TEMPLATES[i % TEMPLATES.length](sym, a);
    out.push({
      id: "gc" + i,
      kind: "gen",
      author: t.id,
      sym,
      title: caps[0],
      captions: caps,
      tags: ["#" + sym.toLowerCase(), i % 2 ? "#trading" : "#aktien", i % 3 ? "#charttechnik" : "#akytex"],
      likes: Math.round(300 + ((i * 7919) % 9000)),
      comments: 12 + ((i * 131) % 180),
      created: Date.now() - (i + 1) * 47 * 60000,
      hue: [220, 265, 200, 30, 285, 330, 190, 150, 240, 45, 0, 210][i],
    });
  });
  return out;
}

// ---------- Canvas-Renderer (9:16) ----------
export function drawClip(ctx, W, H, clip, market, t, authorLabel) {
  const p = Math.min(1, t / CLIP_MS);
  const hue = clip.hue ?? 230;
  // Hintergrund: Weltraum-Verlauf
  const g = ctx.createLinearGradient(0, 0, W, H);
  g.addColorStop(0, `hsl(${hue} 60% 10%)`);
  g.addColorStop(1, `hsl(${(hue + 60) % 360} 55% 6%)`);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, W, H);
  const neb = ctx.createRadialGradient(W * 0.7, H * 0.25, 10, W * 0.7, H * 0.25, W * 0.9);
  neb.addColorStop(0, `hsla(${hue + 40} 90% 60% / .28)`);
  neb.addColorStop(1, "transparent");
  ctx.fillStyle = neb;
  ctx.fillRect(0, 0, W, H);
  for (let i = 0; i < 60; i++) {
    const x = (i * 97.3 + t * 0.004 * ((i % 5) + 1)) % W;
    const y = (i * 151.7) % H;
    ctx.globalAlpha = 0.25 + ((i * 13) % 10) / 20;
    ctx.fillStyle = "#fff";
    ctx.fillRect(x, y, i % 7 === 0 ? 2 : 1, i % 7 === 0 ? 2 : 1);
  }
  ctx.globalAlpha = 1;

  // Chart-Replay (Stundenkerzen der letzten Tage)
  const bars = aggregate(market.get(clip.sym).m1.slice(-60 * 24 * 5), "1h");
  const closes = bars.map((b) => b.close);
  const n = Math.max(2, Math.floor(closes.length * (0.15 + 0.85 * Math.min(1, p * 1.25))));
  const vis = closes.slice(0, n);
  const lo = Math.min(...closes);
  const hi = Math.max(...closes);
  const cx0 = W * 0.08;
  const cw = W * 0.84;
  const cy0 = H * 0.3;
  const ch = H * 0.36;
  const X = (i) => cx0 + (i / (closes.length - 1)) * cw;
  const Y = (v) => cy0 + (1 - (v - lo) / (hi - lo || 1)) * ch;
  const up = vis[vis.length - 1] >= vis[0];
  const col = up ? "#34d399" : "#fb7185";
  ctx.strokeStyle = "rgba(255,255,255,.07)";
  ctx.lineWidth = 1;
  for (let k = 0; k <= 4; k++) {
    ctx.beginPath();
    ctx.moveTo(cx0, cy0 + (ch * k) / 4);
    ctx.lineTo(cx0 + cw, cy0 + (ch * k) / 4);
    ctx.stroke();
  }
  const area = ctx.createLinearGradient(0, cy0, 0, cy0 + ch);
  area.addColorStop(0, up ? "rgba(52,211,153,.35)" : "rgba(251,113,133,.35)");
  area.addColorStop(1, "rgba(0,0,0,0)");
  ctx.beginPath();
  vis.forEach((v, i) => (i ? ctx.lineTo(X(i), Y(v)) : ctx.moveTo(X(i), Y(v))));
  ctx.lineTo(X(vis.length - 1), cy0 + ch);
  ctx.lineTo(X(0), cy0 + ch);
  ctx.fillStyle = area;
  ctx.fill();
  ctx.beginPath();
  vis.forEach((v, i) => (i ? ctx.lineTo(X(i), Y(v)) : ctx.moveTo(X(i), Y(v))));
  ctx.strokeStyle = col;
  ctx.lineWidth = W * 0.008;
  ctx.shadowColor = col;
  ctx.shadowBlur = 18;
  ctx.stroke();
  ctx.shadowBlur = 0;
  const lx = X(vis.length - 1);
  const ly = Y(vis[vis.length - 1]);
  ctx.beginPath();
  ctx.arc(lx, ly, W * 0.016 * (1 + 0.25 * Math.sin(t / 150)), 0, Math.PI * 2);
  ctx.fillStyle = "#fff";
  ctx.fill();

  // Kopf: Symbol & Kurszähler
  ctx.fillStyle = "rgba(255,255,255,.95)";
  ctx.font = `800 ${W * 0.09}px system-ui, sans-serif`;
  ctx.textAlign = "left";
  ctx.fillText(clip.sym, cx0, H * 0.14);
  ctx.font = `700 ${W * 0.06}px system-ui, sans-serif`;
  const shown = vis[vis.length - 1];
  ctx.fillText(`${f2(shown)} €`, cx0, H * 0.2);
  const chg = shown / vis[0] - 1;
  ctx.fillStyle = col;
  ctx.font = `700 ${W * 0.042}px system-ui, sans-serif`;
  ctx.fillText(`${chg >= 0 ? "▲ +" : "▼ "}${f2(chg * 100)} %`, cx0, H * 0.245);

  // Untertitel nacheinander einblenden
  const caps = clip.captions || [clip.title];
  const seg = CLIP_MS / caps.length;
  const ci = Math.min(caps.length - 1, Math.floor(t / seg));
  const local = (t - ci * seg) / seg;
  const alpha = Math.min(1, local * 5) * Math.min(1, (1 - local) * 6 + (ci === caps.length - 1 ? 1 : 0));
  ctx.globalAlpha = Math.max(0, Math.min(1, alpha));
  const text = caps[ci];
  ctx.font = `800 ${W * 0.058}px system-ui, sans-serif`;
  const words = text.split(" ");
  const lines = [];
  let line = "";
  for (const w of words) {
    const test = line ? line + " " + w : w;
    if (ctx.measureText(test).width > W * 0.8) {
      lines.push(line);
      line = w;
    } else line = test;
  }
  lines.push(line);
  const by = H * 0.69;
  lines.forEach((l, k) => {
    const tw = ctx.measureText(l).width;
    const yy = by + k * W * 0.08;
    ctx.fillStyle = "rgba(0,0,0,.55)";
    ctx.beginPath();
    ctx.roundRect ? ctx.roundRect(W / 2 - tw / 2 - W * 0.03, yy - W * 0.058, tw + W * 0.06, W * 0.076, W * 0.02) : ctx.rect(W / 2 - tw / 2 - W * 0.03, yy - W * 0.058, tw + W * 0.06, W * 0.076);
    ctx.fill();
    ctx.fillStyle = "#fff";
    ctx.textAlign = "center";
    ctx.fillText(l, W / 2, yy);
  });
  ctx.globalAlpha = 1;
  ctx.textAlign = "left";
  // Wasserzeichen oben rechts
  ctx.font = `300 ${W * 0.035}px system-ui, sans-serif`;
  ctx.fillStyle = "rgba(255,255,255,.6)";
  ctx.textAlign = "right";
  ctx.fillText("ΛKYTEX", W * 0.92, H * 0.075);
  if (authorLabel) {
    ctx.font = `600 ${W * 0.03}px system-ui, sans-serif`;
    ctx.fillText(authorLabel, W * 0.92, H * 0.105);
  }
  ctx.textAlign = "left";
}

// Chart-Clip als WebM aufnehmen (wo MediaRecorder verfügbar ist)
export function recordClip(clip, market, authorLabel, ms = 8000) {
  return new Promise((resolve, reject) => {
    if (typeof MediaRecorder === "undefined") return reject(new Error("unsupported"));
    const c = document.createElement("canvas");
    c.width = 540;
    c.height = 960;
    const ctx = c.getContext("2d");
    let stream;
    try {
      stream = c.captureStream(30);
    } catch (e) {
      return reject(e);
    }
    const type = ["video/webm;codecs=vp9", "video/webm;codecs=vp8", "video/webm", "video/mp4"].find((t) => MediaRecorder.isTypeSupported?.(t));
    if (!type) return reject(new Error("unsupported"));
    const rec = new MediaRecorder(stream, { mimeType: type, videoBitsPerSecond: 2_500_000 });
    const chunks = [];
    rec.ondataavailable = (e) => e.data.size && chunks.push(e.data);
    rec.onstop = () => resolve(new Blob(chunks, { type: type.split(";")[0] }));
    const t0 = performance.now();
    const frame = () => {
      const t = ((performance.now() - t0) / ms) * CLIP_MS;
      drawClip(ctx, 540, 960, clip, market, t, authorLabel);
      if (performance.now() - t0 < ms) requestAnimationFrame(frame);
      else rec.stop();
    };
    rec.start(250);
    frame();
  });
}
