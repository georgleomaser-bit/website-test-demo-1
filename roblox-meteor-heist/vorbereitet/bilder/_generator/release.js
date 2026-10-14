#!/usr/bin/env node
/* =====================================================================
 *  METEOR HEIST – Release-Bilder (Banner, neue Vorschaubilder, Social)
 *
 *  Baut mit den ECHTEN Aliens aus dem Spiel (gerenderte Freisteller in
 *  ./aliens/, Eier mit Aura in ./eier/) und im selben Stil wie die
 *  Thumbnails aus generate.js (gleiche Schrift-, Stern- und Meteor-Bausteine):
 *
 *    banner-1920x1080.png        Haupt-Banner / Key-Art (auch als Thumbnail nutzbar)
 *    vorschau-aliens.png         1920x1080  "183 ALIENS ZUM SAMMELN!" (eine pro Seltenheit)
 *    vorschau-mutationen.png     1920x1080  "SELTENE MUTATIONEN!" (ein Alien in allen Mutationen)
 *    vorschau-eier.png           1920x1080  "SELTENE EIER LEUCHTEN!" (Eier mit Aura je Seltenheit)
 *    banner-breit-1500x500.png   Social-/Community-Banner (z. B. X, Discord, Roblox-Gruppe)
 *    banner-hochkant-1080x1920.png  TikTok / YouTube Shorts / Story
 *    spiel-icon-alien.png        512x512 Alternative zum Spiel-Icon (Alien schlüpft aus dem Ei)
 *
 *  Benutzung:   node release.js [--out <ordner>] [name-filter]
 *  Ausgabe:     ../ (vorbereitet/bilder/)
 *  Freisteller: python3 prep_aliens.py <render-ordner> ./aliens   (siehe README.md)
 * ===================================================================== */
'use strict';

const fs = require('fs');
const path = require('path');
const G = require('./generate.js');

const { n1, uid, rng, commonDefs, sparkle, starField, meteor, txt, emo, alienEgg, skyDefs, nebula, ribbon, pill, pageHTML, fitText, textBounds, loadPlaywright, FILL } = G.helpers;

const ALIEN_DIR = path.join(__dirname, 'aliens');
const EGG_DIR = path.join(__dirname, 'eier');

// Seltenheiten wie Config.Rarities im Spiel (Farben 1:1)
const RARITY = {
  Common: '#c8c8c8',
  Uncommon: '#55dc5f',
  Rare: '#4696ff',
  Epic: '#b450ff',
  Legendary: '#ffbe28',
  Mythic: '#ff3c5a',
  Celestial: '#5ae6ff',
  Divine: '#fff096',
  Secret: '#ffffff',
  Godly: '#ffd200',
  Cosmic: '#8a6cff',
  Infinity: '#3cffc8',
};

// ---------------------------------------------------------------------
//  Freisteller laden (als data-URI eingebettet, damit Chromium sie sicher lädt)
// ---------------------------------------------------------------------
function pngSize(buf) {
  return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
}
const cache = new Map();
function cutout(dir, id) {
  const key = dir + '/' + id;
  if (cache.has(key)) return cache.get(key);
  const file = path.join(dir, id + '.png');
  if (!fs.existsSync(file)) throw Object.assign(new Error(`Freisteller fehlt: ${file}`), { user: true });
  const buf = fs.readFileSync(file);
  const v = { url: 'data:image/png;base64,' + buf.toString('base64'), ...pngSize(buf) };
  cache.set(key, v);
  return v;
}
const has = (dir, id) => fs.existsSync(path.join(dir, id + '.png'));

