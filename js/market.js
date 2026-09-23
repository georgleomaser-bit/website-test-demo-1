// Markt-Simulation: erzeugt realistische Kurshistorien und Live-Ticks für alle Aktien.
import { STOCKS } from "./data.js";

export const TIMEFRAMES = [
  { id: "1m", label: "1m", sec: 60 },
  { id: "5m", label: "5m", sec: 300 },
  { id: "15m", label: "15m", sec: 900 },
  { id: "1h", label: "1H", sec: 3600 },
  { id: "4h", label: "4H", sec: 14400 },
  { id: "1D", label: "1T", sec: 86400 },
  { id: "1W", label: "1W", sec: 604800 },
];
const TF_SEC = Object.fromEntries(TIMEFRAMES.map((t) => [t.id, t.sec]));

const DAY = 86400;
const WEEK = 604800;
const WEEK_OFFSET = 4 * DAY; // 05.01.1970 war ein Montag
const INTRADAY_DAYS = 7; // Minutenkerzen der letzten 7 Tage
const HISTORY_DAYS = 720; // davor Tageskerzen
export const TICK_MS = 400;
const LIVELY = 1.6; // etwas mehr Bewegung als in echt – ist ja eine Demo

// Alle Zeiten sind in "lokalen Sekunden", damit der Chart die Ortszeit anzeigt.
export const nowSec = () => Math.floor(Date.now() / 1000) - new Date().getTimezoneOffset() * 60;
export const toLocalSec = (ms) => Math.floor(ms / 1000) - new Date(ms).getTimezoneOffset() * 60;

export function bucketOf(t, tf) {
  if (tf === "1W") return Math.floor((t - WEEK_OFFSET) / WEEK) * WEEK + WEEK_OFFSET;
  const s = TF_SEC[tf];
  return Math.floor(t / s) * s;
}

