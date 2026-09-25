// Startseite: Hero-Animation und Effekte beim Scrollen.
// Im Hero formt sich ΛKYTEX aus Lichtpartikeln, blitzt auf und zerfällt in einen Kurschart
// (Kurslinie mit leuchtender Spitze, grüne und rote Kerzen, Kursschilder). Danach formt sich
// der Schriftzug wieder, in einer Endlosschleife. Die Partikel weichen der Maus bzw. dem Finger aus.
const REDUCED = matchMedia("(prefers-reduced-motion: reduce)").matches;
const WORD = "ΛKYTEX";
const P = { form: 1900, glow: 1700, burst: 2300, chart: 3200 };
const LOOP = P.form + P.glow + P.burst + P.chart;
const TICKERS = ["AAPL", "NVDA", "SAP", "TSLA", "MSFT", "AMZN", "META", "ASML", "RHM"];

const ease = (p) => (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2);
const outExpo = (p) => (p >= 1 ? 1 : 1 - Math.pow(2, -10 * p));
const clamp = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const rnd = (a, b) => a + Math.random() * (b - a);

// weiche Leuchtpunkte einmal vorrendern (schneller als jedes Mal einen Verlauf zu zeichnen)
function sprite(rgb, n) {
  const c = document.createElement("canvas");
  c.width = c.height = n;
  const g = c.getContext("2d");
  const r = n / 2;
  const gr = g.createRadialGradient(r, r, 0, r, r, r);
  gr.addColorStop(0, "rgba(255,255,255,1)");
  gr.addColorStop(0.22, `rgba(${rgb},0.95)`);
  gr.addColorStop(0.55, `rgba(${rgb},0.28)`);
  gr.addColorStop(1, `rgba(${rgb},0)`);
  g.fillStyle = gr;
  g.fillRect(0, 0, n, n);
  return c;
}

const S = { on: false, raf: 0, cv: null, x: null, pts: [], W: 0, H: 0, dpr: 1, t0: 0, mouse: { x: -9999, y: -9999 }, visible: true, path: [], labels: [], built: false };

function sampleWord(cx, cy, width, n) {
  const size = Math.round(width / 6.6);
  const gap = size * 0.3;
  const oc = document.createElement("canvas");
  const g = oc.getContext("2d");
  const font = `200 ${size}px Manrope, "Helvetica Neue", Arial, sans-serif`;
  g.font = font;
  const ws = [...WORD].map((c) => g.measureText(c).width);
  const tw = ws.reduce((a, b) => a + b, 0) + gap * (WORD.length - 1);
  oc.width = Math.ceil(tw) + 10;
  oc.height = Math.ceil(size * 1.25);
  g.font = font;
  g.textBaseline = "middle";
  let px = 5;
  [...WORD].forEach((c, i) => {
    g.fillText(c, px, oc.height / 2);
    px += ws[i] + gap;
  });
  const d = g.getImageData(0, 0, oc.width, oc.height).data;
  const all = [];
  for (let y = 0; y < oc.height; y += 2) for (let x = 0; x < oc.width; x += 2) if (d[(y * oc.width + x) * 4 + 3] > 120) all.push([cx - oc.width / 2 + x, cy - oc.height / 2 + y]);
  // gleichmäßig ausdünnen
  const out = [];
  const step = all.length / n;
  for (let i = 0; i < n && all.length; i++) out.push(all[Math.floor(i * step) % all.length]);
  return { out, w: oc.width, h: oc.height };
}

