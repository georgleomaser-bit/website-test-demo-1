// AKTEX Ideen-Börse: versiegelte Trading-Ideen mit automatisch gemessener Performance,
// handelbar mit einem Klick, Autoren erhalten Royalties. (Demo mit fiktiven Profilen)
import { analyze } from "./analysis.js";
import { toLocalSec } from "./market.js";

const KEY = "aktex-v2-community";
const f2 = (v) => v.toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// SHA-256 (Web Crypto), Fallback: FNV-Hash, falls nicht verfügbar
async function sha256(text) {
  try {
    const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
    return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
  } catch (_) {
    let h = 2166136261;
    for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 16777619);
    return (h >>> 0).toString(16).padStart(8, "0").repeat(8);
  }
}
const sealPayload = (i, prev) => JSON.stringify({ a: i.author, s: i.symbol, d: i.dir, e: +i.entry.toFixed(4), t: +i.tp.toFixed(4), l: +i.sl.toFixed(4), c: i.created, h: i.title, p: prev });

export const TRADERS = [
  { id: "t1", handle: "chartmeister", name: "Jonas K.", style: "Swing-Trading", favs: ["NVDA", "AMD", "ASML", "AVGO"], color: "#4f8cff" },
  { id: "t2", handle: "DAXqueen", name: "Mira S.", style: "DAX-Werte", favs: ["SAP", "SIE", "ALV", "RHM"], color: "#e056fd" },
  { id: "t3", handle: "ValueVolker", name: "Volker B.", style: "Value-Investing", favs: ["BMW", "MBG", "BAS", "ALV"], color: "#f59e0b" },
  { id: "t4", handle: "momentum_max", name: "Max R.", style: "Momentum", favs: ["PLTR", "TSLA", "NVDA", "META"], color: "#22c55e" },
  { id: "t5", handle: "DividendenDora", name: "Dora L.", style: "Dividenden", favs: ["KO", "JNJ", "NESN", "DTE", "MUV2"], color: "#06b6d4" },
  { id: "t6", handle: "BreakoutBen", name: "Ben T.", style: "Breakouts", favs: ["META", "NFLX", "AMZN", "ORCL"], color: "#ef4444" },
  { id: "t7", handle: "swing_sophie", name: "Sophie W.", style: "Swing-Trading", favs: ["AAPL", "MSFT", "GOOGL", "V"], color: "#a3e635" },
  { id: "t8", handle: "NordCapital", name: "Henrik N.", style: "Makro & Qualität", favs: ["NOVO", "ASML", "MC", "SAP"], color: "#f472b6" },
  { id: "t9", handle: "EnergieEmil", name: "Emil F.", style: "Rohstoffe & Energie", favs: ["XOM", "TTE", "BAS", "AIR"], color: "#fb923c" },
  { id: "t10", handle: "TechTina", name: "Tina M.", style: "Wachstum", favs: ["MSFT", "GOOGL", "AMZN", "IFX", "SAP"], color: "#818cf8" },
];
const COPIERS = ["anna_trades", "LukasInvest", "bullenbaer", "fintech_fritz", "Marie.K", "depot_dave", "sparfuchs93", "KaiCharts", "LinaLongs", "TomTrader", "EllaETF", "pivot_paul"];

export class Community {
  constructor(market) {
    this.market = market;
    this.state = this.load();
    const day = Math.floor(Date.now() / 86400000);
    const r = rng(day * 7919);
    this.traders = TRADERS.map((t) => ({
      ...t,
      ret1y: -0.05 + r() * 0.75,
      winRate: 0.48 + r() * 0.24,
      risk: 2 + Math.floor(r() * 5),
      followers: Math.round(800 + r() * 48000),
      weights: t.favs.map(() => 0.5 + r()),
    }));
    this.traders.forEach((t) => {
      const s = t.weights.reduce((a, v) => a + v, 0);
      t.weights = t.weights.map((v) => v / s);
    });
    this.generated = this.generateIdeas(r);
    this.ready = this.sealGenerated();
  }

