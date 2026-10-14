#!/usr/bin/env node
/* =====================================================================
 *  AKYTEX TYCOON – Bild-Generator fuer den Roblox-Upload
 *
 *  Zeichnet Thumbnail (1920 x 1080, Deutsch + Englisch) und Spiel-Icon
 *  (512 x 512) im AKYTEX-Look: naechtliche Glas-Skyline, eigener Tower
 *  mit Kran, der gerade eine Etage setzt, das Wahrzeichen "Orbit Spire"
 *  mit Neon-Ring, ein steigender gruener Kerzen-Chart als Hologramm,
 *  Lichtspuren auf der Stadtautobahn und Spiegelung im Wasser.
 *  Alles ist HTML/SVG/CSS und wird mit Playwright (Chromium) fotografiert.
 *  Schriften liegen in ./fonts (SIL OFL 1.1).
 *
 *  Benutzung:
 *    node generate.js              -> alle Bilder neu erzeugen
 *    node generate.js thumbnail    -> nur Bilder, deren Name "thumbnail" enthaelt
 *    node generate.js --out <dir>  -> woanders hinschreiben
 *    node generate.js --html       -> zusaetzlich die HTML-Seiten speichern
 *
 *  Ausgabe: ../ (also vorbereitet/bilder/)
 *
 *  Regeln (docs/KOPIERVORLAGEN.md §4): keine echten Marken, kein
 *  Robux-Symbol, keine Waehrungszeichen, kein Geld-Versprechen, nichts mit
 *  Casino/Wuerfeln/Karten/Gluecksrad, kein "Raytracing". Firmen im Bild
 *  sind die fiktiven Firmen aus dem Spiel.
 * ===================================================================== */
'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { pathToFileURL } = require('url');

function loadPlaywright() {
  try {
    return require('playwright');
  } catch (e) {
    const root = execSync('npm root -g').toString().trim();
    return require(path.join(root, 'playwright'));
  }
}

const FONT_DIR = path.join(__dirname, 'fonts');

// AKYTEX-Farben (wie UI.Theme im Spiel)
const C = {
  bg: '#0b0f17',
  surface: '#121824',
  surface2: '#1a2130',
  border: '#1f2937',
  text: '#e6ecf5',
  text2: '#aab4c3',
  accent: '#4f8cff',
  accentDeep: '#2962ff',
  up: '#22c55e',
  down: '#ef4444',
  warn: '#eab308',
  gold: '#facc15',
};

// ---------------------------------------------------------------------
//  Kleine Helfer
// ---------------------------------------------------------------------
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const r1 = (v) => Math.round(v * 10) / 10;
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const pick = (rand, list) => list[Math.floor(rand() * list.length)];
const lerp = (a, b, t) => a + (b - a) * t;
const smooth = (a, b, x) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};
let UID = 0;
const uid = (p) => `${p}${++UID}`;

// Der ΛKYTEX-Schriftzug aus icons/logo.svg der Website (Strich-Buchstaben)
const WORDMARK_PATHS = [
  'M60 285 L81 227 L102 285',
  'M132 227 V285 M170 227 L134 258 M144 250 L172 285',
  'M200 227 L221 256 L242 227 M221 256 V285',
  'M270 230 H312 M291 230 V285',
  'M377 230 H340 V282 H377 M340 256 H372',
  'M410 227 L452 285 M452 227 L410 285',
];
function wordmarkSvg(width, stroke, color = '#f2f6ff') {
  const vb = [52, 219, 408, 74];
  const h = (width * vb[3]) / vb[2];
  return `<svg class="wordmark" width="${r1(width)}" height="${r1(h)}" viewBox="${vb.join(' ')}" xmlns="http://www.w3.org/2000/svg">
    <defs><filter id="wmGlow" x="-10%" y="-40%" width="120%" height="180%"><feGaussianBlur stdDeviation="3.2" result="b"/>
    <feFlood flood-color="${C.accent}" flood-opacity=".9"/><feComposite in2="b" operator="in" result="g"/>
    <feMerge><feMergeNode in="g"/><feMergeNode in="g"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>
    <g fill="none" stroke="${color}" stroke-width="${stroke}" stroke-linejoin="miter" stroke-linecap="square" filter="url(#wmGlow)">
      ${WORDMARK_PATHS.map((d) => `<path d="${d}"/>`).join('')}
    </g></svg>`;
}

// ---------------------------------------------------------------------
//  Gemeinsame SVG-Defs (Filter, Verlaeufe)
// ---------------------------------------------------------------------
function defs() {
  return `
  <filter id="glowS" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="2.2" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  <filter id="glowM" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  <filter id="glowL" x="-80%" y="-80%" width="260%" height="260%"><feGaussianBlur stdDeviation="14" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  <filter id="bloom" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="60"/></filter>
  <filter id="bloomS" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="28"/></filter>
  <linearGradient id="beam" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="#cfe0ff" stop-opacity=".22"/><stop offset="1" stop-color="#cfe0ff" stop-opacity="0"/></linearGradient>
  <filter id="soft4" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="4"/></filter>
  <filter id="soft1" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="1.1"/></filter>
  <filter id="reflBlur" x="-5%" y="-5%" width="110%" height="110%"><feGaussianBlur stdDeviation="2.6 5"/></filter>
  <linearGradient id="glassSheen" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#ffffff" stop-opacity="0"/><stop offset=".45" stop-color="#cfe0ff" stop-opacity=".16"/>
    <stop offset=".55" stop-color="#cfe0ff" stop-opacity=".05"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
  </linearGradient>
  <linearGradient id="farFace" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#101b38"/><stop offset="1" stop-color="#0a1124"/></linearGradient>
  <linearGradient id="midFace" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#172a52"/><stop offset=".6" stop-color="#0f1b38"/><stop offset="1" stop-color="#0b1430"/></linearGradient>
  <linearGradient id="midSide" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0d1830"/><stop offset="1" stop-color="#070d1e"/></linearGradient>
  <linearGradient id="heroFace" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#18336d"/><stop offset=".38" stop-color="#2a5cc4"/><stop offset=".52" stop-color="#3a6fdc"/>
    <stop offset=".7" stop-color="#1f468f"/><stop offset="1" stop-color="#132a5c"/></linearGradient>
  <linearGradient id="heroSide" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#0d1d44"/><stop offset="1" stop-color="#081230"/></linearGradient>
  <linearGradient id="spireFace" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#15295a"/><stop offset=".45" stop-color="#23468f"/><stop offset=".6" stop-color="#2d58ad"/><stop offset="1" stop-color="#112250"/></linearGradient>
  <linearGradient id="capTop" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5d86d8"/><stop offset="1" stop-color="#2a4688"/></linearGradient>
  <linearGradient id="fadeDown" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="1"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
  <linearGradient id="chartArea" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${C.up}" stop-opacity=".13"/><stop offset="1" stop-color="${C.up}" stop-opacity="0"/></linearGradient>
  <linearGradient id="slabFace" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#2a5cc4"/><stop offset=".5" stop-color="#5a8cf0"/><stop offset="1" stop-color="#2a54b0"/></linearGradient>
  <linearGradient id="deck" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#131c33"/><stop offset="1" stop-color="#060a14"/></linearGradient>`;
}