// Alien (Freisteller) mit Boden-Schatten und optionalem Seltenheits-Leuchten.
// cx = Mitte, baseY = Fußlinie, h = Höhe in Pixeln.
function alien(id, { cx, baseY, h, glow = null, glowOp = 0.55, flip = false, shadow = true, dir = ALIEN_DIR }) {
  const c = cutout(dir, id);
  const w = (c.w / c.h) * h;
  const x = cx - w / 2;
  const y = baseY - h;
  const gid = uid('ag');
  let out = '';
  if (glow) {
    out += `<defs><radialGradient id="${gid}"><stop offset="0" stop-color="${glow}" stop-opacity="${glowOp}"/><stop offset="0.55" stop-color="${glow}" stop-opacity="${glowOp * 0.35}"/><stop offset="1" stop-color="${glow}" stop-opacity="0"/></radialGradient></defs>
      <ellipse class="deco" cx="${n1(cx)}" cy="${n1(baseY - h * 0.5)}" rx="${n1(h * 0.78)}" ry="${n1(h * 0.72)}" fill="url(#${gid})"/>`;
  }
  if (shadow) out += `<ellipse cx="${n1(cx)}" cy="${n1(baseY - h * 0.015)}" rx="${n1(w * 0.36)}" ry="${n1(h * 0.055)}" fill="#05010f" opacity="0.55" filter="url(#blur8)"/>`;
  const tr = flip ? ` transform="translate(${n1(2 * cx)} 0) scale(-1 1)"` : '';
  out += `<image href="${c.url}" x="${n1(x)}" y="${n1(y)}" width="${n1(w)}" height="${n1(h)}"${tr} preserveAspectRatio="xMidYMid meet"/>`;
  return out;
}

// Ei: echter Freisteller mit Aura (./eier/<Rarity>.png), sonst gezeichnetes Ei aus generate.js
const EGG_PAL = { Common: 'green', Uncommon: 'green', Rare: 'cyan', Epic: 'purple', Legendary: 'gold', Mythic: 'pink', Celestial: 'cyan', Divine: 'gold', Secret: 'pink' };
function egg(rarity, { cx, baseY, h, rot = 0 }) {
  if (has(EGG_DIR, rarity)) return alien(rarity, { cx, baseY, h, dir: EGG_DIR, shadow: true });
  return alienEgg({ x: cx, y: baseY - h * 0.5, r: h * 0.5, pal: EGG_PAL[rarity] || 'green', rot, seed: rarity.length * 7, glow: 1.1 });
}

// ---------------------------------------------------------------------
//  Gemeinsamer Hintergrund: lila Weltall, Nebel, Sterne, Meteore, Hügel
// ---------------------------------------------------------------------
function spaceBG(W, H, seed, { hills = true, meteors = true, groundY = H * 0.86 } = {}) {
  const id = uid('sky');
  const k = W / 1920;
  let s = `<defs>${skyDefs(id, '#12063a', '#2c0f6e', '#5a1f86')}</defs><rect class="bg-layer" width="${W}" height="${H}" fill="url(#${id})"/>`;
  s += nebula(W * 0.2, H * 0.25, 700 * k, 450 * k, '#5a2cff', 0.45);
  s += nebula(W * 0.82, H * 0.3, 760 * k, 520 * k, '#ff3dc8', 0.32);
  s += nebula(W * 0.5, H * 0.95, 1100 * k, 360 * k, '#ff7a1a', 0.3);
  s += starField(W, H, Math.round(320 * Math.max(k, 0.6)), seed, { sparkles: 12, yMax: groundY });
  if (meteors) {
    s += meteor({ x: W * 0.09, y: H * 0.16, r: 34 * k + 8, angle: -150, tail: 2.2, pal: 'fire', seed: seed + 1, glow: 0.9 });
    s += meteor({ x: W * 0.93, y: H * 0.12, r: 26 * k + 7, angle: -30, tail: 2.4, pal: 'blue', seed: seed + 2, glow: 0.9 });
    s += meteor({ x: W * 0.78, y: H * 0.42, r: 16 * k + 5, angle: -25, tail: 2.6, pal: 'purple', seed: seed + 3, glow: 0.8 });
    s += meteor({ x: W * 0.2, y: H * 0.5, r: 14 * k + 5, angle: -155, tail: 2.6, pal: 'gold', seed: seed + 4, glow: 0.8 });
  }
  if (hills) {
    const gy = groundY;
    const r = rng(seed + 9);
    let d = `M0,${n1(gy - 40 * k)}`;
    const n = 10;
    for (let i = 1; i <= n; i++) d += ` L${n1((i / n) * W)},${n1(gy - (30 + r() * 80) * k)}`;
    d += ` L${W},${H} L0,${H}Z`;
    const gid = uid('gr');
    s += `<defs><linearGradient id="${gid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3b1f66"/><stop offset="1" stop-color="#120826"/></linearGradient></defs>`;
    s += `<path d="${d}" fill="#26114a"/><rect x="0" y="${n1(gy)}" width="${W}" height="${n1(H - gy)}" fill="url(#${gid})"/>`;
    s += `<ellipse cx="${W / 2}" cy="${n1(gy + 10 * k)}" rx="${n1(W * 0.42)}" ry="${n1(70 * k)}" fill="#ff7a1a" opacity="0.32" filter="url(#blur60)"/>`;
  }
  return s;
}

