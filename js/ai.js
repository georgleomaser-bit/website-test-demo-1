// AKYTEX AI – Marktscan, Depot-Diagnose, Berater-Chat (lokal), Meldungen und Autopilot.
// Läuft komplett im Browser. Wo verfügbar, übernimmt ein Sprachmodell den Chat (siehe app.js).
import { analyze, rating } from "./analysis.js";
import { aggregate, tickStep } from "./market.js";
import * as lab from "./ailab.js";

const KEY = "akytex-v2-ai";
const f2 = (v) => v.toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const pc = (v) => (v > 0 ? "+" : "") + f2(v * 100) + " %";
const eur = (v) => v.toLocaleString("de-DE", { style: "currency", currency: "EUR" });
const deaccent = (s) => s.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
// Umgangssprachliche Namen und Marken
const ALIASES = { google: "GOOGL", alphabet: "GOOGL", youtube: "GOOGL", facebook: "META", instagram: "META", whatsapp: "META", mercedes: "MBG", daimler: "MBG", vw: "VOW3", volkswagen: "VOW3", telekom: "DTE", "munchener ruck": "MUV2", "munich re": "MUV2", lvmh: "MC", "louis vuitton": "MC", totalenergies: "TTE", nestle: "NESN", ozempic: "NOVO", "coca cola": "KO", cola: "KO", mcdonalds: "MCD", "mc donalds": "MCD", exxon: "XOM", jpmorgan: "JPM", "jp morgan": "JPM", "deutsche post": "DHL", "deutsche bank": "DBK", "johnson": "JNJ", microsoft: "MSFT", amazon: "AMZN", nvidia: "NVDA", "n video": "NVDA", envidia: "NVDA", "en vidia": "NVDA", "in video": "NVDA", "rhein metall": "RHM", rheinmetall: "RHM", "s a p": "SAP", "es a p": "SAP", palantier: "PLTR", "palan tier": "PLTR", tesler: "TSLA", "apple aktie": "AAPL", "äppel": "AAPL", "net flix": "NFLX" };
const STOP = new Set(["sie", "aktie", "aktien", "kaufen", "verkaufen", "welche", "sollte", "meinem", "meiner", "depot", "heute", "morgen", "markt", "lohnt", "risiko", "wieviel", "prognose", "backtest", "muster", "warum", "besser", "gerade", "einzahlen", "auszahlen", "danke", "hallo", "bitte", "zeitplan", "sparplan", "chancen", "steuer", "sektor", "sektoren", "stimmung", "tagesplan", "portfolio", "analyse", "trade", "trades", "order", "orders"]);
// Tippfehler-Abstand (Damerau-Levenshtein, optimal string alignment)
function osa(a, b) {
  const d = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array(b.length).fill(0)]);
  for (let j = 1; j <= b.length; j++) d[0][j] = j;
  for (let i = 1; i <= a.length; i++)
    for (let j = 1; j <= b.length; j++) {
      const c = a[i - 1] === b[j - 1] ? 0 : 1;
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + c);
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
    }
  return d[a.length][b.length];
}

export const STRATEGIES = {
  conservative: { label: "Defensiv", buyScore: 0.45, sellScore: -0.2, desc: "Nur starke Signale, ruhige Qualitätswerte (Volatilität unter 2,5 %/Tag).", filter: (v) => v.atrPct < 0.025 },
  balanced: { label: "AI-Mix", buyScore: 0.3, sellScore: -0.3, desc: "Ausgewogene Trendfolge mit solidem Chance-Risiko-Verhältnis." },
  aggressive: { label: "Offensiv", buyScore: 0.18, sellScore: -0.4, desc: "Mehr Trades, höhere Schwankungen, früher Einstieg." },
  momentum: { label: "Momentum", buyScore: 0.25, sellScore: -0.25, desc: "Kauft die stärksten Aktien der letzten 20 Tage im Aufwärtstrend.", rank: (v, m) => m.perf(v.sym, 20) },
  // Akys Profit-Modus: bestes erwartetes Chance-Risiko aus Signal-Score und 20-Tage-Momentum, nur im Aufwärtstrend
  profit: { label: "Profit-Modus", buyScore: 0.22, sellScore: -0.28, desc: "Akys Maximal-Modus: kauft die Aktien mit dem besten erwarteten Chance-Risiko (Trend, Momentum, Konfidenz), sichert Gewinne mit Trailing-Stops und schneidet Verluste früh ab.", filter: (v) => v.d.trendUp, rank: (v, m) => v.score * 0.6 + (m.perf(v.sym, 20) || 0) * 4 },
  meanrev: { label: "Rebound", buyScore: -0.2, sellScore: -0.5, desc: "Kauft überverkaufte Qualitätswerte (RSI < 35) im langfristigen Aufwärtstrend.", filter: (v) => v.h.rsi != null && v.h.rsi < 35 && v.d.trendUp },
};

const GLOSSARY = {
  rsi: ["RSI (Relative-Stärke-Index)", "misst auf einer Skala von 0 bis 100, wie stark die letzten Kursbewegungen waren. Über 70 gilt als überkauft, unter 30 als überverkauft."],
  macd: ["MACD", "vergleicht zwei gleitende Durchschnitte (12 und 26 Perioden). Kreuzt die MACD-Linie die Signallinie nach oben, dreht das Momentum positiv."],
  "stop-loss": ["Stop-Loss", "ist eine Verkaufsorder, die automatisch auslöst, wenn der Kurs unter eine Marke fällt. So begrenzt du Verluste."],
  stop: ["Stop-Loss", "ist eine Verkaufsorder, die automatisch auslöst, wenn der Kurs unter eine Marke fällt. So begrenzt du Verluste."],
  "take-profit": ["Take-Profit", "verkauft automatisch, sobald dein Kursziel erreicht ist – Gewinne werden gesichert."],
  limit: ["Limit-Order", "wird nur zu deinem Wunschpreis oder besser ausgeführt. Beim Kauf also höchstens zum Limit."],
  spread: ["Spread", "ist die Differenz zwischen Kauf- (Ask) und Verkaufskurs (Bid). Er ist im Kurs enthalten und wird im Order-Ticket ausgewiesen."],
  bollinger: ["Bollinger-Bänder", "legen zwei Standardabweichungen um einen 20er-Durchschnitt. Enge Bänder deuten auf eine bevorstehende starke Bewegung hin."],
  "golden cross": ["Golden Cross", "entsteht, wenn der 50-Tage-Durchschnitt den 200-Tage-Durchschnitt nach oben kreuzt – ein klassisches Trendsignal."],
  crv: ["CRV (Chance-Risiko-Verhältnis)", "teilt den möglichen Gewinn bis zum Ziel durch den möglichen Verlust bis zum Stop. Ab 2:1 gilt ein Setup als attraktiv."],
  atr: ["ATR (Average True Range)", "misst die durchschnittliche Schwankungsbreite. Die AI nutzt sie, um Stops passend zur Volatilität zu setzen."],
  diversifikation: ["Diversifikation", "heißt, das Geld auf verschiedene Aktien und Branchen zu verteilen, damit ein einzelner Absturz das Depot nicht ruiniert."],
  vwap: ["VWAP", "ist der volumengewichtete Durchschnittspreis des Tages – viele Profis nutzen ihn als fairen Preis."],
};

export class AkytexAI {
  constructor(market, broker) {
    this.market = market;
    this.broker = broker;
    this.cache = new Map();
    this.state = this.load();
    this.listeners = new Map();
  }

  on(evt, fn) {
    if (!this.listeners.has(evt)) this.listeners.set(evt, new Set());
    this.listeners.get(evt).add(fn);
  }
  emit(evt, data) {
    for (const fn of this.listeners.get(evt) || []) fn(data);
  }

  load() {
    const base = {
      config: { enabled: false, mode: "assist", strategy: "balanced", budgetPct: 30, maxPosPct: 8, stopPct: 5, takePct: 12, maxTrades: 12, universe: "all", manageAll: false, hoursOn: false, from: "09:00", to: "17:30", days: [1, 2, 3, 4, 5], maxDailyLoss: 3, minConf: 50, atrStops: true, shadow: false },
      shadow: { pos: {}, log: [], pnl: 0 },
      journal: [],
      dayStart: { day: "", value: 0 },
      sells: { n: 0, wins: 0 },
      log: [],
      proposals: [],
      feed: [],
      managed: {}, // sym -> { peak }
      tradesDay: { day: "", n: 0 },
      aiPnl: 0,
      unread: 0,
      lastRatings: {},
    };
    try {
      const s = JSON.parse(localStorage.getItem(KEY) || "{}");
      return { ...base, ...s, config: { ...base.config, ...(s.config || {}) }, shadow: { ...base.shadow, ...(s.shadow || {}) }, sells: { ...base.sells, ...(s.sells || {}) } };
    } catch (_) {
      return base;
    }
  }
  save() {
    try {
      localStorage.setItem(KEY, JSON.stringify(this.state));
    } catch (_) {
      /* ignorieren */
    }
  }

