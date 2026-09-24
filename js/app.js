// Akytex – App-Steuerung (UI, Views, Order-Ticket, PWA)
import { STOCKS, DEFAULT_WATCHLIST } from "./data.js";
import { Market, TIMEFRAMES, tickStep, toLocalSec, aggregate } from "./market.js";
import { Broker, START_CASH } from "./broker.js";
import { ChartView, CHART_TYPES, INDICATORS } from "./chart.js";
import { analyze } from "./analysis.js";
import { PLANS, ADDONS, planById, planPrice } from "./plans.js";
import { Community } from "./community.js";
import { AkytexAI, STRATEGIES } from "./ai.js";
import * as lab from "./ailab.js";
import { Scheduler, CONDITIONS, EVERY, WEEKDAYS } from "./scheduler.js";
import { Shop, BASKETS, PRODUCTS, CATS } from "./shop.js";
import { demoClips, drawClip, recordClip, idbAll, idbPut, idbDel, CLIP_MS } from "./clips.js";
import { PAYMENT_CONFIG, TEST_CARDS, TEST_IBAN, cardBrand, luhn, formatCard, quote, stripeLinkFor, AccountStore } from "./payments.js";

// ---------- Hilfsfunktionen ----------
const $ = (s, root = document) => root.querySelector(s);
const $$ = (s, root = document) => [...root.querySelectorAll(s)];
const nf2 = new Intl.NumberFormat("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const eurF = new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR" });
const num = (v) => nf2.format(v);
const eur = (v) => eurF.format(v);
const sEur = (v) => (v > 0 ? "+" : "") + eurF.format(v);
const sNum = (v) => (v > 0 ? "+" : "") + nf2.format(v);
const pct = (v) => (v > 0 ? "+" : "") + nf2.format(v * 100) + " %";
const cls = (v) => (v > 0 ? "up" : v < 0 ? "down" : "");
const compact = (v) => (v >= 1e12 ? num(v / 1e12) + " Bio." : v >= 1e9 ? num(v / 1e9) + " Mrd." : v >= 1e6 ? num(v / 1e6) + " Mio." : v >= 1e3 ? num(v / 1e3) + " Tsd." : String(Math.round(v)));
const clock = (ms) => new Date(ms).toLocaleTimeString("de-DE");
const dateTime = (ms) => new Date(ms).toLocaleString("de-DE", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit" });
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const roundTo = (v, step) => Math.round(v / step) * step;

const SETTINGS_KEY = "akytex-v2-settings";
function loadSettings() {
  try {
    return JSON.parse(localStorage.getItem(SETTINGS_KEY)) || {};
  } catch (_) {
    return {};
  }
}
function saveSettings() {
  try {
    localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
  } catch (_) {
    /* ignorieren */
  }
}

// ---------- Zustand ----------
const VIEWS = ["home", "chart", "markets", "ideas", "clips", "ai", "shop", "portfolio", "business", "account", "legal"];
const market = new Market();
const broker = new Broker(market);
const firstVisit = (() => {
  try {
    return !localStorage.getItem(SETTINGS_KEY);
  } catch (_) {
    return true;
  }
})();
const saved = loadSettings();
// Deep-Links: ?symbol=SAP&tf=1h&view=chart oder kurz #SAP.1h / #markets
function parseLink() {
  const q = new URLSearchParams(location.search);
  const out = { symbol: q.get("symbol"), tf: q.get("tf"), view: q.get("view") };
  const h = decodeURIComponent(location.hash.slice(1));
  if (/^[A-Za-z0-9~_-]+(\.[A-Za-z0-9]+)?$/.test(h)) {
    if (VIEWS.includes(h)) out.view = h;
    else {
      const [sym, tf] = h.split(".");
      if (market.has(sym.toUpperCase())) {
        out.symbol = sym.toUpperCase();
        out.view ||= "chart";
      }
      if (tf) out.tf = TIMEFRAMES.find((t) => t.id.toLowerCase() === tf.toLowerCase())?.id || null;
    }
  }
  return out;
}
const params = { ...parseLink(), get(k) { return this[k] ?? null; }, has(k) { return this[k] != null; } };
const embedded = (() => {
  try {
    return window.top !== window;
  } catch (_) {
    return true;
  }
})();
const settings = {
  symbol: market.has(params.get("symbol")) ? params.get("symbol") : market.has(saved.symbol) ? saved.symbol : "AAPL",
  tf: TIMEFRAMES.some((t) => t.id === params.get("tf")) ? params.get("tf") : TIMEFRAMES.some((t) => t.id === saved.tf) ? saved.tf : "15m",
  type: CHART_TYPES.some((t) => t.id === saved.type) ? saved.type : "candles",
  indicators: Array.isArray(saved.indicators) ? saved.indicators : ["vol", "sma20", "sma50"],
  theme: saved.theme || (matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark"),
  watchlist: (Array.isArray(saved.watchlist) ? saved.watchlist : DEFAULT_WATCHLIST).filter((s) => market.has(s)),
  view: VIEWS.includes(params.get("view")) ? params.get("view") : params.has("symbol") ? "chart" : firstVisit ? "home" : "chart",
  plan: PLANS.some((p) => p.id === saved.plan) ? saved.plan : "free",
  billing: saved.billing === "monthly" ? "monthly" : "yearly",
  addons: Array.isArray(saved.addons) ? saved.addons.filter((a) => ADDONS.some((x) => x.id === a)) : [],
};

const community = new Community(market);
broker.feeFn = () => planById(settings.plan).fee;
const plan = () => planById(settings.plan);
const planTitle = (p) => (p.name.startsWith("AKYTEX") ? p.name : "AKYTEX " + p.name);
const aiEngine = new AkytexAI(market, broker);
const aiMode = () => plan().limits.ai || null; // null | "assist" | "auto"
const scheduler = new Scheduler(market, broker);
const shop = new Shop(market);
const hasAddon = (id) => settings.addons.includes(id) || ADDONS.find((a) => a.id === id).includedIn.includes(settings.plan);

const ui = { ideaFilter: "all", ideaDir: "long", copyTrader: null, side: "buy", otype: "market", rtab: "watch", btab: "positions", hmPeriod: 1, sort: { key: "cap", dir: -1 } };

document.documentElement.dataset.theme = settings.theme;

const chart = new ChartView({
  container: $("#chart"),
  legend: $("#legend"),
  market,
  broker,
  onToolDone: () => setToolButtons("cursor"),
  onAlertAt: (sym, price) => openAlertModal(sym, price),
  onHint: (text) => {
    const h = $("#draw-hint");
    h.textContent = text;
    h.hidden = !text;
  },
});

// ---------- Toasts, Ton, Benachrichtigungen ----------
const notifs = [];
let notifUnread = 0;
function toast(msg, type = "info", title = "") {
  notifs.unshift({ ts: Date.now(), msg, type, title });
  notifs.length = Math.min(notifs.length, 40);
  notifUnread++;
  syncNotifBadge();
  const el = document.createElement("div");
  el.className = `toast ${type}`;
  el.innerHTML = `${title ? `<b>${esc(title)}</b>` : ""}<span>${esc(msg)}</span>`;
  $("#toasts").appendChild(el);
  requestAnimationFrame(() => el.classList.add("show"));
  const kids = $("#toasts").children;
  if (kids.length > 3) kids[0].remove();
  setTimeout(() => {
    el.classList.add("hide");
    setTimeout(() => el.remove(), 450);
  }, 3800);
}

let audioCtx;
function beep(freq = 880, dur = 0.12) {
  try {
    audioCtx ||= new (window.AudioContext || window.webkitAudioContext)();
    const o = audioCtx.createOscillator();
    const g = audioCtx.createGain();
    o.frequency.value = freq;
    g.gain.setValueAtTime(0.08, audioCtx.currentTime);
    g.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + dur);
    o.connect(g).connect(audioCtx.destination);
    o.start();
    o.stop(audioCtx.currentTime + dur);
  } catch (_) {
    /* kein Audio */
  }
}

function notify(title, body) {
  try {
    if ("Notification" in window && Notification.permission === "granted") {
      if (navigator.serviceWorker?.controller) {
        navigator.serviceWorker.ready.then((reg) => reg.showNotification(title, { body, icon: "icons/icon-192.png", badge: "icons/icon-192.png" }));
      } else new Notification(title, { body, icon: "icons/icon-192.png" });
    }
  } catch (_) {
    /* Benachrichtigungen nicht verfügbar */
  }
}

// ---------- Kopfzeile ----------
function buildToolbar() {
  $("#tf-group").innerHTML = TIMEFRAMES.map((t) => `<button class="tb-btn tf" data-tf="${t.id}">${t.label}</button>`).join("");
  $("#chart-type").innerHTML = CHART_TYPES.map((t) => `<option value="${t.id}">${t.label}</option>`).join("");
  $("#tf-group").addEventListener("click", (e) => {
    const b = e.target.closest("[data-tf]");
    if (b) setTimeframe(b.dataset.tf);
  });
  $("#chart-type").addEventListener("change", (e) => {
    settings.type = e.target.value;
    saveSettings();
    chart.configure({ type: settings.type });
  });
  $("#sym-btn").addEventListener("click", openSearch);
  $("#ind-btn").addEventListener("click", openIndicators);
  $("#alert-btn").addEventListener("click", () => openAlertModal(settings.symbol, market.get(settings.symbol).price));
  $("#shot-btn").addEventListener("click", () => {
    const canvas = chart.screenshot();
    const a = document.createElement("a");
    a.download = `akytex-${settings.symbol}-${settings.tf}.png`;
    a.href = canvas.toDataURL("image/png");
    a.click();
  });
  $("#theme-btn").addEventListener("click", () => {
    settings.theme = settings.theme === "dark" ? "light" : "dark";
    document.documentElement.dataset.theme = settings.theme;
    $('meta[name="theme-color"]').content = settings.theme === "dark" ? "#03040a" : "#ffffff";
    saveSettings();
    chart.configure({ theme: settings.theme });
    if (equityChart) buildEquityChart();
  });
  $$(".view-btn").forEach((b) => b.addEventListener("click", () => setView(b.dataset.view)));
}

function syncToolbar() {
  $$("#tf-group [data-tf]").forEach((b) => b.classList.toggle("active", b.dataset.tf === settings.tf));
  $("#chart-type").value = settings.type;
  $("#sym-label").textContent = settings.symbol;
  document.title = `${settings.symbol} ${num(market.get(settings.symbol).price)} · Akytex`;
}

function setTimeframe(tf) {
  settings.tf = tf;
  saveSettings();
  chart.configure({ tf });
  syncToolbar();
}

function setSymbol(sym) {
  if (!market.has(sym)) return;
  settings.symbol = sym;
  saveSettings();
  chart.configure({ symbol: sym });
  syncToolbar();
  renderQuoteCard();
  renderWatchlistSelection();
  resetTicketPrices();
  renderTicket();
  renderRightPanel();
  if (settings.view !== "chart") setView("chart");
}

function setView(view) {
  const changed = settings.view !== view;
  if (changed && document.startViewTransition && !matchMedia("(prefers-reduced-motion: reduce)").matches) {
    document.startViewTransition(() => applyView(view));
    return;
  }
  applyView(view, changed);
}
function applyView(view, animate = true) {
  settings.view = view;
  saveSettings();
  $$(".view-btn").forEach((b) => b.classList.toggle("active", b.dataset.view === view));
  for (const v of VIEWS) $("#view-" + v).hidden = v !== view;
  window.scrollTo({ top: 0 });
  document.body.dataset.view = view;
  const el = $("#view-" + view);
  if (animate) {
    el.classList.remove("entering");
    void el.offsetWidth;
    el.classList.add("entering");
    setTimeout(() => el.classList.remove("entering"), 900);
  }
  if (view === "markets") renderMarkets(true);
  if (view === "portfolio") renderPortfolio(true);
  if (view === "home") renderHome(true);
  if (view === "ideas") renderIdeas();
  if (view === "business") renderBusiness(true);
  if (view === "ai") renderAIView(true);
  if (view === "account") renderAccount();
  if (view === "shop") renderShop();
  if (view === "clips") renderClips();
  else pauseClips();
  if (view === "legal") renderLegal();
  heroAnim(view === "home");
}

// ---------- Laufband ----------
function buildTicker() {
  const items = STOCKS.map((s) => `<span class="tk" data-sym="${s.s}"><b>${s.s}</b> <span class="p"></span> <span class="c"></span></span>`).join("");
  $("#ticker").innerHTML = items + items; // doppelt für nahtlose Schleife
  $("#ticker").addEventListener("click", (e) => {
    const t = e.target.closest("[data-sym]");
    if (t) setSymbol(t.dataset.sym);
  });
}
function renderTicker() {
  for (const el of $$("#ticker .tk")) {
    const q = market.quote(el.dataset.sym);
    el.querySelector(".p").textContent = num(q.price);
    const c = el.querySelector(".c");
    c.textContent = pct(q.changePct);
    c.className = `c ${cls(q.changePct)}`;
  }
}

// ---------- Quote-Karte ----------
function renderQuoteCard() {
  const q = market.quote(settings.symbol);
  const pos = broker.position(settings.symbol);
  const inWl = settings.watchlist.includes(settings.symbol);
  $("#quote-card").innerHTML = `
    <div class="qc-top">
      <div>
        <div class="qc-sym">${q.symbol} <button class="star ${inWl ? "on" : ""}" id="qc-star" title="${inWl ? "Von Watchlist entfernen" : "Zur Watchlist hinzufügen"}">★</button></div>
        <div class="qc-name">${esc(q.name)} · ${q.exchange} · EUR</div>
      </div>
      <div class="qc-px">
        <div class="big" id="qc-price">${num(q.price)}</div>
        <div class="${cls(q.change)}" id="qc-chg">${sNum(q.change)} (${pct(q.changePct)})</div>
      </div>
    </div>
    <div class="qc-range">
      <span>${num(q.low)}</span>
      <div class="bar"><i id="qc-range-dot" style="left:${rangePos(q)}%"></i></div>
      <span>${num(q.high)}</span>
    </div>
    <div class="qc-grid">
      <div><span>Eröffnung</span><b id="qc-open">${num(q.open)}</b></div>
      <div><span>Vortag</span><b>${num(q.prevClose)}</b></div>
      <div><span>Volumen</span><b id="qc-vol">${compact(q.volume)}</b></div>
      <div><span>Marktkap.</span><b id="qc-cap">${compact(q.marketCap)}</b></div>
      <div><span>52W Hoch</span><b>${num(q.high52)}</b></div>
      <div><span>52W Tief</span><b>${num(q.low52)}</b></div>
      <div><span>KGV</span><b>${q.pe ? num(q.pe) : "–"}</b></div>
      <div><span>Div.-Rendite</span><b>${num(q.dy)} %</b></div>
    </div>
    ${pos ? `<div class="qc-pos">Position: <b>${pos.qty} Stk.</b> · Ø ${num(pos.avg)} · <b class="${cls(q.price - pos.avg)}" id="qc-pl">${sEur((q.price - pos.avg) * pos.qty)}</b></div>` : ""}`;
  $("#qc-star").addEventListener("click", () => toggleWatch(settings.symbol));
}
function rangePos(q) {
  return q.high === q.low ? 50 : ((q.price - q.low) / (q.high - q.low)) * 100;
}
function updateQuoteCard() {
  const q = market.quote(settings.symbol);
  const pe = $("#qc-price");
  if (!pe) return;
  flash(pe, q.price, q.prev);
  odometer(pe, num(q.price));
  const c = $("#qc-chg");
  c.textContent = `${sNum(q.change)} (${pct(q.changePct)})`;
  c.className = cls(q.change);
  $("#qc-vol").textContent = compact(q.volume);
  $("#qc-cap").textContent = compact(q.marketCap);
  $("#qc-range-dot").style.left = rangePos(q) + "%";
  const pos = broker.position(settings.symbol);
  const pl = $("#qc-pl");
  if (pos && pl) {
    pl.textContent = sEur((q.price - pos.avg) * pos.qty);
    pl.className = cls(q.price - pos.avg);
  }
}

function flash(el, price, prev) {
  if (price === prev) return;
  el.classList.remove("fl-up", "fl-down");
  void el.offsetWidth;
  el.classList.add(price > prev ? "fl-up" : "fl-down");
}

// ---------- Watchlist ----------
function buildWatchlist() {
  $("#watch-body").innerHTML = settings.watchlist
    .map(
      (s) => `<tr data-sym="${s}">
        <td><b>${s}</b><button class="wl-x" data-rm="${s}" title="Entfernen">✕</button></td>
        <td class="num p"></td><td class="num c"></td><td class="num cp"></td></tr>`
    )
    .join("");
  renderWatchlistSelection();
  renderWatchlist();
}
function renderWatchlist() {
  for (const tr of $$("#watch-body tr")) {
    const q = market.quote(tr.dataset.sym);
    const p = tr.querySelector(".p");
    flash(p, q.price, q.prev);
    p.textContent = num(q.price);
    const c = tr.querySelector(".c");
    c.textContent = sNum(q.change);
    c.className = `num c ${cls(q.change)}`;
    const cp = tr.querySelector(".cp");
    cp.textContent = pct(q.changePct);
    cp.className = `num cp ${cls(q.change)}`;
  }
}
function renderWatchlistSelection() {
  $$("#watch-body tr").forEach((tr) => tr.classList.toggle("sel", tr.dataset.sym === settings.symbol));
}
function toggleWatch(sym) {
  const i = settings.watchlist.indexOf(sym);
  if (i >= 0) settings.watchlist.splice(i, 1);
  else settings.watchlist.push(sym);
  saveSettings();
  buildWatchlist();
  renderQuoteCard();
  if ($("#search-modal").classList.contains("open")) renderSearch();
}

// ---------- Orderbuch & Umsätze ----------
function renderRightPanel() {
  if (ui.rtab === "book") renderBook();
  if (ui.rtab === "tape") renderTape();
  if (ui.rtab === "ai") renderAI();
}
function renderBook() {
  const ob = market.orderBook(settings.symbol, 12);
  const depth = hasAddon("l2") ? 12 : plan().limits.depth;
  const max = Math.max(...ob.bids.map((l) => l.size), ...ob.asks.map((l) => l.size));
  const row = (l, side, i) =>
    i < depth
      ? `<div class="lvl ${side}" data-px="${l.price}"><i style="width:${(l.size / max) * 100}%"></i><span>${num(l.price)}</span><span>${compact(l.size)}</span></div>`
      : `<div class="lvl ${side} locked"><i style="width:${(l.size / max) * 100}%"></i><span>000,00</span><span>0.000</span></div>`;
  const lock = depth < 12 ? `<div class="book-lock"><b>🔒 ${12 - depth} weitere Ebenen je Seite</b><span>Level-2-Orderbuch: Add-on für 4,99 €/Monat – in Pro und Elite inklusive</span><button class="btn primary small" data-open-plans>Level 2 freischalten</button></div>` : "";
  $("#book").innerHTML = `
    <div class="book-head"><span>Preis</span><span>Stück</span></div>
    <div class="asks">${ob.asks.map((l, i) => row(l, "ask", i)).reverse().join("")}</div>
    <div class="book-mid"><b>${num(market.get(settings.symbol).price)}</b><span>Spread ${num(ob.spread)}</span></div>
    <div class="bids">${ob.bids.map((l, i) => row(l, "bid", i)).join("")}</div>${lock}`;
}
function renderTape() {
  $("#tape-body").innerHTML = market
    .get(settings.symbol)
    .trades.slice(0, 40)
    .map((t) => `<tr><td>${clock(t.ts)}</td><td class="num ${t.side === "buy" ? "up" : "down"}">${num(t.price)}</td><td class="num">${compact(t.size)}</td></tr>`)
    .join("");
}

// ---------- Order-Ticket ----------
function resetTicketPrices() {
  const q = market.quote(settings.symbol);
  const step = tickStep(q.price);
  $("#px").step = step;
  $("#sl").step = step;
  $("#tp").step = step;
  $("#px").value = roundTo(ui.otype === "stop" ? (ui.side === "buy" ? q.price * 1.01 : q.price * 0.99) : ui.side === "buy" ? q.bid : q.ask, step).toFixed(2);
  $("#sl").value = roundTo(q.price * 0.95, step).toFixed(2);
  $("#tp").value = roundTo(q.price * 1.1, step).toFixed(2);
}

function ticketEntryPrice() {
  const q = market.quote(settings.symbol);
  if (ui.otype === "market") return ui.side === "buy" ? q.ask : q.bid;
  return parseFloat($("#px").value) || 0;
}

function renderTicket() {
  const q = market.quote(settings.symbol);
  $("#bid-px").textContent = num(q.bid);
  $("#ask-px").textContent = num(q.ask);
  $("#spread").textContent = num(q.ask - q.bid);
  $$(".side-switch .side").forEach((b) => b.classList.toggle("active", b.dataset.side === ui.side));
  $$(".otype .ot").forEach((b) => b.classList.toggle("active", b.dataset.type === ui.otype));
  $("#px-field").hidden = ui.otype === "market";
  $("#px-label").textContent = ui.otype === "limit" ? "Limitpreis" : "Stopp-Preis";
  $("#bracket").hidden = ui.side !== "buy";

  const qty = parseInt($("#qty").value, 10) || 0;
  const entry = ticketEntryPrice();
  const total = qty * entry;
  $("#o-total").textContent = eur(total);
  const pos = broker.position(settings.symbol);
  if (ui.side === "buy") $("#o-bp").textContent = eur(broker.buyingPower());
  else $("#o-bp").textContent = `${Math.max(0, (pos?.qty || 0) - broker.reservedQty(settings.symbol))} Stk. frei`;
  $("#o-bp").previousElementSibling.textContent = ui.side === "buy" ? "Kaufkraft" : "Bestand";
  const fee = plan().fee;
  $("#o-fee").innerHTML = fee ? `${eur(fee)} <button type="button" class="fee-up" data-open-plans>0 € mit Pro</button>` : `<span class="up">0,00 € · ${plan().name}</span>`;
  const spreadCost = ui.otype === "market" ? ((q.ask - q.bid) / 2) * qty : 0;
  $("#o-spread").textContent = eur(spreadCost);
  $("#o-costs").textContent = eur(fee + spreadCost);

  const slOn = $("#sl-on").checked && ui.side === "buy";
  const tpOn = $("#tp-on").checked && ui.side === "buy";
  $("#sl").disabled = !slOn;
  $("#tp").disabled = !tpOn;
  const riskRow = $("#o-risk-row");
  riskRow.hidden = !(slOn || tpOn);
  if (slOn || tpOn) {
    const risk = slOn ? (entry - parseFloat($("#sl").value)) * qty : null;
    const reward = tpOn ? (parseFloat($("#tp").value) - entry) * qty : null;
    const crv = risk > 0 && reward > 0 ? ` · CRV ${nf2.format(reward / risk)}` : "";
    $("#o-risk").innerHTML = `${risk != null ? `<span class="down">${eur(-risk)}</span>` : "–"} / ${reward != null ? `<span class="up">${sEur(reward)}</span>` : "–"}${crv}`;
  }

  const btn = $("#o-submit");
  const typeLbl = { market: "", limit: " Limit", stop: " Stopp" }[ui.otype];
  btn.textContent = `${qty || ""} ${settings.symbol} ${ui.side === "buy" ? "kaufen" : "verkaufen"}${typeLbl}`.replace(/\s+/g, " ").trim();
  btn.className = `submit ${ui.side}`;
}

function bindTicket() {
  $$(".side-switch .side").forEach((b) =>
    b.addEventListener("click", () => {
      ui.side = b.dataset.side;
      resetTicketPrices();
      renderTicket();
    })
  );
  $$(".otype .ot").forEach((b) =>
    b.addEventListener("click", () => {
      ui.otype = b.dataset.type;
      resetTicketPrices();
      renderTicket();
    })
  );
  $("#ticket").addEventListener("input", renderTicket);
  $("#ticket").addEventListener("click", (e) => {
    const s = e.target.closest("[data-step]");
    if (s) {
      const inp = $("#px");
      const step = tickStep(market.get(settings.symbol).price);
      inp.value = Math.max(step, (parseFloat(inp.value) || 0) + step * +s.dataset.step).toFixed(2);
      renderTicket();
    }
    const qs = e.target.closest("[data-qstep]");
    if (qs) {
      const inp = $("#qty");
      inp.value = Math.max(1, (parseInt(inp.value, 10) || 0) + +qs.dataset.qstep);
      renderTicket();
    }
    const p = e.target.closest("[data-pct]");
    if (p) {
      const f = +p.dataset.pct;
      let q;
      if (ui.side === "buy") q = Math.floor((broker.buyingPower() * f) / ticketEntryPrice());
      else q = Math.floor(Math.max(0, (broker.position(settings.symbol)?.qty || 0) - broker.reservedQty(settings.symbol)) * f);
      $("#qty").value = Math.max(0, q);
      renderTicket();
    }
  });
  $("#ticket").addEventListener("submit", (e) => {
    e.preventDefault();
    const slOn = $("#sl-on").checked && ui.side === "buy";
    const tpOn = $("#tp-on").checked && ui.side === "buy";
    const res = broker.placeOrder({
      symbol: settings.symbol,
      side: ui.side,
      type: ui.otype,
      qty: parseInt($("#qty").value, 10),
      limitPrice: ui.otype === "limit" ? parseFloat($("#px").value) : null,
      stopPrice: ui.otype === "stop" ? parseFloat($("#px").value) : null,
      sl: slOn ? parseFloat($("#sl").value) : null,
      tp: tpOn ? parseFloat($("#tp").value) : null,
    });
    if (!res.ok) {
      toast(res.msg, "error", "Order abgelehnt");
      beep(220, 0.2);
      haptic([30, 40, 30]);
      shake($("#ticket"));
    } else {
      haptic(12);
      const b = $("#o-submit");
      b.classList.remove("done");
      void b.offsetWidth;
      b.classList.add("done");
    }
  });
}

// ---------- Unteres Panel ----------
function renderAccountBar() {
  const eq = broker.equity();
  const un = broker.unrealized();
  const total = eq - START_CASH;
  $("#acct").innerHTML = `
    <span>Gesamtwert <b>${eur(eq)}</b></span>
    <span>Guthaben <b>${eur(broker.state.cash)}</b></span>
    <span>Kaufkraft <b>${eur(broker.buyingPower())}</b></span>
    <span>Unreal. G/V <b class="${cls(un)}">${sEur(un)}</b></span>
    <span>Gesamt <b class="${cls(total)}">${pct(total / START_CASH)}</b></span>`;
  $("#cnt-pos").textContent = Object.keys(broker.state.positions).length;
  $("#cnt-ord").textContent = broker.state.orders.length;
  $("#cnt-al").textContent = broker.state.alerts.filter((a) => a.active).length;
}

function positionsTable(compactMode = false) {
  const rows = Object.entries(broker.state.positions);
  if (!rows.length) return `<div class="empty">Keine offenen Positionen. Kaufe eine Aktie über das Order-Ticket rechts.</div>`;
  return `<table class="grid"><thead><tr>
      <th>Symbol</th><th class="num">Stück</th><th class="num">Ø Einstand</th><th class="num">Kurs</th>
      <th class="num">Marktwert</th><th class="num">G/V</th><th class="num">G/V %</th>${compactMode ? "" : '<th class="num">Anteil</th>'}<th></th>
    </tr></thead><tbody>
    ${rows
      .map(([sym, p]) => {
        const px = market.get(sym).price;
        const val = px * p.qty;
        const pl = (px - p.avg) * p.qty;
        return `<tr data-sym="${sym}" class="clickable">
          <td><b>${sym}</b> <span class="muted">${esc(market.get(sym).n)}</span></td>
          <td class="num">${p.qty}</td><td class="num">${num(p.avg)}</td><td class="num">${num(px)}</td>
          <td class="num">${eur(val)}</td><td class="num ${cls(pl)}">${sEur(pl)}</td><td class="num ${cls(pl)}">${pct((px - p.avg) / p.avg)}</td>
          ${compactMode ? "" : `<td class="num">${nf2.format((val / broker.equity()) * 100)} %</td>`}
          <td class="num"><button class="mini-btn danger" data-close-pos="${sym}">Schließen</button></td></tr>`;
      })
      .join("")}</tbody></table>`;
}

function renderBottom() {
  const el = $("#bpanel");
  const s = broker.state;
  $$(".btab").forEach((b) => b.classList.toggle("active", b.dataset.btab === ui.btab));
  if (ui.btab === "positions") el.innerHTML = positionsTable(true);
  if (ui.btab === "orders") {
    el.innerHTML = s.orders.length
      ? `<table class="grid"><thead><tr><th>Erstellt</th><th>Symbol</th><th>Seite</th><th>Typ</th><th class="num">Stück</th><th class="num">Preis</th><th class="num">Aktuell</th><th class="num">Abstand</th><th></th></tr></thead><tbody>
        ${s.orders
          .map((o) => {
            const px = o.limitPrice ?? o.stopPrice;
            const cur = market.get(o.symbol).price;
            return `<tr data-sym="${o.symbol}" class="clickable"><td>${dateTime(o.created)}</td><td><b>${o.symbol}</b></td>
            <td><span class="tag ${o.side}">${o.side === "buy" ? "Kauf" : "Verkauf"}</span></td>
            <td>${o.tag ? o.tag + " · " : ""}${o.type === "limit" ? "Limit" : "Stopp"}${o.oco ? " (OCO)" : ""}</td>
            <td class="num">${o.qty}</td><td class="num">${num(px)}</td><td class="num">${num(cur)}</td><td class="num">${pct((px - cur) / cur)}</td>
            <td class="num"><button class="mini-btn" data-cancel="${o.id}">Stornieren</button></td></tr>`;
          })
          .join("")}</tbody></table>`
      : `<div class="empty">Keine offenen Orders. Limit- und Stopp-Orders erscheinen hier, bis sie ausgeführt werden.</div>`;
  }
  if (ui.btab === "history") {
    el.innerHTML = s.orderHistory.length
      ? `<table class="grid"><thead><tr><th>Zeit</th><th>Symbol</th><th>Seite</th><th>Typ</th><th class="num">Stück</th><th class="num">Preis</th><th class="num">Gebühr</th><th class="num">G/V</th><th>Status</th></tr></thead><tbody>
        ${s.orderHistory
          .slice(0, 100)
          .map((o) => {
            const f = o.status === "ausgeführt" ? s.fills.find((x) => x.orderId === o.id) : null;
            return `<tr><td>${dateTime(o.closed || o.created)}</td><td><b>${o.symbol}</b></td>
            <td><span class="tag ${o.side}">${o.side === "buy" ? "Kauf" : "Verkauf"}</span></td>
            <td>${o.tag ? o.tag + " · " : ""}${{ market: "Market", limit: "Limit", stop: "Stopp" }[o.type]}</td>
            <td class="num">${o.qty}</td><td class="num">${o.fillPrice ? num(o.fillPrice) : num(o.limitPrice ?? o.stopPrice ?? 0)}</td>
            <td class="num">${f ? eur(f.fee || 0) : "–"}</td>
            <td class="num ${f?.pnl != null ? cls(f.pnl) : ""}">${f?.pnl != null ? sEur(f.pnl) : "–"}</td>
            <td><span class="status ${o.status === "ausgeführt" ? "ok" : "no"}">${esc(o.status)}</span></td></tr>`;
          })
          .join("")}</tbody></table>`
      : `<div class="empty">Noch keine Orders.</div>`;
  }
  if (ui.btab === "alerts") {
    el.innerHTML = s.alerts.length
      ? `<table class="grid"><thead><tr><th>Symbol</th><th>Bedingung</th><th class="num">Aktuell</th><th>Notiz</th><th>Status</th><th></th></tr></thead><tbody>
        ${s.alerts
          .map(
            (a) => `<tr data-sym="${a.symbol}" class="clickable"><td><b>${a.symbol}</b></td>
            <td>Kurs ${a.dir === "above" ? "steigt über" : "fällt unter"} ${num(a.price)}</td>
            <td class="num">${num(market.get(a.symbol).price)}</td><td>${esc(a.note || "")}</td>
            <td>${a.active ? '<span class="status wait">aktiv</span>' : `<span class="status ok">ausgelöst ${clock(a.triggered)}</span>`}</td>
            <td class="num"><button class="mini-btn" data-rm-alert="${a.id}">Löschen</button></td></tr>`
          )
          .join("")}</tbody></table>`
      : `<div class="empty">Keine Alarme. Erstelle einen über „Alarm“ oben oder das Glocken-Werkzeug im Chart.</div>`;
  }
}

function bindTables() {
  document.addEventListener("click", (e) => {
    const cp = e.target.closest("[data-close-pos]");
    if (cp) {
      e.stopPropagation();
      const r = broker.closePosition(cp.dataset.closePos);
      if (!r.ok) toast(r.msg, "error");
      return;
    }
    const c = e.target.closest("[data-cancel]");
    if (c) {
      e.stopPropagation();
      broker.cancelOrder(c.dataset.cancel);
      toast("Order storniert.", "info");
      return;
    }
    const ra = e.target.closest("[data-rm-alert]");
    if (ra) {
      e.stopPropagation();
      broker.removeAlert(ra.dataset.rmAlert);
      return;
    }
    const rm = e.target.closest("[data-rm]");
    if (rm) {
      e.stopPropagation();
      toggleWatch(rm.dataset.rm);
      return;
    }
    const row = e.target.closest("tr[data-sym], .hm-tile[data-sym]");
    if (row && !e.target.closest("#ticker")) setSymbol(row.dataset.sym);
  });
  $$(".btab").forEach((b) =>
    b.addEventListener("click", () => {
      ui.btab = b.dataset.btab;
      renderBottom();
    })
  );
  $$(".rtab").forEach((b) =>
    b.addEventListener("click", () => {
      ui.rtab = b.dataset.rtab;
      $$(".rtab").forEach((x) => x.classList.toggle("active", x === b));
      $("#rpanel-watch").hidden = ui.rtab !== "watch";
      $("#rpanel-book").hidden = ui.rtab !== "book";
      $("#rpanel-tape").hidden = ui.rtab !== "tape";
      $("#rpanel-ai").hidden = ui.rtab !== "ai";
      renderRightPanel();
    })
  );
  // Klick ins Orderbuch übernimmt den Preis als Limit
  $("#book").addEventListener("click", (e) => {
    const l = e.target.closest("[data-px]");
    if (!l) return;
    ui.otype = "limit";
    ui.side = l.classList.contains("bid") ? "buy" : "sell";
    $("#px").value = (+l.dataset.px).toFixed(2);
    renderTicket();
    toast(`Limitpreis ${num(+l.dataset.px)} übernommen.`, "info");
  });
  $("#wl-add").addEventListener("click", openSearch);
}

// ---------- Zeichenwerkzeuge ----------
function setToolButtons(tool) {
  $$("#drawbar [data-tool]").forEach((b) => b.classList.toggle("active", b.dataset.tool === tool));
}
function bindDrawbar() {
  $$("#drawbar [data-tool]").forEach((b) =>
    b.addEventListener("click", () => {
      chart.setTool(b.dataset.tool);
      setToolButtons(b.dataset.tool);
    })
  );
  $("#magnet-btn").addEventListener("click", (e) => {
    chart.magnet = !chart.magnet;
    e.currentTarget.classList.toggle("active", chart.magnet);
  });
  $("#undo-btn").addEventListener("click", () => chart.undoDrawing());
  $("#clear-btn").addEventListener("click", () => {
    chart.clearDrawings();
    toast("Alle Zeichnungen für " + settings.symbol + " gelöscht.", "info");
  });
  $("#fit-btn").addEventListener("click", () => chart.resetView());
}

// ---------- Dialoge ----------
function openModal(id) {
  const m = $(id);
  m.hidden = false;
  requestAnimationFrame(() => requestAnimationFrame(() => m.classList.add("open")));
}
function closeModals() {
  $$(".modal:not([hidden])").forEach((m) => {
    m.classList.remove("open");
    setTimeout(() => {
      if (!m.classList.contains("open")) m.hidden = true;
    }, 320);
  });
}
document.addEventListener("click", (e) => {
  if (e.target.matches("[data-close]") || e.target.classList.contains("modal")) closeModals();
});

let searchIdx = 0;
function openSearch() {
  openModal("#search-modal");
  const inp = $("#search-input");
  inp.value = "";
  searchIdx = 0;
  renderSearch();
  inp.focus();
}
function searchResults() {
  const q = $("#search-input").value.trim().toLowerCase();
  return market.list.filter((s) => !q || s.s.toLowerCase().includes(q) || s.n.toLowerCase().includes(q) || s.sec.toLowerCase().includes(q));
}
function renderSearch() {
  const res = searchResults();
  searchIdx = Math.min(searchIdx, Math.max(0, res.length - 1));
  $("#search-list").innerHTML = res.length
    ? res
        .map((s, i) => {
          const q = market.quote(s.s);
          const on = settings.watchlist.includes(s.s);
          return `<li class="${i === searchIdx ? "hl" : ""}" data-pick="${s.s}">
            <b class="sy">${s.s}</b><span class="nm">${esc(s.n)}<small>${s.sec} · ${s.ex}</small></span>
            <span class="num">${num(q.price)}</span><span class="num ${cls(q.change)}">${pct(q.changePct)}</span>
            <button class="star ${on ? "on" : ""}" data-star="${s.s}" title="Watchlist">★</button></li>`;
        })
        .join("")
    : `<li class="empty">Keine Treffer.</li>`;
}
function bindSearch() {
  $("#search-input").addEventListener("input", () => {
    searchIdx = 0;
    renderSearch();
  });
  $("#search-input").addEventListener("keydown", (e) => {
    const res = searchResults();
    if (e.key === "ArrowDown") searchIdx = Math.min(res.length - 1, searchIdx + 1);
    else if (e.key === "ArrowUp") searchIdx = Math.max(0, searchIdx - 1);
    else if (e.key === "Enter" && res[searchIdx]) {
      closeModals();
      setSymbol(res[searchIdx].s);
      return;
    } else return;
    e.preventDefault();
    renderSearch();
    $("#search-list .hl")?.scrollIntoView({ block: "nearest" });
  });
  $("#search-list").addEventListener("click", (e) => {
    const st = e.target.closest("[data-star]");
    if (st) {
      toggleWatch(st.dataset.star);
      return;
    }
    const li = e.target.closest("[data-pick]");
    if (li) {
      closeModals();
      setSymbol(li.dataset.pick);
    }
  });
}

function openIndicators() {
  const groups = ["Overlay", "Oszillator"];
  $("#ind-list").innerHTML = groups
    .map(
      (g) => `<h4>${g === "Overlay" ? "Im Kurschart" : "Oszillatoren (eigener Bereich)"}</h4>` +
        INDICATORS.filter((i) => i.group === g)
          .map((i) => `<label class="ind-item"><input type="checkbox" value="${i.id}" ${settings.indicators.includes(i.id) ? "checked" : ""}/><i style="background:${i.color || "#8a97ab"}"></i>${i.name}</label>`)
          .join("")
    )
    .join("");
  openModal("#ind-modal");
}
function bindIndicators() {
  $("#ind-list").addEventListener("change", (e) => {
    const max = plan().limits.indicators;
    if ($$("#ind-list input:checked").length > max) {
      e.target.checked = false;
      closeModals();
      setTimeout(() => openPlans(`Im Tarif ${plan().name} kannst du ${max} Indikatoren gleichzeitig nutzen. Mit Pro bis zu 8, mit Elite unbegrenzt.`), 330);
      return;
    }
    settings.indicators = $$("#ind-list input:checked").map((i) => i.value);
    saveSettings();
    chart.configure({ indicators: new Set(settings.indicators) });
  });
}

function openAlertModal(sym, price) {
  $("#al-sym").innerHTML = STOCKS.map((s) => `<option value="${s.s}" ${s.s === sym ? "selected" : ""}>${s.s} – ${esc(s.n)}</option>`).join("");
  $("#al-px").value = price.toFixed(2);
  $("#al-note").value = "";
  updateAlertHint();
  openModal("#alert-modal");
  setTimeout(() => $("#al-px").focus(), 20);
}
function updateAlertHint() {
  const cur = market.get($("#al-sym").value).price;
  const px = parseFloat($("#al-px").value);
  $("#al-hint").textContent = px ? `Aktuell ${num(cur)} – Alarm, wenn der Kurs ${px >= cur ? "über" : "unter"} ${num(px)} ${px >= cur ? "steigt" : "fällt"}.` : "";
}
function bindAlerts() {
  $("#al-sym").addEventListener("change", () => {
    $("#al-px").value = market.get($("#al-sym").value).price.toFixed(2);
    updateAlertHint();
  });
  $("#al-px").addEventListener("input", updateAlertHint);
  $("#alert-form").addEventListener("submit", (e) => {
    e.preventDefault();
    const sym = $("#al-sym").value;
    const px = parseFloat($("#al-px").value);
    if (!(px > 0)) return;
    const max = plan().limits.alerts;
    if (broker.state.alerts.filter((a) => a.active).length >= max) {
      closeModals();
      setTimeout(() => openPlans(`Im Tarif ${plan().name} sind ${max} aktive Alarme möglich. Upgrade für mehr.`), 330);
      return;
    }
    broker.addAlert(sym, px, $("#al-note").value.trim());
    closeModals();
    toast(`Alarm für ${sym} bei ${num(px)} erstellt.`, "success");
    if ("Notification" in window && Notification.permission === "default") Notification.requestPermission().catch(() => {});
  });
}

// ---------- Märkte ----------
function renderMarkets(full = false) {
  if (settings.view !== "markets") return;
  const list = market.list.map((s) => {
    const q = market.quote(s.s);
    return { s: s.s, n: s.n, sec: s.sec, price: q.price, chg: q.changePct, w: market.perf(s.s, 5), y: market.perf(s.s, 365), m: market.perf(s.s, 30), vol: q.volume, cap: q.marketCap, pe: q.pe, dy: q.dy };
  });

  // Top-Bewegungen
  const sorted = [...list].sort((a, b) => b.chg - a.chg);
  const chip = (x) => `<button class="chip ${cls(x.chg)}" data-pick-sym="${x.s}"><b>${x.s}</b> ${pct(x.chg)}</button>`;
  $("#movers").innerHTML = `<span class="muted">Top:</span>${sorted.slice(0, 3).map(chip).join("")}<span class="muted">Flop:</span>${sorted.slice(-3).reverse().map(chip).join("")}`;

  // Heatmap nach Sektoren, Kachelgröße nach Marktkapitalisierung
  const perfKey = { 1: "chg", 5: "w", 30: "m", 365: "y" }[ui.hmPeriod];
  const scale = { 1: 0.03, 5: 0.06, 30: 0.12, 365: 0.4 }[ui.hmPeriod];
  const sectors = {};
  for (const x of list) (sectors[x.sec] ||= []).push(x);
  const secOrder = Object.entries(sectors).sort((a, b) => b[1].reduce((s, x) => s + x.cap, 0) - a[1].reduce((s, x) => s + x.cap, 0));
  $("#heatmap").innerHTML = secOrder
    .map(([sec, xs]) => {
      const capSum = xs.reduce((s, x) => s + x.cap, 0);
      return `<div class="hm-sector" style="flex-grow:${Math.sqrt(capSum / 1e9)}"><div class="hm-sec-title">${sec}</div><div class="hm-tiles">
        ${xs
          .sort((a, b) => b.cap - a.cap)
          .map((x) => `<div class="hm-tile" data-sym="${x.s}" style="flex-grow:${Math.sqrt(x.cap / 1e9)};background:${heatColor(x[perfKey] / scale)}" title="${esc(x.n)}"><b>${x.s}</b><span>${pct(x[perfKey])}</span></div>`)
          .join("")}</div></div>`;
    })
    .join("");

  // Screener
  if (full) {
    const sel = $("#sc-sector");
    if (sel.options.length === 1) sel.innerHTML += [...new Set(STOCKS.map((s) => s.sec))].sort().map((s) => `<option>${s}</option>`).join("");
  }
  const f = $("#sc-search").value.trim().toLowerCase();
  const sec = $("#sc-sector").value;
  const { key, dir } = ui.sort;
  const rows = list
    .filter((x) => (!sec || x.sec === sec) && (!f || x.s.toLowerCase().includes(f) || x.n.toLowerCase().includes(f)))
    .sort((a, b) => (typeof a[key] === "string" ? a[key].localeCompare(b[key]) : a[key] - b[key]) * dir);
  $$(".screener th[data-sort]").forEach((th) => th.classList.toggle("sorted", th.dataset.sort === key));
  $("#sc-body").innerHTML = rows
    .map(
      (x) => `<tr data-sym="${x.s}" class="clickable"><td><b>${x.s}</b></td><td>${esc(x.n)}</td><td class="muted">${x.sec}</td>
      <td class="num">${num(x.price)}</td><td class="num ${cls(x.chg)}">${pct(x.chg)}</td><td class="num ${cls(x.w)}">${pct(x.w)}</td><td class="num ${cls(x.y)}">${pct(x.y)}</td>
      <td class="num">${compact(x.vol)}</td><td class="num">${compact(x.cap)}</td><td class="num">${x.pe ? num(x.pe) : "–"}</td><td class="num">${num(x.dy)}</td>
      <td class="num"><button class="star ${settings.watchlist.includes(x.s) ? "on" : ""}" data-star-sc="${x.s}">★</button></td></tr>`
    )
    .join("");
}
function heatColor(v) {
  const x = Math.max(-1, Math.min(1, v));
  if (x >= 0) return `rgba(34,197,94,${0.18 + x * 0.7})`;
  return `rgba(239,68,68,${0.18 - x * 0.7})`;
}
function bindMarkets() {
  $("#hm-period").addEventListener("click", (e) => {
    const b = e.target.closest("[data-p]");
    if (!b) return;
    ui.hmPeriod = +b.dataset.p;
    $$("#hm-period button").forEach((x) => x.classList.toggle("active", x === b));
    renderMarkets();
  });
  $$(".screener th[data-sort]").forEach((th) =>
    th.addEventListener("click", () => {
      const k = th.dataset.sort;
      ui.sort = { key: k, dir: ui.sort.key === k ? -ui.sort.dir : ["s", "n", "sec"].includes(k) ? 1 : -1 };
      renderMarkets();
    })
  );
  $("#sc-search").addEventListener("input", () => renderMarkets());
  $("#sc-sector").addEventListener("change", () => renderMarkets());
  document.addEventListener("click", (e) => {
    const s = e.target.closest("[data-star-sc]");
    if (s) {
      e.stopPropagation();
      toggleWatch(s.dataset.starSc);
      renderMarkets();
      return;
    }
    const p = e.target.closest("[data-pick-sym]");
    if (p) setSymbol(p.dataset.pickSym);
  }, true);
}

// ---------- Depot ----------
let equityChart = null;
let equitySeries = null;
function buildEquityChart() {
  const el = $("#equity-chart");
  if (equityChart) equityChart.remove();
  const dark = settings.theme === "dark";
  equityChart = window.LightweightCharts.createChart(el, {
    autoSize: true,
    layout: { background: { type: "solid", color: "transparent" }, textColor: dark ? "#aab4c3" : "#434b58", attributionLogo: false },
    grid: { vertLines: { visible: false }, horzLines: { color: dark ? "rgba(138,151,171,0.08)" : "rgba(40,50,70,0.07)" } },
    rightPriceScale: { borderVisible: false },
    timeScale: { borderVisible: false, timeVisible: true },
    localization: { locale: "de-DE", priceFormatter: (p) => eur(p) },
  });
  equitySeries = equityChart.addSeries(window.LightweightCharts.BaselineSeries, {
    baseValue: { type: "price", price: START_CASH },
    topLineColor: "#22c55e",
    bottomLineColor: "#ef4444",
    topFillColor1: "rgba(34,197,94,0.3)",
    topFillColor2: "rgba(34,197,94,0.02)",
    bottomFillColor1: "rgba(239,68,68,0.02)",
    bottomFillColor2: "rgba(239,68,68,0.3)",
    lineWidth: 2,
  });
  updateEquityChart();
  equityChart.timeScale().fitContent();
}
function updateEquityChart() {
  if (!equitySeries) return;
  const pts = [];
  let last = -1;
  for (const p of broker.state.equityCurve) {
    if (p.time <= last) continue;
    pts.push({ time: p.time, value: p.value });
    last = p.time;
  }
  const now = Math.max(last + 1, Math.floor(Date.now() / 1000) - new Date().getTimezoneOffset() * 60);
  pts.push({ time: now, value: broker.equity() });
  equitySeries.setData(pts);
}

function renderPortfolio(full = false) {
  if (settings.view !== "portfolio") return;
  const eq = broker.equity();
  const un = broker.unrealized();
  const st = broker.stats();
  const total = eq - START_CASH;
  $("#kpis").innerHTML = [
    ["Gesamtwert", eur(eq), ""],
    ["Gesamtrendite", `${sEur(total)} <small>${pct(total / START_CASH)}</small>`, cls(total)],
    ["Guthaben", eur(broker.state.cash), ""],
    ["Positionswert", eur(broker.positionsValue()), ""],
    ["Unrealisiert", sEur(un), cls(un)],
    ["Realisiert", sEur(broker.state.realized), cls(broker.state.realized)],
    ["Trades", `${st.trades}`, ""],
    ["Trefferquote", st.winRate == null ? "–" : nf2.format(st.winRate * 100) + " %", ""],
    ["Gebühren gezahlt", eur(broker.state.fees || 0), ""],
    ["Royalties verdient", sEur(community.state.royaltyTotal || 0), (community.state.royaltyTotal || 0) > 0 ? "up" : ""],
    ["Tarif", `${planTitle(plan())}`, "plan-kpi"],
  ]
    .map(([k, v, c]) => `<div class="kpi"><span>${k}</span><b class="${c}">${v}</b></div>`)
    .join("");

  // Aufteilung
  const parts = Object.entries(broker.state.positions).map(([s, p]) => ({ s, v: p.qty * market.get(s).price }));
  parts.push({ s: "Cash", v: broker.state.cash });
  parts.sort((a, b) => b.v - a.v);
  const colors = ["#4f8cff", "#22c55e", "#f59e0b", "#e056fd", "#06b6d4", "#ef4444", "#a3e635", "#f472b6", "#94a3b8"];
  $("#donut").innerHTML = donut(
    parts.map((p, i) => ({ label: p.s, value: p.v, color: p.s === "Cash" ? "#64748b" : colors[i % colors.length] })),
    `<tspan x="100" dy="-4" class="dn-big">${compact(broker.positionsValue())}</tspan><tspan x="100" dy="18" class="dn-sub">investiert</tspan>`
  );
  renderTax();
  $("#alloc").innerHTML =
    `<div class="alloc-bar">${parts.map((p, i) => `<i style="flex-grow:${p.v};background:${p.s === "Cash" ? "#64748b" : colors[i % colors.length]}"></i>`).join("")}</div>` +
    `<ul class="alloc-list">${parts.map((p, i) => `<li><i style="background:${p.s === "Cash" ? "#64748b" : colors[i % colors.length]}"></i><b>${p.s}</b><span>${eur(p.v)}</span><span class="muted">${nf2.format((p.v / eq) * 100)} %</span></li>`).join("")}</ul>`;

  $("#pf-positions").innerHTML = positionsTable(false);
  if (full || !equityChart) buildEquityChart();
  else updateEquityChart();
}

// ---------- Ereignisse vom Broker ----------
broker.on("fill", (f) => {
  if (aiEngine.executing) return;
  const verb = f.side === "buy" ? "Gekauft" : "Verkauft";
  const pnl = f.pnl != null ? ` · G/V ${sEur(f.pnl)}` : "";
  toast(`${f.qty} × ${f.symbol} zu ${num(f.price)}${pnl}`, f.side === "buy" ? "success" : "sell", `${verb} (${{ market: "Market", limit: "Limit", stop: "Stopp" }[f.type]})`);
  beep(f.side === "buy" ? 880 : 660);
  if (f.type !== "market") notify(`Akytex: Order ausgeführt`, `${verb}: ${f.qty} × ${f.symbol} zu ${num(f.price)} €`);
});
broker.on("placed", (o) => toast(`${o.side === "buy" ? "Kauf" : "Verkauf"} ${o.qty} × ${o.symbol} @ ${num(o.limitPrice ?? o.stopPrice)}`, "info", `${o.type === "limit" ? "Limit" : "Stopp"}-Order platziert`));
broker.on("reject", (o) => toast(`${o.symbol}: ${o.status}`, "error", "Order abgelehnt"));
broker.on("alert", (a) => {
  const msg = `${a.symbol} ${a.dir === "above" ? "über" : "unter"} ${num(a.price)}${a.note ? " – " + a.note : ""}`;
  toast(msg, "warn", "⏰ Alarm ausgelöst");
  beep(1046, 0.15);
  setTimeout(() => beep(1318, 0.2), 180);
  notify("Akytex Alarm", msg);
});
broker.on("change", () => {
  chart.refreshOverlays();
  renderAccountBar();
  renderBottom();
  renderQuoteCard();
  renderTicket();
  renderPortfolio();
});

// ---------- Live-Schleife ----------
let frame = false;
let slowTick = 0;
market.onTick(() => {
  if (frame) return;
  frame = true;
  requestAnimationFrame(() => {
    frame = false;
    if (settings.view === "chart") {
      chart.update();
      updateQuoteCard();
      renderWatchlist();
      renderRightPanel();
      renderTicket();
      renderAccountBar();
      if ((ui.btab === "positions" || ui.btab === "orders") && slowTick % 2 === 0) renderBottom();
    }
    renderTicker();
    syncTitle();
    if (settings.view === "home") renderHomeLive();
    if (settings.view === "business" && slowTick % 5 === 0) renderBusiness();
    if (++slowTick % 5 === 0) {
      if (settings.view === "chart" && ui.rtab === "ai") renderAI();
      if (slowTick % 25 === 0) checkSignals();
      if (settings.view === "ideas") renderLeaderboard();
      renderMarkets();
      renderPortfolio();
    }
  });
});
function syncTitle() {
  const q = market.quote(settings.symbol);
  document.title = `${settings.symbol} ${num(q.price)} ${pct(q.changePct)} · Akytex`;
}

// ---------- Tastatur ----------
document.addEventListener("keydown", (e) => {
  const typing = e.target.matches("input, select, textarea");
  if (e.key === "Escape") {
    closeModals();
    chart.setTool("cursor");
    setToolButtons("cursor");
    return;
  }
  if (typing) return;
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "z") {
    e.preventDefault();
    chart.undoDrawing();
    return;
  }
  if (e.altKey) {
    const map = { t: "trend", h: "hline", f: "fib" };
    const tool = map[e.key.toLowerCase()];
    if (tool) {
      e.preventDefault();
      chart.setTool(tool);
      setToolButtons(tool);
    }
    return;
  }
  if (e.key === "/" || (/^[a-zA-Z]$/.test(e.key) && !e.ctrlKey && !e.metaKey)) {
    e.preventDefault();
    openSearch();
    if (e.key !== "/") {
      $("#search-input").value = e.key;
      renderSearch();
    }
  }
});

