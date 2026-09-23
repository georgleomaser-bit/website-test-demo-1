// Aktex – Demo-Aktienhandel mit simulierten Echtzeitkursen
(() => {
  "use strict";

  const START_CASH = 10000;
  const TICK_MS = 1000;
  const HISTORY_POINTS = 120;
  const STORAGE_KEY = "aktex-demo-account-v1";

  const STOCKS = [
    { symbol: "AAPL", name: "Apple Inc.", price: 189.5, vol: 0.0015 },
    { symbol: "MSFT", name: "Microsoft Corp.", price: 412.3, vol: 0.0014 },
    { symbol: "NVDA", name: "NVIDIA Corp.", price: 118.2, vol: 0.003 },
    { symbol: "AMZN", name: "Amazon.com Inc.", price: 178.9, vol: 0.002 },
    { symbol: "GOOGL", name: "Alphabet Inc.", price: 164.1, vol: 0.0017 },
    { symbol: "META", name: "Meta Platforms Inc.", price: 498.7, vol: 0.0022 },
    { symbol: "TSLA", name: "Tesla Inc.", price: 242.6, vol: 0.0035 },
    { symbol: "SAP", name: "SAP SE", price: 198.4, vol: 0.0014 },
    { symbol: "SIE", name: "Siemens AG", price: 172.8, vol: 0.0013 },
    { symbol: "ALV", name: "Allianz SE", price: 268.5, vol: 0.0011 },
    { symbol: "BMW", name: "BMW AG", price: 88.3, vol: 0.0016 },
    { symbol: "MBG", name: "Mercedes-Benz Group AG", price: 64.9, vol: 0.0016 },
    { symbol: "VOW3", name: "Volkswagen AG Vz.", price: 102.4, vol: 0.0018 },
    { symbol: "DTE", name: "Deutsche Telekom AG", price: 23.1, vol: 0.001 },
    { symbol: "ADS", name: "adidas AG", price: 221.6, vol: 0.0019 },
    { symbol: "BAS", name: "BASF SE", price: 45.7, vol: 0.0015 },
    { symbol: "DBK", name: "Deutsche Bank AG", price: 15.8, vol: 0.0024 },
    { symbol: "RHM", name: "Rheinmetall AG", price: 512.0, vol: 0.0028 },
    { symbol: "NFLX", name: "Netflix Inc.", price: 682.1, vol: 0.002 },
    { symbol: "AMD", name: "Advanced Micro Devices", price: 152.4, vol: 0.003 },
    { symbol: "ASML", name: "ASML Holding N.V.", price: 812.5, vol: 0.002 },
    { symbol: "NESN", name: "Nestlé S.A.", price: 88.6, vol: 0.0009 },
  ];

  // ---------- Formatierung ----------
  const eur = new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR" });
  const pct = new Intl.NumberFormat("de-DE", { style: "percent", minimumFractionDigits: 2, maximumFractionDigits: 2, signDisplay: "always" });
  const signedEur = (v) => (v > 0 ? "+" : "") + eur.format(v);
  const time = (ts) => new Date(ts).toLocaleTimeString("de-DE");
  const cls = (v) => (v > 0 ? "up" : v < 0 ? "down" : "");

  // ---------- Marktdaten (Simulation) ----------
  const market = new Map();
  for (const s of STOCKS) {
    const history = [];
    let p = s.price;
    // etwas Vorlauf erzeugen, damit der Chart direkt gefüllt ist
    for (let i = 0; i < HISTORY_POINTS; i++) {
      p = step(p, s.vol);
      history.push(p);
    }
    market.set(s.symbol, {
      ...s,
      open: history[0],
      high: Math.max(...history),
      low: Math.min(...history),
      price: p,
      prev: p,
      history,
    });
  }

  function step(price, vol) {
    // Zufallsbewegung (Box-Muller für normalverteilte Änderung)
    const u = 1 - Math.random();
    const v = Math.random();
    const z = Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
    return Math.max(0.5, price * (1 + z * vol));
  }

  function tick() {
    for (const s of market.values()) {
      s.prev = s.price;
      s.price = step(s.price, s.vol);
      s.high = Math.max(s.high, s.price);
      s.low = Math.min(s.low, s.price);
      s.history.push(s.price);
      if (s.history.length > HISTORY_POINTS) s.history.shift();
    }
    render();
  }

  // ---------- Konto ----------
  let account = loadAccount();

  function freshAccount() {
    return { cash: START_CASH, holdings: {}, transactions: [] };
  }

  function loadAccount() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (raw) {
        const a = JSON.parse(raw);
        if (typeof a.cash === "number" && a.holdings && Array.isArray(a.transactions)) {
          // nur bekannte Aktien übernehmen
          for (const sym of Object.keys(a.holdings)) if (!market.has(sym)) delete a.holdings[sym];
          a.transactions = a.transactions.filter((t) => market.has(t.symbol));
          return a;
        }
      }
    } catch (_) { /* Speicher nicht verfügbar */ }
    return freshAccount();
  }

  function saveAccount() {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(account)); } catch (_) { /* ignorieren */ }
  }

  function trade(side, symbol, qty) {
    const s = market.get(symbol);
    if (!s) return { ok: false, msg: "Unbekannte Aktie." };
    if (!Number.isInteger(qty) || qty <= 0) return { ok: false, msg: "Bitte eine gültige Anzahl eingeben." };

    const price = s.price;
    const total = price * qty;
    const h = account.holdings[symbol] || { qty: 0, avg: 0 };

    if (side === "buy") {
      if (total > account.cash + 1e-9) return { ok: false, msg: "Nicht genügend Guthaben." };
      account.cash -= total;
      h.avg = (h.avg * h.qty + total) / (h.qty + qty);
      h.qty += qty;
      account.holdings[symbol] = h;
    } else {
      if (qty > h.qty) return { ok: false, msg: `Du besitzt nur ${h.qty} Stück ${symbol}.` };
      account.cash += total;
      h.qty -= qty;
      if (h.qty === 0) delete account.holdings[symbol];
      else account.holdings[symbol] = h;
    }

    account.transactions.unshift({ side, symbol, qty, price, ts: Date.now() });
    account.transactions = account.transactions.slice(0, 100);
    saveAccount();
    const verb = side === "buy" ? "gekauft" : "verkauft";
    return { ok: true, msg: `${qty} × ${symbol} zu ${eur.format(price)} ${verb}.` };
  }

  // ---------- UI ----------
  const $ = (id) => document.getElementById(id);
  const els = {
    cash: $("cash"), pv: $("portfolio-value"), pl: $("total-pl"),
    marketBody: $("market-body"), search: $("search"),
    name: $("detail-name"), symbol: $("detail-symbol"), price: $("detail-price"), change: $("detail-change"),
    open: $("stat-open"), high: $("stat-high"), low: $("stat-low"), owned: $("stat-owned"),
    chart: $("chart"), form: $("trade-form"), qty: $("qty"), total: $("order-total"), submit: $("trade-submit"),
    holdings: $("holdings"), history: $("history"), toast: $("toast"),
  };

  let selected = STOCKS[0].symbol;
  let side = "buy";
  const rows = new Map();

  function buildMarketTable() {
    els.marketBody.innerHTML = "";
    for (const s of market.values()) {
      const tr = document.createElement("tr");
      tr.dataset.symbol = s.symbol;
      tr.innerHTML = `
        <td><span class="sym">${s.symbol}</span><span class="co">${s.name}</span></td>
        <td class="num price"></td>
        <td class="num chg"></td>`;
      tr.addEventListener("click", () => select(s.symbol));
      els.marketBody.appendChild(tr);
      rows.set(s.symbol, tr);
    }
  }

  function select(symbol) {
    selected = symbol;
    render();
  }

  function renderMarket() {
    const q = els.search.value.trim().toLowerCase();
    for (const s of market.values()) {
      const tr = rows.get(s.symbol);
      const visible = !q || s.symbol.toLowerCase().includes(q) || s.name.toLowerCase().includes(q);
      tr.hidden = !visible;
      tr.classList.toggle("selected", s.symbol === selected);
      if (!visible) continue;

      const change = (s.price - s.open) / s.open;
      const priceCell = tr.querySelector(".price");
      const chgCell = tr.querySelector(".chg");
      priceCell.textContent = eur.format(s.price);
      chgCell.textContent = pct.format(change);
      chgCell.className = `num chg ${cls(change)}`;

      if (s.price !== s.prev) {
        const flash = s.price > s.prev ? "flash-up" : "flash-down";
        priceCell.classList.remove("flash-up", "flash-down");
        void priceCell.offsetWidth; // Animation neu starten
        priceCell.classList.add(flash);
      }
    }
  }

  function renderDetail() {
    const s = market.get(selected);
    const change = s.price - s.open;
    els.name.textContent = s.name;
    els.symbol.textContent = s.symbol;
    els.price.textContent = eur.format(s.price);
    els.change.textContent = `${signedEur(change)} (${pct.format(change / s.open)})`;
    els.change.className = `change ${cls(change)}`;
    els.open.textContent = eur.format(s.open);
    els.high.textContent = eur.format(s.high);
    els.low.textContent = eur.format(s.low);
    els.owned.textContent = `${account.holdings[s.symbol]?.qty || 0} Stk.`;
    drawChart(s);
    renderOrderTotal();
  }

  function renderOrderTotal() {
    const s = market.get(selected);
    const qty = parseInt(els.qty.value, 10) || 0;
    els.total.textContent = eur.format(qty * s.price);
    els.submit.textContent = `${qty || ""} ${s.symbol} ${side === "buy" ? "kaufen" : "verkaufen"}`.trim();
    els.submit.classList.toggle("sell", side === "sell");
    const owned = account.holdings[s.symbol]?.qty || 0;
    els.submit.disabled = qty <= 0 || (side === "buy" ? qty * s.price > account.cash : qty > owned);
  }

  function renderAccount() {
    let value = 0;
    let cost = 0;
    for (const [sym, h] of Object.entries(account.holdings)) {
      value += market.get(sym).price * h.qty;
      cost += h.avg * h.qty;
    }
    const total = account.cash + value;
    const pl = total - START_CASH;
    els.cash.textContent = eur.format(account.cash);
    els.pv.textContent = eur.format(value);
    els.pl.textContent = `${signedEur(pl)} (${pct.format(pl / START_CASH)})`;
    els.pl.className = `value ${cls(pl)}`;
    return { value, cost };
  }

  function renderHoldings() {
    const entries = Object.entries(account.holdings);
    if (!entries.length) {
      els.holdings.innerHTML = `<div class="empty">Noch keine Aktien im Depot. Wähle links eine Aktie und kaufe sie.</div>`;
      return;
    }
    els.holdings.innerHTML = entries
      .map(([sym, h]) => {
        const s = market.get(sym);
        const val = s.price * h.qty;
        const pl = (s.price - h.avg) * h.qty;
        return `
          <div class="holding" data-symbol="${sym}">
            <div><span class="sym">${sym}</span> <span class="muted">${h.qty} Stk.</span></div>
            <div class="right">${eur.format(val)}</div>
            <div class="muted">Ø ${eur.format(h.avg)}</div>
            <div class="right ${cls(pl)}">${signedEur(pl)}</div>
          </div>`;
      })
      .join("");
  }

  function renderHistory() {
    if (!account.transactions.length) {
      els.history.innerHTML = `<li class="empty">Noch keine Transaktionen.</li>`;
      return;
    }
    els.history.innerHTML = account.transactions
      .map((t) => `
        <li>
          <span><span class="tag ${t.side}">${t.side === "buy" ? "KAUF" : "VERKAUF"}</span>${t.qty} × ${t.symbol}</span>
          <span class="muted">${eur.format(t.price)} · ${time(t.ts)}</span>
        </li>`)
      .join("");
  }

  function drawChart(s) {
    const canvas = els.chart;
    const dpr = window.devicePixelRatio || 1;
    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    if (canvas.width !== w * dpr || canvas.height !== h * dpr) {
      canvas.width = w * dpr;
      canvas.height = h * dpr;
    }
    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);

    const data = s.history;
    const min = Math.min(...data);
    const max = Math.max(...data);
    const pad = { t: 16, r: 64, b: 16, l: 12 };
    const range = max - min || 1;
    const x = (i) => pad.l + (i / (HISTORY_POINTS - 1)) * (w - pad.l - pad.r);
    const y = (v) => pad.t + (1 - (v - min) / range) * (h - pad.t - pad.b);
    const color = s.price >= data[0] ? "#22c55e" : "#ef4444";

    // Gitternetz + Achsenbeschriftung
    ctx.strokeStyle = "rgba(138,151,171,0.15)";
    ctx.fillStyle = "#8a97ab";
    ctx.font = "11px system-ui, sans-serif";
    ctx.lineWidth = 1;
    for (let i = 0; i <= 4; i++) {
      const v = min + (range * i) / 4;
      const yy = y(v);
      ctx.beginPath();
      ctx.moveTo(pad.l, yy);
      ctx.lineTo(w - pad.r, yy);
      ctx.stroke();
      ctx.fillText(v.toFixed(2), w - pad.r + 6, yy + 4);
    }

    // Fläche
    const grad = ctx.createLinearGradient(0, pad.t, 0, h - pad.b);
    grad.addColorStop(0, color + "55");
    grad.addColorStop(1, color + "00");
    ctx.beginPath();
    data.forEach((v, i) => (i ? ctx.lineTo(x(i), y(v)) : ctx.moveTo(x(i), y(v))));
    ctx.lineTo(x(data.length - 1), h - pad.b);
    ctx.lineTo(x(0), h - pad.b);
    ctx.closePath();
    ctx.fillStyle = grad;
    ctx.fill();

    // Linie
    ctx.beginPath();
    data.forEach((v, i) => (i ? ctx.lineTo(x(i), y(v)) : ctx.moveTo(x(i), y(v))));
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.stroke();

    // aktueller Punkt
    const lx = x(data.length - 1);
    const ly = y(s.price);
    ctx.beginPath();
    ctx.arc(lx, ly, 4, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.fill();
  }

  function render() {
    renderMarket();
    renderAccount();
    renderDetail();
    renderHoldings();
  }

  let toastTimer;
  function toast(msg, type) {
    els.toast.textContent = msg;
    els.toast.className = `toast show ${type}`;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => (els.toast.className = "toast"), 2800);
  }

  // ---------- Events ----------
  els.search.addEventListener("input", renderMarket);

  document.querySelectorAll(".tab").forEach((tab) =>
    tab.addEventListener("click", () => {
      side = tab.dataset.side;
      document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("active", t === tab));
      renderOrderTotal();
    })
  );

  els.qty.addEventListener("input", renderOrderTotal);
  $("qty-minus").addEventListener("click", () => {
    els.qty.value = Math.max(1, (parseInt(els.qty.value, 10) || 1) - 1);
    renderOrderTotal();
  });
  $("qty-plus").addEventListener("click", () => {
    els.qty.value = (parseInt(els.qty.value, 10) || 0) + 1;
    renderOrderTotal();
  });
  $("qty-max").addEventListener("click", () => {
    const s = market.get(selected);
    const max = side === "buy" ? Math.floor(account.cash / s.price) : account.holdings[selected]?.qty || 0;
    els.qty.value = Math.max(max, 0);
    renderOrderTotal();
  });

  els.form.addEventListener("submit", (e) => {
    e.preventDefault();
    const result = trade(side, selected, parseInt(els.qty.value, 10));
    toast(result.msg, result.ok ? "success" : "error");
    if (result.ok) {
      renderHistory();
      render();
    }
  });

  els.holdings.addEventListener("click", (e) => {
    const card = e.target.closest(".holding");
    if (card) select(card.dataset.symbol);
  });

  $("reset-btn").addEventListener("click", () => {
    if (!confirm("Demo-Konto wirklich zurücksetzen? Alle Positionen und Transaktionen werden gelöscht.")) return;
    account = freshAccount();
    saveAccount();
    renderHistory();
    render();
    toast("Konto zurückgesetzt – 10.000 € Startguthaben.", "success");
  });

  window.addEventListener("resize", () => drawChart(market.get(selected)));

  // ---------- Start ----------
  buildMarketTable();
  renderHistory();
  render();
  setInterval(tick, TICK_MS);
})();
