// AKYTEX AI Labor: erweiterte Analysefunktionen (Muster, Prognosen, Risiko, Backtests, Portfolio-Werkzeuge)
import { analyze, rating } from "./analysis.js";
import * as ind from "./indicators.js";
import { aggregate } from "./market.js";

const f2 = (v) => v.toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const mean = (a) => (a.length ? a.reduce((s, v) => s + v, 0) / a.length : 0);
const std = (a) => {
  const m = mean(a);
  return Math.sqrt(mean(a.map((v) => (v - m) ** 2)));
};
const rets = (closes) => closes.slice(1).map((c, i) => Math.log(c / closes[i]));
// Standardnormal-Verteilungsfunktion
const ncdf = (x) => {
  const t = 1 / (1 + 0.2316419 * Math.abs(x));
  const d = 0.3989423 * Math.exp((-x * x) / 2);
  const p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))));
  return x > 0 ? 1 - p : p;
};
function gauss() {
  const u = 1 - Math.random();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * Math.random());
}

export const barsFor = (market, sym, tf) => {
  const st = market.get(sym);
  if (tf === "1D") return st.days.slice(-400);
  return aggregate(st.m1, tf);
};

// 1 · Multi-Timeframe-Konsens
export function mtf(market, sym) {
  const frames = ["15m", "1h", "4h", "1D"].map((tf) => {
    const a = analyze(barsFor(market, sym, tf));
    return { tf, score: a.score, rating: a.rating };
  });
  const consensus = mean(frames.map((f) => f.score));
  const sameSign = frames.filter((f) => Math.sign(f.score) === Math.sign(consensus)).length;
  return { frames, consensus, rating: rating(consensus), agreement: sameSign / frames.length };
}

// 2 · Signal-Konfidenz (Übereinstimmung von Indikatoren und Zeitebenen)
export function confidence(market, sym) {
  const m = mtf(market, sym);
  const a = analyze(barsFor(market, sym, "1h"));
  const all = [...a.oscillators.list, ...a.movingAverages.list];
  const dir = Math.sign(m.consensus) || 1;
  const agree = all.filter((s) => Math.sign(s.action) === dir).length / all.length;
  return Math.round((agree * 0.5 + m.agreement * 0.5) * 100);
}

// 3 · Score-Erklärung
export function explain(market, sym) {
  const a = analyze(barsFor(market, sym, "1h"));
  const n = a.oscillators.list.length;
  const m = a.movingAverages.list.length;
  const items = [
    ...a.oscillators.list.map((s) => ({ name: s.name, value: s.value, contrib: (s.action * 0.45) / n })),
    ...a.movingAverages.list.map((s) => ({ name: s.name, value: s.value, contrib: (s.action * 0.55) / m })),
  ].sort((x, y) => Math.abs(y.contrib) - Math.abs(x.contrib));
  return { score: a.score, rating: a.rating, items };
}

// 4 · Kerzenmuster
export function patterns(bars) {
  const out = [];
  const n = bars.length;
  if (n < 4) return out;
  const [a, b, c] = [bars[n - 3], bars[n - 2], bars[n - 1]];
  const body = (x) => Math.abs(x.close - x.open);
  const range = (x) => x.high - x.low || 1e-9;
  const up = (x) => x.close > x.open;
  const lowerWick = (x) => Math.min(x.open, x.close) - x.low;
  const upperWick = (x) => x.high - Math.max(x.open, x.close);
  const trendDown = bars[n - 6] && bars[n - 6].close > b.close;
  const trendUp = bars[n - 6] && bars[n - 6].close < b.close;
  if (body(c) / range(c) < 0.1) out.push({ name: "Doji", bias: 0, text: "Unentschlossenheit – Richtungswechsel möglich" });
  if (lowerWick(c) > 2 * body(c) && upperWick(c) < body(c) && trendDown) out.push({ name: "Hammer", bias: 1, text: "Käufer drehen den Kurs nach Abverkauf" });
  if (upperWick(c) > 2 * body(c) && lowerWick(c) < body(c) && trendUp) out.push({ name: "Shooting Star", bias: -1, text: "Verkäufer drücken nach Anstieg" });
  if (up(c) && !up(b) && c.close > b.open && c.open < b.close) out.push({ name: "Bullish Engulfing", bias: 1, text: "Grüne Kerze umschließt die rote – Kaufdruck" });
  if (!up(c) && up(b) && c.close < b.open && c.open > b.close) out.push({ name: "Bearish Engulfing", bias: -1, text: "Rote Kerze umschließt die grüne – Verkaufsdruck" });
  if (!up(a) && body(b) / range(b) < 0.3 && up(c) && c.close > (a.open + a.close) / 2) out.push({ name: "Morning Star", bias: 1, text: "Dreikerzen-Umkehr nach oben" });
  if (up(a) && body(b) / range(b) < 0.3 && !up(c) && c.close < (a.open + a.close) / 2) out.push({ name: "Evening Star", bias: -1, text: "Dreikerzen-Umkehr nach unten" });
  if (up(a) && up(b) && up(c) && b.close > a.close && c.close > b.close) out.push({ name: "Drei weiße Soldaten", bias: 1, text: "Drei starke Anstiegskerzen in Folge" });
  return out;
}