  // ---------- Analyse ----------
  // Kombiniert Stunden- und Tagesbild; Ergebnis wird 10 s zwischengespeichert
  scan(sym) {
    const c = this.cache.get(sym);
    if (c && Date.now() - c.ts < 10000) return c.v;
    const st = this.market.get(sym);
    const hourly = aggregate(st.m1.slice(-60 * 24 * 7), "1h");
    const h = analyze(hourly);
    const d = analyze(st.days.slice(-260));
    const q = this.market.quote(sym);
    const score = h.score * 0.55 + d.score * 0.45;
    const v = { sym, name: st.n, sector: st.sec, price: st.price, score, rating: rating(score), h, d, dayChg: q.changePct, atrPct: d.atr / st.price };
    v.reason = this.reason(v);
    this.cache.set(sym, { ts: Date.now(), v });
    return v;
  }

  reason(v) {
    const parts = [];
    const { h, d } = v;
    if (d.trendUp && h.trendUp) parts.push("Aufwärtstrend im Tages- und Stundenchart");
    else if (!d.trendUp && !h.trendUp) parts.push("Abwärtstrend auf beiden Zeitebenen");
    else parts.push(d.trendUp ? "langfristig aufwärts, kurzfristig schwächer" : "kurzfristige Erholung im Abwärtstrend");
    if (h.rsi != null) parts.push(`RSI ${f2(h.rsi)}${h.rsi < 30 ? " (überverkauft)" : h.rsi > 70 ? " (überkauft)" : ""}`);
    parts.push(`MACD ${h.oscillators.list.find((s) => s.name.startsWith("MACD")).action > 0 ? "positiv" : "negativ"}`);
    if (d.cross === "golden") parts.push("frisches Golden Cross");
    if (h.volRatio > 1.6) parts.push("erhöhtes Volumen");
    return parts.join(", ");
  }

  scanAll(universe) {
    return universe.map((s) => this.scan(s)).sort((a, b) => b.score - a.score);
  }

  // ---------- Depot-Diagnose ----------
  doctor() {
    const b = this.broker;
    const eq = b.equity();
    const pos = Object.entries(b.state.positions);
    const cashPct = b.state.cash / eq;
    const sectors = {};
    let volW = 0;
    let quality = 0;
    const holdings = pos.map(([sym, p]) => {
      const v = this.scan(sym);
      const val = p.qty * v.price;
      sectors[v.sector] = (sectors[v.sector] || 0) + val;
      volW += (val / eq) * v.atrPct;
      quality += (val / eq) * v.score;
      return { sym, val, weight: val / eq, pnl: (v.price - p.avg) / p.avg, v };
    });
    const invested = eq - b.state.cash;
    const hhi = invested > 0 ? Object.values(sectors).reduce((a, x) => a + (x / invested) ** 2, 0) : 1;
    const maxW = holdings.reduce((a, h) => Math.max(a, h.weight), 0);
    const div = pos.length === 0 ? 20 : Math.round(Math.max(0, Math.min(100, (1 - hhi) * 110 + Math.min(pos.length, 10) * 3 - Math.max(0, maxW - 0.2) * 150)));
    const risk = Math.round(Math.max(0, Math.min(100, 100 - volW * 2500)));
    const qual = pos.length ? Math.round(Math.max(0, Math.min(100, 50 + (quality / Math.max(0.01, 1 - cashPct)) * 90))) : 50;
    const liq = Math.round(cashPct < 0.05 ? 40 : cashPct > 0.7 ? 45 : cashPct > 0.4 ? 70 : 95);
    const score = Math.round(div * 0.3 + risk * 0.25 + qual * 0.3 + liq * 0.15);
    const tips = [];
    if (!pos.length) tips.push({ icon: "🚀", text: "Dein Depot ist noch leer. Starte mit 3–5 Aktien aus verschiedenen Branchen – frag mich nach Chancen." });
    if (cashPct > 0.6 && pos.length) tips.push({ icon: "💶", text: `${f2(cashPct * 100)} % liegen als Guthaben. Investiertes Geld arbeitet – der Autopilot kann einen Teil schrittweise anlegen.` });
    if (maxW > 0.25) {
      const h = holdings.find((x) => x.weight === maxW);
      tips.push({ icon: "⚖️", text: `${h.sym} macht ${f2(maxW * 100)} % deines Depots aus. Über 20 % in einer Aktie erhöht das Klumpenrisiko.` });
    }
    const top = Object.entries(sectors).sort((a, b) => b[1] - a[1])[0];
    if (top && invested > 0 && top[1] / invested > 0.5) tips.push({ icon: "🧩", text: `${f2((top[1] / invested) * 100)} % deiner Aktien stecken in „${top[0]}“. Beimischen anderer Branchen senkt das Risiko.` });
    for (const h of holdings) {
      if (h.v.score < -0.3) tips.push({ icon: "⚠️", text: `${h.sym}: AKYTEX AI bewertet „${h.v.rating.label}“ (${h.v.reason}). Prüfe einen Stop-Loss oder Teilverkauf.`, sym: h.sym, action: "sell" });
      else if (h.pnl > 0.12) tips.push({ icon: "🎯", text: `${h.sym} liegt ${pc(h.pnl)} im Plus. Einen Teil sichern oder den Stop nachziehen?`, sym: h.sym, action: "trail" });
    }
    const noStop = holdings.filter((h) => !b.state.orders.some((o) => o.symbol === h.sym && o.type === "stop" && o.side === "sell"));
    if (noStop.length) tips.push({ icon: "🛡️", text: `${noStop.length} Position${noStop.length > 1 ? "en" : ""} ohne Stop-Loss (${noStop.map((h) => h.sym).join(", ")}).` });
    if (!tips.length) tips.push({ icon: "✅", text: "Dein Depot ist gut aufgestellt. Weiter so!" });
    return { score, parts: { div, risk, qual, liq }, holdings, sectors, cashPct, tips };
  }

  // ---------- Meldungen ----------
  push(item) {
    const it = { id: Math.random().toString(36).slice(2, 9), ts: Date.now(), ...item };
    this.state.feed.unshift(it);
    this.state.feed.length = Math.min(this.state.feed.length, 60);
    this.state.unread++;
    this.save();
    this.emit("feed", it);
    return it;
  }

  briefing(universe) {
    const all = this.scanAll(universe);
    const up = all.filter((v) => v.dayChg > 0).length;
    const best = [...all].sort((a, b) => b.dayChg - a.dayChg)[0];
    const worst = [...all].sort((a, b) => a.dayChg - b.dayChg)[0];
    const doc = this.doctor();
    return this.push({
      kind: "briefing",
      icon: "☀️",
      title: "Dein Markt-Briefing",
      text: `${up} von ${all.length} Aktien im Plus. Stärkster Wert ${best.sym} (${pc(best.dayChg)}), schwächster ${worst.sym} (${pc(worst.dayChg)}). Top-Chance laut AI: ${all[0].sym} (${all[0].rating.label}). Depot-Score: ${doc.score}/100.`,
      sym: all[0].sym,
    });
  }

  // Beobachtet Watchlist + Depot und meldet Wichtiges
  watch(symbols) {
    const out = [];
    for (const sym of symbols) {
      const v = this.scan(sym);
      const prev = this.state.lastRatings[sym];
      if (prev && prev !== v.rating.key) {
        const pos = this.broker.position(sym);
        out.push(
          this.push({
            kind: "signal",
            icon: v.score > 0 ? "📈" : "📉",
            title: `${sym}: Rating wechselt auf „${v.rating.label}“`,
            text: `${v.reason}.${pos ? ` Du hältst ${pos.qty} Stück (${pc((v.price - pos.avg) / pos.avg)}).` : ""}`,
            sym,
            action: v.score > 0.2 && !pos ? "buy" : v.score < -0.2 && pos ? "sell" : null,
          })
        );
      }
      this.state.lastRatings[sym] = v.rating.key;
      if (Math.abs(v.dayChg) > 0.04 && !this.state[`mv_${sym}_${new Date().toDateString()}`]) {
        this.state[`mv_${sym}_${new Date().toDateString()}`] = 1;
        out.push(this.push({ kind: "move", icon: "⚡", title: `${sym} ${v.dayChg > 0 ? "springt" : "fällt"} ${pc(v.dayChg)}`, text: `Ungewöhnlich starke Tagesbewegung. ${v.reason}.`, sym }));
      }
    }
    // Stop-Nähe bei Positionen
    for (const o of this.broker.state.orders) {
      if (o.type !== "stop" || o.side !== "sell") continue;
      const p = this.market.get(o.symbol).price;
      const k = `near_${o.id}`;
      if (!this.state[k] && (p - o.stopPrice) / p < 0.01) {
        this.state[k] = 1;
        out.push(this.push({ kind: "risk", icon: "🛡️", title: `${o.symbol} nähert sich deinem Stop`, text: `Kurs ${f2(p)} €, Stop bei ${f2(o.stopPrice)} € (unter 1 % Abstand).`, sym: o.symbol }));
      }
    }
    this.save();
    return out;
  }

