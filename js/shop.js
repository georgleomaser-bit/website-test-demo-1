// AKYTEX Store: Spotlight-Themenpakete (live nach Momentum), digitale Produkte, Merch, Geschenkkarten
const KEY = "akytex-v2-shop";

export const BASKETS = [
  { id: "b-ai", name: "KI & Chips", icon: "🤖", syms: ["NVDA", "AMD", "ASML", "AVGO", "IFX"], desc: "Die Schaufeln des KI-Goldrauschs" },
  { id: "b-bigtech", name: "Big Tech", icon: "🌐", syms: ["AAPL", "MSFT", "GOOGL", "AMZN", "META"], desc: "Die Giganten des Internets" },
  { id: "b-de", name: "Deutsche Champions", icon: "🇩🇪", syms: ["SAP", "SIE", "ALV", "MUV2", "DTE"], desc: "DAX-Schwergewichte mit Weltrang" },
  { id: "b-div", name: "Dividenden-Könige", icon: "👑", syms: ["KO", "JNJ", "ALV", "MUV2", "NESN"], desc: "Verlässliche Ausschüttungen" },
  { id: "b-def", name: "Verteidigung & Luftfahrt", icon: "✈️", syms: ["RHM", "AIR", "SIE"], desc: "Sicherheit und Mobilität" },
  { id: "b-lux", name: "Luxus & Lifestyle", icon: "💎", syms: ["MC", "ADS", "MCD", "NFLX"], desc: "Marken mit Preissetzungsmacht" },
  { id: "b-energy", name: "Energie & Rohstoffe", icon: "⚡", syms: ["XOM", "TTE", "BAS"], desc: "Die Basis der Weltwirtschaft" },
  { id: "b-health", name: "Gesundheit", icon: "🧬", syms: ["JNJ", "NOVO", "BAYN"], desc: "Demografie als Rückenwind" },
  { id: "b-auto", name: "Auto & E-Mobilität", icon: "🚗", syms: ["TSLA", "BMW", "MBG", "VOW3"], desc: "Die Zukunft auf vier Rädern" },
];

export const PRODUCTS = [
  { id: "s-momentum", cat: "strategy", name: "Quant Momentum Pro", price: 19, icon: "🚀", grad: ["#3b5bdb", "#b36bff"], desc: "Autopilot-Preset: stärkste Aktien im Aufwärtstrend, enge ATR-Stops.", unlock: { strategy: "momentum", minConf: 60 } },
  { id: "s-rebound", cat: "strategy", name: "Rebound Hunter", price: 24, icon: "🎯", grad: ["#0ea5e9", "#22c55e"], desc: "Autopilot-Preset: überverkaufte Qualitätswerte im langfristigen Trend.", unlock: { strategy: "meanrev", minConf: 45 } },
  { id: "s-defensive", cat: "strategy", name: "Dividenden-Autopilot", price: 14, icon: "🛡️", grad: ["#f59e0b", "#ef4444"], desc: "Autopilot-Preset: ruhige Werte, kleine Positionen, defensive Stops.", unlock: { strategy: "conservative", minConf: 55 } },
  { id: "c-basics", cat: "course", name: "Börse in 7 Tagen", price: 49, icon: "🎓", grad: ["#22c55e", "#0ea5e9"], desc: "7 Lektionen: Aktien, Orders, Gebühren, Risiko, Depotaufbau.", lessons: ["Was ist eine Aktie?", "Orderarten: Market, Limit, Stopp", "Kosten verstehen: Spread & Gebühren", "Risiko begrenzen mit Stop-Loss", "Diversifikation richtig", "Sparpläne und Zinseszins", "Dein erster Plan"] },
  { id: "c-charts", cat: "course", name: "Chartanalyse Masterclass", price: 99, icon: "📊", grad: ["#b36bff", "#ec4899"], desc: "Trends, Kerzenmuster, Indikatoren und Setups wie ein Profi lesen.", lessons: ["Trends und Zeitebenen", "Unterstützung & Widerstand", "Kerzenmuster", "RSI, MACD & Bollinger", "Ausbrüche und Fehlausbrüche", "Chance-Risiko-Verhältnis", "Das perfekte Setup"] },
  { id: "c-ai", cat: "course", name: "Trading mit AKYTEX AI", price: 39, icon: "🧠", grad: ["#7c9cff", "#ffcf6e"], desc: "Autopilot, Zeitpläne und das AI-Labor gezielt einsetzen.", lessons: ["Wie AKYTEX AI denkt", "Konfidenz & Multi-Timeframe", "Zeitpläne und Regeln", "Autopilot sicher einstellen", "Backtests lesen", "Risiko mit Monte Carlo"] },
  { id: "r-picks", cat: "report", name: "Top 10 AI-Picks (heute)", price: 4.99, icon: "📑", grad: ["#ffcf6e", "#f97316"], desc: "Die zehn stärksten Signale des Tages mit Begründung, Ziel und Stop.", report: "picks" },
  { id: "r-outlook", cat: "report", name: "Marktausblick", price: 9.99, icon: "🔭", grad: ["#0ea5e9", "#7c9cff"], desc: "Sentiment, Sektor-Rotation, Anomalien und Szenarien auf einen Blick.", report: "outlook" },
  { id: "m-hoodie", cat: "merch", name: "ΛKYTEX Hoodie „Orbit“", price: 69, icon: "hoodie", grad: ["#0b1a36", "#3b5bdb"], desc: "Schwerer Bio-Baumwoll-Hoodie mit gesticktem Λ-Logo.", physical: true },
  { id: "m-cap", cat: "merch", name: "ΛKYTEX Cap", price: 29, icon: "cap", grad: ["#111827", "#7c5cff"], desc: "Sechs-Panel-Cap, gestickt, verstellbar.", physical: true },
  { id: "m-mug", cat: "merch", name: "Tasse „Markets move“", price: 19, icon: "mug", grad: ["#1e1b4b", "#b36bff"], desc: "Keramik, 350 ml, spülmaschinenfest.", physical: true },
  { id: "m-note", cat: "merch", name: "Trading-Journal (Notizbuch)", price: 24, icon: "note", grad: ["#172554", "#ffcf6e"], desc: "Gebunden, 192 Seiten mit Trade-Vorlagen.", physical: true },
  { id: "g-25", cat: "gift", name: "Geschenkkarte 25 €", price: 25, icon: "🎁", grad: ["#ec4899", "#b36bff"], desc: "Für Abos, Kurse und den Store. Code sofort per E-Mail.", gift: 25 },
  { id: "g-50", cat: "gift", name: "Geschenkkarte 50 €", price: 50, icon: "🎁", grad: ["#b36bff", "#3b5bdb"], desc: "Für Abos, Kurse und den Store. Code sofort per E-Mail.", gift: 50 },
  { id: "g-100", cat: "gift", name: "Geschenkkarte 100 €", price: 100, icon: "🎁", grad: ["#3b5bdb", "#ffcf6e"], desc: "Für Abos, Kurse und den Store. Code sofort per E-Mail.", gift: 100 },
];
export const CATS = { all: "Alle", basket: "Themen-Pakete", strategy: "Strategien", course: "Academy", report: "Reports", merch: "Merch", gift: "Geschenkkarten" };

