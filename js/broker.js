// Demo-Broker: Konto, Orders (Market/Limit/Stop mit Stop-Loss & Take-Profit), Positionen, Alarme.
import { nowSec } from "./market.js";

export const START_CASH = 100000;
const KEY = "akytex-v2-account";

const uid = () => Math.random().toString(36).slice(2, 10);

function fresh() {
  return {
    cash: START_CASH,
    positions: {}, // sym -> { qty, avg, realized }
    orders: [], // offene Orders
    orderHistory: [], // ausgeführt / storniert / abgelehnt
    fills: [],
    alerts: [],
    realized: 0,
    fees: 0,
    equityCurve: [],
    created: Date.now(),
  };
}

export class Broker {
  constructor(market) {
    this.market = market;
    this.listeners = new Map();
    this.feeFn = () => 0; // Ordergebühr je nach Tarif
    this.state = this.load();
    market.onTick(() => this.onTick());
  }

  on(evt, fn) {
    if (!this.listeners.has(evt)) this.listeners.set(evt, new Set());
    this.listeners.get(evt).add(fn);
  }
  emit(evt, data) {
    for (const fn of this.listeners.get(evt) || []) fn(data);
  }

  load() {
    try {
      const raw = localStorage.getItem(KEY);
      if (raw) {
        const s = { ...fresh(), ...JSON.parse(raw) };
        for (const sym of Object.keys(s.positions)) if (!this.market.has(sym)) delete s.positions[sym];
        s.orders = s.orders.filter((o) => this.market.has(o.symbol));
        return s;
      }
    } catch (_) {
      /* Speicher nicht verfügbar */
    }
    return fresh();
  }
  save() {
    try {
      localStorage.setItem(KEY, JSON.stringify(this.state));
    } catch (_) {
      /* ignorieren */
    }
  }
  reset() {
    this.state = fresh();
    this.save();
    this.emit("change");
  }

  // ---------- Kennzahlen ----------
  position(sym) {
    return this.state.positions[sym] || null;
  }
  positionsValue() {
    let v = 0;
    for (const [sym, p] of Object.entries(this.state.positions)) v += p.qty * this.market.get(sym).price;
    return v;
  }
  unrealized() {
    let v = 0;
    for (const [sym, p] of Object.entries(this.state.positions)) v += (this.market.get(sym).price - p.avg) * p.qty;
    return v;
  }
  equity() {
    return this.state.cash + this.positionsValue();
  }
  reservedCash() {
    return this.state.orders
      .filter((o) => o.side === "buy")
      .reduce((a, o) => a + o.qty * (o.limitPrice || o.stopPrice || this.market.get(o.symbol).price), 0);
  }
  buyingPower() {
    return Math.max(0, this.state.cash - this.reservedCash());
  }
  reservedQty(sym) {
    // Stück, die bereits in offenen Verkaufsorders gebunden sind (SL/TP-Paare zählen einmal)
    const groups = new Set();
    let q = 0;
    for (const o of this.state.orders) {
      if (o.symbol !== sym || o.side !== "sell") continue;
      if (o.oco) {
        if (groups.has(o.oco)) continue;
        groups.add(o.oco);
      }
      q += o.qty;
    }
    return q;
  }
  stats() {
    const closed = this.state.fills.filter((f) => f.side === "sell" && f.pnl != null);
    const wins = closed.filter((f) => f.pnl > 0).length;
    return {
      trades: this.state.fills.length,
      closed: closed.length,
      winRate: closed.length ? wins / closed.length : null,
      best: closed.length ? Math.max(...closed.map((f) => f.pnl)) : null,
      worst: closed.length ? Math.min(...closed.map((f) => f.pnl)) : null,
    };
  }

  // ---------- Orders ----------
  // Gebühren einer Order: Ordergebühr laut Tarif + ggf. Ideen-Gebühr (Prozent vom Volumen)
  costs(qty, price, ideaFeePct = 0) {
    const orderFee = this.feeFn();
    const ideaFee = qty * price * ideaFeePct;
    return { orderFee, ideaFee, total: orderFee + ideaFee };
  }