  // ---------- Autopilot ----------
  resetDay() {
    const d = new Date().toDateString();
    if (this.state.tradesDay.day !== d) this.state.tradesDay = { day: d, n: 0 };
  }

  // Ein Entscheidungsschritt. execute=true handelt selbst, sonst entstehen Vorschläge.
  inHours() {
    const c = this.state.config;
    if (!c.hoursOn) return true;
    const d = new Date();
    const cur = d.getHours() * 60 + d.getMinutes();
    const [fh, fm] = c.from.split(":").map(Number);
    const [th, tm] = c.to.split(":").map(Number);
    return c.days.includes(d.getDay()) && cur >= fh * 60 + fm && cur <= th * 60 + tm;
  }

  // Notbremse: pausiert den Autopiloten bei zu hohem Tagesverlust
  circuitBreaker() {
    const c = this.state.config;
    const d = new Date().toDateString();
    const eq = this.broker.equity();
    if (this.state.dayStart.day !== d) this.state.dayStart = { day: d, value: eq };
    const chg = eq / this.state.dayStart.value - 1;
    if (c.maxDailyLoss && chg <= -c.maxDailyLoss / 100) {
      c.enabled = false;
      this.push({ kind: "risk", icon: "🛑", title: "Notbremse ausgelöst", text: `Das Depot liegt heute ${(chg * 100).toFixed(2).replace(".", ",")} % im Minus (Grenze −${c.maxDailyLoss} %). Der Autopilot pausiert bis du ihn wieder startest.` });
      this.save();
      return true;
    }
    return false;
  }

  step(universe, execute) {
    const c = this.state.config;
    if (!c.enabled) return [];
    if (!this.inHours()) return [];
    if (this.circuitBreaker()) return [];
    this.resetDay();
    const b = this.broker;
    const S = STRATEGIES[c.strategy] || STRATEGIES.balanced;
    const eq = b.equity();
    const actions = [];
    const shadow = c.shadow;

    // 1) Verkäufe prüfen
    const managed = c.manageAll ? Object.keys(b.state.positions) : Object.keys(this.state.managed).filter((s) => b.position(s));
    for (const sym of managed) {
      const p = b.position(sym);
      const v = this.scan(sym);
      const m = (this.state.managed[sym] ||= { peak: v.price });
      m.peak = Math.max(m.peak, v.price);
      const pnl = (v.price - p.avg) / p.avg;
      // Stop/Ziel-Orders der AI selbst zählen nicht als gebunden – die AI verwaltet sie
      const aiOrder = b.state.orders.find((o) => o.symbol === sym && o.side === "sell" && o.aiManaged);
      const free = p.qty - b.reservedQty(sym) + (aiOrder ? aiOrder.qty : 0);
      if (free <= 0) continue;
      let why = null;
      let qty = free;
      if (pnl <= -c.stopPct / 100) why = `Stop-Loss: ${pc(pnl)} erreicht die Verlustgrenze von −${c.stopPct} %`;
      else if (pnl >= c.takePct / 100) {
        why = `Gewinnziel +${c.takePct} % erreicht (${pc(pnl)}) – die Hälfte wird gesichert`;
        qty = Math.max(1, Math.floor(free / 2));
      } else if (pnl > 0.02 && v.price < m.peak * (1 - (c.stopPct / 100) * 0.6)) why = `Trailing-Stop: ${pc(v.price / m.peak - 1)} unter dem Hoch seit Kauf, Gewinn ${pc(pnl)} wird gesichert`;
      else if (v.score <= S.sellScore) why = `Signal dreht: ${v.rating.label} (${v.reason})`;
      if (why) actions.push({ side: "sell", sym, qty, price: v.price, why, score: v.score });
    }

    // 2) Käufe suchen
    const aiInvested = Object.keys(this.state.managed).reduce((a, s) => a + (b.position(s)?.qty || 0) * this.market.get(s).price, 0);
    let budget = Math.min(b.buyingPower(), (eq * c.budgetPct) / 100 - aiInvested);
    const sectorVal = {};
    for (const [s, p] of Object.entries(b.state.positions)) sectorVal[this.market.get(s).sec] = (sectorVal[this.market.get(s).sec] || 0) + p.qty * this.market.get(s).price;
    let cands = this.scanAll(universe).filter((v) => v.score >= S.buyScore && !b.position(v.sym) && !(shadow && this.state.shadow.pos[v.sym]) && !actions.some((a) => a.sym === v.sym) && (!S.filter || S.filter(v)));
    if (S.rank) cands = cands.sort((x, y) => S.rank(y, this.market) - S.rank(x, this.market));
    for (const v of cands) {
      const conf = lab.confidence(this.market, v.sym);
      if (conf < c.minConf) continue;
      v.conf = conf;
      if (this.state.tradesDay.n + actions.length >= c.maxTrades) break;
      const size = Math.min(budget, (eq * c.maxPosPct) / 100);
      const q = this.market.quote(v.sym);
      const qty = Math.floor(size / q.ask);
      if (qty < 1 || size < 250) break;
      if (((sectorVal[v.sector] || 0) + qty * q.ask) / eq > 0.35) continue; // Branchenlimit 35 %
      const atr = v.d.atr;
      const sl = c.atrStops ? q.ask - 1.5 * atr : q.ask * (1 - c.stopPct / 100);
      const tp = c.atrStops ? q.ask + 3 * atr : q.ask * (1 + c.takePct / 100);
      actions.push({ side: "buy", sym: v.sym, qty, price: q.ask, why: `${S.label}: ${v.rating.label} (Score ${f2(v.score)}, Konfidenz ${conf} %): ${v.reason}`, score: v.score, conf, sl, tp });
      budget -= qty * q.ask;
      sectorVal[v.sector] = (sectorVal[v.sector] || 0) + qty * q.ask;
      if (actions.filter((a) => a.side === "buy").length >= 2) break; // max. 2 Käufe pro Schritt
    }

    const done = [];
    if (shadow) {
      // Schattenmodus: Entscheidungen nur protokollieren und virtuell bewerten
      for (const a of actions) {
        const sp = this.state.shadow;
        if (a.side === "buy") sp.pos[a.sym] = { qty: a.qty, entry: a.price };
        sp.log.unshift({ ts: Date.now(), side: a.side, sym: a.sym, qty: a.qty, price: a.price, why: a.why });
        sp.log.length = Math.min(sp.log.length, 60);
        done.push(a);
      }
      // virtuelle Verkäufe
      for (const [sym, p] of Object.entries(this.state.shadow.pos)) {
        const v = this.scan(sym);
        const pnl = v.price / p.entry - 1;
        if (pnl <= -c.stopPct / 100 || pnl >= c.takePct / 100 || v.score <= S.sellScore) {
          this.state.shadow.pnl += (v.price - p.entry) * p.qty;
          this.state.shadow.log.unshift({ ts: Date.now(), side: "sell", sym, qty: p.qty, price: v.price, why: `Schatten-Verkauf (${(pnl * 100).toFixed(1).replace(".", ",")} %)` });
          delete this.state.shadow.pos[sym];
        }
      }
      this.save();
      return done;
    }
    for (const a of actions) {
      if (execute) {
        const r = this.execute(a, "Autopilot");
        if (r.ok) done.push(a);
      } else if (!this.state.proposals.some((p) => p.sym === a.sym && p.side === a.side)) {
        const prop = { id: Math.random().toString(36).slice(2, 9), ts: Date.now(), ...a };
        this.state.proposals.unshift(prop);
        this.state.proposals.length = Math.min(this.state.proposals.length, 8);
        this.push({ kind: "proposal", icon: a.side === "buy" ? "🟢" : "🔴", title: `Vorschlag: ${a.qty} ${a.sym} ${a.side === "buy" ? "kaufen" : "verkaufen"}`, text: a.why, sym: a.sym, proposal: prop.id });
        done.push(prop);
      }
    }
    this.save();
    return done;
  }

