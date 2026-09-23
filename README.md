# ΛKTEX – Trading-Plattform (Demo)

*Markets move. Ideas stay.*

Eine an TradingView angelehnte Trading-Plattform im Browser – installierbar als App (PWA), offline nutzbar, mit flüssigen iOS-artigen Animationen.

> **Hinweis:** Alle Kurse sind **simuliert** – keine echten Marktdaten, kein echtes Geld. Demo-Konto mit 100.000 € Startkapital.

## Funktionen

**Charts (TradingView Lightweight Charts)**
- Zeiteinheiten 1m · 5m · 15m · 1H · 4H · 1T · 1W, Live-Kerzen im Sekundentakt
- Chart-Typen: Kerzen, Hohle Kerzen, Heikin Ashi, Balken, Linie, Fläche, Baseline
- Indikatoren: Volumen, SMA 20/50/200, EMA 9/21, Bollinger-Bänder, VWAP, RSI, MACD, Stochastik, ATR
- Zeichenwerkzeuge: Trendlinie, horizontale Linie, Fibonacci-Retracement, Alarm-Linie, Magnet, Rückgängig
- Live-Legende (OHLC + Indikatorwerte), Kauf-/Verkaufsmarker, Linien für Einstand/Orders/Alarme, Chart-Screenshot

**Handel**
- Market-, Limit- und Stopp-Orders, Stop-Loss & Take-Profit als OCO-Paar
- Bid/Ask mit Spread, Orderbuch (Klick übernimmt Limitpreis), Umsätze (Time & Sales)
- Positionen mit G/V, offene Orders, Order-Historie, Kaufkraft-Prüfung, Risiko/Chance-Verhältnis
- Preisalarme mit Ton und System-Benachrichtigung

**Märkte & Depot**
- 40 Aktien (USA, DAX, Europa), Watchlist, Symbolsuche (Taste `/`), Laufband
- Heatmap nach Sektoren (1T/1W/1M/1J) und sortierbarer Screener
- Depotseite mit Kennzahlen, Depotentwicklung und Aufteilung

**App & Design**
- Installierbar als App auf PC, Mac, Android und iPhone („App installieren“-Button)
- Animierter Startbildschirm mit dem AKTEX-Logo, Federanimationen, Bottom-Sheets, Dynamic-Island-Meldungen
- Hell/Dunkel-Modus, Tastenkürzel (Alt+T/H/F Zeichnen, Strg+Z, Esc)
- **Teilen per Link:** Der Teilen-Button erzeugt einen Link wie `…/?symbol=SAP&tf=1h`, der genau diese Ansicht öffnet

## Starten (lokal)

```bash
python3 -m http.server 8000
# http://localhost:8000 öffnen
```

## Online stellen (Link zum Teilen)

Der Workflow `.github/workflows/pages.yml` veröffentlicht die Seite automatisch auf GitHub Pages:

1. Repository → **Settings → Pages** → Source: **GitHub Actions** wählen.
   (GitHub Pages ist für private Repositories nur mit einem kostenpflichtigen Plan verfügbar – sonst das Repository auf *public* stellen.)
2. Workflow **Deploy AKTEX to GitHub Pages** erneut ausführen (Actions → Run workflow).
3. Die Adresse lautet dann `https://georgleomaser-bit.github.io/website-test-demo-1/` – diesen Link kann man verschicken und die App von dort installieren.

## Aufbau

| Datei | Inhalt |
| --- | --- |
| `index.html` | Oberfläche, Startbildschirm |
| `css/app.css` | Design, Themes, Animationen |
| `js/market.js` | Marktsimulation (Historie + Live-Ticks, Orderbuch) |
| `js/indicators.js` | Technische Indikatoren |
| `js/broker.js` | Demo-Broker: Orders, Positionen, Alarme |
| `js/chart.js` | Chart, Indikatoren, Zeichenwerkzeuge |
| `js/app.js` | UI-Logik, Views, Teilen, Installation |
| `manifest.webmanifest`, `sw.js` | App-Installation & Offline-Modus |
| `icons/` | AKTEX-Logo (SVG/PNG) |

Chart-Bibliothek: [TradingView Lightweight Charts™](https://github.com/tradingview/lightweight-charts) (Apache-2.0, siehe `js/vendor/`).