// ---------- App-Installation (PWA) ----------
let installEvent = null;
const isStandalone = () => matchMedia("(display-mode: standalone)").matches || navigator.standalone === true;

function setupInstall() {
  const btn = $("#install-btn");
  btn.hidden = isStandalone() || embedded;
  $("#hero-install").hidden = isStandalone() || embedded;
  window.addEventListener("beforeinstallprompt", (e) => {
    e.preventDefault();
    installEvent = e;
    btn.hidden = embedded;
  });
  window.addEventListener("appinstalled", () => {
    installEvent = null;
    btn.hidden = true;
    toast("Akytex wurde als App installiert.", "success");
  });
  btn.addEventListener("click", async () => {
    if (installEvent) {
      installEvent.prompt();
      await installEvent.userChoice.catch(() => {});
      installEvent = null;
      return;
    }
    const ua = navigator.userAgent;
    const ios = /iphone|ipad|ipod/i.test(ua) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
    const android = /android/i.test(ua);
    const safariMac = /safari/i.test(ua) && !/chrome|chromium|edg/i.test(ua) && !ios;
    let html;
    if (ios)
      html = `<ol><li>Tippe in Safari unten auf <b>Teilen</b> <span class="kbd">⬆︎</span>.</li><li>Wähle <b>„Zum Home-Bildschirm“</b>.</li><li>Tippe auf <b>Hinzufügen</b> – Akytex erscheint als App-Symbol.</li></ol>`;
    else if (android)
      html = `<ol><li>Öffne das Browser-Menü <span class="kbd">⋮</span>.</li><li>Wähle <b>„App installieren“</b> bzw. <b>„Zum Startbildschirm hinzufügen“</b>.</li></ol>`;
    else if (safariMac) html = `<ol><li>Klicke in Safari auf <b>Ablage → Zum Dock hinzufügen…</b></li><li>Bestätige mit <b>Hinzufügen</b>.</li></ol>`;
    else
      html = `<ol><li>In <b>Chrome</b> oder <b>Edge</b>: Klicke auf das Installieren-Symbol <span class="kbd">⊕</span> rechts in der Adressleiste<br>oder Menü <span class="kbd">⋮</span> → <b>„Akytex installieren“</b>.</li><li>Akytex startet danach in einem eigenen Fenster, mit Desktop-Symbol und funktioniert auch offline.</li></ol><p class="muted">Firefox unterstützt die Installation am Desktop nicht – bitte Chrome oder Edge verwenden.</p>`;
    if (location.protocol === "file:") html = `<p>Die App-Installation benötigt einen Webserver (https oder localhost). Starte z. B. <code>python3 -m http.server</code> im Projektordner und öffne <code>http://localhost:8000</code>.</p>`;
    $("#install-help").innerHTML = html;
    openModal("#install-modal");
  });

  if ("serviceWorker" in navigator && location.protocol !== "file:") {
    navigator.serviceWorker.register("./sw.js").catch(() => {});
  }
}

// ---------- Tarife ----------
function renderPlans(el) {
  const billing = settings.billing;
  const cur = plan();
  const addonSum = ADDONS.filter((a) => settings.addons.includes(a.id) && !a.includedIn.includes(cur.id)).reduce((s, a) => s + a.price, 0);
  const myMonthly = planPrice(cur, billing) + addonSum;
  el.innerHTML = `
    <div class="plans-top">
      <div class="seg bill-seg" role="group" aria-label="Abrechnung">
        <button class="${billing === "monthly" ? "active" : ""}" data-billing="monthly">Monatlich</button>
        <button class="${billing === "yearly" ? "active" : ""}" data-billing="yearly">Jährlich <span class="save-chip">bis −23 %</span></button>
      </div>
      <div class="my-bill">Dein Abo: <b>${cur.name}</b>${addonSum ? ` + ${eur(addonSum)} Add-ons` : ""} = <b>${eur(myMonthly)} / Monat</b></div>
    </div>
    <div class="plan-cards">${PLANS.filter((p) => !p.group).map((p) => {
      const price = planPrice(p, billing);
      const isCur = p.id === settings.plan;
      const save = (p.monthly - p.yearly) * 12;
      const sub = !price
        ? "dauerhaft kostenlos"
        : billing === "yearly"
          ? `${eur(p.yearly * 12)} jährlich abgerechnet · du sparst ${eur(save)}`
          : `monatlich kündbar · ≈ ${eur((price * 12) / 365)} pro Tag`;
      return `<div class="plan ${p.popular ? "popular" : ""} ${isCur ? "current" : ""}">
        ${p.popular ? '<span class="plan-badge">Beliebteste Wahl</span>' : ""}
        <h4>${p.name}</h4><p class="muted">${p.tagline}</p>
        <div class="price">${billing === "yearly" && price ? `<s>${nf2.format(p.monthly)} €</s>` : ""}<b>${price ? nf2.format(price) + " €" : "0 €"}</b><span>/ Monat</span></div>
        <div class="price-sub">${sub}</div>
        <div class="fee-line"><span>Ordergebühr</span><b>${eur(p.fee)}</b></div>
        <ul>${p.features.map((f) => `<li>${esc(f)}</li>`).join("")}</ul>
        <button class="btn ${p.popular ? "primary" : ""} plan-choose" data-plan="${p.id}" ${isCur ? "disabled" : ""}>${isCur ? "Aktueller Tarif" : price ? `${p.name} 14 Tage gratis testen` : "Kostenlos nutzen"}</button>
      </div>`;
    }).join("")}</div>
    <div class="ai-plans">
      <div class="ai-plans-head"><span class="spark-ic">✦</span><div><h4>AKYTEX AI</h4><p class="muted">Dein KI-Berater – und auf Wunsch der Autopilot für dein Depot.</p></div></div>
      <div class="ai-plan-cards">${PLANS.filter((p) => p.group === "ai").map((p) => {
        const price = planPrice(p, billing);
        const isCur = p.id === settings.plan;
        return `<div class="plan ai-plan ${p.id} ${isCur ? "current" : ""}">
          ${p.id === "aiprem" ? '<span class="plan-badge gold">Autopilot</span>' : ""}
          <h4>${p.name}</h4><p class="muted">${p.tagline}</p>
          <div class="price">${billing === "yearly" ? `<s>${nf2.format(p.monthly)} €</s>` : ""}<b>${nf2.format(price)} €</b><span>/ Monat</span></div>
          <div class="price-sub">${billing === "yearly" ? `${eur(p.yearly * 12)} jährlich abgerechnet · du sparst ${eur((p.monthly - p.yearly) * 12)}` : `monatlich kündbar · ≈ ${eur((price * 12) / 365)} pro Tag`}</div>
          <ul>${p.features.map((f) => `<li>${esc(f)}</li>`).join("")}</ul>
          <button class="btn primary plan-choose" data-plan="${p.id}" ${isCur ? "disabled" : ""}>${isCur ? "Aktueller Tarif" : `${p.name} 14 Tage gratis testen`}</button>
        </div>`;
      }).join("")}</div>
    </div>
    <h4 class="addons-h">Add-ons <span class="muted">– einzeln zubuchbar, monatlich kündbar</span></h4>
    <div class="addons">${ADDONS.map((a) => {
      const incl = a.includedIn.includes(settings.plan);
      const on = settings.addons.includes(a.id);
      return `<div class="addon ${incl || on ? "on" : ""}"><div class="ad-ic">${a.icon}</div>
        <div class="ad-body"><b>${a.name}</b><span>${a.desc}</span></div>
        <div class="ad-price">${incl ? '<span class="incl">inklusive</span>' : `<b>${eur(a.price)}</b><small>/ Monat</small>`}</div>
        ${incl ? "" : `<button class="switch ${on ? "on" : ""}" data-addon="${a.id}" aria-pressed="${on}" aria-label="${a.name} ${on ? "abbestellen" : "buchen"}"><i></i></button>`}</div>`;
    }).join("")}</div>
    <details class="pricelist"><summary>Preis- und Leistungsverzeichnis</summary>
      <div class="table-scroll"><table class="grid">
        <thead><tr><th></th>${PLANS.map((p) => `<th class="num">${p.name}</th>`).join("")}</tr></thead>
        <tbody>
          <tr><td>Monatlich</td>${PLANS.map((p) => `<td class="num">${eur(p.monthly)}</td>`).join("")}</tr>
          <tr><td>Jährlich (pro Monat)</td>${PLANS.map((p) => `<td class="num">${eur(p.yearly)}</td>`).join("")}</tr>
          <tr><td>Ordergebühr</td>${PLANS.map((p) => `<td class="num">${eur(p.fee)}</td>`).join("")}</tr>
          <tr><td>Ideen-Gebühr (vom Volumen)</td>${PLANS.map((p) => `<td class="num">${nf2.format(p.ideaFee * 100)} %</td>`).join("")}</tr>
          <tr><td>Dein Creator-Anteil</td>${PLANS.map((p) => `<td class="num">${Math.round(p.creatorShare * 100)} %</td>`).join("")}</tr>
          <tr><td>Depotführung</td>${PLANS.map(() => `<td class="num">0,00 €</td>`).join("")}</tr>
          <tr><td>Orderbuch-Ebenen</td>${PLANS.map((p) => `<td class="num">${p.limits.depth}</td>`).join("")}</tr>
          <tr><td>Indikatoren / Alarme</td>${PLANS.map((p) => `<td class="num">${p.limits.indicators > 50 ? "∞" : p.limits.indicators} / ${p.limits.alerts > 500 ? "∞" : p.limits.alerts}</td>`).join("")}</tr>
        </tbody></table></div>
      <p class="muted">Spread: Differenz zwischen Kauf- und Verkaufskurs, im Kurs enthalten und vor jeder Order im Ticket ausgewiesen. Es gibt keine weiteren Kosten.</p>
    </details>`;
}
function openPlans(reason) {
  $("#plans-note").textContent = (reason ? reason + " " : "") + "Demo: Es findet keine Zahlung statt – Tarife lassen sich frei ausprobieren.";
  renderPlans($("#modal-plans"));
  openModal("#plans-modal");
}
function setPlan(id, quiet = false) {
  const p = planById(id);
  settings.plan = p.id;
  saveSettings();
  refreshMonetization();
  if (quiet) return;
  closeModals();
  if (p.monthly) {
    confetti();
    toast(`Alle ${p.name}-Funktionen sind freigeschaltet. Ordergebühr: ${eur(p.fee)}.`, "success", `Willkommen bei ${planTitle(p)} 🎉`);
  } else toast("Du nutzt jetzt den Free-Tarif.", "info");
}
function toggleAddon(id) {
  const a = ADDONS.find((x) => x.id === id);
  const i = settings.addons.indexOf(id);
  if (i >= 0) settings.addons.splice(i, 1);
  else settings.addons.push(id);
  saveSettings();
  haptic(10);
  refreshMonetization();
  toast(i >= 0 ? `${a.name} abbestellt.` : `${a.name} ist aktiv (${eur(a.price)} / Monat).`, i >= 0 ? "info" : "success", i >= 0 ? "Add-on entfernt" : "Add-on gebucht");
}
function refreshMonetization() {
  syncPlan();
  if (settings.view === "ai") renderAIView(true);
  for (const el of [$("#home-plans"), $("#modal-plans")]) if (el.childElementCount) renderPlans(el);
  renderTicket();
  renderRightPanel();
  renderPortfolio();
  if (ui.rtab === "ai") renderAI(true);
}
function syncPlan() {
  $("#plan-label").textContent = plan().name;
  $("#plan-btn").dataset.plan = plan().id;
}
function confetti() {
  const colors = ["#4f8cff", "#6ea2f2", "#22c55e", "#eab308", "#e056fd", "#ffffff"];
  for (let i = 0; i < 60; i++) {
    const d = document.createElement("i");
    d.className = "confetti";
    d.style.background = colors[i % colors.length];
    d.style.left = 50 + (Math.random() - 0.5) * 20 + "vw";
    document.body.appendChild(d);
    const x = (Math.random() - 0.5) * 900;
    const y = -(300 + Math.random() * 400);
    d.animate(
      [
        { transform: "translate(0,0) rotate(0)", opacity: 1 },
        { transform: `translate(${x * 0.6}px, ${y}px) rotate(${Math.random() * 540}deg)`, opacity: 1, offset: 0.45 },
        { transform: `translate(${x}px, ${y + 700}px) rotate(${Math.random() * 1080}deg)`, opacity: 0 },
      ],
      { duration: 1600 + Math.random() * 900, easing: "cubic-bezier(.2,.7,.3,1)" }
    ).onfinish = () => d.remove();
  }
}

// ---------- AKYTEX AI ----------
let aiLast = 0;
function gaugeSvg() {
  const seg = (i, color) => {
    const a0 = Math.PI - (i * Math.PI) / 5 - 0.02;
    const a1 = Math.PI - ((i + 1) * Math.PI) / 5 + 0.02;
    const p = (a) => `${100 + 78 * Math.cos(a)} ${100 - 78 * Math.sin(a)}`;
    return `<path d="M${p(a0)} A78 78 0 0 1 ${p(a1)}" stroke="${color}" stroke-width="12" fill="none" stroke-linecap="round"/>`;
  };
  return `<svg viewBox="0 0 200 118" class="gauge-svg">
    ${["#ef4444", "#f97316", "#94a3b8", "#84cc16", "#22c55e"].map((c, i) => seg(i, c)).join("")}
    <g class="needle" id="ai-needle"><path d="M100 100 L96 98 L100 34 L104 98 Z" fill="var(--text)"/></g>
    <circle cx="100" cy="100" r="7" fill="var(--text)"/><circle cx="100" cy="100" r="3" fill="var(--bg-2)"/>
    <text x="16" y="116" class="g-lbl">Verkaufen</text><text x="184" y="116" class="g-lbl" text-anchor="end">Kaufen</text>
  </svg>`;
}
function renderAI(force = false) {
  if (ui.rtab !== "ai") return;
  if (!force && Date.now() - aiLast < 1500) return;
  aiLast = Date.now();
  const el = $("#ai");
  if (!el.dataset.ready) {
    el.innerHTML = `<div class="ai-head"><b>AKYTEX AI</b><span class="ai-badge">Echtzeit</span></div><div class="gauge">${gaugeSvg()}</div><div id="ai-body"></div>`;
    el.dataset.ready = "1";
  }
  const a = analyze(chart.raw);
  $("#ai-needle").style.transform = `rotate(${Math.max(-1, Math.min(1, a.score * 1.6)) * 90}deg)`;
  const tfl = TIMEFRAMES.find((t) => t.id === settings.tf).label;
  const pro = plan().limits.aiDetails;
  const c = { buy: a.oscillators.counts.buy + a.movingAverages.counts.buy, sell: a.oscillators.counts.sell + a.movingAverages.counts.sell, neutral: a.oscillators.counts.neutral + a.movingAverages.counts.neutral };
  const sigRow = (s) => `<tr><td>${s.name}</td><td class="num">${s.value == null ? "–" : num(s.value)}</td><td class="num ${s.action > 0 ? "up" : s.action < 0 ? "down" : "muted"}">${s.action > 0 ? "Kaufen" : s.action < 0 ? "Verkaufen" : "Neutral"}</td></tr>`;
  const st = a.setup;
  const crv = Math.abs(st.tp - st.entry) / Math.abs(st.entry - st.sl);
  const details = `
    <ul class="ai-text">${a.text.map((t) => `<li>${esc(t)}</li>`).join("")}</ul>
    <div class="ai-levels">
      <div><span>Widerstand</span><b>${num(a.levels.resistance)}</b></div>
      <div><span>Pivot</span><b>${num(a.levels.pivot)}</b></div>
      <div><span>Unterstützung</span><b>${num(a.levels.support)}</b></div>
    </div>
    <div class="ai-setup ${st.side}">
      <div class="ai-setup-h"><b>${st.side === "buy" ? "▲ Long-Setup" : "▼ Bärisches Setup"}</b><span>CRV ${nf2.format(crv)} : 1</span></div>
      <div class="ai-setup-g"><span>Einstieg <b>${num(st.entry)}</b></span><span>Ziel <b class="up">${num(st.tp)}</b></span><span>Stop <b class="down">${num(st.sl)}</b></span></div>
      <button class="btn primary small" id="ai-apply">${st.side === "buy" ? "Setup ins Order-Ticket übernehmen" : "Position mit Stop absichern"}</button>
    </div>
    <details class="ai-all"><summary>Alle ${a.oscillators.list.length + a.movingAverages.list.length} Signale</summary>
      <table class="grid"><thead><tr><th>Oszillator</th><th class="num">Wert</th><th class="num">Signal</th></tr></thead><tbody>${a.oscillators.list.map(sigRow).join("")}</tbody></table>
      <table class="grid"><thead><tr><th>Durchschnitt</th><th class="num">Wert</th><th class="num">Signal</th></tr></thead><tbody>${a.movingAverages.list.map(sigRow).join("")}</tbody></table>
    </details>`;
  const locked = `
    <ul class="ai-text">${a.text.slice(0, 1).map((t) => `<li>${esc(t)}</li>`).join("")}</ul>
    <div class="ai-lock">
      <div class="ai-lock-blur"><div class="ai-levels"><div><span>Widerstand</span><b>000,00</b></div><div><span>Pivot</span><b>000,00</b></div><div><span>Unterstützung</span><b>000,00</b></div></div><div class="ai-setup"><b>Long-Setup · CRV 2 : 1</b><br>Einstieg 000,00 · Ziel 000,00 · Stop 000,00</div></div>
      <div class="ai-lock-cta"><b>🔒 Detail-Analyse mit Pro</b><span>Marken, Trade-Setups und alle 16 Signale</span><button class="btn primary small" data-open-plans>Pro 14 Tage gratis</button></div>
    </div>`;
  const openDetails = $("#ai-body details")?.open;
  $("#ai-body").innerHTML = `
    <div class="ai-rating ${a.rating.key}">${a.rating.label}</div>
    <div class="ai-sub muted">${settings.symbol} · ${tfl} · ${c.buy + c.sell + c.neutral} Signale</div>
    <div class="ai-counts"><span class="down"><b>${c.sell}</b>Verkaufen</span><span><b>${c.neutral}</b>Neutral</span><span class="up"><b>${c.buy}</b>Kaufen</span></div>
    <div class="ai-groups">
      <div><span>Oszillatoren</span><b class="${a.oscillators.rating.key}">${a.oscillators.rating.label}</b></div>
      <div><span>Durchschnitte</span><b class="${a.movingAverages.rating.key}">${a.movingAverages.rating.label}</b></div>
    </div>
    ${pro ? details : locked}
    <p class="ai-disc">Automatisch berechnet aus technischen Indikatoren. Keine Anlageberatung.</p>`;
  if (openDetails) $("#ai-body details").open = true;
  $("#ai-apply")?.addEventListener("click", () => applySetup(a));
}
function applySetup(a) {
  const st = a.setup;
  const step = tickStep(st.entry);
  if (st.side === "buy") {
    ui.side = "buy";
    ui.otype = "market";
    const qty = Math.max(1, Math.floor((broker.equity() * 0.01) / Math.max(0.01, st.entry - st.sl)));
    $("#qty").value = Math.min(qty, Math.floor((broker.equity() * 0.1) / st.entry), Math.floor(broker.buyingPower() / st.entry));
    $("#sl-on").checked = true;
    $("#tp-on").checked = true;
    $("#sl").value = roundTo(st.sl, step).toFixed(2);
    $("#tp").value = roundTo(st.tp, step).toFixed(2);
    renderTicket();
    toast("Stückzahl so gewählt, dass der Stop maximal 1 % deines Depots riskiert (höchstens 10 % Positionsgröße).", "info", "Setup übernommen");
  } else {
    const pos = broker.position(settings.symbol);
    if (!pos) {
      toast("Leerverkäufe sind im Demo-Depot nicht möglich. Kein Bestand zum Absichern.", "warn", "Bärisches Signal");
      return;
    }
    ui.side = "sell";
    ui.otype = "stop";
    $("#qty").value = Math.max(0, pos.qty - broker.reservedQty(settings.symbol));
    $("#px").value = roundTo(a.last - 1.5 * a.atr, step).toFixed(2);
    renderTicket();
    toast("Verkaufs-Stopp vorbereitet – prüfen und absenden.", "info", "Absicherung");
  }
  $("#ticket").scrollIntoView({ behavior: "smooth", block: "nearest" });
  flashEl($("#ticket"));
}
function flashEl(el) {
  el.animate([{ boxShadow: "0 0 0 0 rgba(79,140,255,.6)" }, { boxShadow: "0 0 0 12px rgba(79,140,255,0)" }], { duration: 900, easing: "ease-out" });
}