// 5 · RSI-Divergenzen
export function divergence(bars) {
  const closes = bars.map((b) => b.close);
  const r = ind.rsi(closes, 14);
  const n = closes.length;
  if (n < 40) return null;
  const w = closes.slice(-30);
  const rw = r.slice(-30);
  const iLowOld = w.slice(0, 15).indexOf(Math.min(...w.slice(0, 15)));
  const iLowNew = 15 + w.slice(15).indexOf(Math.min(...w.slice(15)));
  const iHighOld = w.slice(0, 15).indexOf(Math.max(...w.slice(0, 15)));
  const iHighNew = 15 + w.slice(15).indexOf(Math.max(...w.slice(15)));
  if (w[iLowNew] < w[iLowOld] && rw[iLowNew] > rw[iLowOld] + 2) return { type: "bullish", text: "Bullische Divergenz: tieferes Kurstief, aber höheres RSI-Tief" };
  if (w[iHighNew] > w[iHighOld] && rw[iHighNew] < rw[iHighOld] - 2) return { type: "bearish", text: "Bärische Divergenz: höheres Kurshoch, aber tieferes RSI-Hoch" };
  return null;
}

// 6/7 · Bollinger-Squeeze & Ausbruch
export function squeeze(bars) {
  const closes = bars.map((b) => b.close);
  const bb = ind.bollinger(closes, 20, 2);
  const widths = bb.mid.map((m, i) => (m ? (bb.upper[i] - bb.lower[i]) / m : null)).filter((v) => v != null);
  const cur = widths[widths.length - 1];
  const sorted = [...widths.slice(-120)].sort((a, b) => a - b);
  const pct = sorted.findIndex((v) => v >= cur) / sorted.length;
  const hi20 = Math.max(...bars.slice(-21, -1).map((b) => b.high));
  const lo20 = Math.min(...bars.slice(-21, -1).map((b) => b.low));
  const last = bars[bars.length - 1].close;
  return { squeeze: pct < 0.12, widthPct: pct, breakout: last > hi20 ? "up" : last < lo20 ? "down" : null, hi20, lo20 };
}

// 8 · Trendstärke (ADX)
export function adx(bars, n = 14) {
  if (bars.length < n * 3) return null;
  let trS = 0;
  let pS = 0;
  let mS = 0;
  const dx = [];
  for (let i = 1; i < bars.length; i++) {
    const b = bars[i];
    const p = bars[i - 1];
    const up = b.high - p.high;
    const dn = p.low - b.low;
    const tr = Math.max(b.high - b.low, Math.abs(b.high - p.close), Math.abs(b.low - p.close));
    const pdm = up > dn && up > 0 ? up : 0;
    const mdm = dn > up && dn > 0 ? dn : 0;
    trS = trS - trS / n + tr;
    pS = pS - pS / n + pdm;
    mS = mS - mS / n + mdm;
    if (i >= n) {
      const pdi = (100 * pS) / trS;
      const mdi = (100 * mS) / trS;
      dx.push((100 * Math.abs(pdi - mdi)) / (pdi + mdi || 1));
    }
  }
  const v = mean(dx.slice(-n));
  return { value: v, label: v > 40 ? "sehr starker Trend" : v > 25 ? "klarer Trend" : v > 18 ? "schwacher Trend" : "kein Trend (Seitwärts)" };
}

