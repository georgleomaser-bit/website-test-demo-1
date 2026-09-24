// Chart-Ansicht auf Basis von TradingView Lightweight Charts (lokal eingebunden, Apache-2.0).
import { bucketOf } from "./market.js";
import * as ind from "./indicators.js";

const LWC = window.LightweightCharts;

export const CHART_TYPES = [
  { id: "candles", label: "Kerzen" },
  { id: "hollow", label: "Hohle Kerzen" },
  { id: "heikin", label: "Heikin Ashi" },
  { id: "bars", label: "Balken" },
  { id: "line", label: "Linie" },
  { id: "area", label: "Fläche" },
  { id: "baseline", label: "Baseline" },
];

export const INDICATORS = [
  { id: "vol", name: "Volumen", group: "Overlay" },
  { id: "sma20", name: "SMA 20", group: "Overlay", color: "#f5b942" },
  { id: "sma50", name: "SMA 50", group: "Overlay", color: "#4f8cff" },
  { id: "sma200", name: "SMA 200", group: "Overlay", color: "#e056fd" },
  { id: "ema9", name: "EMA 9", group: "Overlay", color: "#00d1b2" },
  { id: "ema21", name: "EMA 21", group: "Overlay", color: "#ff7a45" },
  { id: "bb", name: "Bollinger-Bänder (20, 2)", group: "Overlay", color: "#7c8cff" },
  { id: "vwap", name: "VWAP (Intraday)", group: "Overlay", color: "#ffd166" },
  { id: "rsi", name: "RSI (14)", group: "Oszillator", color: "#b388ff" },
  { id: "macd", name: "MACD (12, 26, 9)", group: "Oszillator", color: "#4f8cff" },
  { id: "stoch", name: "Stochastik (14, 3)", group: "Oszillator", color: "#4f8cff" },
  { id: "atr", name: "ATR (14)", group: "Oszillator", color: "#ff7a45" },
];

const FIB_LEVELS = [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1];
const FIB_COLORS = ["#8a97ab", "#ef4444", "#f59e0b", "#22c55e", "#06b6d4", "#4f8cff", "#8a97ab"];

const THEMES = {
  dark: { bg: "#060812", text: "#aab3d4", grid: "rgba(140,160,255,0.06)", border: "rgba(140,160,255,0.14)", up: "#22c55e", down: "#ef4444", cross: "#6b75a0" },
  light: { bg: "#ffffff", text: "#434b58", grid: "rgba(40,50,70,0.07)", border: "#e3e7ee", up: "#089981", down: "#f23645", cross: "#9aa3b2" },
};

const fmtVol = (v) => (v >= 1e9 ? (v / 1e9).toFixed(2) + " Mrd" : v >= 1e6 ? (v / 1e6).toFixed(2) + " Mio" : v >= 1e3 ? (v / 1e3).toFixed(1) + " Tsd" : String(Math.round(v)));

export class ChartView {
  constructor({ container, legend, market, broker, onToolDone, onAlertAt, onHint }) {
    this.el = container;
    this.legendEl = legend;
    this.market = market;
    this.broker = broker;
    this.onToolDone = onToolDone;
    this.onAlertAt = onAlertAt;
    this.onHint = onHint;

    this.symbol = "AAPL";
    this.tf = "15m";
    this.type = "candles";
    this.indicators = new Set(["vol", "sma20", "sma50"]);
    this.theme = "dark";
    this.tool = "cursor";
    this.magnet = true;
    this.drawings = loadDrawings();
    this.pending = null;

    this.chart = null;
    this.series = {};
    this.lines = [];
    this.drawingSeries = [];
  }

  configure(opts) {
    const keepRange = this.chart && opts.symbol === undefined && opts.tf === undefined;
    Object.assign(this, opts);
    this.build(keepRange);
  }