  execute(a, by) {
    const b = this.broker;
    const step = tickStep(a.price);
    const order = { symbol: a.sym, side: a.side, type: "market", qty: a.qty };
    if (a.side === "sell") {
      // gebundene Stop/TP-Orders der AI freigeben
      for (const o of [...b.state.orders]) if (o.symbol === a.sym && o.side === "sell" && o.aiManaged) b.cancelOrder(o.id, "storniert (AI)");
    }
    if (a.side === "buy" && a.sl && a.tp) {
      order.sl = Math.round(a.sl / step) * step;
      order.tp = Math.round(a.tp / step) * step;
    }
    const before = b.position(a.sym);
    const avg = before?.avg;
    this.executing = true; // Ausführungs-Meldung kommt vom Autopiloten selbst
    const r = b.placeOrder(order);
    this.executing = false;
    if (!r.ok) return r;
    this.resetDay();
    this.state.tradesDay.n++;
    if (a.side === "buy") {
      this.state.managed[a.sym] = { peak: a.price };
      for (const o of b.state.orders) if (o.symbol === a.sym && o.parent === r.order.id) o.aiManaged = true;
      b.save();
    } else {
      if (avg) {
        const pl = (a.price - avg) * a.qty;
        this.state.aiPnl += pl;
        this.state.sells.n++;
        if (pl > 0) this.state.sells.wins++;
      }
      if (!b.position(a.sym)) delete this.state.managed[a.sym];
    }
    const sc = this.scan(a.sym);
    this.state.journal.unshift({ ts: Date.now(), by, side: a.side, sym: a.sym, qty: a.qty, price: a.price, why: a.why, rating: sc.rating.label, score: +sc.score.toFixed(2), rsi: sc.h.rsi != null ? +sc.h.rsi.toFixed(1) : null, conf: a.conf ?? null, equity: Math.round(b.equity()), strategy: this.state.config.strategy });
    this.state.journal.length = Math.min(this.state.journal.length, 150);
    const entry = { ts: Date.now(), by, side: a.side, sym: a.sym, qty: a.qty, price: a.price, why: a.why };
    this.state.log.unshift(entry);
    this.state.log.length = Math.min(this.state.log.length, 80);
    this.save();
    this.emit("trade", entry);
    return r;
  }

  acceptProposal(id) {
    const p = this.state.proposals.find((x) => x.id === id);
    if (!p) return { ok: false, msg: "Vorschlag nicht mehr gültig." };
    this.state.proposals = this.state.proposals.filter((x) => x.id !== id);
    const q = this.market.quote(p.sym);
    const fresh = { ...p, price: p.side === "buy" ? q.ask : q.bid };
    if (p.side === "buy") {
      fresh.sl = fresh.price * (1 - this.state.config.stopPct / 100);
      fresh.tp = fresh.price * (1 + this.state.config.takePct / 100);
    }
    const r = this.execute(fresh, "Du (AI-Vorschlag)");
    this.save();
    return r;
  }
  dismissProposal(id) {
    this.state.proposals = this.state.proposals.filter((x) => x.id !== id);
    this.save();
  }

  // Not-Aus: Autopilot stoppen, offene Vorschläge verwerfen. Positionen und ihre Stops bleiben bestehen.
  killSwitch() {
    this.state.config.enabled = false;
    this.state.proposals = [];
    this.save();
  }

  // ---------- Lokaler Berater-Chat ----------
  // Erweiterte Absichten (Labor-Werkzeuge, Zeitplan, Kontext-Gedächtnis), sonst Basisantwort
  // Antwort plus passende Folgefragen
  answer(text, ctx) {
    this.turnSym = null;
    const res = this.route(text, ctx);
    if (!res.follow) res.follow = this.followUps(text, this.turnSym);
    return res;
  }

  followUps(text, sym) {
    const t = text.toLowerCase();
    const pick = (arr) => arr.filter((q) => q.toLowerCase() !== t).slice(0, 3);
    if (sym) {
      const held = !!this.broker.position(sym);
      const qs = [`Warum bewertest du ${sym} so?`, `Prognose für ${sym}`, held ? `Soll ich ${sym} verkaufen?` : `Wie viel ${sym} soll ich kaufen?`, `Backtest ${sym}`, `Muster bei ${sym}`];
      // Was gerade gefragt wurde, nicht noch einmal anbieten
      return pick(qs.filter((q) => !t.includes(q.toLowerCase().split(" ")[0])));
    }
    if (/depot|portfolio|wie steh/.test(t)) return pick(["Wie riskant ist mein Depot?", "Rebalancing vorschlagen", "Tagesplan"]);
    if (/risiko|var\b|monte/.test(t)) return pick(["Wie kann ich mich absichern?", "Rebalancing vorschlagen", "Wie steht mein Depot?"]);
    if (/kauf|chance|empfehl|beste|top/.test(t)) return pick(["Wie ist die Marktlage heute?", "Sektor-Rotation", "Tagesplan"]);
    if (/markt|lage|stimmung|sektor/.test(t)) return pick(["Was soll ich jetzt kaufen?", "Gibt es Anomalien?", "Wie steht mein Depot?"]);
    return pick(["Wie steht mein Depot?", "Was soll ich jetzt kaufen?", "Wie ist die Marktlage heute?"]);
  }