// 9 · Unterstützungs-/Widerstandszonen aus Umkehrpunkten
export function zones(bars) {
  const piv = [];
  for (let i = 3; i < bars.length - 3; i++) {
    const w = bars.slice(i - 3, i + 4);
    if (bars[i].high === Math.max(...w.map((b) => b.high))) piv.push(bars[i].high);
    if (bars[i].low === Math.min(...w.map((b) => b.low))) piv.push(bars[i].low);
  }
  const last = bars[bars.length - 1].close;
  const tol = last * 0.006;
  const clusters = [];
  for (const p of piv.sort((a, b) => a - b)) {
    const c = clusters.find((x) => Math.abs(x.level - p) < tol);
    if (c) {
      c.level = (c.level * c.n + p) / (c.n + 1);
      c.n++;
    } else clusters.push({ level: p, n: 1 });
  }
  const strong = clusters.filter((c) => c.n >= 2);
  return {
    supports: strong.filter((c) => c.level < last).sort((a, b) => b.level - a.level).slice(0, 3),
    resistances: strong.filter((c) => c.level > last).sort((a, b) => a.level - b.level).slice(0, 3),
  };
}

// 10 · Relative Stärke zum Gesamtmarkt
export function relStrength(market, sym, days = 20) {
  const all = market.list.map((s) => market.perf(s.s, days));
  const own = market.perf(sym, days);
  return { own, market: mean(all), diff: own - mean(all), rank: all.filter((v) => v > own).length + 1, of: all.length };
}

// 11 · Sektor-Rotation
export function sectorRotation(market) {
  const sec = {};
  for (const s of market.list) (sec[s.sec] ||= []).push(s.s);
  return Object.entries(sec)
    .map(([name, syms]) => ({ name, d5: mean(syms.map((x) => market.perf(x, 5))), d20: mean(syms.map((x) => market.perf(x, 20))), n: syms.length }))
    .map((x) => ({ ...x, phase: x.d20 > 0 && x.d5 > 0 ? "Führend" : x.d20 < 0 && x.d5 > 0 ? "Erholung" : x.d20 > 0 && x.d5 < 0 ? "Schwächelnd" : "Nachzügler" }))
    .sort((a, b) => b.d5 - a.d5);
}

// 12 · AKYTEX Sentiment-Index (Angst & Gier)
export function sentimentIndex(market) {
  const qs = market.list.map((s) => market.quote(s.s));
  const breadth = qs.filter((q) => q.changePct > 0).length / qs.length;
  const mom = mean(market.list.map((s) => market.perf(s.s, 5)));
  const rsis = market.list.map((s) => ind.rsi(s.days.slice(-60).map((d) => d.close), 14).at(-1) || 50);
  const highs = qs.filter((q) => q.price >= q.high52 * 0.97).length / qs.length;
  const v = Math.round(Math.max(0, Math.min(100, breadth * 35 + (0.5 + mom * 8) * 25 + (mean(rsis) / 100) * 25 + highs * 60)));
  const label = v >= 75 ? "Extreme Gier" : v >= 58 ? "Gier" : v >= 42 ? "Neutral" : v >= 25 ? "Angst" : "Extreme Angst";
  return { value: v, label, parts: { breadth, mom, rsi: mean(rsis), highs } };
}

// 13 · Volatilitäts-Regime
export function volRegime(market, sym) {
  const d = market.get(sym).days.map((x) => x.close);
  const short = std(rets(d.slice(-21))) * Math.sqrt(252);
  const long = std(rets(d.slice(-250))) * Math.sqrt(252);
  const r = short / (long || 1);
  return { short, long, ratio: r, label: r > 1.35 ? "stürmisch" : r < 0.75 ? "ruhig" : "normal" };
}