  placeOrder({ symbol, side, type, qty, limitPrice, stopPrice, sl, tp, ideaId = null, ideaFeePct = 0 }) {
    const q = this.market.quote(symbol);
    qty = Math.floor(Number(qty));
    if (!Number.isFinite(qty) || qty <= 0) return { ok: false, msg: "Bitte eine gültige Stückzahl eingeben." };
    if (type === "limit" && !(limitPrice > 0)) return { ok: false, msg: "Bitte einen Limitpreis angeben." };
    if (type === "stop" && !(stopPrice > 0)) return { ok: false, msg: "Bitte einen Stopp-Preis angeben." };

    if (side === "buy") {
      const px = type === "limit" ? limitPrice : type === "stop" ? stopPrice : q.ask;
      if (qty * px + this.costs(qty, px, ideaFeePct).total > this.buyingPower() + 1e-6) return { ok: false, msg: "Nicht genügend Kaufkraft (inkl. Gebühren)." };
      if (sl != null && !(sl < px)) return { ok: false, msg: "Stop-Loss muss unter dem Einstiegskurs liegen." };
      if (tp != null && !(tp > px)) return { ok: false, msg: "Take-Profit muss über dem Einstiegskurs liegen." };
      if (type === "stop" && stopPrice <= q.price) return { ok: false, msg: "Kauf-Stopp muss über dem aktuellen Kurs liegen." };
    } else {
      const pos = this.position(symbol);
      const free = (pos?.qty || 0) - this.reservedQty(symbol);
      if (qty > free) return { ok: false, msg: `Nur ${Math.max(0, free)} Stück ${symbol} frei verfügbar (Leerverkauf nicht möglich).` };
      if (type === "stop" && stopPrice >= q.price) return { ok: false, msg: "Verkaufs-Stopp muss unter dem aktuellen Kurs liegen." };
    }

    const order = {
      id: uid(),
      symbol,
      side,
      type,
      qty,
      limitPrice: type === "limit" ? limitPrice : null,
      stopPrice: type === "stop" ? stopPrice : null,
      sl: side === "buy" ? sl ?? null : null,
      tp: side === "buy" ? tp ?? null : null,
      oco: null,
      ideaId,
      ideaFeePct,
      created: Date.now(),
      status: "open",
    };

    if (type === "market") {
      this.fill(order, side === "buy" ? q.ask : q.bid);
    } else {
      this.state.orders.push(order);
      this.save();
      this.emit("change");
      this.emit("placed", order);
    }
    return { ok: true, order };
  }

  cancelOrder(id, reason = "storniert") {
    const i = this.state.orders.findIndex((o) => o.id === id);
    if (i < 0) return;
    const [o] = this.state.orders.splice(i, 1);
    o.status = reason;
    o.closed = Date.now();
    this.state.orderHistory.unshift(o);
    this.state.orderHistory.length = Math.min(this.state.orderHistory.length, 200);
    this.save();
    this.emit("change");
  }

  modifyOrderPrice(id, price) {
    const o = this.state.orders.find((x) => x.id === id);
    if (!o || !(price > 0)) return;
    if (o.type === "limit") o.limitPrice = price;
    else o.stopPrice = price;
    this.save();
    this.emit("change");
  }

  closePosition(sym) {
    const pos = this.position(sym);
    if (!pos) return { ok: false, msg: "Keine Position." };
    // zugehörige Verkaufsorders (SL/TP) zuerst entfernen
    for (const o of [...this.state.orders]) if (o.symbol === sym && o.side === "sell") this.cancelOrder(o.id);
    return this.placeOrder({ symbol: sym, side: "sell", type: "market", qty: pos.qty });
  }

  fill(order, price) {
    const s = this.state;
    const sym = order.symbol;
    let pnl = null;
    let held = null; // Haltedauer und Einstand fürs Trader-Profil (Jarvis)
    let entry = null;
    const { orderFee, ideaFee, total: fee } = this.costs(order.qty, price, order.ideaFeePct || 0);
    if (order.side === "buy") {
      const cost = order.qty * price;
      if (cost + fee > s.cash + 1e-6) {
        this.reject(order, "abgelehnt: Guthaben");
        return;
      }
      s.cash -= cost + fee;
      const p = s.positions[sym] || { qty: 0, avg: 0, realized: 0, opened: Date.now() };
      // Einstandskurs inklusive Gebühr
      p.avg = (p.avg * p.qty + cost + fee) / (p.qty + order.qty);
      p.qty += order.qty;
      s.positions[sym] = p;
    } else {
      const p = s.positions[sym];
      if (!p || p.qty < order.qty) {
        this.reject(order, "abgelehnt: Bestand");
        return;
      }
      s.cash += order.qty * price - fee;
      held = Date.now() - (p.opened || Date.now());
      entry = p.avg;
      pnl = (price - p.avg) * order.qty - fee;
      p.realized += pnl;
      s.realized += pnl;
      p.qty -= order.qty;
      if (p.qty === 0) delete s.positions[sym];
    }

    s.fees = (s.fees || 0) + fee;
    const fill = { id: uid(), orderId: order.id, symbol: sym, side: order.side, type: order.type, qty: order.qty, price, fee, orderFee, ideaFee, ideaId: order.ideaId || null, pnl, held, entry, ts: Date.now(), time: nowSec() };
    s.fills.unshift(fill);
    s.fills.length = Math.min(s.fills.length, 500);
    order.status = "ausgeführt";
    order.fillPrice = price;
    order.closed = Date.now();
    s.orderHistory.unshift(order);
    s.orderHistory.length = Math.min(s.orderHistory.length, 200);

    // Stop-Loss / Take-Profit als OCO-Paar anlegen
    if (order.side === "buy" && (order.sl || order.tp)) {
      const oco = order.sl && order.tp ? uid() : null;
      const base = { symbol: sym, side: "sell", qty: order.qty, sl: null, tp: null, oco, created: Date.now(), status: "open", parent: order.id };
      if (order.sl) s.orders.push({ ...base, id: uid(), type: "stop", stopPrice: order.sl, limitPrice: null, tag: "SL" });
      if (order.tp) s.orders.push({ ...base, id: uid(), type: "limit", limitPrice: order.tp, stopPrice: null, tag: "TP" });
    }
    // OCO: Gegenstück stornieren
    if (order.oco) {
      for (const o of [...s.orders]) if (o.oco === order.oco && o.id !== order.id) this.cancelOrder(o.id, "storniert (OCO)");
    }

    this.save();
    this.emit("fill", fill);
    this.emit("change");
  }