// ---------- Startseite ----------
let homeChart = null;
let homeSeries = null;
let homeSym = "NVDA";
function spark(values, w, h, color) {
  const min = Math.min(...values);
  const max = Math.max(...values);
  const pts = values.map((v, i) => `${((i / (values.length - 1)) * w).toFixed(1)},${(h - 2 - ((v - min) / (max - min || 1)) * (h - 4)).toFixed(1)}`);
  const id = "sg" + Math.random().toString(36).slice(2, 7);
  return `<svg viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" class="spark"><defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${color}" stop-opacity=".35"/><stop offset="1" stop-color="${color}" stop-opacity="0"/></linearGradient></defs><polygon points="0,${h} ${pts.join(" ")} ${w},${h}" fill="url(#${id})"/><polyline points="${pts.join(" ")}" fill="none" stroke="${color}" stroke-width="1.8" vector-effect="non-scaling-stroke"/></svg>`;
}
function renderHome(full = false) {
  renderPlans($("#home-plans"));
  community.ready.then(renderUspDemo);
  if (full || !homeChart) buildHomeChart();
  renderHomeLive(true);
  if (!renderHome.observer) {
    renderHome.observer = new IntersectionObserver(
      (es) => es.forEach((e) => e.isIntersecting && (e.target.classList.add("in"), renderHome.observer.unobserve(e.target))),
      { threshold: 0.12 }
    );
  }
  $$("#view-home .reveal:not(.in)").forEach((el) => renderHome.observer.observe(el));
}
let homeLiveTick = 0;
function renderHomeLive(force = false) {
  if (!force && ++homeLiveTick % 2) return;
  [["#fc1", "NVDA"], ["#fc2", "SAP"], ["#fc3", "RHM"]].forEach(([sel, sym]) => {
    const q = market.quote(sym);
    const st = market.get(sym);
    const closes = st.m1.slice(-90).map((b) => b.close);
    $(sel).innerHTML = `<div class="fc-top"><b>${sym}</b><span class="${cls(q.change)}">${pct(q.changePct)}</span></div><div class="fc-px">${num(q.price)} €</div>${spark(closes, 160, 44, q.change >= 0 ? "#22c55e" : "#ef4444")}`;
  });
  $("#mini-list").innerHTML = ["NVDA", "AAPL", "SAP", "TSLA", "RHM", "ASML"]
    .map((sym) => {
      const q = market.quote(sym);
      return `<button class="mini-row ${sym === homeSym ? "active" : ""}" data-home-sym="${sym}"><b>${sym}</b><span class="muted">${esc(q.name)}</span><span class="num">${num(q.price)}</span><span class="num ${cls(q.change)}">${pct(q.changePct)}</span></button>`;
    })
    .join("");
  if (homeSeries) {
    const d = market.get(homeSym).days;
    const l = d[d.length - 1];
    homeSeries.update({ time: l.time, value: l.close });
  }
}
function buildHomeChart() {
  const el = $("#home-chart");
  if (homeChart) homeChart.remove();
  const dark = settings.theme === "dark";
  homeChart = window.LightweightCharts.createChart(el, {
    autoSize: true,
    layout: { background: { type: "solid", color: "transparent" }, textColor: dark ? "#aab4c3" : "#434b58", attributionLogo: false },
    grid: { vertLines: { visible: false }, horzLines: { color: dark ? "rgba(138,151,171,0.08)" : "rgba(40,50,70,0.07)" } },
    rightPriceScale: { borderVisible: false },
    timeScale: { borderVisible: false },
    handleScroll: false,
    handleScale: false,
    localization: { locale: "de-DE", priceFormatter: (p) => num(p) },
  });
  homeSeries = homeChart.addSeries(window.LightweightCharts.AreaSeries, { lineColor: "#6ea2f2", topColor: "rgba(79,140,255,0.4)", bottomColor: "rgba(79,140,255,0)", lineWidth: 2 });
  homeSeries.setData(market.get(homeSym).days.slice(-365).map((b) => ({ time: b.time, value: b.close })));
  homeChart.timeScale().fitContent();
}

// ---------- Ideen ----------
const ago = (ms) => {
  const m = Math.max(1, Math.round((Date.now() - ms) / 60000));
  if (m < 60) return `vor ${m} Min.`;
  const h = Math.round(m / 60);
  if (h < 24) return `vor ${h} Std.`;
  const d = Math.round(h / 24);
  return `vor ${d} ${d === 1 ? "Tag" : "Tagen"}`;
};
function authorOf(idea) {
  if (idea.author === "me") return { handle: "du", name: "Du", style: "Mein Profil", color: "#6ea2f2", me: true };
  return community.trader(idea.author);
}
function avatar(t) {
  const txt = t.me ? "DU" : t.handle.replace(/[^A-Za-z]/g, "").slice(0, 2).toUpperCase();
  return `<span class="avatar" style="--c:${t.color}">${txt}</span>`;
}
function ideaChart(i, W = 320, H = 150) {
  const m1 = market.get(i.symbol).m1;
  const t0 = toLocalSec(i.created);
  const tNow = m1[m1.length - 1].time;
  const span = Math.max(3 * 3600, tNow - t0);
  const tStart = t0 - span * 0.4;
  let k = m1.length - 1;
  while (k > 0 && m1[k - 1].time >= tStart) k--;
  const src = m1.slice(k);
  const step = Math.max(1, Math.ceil(src.length / 150));
  const pts = src.filter((_, j) => j % step === 0 || j === src.length - 1);
  const vals = pts.map((b) => b.close).concat([i.tp, i.sl, i.entry]);
  const lo = Math.min(...vals);
  const hi = Math.max(...vals);
  const pad = (hi - lo) * 0.08 || 1;
  const x = (t) => ((t - tStart) / (tNow - tStart || 1)) * (W - 58);
  const y = (v) => 8 + (1 - (v - (lo - pad)) / (hi - lo + 2 * pad)) * (H - 16);
  const before = pts.filter((b) => b.time <= t0);
  const after = pts.filter((b) => b.time >= t0);
  const line = (arr) => arr.map((b, j) => `${j ? "L" : "M"}${x(b.time).toFixed(1)} ${y(b.close).toFixed(1)}`).join(" ");
  const col = i.perf >= 0 ? "var(--up)" : "var(--down)";
  const gid = "ig" + i.id;
  const lvl = (v, c, t) => `<line x1="0" x2="${W - 58}" y1="${y(v)}" y2="${y(v)}" stroke="${c}" stroke-dasharray="4 4" stroke-width="1"/><rect x="${W - 56}" y="${y(v) - 8}" width="56" height="16" rx="4" fill="${c}"/><text x="${W - 28}" y="${y(v) + 4}" text-anchor="middle" class="ic-lbl">${t}</text>`;
  const px0 = x(t0);
  let end = "";
  if (i.status !== "open" && i.closedAt) end = `<circle cx="${x(i.closedAt)}" cy="${y(i.exit)}" r="5" fill="${i.status === "target" ? "var(--up)" : "var(--down)"}" stroke="var(--panel)" stroke-width="2"/>`;
  return `<svg viewBox="0 0 ${W} ${H}" class="idea-svg" preserveAspectRatio="none">
    <defs><linearGradient id="${gid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${col}" stop-opacity=".28"/><stop offset="1" stop-color="${col}" stop-opacity="0"/></linearGradient></defs>
    <rect x="${px0}" y="0" width="${W - 58 - px0}" height="${H}" fill="var(--accent)" opacity=".05"/>
    ${after.length > 1 ? `<path d="${line(after)} L${x(after[after.length - 1].time)} ${H} L${x(after[0].time)} ${H} Z" fill="url(#${gid})"/>` : ""}
    <path d="${line(before)}" fill="none" stroke="var(--muted)" stroke-width="1.4" opacity=".7"/>
    ${after.length > 1 ? `<path d="${line(after)}" fill="none" stroke="${col}" stroke-width="1.8"/>` : ""}
    ${lvl(i.tp, "var(--up)", num(i.tp))}${lvl(i.sl, "var(--down)", num(i.sl))}${lvl(i.entry, "var(--accent)", num(i.entry))}
    <line x1="${px0}" x2="${px0}" y1="0" y2="${H}" stroke="var(--accent)" stroke-width="1"/>
    <circle cx="${px0}" cy="${y(i.entry)}" r="4.5" fill="var(--accent)" stroke="var(--panel)" stroke-width="2"/>
    ${end}
  </svg>`;
}
function statusBadge(i) {
  if (i.status === "target") return `<span class="istatus target">✓ Ziel erreicht</span>`;
  if (i.status === "stop") return `<span class="istatus stop">✗ Stop</span>`;
  return `<span class="istatus open"><i></i>Läuft</span>`;
}
function ideaCard(i, k = 0) {
  const t = authorOf(i);
  const liked = community.isLiked(i.id);
  const stats = t.me ? null : community.traderStats(i.author);
  const long = i.dir === "long";
  return `<article class="idea-card st-${i.status}" style="--k:${Math.min(k, 12)}" data-idea="${i.id}">
    <header>${avatar(t)}<div class="who"><b>@${esc(t.handle)}</b><small>${esc(t.style)} · ${ago(i.created)}</small></div>
      ${stats && stats.hitRate != null ? `<span class="verified" title="Überprüfte Trefferquote aus ${stats.closed} abgeschlossenen Ideen">✓ ${Math.round(stats.hitRate * 100)} %</span>` : ""}
      ${t.me ? `<span class="mine-chip">Deine Idee</span>` : `<button class="follow-btn ${community.isFollowing(i.author) ? "on" : ""}" data-follow="${i.author}">${community.isFollowing(i.author) ? "Gefolgt" : "Folgen"}</button>`}
    </header>
    <div class="idea-vis" data-open-sym="${i.symbol}" data-open-tf="${i.tf}">${i.img && t.me ? `<img src="${i.img}" alt="Chart ${i.symbol}" loading="lazy" />` : ideaChart(i)}<span class="dir ${i.dir}">${long ? "▲ Long" : "▼ Short"}</span>${statusBadge(i)}</div>
    <div class="idea-meta"><button class="sym-chip" data-open-sym="${i.symbol}" data-open-tf="${i.tf}">${i.symbol}</button><span class="muted">${TIMEFRAMES.find((x) => x.id === i.tf)?.label || i.tf}</span><b class="perf ${cls(i.perf)}">${pct(i.perf)}</b></div>
    <h3>${esc(i.title)}</h3>
    <p>${esc(i.body)}</p>
    <div class="idea-levels"><span>Einstieg<b>${num(i.entry)}</b></span><span>Ziel<b class="up">${num(i.tp)}</b></span><span>Stop<b class="down">${num(i.sl)}</b></span></div>
    <button class="seal" data-seal="${i.id}">🔒 Versiegelt ${new Date(i.created).toLocaleString("de-DE", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" })} · <code>${i.hash ? i.hash.slice(0, 12) : "wird versiegelt…"}</code></button>
    <footer>
      <button class="like ${liked ? "on" : ""}" data-like="${i.id}"><span class="heart">♥</span> ${i.likes + (liked ? 1 : 0)}</button>
      <span class="muted" title="So oft wurde die Idee gehandelt">🔁 ${i.copies || 0}</span>
      ${t.me ? `<span class="up royalty-chip">💸 ${eur(i.royalty || 0)}</span>` : ""}
      <span class="spacer"></span>
      <button class="btn primary small" data-idea-trade="${i.id}" ${i.status !== "open" ? "disabled" : ""}>${i.status !== "open" ? "Abgeschlossen" : "Idee handeln"}</button>
    </footer>
  </article>`;
}
function renderIdeaStats() {
  const mine = community.state.ideas.map((i) => community.evaluate(i));
  const closed = mine.filter((i) => i.status !== "open");
  const hit = closed.length ? closed.filter((i) => i.status === "target").length / closed.length : null;
  const copies = mine.reduce((a, i) => a + (i.copies || 0), 0);
  const log = community.state.royaltyLog.slice(0, 4);
  $("#idea-stats").innerHTML = `
    <div class="is-tile big"><span>Deine Royalties</span><b class="up">${eur(community.state.royaltyTotal || 0)}</b><small>Creator-Anteil ${Math.round(plan().creatorShare * 100)} %${plan().creatorShare < 0.7 ? ` · <button class="fee-up" data-open-plans>bis 70 % mit Elite</button>` : ""}</small></div>
    <div class="is-tile"><span>Deine Ideen</span><b>${mine.length}</b><small>${mine.length - closed.length} laufen</small></div>
    <div class="is-tile"><span>Trefferquote (verifiziert)</span><b>${hit == null ? "–" : Math.round(hit * 100) + " %"}</b><small>${closed.length} abgeschlossen</small></div>
    <div class="is-tile"><span>Von anderen gehandelt</span><b>${copies}×</b><small>Trades auf deine Ideen</small></div>
    <div class="is-feed">${log.length ? log.map((e) => `<div><b>@${esc(e.copier)}</b> handelt deine ${e.symbol}-Idee <span class="up">+${eur(e.royalty)}</span></div>`).join("") : `<div class="muted">Teile eine Idee – sobald andere sie handeln, verdienst du mit.</div>`}</div>`;
}
function renderIdeas() {
  if (settings.view !== "ideas") return;
  renderIdeaStats();
  const f = ui.ideaFilter;
  const ideas = community.allIdeas().filter((i) => (f === "all" ? true : f === "mine" ? i.author === "me" : f === "following" ? community.isFollowing(i.author) : i.dir === f));
  $("#ideas-grid").innerHTML = ideas.length ? ideas.map((i, k) => ideaCard(i, k)).join("") : `<div class="empty card">Noch keine Ideen in diesem Filter. ${f === "mine" ? "Teile deine erste Idee über „+ Idee teilen“." : ""}</div>`;
  renderLeaderboard();
}
function renderLeaderboard() {
  if (settings.view !== "ideas") return;
  const me = { id: "me", handle: "du", style: "Dein Demo-Depot", color: "#6ea2f2", me: true, ret1y: broker.equity() / START_CASH - 1, winRate: broker.stats().winRate ?? 0, followers: 0 };
  const rows = [...community.traders, me].sort((a, b) => b.ret1y - a.ret1y);
  const medal = ["🥇", "🥈", "🥉"];
  $("#leaderboard").innerHTML = rows
    .map((t, i) => {
      const st = t.me ? null : community.traderStats(t.id);
      return `<div class="lb-row ${t.me ? "me" : ""}">
      <span class="rank">${medal[i] || i + 1}</span>${avatar(t)}
      <div class="who"><b>@${esc(t.handle)}</b><small>${t.me ? esc(t.style) : `${st.hitRate == null ? "–" : "✓ " + Math.round(st.hitRate * 100) + " % Treffer"} · ${compact(t.followers)} Follower`}</small></div>
      <b class="num ${cls(t.ret1y)}">${pct(t.ret1y)}</b>
      ${t.me ? "<span></span>" : `<button class="mini-btn" data-copy="${t.id}">Kopieren</button>`}
    </div>`;
    })
    .join("");
}
function openCopy(id) {
  const t = community.trader(id);
  ui.copyTrader = id;
  $("#copy-title").textContent = `Portfolio von @${t.handle} kopieren`;
  $("#copy-alloc").innerHTML = `<div class="copy-head">${avatar(t)}<div><b>@${esc(t.handle)}</b><small class="muted">${esc(t.style)} · Rendite 1 J. <span class="${cls(t.ret1y)}">${pct(t.ret1y)}</span> · Risiko ${t.risk}/7</small></div></div>
    <div class="alloc-bar">${t.favs.map((s, i) => `<i style="flex-grow:${t.weights[i]};background:hsl(${210 + i * 40} 80% 60%)"></i>`).join("")}</div>
    <ul class="alloc-list">${t.favs.map((s, i) => `<li><i style="background:hsl(${210 + i * 40} 80% 60%)"></i><b>${s}</b><span>${esc(market.get(s).n)}</span><span class="muted">${nf2.format(t.weights[i] * 100)} %</span></li>`).join("")}</ul>`;
  updateCopyHint();
  openModal("#copy-modal");
}
function updateCopyHint() {
  const amt = parseFloat($("#copy-amount").value) || 0;
  const n = community.trader(ui.copyTrader).favs.length;
  $("#copy-hint").innerHTML = plan().limits.copy
    ? `${n} Market-Orders über insgesamt ca. ${eur(amt)} (Gebühren: ${eur(plan().fee * n)}).`
    : `🔒 Copy-Trading ist Teil von <b>AKYTEX Elite</b>.`;
}
function bindGrowth() {
  syncPlan();
  document.addEventListener("click", (e) => {
    const t = e.target;
    if (t.closest("[data-open-plans]")) return openPlans();
    const pc = t.closest(".plan-choose");
    if (pc) return choosePlan(pc.dataset.plan);
    const go = t.closest("[data-goto]");
    if (go) return setView(go.dataset.goto);
    const hs = t.closest("[data-home-sym]");
    if (hs) {
      homeSym = hs.dataset.homeSym;
      buildHomeChart();
      renderHomeLive(true);
      return;
    }
    const os = t.closest("[data-open-sym]");
    if (os) {
      if (os.dataset.openTf && os.dataset.openTf !== settings.tf) setTimeframe(os.dataset.openTf);
      return setSymbol(os.dataset.openSym);
    }
    const lk = t.closest("[data-like]");
    if (lk) {
      const on = community.toggleLike(lk.dataset.like);
      haptic(8);
      lk.classList.toggle("on", on);
      const n = parseInt(lk.textContent.replace(/\D/g, ""), 10) + (on ? 1 : -1);
      lk.innerHTML = `<span class="heart">♥</span> ${n}`;
      return;
    }
    const fl = t.closest("[data-follow]");
    if (fl) {
      const on = community.toggleFollow(fl.dataset.follow);
      haptic(8);
      toast(on ? `Du folgst jetzt @${community.trader(fl.dataset.follow).handle}.` : "Nicht mehr gefolgt.", on ? "success" : "info");
      return renderIdeas();
    }
    const tr = t.closest("[data-idea-trade]");
    if (tr) return openIdeaTrade(tr.dataset.ideaTrade);
    const sealBtn = t.closest("[data-seal]");
    if (sealBtn) {
      const i = community.find(sealBtn.dataset.seal);
      if (i) toast(`${new Date(i.created).toLocaleString("de-DE")} · SHA-256 ${i.hash ? i.hash.slice(0, 32) + "…" : "–"} · verkettet mit ${i.prev ? i.prev.slice(0, 8) + "…" : "–"}`, "info", "🔒 Versiegelte Idee");
      return;
    }
    const bill = t.closest("[data-billing]");
    if (bill) {
      settings.billing = bill.dataset.billing;
      saveSettings();
      haptic(6);
      for (const el of [$("#home-plans"), $("#modal-plans")]) if (el.childElementCount) renderPlans(el);
      return;
    }
    const ad = t.closest("[data-addon]");
    if (ad) return toggleAddon(ad.dataset.addon);
    const cp = t.closest("[data-copy]");
    if (cp) return openCopy(cp.dataset.copy);
    const flt = t.closest("#idea-filter [data-f]");
    if (flt) {
      ui.ideaFilter = flt.dataset.f;
      $$("#idea-filter button").forEach((b) => b.classList.toggle("active", b === flt));
      return renderIdeas();
    }
    const dir = t.closest("#idea-dir [data-d]");
    if (dir) {
      ui.ideaDir = dir.dataset.d;
      $$("#idea-dir button").forEach((b) => b.classList.toggle("active", b === dir));
      fillIdeaLevels();
    }
  });
  $("#plan-btn").addEventListener("click", () => openPlans());
  $("#hero-install").addEventListener("click", () => $("#install-btn").click());
  $("#copy-amount").addEventListener("input", updateCopyHint);
  $("#copy-form").addEventListener("submit", (e) => {
    e.preventDefault();
    if (!plan().limits.copy) {
      closeModals();
      setTimeout(() => openPlans("Copy-Trading ist Teil von AKYTEX Elite."), 330);
      return;
    }
    const t = community.trader(ui.copyTrader);
    const amt = parseFloat($("#copy-amount").value) || 0;
    let ok = 0;
    t.favs.forEach((sym, i) => {
      const q = market.quote(sym);
      const qty = Math.floor((amt * t.weights[i]) / q.ask);
      if (qty > 0 && broker.placeOrder({ symbol: sym, side: "buy", type: "market", qty }).ok) ok++;
    });
    closeModals();
    if (ok) {
      confetti();
      toast(`${ok} Positionen von @${t.handle} ins Depot übernommen.`, "success", "Portfolio kopiert");
    } else toast("Betrag zu klein oder nicht genug Kaufkraft.", "error");
  });
  $("#publish-btn").addEventListener("click", openIdeaModal);
  $("#idea-sym").addEventListener("change", fillIdeaLevels);
  $("#itrade-qty").addEventListener("input", updateIdeaTradeCosts);
  $("#itrade-form").addEventListener("submit", (e) => {
    e.preventDefault();
    const i = community.find(ui.tradeIdea);
    if (!i) return;
    const res = broker.placeOrder({ symbol: i.symbol, side: "buy", type: "market", qty: parseInt($("#itrade-qty").value, 10), sl: i.sl, tp: i.tp, ideaId: i.id, ideaFeePct: plan().ideaFee });
    if (!res.ok) {
      shake($("#itrade-form"));
      return toast(res.msg, "error", "Order abgelehnt");
    }
    i.copies = (i.copies || 0) + 1;
    closeModals();
    confetti();
    const fill = broker.state.fills[0];
    toast(`@${authorOf(i).handle} erhält ${eur((fill?.ideaFee || 0) * 0.5)} Royalty. Stop & Ziel sind gesetzt.`, "success", `Idee gehandelt: ${i.symbol}`);
    renderIdeas();
  });
  $("#idea-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const sym = $("#idea-sym").value;
    const entry = market.get(sym).price;
    const tp = parseFloat($("#idea-tp").value);
    const sl = parseFloat($("#idea-sl").value);
    const long = ui.ideaDir === "long";
    if (!(long ? tp > entry && sl < entry : tp < entry && sl > entry)) {
      shake($("#idea-form"));
      return toast(long ? "Bei Long muss das Ziel über und der Stop unter dem Kurs liegen." : "Bei Short muss das Ziel unter und der Stop über dem Kurs liegen.", "error", "Bitte Ziel & Stop prüfen");
    }
    await community.addIdea({
      symbol: sym,
      tf: settings.tf,
      dir: ui.ideaDir,
      title: $("#idea-title").value.trim(),
      body: $("#idea-body").value.trim(),
      entry,
      tp,
      sl,
      img: sym === settings.symbol ? ui.ideaShot : null,
    });
    closeModals();
    confetti();
    toast("Versiegelt und veröffentlicht. Sobald andere sie handeln, verdienst du Royalties.", "success", "Idee ist live 🔒");
    ui.ideaFilter = "all";
    $$("#idea-filter button").forEach((b) => b.classList.toggle("active", b.dataset.f === "all"));
    if (settings.view !== "ideas") setView("ideas");
    else renderIdeas();
  });
}
function openIdeaModal() {
  $("#idea-sym").innerHTML = STOCKS.map((s) => `<option value="${s.s}" ${s.s === settings.symbol ? "selected" : ""}>${s.s} – ${esc(s.n)}</option>`).join("");
  $("#idea-title").value = "";
  $("#idea-body").value = "";
  ui.ideaShot = null;
  try {
    const src = chart.screenshot();
    if (!src.width || !src.height) throw new Error("Chart nicht sichtbar");
    const w = 560;
    const c = document.createElement("canvas");
    c.width = w;
    c.height = Math.round((src.height / src.width) * w) || 300;
    c.getContext("2d").drawImage(src, 0, 0, c.width, c.height);
    ui.ideaShot = c.toDataURL("image/jpeg", 0.72);
    $("#idea-shot").src = ui.ideaShot;
    $("#idea-shot").hidden = false;
  } catch (_) {
    $("#idea-shot").hidden = true;
  }
  fillIdeaLevels();
  openModal("#idea-modal");
  setTimeout(() => $("#idea-title").focus(), 50);
}
// Einstieg/Ziel/Stop aus der AKYTEX-AI-Analyse vorschlagen
function fillIdeaLevels() {
  const sym = $("#idea-sym").value;
  const st = market.get(sym);
  const a = analyze(st.days.slice(-260));
  const u = a.atr * 0.6;
  const e = st.price;
  const long = ui.ideaDir === "long";
  const step = tickStep(e);
  $("#idea-entry").value = e.toFixed(2);
  $("#idea-tp").value = roundTo(long ? e + 2 * u : e - 2 * u, step).toFixed(2);
  $("#idea-sl").value = roundTo(long ? e - u : e + u, step).toFixed(2);
}
function openIdeaTrade(id) {
  const i = community.find(id);
  if (!i) return;
  if (i.status !== "open") return toast("Diese Idee ist bereits abgeschlossen.", "info");
  if (i.dir !== "long") return toast("Short-Ideen lassen sich im Demo-Depot nicht handeln (keine Leerverkäufe).", "warn", "Nur Long-Ideen");
  ui.tradeIdea = id;
  const t = authorOf(i);
  const q = market.quote(i.symbol);
  const riskQty = Math.floor((broker.equity() * 0.01) / Math.max(0.01, q.ask - i.sl));
  const capQty = Math.floor((broker.equity() * 0.1) / q.ask); // höchstens 10 % des Depots
  $("#itrade-qty").value = Math.max(1, Math.min(riskQty, capQty, Math.floor(broker.buyingPower() / q.ask)));
  $("#itrade-info").innerHTML = `
    <div class="it-head">${avatar(t)}<div><b>${esc(i.title)}</b><small class="muted">@${esc(t.handle)} · versiegelt ${ago(i.created)} · <code>${(i.hash || "").slice(0, 10)}</code></small></div></div>
    <div class="it-chart">${ideaChart(i, 360, 130)}</div>
    <div class="idea-levels"><span>Einstieg<b>${num(i.entry)}</b></span><span>Aktuell<b>${num(q.ask)}</b></span><span>Ziel<b class="up">${num(i.tp)}</b></span><span>Stop<b class="down">${num(i.sl)}</b></span></div>
    <p class="muted it-note">Ziel und Stop der Idee werden als Take-Profit und Stop-Loss übernommen. Stückzahl vorbelegt: max. 1 % Depotrisiko und höchstens 10 % des Depots.</p>`;
  updateIdeaTradeCosts();
  openModal("#itrade-modal");
}
function updateIdeaTradeCosts() {
  const i = community.find(ui.tradeIdea);
  if (!i) return;
  const t = authorOf(i);
  const q = market.quote(i.symbol);
  const qty = parseInt($("#itrade-qty").value, 10) || 0;
  const vol = qty * q.ask;
  const c = broker.costs(qty, q.ask, plan().ideaFee);
  const spread = ((q.ask - q.bid) / 2) * qty;
  $("#itrade-costs").innerHTML = `
    <div><dt>Ordervolumen</dt><dd>${eur(vol)}</dd></div>
    <div><dt>Ordergebühr (${plan().name})</dt><dd>${eur(c.orderFee)}</dd></div>
    <div><dt>Ideen-Gebühr (${nf2.format(plan().ideaFee * 100)} %)</dt><dd>${eur(c.ideaFee)}</dd></div>
    <div class="sub"><dt>davon an @${esc(t.handle)}</dt><dd>${eur(c.ideaFee * 0.5)}</dd></div>
    <div><dt>Spread-Kosten (im Kurs)</dt><dd>${eur(spread)}</dd></div>
    <div class="total"><dt>Kosten gesamt</dt><dd>${eur(c.total + spread)}</dd></div>`;
  $("#itrade-submit").textContent = `${qty} ${i.symbol} kaufen – Idee handeln`;
}
// ---------- Grafik-Helfer ----------
function donut(parts, center, size = 200) {
  const total = parts.reduce((a, p) => a + p.value, 0) || 1;
  const r = 70;
  const C = 2 * Math.PI * r;
  let acc = 0;
  const segs = parts
    .filter((p) => p.value > 0)
    .map((p) => {
      const len = (p.value / total) * C;
      const s = `<circle cx="100" cy="100" r="${r}" fill="none" stroke="${p.color}" stroke-width="26" stroke-dasharray="${Math.max(0, len - 2)} ${C}" stroke-dashoffset="${-acc}" transform="rotate(-90 100 100)" class="dn-seg"><title>${esc(p.label)}: ${nf2.format((p.value / total) * 100)} %</title></circle>`;
      acc += len;
      return s;
    })
    .join("");
  return `<div class="donut"><svg viewBox="0 0 200 200" width="${size}" height="${size}"><circle cx="100" cy="100" r="${r}" fill="none" stroke="var(--panel-2)" stroke-width="26"/>${segs}<text x="100" y="100" text-anchor="middle" class="dn-text">${center}</text></svg>
    <ul class="dn-legend">${parts.map((p) => `<li><i style="background:${p.color}"></i><span>${esc(p.label)}</span><b>${nf2.format((p.value / total) * 100)} %</b></li>`).join("")}</ul></div>`;
}
function tween(el, to, fmt, ms = 900) {
  const from = +el.dataset.v || 0;
  el.dataset.v = to;
  const t0 = performance.now();
  const stepF = (t) => {
    const k = Math.min(1, (t - t0) / ms);
    const e = 1 - Math.pow(1 - k, 4);
    el.textContent = fmt(from + (to - from) * e);
    if (k < 1) requestAnimationFrame(stepF);
  };
  requestAnimationFrame(stepF);
}
const bigEur = (v) => (v >= 1e9 ? nf2.format(v / 1e9) + " Mrd. €" : v >= 1e6 ? nf2.format(v / 1e6) + " Mio. €" : eur(v));

// ---------- Steuer-Report (Add-on) ----------
function renderTax() {
  const realized = broker.state.realized || 0;
  const taxable = Math.max(0, realized - 1000);
  const tax = taxable * 0.26375;
  const inner = `<div class="tax-grid">
      <div><span>Realisierte Gewinne (nach Gebühren)</span><b class="${cls(realized)}">${sEur(realized)}</b></div>
      <div><span>Sparerpauschbetrag</span><b>${eur(1000)}</b></div>
      <div><span>Steuerpflichtig</span><b>${eur(taxable)}</b></div>
      <div><span>Abgeltungsteuer + Soli (26,375 %)</span><b class="down">${eur(tax)}</b></div>
      <div><span>Gezahlte Gebühren</span><b>${eur(broker.state.fees || 0)}</b></div>
      <div><span>Royalties (Einkünfte)</span><b class="up">${eur(community.state.royaltyTotal || 0)}</b></div>
    </div><p class="muted">Vereinfachte Schätzung ohne Kirchensteuer und Verlustverrechnung. Keine Steuerberatung.</p>`;
  $("#tax-card").innerHTML = `<div class="card-head"><h2>🧾 Steuer-Report ${new Date().getFullYear()}</h2>${hasAddon("tax") ? '<span class="incl">aktiv</span>' : ""}</div>` +
    (hasAddon("tax") ? inner : `<div class="ai-lock"><div class="ai-lock-blur">${inner}</div><div class="ai-lock-cta"><b>🔒 Steuer-Report</b><span>Add-on für 2,99 €/Monat – in Elite inklusive</span><button class="btn primary small" data-open-plans>Freischalten</button></div></div>`);
}

// ---------- AI-Signal-Alarme (Add-on) ----------
const lastRatings = {};
function checkSignals() {
  if (!hasAddon("signals") || !chart.raw?.length) return;
  const key = settings.symbol + settings.tf;
  const r = analyze(chart.raw).rating;
  if (lastRatings[key] && lastRatings[key] !== r.key) {
    toast(`${settings.symbol} (${TIMEFRAMES.find((t) => t.id === settings.tf).label}) wechselt auf „${r.label}“.`, r.key.includes("buy") ? "success" : r.key.includes("sell") ? "sell" : "info", "⚡ AI-Signal");
    beep(990, 0.1);
    notify("AKYTEX AI-Signal", `${settings.symbol}: ${r.label}`);
  }
  lastRatings[key] = r.key;
}

// ---------- Royalties: andere handeln deine Ideen (Simulation) ----------
setInterval(() => {
  const ev = community.simulateCopies(plan().creatorShare);
  if (!ev.length) return;
  const sum = ev.reduce((a, e) => a + e.royalty, 0);
  broker.credit(sum, "Royalty");
  const e = ev[0];
  toast(`@${e.copier} handelt deine ${e.symbol}-Idee (${eur(e.volume)}).`, "success", `💸 +${eur(sum)} Royalty`);
  beep(1320, 0.08);
  if (settings.view === "ideas") renderIdeas();
}, 11000);

