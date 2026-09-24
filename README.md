# ΛKYTEX – Trading-Plattform (Demo)

*Markets move. Ideas stay.*

Eine an TradingView angelehnte Trading-Plattform im Browser – installierbar als App (PWA), offline nutzbar, mit flüssigen iOS-artigen Animationen.

> **Hinweis:** Alle Kurse sind **simuliert**, in der Community gibt es keine Bots – keine echten Marktdaten, kein echtes Geld, keine Anlageberatung. Demo-Konto mit 100.000 € Startkapital.

> **Zweites Business: NOVA** – ein KI-Assistent zum Sprechen und Schreiben (wie Claude) im professionellen Design, komplett getrennt von AKYTEX: [`nova/NOVA.md`](nova/NOVA.md) · Vorschau: `…/website-test-demo-1/nova/`

> **Drittes Business: Handy-Hilfe** – kleiner Service vor Ort mit Sparziel-Tracker fürs iPhone 18 Pro und druckbarem Flyer: [`iphone/`](iphone/index.html) · Vorschau: `…/website-test-demo-1/iphone/`

> **Viertes Business: Web-Studio** – Webseiten für lokale Läden bauen (Generator mit Live-Vorschau und Download), Angebote und Rechnungen, Kunden-Board mit iPhone-Sparziel und **Autopilot** (Liste von Läden → fertige Entwürfe, Briefe, ZIP für Netlify, Nachfass-Termine): [`webstudio/`](webstudio/index.html)

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

**Geschäftsmodell & Community**
- Startseite (Landingpage) mit Live-Kursen, Features, Preisen und FAQ – ideal für geteilte Links
- Tarife Free / Pro / Elite mit Ordergebühren (1 € im Free-Tarif, 0 € im Abo) und Funktionslimits
- **AKYTEX AI:** technische Bewertung jeder Aktie (Tachometer, 16 Signale, Marken, Trade-Setup mit 1 %-Risiko)
- **Ideen:** Community-Feed mit Trading-Ideen (eigene Ideen inkl. Chart-Screenshot teilen), Likes, Folgen
- **Rangliste & Copy-Trading:** Top-Trader-Ranking (inkl. eigenem Depot), Portfolios mit einem Klick kopieren
- **Ideen-Börse (USP):** versiegelte Ideen (SHA-256), live gemessene Performance, verifizierte Trefferquoten, 1-Klick-Handel mit Stop & Ziel, Royalties für Autoren
- **Preismodell:** Free · Plus · Pro · Elite, AKYTEX AI (99 €), AI Premium (249 €) und Ultra mit Jarvis-Sprachmodus (299 €), monatlich/jährlich, Add-ons, Preis- und Leistungsverzeichnis, volle Kostenaufstellung vor jeder Order
- **AKYTEX AI:** Berater-Chat (lokal oder mit Claude, wo verfügbar), Meldungen, Depot-Doktor, Chancen-Scan und **Autopilot** (Vorschläge oder selbstständig in deinen Limits, mit Protokoll und Not-Aus)
- **Business-Dashboard:** Umsatz- und Bewertungsmodell mit Reglern, Umsatz nach Quelle, 5-Jahres-Pfad, Funnel
- Geschäftsplan: siehe [`BUSINESS.md`](BUSINESS.md)

**AKYTEX AI – 50 Funktionen** (Tab „✦ 50 Features“ in der AI-Ansicht)
- Cockpit: Berater-Chat mit Kontext-Gedächtnis, Slash-Befehlen (`/prognose`, `/backtest`, `/risiko`, `/plan` …), Vorlesen, Limit-Orders und Alarme per Chat
- **Zeitplan:** zeitgesteuerte Orders („Kaufe 10 SAP um 15:30“), Sparpläne (täglich/werktags/wöchentlich/monatlich), Wenn-Dann-Regeln (Kurs, RSI, Rating, Tagesänderung) mit Zeitfenster, Live-Countdowns und Verlauf
- **Autopilot:** 5 Strategie-Presets, Handelszeiten, Tagesverlust-Notbremse, Konfidenz-Schwelle, ATR-Smart-Stops, Schattenmodus, Trade-Journal, Performance
- **Labor:** Prognose-Korridor, Multi-Timeframe, Score-Erklärung, Muster & Zonen, Backtest, Monte Carlo, VaR, Korrelation, Sentiment-Index, Sektor-Rotation, Anomalie-Radar, ähnliche Setups, Positionsgröße, Rebalancing, Steuer-Tipps

**Shop & Clips**
- **Store mit Spotlight:** Themen-Pakete, die live nach Momentum rotieren (mit einem Klick investieren), Autopilot-Strategien, Academy-Kurse, AI-Reports, Merch, Geschenkkarten, Warenkorb und Bestellungen
- **AKYTEX Clips:** vertikaler Video-Feed (Doppeltipp = Like, Kommentare, Teilen, „Handeln“, Melden), eigene Videos hochladen, Chart-Clips aufnehmen