// leuchtende Plattform (Krater-Ring), auf der Aliens stehen
function platform(cx, cy, rx, ry) {
  const id = uid('pf');
  return `<defs><radialGradient id="${id}" cx="0.5" cy="0.45" r="0.6"><stop offset="0" stop-color="#ffe07a"/><stop offset="0.25" stop-color="#ff9a1a"/><stop offset="0.6" stop-color="#b8300c"/><stop offset="0.9" stop-color="#3a1030"/><stop offset="1" stop-color="#22092e"/></radialGradient></defs>
    <ellipse cx="${n1(cx)}" cy="${n1(cy + ry * 0.12)}" rx="${n1(rx * 1.04)}" ry="${n1(ry * 1.08)}" fill="#8a5ab8" stroke="#120826" stroke-width="8"/>
    <ellipse cx="${n1(cx)}" cy="${n1(cy + ry * 0.2)}" rx="${n1(rx * 0.88)}" ry="${n1(ry * 0.8)}" fill="url(#${id})"/>
    <ellipse cx="${n1(cx)}" cy="${n1(cy)}" rx="${n1(rx * 0.7)}" ry="${n1(ry * 0.7)}" fill="#ff8a1a" opacity="0.3" filter="url(#blur60)"/>`;
}

function headline(text, o) {
  return txt(text, { fill: ['#fffbd0', '#ffd21a', '#ff7a00'], sw: 0.17, glow: '#ff5a00', glowOp: 0.45, ...o });
}

// Seltenheits-Schild (kleine Pille mit Seltenheitsfarbe)
function rarityTag(cx, cy, name, { size = 34, w = null } = {}) {
  const col = RARITY[name] || '#ffffff';
  const width = w || Math.max(150, name.length * size * 0.72 + 50);
  const id = uid('rt');
  const h = size * 1.55;
  return `<g>
    <defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a1250"/><stop offset="1" stop-color="#14062a"/></linearGradient></defs>
    <rect x="${n1(cx - width / 2)}" y="${n1(cy - h / 2)}" width="${n1(width)}" height="${n1(h)}" rx="${n1(h / 2)}" fill="url(#${id})" stroke="${col}" stroke-width="6"/>
    ${txt(name.toUpperCase(), { x: cx, cy, size, fill: [col, col, col], sw: 0.16, depth: 0.05, maxW: width - 30 })}
  </g>`;
}

const LOGO = (x, cy, size, maxW) =>
  txt('METEOR HEIST', { x, cy, size, fill: ['#fffbd0', '#ffd21a', '#ff7a00'], sw: 0.17, depth: 0.09, glow: '#ff5a00', glowOp: 0.55, maxW });

// ---------------------------------------------------------------------
//  BILDER
// ---------------------------------------------------------------------
function svgWrap(W, H, inner) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}"><defs>${commonDefs(W / 1920 + 0.5)}</defs>${inner}</svg>`;
}

