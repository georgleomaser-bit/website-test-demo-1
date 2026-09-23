// AKTEX AI Zeitplan: zeitgesteuerte Orders, Sparpläne und Wenn-Dann-Regeln
import * as ind from "./indicators.js";
import { aggregate } from "./market.js";
import { analyze } from "./analysis.js";

const KEY = "aktex-v2-schedule";
const uid = () => Math.random().toString(36).slice(2, 9);
const f2 = (v) => v.toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export const CONDITIONS = {
  price_above: { label: "Kurs steigt über", unit: "€" },
  price_below: { label: "Kurs fällt unter", unit: "€" },
  rsi_below: { label: "RSI (1H) fällt unter", unit: "" },
  rsi_above: { label: "RSI (1H) steigt über", unit: "" },
  day_up: { label: "Tagesplus größer als", unit: "%" },
  day_down: { label: "Tagesminus größer als", unit: "%" },
  rating_buy: { label: "AI-Rating wird „Kaufen“", unit: null },
  rating_sell: { label: "AI-Rating wird „Verkaufen“", unit: null },
};
export const EVERY = { hourly: "stündlich", daily: "täglich", weekdays: "werktags", weekly: "wöchentlich", monthly: "monatlich" };
export const WEEKDAYS = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"];

export class Scheduler {
  constructor(market, broker) {
    this.market = market;
    this.broker = broker;
    this.listeners = new Set();
    this.state = this.load();
    this.lastEval = 0;
  }
  on(fn) {
    this.listeners.add(fn);
  }
  emit(e) {
    for (const fn of this.listeners) fn(e);
  }
  load() {
    try {
      return { tasks: [], ...JSON.parse(localStorage.getItem(KEY) || "{}") };
    } catch (_) {
      return { tasks: [] };
    }
  }
  save() {
    try {
      localStorage.setItem(KEY, JSON.stringify(this.state));
    } catch (_) {
      /* ignorieren */
    }
  }

  // Nächster Ausführungszeitpunkt für wiederkehrende Aufgaben
  nextRun(t, from = Date.now()) {
    const [hh, mm] = (t.time || "09:00").split(":").map(Number);
    const d = new Date(from);
    if (t.every === "hourly") {
      const n = new Date(from);
      n.setMinutes(mm, 0, 0);
      if (n.getTime() <= from) n.setHours(n.getHours() + 1);
      return n.getTime();
    }
    d.setHours(hh, mm, 0, 0);
    const bump = () => d.setDate(d.getDate() + 1);
    if (d.getTime() <= from) bump();
    if (t.every === "weekdays") while (d.getDay() === 0 || d.getDay() === 6) bump();
    if (t.every === "weekly") while (d.getDay() !== +(t.weekday ?? 1)) bump();
    if (t.every === "monthly") {
      const day = +(t.monthday || 1);
      const m = new Date(from);
      m.setDate(day);
      m.setHours(hh, mm, 0, 0);
      if (m.getTime() <= from) m.setMonth(m.getMonth() + 1);
      return m.getTime();
    }
    return d.getTime();
  }

  add(task) {
    const t = { id: uid(), created: Date.now(), enabled: true, runs: [], ...task };
    if (t.type === "recurring") t.next = this.nextRun(t);
    this.state.tasks.unshift(t);
    this.save();
    this.emit({ kind: "change" });
    return t;
  }
  remove(id) {
    this.state.tasks = this.state.tasks.filter((t) => t.id !== id);
    this.save();
    this.emit({ kind: "change" });
  }
  toggle(id) {
    const t = this.state.tasks.find((x) => x.id === id);
    if (!t) return;
    t.enabled = !t.enabled;
    if (t.enabled && t.type === "recurring") t.next = this.nextRun(t);
    this.save();
    this.emit({ kind: "change" });
  }