// ---------------------------------------------------------------------
//  Bausteine
// ---------------------------------------------------------------------

// Quader in leichter Untersicht: Front, Seite (steigt nach rechts), Dachkante
function prism(o) {
  const { x, top, base, w, s, rand } = o;
  const dy = s * 0.3;
  const h = base - top;
  let out = '';
  // Seite
  out += `<polygon points="${x + w},${top} ${x + w + s},${top - dy} ${x + w + s},${base - dy} ${x + w},${base}" fill="${o.side || 'url(#midSide)'}"/>`;
  // Front
  out += `<rect x="${x}" y="${top}" width="${w}" height="${h}" fill="${o.face || 'url(#midFace)'}"/>`;
  // Fenster
  if (o.windows !== false) {
    const cw = o.cw || 11;
    const ch = o.ch || 13;
    const litP = o.litP ?? 0.22;
    const cols = Math.floor((w - 6) / cw);
    const rows = Math.floor((h - 8) / ch);
    const ox = x + (w - cols * cw) / 2;
    let win = '';
    for (let r = 0; r < rows; r++) {
      // ganze Etagen sind manchmal hell (Bueros), sonst einzelne Fenster
      const floorLit = rand() < 0.07;
      for (let c = 0; c < cols; c++) {
        const lit = floorLit ? rand() < 0.8 : rand() < litP;
        if (!lit) continue;
        const k = rand();
        const col = k < 0.62 ? '#a9c6ff' : k < 0.86 ? '#ffd9a0' : C.accent;
        const op = r1(0.35 + rand() * 0.5);
        win += `<rect x="${r1(ox + c * cw + 2)}" y="${r1(top + 6 + r * ch)}" width="${cw - 4}" height="${ch - 6}" fill="${col}" opacity="${op}"/>`;
      }
    }
    out += win;
    // Seitenfenster (schraeg)
    if (s >= 14) {
      const scols = Math.floor((s - 4) / cw);
      let sw = '';
      for (let r = 0; r < rows; r++) {
        for (let c = 0; c < scols; c++) {
          if (rand() > litP * 0.6) continue;
          sw += `<rect x="${r1(3 + c * cw)}" y="${r1(6 + r * ch)}" width="${cw - 5}" height="${ch - 6}" fill="#7fa6ec" opacity="${r1(0.18 + rand() * 0.3)}"/>`;
        }
      }
      out += `<g transform="matrix(1 ${r1(-dy / s * 100) / 100} 0 1 ${x + w} ${top})">${sw}</g>`;
    }
  }
  // Glanzstreifen
  if (o.sheen) out += `<rect x="${x}" y="${top}" width="${w}" height="${h}" fill="url(#glassSheen)"/>`;
  // Dachkante
  out += `<polygon points="${x},${top} ${x + s},${top - dy} ${x + w + s},${top - dy} ${x + w},${top}" fill="${o.cap || '#1d3266'}"/>`;
  // Neon-Kanten
  if (o.neonTop)
    out += `<line x1="${x}" y1="${top + 1.5}" x2="${x + w}" y2="${top + 1.5}" stroke="${o.neonColor || C.accent}" stroke-width="2.5" filter="url(#glowM)"/>`;
  if (o.neonEdge)
    out += `<line x1="${x + w}" y1="${top}" x2="${x + w}" y2="${base}" stroke="${o.neonColor || C.accent}" stroke-width="2" opacity=".85" filter="url(#glowM)"/>`;
  return out;
}

// Antenne mit rotem Flugwarnlicht
function antenna(x, y, len) {
  return `<line x1="${x}" y1="${y}" x2="${x}" y2="${y - len}" stroke="#2a3b66" stroke-width="2"/>
    <circle cx="${x}" cy="${y - len}" r="2.6" fill="#ff4848" filter="url(#glowM)"/>`;
}

// Ferne Skyline-Silhouette (flach, viele kleine Lichter)
function farLayer(rand, W, horizon, heightAt) {
  let out = '';
  let x = -30;
  while (x < W + 30) {
    const w = 34 + rand() * 80;
    const h = heightAt(x) * (0.55 + rand() * 0.6);
    const top = horizon - h;
    out += `<rect x="${r1(x)}" y="${r1(top)}" width="${r1(w)}" height="${r1(h + 2)}" fill="url(#farFace)"/>`;
    // Lichtpunkte
    const cols = Math.floor(w / 9);
    const rows = Math.floor(h / 11);
    for (let r = 1; r < rows; r++)
      for (let c = 0; c < cols; c++)
        if (rand() < 0.1)
          out += `<rect x="${r1(x + 3 + c * 9)}" y="${r1(top + r * 11)}" width="3" height="4" fill="${rand() < 0.75 ? '#6f97e8' : '#e8c48a'}" opacity="${r1(0.25 + rand() * 0.35)}"/>`;
    if (h > 200 && rand() < 0.45) out += antenna(r1(x + w / 2), r1(top), r1(18 + rand() * 40));
    if (rand() < 0.12)
      out += `<line x1="${r1(x)}" y1="${r1(top + 1)}" x2="${r1(x + w)}" y2="${r1(top + 1)}" stroke="${C.accent}" stroke-width="1.6" opacity=".7" filter="url(#glowS)"/>`;
    x += w + rand() * 8 - 2;
  }
  return out;
}