// ---------- Startseite: animierter Hintergrund & USP-Demo ----------
let heroRaf = 0;
function heroAnim(on) {
  const cv = $("#hero-canvas");
  cancelAnimationFrame(heroRaf);
  if (!on || !cv || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  const ctx = cv.getContext("2d");
  const dpr = Math.min(2, devicePixelRatio || 1);
  const candles = [];
  let price = 0.5;
  let t = 0;
  const resize = () => {
    cv.width = cv.clientWidth * dpr;
    cv.height = cv.clientHeight * dpr;
  };
  resize();
  const draw = () => {
    if (cv.width !== cv.clientWidth * dpr) resize();
    const W = cv.width;
    const H = cv.height;
    t++;
    if (t % 6 === 0) {
      const o = price;
      price = Math.min(0.85, Math.max(0.15, price + (Math.random() - 0.47) * 0.035));
      candles.push({ x: W + 10, o, c: price, h: Math.max(o, price) + Math.random() * 0.02, l: Math.min(o, price) - Math.random() * 0.02 });
    }
    ctx.clearRect(0, 0, W, H);
    const bw = 7 * dpr;
    for (const c of candles) {
      c.x -= 1.2 * dpr;
      const up = c.c >= c.o;
      const drift = (1 - c.x / W) * 0.25; // leicht ansteigend nach rechts
      const Y = (v) => H * (1 - v + drift - 0.1);
      ctx.globalAlpha = 0.16 * Math.min(1, c.x / (W * 0.3));
      ctx.fillStyle = ctx.strokeStyle = up ? "#4f8cff" : "#6ea2f2";
      ctx.beginPath();
      ctx.moveTo(c.x, Y(c.h));
      ctx.lineTo(c.x, Y(c.l));
      ctx.lineWidth = dpr;
      ctx.stroke();
      ctx.fillRect(c.x - bw / 2, Math.min(Y(c.o), Y(c.c)), bw, Math.max(2, Math.abs(Y(c.o) - Y(c.c))));
    }
    while (candles.length && candles[0].x < -20) candles.shift();
    heroRaf = requestAnimationFrame(draw);
  };
  draw();
}
function renderUspDemo() {
  const el = $("#usp-demo");
  if (!el) return;
  const best = community.allIdeas().filter((i) => i.dir === "long").sort((a, b) => b.perf - a.perf)[0];
  if (!best) return;
  const royalty = (best.copies || 0) * 3000 * 0.002 * 0.5;
  el.innerHTML = `${ideaCard(best)}<div class="usp-earn"><span>@${esc(authorOf(best).handle)} hat mit dieser Idee verdient</span><b>${eur(royalty)}</b><small>${best.copies} Trades × Ø 3.000 € × 0,20 % × 50 % Creator-Anteil (Beispiel)</small></div>`;
}

// ---------- Business-Dashboard ----------
const BIZ = [
  { k: "users", label: "Nutzer", min: 4, max: 7.7, step: 0.01, val: 6, fmt: (v) => compact(Math.round(10 ** v)) },
  { k: "conv", label: "Anteil zahlender Nutzer", min: 1, max: 25, step: 0.5, val: 8, fmt: (v) => nf2.format(v) + " %" },
  { k: "yearly", label: "Anteil Jahresabos", min: 0, max: 100, step: 5, val: 50, fmt: (v) => v + " %" },
  { k: "trades", label: "Trades je aktivem Nutzer / Monat", min: 0, max: 20, step: 1, val: 4, fmt: (v) => String(v) },
  { k: "idea", label: "Anteil Ideen-Trades", min: 0, max: 60, step: 5, val: 20, fmt: (v) => v + " %" },
  { k: "cash", label: "Ø Guthaben pro Nutzer", min: 0, max: 10000, step: 250, val: 2000, fmt: (v) => eur(v) },
  { k: "margin", label: "Zinsmarge auf Guthaben", min: 0, max: 3, step: 0.1, val: 1, fmt: (v) => nf2.format(v) + " %" },
  { k: "multiple", label: "Bewertung (× Jahresumsatz)", min: 3, max: 20, step: 0.5, val: 10, fmt: (v) => nf2.format(v) + "×" },
];
const bizVals = Object.fromEntries(BIZ.map((b) => [b.k, b.val]));
function bizModel(v, usersOverride) {
  const users = usersOverride ?? 10 ** v.users;
  const conv = v.conv / 100;
  const paid = users * conv;
  const y = v.yearly / 100;
  const mix = { plus: 0.44, pro: 0.38, elite: 0.125, ai: 0.04, aiprem: 0.015 };
  const subsM = paid * PLANS.filter((p) => mix[p.id]).reduce((a, p) => a + mix[p.id] * (y * p.yearly + (1 - y) * p.monthly), 0);
  const trades = users * 0.35 * v.trades;
  const streams = [
    { label: "Abos", color: "#4f8cff", value: subsM * 12 },
    { label: "Add-ons", color: "#a78bfa", value: paid * 0.25 * 5.5 * 12 },
    { label: "Ordergebühren", color: "#22c55e", value: trades * (1 - v.idea / 100) * ((1 - conv) * 1 + conv * 0.45 * 0.5) * 12 },
    { label: "Ideen-Börse", color: "#f59e0b", value: trades * (v.idea / 100) * 1500 * 0.0018 * 0.45 * 12 },
    { label: "Zinsmarge", color: "#06b6d4", value: users * v.cash * (v.margin / 100) },
  ];
  const arr = streams.reduce((a, s) => a + s.value, 0);
  return { users, paid, streams, arr, mrr: arr / 12, valuation: arr * v.multiple, arpu: arr / users };
}
function renderBusiness(full = false) {
  if (settings.view !== "business") return;
  const box = $("#biz-sliders");
  if (!box.childElementCount) {
    box.innerHTML = BIZ.map(
      (b) => `<label class="slider"><span>${b.label}<b id="bv-${b.k}">${b.fmt(bizVals[b.k])}</b></span>
      <input type="range" id="bs-${b.k}" min="${b.min}" max="${b.max}" step="${b.step}" value="${bizVals[b.k]}" /></label>`
    ).join("");
    box.addEventListener("input", (e) => {
      const b = BIZ.find((x) => "bs-" + x.k === e.target.id);
      if (!b) return;
      bizVals[b.k] = +e.target.value;
      $("#bv-" + b.k).textContent = b.fmt(bizVals[b.k]);
      renderBusiness();
    });
  }
  const m = bizModel(bizVals);
  tween($("#biz-valuation"), m.valuation, bigEur, full ? 1400 : 500);
  const need = 1e9 / (m.arpu * bizVals.multiple);
  const prog = Math.min(1, Math.log10(Math.max(1, m.valuation)) / 11); // Skala bis 100 Mrd.
  const unicorn = Math.log10(1e9) / 11;
  $("#biz-bill").innerHTML = `
    <div class="uni-bar"><i style="width:${prog * 100}%"></i><span class="uni-mark" style="left:${unicorn * 100}%">🦄 1 Mrd.</span></div>
    <p>${m.valuation >= 1e9 ? `<b class="up">Unicorn-Status erreicht.</b> ` : ""}Für 1 Mrd. € Bewertung braucht AKYTEX bei diesen Annahmen <b>${compact(Math.round(need))} Nutzer</b>.</p>`;
  $("#biz-kpis").innerHTML = [
    ["Jahresumsatz (ARR)", bigEur(m.arr)],
    ["Monatsumsatz (MRR)", bigEur(m.mrr)],
    ["Zahlende Nutzer", compact(Math.round(m.paid))],
    ["Umsatz je Nutzer / Jahr", eur(m.arpu)],
  ]
    .map(([k, v]) => `<div><span>${k}</span><b>${v}</b></div>`)
    .join("");
  $("#biz-arr-lbl").textContent = bigEur(m.arr) + " / Jahr";
  $("#biz-donut").innerHTML = donut(m.streams, `<tspan x="100" dy="-4" class="dn-big">${bigEur(m.arr).replace(" €", "")}</tspan><tspan x="100" dy="18" class="dn-sub">€ pro Jahr</tspan>`, 220);

  // 5-Jahres-Pfad
  const W = 900;
  const H = 260;
  const Q = 20;
  const pts = [];
  for (let q = 0; q <= Q; q++) {
    const s = 1 / (1 + Math.exp(-(q / Q - 0.55) * 9));
    const s0 = 1 / (1 + Math.exp(0.55 * 9));
    const users = 1e4 + (m.users - 1e4) * ((s - s0) / (1 - s0));
    pts.push({ q, v: bizModel(bizVals, users).valuation });
  }
  const maxV = Math.max(pts[Q].v, 1.15e9) * 1.08;
  const X = (q) => 50 + (q / Q) * (W - 70);
  const Y = (v) => 16 + (1 - v / maxV) * (H - 46);
  const path = pts.map((p, i) => `${i ? "L" : "M"}${X(p.q).toFixed(1)} ${Y(p.v).toFixed(1)}`).join(" ");
  const yb = Y(1e9);
  const ticks = [0, 0.25, 0.5, 0.75, 1].map((f) => f * maxV);
  $("#biz-proj").innerHTML = `<svg viewBox="0 0 ${W} ${H}" class="proj-svg">
    <defs><linearGradient id="pg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4f8cff" stop-opacity=".45"/><stop offset="1" stop-color="#4f8cff" stop-opacity="0"/></linearGradient></defs>
    ${ticks.map((v) => `<line x1="50" x2="${W - 20}" y1="${Y(v)}" y2="${Y(v)}" stroke="var(--border)"/><text x="44" y="${Y(v) + 4}" text-anchor="end" class="ax">${bigEur(v).replace(" €", "")}</text>`).join("")}
    ${[0, 1, 2, 3, 4, 5].map((y) => `<text x="${X(y * 4)}" y="${H - 8}" text-anchor="middle" class="ax">${y === 0 ? "Start" : "Jahr " + y}</text>`).join("")}
    <path d="${path} L${X(Q)} ${Y(0)} L${X(0)} ${Y(0)} Z" fill="url(#pg)"/>
    <path d="${path}" fill="none" stroke="#6ea2f2" stroke-width="3" class="proj-line"/>
    <line x1="50" x2="${W - 20}" y1="${yb}" y2="${yb}" stroke="#d4af37" stroke-dasharray="6 5" stroke-width="1.5"/>
    <text x="${W - 22}" y="${yb - 7}" text-anchor="end" class="ax gold">🦄 1 Mrd. € Bewertung</text>
    <circle cx="${X(Q)}" cy="${Y(pts[Q].v)}" r="6" fill="#6ea2f2" stroke="var(--panel)" stroke-width="3"/>
  </svg>`;

  // Funnel
  const stages = [
    ["Besucher", m.users * 4, "#334155"],
    ["Demo-Nutzer", m.users, "#4f8cff"],
    ["Aktive Trader", m.users * 0.35, "#22c55e"],
    ["Zahlende Abonnenten", m.paid, "#f59e0b"],
    ["Elite- & AI-Kunden", m.paid * 0.18, "#d4af37"],
  ];
  const top = Math.sqrt(stages[0][1]);
  $("#biz-funnel").innerHTML = stages
    .map(([l, v, c]) => `<div class="fn-row"><div class="fn-bar" style="width:${Math.max(6, (Math.sqrt(v) / top) * 100)}%;background:${c}"><span>${compact(Math.round(v))}</span></div><em>${l}</em></div>`)
    .join("");
}

// ---------- AKYTEX AI: Ansicht, Chat, Autopilot ----------
let llm = null; // Sprachmodell (nur in Claude-Umgebungen verfügbar)
let llmOff = false;
let chatCtl = null;
const chat = []; // { role: "user"|"assistant", text, html, actions }
const aiActions = new Map();
try {
  window.claude?.use?.("sample")?.then((s) => {
    llm = s || null;
    renderAIHeader();
  }).catch(() => {});
} catch (_) {
  /* nicht verfügbar */
}
const aiUniverse = () => (aiEngine.state.config.universe === "watchlist" ? settings.watchlist : STOCKS.map((s) => s.s));

function ring(value, label, size = 86, color = "#6ea2f2") {
  const r = 34;
  const C = 2 * Math.PI * r;
  return `<div class="ring" style="--s:${size}px"><svg viewBox="0 0 80 80"><circle cx="40" cy="40" r="${r}" class="ring-bg"/><circle cx="40" cy="40" r="${r}" class="ring-fg" stroke="${color}" stroke-dasharray="${(value / 100) * C} ${C}" transform="rotate(-90 40 40)"/></svg><b>${value}</b><span>${label}</span></div>`;
}
const scoreColor = (v) => (v >= 70 ? "#22c55e" : v >= 45 ? "#f59e0b" : "#ef4444");

function renderAIHeader() {
  if (!$("#ai-chips")) return;
  const mode = aiMode();
  const c = aiEngine.state.config;
  const ap = !mode ? "Autopilot gesperrt" : c.enabled ? (mode === "auto" && c.mode === "auto" ? "Autopilot handelt" : "Autopilot schlägt vor") : "Autopilot aus";
  $("#ai-chips").innerHTML = `
    <span class="chip-s ${mode ? "on" : ""}">${mode ? "✓ " + plan().name : "🔒 Nicht im Tarif " + plan().name}</span>
    <span class="chip-s ${c.enabled && mode ? "live" : ""}"><i></i>${ap}</span>
    <span class="chip-s">${llm && !llmOff ? "🧠 Sprachmodell: Claude" : "⚙️ AKYTEX Engine (lokal)"}</span>`;
  $("#ai-model").textContent = llm && !llmOff ? "antwortet mit Claude" : "lokale AKYTEX Engine";
  const n = aiEngine.state.unread;
  $("#ai-badge").hidden = !n || !mode;
  $("#ai-badge").textContent = n > 9 ? "9+" : n;
}

function renderAIView(full = false) {
  if (settings.view !== "ai") return;
  const mode = aiMode();
  renderAIHeader();
  const doc = aiEngine.doctor();
  $("#ai-score").innerHTML = ring(doc.score, "Depot-Score", 128, scoreColor(doc.score));
  $("#ai-locked").hidden = !!mode;
  $("#ai-main").classList.toggle("is-locked", !mode);
  $("#ai-opps-card").classList.toggle("is-locked", !mode);
  $("#ai-doctor-card").classList.toggle("is-locked", !mode);
  $$('.ai-pane[data-aipane="plan"], .ai-pane[data-aipane="lab"]').forEach((p) => p.classList.toggle("is-locked", !mode));
  if (!mode) {
    $("#ai-locked").innerHTML = `<div class="lock-card"><div class="orb small"><i></i><i></i><i></i></div><div><h3>AKYTEX AI freischalten</h3><p>Berater-Chat, Meldungen, Depot-Doktor und Autopilot gibt es in <b>AKYTEX AI</b> (ab 79 €/Monat) und <b>AI Premium</b> mit selbstständig handelndem Autopilot.</p></div><button class="btn primary big" data-open-plans>Tarife ansehen</button></div>`;
  }
  if (full && !chat.length) {
    chat.push({ role: "assistant", html: `<p>Hallo! Ich bin <b>AKYTEX AI</b>. Ich kenne dein Depot, scanne alle ${STOCKS.length} Aktien laufend und helfe dir bei Entscheidungen. Frag mich etwas – oder tippe auf einen Vorschlag.</p>` });
  }
  if (aiTab !== "cockpit") {
    if (aiTab === "plan") renderPlanPane();
    if (aiTab === "lab" && full) renderLab();
    if (aiTab === "features") renderFeatures();
    return;
  }
  renderChat();
  renderAutopilot();
  renderFeed();
  renderOpps();
  renderDoctor(doc);
  if (mode && full) {
    aiEngine.state.unread = 0;
    aiEngine.save();
    renderAIHeader();
    if (!aiEngine.state.feed.length) aiEngine.briefing(aiUniverse());
  }
}

function fmtLLM(text) {
  const lines = esc(text).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>").split("\n");
  let html = "";
  let inList = false;
  for (const l of lines) {
    const m = l.match(/^\s*[-•*]\s+(.*)/);
    if (m) {
      if (!inList) html += "<ul>";
      inList = true;
      html += `<li>${m[1]}</li>`;
    } else {
      if (inList) html += "</ul>";
      inList = false;
      if (l.trim()) html += `<p>${l}</p>`;
    }
  }
  return html + (inList ? "</ul>" : "");
}

function renderChat() {
  const log = $("#chat-log");
  if (!log) return;
  log.innerHTML = chat
    .map((m, k) => {
      const acts = (m.actions || [])
        .map((a) => {
          const id = "a" + k + "_" + Math.random().toString(36).slice(2, 7);
          aiActions.set(id, a);
          return `<button class="${a.primary ? "btn primary small" : "mini-btn"}" data-ai-act="${id}" ${a.done ? "disabled" : ""}>${a.done ? "✓ " : ""}${esc(a.label)}</button>`;
        })
        .join("");
      return `<div class="msg ${m.role}">${m.role === "assistant" ? '<span class="msg-av">✦</span>' : ""}<div class="bubble">${m.role === "assistant" && !m.pending && k > 0 ? `<button class="speak" data-speak="${k}" title="Vorlesen">🔊</button>` : ""}${m.html ?? esc(m.text)}${m.pending ? '<span class="typing"><i></i><i></i><i></i></span>' : ""}${acts ? `<div class="msg-acts">${acts}</div>` : ""}</div></div>`;
    })
    .join("");
  log.scrollTop = log.scrollHeight;
}

async function sendChat(text) {
  text = text.trim();
  if (!text) return;
  if (!aiMode()) return openPlans("Der Berater-Chat ist Teil von AKYTEX AI.");
  chat.push({ role: "user", text });
  const msg = { role: "assistant", html: "", pending: true };
  chat.push(msg);
  renderChat();
  haptic(6);
  if (llm && !llmOff) {
    try {
      await llmAnswer(text, msg);
      return;
    } catch (e) {
      if (e?.code === "cancelled") {
        msg.pending = false;
        msg.html = msg.html || "<p class='muted'>Abgebrochen.</p>";
        renderChat();
        return;
      }
      if (["not_granted", "sampling_disabled", "tools_unavailable", "not_declared", "capability_disabled", "capability_removed"].includes(e?.code)) llmOff = true;
      msg.note = e?.code === "rate_limited" ? "Das Sprachmodell ist gerade ausgelastet – ich antworte mit der lokalen Engine." : "";
      renderAIHeader();
    } finally {
      $("#chat-stop").hidden = true;
    }
  }
  // Lokale Engine: kurze „Denkpause“, dann Antwort
  await new Promise((r) => setTimeout(r, 450 + Math.random() * 500));
  const ans = aiEngine.answer(text, { universe: aiUniverse(), scheduler, community });
  msg.pending = false;
  msg.html = (msg.note ? `<p class="muted">${msg.note}</p>` : "") + ans.html;
  msg.actions = ans.actions;
  renderChat();
}

async function llmAnswer(text, msg) {
  const rules = `Du bist AKYTEX AI, der KI-Berater und Quant-Analyst der Trading-App AKYTEX. Denke wie ein erfahrener Portfoliomanager: prüfe mehrere Werkzeuge (Analyse, Muster, Prognose, Backtest, Risiko), bevor du urteilst, und begründe knapp mit Zahlen. Wichtig: Es ist eine Demo mit simulierten Kursen in EUR und virtuellem Geld. Antworte auf Deutsch, freundlich und konkret, höchstens 150 Wörter. Hole dir Zahlen immer über die Tools, bevor du sie nennst, und erfinde keine. Du führst niemals selbst Orders aus: Wenn du einen Kauf oder Verkauf empfiehlst, rufe propose_trade auf – der Nutzer bestätigt per Button. Nenne bei Empfehlungen kurz das Risiko und dass es keine Anlageberatung ist. Formatiere nur mit kurzen Absätzen und Aufzählungen ("- ").
Kontext: Tarif ${plan().name}. Geöffnete Aktie: ${settings.symbol}. Watchlist: ${settings.watchlist.join(", ")}. Verfügbare Symbole: ${STOCKS.map((s) => s.s).join(", ")}.`;
  const history = chat
    .slice(0, -2)
    .filter((m) => (m.text || m.plain) && !m.pending)
    .slice(-8)
    .map((m) => ({ role: m.role, content: m.text || m.plain }));
  const turns = [{ role: "user", content: rules }, ...history, { role: "user", content: text }];
  const proposals = [];
  const tools = [
    { name: "get_portfolio", description: "Liefert das Depot des Nutzers: Gesamtwert, Guthaben, Depot-Score, Positionen mit Gewicht, Gewinn/Verlust und AI-Rating sowie Hinweise.", execute: () => aiEngine.toolPortfolio() },
    {
      name: "analyze_stock",
      description: "Technische Analyse einer Aktie: Kurs, Tagesänderung, AI-Score und Rating, Begründung, RSI, Unterstützung, Widerstand, vorgeschlagener Stop und Ziel.",
      inputSchema: { type: "object", properties: { symbol: { type: "string", description: "Tickersymbol, z. B. SAP" } }, required: ["symbol"] },
      execute: (i) => {
        const sym = String(i.symbol || "").toUpperCase();
        if (!market.has(sym)) throw new Error("Unbekanntes Symbol " + sym);
        return aiEngine.toolAnalyze(sym);
      },
    },
    { name: "scan_market", description: "Scannt alle Aktien und liefert die stärksten und schwächsten Signale mit Begründung.", execute: () => aiEngine.toolScan(aiUniverse()) },
    {
      name: "propose_trade",
      description: "Schlägt dem Nutzer eine Order vor. Sie wird NICHT ausgeführt, sondern als Button angezeigt, den der Nutzer bestätigen muss. side ist buy oder sell.",
      inputSchema: { type: "object", properties: { side: { type: "string", enum: ["buy", "sell"] }, symbol: { type: "string" }, qty: { type: "integer" }, reason: { type: "string" } }, required: ["side", "symbol", "qty"] },
      execute: (i) => {
        const sym = String(i.symbol || "").toUpperCase();
        const qty = Math.floor(Number(i.qty));
        const side = i.side === "sell" ? "sell" : "buy";
        if (!market.has(sym) || !(qty > 0)) throw new Error("Ungültiger Vorschlag");
        const v = aiEngine.toolAnalyze(sym);
        proposals.push({ label: `${qty} ${sym} ${side === "buy" ? "kaufen" : "verkaufen"}`, side, sym, qty, primary: true, sl: side === "buy" ? v.suggestedStop : undefined, tp: side === "buy" ? v.suggestedTarget : undefined });
        return "Vorschlag wird dem Nutzer als Button angezeigt.";
      },
    },
    {
      name: "forecast",
      description: "Statistischer Prognose-Korridor einer Aktie für 20 Handelstage (Perzentile 5/25/50/75/95) und Wahrscheinlichkeit, +10 % zu berühren.",
      inputSchema: { type: "object", properties: { symbol: { type: "string" } }, required: ["symbol"] },
      execute: (i) => {
        const sym = String(i.symbol || "").toUpperCase();
        if (!market.has(sym)) throw new Error("Unbekanntes Symbol");
        const f = lab.forecast(market, sym, 20);
        const e = f.path[20];
        return { price: +f.price.toFixed(2), p5: +e.p5.toFixed(2), p25: +e.p25.toFixed(2), p50: +e.p50.toFixed(2), p75: +e.p75.toFixed(2), p95: +e.p95.toFixed(2), probPlus10Pct: +lab.probReach(market, sym, f.price * 1.1, 20).toFixed(2) };
      },
    },
    {
      name: "backtest",
      description: "Backtest von drei Strategien (SMA-Kreuzung, RSI-Umkehr, MACD mit Trendfilter) auf ca. 2 Jahren Tagesdaten; liefert Rendite, Trades, Trefferquote, maximalen Rückgang und Kaufen-und-Halten.",
      inputSchema: { type: "object", properties: { symbol: { type: "string" } }, required: ["symbol"] },
      execute: (i) => {
        const sym = String(i.symbol || "").toUpperCase();
        if (!market.has(sym)) throw new Error("Unbekanntes Symbol");
        return ["sma", "rsi", "macd"].map((k) => {
          const r = lab.backtest(market, sym, k);
          return { strategy: r.label, returnPct: +(r.ret * 100).toFixed(1), buyHoldPct: +(r.buyHold * 100).toFixed(1), trades: r.trades, winRate: r.winRate, maxDrawdownPct: +(r.maxDD * 100).toFixed(1) };
        });
      },
    },
    {
      name: "patterns",
      description: "Muster-Scan einer Aktie: Kerzenmuster, RSI-Divergenz, Bollinger-Squeeze, Ausbruch, Trendstärke (ADX), Unterstützungs- und Widerstandszonen, Multi-Timeframe-Konsens.",
      inputSchema: { type: "object", properties: { symbol: { type: "string" } }, required: ["symbol"] },
      execute: (i) => {
        const sym = String(i.symbol || "").toUpperCase();
        if (!market.has(sym)) throw new Error("Unbekanntes Symbol");
        const bars = lab.barsFor(market, sym, "1D");
        const z = lab.zones(bars);
        const m = lab.mtf(market, sym);
        return { candles: lab.patterns(bars).map((p) => p.name), divergence: lab.divergence(bars)?.text || null, squeeze: lab.squeeze(bars), adx: lab.adx(bars), supports: z.supports.map((x) => +x.level.toFixed(2)), resistances: z.resistances.map((x) => +x.level.toFixed(2)), mtf: m.frames.map((f) => `${f.tf}: ${f.rating.label}`), confidencePct: lab.confidence(market, sym) };
      },
    },
    { name: "portfolio_risk", description: "Risiko des Depots: Value at Risk 95/99 %, Expected Shortfall, Monte-Carlo-Perzentile nach 1 Jahr und Verlustwahrscheinlichkeit.", execute: () => {
        const v = lab.valueAtRisk(broker, market);
        const mc = lab.monteCarlo(broker, market, 252, 300);
        return { var95: Math.round(v.var95), var99: Math.round(v.var99), es95: Math.round(v.es95), mcP5: Math.round(mc.p5), mcMedian: Math.round(mc.p50), mcP95: Math.round(mc.p95), lossProbability: +mc.lossProb.toFixed(2) };
      } },
    { name: "market_overview", description: "Marktüberblick: AKYTEX Sentiment-Index (Angst & Gier), Sektor-Rotation und Anomalien.", execute: () => ({ sentiment: lab.sentimentIndex(market), sectors: lab.sectorRotation(market).map((x) => ({ name: x.name, d5: +(x.d5 * 100).toFixed(1), d20: +(x.d20 * 100).toFixed(1), phase: x.phase })), anomalies: lab.anomalies(market).map((x) => x.sym) }) },
    {
      name: "propose_schedule",
      description: "Schlägt einen zeitgesteuerten Auftrag, Sparplan oder eine Wenn-Dann-Regel vor (Beschreibung in natürlicher Sprache, z. B. 'Kaufe 10 SAP um 15:30', 'Sparplan 200 € ASML monatlich', 'Verkaufe TSLA wenn über 260'). Der Nutzer bestätigt per Button.",
      inputSchema: { type: "object", properties: { instruction: { type: "string" } }, required: ["instruction"] },
      execute: (i) => {
        const task = scheduler.parse(String(i.instruction || ""), (x) => aiEngine.findSymbols(x));
        if (!task) throw new Error("Konnte den Auftrag nicht verstehen");
        const desc = scheduler.describe({ ...task, at: task.at || Date.now() });
        proposals.push({ label: `Zeitplan: ${desc}`, schedule: task, primary: true });
        return "Vorschlag angezeigt: " + desc;
      },
    },
    { name: "daily_plan", description: "Erstellt den KI-Tagesplan (schwache Positionen reduzieren, fehlende Stops setzen, starke Chancen kaufen). Wird dem Nutzer als ausführbarer Plan angezeigt.", execute: () => {
        const steps = lab.dailyPlan(aiEngine, broker, market, aiUniverse());
        if (steps.length) proposals.push({ label: `Plan ausführen (${steps.length} Schritte)`, plan: steps, primary: true });
        return steps.map((x) => x.why);
      } },
    { name: "get_autopilot", description: "Status und Einstellungen des Autopiloten sowie die letzten Entscheidungen.", execute: () => ({ ...aiEngine.state.config, tier: aiMode(), lastDecisions: aiEngine.state.log.slice(0, 5).map((l) => `${l.side} ${l.qty} ${l.sym}: ${l.why}`) }) },
  ];
  chatCtl = new AbortController();
  $("#chat-stop").hidden = false;
  const { text: out } = await llm(turns, {
    tools,
    modelTier: "quick",
    signal: chatCtl.signal,
    onText: ({ text: t }) => {
      msg.pending = false;
      msg.html = fmtLLM(t);
      renderChat();
    },
  });
  msg.pending = false;
  msg.plain = out;
  msg.html = fmtLLM(out);
  msg.actions = proposals;
  renderChat();
}

function runAiAction(a, btn) {
  if (a.open) return setSymbol(a.open);
  const done = () => {
    a.done = true;
    btn.disabled = true;
    btn.textContent = "✓ " + a.label;
  };
  if (a.schedule) {
    scheduler.add(a.schedule);
    done();
    toast(scheduler.describe(scheduler.state.tasks[0]), "success", "⏱ Auftrag angelegt");
    return;
  }
  if (a.alert) {
    broker.addAlert(a.alert.sym, a.alert.price);
    done();
    return toast(`Alarm für ${a.alert.sym} bei ${num(a.alert.price)} € aktiv.`, "success");
  }
  if (a.watch) {
    for (const s of a.watch) if (!settings.watchlist.includes(s)) settings.watchlist.push(s);
    saveSettings();
    buildWatchlist();
    done();
    return toast(`${a.watch.length} Aktien in der Watchlist.`, "success");
  }
  if (a.idea) {
    openIdeaModal();
    $("#idea-sym").value = a.idea.sym;
    ui.ideaDir = a.idea.dir;
    $$("#idea-dir button").forEach((b) => b.classList.toggle("active", b.dataset.d === a.idea.dir));
    fillIdeaLevels();
    $("#idea-tp").value = a.idea.tp.toFixed(2);
    $("#idea-sl").value = a.idea.sl.toFixed(2);
    $("#idea-title").value = a.idea.title;
    $("#idea-body").value = a.idea.body;
    return;
  }
  if (a.lab) {
    if (a.sym) labSym = a.sym;
    labFocus = a.lab;
    return setAiTab("lab");
  }
  if (a.plan) {
    let ok = 0;
    for (const st of a.plan) {
      let r;
      if (st.kind === "stop") r = broker.placeOrder({ symbol: st.sym, side: "sell", type: "stop", qty: st.qty, stopPrice: roundTo(st.price, tickStep(st.price)) });
      else r = broker.placeOrder({ symbol: st.sym, side: st.kind === "buy" ? "buy" : "sell", type: "market", qty: st.qty });
      if (r.ok) ok++;
    }
    done();
    aiEngine.state.log.unshift({ ts: Date.now(), by: "Du (KI-Plan)", side: "buy", sym: a.plan.map((x) => x.sym).join(", "), qty: ok, price: 0, why: `${ok} von ${a.plan.length} Schritten ausgeführt` });
    aiEngine.save();
    return toast(`${ok} von ${a.plan.length} Schritten ausgeführt.`, ok ? "success" : "error", "KI-Plan");
  }
  if (a.limit) {
    const r = broker.placeOrder({ symbol: a.sym, side: a.side, type: "limit", qty: a.qty, limitPrice: a.limit });
    if (!r.ok) return toast(r.msg, "error", "Order abgelehnt");
    return done();
  }
  const order = { symbol: a.sym, side: a.side, type: "market", qty: a.qty };
  if (a.side === "buy" && a.sl && a.tp) {
    const q = market.quote(a.sym);
    if (a.sl < q.ask && a.tp > q.ask) {
      const step = tickStep(q.ask);
      order.sl = roundTo(a.sl, step);
      order.tp = roundTo(a.tp, step);
    }
  }
  const r = broker.placeOrder(order);
  if (!r.ok) return toast(r.msg, "error", "Order abgelehnt");
  a.done = true;
  btn.disabled = true;
  btn.textContent = "✓ " + a.label;
  aiEngine.state.log.unshift({ ts: Date.now(), by: "Du (AI-Berater)", side: a.side, sym: a.sym, qty: a.qty, price: market.get(a.sym).price, why: "Vom Berater vorgeschlagen, von dir bestätigt" });
  aiEngine.save();
  if (settings.view === "ai") renderAutopilot();
}

function renderAutopilot() {
  const el = $("#autopilot");
  if (!el) return;
  const c = aiEngine.state.config;
  const mode = aiMode();
  const auto = mode === "auto";
  const eq = broker.equity();
  const managed = Object.keys(aiEngine.state.managed).filter((s) => broker.position(s));
  const used = managed.reduce((a, s) => a + broker.position(s).qty * market.get(s).price, 0);
  const sl = (k, label, min, max, step, fmt) => `<label class="slider"><span>${label}<b id="apv-${k}">${fmt(c[k])}</b></span><input type="range" id="ap-${k}" data-ap="${k}" min="${min}" max="${max}" step="${step}" value="${c[k]}" /></label>`;
  el.innerHTML = `
    <div class="ap-head">
      <div class="orb tiny ${c.enabled && mode ? "spin" : ""}"><i></i><i></i><i></i></div>
      <div><h2>Autopilot</h2><small class="muted">${c.enabled && mode ? (auto && c.mode === "auto" ? "handelt selbstständig" : "macht Vorschläge") : "pausiert"}</small></div>
      <button class="switch big ${c.enabled ? "on" : ""}" id="ap-toggle" aria-pressed="${c.enabled}" aria-label="Autopilot ein/aus"><i></i></button>
    </div>
    <div class="seg ap-mode" role="group">
      <button class="${c.mode === "assist" ? "active" : ""}" data-apmode="assist">Vorschläge</button>
      <button class="${c.mode === "auto" ? "active" : ""}" data-apmode="auto">${auto ? "" : "🔒 "}Autonom</button>
    </div>
    <div class="seg ap-strat" role="group">${Object.entries(STRATEGIES).map(([k, v]) => `<button class="${c.strategy === k ? "active" : ""}" data-apstrat="${k}" title="${v.desc}">${v.label}</button>`).join("")}</div>
    <p class="muted ap-desc">${STRATEGIES[c.strategy].desc}</p>
    ${sl("budgetPct", "Budget für den Autopiloten", 5, 100, 5, (v) => v + " % des Depots")}
    ${sl("maxPosPct", "Max. je Aktie", 2, 25, 1, (v) => v + " %")}
    ${sl("stopPct", "Stop-Loss", 2, 20, 0.5, (v) => "−" + nf2.format(v) + " %")}
    ${sl("takePct", "Gewinnziel", 4, 40, 1, (v) => "+" + v + " %")}
    ${sl("maxTrades", "Max. Trades pro Tag", 1, 40, 1, (v) => String(v))}
    <div class="ap-row"><label class="chk"><input type="checkbox" id="ap-all" ${c.manageAll ? "checked" : ""}/> Auch meine eigenen Positionen verwalten</label>
      <select id="ap-universe"><option value="all" ${c.universe === "all" ? "selected" : ""}>Alle ${STOCKS.length} Aktien</option><option value="watchlist" ${c.universe === "watchlist" ? "selected" : ""}>Nur Watchlist</option></select></div>
    <div class="ap-stats">
      <div><span>Investiert</span><b>${eur(used)}</b><small>${nf2.format((used / eq) * 100)} % von ${c.budgetPct} %</small></div>
      <div><span>Positionen</span><b>${managed.length}</b><small>von der AI verwaltet</small></div>
      <div><span>Realisiert</span><b class="${cls(aiEngine.state.aiPnl)}">${sEur(aiEngine.state.aiPnl)}</b><small>AI-Trades</small></div>
    </div>
    <div class="ap-budget"><i style="width:${Math.min(100, (used / eq) * 100 / Math.max(1, c.budgetPct) * 100)}%"></i></div>
    ${aiEngine.state.proposals.length ? `<h4 class="ap-h">Offene Vorschläge</h4>${aiEngine.state.proposals.map((p) => `<div class="prop ${p.side}"><div><b>${p.side === "buy" ? "Kaufen" : "Verkaufen"}: ${p.qty} ${p.sym}</b><small>${esc(p.why)}</small></div><div class="prop-btns"><button class="btn primary small" data-prop-ok="${p.id}">Ausführen</button><button class="mini-btn" data-prop-no="${p.id}">✕</button></div></div>`).join("")}` : ""}
    <h4 class="ap-h">Protokoll</h4>
    <div class="ap-log">${aiEngine.state.log.length ? aiEngine.state.log.slice(0, 12).map((l) => `<div class="ap-entry ${l.side}"><span class="tag ${l.side}">${l.side === "buy" ? "Kauf" : "Verkauf"}</span><div><b>${l.qty} ${l.sym}</b> <small class="muted">${clock(l.ts)} · ${esc(l.by)}</small><small>${esc(l.why)}</small></div></div>`).join("") : '<div class="muted">Noch keine Entscheidungen.</div>'}</div>
    <button class="btn kill" id="ap-kill">⏻ Not-Aus</button>`;
}

function renderFeed() {
  const el = $("#ai-feed");
  if (!el) return;
  const f = aiEngine.state.feed;
  el.innerHTML = f.length
    ? f
        .slice(0, 20)
        .map(
          (m) => `<div class="feed-item ${m.kind}"><span class="fi-ic">${m.icon}</span><div><b>${esc(m.title)}</b><p>${esc(m.text)}</p><small class="muted">${ago(m.ts)}</small>
          ${m.proposal && aiEngine.state.proposals.some((p) => p.id === m.proposal) ? `<div class="msg-acts"><button class="btn primary small" data-prop-ok="${m.proposal}">Ausführen</button><button class="mini-btn" data-prop-no="${m.proposal}">Ablehnen</button></div>` : m.sym ? `<div class="msg-acts"><button class="mini-btn" data-ask="Was hältst du von ${m.sym}?">Fragen</button><button class="mini-btn" data-open-sym="${m.sym}">Chart</button></div>` : ""}</div></div>`
        )
        .join("")
    : `<div class="muted">Noch keine Meldungen. Die AI meldet sich bei Signalwechseln, starken Bewegungen und Risiken.</div>`;
}

function renderOpps() {
  const el = $("#ai-opps");
  if (!el) return;
  const top = aiEngine.scanAll(aiUniverse()).slice(0, 6);
  el.innerHTML = top
    .map((v) => {
      const closes = aggregateCloses(v.sym);
      const sc = Math.round((v.score + 1) * 50);
      return `<button class="opp" data-ask="Was hältst du von ${v.sym}?">
        <div class="opp-top">${ring(sc, "Score", 58, sc >= 60 ? "#22c55e" : sc >= 45 ? "#f59e0b" : "#ef4444")}<div><b>${v.sym}</b><small class="muted">${esc(v.name)}</small><span class="opp-rt ${v.score > 0.1 ? "up" : ""}">${v.rating.label}</span></div></div>
        ${spark(closes, 200, 40, "#6ea2f2")}
        <p>${esc(v.reason)}</p>
        <div class="opp-px"><b>${num(v.price)} €</b><span class="${cls(v.dayChg)}">${pct(v.dayChg)}</span></div>
      </button>`;
    })
    .join("");
}
function aggregateCloses(sym) {
  const m1 = market.get(sym).m1;
  const out = [];
  for (let i = Math.max(0, m1.length - 1440); i < m1.length; i += 20) out.push(m1[i].close);
  out.push(m1[m1.length - 1].close);
  return out;
}

function renderDoctor(doc) {
  const el = $("#ai-doctor");
  if (!el) return;
  el.innerHTML = `
    <div class="doc-rings">${ring(doc.parts.div, "Streuung", 92, scoreColor(doc.parts.div))}${ring(doc.parts.risk, "Risiko", 92, scoreColor(doc.parts.risk))}${ring(doc.parts.qual, "Qualität", 92, scoreColor(doc.parts.qual))}${ring(doc.parts.liq, "Liquidität", 92, scoreColor(doc.parts.liq))}</div>
    <ul class="doc-tips">${doc.tips.map((t) => `<li><span>${t.icon}</span><p>${esc(t.text)}</p>${t.sym ? `<button class="mini-btn" data-ask="Soll ich ${t.sym} verkaufen?">Beraten</button>` : ""}</li>`).join("")}</ul>`;
}

function bindAI() {
  $("#chat-form").addEventListener("submit", (e) => {
    e.preventDefault();
    const v = $("#chat-input").value;
    $("#chat-input").value = "";
    sendChat(v);
  });
  $("#chat-stop").addEventListener("click", () => chatCtl?.abort());
  $("#feed-clear").addEventListener("click", () => {
    aiEngine.state.unread = 0;
    aiEngine.save();
    renderAIHeader();
  });
  document.addEventListener("click", (e) => {
    const t = e.target;
    const spk = t.closest("[data-speak]");
    if (spk) {
      const tmp = document.createElement("div");
      tmp.innerHTML = chat[+spk.dataset.speak].html || "";
      return speak(tmp.textContent);
    }
    const ask = t.closest("[data-ask]");
    if (ask) {
      if (settings.view !== "ai") setView("ai");
      return sendChat(ask.dataset.ask);
    }
    const act = t.closest("[data-ai-act]");
    if (act) {
      const a = aiActions.get(act.dataset.aiAct);
      if (a && !a.done) runAiAction(a, act);
      return;
    }
    const ok = t.closest("[data-prop-ok]");
    if (ok) {
      const r = aiEngine.acceptProposal(ok.dataset.propOk);
      if (!r.ok) toast(r.msg, "error", "Nicht ausgeführt");
      return renderAIView();
    }
    const no = t.closest("[data-prop-no]");
    if (no) {
      aiEngine.dismissProposal(no.dataset.propNo);
      return renderAIView();
    }
    if (t.closest("#ap-toggle")) {
      if (!aiMode()) return openPlans("Der Autopilot ist Teil von AKYTEX AI.");
      const c = aiEngine.state.config;
      c.enabled = !c.enabled;
      aiEngine.save();
      haptic(15);
      toast(c.enabled ? (aiMode() === "auto" && c.mode === "auto" ? "Der Autopilot handelt jetzt selbstständig in deinen Limits." : "Der Autopilot schlägt dir Trades vor – du entscheidest.") : "Autopilot pausiert.", c.enabled ? "success" : "info", c.enabled ? "🤖 Autopilot an" : "Autopilot aus");
      if (c.enabled) setTimeout(autopilotTick, 800);
      return renderAIView();
    }
    const md = t.closest("[data-apmode]");
    if (md) {
      if (md.dataset.apmode === "auto" && aiMode() !== "auto") return openPlans("Selbstständiges Handeln ist Teil von AKYTEX AI Premium.");
      aiEngine.state.config.mode = md.dataset.apmode;
      aiEngine.save();
      return renderAIView();
    }
    const stg = t.closest("[data-apstrat]");
    if (stg) {
      aiEngine.state.config.strategy = stg.dataset.apstrat;
      aiEngine.save();
      return renderAutopilot();
    }
    if (t.closest("#ap-kill")) {
      aiEngine.killSwitch();
      haptic([40, 30, 40]);
      toast("Autopilot gestoppt, offene Vorschläge verworfen. Deine Positionen und Stops bleiben bestehen.", "warn", "⏻ Not-Aus");
      return renderAIView();
    }
  });
  document.addEventListener("input", (e) => {
    const k = e.target.dataset?.ap;
    if (!k) return;
    aiEngine.state.config[k] = +e.target.value;
    aiEngine.save();
    const fmt = { budgetPct: (v) => v + " % des Depots", maxPosPct: (v) => v + " %", stopPct: (v) => "−" + nf2.format(v) + " %", takePct: (v) => "+" + v + " %", maxTrades: (v) => String(v) }[k];
    $("#apv-" + k).textContent = fmt(+e.target.value);
  });
  document.addEventListener("change", (e) => {
    if (e.target.id === "ap-all") aiEngine.state.config.manageAll = e.target.checked;
    else if (e.target.id === "ap-universe") aiEngine.state.config.universe = e.target.value;
    else return;
    aiEngine.save();
  });
  aiEngine.on("trade", (l) => {
    toast(`${l.side === "buy" ? "Kauf" : "Verkauf"}: ${l.qty} ${l.sym} – ${l.why}`, l.side === "buy" ? "success" : "sell", "🤖 Autopilot");
    if (settings.view === "ai") renderAIView();
  });
  aiEngine.on("feed", (m) => {
    renderAIHeader();
    if (settings.view === "ai") renderFeed();
    else if (m.kind !== "briefing" && aiMode()) toast(m.text, m.kind === "risk" ? "warn" : "info", `✦ ${m.title}`);
  });
}

function autopilotTick() {
  const mode = aiMode();
  if (!mode || !aiEngine.state.config.enabled) return;
  aiEngine.step(aiUniverse(), mode === "auto" && aiEngine.state.config.mode === "auto");
  if (settings.view === "ai") renderAIView();
}
setInterval(autopilotTick, 15000);
setInterval(() => {
  if (!aiMode()) return;
  const syms = [...new Set([...settings.watchlist, ...Object.keys(broker.state.positions)])];
  aiEngine.watch(syms);
  if (settings.view === "ai") {
    renderOpps();
    renderDoctor(aiEngine.doctor());
    $("#ai-score").innerHTML = ring(aiEngine.doctor().score, "Depot-Score", 128, scoreColor(aiEngine.doctor().score));
  }
}, 25000);

// ---------- Bezahlsystem: Checkout ----------
const account = new AccountStore();
let co = null;
function choosePlan(id) {
  const p = planById(id);
  if (!p.monthly) {
    if (account.state.sub && account.state.sub.status !== "canceled") return openCancel();
    return setPlan("free");
  }
  openCheckout(id);
}
// ---------- AKYTEX Pay ----------
// Ein elegantes Bezahl-Sheet für Abos, Shop-Bestellungen und Zahlungsmethoden (Testmodus)
let pay = null;
function openCheckout(planId, startStep = 0) {
  if (startStep === 2) return openPay({ kind: "method" });
  const link = stripeLinkFor(planId, settings.billing);
  if (link && PAYMENT_CONFIG.mode === "live") {
    location.href = link;
    return;
  }
  openPay({ kind: "sub", planId, billing: settings.billing, addons: settings.addons.slice() });
}
function openPay(order) {
  const saved = account.state.method;
  pay = { promo: null, open: null, method: saved ? "saved" : "card", contact: { ...(account.state.profile || { name: "", email: "" }) }, address: { street: "", zip: "", city: "" }, ...order };
  if (!account.state.profile && pay.kind !== "method") pay.open = "contact";
  else if (!saved || pay.kind === "method") pay.open = "method";
  closeModals();
  setTimeout(() => {
    renderPay();
    openModal("#pay-modal");
  }, 330);
}
function stepper(el, i) {
  $$(el + " span").forEach((s, k) => {
    s.classList.toggle("on", k <= i);
    s.classList.toggle("cur", k === i);
  });
}
function payTotals() {
  if (pay.kind === "sub") {
    const q = quote({ planId: pay.planId, billing: pay.billing, addons: pay.addons, promo: pay.promo });
    return { q, due: 0, after: q.total, lines: q.lines, discount: q.discount, vat: q.vat };
  }
  if (pay.kind === "shop") {
    const lines = pay.items.map((i) => ({ label: `${i.qty}× ${i.name}`, amount: i.price * i.qty }));
    const sub = lines.reduce((s, l) => s + l.amount, 0);
    const physical = pay.items.some((i) => i.physical);
    const ship = physical && sub < 50 ? 4.9 : 0;
    if (ship) lines.push({ label: "Versand (kostenlos ab 50 €)", amount: ship });
    const pr = pay.promo && PAYMENT_CONFIG.promos[pay.promo];
    const discount = pr?.pct ? sub * pr.pct : 0;
    const total = sub + ship - discount;
    return { due: total, lines, discount, vat: total - total / (1 + PAYMENT_CONFIG.vatRate), physical };
  }
  return { due: 0, lines: [], discount: 0, vat: 0 };
}
function methodLabel(m) {
  return m === "saved" ? account.state.method?.label : { card: "Neue Karte", paypal: "PayPal", apple: "Apple Pay", google: "Google Pay", sepa: "SEPA-Lastschrift", klarna: "Klarna" }[m];
}
function renderPay() {
  const T = payTotals();
  const trialEnd = new Date(Date.now() + PAYMENT_CONFIG.trialDays * 86400000).toLocaleDateString("de-DE");
  const p = pay.kind === "sub" ? planById(pay.planId) : null;
  const row = (key, label, value, body) => `<div class="ps-row ${pay.open === key ? "open" : ""}" data-row="${key}"><button class="ps-head" data-ps-toggle="${key}"><span>${label}</span><b>${value}</b><i>›</i></button><div class="ps-body"><div>${body}</div></div></div>`;
  let hero;
  if (pay.kind === "sub") hero = `<div class="ps-product ${p.group ? "ai" : ""}"><div class="orb tiny spin"><i></i><i></i><i></i></div><div><b>${planTitle(p)}</b><small>${pay.billing === "yearly" ? "Jahresabo" : "Monatsabo"} · ${PAYMENT_CONFIG.trialDays} Tage gratis</small></div></div><div class="ps-amount"><span>Heute</span><b>0,00 €</b><small>danach ${eur(T.after)} ${pay.billing === "yearly" ? "pro Jahr" : "pro Monat"} ab ${trialEnd}</small></div>`;
  else if (pay.kind === "shop") hero = `<div class="ps-product"><div class="ps-cart-ic">🛍️</div><div><b>AKYTEX Store</b><small>${pay.items.reduce((s, i) => s + i.qty, 0)} Artikel</small></div></div><div class="ps-amount"><span>Gesamt</span><b>${eur(T.due)}</b><small>inkl. ${eur(T.vat)} MwSt.</small></div>`;
  else hero = `<div class="ps-product"><div class="ps-cart-ic">💳</div><div><b>Zahlungsmethode</b><small>für dein AKYTEX-Abo</small></div></div>`;

  const rows = [];
  if (pay.kind === "sub") {
    const paid = PLANS.filter((x) => x.monthly);
    rows.push(
      row(
        "plan",
        "Tarif",
        `${p.name} · ${pay.billing === "yearly" ? "jährlich" : "monatlich"}`,
        `<div class="ps-plans">${paid.map((x) => `<button class="${x.id === pay.planId ? "on" : ""} ${x.group ? "ai" : ""}" data-ps-plan="${x.id}"><b>${x.name}</b><span>${eur(planPrice(x, pay.billing))}</span></button>`).join("")}</div>
         <div class="seg ps-bill"><button class="${pay.billing === "monthly" ? "active" : ""}" data-ps-bill="monthly">Monatlich</button><button class="${pay.billing === "yearly" ? "active" : ""}" data-ps-bill="yearly">Jährlich <span class="save-chip">−23 %</span></button></div>
         <div class="ps-addons">${ADDONS.map((a) => {
           const incl = a.includedIn.includes(pay.planId);
           return `<label><input type="checkbox" data-ps-addon="${a.id}" ${incl || pay.addons.includes(a.id) ? "checked" : ""} ${incl ? "disabled" : ""}/> ${a.icon} ${a.name}<b>${incl ? "inklusive" : "+" + eur(a.price)}</b></label>`;
         }).join("")}</div>`
      )
    );
  }
  if (pay.kind === "shop") rows.push(row("items", "Warenkorb", `${pay.items.length} Position${pay.items.length > 1 ? "en" : ""}`, `<ul class="ps-items">${pay.items.map((i) => `<li><span>${i.icon || "•"}</span><div><b>${esc(i.name)}</b><small>${i.qty} × ${eur(i.price)}</small></div><b>${eur(i.qty * i.price)}</b></li>`).join("")}</ul>`));
  if (pay.kind !== "method") {
    rows.push(row("promo", "Gutschein", pay.promo ? `✓ ${pay.promo}` : "Hinzufügen", `<div class="promo"><input type="text" id="ps-promo" placeholder="z. B. AKYTEX20" value="${pay.promo || ""}" /><button class="btn" data-ps-promo>Einlösen</button></div>`));
    rows.push(
      row(
        "contact",
        "Kontakt",
        pay.contact.name ? esc(pay.contact.name) : "Angeben",
        `<div class="row2"><label class="field"><span>Name</span><input type="text" id="ps-name" value="${esc(pay.contact.name || "")}" autocomplete="name" maxlength="60" /></label><label class="field"><span>E-Mail (optional)</span><input type="email" id="ps-email" value="${esc(pay.contact.email || "")}" autocomplete="email" maxlength="120" /></label></div><p class="muted small">Nur in diesem Browser gespeichert.</p>`
      )
    );
  }
  if (T.physical)
    rows.push(row("address", "Lieferadresse", pay.address.city ? `${esc(pay.address.zip)} ${esc(pay.address.city)}` : "Angeben", `<label class="field"><span>Straße & Nr.</span><input type="text" id="ps-street" value="${esc(pay.address.street)}" autocomplete="street-address" /></label><div class="row2"><label class="field"><span>PLZ</span><input type="text" id="ps-zip" value="${esc(pay.address.zip)}" autocomplete="postal-code" /></label><label class="field"><span>Ort</span><input type="text" id="ps-city" value="${esc(pay.address.city)}" autocomplete="address-level2" /></label></div>`));
  const m = pay.method;
  const tabs = [["card", "💳 Karte"], ["paypal", "PayPal"], ["apple", "Apple Pay"], ["google", "Google Pay"], ["sepa", "SEPA"], ["klarna", "Klarna"]];
  let form = "";
  if (m === "card")
    form = `<div class="card-visual" id="card-visual"><div class="cv-chip"></div><div class="cv-brand" id="cv-brand"></div><div class="cv-num" id="cv-num">•••• •••• •••• ••••</div><div class="cv-row"><span id="cv-name">KARTENINHABER</span><span id="cv-exp">MM/JJ</span></div></div>
      <label class="field"><span>Kartennummer</span><input type="text" id="cc-num" inputmode="numeric" autocomplete="off" placeholder="4242 4242 4242 4242" /></label>
      <div class="row3"><label class="field"><span>Gültig bis</span><input type="text" id="cc-exp" inputmode="numeric" autocomplete="off" placeholder="MM/JJ" /></label><label class="field"><span>CVC</span><input type="text" id="cc-cvc" inputmode="numeric" autocomplete="off" placeholder="123" maxlength="4" /></label><label class="field"><span>Name</span><input type="text" id="cc-name" autocomplete="off" placeholder="Max Muster" /></label></div>
      <div class="testcards"><span class="muted small">Testkarten:</span><button class="mini-btn" data-tc="4242424242424242">Erfolg</button><button class="mini-btn" data-tc="4000002500003155">3-D Secure</button><button class="mini-btn" data-tc="4000000000000002">Abgelehnt</button></div>`;
  else if (m === "sepa") form = `<label class="field"><span>Kontoinhaber</span><input type="text" id="sepa-name" autocomplete="off" /></label><label class="field"><span>IBAN</span><input type="text" id="sepa-iban" autocomplete="off" placeholder="DE89 3704 0044 0532 0130 00" /></label><div class="testcards"><span class="muted small">Test-IBAN:</span><button class="mini-btn" data-tiban>einsetzen</button></div>`;
  else if (m !== "saved") form = `<div class="wallet-pane"><div class="wallet-logo ${m}">${{ paypal: "PayPal", apple: "Apple Pay", google: "Google Pay", klarna: "Klarna." }[m]}</div><p class="muted small">Du bestätigst im nächsten Schritt (simuliert).</p></div>`;
  rows.push(
    row(
      "method",
      "Bezahlen mit",
      methodLabel(m) || "Wählen",
      `${account.state.method ? `<button class="ps-saved ${m === "saved" ? "on" : ""}" data-ps-method="saved"><span>💳</span><b>${esc(account.state.method.label)}</b><small>gespeichert</small></button>` : ""}
       <div class="pay-tabs">${tabs.map(([k, l]) => `<button class="${m === k ? "on" : ""}" data-ps-method="${k}">${l}</button>`).join("")}</div>
       <div class="pay-form" id="pay-form">${form}</div>`
    )
  );
  const sumRows = `${T.lines.map((l) => `<div><span>${esc(l.label)}</span><b>${eur(l.amount)}</b></div>`).join("")}${T.discount ? `<div class="up"><span>Gutschein ${pay.promo}</span><b>−${eur(T.discount)}</b></div>` : ""}<div class="muted"><span>enthaltene MwSt. (19 %)</span><span>${eur(T.vat)}</span></div>`;
  $("#pay-sheet").innerHTML = `
    <div class="ps-top"><div class="ps-brand">ΛKYTEX <span>Pay</span></div><span class="test-chip">🧪 Testmodus</span><button class="icon-btn" data-close>✕</button></div>
    <div class="ps-hero">${hero}</div>
    <div class="ps-rows">${rows.join("")}</div>
    ${pay.kind !== "method" ? `<details class="ps-sum"><summary>Kostenübersicht</summary><div class="co-sum">${sumRows}</div></details>` : ""}
    ${pay.kind !== "method" ? `<label class="chk legal-chk"><input type="checkbox" id="ps-legal" /> Ich akzeptiere die <a href="#" data-legal-open="terms">AGB</a>, die <a href="#" data-legal-open="withdrawal">Widerrufsbelehrung</a> und die <a href="#" data-legal-open="risk">Risikohinweise</a>.</label>` : ""}
    <p class="co-err" id="co-err" hidden></p>
    <button class="hold-pay" id="hold-pay" aria-label="Zum Bezahlen gedrückt halten"><span class="hp-fill"></span><span class="hp-label">${pay.kind === "method" ? "Zum Speichern halten" : pay.kind === "sub" ? "Zum Abonnieren halten · zahlungspflichtig" : `Zum Bezahlen halten · ${eur(T.due)}`}</span></button>
    <p class="ps-foot">🔒 Ende-zu-Ende verschlüsselt · Testmodus: es wird nichts abgebucht, nur Testkarten</p>`;
  if (m === "card") bindCardInputs();
  bindHold();
}
function bindCardInputs() {
  const num = $("#cc-num");
  const upd = () => {
    const v = num.value.replace(/\D/g, "");
    $("#cv-num").textContent = formatCard(v) || "•••• •••• •••• ••••";
    const b = cardBrand(v);
    $("#cv-brand").textContent = { visa: "VISA", mastercard: "mastercard", amex: "AMEX" }[b] || "";
    $("#card-visual").dataset.brand = b;
  };
  num.addEventListener("input", () => {
    num.value = formatCard(num.value);
    upd();
  });
  $("#cc-exp").addEventListener("input", (e) => {
    let v = e.target.value.replace(/\D/g, "").slice(0, 4);
    if (v.length > 2) v = v.slice(0, 2) + "/" + v.slice(2);
    e.target.value = v;
    $("#cv-exp").textContent = v || "MM/JJ";
  });
  $("#cc-name").addEventListener("input", (e) => ($("#cv-name").textContent = e.target.value.toUpperCase() || "KARTENINHABER"));
  $("#cc-cvc").addEventListener("focus", () => $("#card-visual").classList.add("flip"));
  $("#cc-cvc").addEventListener("blur", () => $("#card-visual").classList.remove("flip"));
}
function coError(msg) {
  const e = $("#co-err");
  e.textContent = msg;
  e.hidden = false;
  shake($("#pay-sheet"));
  haptic([30, 40, 30]);
}
// Gedrückt halten zum Bezahlen (Maus, Touch oder Leertaste/Enter)
function bindHold() {
  const btn = $("#hold-pay");
  let timer = null;
  const start = (e) => {
    if (btn.classList.contains("busy")) return;
    e.preventDefault();
    const err = validatePay();
    if (err) return coError(err);
    $("#co-err").hidden = true;
    btn.classList.add("holding");
    haptic(8);
    timer = setTimeout(() => {
      btn.classList.remove("holding");
      btn.classList.add("busy");
      haptic([12, 30, 12]);
      runPay();
    }, 900);
  };
  const cancel = () => {
    clearTimeout(timer);
    btn.classList.remove("holding");
  };
  btn.addEventListener("pointerdown", start);
  btn.addEventListener("pointerup", cancel);
  btn.addEventListener("pointerleave", cancel);
  btn.addEventListener("keydown", (e) => {
    if ((e.key === " " || e.key === "Enter") && !e.repeat) start(e);
  });
  btn.addEventListener("keyup", cancel);
}
function readPayForms() {
  if ($("#ps-name")) pay.contact = { name: $("#ps-name").value.trim(), email: $("#ps-email").value.trim() };
  if ($("#ps-street")) pay.address = { street: $("#ps-street").value.trim(), zip: $("#ps-zip").value.trim(), city: $("#ps-city").value.trim() };
}
function openPayRow(key) {
  pay.open = key;
  $$("#pay-sheet .ps-row").forEach((r) => r.classList.toggle("open", r.dataset.row === key));
}
function validatePay() {
  readPayForms();
  if (pay.kind !== "method") {
    if (!pay.contact.name) {
      pay.open = "contact";
      renderPay();
      return "Bitte deinen Namen angeben.";
    }
    if (payTotals().physical && (!pay.address.street || !/^\d{5}$/.test(pay.address.zip) || !pay.address.city)) {
      pay.open = "address";
      renderPay();
      return "Bitte eine vollständige Lieferadresse angeben (PLZ fünfstellig).";
    }
    if (!$("#ps-legal").checked) return "Bitte AGB, Widerrufsbelehrung und Risikohinweise bestätigen.";
  }
  const m = pay.method;
  if (m === "saved") {
    pay.resolved = { method: account.state.method, needs3ds: false };
    return null;
  }
  if (m !== "saved" && pay.open !== "method") {
    openPayRow("method");
    if (m === "card" || m === "sepa") return "Bitte die Zahlungsdaten eingeben.";
  }
  if (m === "card") {
    const n = ($("#cc-num")?.value || "").replace(/\D/g, "");
    const exp = ($("#cc-exp")?.value || "").match(/^(\d{2})\/(\d{2})$/);
    if (!luhn(n)) return "Die Kartennummer ist ungültig.";
    const tc = TEST_CARDS[n];
    if (!tc) return "Testmodus: Bitte nur Testkarten verwenden (z. B. 4242 4242 4242 4242). Echte Karten werden nicht angenommen.";
    if (!exp || +exp[1] < 1 || +exp[1] > 12 || new Date(2000 + +exp[2], +exp[1]) < new Date()) return "Das Ablaufdatum ist ungültig oder abgelaufen.";
    if (!/^\d{3,4}$/.test($("#cc-cvc").value)) return "Bitte die Prüfnummer (CVC) eingeben.";
    pay.resolved = { tc, method: { type: "card", brand: tc.brand, last4: n.slice(-4), label: `${{ visa: "Visa", mastercard: "Mastercard", amex: "American Express" }[tc.brand]} •••• ${n.slice(-4)}` }, needs3ds: tc.result === "3ds" };
    return null;
  }
  if (m === "sepa") {
    const iban = $("#sepa-iban").value.replace(/\s/g, "").toUpperCase();
    if (!$("#sepa-name").value.trim()) return "Bitte den Kontoinhaber angeben.";
    if (iban !== TEST_IBAN) return "Testmodus: Bitte die Test-IBAN DE89 3704 0044 0532 0130 00 verwenden.";
    pay.resolved = { method: { type: "sepa", label: `SEPA-Lastschrift •••• ${iban.slice(-4)}` }, needs3ds: false };
    return null;
  }
  pay.resolved = { method: { type: m, label: { paypal: "PayPal (Testkonto)", apple: "Apple Pay (Test)", google: "Google Pay (Test)", klarna: "Klarna (Test)" }[m] }, needs3ds: false, wallet: true };
  return null;
}
async function runPay() {
  const btn = $("#hold-pay");
  const r = pay.resolved;
  // Biometrie-/Bestätigungs-Animation
  btn.querySelector(".hp-label").innerHTML = `<span class="face"><i></i></span> Bestätige …`;
  await new Promise((res) => setTimeout(res, 700));
  if (r.tc?.result === "declined" || r.tc?.result === "funds") {
    btn.classList.remove("busy");
    renderPay();
    return coError(r.tc.result === "declined" ? "Die Bank hat die Zahlung abgelehnt (Testkarte „abgelehnt“)." : "Nicht genügend Deckung (Testkarte).");
  }
  if (r.needs3ds || r.wallet) {
    const ok = await secureDialog(pay.method, r.needs3ds);
    if (!ok) {
      btn.classList.remove("busy");
      renderPay();
      return coError("Die Bestätigung wurde abgebrochen.");
    }
  }
  btn.querySelector(".hp-label").innerHTML = `<span class="spinner sm"></span> Wird verarbeitet …`;
  await new Promise((res) => setTimeout(res, 800));
  payComplete(r.method);
}
function payComplete(method) {
  if (pay.contact?.name) account.setProfile({ name: pay.contact.name, email: pay.contact.email || "" });
  let title;
  let sub;
  let actions = `<button class="btn primary" data-ps-done>Fertig</button>`;
  if (pay.kind === "method") {
    account.state.method = method;
    account.save();
    title = "Gespeichert";
    sub = method.label;
  } else if (pay.kind === "sub") {
    const q = payTotals().q;
    account.subscribe(q, method);
    settings.billing = pay.billing;
    settings.addons = pay.addons.slice();
    saveSettings();
    setPlan(pay.planId, true);
    title = `Willkommen bei ${planTitle(planById(pay.planId))}`;
    sub = `Testphase bis ${new Date(account.state.sub.trialEnds).toLocaleDateString("de-DE")} · alle Funktionen sind aktiv`;
    actions = `<button class="btn" data-invoice="0">Beleg</button>${actions}`;
  } else {
    const T = payTotals();
    account.state.method = account.state.method || method;
    const order = shopComplete(pay.items, T, method, pay.address);
    title = "Bestellung bestätigt";
    sub = `Bestellnummer ${order.no} · ${eur(T.due)}`;
    actions = `<button class="btn" data-invoice="0">Rechnung</button>${actions}`;
  }
  confetti();
  haptic([10, 40, 20]);
  syncAccountUI();
  $("#pay-sheet").innerHTML = `<div class="ps-success"><svg class="check" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36"/><path d="M24 41 l11 11 l22 -24"/></svg><h2>${esc(title)}</h2><p class="muted">${esc(sub)}</p><div class="co-done-actions">${actions}</div></div>`;
}
function secureDialog(m, is3ds) {
  return new Promise((resolve) => {
    const d = document.createElement("div");
    d.className = "secure-sheet";
    const title = is3ds ? "3-D Secure" : { paypal: "PayPal", apple: "Apple Pay", google: "Google Pay", klarna: "Klarna" }[m];
    d.innerHTML = `<div class="ss-box"><div class="ss-logo ${m}">${title}</div>
      <p>${is3ds ? "Deine Bank bittet um Bestätigung. Öffne deine Banking-App (simuliert) oder bestätige hier." : "Bestätige die Zahlung über " + title + " (simuliert)."}</p>
      <div class="ss-face" ${m === "apple" ? "" : "hidden"}><span></span></div>
      <div class="ss-actions"><button class="btn ghost" data-ss="0">Abbrechen</button><button class="btn primary" data-ss="1">${m === "apple" ? "Mit Face ID bestätigen" : "Bestätigen"}</button></div></div>`;
    $("#pay-sheet").appendChild(d);
    requestAnimationFrame(() => d.classList.add("open"));
    d.addEventListener("click", (e) => {
      const b = e.target.closest("[data-ss]");
      if (!b) return;
      const ok = b.dataset.ss === "1";
      const finish = () => {
        d.classList.remove("open");
        setTimeout(() => d.remove(), 350);
        resolve(ok);
      };
      if (ok && m === "apple") {
        d.querySelector(".ss-face").classList.add("scan");
        setTimeout(finish, 1100);
      } else finish();
    });
  });
}
function bindCheckout() {
  $("#pay-sheet").addEventListener("click", (e) => {
    const t = e.target;
    const tog = t.closest("[data-ps-toggle]");
    if (tog) {
      readPayForms();
      pay.open = pay.open === tog.dataset.psToggle ? null : tog.dataset.psToggle;
      $$("#pay-sheet .ps-row").forEach((r) => r.classList.toggle("open", r.dataset.row === pay.open));
      return;
    }
    const pl = t.closest("[data-ps-plan]");
    if (pl) {
      pay.planId = pl.dataset.psPlan;
      return renderPay();
    }
    const bl = t.closest("[data-ps-bill]");
    if (bl) {
      pay.billing = bl.dataset.psBill;
      return renderPay();
    }
    if (t.closest("[data-ps-promo]")) {
      const code = $("#ps-promo").value.trim().toUpperCase();
      if (!PAYMENT_CONFIG.promos[code] || (pay.kind === "shop" && !PAYMENT_CONFIG.promos[code].pct)) {
        shake($("#pay-sheet .promo"));
        return toast(`Der Code „${code}“ ist hier nicht gültig. Probier AKYTEX20.`, "error", "Gutschein");
      }
      pay.promo = code;
      pay.open = account.state.method ? null : "method";
      toast(PAYMENT_CONFIG.promos[code].label, "success", `Gutschein ${code} eingelöst`);
      return renderPay();
    }
    const me = t.closest("[data-ps-method]");
    if (me) {
      readPayForms();
      pay.method = me.dataset.psMethod;
      pay.open = "method";
      return renderPay();
    }
    const tc = t.closest("[data-tc]");
    if (tc) {
      $("#co-err").hidden = true;
      $("#cc-num").value = formatCard(tc.dataset.tc);
      $("#cc-exp").value = "12/" + String((new Date().getFullYear() + 3) % 100).padStart(2, "0");
      $("#cc-cvc").value = "123";
      $("#cc-name").value = pay.contact?.name || account.state.profile?.name || "Max Muster";
      ["#cc-num", "#cc-exp", "#cc-name"].forEach((s) => $(s).dispatchEvent(new Event("input")));
      return;
    }
    if (t.closest("[data-tiban]")) {
      $("#sepa-iban").value = "DE89 3704 0044 0532 0130 00";
      $("#sepa-name").value = pay.contact?.name || "Max Muster";
      return;
    }
    if (t.closest("[data-ps-done]")) {
      closeModals();
      if (settings.view === "home") setView("chart");
    }
  });
  $("#pay-sheet").addEventListener("change", (e) => {
    const a = e.target.dataset?.psAddon;
    if (!a) return;
    pay.addons = e.target.checked ? [...new Set([...pay.addons, a])] : pay.addons.filter((x) => x !== a);
    renderPay();
  });
}

// ---------- Rechnungen & Kündigung ----------
function openInvoice(i) {
  const inv = account.state.invoices[i];
  if (!inv) return;
  const pr = account.state.profile;
  $("#invoice").innerHTML = `
    <div class="inv-head"><div><img src="icons/icon.svg" alt="" width="36" height="36"/><b>ΛKYTEX</b><small>[Firmenname] · [Straße Nr.] · [PLZ Ort]<br>USt-IdNr. [DE…]</small></div>
      <div class="inv-meta"><b>Rechnung ${inv.no}</b><span>Datum: ${new Date(inv.date).toLocaleDateString("de-DE")}</span><span>Kunde: ${esc(pr?.name || "–")}</span></div></div>
    <table class="grid inv-table"><thead><tr><th>Leistung</th><th class="num">Betrag</th></tr></thead><tbody>
      ${inv.lines.map((l) => `<tr><td>${esc(l.label)}</td><td class="num">${eur(l.amount)}</td></tr>`).join("")}
    </tbody></table>
    <div class="inv-sum"><div><span>Nettobetrag</span><b>${eur(inv.net)}</b></div><div><span>zzgl. 19 % MwSt.</span><b>${eur(inv.vat)}</b></div><div class="co-total"><span>Gesamt</span><b>${eur(inv.total)}</b></div></div>
    <p class="muted small">${esc(inv.note || "")}</p>
    <p class="test-banner">Testbeleg aus dem Demo-Checkout – es wurde keine Zahlung ausgeführt.</p>`;
  openModal("#invoice-modal");
}
function openCancel() {
  const sub = account.state.sub;
  const body = $("#cancel-body");
  if (!sub || sub.status === "canceled") {
    body.innerHTML = sub
      ? `<p>Dein Abo <b>${planTitle(planById(sub.plan))}</b> ist bereits gekündigt und endet am <b>${new Date(sub.cancelAt).toLocaleDateString("de-DE")}</b>.</p><button class="btn" data-resume>Kündigung zurücknehmen</button>`
      : `<p>Du hast aktuell kein kostenpflichtiges Abo. Es gibt nichts zu kündigen.</p>`;
  } else {
    body.innerHTML = `<p>Vertrag: <b>${planTitle(planById(sub.plan))}</b> (${sub.billing === "yearly" ? "jährlich" : "monatlich"}), ${eur(sub.total)} ${sub.billing === "yearly" ? "pro Jahr" : "pro Monat"}.</p>
      <p>Die Kündigung wird zum <b>${new Date(sub.renews).toLocaleDateString("de-DE")}</b> wirksam. Bis dahin nutzt du alle Funktionen weiter.</p>
      <label class="field"><span>Grund (optional)</span><select id="cancel-reason"><option value="">Keine Angabe</option><option>Zu teuer</option><option>Nutze es zu selten</option><option>Funktion fehlt</option><option>Wechsel zu anderem Anbieter</option></select></label>
      <button class="btn danger-solid" data-cancel-now>Jetzt kündigen</button>
      <p class="muted small">Du erhältst eine Kündigungsbestätigung mit Datum und Uhrzeit.</p>`;
  }
  closeModals();
  setTimeout(() => openModal("#cancel-modal"), 330);
}
function bindCancel() {
  $("#cancel-body").addEventListener("click", (e) => {
    if (e.target.closest("[data-cancel-now]")) {
      const sub = account.cancel($("#cancel-reason").value);
      $("#cancel-body").innerHTML = `<div class="co-done small"><svg class="check" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36"/><path d="M24 41 l11 11 l22 -24"/></svg>
        <h3>Kündigung bestätigt</h3><p>Eingegangen am ${new Date().toLocaleString("de-DE")}. Dein Tarif <b>${planTitle(planById(sub.plan))}</b> endet am <b>${new Date(sub.cancelAt).toLocaleDateString("de-DE")}</b>. Danach wechselst du automatisch zu Free.</p></div>`;
      syncAccountUI();
      toast(`Dein Abo endet am ${new Date(sub.cancelAt).toLocaleDateString("de-DE")}.`, "info", "Kündigung bestätigt");
    }
    if (e.target.closest("[data-resume]")) {
      account.resume();
      closeModals();
      syncAccountUI();
      toast("Schön, dass du bleibst! Dein Abo läuft weiter.", "success", "Kündigung zurückgenommen");
    }
  });
}
function checkSubscription() {
  const sub = account.state.sub;
  if (!sub) return;
  if (sub.status === "canceled" && Date.now() >= sub.cancelAt) {
    account.state.sub = null;
    account.save();
    setPlan("free", true);
    return;
  }
  if (sub.status === "trial" && Date.now() >= sub.trialEnds) {
    // erste (Test-)Abbuchung nach der Testphase
    sub.status = "active";
    account.addInvoice({ date: sub.trialEnds, lines: [{ label: `${planTitle(planById(sub.plan))} (${sub.billing === "yearly" ? "jährlich" : "monatlich"})`, amount: sub.total }], total: sub.total, note: "Abbuchung nach der Testphase (Testmodus)" });
    sub.renews = sub.trialEnds + (sub.billing === "yearly" ? 365 : 30) * 86400000;
    account.save();
  }
}

// ---------- Onboarding ----------
let ob = null;
function openOnboarding() {
  ob = { step: 0, name: account.state.profile?.name || "", email: account.state.profile?.email || "", exp: null, goal: null, risk: 4 };
  renderOnboarding();
  openModal("#onboard-modal");
}
function renderOnboarding(dir = 1) {
  stepper("#ob-steps", Math.min(ob.step, 3));
  const opt = (key, val, icon, title, text) => `<button class="ob-opt ${ob[key] === val ? "on" : ""}" data-ob="${key}" data-val="${val}"><span>${icon}</span><b>${title}</b><small>${text}</small></button>`;
  let html = "";
  if (ob.step === 0)
    html = `<div class="co-narrow"><div class="ob-hero"><img src="icons/logo.svg" alt="" width="96" height="96"/><h2>Willkommen bei ΛKYTEX</h2><p class="muted">In 30 Sekunden richten wir die App auf dich ein.</p></div>
      <label class="field"><span>Wie heißt du?</span><input type="text" id="ob-name" maxlength="60" value="${esc(ob.name)}" autocomplete="given-name" /></label>
      <label class="field"><span>E-Mail (optional)</span><input type="email" id="ob-email" maxlength="120" value="${esc(ob.email)}" autocomplete="email" /></label>
      <p class="muted small">Wird nur in diesem Browser gespeichert.</p>
      <div class="co-actions"><button class="btn ghost" data-ob-skip>Überspringen</button><button class="btn primary" data-ob-next>Weiter</button></div></div>`;
  else if (ob.step === 1)
    html = `<div class="co-narrow"><h3>Wie viel Börsenerfahrung hast du?</h3><div class="ob-opts">${opt("exp", "new", "🌱", "Einsteiger", "Ich fange gerade an")}${opt("exp", "some", "📈", "Fortgeschritten", "Ich habe schon Aktien gekauft")}${opt("exp", "pro", "🏆", "Profi", "Ich trade regelmäßig")}</div><div class="co-actions"><button class="btn ghost" data-ob-back>Zurück</button><button class="btn primary" data-ob-next ${ob.exp ? "" : "disabled"}>Weiter</button></div></div>`;
  else if (ob.step === 2)
    html = `<div class="co-narrow"><h3>Was ist dein Ziel?</h3><div class="ob-opts">${opt("goal", "wealth", "🏡", "Vermögen aufbauen", "Langfristig investieren")}${opt("goal", "trade", "⚡", "Aktiv traden", "Chancen schnell nutzen")}${opt("goal", "income", "💶", "Dividenden", "Regelmäßige Erträge")}</div><div class="co-actions"><button class="btn ghost" data-ob-back>Zurück</button><button class="btn primary" data-ob-next ${ob.goal ? "" : "disabled"}>Weiter</button></div></div>`;
  else if (ob.step === 3) {
    const lbl = ["", "Sehr vorsichtig", "Vorsichtig", "Eher vorsichtig", "Ausgewogen", "Eher mutig", "Mutig", "Sehr mutig"][ob.risk];
    html = `<div class="co-narrow"><h3>Wie viel Schwankung hältst du aus?</h3><div class="risk-big"><b id="ob-risk-l">${lbl}</b><span id="ob-risk-v">${ob.risk} / 7</span></div>
      <input type="range" id="ob-risk" min="1" max="7" step="1" value="${ob.risk}" />
      <div class="risk-scale"><span>Sicherheit</span><span>Rendite</span></div>
      <div class="co-actions"><button class="btn ghost" data-ob-back>Zurück</button><button class="btn primary" data-ob-next>Fertig</button></div></div>`;
  } else {
    const rec = ob.goal === "trade" && ob.risk >= 5 ? "aiprem" : ob.exp === "pro" ? "pro" : ob.goal === "wealth" && ob.exp === "new" ? "ai" : ob.exp === "new" ? "plus" : "pro";
    const p = planById(rec);
    html = `<div class="co-done"><svg class="check" viewBox="0 0 80 80"><circle cx="40" cy="40" r="36"/><path d="M24 41 l11 11 l22 -24"/></svg>
      <h2>Alles bereit, ${esc(ob.name || "Trader")}!</h2><p class="muted">Dein Profil: ${{ new: "Einsteiger", some: "Fortgeschritten", pro: "Profi" }[ob.exp]} · ${{ wealth: "Vermögensaufbau", trade: "Aktiv traden", income: "Dividenden" }[ob.goal]} · Risiko ${ob.risk}/7. Den Autopiloten habe ich auf „${STRATEGIES[ob.risk <= 3 ? "conservative" : ob.risk >= 6 ? "aggressive" : "balanced"].label}“ eingestellt.</p>
      <div class="rec-card"><span class="usp-eyebrow">Unsere Empfehlung</span><h3>${planTitle(p)}</h3><p class="muted">${p.tagline} · ${eur(planPrice(p, settings.billing))}/Monat, ${PAYMENT_CONFIG.trialDays} Tage gratis</p></div>
      <div class="co-done-actions"><button class="btn" data-ob-free>Kostenlos starten</button><button class="btn primary" data-ob-rec="${p.id}">${p.name} gratis testen</button></div></div>`;
  }
  $("#ob-stage").innerHTML = `<div class="co-slide ${dir > 0 ? "fwd" : "back"}">${html}</div>`;
}
function finishOnboarding() {
  account.setProfile({ name: ob.name || "Trader", email: ob.email || "" });
  account.state.onboarding = { exp: ob.exp, goal: ob.goal, risk: ob.risk, at: Date.now() };
  account.save();
  aiEngine.state.config.strategy = ob.risk <= 3 ? "conservative" : ob.risk >= 6 ? "aggressive" : "balanced";
  aiEngine.save();
  syncAccountUI();
}
function bindOnboarding() {
  $("#ob-stage").addEventListener("click", (e) => {
    const t = e.target;
    const o = t.closest("[data-ob]");
    if (o) {
      ob[o.dataset.ob] = o.dataset.val;
      haptic(6);
      return renderOnboarding(0);
    }
    if (t.closest("[data-ob-next]")) {
      if (ob.step === 0) {
        ob.name = $("#ob-name").value.trim();
        ob.email = $("#ob-email").value.trim();
        if (!ob.name) return shake($("#ob-name"));
      }
      ob.step++;
      if (ob.step === 4) finishOnboarding();
      return renderOnboarding(1);
    }
    if (t.closest("[data-ob-back]")) {
      ob.step--;
      return renderOnboarding(-1);
    }
    if (t.closest("[data-ob-skip]")) {
      closeModals();
      return setView("chart");
    }
    if (t.closest("[data-ob-free]")) {
      closeModals();
      return setView("chart");
    }
    const r = t.closest("[data-ob-rec]");
    if (r) return openCheckout(r.dataset.obRec);
  });
  $("#ob-stage").addEventListener("input", (e) => {
    if (e.target.id !== "ob-risk") return;
    ob.risk = +e.target.value;
    $("#ob-risk-l").textContent = ["", "Sehr vorsichtig", "Vorsichtig", "Eher vorsichtig", "Ausgewogen", "Eher mutig", "Mutig", "Sehr mutig"][ob.risk];
    $("#ob-risk-v").textContent = ob.risk + " / 7";
  });
}

// ---------- Konto-Ansicht ----------
let acctTab = "profile";
function avatarFor(name) {
  const ini = (name || "?").split(/\s+/).map((w) => w[0]).join("").slice(0, 2).toUpperCase();
  return `<span class="avatar" style="--c:#6ea2f2">${esc(ini)}</span>`;
}
function syncAccountUI() {
  const pr = account.state.profile;
  $("#acct-av").textContent = pr ? pr.name.split(/\s+/).map((w) => w[0]).join("").slice(0, 2).toUpperCase() : "?";
  $("#acct-btn").classList.toggle("in", !!pr);
  if (settings.view === "account") renderAccount();
}
function renderAcctMenu() {
  const pr = account.state.profile;
  const sub = account.state.sub;
  $("#acct-menu").innerHTML = pr
    ? `<div class="menu-head">${avatarFor(pr.name)}<div><b>${esc(pr.name)}</b><small class="muted">${planTitle(plan())}${sub ? " · " + { trial: "Testphase", active: "aktiv", canceled: "gekündigt" }[sub.status] : ""}</small></div></div>
      <button data-goto="account" data-acct-tab="profile">👤 Profil & Konto</button><button data-goto="account" data-acct-tab="billing">💳 Abo & Zahlung</button><button data-goto="account" data-acct-tab="invoices">🧾 Rechnungen</button><button data-open-plans>✦ Tarife</button><button data-goto="legal">⚖️ Rechtliches</button><button data-signout>Abmelden</button>`
    : `<div class="menu-head"><span class="avatar" style="--c:#64748b">?</span><div><b>Nicht angemeldet</b><small class="muted">Demo-Depot aktiv</small></div></div><button data-onboard>✨ Konto erstellen</button><button data-open-plans>✦ Tarife</button><button data-goto="legal">⚖️ Rechtliches</button>`;
}
function renderAccount() {
  if (settings.view !== "account") return;
  $$("#acct-nav button").forEach((b) => b.classList.toggle("active", b.dataset.acct === acctTab));
  const pr = account.state.profile;
  const sub = account.state.sub;
  const el = $("#acct-body");
  const tog = (k, label, desc) => `<div class="set-row"><div><b>${label}</b><small class="muted">${desc}</small></div><button class="switch ${account.state.prefs[k] ? "on" : ""}" data-pref="${k}" aria-pressed="${account.state.prefs[k]}"><i></i></button></div>`;
  let html = "";
  if (acctTab === "profile") {
    html = pr
      ? `<div class="profile-top">${avatarFor(pr.name).replace('class="avatar"', 'class="avatar xl"')}<div><h2>${esc(pr.name)}</h2><p class="muted">Mitglied seit ${new Date(pr.since).toLocaleDateString("de-DE")} · ${planTitle(plan())}</p></div></div>
        <form class="form narrow" id="profile-form"><label class="field"><span>Name</span><input type="text" id="pf-name" value="${esc(pr.name)}" maxlength="60" /></label><label class="field"><span>E-Mail</span><input type="email" id="pf-email" value="${esc(pr.email || "")}" maxlength="120" /></label><button class="btn primary">Speichern</button></form>
        ${account.state.onboarding ? `<div class="kv"><div><span>Erfahrung</span><b>${{ new: "Einsteiger", some: "Fortgeschritten", pro: "Profi" }[account.state.onboarding.exp] || "–"}</b></div><div><span>Ziel</span><b>${{ wealth: "Vermögensaufbau", trade: "Aktiv traden", income: "Dividenden" }[account.state.onboarding.goal] || "–"}</b></div><div><span>Risiko</span><b>${account.state.onboarding.risk}/7</b></div></div><button class="link-btn" data-onboard>Anlageprofil neu einrichten</button>` : `<button class="btn" data-onboard>Anlageprofil einrichten</button>`}`
      : `<div class="empty-state"><div class="orb small"><i></i><i></i><i></i></div><h3>Noch kein Konto</h3><p class="muted">Erstelle ein kostenloses Profil – in 30 Sekunden.</p><button class="btn primary" data-onboard>Konto erstellen</button></div>`;
  } else if (acctTab === "billing") {
    const p = plan();
    html = `<div class="bill-card ${p.group ? "ai" : ""}"><div><span class="usp-eyebrow">Dein Tarif</span><h2>${planTitle(p)}</h2><p class="muted">${sub ? `${eur(sub.total)} ${sub.billing === "yearly" ? "pro Jahr" : "pro Monat"} · ${sub.billing === "yearly" ? "jährlich" : "monatlich"}` : p.monthly ? "Direkt aktiviert (ohne Checkout)" : "Kostenlos"}</p></div>
        ${sub ? `<span class="status-pill ${sub.status}">${{ trial: "Testphase", active: "Aktiv", canceled: "Gekündigt" }[sub.status]}</span>` : ""}</div>
      ${sub ? `<div class="kv"><div><span>${sub.status === "trial" ? "Testphase bis" : sub.status === "canceled" ? "Endet am" : "Nächste Abbuchung"}</span><b>${new Date(sub.status === "canceled" ? sub.cancelAt : sub.status === "trial" ? sub.trialEnds : sub.renews).toLocaleDateString("de-DE")}</b></div><div><span>Zahlungsmethode</span><b>${esc(account.state.method?.label || "–")}</b></div><div><span>Gutschein</span><b>${sub.promo || "–"}</b></div></div>` : ""}
      <div class="btn-row"><button class="btn primary" data-open-plans>Tarif wechseln</button>${sub ? `<button class="btn" data-change-method>Zahlungsmethode ändern</button>` : ""}${PAYMENT_CONFIG.stripePortal ? `<a class="btn" href="${PAYMENT_CONFIG.stripePortal}" target="_blank" rel="noopener">Kundenportal</a>` : ""}</div>
      <div class="cancel-zone"><div><b>Kündigen</b><small class="muted">Jederzeit zum Ende der Laufzeit – ohne Umwege.</small></div><button class="btn danger" data-cancel-open>Verträge hier kündigen</button></div>`;
  } else if (acctTab === "invoices") {
    const inv = account.state.invoices;
    html = inv.length
      ? `<div class="table-scroll"><table class="grid"><thead><tr><th>Nr.</th><th>Datum</th><th class="num">Betrag</th><th>Status</th><th></th></tr></thead><tbody>${inv.map((x, i) => `<tr><td>${x.no}</td><td>${new Date(x.date).toLocaleDateString("de-DE")}</td><td class="num">${eur(x.total)}</td><td><span class="status ok">${esc(x.status)}</span></td><td class="num"><button class="mini-btn" data-invoice="${i}">Ansehen</button></td></tr>`).join("")}</tbody></table></div>`
      : `<div class="empty">Noch keine Rechnungen. Sie erscheinen hier nach dem ersten Checkout.</div>`;
  } else if (acctTab === "orders") {
    const os = shop.state.orders;
    html = os.length
      ? os.map((o) => `<div class="order"><div class="order-h"><b>${o.no}</b><span class="muted">${new Date(o.date).toLocaleString("de-DE")}</span><span class="status ok">${esc(o.status)}</span><b>${eur(o.total)}</b></div><ul>${o.items.map((i) => `<li>${i.qty}× ${esc(i.name)}</li>`).join("")}</ul>${o.codes.length ? `<p>🎁 ${o.codes.map((c) => `<code>${c.code}</code> (${eur(c.value)})`).join(" · ")}</p>` : ""}${o.address ? `<small class="muted">Lieferung an ${esc(o.address.street)}, ${esc(o.address.zip)} ${esc(o.address.city)}</small>` : ""}</div>`).join("")
      : `<div class="empty">Noch keine Bestellungen. <button class="link-btn" data-goto="shop">Zum Store</button></div>`;
  } else if (acctTab === "notify") {
    html = `${tog("push", "Push-Benachrichtigungen", "Order-Ausführungen und Alarme als System-Mitteilung")}${tog("fills", "Order-Bestätigungen", "Meldung bei jeder Ausführung")}${tog("ai", "AKYTEX AI-Meldungen", "Signalwechsel, Risiken, Autopilot-Entscheidungen")}${tog("email", "Wochenreport per E-Mail", "Zusammenfassung deines Depots (im Echtbetrieb)")}
      <button class="btn" data-perm>Browser-Benachrichtigungen erlauben</button>`;
  } else if (acctTab === "security") {
    html = `${tog("twofa", "Zwei-Faktor-Anmeldung", "Zusätzlicher Code bei jeder Anmeldung")}${tog("passkey", "Passkey", "Anmelden mit Face ID, Touch ID oder Windows Hello")}
      <h4 class="ap-h">Aktive Sitzungen</h4><div class="set-row"><div><b>Dieses Gerät</b><small class="muted">${esc(navigator.platform || "Browser")} · jetzt aktiv</small></div><span class="status ok">aktuell</span></div>
      <p class="muted small">In der Demo sind Sicherheits-Einstellungen Vorschau-Schalter; im Echtbetrieb übernimmt das der Login-Server.</p>`;
  } else if (acctTab === "data") {
    html = `<div class="set-row"><div><b>Daten exportieren</b><small class="muted">Konto, Depot, Ideen und Einstellungen als JSON (DSGVO Art. 20)</small></div><button class="btn" data-export>Export</button></div>
      <div class="set-row"><div><b>Demo-Depot zurücksetzen</b><small class="muted">Positionen, Orders und Alarme löschen, 100.000 € Startguthaben</small></div><button class="btn" data-goto="portfolio">Zum Depot</button></div>
      <div class="set-row"><div><b>Abmelden</b><small class="muted">Profil von diesem Gerät entfernen</small></div><button class="btn danger" data-signout>Abmelden</button></div>`;
  }
  el.innerHTML = `<div class="co-slide fwd">${html}</div>`;
}
function bindAccount() {
  $("#acct-nav").addEventListener("click", (e) => {
    const b = e.target.closest("[data-acct]");
    if (!b) return;
    acctTab = b.dataset.acct;
    renderAccount();
  });
  document.addEventListener("submit", (e) => {
    if (e.target.id !== "profile-form") return;
    e.preventDefault();
    account.setProfile({ name: $("#pf-name").value.trim() || account.state.profile.name, email: $("#pf-email").value.trim() });
    syncAccountUI();
    toast("Profil gespeichert.", "success");
  });
  document.addEventListener("click", (e) => {
    const t = e.target;
    const tabBtn = t.closest("[data-acct-tab]");
    if (tabBtn) {
      acctTab = tabBtn.dataset.acctTab;
      if (settings.view === "account") renderAccount();
    }
    const pref = t.closest("[data-pref]");
    if (pref) {
      const k = pref.dataset.pref;
      account.state.prefs[k] = !account.state.prefs[k];
      account.save();
      haptic(6);
      pref.classList.toggle("on", account.state.prefs[k]);
      return;
    }
    if (t.closest("[data-onboard]")) {
      closePopovers();
      return openOnboarding();
    }
    if (t.closest("[data-signout]")) {
      account.signOut();
      closePopovers();
      syncAccountUI();
      return toast("Du wurdest abgemeldet. Dein Demo-Depot bleibt erhalten.", "info", "Abgemeldet");
    }
    const inv = t.closest("[data-invoice]");
    if (inv) return openInvoice(+inv.dataset.invoice);
    if (t.closest("[data-cancel-open]")) return openCancel();
    if (t.closest("[data-change-method]")) return openCheckout(settings.plan, 2);
    if (t.closest("[data-perm]")) {
      if ("Notification" in window) Notification.requestPermission().then((r) => toast(r === "granted" ? "Benachrichtigungen sind erlaubt." : "Benachrichtigungen wurden nicht erlaubt.", r === "granted" ? "success" : "info")).catch(() => {});
      return;
    }
    if (t.closest("[data-export]")) {
      const data = { exportiert: new Date().toISOString(), konto: account.state, depot: broker.state, einstellungen: settings, ideen: community.state, ai: aiEngine.state };
      $("#json-out").value = JSON.stringify(data, null, 2);
      return openModal("#json-modal");
    }
    const lo = t.closest("[data-legal-open]");
    if (lo) {
      e.preventDefault();
      legalTab = lo.dataset.legalOpen;
      closeModals();
      closePopovers();
      return setView("legal");
    }
  });
  $("#json-copy").addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText($("#json-out").value);
      toast("Daten in die Zwischenablage kopiert.", "success");
    } catch (_) {
      $("#json-out").select();
      toast("Bitte mit Strg/⌘ + C kopieren.", "info");
    }
  });
}