function chartTargets(cx, cy, w, h, n) {
  const left = cx - w / 2;
  const steps = 60;
  const path = [];
  let y = cy + h * 0.3;
  for (let i = 0; i <= steps; i++) {
    path.push([left + (w * i) / steps, y]);
    y += rnd(-h * 0.13, h * 0.085);
    y = Math.min(cy + h * 0.45, Math.max(cy - h * 0.55, y));
  }
  S.path = path;
  const nLine = Math.round(n * 0.5);
  const tg = [];
  for (let i = 0; i < nLine; i++) {
    const f = (i / nLine) * steps;
    const k = Math.min(steps - 1, Math.floor(f));
    const q = f - k;
    tg.push({ x: path[k][0] + (path[k + 1][0] - path[k][0]) * q, y: path[k][1] + (path[k + 1][1] - path[k][1]) * q, c: 0 });
  }
  const K = S.W < 700 ? 12 : 22;
  const cw = w / K;
  const floor = cy + h * 0.62;
  const candles = [];
  let lvl = h * 0.35;
  for (let k = 0; k < K; k++) {
    const up = Math.random() < 0.62;
    const body = rnd(h * 0.08, h * 0.3);
    lvl = Math.max(h * 0.12, Math.min(h * 0.75, lvl + (up ? body * 0.4 : -body * 0.4)));
    candles.push({ x: left + cw * (k + 0.5), top: floor - lvl - body, body, wick: rnd(h * 0.03, h * 0.1), c: up ? 1 : 2 });
  }
  for (let i = 0; i < n - nLine; i++) {
    const cd = candles[i % K];
    tg.push(Math.random() < 0.15 ? { x: cd.x, y: cd.top - cd.wick + Math.random() * (cd.body + cd.wick * 2), c: cd.c } : { x: cd.x + rnd(-cw * 0.26, cw * 0.26), y: cd.top + Math.random() * cd.body, c: cd.c });
  }
  const end = path[path.length - 1];
  S.labels = [...TICKERS]
    .sort(() => Math.random() - 0.5)
    .slice(0, S.W < 700 ? 2 : 4)
    .map((t, i, a) => {
      const up = Math.random() < 0.72;
      const at = path[Math.round(((i + 1) / (a.length + 0.4)) * steps)] || end;
      return { t, v: `${up ? "+" : "−"}${rnd(0.4, 6.8).toFixed(2).replace(".", ",")} %`, up, x: at[0], y: at[1] - 26 - (i % 2) * 18, d: i * 180 };
    });
  return tg.sort((a, b) => a.x - b.x);
}

function build() {
  const cv = S.cv;
  const r = cv.getBoundingClientRect();
  if (!r.width) return false;
  S.dpr = Math.min(2, devicePixelRatio || 1);
  S.W = r.width;
  S.H = r.height;
  cv.width = Math.round(S.W * S.dpr);
  cv.height = Math.round(S.H * S.dpr);
  const mobile = S.W < 700;
  const n = mobile ? 620 : 1100;
  const width = Math.min(S.W * (mobile ? 0.92 : 0.8), 1080);
  const cx = S.W / 2;
  // Schriftzug und Chart sitzen auf der eigenen Bühne unter den Knöpfen
  const st = document.getElementById("hx-stage")?.getBoundingClientRect();
  const cy = st && st.height ? st.top - r.top + st.height / 2 : S.H - 150;
  const { out, w, h } = sampleWord(cx, cy, width, n);
  const tg = chartTargets(cx, cy, w, (st && st.height ? st.height : 220) * 0.72, out.length);
  const src = out.slice().sort((a, b) => a[0] - b[0]);
  const old = S.pts;
  S.pts = src.map(([wx, wy], i) => {
    const o = old[i];
    const x0 = o ? o.x : rnd(0, S.W);
    const y0 = o ? o.y : rnd(0, S.H);
    return { x: x0, y: y0, sx: x0, sy: y0, fx: 0, fy: 0, wx, wy, tx: tg[i].x, ty: tg[i].y, c: tg[i].c, d: (wx - (cx - w / 2)) / w, j: Math.random(), vx: 0, vy: 0 };
  });
  S.sp = [sprite("150,190,255", mobile ? 10 : 12), sprite("52,211,153", 10), sprite("248,113,113", 10), sprite("210,228,255", mobile ? 16 : 20)];
  S.built = true;
  return true;
}