// Kerzen-Chart als Hologramm im Himmel (steigend, ein paar rote Kerzen)
function candleChart(rand, x0, x1, yStart, yEnd, n, opts = {}) {
  const step = (x1 - x0) / (n - 1);
  const bw = Math.max(4, step * 0.46);
  let price = yStart;
  const pts = [];
  let out = '';
  const reds = new Set(opts.reds || [3, 8, 9, 15, 21, 27]);
  for (let i = 0; i < n; i++) {
    const t = i / (n - 1);
    const target = lerp(yStart, yEnd, Math.pow(t, 1.35));
    const isRed = reds.has(i);
    const open = price;
    let close = isRed ? open + (8 + rand() * 18) * (opts.scale || 1) : Math.min(open - 4, target - rand() * 16 * (opts.scale || 1));
    if (!isRed && close > open - 4) close = open - 6;
    const hi = Math.min(open, close) - (5 + rand() * 18) * (opts.scale || 1);
    const lo = Math.max(open, close) + (5 + rand() * 16) * (opts.scale || 1);
    const cx = x0 + i * step;
    const col = isRed ? C.down : C.up;
    out += `<line x1="${r1(cx)}" y1="${r1(hi)}" x2="${r1(cx)}" y2="${r1(lo)}" stroke="${col}" stroke-width="${opts.wick || 2}"/>`;
    out += `<rect x="${r1(cx - bw / 2)}" y="${r1(Math.min(open, close))}" width="${r1(bw)}" height="${r1(Math.max(3, Math.abs(close - open)))}" rx="1.5" fill="${col}"/>`;
    pts.push([cx, close]);
    price = close;
  }
  const line = pts.map((p, i) => `${i ? 'L' : 'M'}${r1(p[0])} ${r1(p[1])}`).join(' ');
  const area = `${line} L${r1(pts[pts.length - 1][0])} ${opts.areaBase || yStart + 80} L${r1(pts[0][0])} ${opts.areaBase || yStart + 80} Z`;
  return {
    svg: `<path d="${area}" fill="url(#chartArea)"/>
      <g filter="url(#glowM)" opacity="${opts.opacity || 0.8}">${out}</g>
      <path d="${line}" fill="none" stroke="#7cf0a4" stroke-width="${opts.lineW || 2.4}" opacity=".85" filter="url(#glowS)"/>`,
    last: pts[pts.length - 1],
  };
}

// Turmdrehkran mit Gitter-Mast; Haken haengt an trolleyX
function crane(o) {
  const { mx, base, top, jl, jr, trolleyX, hookY } = o;
  const yel = C.warn;
  const mw = 14;
  let out = '';
  // Mast (Gitter)
  out += `<rect x="${mx - mw / 2}" y="${top}" width="${mw}" height="${base - top}" fill="none" stroke="${yel}" stroke-width="2"/>`;
  let zig = '';
  for (let y = base; y > top + 8; y -= 14) zig += `M${mx - mw / 2} ${y} L${mx + mw / 2} ${y - 14} M${mx + mw / 2} ${y} L${mx - mw / 2} ${y - 14} `;
  out += `<path d="${zig}" stroke="${yel}" stroke-width="1.1" opacity=".8" fill="none"/>`;
  // Ausleger (Jib) als Dreiecks-Fachwerk
  const jy = top;
  out += `<line x1="${mx - jl}" y1="${jy}" x2="${mx + jr}" y2="${jy}" stroke="${yel}" stroke-width="3"/>`;
  out += `<line x1="${mx - jl}" y1="${jy + 9}" x2="${mx + jr}" y2="${jy + 9}" stroke="${yel}" stroke-width="1.6"/>`;
  let truss = '';
  for (let x = mx - jl; x < mx + jr - 1; x += 16) truss += `M${x} ${jy + 9} L${x + 8} ${jy} L${x + 16} ${jy + 9} `;
  out += `<path d="${truss}" stroke="${yel}" stroke-width="1.1" fill="none" opacity=".85"/>`;
  // Spitze + Abspannseile
  out += `<path d="M${mx - mw / 2} ${jy} L${mx} ${jy - 46} L${mx + mw / 2} ${jy}" stroke="${yel}" stroke-width="2.4" fill="none"/>`;
  out += `<path d="M${mx} ${jy - 46} L${mx - jl * 0.92} ${jy} M${mx} ${jy - 46} L${mx + jr * 0.95} ${jy}" stroke="${yel}" stroke-width="1" opacity=".75" fill="none"/>`;
  // Gegengewicht + Fuehrerhaus
  out += `<rect x="${mx + jr - 46}" y="${jy + 9}" width="40" height="22" rx="2" fill="#3a3f4c" stroke="#59606e" stroke-width="1"/>`;
  out += `<rect x="${mx - 12}" y="${jy + 9}" width="24" height="18" rx="3" fill="#1b2232" stroke="${yel}" stroke-width="1.5"/>`;
  out += `<rect x="${mx - 9}" y="${jy + 12}" width="18" height="8" rx="1.5" fill="#ffe2a0" opacity=".8"/>`;
  // Laufkatze, Seil, Haken
  out += `<rect x="${trolleyX - 9}" y="${jy + 7}" width="18" height="8" rx="2" fill="#59606e"/>`;
  out += `<line x1="${trolleyX - 3}" y1="${jy + 15}" x2="${trolleyX - 3}" y2="${hookY}" stroke="#c8d2e4" stroke-width="1.3"/>`;
  out += `<line x1="${trolleyX + 3}" y1="${jy + 15}" x2="${trolleyX + 3}" y2="${hookY}" stroke="#c8d2e4" stroke-width="1.3"/>`;
  out += `<rect x="${trolleyX - 8}" y="${hookY}" width="16" height="10" rx="2" fill="${yel}"/>`;
  // Warnlichter
  out += `<circle cx="${mx}" cy="${jy - 46}" r="3.2" fill="#ff4848" filter="url(#glowM)"/>`;
  out += `<circle cx="${mx - jl + 3}" cy="${jy - 1}" r="2.6" fill="#ff4848" filter="url(#glowM)"/>`;
  return out;
}

// Neue Etage (Deckenplatte mit Glas) haengt am Haken
function slab(x, top, w, s, h) {
  const dy = s * 0.3;
  return `
    <polygon points="${x + w},${top} ${x + w + s},${top - dy} ${x + w + s},${top + h - dy} ${x + w},${top + h}" fill="#17306a"/>
    <rect x="${x}" y="${top}" width="${w}" height="${h}" fill="url(#slabFace)"/>
    <rect x="${x}" y="${top}" width="${w}" height="${h}" fill="url(#glassSheen)"/>
    <polygon points="${x},${top} ${x + s},${top - dy} ${x + w + s},${top - dy} ${x + w},${top}" fill="url(#capTop)"/>
    ${Array.from({ length: Math.floor(w / 20) }, (_, i) => `<line x1="${x + 10 + i * 20}" y1="${top + 3}" x2="${x + 10 + i * 20}" y2="${top + h - 3}" stroke="#cfe0ff" stroke-width="1" opacity=".35"/>`).join('')}
    <rect x="${x}" y="${top}" width="${w}" height="${h}" fill="none" stroke="#9cc2ff" stroke-width="1.6" filter="url(#glowS)"/>`;
}

