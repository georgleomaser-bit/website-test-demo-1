// Weltraum-Hintergrund: drei Sternen-Ebenen mit Parallax, Funkeln und gelegentlichen Sternschnuppen.
// Vorgerenderte Ebenen + wenige bewegte Punkte = flüssig auch auf dem Handy. Pausiert im Hintergrund-Tab.
export function startSpace(canvas) {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const g = canvas.getContext("2d");
  let W = 0;
  let H = 0;
  let dpr = 1;
  let layers = [];
  let twinkles = [];
  let shoot = null;
  let mx = 0;
  let my = 0;
  const HUES = ["255,255,255", "190,210,255", "220,200,255", "170,230,255", "255,230,210"];
  function build() {
    dpr = Math.min(2, devicePixelRatio || 1);
    W = innerWidth;
    H = innerHeight;
    canvas.width = W * dpr;
    canvas.height = H * dpr;
    const area = (W * H) / 1e6;
    layers = [0.25, 0.55, 1].map((depth, li) => {
      const c = document.createElement("canvas");
      c.width = (W + 80) * dpr;
      c.height = (H + 80) * dpr;
      const x = c.getContext("2d");
      const n = Math.round([520, 220, 70][li] * area + [80, 30, 10][li]);
      for (let i = 0; i < n; i++) {
        const r = (0.35 + Math.random() * (0.6 + li * 0.7)) * dpr;
        x.fillStyle = `rgba(${HUES[(Math.random() * HUES.length) | 0]},${0.25 + Math.random() * 0.6})`;
        x.beginPath();
        x.arc(Math.random() * c.width, Math.random() * c.height, r, 0, Math.PI * 2);
        x.fill();
        if (li === 2 && Math.random() < 0.12) {
          const gl = x.createRadialGradient(0, 0, 0, 0, 0, r * 3.5);
          x.save();
          x.translate(Math.random() * c.width, Math.random() * c.height);
          gl.addColorStop(0, "rgba(200,220,255,0.28)");
          gl.addColorStop(1, "rgba(200,220,255,0)");
          x.fillStyle = gl;
          x.fillRect(-r * 3.5, -r * 3.5, r * 7, r * 7);
          x.restore();
        }
      }
      return { c, depth, drift: [0.004, 0.009, 0.016][li] };
    });
    twinkles = Array.from({ length: Math.round(40 * area + 12) }, () => ({ x: Math.random() * W, y: Math.random() * H, s: Math.random() * 6.28, sp: 0.6 + Math.random() * 1.6, r: 0.8 + Math.random() * 1.4 }));
  }
  addEventListener("resize", () => {
    clearTimeout(build.t);
    build.t = setTimeout(build, 150);
  });
  addEventListener("pointermove", (e) => {
    mx = (e.clientX / W - 0.5) * 2;
    my = (e.clientY / H - 0.5) * 2;
  });
  build();
  let last = 0;
  const loop = (now) => {
    requestAnimationFrame(loop);
    if (document.hidden) return;
    if (now - last < 32 && !reduce) return; // ~30 Bilder/s reichen für Sterne – spart Akku
    last = now;
    const t = now / 1000;
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.clearRect(0, 0, W, H);
    for (const L of layers) {
      const ox = -40 + ((t * L.drift * 60) % 40) - mx * 14 * L.depth;
      const oy = -40 - my * 10 * L.depth;
      g.drawImage(L.c, ox, oy, W + 80, H + 80);
    }
    for (const s of twinkles) {
      const a = 0.25 + 0.75 * Math.pow(Math.max(0, Math.sin(t * s.sp + s.s)), 3);
      g.fillStyle = `rgba(235,240,255,${a})`;
      g.beginPath();
      g.arc(s.x, s.y, s.r * (0.7 + a * 0.5), 0, Math.PI * 2);
      g.fill();
    }
    // Sternschnuppe ab und zu
    if (!reduce && !shoot && Math.random() < 0.004) shoot = { x: Math.random() * W * 0.8, y: Math.random() * H * 0.4, vx: 9 + Math.random() * 6, vy: 3 + Math.random() * 3, life: 1 };
    if (shoot) {
      const gr = g.createLinearGradient(shoot.x, shoot.y, shoot.x - shoot.vx * 9, shoot.y - shoot.vy * 9);
      gr.addColorStop(0, `rgba(255,255,255,${shoot.life})`);
      gr.addColorStop(1, "rgba(160,190,255,0)");
      g.strokeStyle = gr;
      g.lineWidth = 1.6;
      g.beginPath();
      g.moveTo(shoot.x, shoot.y);
      g.lineTo(shoot.x - shoot.vx * 9, shoot.y - shoot.vy * 9);
      g.stroke();
      shoot.x += shoot.vx;
      shoot.y += shoot.vy;
      shoot.life -= 0.025;
      if (shoot.life <= 0 || shoot.x > W + 100) shoot = null;
    }
  };
  requestAnimationFrame(loop);
}
