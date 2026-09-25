// Hintergrund der App: der Schriftzug ΛKYTEX leuchtet regelmäßig auf und löst sich in Aktienkurse auf
// (eine Kurslinie und Kerzen), die dann verblassen. Leise im Hintergrund, hinter dem Liquid Glass.
// Spart Strom: läuft nur, solange die Seite sichtbar ist, und pausiert zwischen den Durchgängen ganz.
const REDUCED = matchMedia("(prefers-reduced-motion: reduce)").matches;
const WORD = "ΛKYTEX";
// Ablauf eines Durchgangs in Millisekunden
const T = { gather: 1700, blink: 1700, dissolve: 2600, hold: 2000, fade: 1800 };
const CYCLE = T.gather + T.blink + T.dissolve + T.hold + T.fade;
const PAUSE = 6500;
const TICKERS = ["AAPL", "NVDA", "SAP", "TSLA", "MSFT", "AMZN", "META", "ASML"];

const ease = (p) => (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2);
const clamp = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const rnd = (a, b) => a + Math.random() * (b - a);

export function startBackdrop() {
  if (REDUCED || document.querySelector(".bgfx")) return;
  const cv = document.createElement("canvas");
  cv.className = "bgfx";
  cv.setAttribute("aria-hidden", "true");
  document.body.prepend(cv);
  const x = cv.getContext("2d");
  const N = innerWidth < 700 ? 560 : 1100;
  let W = 0;
  let H = 0;
  let dpr = 1;
  let pts = [];
  let labels = [];
  let raf = 0;
  let start = 0;
  let wait = 0;

  // Punkte des Schriftzugs aus einem unsichtbaren Canvas abtasten
  function wordPoints(cx, cy, width) {
    const size = Math.round(width / 5.2);
    const gap = size * 0.28;
    const oc = document.createElement("canvas");
    const g = oc.getContext("2d");
    g.font = `300 ${size}px Manrope, "Helvetica Neue", Arial, sans-serif`;
    const ws = [...WORD].map((c) => g.measureText(c).width);
    const tw = ws.reduce((a, b) => a + b, 0) + gap * (WORD.length - 1);
    oc.width = Math.ceil(tw) + 8;
    oc.height = Math.ceil(size * 1.3);
    g.font = `300 ${size}px Manrope, "Helvetica Neue", Arial, sans-serif`;
    g.textBaseline = "middle";
    g.fillStyle = "#000";
    let px = 4;
    [...WORD].forEach((c, i) => {
      g.fillText(c, px, oc.height / 2);
      px += ws[i] + gap;
    });
    const data = g.getImageData(0, 0, oc.width, oc.height).data;
    const step = Math.max(2, Math.round(Math.sqrt((tw * size * 0.2) / N)));
    const out = [];
    for (let yy = 0; yy < oc.height; yy += step)
      for (let xx = 0; xx < oc.width; xx += step) if (data[(yy * oc.width + xx) * 4 + 3] > 128) out.push([cx - oc.width / 2 + xx, cy - oc.height / 2 + yy]);
    return { out, w: oc.width, h: oc.height };
  }

  // Ziele „Aktien“: eine steigende Kurslinie und Kerzen darunter
  function stockTargets(cx, cy, w, h, n) {
    const left = cx - w / 2;
    const nLine = Math.round(n * 0.55);
    const line = [];
    let y = cy + h * 0.25;
    const steps = 48;
    const path = [];
    for (let i = 0; i <= steps; i++) {
      path.push([left + (w * i) / steps, y]);
      y += rnd(-h * 0.16, h * 0.1); // leicht aufwärts
      y = Math.min(cy + h * 0.55, Math.max(cy - h * 0.65, y));
    }
    for (let i = 0; i < nLine; i++) {
      const f = (i / nLine) * steps;
      const k = Math.min(steps - 1, Math.floor(f));
      const q = f - k;
      line.push({ x: path[k][0] + (path[k + 1][0] - path[k][0]) * q, y: path[k][1] + (path[k + 1][1] - path[k][1]) * q, c: 0 });
    }
    const candles = [];
    const K = innerWidth < 700 ? 10 : 16;
    const cw = w / K;
    let base = cy + h * 0.1;
    for (let k = 0; k < K; k++) {
      const up = Math.random() < 0.6;
      const body = rnd(h * 0.12, h * 0.45);
      const top = base - (up ? body : 0);
      const wick = rnd(h * 0.05, h * 0.18);
      candles.push({ x: left + cw * (k + 0.5), top, body, wick, c: up ? 1 : 2 });
      base += up ? -body * 0.35 : body * 0.35;
      base = Math.min(cy + h * 0.5, Math.max(cy - h * 0.3, base));
    }
    const rest = n - nLine;
    const cand = [];
    for (let i = 0; i < rest; i++) {
      const cd = candles[i % K];
      const wickPt = Math.random() < 0.18;
      cand.push(
        wickPt
          ? { x: cd.x, y: cd.top - cd.wick + Math.random() * (cd.body + cd.wick * 2), c: cd.c }
          : { x: cd.x + rnd(-cw * 0.22, cw * 0.22), y: cd.top + Math.random() * cd.body, c: cd.c },
      );
    }
    const end = path[path.length - 1];
    labels = TICKERS.sort(() => Math.random() - 0.5)
      .slice(0, innerWidth < 700 ? 2 : 3)
      .map((t, i) => ({ t: `${t} ${Math.random() < 0.7 ? "+" : "−"}${rnd(0.3, 4.8).toFixed(1).replace(".", ",")} %`, x: end[0] - i * w * 0.34 - rnd(0, w * 0.08), y: cy - h * (0.75 + 0.18 * (i % 2)) }));
    return [...line, ...cand].sort((a, b) => a.x - b.x);
  }

  function setup() {
    dpr = Math.min(2, devicePixelRatio || 1);
    W = innerWidth;
    H = innerHeight;
    cv.width = Math.round(W * dpr);
    cv.height = Math.round(H * dpr);
    const width = Math.min(W * 0.84, 980);
    const cx = W / 2;
    const cy = H * 0.52;
    const { out, w, h } = wordPoints(cx, cy, width);
    const src = out.sort(() => Math.random() - 0.5).slice(0, N).sort((a, b) => a[0] - b[0]);
    const tg = stockTargets(cx, cy, w, h * 1.2, src.length);
    pts = src.map(([wx, wy], i) => ({ sx: rnd(0, W), sy: rnd(0, H), wx, wy, tx: tg[i].x, ty: tg[i].y, c: tg[i].c, d: (wx - (cx - w / 2)) / w, j: Math.random() }));
  }

  const dark = () => document.documentElement.dataset.theme === "dark";
  function frame(now) {
    if (!start) start = now;
    const t = now - start;
    if (t > CYCLE) {
      x.clearRect(0, 0, cv.width, cv.height);
      raf = 0;
      start = 0;
      wait = setTimeout(run, PAUSE);
      return;
    }
    raf = requestAnimationFrame(frame);
    const d = dark();
    const base = d ? 0.75 : 0.62;
    const col = d ? ["rgb(140,180,255)", "rgb(52,211,153)", "rgb(248,113,113)"] : ["rgb(41,98,255)", "rgb(8,153,129)", "rgb(229,57,70)"];
    const t1 = T.gather;
    const t2 = t1 + T.blink;
    const t3 = t2 + T.dissolve;
    const t4 = t3 + T.hold;
    let alpha = base;
    if (t < t1) alpha = base * ease(t / t1);
    else if (t < t2) {
      // Aufblinken: zwei weiche Lichtimpulse
      const p = (t - t1) / T.blink;
      alpha = base * (1 + 0.9 * Math.pow(Math.sin(p * Math.PI * 2), 2));
    } else if (t > t4) alpha = base * (1 - ease((t - t4) / T.fade));
    x.setTransform(dpr, 0, 0, dpr, 0, 0);
    x.clearRect(0, 0, W, H);
    const s = W < 700 ? 3 : 4.5;
    // nach Farbe gruppiert zeichnen – nur drei Farbwechsel pro Bild
    for (let c = 0; c < 3; c++) {
      x.fillStyle = col[c];
      for (const p of pts) {
        let px;
        let py;
        let pc = 0;
        if (t < t1) {
          const q = ease(clamp((t / t1 - p.j * 0.25) / 0.75));
          px = p.sx + (p.wx - p.sx) * q;
          py = p.sy + (p.wy - p.sy) * q;
        } else if (t < t2) {
          px = p.wx + Math.sin(now / 300 + p.j * 9) * 0.4;
          py = p.wy;
        } else {
          // Auflösen von links nach rechts
          const q = ease(clamp(((t - t2) / T.dissolve - p.d * 0.45) / 0.55));
          const arc = Math.sin(q * Math.PI) * (12 + p.j * 26);
          px = p.wx + (p.tx - p.wx) * q;
          py = p.wy + (p.ty - p.wy) * q - arc;
          if (t > t4) py -= ((t - t4) / T.fade) * 30 * (0.5 + p.j);
          pc = q > 0.6 ? p.c : 0;
        }
        if (pc !== c) continue;
        x.globalAlpha = Math.min(1, alpha * (0.55 + 0.45 * p.j));
        x.fillRect(px, py, s, s);
      }
    }
    // Kurs-Schilder erscheinen, wenn die Kurslinie steht
    if (t > t2 + T.dissolve * 0.6) {
      const la = alpha * clamp((t - t2 - T.dissolve * 0.6) / 700);
      x.globalAlpha = la;
      x.font = `600 ${W < 700 ? 11 : 13}px Manrope, system-ui, sans-serif`;
      for (const l of labels) {
        x.fillStyle = l.t.includes("−") ? col[2] : col[1];
        x.fillText(l.t, l.x, l.y);
      }
    }
    x.globalAlpha = 1;
  }

  function run() {
    if (document.hidden) return;
    setup();
    start = 0;
    raf = requestAnimationFrame(frame);
  }
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      cancelAnimationFrame(raf);
      clearTimeout(wait);
      raf = 0;
      x.clearRect(0, 0, cv.width, cv.height);
    } else if (!raf) {
      clearTimeout(wait);
      wait = setTimeout(run, 1500);
    }
  });
  const go = () => (wait = setTimeout(run, 2600));
  (document.fonts?.ready || Promise.resolve()).then(go, go);
}
