// NOVA-Zeichen: schlichte, animierte Marke (reines CSS) – reagiert auf Zuhören, Denken und Sprechen.
// Die Stärke der Bewegung (--lvl) wird hier weich geglättet; Form und Farben stehen in nova.css.
const REDUCED = matchMedia("(prefers-reduced-motion: reduce)").matches;
export function createOrb(el) {
  const o = { state: "idle", lvl: 0.1, kick: 0, last: 0 };
  const tick = (now) => {
    requestAnimationFrame(tick);
    if (document.hidden) return;
    const dt = Math.min(0.05, (now - (o.last || now)) / 1000) || 0.016;
    o.last = now;
    const t = now / 1000;
    const target = { idle: 0.1, listen: 0.45 + 0.25 * Math.abs(Math.sin(t * 3.1)) + o.kick * 0.3, think: 0.35 + 0.15 * Math.sin(t * 4), speak: 0.4 + 0.3 * Math.abs(Math.sin(t * 6.3) * Math.sin(t * 2.1)) + o.kick * 0.25, error: 0.2 }[o.state] ?? 0.1;
    o.lvl += (target - o.lvl) * (1 - Math.pow(0.002, dt));
    o.kick *= Math.pow(0.03, dt);
    if (!REDUCED) document.documentElement.style.setProperty("--lvl", o.lvl.toFixed(3));
  };
  requestAnimationFrame(tick);
  return {
    set(state) {
      o.state = state;
      o.kick = 1;
      el.dataset.state = state;
    },
    kick(v = 0.7) {
      o.kick = Math.max(o.kick, v);
    },
    get state() {
      return o.state;
    },
  };
}