// ---------- Rechtliches (Vorlagen) ----------
let legalTab = "impressum";
const PH = (t) => `<mark class="ph">[${t}]</mark>`;
const LEGAL = {
  impressum: () => `<h2>Impressum</h2><p>Angaben gemäß § 5 DDG</p><p>${PH("Firmenname und Rechtsform")}<br>${PH("Straße Hausnummer")}<br>${PH("PLZ Ort")}</p><p><b>Vertreten durch:</b> ${PH("Geschäftsführung")}<br><b>Kontakt:</b> ${PH("E-Mail")} · ${PH("Telefon")}<br><b>Registereintrag:</b> ${PH("Registergericht, HRB-Nummer")}<br><b>USt-IdNr.:</b> ${PH("DE…")}</p><p><b>Aufsicht:</b> Im Echtbetrieb ${PH("Bundesanstalt für Finanzdienstleistungsaufsicht (BaFin) bzw. lizenzierter Partner")}</p><p>Verantwortlich für den Inhalt nach § 18 Abs. 2 MStV: ${PH("Name, Anschrift")}</p>`,
  privacy: () => `<h2>Datenschutzerklärung</h2><h3>Kurzfassung für diese Demo</h3><ul><li>Alle Daten (Profil, Depot, Einstellungen, Ideen) werden ausschließlich <b>lokal in deinem Browser</b> gespeichert.</li><li>Es gibt keinen Server, kein Tracking und keine Cookies zu Werbezwecken.</li><li>Im Testmodus des Checkouts werden keine Zahlungsdaten gespeichert oder übertragen.</li><li>Nutzt du den Berater-Chat in einer Claude-Umgebung, wird deine Frage samt nötiger Depotdaten an das Sprachmodell übermittelt.</li></ul><h3>Für den Echtbetrieb ergänzen</h3><p>Verantwortlicher: ${PH("Name, Anschrift, Kontakt")} · Datenschutzbeauftragter: ${PH("Kontakt")}</p><p>Zwecke und Rechtsgrundlagen (Art. 6 DSGVO), Auftragsverarbeiter (${PH("Hosting, Zahlungsanbieter, Identifizierung")}), Speicherdauer, Drittlandübermittlung, Betroffenenrechte (Auskunft, Berichtigung, Löschung, Einschränkung, Datenübertragbarkeit, Widerspruch), Beschwerderecht bei der Aufsichtsbehörde.</p>`,
  terms: () => `<h2>Allgemeine Geschäftsbedingungen (Vorlage)</h2><ol><li><b>Geltungsbereich:</b> Diese AGB gelten für die Nutzung der Plattform AKYTEX von ${PH("Firmenname")}.</li><li><b>Leistungen:</b> Charts, Analysen, Community-Funktionen und – mit entsprechendem Tarif – AKYTEX AI. In der Demo werden alle Kurse simuliert und es wird mit virtuellem Geld gehandelt.</li><li><b>Tarife und Preise:</b> Es gelten die Preise laut Preis- und Leistungsverzeichnis inkl. gesetzlicher MwSt. Kostenpflichtige Tarife beginnen mit einer ${PAYMENT_CONFIG.trialDays}-tägigen kostenlosen Testphase.</li><li><b>Laufzeit und Kündigung:</b> Monatstarife verlängern sich um jeweils einen Monat, Jahrestarife um ein Jahr, sofern nicht zum Ende der Laufzeit gekündigt wird. Die Kündigung ist jederzeit über „Verträge hier kündigen“ möglich.</li><li><b>Keine Anlageberatung:</b> Inhalte, Ideen und AI-Einschätzungen sind keine Anlageberatung. ${PH("Regelungen für Beratung/Vermögensverwaltung im Echtbetrieb")}</li><li><b>Haftung, Gerichtsstand, Schlussbestimmungen:</b> ${PH("anwaltlich ergänzen")}</li></ol>`,
  withdrawal: () => `<h2>Widerrufsbelehrung (Vorlage)</h2><p><b>Widerrufsrecht:</b> Du hast das Recht, binnen vierzehn Tagen ohne Angabe von Gründen diesen Vertrag zu widerrufen. Die Widerrufsfrist beträgt vierzehn Tage ab dem Tag des Vertragsabschlusses.</p><p>Um dein Widerrufsrecht auszuüben, musst du uns (${PH("Name, Anschrift, E-Mail")}) mittels einer eindeutigen Erklärung über deinen Entschluss informieren.</p><p><b>Folgen des Widerrufs:</b> Wir erstatten alle Zahlungen unverzüglich, spätestens binnen vierzehn Tagen. ${PH("Regelung bei vorzeitigem Leistungsbeginn anwaltlich prüfen")}</p>`,
  risk: () => `<h2>Risikohinweise</h2><ul><li>Der Handel mit Aktien ist mit Risiken verbunden und kann zum <b>Totalverlust</b> des eingesetzten Kapitals führen.</li><li>Vergangene Wertentwicklungen, Ideen-Trefferquoten und AI-Bewertungen sind <b>kein verlässlicher Indikator</b> für künftige Ergebnisse.</li><li>AKYTEX AI und der Autopilot handeln regelbasiert; auch automatische Stops schützen nicht vor Kurslücken.</li><li>Copy-Trading und Ideen-Handel übernehmen fremde Entscheidungen – prüfe sie selbst.</li><li>In dieser Demo sind alle Kurse simuliert, das Geld ist virtuell.</li></ul>`,
};
function renderLegal() {
  $$("#legal-tabs button").forEach((b) => b.classList.toggle("active", b.dataset.legal === legalTab));
  $("#legal-body").innerHTML = `<div class="co-slide fwd">${LEGAL[legalTab]()}</div>`;
}