function mulberry32(a) {
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function hash(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}
function gauss(rnd) {
  const u = 1 - rnd();
  const v = rnd();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}
// Handelsaktivität über den Tag (mehr Umsatz zur Eröffnung und am Nachmittag)
function season(t) {
  const h = (t % DAY) / 3600;
  return 0.55 + 0.9 * (Math.exp(-((h - 9.5) ** 2) / 3) + Math.exp(-((h - 16) ** 2) / 3));
}

export function tickStep(price) {
  if (price < 10) return 0.005;
  if (price < 50) return 0.01;
  if (price < 200) return 0.02;
  if (price < 1000) return 0.05;
  return 0.2;
}

function generate(def, now) {
  const rnd = mulberry32(hash(def.s + ":" + Math.floor(now / DAY)));
  const sigmaD = def.v / Math.sqrt(365);
  const sigmaM = (sigmaD / Math.sqrt(1440)) * LIVELY;
  const adv = Math.max(2e5, def.sh * 1e9 * 0.0035); // durchschnittliches Tagesvolumen
  const todayStart = Math.floor(now / DAY) * DAY;
  const intraStart = todayStart - (INTRADAY_DAYS - 1) * DAY;

  const days = [];
  let price = def.p * (0.55 + rnd() * 0.8);
  let vs = 1; // Volatilitätsregime
  let drift = (rnd() - 0.45) * sigmaD * 0.1;
  for (let i = HISTORY_DAYS; i >= 1; i--) {
    if (i % 60 === 0) drift = (rnd() - 0.47) * sigmaD * 0.12; // Trendwechsel
    vs = Math.exp(0.92 * Math.log(vs) + 0.22 * gauss(rnd));
    const open = price * (1 + gauss(rnd) * sigmaD * 0.15);
    const ret = drift + gauss(rnd) * sigmaD * vs;
    const close = open * Math.exp(ret);
    const high = Math.max(open, close) * (1 + Math.abs(gauss(rnd)) * sigmaD * 0.45 * vs);
    const low = Math.min(open, close) * (1 - Math.abs(gauss(rnd)) * sigmaD * 0.45 * vs);
    const volume = Math.round(adv * vs * Math.exp(gauss(rnd) * 0.3) * (1 + (Math.abs(ret) / sigmaD) * 0.3));
    days.push({ time: intraStart - i * DAY, open, high, low, close, volume });
    price = close;
  }

  const m1 = [];
  const lastMin = Math.floor(now / 60) * 60;
  for (let t = intraStart; t <= lastMin; t += 60) {
    vs = Math.exp(0.998 * Math.log(vs) + 0.03 * gauss(rnd));
    const sz = season(t);
    const s = sigmaM * vs * Math.sqrt(sz);
    const open = price;
    let c = open;
    let high = open;
    let low = open;
    for (let k = 0; k < 4; k++) {
      c *= Math.exp(gauss(rnd) * s * 0.5);
      if (c > high) high = c;
      if (c < low) low = c;
    }
    const volume = Math.round((adv / 1440) * sz * vs * Math.exp(gauss(rnd) * 0.5) * (1 + (Math.abs(c / open - 1) / s) * 0.4));
    m1.push({ time: t, open, high, low, close: c, volume });
    price = c;
  }

  // auf den Referenzkurs skalieren
  const f = def.p / price;
  for (const arr of [days, m1]) {
    for (const b of arr) {
      b.open *= f;
      b.high *= f;
      b.low *= f;
      b.close *= f;
    }
  }
  // Tageskerzen aus den Minutenkerzen ergänzen
  for (const d of aggregate(m1, "1D")) days.push(d);

  return { ...def, days, m1, price: def.p, prev: def.p, vs, sigmaM, adv, trades: [] };
}

export function aggregate(src, tf) {
  const out = [];
  let cur = null;
  for (const b of src) {
    const t = bucketOf(b.time, tf);
    if (!cur || cur.time !== t) {
      cur = { time: t, open: b.open, high: b.high, low: b.low, close: b.close, volume: b.volume };
      out.push(cur);
    } else {
      if (b.high > cur.high) cur.high = b.high;
      if (b.low < cur.low) cur.low = b.low;
      cur.close = b.close;
      cur.volume += b.volume;
    }
  }
  return out;
}

export class Market {
  constructor() {
    const now = nowSec();
    this.stocks = new Map(STOCKS.map((d) => [d.s, generate(d, now)]));
    this.listeners = new Set();
    this.timer = null;
  }

  get list() {
    return [...this.stocks.values()];
  }
  get(sym) {
    return this.stocks.get(sym);
  }
  has(sym) {
    return this.stocks.has(sym);
  }
  onTick(fn) {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }
  start() {
    if (!this.timer) this.timer = setInterval(() => this.tick(), TICK_MS);
  }

  tick() {
    const t = nowSec();
    const minute = Math.floor(t / 60) * 60;
    const day = Math.floor(t / DAY) * DAY;
    const sz = season(t);
    const dtFactor = Math.sqrt(TICK_MS / 60000);
    for (const st of this.stocks.values()) {
      st.vs = Math.exp(0.9995 * Math.log(st.vs) + 0.012 * gauss(Math.random));
      let r = gauss(Math.random) * st.sigmaM * st.vs * Math.sqrt(sz) * dtFactor;
      if (Math.random() < 0.0004) r += gauss(Math.random) * st.sigmaM * 6; // gelegentliche Sprünge (News)
      const price = st.price * Math.exp(r);
      const vol = Math.max(1, Math.round((st.adv / 1440) * dtFactor ** 2 * sz * st.vs * Math.exp(gauss(Math.random) * 0.7)));

      let c = st.m1[st.m1.length - 1];
      if (c.time !== minute) {
        c = { time: minute, open: st.price, high: st.price, low: st.price, close: st.price, volume: 0 };
        st.m1.push(c);
        if (st.m1.length > INTRADAY_DAYS * 1440 + 60) st.m1.shift();
      }
      c.high = Math.max(c.high, price);
      c.low = Math.min(c.low, price);
      c.close = price;
      c.volume += vol;

      let d = st.days[st.days.length - 1];
      if (d.time !== day) {
        d = { time: day, open: st.price, high: st.price, low: st.price, close: st.price, volume: 0 };
        st.days.push(d);
      }
      d.high = Math.max(d.high, price);
      d.low = Math.min(d.low, price);
      d.close = price;
      d.volume += vol;

      st.trades.unshift({ ts: Date.now(), price, size: vol, side: price >= st.price ? "buy" : "sell" });
      if (st.trades.length > 60) st.trades.length = 60;

      st.prev = st.price;
      st.price = price;
    }
    for (const fn of this.listeners) fn();
  }

  bars(sym, tf) {
    const st = this.get(sym);
    if (tf === "1D") return st.days.map((b) => ({ ...b }));
    if (tf === "1W") return aggregate(st.days, "1W");
    if (tf === "1m") return st.m1.map((b) => ({ ...b }));
    return aggregate(st.m1, tf);
  }

  lastBar(sym, tf) {
    const st = this.get(sym);
    if (tf === "1m") return { ...st.m1[st.m1.length - 1] };
    if (tf === "1D") return { ...st.days[st.days.length - 1] };
    const src = tf === "1W" ? st.days : st.m1;
    const start = bucketOf(src[src.length - 1].time, tf);
    let i = src.length - 1;
    while (i > 0 && src[i - 1].time >= start) i--;
    return aggregate(src.slice(i), tf)[0];
  }

  quote(sym) {
    const st = this.get(sym);
    const today = st.days[st.days.length - 1];
    const prevClose = st.days[st.days.length - 2].close;
    const year = st.days.slice(-365);
    const month = st.days.slice(-31, -1);
    const step = tickStep(st.price);
    const spread = Math.max(step, st.price * 0.0004);
    const bid = Math.floor((st.price - spread / 2) / step) * step;
    const ask = bid + Math.ceil(spread / step) * step;
    return {
      symbol: st.s,
      name: st.n,
      price: st.price,
      prev: st.prev,
      prevClose,
      change: st.price - prevClose,
      changePct: (st.price - prevClose) / prevClose,
      open: today.open,
      high: today.high,
      low: today.low,
      volume: today.volume,
      bid,
      ask,
      high52: Math.max(...year.map((d) => d.high)),
      low52: Math.min(...year.map((d) => d.low)),
      avgVolume: month.reduce((a, d) => a + d.volume, 0) / Math.max(1, month.length),
      marketCap: st.sh * 1e9 * st.price,
      pe: st.pe,
      dy: st.dy,
      sector: st.sec,
      exchange: st.ex,
    };
  }

  // Performance über einen Zeitraum in Tagen (für den Screener)
  perf(sym, days) {
    const st = this.get(sym);
    const ref = st.days[Math.max(0, st.days.length - 1 - days)].close;
    return (st.price - ref) / ref;
  }

  orderBook(sym, depth = 12) {
    const st = this.get(sym);
    const q = this.quote(sym);
    const step = tickStep(st.price);
    const base = st.adv / 1440 / 6;
    const lvl = (i) => Math.max(1, Math.round(base * (0.25 + Math.random() * 1.2) * (1 + i * 0.18)));
    const bids = [];
    const asks = [];
    for (let i = 0; i < depth; i++) {
      bids.push({ price: q.bid - i * step, size: lvl(i) });
      asks.push({ price: q.ask + i * step, size: lvl(i) });
    }
    return { bids, asks, spread: q.ask - q.bid };
  }
}