// 14 · Anomalie-Radar
export function anomalies(market) {
  const out = [];
  for (const s of market.list) {
    const q = market.quote(s.s);
    const dv = std(rets(s.days.slice(-60).map((d) => d.close)));
    const z = q.changePct / (dv || 1);
    const volX = q.volume / (q.avgVolume || 1);
    if (Math.abs(z) > 2.2 || volX > 2.2) out.push({ sym: s.s, z, volX, chg: q.changePct });
  }
  return out.sort((a, b) => Math.abs(b.z) - Math.abs(a.z)).slice(0, 8);
}

// 15 · Prognose-Korridor (Perzentile je Tag)
export function forecast(market, sym, days = 20) {
  const st = market.get(sym);
  const closes = st.days.slice(-120).map((d) => d.close);
  const sigma = std(rets(closes));
  const a = analyze(st.days.slice(-260));
  const drift = a.score * sigma * 0.08; // leichte Neigung nach AI-Score
  const z = { p5: -1.645, p25: -0.674, p50: 0, p75: 0.674, p95: 1.645 };
  const out = [];
  for (let t = 0; t <= days; t++) {
    const row = { t };
    for (const [k, zz] of Object.entries(z)) row[k] = st.price * Math.exp(drift * t + zz * sigma * Math.sqrt(t));
    out.push(row);
  }
  return { sym, price: st.price, sigma, drift, days, path: out, history: closes.slice(-40) };
}

// 48 · Wahrscheinlichkeit, ein Ziel vor dem Stop zu erreichen (Brownsche Bewegung ohne Drift)
export function hitProbability(price, target, stop) {
  if (!(stop < price && target > price) && !(stop > price && target < price)) return null;
  const a = Math.abs(Math.log(stop / price));
  const b = Math.abs(Math.log(target / price));
  return a / (a + b);
}
export function probReach(market, sym, level, days = 20) {
  const f = forecast(market, sym, days);
  const s = f.sigma * Math.sqrt(days);
  const x = Math.log(level / f.price);
  // Wahrscheinlichkeit, das Niveau innerhalb der Frist zu berühren (Reflexionsprinzip)
  return Math.min(1, 2 * (1 - ncdf(Math.abs(x) / (s || 1))));
}

// 16 · Was-wäre-wenn
export function whatIf(market, sym, amount, days = 30) {
  const f = forecast(market, sym, days);
  const end = f.path[days];
  const qty = Math.floor(amount / f.price);
  const inv = qty * f.price;
  const m = (p) => qty * p - inv;
  return { qty, invested: inv, p5: m(end.p5), p50: m(end.p50), p95: m(end.p95), lossProb: ncdf(-(f.drift * days) / (f.sigma * Math.sqrt(days))), days };
}

// Portfolio-Renditen (für Risiko-Werkzeuge)
function holdingsReturns(broker, market, days = 120) {
  const pos = Object.entries(broker.state.positions);
  return pos.map(([sym, p]) => ({ sym, value: p.qty * market.get(sym).price, r: rets(market.get(sym).days.slice(-days - 1).map((d) => d.close)) }));
}

// 17 · Monte-Carlo-Depotsimulation
export function monteCarlo(broker, market, days = 252, paths = 600) {
  const h = holdingsReturns(broker, market);
  const cash = broker.state.cash;
  const start = cash + h.reduce((s, x) => s + x.value, 0);
  const finals = [];
  for (let p = 0; p < paths; p++) {
    let v = cash;
    const common = gauss(); // gemeinsamer Marktfaktor
    for (const x of h) {
      const mu = mean(x.r);
      const sd = std(x.r);
      const z = 0.55 * common + 0.835 * gauss();
      v += x.value * Math.exp(mu * days * 0.5 + sd * Math.sqrt(days) * z);
    }
    finals.push(v);
  }
  finals.sort((a, b) => a - b);
  const q = (k) => finals[Math.floor(k * (finals.length - 1))];
  return { start, p5: q(0.05), p25: q(0.25), p50: q(0.5), p75: q(0.75), p95: q(0.95), lossProb: finals.filter((v) => v < start).length / finals.length, finals, days };
}