  route(text, ctx) {
    const t = text.toLowerCase().trim();
    let syms = this.findSymbols(text);
    // Kontext-Gedächtnis: „davon“, „die Aktie“, „es“ beziehen sich auf die zuletzt besprochene Aktie
    if (!syms.length && this.lastSym && /(davon|die aktie|der aktie|dem wert|diese|dieser|es |sie |ihr |die.*kaufen|warum|prognose|backtest|wahrscheinlich)/.test(t + " ")) syms = [this.lastSym];
    if (syms.length) this.lastSym = syms[0];
    const sym = syms[0];
    this.turnSym = sym || null;
    const M = this.market;
    const B = this.broker;
    const eurS = (v) => (v > 0 ? "+" : "") + eur(v);
    const cmd = t.startsWith("/") ? t.split(/\s+/)[0].slice(1) : null;
    const has = (re) => re.test(t) || (cmd && re.test(cmd));

    if (cmd === "hilfe" || cmd === "help") return { html: `<p>Befehle: <code>/scan</code> <code>/plan</code> <code>/prognose SAP</code> <code>/backtest SAP</code> <code>/mtf SAP</code> <code>/warum SAP</code> <code>/muster</code> <code>/risiko</code> <code>/rebalance</code> <code>/sentiment</code> <code>/sektoren</code> <code>/anomalien</code> <code>/steuer</code> <code>/rückblick</code>. Zeitpläne: „Kaufe 10 SAP um 15:30“, „Sparplan 200 € ASML monatlich“, „Verkaufe TSLA wenn über 260“.</p>` };

    // Zeitplan / Timer / Regeln
    if (ctx.scheduler && /(um \d{1,2}[:.]\d{2}|in \d+\s*(min|std|stund)|jeden|jede |sparplan|täglich|werktags|wöchentlich|monatlich|stündlich|wenn |falls |sobald )/.test(t) && /(kauf|verkauf|sparplan|buy|sell)/.test(t) && syms.length) {
      const task = ctx.scheduler.parse(text, (x) => this.findSymbols(x).length ? this.findSymbols(x) : syms);
      if (task) return { html: `<p>Ich habe folgenden Auftrag verstanden:</p><p class="sched-pill">⏱ ${ctx.scheduler.describe({ ...task, at: task.at || Date.now() })}</p><p class="muted">Lege ihn an – du siehst ihn danach im Tab „Zeitplan“ mit Countdown.</p>`, actions: [{ label: "Zeitplan anlegen", schedule: task, primary: true }] };
    }
    // Limit-Order: „kaufe 10 SAP limit 230“ / „zu 230“
    const lim = t.match(/(kauf\w*|verkauf\w*)\s+(\d+)\s+.*?(?:limit|zu|bei)\s+(\d+(?:[.,]\d+)?)/);
    if (lim && sym) {
      const side = /verkauf/.test(lim[1]) ? "sell" : "buy";
      const limit = parseFloat(lim[3].replace(",", "."));
      return { html: `<p><b>${lim[2]} ${sym}</b> ${side === "buy" ? "kaufen" : "verkaufen"} mit <b>Limit ${eur(limit)}</b> (aktuell ${eur(M.get(sym).price)}). Die Order bleibt offen, bis der Kurs das Limit erreicht.</p>`, actions: [{ label: `Limit-Order ${lim[2]} ${sym} @ ${f2(limit)}`, side, sym, qty: +lim[2], limit, primary: true }] };
    }
    // Alarm per Chat
    const al = t.match(/(alarm|benachrichtig|sag bescheid|melde).*?(über|ueber|unter)\s*(\d+(?:[.,]\d+)?)/);
    if (al && sym) {
      const price = parseFloat(al[3].replace(",", "."));
      return { html: `<p>Ich richte einen Preisalarm ein: <b>${sym}</b> ${/unter/.test(al[2]) ? "fällt unter" : "steigt über"} <b>${eur(price)}</b>.</p>`, actions: [{ label: "Alarm erstellen", alert: { sym, price }, primary: true }] };
    }
    // Tagesplan
    if (cmd === "plan" || /tagesplan|was soll ich heute|was tun|plan für heute/.test(t)) {
      const steps = lab.dailyPlan(this, B, M, ctx.universe);
      return {
        html: steps.length ? `<p>Dein <b>KI-Tagesplan</b>:</p><ol>${steps.map((s) => `<li>${s.why}</li>`).join("")}</ol>` : "<p>Heute ist nichts zu tun – dein Depot ist gut aufgestellt. 👌</p>",
        actions: steps.length ? [{ label: `Plan ausführen (${steps.length} Schritte)`, plan: steps, primary: true }] : [],
      };
    }
    // Prognose
    if ((cmd === "prognose" || /prognose|vorhersage|wohin geht|wo steht .* in|kursziel/.test(t)) && sym) {
      const f = lab.forecast(M, sym, 20);
      const e = f.path[20];
      const up10 = lab.probReach(M, sym, f.price * 1.1, 20);
      return { html: `<p><b>Prognose-Korridor ${sym}</b> für 20 Handelstage (aus Volatilität und AI-Trend):</p><ul><li>Mittleres Szenario: <b>${eur(e.p50)}</b></li><li>50 %-Spanne: ${eur(e.p25)} – ${eur(e.p75)}</li><li>90 %-Spanne: ${eur(e.p5)} – ${eur(e.p95)}</li><li>Chance, +10 % zu berühren: <b>${Math.round(up10 * 100)} %</b></li></ul><p class="muted">Statistische Schätzung, keine Garantie.</p>`, actions: [{ label: "Im Labor als Grafik", lab: "forecast", sym }] };
    }
    // Wahrscheinlichkeit für ein Kursniveau
    const pr = t.match(/wahrscheinlich\w*.*?(\d+(?:[.,]\d+)?)/);
    if (pr && sym) {
      const lvl = parseFloat(pr[1].replace(",", "."));
      const p = lab.probReach(M, sym, lvl, 20);
      return { html: `<p>Die Wahrscheinlichkeit, dass <b>${sym}</b> (aktuell ${eur(M.get(sym).price)}) innerhalb von 20 Handelstagen <b>${eur(lvl)}</b> berührt, liegt bei etwa <b>${Math.round(p * 100)} %</b>.</p>` };
    }
    // Backtest
    if ((cmd === "backtest" || /backtest|hätte funktioniert|strategie test/.test(t)) && sym) {
      const res = ["sma", "rsi", "macd"].map((k) => lab.backtest(M, sym, k));
      const best = [...res].sort((a, b) => b.ret - a.ret)[0];
      return { html: `<p><b>Backtest ${sym}</b> (ca. 2 Jahre, inkl. Gebühren):</p><ul>${res.map((r) => `<li>${r.label}: <b class="${r.ret >= 0 ? "up" : "down"}">${pc(r.ret)}</b> · ${r.trades} Trades · Trefferquote ${r.winRate == null ? "–" : Math.round(r.winRate * 100) + " %"} · max. Rückgang ${pc(r.maxDD)}</li>`).join("")}</ul><p>Kaufen & Halten: <b>${pc(res[0].buyHold)}</b>. Beste Strategie: <b>${best.label}</b>.</p>`, actions: [{ label: "Backtest-Grafik", lab: "backtest", sym }] };
    }
    // Multi-Timeframe
    if (cmd === "mtf" || (/zeitebene|timeframe|mtf/.test(t) && sym)) {
      const m = lab.mtf(M, sym || this.lastSym || "AAPL");
      return { html: `<p><b>Multi-Timeframe ${sym || this.lastSym}</b>: Konsens <b>${m.rating.label}</b> (${Math.round(m.agreement * 100)} % Übereinstimmung)</p><ul>${m.frames.map((f) => `<li>${f.tf}: ${f.rating.label} (${f2(f.score)})</li>`).join("")}</ul>` };
    }
    // Warum? Score-Erklärung
    if ((cmd === "warum" || /warum|wieso|begründ|erklär.*(score|rating|bewertung)/.test(t)) && sym) {
      const e = lab.explain(M, sym);
      const conf = lab.confidence(M, sym);
      return { html: `<p><b>${sym}: ${e.rating.label}</b> (Score ${f2(e.score)}, Konfidenz ${conf} %). Die wichtigsten Treiber:</p><ul>${e.items.slice(0, 6).map((i) => `<li class="${i.contrib > 0 ? "up" : i.contrib < 0 ? "down" : ""}">${i.contrib > 0 ? "▲" : i.contrib < 0 ? "▼" : "•"} ${i.name}${i.value != null ? ` (${f2(i.value)})` : ""}</li>`).join("")}</ul>` };
    }
    // Muster
    if (cmd === "muster" || /muster|pattern|kerzen|divergenz|squeeze|ausbruch/.test(t)) {
      if (sym) {
        const bars = lab.barsFor(M, sym, "1D");
        const p = lab.patterns(bars);
        const dv = lab.divergence(bars);
        const sq = lab.squeeze(bars);
        const ad = lab.adx(bars);
        return { html: `<p><b>Muster-Scan ${sym}</b> (Tageschart):</p><ul>${p.map((x) => `<li>${x.bias > 0 ? "🟢" : x.bias < 0 ? "🔴" : "⚪"} ${x.name}: ${x.text}</li>`).join("") || "<li>Keine markanten Kerzenmuster.</li>"}${dv ? `<li>${dv.type === "bullish" ? "🟢" : "🔴"} ${dv.text}</li>` : ""}${sq.squeeze ? "<li>🟡 Bollinger-Squeeze: Volatilität extrem niedrig – starke Bewegung wahrscheinlich</li>" : ""}${sq.breakout ? `<li>${sq.breakout === "up" ? "🚀 Ausbruch über das 20-Tage-Hoch" : "⚠️ Bruch unter das 20-Tage-Tief"}</li>` : ""}${ad ? `<li>Trendstärke (ADX): ${f2(ad.value)} – ${ad.label}</li>` : ""}</ul>` };
      }
      const hits = [];
      for (const u of ctx.universe) {
        const bars = lab.barsFor(M, u, "1D");
        const p = lab.patterns(bars).filter((x) => x.bias !== 0);
        const dv = lab.divergence(bars);
        const sq = lab.squeeze(bars);
        if (p.length || dv || sq.breakout) hits.push(`<li><b>${u}</b>: ${[...p.map((x) => x.name), dv ? (dv.type === "bullish" ? "bullische" : "bärische") + " Divergenz" : null, sq.breakout ? (sq.breakout === "up" ? "Ausbruch ↑" : "Bruch ↓") : null].filter(Boolean).join(", ")}</li>`);
      }
      return { html: `<p><b>Muster-Scanner</b> über ${ctx.universe.length} Aktien:</p><ul>${hits.slice(0, 10).join("") || "<li>Aktuell keine Signale.</li>"}</ul>` };
    }
    // Risiko: VaR + Monte Carlo
    if (cmd === "risiko" || /value at risk|var\b|monte|simulation|worst case|schlimmsten/.test(t)) {
      const v = lab.valueAtRisk(B, M);
      const mc = lab.monteCarlo(B, M, 252, 400);
      return { html: `<p><b>Risiko-Analyse</b> deines Depots:</p><ul><li>Value at Risk (1 Tag, 95 %): <b class="down">−${eur(v.var95)}</b></li><li>Value at Risk (1 Tag, 99 %): <b class="down">−${eur(v.var99)}</b></li><li>Expected Shortfall (95 %): −${eur(v.es95)}</li><li>Monte-Carlo in 1 Jahr: Median <b>${eur(mc.p50)}</b>, 90 %-Spanne ${eur(mc.p5)} – ${eur(mc.p95)}</li><li>Verlustwahrscheinlichkeit nach 1 Jahr: ${Math.round(mc.lossProb * 100)} %</li></ul>`, actions: [{ label: "Monte-Carlo-Grafik", lab: "montecarlo" }] };
    }
    // Rebalancing
    if (cmd === "rebalance" || /rebalanc|umschicht|ausbalancier|gleichgewicht/.test(t)) {
      const r = lab.rebalance(B, M, /risiko/.test(t) ? "risk" : "equal");
      return {
        html: r.trades.length ? `<p><b>Rebalancing (${r.mode === "risk" ? "Risiko-Parität" : "gleich gewichtet"}, 10 % Cash-Puffer):</b></p><ul>${r.trades.map((x) => `<li>${x.side === "buy" ? "Kaufe" : "Verkaufe"} ${x.qty} ${x.sym}</li>`).join("")}</ul>` : "<p>Dein Depot ist bereits ausgewogen – keine Umschichtung nötig.</p>",
        actions: r.trades.length ? [{ label: "Rebalancing ausführen", plan: r.trades.map((x) => ({ kind: x.side, sym: x.sym, qty: x.qty, why: "Rebalancing" })), primary: true }] : [],
      };
    }
    // Sentiment
    if (cmd === "sentiment" || /stimmung|sentiment|angst|gier|fear|greed/.test(t)) {
      const si = lab.sentimentIndex(M);
      const cs = sym && ctx.community ? lab.communitySentiment(ctx.community, sym) : null;
      return { html: `<p>AKYTEX Sentiment-Index: <b>${si.value}/100 – ${si.label}</b></p><ul><li>Marktbreite: ${Math.round(si.parts.breadth * 100)} % der Aktien im Plus</li><li>Momentum (5 Tage): ${pc(si.parts.mom)}</li><li>Ø RSI: ${f2(si.parts.rsi)}</li></ul>${cs && cs.n ? `<p>Community zu ${sym}: ${cs.long} Long / ${cs.short} Short (${Math.round(cs.bull * 100)} % bullisch)</p>` : ""}` };
    }
    // Sektoren
    if (cmd === "sektoren" || /sektor|branche|rotation/.test(t)) {
      const r = lab.sectorRotation(M);
      return { html: `<p><b>Sektor-Rotation</b> (5 / 20 Tage):</p><ol>${r.map((x) => `<li><b>${x.name}</b> ${pc(x.d5)} / ${pc(x.d20)} · ${x.phase}</li>`).join("")}</ol>` };
    }
    // Anomalien
    if (cmd === "anomalien" || /anomalie|ungewöhnlich|auffällig/.test(t)) {
      const a = lab.anomalies(M);
      return { html: `<p><b>Anomalie-Radar</b>:</p><ul>${a.map((x) => `<li><b>${x.sym}</b> ${pc(x.chg)} (${f2(x.z)} σ), Volumen ${f2(x.volX)}× normal</li>`).join("") || "<li>Keine Auffälligkeiten.</li>"}</ul>` };
    }
    // Steuer
    if (cmd === "steuer" || /steuer|pauschbetrag|freistellung/.test(t)) return { html: `<p><b>Steuer-Tipps</b>:</p><ul>${lab.taxHints(B, M).map((h) => `<li>${h}</li>`).join("")}</ul><p class="muted">Keine Steuerberatung.</p>` };
    // Vergleich
    if (/vergleich|versus|\bvs\b|oder .* besser|besser .* oder/.test(t) && syms.length >= 2) {
      const [x, y] = lab.compare(M, syms[0], syms[1]);
      const row = (l, a, b) => `<tr><td>${l}</td><td class="num">${a}</td><td class="num">${b}</td></tr>`;
      return { html: `<table class="grid mini-table"><thead><tr><th></th><th class="num">${x.sym}</th><th class="num">${y.sym}</th></tr></thead><tbody>${row("Kurs", eur(x.price), eur(y.price))}${row("Heute", pc(x.d1), pc(y.d1))}${row("20 Tage", pc(x.d20), pc(y.d20))}${row("1 Jahr", pc(x.y), pc(y.y))}${row("KGV", x.pe ? f2(x.pe) : "–", y.pe ? f2(y.pe) : "–")}${row("Dividende", f2(x.dy) + " %", f2(y.dy) + " %")}${row("Volatilität p. a.", f2(x.vol * 100) + " %", f2(y.vol * 100) + " %")}${row("AI-Rating", x.rating, y.rating)}</tbody></table><p>Technisch vorne: <b>${x.score >= y.score ? x.sym : y.sym}</b>.</p>` };
    }
    // Was wäre wenn
    const wi = t.match(/(\d+(?:[.,]\d+)?)\s*(?:€|eur|euro)/);
    if (wi && sym && /was wäre|was waere|wenn ich|investier|anlegen/.test(t)) {
      const amount = parseFloat(wi[1].replace(",", "."));
      const w = lab.whatIf(M, sym, amount, 30);
      return { html: `<p><b>Was-wäre-wenn:</b> ${eur(amount)} in ${sym} (${w.qty} Stück) nach 30 Handelstagen:</p><ul><li>Schlechtes Szenario (5 %): <b class="down">${eurS(w.p5)}</b></li><li>Mittleres Szenario: <b>${eurS(w.p50)}</b></li><li>Gutes Szenario (95 %): <b class="up">${eurS(w.p95)}</b></li><li>Verlustwahrscheinlichkeit: ${Math.round(w.lossProb * 100)} %</li></ul>`, actions: w.qty ? [{ label: `${w.qty} ${sym} kaufen`, side: "buy", sym, qty: w.qty }] : [] };
    }
    // Positionsgröße
    if (/wie viel|wieviel|positionsgröße|stückzahl|how many/.test(t) && sym) {
      const v = this.scan(sym);
      const risk = parseFloat((t.match(/(\d+(?:[.,]\d+)?)\s*%/) || [0, "1"])[1].replace(",", "."));
      const z = lab.sizing(B.equity(), v.price, v.h.setup.sl, risk);
      return { html: `<p>Bei <b>${f2(risk)} % Risiko</b> und Stop bei ${eur(v.h.setup.sl)} (1,5 × ATR): <b>${z.qty} Stück ${sym}</b> ≈ ${eur(z.value)} (${f2(z.weight * 100)} % des Depots). Maximaler Verlust bis Stop: ${eur(z.risk)}. (Positionsgröße auf höchstens 20 % des Depots begrenzt.)</p>`, actions: z.qty ? [{ label: `${z.qty} ${sym} mit Stop kaufen`, side: "buy", sym, qty: z.qty, sl: v.h.setup.sl, tp: v.h.setup.tp, primary: true }] : [] };
    }
    // Ähnliche Setups
    if (/ähnlich|aehnlich|wie .* sonst|vergleichbar/.test(t) && sym) {
      const sm = lab.similar(M, sym);
      return { html: `<p>Aktien mit dem ähnlichsten technischen Bild wie <b>${sym}</b>:</p><ol>${sm.map((x) => `<li><b>${x.sym}</b> – ${Math.round(x.similarity * 100)} % Ähnlichkeit</li>`).join("")}</ol>` };
    }
    // Ideen-Entwurf
    if (/idee|entwurf|schreib/.test(t) && sym) {
      const d = lab.draftIdea(M, sym);
      return { html: `<p>Entwurf für die Ideen-Börse:</p><p><b>${d.title}</b><br>${d.body}</p>`, actions: [{ label: "In Ideen-Börse übernehmen", idea: { sym, ...d }, primary: true }] };
    }
    // Watchlist-Generator
    const theme = Object.keys(lab.THEMES).find((k) => t.includes(k) || (k === "dividende" && t.includes("dividend")));
    if (/watchlist|liste|themen/.test(t) && theme) {
      const list = lab.themeWatchlist(M, theme);
      return { html: `<p><b>${lab.THEMES[theme].label}</b> – meine Auswahl:</p><p>${list.map((x) => `<b>${x}</b>`).join(" · ")}</p>`, actions: [{ label: "Zur Watchlist hinzufügen", watch: list, primary: true }] };
    }
    // Abend-Rückblick
    if (cmd === "rückblick" || cmd === "rueckblick" || /rückblick|abend|heute gelaufen|recap/.test(t)) {
      const today = new Date().toDateString();
      const fills = B.state.fills.filter((x) => new Date(x.ts).toDateString() === today);
      const dayChg = this.state.dayStart.value ? B.equity() - this.state.dayStart.value : 0;
      const doc = this.doctor();
      const hs = [...doc.holdings].sort((a, b) => b.v.dayChg - a.v.dayChg);
      return { html: `<p><b>Dein Tagesrückblick</b></p><ul><li>Depot heute: <b class="${dayChg >= 0 ? "up" : "down"}">${eurS(dayChg)}</b></li><li>${fills.length} Ausführungen heute</li>${hs.length ? `<li>Bester Wert: ${hs[0].sym} (${pc(hs[0].v.dayChg)}) · Schwächster: ${hs.at(-1).sym} (${pc(hs.at(-1).v.dayChg)})</li>` : ""}<li>Depot-Score: ${doc.score}/100</li></ul>` };
    }
    return this.answerBase(text, ctx);
  }

