// AKYTEX AI – regelbasierte technische Analyse (Oszillatoren, gleitende Durchschnitte, Marken, Setup)
import * as ind from "./indicators.js";

const f2 = (v) => v.toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export const RATINGS = [
  { min: 0.5, label: "Stark kaufen", key: "strong-buy" },
  { min: 0.1, label: "Kaufen", key: "buy" },
  { min: -0.1, label: "Neutral", key: "neutral" },
  { min: -0.5, label: "Verkaufen", key: "sell" },
  { min: -Infinity, label: "Stark verkaufen", key: "strong-sell" },
];
export const rating = (score) => RATINGS.find((r) => score >= r.min);

function cci(bars, n = 20) {
  const i = bars.length - 1;
  if (i < n) return null;
  const tps = bars.slice(-n).map((b) => (b.high + b.low + b.close) / 3);
  const m = tps.reduce((a, v) => a + v, 0) / n;
  const md = tps.reduce((a, v) => a + Math.abs(v - m), 0) / n;
  return md ? (tps[n - 1] - m) / (0.015 * md) : 0;
}
function williams(bars, n = 14) {
  const s = bars.slice(-n);
  const hh = Math.max(...s.map((b) => b.high));
  const ll = Math.min(...s.map((b) => b.low));
  return hh === ll ? -50 : (-(hh - bars[bars.length - 1].close) / (hh - ll)) * 100;
}