// 18 · Value at Risk & Expected Shortfall (historische Simulation, 1 Tag)
export function valueAtRisk(broker, market) {
  const h = holdingsReturns(broker, market, 250);
  if (!h.length) return { var95: 0, var99: 0, es95: 0, value: 0 };
  const n = Math.min(...h.map((x) => x.r.length));
  const pnl = [];
  for (let i = 0; i < n; i++) pnl.push(h.reduce((s, x) => s + x.value * (Math.exp(x.r[x.r.length - n + i]) - 1), 0));
  pnl.sort((a, b) => a - b);
  const q = (k) => -pnl[Math.floor(k * (pnl.length - 1))];
  const tail = pnl.slice(0, Math.max(1, Math.floor(pnl.length * 0.05)));
  return { var95: q(0.05), var99: q(0.01), es95: -mean(tail), value: h.reduce((s, x) => s + x.value, 0) };
}

// 19 · Korrelations-Matrix
export function correlation(market, syms, days = 90) {
  const R = syms.map((s) => rets(market.get(s).days.slice(-days - 1).map((d) => d.close)));
  const corr = (a, b) => {
    const ma = mean(a);
    const mb = mean(b);
    let num = 0;
    let da = 0;
    let db = 0;
    for (let i = 0; i < a.length; i++) {
      num += (a[i] - ma) * (b[i] - mb);
      da += (a[i] - ma) ** 2;
      db += (b[i] - mb) ** 2;
    }
    return num / Math.sqrt(da * db || 1);
  };
  return { syms, m: R.map((a) => R.map((b) => corr(a, b))) };
}

// 20 · Strategie-Backtest auf Tagesbasis
export function backtest(market, sym, strategy = "sma", days = 500) {
  const bars = market.get(sym).days.slice(-days);
  const closes = bars.map((b) => b.close);
  const s20 = ind.sma(closes, 20);
  const s50 = ind.sma(closes, 50);
  const r = ind.rsi(closes, 14);
  const m = ind.macd(closes);
  let pos = false;
  let entry = 0;
  let eq = 1;
  const curve = [];
  const trades = [];
  for (let i = 1; i < closes.length; i++) {
    if (pos) eq *= closes[i] / closes[i - 1];
    let buy = false;
    let sell = false;
    if (strategy === "sma") {
      buy = s20[i] && s50[i] && s20[i] > s50[i] && s20[i - 1] <= s50[i - 1];
      sell = s20[i] && s50[i] && s20[i] < s50[i] && s20[i - 1] >= s50[i - 1];
    } else if (strategy === "rsi") {
      buy = r[i] != null && r[i] < 32;
      sell = r[i] != null && r[i] > 62;
    } else {
      buy = m.line[i] != null && m.signal[i] != null && m.line[i] > m.signal[i] && m.line[i - 1] <= m.signal[i - 1] && closes[i] > (s50[i] || 0);
      sell = m.line[i] != null && m.signal[i] != null && m.line[i] < m.signal[i] && m.line[i - 1] >= m.signal[i - 1];
    }
    if (!pos && buy) {
      pos = true;
      entry = closes[i];
      eq *= 1 - 0.0005;
    } else if (pos && sell) {
      pos = false;
      trades.push(closes[i] / entry - 1);
      eq *= 1 - 0.0005;
    }
    curve.push(eq);
  }
  const bh = closes.at(-1) / closes[0] - 1;
  let peak = 1;
  let dd = 0;
  for (const v of curve) {
    peak = Math.max(peak, v);
    dd = Math.min(dd, v / peak - 1);
  }
  return {
    sym,
    strategy,
    label: { sma: "SMA-Kreuzung 20/50", rsi: "RSI-Umkehr 32/62", macd: "MACD + Trendfilter" }[strategy],
    ret: eq - 1,
    buyHold: bh,
    trades: trades.length,
    winRate: trades.length ? trades.filter((t) => t > 0).length / trades.length : null,
    maxDD: dd,
    curve,
    bhCurve: closes.slice(1).map((c) => c / closes[0]),
  };
}