function frame(now) {
  S.raf = requestAnimationFrame(frame);
  if (!S.visible || document.hidden) return;
  const { x, W, H, dpr } = S;
  if (!S.t0) S.t0 = now;
  let t = now - S.t0;
  if (t > LOOP) {
    // neue Runde: vom Chart zurück zum Schriftzug, mit neuem Chart
    build();
    S.t0 = now;
    t = 0;
  }
  const a1 = P.form;
  const a2 = a1 + P.glow;
  const a3 = a2 + P.burst;
  x.setTransform(dpr, 0, 0, dpr, 0, 0);
  // Leuchtspuren: altes Bild nur teilweise löschen
  x.globalCompositeOperation = "destination-out";
  x.fillStyle = "rgba(0,0,0,0.42)";
  x.fillRect(0, 0, W, H);
  x.globalCompositeOperation = "lighter";
  let flash = 0;
  if (t >= a1 && t < a2) {
    const q = (t - a1) / P.glow;
    flash = Math.pow(Math.sin(q * Math.PI * 2), 2) * (q < 0.5 ? 1 : 0.7);
  }
  const wave = t >= a1 && t < a2 ? (t - a1) / P.glow : -1;
  const mx = S.mouse.x;
  const my = S.mouse.y;
  const chartQ = clamp((t - a3 + 400) / 900);
  for (const p of S.pts) {
    let bx;
    let by;
    let big = false;
    let col = 0;
    if (t < a1) {
      const q = ease(clamp((t / a1 - p.j * 0.3) / 0.7));
      const sw = Math.sin(q * Math.PI) * (18 + p.j * 36);
      bx = p.sx + (p.wx - p.sx) * q + Math.cos(p.j * 12) * sw;
      by = p.sy + (p.wy - p.sy) * q + Math.sin(p.j * 12) * sw;
    } else if (t < a2) {
      bx = p.wx;
      by = p.wy + Math.sin(now / 420 + p.d * 8) * 0.8;
      big = wave >= 0 && Math.abs(p.d - wave * 1.3 + 0.15) < 0.07;
    } else {
      const q = outExpo(clamp(((t - a2) / P.burst - p.d * 0.5) / 0.5));
      const arc = Math.sin(q * Math.PI) * (16 + p.j * 40);
      bx = p.wx + (p.tx - p.wx) * q + (p.j - 0.5) * arc;
      by = p.wy + (p.ty - p.wy) * q - arc;
      if (t > a3) by += Math.sin(now / 600 + p.d * 14) * 1.4;
      col = q > 0.55 ? p.c : 0;
    }
    // der Maus ausweichen (federnd)
    const dx = bx + p.fx - mx;
    const dy = by + p.fy - my;
    const dd = dx * dx + dy * dy;
    if (dd < 9000) {
      const f = (1 - dd / 9000) * 7;
      const l = Math.sqrt(dd) || 1;
      p.vx += (dx / l) * f;
      p.vy += (dy / l) * f;
    }
    p.vx = (p.vx - p.fx * 0.08) * 0.82;
    p.vy = (p.vy - p.fy * 0.08) * 0.82;
    p.fx += p.vx;
    p.fy += p.vy;
    p.x = bx + p.fx;
    p.y = by + p.fy;
    const spr = big ? S.sp[3] : S.sp[col];
    const n = spr.width * (big ? 1 : 0.55 + p.j * 0.45) * (1 + flash * 0.5);
    x.globalAlpha = Math.min(1, (col ? 0.7 : 0.42 + 0.3 * p.j) + flash * 0.45);
    x.drawImage(spr, p.x - n / 2, p.y - n / 2, n, n);
  }
  // Kurslinie und Schilder, sobald der Chart steht
  if (chartQ > 0 && S.path.length) {
    const pts = S.path;
    const upto = Math.max(2, Math.round(pts.length * chartQ));
    x.globalAlpha = 0.9 * chartQ;
    x.lineWidth = 2.2;
    x.lineJoin = "round";
    x.strokeStyle = "rgba(140,190,255,0.9)";
    x.beginPath();
    for (let i = 0; i < upto; i++) {
      const yy = pts[i][1] + Math.sin(now / 600 + i * 0.5) * 1.2;
      i ? x.lineTo(pts[i][0], yy) : x.moveTo(pts[i][0], yy);
    }
    x.stroke();
    const hd = pts[upto - 1];
    const pulse = 0.6 + 0.4 * Math.sin(now / 220);
    const hs = 26 + pulse * 12;
    x.globalAlpha = chartQ;
    x.drawImage(S.sp[3], hd[0] - hs / 2, hd[1] - hs / 2, hs, hs);
    x.globalCompositeOperation = "source-over";
    const fs = W < 700 ? 11 : 13;
    x.font = `700 ${fs}px Manrope, system-ui, sans-serif`;
    for (const l of S.labels) {
      const q = clamp((t - a3 - l.d) / 500);
      if (!q) continue;
      const lx = l.x;
      const ly = l.y - (1 - outExpo(q)) * 12;
      const txt = `${l.t}  ${l.v}`;
      const tw = x.measureText(txt).width + 18;
      x.globalAlpha = q * 0.92;
      x.fillStyle = "rgba(10,22,60,0.72)";
      x.beginPath();
      x.roundRect ? x.roundRect(lx - tw / 2, ly - fs - 5, tw, fs + 12, 9) : x.rect(lx - tw / 2, ly - fs - 5, tw, fs + 12);
      x.fill();
      x.strokeStyle = "rgba(160,200,255,0.35)";
      x.lineWidth = 1;
      x.stroke();
      x.fillStyle = "#fff";
      x.fillText(l.t, lx - tw / 2 + 9, ly + 1);
      x.fillStyle = l.up ? "#34d399" : "#f87171";
      x.fillText(l.v, lx - tw / 2 + 9 + x.measureText(l.t + "  ").width, ly + 1);
    }
  }
  x.globalAlpha = 1;
  x.globalCompositeOperation = "source-over";
}