// 1) Haupt-Banner / Key-Art
function banner() {
  const W = 1920, H = 1080, base = 905;
  const line = [
    // [Id, Mitte x, Höhe, Seltenheit fürs Leuchten, spiegeln]
    ['CobaltRobot', 285, 270, 'Rare', false],
    ['GalaxyMushroom', 510, 320, 'Celestial', false],
    ['StarfallSquid', 735, 350, 'Mythic', false],
    ['HaloKing', 985, 440, 'Divine', true],
    ['SeraphSpiky_Gold', 1240, 350, 'Legendary', true],
    ['GalaxySquid', 1465, 340, 'Celestial', true],
    ['BloodMoonSpiky', 1665, 270, 'Divine', true],
  ];
  let al = '';
  // hinten zuerst (kleinere zuerst)
  [...line].sort((a, b) => a[2] - b[2]).forEach(([id, cx, h, rar, flip]) => {
    al += alien(id, { cx, baseY: base - (h > 420 ? 10 : 0), h, glow: RARITY[rar], glowOp: 0.35, flip });
  });
  const eggs = egg('Legendary', { cx: 150, baseY: 1000, h: 170, rot: -10 }) + egg('Mythic', { cx: 1790, baseY: 1010, h: 190, rot: 8 }) + egg('Epic', { cx: 1010, baseY: 1040, h: 120, rot: 4 });
  return svgWrap(W, H, `
    ${spaceBG(W, H, 7781, { groundY: 870 })}
    ${platform(960, 905, 860, 120)}
    ${al}
    ${eggs}
    ${LOGO(960, 150, 210, 1700)}
    ${ribbon(960, 300, 980, 96, 'SCHNAPP EIER · SCHLÜPFE ALIENS!', { fill: ['#ff86e0', '#c018a8'] })}
  `);
}

// 2) Vorschau: Aliens je Seltenheit
function previewAliens() {
  const W = 1920, H = 1080;
  const row = [
    ['PebbleBlob', 'Common'], ['CometSquid', 'Uncommon'], ['CobaltRobot', 'Rare'], ['PlasmaRobot', 'Epic'],
    ['LunarKing', 'Legendary'], ['StarfallSquid', 'Mythic'], ['QuasarKing', 'Celestial'], ['HaloKing', 'Divine'],
  ].filter(([id]) => has(ALIEN_DIR, id));
  const n = row.length;
  const left = 175, right = W - 175;
  let s = '';
  row.forEach(([id, rar], i) => {
    const cx = n === 1 ? W / 2 : left + (i / (n - 1)) * (right - left);
    const h = 205 + i * 14; // seltener = größer
    const baseY = 810 - (i % 2) * 40;
    s += alien(id, { cx, baseY, h, glow: RARITY[rar], glowOp: 0.6 });
    s += rarityTag(cx, baseY + 48, rar, { size: 26 });
  });
  return svgWrap(W, H, `
    ${spaceBG(W, H, 5521, { groundY: 930, meteors: true })}
    ${headline('183 ALIENS', { x: 960, cy: 140, size: 190, maxW: 1500 })}
    ${txt('ZUM SAMMELN!', { x: 960, cy: 300, size: 110, fill: FILL.white, sw: 0.17, depth: 0.08, maxW: 1400 })}
    ${s}
    ${pill(960, 985, '12 SELTENHEITEN BIS INFINITY', { fill: ['#b450ff', '#5a12a8'], size: 50, w: 1100 })}
  `);
}

// 3) Vorschau: Mutationen
function previewMutations() {
  const W = 1920, H = 1080;
  const muts = [
    ['SeraphSpiky', 'NORMAL', '#ffffff', ''],
    ['SeraphSpiky_Gold', 'GOLD', '#ffcd32', 'x2'],
    ['SeraphSpiky_Frost', 'FROST', '#96dcff', 'x3'],
    ['SeraphSpiky_Lava', 'LAVA', '#ff6e1e', 'x3'],
    ['SeraphSpiky_Diamond', 'DIAMANT', '#78e6ff', 'x4'],
    ['SeraphSpiky_Galaxy', 'GALAXY', '#9646ff', 'x10'],
    ['SeraphSpiky_Rainbow', 'REGENBOGEN', '#ff7ad9', 'x15'],
  ].filter(([id]) => has(ALIEN_DIR, id));
  const n = muts.length;
  const left = 170, right = W - 170;
  let s = '';
  muts.forEach(([id, label, col, mult], i) => {
    const cx = n === 1 ? W / 2 : left + (i / (n - 1)) * (right - left);
    const h = 250 + (i / Math.max(1, n - 1)) * 110;
    const baseY = 800;
    s += alien(id, { cx, baseY, h, glow: col, glowOp: 0.65 });
    s += txt(label, { x: cx, cy: baseY + 55, size: 38, fill: [col, col, col], sw: 0.18, depth: 0.06, maxW: (right - left) / n });
    if (mult) s += txt(mult, { x: cx, cy: baseY + 115, size: 54, fill: FILL.gold, sw: 0.18, depth: 0.07, maxW: 200 });
  });
  return svgWrap(W, H, `
    ${spaceBG(W, H, 9912, { groundY: 960, meteors: true })}
    ${headline('SELTENE MUTATIONEN!', { x: 960, cy: 150, size: 150, maxW: 1760 })}
    ${txt('MEHR GELD PRO SEKUNDE', { x: 960, cy: 300, size: 80, fill: FILL.white, sw: 0.17, depth: 0.08, maxW: 1400 })}
    ${s}
  `);
}