// ---------- Mitteilungen, Konto-Menü, Befehlspalette ----------
function syncNotifBadge() {
  const b = $("#notif-badge");
  if (!b) return;
  b.hidden = !notifUnread;
  b.textContent = notifUnread > 9 ? "9+" : notifUnread;
}
function renderNotifs() {
  $("#notif-list").innerHTML = notifs.length
    ? notifs.map((n) => `<div class="notif ${n.type}"><i></i><div>${n.title ? `<b>${esc(n.title)}</b>` : ""}<p>${esc(n.msg)}</p><small class="muted">${ago(n.ts)}</small></div></div>`).join("")
    : `<div class="muted empty">Keine Mitteilungen.</div>`;
}
function closePopovers() {
  $$(".popover").forEach((p) => {
    p.classList.remove("open");
    setTimeout(() => {
      if (!p.classList.contains("open")) p.hidden = true;
    }, 250);
  });
}
function togglePopover(id, render) {
  const p = $(id);
  const open = p.hidden || !p.classList.contains("open");
  closePopovers();
  if (!open) return;
  render();
  p.hidden = false;
  requestAnimationFrame(() => p.classList.add("open"));
}
let cmdIdx = 0;
function cmdItems(q) {
  const items = [
    ...[["home", "Start"], ["chart", "Chart"], ["markets", "Märkte"], ["ideas", "Ideen-Börse"], ["clips", "Clips"], ["ai", "AKYTEX AI"], ["shop", "Shop"], ["portfolio", "Depot"], ["business", "Business-Dashboard"], ["account", "Mein Konto"], ["legal", "Rechtliches"]].map(([v, l]) => ({ icon: "↗", label: `Gehe zu ${l}`, run: () => setView(v) })),
    { icon: "✦", label: "Tarife ansehen", run: () => openPlans() },
    { icon: "💳", label: "Pro abonnieren (Checkout)", run: () => openCheckout("pro") },
    { icon: "🤖", label: "AI Premium abonnieren (Checkout)", run: () => openCheckout("aiprem") },
    { icon: "💡", label: "Idee teilen", run: () => openIdeaModal() },
    { icon: "⏱", label: "Zeitplan / Timer anlegen", run: () => setAiTab("plan") },
    { icon: "🧪", label: "AI-Labor öffnen", run: () => setAiTab("lab") },
    { icon: "🎬", label: "Chart-Clip aufnehmen", run: () => recordChartClip() },
    { icon: "🛍️", label: "Warenkorb öffnen", run: () => openCart() },
    { icon: "⏰", label: "Alarm erstellen", run: () => openAlertModal(settings.symbol, market.get(settings.symbol).price) },
    { icon: "◐", label: "Hell/Dunkel umschalten", run: () => $("#theme-btn").click() },
    { icon: "🔗", label: "Link teilen", run: () => share() },
    { icon: "⏻", label: `Autopilot ${aiEngine.state.config.enabled ? "ausschalten" : "einschalten"}`, run: () => (setView("ai"), setTimeout(() => $("#ap-toggle")?.click(), 400)) },
    { icon: "🧾", label: "Rechnungen", run: () => ((acctTab = "invoices"), setView("account")) },
    { icon: "✕", label: "Verträge hier kündigen", run: () => openCancel() },
    ...STOCKS.map((s) => ({ icon: "📈", label: `${s.s} – ${s.n}`, sub: `${num(market.get(s.s).price)} €`, run: () => setSymbol(s.s) })),
  ];
  const t = q.trim().toLowerCase();
  let res = t ? items.filter((i) => i.label.toLowerCase().includes(t)) : items.slice(0, 14);
  if (t.length > 2) res.push({ icon: "✦", label: `AKYTEX AI fragen: „${q.trim()}“`, run: () => (setView("ai"), setTimeout(() => sendChat(q.trim()), 350)) });
  return res.slice(0, 14);
}
function renderCmd() {
  const res = cmdItems($("#cmdk-input").value);
  cmdIdx = Math.min(cmdIdx, res.length - 1);
  $("#cmdk-list").innerHTML = res.map((r, i) => `<li class="${i === cmdIdx ? "hl" : ""}" data-cmd="${i}"><span class="ci">${r.icon}</span><span>${esc(r.label)}</span>${r.sub ? `<small class="muted">${r.sub}</small>` : ""}</li>`).join("");
  $("#cmdk-list").onclick = (e) => {
    const li = e.target.closest("[data-cmd]");
    if (!li) return;
    closeModals();
    res[+li.dataset.cmd].run();
  };
  return res;
}
function openCmd() {
  cmdIdx = 0;
  $("#cmdk-input").value = "";
  renderCmd();
  openModal("#cmdk-modal");
  $("#cmdk-input").focus();
}
function bindShell() {
  $("#cmdk-btn").addEventListener("click", openCmd);
  $("#cmdk-input").addEventListener("input", () => {
    cmdIdx = 0;
    renderCmd();
  });
  $("#cmdk-input").addEventListener("keydown", (e) => {
    const res = cmdItems($("#cmdk-input").value);
    if (e.key === "ArrowDown") cmdIdx = Math.min(res.length - 1, cmdIdx + 1);
    else if (e.key === "ArrowUp") cmdIdx = Math.max(0, cmdIdx - 1);
    else if (e.key === "Enter" && res[cmdIdx]) {
      closeModals();
      return res[cmdIdx].run();
    } else return;
    e.preventDefault();
    renderCmd();
    $("#cmdk-list .hl")?.scrollIntoView({ block: "nearest" });
  });
  document.addEventListener("keydown", (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k") {
      e.preventDefault();
      openCmd();
    }
  }, true);
  $("#notif-btn").addEventListener("click", (e) => {
    e.stopPropagation();
    notifUnread = 0;
    syncNotifBadge();
    togglePopover("#notif-panel", renderNotifs);
  });
  $("#notif-clear").addEventListener("click", () => {
    notifs.length = 0;
    renderNotifs();
  });
  $("#acct-btn").addEventListener("click", (e) => {
    e.stopPropagation();
    togglePopover("#acct-menu", renderAcctMenu);
  });
  document.addEventListener("click", (e) => {
    if (!e.target.closest(".pop-wrap")) closePopovers();
    else if (e.target.closest(".popover button")) closePopovers();
  });
  $("#legal-tabs").addEventListener("click", (e) => {
    const b = e.target.closest("[data-legal]");
    if (!b) return;
    legalTab = b.dataset.legal;
    renderLegal();
  });
  $("#hero-start").addEventListener("click", () => (account.signedIn ? setView("chart") : openOnboarding()));
}

// Globale Fußzeile auf allen Seiten
function injectFooters() {
  const foot = `<footer class="site-foot">
    <div class="sf-brand"><img src="icons/icon.svg" alt="" width="30" height="30"/><div><b>ΛKYTEX</b><small>Markets move. Ideas stay.</small></div></div>
    <div class="sf-cols">
      <div><b>Produkt</b><button data-goto="chart">Chart</button><button data-goto="ideas">Ideen-Börse</button><button data-goto="ai">AKYTEX AI</button><button data-open-plans>Preise</button></div>
      <div><b>Konto</b><button data-goto="account" data-acct-tab="billing">Abo & Zahlung</button><button data-goto="account" data-acct-tab="invoices">Rechnungen</button><button data-cancel-open class="sf-cancel">Verträge hier kündigen</button></div>
      <div><b>Rechtliches</b><button data-legal-open="impressum">Impressum</button><button data-legal-open="privacy">Datenschutz</button><button data-legal-open="terms">AGB</button><button data-legal-open="risk">Risikohinweise</button></div>
    </div>
    <small class="sf-note">Demo-Anwendung: Kurse, Community-Profile und Zahlungen sind simuliert. Keine Anlageberatung. Kein echtes Geld. © ${new Date().getFullYear()} ${PH("Firmenname")}</small>
  </footer>`;
  $$(".site-foot-slot").forEach((s) => (s.outerHTML = foot));
  for (const v of ["markets", "ideas", "ai", "portfolio", "business", "account", "legal"]) {
    const inner = $(`#view-${v} .page-inner`);
    if (inner && !inner.querySelector(".site-foot")) inner.insertAdjacentHTML("beforeend", foot);
  }
}