  answerBase(text, ctx) {
    const t = text.toLowerCase().trim();
    const syms = this.findSymbols(text);
    const qtyM = t.match(/(\d+)\s*(?:stück|stk\.?|x)?\s*([a-zäöü0-9.&-]+)/i);

    // Ein- und Auszahlungen: "zahle 500 € ein", "200 auszahlen"
    const fundIn = /(einzahl|zahle? .*ein\b|aufladen|geld (drauf|rein|einzahlen)|top ?up)/.test(t);
    const fundOut = /(auszahl|abheben|geld raus|zahle? .*aus\b)/.test(t);
    if (fundIn || fundOut) {
      const amt = parseFloat((t.match(/(\d[\d.]*(?:,\d{1,2})?)\s*(?:€|eur|euro)?/) || [])[1]?.replace(/\./g, "").replace(",", ".") || "0");
      const dir = fundOut && !fundIn ? "out" : "in";
      return {
        html: dir === "in" ? `<p>Gern! ${amt ? `<b>${eur(amt)}</b> kannst du sofort einzahlen` : "Einzahlen geht sofort"} – per Apple Pay, Google Pay, Karte, Echtzeitüberweisung, PayPal oder Lastschrift. Das Geld ist direkt handelbar. Größere Beträge überweist du einfach auf deine Depot-IBAN.</p>` : `<p>${amt ? `<b>${eur(amt)}</b> ` : "Dein Guthaben "}zahle ich dir auf dein Referenzkonto aus – per Echtzeit-Auszahlung in Sekunden. Verfügbar sind <b>${eur(this.broker.buyingPower())}</b>.</p>`,
        actions: [{ label: dir === "in" ? `${amt ? eur(amt) + " " : ""}einzahlen` : `${amt ? eur(amt) + " " : ""}auszahlen`, fund: dir, amount: amt, primary: true }],
        follow: dir === "in" ? ["Was soll ich jetzt kaufen?", "Sparplan 200 € ASML monatlich", "Wie steht mein Depot?"] : ["Wie steht mein Depot?"],
      };
    }

    // Kauf-/Verkaufsbefehle: "kaufe 10 SAP", "verkauf 5 tesla"
    const cmd = t.match(/\b(kauf\w*|verkauf\w*|buy|sell)\b/);
    if (cmd && syms.length && /\d/.test(t) && !/soll|sollte|lohnt|würdest|empfiehl/.test(t)) {
      const side = /verkauf|sell/.test(cmd[1]) ? "sell" : "buy";
      const sym = syms[0];
      const qty = parseInt((qtyM && qtyM[1]) || "1", 10);
      const v = this.scan(sym);
      const pos = this.broker.position(sym);
      if (side === "sell" && (!pos || pos.qty < qty)) return { html: `<p>Du hältst ${pos ? pos.qty : 0} Stück ${sym} – ${qty} kann ich nicht verkaufen.</p>` };
      return {
        html: `<p>Verstanden: <b>${qty} ${sym} ${side === "buy" ? "kaufen" : "verkaufen"}</b> zu ca. ${eur(v.price)} (≈ ${eur(qty * v.price)}).</p><p>Meine Einschätzung: <b class="${v.score > 0.1 ? "up" : v.score < -0.1 ? "down" : ""}">${v.rating.label}</b> – ${v.reason}.</p><p>Bitte bestätige die Order:</p>`,
        actions: [{ label: `${qty} ${sym} ${side === "buy" ? "kaufen" : "verkaufen"}`, side, sym, qty, primary: true }],
      };
    }

    // Glossar
    const g = Object.keys(GLOSSARY).find((k) => t.includes(k));
    if (g && /(was|erklär|bedeutet|heißt|wie funktioniert)/.test(t)) {
      const [name, desc] = GLOSSARY[g];
      return { html: `<p><b>${name}</b> ${desc}</p>` };
    }

    // Autopilot
    if (/autopilot|automatisch|selbstständig|selbständig|für mich handeln/.test(t)) {
      const c = this.state.config;
      return {
        html: `<p>Der <b>Autopilot</b> analysiert alle ${ctx.universe.length} Aktien laufend und handelt nach deiner Strategie <b>${STRATEGIES[c.strategy].label}</b>:</p>
        <ul><li>Budget: max. ${c.budgetPct} % deines Depots, je Aktie max. ${c.maxPosPct} %</li><li>Jeder Kauf bekommt Stop-Loss −${c.stopPct} % und Ziel +${c.takePct} %</li><li>Trailing-Stop sichert Gewinne, max. ${c.maxTrades} Trades pro Tag, max. 35 % je Branche</li><li>Jede Entscheidung wird mit Begründung protokolliert – Not-Aus jederzeit.</li></ul>
        <p>Status: <b>${c.enabled ? (c.mode === "auto" ? "aktiv – handelt selbstständig" : "aktiv – macht Vorschläge") : "aus"}</b>.</p>`,
      };
    }

    // Einzelaktie analysieren / "soll ich X verkaufen"
    if (syms.length) {
      return this.stockAnswer(syms[0], /verkauf|halten|behalten|raus/.test(t));
    }

    // Depot
    if (/depot|portfolio|wie steh|mein geld|meine aktien|performance|diagnose|check/.test(t)) return this.portfolioAnswer();
    // Risiko
    if (/risiko|gefahr|sicher|absicher|verlust/.test(t)) return this.riskAnswer();
    // Chancen / was kaufen
    if (/kauf|chance|empfehl|tipp|invest|was soll|lohnt|beste|top/.test(t)) return this.ideasAnswer(ctx.universe);
    // Markt
    if (/markt|heute|lage|briefing|news|stimmung|dax|nasdaq/.test(t)) return this.marketAnswer(ctx.universe);
    if (/^(hi|hallo|hey|moin|servus|guten)/.test(t) || /hilfe|help|was kannst/.test(t)) {
      return {
        html: `<p>Hallo! Ich bin <b>Aky</b>, dein persönlicher Trading-Berater. Ich kann:</p><ul><li>dein <b>Depot analysieren</b> und Risiken finden</li><li><b>Chancen</b> im Markt aufspüren</li><li>jede <b>Aktie bewerten</b> (z. B. „Was hältst du von SAP?“)</li><li>Orders vorbereiten („Kaufe 10 NVDA“)</li><li>Begriffe erklären („Was ist ein RSI?“)</li><li>mit dem <b>Autopilot</b> selbstständig handeln</li></ul>`,
      };
    }
    // Nicht verstanden: ähnlichste Themen vorschlagen statt einer Sackgasse
    const topics = [
      [/depo|portf|geld|konto/, "Wie steht mein Depot?"],
      [/kauf|invest|aktie|chanc/, "Was soll ich jetzt kaufen?"],
      [/risk|risik|sicher|verlust|crash/, "Wie riskant ist mein Depot?"],
      [/markt|börs|boers|news|heute/, "Wie ist die Marktlage heute?"],
      [/plan|heute|tun/, "Tagesplan"],
      [/steuer|finanzamt/, "Steuer-Tipps"],
    ].filter(([re]) => re.test(t)).map(([, q]) => q);
    const follow = [...new Set([...topics, "Wie steht mein Depot?", "Was soll ich jetzt kaufen?", "Was ist ein RSI?"])].slice(0, 3);
    return { html: `<p>Das habe ich noch nicht ganz verstanden${topics.length ? " – meintest du vielleicht eines davon?" : "."} Du kannst mich nach deinem Depot, nach Chancen oder nach einer Aktie wie „Tesla“ fragen, Begriffe erklären lassen oder direkt sagen „Kaufe 5 SAP“ oder „Zahle 500 € ein“.</p>`, follow };
  }