// 4) Vorschau: Eier mit Aura
function previewEggs() {
  const W = 1920, H = 1080;
  const list = ['Common', 'Rare', 'Epic', 'Legendary', 'Mythic', 'Celestial', 'Divine', 'Secret'];
  const n = list.length;
  const left = 170, right = W - 170;
  let s = '';
  list.forEach((rar, i) => {
    const cx = left + (i / (n - 1)) * (right - left);
    const h = 150 + i * 15;
    const baseY = 790;
    s += egg(rar, { cx, baseY, h, rot: (i % 2 ? 6 : -6) });
    s += rarityTag(cx, baseY + 70, rar, { size: 26 });
  });
  return svgWrap(W, H, `
    ${spaceBG(W, H, 3141, { groundY: 930 })}
    ${headline('SELTENE EIER LEUCHTEN!', { x: 960, cy: 150, size: 140, maxW: 1760 })}
    ${txt('SCHNAPP SIE DIR ZUERST!', { x: 960, cy: 295, size: 80, fill: FILL.white, sw: 0.17, depth: 0.08, maxW: 1400 })}
    ${s}
  `);
}

// 5) Breites Banner 1500x500
function bannerWide() {
  const W = 1500, H = 500;
  const al =
    alien('CobaltRobot', { cx: 1010, baseY: 455, h: 210, glow: RARITY.Rare, glowOp: 0.35 }) +
    alien('StarfallSquid', { cx: 1150, baseY: 465, h: 280, glow: RARITY.Mythic, glowOp: 0.35 }) +
    alien('HaloKing', { cx: 1330, baseY: 470, h: 320, glow: RARITY.Divine, glowOp: 0.35, flip: true });
  return svgWrap(W, H, `
    ${spaceBG(W, H, 4242, { groundY: 440, meteors: true })}
    ${al}
    ${egg('Legendary', { cx: 860, baseY: 470, h: 120, rot: -8 })}
    ${LOGO(410, 190, 120, 720)}
    ${txt('SCHNAPP EIER · SCHLÜPFE ALIENS!', { x: 410, cy: 320, size: 44, fill: FILL.white, sw: 0.17, depth: 0.07, maxW: 720 })}
    ${pill(410, 410, 'JETZT AUF ROBLOX', { fill: ['#3dff6e', '#0a9a3a'], size: 34, w: 470 })}
  `);
}