  // ---------- Aufbau ----------
  build(keepRange = false) {
    const range = keepRange && this.chart ? this.chart.timeScale().getVisibleLogicalRange() : null;
    if (this.chart) this.chart.remove();
    this.series = {};
    this.lines = [];
    this.drawingSeries = [];
    this.pending = null;
    const th = THEMES[this.theme];

    const chart = LWC.createChart(this.el, {
      autoSize: true,
      layout: { background: { type: "solid", color: th.bg }, textColor: th.text, fontFamily: "Inter, system-ui, sans-serif", fontSize: 11, panes: { separatorColor: th.border, separatorHoverColor: "rgba(79,140,255,0.3)" } },
      grid: { vertLines: { color: th.grid }, horzLines: { color: th.grid } },
      crosshair: { mode: LWC.CrosshairMode.Normal, vertLine: { color: th.cross, labelBackgroundColor: "#2a3446" }, horzLine: { color: th.cross, labelBackgroundColor: "#2a3446" } },
      rightPriceScale: { borderColor: th.border },
      timeScale: { borderColor: th.border, timeVisible: this.tf !== "1D" && this.tf !== "1W", secondsVisible: false, rightOffset: 10, barSpacing: 8 },
      localization: { locale: "de-DE", priceFormatter: (p) => p.toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) },
    });
    this.chart = chart;

    this.raw = this.market.bars(this.symbol, this.tf);
    this.addMainSeries();
    this.addIndicatorSeries();
    this.setAllData();
    this.refreshOverlays();

    chart.subscribeCrosshairMove((p) => this.onCrosshair(p));
    chart.subscribeClick((p) => this.onClick(p));