  load() {
    const base = { ideas: [], liked: [], following: [], royaltyTotal: 0, royaltyLog: [] };
    try {
      const s = { ...base, ...JSON.parse(localStorage.getItem(KEY) || "{}") };
      // Ideen aus älteren Versionen ohne Kursmarken ergänzen
      s.ideas = s.ideas.filter((i) => this.market.has(i.symbol)).map((i) => this.normalize(i));
      return s;
    } catch (_) {
      return base;
    }
  }
  normalize(i) {
    if (i.entry && i.tp && i.sl) return i;
    const st = this.market.get(i.symbol);
    const e = this.priceAt(i.symbol, i.created) || st.price;
    const d = st.price * 0.02;
    return { ...i, entry: e, tp: i.dir === "long" ? e + 2 * d : e - 2 * d, sl: i.dir === "long" ? e - d : e + d, copies: i.copies || 0, royalty: i.royalty || 0 };
  }
  save() {
    try {
      localStorage.setItem(KEY, JSON.stringify(this.state));
    } catch (_) {
      this.state.ideas.forEach((i) => delete i.img); // Screenshots opfern, Ideen bleiben
      try {
        localStorage.setItem(KEY, JSON.stringify(this.state));
      } catch (_) {
        /* ignorieren */
      }
    }
  }

  trader(id) {
    return this.traders.find((t) => t.id === id);
  }