// ---------- Feinschliff: 3D-Neigung, Spotlight, Live-Aktivität, Rollziffern ----------
function bindDepth() {
  if (!matchMedia("(hover: hover) and (pointer: fine)").matches || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  let cur = null;
  let raf = 0;
  document.addEventListener("pointermove", (e) => {
    const el = e.target.closest(".plan, .feature, .opp, .usp-step, .kpi, .is-tile, .bill-card");
    if (cur && cur !== el) {
      cur.style.transform = "";
      cur.classList.remove("tilting");
    }
    cur = el;
    if (!el) return;
    cancelAnimationFrame(raf);
    raf = requestAnimationFrame(() => {
      const r = el.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width;
      const y = (e.clientY - r.top) / r.height;
      el.classList.add("tilting");
      el.style.setProperty("--mx", x * 100 + "%");
      el.style.setProperty("--my", y * 100 + "%");
      el.style.transform = `perspective(900px) rotateX(${(0.5 - y) * 5}deg) rotateY(${(x - 0.5) * 7}deg) translateY(-4px)`;
    });
  });
  document.addEventListener("pointerleave", () => cur && (cur.style.transform = ""));
}
const ACT_NAMES = ["anna_trades", "LukasInvest", "bullenbaer", "fintech_fritz", "Marie.K", "depot_dave", "sparfuchs93", "KaiCharts", "LinaLongs", "TomTrader", "EllaETF", "pivot_paul"];
function liveActivity() {
  const el = $("#live-activity");
  if (!el || settings.view !== "home") return;
  const s = STOCKS[Math.floor(Math.random() * STOCKS.length)];
  const kinds = [
    () => `<b>@${ACT_NAMES[Math.floor(Math.random() * ACT_NAMES.length)]}</b> kaufte ${1 + Math.floor(Math.random() * 40)} ${s.s}`,
    () => `<b>@${ACT_NAMES[Math.floor(Math.random() * ACT_NAMES.length)]}</b> teilte eine Idee zu ${s.s}`,
    () => `🤖 Ein Autopilot sicherte Gewinne bei ${s.s}`,
    () => `<b>@${ACT_NAMES[Math.floor(Math.random() * ACT_NAMES.length)]}</b> handelt eine Idee von @${community.traders[Math.floor(Math.random() * community.traders.length)].handle}`,
  ];
  const pill = document.createElement("div");
  pill.className = "act-pill";
  pill.innerHTML = `<i></i>${kinds[Math.floor(Math.random() * kinds.length)]()} <small>· gerade eben · Demo</small>`;
  el.prepend(pill);
  requestAnimationFrame(() => pill.classList.add("in"));
  while (el.children.length > 3) el.lastElementChild.remove();
}
setInterval(liveActivity, 2600);

// Rollziffern für den großen Kurs in der Kurskarte
function odometer(el, text) {
  if (!el) return;
  if (el.dataset.txt === text) return;
  const prev = el.dataset.txt || "";
  el.dataset.txt = text;
  if (prev.length !== text.length || !el.querySelector(".od")) {
    el.innerHTML = [...text].map((ch) => (/\d/.test(ch) ? `<span class="od"><span class="od-col" style="transform:translateY(-${+ch * 10}%)">${"0123456789".split("").map((d) => `<i>${d}</i>`).join("")}</span></span>` : `<span class="od-s">${ch}</span>`)).join("");
    return;
  }
  const cols = el.querySelectorAll(".od-col");
  let k = 0;
  for (const ch of text) if (/\d/.test(ch)) cols[k++].style.transform = `translateY(-${+ch * 10}%)`;
}

// ---------- AKYTEX AI: Tabs, Zeitplan, Labor, Features ----------
let aiTab = "cockpit";
let labSym = "NVDA";
let labFocus = null;
let labBt = "sma";
let schedType = "once";
function setAiTab(tab) {
  aiTab = tab;
  if (settings.view !== "ai") setView("ai");
  $$("#ai-tabs [data-aitab]").forEach((b) => b.classList.toggle("active", b.dataset.aitab === tab));
  $$(".ai-pane").forEach((p) => (p.hidden = p.dataset.aipane !== tab));
  if (tab === "plan") renderPlanPane();
  if (tab === "lab") renderLab();
  if (tab === "features") renderFeatures();
  if (tab === "cockpit") renderAIView();
}

// SVG-Helfer
function svgLine(series, { w = 560, h = 210, pad = 62, band = null, markX = null, yFmt = (v) => num(v) } = {}) {
  const all = series.flatMap((s) => s.data).concat(band ? band.flatMap((b) => [b.lo, b.hi]) : []);
  const lo = Math.min(...all);
  const hi = Math.max(...all);
  // Breite aus allen Reihen inkl. Versatz und Bändern
  const n = Math.max(...series.map((s) => s.data.length + (s.offset || 0)), ...(band ? band.flatMap((b) => b.pts.map((p) => p.i + 1)) : [0]));
  const X = (i) => pad + (i / Math.max(1, n - 1)) * (w - pad - 8);
  const Y = (v) => 8 + (1 - (v - lo) / (hi - lo || 1)) * (h - 26);
  const ticks = [lo, (lo + hi) / 2, hi];
  let out = ticks.map((t) => `<line x1="${pad}" x2="${w - 8}" y1="${Y(t)}" y2="${Y(t)}" class="gl"/><text x="${pad - 4}" y="${Y(t) + 3}" text-anchor="end" class="ax">${yFmt(t)}</text>`).join("");
  if (band) {
    for (const b of band) {
      const up = b.pts.map((p) => `${X(p.i)},${Y(p.hi)}`).join(" ");
      const dn = b.pts.map((p) => `${X(p.i)},${Y(p.lo)}`).reverse().join(" ");
      out += `<polygon points="${up} ${dn}" fill="${b.color}" opacity="${b.op}"/>`;
    }
  }
  for (const s of series) {
    const off = s.offset || 0;
    out += `<polyline points="${s.data.map((v, i) => `${X(i + off)},${Y(v)}`).join(" ")}" fill="none" stroke="${s.color}" stroke-width="${s.width || 2}" ${s.dash ? `stroke-dasharray="${s.dash}"` : ""} class="ln"/>`;
  }
  if (markX != null) out += `<line x1="${X(markX)}" x2="${X(markX)}" y1="4" y2="${h - 16}" stroke="var(--muted)" stroke-dasharray="3 3"/>`;
  return `<svg viewBox="0 0 ${w} ${h}" class="lab-svg">${out}</svg>`;
}
function bars(items, { max = null, fmt = (v) => nf2.format(v) } = {}) {
  const m = max ?? Math.max(...items.map((i) => Math.abs(i.v)), 1e-9);
  return `<div class="hbars">${items.map((i) => `<div class="hb"><span>${esc(i.label)}</span><div class="hb-track"><i class="${i.v >= 0 ? "pos" : "neg"}" style="width:${(Math.abs(i.v) / m) * 50}%;${i.v >= 0 ? "left:50%" : `right:50%`}"></i></div><b class="${i.v > 0 ? "up" : i.v < 0 ? "down" : ""}">${fmt(i.v)}</b></div>`).join("")}</div>`;
}
function gaugeSmall(v, label) {
  const a = Math.PI * (1 - v / 100);
  const x = 60 + 46 * Math.cos(a);
  const y = 58 - 46 * Math.sin(a);
  return `<svg viewBox="0 0 120 70" class="g-small"><defs><linearGradient id="gg" x1="0" x2="1"><stop offset="0" stop-color="#ef4444"/><stop offset=".5" stop-color="#eab308"/><stop offset="1" stop-color="#22c55e"/></linearGradient></defs><path d="M14 58 A46 46 0 0 1 106 58" fill="none" stroke="url(#gg)" stroke-width="9" stroke-linecap="round"/><circle cx="${x}" cy="${y}" r="7" fill="var(--text)" stroke="var(--panel)" stroke-width="3"/><text x="60" y="54" text-anchor="middle" class="g-val">${v}</text></svg><div class="g-lbl2">${label}</div>`;
}

// Labor
function renderLab() {
  const sel = $("#lab-sym");
  if (!sel.options.length) sel.innerHTML = STOCKS.map((s) => `<option value="${s.s}">${s.s} – ${esc(s.n)}</option>`).join("");
  sel.value = labSym;
  const sym = labSym;
  const card = (id, title, sub, body, wide = false) => `<section class="card lab-card ${wide ? "wide" : ""} ${labFocus === id ? "focus" : ""}" id="lab-${id}"><div class="card-head"><h2>${title}</h2><span class="muted">${sub}</span></div>${body}</section>`;
  const f = lab.forecast(market, sym, 20);
  const hist = f.history;
  const H = hist.length;
  const fanPts = (k1, k2) => f.path.map((p, t) => ({ i: H - 1 + t, lo: p[k1], hi: p[k2] }));
  const forecastSvg = svgLine(
    [
      { data: hist, color: "#6ea2f2" },
      { data: f.path.map((p) => p.p50), color: "#d4af37", dash: "5 4", offset: H - 1 },
    ],
    { w: 1100, h: 280, pad: 70, band: [{ pts: fanPts("p5", "p95"), color: "#7c9cff", op: 0.16 }, { pts: fanPts("p25", "p75"), color: "#b36bff", op: 0.24 }].map((b) => ({ ...b, lo: Math.min(...b.pts.map((p) => p.lo)), hi: Math.max(...b.pts.map((p) => p.hi)) })), markX: H - 1 }
  );
  const e20 = f.path[20];
  const m = lab.mtf(market, sym);
  const ex = lab.explain(market, sym);
  const bars1d = lab.barsFor(market, sym, "1D");
  const pats = lab.patterns(bars1d);
  const dv = lab.divergence(bars1d);
  const sq = lab.squeeze(bars1d);
  const ad = lab.adx(bars1d);
  const zn = lab.zones(bars1d);
  const bt = lab.backtest(market, sym, labBt);
  const mc = lab.monteCarlo(broker, market, 252, 500);
  const vr = lab.valueAtRisk(broker, market);
  const ddw = lab.drawdown(broker);
  const corrSyms = (Object.keys(broker.state.positions).length >= 3 ? Object.keys(broker.state.positions) : settings.watchlist).slice(0, 8);
  const cm = lab.correlation(market, corrSyms);
  const si = lab.sentimentIndex(market);
  const rot = lab.sectorRotation(market);
  const an = lab.anomalies(market);
  const sim = lab.similar(market, sym);
  const rs = lab.relStrength(market, sym);
  const rb = lab.rebalance(broker, market, "equal");
  const v = aiEngine.scan(sym);
  const sz = lab.sizing(broker.equity(), v.price, v.h.setup.sl, 1);
  const hit = lab.hitProbability(v.price, v.h.setup.tp, v.h.setup.sl);
  const vreg = lab.volRegime(market, sym);
  const conf = lab.confidence(market, sym);
  const cs = lab.communitySentiment(community, sym);
  // Histogramm Monte Carlo
  const bins = 24;
  const mn = mc.finals[0];
  const mxv = mc.finals[mc.finals.length - 1];
  const hgram = new Array(bins).fill(0);
  for (const x of mc.finals) hgram[Math.min(bins - 1, Math.floor(((x - mn) / (mxv - mn || 1)) * bins))]++;
  const hmax = Math.max(...hgram);
  const mcSvg = `<svg viewBox="0 0 520 170" class="lab-svg">${hgram.map((c, i) => { const x0 = mn + ((mxv - mn) * i) / bins; return `<rect x="${10 + i * 20.8}" y="${150 - (c / hmax) * 135}" width="18" height="${(c / hmax) * 135}" rx="3" fill="${x0 < mc.start ? "#ef4444" : "#22c55e"}" opacity=".75"/>`; }).join("")}<text x="10" y="166" class="ax">${bigEur(mn)}</text><text x="510" y="166" text-anchor="end" class="ax">${bigEur(mxv)}</text></svg>`;
  const j = aiEngine.state.journal.slice(0, 8);
  const sells = aiEngine.state.sells;
  $("#lab-grid").innerHTML = [
    card("forecast", "📈 Prognose-Korridor", `${sym} · 20 Handelstage`, `${forecastSvg}<div class="lab-kv"><div><span>Median</span><b>${eur(e20.p50)}</b></div><div><span>50 %-Spanne</span><b>${num(e20.p25)} – ${num(e20.p75)}</b></div><div><span>90 %-Spanne</span><b>${num(e20.p5)} – ${num(e20.p95)}</b></div><div><span>Chance +10 %</span><b>${Math.round(lab.probReach(market, sym, f.price * 1.1, 20) * 100)} %</b></div></div>`, true),
    card("mtf", "🧭 Multi-Timeframe & Konfidenz", sym, `<div class="mtf">${m.frames.map((x) => `<div class="mtf-f"><span>${x.tf}</span>${gaugeSmall(Math.round((x.score + 1) * 50), x.rating.label)}</div>`).join("")}</div><div class="lab-kv"><div><span>Konsens</span><b>${m.rating.label}</b></div><div><span>Übereinstimmung</span><b>${Math.round(m.agreement * 100)} %</b></div><div><span>Signal-Konfidenz</span><b>${conf} %</b></div><div><span>Volatilität</span><b>${vreg.label}</b></div></div>`),
    card("explain", "🔍 Warum dieses Rating?", `${sym} · ${ex.rating.label}`, bars(ex.items.slice(0, 10).map((i) => ({ label: i.name, v: i.contrib * 100 })), { fmt: (v) => (v > 0 ? "+" : "") + nf2.format(v) })),
    card("patterns", "🕯️ Muster & Zonen", `${sym} · Tageschart`, `<ul class="lab-list">${pats.map((p) => `<li>${p.bias > 0 ? "🟢" : p.bias < 0 ? "🔴" : "⚪"} <b>${p.name}</b> – ${p.text}</li>`).join("") || "<li class='muted'>Keine markanten Kerzenmuster</li>"}${dv ? `<li>${dv.type === "bullish" ? "🟢" : "🔴"} ${dv.text}</li>` : ""}<li>${sq.squeeze ? "🟡 Bollinger-Squeeze aktiv" : "Bandbreite normal"}${sq.breakout ? ` · ${sq.breakout === "up" ? "🚀 Ausbruch nach oben" : "⚠️ Bruch nach unten"}` : ""}</li>${ad ? `<li>ADX ${nf2.format(ad.value)} – ${ad.label}</li>` : ""}</ul><div class="zones"><div><span>Widerstände</span>${zn.resistances.map((z) => `<b class="down">${num(z.level)}</b>`).join("") || "–"}</div><div><span>Unterstützungen</span>${zn.supports.map((z) => `<b class="up">${num(z.level)}</b>`).join("") || "–"}</div></div>`),
    card("backtest", "⏪ Strategie-Backtest", `${sym} · ${bt.label}`, `<div class="seg bt-seg">${[["sma", "SMA 20/50"], ["rsi", "RSI"], ["macd", "MACD"]].map(([k, l]) => `<button class="${labBt === k ? "active" : ""}" data-bt="${k}">${l}</button>`).join("")}</div>${svgLine([{ data: bt.bhCurve, color: "var(--muted)", width: 1.5 }, { data: bt.curve, color: "#22c55e" }], { w: 1100, h: 260, pad: 70, yFmt: (v) => nf2.format((v - 1) * 100) + " %" })}<div class="lab-kv"><div><span>Strategie</span><b class="${cls(bt.ret)}">${pct(bt.ret)}</b></div><div><span>Kaufen & Halten</span><b class="${cls(bt.buyHold)}">${pct(bt.buyHold)}</b></div><div><span>Trades / Treffer</span><b>${bt.trades} / ${bt.winRate == null ? "–" : Math.round(bt.winRate * 100) + " %"}</b></div><div><span>Max. Rückgang</span><b class="down">${pct(bt.maxDD)}</b></div></div>`, true),
    card("montecarlo", "🎲 Monte-Carlo-Depot", "500 Szenarien · 1 Jahr", `${mcSvg}<div class="lab-kv"><div><span>Median</span><b>${eur(mc.p50)}</b></div><div><span>Schlecht (5 %)</span><b class="down">${eur(mc.p5)}</b></div><div><span>Gut (95 %)</span><b class="up">${eur(mc.p95)}</b></div><div><span>Verlust-Wahrsch.</span><b>${Math.round(mc.lossProb * 100)} %</b></div></div>`),
    card("risk", "🛡️ Risiko-Kennzahlen", "Historische Simulation", `<div class="lab-kv big"><div><span>VaR 95 % (1 Tag)</span><b class="down">−${eur(vr.var95)}</b></div><div><span>VaR 99 % (1 Tag)</span><b class="down">−${eur(vr.var99)}</b></div><div><span>Expected Shortfall</span><b class="down">−${eur(vr.es95)}</b></div><div><span>Drawdown vom Hoch</span><b class="${ddw.dd < 0 ? "down" : ""}">${pct(ddw.dd)}</b></div></div>`),
    card("corr", "🧩 Korrelations-Matrix", corrSyms.length ? corrSyms.join(" · ") : "–", `<div class="corr" style="--n:${corrSyms.length}"><span></span>${corrSyms.map((s) => `<span class="ch">${s}</span>`).join("")}${cm.m.map((row, i) => `<span class="ch">${corrSyms[i]}</span>${row.map((c) => `<span class="cc" style="background:${c >= 0 ? `rgba(239,68,68,${c * 0.8})` : `rgba(79,140,255,${-c * 0.8})`}" title="${nf2.format(c)}">${c.toFixed(1).replace(".", ",")}</span>`).join("")}`).join("")}</div><p class="muted small">Rot = laufen zusammen (Klumpenrisiko), Blau = gleichen sich aus.</p>`),
    card("sentiment", "🌡️ AKYTEX Sentiment-Index", si.label, `<div class="si">${gaugeSmall(si.value, si.label)}</div><div class="lab-kv"><div><span>Marktbreite</span><b>${Math.round(si.parts.breadth * 100)} %</b></div><div><span>Momentum 5T</span><b class="${cls(si.parts.mom)}">${pct(si.parts.mom)}</b></div><div><span>Ø RSI</span><b>${nf2.format(si.parts.rsi)}</b></div><div><span>Community ${sym}</span><b>${cs.n ? Math.round(cs.bull * 100) + " % bullisch" : "–"}</b></div></div>`),
    card("sectors", "🔄 Sektor-Rotation", "5 Tage", bars(rot.map((x) => ({ label: `${x.name} · ${x.phase}`, v: x.d5 * 100 })), { fmt: (v) => (v > 0 ? "+" : "") + nf2.format(v) + " %" })),
    card("anomalies", "📡 Anomalie-Radar", "Ungewöhnliche Bewegungen", `<ul class="lab-list">${an.map((x) => `<li><button class="sym-chip" data-open-sym="${x.sym}">${x.sym}</button> ${pct(x.chg)} · ${nf2.format(x.z)} σ · Volumen ${nf2.format(x.volX)}×</li>`).join("") || "<li class='muted'>Alles ruhig.</li>"}</ul>`),
    card("similar", "🧬 Ähnliche Setups & Relative Stärke", sym, `<ul class="lab-list">${sim.map((x) => `<li><button class="sym-chip" data-lab-sym="${x.sym}">${x.sym}</button> ${Math.round(x.similarity * 100)} % ähnlich</li>`).join("")}</ul><div class="lab-kv"><div><span>20T ${sym}</span><b class="${cls(rs.own)}">${pct(rs.own)}</b></div><div><span>20T Markt</span><b class="${cls(rs.market)}">${pct(rs.market)}</b></div><div><span>Rang</span><b>${rs.rank} / ${rs.of}</b></div></div>`),
    card("sizing", "📐 Positionsgröße & Treffer-Chance", `${sym} · 1 % Risiko`, `<div class="lab-kv"><div><span>Einstieg</span><b>${eur(v.price)}</b></div><div><span>Stop (1,5 × ATR)</span><b class="down">${eur(v.h.setup.sl)}</b></div><div><span>Ziel (3 × ATR)</span><b class="up">${eur(v.h.setup.tp)}</b></div><div><span>Stückzahl</span><b>${sz.qty}</b></div><div><span>Positionswert</span><b>${eur(sz.value)}</b></div><div><span>Ziel vor Stop</span><b>${hit == null ? "–" : Math.round(hit * 100) + " %"}</b></div></div>${sz.qty ? `<button class="btn primary small" data-lab-buy="${sym}" data-qty="${sz.qty}">${sz.qty} ${sym} mit Stop & Ziel kaufen</button>` : ""}`),
    card("rebalance", "⚖️ Rebalancing", "Gleichgewichtet · 10 % Cash", rb.targets.length ? `${bars(rb.targets.map((x) => ({ label: x.sym, v: (x.target - x.cur) * 100 })), { fmt: (v) => (v > 0 ? "+" : "") + nf2.format(v) + " Pp" })}${rb.trades.length ? `<button class="btn primary small" data-lab-rebal>Rebalancing ausführen (${rb.trades.length} Trades)</button>` : "<p class='muted'>Bereits ausgewogen.</p>"}` : "<p class='muted'>Noch keine Positionen.</p>"),
    card("journal", "📓 Trade-Journal der AI", `${aiEngine.state.journal.length} Einträge`, j.length ? `<div class="table-scroll"><table class="grid mini-table"><thead><tr><th>Zeit</th><th>Trade</th><th>Rating</th><th class="num">RSI</th><th class="num">Konf.</th></tr></thead><tbody>${j.map((x) => `<tr><td>${clock(x.ts)}</td><td><span class="tag ${x.side}">${x.side === "buy" ? "K" : "V"}</span> ${x.qty} ${x.sym}</td><td>${x.rating}</td><td class="num">${x.rsi ?? "–"}</td><td class="num">${x.conf ?? "–"}</td></tr>`).join("")}</tbody></table></div>` : "<p class='muted'>Noch keine AI-Trades.</p>", true),
    card("perf", "🏁 Autopilot-Performance", STRATEGIES[aiEngine.state.config.strategy]?.label || "", `<div class="lab-kv"><div><span>Realisiert</span><b class="${cls(aiEngine.state.aiPnl)}">${sEur(aiEngine.state.aiPnl)}</b></div><div><span>Verkäufe / Gewinner</span><b>${sells.n} / ${sells.wins}</b></div><div><span>Trefferquote</span><b>${sells.n ? Math.round((sells.wins / sells.n) * 100) + " %" : "–"}</b></div><div><span>Schattenmodus</span><b class="${cls(aiEngine.state.shadow.pnl)}">${sEur(aiEngine.state.shadow.pnl)}</b></div></div><p class="muted small">Schattenmodus: Der Autopilot entscheidet, handelt aber nicht – so testest du Strategien risikofrei.</p>`),
    card("tax", "🧾 Steuer-Tipps", "Sparerpauschbetrag & Verluste", `<ul class="lab-list">${lab.taxHints(broker, market).map((h) => `<li>${h}</li>`).join("")}</ul>`),
  ].join("");
  if (labFocus) {
    const el = $("#lab-" + labFocus);
    el?.scrollIntoView({ behavior: "smooth", block: "center" });
    labFocus = null;
  }
}

// Zeitplan
function renderPlanPane() {
  const sel = $("#sc-sym");
  if (!sel.options.length) {
    sel.innerHTML = STOCKS.map((s) => `<option value="${s.s}">${s.s}</option>`).join("");
    $("#sc-cond").innerHTML = Object.entries(CONDITIONS).map(([k, c]) => `<option value="${k}">${c.label}</option>`).join("");
    const d = new Date(Date.now() + 5 * 60000);
    d.setSeconds(0, 0);
    $("#sc-at").value = new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
  }
  sel.value = sel.value || settings.symbol;
  renderSchedPreview();
  renderSchedList();
  renderApHours();
}
function schedFromForm() {
  const action = { side: $("#sc-side").value, sym: $("#sc-sym").value, mode: $("#sc-mode").value, value: +$("#sc-val").value, limit: parseFloat($("#sc-limit").value) || null };
  if (schedType === "once") return { type: "once", action, at: new Date($("#sc-at").value).getTime() };
  if (schedType === "recurring") return { type: "recurring", action, every: $("#sc-every").value, weekday: +$("#sc-wd").value, monthday: +$("#sc-wd").value, time: $("#sc-time").value };
  return { type: "rule", action, cond: { kind: $("#sc-cond").value, value: +$("#sc-cval").value }, window: { from: $("#sc-from").value, to: $("#sc-to").value }, once: $("#sc-once").checked, cooldownMin: 60 };
}
function renderSchedPreview() {
  try {
    const t = schedFromForm();
    $("#sched-preview").innerHTML = `⏱ ${esc(scheduler.describe({ ...t, at: t.at || Date.now() }))}`;
  } catch (_) {
    $("#sched-preview").textContent = "";
  }
}
const fmtCountdown = (ms) => {
  if (ms <= 0) return "jetzt";
  const s = Math.floor(ms / 1000);
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  return d ? `${d} T ${h} Std.` : h ? `${h}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}` : `${m}:${String(sec).padStart(2, "0")}`;
};
function renderSchedList() {
  const tasks = scheduler.state.tasks;
  $("#sched-count").textContent = `${tasks.filter((t) => t.enabled).length} aktiv`;
  $("#sched-list").innerHTML = tasks.length
    ? tasks
        .map((t) => {
          const due = t.type === "once" ? t.at : t.type === "recurring" ? t.next : null;
          const total = t.type === "once" ? t.at - t.created : t.type === "recurring" ? (t.every === "hourly" ? 3600000 : t.every === "monthly" ? 30 * 86400000 : t.every === "weekly" ? 7 * 86400000 : 86400000) : 1;
          const left = due ? due - Date.now() : 0;
          const prog = due ? Math.max(0, Math.min(1, 1 - left / total)) : 0;
          const C = 2 * Math.PI * 18;
          return `<div class="sched-item ${t.enabled ? "" : "off"} ${t.type}">
            <div class="cd-ring"><svg viewBox="0 0 44 44"><circle cx="22" cy="22" r="18" class="ring-bg"/><circle cx="22" cy="22" r="18" class="ring-fg" stroke="${t.type === "rule" ? "#a78bfa" : t.action.side === "buy" ? "#22c55e" : "#ef4444"}" stroke-dasharray="${(t.type === "rule" ? 1 : prog) * C} ${C}" transform="rotate(-90 22 22)"/></svg><span>${t.type === "rule" ? "⚡" : t.type === "recurring" ? "🔁" : "⏱"}</span></div>
            <div class="si-body"><b>${esc(scheduler.describe(t))}</b><small class="muted">${t.done ? "erledigt" : !t.enabled ? "pausiert" : t.type === "rule" ? `überwacht live · ${t.runs.length}× ausgelöst` : `in <span class="cd" data-due="${due}">${fmtCountdown(left)}</span>`}${t.runs[0] ? ` · zuletzt: ${esc(t.runs[0].msg)}` : ""}</small></div>
            <div class="si-actions"><button class="mini-btn" data-sched-run="${t.id}" title="Jetzt ausführen">▶</button><button class="switch ${t.enabled ? "on" : ""}" data-sched-toggle="${t.id}"><i></i></button><button class="mini-btn" data-sched-del="${t.id}" title="Löschen">✕</button></div>
          </div>`;
        })
        .join("")
    : `<div class="empty-state small"><div class="orb tiny spin"><i></i><i></i><i></i></div><p class="muted">Noch keine Aufträge. Lege links einen an – oder sag im Chat z. B. „Kaufe 10 SAP um 15:30“.</p></div>`;
}
function renderApHours() {
  const c = aiEngine.state.config;
  const tog = (k, label, desc) => `<div class="set-row"><div><b>${label}</b><small class="muted">${desc}</small></div><button class="switch ${c[k] ? "on" : ""}" data-apbool="${k}"><i></i></button></div>`;
  $("#ap-hours").innerHTML = `
    ${tog("hoursOn", "Handelszeiten festlegen", "Der Autopilot handelt nur im gewählten Zeitfenster")}
    <div class="row3 ${c.hoursOn ? "" : "dim"}"><label class="field"><span>Von</span><input type="time" data-apstr="from" value="${c.from}" /></label><label class="field"><span>Bis</span><input type="time" data-apstr="to" value="${c.to}" /></label><div class="field"><span>Tage</span><div class="days">${[1, 2, 3, 4, 5, 6, 0].map((d) => `<button class="${c.days.includes(d) ? "on" : ""}" data-apday="${d}">${WEEKDAYS[d]}</button>`).join("")}</div></div></div>
    <label class="slider"><span>Notbremse: Pause bei Tagesverlust<b id="apv-maxDailyLoss">−${c.maxDailyLoss} %</b></span><input type="range" data-ap="maxDailyLoss" min="1" max="15" step="0.5" value="${c.maxDailyLoss}" /></label>
    <label class="slider"><span>Mindest-Konfidenz für Käufe<b id="apv-minConf">${c.minConf} %</b></span><input type="range" data-ap="minConf" min="30" max="90" step="5" value="${c.minConf}" /></label>
    ${tog("atrStops", "Smart-Stops (ATR)", "Stop und Ziel passen sich der Schwankungsbreite jeder Aktie an")}
    ${tog("shadow", "Schattenmodus", "Autopilot entscheidet, handelt aber nicht – risikofrei testen")}
    <p class="muted small">${aiEngine.inHours() ? "🟢 Aktuell im Handelsfenster" : "🌙 Aktuell außerhalb des Handelsfensters"}</p>`;
}
function tickCountdowns() {
  const sc = $("#spot-cd");
  if (sc && settings.view === "shop") sc.textContent = fmtCountdown(shop.spotlightEndsIn());
  if (settings.view !== "ai" || aiTab !== "plan") return;
  for (const el of $$("#sched-list .cd")) el.textContent = fmtCountdown(+el.dataset.due - Date.now());
}
setInterval(() => {
  if (aiMode()) scheduler.tick();
  tickCountdowns();
}, 1000);
scheduler.on((e) => {
  if (e.kind === "run") {
    toast(e.run.msg, e.run.ok ? "success" : "error", "⏱ Zeitplan");
    beep(e.run.ok ? 1180 : 300, 0.1);
    notify("AKYTEX Zeitplan", e.run.msg);
  }
  if (settings.view === "ai" && aiTab === "plan") renderSchedList();
});

function bindAiTabs() {
  $("#ai-tabs").addEventListener("click", (e) => {
    const b = e.target.closest("[data-aitab]");
    if (b) setAiTab(b.dataset.aitab);
  });
  $("#sched-type").addEventListener("click", (e) => {
    const b = e.target.closest("[data-st]");
    if (!b) return;
    schedType = b.dataset.st;
    $$("#sched-type button").forEach((x) => x.classList.toggle("active", x === b));
    $$(".st-pane").forEach((p) => (p.hidden = p.dataset.stp !== schedType));
    if (schedType === "rule" && !$("#sc-cval").value) $("#sc-cval").value = roundTo(market.get($("#sc-sym").value).price * 0.97, 0.01).toFixed(2);
    renderSchedPreview();
  });
  $("#sched-form").addEventListener("input", renderSchedPreview);
  $("#sched-form").addEventListener("change", (e) => {
    if (e.target.id === "sc-sym" && schedType === "rule") $("#sc-cval").value = roundTo(market.get(e.target.value).price * 0.97, 0.01).toFixed(2);
    renderSchedPreview();
  });
  $("#sched-form").addEventListener("click", (e) => {
    const q = e.target.closest("[data-qt]");
    if (!q) return;
    let d;
    if (q.dataset.qt === "open") {
      d = new Date();
      d.setDate(d.getDate() + 1);
      d.setHours(9, 0, 0, 0);
    } else d = new Date(Date.now() + +q.dataset.qt * 60000);
    $("#sc-at").value = new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
    renderSchedPreview();
  });
  $("#sched-form").addEventListener("submit", (e) => {
    e.preventDefault();
    if (!aiMode()) return openPlans("Zeitpläne und Regeln sind Teil von AKYTEX AI.");
    const t = schedFromForm();
    if (!(t.action.value > 0)) return shake($("#sc-val"));
    if (t.type === "once" && !(t.at > Date.now())) return toast("Bitte einen Zeitpunkt in der Zukunft wählen.", "error");
    if (t.type === "rule" && CONDITIONS[t.cond.kind].unit != null && !(t.cond.value > 0)) return shake($("#sc-cval"));
    scheduler.add(t);
    haptic(12);
    toast(scheduler.describe(scheduler.state.tasks[0]), "success", "⏱ Auftrag angelegt");
    renderSchedList();
  });
  $("#sched-list").addEventListener("click", (e) => {
    const r = e.target.closest("[data-sched-run]");
    if (r) {
      const t = scheduler.state.tasks.find((x) => x.id === r.dataset.schedRun);
      if (t) scheduler.execute(t, "manuell gestartet");
      return renderSchedList();
    }
    const tg = e.target.closest("[data-sched-toggle]");
    if (tg) return scheduler.toggle(tg.dataset.schedToggle);
    const d = e.target.closest("[data-sched-del]");
    if (d) return scheduler.remove(d.dataset.schedDel);
  });
  $("#ap-hours").addEventListener("click", (e) => {
    const c = aiEngine.state.config;
    const b = e.target.closest("[data-apbool]");
    if (b) {
      c[b.dataset.apbool] = !c[b.dataset.apbool];
      aiEngine.save();
      haptic(6);
      return renderApHours();
    }
    const d = e.target.closest("[data-apday]");
    if (d) {
      const day = +d.dataset.apday;
      c.days = c.days.includes(day) ? c.days.filter((x) => x !== day) : [...c.days, day];
      aiEngine.save();
      return renderApHours();
    }
  });
  $("#ap-hours").addEventListener("change", (e) => {
    const k = e.target.dataset.apstr;
    if (!k) return;
    aiEngine.state.config[k] = e.target.value;
    aiEngine.save();
  });
  $("#lab-sym").addEventListener("change", (e) => {
    labSym = e.target.value;
    renderLab();
  });
  $("#lab-grid").addEventListener("click", (e) => {
    const bt = e.target.closest("[data-bt]");
    if (bt) {
      labBt = bt.dataset.bt;
      labFocus = "backtest";
      return renderLab();
    }
    const ls = e.target.closest("[data-lab-sym]");
    if (ls) {
      labSym = ls.dataset.labSym;
      return renderLab();
    }
    const lb = e.target.closest("[data-lab-buy]");
    if (lb) {
      if (!aiMode()) return openPlans("Das AI-Labor ist Teil von AKYTEX AI.");
      const v = aiEngine.scan(lb.dataset.labBuy);
      const step = tickStep(v.price);
      const r = broker.placeOrder({ symbol: lb.dataset.labBuy, side: "buy", type: "market", qty: +lb.dataset.qty, sl: roundTo(v.h.setup.sl, step), tp: roundTo(v.h.setup.tp, step) });
      if (!r.ok) toast(r.msg, "error");
      return;
    }
    if (e.target.closest("[data-lab-rebal]")) {
      if (!aiMode()) return openPlans("Das AI-Labor ist Teil von AKYTEX AI.");
      const rb = lab.rebalance(broker, market, "equal");
      let ok = 0;
      for (const t of rb.trades) if (broker.placeOrder({ symbol: t.sym, side: t.side, type: "market", qty: t.qty }).ok) ok++;
      toast(`${ok} von ${rb.trades.length} Trades ausgeführt.`, "success", "Rebalancing");
      return renderLab();
    }
  });
  $("#feat-grid").addEventListener("click", (e) => {
    const b = e.target.closest("[data-feat]");
    if (!b) return;
    FEATURES[+b.dataset.feat][3]();
  });
}

// Die 50 neuen AKYTEX-AI-Funktionen
const ask = (q) => () => {
  setAiTab("cockpit");
  setTimeout(() => sendChat(q), 250);
};
const labGo = (tool) => () => {
  labFocus = tool;
  labSym = settings.symbol;
  setAiTab("lab");
};
const planGo = () => setAiTab("plan");
const FEATURES = [
  ["🧭", "Multi-Timeframe-Konsens", "15m, 1H, 4H und 1T in einem Urteil", labGo("mtf")],
  ["🎯", "Signal-Konfidenz", "Wie einig sind sich Indikatoren und Zeitebenen?", labGo("mtf")],
  ["🔍", "Score-Erklärung", "Welche Indikatoren das Rating treiben", labGo("explain")],
  ["🕯️", "Kerzenmuster-Erkennung", "Hammer, Engulfing, Morning Star & Co.", labGo("patterns")],
  ["↘️", "RSI-Divergenzen", "Versteckte Trendwenden früh erkennen", labGo("patterns")],
  ["🟡", "Bollinger-Squeeze", "Ruhe vor dem Sturm erkennen", labGo("patterns")],
  ["🚀", "Ausbruchs-Erkennung", "20-Tage-Hoch oder -Tief gebrochen", labGo("patterns")],
  ["💪", "Trendstärke (ADX)", "Trend oder Seitwärtsphase?", labGo("patterns")],
  ["🧱", "Unterstützungs-/Widerstandszonen", "Aus echten Umkehrpunkten geclustert", labGo("patterns")],
  ["🏎️", "Relative Stärke", "Aktie vs. Gesamtmarkt mit Rang", labGo("similar")],
  ["🔄", "Sektor-Rotation", "Führende und schwächelnde Branchen", labGo("sectors")],
  ["🌡️", "Sentiment-Index", "Angst & Gier des Marktes (0–100)", labGo("sentiment")],
  ["🌪️", "Volatilitäts-Regime", "Ruhig, normal oder stürmisch", labGo("mtf")],
  ["📡", "Anomalie-Radar", "Ungewöhnliche Kurs- und Volumensprünge", labGo("anomalies")],
  ["📈", "Prognose-Korridor", "Wahrscheinliche Kursspanne für 20 Tage", labGo("forecast")],
  ["🤔", "Was-wäre-wenn-Simulator", "Szenarien für eine Investition", ask("Was wäre, wenn ich 5000 € in NVDA investiere?")],
  ["🎲", "Monte-Carlo-Depot", "500 Zukunftsszenarien für dein Depot", labGo("montecarlo")],
  ["🛡️", "Value at Risk", "Möglicher Verlust an einem schlechten Tag", labGo("risk")],
  ["🧩", "Korrelations-Matrix", "Klumpenrisiko sichtbar machen", labGo("corr")],
  ["⏪", "Strategie-Backtest", "3 Strategien gegen Kaufen & Halten", labGo("backtest")],
  ["🧬", "Ähnliche Setups", "Aktien mit gleichem technischem Bild", labGo("similar")],
  ["⚔️", "Aktienvergleich", "Zwei Aktien Seite an Seite", ask("Vergleiche SAP und MSFT")],
  ["📋", "Themen-Watchlists", "Dividende, Wachstum, Value, Tech …", ask("Baue mir eine Watchlist für Dividende")],
  ["📐", "Positionsgrößen-Rechner", "Stückzahl nach Risiko in %", labGo("sizing")],
  ["⚖️", "Rebalancing-Assistent", "Depot auf Zielgewichte bringen", labGo("rebalance")],
  ["🧾", "Steuer-Tipps", "Pauschbetrag & Verlustverrechnung", labGo("tax")],
  ["👥", "Community-Stimmung", "Long/Short-Verhältnis der Ideen", labGo("sentiment")],
  ["✍️", "Ideen-Entwurf per AI", "Die AI schreibt deine nächste Idee", ask("Schreib eine Idee zu SAP")],
  ["🧠", "Chat-Gedächtnis", "„Und davon 5 kaufen?“ – versteht Bezüge", ask("Was hältst du von ASML?")],
  ["⌨️", "Slash-Befehle", "/prognose, /backtest, /risiko, /plan …", ask("/hilfe")],
  ["🔊", "Vorlesen", "Antworten per Sprachausgabe anhören", ask("Wie ist die Marktlage heute?")],
  ["💬", "Limit-Orders per Chat", "„Kaufe 10 SAP limit 230“", ask("Kaufe 10 SAP limit 230")],
  ["🔔", "Alarme per Chat", "„Alarm wenn TSLA über 260“", ask("Alarm wenn TSLA über 260")],
  ["⏱", "Zeitgesteuerte Orders", "Kaufen oder verkaufen zur Wunschzeit", planGo],
  ["🔁", "Sparpläne", "Täglich, wöchentlich, monatlich investieren", ask("Sparplan 200 € ASML monatlich")],
  ["⚡", "Wenn-Dann-Regeln", "Kurs, RSI, Rating oder Tagesänderung als Auslöser", ask("Kaufe NVDA wenn RSI unter 30")],
  ["⏳", "Live-Countdowns", "Jeder Auftrag mit Countdown und Verlauf", planGo],
  ["🕘", "Autopilot-Handelszeiten", "Nur zu deinen Zeiten und Tagen handeln", planGo],
  ["🛑", "Tagesverlust-Notbremse", "Pausiert den Autopiloten automatisch", planGo],
  ["🎛️", "5 Strategie-Presets", "Defensiv, AI-Mix, Offensiv, Momentum, Rebound", () => setAiTab("cockpit")],
  ["🎚️", "Konfidenz-Schwelle", "Autopilot kauft nur bei hoher Sicherheit", planGo],
  ["📏", "Smart-Stops (ATR)", "Stops passend zur Schwankung jeder Aktie", planGo],
  ["👻", "Schattenmodus", "Strategien risikofrei mitlaufen lassen", planGo],
  ["🏁", "Autopilot-Performance", "Trefferquote und Gewinn der AI-Trades", labGo("perf")],
  ["📓", "Automatisches Trade-Journal", "Jeder Trade mit Rating, RSI und Konfidenz", labGo("journal")],
  ["☀️", "Briefing & Rückblick", "Morgens planen, abends auswerten", ask("/rückblick")],
  ["🪪", "Persönliches Anlageprofil", "Risiko und Ziel aus dem Onboarding fließen ein", () => (account.signedIn ? ((acctTab = "profile"), setView("account")) : openOnboarding())],
  ["🎯", "Ziel-Wahrscheinlichkeit", "Chance, das Ziel vor dem Stop zu erreichen", labGo("sizing")],
  ["📉", "Drawdown-Wächter", "Abstand deines Depots zum Höchststand", labGo("risk")],
  ["🗓️", "KI-Tagesplan", "Die 3–6 wichtigsten Schritte für heute", ask("/plan")],
];
function renderFeatures() {
  $("#feat-grid").innerHTML = FEATURES.map(([ic, name, desc], i) => `<button class="feat" data-feat="${i}" style="--k:${i}"><span class="feat-n">${String(i + 1).padStart(2, "0")}</span><span class="feat-ic">${ic}</span><b>${name}</b><small>${desc}</small></button>`).join("");
}

// Vorlesen
function speak(text) {
  try {
    speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(text);
    u.lang = "de-DE";
    u.rate = 1.03;
    speechSynthesis.speak(u);
  } catch (_) {
    toast("Sprachausgabe wird von diesem Browser nicht unterstützt.", "info");
  }
}

// ---------- AKYTEX Store ----------
let shopCat = "all";
const basketAmt = {};
const MERCH_SVG = {
  hoodie: `<path d="M60 38 L84 26 Q100 40 116 26 L140 38 L162 70 L146 82 L140 74 L140 150 L60 150 L60 74 L54 82 L38 70 Z" fill="rgba(255,255,255,.1)" stroke="rgba(255,255,255,.35)" stroke-width="2"/><path d="M88 30 Q100 52 112 30" fill="none" stroke="rgba(255,255,255,.35)" stroke-width="2"/><path d="M90 108 L100 88 L110 108" fill="none" stroke="#ffcf6e" stroke-width="3.5"/>`,
  cap: `<path d="M50 110 Q52 58 100 54 Q148 58 150 110 Z" fill="rgba(255,255,255,.12)" stroke="rgba(255,255,255,.35)" stroke-width="2"/><path d="M50 110 Q100 100 172 118 Q150 128 100 122 Q60 120 50 110" fill="rgba(255,255,255,.2)"/><path d="M90 98 L100 78 L110 98" fill="none" stroke="#ffcf6e" stroke-width="3.5"/>`,
  mug: `<rect x="62" y="56" width="68" height="84" rx="10" fill="rgba(255,255,255,.14)" stroke="rgba(255,255,255,.35)" stroke-width="2"/><path d="M130 76 Q156 76 156 98 Q156 120 130 120" fill="none" stroke="rgba(255,255,255,.35)" stroke-width="7"/><path d="M86 108 L96 88 L106 108" fill="none" stroke="#ffcf6e" stroke-width="3.5"/>`,
  note: `<rect x="64" y="40" width="80" height="110" rx="8" fill="rgba(255,255,255,.14)" stroke="rgba(255,255,255,.35)" stroke-width="2"/><rect x="64" y="40" width="12" height="110" rx="4" fill="rgba(255,255,255,.2)"/><path d="M96 102 L106 82 L116 102" fill="none" stroke="#ffcf6e" stroke-width="3.5"/>`,
};
function productArt(p) {
  const id = "pg" + p.id;
  const merch = MERCH_SVG[p.icon];
  return `<svg viewBox="0 0 200 170" class="p-art"><defs><linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${p.grad[0]}"/><stop offset="1" stop-color="${p.grad[1]}"/></linearGradient><radialGradient id="${id}r" cx=".3" cy=".2" r=".8"><stop offset="0" stop-color="#fff" stop-opacity=".25"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient></defs><rect width="200" height="170" fill="url(#${id})"/><rect width="200" height="170" fill="url(#${id}r)"/>${[...Array(14)].map((_, i) => `<circle cx="${(i * 53) % 200}" cy="${(i * 37) % 170}" r="${(i % 3) * 0.6 + 0.6}" fill="#fff" opacity=".5"/>`).join("")}${merch || `<text x="100" y="104" text-anchor="middle" font-size="58">${p.icon}</text>`}</svg>`;
}
function renderShop() {
  if (settings.view !== "shop") return;
  const bs = shop.baskets();
  const top = bs[0];
  const amt = (b) => basketAmt[b.id] || 1000;
  const bsSpark = (b, w = 320, h = 90) => spark(b.series, w, h, b.d20 >= 0 ? "#22c55e" : "#ef4444");
  $("#spot").innerHTML = `
    <div class="spot-main">
      <div class="spot-glow"></div>
      <span class="spot-badge">🔥 Im Spotlight · wechselt in <b id="spot-cd">${fmtCountdown(shop.spotlightEndsIn())}</b></span>
      <div class="spot-grid">
        <div>
          <div class="spot-ic">${top.icon}</div>
          <h1>${top.name}</h1>
          <p class="muted">${top.desc} · ${top.syms.length} Aktien, gleich gewichtet</p>
          <div class="spot-perf"><div><span>Heute</span><b class="${cls(top.d1)}">${pct(top.d1)}</b></div><div><span>5 Tage</span><b class="${cls(top.d5)}">${pct(top.d5)}</b></div><div><span>20 Tage</span><b class="${cls(top.d20)}">${pct(top.d20)}</b></div></div>
          <div class="spot-members">${top.syms.map((x) => `<button class="sym-chip" data-open-sym="${x}">${x}</button>`).join("")}</div>
          <div class="amt-row">${[500, 1000, 2500, 5000].map((a) => `<button class="${amt(top) === a ? "on" : ""}" data-bamt="${top.id}" data-v="${a}">${a.toLocaleString("de-DE")} €</button>`).join("")}</div>
          <button class="btn primary big" data-binvest="${top.id}">Paket für ${eur(amt(top))} investieren</button>
          <p class="muted small">Kauf per Market-Order aus deinem Depot-Guthaben. Ordergebühren laut Tarif (${eur(plan().fee)} je Aktie im Tarif ${plan().name}).</p>
        </div>
        <div class="spot-chart">${bsSpark(top, 420, 200)}<span class="muted small">Paket-Index · 30 Tage</span></div>
      </div>
    </div>
    <div class="spot-side">${bs.slice(1, 3).map((b) => `<button class="spot-mini" data-shopcat="basket"><span class="spot-ic sm">${b.icon}</span><div><b>${b.name}</b><small class="${cls(b.d5)}">${pct(b.d5)} in 5 Tagen</small></div>${spark(b.series, 120, 40, b.d5 >= 0 ? "#22c55e" : "#ef4444")}</button>`).join("")}
      <button class="spot-mini gold" data-shop-add="r-picks"><span class="spot-ic sm">📑</span><div><b>Top 10 AI-Picks von heute</b><small>Report · ${eur(4.99)}</small></div></button></div>`;
  $("#shop-cats").innerHTML = Object.entries(CATS).map(([k, l]) => `<button class="${shopCat === k ? "active" : ""}" data-shopcat="${k}">${l}</button>`).join("");
  const basketCard = (b, i) => `<article class="p-card basket" style="--k:${i}"><div class="b-head"><span class="spot-ic sm">${b.icon}</span><div><b>${b.name}</b><small class="muted">${b.syms.join(" · ")}</small></div>${i === 0 ? '<span class="hot">🔥 #1</span>' : ""}</div>${bsSpark(b, 300, 70)}<div class="spot-perf sm"><div><span>5T</span><b class="${cls(b.d5)}">${pct(b.d5)}</b></div><div><span>20T</span><b class="${cls(b.d20)}">${pct(b.d20)}</b></div></div><div class="amt-row sm">${[500, 1000, 2500].map((a) => `<button class="${amt(b) === a ? "on" : ""}" data-bamt="${b.id}" data-v="${a}">${a.toLocaleString("de-DE")} €</button>`).join("")}</div><button class="btn primary" data-binvest="${b.id}">Investieren</button></article>`;
  const prodCard = (p, i) => {
    const owned = shop.owns(p.id);
    const inCart = shop.state.cart.some((c) => c.id === p.id);
    const cta = owned ? `<button class="btn" data-shop-open="${p.id}">${p.cat === "strategy" ? "Aktivieren" : "Öffnen"}</button>` : `<button class="btn primary" data-shop-add="${p.id}">${inCart && !p.physical && !p.gift ? "✓ Im Warenkorb" : "In den Warenkorb"}</button>`;
    return `<article class="p-card" style="--k:${i}">${productArt(p)}<div class="p-body"><span class="p-cat">${CATS[p.cat]}</span><b>${esc(p.name)}</b><small>${esc(p.desc)}</small><div class="p-foot"><b class="p-price">${eur(p.price)}</b>${owned ? '<span class="incl">gekauft</span>' : ""}${cta}</div></div></article>`;
  };
  let html = "";
  if (shopCat === "basket") html = bs.map(basketCard).join("");
  else if (shopCat === "all") html = bs.slice(0, 3).map(basketCard).join("") + PRODUCTS.map(prodCard).join("");
  else html = PRODUCTS.filter((p) => p.cat === shopCat).map(prodCard).join("");
  $("#shop-grid").innerHTML = html;
}
function syncCart() {
  const n = shop.count();
  $("#cart-badge").hidden = !n;
  $("#cart-badge").textContent = n;
}
function openCart() {
  renderCart();
  const d = $("#cart-drawer");
  d.hidden = false;
  requestAnimationFrame(() => d.classList.add("open"));
}
function closeCart() {
  const d = $("#cart-drawer");
  d.classList.remove("open");
  setTimeout(() => (d.hidden = true), 380);
}
function renderCart() {
  const items = shop.cartItems();
  const sub = items.reduce((s, i) => s + i.price * i.qty, 0);
  const physical = items.some((i) => i.physical);
  $("#cart-body").innerHTML = items.length
    ? `<ul class="cart-list">${items.map((i) => `<li><div class="cart-art">${productArt(i)}</div><div><b>${esc(i.name)}</b><small class="muted">${eur(i.price)}</small>${i.physical || i.gift ? `<div class="qty-step"><button data-cart-q="${i.id}" data-d="-1">−</button><span>${i.qty}</span><button data-cart-q="${i.id}" data-d="1">+</button></div>` : ""}</div><div class="cart-r"><b>${eur(i.price * i.qty)}</b><button class="link-btn" data-cart-rm="${i.id}">Entfernen</button></div></li>`).join("")}</ul>
      <div class="co-sum"><div><span>Zwischensumme</span><b>${eur(sub)}</b></div>${physical ? `<div><span>Versand</span><b>${sub >= 50 ? "kostenlos" : eur(4.9)}</b></div>` : ""}<div class="co-total"><span>Gesamt</span><b>${eur(sub + (physical && sub < 50 ? 4.9 : 0))}</b></div><div class="muted small"><span>inkl. 19 % MwSt.</span></div></div>
      <button class="hold-pay static" data-cart-checkout><span class="hp-label">Zur Kasse mit ΛKYTEX Pay</span></button>`
    : `<div class="empty-state"><div class="spot-ic">🛍️</div><h3>Dein Warenkorb ist leer</h3><p class="muted">Entdecke Strategien, Kurse und Merch im Store.</p><button class="btn primary" data-goto="shop" data-close-drawer>Zum Store</button></div>`;
}
// Wird von AKYTEX Pay nach erfolgreicher (Test-)Zahlung aufgerufen
function shopComplete(items, T, method, address) {
  const order = shop.complete(items, T.due, method, address);
  account.addInvoice({ date: Date.now(), lines: T.lines.concat(T.discount ? [{ label: `Gutschein ${pay.promo}`, amount: -T.discount }] : []), total: T.due, note: `Bestellung ${order.no}${order.codes.length ? " · Geschenkcodes: " + order.codes.map((c) => c.code).join(", ") : ""}` });
  account.save();
  syncCart();
  if (settings.view === "shop") renderShop();
  if (order.codes.length) setTimeout(() => toast(order.codes.map((c) => `${c.code} (${eur(c.value)})`).join(" · "), "success", "🎁 Deine Geschenkcodes"), 1200);
  return order;
}
function investBasket(id) {
  const b = BASKETS.find((x) => x.id === id);
  const amount = basketAmt[id] || 1000;
  const per = amount / b.syms.length;
  let ok = 0;
  const fails = [];
  for (const sym of b.syms) {
    const q = market.quote(sym);
    const qty = Math.floor(per / q.ask);
    if (qty < 1) {
      fails.push(sym);
      continue;
    }
    const r = broker.placeOrder({ symbol: sym, side: "buy", type: "market", qty });
    if (r.ok) ok++;
    else fails.push(sym);
  }
  if (ok) {
    confetti();
    toast(`${ok} von ${b.syms.length} Aktien gekauft${fails.length ? ` (${fails.join(", ")}: Betrag zu klein oder Kaufkraft fehlt)` : ""}.`, "success", `${b.icon} ${b.name} im Depot`);
  } else toast("Betrag zu klein oder nicht genug Kaufkraft.", "error");
}
const LESSON_TEXT = {
  "Was ist eine Aktie?": "Eine Aktie ist ein Anteil an einem Unternehmen. Steigt der Wert des Unternehmens oder schüttet es Gewinne aus, profitierst du anteilig – sinkt er, verlierst du.",
  "Orderarten: Market, Limit, Stopp": "Market kauft sofort zum aktuellen Kurs. Limit kauft nur zu deinem Wunschpreis oder besser. Stopp wird zur Market-Order, sobald eine Schwelle erreicht ist – ideal zum Absichern.",
  "Kosten verstehen: Spread & Gebühren": "Der Spread ist die Differenz zwischen Kauf- und Verkaufskurs. Dazu kommen Ordergebühren. AKYTEX zeigt dir vor jeder Order alle Kosten.",
  "Risiko begrenzen mit Stop-Loss": "Lege vor dem Kauf fest, wie viel du maximal verlieren willst – etwa 1 % des Depots pro Trade – und setze den Stop entsprechend.",
  "Diversifikation richtig": "Verteile dein Geld auf mehrere Aktien und Branchen. Mehr als 20 % in einer Aktie erhöht das Klumpenrisiko deutlich.",
  "Sparpläne und Zinseszins": "Regelmäßig kleine Beträge investieren glättet Einstiegskurse. Über Jahre wirkt der Zinseszins – Gewinne erzeugen weitere Gewinne.",
  "Dein erster Plan": "Ziel festlegen, Risiko definieren, 3–5 Aktien aus verschiedenen Branchen wählen, Stops setzen, Sparplan einrichten, monatlich prüfen.",
};
function openContent(p) {
  let html = "";
  if (p.lessons) html = `<ol class="lessons">${p.lessons.map((l, i) => `<li><details ${i === 0 ? "open" : ""}><summary><span>${i + 1}</span>${esc(l)}</summary><p>${esc(LESSON_TEXT[l] || "In dieser Lektion lernst du die Grundlagen zu „" + l + "“ Schritt für Schritt – mit Beispielen aus dem AKYTEX-Chart und einer kurzen Übung im Demo-Depot.")}</p></details></li>`).join("")}</ol>`;
  else if (p.report === "picks") {
    const top = aiEngine.scanAll(STOCKS.map((s) => s.s)).slice(0, 10);
    html = `<p class="muted small">Stand ${new Date().toLocaleString("de-DE")} · automatisch von AKYTEX AI berechnet · keine Anlageberatung</p><ol class="report-list">${top.map((v) => `<li><div><b>${v.sym}</b> <span class="muted">${esc(v.name)}</span></div><div class="up">${v.rating.label} · Konfidenz ${lab.confidence(market, v.sym)} %</div><small>${esc(v.reason)} · Ziel ${num(v.h.setup.tp)} · Stop ${num(v.h.setup.sl)}</small></li>`).join("")}</ol>`;
  } else if (p.report === "outlook") {
    const si = lab.sentimentIndex(market);
    const rot = lab.sectorRotation(market);
    const an = lab.anomalies(market);
    html = `<p class="muted small">Stand ${new Date().toLocaleString("de-DE")}</p><h4>Stimmung: ${si.value}/100 – ${si.label}</h4>${gaugeSmall(si.value, si.label)}<h4>Sektoren</h4>${bars(rot.map((x) => ({ label: x.name, v: x.d20 * 100 })), { fmt: (v) => (v > 0 ? "+" : "") + nf2.format(v) + " %" })}<h4>Auffällig</h4><p>${an.map((x) => `<b>${x.sym}</b> ${pct(x.chg)}`).join(" · ") || "Keine Anomalien."}</p><h4>Szenario</h4><p>${si.value > 55 ? "Die Stimmung ist optimistisch – Gewinne laufen lassen, aber Stops nachziehen." : si.value < 45 ? "Vorsicht dominiert – Qualitätswerte mit Rabatt beobachten, Positionen klein halten." : "Neutraler Markt – selektiv nach relativer Stärke vorgehen."}</p>`;
  }
  $("#content-title").textContent = p.name;
  $("#content-body").innerHTML = html;
  openModal("#content-modal");
}
function bindShop() {
  document.addEventListener("click", (e) => {
    const t = e.target;
    const sc = t.closest("[data-shopcat]");
    if (sc) {
      shopCat = sc.dataset.shopcat;
      if (settings.view !== "shop") setView("shop");
      return renderShop();
    }
    const ba = t.closest("[data-bamt]");
    if (ba) {
      basketAmt[ba.dataset.bamt] = +ba.dataset.v;
      return renderShop();
    }
    const bi = t.closest("[data-binvest]");
    if (bi) return investBasket(bi.dataset.binvest);
    const add = t.closest("[data-shop-add]");
    if (add) {
      const ok = shop.add(add.dataset.shopAdd);
      haptic(8);
      syncCart();
      if (ok === false) return openCart();
      toast(shop.product(add.dataset.shopAdd).name, "success", "🛍️ Im Warenkorb");
      const badge = $("#cart-btn");
      badge.classList.remove("bump");
      void badge.offsetWidth;
      badge.classList.add("bump");
      if (settings.view === "shop") renderShop();
      return;
    }
    const op = t.closest("[data-shop-open]");
    if (op) {
      const p = shop.product(op.dataset.shopOpen);
      if (p.unlock) {
        Object.assign(aiEngine.state.config, p.unlock);
        aiEngine.save();
        return toast(`Autopilot nutzt jetzt „${p.name}“.`, "success", "Strategie aktiviert");
      }
      return openContent(p);
    }
    if (t.closest("#cart-btn")) return openCart();
    if (t.closest("[data-close-drawer]") || t.id === "cart-drawer") return closeCart();
    const q = t.closest("[data-cart-q]");
    if (q) {
      const c = shop.state.cart.find((x) => x.id === q.dataset.cartQ);
      shop.setQty(q.dataset.cartQ, (c?.qty || 0) + +q.dataset.d);
      syncCart();
      return renderCart();
    }
    const rm = t.closest("[data-cart-rm]");
    if (rm) {
      shop.setQty(rm.dataset.cartRm, 0);
      syncCart();
      renderCart();
      if (settings.view === "shop") renderShop();
      return;
    }
    if (t.closest("[data-cart-checkout]")) {
      closeCart();
      return openPay({ kind: "shop", items: shop.cartItems() });
    }
  });
  syncCart();
}

// ---------- AKYTEX Clips ----------
const CLIPS_KEY = "akytex-v2-clips";
const clipsState = (() => {
  try {
    return { liked: [], comments: {}, reported: [], myGen: [], ...JSON.parse(localStorage.getItem(CLIPS_KEY) || "{}") };
  } catch (_) {
    return { liked: [], comments: {}, reported: [], myGen: [] };
  }
})();
const saveClips = () => {
  try {
    localStorage.setItem(CLIPS_KEY, JSON.stringify(clipsState));
  } catch (_) {
    /* ignorieren */
  }
};
let clipFilter = "foryou";
let clipList = [];
let clipUrls = [];
let activeClip = null;
let clipRaf = 0;
let clipT0 = 0;
let clipPausedAt = null;
let clipObserver = null;
let pendingFile = null;
const seededComments = ["Starke Analyse 🔥", "Genau mein Level!", "Bin auch Long 🚀", "Stop ist mir zu eng", "Danke fürs Teilen!", "Wie siehst du den RSI?"];
async function loadClips() {
  const demo = demoClips(market, community.traders);
  const mine = await idbAll();
  clipUrls.forEach((u) => URL.revokeObjectURL(u));
  clipUrls = [];
  const user = mine.map((c) => {
    const url = URL.createObjectURL(c.blob);
    clipUrls.push(url);
    return { ...c, url };
  });
  return [...user, ...clipsState.myGen, ...demo].filter((c) => !clipsState.reported.includes(c.id)).sort((a, b) => b.created - a.created);
}
function clipAuthor(c) {
  if (c.author === "me") return { handle: account.state.profile?.name?.replace(/\s+/g, "").toLowerCase() || "du", style: "Dein Clip", color: "#6ea2f2", me: true };
  return community.trader(c.author) || { handle: "trader", style: "", color: "#64748b" };
}
async function renderClips() {
  if (settings.view !== "clips") return;
  clipList = await loadClips();
  const list = clipList.filter((c) => (clipFilter === "mine" ? c.author === "me" : clipFilter === "following" ? community.isFollowing(c.author) : true));
  const feed = $("#clips-feed");
  feed.innerHTML = list.length
    ? list
        .map((c) => {
          const a = clipAuthor(c);
          const liked = clipsState.liked.includes(c.id);
          const q = market.quote(c.sym);
          const nCom = (c.comments || 0) + (clipsState.comments[c.id]?.length || 0);
          return `<article class="clip" data-clip="${c.id}">
            <div class="clip-stage" data-clip-stage="${c.id}">${c.kind === "video" ? `<video src="${c.url}" playsinline muted loop preload="metadata"></video>` : `<canvas></canvas>`}<div class="clip-paused">▶</div><div class="heart-burst">♥</div></div>
            <div class="clip-prog"><i></i></div>
            <div class="clip-info">
              <div class="ci-author">${avatar(a)}<b>@${esc(a.handle)}</b>${a.me ? "" : `<button class="follow-btn sm ${community.isFollowing(c.author) ? "on" : ""}" data-follow="${c.author}">${community.isFollowing(c.author) ? "Gefolgt" : "Folgen"}</button>`}</div>
              <p>${esc(c.title || c.caption || "")}</p>
              <div class="ci-tags">${(c.tags || []).map((t) => `<span>${esc(t)}</span>`).join("")}</div>
              <button class="ci-sym" data-open-sym="${c.sym}"><b>${c.sym}</b> ${num(q.price)} € <span class="${cls(q.change)}">${pct(q.changePct)}</span></button>
            </div>
            <div class="clip-rail">
              <button class="${liked ? "on" : ""}" data-clip-like="${c.id}"><span>♥</span><small>${compact((c.likes || 0) + (liked ? 1 : 0))}</small></button>
              <button data-clip-cmt="${c.id}"><span>💬</span><small>${nCom}</small></button>
              <button data-clip-share="${c.id}"><span>↗</span><small>Teilen</small></button>
              <button class="trade" data-clip-trade="${c.sym}"><span>📈</span><small>Handeln</small></button>
              ${c.author === "me" ? `<button data-clip-del="${c.id}"><span>🗑</span><small>Löschen</small></button>` : `<button data-clip-report="${c.id}"><span>⚑</span><small>Melden</small></button>`}
            </div>
          </article>`;
        })
        .join("")
    : `<div class="empty-state clips-empty"><div class="spot-ic">🎬</div><h3>${clipFilter === "mine" ? "Noch keine eigenen Clips" : "Noch nichts hier"}</h3><p class="muted">${clipFilter === "mine" ? "Lade ein Video hoch oder nimm einen Chart-Clip auf." : "Folge Tradern, um ihre Clips hier zu sehen."}</p></div>`;
  clipObserver?.disconnect();
  clipObserver = new IntersectionObserver(
    (es) => {
      for (const e of es) if (e.isIntersecting && e.intersectionRatio > 0.6) playClip(e.target.dataset.clip);
    },
    { root: feed, threshold: [0.6] }
  );
  $$("#clips-feed .clip").forEach((el) => clipObserver.observe(el));
}
function playClip(id) {
  if (activeClip === id && !clipPausedAt) return;
  pauseClips();
  activeClip = id;
  const el = $(`#clips-feed [data-clip="${id}"]`);
  const c = clipList.find((x) => x.id === id);
  if (!el || !c) return;
  el.classList.remove("paused");
  const bar = el.querySelector(".clip-prog i");
  if (c.kind === "video") {
    const v = el.querySelector("video");
    v.play().catch(() => {});
    const loop = () => {
      if (v.duration) bar.style.width = (v.currentTime / v.duration) * 100 + "%";
      clipRaf = requestAnimationFrame(loop);
    };
    loop();
    return;
  }
  const cv = el.querySelector("canvas");
  const dpr = Math.min(2, devicePixelRatio || 1);
  cv.width = cv.clientWidth * dpr;
  cv.height = cv.clientHeight * dpr;
  const ctx = cv.getContext("2d");
  const label = "@" + clipAuthor(c).handle;
  clipT0 = performance.now() - (clipPausedAt || 0);
  clipPausedAt = null;
  const loop = () => {
    const t = (performance.now() - clipT0) % CLIP_MS;
    drawClip(ctx, cv.width, cv.height, c, market, t, label);
    bar.style.width = (t / CLIP_MS) * 100 + "%";
    clipRaf = requestAnimationFrame(loop);
  };
  loop();
}
function pauseClips(keepPos = false) {
  cancelAnimationFrame(clipRaf);
  $$("#clips-feed video").forEach((v) => v.pause());
  clipPausedAt = keepPos ? (performance.now() - clipT0) % CLIP_MS : null;
  if (!keepPos) activeClip = null;
}
function likeClip(id, burst = false) {
  const i = clipsState.liked.indexOf(id);
  if (i >= 0 && !burst) clipsState.liked.splice(i, 1);
  else if (i < 0) clipsState.liked.push(id);
  saveClips();
  haptic(10);
  const el = $(`#clips-feed [data-clip="${id}"]`);
  const btn = el?.querySelector("[data-clip-like]");
  const c = clipList.find((x) => x.id === id);
  if (btn && c) {
    const on = clipsState.liked.includes(id);
    btn.classList.toggle("on", on);
    btn.querySelector("small").textContent = compact((c.likes || 0) + (on ? 1 : 0));
  }
  if (burst && el) {
    const h = el.querySelector(".heart-burst");
    h.classList.remove("go");
    void h.offsetWidth;
    h.classList.add("go");
  }
}
let cmtClip = null;
function openComments(id) {
  cmtClip = id;
  const base = clipList.find((x) => x.id === id);
  const seed = base && base.kind === "gen" && base.author !== "me" ? seededComments.slice(id.length % 3, (id.length % 3) + 3).map((t, k) => ({ who: ["anna_trades", "KaiCharts", "LinaLongs"][k], text: t, ts: base.created + (k + 1) * 600000, demo: true })) : [];
  const list = [...seed, ...(clipsState.comments[id] || [])];
  $("#comments-list").innerHTML = list.length ? list.map((c) => `<div class="cmt"><b>@${esc(c.who)}</b>${c.demo ? '<span class="demo-note small"> Demo</span>' : ""}<p>${esc(c.text)}</p><small class="muted">${ago(c.ts)}</small></div>`).join("") : `<p class="muted">Noch keine Kommentare. Sei der Erste!</p>`;
  openModal("#comments-modal");
}
async function recordChartClip() {
  const sym = settings.symbol;
  const a = analyze(aggregate(market.get(sym).m1.slice(-60 * 24 * 7), "1h"));
  const caps = [`${sym}: mein Blick auf den Chart`, `${a.rating.label} laut AKYTEX AI`, `Ziel ${num(a.setup.tp)} · Stop ${num(a.setup.sl)}`];
  const clip = { id: "m" + Date.now(), kind: "gen", author: "me", sym, title: caps[0], captions: caps, tags: ["#" + sym.toLowerCase(), "#akytex"], likes: 0, comments: 0, created: Date.now(), hue: 250 };
  toast("Aufnahme läuft (8 Sekunden) …", "info", "🎬 Chart-Clip");
  try {
    const blob = await recordClip(clip, market, "@" + clipAuthor(clip).handle);
    await idbPut({ id: clip.id, kind: "video", blob, author: "me", sym, title: caps[0], caption: caps[0], tags: clip.tags, likes: 0, comments: 0, created: Date.now() });
    toast("Dein Chart-Clip ist als Video gespeichert.", "success", "🎬 Clip veröffentlicht");
  } catch (_) {
    clipsState.myGen.unshift(clip);
    saveClips();
    toast("Dein Chart-Clip ist veröffentlicht (Live-Render).", "success", "🎬 Clip veröffentlicht");
  }
  clipFilter = "mine";
  $$("#clips-tabs button").forEach((b) => b.classList.toggle("active", b.dataset.cf === "mine"));
  if (settings.view !== "clips") setView("clips");
  else renderClips();
}
function setClipFile(f) {
  if (!f) return;
  if (!/^video\/(mp4|webm|quicktime)$/.test(f.type)) return toast("Bitte ein MP4-, WebM- oder MOV-Video wählen.", "error");
  if (f.size > 60 * 1024 * 1024) return toast("Das Video ist größer als 60 MB.", "error");
  pendingFile = f;
  $("#clip-drop-inner").innerHTML = `<video src="${URL.createObjectURL(f)}" muted playsinline autoplay loop></video><span class="muted small">${esc(f.name)} · ${nf2.format(f.size / 1048576)} MB</span>`;
}
function bindClips() {
  $("#clips-tabs").addEventListener("click", (e) => {
    const b = e.target.closest("[data-cf]");
    if (!b) return;
    clipFilter = b.dataset.cf;
    $$("#clips-tabs button").forEach((x) => x.classList.toggle("active", x === b));
    renderClips();
  });
  $("#clip-record-btn").addEventListener("click", recordChartClip);
  $("#clip-upload-btn").addEventListener("click", () => {
    pendingFile = null;
    $("#clip-drop-inner").innerHTML = `<b>Video auswählen</b><span class="muted small">MP4, WebM oder MOV · max. 60 MB · Hochformat empfohlen</span>`;
    $("#clip-caption").value = "";
    $("#clip-sym").innerHTML = STOCKS.map((s) => `<option value="${s.s}" ${s.s === settings.symbol ? "selected" : ""}>${s.s} – ${esc(s.n)}</option>`).join("");
    openModal("#clip-modal");
  });
  const drop = $("#clip-drop");
  drop.addEventListener("click", () => $("#clip-file").click());
  $("#clip-file").addEventListener("change", (e) => setClipFile(e.target.files[0]));
  drop.addEventListener("dragover", (e) => {
    e.preventDefault();
    drop.classList.add("over");
  });
  drop.addEventListener("dragleave", () => drop.classList.remove("over"));
  drop.addEventListener("drop", (e) => {
    e.preventDefault();
    drop.classList.remove("over");
    setClipFile(e.dataTransfer.files[0]);
  });
  $("#clip-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    if (!pendingFile) return shake($("#clip-drop"));
    const cap = $("#clip-caption").value.trim();
    const tags = cap.match(/#[\wäöüß]+/gi) || [];
    try {
      await idbPut({ id: "u" + Date.now(), kind: "video", blob: pendingFile, author: "me", sym: $("#clip-sym").value, title: cap.replace(/#[\wäöüß]+/gi, "").trim(), caption: cap, tags, likes: 0, comments: 0, created: Date.now() });
      closeModals();
      confetti();
      toast("Dein Clip ist im Feed.", "success", "🎬 Veröffentlicht");
      clipFilter = "mine";
      $$("#clips-tabs button").forEach((b) => b.classList.toggle("active", b.dataset.cf === "mine"));
      renderClips();
    } catch (_) {
      toast("Speichern nicht möglich (Browser-Speicher voll oder gesperrt).", "error");
    }
  });
  $("#comment-form").addEventListener("submit", (e) => {
    e.preventDefault();
    const v = $("#comment-input").value.trim();
    if (!v || !cmtClip) return;
    (clipsState.comments[cmtClip] ||= []).push({ who: clipAuthor({ author: "me" }).handle, text: v, ts: Date.now() });
    saveClips();
    $("#comment-input").value = "";
    openComments(cmtClip);
    const b = $(`#clips-feed [data-clip-cmt="${cmtClip}"] small`);
    if (b) b.textContent = +b.textContent + 1;
  });
  let lastTap = 0;
  $("#clips-feed").addEventListener("click", async (e) => {
    const t = e.target;
    const st = t.closest("[data-clip-stage]");
    if (st) {
      const id = st.dataset.clipStage;
      const now = Date.now();
      if (now - lastTap < 300) {
        likeClip(id, true);
        lastTap = 0;
        return;
      }
      lastTap = now;
      setTimeout(() => {
        if (lastTap !== now) return;
        const el = st.closest(".clip");
        if (el.classList.contains("paused")) {
          el.classList.remove("paused");
          activeClip = null;
          playClip(id);
        } else {
          el.classList.add("paused");
          pauseClips(true);
          activeClip = id;
        }
      }, 300);
      return;
    }
    const lk = t.closest("[data-clip-like]");
    if (lk) return likeClip(lk.dataset.clipLike);
    const cm = t.closest("[data-clip-cmt]");
    if (cm) return openComments(cm.dataset.clipCmt);
    if (t.closest("[data-clip-share]")) return share();
    const tr = t.closest("[data-clip-trade]");
    if (tr) {
      pauseClips();
      setSymbol(tr.dataset.clipTrade);
      return flashEl($("#ticket"));
    }
    const rp = t.closest("[data-clip-report]");
    if (rp) {
      clipsState.reported.push(rp.dataset.clipReport);
      saveClips();
      toast("Danke für deine Meldung. Der Clip wird geprüft und ist für dich ausgeblendet.", "info", "⚑ Gemeldet");
      return renderClips();
    }
    const dl = t.closest("[data-clip-del]");
    if (dl) {
      const id = dl.dataset.clipDel;
      await idbDel(id).catch(() => {});
      clipsState.myGen = clipsState.myGen.filter((x) => x.id !== id);
      saveClips();
      return renderClips();
    }
  });
  document.addEventListener("keydown", (e) => {
    if (settings.view !== "clips" || e.target.matches("input, textarea, select")) return;
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      $("#clips-feed").scrollBy({ top: (e.key === "ArrowDown" ? 1 : -1) * $("#clips-feed").clientHeight, behavior: "smooth" });
    }
  });
}

// ---------- Weltraum: Sternenfeld mit Parallaxe und Sternschnuppen ----------
function spaceField() {
  const cv = $("#space");
  if (!cv) return;
  const ctx = cv.getContext("2d");
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const dpr = Math.min(2, devicePixelRatio || 1);
  let W = 0;
  let H = 0;
  let stars = [];
  let shoot = null;
  let mx = 0;
  let my = 0;
  let last = 0;
  const hues = [220, 250, 275, 45, 200];
  const init = () => {
    W = cv.width = innerWidth * dpr;
    H = cv.height = innerHeight * dpr;
    const n = Math.min(900, Math.round((innerWidth * innerHeight) / 2300));
    stars = Array.from({ length: n }, () => ({ x: Math.random() * W, y: Math.random() * H, z: Math.random() ** 2, tw: Math.random() * 6.28, h: hues[Math.floor(Math.random() * hues.length)] }));
  };
  init();
  addEventListener("resize", init);
  addEventListener("pointermove", (e) => {
    mx = (e.clientX / innerWidth - 0.5) * 2;
    my = (e.clientY / innerHeight - 0.5) * 2;
  });
  const frame = (t) => {
    requestAnimationFrame(frame);
    const hidden = document.hidden || settings.view === "chart" || document.documentElement.dataset.theme !== "dark";
    if (hidden || t - last < 33) return; // ~30 fps reicht und schont den Akku
    last = t;
    ctx.clearRect(0, 0, W, H);
    for (const s of stars) {
      if (!reduce) {
        s.x -= (0.03 + s.z * 0.18) * dpr;
        if (s.x < 0) s.x += W;
      }
      const x = s.x + mx * s.z * 14 * dpr;
      const y = s.y + my * s.z * 10 * dpr;
      const a = 0.25 + 0.75 * s.z * (0.65 + 0.35 * Math.sin(t / 700 + s.tw));
      const r = (0.35 + s.z * 1.35) * dpr;
      ctx.fillStyle = `hsla(${s.h}, 90%, ${s.h === 45 ? 80 : 88}%, ${a})`;
      ctx.beginPath();
      ctx.arc(x, y, r, 0, 6.283);
      ctx.fill();
      if (s.z > 0.85) {
        ctx.fillStyle = `hsla(${s.h}, 100%, 85%, ${a * 0.12})`;
        ctx.beginPath();
        ctx.arc(x, y, r * 4, 0, 6.283);
        ctx.fill();
      }
    }
    if (!reduce && !shoot && Math.random() < 0.004) shoot = { x: Math.random() * W * 0.8 + W * 0.2, y: Math.random() * H * 0.4, vx: -(8 + Math.random() * 6) * dpr, vy: (3 + Math.random() * 3) * dpr, life: 1 };
    if (shoot) {
      const g = ctx.createLinearGradient(shoot.x, shoot.y, shoot.x - shoot.vx * 12, shoot.y - shoot.vy * 12);
      g.addColorStop(0, `rgba(255,255,255,${shoot.life})`);
      g.addColorStop(1, "rgba(124,156,255,0)");
      ctx.strokeStyle = g;
      ctx.lineWidth = 2 * dpr;
      ctx.beginPath();
      ctx.moveTo(shoot.x, shoot.y);
      ctx.lineTo(shoot.x - shoot.vx * 12, shoot.y - shoot.vy * 12);
      ctx.stroke();
      shoot.x += shoot.vx;
      shoot.y += shoot.vy;
      shoot.life -= 0.02;
      if (shoot.life <= 0) shoot = null;
    }
  };
  requestAnimationFrame(frame);
}

// ---------- Bewegung: Splash, Segmente, Ripple, Haptik ----------
function haptic(pattern) {
  try {
    navigator.vibrate?.(pattern);
  } catch (_) {
    /* nicht unterstützt */
  }
}
function shake(el) {
  el.animate([{ transform: "translateX(0)" }, { transform: "translateX(-8px)" }, { transform: "translateX(7px)" }, { transform: "translateX(-4px)" }, { transform: "translateX(0)" }], { duration: 380, easing: "cubic-bezier(.36,.07,.19,.97)" });
}

function runSplash(replay = false) {
  const brand = $("#brand");
  brand.classList.remove("play");
  void brand.offsetWidth;
  brand.classList.add("play");
  let sp = $("#splash");
  if (!sp) return;
  if (replay) {
    // Knoten klonen, damit alle Animationen neu starten
    const clone = sp.cloneNode(true);
    clone.classList.remove("out");
    sp.replaceWith(clone);
    sp = clone;
  }
  const done = () => sp.classList.add("out");
  sp.addEventListener("click", done);
  setTimeout(done, matchMedia("(prefers-reduced-motion: reduce)").matches ? 200 : 2400);
}

const SEGMENTS = [
  [".views", "pill-ind"],
  [".otype", "pill-ind"],
  ["#hm-period", "pill-ind"],
  ["#idea-filter", "pill-ind"],
  ["#idea-dir", "pill-ind"],
  [".rtabs", "line-ind"],
  [".btab-list", "line-ind"],
];
function initSegments() {
  const conts = [];
  for (const [sel, kind] of SEGMENTS) {
    const c = $(sel);
    if (!c) continue;
    c.classList.add("has-ind", kind);
    const ind = document.createElement("span");
    ind.className = "seg-ind";
    c.prepend(ind);
    conts.push(c);
  }
  let queued = false;
  const sync = () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      for (const c of conts) {
        const a = c.querySelector(":scope > .active");
        const ind = c.firstElementChild;
        if (!a || !a.offsetWidth) {
          ind.style.opacity = 0;
          continue;
        }
        ind.style.opacity = 1;
        ind.style.width = a.offsetWidth + "px";
        ind.style.transform = `translateX(${a.offsetLeft}px)`;
      }
    });
  };
  const mo = new MutationObserver(sync);
  conts.forEach((c) => mo.observe(c, { attributes: true, attributeFilter: ["class", "hidden"], subtree: true }));
  const ro = new ResizeObserver(sync);
  conts.forEach((c) => ro.observe(c));
  document.addEventListener("click", sync);
  sync();
}