    if (range) chart.timeScale().setVisibleLogicalRange(range);
    else {
      const n = this.raw.length;
      chart.timeScale().setVisibleLogicalRange({ from: Math.max(0, n - 150), to: n + 10 });
    }
    this.renderLegend(null);
  }

  addMainSeries() {
    const th = THEMES[this.theme];
    const c = this.chart;
    const common = { priceLineVisible: true, lastValueVisible: true };
    switch (this.type) {
      case "bars":
        this.series.main = c.addSeries(LWC.BarSeries, { ...common, upColor: th.up, downColor: th.down, thinBars: false });
        break;
      case "line":
        this.series.main = c.addSeries(LWC.LineSeries, { ...common, color: "#4f8cff", lineWidth: 2 });
        break;
      case "area":
        this.series.main = c.addSeries(LWC.AreaSeries, { ...common, lineColor: "#4f8cff", topColor: "rgba(79,140,255,0.35)", bottomColor: "rgba(79,140,255,0.02)", lineWidth: 2 });
        break;
      case "baseline": {
        const base = this.raw.length ? this.raw[Math.max(0, this.raw.length - 150)].close : 0;
        this.series.main = c.addSeries(LWC.BaselineSeries, { ...common, baseValue: { type: "price", price: base }, topLineColor: th.up, bottomLineColor: th.down, topFillColor1: "rgba(34,197,94,0.25)", topFillColor2: "rgba(34,197,94,0.02)", bottomFillColor1: "rgba(239,68,68,0.02)", bottomFillColor2: "rgba(239,68,68,0.25)" });
        break;
      }
      case "hollow":
        this.series.main = c.addSeries(LWC.CandlestickSeries, { ...common, upColor: "rgba(0,0,0,0)", downColor: th.down, borderUpColor: th.up, borderDownColor: th.down, wickUpColor: th.up, wickDownColor: th.down });
        break;
      default:
        this.series.main = c.addSeries(LWC.CandlestickSeries, { ...common, upColor: th.up, downColor: th.down, borderVisible: false, wickUpColor: th.up, wickDownColor: th.down });
    }
    this.series.main.priceScale().applyOptions({ scaleMargins: { top: 0.08, bottom: this.indicators.has("vol") ? 0.22 : 0.08 } });
    this.markers = LWC.createSeriesMarkers(this.series.main, []);
  }

  addIndicatorSeries() {
    const c = this.chart;
    const th = THEMES[this.theme];
    const line = (color, pane = 0, extra = {}) => c.addSeries(LWC.LineSeries, { color, lineWidth: 1.5, priceLineVisible: false, lastValueVisible: false, crosshairMarkerVisible: false, ...extra }, pane);
    const intraday = this.tf !== "1D" && this.tf !== "1W";
    let pane = 1;

    for (const def of INDICATORS) {
      if (!this.indicators.has(def.id)) continue;
      switch (def.id) {
        case "vol":
          this.series.vol = c.addSeries(LWC.HistogramSeries, { priceFormat: { type: "volume" }, priceScaleId: "vol", priceLineVisible: false, lastValueVisible: false });
          this.series.vol.priceScale().applyOptions({ scaleMargins: { top: 0.82, bottom: 0 } });
          break;
        case "sma20":
        case "sma50":
        case "sma200":
        case "ema9":
        case "ema21":
          this.series[def.id] = line(def.color);
          break;
        case "bb":
          this.series.bbU = line(def.color, 0, { lineWidth: 1 });
          this.series.bbM = line("#f59e0b", 0, { lineWidth: 1, lineStyle: LWC.LineStyle.Dashed });
          this.series.bbL = line(def.color, 0, { lineWidth: 1 });
          break;
        case "vwap":
          if (intraday) this.series.vwap = line(def.color, 0, { lineWidth: 2 });
          break;
        case "rsi":
          this.series.rsi = line(def.color, pane, { lastValueVisible: true });
          this.series.rsi.createPriceLine({ price: 70, color: "rgba(239,68,68,0.5)", lineStyle: LWC.LineStyle.Dashed, lineWidth: 1, axisLabelVisible: false });
          this.series.rsi.createPriceLine({ price: 30, color: "rgba(34,197,94,0.5)", lineStyle: LWC.LineStyle.Dashed, lineWidth: 1, axisLabelVisible: false });
          this.series.rsi.createPriceLine({ price: 50, color: "rgba(138,151,171,0.3)", lineStyle: LWC.LineStyle.Dotted, lineWidth: 1, axisLabelVisible: false });
          pane++;
          break;
        case "macd":
          this.series.macdH = c.addSeries(LWC.HistogramSeries, { priceLineVisible: false, lastValueVisible: false }, pane);
          this.series.macdL = line("#4f8cff", pane, { lastValueVisible: true });
          this.series.macdS = line("#ff7a45", pane);
          pane++;
          break;
        case "stoch":
          this.series.stK = line("#4f8cff", pane, { lastValueVisible: true });
          this.series.stD = line("#ff7a45", pane);
          this.series.stK.createPriceLine({ price: 80, color: "rgba(239,68,68,0.5)", lineStyle: LWC.LineStyle.Dashed, lineWidth: 1, axisLabelVisible: false });
          this.series.stK.createPriceLine({ price: 20, color: "rgba(34,197,94,0.5)", lineStyle: LWC.LineStyle.Dashed, lineWidth: 1, axisLabelVisible: false });
          pane++;
          break;
        case "atr":
          this.series.atr = line(def.color, pane, { lastValueVisible: true });
          pane++;
          break;
      }
    }
    const panes = c.panes();
    for (let i = 1; i < panes.length; i++) panes[i].setHeight(110);
    void th;
  }

  // Berechnet alle abgeleiteten Reihen aus den Rohkerzen
  compute() {
    const bars = this.type === "heikin" ? ind.heikinAshi(this.raw) : this.raw;
    const closes = this.raw.map((b) => b.close);
    const out = { bars, closes };
    const I = this.indicators;
    if (I.has("sma20")) out.sma20 = ind.sma(closes, 20);
    if (I.has("sma50")) out.sma50 = ind.sma(closes, 50);
    if (I.has("sma200")) out.sma200 = ind.sma(closes, 200);
    if (I.has("ema9")) out.ema9 = ind.ema(closes, 9);
    if (I.has("ema21")) out.ema21 = ind.ema(closes, 21);
    if (I.has("bb")) out.bb = ind.bollinger(closes, 20, 2);
    if (I.has("vwap") && this.series.vwap) out.vwap = ind.vwap(this.raw);
    if (I.has("rsi")) out.rsi = ind.rsi(closes, 14);
    if (I.has("macd")) out.macd = ind.macd(closes);
    if (I.has("stoch")) out.stoch = ind.stochastic(this.raw);
    if (I.has("atr")) out.atr = ind.atr(this.raw);
    this.calc = out;
    return out;
  }

  // Liefert für jede Serie den Datenpunkt i
  pointFns() {
    const th = THEMES[this.theme];
    const c = this.calc;
    const lp = (arr) => (i) => (arr[i] == null ? { time: this.raw[i].time } : { time: this.raw[i].time, value: arr[i] });
    const fns = {};
    const isOHLC = ["candles", "hollow", "heikin", "bars"].includes(this.type);
    fns.main = isOHLC ? (i) => ({ time: c.bars[i].time, open: c.bars[i].open, high: c.bars[i].high, low: c.bars[i].low, close: c.bars[i].close }) : (i) => ({ time: this.raw[i].time, value: this.raw[i].close });
    if (this.series.vol) fns.vol = (i) => ({ time: this.raw[i].time, value: this.raw[i].volume, color: this.raw[i].close >= this.raw[i].open ? hexA(th.up, 0.35) : hexA(th.down, 0.35) });
    for (const k of ["sma20", "sma50", "sma200", "ema9", "ema21", "rsi", "atr", "vwap"]) if (this.series[k] && c[k]) fns[k] = lp(c[k]);
    if (c.bb) {
      fns.bbU = lp(c.bb.upper);
      fns.bbM = lp(c.bb.mid);
      fns.bbL = lp(c.bb.lower);
    }
    if (c.macd) {
      fns.macdL = lp(c.macd.line);
      fns.macdS = lp(c.macd.signal);
      fns.macdH = (i) => {
        const v = c.macd.hist[i];
        if (v == null) return { time: this.raw[i].time };
        const prev = c.macd.hist[i - 1] ?? 0;
        const color = v >= 0 ? (v >= prev ? "#22c55e" : "rgba(34,197,94,0.5)") : v <= prev ? "#ef4444" : "rgba(239,68,68,0.5)";
        return { time: this.raw[i].time, value: v, color };
      };
    }
    if (c.stoch) {
      fns.stK = lp(c.stoch.k);
      fns.stD = lp(c.stoch.d);
    }
    return fns;
  }

  setAllData() {
    this.compute();
    const fns = this.pointFns();
    for (const [k, fn] of Object.entries(fns)) this.series[k].setData(this.raw.map((_, i) => fn(i)));
    this.timeIndex = new Map(this.raw.map((b, i) => [b.time, i]));
  }

  // ---------- Live-Update ----------
  update() {
    if (!this.chart) return;
    const bar = this.market.lastBar(this.symbol, this.tf);
    const last = this.raw[this.raw.length - 1];
    if (last && bar.time === last.time) this.raw[this.raw.length - 1] = bar;
    else if (!last || bar.time > last.time) {
      this.raw.push(bar);
      this.timeIndex.set(bar.time, this.raw.length - 1);
    } else return;
    this.compute();
    const fns = this.pointFns();
    const i = this.raw.length - 1;
    for (const [k, fn] of Object.entries(fns)) this.series[k].update(fn(i));
    if (!this.hovering) this.renderLegend(null);
  }

  // ---------- Legende ----------
  onCrosshair(p) {
    this.hovering = !!(p && p.time);
    this.renderLegend(p && p.time ? this.timeIndex.get(p.time) : null);
    if (this.pending && p && p.point) this.previewPending(p);
  }

  renderLegend(idx) {
    const i = idx == null ? this.raw.length - 1 : idx;
    const b = this.raw[i];
    if (!b) return;
    const prev = this.raw[i - 1];
    const ch = prev ? b.close - prev.close : 0;
    const chp = prev ? ch / prev.close : 0;
    const cls = ch >= 0 ? "up" : "down";
    const f = (v) => (v == null ? "–" : v.toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 }));
    const st = this.market.get(this.symbol);
    const c = this.calc || {};
    const tfLabel = { "1m": "1", "5m": "5", "15m": "15", "1h": "1H", "4h": "4H", "1D": "1T", "1W": "1W" }[this.tf];
    const rows = [];
    const add = (label, color, val) => rows.push(`<span class="lg-ind"><span style="color:${color}">${label}</span> <b>${val}</b></span>`);
    for (const def of INDICATORS) {
      if (!this.indicators.has(def.id)) continue;
      if (["sma20", "sma50", "sma200", "ema9", "ema21", "vwap"].includes(def.id) && c[def.id]) add(def.name.split(" (")[0], def.color, f(c[def.id][i]));
      if (def.id === "bb" && c.bb) add("BB", def.color, `${f(c.bb.upper[i])} · ${f(c.bb.mid[i])} · ${f(c.bb.lower[i])}`);
      if (def.id === "rsi" && c.rsi) add("RSI", def.color, f(c.rsi[i]));
      if (def.id === "macd" && c.macd) add("MACD", def.color, `${f(c.macd.line[i])} · ${f(c.macd.signal[i])} · ${f(c.macd.hist[i])}`);
      if (def.id === "stoch" && c.stoch) add("Stoch", def.color, `${f(c.stoch.k[i])} · ${f(c.stoch.d[i])}`);
      if (def.id === "atr" && c.atr) add("ATR", def.color, f(c.atr[i]));
    }
    this.legendEl.innerHTML = `
      <div class="lg-title"><b>${st.s}</b> <span>· ${tfLabel} · ${st.ex}</span> <span class="lg-name">${st.n}</span></div>
      <div class="lg-ohlc">
        <span>E <b class="${cls}">${f(b.open)}</b></span>
        <span>H <b class="${cls}">${f(b.high)}</b></span>
        <span>T <b class="${cls}">${f(b.low)}</b></span>
        <span>S <b class="${cls}">${f(b.close)}</b></span>
        <b class="${cls}">${ch >= 0 ? "+" : ""}${f(ch)} (${ch >= 0 ? "+" : ""}${(chp * 100).toFixed(2)} %)</b>
        ${this.indicators.has("vol") ? `<span>Vol <b>${fmtVol(b.volume)}</b></span>` : ""}
      </div>
      <div class="lg-inds">${rows.join("")}</div>`;
  }

  // ---------- Preislinien, Marker, Zeichnungen ----------
  refreshOverlays() {
    if (!this.chart) return;
    const main = this.series.main;
    for (const l of this.lines) main.removePriceLine(l);
    this.lines = [];
    for (const s of this.drawingSeries) this.chart.removeSeries(s);
    this.drawingSeries = [];
    const S = LWC.LineStyle;
    const add = (o) => this.lines.push(main.createPriceLine({ lineWidth: 1, axisLabelVisible: true, ...o }));

    const pos = this.broker.position(this.symbol);
    if (pos) add({ price: pos.avg, color: "#4f8cff", lineStyle: S.Solid, lineWidth: 2, title: `Einstand ${pos.qty}` });
    for (const o of this.broker.state.orders) {
      if (o.symbol !== this.symbol) continue;
      const px = o.limitPrice ?? o.stopPrice;
      const label = o.tag || (o.type === "limit" ? "LMT" : "STP");
      const color = o.tag === "SL" ? "#ef4444" : o.tag === "TP" ? "#22c55e" : "#f59e0b";
      add({ price: px, color, lineStyle: S.Dashed, title: `${label} ${o.side === "buy" ? "Kauf" : "Verk."} ${o.qty}` });
    }
    for (const a of this.broker.state.alerts) {
      if (a.symbol !== this.symbol || !a.active) continue;
      add({ price: a.price, color: "#eab308", lineStyle: S.LargeDashed, title: "⏰ Alarm" });
    }

    const first = this.raw[0]?.time ?? 0;
    for (const d of this.drawings[this.symbol] || []) {
      if (d.type === "hline") add({ price: d.price, color: d.color || "#9aa3b2", lineStyle: S.Solid, title: "" });
      if (d.type === "fib") {
        FIB_LEVELS.forEach((lv, k) => {
          add({ price: d.p2 + (d.p1 - d.p2) * lv, color: FIB_COLORS[k], lineStyle: S.Solid, title: `Fib ${lv}`, axisLabelVisible: false });
        });
      }
      if (d.type === "trend") {
        const t1 = bucketOf(d.t1, this.tf);
        const t2 = bucketOf(d.t2, this.tf);
        if (t1 === t2 || Math.min(t1, t2) < first) continue;
        const s = this.chart.addSeries(LWC.LineSeries, { color: d.color || "#4f8cff", lineWidth: 2, priceLineVisible: false, lastValueVisible: false, crosshairMarkerVisible: false, autoscaleInfoProvider: () => null });
        const pts = [{ time: t1, value: d.p1 }, { time: t2, value: d.p2 }].sort((a, b) => a.time - b.time);
        s.setData(pts);
        this.drawingSeries.push(s);
      }
    }

    // Ausführungen als Pfeile
    const markers = [];
    for (const f of this.broker.state.fills) {
      if (f.symbol !== this.symbol) continue;
      const t = bucketOf(f.time, this.tf);
      if (t < first) continue;
      markers.push({ time: t, position: f.side === "buy" ? "belowBar" : "aboveBar", color: f.side === "buy" ? "#22c55e" : "#ef4444", shape: f.side === "buy" ? "arrowUp" : "arrowDown", text: `${f.side === "buy" ? "K" : "V"} ${f.qty}` });
    }
    markers.sort((a, b) => a.time - b.time);
    this.markers.setMarkers(markers);
  }

  // ---------- Werkzeuge ----------
  setTool(tool) {
    this.tool = tool;
    this.pending = null;
    this.clearPreview();
    const hints = {
      cursor: "",
      hline: "Klicke in den Chart, um eine horizontale Linie zu setzen.",
      trend: "Klicke Start- und Endpunkt der Trendlinie.",
      fib: "Klicke Hoch und Tief für das Fibonacci-Retracement.",
      alert: "Klicke auf den Preis, bei dem du alarmiert werden möchtest.",
    };
    this.onHint?.(hints[tool] || "");
  }

  pointFromParam(p) {
    if (!p.point) return null;
    let price = this.series.main.coordinateToPrice(p.point.y);
    if (price == null) return null;
    let time = p.time ?? null;
    if (this.magnet && time != null) {
      const b = this.raw[this.timeIndex.get(time)];
      if (b) {
        const cands = [b.open, b.high, b.low, b.close];
        const near = cands.reduce((a, v) => (Math.abs(v - price) < Math.abs(a - price) ? v : a), cands[0]);
        const px = this.series.main.priceToCoordinate(near);
        if (px != null && Math.abs(px - p.point.y) < 18) price = near;
      }
    }
    return { time, price };
  }

  onClick(p) {
    if (this.tool === "cursor") return;
    const pt = this.pointFromParam(p);
    if (!pt) return;
    const list = (this.drawings[this.symbol] ||= []);
    if (this.tool === "hline") {
      list.push({ type: "hline", price: pt.price });
      this.finishTool();
    } else if (this.tool === "alert") {
      this.onAlertAt?.(this.symbol, pt.price);
      this.finishTool(false);
    } else if (this.tool === "trend" || this.tool === "fib") {
      if (pt.time == null) return;
      if (!this.pending) {
        this.pending = pt;
        this.onHint?.(this.tool === "trend" ? "Jetzt den Endpunkt klicken." : "Jetzt den zweiten Punkt klicken.");
        return;
      }
      const a = this.pending;
      if (this.tool === "trend") list.push({ type: "trend", t1: a.time, p1: a.price, t2: pt.time, p2: pt.price });
      else list.push({ type: "fib", t1: a.time, p1: a.price, t2: pt.time, p2: pt.price });
      this.pending = null;
      this.finishTool();
    }
  }

  finishTool(save = true) {
    this.clearPreview();
    if (save) saveDrawings(this.drawings);
    this.refreshOverlays();
    this.setTool("cursor");
    this.onToolDone?.();
  }

  previewPending(p) {
    const pt = this.pointFromParam(p);
    if (!pt || pt.time == null || pt.time === this.pending.time) return;
    if (!this.preview) {
      this.preview = this.chart.addSeries(LWC.LineSeries, { color: "rgba(79,140,255,0.7)", lineWidth: 2, lineStyle: LWC.LineStyle.Dashed, priceLineVisible: false, lastValueVisible: false, crosshairMarkerVisible: false, autoscaleInfoProvider: () => null });
    }
    const pts = [{ time: this.pending.time, value: this.pending.price }, { time: pt.time, value: pt.price }].sort((a, b) => a.time - b.time);
    this.preview.setData(pts);
  }

  clearPreview() {
    if (this.preview && this.chart) this.chart.removeSeries(this.preview);
    this.preview = null;
  }

  undoDrawing() {
    const list = this.drawings[this.symbol];
    if (!list || !list.length) return false;
    list.pop();
    saveDrawings(this.drawings);
    this.refreshOverlays();
    return true;
  }

  clearDrawings() {
    delete this.drawings[this.symbol];
    saveDrawings(this.drawings);
    this.refreshOverlays();
  }

  resetView() {
    const n = this.raw.length;
    this.chart.timeScale().setVisibleLogicalRange({ from: Math.max(0, n - 150), to: n + 10 });
    this.chart.priceScale("right").applyOptions({ autoScale: true });
  }

  screenshot() {
    return this.chart.takeScreenshot();
  }
}

function hexA(hex, a) {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
}

function loadDrawings() {
  try {
    return JSON.parse(localStorage.getItem("akytex-v2-drawings")) || {};
  } catch (_) {
    return {};
  }
}
function saveDrawings(d) {
  try {
    localStorage.setItem("akytex-v2-drawings", JSON.stringify(d));
  } catch (_) {
    /* ignorieren */
  }
}