  // Kurs zu einem Zeitpunkt (Minutenkerze)
  priceAt(sym, ms) {
    const m1 = this.market.get(sym).m1;
    const t = toLocalSec(ms);
    let lo = 0;
    let hi = m1.length - 1;
    if (t < m1[0].time) return m1[0].open;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (m1[mid].time <= t) lo = mid;
      else hi = mid - 1;
    }
    return m1[lo].close;
  }

  generateIdeas(r) {
    const ideas = [];
    const now = Date.now();
    for (let i = 0; i < 26; i++) {
      const t = this.traders[i % this.traders.length];
      const sym = t.favs[Math.floor(r() * t.favs.length)];
      const st = this.market.get(sym);
      if (!st) continue;
      const created = now - Math.floor((0.05 + r() * 1.9) * 86400000);
      const a = analyze(st.days.slice(-260));
      const long = a.score >= -0.05;
      const entry = this.priceAt(sym, created);
      const unit = a.atr * (0.45 + r() * 0.5);
      const tp = long ? entry + 2 * unit : entry - 2 * unit;
      const sl = long ? entry - unit : entry + unit;
      const T = { entry: f2(entry), tp: f2(tp), sl: f2(sl) };
      let title;
      let body;
      if (long && a.rsi != null && a.rsi < 38) {
        title = `${sym}: Überverkauft – Rebound in Sicht?`;
        body = `RSI bei ${f2(a.rsi)}, die Unterstützung hält. Einstieg ${T.entry}, Ziel ${T.tp}, Stop ${T.sl}.`;
      } else if (!long && a.rsi != null && a.rsi < 38) {
        title = `${sym}: Kein Boden in Sicht`;
        body = `RSI ${f2(a.rsi)}, aber jede Erholung wird verkauft. Short ab ${T.entry}, Ziel ${T.tp}, Stop ${T.sl}.`;
      } else if (a.rsi != null && a.rsi > 66) {
        title = long ? `${sym}: Momentum ungebrochen` : `${sym} heiß gelaufen – Rücksetzer fällig`;
        body = `RSI ${f2(a.rsi)}. ${long ? "Ich reite den Trend weiter" : "Ich erwarte eine Abkühlung"}: Einstieg ${T.entry}, Ziel ${T.tp}, Stop ${T.sl}.`;
      } else if (long && a.cross === "golden") {
        title = `Golden Cross bei ${sym} 🚀`;
        body = `SMA 50 kreuzt SMA 200 nach oben. Ziel ${T.tp}, Absicherung bei ${T.sl}.`;
      } else if (long) {
        title = [`${sym} im Aufwärtstrend – Long-Setup`, `${sym}: Ausbruch voraus`, `${sym} – Rücksetzer zum Kaufen`][i % 3];
        body = `Kurs über den wichtigen Durchschnitten, MACD positiv. Einstieg ${T.entry}, Ziel ${T.tp}, Stop ${T.sl} (CRV 2:1).`;
      } else {
        title = [`${sym}: Abwärtstrend bleibt intakt`, `${sym} unter Druck – Short-Idee`][i % 2];
        body = `Tiefere Hochs, Kurs unter SMA 50. Short ab ${T.entry}, Ziel ${T.tp}, Stop ${T.sl}.`;
      }
      const likes = Math.round(20 + r() * t.followers * 0.02);
      ideas.push({
        id: "g" + i,
        author: t.id,
        symbol: sym,
        tf: ["1D", "4h", "1h", "15m", "1D"][Math.floor(r() * 5)],
        dir: long ? "long" : "short",
        title,
        body,
        entry,
        tp,
        sl,
        created,
        likes,
        comments: Math.round(r() * 60),
        copies: Math.round(likes * (0.2 + r() * 0.5)),
      });
    }
    return ideas.sort((a, b) => a.created - b.created);
  }

  async sealGenerated() {
    let prev = "0".repeat(64);
    for (const i of this.generated) {
      i.prev = prev;
      i.hash = await sha256(sealPayload(i, prev));
      prev = i.hash;
    }
  }

  // Status und Performance seit Veröffentlichung (Ziel/Stop werden auf Minutenbasis geprüft)
  evaluate(i) {
    const st = this.market.get(i.symbol);
    const sign = i.dir === "long" ? 1 : -1;
    if (!i.status || i.status === "open") {
      const m1 = st.m1;
      const from = Math.max(toLocalSec(i.created), i._scanT || 0);
      let lo = 0;
      let hi = m1.length - 1;
      while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (m1[mid].time < Math.floor(from / 60) * 60) lo = mid + 1;
        else hi = mid;
      }
      i.status = "open";
      for (let k = lo; k < m1.length; k++) {
        const b = m1[k];
        const hitSl = i.dir === "long" ? b.low <= i.sl : b.high >= i.sl;
        const hitTp = i.dir === "long" ? b.high >= i.tp : b.low <= i.tp;
        if (hitSl || hitTp) {
          i.status = hitSl ? "stop" : "target";
          i.exit = hitSl ? i.sl : i.tp;
          i.closedAt = b.time;
          break;
        }
      }
      if (i.status === "open") i._scanT = m1[m1.length - 1].time;
    }
    const px = i.status === "open" ? st.price : i.exit;
    i.perf = (sign * (px - i.entry)) / i.entry;
    return i;
  }

  traderStats(id) {
    const ideas = this.generated.filter((i) => i.author === id).map((i) => this.evaluate(i));
    const closed = ideas.filter((i) => i.status !== "open");
    const hits = closed.filter((i) => i.status === "target").length;
    return { ideas: ideas.length, closed: closed.length, hitRate: closed.length ? hits / closed.length : null, avg: ideas.length ? ideas.reduce((a, i) => a + i.perf, 0) / ideas.length : 0 };
  }

  allIdeas() {
    return [...this.state.ideas, ...this.generated].map((i) => this.evaluate(i)).sort((a, b) => b.created - a.created);
  }
  find(id) {
    return this.allIdeas().find((i) => i.id === id);
  }

  async addIdea(idea) {
    const prev = this.state.ideas[0]?.hash || "0".repeat(64);
    const i = { ...idea, id: "u" + Date.now(), author: "me", created: Date.now(), likes: 0, comments: 0, copies: 0, royalty: 0, prev };
    i.hash = await sha256(sealPayload(i, prev));
    this.state.ideas.unshift(i);
    this.state.ideas = this.state.ideas.slice(0, 30);
    this.save();
    return i;
  }

  // Simuliert andere Nutzer, die deine offenen Ideen handeln → Royalties für dich
  simulateCopies(creatorShare) {
    const events = [];
    for (const i of this.state.ideas) {
      this.evaluate(i);
      if (i.status !== "open") continue;
      const p = 0.18 + Math.max(-0.12, Math.min(0.35, i.perf * 12));
      if (Math.random() > p) continue;
      const volume = Math.round(400 + Math.random() * 7600);
      const royalty = volume * 0.002 * creatorShare;
      i.copies = (i.copies || 0) + 1;
      i.royalty = (i.royalty || 0) + royalty;
      this.state.royaltyTotal += royalty;
      const e = { ts: Date.now(), idea: i.id, symbol: i.symbol, copier: COPIERS[Math.floor(Math.random() * COPIERS.length)], volume, royalty };
      this.state.royaltyLog.unshift(e);
      this.state.royaltyLog.length = Math.min(this.state.royaltyLog.length, 50);
      events.push(e);
    }
    if (events.length) this.save();
    return events;
  }

  isLiked(id) {
    return this.state.liked.includes(id);
  }
  toggleLike(id) {
    const i = this.state.liked.indexOf(id);
    if (i >= 0) this.state.liked.splice(i, 1);
    else this.state.liked.push(id);
    this.save();
    return i < 0;
  }
  isFollowing(id) {
    return this.state.following.includes(id);
  }
  toggleFollow(id) {
    const i = this.state.following.indexOf(id);
    if (i >= 0) this.state.following.splice(i, 1);
    else this.state.following.push(id);
    this.save();
    return i < 0;
  }
}