function bindRipple() {
  document.addEventListener("pointerdown", (e) => {
    const b = e.target.closest(".submit, .install-btn, .btn.primary, .side");
    if (!b) return;
    b.classList.add("ripple");
    const r = b.getBoundingClientRect();
    const d = Math.max(r.width, r.height) * 2.2;
    const dot = document.createElement("span");
    dot.className = "ripple-dot";
    dot.style.cssText = `width:${d}px;height:${d}px;left:${e.clientX - r.left - d / 2}px;top:${e.clientY - r.top - d / 2}px`;
    b.appendChild(dot);
    setTimeout(() => dot.remove(), 700);
  });
}

// ---------- Teilen ----------
function shareUrl() {
  let base = location.href.split("#")[0].split("?")[0];
  // eingebettet (z. B. als geteilte Seite): Adresse der äußeren Seite verwenden
  if (embedded && document.referrer) {
    try {
      const r = new URL(document.referrer);
      if (r.pathname.length > 1) base = r.origin + r.pathname;
    } catch (_) {
      /* Referrer unbrauchbar */
    }
  }
  const token = settings.view === "chart" ? `${settings.symbol}.${settings.tf}` : settings.view;
  return `${base}#${token}`;
}
window.addEventListener("hashchange", () => {
  const l = parseLink();
  if (l.tf && l.tf !== settings.tf) setTimeframe(l.tf);
  if (l.symbol && l.symbol !== settings.symbol) setSymbol(l.symbol);
  else if (l.view && l.view !== settings.view) setView(l.view);
});
async function share() {
  const url = shareUrl();
  const q = market.quote(settings.symbol);
  const data = { title: `AKYTEX · ${settings.symbol}`, text: `${q.name} (${settings.symbol}) ${num(q.price)} € ${pct(q.changePct)} – schau dir das auf AKYTEX an:`, url };
  haptic(10);
  if (navigator.share && !embedded) {
    try {
      await navigator.share(data);
      return;
    } catch (e) {
      if (e && e.name === "AbortError") return;
    }
  }
  try {
    await navigator.clipboard.writeText(url);
    toast(url, "success", "Link kopiert");
  } catch (_) {
    toast(url, "info", "Link zum Teilen (bitte kopieren)");
  }
}

// ---------- Start ----------
community.ready.then(() => {
  if (settings.view === "ideas") renderIdeas();
});
runSplash();
spaceField();
buildToolbar();
buildTicker();
initSegments();
bindRipple();
$("#share-btn").addEventListener("click", share);
$("#brand").addEventListener("click", () => {
  haptic(8);
  const b = $("#brand");
  b.classList.remove("play");
  void b.offsetWidth;
  b.classList.add("play");
  setView("home");
});
$("#brand").addEventListener("dblclick", () => runSplash(true));
bindGrowth();
bindAI();
bindAiTabs();
bindShop();
bindClips();
bindCheckout();
bindCancel();
bindOnboarding();
bindAccount();
bindShell();
bindDepth();
injectFooters();
checkSubscription();
syncAccountUI();
bindTicket();
bindTables();
bindDrawbar();
bindSearch();
bindIndicators();
bindAlerts();
bindMarkets();
// Zurücksetzen mit Bestätigung direkt am Button (zweiter Klick innerhalb von 4 s)
let resetArmed = null;
$("#reset-btn").addEventListener("click", (e) => {
  const b = e.currentTarget;
  if (!resetArmed) {
    b.textContent = "Wirklich alles löschen? Nochmal klicken";
    b.classList.add("danger-armed");
    resetArmed = setTimeout(() => {
      resetArmed = null;
      b.textContent = "Demo-Konto zurücksetzen";
      b.classList.remove("danger-armed");
    }, 4000);
    return;
  }
  clearTimeout(resetArmed);
  resetArmed = null;
  b.textContent = "Demo-Konto zurücksetzen";
  b.classList.remove("danger-armed");
  broker.reset();
  toast(`Konto zurückgesetzt – ${eur(START_CASH)} Startguthaben.`, "success");
});

chart.configure({ symbol: settings.symbol, tf: settings.tf, type: settings.type, indicators: new Set(settings.indicators), theme: settings.theme });
syncToolbar();
buildWatchlist();
renderQuoteCard();
resetTicketPrices();
renderTicket();
renderAccountBar();
renderBottom();
renderTicker();
setView(settings.view);
setupInstall();
renderAIHeader();
market.start();