export function heroFx(on) {
  const cv = document.getElementById("hero-canvas");
  if (!cv || REDUCED) return;
  if (!S.cv) {
    S.cv = cv;
    S.x = cv.getContext("2d");
    new IntersectionObserver(([e]) => (S.visible = e.isIntersecting)).observe(cv);
    const hero = cv.parentElement;
    const move = (e) => {
      const r = cv.getBoundingClientRect();
      S.mouse.x = e.clientX - r.left;
      S.mouse.y = e.clientY - r.top;
    };
    hero.addEventListener("pointermove", move, { passive: true });
    hero.addEventListener("pointerdown", move, { passive: true });
    hero.addEventListener("pointerleave", () => (S.mouse.x = S.mouse.y = -9999));
    let rt = 0;
    addEventListener("resize", () => {
      clearTimeout(rt);
      rt = setTimeout(() => S.on && build(), 250);
    });
  }
  cancelAnimationFrame(S.raf);
  S.on = on;
  if (!on) return;
  requestAnimationFrame(() => {
    if (!S.on) return;
    if (!build()) return;
    S.t0 = 0;
    S.raf = requestAnimationFrame(frame);
  });
}

// ---------- Effekte auf der Startseite ----------
export function initHomeFx(root) {
  if (!root || root.dataset.fx) return;
  root.dataset.fx = "1";
  // Zahlen zählen hoch, sobald sie sichtbar werden
  const io = new IntersectionObserver(
    (es) =>
      es.forEach((e) => {
        if (!e.isIntersecting) return;
        io.unobserve(e.target);
        const el = e.target;
        const to = +el.dataset.count;
        const suf = el.dataset.suffix || "";
        if (REDUCED) return;
        const t0 = performance.now();
        const step = (now) => {
          const q = Math.min(1, (now - t0) / 1400);
          el.textContent = Math.round(to * outExpo(q)) + suf;
          if (q < 1) requestAnimationFrame(step);
        };
        requestAnimationFrame(step);
      }),
    { threshold: 0.6 },
  );
  root.querySelectorAll("[data-count]").forEach((el) => io.observe(el));
  if (REDUCED) return;
  // Karten neigen sich zur Maus, ein Lichtfleck folgt dem Zeiger
  const tiltSel = ".feature, .usp-step, .fu-hero, .ac-hero, .lg-hero, .jvp-card, .band div, .hx-go";
  root.addEventListener(
    "pointermove",
    (e) => {
      if (e.pointerType !== "mouse") return;
      const el = e.target.closest(tiltSel);
      if (!el) return;
      const r = el.getBoundingClientRect();
      const px = (e.clientX - r.left) / r.width;
      const py = (e.clientY - r.top) / r.height;
      el.style.setProperty("--mx", `${(px * 100).toFixed(1)}%`);
      el.style.setProperty("--my", `${(py * 100).toFixed(1)}%`);
      if (el.classList.contains("hx-go")) {
        el.style.setProperty("--tx", `${((px - 0.5) * 10).toFixed(1)}px`);
        el.style.setProperty("--ty", `${((py - 0.5) * 8).toFixed(1)}px`);
      } else if (r.width < 700) {
        el.style.setProperty("--rx", `${((0.5 - py) * 7).toFixed(2)}deg`);
        el.style.setProperty("--ry", `${((px - 0.5) * 9).toFixed(2)}deg`);
      }
    },
    { passive: true },
  );
  root.addEventListener(
    "pointerout",
    (e) => {
      const el = e.target.closest(tiltSel);
      if (el && !el.contains(e.relatedTarget)) ["--rx", "--ry", "--tx", "--ty"].forEach((k) => el.style.removeProperty(k));
    },
    { passive: true },
  );
  // Parallaxe: der Hero-Inhalt gleitet beim Scrollen weich nach oben und verblasst
  const hero = root.querySelector(".hx");
  let ticking = false;
  root.addEventListener(
    "scroll",
    () => {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(() => {
        ticking = false;
        const h = hero?.offsetHeight || 1;
        const q = Math.min(1, root.scrollTop / h);
        hero?.style.setProperty("--hs", q.toFixed(3));
      });
    },
    { passive: true },
  );
}
