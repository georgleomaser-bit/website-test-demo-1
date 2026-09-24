// Test-Server, der den Broker-/Kursdaten-Server aus GO-LIVE.md nachbildet – nur zum Entwickeln und Testen.
// Er bewegt kein echtes Geld. Start: node server/mock-broker.mjs  (Port 8787)
// Dann in js/config.js: trading.apiBase = "http://localhost:8787",
// marketData.streamUrl = "http://localhost:8787/stream", marketData.historyUrl = "http://localhost:8787/history"
import http from "node:http";
import { STOCKS } from "../js/data.js";

const PORT = +process.env.PORT || 8787;
const DAY = 86400;
const price = Object.fromEntries(STOCKS.map((s) => [s.s, s.p]));
const accounts = new Map(); // sid -> Konto
const uid = () => Math.random().toString(36).slice(2, 10);

function account(sid) {
  if (!accounts.has(sid)) accounts.set(sid, { user: { name: "Test Kunde", email: "kunde@example.com" }, cash: 0, positions: {}, orders: [], orderHistory: [], fills: [], realized: 0, fees: 0, netDeposits: 0, transfers: [] });
  return accounts.get(sid);
}
function fill(acc, o, px) {
  const cost = o.qty * px;
  if (o.side === "buy") {
    if (cost > acc.cash) return reject(acc, o, "Nicht genügend Guthaben.");
    acc.cash -= cost;
    const p = acc.positions[o.symbol] || { qty: 0, avg: 0, realized: 0 };
    p.avg = (p.avg * p.qty + cost) / (p.qty + o.qty);
    p.qty += o.qty;
    acc.positions[o.symbol] = p;
  } else {
    const p = acc.positions[o.symbol];
    if (!p || p.qty < o.qty) return reject(acc, o, "Nicht genügend Stück im Depot.");
    const pnl = (px - p.avg) * o.qty;
    p.qty -= o.qty;
    p.realized += pnl;
    acc.realized += pnl;
    acc.cash += cost;
    if (!p.qty) delete acc.positions[o.symbol];
  }
  Object.assign(o, { status: "ausgeführt", fillPrice: px, closed: Date.now() });
  acc.orderHistory.unshift(o);
  acc.fills.push({ id: uid(), orderId: o.id, symbol: o.symbol, side: o.side, qty: o.qty, price: px, ts: Date.now(), fee: 0 });
  return { ok: true, order: o };
}
function reject(acc, o, msg) {
  Object.assign(o, { status: msg, closed: Date.now() });
  acc.orderHistory.unshift(o);
  return { ok: false, msg };
}
// Zufallskurse für den Test-Stream
setInterval(() => {
  for (const s of STOCKS) price[s.s] *= Math.exp((Math.random() - 0.5) * 0.002);
  for (const acc of accounts.values())
    for (const o of [...acc.orders]) {
      const px = price[o.symbol];
      const hit = o.type === "limit" ? (o.side === "buy" ? px <= o.limitPrice : px >= o.limitPrice) : o.side === "buy" ? px >= o.stopPrice : px <= o.stopPrice;
      if (hit) {
        acc.orders.splice(acc.orders.indexOf(o), 1);
        fill(acc, o, px);
      }
    }
}, 500);
function history(sym) {
  let p = price[sym];
  const now = Math.floor(Date.now() / 1000);
  const days = [];
  for (let i = 400; i >= 0; i--) {
    const o = p;
    p = p / Math.exp((Math.random() - 0.5) * 0.03);
    days.unshift({ time: Math.floor(now / DAY) * DAY - i * DAY, open: p, high: Math.max(o, p) * 1.005, low: Math.min(o, p) * 0.995, close: o, volume: 1e6 });
  }
  days.forEach((d, i) => (d.time = (Math.floor(now / DAY) - (days.length - 1 - i)) * DAY));
  const m1 = [];
  let q = price[sym];
  for (let i = 0; i < 600; i++) {
    const c = q;
    q = q / Math.exp((Math.random() - 0.5) * 0.002);
    m1.unshift({ time: (Math.floor(now / 60) - i) * 60, open: q, high: Math.max(q, c), low: Math.min(q, c), close: c, volume: 1000 });
  }
  days[days.length - 1].close = price[sym];
  return { m1, days };
}

