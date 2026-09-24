// AKYTEX Echtbetrieb: verbindet die App mit dem Server des Broker-Partners und dem Kursdaten-Anbieter.
// Nur aktiv, wenn in js/config.js die Adressen eingetragen sind. API-Vertrag: GO-LIVE.md
import { CONFIG, LIVE } from "./config.js";
import { toLocalSec } from "./market.js";

// Anfragen an den Broker-Server; Anmeldung über ein Sitzungs-Cookie des Servers
export async function api(method, path, body) {
  const res = await fetch(CONFIG.trading.apiBase.replace(/\/$/, "") + path, {
    method,
    credentials: "include",
    headers: body ? { "Content-Type": "application/json" } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  if (res.status === 401) throw Object.assign(new Error("Bitte anmelden."), { code: "auth" });
  if (!res.ok || data.ok === false) throw Object.assign(new Error(data.msg || `Serverfehler (${res.status})`), { code: "api" });
  return data;
}
export const loginUrl = () => `${CONFIG.trading.apiBase.replace(/\/$/, "")}/auth/login?return=${encodeURIComponent(location.href.split("#")[0])}`;

// Echte Kurse: Historie laden, dann Live-Stream (Server-Sent Events)
export async function connectMarket(market, onStatus = () => {}) {
  if (!LIVE.data) return false;
  const base = CONFIG.marketData.historyUrl;
  let loaded = 0;
  await Promise.all(
    market.list.map(async (st) => {
      try {
        const r = await fetch(`${base}?symbol=${encodeURIComponent(st.s)}`, { credentials: "include" });
        // Minutenkerzen kommen in UTC-Sekunden, Tageskerzen mit dem Datum um 00:00 UTC
        const h = r.ok ? await r.json() : null;
        if (h && market.loadHistory(st.s, { m1: (h.m1 || []).map((b) => ({ ...b, time: toLocalSec(b.time * 1000) })), days: h.days || [] })) loaded++;
      } catch (_) {
        /* Symbol ohne Daten bleibt unverändert */
      }
    })
  );
  market.useFeed();
  const open = () => {
    const es = new EventSource(CONFIG.marketData.streamUrl, { withCredentials: true });
    es.onopen = () => onStatus("live");
    es.onmessage = (e) => {
      try {
        const m = JSON.parse(e.data);
        for (const q of Array.isArray(m) ? m : [m]) market.applyTrade(q.s, +q.p, +q.v || 0, +q.t || Date.now());
      } catch (_) {
        /* ungültige Nachricht ignorieren */
      }
    };
    es.onerror = () => onStatus("reconnecting"); // EventSource verbindet sich selbst neu
  };
  open();
  onStatus(loaded ? "live" : "nohistory");
  return true;
}

// Echtes Depot: Der Broker-Server ist die Quelle der Wahrheit. Die App zeigt seinen Stand
// und schickt Orders, Stornos und Überweisungen an ihn statt sie selbst auszuführen.
export function connectBroker(broker, onStatus = () => {}) {
  if (!LIVE.trading) return null;
  broker.live = true;
  // Demo-Depot ausblenden, bis der Server den echten Stand liefert
  broker.state = { ...broker.state, cash: 0, positions: {}, orders: [], orderHistory: [], fills: [], realized: 0, fees: 0, netDeposits: 0, transfers: [], equityCurve: [] };
  broker.onTick = liveAlertsOnly(broker);
  broker.save = () => {}; // nichts lokal speichern – der Server führt das Depot
  const known = new Set();
  const sync = async () => {
    try {
      const acc = await api("GET", "/account");
      const prevFills = broker.state.fills?.length || 0;
      Object.assign(broker.state, {
        cash: acc.cash,
        positions: acc.positions || {},
        orders: acc.orders || [],
        orderHistory: acc.orderHistory || [],
        fills: acc.fills || [],
        realized: acc.realized || 0,
        fees: acc.fees || 0,
        netDeposits: acc.netDeposits || 0,
        transfers: acc.transfers || [],
      });
      broker.user = acc.user || null;
      // neue Ausführungen melden
      for (const f of (acc.fills || []).slice(0, Math.max(0, (acc.fills || []).length - prevFills))) if (!known.has(f.id)) broker.emit("fill", f);
      for (const f of acc.fills || []) known.add(f.id);
      broker.emit("change");
      onStatus("live", broker.user);
    } catch (e) {
      onStatus(e.code === "auth" ? "login" : "offline");
    }
  };
  broker.sync = sync;
  broker.placeOrder = (o) => {
    const order = { ...o, qty: Math.floor(Number(o.qty)), status: "wird gesendet", created: Date.now() };
    if (!(order.qty > 0)) return { ok: false, msg: "Bitte eine gültige Stückzahl eingeben." };
    api("POST", "/orders", order)
      .then((r) => (r.order?.status === "open" ? broker.emit("placed", r.order) : null))
      .catch((e) => broker.emit("reject", { ...order, status: e.message }))
      .finally(sync);
    return { ok: true, order, pending: true };
  };
  broker.cancelOrder = (id) => api("DELETE", `/orders/${encodeURIComponent(id)}`).catch((e) => broker.emit("reject", { symbol: "", status: e.message })).finally(sync);
  broker.modifyOrderPrice = (id, price) => api("PATCH", `/orders/${encodeURIComponent(id)}`, { price }).catch((e) => broker.emit("reject", { symbol: "", status: e.message })).finally(sync);
  broker.reset = () => {};
  broker.credit = () => {};
  broker.invested = () => broker.state.netDeposits || broker.equity() || 1;
  // Ein-/Auszahlungen: Der Server liefert ggf. eine Bezahlseite (Karte, Wallet, Lastschrift) zum Weiterleiten
  broker.requestTransfer = async (t) => {
    const r = await api("POST", "/transfers", t);
    if (r.redirectUrl) location.href = r.redirectUrl;
    await sync();
    return r;
  };
  sync();
  setInterval(sync, 5000);
  return sync;
}

// Im Echtbetrieb führt die Börse Orders aus – lokal werden nur noch Preisalarme geprüft
function liveAlertsOnly(broker) {
  return () => {
    let changed = false;
    for (const a of broker.state.alerts || []) {
      if (!a.active) continue;
      const p = broker.market.get(a.symbol).price;
      if ((a.dir === "above" && p >= a.price) || (a.dir === "below" && p <= a.price)) {
        a.active = false;
        a.triggered = Date.now();
        broker.emit("alert", a);
        changed = true;
      }
    }
    if (changed) broker.emit("change");
  };
}