export function analyze(bars) {
  const closes = bars.map((b) => b.close);
  const n = closes.length;
  const last = closes[n - 1];
  const at = (arr) => arr[n - 1];
  const sig = (name, value, action) => ({ name, value, action });

  // Oszillatoren
  const osc = [];
  const rsi = at(ind.rsi(closes, 14));
  osc.push(sig("RSI (14)", rsi, rsi == null ? 0 : rsi < 30 ? 1 : rsi > 70 ? -1 : 0));
  const st = ind.stochastic(bars, 14, 3);
  const k = at(st.k);
  const d = at(st.d);
  osc.push(sig("Stochastik %K (14, 3)", k, k == null ? 0 : k < 20 && k > d ? 1 : k > 80 && k < d ? -1 : 0));
  const m = ind.macd(closes);
  const macdL = at(m.line);
  const macdS = at(m.signal);
  osc.push(sig("MACD (12, 26)", macdL, macdL == null || macdS == null ? 0 : macdL > macdS ? 1 : -1));
  const mom = n > 10 ? last - closes[n - 11] : 0;
  osc.push(sig("Momentum (10)", mom, mom > 0 ? 1 : mom < 0 ? -1 : 0));
  const c = cci(bars);
  osc.push(sig("CCI (20)", c, c == null ? 0 : c < -100 ? 1 : c > 100 ? -1 : 0));
  const w = williams(bars);
  osc.push(sig("Williams %R (14)", w, w < -80 ? 1 : w > -20 ? -1 : 0));

  // Gleitende Durchschnitte
  const ma = [];
  const smas = {};
  for (const p of [10, 20, 50, 100, 200]) {
    const s = at(ind.sma(closes, p));
    const e = at(ind.ema(closes, p));
    smas[p] = s;
    if (s != null) ma.push(sig(`SMA ${p}`, s, last > s ? 1 : -1));
    if (e != null) ma.push(sig(`EMA ${p}`, e, last > e ? 1 : -1));
  }

  const score = (arr) => (arr.length ? arr.reduce((a, s) => a + s.action, 0) / arr.length : 0);
  const count = (arr) => ({ buy: arr.filter((s) => s.action > 0).length, sell: arr.filter((s) => s.action < 0).length, neutral: arr.filter((s) => s.action === 0).length });
  const oscScore = score(osc);
  const maScore = score(ma);
  const total = oscScore * 0.45 + maScore * 0.55;

  // Marken & Volatilität
  const look = bars.slice(-60);
  const support = Math.min(...look.map((b) => b.low));
  const resistance = Math.max(...look.map((b) => b.high));
  const atr = at(ind.atr(bars, 14)) || last * 0.01;
  const prev = bars[n - 2] || bars[n - 1];
  const pivot = (prev.high + prev.low + prev.close) / 3;
  const vols = bars.slice(-21, -1).map((b) => b.volume);
  const volRatio = vols.length ? bars[n - 1].volume / (vols.reduce((a, v) => a + v, 0) / vols.length) : 1;
  const sma50 = at(ind.sma(closes, 50));
  const sma200 = at(ind.sma(closes, 200));
  const s50 = ind.sma(closes, 50);
  const s200 = ind.sma(closes, 200);
  let cross = null;
  for (let i = n - 1; i > n - 15 && i > 0; i--) {
    if (s50[i] == null || s200[i] == null || s50[i - 1] == null || s200[i - 1] == null) break;
    if (s50[i] > s200[i] && s50[i - 1] <= s200[i - 1]) cross = "golden";
    if (s50[i] < s200[i] && s50[i - 1] >= s200[i - 1]) cross = "death";
    if (cross) break;
  }

  // Text
  const text = [];
  if (sma50 != null && sma200 != null) {
    if (last > sma50 && sma50 > sma200) text.push(`Der Kurs notiert über SMA 50 (${f2(sma50)}) und SMA 200 (${f2(sma200)}) – intakter Aufwärtstrend.`);
    else if (last < sma50 && sma50 < sma200) text.push(`Der Kurs liegt unter SMA 50 (${f2(sma50)}) und SMA 200 (${f2(sma200)}) – der Abwärtstrend dominiert.`);
    else text.push(`Gemischtes Trendbild: Kurs ${last > sma50 ? "über" : "unter"} SMA 50, SMA 50 ${sma50 > sma200 ? "über" : "unter"} SMA 200.`);
  } else if (sma50 != null) text.push(`Kurs ${last > sma50 ? "über" : "unter"} dem SMA 50 (${f2(sma50)}).`);
  if (cross === "golden") text.push("Frisches Golden Cross (SMA 50 kreuzt SMA 200 nach oben) – klassisches Kaufsignal.");
  if (cross === "death") text.push("Death Cross (SMA 50 kreuzt SMA 200 nach unten) – Vorsicht.");
  if (rsi != null) {
    if (rsi < 30) text.push(`RSI bei ${f2(rsi)}: überverkauft, technische Gegenbewegung möglich.`);
    else if (rsi > 70) text.push(`RSI bei ${f2(rsi)}: überkauft, Rücksetzer wahrscheinlicher.`);
    else text.push(`RSI neutral bei ${f2(rsi)}.`);
  }
  if (macdL != null && macdS != null) text.push(`MACD ${macdL > macdS ? "über" : "unter"} der Signallinie – Momentum ${macdL > macdS ? "positiv" : "negativ"}.`);
  const distR = (resistance - last) / last;
  const distS = (last - support) / last;
  if (distR < 0.015) text.push(`Kurs testet den Widerstand bei ${f2(resistance)} – ein Ausbruch würde neues Potenzial öffnen.`);
  else if (distS < 0.015) text.push(`Kurs nahe der Unterstützung bei ${f2(support)}.`);
  if (volRatio > 1.6) text.push(`Überdurchschnittliches Volumen (${f2(volRatio)}× Durchschnitt) bestätigt die Bewegung.`);
  text.push(`Volatilität (ATR 14): ${f2(atr)} bzw. ${f2((atr / last) * 100)} % des Kurses.`);

  const long = total >= 0;
  const setup = long
    ? { side: "buy", entry: last, sl: last - 1.5 * atr, tp: last + 3 * atr }
    : { side: "sell", entry: last, sl: last + 1.5 * atr, tp: last - 3 * atr };

  return {
    score: total,
    rating: rating(total),
    oscillators: { list: osc, score: oscScore, rating: rating(oscScore), counts: count(osc) },
    movingAverages: { list: ma, score: maScore, rating: rating(maScore), counts: count(ma) },
    levels: { support, resistance, pivot, r1: 2 * pivot - prev.low, s1: 2 * pivot - prev.high },
    atr,
    rsi,
    cross,
    volRatio,
    trendUp: sma50 != null && last > sma50,
    text,
    setup,
    last,
  };
}