// 21 · Ähnliche Setups
function features(market, sym) {
  const d = market.get(sym).days.slice(-120);
  const c = d.map((x) => x.close);
  const r = ind.rsi(c, 14).at(-1) || 50;
  const mh = ind.macd(c).hist.at(-1) || 0;
  const s50 = ind.sma(c, 50).at(-1) || c.at(-1);
  return [r / 100, Math.tanh(mh / (c.at(-1) * 0.01)), Math.tanh((c.at(-1) / s50 - 1) * 10), Math.tanh(market.perf(sym, 20) * 5), std(rets(c.slice(-30))) * 30];
}
export function similar(market, sym, n = 3) {
  const f = features(market, sym);
  return market.list
    .filter((s) => s.s !== sym)
    .map((s) => {
      const g = features(market, s.s);
      return { sym: s.s, dist: Math.sqrt(f.reduce((a, v, i) => a + (v - g[i]) ** 2, 0)) };
    })
    .sort((a, b) => a.dist - b.dist)
    .slice(0, n)
    .map((x) => ({ ...x, similarity: Math.max(0, 1 - x.dist) }));
}

// 22 · Aktienvergleich
export function compare(market, a, b) {
  const row = (s) => {
    const q = market.quote(s);
    const an = analyze(market.get(s).days.slice(-260));
    return { sym: s, price: q.price, d1: q.changePct, d20: market.perf(s, 20), y: market.perf(s, 365), pe: q.pe, dy: q.dy, vol: volRegime(market, s).short, score: an.score, rating: an.rating.label, cap: q.marketCap };
  };
  return [row(a), row(b)];
}

// 23 · Themen-Watchlist-Generator
export const THEMES = {
  dividende: { label: "Dividenden-Stars", sort: (q) => q.dy },
  wachstum: { label: "Wachstum & Momentum", sort: (q, m, s) => m.perf(s, 60) },
  value: { label: "Value (günstig bewertet)", sort: (q) => (q.pe > 0 ? -q.pe : -999) },
  defensiv: { label: "Defensiv & ruhig", sort: (q, m, s) => -volRegime(m, s).short },
  tech: { label: "Tech & KI", filter: (q) => q.sector === "Technologie", sort: (q, m, s) => m.perf(s, 20) },
  deutschland: { label: "Deutschland (XETRA)", filter: (q) => q.exchange === "XETRA", sort: (q) => q.marketCap },
};
export function themeWatchlist(market, key, n = 6) {
  const t = THEMES[key];
  return market.list
    .map((s) => ({ s: s.s, q: market.quote(s.s) }))
    .filter((x) => !t.filter || t.filter(x.q))
    .sort((a, b) => t.sort(b.q, market, b.s) - t.sort(a.q, market, a.s))
    .slice(0, n)
    .map((x) => x.s);
}

// 24 · Positionsgröße nach Risiko
export function sizing(equity, entry, stop, riskPct = 1, maxWeight = 0.2) {
  const perShare = Math.abs(entry - stop);
  if (!perShare) return { qty: 0, risk: 0, value: 0 };
  // Risiko-basiert, aber höchstens maxWeight (Standard 20 %) des Depots in einer Aktie
  const qty = Math.min(Math.floor((equity * riskPct) / 100 / perShare), Math.floor((equity * maxWeight) / entry));
  return { qty, risk: qty * perShare, value: qty * entry, weight: (qty * entry) / equity };
}

// 25 · Rebalancing-Vorschlag
export function rebalance(broker, market, mode = "equal", cashBuffer = 0.1) {
  const pos = Object.entries(broker.state.positions);
  if (!pos.length) return { trades: [], targets: [] };
  const eq = broker.equity();
  const investable = eq * (1 - cashBuffer);
  let weights;
  if (mode === "risk") {
    const inv = pos.map(([s]) => 1 / (std(rets(market.get(s).days.slice(-61).map((d) => d.close))) || 1));
    const sum = inv.reduce((a, v) => a + v, 0);
    weights = inv.map((v) => v / sum);
  } else weights = pos.map(() => 1 / pos.length);
  const trades = [];
  const targets = pos.map(([sym, p], i) => {
    const price = market.get(sym).price;
    const target = investable * weights[i];
    const cur = p.qty * price;
    const diff = Math.round((target - cur) / price);
    if (Math.abs(diff * price) > eq * 0.01 && diff !== 0) trades.push({ sym, side: diff > 0 ? "buy" : "sell", qty: Math.abs(diff) });
    return { sym, cur: cur / eq, target: target / eq };
  });
  return { trades, targets, mode };
}