  findSymbols(text) {
    const out = [];
    const up = text.toUpperCase();
    // Kürzel, die auch normale deutsche Wörter sind („sie“, „ko“, „v“), zählen nur in Großbuchstaben
    const AMBIG = new Set(["SIE", "KO", "V", "MC", "BAS", "MA"]);
    const low = deaccent(text.toLowerCase());
    for (const st of this.market.list) {
      const first = deaccent(st.n.split(/[ .,-]/)[0].toLowerCase());
      if (new RegExp(`\\b${st.s}\\b`).test(AMBIG.has(st.s) ? text : up) || (first.length > 3 && new RegExp(`\\b${first.replace(/[^a-z0-9]/g, "")}`).test(low))) out.push(st.s);
    }
    for (const [alias, sym] of Object.entries(ALIASES)) if (!out.includes(sym) && new RegExp(`\\b${alias}\\b`).test(low)) out.push(sym);
    if (out.length) return out;
    // Tippfehler verzeihen: „Nvidea“, „Appel“, „Rheinmetal“
    const words = low.match(/[a-zäöüß]{5,}/g) || [];
    for (const w of words) {
      if (STOP.has(w)) continue;
      let best = null;
      for (const st of this.market.list) {
        const names = [deaccent(st.n.split(/[ .,-]/)[0].toLowerCase()), ...Object.keys(ALIASES).filter((a) => ALIASES[a] === st.s && !a.includes(" "))];
        for (const n of names) {
          if (n.length < 4) continue;
          const d = osa(w, n);
          const max = n.length >= 7 ? 2 : 1;
          if (d <= max && (!best || d < best.d)) best = { d, s: st.s };
        }
      }
      if (best && !out.includes(best.s)) out.push(best.s);
    }
    return out;
  }