// Leuchtpunkte / Funken
function sparks(rand, cx, cy, rx, ry, n, color) {
  let out = '';
  for (let i = 0; i < n; i++) {
    const a = rand() * Math.PI * 2;
    const d = Math.sqrt(rand());
    const r = 0.8 + rand() * 2;
    out += `<circle cx="${r1(cx + Math.cos(a) * rx * d)}" cy="${r1(cy + Math.sin(a) * ry * d)}" r="${r1(r)}" fill="${color}" opacity="${r1(0.35 + rand() * 0.6)}"/>`;
  }
  return `<g filter="url(#glowS)">${out}</g>`;
}

// Stadtautobahn mit Lichtspuren
function highway(rand, W, y) {
  let out = `<rect x="0" y="${y}" width="${W}" height="34" fill="url(#deck)"/>`;
  out += `<line x1="0" y1="${y + 0.5}" x2="${W}" y2="${y + 0.5}" stroke="#3a5596" stroke-width="1.5" opacity=".8"/>`;
  // Laternen
  for (let x = 40; x < W; x += 150) {
    out += `<line x1="${x}" y1="${y}" x2="${x}" y2="${y - 22}" stroke="#2a3654" stroke-width="2"/>`;
    out += `<line x1="${x}" y1="${y - 22}" x2="${x + 10}" y2="${y - 22}" stroke="#2a3654" stroke-width="2"/>`;
    out += `<circle cx="${x + 10}" cy="${y - 21}" r="2.4" fill="#ffd9a0" filter="url(#glowM)"/>`;
  }
  // Lichtspuren: rote Rücklichter, warme Scheinwerfer, ein blaues Unterboden-Licht (Hypercar)
  const lanes = [
    { yy: y + 9, col: '#ff4d4d', w: 2.6, op: 0.9 },
    { yy: y + 14, col: '#ff6a5a', w: 1.8, op: 0.7 },
    { yy: y + 21, col: '#ffe7b8', w: 2.6, op: 0.9 },
    { yy: y + 26, col: '#fff3d6', w: 1.6, op: 0.75 },
    { yy: y + 17.5, col: C.accent, w: 2.8, op: 0.95 },
  ];
  for (const l of lanes) {
    let x = -20;
    let d = '';
    while (x < W) {
      const len = 80 + rand() * 420;
      d += `M${r1(x)} ${l.yy} H${r1(Math.min(W + 20, x + len))} `;
      x += len + 20 + rand() * 160;
    }
    out += `<path d="${d}" stroke="${l.col}" stroke-width="${l.w}" stroke-linecap="round" opacity="${l.op}" filter="url(#glowM)" fill="none"/>`;
  }
  // Gelaender
  out += `<line x1="0" y1="${y + 31}" x2="${W}" y2="${y + 31}" stroke="#22314f" stroke-width="2"/>`;
  return out;
}

// Wasser: Grund, Wellenlinien
function waterRipples(rand, W, y0, y1) {
  let out = '';
  for (let i = 0; i < 260; i++) {
    const y = y0 + Math.pow(rand(), 1.3) * (y1 - y0);
    const x = rand() * W;
    const len = 12 + rand() * 120;
    out += `<line x1="${r1(x)}" y1="${r1(y)}" x2="${r1(x + len)}" y2="${r1(y)}" stroke="${rand() < 0.25 ? C.accent : '#9fbfff'}" stroke-width="${r1(0.8 + rand())}" opacity="${r1(0.04 + rand() * 0.12)}"/>`;
  }
  return out;
}

// Sterne
function stars(rand, W, maxY, n) {
  let out = '';
  for (let i = 0; i < n; i++) {
    out += `<circle cx="${r1(rand() * W)}" cy="${r1(Math.pow(rand(), 1.4) * maxY)}" r="${r1(0.5 + rand() * 1.2)}" fill="#dfe8ff" opacity="${r1(0.15 + rand() * 0.6)}"/>`;
  }
  return out;
}

// LED-Laufschrift an einer Fassade (fiktive Firmen aus dem Spiel)
function ledTicker(x, y, w, h, items) {
  const id = uid('tk');
  let tx = x + 10;
  let txt = '';
  for (const it of items) {
    const col = it.up ? C.up : C.down;
    txt += `<tspan x="${tx}" fill="#dfe8ff">${esc(it.sym)}</tspan>`;
    tx += it.sym.length * h * 0.48 + 8;
    txt += `<tspan x="${tx}" fill="${col}">${it.up ? '▲' : '▼'} ${esc(it.chg)}</tspan>`;
    tx += (it.chg.length + 2) * h * 0.42 + 26;
  }
  return `<clipPath id="${id}"><rect x="${x}" y="${y}" width="${w}" height="${h}"/></clipPath>
    <rect x="${x}" y="${y}" width="${w}" height="${h}" fill="#04070f"/>
    <g clip-path="url(#${id})" filter="url(#glowS)"><text y="${y + h * 0.76}" font-family="Titillium Web" font-weight="900" font-size="${h * 0.78}">${txt}</text></g>
    <rect x="${x}" y="${y}" width="${w}" height="${h}" fill="none" stroke="#25365e" stroke-width="1"/>`;
}