  describe(t) {
    const a = t.action;
    const what = `${a.side === "buy" ? "Kaufe" : "Verkaufe"} ${a.mode === "amount" ? `für ${f2(a.value)} €` : a.mode === "pct" ? `${a.value} % der Position` : `${a.value} Stück`} ${a.sym}${a.limit ? ` (Limit ${f2(a.limit)} €)` : ""}`;
    if (t.type === "once") return `${what} am ${new Date(t.at).toLocaleString("de-DE", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" })}`;
    if (t.type === "recurring") return `${what} ${EVERY[t.every]}${t.every === "weekly" ? ` am ${WEEKDAYS[t.weekday ?? 1]}` : t.every === "monthly" ? ` am ${t.monthday || 1}.` : ""}${t.every === "hourly" ? ` zur Minute ${t.time.split(":")[1]}` : ` um ${t.time}`}`;
    const c = CONDITIONS[t.cond.kind];
    return `${what}, wenn ${c.label}${c.unit != null ? ` ${f2(t.cond.value)}${c.unit ? " " + c.unit : ""}` : ""}${t.window ? ` (nur ${t.window.from}–${t.window.to})` : ""}`;
  }

  evalCondition(t) {
    const sym = t.action.sym;
    const st = this.market.get(sym);
    const q = this.market.quote(sym);
    const v = +t.cond.value;
    switch (t.cond.kind) {
      case "price_above":
        return st.price >= v;
      case "price_below":
        return st.price <= v;
      case "day_up":
        return q.changePct * 100 >= v;
      case "day_down":
        return q.changePct * 100 <= -v;
      case "rsi_below":
      case "rsi_above": {
        const r = ind.rsi(aggregate(st.m1.slice(-60 * 24 * 3), "1h").map((b) => b.close), 14).at(-1);
        return t.cond.kind === "rsi_below" ? r <= v : r >= v;
      }
      case "rating_buy":
      case "rating_sell": {
        const a = analyze(aggregate(st.m1.slice(-60 * 24 * 7), "1h"));
        return t.cond.kind === "rating_buy" ? a.score >= 0.1 : a.score <= -0.1;
      }
    }
    return false;
  }

  inWindow(w) {
    if (!w) return true;
    const d = new Date();
    const cur = d.getHours() * 60 + d.getMinutes();
    const [fh, fm] = w.from.split(":").map(Number);
    const [th, tm] = w.to.split(":").map(Number);
    return cur >= fh * 60 + fm && cur <= th * 60 + tm;
  }

  execute(t, why) {
    const a = t.action;
    const b = this.broker;
    const q = this.market.quote(a.sym);
    let qty = +a.value;
    if (a.mode === "amount") qty = Math.floor(+a.value / (a.side === "buy" ? q.ask : q.bid));
    if (a.mode === "pct") qty = Math.floor(((b.position(a.sym)?.qty || 0) * +a.value) / 100);
    let res;
    if (qty < 1) res = { ok: false, msg: a.mode === "amount" ? "Betrag reicht nicht für eine Aktie" : "Keine Stücke vorhanden" };
    else res = b.placeOrder({ symbol: a.sym, side: a.side, type: a.limit ? "limit" : "market", qty, limitPrice: a.limit || null });
    const run = { ts: Date.now(), ok: res.ok, msg: res.ok ? `${a.side === "buy" ? "Gekauft" : "Verkauft"}: ${qty} ${a.sym}${why ? " – " + why : ""}` : res.msg };
    t.runs.unshift(run);
    t.runs.length = Math.min(t.runs.length, 20);
    t.lastRun = run.ts;
    this.save();
    this.emit({ kind: "run", task: t, run });
    return run;
  }

  tick() {
    const now = Date.now();
    let changed = false;
    const evalConds = now - this.lastEval > 4000;
    if (evalConds) this.lastEval = now;
    for (const t of this.state.tasks) {
      if (!t.enabled) continue;
      if (t.type === "once" && now >= t.at) {
        this.execute(t, "Timer abgelaufen");
        t.enabled = false;
        t.done = true;
        changed = true;
      } else if (t.type === "recurring" && now >= t.next) {
        this.execute(t, `Sparplan (${EVERY[t.every]})`);
        t.next = this.nextRun(t, now + 1000);
        changed = true;
      } else if (t.type === "rule" && evalConds) {
        if (!this.inWindow(t.window)) continue;
        if (t.lastRun && now - t.lastRun < (t.cooldownMin || 60) * 60000) continue;
        if (this.evalCondition(t)) {
          this.execute(t, "Bedingung erfüllt");
          if (t.once) t.enabled = false;
          changed = true;
        }
      }
    }
    if (changed) {
      this.save();
      this.emit({ kind: "change" });
    }
  }