// 26 · Steuer-Tipps
export function taxHints(broker, market) {
  const realized = broker.state.realized || 0;
  const hints = [];
  const left = Math.max(0, 1000 - realized);
  if (left > 0) hints.push(`Noch ${f2(left)} € Sparerpauschbetrag frei – Gewinne bis dahin bleiben steuerfrei.`);
  else hints.push(`Sparerpauschbetrag ausgeschöpft; auf weitere ${f2(realized - 1000)} € Gewinn fallen ca. ${f2((realized - 1000) * 0.26375)} € Steuern an.`);
  const losers = Object.entries(broker.state.positions).map(([s, p]) => ({ s, pl: (market.get(s).price - p.avg) * p.qty })).filter((x) => x.pl < -50);
  if (losers.length && realized > 1000) hints.push(`Verlustverrechnung: ${losers.map((x) => x.s).join(", ")} liegen im Minus (${f2(losers.reduce((a, x) => a + x.pl, 0))} €). Ein Verkauf würde realisierte Gewinne steuerlich mindern.`);
  hints.push("Freistellungsauftrag beim Broker einrichten, damit der Pauschbetrag automatisch berücksichtigt wird.");
  return hints;
}

// 27 · Community-Stimmung je Aktie
export function communitySentiment(community, sym) {
  const ideas = community.allIdeas().filter((i) => i.symbol === sym);
  const long = ideas.filter((i) => i.dir === "long").length;
  return { n: ideas.length, long, short: ideas.length - long, bull: ideas.length ? long / ideas.length : null };
}

// 28 · Ideen-Entwurf
export function draftIdea(market, sym) {
  const a = analyze(barsFor(market, sym, "1D"));
  const st = market.get(sym);
  const long = a.score >= 0;
  const u = a.atr * 0.6;
  const pat = patterns(barsFor(market, sym, "1D"));
  const dv = divergence(barsFor(market, sym, "1D"));
  const tp = long ? st.price + 2 * u : st.price - 2 * u;
  const sl = long ? st.price - u : st.price + u;
  const reasons = [a.text[0], pat[0] ? `Muster: ${pat[0].name}` : null, dv ? dv.text : null].filter(Boolean);
  return { dir: long ? "long" : "short", tp, sl, title: `${sym}: ${long ? "Long-Chance" : "Short-Setup"} laut AKYTEX AI (${a.rating.label})`, body: `${reasons.join(" ")} Ziel ${f2(tp)}, Stop ${f2(sl)}.` };
}

// 44/49 · Depot-Drawdown
export function drawdown(broker) {
  const c = broker.state.equityCurve;
  if (!c.length) return { dd: 0, peak: broker.equity() };
  const peak = Math.max(...c.map((x) => x.value), broker.equity());
  return { dd: broker.equity() / peak - 1, peak };
}

// 50 · KI-Tagesplan
export function dailyPlan(ai, broker, market, universe) {
  const steps = [];
  const doc = ai.doctor();
  for (const h of doc.holdings) {
    if (h.v.score < -0.3) steps.push({ kind: "sell", sym: h.sym, qty: Math.max(1, Math.floor(broker.position(h.sym).qty / 2)), why: `${h.sym} schwach (${h.v.rating.label}) – Hälfte reduzieren` });
    const hasStop = broker.state.orders.some((o) => o.symbol === h.sym && o.type === "stop" && o.side === "sell");
    if (!hasStop) steps.push({ kind: "stop", sym: h.sym, price: h.v.price - h.v.h.atr * 1.5, qty: broker.position(h.sym).qty - broker.reservedQty(h.sym), why: `${h.sym} ohne Stop – Stop bei 1,5 × ATR setzen` });
  }
  const eq = broker.equity();
  for (const v of ai.scanAll(universe).filter((x) => !broker.position(x.sym) && x.score > 0.3).slice(0, 2)) {
    steps.push({ kind: "buy", sym: v.sym, qty: Math.max(1, Math.floor((eq * 0.04) / v.price)), why: `${v.sym}: ${v.rating.label} – 4 % des Depots` });
  }
  return steps.filter((s) => s.qty > 0).slice(0, 6);
}