// ---------------------------------------------------------------------
//  Szene fuer das Thumbnail (1920 x 1080)
// ---------------------------------------------------------------------
function thumbnailScene(lang) {
  const W = 1920;
  const H = 1080;
  const HZ = 842; // Wasserlinie
  const rand = rng(20261014);
  let city = '';

  // --- ferne Skyline: links flach (ruhig hinter dem Text), rechts hoch
  city += farLayer(rand, W, HZ, (x) => 90 + 330 * smooth(560, 1350, x));

  // --- zwei Suchscheinwerfer hinter dem Wahrzeichen
  city += `<polygon points="1662,520 1300,0 1420,0" fill="url(#beam)" opacity=".7"/><polygon points="1690,520 1880,0 1990,0" fill="url(#beam)" opacity=".55"/>`;

  // --- Kerzen-Chart als Hologramm hinter den mittleren Tuermen
  const chart = candleChart(rand, 830, 1866, 452, 112, 34, { areaBase: 842 });
  const grid = Array.from({ length: 7 }, (_, i) => `<line x1="700" y1="${200 + i * 95}" x2="${W}" y2="${200 + i * 95}" stroke="${C.accent}" stroke-width="1" opacity=".07"/>`).join('');
  city += `<g opacity=".9">${grid}${chart.svg}</g>`;

  // --- mittlere Tuerme (Quader mit Fenstern)
  const mids = [
    { x: 30, h: 150, w: 90, s: 24 },
    { x: 150, h: 115, w: 70, s: 18 },
    { x: 260, h: 175, w: 96, s: 26 },
    { x: 400, h: 135, w: 80, s: 20 },
    { x: 520, h: 205, w: 92, s: 24, neonTop: true },
    { x: 650, h: 260, w: 100, s: 26 },
    { x: 790, h: 340, w: 110, s: 30, neonEdge: true },
    { x: 1460, h: 395, w: 96, s: 26, neonTop: true },
    { x: 1820, h: 330, w: 110, s: 30 },
  ];
  for (const m of mids) {
    city += prism({ x: m.x, top: HZ - m.h, base: HZ, w: m.w, s: m.s, rand, neonTop: m.neonTop, neonEdge: m.neonEdge, litP: 0.2 });
    if (m.h > 250 && rand() < 0.8) city += antenna(m.x + m.w * 0.3, HZ - m.h - m.s * 0.15, 30 + rand() * 30);
  }

  // --- Nachbarturm links vom eigenen Tower mit LED-Ticker
  city += prism({ x: 960, top: 452, base: HZ, w: 130, s: 34, rand, face: 'url(#midFace)', litP: 0.26, neonTop: true });
  city += prism({ x: 980, top: 400, base: 452, w: 90, s: 24, rand, litP: 0.3 });
  city += antenna(1025, 392, 56);
  city += ledTicker(966, 500, 118, 22, [
    { sym: 'KERN', chg: '12,4 %', up: true },
    { sym: 'TIKO', chg: '3,1 %', up: true },
    { sym: 'COGN', chg: '0,8 %', up: false },
  ]);

  // --- Wahrzeichen "ΛKYTEX Orbit Spire" (rechts)
  const sp = { x: 1594, w: 142, s: 40 };
  const ringY = 236;
  // hinterer Ring-Teil
  city += `<ellipse cx="${sp.x + sp.w / 2 + 14}" cy="${ringY}" rx="132" ry="28" fill="none" stroke="${C.accent}" stroke-width="4" opacity=".55" filter="url(#glowM)" stroke-dasharray="0 1 415 9999" pathLength="830" transform="rotate(0)"/>`;
  city += prism({ x: sp.x, top: 520, base: HZ, w: sp.w, s: sp.s, rand, face: 'url(#spireFace)', side: 'url(#heroSide)', litP: 0.28, sheen: true, neonEdge: true, cap: '#2b4a8e' });
  city += prism({ x: sp.x + 14, top: 330, base: 520, w: sp.w - 28, s: sp.s - 8, rand, face: 'url(#spireFace)', side: 'url(#heroSide)', litP: 0.3, sheen: true, neonTop: true, cap: '#2b4a8e' });
  city += prism({ x: sp.x + 30, top: 210, base: 330, w: sp.w - 60, s: sp.s - 14, rand, face: 'url(#spireFace)', side: 'url(#heroSide)', litP: 0.34, sheen: true, neonTop: true, cap: '#3557a0' });
  // Spitze
  const tipX = sp.x + sp.w / 2 + 10;
  city += `<polygon points="${sp.x + 40},${210 - 6} ${tipX},96 ${sp.x + sp.w - 20},${210 - 9}" fill="#1c3570"/>`;
  city += `<line x1="${tipX}" y1="96" x2="${tipX}" y2="40" stroke="#8fa9d8" stroke-width="2.4"/>`;
  city += `<circle cx="${tipX}" cy="40" r="4" fill="#ff4848" filter="url(#glowL)"/>`;
  // Λ-Emblem auf der Spitze
  city += `<path d="M${tipX - 22} 192 L${tipX} 140 L${tipX + 22} 192" fill="none" stroke="#eaf1ff" stroke-width="5" filter="url(#glowM)"/>`;
  // vorderer Ring-Teil
  city += `<path d="M${sp.x + sp.w / 2 + 14 - 132} ${ringY} A132 28 0 0 0 ${sp.x + sp.w / 2 + 14 + 132} ${ringY}" fill="none" stroke="#8fb8ff" stroke-width="4.5" filter="url(#glowM)"/>`;
  city += `<path d="M${sp.x + sp.w / 2 + 14 - 132} ${ringY} A132 28 0 0 0 ${sp.x + sp.w / 2 + 14 + 132} ${ringY}" fill="none" stroke="#ffffff" stroke-width="1.5" opacity=".8"/>`;

  // --- eigener Tower (Mitte rechts) mit Kran und neuer Etage
  const hx = 1150;
  // Lichtschein hinter dem Tower
  city += `<ellipse cx="${hx + 130}" cy="430" rx="230" ry="330" fill="${C.accent}" opacity=".22" filter="url(#bloom)"/>`;
  city += prism({ x: hx, top: 560, base: HZ, w: 250, s: 66, rand, face: 'url(#heroFace)', side: 'url(#heroSide)', litP: 0.3, sheen: true, neonTop: true, neonEdge: true, cw: 13, ch: 15, cap: 'url(#capTop)' });
  city += prism({ x: hx + 22, top: 400, base: 560, w: 206, s: 56, rand, face: 'url(#heroFace)', side: 'url(#heroSide)', litP: 0.34, sheen: true, neonTop: true, neonEdge: true, cw: 13, ch: 15, cap: 'url(#capTop)' });
  city += prism({ x: hx + 44, top: 300, base: 400, w: 162, s: 46, rand, face: 'url(#heroFace)', side: 'url(#heroSide)', litP: 0.38, sheen: true, neonTop: true, neonEdge: true, cw: 13, ch: 15, cap: 'url(#capTop)' });
  // Bau-Vorschau (Hologramm-Umriss, wo die Etage landet)
  city += `<rect x="${hx + 44}" y="270" width="162" height="28" fill="${C.accent}" fill-opacity=".10" stroke="${C.accent}" stroke-width="2" stroke-dasharray="9 6" filter="url(#glowS)"/>`;
  // Kran auf dem Dach
  city += crane({ mx: hx + 268, base: 390, top: 120, jl: 330, jr: 122, trolleyX: hx + 125, hookY: 196 });
  // haengende Etage
  city += `<line x1="${hx + 125}" y1="206" x2="${hx + 60}" y2="222" stroke="#c8d2e4" stroke-width="1.1"/><line x1="${hx + 125}" y1="206" x2="${hx + 190}" y2="222" stroke="#c8d2e4" stroke-width="1.1"/>`;
  city += slab(hx + 44, 222, 162, 46, 28);
  city += sparks(rand, hx + 125, 262, 150, 40, 40, '#9cc2ff');

  // --- Stadtautobahn mit Lichtspuren
  city += highway(rand, W, HZ - 34);

  // --- Himmel
  const sky = `
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#03060e"/><stop offset=".38" stop-color="#071230"/><stop offset=".64" stop-color="#0f2150"/>
      <stop offset=".76" stop-color="#1f3a80"/><stop offset=".785" stop-color="#3b4f9a"/><stop offset="1" stop-color="#3b4f9a"/></linearGradient>
    <radialGradient id="dusk" cx="0.62" cy="0.78" r="0.55" gradientTransform="matrix(1 0 0 .45 0 .43)">
      <stop offset="0" stop-color="#ff8a4c" stop-opacity=".42"/><stop offset=".35" stop-color="#c2508f" stop-opacity=".18"/><stop offset="1" stop-color="#c2508f" stop-opacity="0"/></radialGradient>
    <linearGradient id="water" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0a1430"/><stop offset=".25" stop-color="#060c1d"/><stop offset="1" stop-color="#02050c"/></linearGradient>
    <mask id="reflMask"><rect x="0" y="${HZ}" width="${W}" height="${H - HZ}" fill="url(#fadeDown)"/></mask>
    <linearGradient id="textShade" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#02050c" stop-opacity=".88"/><stop offset=".3" stop-color="#02050c" stop-opacity=".62"/><stop offset=".5" stop-color="#02050c" stop-opacity="0"/></linearGradient>
    <radialGradient id="vig" cx=".5" cy=".5" r=".75"><stop offset=".6" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".55"/></radialGradient>`;

  return `<svg class="scene" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg">
    <defs>${defs()}${sky}</defs>
    <rect width="${W}" height="${H}" fill="url(#sky)"/>
    <rect width="${W}" height="${HZ}" fill="url(#dusk)"/>
    ${stars(rand, W, 520, 170)}
    <rect x="0" y="${HZ}" width="${W}" height="${H - HZ}" fill="url(#water)"/>
    <g id="city">${city}</g>
    <g mask="url(#reflMask)" opacity=".55"><g filter="url(#reflBlur)" transform="translate(0 ${2 * HZ}) scale(1 -1)"><use href="#city"/></g></g>
    <line x1="0" y1="${HZ + 0.5}" x2="${W}" y2="${HZ + 0.5}" stroke="#5b7fd0" stroke-width="1" opacity=".5"/>
    ${waterRipples(rand, W, HZ + 4, H)}
    <rect width="${W}" height="${H}" fill="url(#textShade)"/>
    <rect width="${W}" height="${H}" fill="url(#vig)"/>
  </svg>`;
}