  stockAnswer(sym, holdingQ) {
    const v = this.scan(sym);
    const pos = this.broker.position(sym);
    const d = v.d;
    const h = v.h;
    const setup = h.setup;
    let rec;
    if (pos) {
      const pnl = (v.price - pos.avg) / pos.avg;
      rec = v.score < -0.25 ? `Du hältst ${pos.qty} Stück (${pc(pnl)}). Die Signale sind schwach – ich würde <b>reduzieren oder einen engen Stop</b> bei ${eur(v.price - h.atr * 1.2)} setzen.` : v.score > 0.25 ? `Du hältst ${pos.qty} Stück (${pc(pnl)}). Das Bild ist stark – <b>halten</b> und den Stop auf ${eur(v.price - h.atr * 1.5)} nachziehen.` : `Du hältst ${pos.qty} Stück (${pc(pnl)}). Neutral – <b>halten</b>, aber mit Stop absichern.`;
    } else rec = v.score > 0.25 ? `Interessanter Einstieg: Ziel ${eur(setup.tp)}, Stop ${eur(setup.sl)} (CRV ≈ 2:1).` : v.score < -0.25 ? "Aktuell <b>kein Kauf</b> – warte auf eine Trendwende." : "Abwarten, bis sich ein klarer Trend zeigt.";
    const actions = [];
    if (!pos && v.score > 0.1) {
      const qty = Math.max(1, Math.floor((this.broker.equity() * 0.05) / v.price));
      actions.push({ label: `${qty} ${sym} kaufen (5 % Depot)`, side: "buy", sym, qty, primary: true, sl: setup.sl, tp: setup.tp });
    }
    if (pos && v.score < -0.1) actions.push({ label: `${Math.max(1, Math.floor(pos.qty / 2))} ${sym} verkaufen (Hälfte)`, side: "sell", sym, qty: Math.max(1, Math.floor(pos.qty / 2)), primary: true });
    actions.push({ label: `Chart ${sym} öffnen`, open: sym });
    return {
      html: `<div class="ai-stock"><div><b>${sym}</b> · ${this.market.get(sym).n}</div><div class="ai-stock-px">${eur(v.price)} <span class="${v.dayChg >= 0 ? "up" : "down"}">${pc(v.dayChg)}</span></div></div>
        <p>AKYTEX AI: <b class="${v.score > 0.1 ? "up" : v.score < -0.1 ? "down" : ""}">${v.rating.label}</b> (Score ${f2(v.score)}, Konfidenz ${lab.confidence(this.market, sym)} %). ${v.reason}.</p>
        <ul><li>Unterstützung ${eur(d.levels.support)} · Widerstand ${eur(d.levels.resistance)}</li><li>Tagesvolatilität ≈ ${f2(v.atrPct * 100)} %</li>${holdingQ && !pos ? "<li>Du hältst diese Aktie aktuell nicht.</li>" : ""}</ul>
        <p>${rec}</p>`,
      actions,
    };
  }

  portfolioAnswer() {
    const doc = this.doctor();
    const b = this.broker;
    const hs = [...doc.holdings].sort((a, c) => c.pnl - a.pnl);
    return {
      html: `<p>Dein Depot: <b>${eur(b.equity())}</b>, davon ${f2(doc.cashPct * 100)} % Guthaben. <b>Depot-Score ${doc.score}/100</b> (Streuung ${doc.parts.div}, Risiko ${doc.parts.risk}, Qualität ${doc.parts.qual}, Liquidität ${doc.parts.liq}).</p>
      ${hs.length ? `<p>Beste Position: <b>${hs[0].sym}</b> ${pc(hs[0].pnl)} · Schwächste: <b>${hs[hs.length - 1].sym}</b> ${pc(hs[hs.length - 1].pnl)}</p>` : ""}
      <ul>${doc.tips.slice(0, 4).map((t) => `<li>${t.icon} ${t.text}</li>`).join("")}</ul>`,
      actions: doc.tips.filter((t) => t.action === "sell").slice(0, 2).map((t) => ({ label: `${t.sym} halbieren`, side: "sell", sym: t.sym, qty: Math.max(1, Math.floor(b.position(t.sym).qty / 2)) })),
    };
  }

  riskAnswer() {
    const doc = this.doctor();
    const eq = this.broker.equity();
    const worst = doc.holdings.reduce((a, h) => a + h.val * h.v.atrPct * 2.33, 0); // ~99 %-Tagesrisiko grob
    return {
      html: `<p>Risiko-Check: Risiko-Score <b>${doc.parts.risk}/100</b> (höher = ruhiger).</p><ul><li>Geschätzter Verlust an einem sehr schlechten Tag (1 von 100): <b class="down">${eur(-worst)}</b> (${f2((worst / eq) * 100)} % des Depots)</li><li>Größte Einzelposition: ${doc.holdings.length ? f2(Math.max(...doc.holdings.map((h) => h.weight)) * 100) + " %" : "–"}</li><li>Branchen: ${Object.keys(doc.sectors).length || 0}</li></ul><ul>${doc.tips.filter((t) => ["⚖️", "🧩", "🛡️", "⚠️"].includes(t.icon)).map((t) => `<li>${t.icon} ${t.text}</li>`).join("") || "<li>✅ Keine akuten Risiken gefunden.</li>"}</ul>`,
    };
  }

  ideasAnswer(universe) {
    const top = this.scanAll(universe).filter((v) => !this.broker.position(v.sym)).slice(0, 3);
    const eq = this.broker.equity();
    return {
      html: `<p>Die aktuell stärksten Chancen laut AKYTEX AI:</p><ol>${top.map((v) => `<li><b>${v.sym}</b> – ${v.rating.label} (Score ${f2(v.score)}): ${v.reason}.</li>`).join("")}</ol><p class="muted">Tipp: nicht mehr als 5–10 % des Depots pro Aktie, immer mit Stop-Loss.</p>`,
      actions: top.map((v) => {
        const qty = Math.max(1, Math.floor((eq * 0.05) / v.price));
        return { label: `${qty} ${v.sym} kaufen`, side: "buy", sym: v.sym, qty, sl: v.h.setup.sl, tp: v.h.setup.tp };
      }),
    };
  }

  marketAnswer(universe) {
    const all = this.scanAll(universe);
    const sectors = {};
    for (const v of all) (sectors[v.sector] ||= []).push(v.dayChg);
    const sec = Object.entries(sectors).map(([s, a]) => [s, a.reduce((x, y) => x + y, 0) / a.length]).sort((a, b) => b[1] - a[1]);
    const up = all.filter((v) => v.dayChg > 0).length;
    const mood = up / all.length > 0.6 ? "freundlich 🟢" : up / all.length < 0.4 ? "schwach 🔴" : "gemischt 🟡";
    return {
      html: `<p>Marktstimmung heute: <b>${mood}</b> – ${up} von ${all.length} Aktien im Plus.</p><ul><li>Stärkste Branche: <b>${sec[0][0]}</b> (${pc(sec[0][1])})</li><li>Schwächste Branche: <b>${sec[sec.length - 1][0]}</b> (${pc(sec[sec.length - 1][1])})</li><li>Top-Signal: <b>${all[0].sym}</b> (${all[0].rating.label}) · Schwächstes Signal: <b>${all[all.length - 1].sym}</b> (${all[all.length - 1].rating.label})</li></ul>`,
    };
  }

  // Kompakte Daten für ein Sprachmodell (Tools)
  toolPortfolio() {
    const b = this.broker;
    const doc = this.doctor();
    return {
      equity: +b.equity().toFixed(2),
      cash: +b.state.cash.toFixed(2),
      score: doc.score,
      scoreParts: doc.parts,
      positions: doc.holdings.map((h) => ({ symbol: h.sym, weightPct: +(h.weight * 100).toFixed(1), pnlPct: +(h.pnl * 100).toFixed(2), aiRating: h.v.rating.label })),
      tips: doc.tips.map((t) => t.text).slice(0, 6),
    };
  }
  toolAnalyze(sym) {
    const v = this.scan(sym);
    return {
      symbol: sym,
      name: v.name,
      sector: v.sector,
      priceEur: +v.price.toFixed(2),
      dayChangePct: +(v.dayChg * 100).toFixed(2),
      aiScore: +v.score.toFixed(2),
      aiRating: v.rating.label,
      reasons: v.reason,
      rsiHourly: v.h.rsi != null ? +v.h.rsi.toFixed(1) : null,
      support: +v.d.levels.support.toFixed(2),
      resistance: +v.d.levels.resistance.toFixed(2),
      suggestedStop: +v.h.setup.sl.toFixed(2),
      suggestedTarget: +v.h.setup.tp.toFixed(2),
      volatilityPct: +(v.atrPct * 100).toFixed(2),
    };
  }
  toolScan(universe, n = 6) {
    const all = this.scanAll(universe);
    const m = (v) => ({ symbol: v.sym, rating: v.rating.label, score: +v.score.toFixed(2), dayChangePct: +(v.dayChg * 100).toFixed(2), reasons: v.reason });
    return { strongest: all.slice(0, n).map(m), weakest: all.slice(-3).map(m) };
  }
}
