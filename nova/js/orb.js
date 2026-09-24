// NOVA-Kern: leuchtende Partikel-Kugel (Canvas), reagiert auf Zuhören, Denken und Sprechen.
// Leuchtpunkte werden vorgerendert und je Farbe neu gemalt – flüssig auch auf dem Handy.
const REDUCED = matchMedia("(prefers-reduced-motion: reduce)").matches;
const COLORS = { idle: [140, 120, 255], listen: [90, 200, 255], think: [200, 110, 255], speak: [120, 170, 255], error: [255, 110, 110] };
const mix = (a, b, k) => a.map((v, i) => v + (b[i] - v) * k);
function sprites(rgb) {
  const hi = mix(rgb, [255, 255, 255], 0.85).map(Math.round);
  return [3, 5, 8, 12].map((n) => {
    const c = document.createElement("canvas");
    c.width = c.height = n;
    const g = c.getContext("2d");
    const gr = g.createRadialGradient(n / 2, n / 2, 0, n / 2, n / 2, n / 2);
    gr.addColorStop(0, `rgba(${hi},1)`);
    gr.addColorStop(0.35, `rgba(${rgb.map(Math.round)},0.85)`);
    gr.addColorStop(1, `rgba(${rgb.map(Math.round)},0)`);
    g.fillStyle = gr;
    g.fillRect(0, 0, n, n);
    return { n, c };
  });
}
export function createOrb(canvas) {
  const N = matchMedia("(max-width: 700px)").matches ? 520 : 820;
  const GOLD = Math.PI * (3 - Math.sqrt(5));
  const pts = Array.from({ length: N }, (_, i) => {
    const y = 1 - (2 * (i + 0.5)) / N;
    const r = Math.sqrt(1 - y * y);
    const a = i * GOLD;
    return { x: Math.cos(a) * r, y, z: Math.sin(a) * r, s: (i * 12.9898) % 6.283, ring: i % 7 === 0 };
  });
  const RING = [
    { r: 1.5, n: 110, tilt: 0.42, sp: 0.35 },
    { r: 1.82, n: 80, tilt: 0.46, sp: -0.22 },
  ].flatMap((ring) => Array.from({ length: ring.n }, (_, i) => ({ ...ring, a: (i / ring.n) * Math.PI * 2 + Math.random() * 0.08, j: 0.94 + Math.random() * 0.12 })));
  const o = { state: "idle", lvl: 0.15, kick: 0, rgb: COLORS.idle.slice(), spr: sprites(COLORS.idle), sprAt: 0, ay: 0, raf: 0, last: 0 };
  const draw = (now) => {
    o.raf = requestAnimationFrame(draw);
    if (document.hidden) return;
    const dt = Math.min(0.05, (now - (o.last || now)) / 1000) || 0.016;
    o.last = now;
    const t = now / 1000;
    const target = { idle: 0.16 + 0.04 * Math.sin(t * 1.3), listen: 0.45 + 0.25 * Math.abs(Math.sin(t * 3.1)) + o.kick * 0.4, think: 0.5 + 0.18 * Math.sin(t * 5), speak: 0.5 + 0.28 * Math.abs(Math.sin(t * 6.3) * Math.sin(t * 2.1)) + o.kick * 0.3, error: 0.3 }[o.state] ?? 0.2;
    o.lvl += (target - o.lvl) * (1 - Math.pow(0.001, dt));
    o.kick *= Math.pow(0.03, dt);
    const want = COLORS[o.state] || COLORS.idle;
    o.rgb = mix(o.rgb, want, 1 - Math.pow(0.05, dt));
    if (now - o.sprAt > 80 && o.rgb.some((v, i) => Math.abs(v - want[i]) > 2)) {
      o.spr = sprites(o.rgb);
      o.sprAt = now;
    }
    canvas.parentElement?.style.setProperty("--lvl", o.lvl.toFixed(3));
    canvas.parentElement?.style.setProperty("--orb", o.rgb.map(Math.round).join(","));
    if (REDUCED && o.drawn) return;
    o.drawn = true;
    const dpr = Math.min(1.6, devicePixelRatio || 1);
    const W = Math.round((canvas.clientWidth || 280) * dpr);
    if (canvas.width !== W) canvas.width = canvas.height = W;
    const g = canvas.getContext("2d");
    const c = W / 2;
    const R = W * 0.24 * (1 + o.lvl * 0.08);
    const L = o.lvl;
    o.ay += dt * ({ think: 1.5, speak: 0.8, listen: 0.6 }[o.state] || 0.3);
    const ax = 0.4 + 0.1 * Math.sin(t * 0.3);
    const cy = Math.cos(o.ay);
    const sy = Math.sin(o.ay);
    const cx = Math.cos(ax);
    const sx = Math.sin(ax);
    const [r, gg, b] = o.rgb.map(Math.round);
    g.clearRect(0, 0, W, W);
    const glow = g.createRadialGradient(c, c, 0, c, c, R * (1.8 + L * 0.5));
    glow.addColorStop(0, `rgba(${r},${gg},${b},${0.3 + 0.3 * L})`);
    glow.addColorStop(0.5, `rgba(${r},${gg},${b},${0.08 + 0.1 * L})`);
    glow.addColorStop(1, "rgba(0,0,0,0)");
    g.fillStyle = glow;
    g.fillRect(0, 0, W, W);
    // Planetenkörper: dunkle Kugel mit Randlicht (wirkt räumlich, Partikel liegen darauf)
    const body = g.createRadialGradient(c - R * 0.35, c - R * 0.4, R * 0.1, c, c, R * 1.02);
    body.addColorStop(0, `rgba(${Math.min(255, r + 40)},${Math.min(255, gg + 40)},255,0.55)`);
    body.addColorStop(0.55, `rgba(${(r * 0.25) | 0},${(gg * 0.2) | 0},${(b * 0.45) | 0},0.85)`);
    body.addColorStop(0.92, "rgba(6,4,20,0.9)");
    body.addColorStop(1, `rgba(${r},${gg},${b},0.5)`);
    g.fillStyle = body;
    g.beginPath();
    g.arc(c, c, R * 1.02, 0, Math.PI * 2);
    g.fill();
    // Ringbahnen als feine Lichtlinien
    for (const [rr, w, al] of [
      [1.5, 1.2, 0.35],
      [1.82, 0.9, 0.22],
    ]) {
      g.strokeStyle = `rgba(${Math.min(255, r + 60)},${Math.min(255, gg + 60)},255,${al * (0.7 + 0.6 * L)})`;
      g.lineWidth = w * dpr;
      g.beginPath();
      g.ellipse(c, c, R * rr, R * rr * Math.sin(0.44), 0.08, 0, Math.PI * 2);
      g.stroke();
    }
    g.globalCompositeOperation = "lighter";
    for (const p of pts) {
      const wob = 1 + L * 0.12 * Math.sin(p.s * 3 + t * 2.4) + (p.ring ? 0.12 : 0);
      const X = p.x * cy + p.z * sy;
      const Z0 = -p.x * sy + p.z * cy;
      const Y = p.y * cx - Z0 * sx;
      const Z = p.y * sx + Z0 * cx;
      const depth = (1 - Z) / 2;
      const size = (p.ring ? 5 : 3.4) * (0.5 + depth) * dpr * (0.9 + 0.5 * L);
      const sp = o.spr[size < 4 ? 0 : size < 6.5 ? 1 : size < 10 ? 2 : 3];
      g.globalAlpha = Math.min(1, 0.2 + 0.7 * depth * (0.6 + 0.5 * L));
      g.drawImage(sp.c, (c + X * R * wob - sp.n / 2) | 0, (c + Y * R * wob - sp.n / 2) | 0);
    }
    // Umlaufringe (vorne heller als hinten – wirkt wie ein Planet mit Ringen)
    const ringSpeed = { think: 2.2, speak: 1.4, listen: 1.1 }[o.state] || 0.6;
    for (const q of RING) {
      const a = q.a + t * q.sp * ringSpeed;
      const ex = Math.cos(a) * q.r * q.j;
      const ey = Math.sin(a) * q.r * q.j * Math.sin(0.44);
      const rx = ex * Math.cos(0.08) - ey * Math.sin(0.08);
      const ry = ex * Math.sin(0.08) + ey * Math.cos(0.08);
      const front = Math.sin(a) > 0; // untere Hälfte liegt vor dem Planeten
      const sp = o.spr[front ? 2 : 1];
      g.globalAlpha = Math.min(1, (front ? 0.95 : 0.35) * (0.7 + 0.5 * L));
      g.drawImage(sp.c, (c + rx * R - sp.n / 2) | 0, (c + ry * R - sp.n / 2) | 0);
    }
    g.globalAlpha = 1;
    const core = g.createRadialGradient(c, c, 0, c, c, R * (0.45 + 0.2 * L));
    core.addColorStop(0, `rgba(255,255,255,${0.8 + 0.2 * L})`);
    core.addColorStop(0.4, `rgba(${r},${gg},${b},${0.5 + 0.3 * L})`);
    core.addColorStop(1, "rgba(0,0,0,0)");
    g.fillStyle = core;
    g.beginPath();
    g.arc(c, c, R * (0.45 + 0.2 * L), 0, Math.PI * 2);
    g.fill();
    g.globalCompositeOperation = "source-over";
  };
  o.raf = requestAnimationFrame(draw);
  return {
    set(state) {
      o.state = state;
      o.kick = 1;
    },
    kick(v = 0.7) {
      o.kick = Math.max(o.kick, v);
    },
    get state() {
      return o.state;
    },
  };
}
