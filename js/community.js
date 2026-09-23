// Community: Trader-Profile, Trading-Ideen, Rangliste (Demo-Community mit fiktiven Profilen)
import { analyze } from "./analysis.js";

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

export class Community {
  constructor(market) {
    this.market = market;
    this.state = this.load();
    const day = Math.floor(Date.now() / 86400000);
    const r = rng(day * 7919);
    // Kennzahlen der Trader (täglich neu gewürfelt, innerhalb eines Tages stabil)
    this.traders = TRADERS.map((t) => ({
      ...t,
      ret1y: -0.05 + r() * 0.75,
      ret30: -0.06 + r() * 0.18,
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
  }

  load() {
    try {
      return { ideas: [], liked: [], following: [], ...JSON.parse(localStorage.getItem(KEY) || "{}") };
    } catch (_) {
      return { ideas: [], liked: [], following: [] };
    }
  }
  save() {
    try {
      localStorage.setItem(KEY, JSON.stringify(this.state));
    } catch (_) {
      // Speicher voll: älteste eigene Ideen verwerfen
      this.state.ideas = this.state.ideas.slice(0, 5);
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

  generateIdeas(r) {
    const ideas = [];
    const now = Date.now();
    for (let i = 0; i < 18; i++) {
      const t = this.traders[i % this.traders.length];
      const sym = t.favs[Math.floor(r() * t.favs.length)];
      const st = this.market.get(sym);
      if (!st) continue;
      const bars = st.days.slice(-260);
      const a = analyze(bars);
      const long = a.score >= 0;
      const L = a.levels;
      let title;
      let body;
      if (a.rsi != null && a.rsi < 35) {
        title = `${sym}: Überverkauft – Rebound in Sicht?`;
        body = `RSI bei ${f2(a.rsi)}. Die Zone um ${f2(L.support)} hat mehrfach gehalten. Ich spekuliere auf eine Gegenbewegung Richtung ${f2(a.last + 2.5 * a.atr)}, Stop unter ${f2(L.support - a.atr * 0.5)}.`;
      } else if (a.rsi != null && a.rsi > 68) {
        title = `${sym} heiß gelaufen – Gewinne absichern`;
        body = `RSI ${f2(a.rsi)} und Kurs weit über dem Durchschnitt. Ich ziehe meinen Stop auf ${f2(a.last - 1.2 * a.atr)} nach und warte auf einen Rücksetzer Richtung ${f2(L.pivot)}.`;
      } else if (a.cross === "golden") {
        title = `Golden Cross bei ${sym} 🚀`;
        body = `Der SMA 50 hat den SMA 200 nach oben gekreuzt. Klassisches Trendsignal – Ziel ${f2(a.setup.tp)}, Absicherung bei ${f2(a.setup.sl)}.`;
      } else if ((L.resistance - a.last) / a.last < 0.02) {
        title = `${sym} klopft an den Widerstand bei ${f2(L.resistance)}`;
        body = `Mehrfacher Test des Hochs. Bricht ${sym} per Tagesschluss darüber aus, ist Platz bis ${f2(L.resistance + 2 * a.atr)}. Bis dahin abwarten.`;
      } else if (long) {
        title = `${sym} im Aufwärtstrend – Long-Setup`;
        body = `Kurs über den wichtigen Durchschnitten, MACD positiv. Einstieg um ${f2(a.last)}, Ziel ${f2(a.setup.tp)}, Stop ${f2(a.setup.sl)} (CRV 2:1).`;
      } else {
        title = `${sym}: Abwärtstrend bleibt intakt`;
        body = `Tiefere Hochs, Kurs unter SMA 50. Ich bleibe an der Seitenlinie, solange ${f2(L.pivot)} nicht zurückerobert wird. Nächste Unterstützung ${f2(L.support)}.`;
      }
      ideas.push({
        id: "g" + i,
        author: t.id,
        symbol: sym,
        tf: ["1D", "4h", "1h", "1D", "1W"][Math.floor(r() * 5)],
        dir: long ? "long" : "short",
        title,
        body,
        created: now - Math.floor(r() * 2 * 86400000),
        likes: Math.round(20 + r() * t.followers * 0.02),
        comments: Math.round(r() * 60),
      });
    }
    return ideas.sort((a, b) => b.created - a.created);
  }

  allIdeas() {
    return [...this.state.ideas, ...this.generated].sort((a, b) => b.created - a.created);
  }
  addIdea(idea) {
    this.state.ideas.unshift({ ...idea, id: "u" + Date.now(), author: "me", created: Date.now(), likes: 0, comments: 0 });
    this.state.ideas = this.state.ideas.slice(0, 20);
    this.save();
  }
  removeIdea(id) {
    this.state.ideas = this.state.ideas.filter((i) => i.id !== id);
    this.save();
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