// ---------------------------------------------------------------------
//  Szene fuer das Spiel-Icon (512 x 512)
// ---------------------------------------------------------------------
function iconScene() {
  const S = 512;
  const HZ = 404;
  const rand = rng(512512);
  let city = '';
  city += farLayer(rand, S, HZ, (x) => 70 + 60 * Math.sin((x / S) * Math.PI));
  const chart = candleChart(rand, 34, 478, 380, 120, 16, { scale: 0.7, reds: [3, 9], areaBase: HZ, lineW: 3, wick: 2.4 });
  city += `<g opacity=".95">${chart.svg}</g>`;
  city += prism({ x: 40, top: HZ - 120, base: HZ, w: 70, s: 20, rand, litP: 0.25 });
  city += prism({ x: 392, top: HZ - 150, base: HZ, w: 80, s: 22, rand, litP: 0.25, neonTop: true });
  // Haupt-Tower mit Krone
  const x = 186;
  city += `<ellipse cx="256" cy="230" rx="110" ry="170" fill="${C.accent}" opacity=".26" filter="url(#bloomS)"/>`;
  city += prism({ x, top: 250, base: HZ, w: 130, s: 36, rand, face: 'url(#heroFace)', side: 'url(#heroSide)', litP: 0.36, sheen: true, neonTop: true, neonEdge: true, cw: 12, ch: 14, cap: 'url(#capTop)' });
  city += prism({ x: x + 14, top: 168, base: 250, w: 102, s: 30, rand, face: 'url(#heroFace)', side: 'url(#heroSide)', litP: 0.4, sheen: true, neonTop: true, neonEdge: true, cw: 12, ch: 14, cap: 'url(#capTop)' });
  city += prism({ x: x + 28, top: 112, base: 168, w: 74, s: 24, rand, face: 'url(#heroFace)', side: 'url(#heroSide)', litP: 0.45, sheen: true, neonTop: true, cw: 12, ch: 14, cap: 'url(#capTop)' });
  const cx = x + 28 + 37 + 8;
  // Krone: Ring + Λ
  city += `<ellipse cx="${cx}" cy="96" rx="70" ry="15" fill="none" stroke="${C.accent}" stroke-width="3.5" opacity=".55" filter="url(#glowM)"/>`;
  city += `<polygon points="${x + 36},108 ${cx},38 ${x + 96},104" fill="#1c3570"/>`;
  city += `<path d="M${cx - 18} 98 L${cx} 56 L${cx + 18} 98" fill="none" stroke="#f2f6ff" stroke-width="5.5" filter="url(#glowM)"/>`;
  city += `<path d="M${cx - 70} 96 A70 15 0 0 0 ${cx + 70} 96" fill="none" stroke="#9cc2ff" stroke-width="4" filter="url(#glowM)"/>`;
  city += `<line x1="${cx}" y1="38" x2="${cx}" y2="16" stroke="#8fa9d8" stroke-width="2"/><circle cx="${cx}" cy="16" r="3.4" fill="#ff4848" filter="url(#glowM)"/>`;
  city += `<rect x="0" y="${HZ - 14}" width="${S}" height="14" fill="url(#deck)"/>`;
  city += `<path d="M0 ${HZ - 9} H${S}" stroke="#ff4d4d" stroke-width="2" opacity=".8" filter="url(#glowM)"/><path d="M0 ${HZ - 5} H${S}" stroke="#ffe7b8" stroke-width="2" opacity=".8" filter="url(#glowM)" stroke-dasharray="120 30 200 40"/>`;
  return `<svg class="scene" width="${S}" height="${S}" viewBox="0 0 ${S} ${S}" xmlns="http://www.w3.org/2000/svg">
    <defs>${defs()}
      <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#03060e"/><stop offset=".5" stop-color="#0a1840"/><stop offset=".78" stop-color="#22408a"/><stop offset="1" stop-color="#22408a"/></linearGradient>
      <linearGradient id="water" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0a1430"/><stop offset="1" stop-color="#02050c"/></linearGradient>
      <mask id="reflMask"><rect x="0" y="${HZ}" width="${S}" height="${S - HZ}" fill="url(#fadeDown)"/></mask>
      <radialGradient id="vig" cx=".5" cy=".45" r=".72"><stop offset=".62" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".6"/></radialGradient>
    </defs>
    <rect width="${S}" height="${S}" fill="url(#sky)"/>
    ${stars(rand, S, 240, 50)}
    <rect x="0" y="${HZ}" width="${S}" height="${S - HZ}" fill="url(#water)"/>
    <g id="city">${city}</g>
    <g mask="url(#reflMask)" opacity=".45"><g filter="url(#reflBlur)" transform="translate(0 ${2 * HZ}) scale(1 -1)"><use href="#city"/></g></g>
    ${waterRipples(rand, S, HZ + 3, S).split('</line>').slice(0, 60).join('</line>')}
    <rect width="${S}" height="${S}" fill="url(#vig)"/>
  </svg>`;
}