  reject(order, reason) {
    const i = this.state.orders.indexOf(order);
    if (i >= 0) this.state.orders.splice(i, 1);
    order.status = reason;
    order.closed = Date.now();
    this.state.orderHistory.unshift(order);
    this.save();
    this.emit("reject", order);
    this.emit("change");
  }

  // Gutschrift (z. B. Royalties aus der Ideen-Börse)
  credit(amount, note) {
    this.state.cash += amount;
    this.state.royalties = (this.state.royalties || 0) + amount;
    this.save();
    this.emit("change", { credit: amount, note });
  }

  // Ein- und Auszahlungen: verändern das Guthaben, zählen aber nicht zur Rendite
  deposit(amount, meta = {}) {
    this.state.cash += amount;
    this.state.netDeposits = (this.state.netDeposits || 0) + amount;
    this.state.transfers = [{ id: uid(), type: "in", amount, at: Date.now(), ...meta }, ...(this.state.transfers || [])].slice(0, 100);
    this.save();
    this.emit("change", { deposit: amount });
  }
  withdraw(amount, meta = {}) {
    if (!(amount > 0)) return { ok: false, msg: "Bitte einen Betrag eingeben." };
    if (amount > this.buyingPower() + 1e-6) return { ok: false, msg: `Verfügbar sind höchstens ${this.buyingPower().toLocaleString("de-DE", { style: "currency", currency: "EUR" })}. Offene Orders reservieren Guthaben.` };
    this.state.cash -= amount;
    this.state.netDeposits = (this.state.netDeposits || 0) - amount;
    this.state.transfers = [{ id: uid(), type: "out", amount, at: Date.now(), ...meta }, ...(this.state.transfers || [])].slice(0, 100);
    this.save();
    this.emit("change", { withdraw: amount });
    return { ok: true };
  }
  // Eingesetztes Kapital: Startguthaben plus Einzahlungen minus Auszahlungen
  invested() {
    return START_CASH + (this.state.netDeposits || 0);
  }

  // ---------- Alarme ----------
  addAlert(symbol, price, note = "") {
    const cur = this.market.get(symbol).price;
    const a = { id: uid(), symbol, price, dir: price >= cur ? "above" : "below", note, active: true, created: Date.now() };
    this.state.alerts.unshift(a);
    this.save();
    this.emit("change");
    return a;
  }
  removeAlert(id) {
    this.state.alerts = this.state.alerts.filter((a) => a.id !== id);
    this.save();
    this.emit("change");
  }

  // ---------- Live-Abgleich ----------
  onTick() {
    const s = this.state;
    for (const o of [...s.orders]) {
      if (!s.orders.includes(o)) continue; // durch OCO bereits entfernt
      const q = this.market.quote(o.symbol);
      let px = null;
      if (o.type === "limit") {
        if (o.side === "buy" && q.ask <= o.limitPrice) px = q.ask;
        if (o.side === "sell" && q.bid >= o.limitPrice) px = q.bid;
      } else if (o.type === "stop") {
        if (o.side === "buy" && q.ask >= o.stopPrice) px = q.ask;
        if (o.side === "sell" && q.bid <= o.stopPrice) px = q.bid;
      }
      if (px != null) {
        s.orders.splice(s.orders.indexOf(o), 1);
        this.fill(o, px);
      }
    }

    let alertChanged = false;
    for (const a of s.alerts) {
      if (!a.active) continue;
      const p = this.market.get(a.symbol).price;
      if ((a.dir === "above" && p >= a.price) || (a.dir === "below" && p <= a.price)) {
        a.active = false;
        a.triggered = Date.now();
        alertChanged = true;
        this.emit("alert", a);
      }
    }
    if (alertChanged) {
      this.save();
      this.emit("change");
    }

    // Equity-Kurve alle 15 Sekunden fortschreiben
    const t = Date.now();
    const last = s.equityCurve[s.equityCurve.length - 1];
    if (!last || t - last.ts >= 15000) {
      s.equityCurve.push({ ts: t, time: nowSec(), value: this.equity() });
      if (s.equityCurve.length > 3000) s.equityCurve.shift();
      this.save();
    }
  }
}