const json = (res, code, data) => {
  res.writeHead(code, { "Content-Type": "application/json" });
  res.end(JSON.stringify(data));
};
const body = (req) => new Promise((r) => { let d = ""; req.on("data", (c) => (d += c)); req.on("end", () => { try { r(JSON.parse(d || "{}")); } catch { r({}); } }); });

http
  .createServer(async (req, res) => {
    const url = new URL(req.url, `http://${req.headers.host}`);
    const origin = req.headers.origin;
    if (origin) res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Access-Control-Allow-Credentials", "true");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");
    if (req.method === "OPTIONS") return res.end();
    const sid = /sid=([a-z0-9]+)/.exec(req.headers.cookie || "")?.[1];

    if (url.pathname === "/history") return json(res, 200, history(url.searchParams.get("symbol")));
    if (url.pathname === "/stream") {
      res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", Connection: "keep-alive" });
      const t = setInterval(() => res.write(`data: ${JSON.stringify(STOCKS.map((s) => ({ s: s.s, p: +price[s.s].toFixed(4), v: Math.round(Math.random() * 500), t: Date.now() })))}\n\n`), 500);
      return req.on("close", () => clearInterval(t));
    }
    if (url.pathname === "/auth/login") {
      // Hier würde der Partner Login, Identifizierung (KYC) und Depoteröffnung durchführen
      res.writeHead(302, { "Set-Cookie": `sid=${uid()}; Path=/; HttpOnly; SameSite=Lax`, Location: url.searchParams.get("return") || "/" });
      return res.end();
    }
    if (!sid) return json(res, 401, { ok: false, msg: "Nicht angemeldet" });
    const acc = account(sid);

    if (url.pathname === "/account" && req.method === "GET") return json(res, 200, acc);
    if (url.pathname === "/orders" && req.method === "POST") {
      const b = await body(req);
      const o = { id: uid(), symbol: b.symbol, side: b.side === "sell" ? "sell" : "buy", type: b.type || "market", qty: Math.floor(+b.qty), limitPrice: b.limitPrice ?? null, stopPrice: b.stopPrice ?? null, created: Date.now(), status: "open" };
      if (!price[o.symbol] || !(o.qty > 0)) return json(res, 400, { ok: false, msg: "Ungültige Order." });
      if (o.type === "market") {
        const r = fill(acc, o, price[o.symbol]);
        return json(res, r.ok ? 200 : 400, r);
      }
      acc.orders.push(o);
      return json(res, 200, { ok: true, order: o });
    }
    const m = url.pathname.match(/^\/orders\/(\w+)$/);
    if (m) {
      const o = acc.orders.find((x) => x.id === m[1]);
      if (!o) return json(res, 404, { ok: false, msg: "Order nicht gefunden." });
      if (req.method === "DELETE") {
        acc.orders.splice(acc.orders.indexOf(o), 1);
        Object.assign(o, { status: "storniert", closed: Date.now() });
        acc.orderHistory.unshift(o);
      } else if (req.method === "PATCH") {
        const { price: p } = await body(req);
        if (o.type === "limit") o.limitPrice = p;
        else o.stopPrice = p;
      }
      return json(res, 200, { ok: true, order: o });
    }
    if (url.pathname === "/transfers" && req.method === "POST") {
      const b = await body(req);
      const amount = +b.amount;
      if (!(amount > 0)) return json(res, 400, { ok: false, msg: "Ungültiger Betrag." });
      if (b.type === "out" && amount > acc.cash) return json(res, 400, { ok: false, msg: "Nicht genügend Guthaben." });
      acc.cash += b.type === "out" ? -amount : amount;
      acc.netDeposits += b.type === "out" ? -amount : amount;
      acc.transfers.unshift({ id: uid(), type: b.type === "out" ? "out" : "in", amount, method: b.method, at: Date.now() });
      // Ein echter Partner gäbe hier z. B. { redirectUrl } zu seiner Bezahlseite zurück
      return json(res, 200, { ok: true });
    }
    json(res, 404, { ok: false, msg: "Unbekannter Pfad" });
  })
  .listen(PORT, () => console.log(`AKYTEX Test-Broker läuft auf http://localhost:${PORT}`));