// ---------------------------------------------------------------------
//  Texte
// ---------------------------------------------------------------------
const TEXT = {
  de: {
    line1: 'LIES DIE NEWS.',
    line2: 'BAU DIE SKYLINE.',
    breaking: 'EILMELDUNG',
    headline: 'Kernwerk Systems: Rekord-Auftrag',
    floor: '+1 ETAGE',
  },
  en: {
    line1: 'READ THE NEWS.',
    line2: 'BUILD THE SKYLINE.',
    breaking: 'BREAKING',
    headline: 'Kernwerk Systems lands record order',
    floor: '+1 FLOOR',
  },
};

function fontFaces() {
  const f = (file) => pathToFileURL(path.join(FONT_DIR, file)).href;
  return `
  @font-face { font-family: 'Michroma'; src: url('${f('michroma-latin-400.woff2')}') format('woff2'); font-weight: 400; }
  @font-face { font-family: 'Titillium Web'; src: url('${f('titilliumweb-latin-700.woff2')}') format('woff2'); font-weight: 700; }
  @font-face { font-family: 'Titillium Web'; src: url('${f('titilliumweb-latin-900.woff2')}') format('woff2'); font-weight: 900; }
  @font-face { font-family: 'Unbounded'; src: url('${f('unbounded-latin-700-normal.woff2')}') format('woff2'); font-weight: 700; }
  @font-face { font-family: 'Manrope'; src: url('${f('manrope-latin-700-normal.woff2')}') format('woff2'); font-weight: 700; }
  @font-face { font-family: 'Manrope'; src: url('${f('manrope-latin-800-normal.woff2')}') format('woff2'); font-weight: 800; }`;
}

function page(w, h, body, css) {
  return `<!doctype html><html><head><meta charset="utf-8"><style>
  ${fontFaces()}
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: ${w}px; height: ${h}px; overflow: hidden; background: ${C.bg}; }
  .stage { position: relative; width: ${w}px; height: ${h}px; overflow: hidden; }
  .scene { position: absolute; left: 0; top: 0; }
  .abs { position: absolute; }
  .txt { white-space: nowrap; display: inline-block; }
  ${css}
  </style></head><body><div class="stage">${body}</div></body></html>`;
}

function thumbnailHtml(lang) {
  const t = TEXT[lang];
  const W = 1920;
  const H = 1080;
  const spark = (() => {
    const pts = [30, 28, 31, 26, 27, 22, 24, 18, 19, 12, 14, 6];
    return pts.map((v, i) => `${i ? 'L' : 'M'}${i * 12} ${v}`).join(' ');
  })();
  const css = `
  .brand { left: 112px; top: 128px; }
  .title { left: 104px; top: 236px; font-family: 'Unbounded'; font-weight: 700; font-size: 176px; letter-spacing: -0.01em; line-height: 1;
    background: linear-gradient(180deg, #ffffff 0%, #dbe7ff 45%, #7fa9ff 100%); -webkit-background-clip: text; background-clip: text; color: transparent;
    filter: drop-shadow(0 0 28px rgba(79,140,255,.55)) drop-shadow(0 6px 0 rgba(0,0,0,.35)); }
  .bar { left: 112px; top: 452px; width: 150px; height: 7px; border-radius: 4px; background: ${C.accent}; box-shadow: 0 0 22px ${C.accent}, 0 0 6px ${C.accent}; }
  .tag { left: 110px; font-family: 'Michroma'; font-size: 54px; letter-spacing: 0.02em; line-height: 1; text-shadow: 0 2px 10px rgba(0,0,0,.6); }
  .tag1 { top: 500px; color: ${C.text}; }
  .tag2 { top: 576px; color: #7fb0ff; text-shadow: 0 0 22px rgba(79,140,255,.65), 0 2px 10px rgba(0,0,0,.6); }
  .card { left: 112px; top: 712px; width: 600px; padding: 22px 26px 22px 26px; border-radius: 18px;
    background: rgba(18,24,36,.78); border: 1px solid rgba(79,140,255,.35);
    box-shadow: 0 18px 50px rgba(0,0,0,.55), inset 0 1px 0 rgba(255,255,255,.06), 0 0 40px rgba(79,140,255,.12);
    backdrop-filter: blur(10px); }
  .card .row { display: flex; align-items: center; gap: 14px; }
  .pill { display: inline-flex; align-items: center; gap: 10px; padding: 7px 14px; border-radius: 999px; background: rgba(239,68,68,.16);
    border: 1px solid rgba(239,68,68,.55); color: #ff8a8a; font-family: 'Manrope'; font-weight: 800; font-size: 20px; letter-spacing: .14em; }
  .dot { width: 10px; height: 10px; border-radius: 50%; background: ${C.down}; box-shadow: 0 0 10px ${C.down}; }
  .live { font-family: 'Titillium Web'; font-weight: 700; font-size: 22px; color: ${C.text2}; letter-spacing: .06em; }
  .headline { margin-top: 14px; font-family: 'Manrope'; font-weight: 800; font-size: 31px; color: ${C.text}; }
  .quote { margin-top: 12px; }
  .sym { font-family: 'Titillium Web'; font-weight: 900; font-size: 26px; color: ${C.text2}; letter-spacing: .08em; padding: 2px 10px;
    border-radius: 8px; background: ${C.surface2}; border: 1px solid ${C.border}; }
  .chg { font-family: 'Titillium Web'; font-weight: 900; font-size: 50px; color: ${C.up}; line-height: 1; text-shadow: 0 0 18px rgba(34,197,94,.55); }
  .floor { left: 986px; top: 206px; padding: 8px 16px; border-radius: 999px; background: rgba(18,24,36,.82); border: 1px solid rgba(34,197,94,.6);
    font-family: 'Titillium Web'; font-weight: 900; font-size: 30px; color: ${C.up}; letter-spacing: .04em; box-shadow: 0 0 24px rgba(34,197,94,.35); }`;
  const body = `
    ${thumbnailScene(lang)}
    <div class="abs brand txt fit" data-fit="560">${wordmarkSvg(520, 6.2)}</div>
    <div class="abs title txt fit" data-fit="820">TYCOON</div>
    <div class="abs bar"></div>
    <div class="abs tag tag1 txt fit" data-fit="780">${esc(t.line1)}</div>
    <div class="abs tag tag2 txt fit" data-fit="780">${esc(t.line2)}</div>
    <div class="abs card">
      <div class="row"><span class="pill"><span class="dot"></span>${esc(t.breaking)}</span><span class="live">09:31</span></div>
      <div class="headline txt fit" data-fit="548">${esc(t.headline)}</div>
      <div class="row quote"><span class="sym">KERN</span><span class="chg">▲ +12,4 %</span>
        <svg width="140" height="40" viewBox="0 0 140 40"><path d="${spark}" fill="none" stroke="${C.up}" stroke-width="3" stroke-linejoin="round" stroke-linecap="round" style="filter: drop-shadow(0 0 6px rgba(34,197,94,.8))"/></svg></div>
    </div>
    <div class="abs floor txt">${esc(t.floor)}</div>`;
  return page(W, H, body, css);
}