  // Text → Aufgabe ("Kaufe 10 SAP um 15:30", "Sparplan 200 € ASML monatlich", "Verkaufe TSLA wenn über 260")
  parse(text, findSymbols) {
    const t = text.toLowerCase();
    const syms = findSymbols(text);
    if (!syms.length) return null;
    const side = /verkauf|sell/.test(t) ? "sell" : "buy";
    const amountM = t.match(/(?:für|fuer|mit)?\s*(\d+(?:[.,]\d+)?)\s*(?:€|eur|euro)/);
    const pctM = t.match(/(\d+)\s*%/);
    const qtyM = t.match(/\b(\d+)\s*(?:stück|stk|x|aktien)?\s+(?=[a-zäöü])/i);
    // ohne Mengenangabe: Kauf für 1.000 €, Verkauf der ganzen Position
    const action = side === "sell" ? { side, sym: syms[0], mode: "pct", value: 100 } : { side, sym: syms[0], mode: "amount", value: 1000 };
    if (amountM) {
      action.mode = "amount";
      action.value = parseFloat(amountM[1].replace(",", "."));
    } else if (pctM && side === "sell" && !/wenn|falls/.test(t.slice(0, t.indexOf(pctM[0])))) {
      action.mode = "pct";
      action.value = +pctM[1];
    } else if (qtyM) {
      action.mode = "qty";
      action.value = +qtyM[1];
    }
    // Wenn-Dann
    const condM = t.match(/(?:wenn|falls|sobald)\s+(?:der\s+)?(?:kurs\s+)?(?:(rsi)\s+)?(über|ueber|unter|>|<)\s*(\d+(?:[.,]\d+)?)/);
    if (condM) {
      const above = /über|ueber|>/.test(condM[2]);
      const val = parseFloat(condM[3].replace(",", "."));
      return { type: "rule", action, cond: { kind: condM[1] ? (above ? "rsi_above" : "rsi_below") : above ? "price_above" : "price_below", value: val }, once: true, cooldownMin: 60 };
    }
    if (/(rating|signal).*(kauf)/.test(t) && /wenn|sobald/.test(t)) return { type: "rule", action, cond: { kind: "rating_buy" }, once: true, cooldownMin: 60 };
    // In X Minuten/Stunden
    const inM = t.match(/in\s+(\d+)\s*(min|minute|minuten|std|stunde|stunden)/);
    if (inM) return { type: "once", action, at: Date.now() + +inM[1] * (/^s/.test(inM[2]) ? 3600000 : 60000) };
    // Wiederkehrend
    const timeM = t.match(/(\d{1,2})[:.](\d{2})/);
    const time = timeM ? `${timeM[1].padStart(2, "0")}:${timeM[2]}` : "09:30";
    const wd = ["sonntag", "montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag"].findIndex((d) => t.includes(d));
    if (/sparplan|jeden|jede|täglich|taeglich|wöchentlich|monatlich|werktags|stündlich/.test(t)) {
      const every = /stündlich/.test(t) ? "hourly" : /werktags/.test(t) ? "weekdays" : /monat/.test(t) ? "monthly" : wd >= 0 || /woche/.test(t) ? "weekly" : "daily";
      return { type: "recurring", action, every, time, weekday: wd >= 0 ? wd : 1, monthday: 1 };
    }
    // Zeitpunkt heute/morgen
    if (timeM) {
      const d = new Date();
      d.setHours(+timeM[1], +timeM[2], 0, 0);
      if (/morgen/.test(t) || d.getTime() <= Date.now()) d.setDate(d.getDate() + 1);
      return { type: "once", action, at: d.getTime() };
    }
    return null;
  }
}
