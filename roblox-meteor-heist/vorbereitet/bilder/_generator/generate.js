#!/usr/bin/env node
/* =====================================================================
 *  METEOR HEIST – Bild-Generator fuer den Roblox-Upload
 *
 *  Erzeugt alle Gamepass-, Developer-Product-, Spiel-Icon- und
 *  Thumbnail-Bilder als PNG. Alles wird mit HTML/SVG/CSS gezeichnet
 *  und mit Playwright (Chromium) fotografiert. Keine Web-Fonts:
 *  Schrift = "DejaVu Sans" Bold, Emojis = "Noto Color Emoji".
 *
 *  Benutzung:
 *    node generate.js            -> alle Bilder neu erzeugen
 *    node generate.js pass-vip   -> nur Bilder, deren Name "pass-vip" enthaelt
 *    node generate.js --html     -> zusaetzlich die HTML-Seiten nach ./html/ schreiben
 *    node generate.js --screens <ordner> --out <ordner>
 *                                -> anderer Screenshot-/Ausgabe-Ordner
 *    node generate.js --no-screens -> Screenshots ignorieren, alles zeichnen
 *
 *  Ausgabe: ../ (also vorbereitet/bilder/)
 *
 *  Screenshot-Modus (siehe README.md): Liegen in vorbereitet/screenshots/
 *  echte In-Game-Bilder (base, krater, tragen, showcase, secret als
 *  .png/.jpg), werden Spiel-Icon und Thumbnails daraus gebaut (plus
 *  thumbnail-4/5). Fehlt ein Screenshot, wird das Bild wie bisher
 *  gezeichnet. Die 14 Pass/Produkt-Icons sind immer gezeichnet.
 *
 *  Qualitaets-Automatik:
 *   - Text wird automatisch verkleinert, bis er in seine Breite passt.
 *   - Bei Gamepass/Produkt-Icons (Roblox schneidet sie RUND zu) wird per
 *     Pixel-Messung geprueft, dass Symbol + Text im mittleren Kreis
 *     (80 % Durchmesser) liegen; sonst wird der Inhalt passend skaliert.
 *   - Thumbnails/Spiel-Icon: Text-Raender werden gegen den Bildrand geprueft.
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

const OUT_DIR = path.resolve(__dirname, '..');
const HTML_DIR = path.join(__dirname, 'html');
const SAFE_R = 512 * 0.4; // 80 % Durchmesser -> Radius 204.8 px

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
let UID = 0;
const uid = (p = 'u') => `${p}${++UID}`;
const n1 = (v) => Math.round(v * 10) / 10;
function mix(a, b, t) {
  // t = Anteil von a (0..1)
  const p = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
  const A = p(a);
  const B = p(b);
  return '#' + A.map((v, i) => Math.round(v * t + B[i] * (1 - t)).toString(16).padStart(2, '0')).join('');
}
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

// ---------------------------------------------------------------------
//  Gemeinsame SVG-Filter
// ---------------------------------------------------------------------
function commonDefs(scale = 1) {
  const s = (v) => n1(v * scale);
  return `
  <filter id="sticker" x="-30%" y="-30%" width="160%" height="160%" color-interpolation-filters="sRGB">
    <feMorphology in="SourceAlpha" operator="dilate" radius="${s(6)}" result="dil"/>
    <feFlood flood-color="#14062a"/><feComposite in2="dil" operator="in" result="outl"/>
    <feOffset in="outl" dy="${s(9)}" result="off"/><feGaussianBlur in="off" stdDeviation="${s(6)}" result="blr"/>
    <feFlood flood-color="#000" flood-opacity="0.55"/><feComposite in2="blr" operator="in" result="shadow"/>
    <feMerge><feMergeNode in="shadow"/><feMergeNode in="outl"/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
  <filter id="dropS" x="-30%" y="-30%" width="160%" height="160%">
    <feDropShadow dx="0" dy="${s(8)}" stdDeviation="${s(7)}" flood-color="#000" flood-opacity="0.55"/>
  </filter>
  <filter id="blur8" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="${s(8)}"/></filter>
  <filter id="blur20" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="${s(20)}"/></filter>
  <filter id="blur60" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="${s(60)}"/></filter>
  <filter id="txtGlow" x="-20%" y="-40%" width="140%" height="180%"><feGaussianBlur stdDeviation="${s(14)}"/></filter>`;
}

// ---------------------------------------------------------------------
//  Sterne / Funkeln
// ---------------------------------------------------------------------
function sparkle(x, y, s, fill = '#fff', op = 1, extra = '') {
  const c = s * 0.13;
  return `<path${extra} d="M${n1(x)},${n1(y - s)} Q${n1(x + c)},${n1(y - c)} ${n1(x + s)},${n1(y)} Q${n1(x + c)},${n1(y + c)} ${n1(x)},${n1(y + s)} Q${n1(x - c)},${n1(y + c)} ${n1(x - s)},${n1(y)} Q${n1(x - c)},${n1(y - c)} ${n1(x)},${n1(y - s)}Z" fill="${fill}" opacity="${op}"/>`;
}

function starField(w, h, n, seed, { big = 0.07, sparkles = 6, sparkleSize = 1, yMax = h } = {}) {
  const r = rng(seed);
  const cols = ['#ffffff', '#d8e6ff', '#fff0d0', '#ecd8ff'];
  let s = '';
  for (let i = 0; i < n; i++) {
    const x = r() * w;
    const y = r() * yMax;
    const isBig = r() < big;
    const rad = (isBig ? 1.7 + r() * 1.6 : 0.6 + r() * 1.1) * Math.max(1, w / 900);
    const op = isBig ? 0.85 + r() * 0.15 : 0.35 + r() * 0.55;
    s += `<circle cx="${n1(x)}" cy="${n1(y)}" r="${n1(rad)}" fill="${cols[(r() * 4) | 0]}" opacity="${op.toFixed(2)}"/>`;
  }
  for (let i = 0; i < sparkles; i++) {
    const x = r() * w;
    const y = r() * yMax;
    const sz = (w / 95) * (0.5 + r() * 0.8) * sparkleSize;
    s += sparkle(x, y, sz, '#ffffff', 0.9);
  }
  return s;
}

// ---------------------------------------------------------------------
//  METEOR (gezeichnet): Felsbrocken mit gluehender Front, Lava-Rissen,
//  Kratern, Leuchten und Feuerschweif.
//  angle = Richtung, in die der Schweif zeigt (Grad, 0 = rechts, -35 = rechts oben)
// ---------------------------------------------------------------------
const PAL = {
  fire: { core: '#fffbe6', hot: '#ffd84a', mid: '#ff7c14', deep: '#b8300c', rock: '#3e1006', glow: '#ff8a1a', crack: '#ffcf3a', tail: ['#fff6c0', '#ffbe2a', '#ff5e12', '#c41a00'] },
  gold: { core: '#ffffff', hot: '#fff27a', mid: '#ffc21a', deep: '#b86e00', rock: '#4a2a00', glow: '#ffcf33', crack: '#fff6a0', tail: ['#fffbd8', '#ffe46a', '#ffb000', '#b06000'] },
  mythic: { core: '#fff2f6', hot: '#ffa0b8', mid: '#ff3c5e', deep: '#a3002e', rock: '#3a0012', glow: '#ff3c6e', crack: '#ffc0d0', tail: ['#ffe6ee', '#ff86a8', '#ff2a56', '#8c0024'] },
  secret: { core: '#ffffff', hot: '#fff4fc', mid: '#ff9be6', deep: '#c83cc8', rock: '#4a1070', glow: '#ffc6f2', crack: '#ffffff', tail: ['#ffffff', '#ffe0f7', '#ff7ada', '#9a3cff'] },
  blue: { core: '#f0f8ff', hot: '#a8dcff', mid: '#3d9bff', deep: '#1240a8', rock: '#0c1a48', glow: '#4aa8ff', crack: '#c8ecff', tail: ['#e8f6ff', '#8ccfff', '#3a8cff', '#1a3ab0'] },
  purple: { core: '#fbf0ff', hot: '#e0a8ff', mid: '#b44dff', deep: '#5a12a8', rock: '#200840', glow: '#c060ff', crack: '#f0d0ff', tail: ['#f8e8ff', '#d89aff', '#a040ff', '#5010a0'] },
  green: { core: '#f2fff0', hot: '#b8ff9a', mid: '#55dc5f', deep: '#167a2a', rock: '#0a2a10', glow: '#6aff70', crack: '#dcffd0', tail: ['#efffe8', '#a8ff90', '#40d050', '#107020'] },
  cyan: { core: '#f0ffff', hot: '#b0fbff', mid: '#5ae6ff', deep: '#0a7fa0', rock: '#062a3a', glow: '#6af0ff', crack: '#e0ffff', tail: ['#f0ffff', '#a8f4ff', '#40d8ff', '#0a70a0'] },
};

function blobPath(r, n, lump, rand, tension = 1 / 6) {
  const pts = [];
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2 + (rand() - 0.5) * 0.25;
    const rr = r * (1 + (rand() - 0.5) * 2 * lump);
    pts.push([Math.cos(a) * rr, Math.sin(a) * rr]);
  }
  let d = `M${n1(pts[0][0])},${n1(pts[0][1])}`;
  for (let i = 0; i < n; i++) {
    const p0 = pts[(i - 1 + n) % n];
    const p1 = pts[i];
    const p2 = pts[(i + 1) % n];
    const p3 = pts[(i + 2) % n];
    const c1 = [p1[0] + (p2[0] - p0[0]) * tension, p1[1] + (p2[1] - p0[1]) * tension];
    const c2 = [p2[0] - (p3[0] - p1[0]) * tension, p2[1] - (p3[1] - p1[1]) * tension];
    d += ` C${n1(c1[0])},${n1(c1[1])} ${n1(c2[0])},${n1(c2[1])} ${n1(p2[0])},${n1(p2[1])}`;
  }
  return { d: d + 'Z', pts };
}

function meteor(o) {
  const { x, y, r, angle = -35, tail = 3.4, pal = 'fire', seed = 7, glow = 1, sparks = 10, deco = true, outline = true, cracks = true } = o;
  const P = typeof pal === 'string' ? PAL[pal] : pal;
  const rand = rng(seed);
  const id = uid('m');
  const L = r * tail;
  const dc = deco ? ' class="deco"' : '';
  let defs = `
    <radialGradient id="${id}g"><stop offset="0" stop-color="${P.glow}" stop-opacity="0.9"/><stop offset="0.28" stop-color="${P.glow}" stop-opacity="0.5"/><stop offset="0.6" stop-color="${P.glow}" stop-opacity="0.16"/><stop offset="1" stop-color="${P.glow}" stop-opacity="0"/></radialGradient>
    <radialGradient id="${id}b" cx="0.4" cy="0.5" fx="0.24" fy="0.46" r="0.72"><stop offset="0" stop-color="${P.core}"/><stop offset="0.2" stop-color="${P.hot}"/><stop offset="0.46" stop-color="${P.mid}"/><stop offset="0.76" stop-color="${P.deep}"/><stop offset="1" stop-color="${P.rock}"/></radialGradient>
    <filter id="${id}f" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="${n1(r * 0.16)}"/></filter>
    <filter id="${id}s" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="${n1(r * 0.04)}"/></filter>`;

  let tails = '';
  if (tail > 0) {
    const layers = [
      [1.45, P.tail[3], 0.9, 1.0, true],
      [1.1, P.tail[2], 1, 0.92, false],
      [0.82, P.tail[1], 1, 0.78, false],
      [0.5, P.tail[0], 1, 0.58, false],
    ];
    layers.forEach(([wf, col, op, lf, blur], i) => {
      const w0 = r * wf;
      const LL = L * lf;
      const gid = `${id}t${i}`;
      defs += `<linearGradient id="${gid}" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="${n1(LL)}" y2="0"><stop offset="0" stop-color="${col}" stop-opacity="${op}"/><stop offset="0.45" stop-color="${col}" stop-opacity="${n1(op * 0.7 * 100) / 100}"/><stop offset="1" stop-color="${col}" stop-opacity="0"/></linearGradient>`;
      tails += `<path d="M0,${n1(-w0)} C${n1(LL * 0.3)},${n1(-w0 * 0.95)} ${n1(LL * 0.7)},${n1(-w0 * 0.3)} ${n1(LL)},0 C${n1(LL * 0.7)},${n1(w0 * 0.3)} ${n1(LL * 0.3)},${n1(w0 * 0.95)} 0,${n1(w0)} A${n1(w0)},${n1(w0)} 0 0 1 0,${n1(-w0)}Z" fill="url(#${gid})"${blur ? ` filter="url(#${id}f)"` : ''}/>`;
    });
    // Flammenzungen
    for (let i = 0; i < 3; i++) {
      const side = i === 1 ? 0 : i === 0 ? -1 : 1;
      const y0 = side * r * 0.62;
      const LL = L * (0.55 + rand() * 0.3);
      const wv = r * 0.16;
      const gid = `${id}z${i}`;
      defs += `<linearGradient id="${gid}" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="${n1(LL)}" y2="0"><stop offset="0" stop-color="${P.tail[0]}" stop-opacity="0.9"/><stop offset="1" stop-color="${P.tail[1]}" stop-opacity="0"/></linearGradient>`;
      tails += `<path d="M0,${n1(y0 - wv)} Q${n1(LL * 0.4)},${n1(y0 * 0.7 - wv + side * r * 0.25)} ${n1(LL)},${n1(y0 * 0.25)} Q${n1(LL * 0.4)},${n1(y0 * 0.7 + wv + side * r * 0.25)} 0,${n1(y0 + wv)}Z" fill="url(#${gid})"/>`;
    }
    // Funken
    for (let i = 0; i < sparks; i++) {
      const t = 0.25 + rand() * 0.95;
      const sx = L * t;
      const sy = (rand() - 0.5) * r * 2.4 * (1 - t * 0.45);
      const sr = r * (0.035 + rand() * 0.06);
      tails += `<circle cx="${n1(sx)}" cy="${n1(sy)}" r="${n1(sr)}" fill="${rand() < 0.5 ? P.tail[0] : P.tail[1]}" opacity="${(0.5 + rand() * 0.5).toFixed(2)}"/>`;
    }
  }

  const blob = blobPath(r, 10, 0.11, rand, 0.12);
  const body = blob.d;
  let detail = '';
  // Schatten auf der Rueckseite (+x) -> mehr Volumen
  detail += `<circle cx="${n1(r * 0.75)}" cy="${n1(r * 0.25)}" r="${n1(r * 0.75)}" fill="${P.rock}" opacity="0.35" filter="url(#${id}f)"/>`;
  // Krater (eher hinten = +x, dort ist der Fels dunkler)
  const craters = [
    [0.38, -0.38, 0.2],
    [0.5, 0.3, 0.16],
    [0.05, 0.55, 0.12],
    [0.12, -0.05, 0.1],
  ];
  craters.forEach(([cx, cy, cr]) => {
    const jx = cx + (rand() - 0.5) * 0.1;
    const jy = cy + (rand() - 0.5) * 0.1;
    detail += `<ellipse cx="${n1(jx * r)}" cy="${n1(jy * r)}" rx="${n1(cr * r)}" ry="${n1(cr * r * 0.85)}" fill="${P.rock}" opacity="0.45"/>`;
    detail += `<path d="M${n1((jx - cr * 0.8) * r)},${n1(jy * r)} A${n1(cr * r * 0.85)},${n1(cr * r * 0.75)} 0 0 0 ${n1((jx + cr * 0.8) * r)},${n1(jy * r)}" fill="none" stroke="${P.hot}" stroke-opacity="0.45" stroke-width="${n1(r * 0.025)}" stroke-linecap="round"/>`;
  });
  if (cracks) {
    const cr = [
      `M${n1(r * 0.15)},${n1(-r * 0.75)} L${n1(r * 0.3)},${n1(-r * 0.5)} L${n1(r * 0.22)},${n1(-r * 0.32)} L${n1(r * 0.42)},${n1(-r * 0.12)}`,
      `M${n1(r * 0.62)},${n1(r * 0.05)} L${n1(r * 0.4)},${n1(r * 0.12)} L${n1(r * 0.3)},${n1(r * 0.35)} L${n1(r * 0.08)},${n1(r * 0.42)}`,
      `M${n1(-r * 0.1)},${n1(r * 0.78)} L${n1(r * 0.05)},${n1(r * 0.62)}`,
    ];
    cr.forEach((d) => {
      detail += `<path d="${d}" fill="none" stroke="${P.crack}" stroke-width="${n1(r * 0.07)}" stroke-linecap="round" stroke-linejoin="round" opacity="0.55" filter="url(#${id}s)"/>`;
      detail += `<path d="${d}" fill="none" stroke="${P.crack}" stroke-width="${n1(r * 0.03)}" stroke-linecap="round" stroke-linejoin="round" opacity="0.95"/>`;
    });
  }
  // gluehender Rand vorne (-x)
  detail += `<path d="M${n1(-r * 0.25)},${n1(-r * 0.9)} A${n1(r * 0.95)},${n1(r * 0.95)} 0 0 0 ${n1(-r * 0.25)},${n1(r * 0.9)}" fill="none" stroke="${P.core}" stroke-width="${n1(r * 0.09)}" stroke-linecap="round" opacity="0.85" filter="url(#${id}s)"/>`;
  detail += `<ellipse cx="${n1(-r * 0.45)}" cy="${n1(-r * 0.35)}" rx="${n1(r * 0.13)}" ry="${n1(r * 0.075)}" fill="#ffffff" opacity="0.6" transform="rotate(-35 ${n1(-r * 0.45)} ${n1(-r * 0.35)})"/>`;

  const glowR = r * 2.3 * glow;
  return `<g transform="translate(${n1(x)} ${n1(y)}) rotate(${angle})">
    <defs>${defs}</defs>
    ${glow > 0 ? `<circle${dc} r="${n1(glowR)}" fill="url(#${id}g)"/>` : ''}
    <g${dc}>${tails}</g>
    <path d="${body}" fill="url(#${id}b)"${outline ? ` stroke="${P.rock}" stroke-width="${n1(r * 0.05)}"` : ''}/>
    <clipPath id="${id}c"><path d="${body}"/></clipPath>
    <g clip-path="url(#${id}c)">${detail}</g>
  </g>`;
}

// ---------------------------------------------------------------------
//  TEXT: fett, dicker dunkler Rand, 3D-Schatten, Farbverlauf.
//  cy = optische Mitte der Grossbuchstaben.
// ---------------------------------------------------------------------
const FILL = {
  gold: ['#fffbd6', '#ffe14a', '#ffa000'],
  fire: ['#fff7b0', '#ffc21a', '#ff6a00'],
  white: ['#ffffff', '#ffffff', '#d6dcff'],
  pink: ['#ffffff', '#ffd6f4', '#ff7ad9'],
};

function txt(text, o) {
  const { x, cy, size, fill = FILL.gold, stroke = '#1a0733', sw = 0.2, depth = 0.08, depthColor = '#0a0216', maxW = 99999, anchor = 'middle', ls = -0.02, glow = null, glowOp = 0.75, cls = '', tspans = null } = o;
  const id = uid('t');
  const base = cy + size * 0.365; // Grundlinie
  const capTop = base - size * 0.73;
  const attrs = `class="t" x="${n1(x)}" y="${n1(base)}" font-size="${n1(size)}" text-anchor="${anchor}" letter-spacing="${n1(ls * size)}"`;
  const grad = (gid, cols) =>
    `<linearGradient id="${gid}" gradientUnits="userSpaceOnUse" x1="0" y1="${n1(capTop)}" x2="0" y2="${n1(base)}">${cols
      .map((c, i) => `<stop offset="${(i / (cols.length - 1)).toFixed(2)}" stop-color="${c}"/>`)
      .join('')}</linearGradient>`;
  let defs = grad(id, fill);
  let content = esc(text);
  let contentMain = content;
  if (tspans) {
    // [{text, fill:[...]}]
    content = tspans.map((t) => esc(t.text)).join('');
    contentMain = tspans
      .map((t, i) => {
        if (!t.fill) return `<tspan>${esc(t.text)}</tspan>`;
        defs += grad(`${id}_${i}`, t.fill);
        return `<tspan fill="url(#${id}_${i})">${esc(t.text)}</tspan>`;
      })
      .join('');
  }
  const swp = n1(sw * size);
  return `<g class="fit ${cls}" data-maxw="${maxW}" data-sw="${swp}" data-cx="${n1(x)}" data-cy="${n1(cy)}">
    <defs>${defs}</defs>
    ${glow ? `<text ${attrs} fill="${glow}" stroke="${glow}" stroke-width="${n1(swp * 2.2)}" stroke-linejoin="round" filter="url(#txtGlow)" opacity="${glowOp}">${content}</text>` : ''}
    <text ${attrs} transform="translate(0 ${n1(depth * size)})" fill="${depthColor}" stroke="${depthColor}" stroke-width="${swp}" stroke-linejoin="round">${content}</text>
    <text ${attrs} data-main="1" fill="url(#${id})" stroke="${stroke}" stroke-width="${swp}" stroke-linejoin="round" paint-order="stroke">${contentMain}</text>
  </g>`;
}

function emo(ch, { x, y, size, filter = 'url(#sticker)', rotate = 0, flip = false, op = 1 }) {
  const tr = [];
  if (rotate) tr.push(`rotate(${rotate} ${x} ${y})`);
  if (flip) tr.push(`translate(${2 * x} 0) scale(-1 1)`);
  return `<text class="e" x="${n1(x)}" y="${n1(y)}" font-size="${n1(size)}" text-anchor="middle" dominant-baseline="central"${filter ? ` filter="${filter}"` : ''}${tr.length ? ` transform="${tr.join(' ')}"` : ''}${op < 1 ? ` opacity="${op}"` : ''}>${ch}</text>`;
}

// Zacken-Sticker (z. B. "2X")
function burst(text, { x, y, r, fill = ['#ff5a5a', '#d4000f'], rot = -12, points = 14, textFill = FILL.white, textSize = null }) {
  const id = uid('b');
  let d = '';
  for (let i = 0; i < points * 2; i++) {
    const a = (i / (points * 2)) * Math.PI * 2 - Math.PI / 2;
    const rr = i % 2 === 0 ? r : r * 0.84;
    d += `${i === 0 ? 'M' : 'L'}${n1(x + Math.cos(a) * rr)},${n1(y + Math.sin(a) * rr)} `;
  }
  d += 'Z';
  return `<g transform="rotate(${rot} ${x} ${y})">
    <defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${fill[0]}"/><stop offset="1" stop-color="${fill[1]}"/></linearGradient></defs>
    <path d="${d}" fill="#14062a" stroke="#14062a" stroke-width="${n1(r * 0.22)}" stroke-linejoin="round" transform="translate(0 ${n1(r * 0.08)})"/>
    <path d="${d}" fill="url(#${id})" stroke="#ffffff" stroke-width="${n1(r * 0.09)}" stroke-linejoin="round"/>
    ${txt(text, { x, cy: y, size: textSize || r * 0.82, fill: textFill, sw: 0.18, depth: 0.06, maxW: r * 1.5 })}
  </g>`;
}

function bolt(cx, cy, h, { fill = ['#fffde0', '#ffe83a', '#ffb000'], rot = 12 } = {}) {
  const id = uid('z');
  const w = h * 0.62;
  const P = [
    [0.18, 0], [0.7, 0], [0.47, 0.37], [0.8, 0.37], [0.2, 1], [0.36, 0.53], [0.04, 0.53],
  ].map(([px, py]) => [cx - w / 2 + px * w, cy - h / 2 + py * h]);
  const d = 'M' + P.map((p) => `${n1(p[0])},${n1(p[1])}`).join(' L') + 'Z';
  return `<g transform="rotate(${rot} ${cx} ${cy})">
    <defs><linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${fill[0]}"/><stop offset="0.45" stop-color="${fill[1]}"/><stop offset="1" stop-color="${fill[2]}"/></linearGradient></defs>
    <path class="deco" d="${d}" fill="#fff36a" opacity="0.7" filter="url(#blur20)"/>
    <path d="${d}" fill="#14062a" stroke="#14062a" stroke-width="${n1(h * 0.075)}" stroke-linejoin="round" transform="translate(0 ${n1(h * 0.035)})"/>
    <path d="${d}" fill="url(#${id})" stroke="#14062a" stroke-width="${n1(h * 0.05)}" stroke-linejoin="round"/>
    <path d="${d}" fill="none" stroke="#ffffff" stroke-opacity="0.65" stroke-width="${n1(h * 0.015)}" stroke-linejoin="round" transform="translate(${n1(-h * 0.012)} ${n1(-h * 0.012)})"/>
  </g>`;
}

function speedLines(x, y, { n = 3, len = 90, gap = 34, color = '#ffffff', w = 13, dir = -1, cls = '' }) {
  let s = '';
  for (let i = 0; i < n; i++) {
    const yy = y + (i - (n - 1) / 2) * gap;
    const l = len * (i === (n - 1) / 2 ? 1 : 0.72);
    const x1 = x;
    const x2 = x + dir * l;
    s += `<line${cls ? ` class="${cls}"` : ''} x1="${n1(x1)}" y1="${n1(yy)}" x2="${n1(x2)}" y2="${n1(yy)}" stroke="#14062a" stroke-width="${w + 9}" stroke-linecap="round"/>`;
    s += `<line${cls ? ` class="${cls}"` : ''} x1="${n1(x1)}" y1="${n1(yy)}" x2="${n1(x2)}" y2="${n1(yy)}" stroke="${color}" stroke-width="${w}" stroke-linecap="round"/>`;
  }
  return s;
}

// ---------------------------------------------------------------------
//  ICON-RAHMEN (512x512): Weltraum-Hintergrund mit Akzentfarbe,
//  Strahlen, Sterne, Ring. Inhalt kommt in <g id="content">.
// ---------------------------------------------------------------------
const ACC = {
  money: { acc: '#2be04f', light: '#c2ffa8', dark: '#0a7d2c' },
  gold: { acc: '#ffc21a', light: '#fff3a0', dark: '#a86400' },
  violet: { acc: '#a64dff', light: '#e6c4ff', dark: '#4f12a0' },
  cyan: { acc: '#1ed2ff', light: '#c4f6ff', dark: '#0a5f96' },
  magenta: { acc: '#ff3dc8', light: '#ffc4f0', dark: '#8f0a72' },
  blue: { acc: '#2f7bff', light: '#b8d6ff', dark: '#0f339a' },
  luck: { acc: '#1fff6a', light: '#cfffe0', dark: '#06873a' },
  orange: { acc: '#ff7a12', light: '#ffd6a0', dark: '#a33600' },
  legend: { acc: '#ffbe28', light: '#fff2a8', dark: '#9c5c00' },
  mythic: { acc: '#ff3c5a', light: '#ffc0cc', dark: '#8e0626' },
};

function iconSVG(spec) {
  const A = ACC[spec.accent];
  const S = 512;
  const C = 256;
  let rays = '';
  const nR = 16;
  for (let i = 0; i < nR; i++) {
    const a0 = (i / nR) * Math.PI * 2;
    const a1 = a0 + (Math.PI * 2) / nR / 2;
    rays += `<path d="M${C},${C} L${n1(C + Math.cos(a0) * 400)},${n1(C + Math.sin(a0) * 400)} L${n1(C + Math.cos(a1) * 400)},${n1(C + Math.sin(a1) * 400)}Z"/>`;
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${S}" height="${S}" viewBox="0 0 ${S} ${S}">
  <defs>
    ${commonDefs(1)}
    <radialGradient id="bgG" cx="0.5" cy="0.45" r="0.72">
      <stop offset="0" stop-color="${mix(A.acc, '#1b0a45', 0.62)}"/>
      <stop offset="0.42" stop-color="${mix(A.acc, '#1a0b44', 0.22)}"/>
      <stop offset="0.78" stop-color="#120830"/>
      <stop offset="1" stop-color="#070418"/>
    </radialGradient>
    <radialGradient id="rayFade"><stop offset="0.15" stop-color="#fff" stop-opacity="1"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
    <mask id="rayMask"><circle cx="${C}" cy="${C}" r="250" fill="url(#rayFade)"/></mask>
    <radialGradient id="cGlow"><stop offset="0" stop-color="${A.light}" stop-opacity="0.7"/><stop offset="0.45" stop-color="${A.acc}" stop-opacity="0.35"/><stop offset="1" stop-color="${A.acc}" stop-opacity="0"/></radialGradient>
    <clipPath id="ringClip"><circle cx="${C}" cy="${C}" r="231"/></clipPath>
    <linearGradient id="ringG" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${A.light}"/><stop offset="0.5" stop-color="${A.acc}"/><stop offset="1" stop-color="${A.dark}"/></linearGradient>
  </defs>
  <g class="bg-layer">
    <rect width="${S}" height="${S}" fill="url(#bgG)"/>
    <g fill="${A.light}" opacity="0.13" mask="url(#rayMask)">${rays}</g>
    ${starField(S, S, 70, spec.seed || 3, { sparkles: 5, sparkleSize: 0.9 })}
    <circle cx="${C}" cy="${C - 10}" r="215" fill="url(#cGlow)"/>
    <circle cx="${C}" cy="${C}" r="240" fill="none" stroke="#14062a" stroke-width="24"/>
    <circle cx="${C}" cy="${C}" r="240" fill="none" stroke="url(#ringG)" stroke-width="14"/>
    <circle cx="${C}" cy="${C}" r="234.5" fill="none" stroke="#ffffff" stroke-opacity="0.35" stroke-width="2"/>
  </g>
  <g clip-path="url(#ringClip)"><g id="content">${spec.content()}</g></g>
</svg>`;
}

// ---------------------------------------------------------------------
//  ICON-DEFINITIONEN
// ---------------------------------------------------------------------
const labelFill = (a) => ['#ffffff', ACC[a].light, ACC[a].acc];
const L_Y = 372; // optische Mitte des Labels
const ICONS = [
  // ------------------------- GAMEPASSES -------------------------
  {
    file: 'pass-2x-cash.png', key: 'DoubleCash', accent: 'money', seed: 11,
    desc: 'Gamepass "2x Cash": grosser Geldsack mit rotem "2X"-Sticker und dem Wort CASH, gruen/gold.',
    content: () =>
      emo('💰', { x: 248, y: 212, size: 236 }) +
      burst('2X', { x: 342, y: 156, r: 72 }) +
      txt('CASH', { x: 256, cy: L_Y, size: 118, fill: FILL.gold, maxW: 360 }),
  },
  {
    file: 'pass-vip.png', key: 'VIP', accent: 'gold', seed: 12,
    desc: 'Gamepass "VIP": goldene Krone und riesiger Schriftzug VIP auf goldenem Glanz.',
    content: () =>
      sparkle(130, 150, 22, '#fff8c0', 1) + sparkle(392, 128, 18, '#fff8c0', 1) +
      emo('👑', { x: 256, y: 205, size: 250 }) +
      txt('VIP', { x: 256, cy: L_Y, size: 150, fill: ['#ffffff', '#fff2a0', '#ffb300'], maxW: 330 }),
  },
  {
    file: 'pass-extra-plaetze.png', key: 'ExtraSlots', accent: 'violet', seed: 13,
    desc: 'Gamepass "+5 Meteor-Plaetze": gezeichneter gluehender Meteor mit Feuerschweif und grosses +5 auf Lila.',
    content: () =>
      meteor({ x: 236, y: 218, r: 104, angle: -38, tail: 2.6, pal: 'fire', seed: 5 }) +
      txt('+5', { x: 256, cy: L_Y - 4, size: 170, fill: FILL.gold, maxW: 330 }),
  },
  {
    file: 'pass-auto-collect.png', key: 'AutoCollect', accent: 'cyan', seed: 14,
    desc: 'Gamepass "Auto Collect": Roboter mit fliegenden Geldscheinen und dem Wort AUTO auf Cyan.',
    content: () =>
      emo('💵', { x: 140, y: 170, size: 84, rotate: -18 }) +
      emo('💵', { x: 372, y: 170, size: 84, rotate: 18 }) +
      emo('🤖', { x: 256, y: 210, size: 228 }) +
      txt('AUTO', { x: 256, cy: L_Y, size: 124, fill: labelFill('cyan'), stroke: '#071a36', maxW: 340 }),
  },
  {
    file: 'pass-2x-aufladen.png', key: 'FastCharge', accent: 'magenta', seed: 15,
    desc: 'Gamepass "2x Aufladen": gluehender Meteor mit grossem gelbem Blitz und 2X auf Magenta.',
    content: () =>
      meteor({ x: 214, y: 214, r: 92, angle: -40, tail: 2.4, pal: 'fire', seed: 9 }) +
      bolt(300, 212, 230, { rot: 14 }) +
      txt('2X', { x: 256, cy: L_Y, size: 160, fill: FILL.gold, maxW: 330 }),
  },
  {
    file: 'pass-speed-boots.png', key: 'SpeedBoots', accent: 'blue', seed: 16,
    desc: 'Gamepass "Speed Boots": Turnschuh mit Tempo-Streifen und dem Wort SPEED auf Blau.',
    content: () =>
      speedLines(160, 210, { n: 3, len: 70, gap: 46, dir: -1, w: 14 }) +
      emo('👟', { x: 280, y: 206, size: 236 }) +
      txt('SPEED', { x: 256, cy: L_Y - 4, size: 110, fill: labelFill('blue'), stroke: '#06143a', maxW: 360 }),
  },
  // ---------------------- DEVELOPER PRODUCTS ----------------------
  {
    file: 'produkt-cash-s.png', key: 'CashSmall', accent: 'money', seed: 21,
    desc: 'Produkt "Cash Paket S": Geldscheinbuendel mit grossem goldenem S.',
    content: () =>
      emo('💵', { x: 256, y: 205, size: 236 }) +
      txt('S', { x: 256, cy: L_Y + 2, size: 170, fill: FILL.gold, maxW: 330 }),
  },
  {
    file: 'produkt-cash-m.png', key: 'CashMedium', accent: 'money', seed: 22,
    desc: 'Produkt "Cash Paket M": Geldsack mit Geldscheinen und grossem goldenem M.',
    content: () =>
      emo('💵', { x: 168, y: 230, size: 130, rotate: -16 }) +
      emo('💵', { x: 346, y: 230, size: 130, rotate: 16 }) +
      emo('💰', { x: 256, y: 200, size: 220 }) +
      txt('M', { x: 256, cy: L_Y + 2, size: 170, fill: FILL.gold, maxW: 330 }),
  },
  {
    file: 'produkt-cash-xl.png', key: 'CashLarge', accent: 'money', seed: 23,
    desc: 'Produkt "Cash Paket XL": Berg aus drei Geldsaecken mit Scheinen und grossem goldenem XL.',
    content: () =>
      emo('💵', { x: 256, y: 116, size: 110, rotate: 8 }) +
      emo('💰', { x: 160, y: 228, size: 150, rotate: -10 }) +
      emo('💰', { x: 352, y: 228, size: 150, rotate: 10 }) +
      emo('💰', { x: 256, y: 206, size: 200 }) +
      txt('XL', { x: 256, cy: L_Y + 2, size: 165, fill: FILL.gold, maxW: 330 }),
  },
  {
    file: 'produkt-server-glueck.png', key: 'ServerLuck', accent: 'luck', seed: 24,
    desc: 'Produkt "2x Server-Glueck": vierblaettriges Kleeblatt mit Funkeln, "2X"-Sticker und GLUECK.',
    content: () =>
      sparkle(128, 140, 22, '#ffffff', 1) + sparkle(150, 292, 14, '#eaffd0', 1) + sparkle(392, 286, 16, '#eaffd0', 1) +
      emo('🍀', { x: 250, y: 208, size: 236 }) +
      burst('2X', { x: 344, y: 152, r: 70, fill: ['#ffd84a', '#ff8a00'], textFill: FILL.white }) +
      txt('GLÜCK', { x: 256, cy: L_Y + 2, size: 112, fill: ['#ffffff', '#d8ffc8', '#3dff6e'], stroke: '#05260f', maxW: 350 }),
  },
  {
    file: 'produkt-speed-10.png', key: 'Speed10', accent: 'blue', seed: 25,
    desc: 'Produkt "+10 Speed-Level": rennende Figur mit Tempo-Streifen und grossem +10 auf Blau.',
    content: () =>
      speedLines(338, 212, { n: 3, len: 70, gap: 46, dir: 1, w: 14 }) +
      emo('🏃', { x: 236, y: 204, size: 240 }) +
      txt('+10', { x: 256, cy: L_Y, size: 150, fill: labelFill('blue'), stroke: '#06143a', maxW: 340 }),
  },
  {
    file: 'produkt-meteoritenschauer.png', key: 'MeteorShower', accent: 'orange', seed: 26,
    desc: 'Produkt "Meteoritenschauer": drei schraeg herabstuerzende Feuer-Meteore und das Wort SCHAUER auf Orange.',
    content: () =>
      meteor({ x: 330, y: 132, r: 34, angle: -38, tail: 3.4, pal: 'fire', seed: 31, sparks: 5 }) +
      meteor({ x: 150, y: 172, r: 44, angle: -38, tail: 3.2, pal: 'fire', seed: 32, sparks: 6 }) +
      meteor({ x: 262, y: 246, r: 74, angle: -38, tail: 2.8, pal: 'fire', seed: 33 }) +
      txt('SCHAUER', { x: 256, cy: L_Y - 8, size: 100, fill: FILL.fire, maxW: 370 }),
  },
  {
    file: 'produkt-legendary-meteor.png', key: 'LegendaryMeteor', accent: 'legend', seed: 27,
    desc: 'Produkt "Legendary Meteor": goldener gluehender Meteor mit Funkeln und dem Wort LEGENDARY.',
    content: () =>
      sparkle(136, 128, 24, '#fffbe0', 1) + sparkle(388, 300, 16, '#fffbe0', 1) + sparkle(150, 300, 12, '#fffbe0', 1) +
      meteor({ x: 244, y: 214, r: 108, angle: -38, tail: 2.5, pal: 'gold', seed: 41 }) +
      txt('LEGENDARY', { x: 256, cy: L_Y - 12, size: 80, fill: ['#ffffff', '#fff09a', '#ffb000'], maxW: 380 }),
  },
  {
    file: 'produkt-mythic-meteor.png', key: 'MythicMeteor', accent: 'mythic', seed: 28,
    desc: 'Produkt "Mythic Meteor": rot-pink gluehender Meteor mit Funkeln und dem Wort MYTHIC.',
    content: () =>
      sparkle(136, 128, 24, '#ffe6ee', 1) + sparkle(388, 300, 16, '#ffe6ee', 1) + sparkle(150, 300, 12, '#ffe6ee', 1) +
      meteor({ x: 244, y: 214, r: 108, angle: -38, tail: 2.5, pal: 'mythic', seed: 42 }) +
      txt('MYTHIC', { x: 256, cy: L_Y - 8, size: 104, fill: ['#ffffff', '#ffc4d4', '#ff3c64'], stroke: '#2a0010', maxW: 370 }),
  },
];

// ---------------------------------------------------------------------
//  SPIEL-ICON (512x512)
// ---------------------------------------------------------------------
function gameIconSVG() {
  const S = 512;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${S}" height="${S}" viewBox="0 0 ${S} ${S}">
  <defs>
    ${commonDefs(1)}
    <linearGradient id="giBg" x1="0" y1="0" x2="0.4" y2="1"><stop offset="0" stop-color="#2a0d6e"/><stop offset="0.55" stop-color="#160a46"/><stop offset="1" stop-color="#080522"/></linearGradient>
    <radialGradient id="giNeb1"><stop offset="0" stop-color="#8a2cff" stop-opacity="0.65"/><stop offset="1" stop-color="#8a2cff" stop-opacity="0"/></radialGradient>
    <radialGradient id="giNeb2"><stop offset="0" stop-color="#1e6bff" stop-opacity="0.55"/><stop offset="1" stop-color="#1e6bff" stop-opacity="0"/></radialGradient>
    <radialGradient id="giNeb3"><stop offset="0" stop-color="#ff3da8" stop-opacity="0.35"/><stop offset="1" stop-color="#ff3da8" stop-opacity="0"/></radialGradient>
  </defs>
  <rect width="${S}" height="${S}" fill="url(#giBg)"/>
  <circle cx="420" cy="90" r="260" fill="url(#giNeb1)"/>
  <circle cx="60" cy="380" r="260" fill="url(#giNeb2)"/>
  <circle cx="300" cy="300" r="200" fill="url(#giNeb3)"/>
  ${starField(S, S, 120, 77, { sparkles: 7 })}
  ${meteor({ x: 222, y: 178, r: 112, angle: -36, tail: 3.1, pal: 'fire', seed: 3, glow: 1.15, sparks: 14 })}
  ${txt('METEOR', { x: 256, cy: 348, size: 104, fill: FILL.fire, maxW: 470, glow: '#ff6a00', glowOp: 0.55 })}
  ${txt('HEIST', { x: 256, cy: 436, size: 116, fill: ['#ffffff', '#e8f0ff', '#8fc8ff'], stroke: '#0a0a36', maxW: 430, glow: '#4a8cff', glowOp: 0.5 })}
</svg>`;
}

// ---------------------------------------------------------------------
//  BLOCK-FIGUR (Roblox-Stil, R6). Ursprung = Huefte (Mitte oben der Beine).
// ---------------------------------------------------------------------
function avatar(o) {
  const {
    x, y, u, lean = 8, legA = 28,
    armL = 0, armR = 0, // Rotation in Grad (0 = haengt runter)
    head = '#ffd23a', torso = '#2a6fe8', legs = '#2fae4a', arms = null, mask = true, angry = false,
    held = '', heldBehind = true, prop = null, rim = '#ffb040', shadow = true, groundY = null, armLen = 2,
  } = o;
  const armCol = arms || head;
  const ol = '#120822';
  const sw = n1(u * 0.08);
  const shade = (w, h, x0, y0) =>
    `<rect x="${n1(x0 + w * 0.62)}" y="${n1(y0)}" width="${n1(w * 0.38)}" height="${n1(h)}" fill="#000" opacity="0.22"/>` +
    `<rect x="${n1(x0)}" y="${n1(y0)}" width="${n1(w)}" height="${n1(Math.min(h, u) * 0.16)}" fill="#fff" opacity="0.22"/>`;
  const part = (x0, y0, w, h, col, rx = u * 0.12) => {
    const cid = uid('c');
    return `<g><clipPath id="${cid}"><rect x="${n1(x0)}" y="${n1(y0)}" width="${n1(w)}" height="${n1(h)}" rx="${n1(rx)}"/></clipPath>
      <rect x="${n1(x0)}" y="${n1(y0)}" width="${n1(w)}" height="${n1(h)}" rx="${n1(rx)}" fill="${col}"/>
      <g clip-path="url(#${cid})">${shade(w, h, x0, y0)}</g>
      <rect x="${n1(x0)}" y="${n1(y0)}" width="${n1(w)}" height="${n1(h)}" rx="${n1(rx)}" fill="none" stroke="${ol}" stroke-width="${sw}"/></g>`;
  };
  const leg = (px, ang, col) =>
    `<g transform="rotate(${ang} ${n1(px)} 0)">${part(px - u * 0.5, -u * 0.1, u, u * 2.1, col)}<rect x="${n1(px - u * 0.5)}" y="${n1(u * 1.65)}" width="${n1(u)}" height="${n1(u * 0.38)}" rx="${n1(u * 0.1)}" fill="#1b1b2a" stroke="${ol}" stroke-width="${sw}"/></g>`;
  const arm = (px, ang, col, extra = '') =>
    `<g transform="rotate(${ang} ${n1(px)} ${n1(-u * 1.75)})">${extra}${part(px - u * 0.5, -u * 2, u, u * armLen, col)}</g>`;
  // Gesicht
  let face = '';
  const hx = -u * 0.62;
  const hy = -u * 3.3;
  const hw = u * 1.24;
  const hh = u * 1.24;
  if (mask) {
    face += `<rect x="${n1(hx - u * 0.04)}" y="${n1(hy + hh * 0.26)}" width="${n1(hw + u * 0.08)}" height="${n1(hh * 0.3)}" rx="${n1(u * 0.06)}" fill="#151022"/>`;
    face += `<path d="M${n1(hx + hw)},${n1(hy + hh * 0.36)} l${n1(u * 0.35)},${n1(-u * 0.12)} l${n1(-u * 0.05)},${n1(u * 0.2)}Z" fill="#151022"/>`;
  }
  const eyeY = hy + hh * 0.41;
  [-0.24, 0.24].forEach((ex) => {
    face += `<ellipse cx="${n1(ex * u)}" cy="${n1(eyeY)}" rx="${n1(u * 0.12)}" ry="${n1(u * 0.1)}" fill="#fff"/>`;
    face += `<circle cx="${n1(ex * u + u * 0.04)}" cy="${n1(eyeY)}" r="${n1(u * 0.055)}" fill="#111"/>`;
  });
  if (angry) {
    face += `<path d="M${n1(-u * 0.42)},${n1(eyeY - u * 0.22)} L${n1(-u * 0.1)},${n1(eyeY - u * 0.1)} M${n1(u * 0.42)},${n1(eyeY - u * 0.22)} L${n1(u * 0.1)},${n1(eyeY - u * 0.1)}" stroke="#111" stroke-width="${n1(u * 0.08)}" stroke-linecap="round"/>`;
    face += `<path d="M${n1(-u * 0.22)},${n1(hy + hh * 0.82)} Q0,${n1(hy + hh * 0.7)} ${n1(u * 0.22)},${n1(hy + hh * 0.82)}" fill="none" stroke="#111" stroke-width="${n1(u * 0.07)}" stroke-linecap="round"/>`;
  } else {
    face += `<path d="M${n1(-u * 0.26)},${n1(hy + hh * 0.7)} Q0,${n1(hy + hh * 0.92)} ${n1(u * 0.26)},${n1(hy + hh * 0.7)}" fill="#3a0d0d" stroke="#111" stroke-width="${n1(u * 0.05)}" stroke-linejoin="round"/>`;
  }
  const headG = `${part(hx, hy, hw, hh, head, u * 0.26)}${face}
    <path d="M${n1(hx + u * 0.15)},${n1(hy + u * 0.03)} L${n1(hx + hw - u * 0.15)},${n1(hy + u * 0.03)}" stroke="${rim}" stroke-width="${n1(u * 0.07)}" stroke-linecap="round" opacity="0.9"/>`;
  const torsoG = `${part(-u, -u * 2.05, u * 2, u * 2.05, torso, u * 0.1)}
    <path d="M${n1(-u * 0.85)},${n1(-u * 2.0)} L${n1(u * 0.85)},${n1(-u * 2.0)}" stroke="${rim}" stroke-width="${n1(u * 0.06)}" stroke-linecap="round" opacity="0.8"/>`;
  const hip = Math.cos((legA * Math.PI) / 180) * u * 2.1;
  return `<g>
    ${shadow ? `<ellipse cx="${n1(x)}" cy="${n1((groundY != null ? groundY : y + hip + u * 0.3))}" rx="${n1(u * 2.2)}" ry="${n1(u * 0.35)}" fill="#000" opacity="0.45" filter="url(#blur8)"/>` : ''}
    <g transform="translate(${n1(x)} ${n1(y)}) rotate(${lean})">
      ${heldBehind ? held : ''}
      ${leg(-u * 0.5, legA, legs)}
      ${leg(u * 0.5, -legA, legs)}
      ${torsoG}
      ${arm(-u * 1.5, armL, armCol, prop && prop.side === 'L' ? prop.svg : '')}
      ${arm(u * 1.5, armR, armCol, prop && prop.side === 'R' ? prop.svg : '')}
      ${headG}
      ${heldBehind ? '' : held}
    </g>
  </g>`;
}

// Bonk-Schlaeger im Arm-Koordinatensystem (Arm haengt nach unten, Hand bei y ~ 0)
function bonkBat(px, u) {
  return `<g>
    <rect x="${n1(px - u * 0.13)}" y="${n1(-u * 0.3)}" width="${n1(u * 0.26)}" height="${n1(u * 2.2)}" rx="${n1(u * 0.1)}" fill="#8a5a2b" stroke="#120822" stroke-width="${n1(u * 0.07)}"/>
    <rect x="${n1(px - u * 0.85)}" y="${n1(u * 1.55)}" width="${n1(u * 1.7)}" height="${n1(u * 1.0)}" rx="${n1(u * 0.3)}" fill="#ff4a4a" stroke="#120822" stroke-width="${n1(u * 0.09)}"/>
    <rect x="${n1(px - u * 0.85)}" y="${n1(u * 1.55)}" width="${n1(u * 1.7)}" height="${n1(u * 0.25)}" rx="${n1(u * 0.12)}" fill="#fff" opacity="0.35"/>
  </g>`;
}

// ---------------------------------------------------------------------
//  THUMBNAIL-BAUSTEINE (1920x1080)
// ---------------------------------------------------------------------
const TW = 1920;
const TH = 1080;

function skyDefs(id, top = '#12063a', mid = '#2c0f6e', low = '#5a1f86') {
  return `<linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${top}"/><stop offset="0.55" stop-color="${mid}"/><stop offset="0.8" stop-color="${low}"/></linearGradient>`;
}

function nebula(cx, cy, rx, ry, col, op) {
  const id = uid('n');
  return `<defs><radialGradient id="${id}"><stop offset="0" stop-color="${col}" stop-opacity="${op}"/><stop offset="1" stop-color="${col}" stop-opacity="0"/></radialGradient></defs><ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="url(#${id})"/>`;
}

function thumbSVG(inner, extraDefs = '') {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${TW}" height="${TH}" viewBox="0 0 ${TW} ${TH}">
  <defs>${commonDefs(2)}${extraDefs}</defs>
  ${inner}
</svg>`;
}

function headlineFill() {
  return ['#fffbd0', '#ffd21a', '#ff7a00'];
}

// ------------------------- THUMBNAIL 1 -------------------------
function thumb1() {
  const groundY = 760;
  const ground = `
    <defs>
      <linearGradient id="gr1" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3b1f66"/><stop offset="1" stop-color="#120826"/></linearGradient>
      <radialGradient id="pit1" cx="0.5" cy="0.45" r="0.6"><stop offset="0" stop-color="#ffe07a"/><stop offset="0.22" stop-color="#ff9a1a"/><stop offset="0.55" stop-color="#b8300c"/><stop offset="0.85" stop-color="#3a1030"/><stop offset="1" stop-color="#22092e"/></radialGradient>
      <linearGradient id="rim1" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8a5ab8"/><stop offset="1" stop-color="#3a1f66"/></linearGradient>
    </defs>
    <path d="M0,${groundY - 30} L180,${groundY - 70} L330,${groundY - 40} L520,${groundY - 95} L700,${groundY - 50} L900,${groundY - 85} L1120,${groundY - 40} L1350,${groundY - 100} L1560,${groundY - 55} L1760,${groundY - 90} L1920,${groundY - 50} L1920,${groundY + 40} L0,${groundY + 40}Z" fill="#26114a"/>
    <rect x="0" y="${groundY}" width="${TW}" height="${TH - groundY}" fill="url(#gr1)"/>
    <ellipse cx="900" cy="${groundY + 10}" rx="760" ry="70" fill="#ff7a1a" opacity="0.35" filter="url(#blur60)"/>
    <!-- Krater -->
    <ellipse cx="900" cy="${groundY + 70}" rx="640" ry="150" fill="url(#rim1)" stroke="#120826" stroke-width="8"/>
    <ellipse cx="900" cy="${groundY + 82}" rx="540" ry="112" fill="url(#pit1)"/>
    <ellipse cx="900" cy="${groundY + 30}" rx="420" ry="120" fill="#ff8a1a" opacity="0.35" filter="url(#blur60)"/>
  `;
  // Meteore im Krater
  const inCrater =
    meteor({ x: 700, y: groundY + 92, r: 34, tail: 0, pal: 'blue', seed: 51, glow: 1.1 }) +
    meteor({ x: 1110, y: groundY + 100, r: 30, tail: 0, pal: 'purple', seed: 52, glow: 1.1 }) +
    meteor({ x: 880, y: groundY + 120, r: 44, tail: 0, pal: 'gold', seed: 53, glow: 1.1 }) +
    meteor({ x: 1000, y: groundY + 70, r: 26, tail: 0, pal: 'fire', seed: 54, glow: 1.1 }) +
    meteor({ x: 790, y: groundY + 60, r: 22, tail: 0, pal: 'green', seed: 55, glow: 1.1 });
  // Rauch
  let smoke = '';
  const rs = rng(99);
  for (let i = 0; i < 9; i++) {
    smoke += `<circle cx="${n1(640 + rs() * 520)}" cy="${n1(groundY - 10 - rs() * 140)}" r="${n1(50 + rs() * 60)}" fill="#7a5a9a" opacity="${(0.18 + rs() * 0.14).toFixed(2)}" filter="url(#blur20)"/>`;
  }
  // fallende Meteore im Himmel
  const sky =
    meteor({ x: 1180, y: 150, r: 26, angle: -32, tail: 5, pal: 'fire', seed: 61, sparks: 6 }) +
    meteor({ x: 1640, y: 90, r: 18, angle: -32, tail: 5, pal: 'cyan', seed: 62, sparks: 4 }) +
    meteor({ x: 1060, y: 420, r: 16, angle: -32, tail: 5, pal: 'purple', seed: 63, sparks: 4 });

  // Speed-Linien hinter der Figur
  let speed = '';
  const sr = rng(7);
  for (let i = 0; i < 6; i++) {
    const yy = 560 + i * 70 + sr() * 18;
    const len = 170 + sr() * 220;
    const x2 = 1265 - sr() * 50 - (i > 3 ? 40 : 0);
    speed += `<defs><linearGradient id="sl${i}" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#fff" stop-opacity="0.85"/></linearGradient></defs><rect x="${n1(x2 - len)}" y="${n1(yy)}" width="${n1(len)}" height="12" rx="6" fill="url(#sl${i})"/>`;
  }

  // Haupt-Figur mit Meteor ueber dem Kopf
  const u = 92;
  const heroX = 1440;
  const heroY = 790;
  const carried = meteor({ x: 0, y: -u * 4.85, r: u * 1.5, angle: 194, tail: 2.9, pal: 'fire', seed: 4, glow: 1.25, sparks: 16 });
  const hero = avatar({
    x: heroX, y: heroY, u, lean: 11, legA: 33, armL: -165, armR: 165, armLen: 2.5,
    head: '#ffd23a', torso: '#2a6fe8', legs: '#2fae4a', held: carried, heldBehind: true, groundY: 1010,
  });
  // Verfolger mit Bonk-Schlaeger
  const u2 = 64;
  const chaser = avatar({
    x: 500, y: 850, u: u2, lean: 10, legA: 32, armL: -55, armR: 165,
    head: '#ffd23a', torso: '#e23b3b', legs: '#3a3f66', mask: false, angry: true, rim: '#ff9a40',
    prop: { side: 'R', svg: `<g transform="translate(0 ${n1(-u2 * 0.1)})">${bonkBat(u2 * 1.5, u2)}</g>` },
    groundY: 1000,
  });

  const head1 = txt('KLAU DIE', { x: 70, cy: 175, size: 190, anchor: 'start', fill: headlineFill(), maxW: 1150, sw: 0.17, depth: 0.08, glow: '#ff5a00', glowOp: 0.45 });
  const head2 = txt('METEORE!', { x: 70, cy: 385, size: 210, anchor: 'start', fill: headlineFill(), maxW: 1180, sw: 0.17, depth: 0.08, glow: '#ff5a00', glowOp: 0.45 });

  return thumbSVG(
    `<rect width="${TW}" height="${TH}" fill="url(#sky1)"/>
    ${nebula(1500, 220, 700, 380, '#8a2cff', 0.45)}
    ${nebula(300, 520, 700, 300, '#1e6bff', 0.35)}
    ${nebula(1000, 640, 900, 200, '#ff5a2a', 0.35)}
    ${starField(TW, TH, 320, 1234, { sparkles: 12, yMax: 720 })}
    ${sky}
    ${ground}
    ${smoke}
    ${inCrater}
    ${chaser}
    ${speed}
    ${hero}
    ${head1}${head2}`,
    skyDefs('sky1')
  );
}

// ------------------------- THUMBNAIL 2 -------------------------
function shield(cx, cy, w, h) {
  const id = uid('sh');
  const d = `M${cx},${cy - h / 2} C${cx + w * 0.3},${cy - h / 2 + h * 0.08} ${cx + w * 0.42},${cy - h / 2 + h * 0.06} ${cx + w / 2},${cy - h / 2 + h * 0.02} L${cx + w / 2},${cy - h * 0.05} C${cx + w / 2},${cy + h * 0.25} ${cx + w * 0.25},${cy + h * 0.42} ${cx},${cy + h / 2} C${cx - w * 0.25},${cy + h * 0.42} ${cx - w / 2},${cy + h * 0.25} ${cx - w / 2},${cy - h * 0.05} L${cx - w / 2},${cy - h / 2 + h * 0.02} C${cx - w * 0.42},${cy - h / 2 + h * 0.06} ${cx - w * 0.3},${cy - h / 2 + h * 0.08} ${cx},${cy - h / 2}Z`;
  return `<g>
    <defs>
      <linearGradient id="${id}a" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="0.35" stop-color="#ffc6f0"/><stop offset="0.7" stop-color="#d55cff"/><stop offset="1" stop-color="#7a2cff"/></linearGradient>
      <linearGradient id="${id}b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3a0a5e"/><stop offset="1" stop-color="#14052a"/></linearGradient>
    </defs>
    <path d="${d}" fill="#ff9ae8" opacity="0.8" filter="url(#blur60)"/>
    <path d="${d}" fill="#0a0216" transform="translate(0 18)"/>
    <path d="${d}" fill="url(#${id}a)" stroke="#14062a" stroke-width="16" stroke-linejoin="round"/>
    <g transform="translate(${cx} ${cy}) scale(0.84) translate(${-cx} ${-cy})"><path d="${d}" fill="url(#${id}b)" stroke="#ffffff" stroke-opacity="0.8" stroke-width="6"/></g>
    ${txt('?', { x: cx, cy: cy - h * 0.12, size: h * 0.42, fill: FILL.pink, maxW: w * 0.6, sw: 0.14 })}
    ${sparkle(cx - w * 0.28, cy - h * 0.26, 26, '#ffffff', 1)}
    ${sparkle(cx + w * 0.27, cy + h * 0.06, 18, '#ffd6f4', 1)}
  </g>`;
}

function ribbon(cx, cy, w, h, text, { fill = ['#ff7ad9', '#c21aa0'], textFill = FILL.white, size = null } = {}) {
  const id = uid('rb');
  const t = h * 0.5;
  return `<g>
    <defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${fill[0]}"/><stop offset="1" stop-color="${fill[1]}"/></linearGradient></defs>
    <path d="M${cx - w / 2 - t},${cy - h / 2 + 20} L${cx - w / 2 + 10},${cy - h / 2 + 20} L${cx - w / 2 + 10},${cy + h / 2 + 20} L${cx - w / 2 - t},${cy + h / 2 + 20} L${cx - w / 2 - t * 0.55},${cy + 20}Z" fill="#8a0a70" stroke="#14062a" stroke-width="10" stroke-linejoin="round"/>
    <path d="M${cx + w / 2 + t},${cy - h / 2 + 20} L${cx + w / 2 - 10},${cy - h / 2 + 20} L${cx + w / 2 - 10},${cy + h / 2 + 20} L${cx + w / 2 + t},${cy + h / 2 + 20} L${cx + w / 2 + t * 0.55},${cy + 20}Z" fill="#8a0a70" stroke="#14062a" stroke-width="10" stroke-linejoin="round"/>
    <rect x="${cx - w / 2}" y="${cy - h / 2}" width="${w}" height="${h}" rx="12" fill="url(#${id})" stroke="#14062a" stroke-width="12"/>
    <rect x="${cx - w / 2 + 12}" y="${cy - h / 2 + 10}" width="${w - 24}" height="${h * 0.22}" rx="8" fill="#fff" opacity="0.3"/>
    ${txt(text, { x: cx, cy, size: size || h * 0.62, fill: textFill, maxW: w - 50, sw: 0.18, depth: 0.07 })}
  </g>`;
}

function thumb2() {
  const mx = 1270;
  const my = 560;
  let rays = '';
  const nR = 28;
  for (let i = 0; i < nR; i++) {
    const a0 = (i / nR) * Math.PI * 2;
    const a1 = a0 + (Math.PI * 2) / nR / 2;
    rays += `<path d="M${mx},${my} L${n1(mx + Math.cos(a0) * 1800)},${n1(my + Math.sin(a0) * 1800)} L${n1(mx + Math.cos(a1) * 1800)},${n1(my + Math.sin(a1) * 1800)}Z"/>`;
  }
  let sp = '';
  const r = rng(321);
  for (let i = 0; i < 22; i++) {
    const a = r() * Math.PI * 2;
    const d = 330 + r() * 260;
    sp += sparkle(mx + Math.cos(a) * d, my + Math.sin(a) * d * 0.8, 10 + r() * 22, r() < 0.5 ? '#ffffff' : '#ffd0f2', 0.95);
  }
  const head1 = txt('', {
    x: 960, cy: 128, size: 150, fill: headlineFill(), maxW: 1800, sw: 0.17, glow: '#ff3dc8', glowOp: 0.5,
    tspans: [{ text: 'SECRET ', fill: ['#ffffff', '#ffe0f6', '#ff7ad9'] }, { text: 'METEOR' }],
  });
  const head2 = txt('GEFUNDEN!', { x: 960, cy: 955, size: 175, fill: headlineFill(), maxW: 1500, sw: 0.17, glow: '#ff5a00', glowOp: 0.45 });
  return thumbSVG(
    `<rect width="${TW}" height="${TH}" fill="url(#sky2)"/>
    ${nebula(mx, my, 1000, 700, '#ff3dc8', 0.45)}
    ${nebula(300, 300, 700, 500, '#5a2cff', 0.45)}
    ${nebula(400, 900, 700, 300, '#1e6bff', 0.35)}
    <defs><radialGradient id="rayF2"><stop offset="0.1" stop-color="#fff" stop-opacity="1"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient><mask id="rayM2"><circle cx="${mx}" cy="${my}" r="1100" fill="url(#rayF2)"/></mask></defs>
    <g fill="#ffe6fa" opacity="0.16" mask="url(#rayM2)">${rays}</g>
    ${starField(TW, TH, 300, 4321, { sparkles: 14 })}
    <circle cx="${mx}" cy="${my}" r="420" fill="#ffd6f6" opacity="0.35" filter="url(#blur60)"/>
    ${meteor({ x: mx, y: my, r: 245, angle: -32, tail: 2.8, pal: 'secret', seed: 12, glow: 1.25, sparks: 20 })}
    ${sparkle(mx - 120, my - 90, 34, '#ffffff', 1)}${sparkle(mx + 95, my + 120, 24, '#ffffff', 0.95)}${sparkle(mx + 40, my - 160, 18, '#ffffff', 0.9)}
    ${sp}
    ${avatar({ x: 1765, y: 905, u: 50, lean: -4, legA: 10, armL: 148, armR: -148, head: '#ffd23a', torso: '#2a6fe8', legs: '#2fae4a', rim: '#ffc6f2', groundY: 1012 })}
    ${shield(520, 545, 400, 460)}
    ${ribbon(520, 690, 520, 130, 'SECRET', { fill: ['#ff86e0', '#c018a8'] })}
    ${head1}${head2}`,
    skyDefs('sky2', '#14052e', '#2a0a5a', '#4a0f6e')
  );
}

// ------------------------- THUMBNAIL 3 -------------------------
function pill(cx, cy, text, { fill = ['#3dff6e', '#0a9a3a'], emoji = '', size = 70, w = 560 } = {}) {
  const id = uid('pl');
  const h = size * 1.6;
  return `<g>
    <defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${fill[0]}"/><stop offset="1" stop-color="${fill[1]}"/></linearGradient></defs>
    <rect x="${cx - w / 2}" y="${cy - h / 2 + 12}" width="${w}" height="${h}" rx="${h / 2}" fill="#0a0216"/>
    <rect x="${cx - w / 2}" y="${cy - h / 2}" width="${w}" height="${h}" rx="${h / 2}" fill="url(#${id})" stroke="#14062a" stroke-width="12"/>
    <rect x="${cx - w / 2 + 26}" y="${cy - h / 2 + 10}" width="${w - 52}" height="${h * 0.25}" rx="${h * 0.12}" fill="#fff" opacity="0.3"/>
    ${emoji ? emo(emoji, { x: cx - w / 2 + h * 0.62, y: cy + 2, size: size * 1.12, filter: 'url(#dropS)' }) : ''}
    ${txt(text, { x: emoji ? cx + h * 0.32 : cx, cy, size, fill: FILL.white, maxW: w - (emoji ? h * 1.35 : 70), sw: 0.18, depth: 0.07 })}
  </g>`;
}

function thumb3() {
  const groundY = 900;
  const pals = ['fire', 'fire', 'fire', 'fire', 'blue', 'purple', 'gold', 'mythic', 'cyan', 'green', 'fire', 'gold'];
  const r = rng(2024);
  const items = [];
  // Hintergrund-Meteore (klein), dann vordere (gross)
  const spots = [
    [140, 120, 30], [460, 60, 22], [1290, 175, 24], [1080, 70, 18], [1450, 120, 34], [1740, 60, 26],
    [180, 610, 40], [620, 660, 30], [980, 700, 46], [1300, 640, 32], [1800, 560, 44], [1880, 420, 24],
    [80, 420, 30], [1360, 820, 36], [500, 830, 36], [1120, 880, 24], [860, 790, 22], [1900, 820, 30],
  ];
  spots.forEach(([x, y, rr], i) => {
    items.push({ x, y, r: rr, pal: pals[(r() * pals.length) | 0], seed: 300 + i });
  });
  items.sort((a, b) => a.r - b.r);
  const mets = items
    .map((m) => meteor({ x: m.x, y: m.y, r: m.r, angle: -36, tail: 5.2, pal: m.pal, seed: m.seed, sparks: 6, glow: 1.1 }))
    .join('');
  const big =
    meteor({ x: 1640, y: 760, r: 92, angle: -36, tail: 3.6, pal: 'fire', seed: 901, glow: 1.2, sparks: 14 }) +
    meteor({ x: 230, y: 760, r: 78, angle: -36, tail: 3.6, pal: 'gold', seed: 902, glow: 1.2, sparks: 12 });
  // Boden + Einschlaege
  let impacts = '';
  [[420, groundY + 50, 1.0], [1000, groundY + 80, 1.3], [1560, groundY + 40, 0.9]].forEach(([x, y, s], i) => {
    impacts += `<ellipse cx="${x}" cy="${y}" rx="${n1(220 * s)}" ry="${n1(55 * s)}" fill="#ff9a1a" opacity="0.6" filter="url(#blur20)"/>
      <ellipse cx="${x}" cy="${y}" rx="${n1(150 * s)}" ry="${n1(32 * s)}" fill="#2a0f30" stroke="#ffb040" stroke-width="6"/>
      <ellipse cx="${x}" cy="${y + 2}" rx="${n1(90 * s)}" ry="${n1(18 * s)}" fill="#ffcf5a" opacity="0.9" filter="url(#blur8)"/>`;
    impacts += meteor({ x, y: y - 18 * s, r: 30 * s, tail: 0, pal: ['purple', 'fire', 'blue'][i], seed: 700 + i, glow: 1.3 });
  });
  const headline = txt('METEORITENSCHAUER!', { x: 960, cy: 300, size: 150, fill: headlineFill(), maxW: 1830, sw: 0.17, glow: '#ff5a00', glowOp: 0.55 });
  const ev = ribbon(960, 110, 420, 110, 'EVENT', { fill: ['#ff5a5a', '#c2000f'] });
  const badges =
    // 600 + 50 Luecke + 700 = 1350 px breit, mittig um x = 960 (vorher beruehrten sich die Pillen)
    pill(585, 500, '3X GLÜCK', { fill: ['#47ff7a', '#0a9a3a'], emoji: '🍀', size: 72, w: 600 }) +
    pill(1285, 500, 'KEINE LOCKS!', { fill: ['#5aa8ff', '#1240c0'], emoji: '🔓', size: 72, w: 700 });

  return thumbSVG(
    `<rect width="${TW}" height="${TH}" fill="url(#sky3)"/>
    ${nebula(960, 820, 1300, 420, '#ff5a1a', 0.55)}
    ${nebula(400, 200, 700, 400, '#8a2cff', 0.45)}
    ${nebula(1600, 260, 700, 400, '#1e6bff', 0.35)}
    ${starField(TW, TH, 300, 777, { sparkles: 10, yMax: 860 })}
    <defs><linearGradient id="gr3" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4a1f5c"/><stop offset="1" stop-color="#140826"/></linearGradient></defs>
    <path d="M0,${groundY - 20} L240,${groundY - 60} L470,${groundY - 25} L760,${groundY - 70} L1040,${groundY - 30} L1330,${groundY - 75} L1620,${groundY - 30} L1920,${groundY - 65} L1920,${TH} L0,${TH}Z" fill="url(#gr3)"/>
    ${mets}
    ${impacts}
    ${big}
    ${ev}
    ${headline}
    ${badges}`,
    skyDefs('sky3', '#14062e', '#3a0f5e', '#8a2a4a')
  );
}

// ---------------------------------------------------------------------
//  SCREENSHOT-MODUS: Spiel-Icon + Thumbnails aus echten In-Game-Bildern.
//  Der Screenshot wird "cover"-skaliert (gleichmaessig, nie verzerrt,
//  ueberstehende Raender werden abgeschnitten), leicht farbkorrigiert
//  (mehr Saettigung/Kontrast), bekommt eine Vignette und dunkle Verlaeufe
//  hinter den Ueberschriften. Texte/Baender/Pillen = dieselben Bausteine
//  wie bei den gezeichneten Thumbnails.
// ---------------------------------------------------------------------
const SHOT_NAMES = ['base', 'krater', 'tragen', 'showcase', 'secret'];
const SHOT_EXTS = ['.png', '.jpg', '.jpeg']; // Reihenfolge = Vorrang bei doppelten Namen
const DEFAULT_SCREENS_DIR = path.resolve(__dirname, '..', '..', 'screenshots');
const SHOT_HREF = '__SCREENSHOT_HREF__'; // Platzhalter, wird beim Rendern ersetzt
const SHOT_UPSCALE_WARN = 1.5; // ab dieser Vergroesserung Hinweis "Aufloesung zu gering"

function findScreens(dir) {
  const found = {};
  const warnings = [];
  const files = fs
    .readdirSync(dir)
    .filter((f) => {
      try {
        return fs.statSync(path.join(dir, f)).isFile();
      } catch (e) {
        return false; // z. B. kaputter Link
      }
    })
    .sort((a, b) => {
      const ka = path.basename(a, path.extname(a)).toLowerCase();
      const kb = path.basename(b, path.extname(b)).toLowerCase();
      if (ka !== kb) return ka < kb ? -1 : 1;
      return SHOT_EXTS.indexOf(path.extname(a).toLowerCase()) - SHOT_EXTS.indexOf(path.extname(b).toLowerCase());
    });
  for (const f of files) {
    const ext = path.extname(f).toLowerCase();
    const name = path.basename(f, path.extname(f)).toLowerCase();
    const isImage = /^\.(png|jpe?g|webp|gif|bmp|heic|heif|avif|tiff?)$/.test(ext);
    if (!isImage) continue; // z. B. README.md
    if (!SHOT_EXTS.includes(ext)) {
      warnings.push(`${f}: Format nicht unterstuetzt - bitte als .png oder .jpg speichern.`);
      continue;
    }
    if (!SHOT_NAMES.includes(name)) {
      warnings.push(`${f}: unbekannter Name, wird ignoriert (erlaubt: ${SHOT_NAMES.join(', ')}).`);
      continue;
    }
    if (found[name]) {
      warnings.push(`${f}: es gibt schon ${path.basename(found[name].file)} fuer "${name}" - ${f} wird ignoriert.`);
      continue;
    }
    found[name] = { name, file: path.join(dir, f) };
  }
  return { found, warnings };
}

function sniffMime(buf) {
  if (buf.slice(0, 8).toString('hex') === '89504e470d0a1a0a') return 'image/png';
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  return null;
}

// Ist die Datei vollstaendig? (abgebrochener Download/Upload/Kopiervorgang)
// Chromium zeigt abgeschnittene Bilder sonst kommentarlos nur halb an
// (Rest leer) -> fast schwarzes Thumbnail ohne jede Warnung.
function isComplete(buf, mime) {
  if (mime === 'image/png') {
    // Chunks ablaufen, bis IEND kommt
    let off = 8;
    while (off + 12 <= buf.length) {
      const len = buf.readUInt32BE(off);
      const type = buf.toString('latin1', off + 4, off + 8);
      off += 12 + len;
      if (off > buf.length) return false;
      if (type === 'IEND') return true;
    }
    return false;
  }
  // JPEG: Segmente ablaufen (APPn samt eingebettetem Vorschaubild wird per
  // Laenge uebersprungen), nach SOS die Bilddaten bis zum naechsten Marker
  // durchsuchen. Vollstaendig = EOI-Marker (FFD9) erreicht.
  const isRst = (m) => m >= 0xd0 && m <= 0xd7;
  let off = 2;
  while (off + 2 <= buf.length) {
    if (buf[off] !== 0xff) return false;
    const m = buf[off + 1];
    if (m === 0xd9) return true;
    if (m === 0xff) { off++; continue; } // Fuellbyte
    if (m === 0x01 || isRst(m)) { off += 2; continue; }
    if (off + 4 > buf.length) return false;
    off += 2 + buf.readUInt16BE(off + 2);
    if (m === 0xda) {
      while (off + 1 < buf.length && !(buf[off] === 0xff && buf[off + 1] !== 0x00 && !isRst(buf[off + 1]))) off++;
      if (off + 1 >= buf.length) return false;
    }
  }
  return false;
}

// Laedt den Screenshot im Browser, misst die echte Groesse und erkennt
// einfarbige Raender (Fensterrahmen, Titelleiste, schwarze Balken,
// transparente Schatten), die vor dem Zuschneiden entfernt werden.
async function analyseShot(page, shot) {
  const buf = fs.readFileSync(shot.file);
  const mime = sniffMime(buf);
  if (!mime) throw new Error('Datei ist kein gueltiges PNG/JPG');
  if (!isComplete(buf, mime)) throw new Error('Datei ist unvollstaendig/abgeschnitten - bitte neu speichern bzw. neu kopieren');
  const url = `data:${mime};base64,${buf.toString('base64')}`;
  const res = await page.evaluate(async (url) => {
    const img = new Image();
    img.src = url;
    await img.decode();
    const W = img.naturalWidth;
    const H = img.naturalHeight;
    const c = document.createElement('canvas');
    c.width = W;
    c.height = H;
    const ctx = c.getContext('2d', { willReadFrequently: true });
    ctx.drawImage(img, 0, 0);
    const d = ctx.getImageData(0, 0, W, H).data;
    const TOL = 26; // erlaubte Abweichung je Farbkanal innerhalb einer Linie
    const SHARE = 0.9; // so viel der Linie muss "gleichfarbig" sein
    const EDGE = 12; // Farbsprung, der einen Rahmen vom Bildinhalt trennt
    const CAP = 0.09; // max. 9 % je Seite; laenger = Bildinhalt (z. B. Himmel), nicht Rahmen
    const diff = (a, b) => Math.max(...a.map((v, i) => Math.abs(v - b[i])));
    // Liefert Median-Farbe (RGBA) einer Linie und ob sie (fast) einfarbig ist
    const line = (n, at) => {
      const step = Math.max(1, Math.floor(n / 1200));
      const hist = [0, 1, 2, 3].map(() => new Uint32Array(256));
      let cnt = 0;
      for (let i = 0; i < n; i += step) {
        const p = at(i) * 4;
        for (let ch = 0; ch < 4; ch++) hist[ch][d[p + ch]]++;
        cnt++;
      }
      const med = hist.map((h) => {
        let s = 0;
        for (let v = 0; v < 256; v++) {
          s += h[v];
          if (s * 2 >= cnt) return v;
        }
        return 255;
      });
      let ok = 0;
      for (let i = 0; i < n; i += step) {
        const p = at(i) * 4;
        if (
          Math.abs(d[p] - med[0]) <= TOL && Math.abs(d[p + 1] - med[1]) <= TOL &&
          Math.abs(d[p + 2] - med[2]) <= TOL && Math.abs(d[p + 3] - med[3]) <= TOL
        ) ok++;
      }
      return { med, uni: ok >= cnt * SHARE };
    };
    // Anteil der Pixel einer Linie, die (fast) die Farbe col haben
    const share = (n, at, col) => {
      const step = Math.max(1, Math.floor(n / 1200));
      let cnt = 0;
      let ok = 0;
      for (let i = 0; i < n; i += step) {
        const p = at(i) * 4;
        if (diff([d[p], d[p + 1], d[p + 2], d[p + 3]], col) <= EDGE) ok++;
        cnt++;
      }
      return ok / cnt;
    };
    // Rahmen = einfarbige Linien vom Rand an, die mit einem klaren Farbsprung
    // enden. Mehrere Schichten (z. B. 1-px-Rand + Titelleiste) werden
    // nacheinander abgeschaelt. Reicht ein Streifen bis CAP oder geht er
    // ohne Farbsprung in den Inhalt ueber (Himmel, Boden), bleibt er stehen.
    const band = (len, cross, at) => {
      const cap = Math.max(1, Math.floor(len * CAP));
      const info = (k) => line(cross, (i) => at(k, i));
      let total = 0;
      for (;;) {
        let k = total;
        let prev = null;
        while (k < cap) {
          const l = info(k);
          if (!l.uni || (prev && diff(l.med, prev) > EDGE)) break;
          prev = l.med;
          k++;
        }
        // naechste Linie muss sich klar vom Streifen abheben (hoechstens halb so viel gleiche Farbe)
        if (k === total || k >= cap || share(cross, (i) => at(k, i), prev) > 0.5) return total;
        total = k;
      }
    };
    const top = band(H, W, (k, i) => k * W + i);
    const bottom = band(H, W, (k, i) => (H - 1 - k) * W + i);
    const rows = H - top - bottom;
    const left = band(W, rows, (k, i) => (top + i) * W + k);
    const right = band(W, rows, (k, i) => (top + i) * W + (W - 1 - k));
    return { w: W, h: H, trim: { top, bottom, left, right } };
  }, url);
  const t = res.trim;
  return {
    ...shot, ...res, url,
    crop: { x: t.left, y: t.top, w: res.w - t.left - t.right, h: res.h - t.top - t.bottom },
  };
}

// "cover": gleichmaessiger Massstab, Zielflaeche immer voll bedeckt.
// fx/fy = wohin (Anteil der Zielbreite/-hoehe) die Mitte des Screenshots
// kommt; zoom > 1 zeigt einen engeren Ausschnitt um die Bildmitte.
function shotPlacement(shot, W, H, { zoom = 1, fx = 0.5, fy = 0.5 } = {}) {
  const c = shot.crop;
  const tx = W * fx;
  const ty = H * fy;
  const s = zoom * Math.max((2 * Math.max(tx, W - tx)) / c.w, (2 * Math.max(ty, H - ty)) / c.h);
  return { s, x: tx - (c.x + c.w / 2) * s, y: ty - (c.y + c.h / 2) * s, w: shot.w * s, h: shot.h * s };
}

// Hintergrund-Ebenen: Screenshot (farbkorrigiert) + Vignette + dunkle
// Verlaeufe oben/unten (Hoehe in px, 0 = keiner) hinter den Ueberschriften.
function shotBackdrop(W, H, pl, { top = 0, bottom = 0, shade = 0.8 } = {}) {
  const contrast = 1.12;
  const icpt = n1((0.5 - 0.5 * contrast) * 1000) / 1000;
  const func = (ch) => `<feFunc${ch} type="linear" slope="${contrast}" intercept="${icpt}"/>`;
  const fade = (id, flip) => {
    const st = [[0, shade], [0.5, shade * 0.66], [1, 0]];
    return `<linearGradient id="${id}" x1="0" y1="${flip ? 1 : 0}" x2="0" y2="${flip ? 0 : 1}">${st
      .map(([o, a]) => `<stop offset="${o}" stop-color="#0c0428" stop-opacity="${n1(a * 100) / 100}"/>`)
      .join('')}</linearGradient>`;
  };
  return `<defs>
    <filter id="shotGrade" filterUnits="userSpaceOnUse" x="0" y="0" width="${W}" height="${H}" color-interpolation-filters="sRGB">
      <feColorMatrix type="saturate" values="1.3"/>
      <feComponentTransfer>${func('R')}${func('G')}${func('B')}</feComponentTransfer>
    </filter>
    <radialGradient id="shotVig" cx="0.5" cy="0.5" r="0.72"><stop offset="0.45" stop-color="#07021a" stop-opacity="0"/><stop offset="0.8" stop-color="#07021a" stop-opacity="0.3"/><stop offset="1" stop-color="#07021a" stop-opacity="0.62"/></radialGradient>
    ${fade('shotFadeT', false)}${fade('shotFadeB', true)}
  </defs>
  <rect width="${W}" height="${H}" fill="#0b0620"/>
  <g filter="url(#shotGrade)"><image class="shot" href="${SHOT_HREF}" x="${n1(pl.x)}" y="${n1(pl.y)}" width="${n1(pl.w)}" height="${n1(pl.h)}" preserveAspectRatio="xMidYMid meet"/></g>
  <rect width="${W}" height="${H}" fill="url(#shotVig)"/>
  ${top ? `<rect x="0" y="0" width="${W}" height="${top}" fill="url(#shotFadeT)"/>` : ''}
  ${bottom ? `<rect x="0" y="${H - bottom}" width="${W}" height="${bottom}" fill="url(#shotFadeB)"/>` : ''}`;
}

const HEAD = { sw: 0.17, depth: 0.08, glow: '#ff5a00', glowOp: 0.5 };

function shotThumb1(pl) {
  const head = txt('', {
    x: 960, cy: 150, size: 178, fill: headlineFill(), maxW: 1800, ...HEAD,
    tspans: [{ text: 'KLAU DIE ', fill: FILL.white }, { text: 'METEORE!' }],
  });
  return thumbSVG(shotBackdrop(TW, TH, pl, { top: 440 }) + head);
}

function shotThumb2(pl) {
  const head1 = txt('', {
    x: 960, cy: 135, size: 160, fill: headlineFill(), maxW: 1800, ...HEAD, glow: '#ff3dc8',
    tspans: [{ text: 'SECRET ', fill: ['#ffffff', '#ffe0f6', '#ff7ad9'] }, { text: 'METEOR' }],
  });
  const head2 = txt('GEFUNDEN!', { x: 960, cy: 950, size: 175, fill: headlineFill(), maxW: 1500, ...HEAD });
  return thumbSVG(shotBackdrop(TW, TH, pl, { top: 400, bottom: 400 }) + head1 + head2);
}

function shotThumb3(pl) {
  const ev = ribbon(960, 100, 400, 104, 'EVENT', { fill: ['#ff5a5a', '#c2000f'] });
  const headline = txt('METEORITENSCHAUER!', { x: 960, cy: 285, size: 150, fill: headlineFill(), maxW: 1830, ...HEAD, glowOp: 0.55 });
  const badges =
    pill(585, 960, '3X GLÜCK', { fill: ['#47ff7a', '#0a9a3a'], emoji: '🍀', size: 72, w: 600 }) +
    pill(1285, 960, 'KEINE LOCKS!', { fill: ['#5aa8ff', '#1240c0'], emoji: '🔓', size: 72, w: 700 });
  return thumbSVG(shotBackdrop(TW, TH, pl, { top: 500, bottom: 330 }) + ev + headline + badges);
}

function shotThumb4(pl) {
  const head = txt('WERDE REICH!', { x: 960, cy: 150, size: 200, fill: headlineFill(), maxW: 1800, ...HEAD });
  const sub = txt('DEINE BASE VOLLER METEORE', { x: 960, cy: 315, size: 80, fill: FILL.white, maxW: 1500, sw: 0.2, depth: 0.08 });
  return thumbSVG(shotBackdrop(TW, TH, pl, { top: 500 }) + head + sub);
}

function shotThumb5(pl) {
  const head1 = txt('', {
    x: 960, cy: 140, size: 190, fill: headlineFill(), maxW: 1800, ...HEAD,
    tspans: [{ text: '27 ', fill: ['#ffffff', '#c4f6ff', '#1ed2ff'] }, { text: 'METEORE' }],
  });
  const head2 = txt('ZUM SAMMELN!', { x: 960, cy: 950, size: 165, fill: headlineFill(), maxW: 1700, ...HEAD });
  return thumbSVG(shotBackdrop(TW, TH, pl, { top: 420, bottom: 400 }) + head1 + head2);
}

function shotGameIcon(pl) {
  const S = 512;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${S}" height="${S}" viewBox="0 0 ${S} ${S}">
  <defs>${commonDefs(1)}</defs>
  ${shotBackdrop(S, S, pl, { bottom: 260, shade: 0.88 })}
  ${txt('METEOR', { x: 256, cy: 348, size: 104, fill: FILL.fire, maxW: 470, glow: '#ff6a00', glowOp: 0.55 })}
  ${txt('HEIST', { x: 256, cy: 436, size: 116, fill: ['#ffffff', '#e8f0ff', '#8fc8ff'], stroke: '#0a0a36', maxW: 430, glow: '#4a8cff', glowOp: 0.5 })}
</svg>`;
}

// ---------------------------------------------------------------------
//  SEITE + RENDERN
// ---------------------------------------------------------------------
function pageHTML(w, h, svg) {
  return `<!doctype html><html><head><meta charset="utf-8"><style>
  html,body{margin:0;padding:0;width:${w}px;height:${h}px;overflow:hidden;background:#0b0620}
  html.check,html.check body{background:transparent}
  html.check .bg-layer,html.check .deco{display:none}
  svg{display:block}
  .t{font-family:'DejaVu Sans','Liberation Sans',sans-serif;font-weight:700}
  .e{font-family:'Noto Color Emoji';font-weight:400}
  </style></head><body>${svg}</body></html>`;
}

// shot.from = Screenshot-Namen in Vorrang-Reihenfolge. Ist keiner davon da,
// wird svg() gezeichnet; Jobs ohne svg (thumbnail-4/5) werden dann uebersprungen.
const JOBS = [
  ...ICONS.map((ic) => ({ file: ic.file, w: 512, h: 512, kind: 'circle', desc: ic.desc, svg: () => iconSVG(ic) })),
  { file: 'spiel-icon.png', w: 512, h: 512, kind: 'square', desc: 'Spiel-Icon: riesiger gluehender Meteor mit Feuerschweif im Weltall, darunter METEOR HEIST.', svg: gameIconSVG,
    // engerer Ausschnitt um die Bildmitte; die Bildmitte landet ueber dem Schriftzug
    shot: { from: ['secret', 'showcase', 'base'], svg: shotGameIcon, place: { zoom: 1.15, fy: 0.4 } } },
  { file: 'thumbnail-1.png', w: TW, h: TH, kind: 'square', desc: 'Thumbnail 1: "KLAU DIE METEORE!" - maskierte Blockfigur rennt mit gluehendem Meteor ueber dem Kopf, Verfolger mit Bonk-Schlaeger, Krater.', svg: thumb1,
    shot: { from: ['tragen'], svg: shotThumb1 } },
  { file: 'thumbnail-2.png', w: TW, h: TH, kind: 'square', desc: 'Thumbnail 2: "SECRET METEOR GEFUNDEN!" - riesiger weiss-pinker Meteor mit Glow und Strahlen, Schild mit "SECRET"-Band.', svg: thumb2,
    shot: { from: ['secret', 'showcase'], svg: shotThumb2 } },
  { file: 'thumbnail-3.png', w: TW, h: TH, kind: 'square', desc: 'Thumbnail 3: "METEORITENSCHAUER!" - viele bunte Meteore regnen schraeg herab, EVENT-Band, 3X GLUECK und KEINE LOCKS!.', svg: thumb3,
    shot: { from: ['krater'], svg: shotThumb3 } },
  { file: 'thumbnail-4.png', w: TW, h: TH, kind: 'square', desc: 'Thumbnail 4 (nur mit Screenshot "base"): "WERDE REICH!" - Deine Base voller Meteore.', svg: null,
    shot: { from: ['base'], svg: shotThumb4 } },
  { file: 'thumbnail-5.png', w: TW, h: TH, kind: 'square', desc: 'Thumbnail 5 (nur mit Screenshot "showcase"): "27 METEORE ZUM SAMMELN!".', svg: null,
    shot: { from: ['showcase'], svg: shotThumb5 } },
];

function pngSize(file) {
  const b = fs.readFileSync(file);
  const sig = b.slice(0, 8).toString('hex');
  if (sig !== '89504e470d0a1a0a') throw new Error(`${file} ist kein PNG`);
  return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
}

async function analyseAlpha(page, buf, R) {
  return page.evaluate(
    async ({ b64, R }) => {
      const img = new Image();
      img.src = 'data:image/png;base64,' + b64;
      await img.decode();
      const c = document.createElement('canvas');
      c.width = img.width;
      c.height = img.height;
      const ctx = c.getContext('2d');
      ctx.drawImage(img, 0, 0);
      const d = ctx.getImageData(0, 0, c.width, c.height).data;
      const cx = c.width / 2;
      const cy = c.height / 2;
      let maxD = 0;
      let outside = 0;
      for (let y = 0; y < c.height; y++) {
        for (let x = 0; x < c.width; x++) {
          if (d[(y * c.width + x) * 4 + 3] > 128) {
            const dd = Math.hypot(x + 0.5 - cx, y + 0.5 - cy);
            if (dd > maxD) maxD = dd;
            if (dd > R) outside++;
          }
        }
      }
      return { maxD, outside };
    },
    { b64: buf.toString('base64'), R }
  );
}

async function fitText(page) {
  return page.evaluate(() => {
    const out = [];
    document.querySelectorAll('g.fit').forEach((g) => {
      const main = g.querySelector('text[data-main]');
      const maxW = +g.dataset.maxw;
      const sw = +g.dataset.sw || 0;
      const w = main.getBBox().width + sw;
      if (w > maxW) {
        const k = maxW / w;
        const cx = +g.dataset.cx;
        const cy = +g.dataset.cy;
        g.setAttribute('transform', `translate(${cx} ${cy}) scale(${k}) translate(${-cx} ${-cy})`);
        out.push({ text: main.textContent, k: Math.round(k * 1000) / 1000 });
      }
    });
    return out;
  });
}

async function textBounds(page, W, H, margin) {
  return page.evaluate(
    ({ W, H, margin }) => {
      const bad = [];
      document.querySelectorAll('g.fit').forEach((g) => {
        const main = g.querySelector('text[data-main]');
        const bb = main.getBBox();
        const size = +main.getAttribute('font-size');
        const sw = +g.dataset.sw || 0;
        const cy = +g.dataset.cy;
        const up = /[ÄÖÜ]/.test(main.textContent) ? 0.52 : 0.4; // Umlaut-Punkte ragen hoeher
        // Box in Text-Koordinaten: Breite aus BBox, Hoehe aus Versalhoehe + Rand + 3D-Schatten
        const x0 = bb.x - sw / 2;
        const x1 = bb.x + bb.width + sw / 2;
        const y0 = cy - size * up - sw / 2;
        const y1 = cy + size * 0.37 + sw / 2 + size * 0.09;
        const m = main.getScreenCTM();
        const pts = [[x0, y0], [x1, y0], [x0, y1], [x1, y1]].map(([x, y]) => new DOMPoint(x, y).matrixTransform(m));
        const box = {
          l: Math.min(...pts.map((p) => p.x)), r: Math.max(...pts.map((p) => p.x)),
          t: Math.min(...pts.map((p) => p.y)), b: Math.max(...pts.map((p) => p.y)),
        };
        if (box.l < margin || box.t < margin || box.r > W - margin || box.b > H - margin) {
          bad.push({ text: main.textContent, box: Object.fromEntries(Object.entries(box).map(([a, b]) => [a, Math.round(b)])) });
        }
      });
      return bad;
    },
    { W, H, margin }
  );
}

const USAGE = `Benutzung: node generate.js [Optionen] [Filter ...]
  Filter              nur Bilder, deren Dateiname den Text enthaelt (z. B. thumbnail, pass-vip)
  --screens <ordner>  In-Game-Screenshots (Standard: ${DEFAULT_SCREENS_DIR})
  --out <ordner>      Ausgabe-Ordner (Standard: ${OUT_DIR})
  --no-screens        Screenshots ignorieren, alles zeichnen
  --html              HTML-Seiten zusaetzlich nach ./html/ (bzw. <out>/html/) schreiben
  --help              diese Hilfe`;

// Bedienfehler (falsche Option, Ordner fehlt): ohne Stacktrace melden
const userError = (msg) => Object.assign(new Error(msg), { user: true });

function parseArgs(argv) {
  const o = { screens: null, out: null, noScreens: false, html: false, filters: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const m = /^--(screens|out)(?:=(.*))?$/.exec(a);
    if (m) {
      const v = m[2] !== undefined ? m[2] : argv[++i];
      if (!v || v.startsWith('--')) throw userError(`--${m[1]} braucht einen Ordner.\n\n${USAGE}`);
      o[m[1]] = path.resolve(v);
    } else if (a === '--no-screens') o.noScreens = true;
    else if (a === '--html') o.html = true;
    else if (a === '--help' || a === '-h') o.help = true;
    else if (a.startsWith('--')) throw userError(`Unbekannte Option: ${a}\n\n${USAGE}`);
    else o.filters.push(a);
  }
  return o;
}

async function main() {
  const opt = parseArgs(process.argv.slice(2));
  if (opt.help) return console.log(USAGE);
  const outDir = opt.out || OUT_DIR;
  const htmlDir = opt.out ? path.join(outDir, 'html') : HTML_DIR;
  const writeHtml = opt.html;
  const jobs = JOBS.filter((j) => !opt.filters.length || opt.filters.some((f) => j.file.includes(f)));

  // ---- Screenshots suchen ----
  const screensDir = opt.screens || DEFAULT_SCREENS_DIR;
  let screens = {};
  if (opt.noScreens) {
    console.log('Screenshots: ausgeschaltet (--no-screens) -> alles gezeichnet');
  } else if (!fs.existsSync(screensDir) || !fs.statSync(screensDir).isDirectory()) {
    if (opt.screens) throw userError(`Screenshot-Ordner nicht gefunden: ${screensDir}`);
    console.log(`Screenshots: Ordner ${screensDir} fehlt -> alles gezeichnet`);
  } else {
    const { found, warnings } = findScreens(screensDir);
    screens = found;
    const names = SHOT_NAMES.filter((n) => found[n]);
    console.log(`Screenshots in ${screensDir}:`);
    console.log(`  gefunden: ${names.length ? names.map((n) => path.basename(found[n].file)).join(', ') : '(keine)'}`);
    const missing = SHOT_NAMES.filter((n) => !found[n]);
    if (missing.length) console.log(`  fehlen:   ${missing.join(', ')}${names.length ? '' : ' -> alles wird gezeichnet'}`);
    warnings.forEach((w) => console.log(`  HINWEIS: ${w}`));
  }
  console.log('');
  fs.mkdirSync(outDir, { recursive: true });
  if (writeHtml) fs.mkdirSync(htmlDir, { recursive: true });

  const { chromium } = loadPlaywright();
  const browser = await chromium.launch();
  const report = [];
  const summary = [];
  let problems = 0;
  const shotCache = new Map();
  let anaPage = null;
  const loadShot = async (name) => {
    if (!shotCache.has(name)) {
      try {
        if (!anaPage) anaPage = await browser.newPage();
        shotCache.set(name, await analyseShot(anaPage, screens[name]));
      } catch (e) {
        problems++;
        console.log(`FEHLER: Screenshot ${path.basename(screens[name].file)} nicht lesbar (${e.message.split('\n')[0]}) -> wird uebersprungen`);
        shotCache.set(name, null);
      }
    }
    return shotCache.get(name);
  };

  for (const job of jobs) {
    UID = 0;
    let shot = null;
    if (job.shot) {
      for (const name of job.shot.from) {
        if (screens[name] && (shot = await loadShot(name))) break;
      }
    }
    const wanted = job.shot ? job.shot.from.map((n) => `"${n}"`).join('/') : '';
    // vorhanden, aber nicht lesbar (kaputt/abgeschnitten) -> ehrlich melden statt "kein Screenshot"
    const broken = !shot && job.shot ? job.shot.from.filter((n) => screens[n]).map((n) => path.basename(screens[n].file)) : [];
    const why = broken.length ? `Screenshot ${broken.join('/')} nicht lesbar` : `kein Screenshot ${wanted}`;
    if (!shot && !job.svg) {
      const old = fs.existsSync(path.join(outDir, job.file)) ? ' (alte Datei im Ausgabe-Ordner bleibt unveraendert liegen)' : '';
      const msg = `uebersprungen - ${why}${old}`;
      console.log(JSON.stringify({ file: job.file, quelle: msg }));
      summary.push([job.file, msg]);
      continue;
    }
    const page = await browser.newPage({ viewport: { width: job.w, height: job.h }, deviceScaleFactor: 1 });
    const pl = shot ? shotPlacement(shot, job.w, job.h, job.shot.place) : null;
    const svg = shot ? job.shot.svg(pl) : job.svg();
    const html = pageHTML(job.w, job.h, shot ? svg.split(SHOT_HREF).join(shot.url) : svg);
    if (writeHtml) {
      // in der HTML-Datei auf den Screenshot verlinken statt ihn einzubetten
      const fileHtml = shot ? pageHTML(job.w, job.h, svg.split(SHOT_HREF).join(pathToFileURL(shot.file).href)) : html;
      fs.writeFileSync(path.join(htmlDir, job.file.replace(/\.png$/, '.html')), fileHtml);
    }
    await page.setContent(html, { waitUntil: 'load' });
    await page.evaluate(async () => {
      await document.fonts.ready;
      // sicherstellen, dass Screenshot-Bilder fertig dekodiert sind
      await Promise.all(
        [...document.querySelectorAll('image.shot')].map((im) => {
          const i = new Image();
          i.src = im.getAttribute('href');
          return i.decode().catch(() => {});
        })
      );
    });
    const fitted = await fitText(page);
    const info = { file: job.file, quelle: 'Zeichnung', fitted };
    if (shot) {
      info.quelle = `Screenshot ${path.basename(shot.file)}`;
      info.screenshot = `${shot.w}x${shot.h}`;
      const t = shot.trim;
      if (t.top || t.bottom || t.left || t.right) info.randEntfernt = t;
      info.massstab = Math.round(pl.s * 1000) / 1000;
      if (pl.s > SHOT_UPSCALE_WARN) {
        info.hinweis = `Screenshot wird ${pl.s.toFixed(2)}x vergroessert und kann unscharf wirken - besser hoehere Aufloesung (mind. 1920x1080) verwenden`;
      }
    } else if (job.shot && !opt.noScreens) {
      info.quelle = `Zeichnung (${why})`;
    }
    summary.push([job.file, info.quelle + (info.hinweis ? '  [unscharf?]' : '')]);

    if (job.kind === 'circle') {
      // Pixel-Pruefung: Inhalt (ohne Hintergrund/Deko) muss im 80%-Kreis liegen
      await page.evaluate(() => document.documentElement.classList.add('check'));
      let a = await analyseAlpha(page, await page.screenshot({ omitBackground: true }), SAFE_R);
      let k = 1;
      for (let i = 0; i < 3 && a.maxD > SAFE_R - 1; i++) {
        k *= (SAFE_R - 2) / a.maxD;
        await page.evaluate((k) => {
          document.getElementById('content').setAttribute('transform', `translate(256 256) scale(${k}) translate(-256 -256)`);
        }, k);
        a = await analyseAlpha(page, await page.screenshot({ omitBackground: true }), SAFE_R);
      }
      await page.evaluate(() => document.documentElement.classList.remove('check'));
      info.contentScale = Math.round(k * 1000) / 1000;
      info.maxRadius = Math.round(a.maxD);
      info.pixelsOutside = a.outside;
      if (a.outside > 0) problems++;
    } else {
      const bad = await textBounds(page, job.w, job.h, job.w > 1000 ? 24 : 10);
      info.textOutOfBounds = bad;
      if (bad.length) problems++;
    }

    const outFile = path.join(outDir, job.file);
    await page.screenshot({ path: outFile, type: 'png' });
    await page.close();
    const sz = pngSize(outFile);
    info.size = `${sz.w}x${sz.h}`;
    if (sz.w !== job.w || sz.h !== job.h) {
      info.sizeError = `erwartet ${job.w}x${job.h}`;
      problems++;
    }
    report.push(info);
    console.log(JSON.stringify(info));
  }
  await browser.close();

  // ---- Zusammenfassung: welches Bild kam woher? ----
  if (summary.length) {
    const circle = new Set(JOBS.filter((j) => j.kind === 'circle').map((j) => j.file));
    const rows = summary.filter(([f]) => !circle.has(f));
    const nIcons = summary.length - rows.length;
    console.log('\nQuelle je Bild:');
    rows.forEach(([f, q]) => console.log(`  ${f.padEnd(18)} ${q}`));
    if (nIcons) console.log(`  ${`${nIcons} Pass/Produkt-Icon(s)`.padEnd(18)} Zeichnung`);
  }
  console.log(problems ? `\nWARNUNG: ${problems} Problem(e), siehe oben.` : `\nOK: ${report.length} Bild(er) erzeugt in ${outDir}`);
  process.exitCode = problems ? 1 : 0;
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e.user ? `FEHLER: ${e.message}` : e);
    process.exit(1);
  });
}

module.exports = { JOBS };