**Konto & Bezahlsystem**
- Onboarding (Profil, Erfahrung, Ziel, Risiko) mit Tarif-Empfehlung
- **AKYTEX Pay:** ein Bezahl-Sheet mit aufklappbaren Zeilen und „Zum Bezahlen halten“, gespeicherte Zahlungsmethode für Ein-Griff-Zahlungen
- Checkout im Testmodus: Tarif, Laufzeit, Add-ons, Gutscheine, MwSt., Karte mit 3-D Secure, PayPal, Apple/Google Pay, SEPA, Klarna – nur Testdaten
- Konto-Bereich: Profil, Abo & Zahlung, Rechnungen, Benachrichtigungen, Sicherheit, Datenexport (DSGVO)
- „Verträge hier kündigen“, Rechtliches (Impressum, Datenschutz, AGB, Widerruf, Risikohinweise als Vorlagen)
- Anschluss an echte Zahlungen über Stripe: siehe [`PAYMENTS.md`](PAYMENTS.md)

**App & Design**
- Installierbar als App auf PC, Mac, Android und iPhone („App installieren“-Button)
- Animierter Startbildschirm mit dem AKYTEX-Logo, Federanimationen, Bottom-Sheets, Dynamic-Island-Meldungen
- Hell/Dunkel-Modus, Befehlspalette (Strg/⌘ + K), Mitteilungszentrale, Tastenkürzel (Alt+T/H/F Zeichnen, Strg+Z, Esc)
- 3D-Neigung und Spotlight auf Karten, Rollziffern beim Kurs, Live-Aktivität auf der Startseite
- **Teilen per Link:** Der Teilen-Button erzeugt einen Link wie `…/?symbol=SAP&tf=1h`, der genau diese Ansicht öffnet

## Starten (lokal)

```bash
python3 -m http.server 8000
# http://localhost:8000 öffnen
```

## Launch
Siehe [`GO-LIVE.md`](GO-LIVE.md) für den Weg in den Echtbetrieb (alle Einträge in `js/config.js`), [`LAUNCH.md`](LAUNCH.md) für die Checkliste, [`BROKER-ANFRAGE.md`](BROKER-ANFRAGE.md) für die Suche nach einem Broker-Partner und [`AKTIE-FAHRPLAN.md`](AKTIE-FAHRPLAN.md) für Firma, Notar und Beteiligungen.

## Online stellen (Link zum Teilen)

Die Seite liegt auf GitHub Pages und wird direkt aus dem Standard-Branch veröffentlicht (Settings → Pages → *Deploy from a branch*). Jede Änderung, die dort landet, ist nach ein bis zwei Minuten online:

`https://georgleomaser-bit.github.io/website-test-demo-1/` – diesen Link kann man verschicken und die App von dort installieren.

## Aufbau

| Datei | Inhalt |
| --- | --- |
| `index.html` | Oberfläche, Startbildschirm |
| `css/app.css` | Design, Themes, Animationen |
| `js/market.js` | Marktsimulation (Historie + Live-Ticks, Orderbuch) |
| `js/indicators.js` | Technische Indikatoren |
| `js/broker.js` | Demo-Broker: Orders, Positionen, Gebühren, Alarme |
| `js/analysis.js` | AKYTEX AI – technische Analyse |
| `js/community.js` | Community: Trader, Ideen, Rangliste |
| `js/plans.js` | Tarife, Add-ons & Limits |
| `js/ai.js` | AKYTEX AI: Scan, Depot-Doktor, Berater, Meldungen, Autopilot |
| `js/payments.js` | Checkout, Testkarten, Abo, Rechnungen, Stripe-Anbindung |
| `js/ailab.js` | AI-Labor: Prognosen, Muster, Backtests, Risiko, Portfolio-Werkzeuge |
| `js/scheduler.js` | Zeitplan: Timer, Sparpläne, Wenn-Dann-Regeln |
| `js/shop.js` | Store: Spotlight-Pakete, Produkte, Warenkorb, Bestellungen |
| `js/clips.js` | Clips: Feed-Renderer, Aufnahme, Speicherung (IndexedDB) |
| `js/chart.js` | Chart, Indikatoren, Zeichenwerkzeuge |
| `js/app.js` | UI-Logik, Views, Teilen, Installation |
| `manifest.webmanifest`, `sw.js` | App-Installation & Offline-Modus |
| `icons/` | AKYTEX-Logo (SVG/PNG) |

Chart-Bibliothek: [TradingView Lightweight Charts™](https://github.com/tradingview/lightweight-charts) (Apache-2.0, siehe `js/vendor/`).