// 6) Hochkant 1080x1920
function bannerTall() {
  const W = 1080, H = 1920;
  const al =
    alien('GalaxyMushroom', { cx: 250, baseY: 1390, h: 330, glow: RARITY.Celestial, glowOp: 0.35 }) +
    alien('SeraphSpiky_Gold', { cx: 840, baseY: 1390, h: 330, glow: RARITY.Legendary, glowOp: 0.35, flip: true }) +
    alien('HaloKing', { cx: 540, baseY: 1470, h: 640, glow: RARITY.Divine, glowOp: 0.45 });
  return svgWrap(W, H, `
    ${spaceBG(W, H, 6262, { groundY: 1420 })}
    ${platform(540, 1460, 480, 90)}
    ${al}
    ${egg('Mythic', { cx: 170, baseY: 1700, h: 200, rot: -8 })}
    ${egg('Legendary', { cx: 910, baseY: 1710, h: 210, rot: 8 })}
    ${LOGO(540, 260, 150, 980)}
    ${txt('SCHNAPP EIER', { x: 540, cy: 440, size: 96, fill: FILL.white, sw: 0.17, depth: 0.08, maxW: 960 })}
    ${txt('SCHLÜPFE ALIENS!', { x: 540, cy: 560, size: 96, fill: FILL.gold, sw: 0.17, depth: 0.08, maxW: 960 })}
    ${pill(540, 1800, 'JETZT AUF ROBLOX SPIELEN', { fill: ['#3dff6e', '#0a9a3a'], size: 52, w: 900 })}
  `);
}

// 7) Alternative Spiel-Icon 512x512
function iconAlien() {
  const W = 512, H = 512;
  return svgWrap(W, H, `
    ${spaceBG(W, H, 1212, { hills: false, meteors: false })}
    <circle cx="256" cy="250" r="190" fill="#ffd21a" opacity="0.35" filter="url(#blur20)"/>
    ${alienEgg({ x: 256, y: 385, r: 120, pal: 'gold', seed: 3, glow: 1.2, crack: 'bottom' })}
    ${alien('HaloKing', { cx: 256, baseY: 360, h: 270, shadow: false })}
    ${meteor({ x: 455, y: 70, r: 26, angle: -30, tail: 2.2, pal: 'fire', seed: 5, glow: 0.9 })}
    ${LOGO(256, 455, 64, 470)}
  `);
}

const JOBS = [
  { file: 'banner-1920x1080.png', w: 1920, h: 1080, svg: banner },
  { file: 'vorschau-aliens.png', w: 1920, h: 1080, svg: previewAliens },
  { file: 'vorschau-mutationen.png', w: 1920, h: 1080, svg: previewMutations },
  { file: 'vorschau-eier.png', w: 1920, h: 1080, svg: previewEggs },
  { file: 'banner-breit-1500x500.png', w: 1500, h: 500, svg: bannerWide },
  { file: 'banner-hochkant-1080x1920.png', w: 1080, h: 1920, svg: bannerTall },
  { file: 'spiel-icon-alien.png', w: 512, h: 512, svg: iconAlien },
];

async function main() {
  const args = process.argv.slice(2);
  let out = path.resolve(__dirname, '..');
  const oi = args.indexOf('--out');
  if (oi >= 0) {
    out = path.resolve(args[oi + 1]);
    args.splice(oi, 2);
  }
  const filter = args.find((a) => !a.startsWith('--'));
  fs.mkdirSync(out, { recursive: true });
  const { chromium } = loadPlaywright();
  const browser = await chromium.launch();
  let problems = 0;
  for (const job of JOBS) {
    if (filter && !job.file.includes(filter)) continue;
    const page = await browser.newPage({ viewport: { width: job.w, height: job.h }, deviceScaleFactor: 1 });
    await page.setContent(pageHTML(job.w, job.h, job.svg()), { waitUntil: 'load' });
    await page.evaluate(async () => {
      await document.fonts.ready;
      await Promise.all([...document.querySelectorAll('image')].map((im) => { const i = new Image(); i.src = im.getAttribute('href'); return i.decode().catch(() => {}); }));
    });
    const fitted = await fitText(page);
    const bad = await textBounds(page, job.w, job.h, Math.round(Math.min(job.w, job.h) * 0.02));
    await page.screenshot({ path: path.join(out, job.file), clip: { x: 0, y: 0, width: job.w, height: job.h } });
    await page.close();
    if (bad.length) problems++;
    console.log(JSON.stringify({ file: job.file, size: `${job.w}x${job.h}`, fitted, textOutOfBounds: bad }));
  }
  await browser.close();
  console.log(problems ? `WARNUNG: ${problems} Bild(er) mit Text am Rand` : 'OK');
  process.exitCode = problems ? 1 : 0;
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e.user ? `FEHLER: ${e.message}` : e);
    process.exit(1);
  });
}
