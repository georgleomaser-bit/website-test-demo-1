// AKTEX AI – Marktscan, Depot-Diagnose, Berater-Chat (lokal), Meldungen und Autopilot.
// Läuft komplett im Browser. Wo verfügbar, übernimmt ein Sprachmodell den Chat (siehe app.js).
import { analyze, rating } from "./analysis.js";
import { aggregate, tickStep } from "./market.js";

const KEY = "aktex-v2-ai";
const f2 = (v) => v.toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const pc = (v) => (v > 0 ? "+" : "") + f2(v * 100) + " %";
const eur = (v) => v.toLocaleString("de-DE", { style: "currency", currency: "EUR" });

export const STRATEGIES = {
  conservative: { label: "Defensiv", buyScore: 0.45, sellScore: -0.2, desc: "Nur starke Signale, enge Stops, Qualitätswerte." },
  balanced: { label: "Ausgewogen", buyScore: 0.3, sellScore: -0.3, desc: "Trendfolge mit solidem Chance-Risiko-Verhältnis." },
  aggressive: { label: "Offensiv", buyScore: 0.18, sellScore: -0.4, desc: "Mehr Trades, Momentum, höhere Schwankungen." },
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

export class AktexAI {
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
      config: { enabled: false, mode: "assist", strategy: "balanced", budgetPct: 30, maxPosPct: 8, stopPct: 5, takePct: 12, maxTrades: 12, universe: "all", manageAll: false },
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
      return { ...base, ...s, config: { ...base.config, ...(s.config || {}) } };
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
      if (h.v.score < -0.3) tips.push({ icon: "⚠️", text: `${h.sym}: AKTEX AI bewertet „${h.v.rating.label}“ (${h.v.reason}). Prüfe einen Stop-Loss oder Teilverkauf.`, sym: h.sym, action: "sell" });
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
  step(universe, execute) {
    const c = this.state.config;
    if (!c.enabled) return [];
    this.resetDay();
    const b = this.broker;
    const S = STRATEGIES[c.strategy];
    const eq = b.equity();
    const actions = [];

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
    const cands = this.scanAll(universe).filter((v) => v.score >= S.buyScore && !b.position(v.sym) && !actions.some((a) => a.sym === v.sym));
    for (const v of cands) {
      if (this.state.tradesDay.n + actions.length >= c.maxTrades) break;
      const size = Math.min(budget, (eq * c.maxPosPct) / 100);
      const q = this.market.quote(v.sym);
      const qty = Math.floor(size / q.ask);
      if (qty < 1 || size < 250) break;
      if (((sectorVal[v.sector] || 0) + qty * q.ask) / eq > 0.35) continue; // Branchenlimit 35 %
      actions.push({ side: "buy", sym: v.sym, qty, price: q.ask, why: `${v.rating.label} (Score ${f2(v.score)}): ${v.reason}`, score: v.score, sl: q.ask * (1 - c.stopPct / 100), tp: q.ask * (1 + c.takePct / 100) });
      budget -= qty * q.ask;
      sectorVal[v.sector] = (sectorVal[v.sector] || 0) + qty * q.ask;
      if (actions.filter((a) => a.side === "buy").length >= 2) break; // max. 2 Käufe pro Schritt
    }

    const done = [];
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
      if (avg) this.state.aiPnl += (a.price - avg) * a.qty;
      if (!b.position(a.sym)) delete this.state.managed[a.sym];
    }
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
  // Antwort als { html, actions } – Aktionen sind Buttons (z. B. Trade-Vorschläge)
  answer(text, ctx) {
    const t = text.toLowerCase().trim();
    const syms = this.findSymbols(text);
    const qtyM = t.match(/(\d+)\s*(?:stück|stk\.?|x)?\s*([a-zäöü0-9.&-]+)/i);

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
        html: `<p>Hallo! Ich bin <b>AKTEX AI</b>, dein persönlicher Trading-Berater. Ich kann:</p><ul><li>dein <b>Depot analysieren</b> und Risiken finden</li><li><b>Chancen</b> im Markt aufspüren</li><li>jede <b>Aktie bewerten</b> (z. B. „Was hältst du von SAP?“)</li><li>Orders vorbereiten („Kaufe 10 NVDA“)</li><li>Begriffe erklären („Was ist ein RSI?“)</li><li>mit dem <b>Autopilot</b> selbstständig handeln</li></ul>`,
      };
    }
    return { html: `<p>Das habe ich nicht ganz verstanden. Frag mich z. B. nach deinem Depot, nach Chancen, nach einer Aktie wie „Tesla“ oder sag „Kaufe 5 SAP“.</p>` };
  }

  findSymbols(text) {
    const out = [];
    const up = text.toUpperCase();
    for (const st of this.market.list) {
      const first = st.n.split(/[ .,-]/)[0].toLowerCase();
      if (new RegExp(`\\b${st.s}\\b`).test(up) || (first.length > 3 && text.toLowerCase().includes(first))) out.push(st.s);
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
        <p>AKTEX AI: <b class="${v.score > 0.1 ? "up" : v.score < -0.1 ? "down" : ""}">${v.rating.label}</b> (Score ${f2(v.score)}). ${v.reason}.</p>
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
      html: `<p>Die aktuell stärksten Chancen laut AKTEX AI:</p><ol>${top.map((v) => `<li><b>${v.sym}</b> – ${v.rating.label} (Score ${f2(v.score)}): ${v.reason}.</li>`).join("")}</ol><p class="muted">Tipp: nicht mehr als 5–10 % des Depots pro Aktie, immer mit Stop-Loss.</p>`,
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