function iconHtml() {
  const css = `
  .brand { left: 50%; bottom: 30px; transform: translateX(-50%); }`;
  const body = `${iconScene()}<div class="abs brand txt fit" data-fit="400">${wordmarkSvg(300, 7)}</div>`;
  return page(512, 512, body, css);
}

// ---------------------------------------------------------------------
//  Rendern + Pruefen
// ---------------------------------------------------------------------
const JOBS = [
  { name: 'thumbnail-1-de', w: 1920, h: 1080, html: () => thumbnailHtml('de') },
  { name: 'thumbnail-1-en', w: 1920, h: 1080, html: () => thumbnailHtml('en') },
  { name: 'spiel-icon', w: 512, h: 512, html: () => iconHtml() },
];

async function main() {
  const args = process.argv.slice(2);
  let out = path.resolve(__dirname, '..');
  const oi = args.indexOf('--out');
  if (oi >= 0) {
    out = path.resolve(args[oi + 1]);
    args.splice(oi, 2);
  }
  const saveHtml = args.includes('--html');
  const filter = args.find((a) => !a.startsWith('--'));
  fs.mkdirSync(out, { recursive: true });

  const { chromium } = loadPlaywright();
  const browser = await chromium.launch();
  let warn = 0;
  for (const job of JOBS) {
    if (filter && !job.name.includes(filter)) continue;
    const html = job.html();
    const page = await browser.newPage({ viewport: { width: job.w, height: job.h }, deviceScaleFactor: 1 });
    const tmp = path.join(out, `.${job.name}.html`);
    fs.writeFileSync(tmp, html);
    await page.goto(pathToFileURL(tmp).href);
    // alle Schriften laden (auch ungenutzte) und pruefen, dass keine fehlt
    const fontsOk = await page.evaluate(async () => {
      await Promise.all([...document.fonts].map((f) => f.load().catch(() => null)));
      await document.fonts.ready;
      return [...document.fonts].map((f) => [`${f.family} ${f.weight}`, f.status === 'loaded']);
    });
    // Texte automatisch verkleinern, bis sie in ihre Breite passen
    await page.evaluate(() => {
      for (const el of document.querySelectorAll('.fit')) {
        const max = Number(el.dataset.fit);
        const svg = el.querySelector('svg.wordmark');
        if (svg) continue;
        let fs = parseFloat(getComputedStyle(el).fontSize);
        let guard = 0;
        while (el.getBoundingClientRect().width > max && fs > 12 && guard++ < 400) {
          fs -= 1;
          el.style.fontSize = `${fs}px`;
        }
      }
    });
    // Textkanten gegen den Bildrand pruefen
    const report = await page.evaluate(
      ({ w, h }) => {
        const bad = [];
        for (const el of document.querySelectorAll('.txt, .card')) {
          const r = el.getBoundingClientRect();
          if (r.left < 24 || r.top < 24 || r.right > w - 24 || r.bottom > h - 24)
            bad.push({ text: el.textContent.trim().slice(0, 40), r: [r.left, r.top, r.right, r.bottom].map(Math.round) });
        }
        const sizes = [...document.querySelectorAll('.fit')].map((el) => [el.textContent.trim().slice(0, 24) || 'logo', getComputedStyle(el).fontSize]);
        return { bad, sizes };
      },
      { w: job.w, h: job.h },
    );
    const file = path.join(out, `${job.name}.png`);
    await page.screenshot({ path: file, clip: { x: 0, y: 0, width: job.w, height: job.h } });
    await page.close();
    if (saveHtml) fs.copyFileSync(tmp, path.join(out, `${job.name}.html`));
    fs.unlinkSync(tmp);
    const missing = fontsOk.filter((f) => !f[1]).map((f) => f[0]);
    if (report.bad.length || missing.length) warn++;
    console.log(
      JSON.stringify({ bild: path.basename(file), groesse: `${job.w}x${job.h}`, textOutOfBounds: report.bad, fehlendeSchriften: missing, schriftgroessen: report.sizes }),
    );
  }
  await browser.close();
  if (warn) {
    console.log('WARNUNG: mindestens ein Bild hat Probleme (siehe oben).');
    process.exit(1);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