export class Shop {
  constructor(market) {
    this.market = market;
    this.state = this.load();
  }
  load() {
    try {
      return { cart: [], orders: [], owned: [], ...JSON.parse(localStorage.getItem(KEY) || "{}") };
    } catch (_) {
      return { cart: [], orders: [], owned: [] };
    }
  }
  save() {
    try {
      localStorage.setItem(KEY, JSON.stringify(this.state));
    } catch (_) {
      /* ignorieren */
    }
  }
  product(id) {
    return PRODUCTS.find((p) => p.id === id);
  }
  owns(id) {
    return this.state.owned.includes(id);
  }
  // Themenpakete live bewertet: Momentum der letzten 5 und 20 Tage
  baskets() {
    const m = this.market;
    return BASKETS.map((b) => {
      const d5 = b.syms.reduce((s, x) => s + m.perf(x, 5), 0) / b.syms.length;
      const d20 = b.syms.reduce((s, x) => s + m.perf(x, 20), 0) / b.syms.length;
      const d1 = b.syms.reduce((s, x) => s + m.quote(x).changePct, 0) / b.syms.length;
      // Index der letzten 30 Tage (gleichgewichtet, normiert auf 100)
      const series = [];
      for (let i = 30; i >= 0; i--) series.push((b.syms.reduce((s, x) => { const d = m.get(x).days; return s + d[d.length - 1 - i].close / d[d.length - 31].close; }, 0) / b.syms.length) * 100);
      return { ...b, d1, d5, d20, heat: d5 * 0.6 + d20 * 0.4, series };
    }).sort((a, c) => c.heat - a.heat);
  }
  spotlightEndsIn() {
    const d = new Date();
    d.setHours(24, 0, 0, 0);
    return d.getTime() - Date.now();
  }
  cartItems() {
    return this.state.cart.map((c) => ({ ...this.product(c.id), qty: c.qty })).filter((x) => x.id);
  }
  add(id, qty = 1) {
    const p = this.product(id);
    if (!p) return;
    const c = this.state.cart.find((x) => x.id === id);
    if (p.cat !== "merch" && p.cat !== "gift" && (c || this.owns(id))) return false; // digitale Produkte nur einmal
    if (c) c.qty += qty;
    else this.state.cart.push({ id, qty });
    this.save();
    return true;
  }
  setQty(id, qty) {
    const c = this.state.cart.find((x) => x.id === id);
    if (!c) return;
    c.qty = Math.max(0, qty);
    if (!c.qty) this.state.cart = this.state.cart.filter((x) => x.id !== id);
    this.save();
  }
  count() {
    return this.state.cart.reduce((s, c) => s + c.qty, 0);
  }
  complete(items, total, method, address) {
    const no = `ORD-${new Date().getFullYear()}-${String(this.state.orders.length + 1).padStart(5, "0")}`;
    const codes = [];
    for (const i of items) {
      if (i.cat !== "merch" && i.cat !== "gift" && !this.owns(i.id)) this.state.owned.push(i.id);
      if (i.gift) for (let k = 0; k < i.qty; k++) codes.push({ value: i.gift, code: "AKX-" + Math.random().toString(36).slice(2, 6).toUpperCase() + "-" + Math.random().toString(36).slice(2, 6).toUpperCase() });
    }
    const order = { no, date: Date.now(), items: items.map((i) => ({ id: i.id, name: i.name, qty: i.qty, price: i.price })), total, method: method.label, address: items.some((i) => i.physical) ? address : null, codes, status: items.some((i) => i.physical) ? "in Vorbereitung (Test)" : "zugestellt (Test)" };
    this.state.orders.unshift(order);
    this.state.cart = [];
    this.save();
    return order;
  }
}
