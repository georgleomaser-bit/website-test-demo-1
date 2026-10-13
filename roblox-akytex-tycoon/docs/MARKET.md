# AKYTEX TYCOON – Markt-Engine (MARKET.md)

Stand: 13.10.2026 · Gilt für: Server-Markt, Orders, Depot, Kerzen/Chart-Stream, Events, Tower-AG, Admin-Markt.
Ergänzt `BESITZER-WUENSCHE.md` (verbindlich). Kalibrier-Werkzeug: `tools/market_calibrate.py` (Referenz-Implementierung des
Preis-Modells + Strategie-Backtest; jede Zahl in §4 und §6 stammt aus diesem Skript).

> **Für den Besitzer in einfachen Worten:** Alle Server zeigen **dieselben Kurse**, weil jeder Server den Kurs aus einer
> geheimen Zahl (Seed) und der Uhrzeit **ausrechnet**. Kurse bewegen sich vor allem durch **Nachrichten**, die man im Spiel
> **liest, bevor** der Kurs reagiert. Wer liest und versteht, gewinnt; wer wild klickt, verliert Gebühren. Es gibt **keine Wetten,
> keinen Hebel, keine Zufallskisten**, und Robux kaufen **nie** Spielgeld fürs Depot. So bleibt es Börse und kein Glücksspiel.


> **Verbindliche Änderungen durch `docs/DESIGN.md` §C19 (Stand 13.10.2026) – bei Widerspruch gilt DESIGN.md:**
> 1. Firmen-IDs 1/2/23 umbenannt: **CGVO „Cognivo KI“** (statt NOVA), **KRWK „Kernwerk Systems“** (statt AKYTEX Holding),
>    **PFFR „Pfotenfreund“** (statt Pfotenglück). Keine handelbare AKYTEX- oder NOVA-Firma.
> 2. „NOVA-Ampel“/NOVA-Tipps heißen **Tiko-Ampel**/Tiko (geskripteter Roboter; „Aky“ und „NOVA“ sind echte KI-Produkte).
> 3. §15: Geld fließt **nur Depot (AKY) → Turm (CR)** über den Gewinn-Transfer (Basis-Hochwassermarke, Schwelle 2 %, max. 6 % der
>    Basis, 1× je Börsentag, Bau-Kurs nur nach Lizenz). Research-Vorlauf über Lizenz + Know-how, nie über Tower-Fortschritt.
> 4. §14.4: statt „Gehalt aus dem Tower“ ins Depot gibt es den **Rettungsschirm** (auf 50 % der Basis, 1×/UTC-Tag, nie abhebbar).
> 5. §1.4: Watchlists, Alarm-Plätze, Multi-Chart nur über Know-how; Robux kauft nur Terminal-Themes/Skins.
> 6. §12.6: Liga-Rang nach **Skill-Score** (Tie-Break Ø-Tagesrendite), absolute Stufen Bronze 300 / Silber 500 / Gold 700 / Diamant 850.
> 7. §16: Tower-AG entfällt; v2 **Trader-AG** mit Kurs aus dem TWR-Index der Handelsrendite.
> 8. §10.1/§11: Remote `Market` (Arten News/Event/Halt/Bell/Ipo/Calendar/DayClose) statt `MarketNews`; Request-Aktionen ohne Punkt
>    (`TradePlace`, `TradeCancel`, `TradeModify`, `MktCandles`, `MktProfile`, `MktCalendar`, `MktNews` …, DESIGN §C9).
> 9. §5.6/§8.2: Speicher `AT_Market_v1`, MemoryStore `AT_Bus_W<w>`, Messaging-Thema `AT_EV`.
> 10. §6.5/§12.4: v1 IPO-**Erstnotiz ohne Zeichnung**; Zeichnung pro rata und Leerverkauf erst v1.1 (IDs/Felder reserviert).
> 11. §12.1: `Pos`/`Short` mit String-Schlüsseln `tostring(instId)`. §11/§14.1: Betrags-Chips **10 % · 25 % · Max**; News-Karte mit
>     Balken „Händler lesen …“ statt Countdown, ohne Kauf-Knopf, gedrosselt (DESIGN §B7.4).

---

## Inhalt
0. Kurzfassung (Entscheidungen) · 1. Compliance zuerst · 2. Was wir von der AKYTEX-Website übernehmen · 3. Zeit & Begriffe ·
4. Instrumente · 5. Preis-Modell · 6. Events & News · 7. Skill-Beweis (Backtest) · 8. Globaler Markt vs. pro Server ·
9. Kerzen & Historie · 10. Netzwerk & Bandbreite · 11. Orders · 12. Depot-Mathematik · 13. Anti-Exploit ·
14. Einfach für Kinder, tief für Profis · 15. Tower-Anbindung (Idle, Bots) · 16. Spieler-Firmen (Tower-AG) ·
17. Admin-Markt-Kontrolle · 18. Module, APIs, Server-Schleife, Budgets · 19. Tests & Akzeptanz · 20. Offene Punkte · Quellen

---

## 0. Kurzfassung (Entscheidungen)

| # | Entscheidung | Warum |
|---|---|---|
| D1 | **Globaler deterministischer Markt**: Kurs = Funktion(Wochen-Seed, Tick, Event-Liste). Jeder Server rechnet selbst, kein Tick-Streaming zwischen Servern. | Identische Kurse überall → kein Server-Hopping-Exploit, null Netzwerk-Kosten, Historie/Offline-Orders exakt nachrechenbar, Studio-tauglich. |
| D2 | **Preis-Nehmer-Markt** (Spieler bewegen den Kurs nicht), Kosten = Spread + Gebühr. | Keine Manipulation (Pump & Dump, Alt-Accounts), keine Liquiditätsprobleme, fair für Kinder. |
| D3 | Kurs = Fundament (Drift + Event-Sprünge) × stationäres Mehr-Oktaven-Rauschen (Markt/Sektor/Firma) × Volatilitäts-Regime. | Kurzfristig Random-Walk-Look, langfristig Mean-Reversion → langfristige Bewegung kommt aus **lesbaren** News/Fundamentaldaten. |
| D4 | **News mit Lesefenster**: Schlagzeile erscheint, Kurs reagiert erst nach 8 s über 45 s. Gerüchte mit Quellen-Sternen, „wie erwartet“-Fallen, Analysten mit echter, sichtbarer Trefferquote. | Lesen + Verstehen = Skill. Backtest: Zufall −0,35 %/Spieltag, informierte Spieler +5,7…+7,7 % mit 100 % positiven Tagen (§7). |
| D5 | Server-Tick **1 Hz** (eine kanonische Kursnotiz je Sekunde), 1s-Kerzen-H/L deterministisch, Orders prüfen genau die Kerzen, die der Chart zeigt. | Billig (< 0,3 ms/Tick), „was der Chart zeigt, hat die Order gesehen“. |
| D6 | **Ein Frame für alle**: 439 Byte/s (43 Instrumente) per `FireAllClients(buffer)`; Historie auf Anfrage aus Ring-Buffern (Buffer-Slice, gecacht). | ≈ 0,44 KB/s je Spieler, 22 KB/s für 50 Spieler (§10). |
| D7 | Geld in **ganzzahligen Cent**, Rundung immer zugunsten des Hauses, Menge × Preis < 2^53 erzwungen. | Kein Cent-Exploit durch Kauf-/Verkauf-Schleifen. |
| D8 | Ordertypen für Kinder: Sofort, Wunschpreis (Limit), Verlust-Stopp, Gewinn-Ziel, Schutz-Paar (OCO); Profi: Nachzieh-Stopp, Leerverkauf 1× (ab Fondsmanager). **Kein Hebel, keine Optionen, keine Binär-/Up-Down-Wetten.** | Compliance + Owner-Wunsch „kein Hebel-Casino“. |
| D9 | **Offline-Orders** (24 h) und Bots werden beim Wiederkommen **exakt** nachgerechnet (deterministischer Markt). | Stop-Loss schützt auch offline; Grund wiederzukommen („Während du weg warst …“). |
| D10 | Admin-Markt-Events global über **MemoryStore-Log (Wahrheit) + MessagingService (Schnellweg)** mit 10 s Vorlauf; Admin-Events klingen immer ab und pausieren die Wochen-Liga. | Alle Server wenden das Event im selben Tick an; Fairness. |
| D11 | Spieler-Firmen nur als **„Tower-AG“** mit Formel-Kurs (aus Tower-Kennzahlen), System als Gegenpartei, 5-min-Fixing, keine Verkäufe des Eigentümers. Phase 2. | Echte Spieler-Aktien zwischen Spielern = Betrug/Manipulation/„Paid Item Trading“ (§16). |
| D12 | Robux berühren den Markt **nie**: kein Depot-Geld, keine Infos, keine Gewinn-Multiplikatoren, keine Verlust-Versicherung. | Kauf darf nie wie ein Einsatz/eine Wette wirken (§1.4). |

---

## 1. Compliance zuerst (Roblox-Regeln 2025/26)

### 1.1 Recherche – was die Regeln sagen
Hinweis: Die Roblox-Seiten (`about.roblox.com`, `create.roblox.com`, `devforum.roblox.com`) waren aus dieser Umgebung per
Netzwerk-Richtlinie **gesperrt**. Die Zitate stammen aus Suchergebnis-Auszügen dieser Seiten (Quellen unten). **Vor dem
Ausfüllen des Fragebogens liest der Besitzer den Live-Wortlaut noch einmal** (Fragen werden umbenannt).

- **Community Standards / Rules of Conduct – Glücksspiel:** „Except where prohibited by local law or regulation, we allow
  unplayable gambling content, such as references to gambling and related imagery. However, we prohibit both simulated and
  actual gambling activities on the platform.“ und „No real money, Robux, or in-experience items of value may be exchanged in
  connection with any gambling activities.“
- Roblox-Sprecher gegenüber der Presse (via iGaming Expert): Roblox „firmly prohibits all simulated and actual gambling activities on our platform“.
- Ältere Formulierung (Experience-Guidelines-Ära, auf dem DevForum zitiert): erlaubt „unplayable gambling content … as well as
  games of luck and chance that are not casino or gambling based“. Ältere ToS-Formulierung (2023 zitiert): verboten sind
  „experiences that include simulated gambling, including playing with virtual chips, simulated betting, or exchanging real
  money, Robux, or in-experience items of value.“
- **Content-Maturity-Labels:** Minimal / Mild / Moderate / Restricted. „Unplayable gambling content“ taucht **erst ab Moderate**
  auf. Minimal und Mild sind laut Creator-Docs auch für jüngere Konten (Roblox Kids 5–8, Roblox Select 9–15) zugänglich.
  Ungenaue oder fehlende Angaben → Roblox schränkt die Spielbarkeit für alle ein.
- **Durchsetzung (Anekdote, DevForum):** Ein Casino-artiges Spiel mit reinem Gratis-Spielgeld und Spielzeit-Limits wurde trotzdem
  dauerhaft gelöscht. → Roblox legt „simulated gambling“ **streng** aus; das Thema allein reicht als Risiko.
- **Paid Random Items:** `PolicyService:GetPolicyInfoForPlayerAsync()` liefert `ArePaidRandomItemsRestricted` und
  `IsPaidItemTradingAllowed`; Pflicht: alle Ergebnisse mit echten Quoten, Summe exakt 100 %.
- **Experience Notifications:** nur für Nutzer ab 13 mit Opt-in; Dark Patterns (falscher Zeitdruck) verboten.

Ein Börsenspiel wird in keiner Regel ausdrücklich genannt. Das Risiko liegt in **Mechanik und Darstellung**: Sieht etwas aus
wie Einsatz → Zufall → Auszahlung, gilt es als simuliertes Glücksspiel. Deshalb ist der Markt so gebaut, dass es **keinen Einsatz
und keine Auszahlung** gibt, sondern nur **Kaufen zu einem angezeigten Preis** und **Verkaufen jederzeit**, und dass das Ergebnis
messbar von **Entscheidungen** abhängt (§7).

### 1.2 Zehn Konstruktionsregeln (verbindlich)
1. **Kein Wett-Format:** keine „Steigt/Fällt in 60 s?“-Runden, keine festen Quoten oder Auszahlungen, kein „Verdoppeln“,
   keine Countdown-Runden, in denen man vorher Geld festlegt. Man besitzt Anteile und verkauft sie, wann man will.
2. **Ergebnis stetig und informationsgetrieben:** Kursbewegung kommt überwiegend aus vorher lesbaren News, Terminen und
   Fundamentaldaten; Rauschen ist kurzfristig und mittelwertstabil (§5). Zufallshandel ≈ 0 oder leicht negativ (§7).
3. **Kein Hebel, keine Optionen/Turbos/CFDs/Futures/Krypto.** Leerverkauf nur 1× mit Sicherheitsleistung, erst ab Fondsmanager.
4. **Klumpen-Grenze:** max. 30–60 % des Depots in einem Einzelwert (Lizenz-abhängig), damit „alles auf eins“ (Zocken)
   technisch nicht geht. ETFs ausgenommen.
5. **Keine Casino-Bilder, -Wörter, -Effekte:** keine Würfel, Karten, Slots, Chips, Glücksräder in der Stadt oder im UI
   (auch nicht als Deko → sonst „unplayable gambling“ = Moderate). Verbotene Wörter in Texten (DE/EN): Wette/bet,
   Einsatz/stake/wager, Jackpot, Gewinnchance/odds, Glücksrad/spin, Casino, all-in, verdoppeln/double or nothing, Los/lottery,
   zocken/gamble, „Rakete garantiert“. Erlaubt: kaufen, verkaufen, investieren, Depot, Rendite, Risiko, Kursziel.
6. **Keine Spielautomaten-Belohnung pro Trade:** Ein Gewinn-Trade zeigt eine grüne Zahl mit kurzem Glow. Konfetti/Geldregen nur
   für **Meilensteine** (Tower-Etage, Lizenzprüfung, Vermögens-Meilenstein, Liga-Platz, „Rekord-Trade“ höchstens 1× je Spieltag).
   Verluste werden ehrlich und ruhig gezeigt; keine „Fast-gewonnen“-Effekte.
7. **Robux → Markt: nichts** (Details §1.4). Keine Auszahlung von Spielgeld in Robux oder Items anderer Spieler.
8. **Kein Handel zwischen Spielern** mit gekauftem Wert (kein P2P-Aktien- oder Geldtransfer, keine Geschenke von Spielgeld).
   → Fragebogen „Paid Item Trading“: Nein. Tower-AG handelt nur gegen das System (§16).
9. **Fiktiv, nicht echt:** nur erfundene Firmen, Börse „AKYTEX Exchange“, Spielgeld-Währung (Vorschlag **„AKY“**, Anzeige
   „1.234,56 AKY“; Zeichen „Ⱥ“ nur falls die Schrift es sicher darstellt). Keine echten Firmen, Logos, Börsen (NASDAQ/DAX …),
   Kürzel großer echter Firmen, keine echten Währungszeichen (€/$) für Spielgeld.
10. **Ehrliche Aufklärung:** Glossar, Risiko-Tipps von NOVA, Gebühren-Spiegel, „Alles ist Spielgeld“-Hinweis im Terminal.
    **Keine** Werbung für echtes Traden, keine URLs/QR-Codes zur Website (Off-Platform-Verweise + Finanzwerbung an Kinder).
    AKYTEX wird über Name, Look, Terminal und NOVA-Assistent beworben, nicht über Links.

### 1.3 Fragebogen (Maturity & Compliance) – erwartete Antworten für den Markt-Teil
| Frage (sinngemäß) | Antwort | Begründung |
|---|---|---|
| Glücksspiel (auch „unplayable gambling content“) | **Keins** | keine Casino-Darstellung, kein Wett-Format, keine Würfel/Slots-Deko |
| Paid Random Items | **Nein** (wenn das Haupt-Design keine Zufallskisten verkauft) | Aktien kauft man zu einem festen, angezeigten Preis; IPO-Zuteilung ist für alle gleich (Quote), kein Los |
| Paid Item Trading | **Nein** | kein Handel zwischen Spielern |
| Übrige Kategorien | laut Haupt-Design ehrlich | – |

Ziel-Label: **Minimal/Mild** (größte Reichweite, Zielgruppe 10–15 vollständig erreichbar).

### 1.4 Robux-Schnittstelle des Markts (Erlaubt / Verboten)
**Erlaubt (Kosmetik/Komfort, kein Einfluss auf Kurse oder Ergebnisse):** Terminal-Themes in AKYTEX-Farbwegen, Kerzen-Stile,
Trading-Desk-Möbel, zusätzliche Chart-Layouts (2×2 Multi-Chart), mehr Watchlists/Alarm-Plätze, Avatar-/Tower-Kosmetik,
Tower-Produktions-Boosts (gehören zur Tower-Ökonomie, nicht zum Handel).

**Verboten:** Spielgeld direkt ins Depot · Infos/„Insider“/frühere News · Gewinn-Multiplikator auf Handelsgewinne
(„2× Trading-Gewinne“ = bezahlt größere Ausschüttung eines Zufallsergebnisses) · Verlust-Versicherung/Crash-Schutz ·
Rückgängig/„nochmal“ für Trades · höhere Limits/Hebel/Leerverkauf · Bot-Performance · Lizenzprüfungen überspringen ·
alles mit Countdown-Runde + Einsatz-Logik. Falls das Haupt-Design Robux-Geldpakete hat: nur in die **Bau-Kasse** (Tower),
nie ins Depot. Die Wochen-Liga misst **Rendite in %** (§12.6) und ist dadurch gegen Robux und Alt-Accounts immun.

---

## 2. Was wir von der AKYTEX-Website übernehmen (`js/`, `README.md`)

| Website | Übernahme ins Spiel |
|---|---|
| `market.js`: Seed je Symbol+Tag (`mulberry32(hash(sym:day))`), `gauss`, Volatilitäts-Regime `vs` (log-AR(1)), Tagesprofil `season()` (mehr Umsatz bei Eröffnung/Nachmittag), `tickStep`, Quote mit Spread, synthetisches Orderbuch, `aggregate()` für Kerzen, `TIMEFRAMES`, `perf()`, Quote-Felder (52W-Hoch/Tief, Ø-Volumen, Marktkap., KGV, Div.-Rendite) | Idee „deterministisch aus Seed“ wird zu **vollständig deterministisch je Tick** (§5). U-förmiges Aktivitätsprofil je Spieltag (Eröffnung/Schluss lebhafter). Synthetisches Orderbuch → „Markttiefe“-Ansicht. Quote-Felder → Firmenprofil („Wochen-Hoch/Tief“). |
| `market.js` `tick()`: gelegentliche Sprünge `Math.random() < 0.0004` („News“) | Ersetzt durch **angekündigte, lesbare News** (§6). Unangekündigte Zufallssprünge gibt es nicht. |
| `broker.js`: Market/Limit/Stop, Stop-Loss & Take-Profit als OCO, `reservedCash()`, `reservedQty()` (OCO-Paar zählt einmal), `stats()` (Trefferquote, bester/schlechtester Trade), Gebühr je Tarif | 1:1 als Server-Logik (§11, §12), Gebühr je **Lizenz** statt Tarif. |
| `ailab.js`: `sentimentIndex()` (Angst & Gier aus Breite, Momentum, RSI, Hochs), `volRegime()` (ruhig/normal/stürmisch), `sectorRotation()`, `anomalies()`, `drawdown()`, `sizing()` (1 %-Risiko-Regel), `backtest()`, `correlation()` | Angst-&-Gier-Anzeige (clientseitig aus dem Frame), **Markt-Wetter** (Regime → Wetter in der Stadt!), Sektor-Heatmap, NOVA-Tipps (Positionsgröße), Profi-Analyse. |
| `indicators.js`: SMA, EMA, Bollinger, RSI, MACD, Stochastik, ATR, VWAP, Heikin Ashi | Port nach `shared/Market/Indicators.luau` für den Client-Chart. |
| `chart.js`: Farben (Up `#22c55e`, Down `#ef4444`, BG `#060812`, Grid `rgba(140,160,255,0.06)`), Indikator-Farben (SMA20 `#f5b942`, SMA50 `#4f8cff`, SMA200 `#e056fd`, EMA9 `#00d1b2`, EMA21 `#ff7a45`, BB `#7c8cff`, VWAP `#ffd166`, RSI `#b388ff`), Chart-Typen (Kerzen, Hohle Kerzen, Heikin Ashi, Linie, Fläche, Baseline) | Chart-Look im Spiel identisch (Tokens in `UI.Theme`). |
| README: Laufband, Heatmap nach Sektoren, Screener, Watchlist, Preisalarme, Rangliste, Copy-Trading, Spotlight-Themenpakete, Zeitplan (Sparpläne, Wenn-Dann-Regeln), Autopilot-Presets | Ticker-Wände in der Stadt, Heatmap-Wand im Börsensaal, **Themen-Körbe** (z. B. „KI-Korb“, 1 Tipp = diversifiziert), Sparplan-Bot, Wenn-Dann-Bots im Tower (§15), „Trade teilen & kopieren“ (v2, **ohne** Zahlungen zwischen Spielern). |
| `data.js`: 40 **echte** Aktien (AAPL, SAP …) | **Nicht** übernehmen (echte Firmen). Stattdessen eigene fiktive Liste (§4). |
| Ideen-Börse mit Royalties für Autoren | **Nicht** übernehmen (Geldfluss zwischen Spielern). |

---

## 3. Zeit & Begriffe

| Begriff | Wert | Bemerkung |
|---|---|---|
| **Tick** | 1 s, `tick = floor(unixMs/1000) − EPOCH` | `EPOCH` = Montag 05.01.2026 00:00 UTC. Server-Uhr: `DateTime.now().UnixTimestampMillis`. Client-Countdowns: `workspace:GetServerTimeNow()`. |
| **Spieltag** („Börsentag“) | 1200 Ticks = **20 min** | Börsen-Glocke bei :00 (Eröffnung), Tagesrückblick bei :20. Tageskerze „1T“. Passt zum Tag/Nacht-Zyklus der Welt. |
| **Woche** (Seed-Segment, Liga) | 604 800 Ticks = 7 echte Tage = 504 Spieltage | Wechsel Montag 00:00 UTC. Neuer Seed, Wochen-Liga neu. |
| **Saison** | 4 Wochen | Belohnungen laut Haupt-Design. |
| Zeitrahmen im Chart | **1s · 5s · 1m · 5m · 15m · 1T (20 min) · 1W (7 Spieltage = 140 min)** | Live: 1s/5s/1m. |
| Instrument-ID | u8: 1–36 Aktien, 40–46 ETFs, 100–139 IPO-Plätze | IDs **nie** wiederverwenden. Tower-AGs laufen nicht im Frame. |
| Währung | **AKY** (Cent-genau) | intern ganzzahlige Cent. |

Börsen-Rhythmus je Spieltag (Minute):
`:00` Glocke + Eröffnung (lebhafter) · `:02` Termin-Vorschau · `:03/:07/:11/:15` Quartalszahlen (je 3 Firmen) ·
`:10` Makro (Zinsentscheid oder Konjunkturdaten) · `:19` Dividenden-Ex-Tag der Zahler · `:17–:20` Schluss (lebhafter) ·
dazwischen Firmen-News (Ø alle ~40 s eine Schlagzeile im ganzen Markt), Sektor-News (Ø alle 10 min), selten Crash/Rallye.

---

## 4. Instrumente

### 4.1 Risikoklassen
| Klasse | σ (Rauschen, log) | Spread (voll) | News-Faktor | 1s | 1m | Spieltag | 2 h | Niveau-Std |
|---|---|---|---|---|---|---|---|---|
| **Stabil** | 0,030 | 0,04 % | ×0,74 | 0,06 % | 0,43 % | 1,8 % | 3,0 % | 2,3 % |
| **Normal** | 0,055 | 0,08 % | ×1,00 | 0,11 % | 0,78 % | 3,3 % | 5,5 % | 4,2 % |
| **Wild** | 0,100 | 0,16 % | ×1,35 | 0,19 % | 1,42 % | 6,0 % | 9,9 % | 7,6 % |
| ETF (Korb) | aus Bestandteilen | 0,03 % | – | ~0,6× Normal | | | | |

Standardabweichung der Log-Rendite ohne Events, gemessen mit `tools/market_calibrate.py` (86 400 Ticks). Das Rauschen sättigt
ab ca. 2–4 h (Mean-Reversion), Autokorrelation der 1m-Renditen −0,02 (kein gratis Momentum), der 1s-Renditen −0,035
(leichter Bid/Ask-Bounce → Sekunden-Scalping lohnt nicht). Korrelation der 1m-Renditen: gleicher Sektor **0,52**, andere
Sektoren **0,18**. Spread × Regime `R(t)`.

### 4.2 Die 36 Firmen (alle fiktiv) – 6 Sektoren × 6
Sektoren (DE/EN): **T** Tech & KI / Tech & AI · **E** Energie & Klima / Energy & Climate · **M** Mobilität & Raumfahrt /
Mobility & Space · **K** Konsum & Food / Consumer & Food · **G** Gaming & Medien / Gaming & Media · **F** Finanzen &
Immobilien / Finance & Real Estate. Startkurs in AKY, Dividende in % je Ausschüttung (alle 3 Spieltage, nur Zahler).

| ID | Kürzel | Name | S | Klasse | Start | Div. | Kurz-Story (DE) |
|---|---|---|---|---|---|---|---|
| 1 | CGVO | Cognivo KI | T | Normal | 240 | – | Lern-Roboter mit KI (umbenannt, DESIGN §C19) |
| 2 | KRWK | Kernwerk Systems | T | Stabil | 180 | 0,4 | Fabrik-Software (umbenannt, DESIGN §C19) |
| 3 | QTRX | Quantorix Quantum | T | Wild | 42 | – | Quantencomputer, schreibt noch Verluste |
| 4 | LMRA | Lumora Chips | T | Normal | 115 | 0,2 | Chips für KI-Rechenzentren |
| 5 | NMBY | Nimbusly Cloud | T | Stabil | 88 | 0,3 | Cloud-Speicher |
| 6 | PXWK | Pixelwerk Robotics | T | Wild | 27 | – | Haushaltsroboter |
| 7 | SNWK | Sonnwerk Solar | E | Normal | 64 | 0,3 | Solarparks |
| 8 | FSNT | Fusionaut | E | Wild | 19 | – | Kernfusion-Start-up |
| 9 | NBRZ | Nordbrise Wind | E | Stabil | 52 | 0,6 | Windparks auf See |
| 10 | HDRV | Hydrava | E | Normal | 36 | – | Wasserstoff |
| 11 | VLTR | Voltaris | E | Normal | 98 | 0,2 | Batterien |
| 12 | GTHM | Geotherma | E | Stabil | 74 | 0,7 | Erdwärme |
| 13 | ORBV | Orbivo Space | M | Wild | 155 | – | Raketen & Satelliten |
| 14 | MGLN | Magliner | M | Stabil | 61 | 0,5 | Magnetschwebebahn |
| 15 | VLCT | Velocitra Motors | M | Normal | 210 | 0,1 | E-Sportwagen |
| 16 | DRNR | Dronaro | M | Normal | 33 | – | Lieferdrohnen |
| 17 | ARLF | Aerolift | M | Wild | 24 | – | Flugtaxis |
| 18 | RTXO | Robotaxo | M | Normal | 47 | – | Robotaxis |
| 19 | KNSX | Knusperix | K | Stabil | 58 | 0,8 | Snacks |
| 20 | BLBR | Blubbro | K | Stabil | 41 | 0,9 | Limonaden |
| 21 | SNKA | Sneakora | K | Normal | 132 | 0,3 | Sneaker |
| 22 | BGPT | Burgerplanet | K | Stabil | 77 | 0,7 | Burger-Kette |
| 23 | PFFR | Pfotenfreund | K | Normal | 29 | 0,2 | Tierbedarf (umbenannt, DESIGN §C19) |
| 24 | SPWK | Spielwerk Toys | K | Normal | 45 | 0,4 | Spielzeug |
| 25 | ARCN | Arcadeon Games | G | Normal | 96 | 0,1 | Videospiele |
| 26 | STMR | Streamora | G | Normal | 143 | – | Streaming |
| 27 | PLVO | Playverso VR | G | Wild | 38 | – | VR-Brillen |
| 28 | MEMT | Memetastic Media | G | Wild | 12 | – | Meme-Videos |
| 29 | ESPV | Esportiva Arena | G | Normal | 54 | 0,2 | E-Sport-Ligen |
| 30 | NNBT | Neonbeat Records | G | Stabil | 66 | 0,5 | Musiklabel |
| 31 | TWBK | Towerbank | F | Stabil | 118 | 1,0 | Bank |
| 32 | SKLA | Skylinea | F | Stabil | 84 | 1,1 | Immobilien |
| 33 | GLDR | Goldader Mining | F | Normal | 71 | 0,4 | Goldminen |
| 34 | SCHF | Sicherhafen | F | Stabil | 102 | 1,2 | Versicherung |
| 35 | KLPY | Klickpay | F | Normal | 89 | – | Bezahl-App |
| 36 | BKRZ | Baukranz | F | Normal | 49 | 0,5 | Baukonzern |

ETFs: **40 AKX36** („AKYTEX 36“, alle gleichgewichtet – die Einsteiger-Empfehlung), **41–46** Sektor-ETFs AKXT, AKXE, AKXM,
AKXK, AKXG, AKXF. ETF-Kurs `= 100 · exp(mittel_i(ln P_i(t) − ln P_i(t_Woche)))` – deterministisch, kein eigenes Rauschen.
IPO-Pipeline (Beispiele, je Saison 4–8): Neuronauten (T), Flora Energy (E), Hyperloop Ost (M), Mondwerk (M), Robochef (K), Aquafarm (K).

Namensregeln: erfundene Komposita, keine Ähnlichkeit mit echten Marken. **Vor Release** jedes Kürzel/jeden Namen einmal
suchen (keine bekannte echte Firma, kein Kürzel eines großen echten Börsenwerts). Logos = UI-Formen (Buchstabe + Verlauf +
Grundform) in Sektor-Farbe, keine Assets.

### 4.3 Fundamentaldaten (sichtbar, Skill für Profis)
Je Firma: Umsatz, Gewinn je Aktie (EPS), KGV = Kurs/EPS, Dividendenrendite, Umsatzwachstum der letzten 4 Quartale,
Analysten-Einschätzungen, nächste Termine. Verborgene **Qualität `q ∈ [−1, 1]`** je Woche (aus dem Seed) steuert:
Fundament-Drift (`+0,2 % + 0,4 % · q` je Spieltag), Mittelwert der Quartals-Überraschung (`0,6 · q`), den angezeigten
Umsatztrend. Wer Fundamentaldaten liest, erkennt `q` nach 2–3 Quartalen – das ist der langfristige Skill.

---

## 5. Preis-Modell

### 5.1 Formel
Für Instrument `i` zum Tick `t` (innerhalb der Woche `w`, `t0` = Wochenstart):

```
ln P_i(t) = ln B_i,w                                     -- Wochen-Basis = Schlusskurs der Vorwoche (§5.6)
          + d_i · (t − t0)                               -- Fundament-Drift (aus Qualität q_i)
          + E_i(t)                                       -- Summe aller Event-Beiträge (News, Zahlen, Crash, Dividende, Admin)
          + σ_i · R(t) · ( β·M(t) + γ·S_s(i)(t) + ε·I_i(t) − N0_i )   -- korreliertes, stationäres Rauschen
          + μ · σ_i · W_i(t)                             -- Mikrostruktur (je Sekunde unabhängig, Bid/Ask-Bounce)
```
- `M` Markt-Feld, `S_s` Sektor-Feld (6), `I_i` Firmen-Feld (36): je ein **Value-Noise mit 14 Oktaven** (Perioden 2 s … 16 384 s),
  Amplitude je Oktave `√Periode` (→ Random-Walk-Spektrum), oberste zwei Oktaven gedämpft (×0,6) → Mean-Reversion ab ~2–4 h.
  Normiert auf Varianz 1.
- Gewichte `β = 0,45, γ = 0,55, ε = 0,70` (Quadratsumme ≈ 1) → Korrelation gleicher Sektor 0,52, sonst 0,18.
- `N0_i = Rauschwert bei t0` → Kurs ist am Wochenwechsel stetig (kein Sprung).
- `R(t)` Volatilitäts-Regime: `exp(0,25 · V(t)) · Boost(t)`, `V` = langsames Feld (Oktaven 15 min … 4,5 h), Boost durch
  Crash/Rallye/Admin (Rampe über 30 s, nie sprunghaft). Anzeige als **Markt-Wetter**: `R < 0,85` sonnig/ruhig,
  `0,85–1,2` wolkig/normal, `> 1,2` Sturm (die Welt übernimmt das Wetter → Gewitter beim Crash).
- `μ = 0,010` (Mikrostruktur relativ zu σ).
- Kurs in Cent: `mid = clamp(round(exp(ln P) · 100), 50, 9 999 999)` (0,50 … 99 999,99 AKY).
- Aktivitätsprofil je Spieltag (aus `market.js season()`): Volumen ×1,4 in den ersten/letzten 3 Minuten.

### 5.2 Hash & Value-Noise in Luau (deterministisch, kein `Random`, kein `math.random`)
Eigenes Hashing statt `Random.new`: identisch auf allen Servern und allen Roblox-Versionen, zustandslos (Random-Access).

```lua
--!strict
-- Noise.luau (nur Server). Luau-Zahlen sind Doubles: exakt bis 2^53 -> 32-Bit-Multiplikation per 16-Bit-Split.
local function mul32(a: number, b: number): number
	local aHi, aLo = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	local bHi, bLo = bit32.rshift(b, 16), bit32.band(b, 0xFFFF)
	local mid = (aHi * bLo + aLo * bHi) % 65536
	return (mid * 65536 + aLo * bLo) % 4294967296
end

local function h32(x: number): number -- "lowbias32" (Wellons)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = mul32(x, 0x7FEB352D)
	x = bit32.bxor(x, bit32.rshift(x, 15))
	x = mul32(x, 0x846CA68B)
	return bit32.bxor(x, bit32.rshift(x, 16))
end

local function hash4(a: number, b: number, c: number, d: number): number
	local h = h32(bit32.bxor(0x9E3779B9, a))
	h = h32(bit32.bxor(h, b))
	h = h32(bit32.bxor(h, c))
	return h32(bit32.bxor(h, d))
end

local function uni(seed: number, fid: number, k: number, n: number): number -- [-1, 1)
	return hash4(seed, fid, k, n) / 2147483648 - 1
end

local K, P0 = 14, 2
local PERIOD, AMP = table.create(K), table.create(K)
local sumSq = 0
for k = 1, K do
	PERIOD[k] = P0 * 2 ^ (k - 1)
	AMP[k] = math.sqrt(PERIOD[k]) * (if k == K then 0.6 elseif k == K - 1 then 0.6 else 1)
	sumSq += AMP[k] ^ 2
end
local INV_NORM = 1 / math.sqrt(sumSq * (2 / 3) * (1 / 3)) -- Var(uni) = 1/3, Mittel der Lerp-Varianz = 2/3

export type Field = { Seed: number, Id: number, Ph: { number }, N: { number }, V0: { number }, V1: { number } }

local function newField(seed: number, fid: number): Field
	local f = { Seed = seed, Id = fid, Ph = {}, N = {}, V0 = {}, V1 = {} }
	for k = 1, K do
		f.Ph[k] = hash4(seed, fid, k - 1, 777) % PERIOD[k] -- Phasenversatz; Oktaven-Index im Hash 0-basiert (= Python-Referenz)
		f.N[k] = -1
	end
	return f
end

-- Sequentiell (Live, Offline-Abgleich) praktisch nur 14 Lerps, Hashes nur beim Gitterwechsel.
local function fieldAt(f: Field, t: number): number
	local sum = 0
	for k = 1, K do
		local u = (t + f.Ph[k]) / PERIOD[k]
		local n = u // 1
		if n ~= f.N[k] then
			f.V0[k] = if n == f.N[k] + 1 then f.V1[k] else uni(f.Seed, f.Id, k - 1, n)
			f.V1[k] = uni(f.Seed, f.Id, k - 1, n + 1)
			f.N[k] = n
		end
		sum += AMP[k] * (f.V0[k] + (f.V1[k] - f.V0[k]) * (u - n))
	end
	return sum * INV_NORM
end

local function whiteAt(seed: number, fid: number, t: number): number -- ≈ N(0,1): Summe von 3 Uniforms
	return uni(seed, fid, 9001, t) + uni(seed, fid, 9002, t) + uni(seed, fid, 9003, t)
end
```
Live-Felder und Random-Access-Felder (Historie/Offline) sind **getrennte** `Field`-Objekte, damit sich Caches nicht stören.
Optional `--!native` für `Noise.luau` (Server-Native-Codegen).

### 5.3 Kurs, Quote, 1s-Kerze
```lua
-- PriceEngine (Ausschnitt). Alle Geldwerte in Cent.
local function logMid(i: number, t: number): number
	local c = INST[i]
	local noise = BETA * fieldAt(F.M, t) + GAMMA * fieldAt(F.S[c.Sector], t) + EPS * fieldAt(F.I[i], t) - c.N0
	return c.LogBase + c.Drift * (t - WEEK_START) + Events.Offset(i, t)
		+ c.Sigma * (Regime.At(t) * noise + MICRO * whiteAt(SEED, 200 + i, t))
end

local function midCents(i: number, t: number): number
	return math.clamp(math.round(math.exp(logMid(i, t)) * 100), 50, 9999999)
end

local function quote(i: number, mid: number, t: number)
	local spread = math.max(1, math.round(mid * INST[i].SpreadBps * Regime.At(t) / 10000))
	local bid = mid - spread // 2
	return bid, bid + spread -- bid, ask (ganzzahlig)
end

-- 1s-Kerze: O = Schluss der Vorsekunde, C = mid(t); H/L deterministisch aus dem Hash (kein echter Zwischenkurs nötig)
local function candle1s(i: number, t: number, o: number, c: number)
	local s = INST[i].Sigma1s -- 1s-Std der Klasse (Stabil 0,0006 / Normal 0,0011 / Wild 0,0019)
	local h = math.max(o, c) * (1 + math.abs(whiteAt(SEED, 300 + i, t)) * s * 0.6)
	local l = math.min(o, c) * (1 - math.abs(whiteAt(SEED, 400 + i, t)) * s * 0.6)
	local v = INST[i].VolBase * Regime.At(t) * (0.5 + (uni(SEED, 500 + i, 0, t) + 1) / 2)
		* (1 + 6 * math.abs(math.log(c / o)) / s) * (if Events.NewsActive(i, t) then 3 else 1)
	return o, math.round(h), math.round(l), c, math.clamp(math.round(v / 10), 0, 65535) -- Volumen in 10er-Lots
end
```

### 5.4 Fundament & Bewertungs-Bremse
- Drift `d_i` je Tick aus `q_i` (§4.3), ETFs aus Bestandteilen.
- **Bewertungs-Bremse** (verhindert Kurse bei 0,50 oder 99 999 AKY über Wochen): `C_i` = Summe aller dauerhaften Sprünge der
  Woche. Ist `C_i > +0,9` (Kurs ≈ ×2,5), steigt die Wahrscheinlichkeit negativer News von 48 % auf 70 % (umgekehrt bei
  `C_i < −0,9`). Das KGV zeigt die Überbewertung vorher an → Profis lernen „zu teuer = Risiko“.

### 5.5 Kosten pro Tick (Server)
44 Felder (1 Markt + 6 Sektor + 36 Firma + 1 Regime) × 14 Lerps ≈ 620 Lerps + ~40 Hashes/s + 43 `exp` → geschätzt
**< 0,1 ms** je 1-Hz-Tick in Luau. (Keine Luau-Laufzeit in dieser Umgebung; Schätzung, im Studio mit `Scheduler.Stats()` messen.)

### 5.6 Seeds & Wochenwechsel
- DataStore `AKX_Market_v1`: Schlüssel `Seed_W<w>` = zufällige 31-Bit-Zahl, angelegt per `UpdateAsync` („nur setzen, wenn leer“)
  vom ersten Server der Woche; der erste Server einer Woche legt auch schon `Seed_W<w+1>` an (kein Ansturm am Wechsel).
- Wochenschluss: Der erste Server, der den Wechsel erlebt, rechnet `P_i(t_ende)` für alle Instrumente und schreibt
  `Close_W<w>` per `UpdateAsync` (alle Server rechnen dieselben Werte; wer zuerst schreibt, ist egal). `B_i,w+1 = Close_W<w>`.
  Fehlt `Close_W<w>` (kein Server lief), rechnet der nächste Server ihn aus `Seed_W<w>` + `Close_W<w−1>` nach.
- Der Seed ist **nie** im Place-File (geleakte Place-Datei verrät keine Zukunft) und erreicht nie einen Client.
- **Studio/Ausfall:** schlägt der DataStore fehl → Seed = `hash4(STUDIO_SALT, w, 0, 0)`, Banner „Lokaler Testmarkt“ im
  Admin-Panel; im Live-Spiel zuerst 60 s Wiederholen mit Backoff (Markt zeigt „öffnet gleich …“), dann derselbe Fallback.

---

## 6. Events & News (der Skill-Kern)

### 6.1 Grundprinzip: erst lesen, dann reagiert der Markt
Jede News hat `t_a` (Veröffentlichung), Lesefenster `DELAY = 8 s`, Reaktions-Rampe `TAU = 45 s` (Smoothstep), optional
Übertreibung `o ∈ [0; 0,3]`, die sich mit 5 min Halbwertszeit teilweise zurückbildet („Überreaktion kaufen/verkaufen“ ist
Profi-Skill). Beitrag zu `E_i(t)` (log):
```
x = t − t_a − DELAY
c(t) = 0                                              für x < 0
c(t) = J · (1 + o) · smooth(x / TAU)                  für 0 ≤ x ≤ TAU
c(t) = J · (1 + o) − J · o · (1 − e^(−(x−TAU)/300))   für x > TAU
```
Stärke-Wortschatz (lernbar, DE/EN, steht in jeder Schlagzeile):
| Band | Anteil | |J| (Normal) | Wörter (DE / EN) |
|---|---|---|---|
| leicht | 50 % | 1–3 % | „leicht“, „etwas“ / „slightly“, „a bit“ |
| deutlich | 30 % | 3–6 % | „deutlich“, „klar“ / „clearly“, „strong“ |
| massiv | 15 % | 6–12 % | „massiv“, „Großauftrag“ / „massive“, „mega deal“ |
| historisch | 5 % | 12–25 % | „historisch“, „Rekord“ / „historic“, „record“ |
Faktor je Klasse: `√(σ_i/σ_Normal)` (Stabil ×0,74, Wild ×1,35). Richtung: 52 % positiv (± Bewertungs-Bremse §5.4).

### 6.2 News-Arten
| Art | Anteil | Verhalten | Skill |
|---|---|---|---|
| **Fakt** | 55 % | volle Reaktion wie oben | schnell + richtig lesen |
| **Gerücht** (Quelle ★–★★★) | 25 % | Sofort 50 % der Reaktion; nach 2 min Bestätigung (+50 %) oder Dementi (−100 %, Kurs fällt unter Start). Bestätigungsquote ★ 35 %, ★★ 60 %, ★★★ 85 % (Sterne sichtbar; Mischung 45/35/20 %) | Quellen bewerten |
| **„Wie erwartet“** | 20 % | positiv klingende, schon erwartete Meldung → Kurs **fällt** um |J| („sell the news“), negative analog | Erwartung vs. Ergebnis verstehen |
| Sektor-News | Ø alle 10 min | trifft alle Firmen des Sektors, Firmen-Sensitivität 0,6–1,4 | Zusammenhänge |
| Makro (:10) | 1×/Spieltag | Konsens vorher sichtbar; Überraschung `s` wirkt über Matrix §6.4 | Matrix lernen |

Häufigkeit Firmen-News: Ø alle 1500 s je Firma → im ganzen Markt alle ~40 s eine Schlagzeile (Azubi sieht nur News seiner
12 Werte + Markt). Beispiel-Vorlagen (Config-Schlüssel, Parameter-Platzhalter, Client lokalisiert):
- `news.contract` DE „{name} gewinnt {band} Großauftrag über {amt} Mrd. AKY“ · EN „{name} wins {band} {amt}B AKY contract“
- `news.recall` DE „{name} muss Produkte zurückrufen – Schaden {band}“ · EN „{name} recalls products – {band} damage“
- `news.rumor.takeover` DE „Gerücht ({stars}): {buyer} will {name} kaufen“ · EN „Rumor ({stars}): {buyer} eyes {name}“
- `news.asexpected` DE „{name}: Gewinn wie erwartet gestiegen“ · EN „{name}: profit up as expected“
- `macro.rates` DE „Zentralbank: Zinsen {dir} – Erwartung war {cons}“ · EN „Central bank: rates {dir} – expected {cons}“

### 6.3 Quartalszahlen, Analysten, Dividenden
- **Quartalszahlen:** jede Firma alle 3 Spieltage (1 h echt); Firma `i` hat Termin, wenn `(Spieltag + i) % 3 == 0`, Slot
  `:03/:07/:11/:15`. Kalender ≥ 1 Spieltag vorher sichtbar. Bei `T−5 min` erscheinen Konsens + Analysten-Urteile.
  Überraschung `s = 0,6·q_i + 0,8·z` (`z` aus dem Hash ≈ N(0,1)), Sprung `J = clamp(0,03 · s · Klassenfaktor, ±0,20)`,
  gleiches Lesefenster/Rampe wie News. Umsatz/EPS im Firmenprofil werden mit `s` fortgeschrieben.
- **Analysten:** 8 erfundene Analysten (z. B. Mira Sommer, Jonas Falk, Lea Brandt, Kenji Mori, Ava Lindqvist, Omar Haddad,
  Clara Weiß, Theo Kranz) mit fester Genauigkeit 55–85 %: Urteil = `sign(s)` mit Wahrscheinlichkeit `acc`, sonst falsch.
  Angezeigt wird die **echte, live gemessene** Trefferquote der letzten 30 Urteile (ehrlich, konvergiert gegen `acc`).
  Skill: den guten Analysten vertrauen.
- **Dividenden:** Zahler schütten am Quartalstag um `:19` aus: Betrag je Aktie `div = round(mid · yield)`; im **selben Tick**
  `E_i −= ln(1 − div/mid)` (Kurs fällt um die Dividende → Dividenden-Mitnahme bringt nichts, realistisch). Anspruch = Bestand
  im Ex-Tick (serverseitig, auch offline nachgerechnet). Leerverkäufer zahlen die Dividende.

### 6.4 Makro-Wirkungs-Matrix (Faktor × Grundsprung 1,5 % × Überraschung)
| Ereignis | Tech | Energie | Mobilität | Konsum | Gaming | Finanzen |
|---|---|---|---|---|---|---|
| Zinsen höher als erwartet | −1,0 | −0,3 | −0,6 | −0,3 | −0,5 | +0,8 |
| Konjunktur stärker | +0,6 | +0,5 | +0,8 | +0,6 | +0,5 | +0,6 |
| Energiepreis steigt | −0,2 | +1,0 | −0,8 | −0,4 | −0,1 | 0 |
| KI-Durchbruch (Sektor-News) | +1,2 | +0,4 (Rechenzentren) | +0,3 | 0 | +0,6 | +0,2 |
| Chip-Knappheit | −0,8 | 0 | −0,7 | 0 | −0,6 | 0 |
| Hitzewelle | 0 | +0,5 | 0 | +0,6 (Getränke) | +0,2 | −0,2 (Versicherung) |
| Esport-WM | 0 | 0 | 0 | +0,2 | +1,0 | 0 |
| Raumfahrt-Mission | +0,2 | 0 | +0,9 (Space) | 0 | +0,2 | 0 |
Die Academy erklärt die Matrix stückweise; Profis kennen sie auswendig.

### 6.5 Crash, Rallye, IPO, Handelspausen
- **Crash** (unangekündigt Ø alle 3,5 h im Plan + wöchentlicher Live-Termin **„Crash-Freitag“**, Freitag 17:00 UTC, Tage vorher
  im Kalender): **Warnphase 3 min** (Regime ×1,3→1,6, Angst-Index fällt, 2–3 Warn-Schlagzeilen „Analysten warnen vor
  Überhitzung“), dann Fall `−12 … −30 % · β_Klasse` über 60–120 s, Erholung 40–60 % des Falls über 10–20 min. Effekte: rote
  Ticker-Wände, Sirenen-Sound (eingebaut), Gewitter-Wetter. Skill: vorher Stops/Cash, danach Erholung kaufen.
- **Rallye** spiegelbildlich (+8 … +20 %, positive Warnzeichen).
- **IPO** (Samstag 17:00 UTC + Admin): `T−24 h` Prospekt (Fundamentaldaten, Sektor, Analysten) · `T−10 min` Zeichnung (Betrag
  reservieren, max. 10 % des Depots) · `T0` Zuteilung **pro rata mit einer für alle gleichen Quote** (aus Seed, z. B. 40 %) –
  **kein Los** · `T0+60 s` Erstnotiz nach 60 s Auktion: `Eröffnung = Ausgabepreis · (1 + pop)`, `pop` korreliert mit den
  Prospekt-Hinweisen (Qualität, Analysten, Sektor-Momentum) → Skill. Erster Spieltag mit Klasse Wild.
- **Handelspausen** (`Halt`, 10 s): bei Admin-Events (Aktivierung), IPO-Erstnotiz (60 s), bei verspätet angekommenen
  globalen Events (§8.4). Normale News lösen **keine** Pause aus.

### 6.6 Deterministischer Tagesplan
```lua
-- EventDirector.BuildDay: zustandslos aus Seed + Spieltag; kein Random-Objekt (Versions-Stabilität)
local function rnd(day: number, k: number): number -- [0, 1)
	return hash4(SEED, 0xDA7, day, k) / 4294967296
end

function EventDirector.BuildDay(day: number): { Event }
	local list, k = {}, 0
	local function nextR() k += 1; return rnd(day, k) end
	addEarnings(list, day)                         -- Kalender: (day + i) % 3 == 0, Slots :03/:07/:11/:15
	addMacro(list, day, nextR)                     -- :10, Konsens bei :02
	for i = 1, 36 do                               -- Firmen-News: Poisson (Rate 1/1500 s) je Firma
		local t = -1500 * math.log(1 - nextR())
		while t < 1200 do
			table.insert(list, makeNews(i, day * 1200 + t // 1, nextR, Bias.Get(i))) -- Art, Band, Richtung, Sterne
			t += -1500 * math.log(1 - nextR())
		end
	end
	addSectorNews(list, day, nextR)                -- Ø alle 600 s
	addCrashRally(list, day, nextR)                -- Rate 1/(3,5 h) + feste Live-Termine aus Config
	addDividends(list, day)                        -- :19 an Quartalstagen der Zahler
	table.sort(list, function(a, b) return a.T < b.T end)
	return list
end
```
`Bias` (Bewertungs-Bremse) hängt von den Sprüngen früherer Tage ab → Tage werden ab Wochenstart **sequentiell** erzeugt und
gecacht (max. 504 Tage × ~60 Events ≈ 30 000 Events, Erzeugung einmalig beim Serverstart im Hintergrund). Der Client erfährt
eine News **erst bei `t_a`** (der Server kennt den Plan, schickt aber nie Zukünftiges).

`Events.Offset(i, t)` = `Settled_i` (Summe der abgeschlossenen, dauerhaften Anteile) + Summe der **aktiven** Events
(Rampe/Rückbildung noch nicht fertig). Für Random-Access (Historie) Präfix-Summen über die nach Zeit sortierten Events +
Binärsuche.

---

## 7. Skill-Beweis (Backtest)

`tools/market_calibrate.py`: 36 Instrumente, 3 Seeds × 12 Spieltage, Startkapital 100 000, 20 % je Trade, max. 5 Positionen,
Kosten je Seite 0,15 % (halber Spread + Azubi-Gebühr). Ohne Crash/Rallye.

| Strategie | Ø je Spieltag | Median | positive Tage | Trades/Tag | Bedeutung |
|---|---|---|---|---|---|
| Zufall (kauft zufällig, hält 1–5 min) | **−0,35 %** | −0,51 % | 39 % | 10,3 | Ohne Wissen kein Gewinn → kein „Glücksspiel mit Gewinnchance“ |
| Spam-Klicken (Sekunden-Momentum) | **−10,95 %** | −10,96 % | 0 % | 202 | Gebühren fressen alles → Rate-Limit + NOVA-Warnung |
| Halten (alle 36, gleichgewichtet) | +0,40 % | +0,03 % | 53 % | – | Geduldiges Investieren lohnt leicht (Drift) |
| Naiv (kauft jede positive Schlagzeile nach 4 s) | +5,20 % | +4,35 % | 89 % | 13,8 | Lesen hilft, Fallen kosten |
| NOVA-Ampel (nur Fakten, nach 20 s) | +5,73 % | +5,21 % | 100 % | 7,6 | Einsteiger-Hilfe funktioniert |
| Smart langsam (filtert Gerüchte ★/★★ und „wie erwartet“, 20 s) | +6,28 % | +5,80 % | 100 % | 8,4 | Verstehen > Tempo |
| Smart schnell (wie oben, 4 s) | **+7,72 %** | +6,96 % | 100 % | 8,4 | höchster Skill |

Lesart: Bei Zufallshandel sind nur 39 % der Tage positiv, bei informiertem Handel 89–100 % → das Ergebnis hängt von
**Entscheidungen** ab, nicht vom Glück. Die Zahlen sind **Obergrenzen eines Bots, der jede Schlagzeile liest**. Ein Mensch
verfolgt 5–10 Werte → realistisch ¼–½ davon.

**Ziel-Korridor nach Balancing** (Rendite je Spieltag): guter aktiver Spieler +1,5 … +4 %, Einsteiger mit Ampel +0,5 … +2 %,
Halten +0,3 … +0,5 %, Zufall −0,5 … 0 %, Spam klar negativ. **Stellschrauben** (alle in `Config/Market.luau`):
`NEWS_MEAN_GAP` (1500 s), Band-Größen, `DELAY` (8 s, Tempo-Skill), `TAU` (45 s), Ampel-Verzögerung (20 s), Fallen-Anteile
(Gerücht 25 %, „wie erwartet“ 20 %), Gebühren, Klumpen- und Positions-Grenzen (§11.6). Nach jeder Änderung Skript laufen lassen.

---

## 8. Globaler Markt vs. pro Server

### 8.1 Vergleich
| Kriterium | A: Jeder Server eigener Zufallsmarkt | B: Leit-Server streamt Ticks (MessagingService) | **C: Global deterministisch + Event-Bus** | D: Spieler-Orderbuch |
|---|---|---|---|---|
| Gleiche Kurse überall | nein | fast (Latenz 0,1–1 s, best effort) | **ja, exakt** | nein (pro Server) |
| Server-Hopping-Exploit (dauerhafte Depots!) | **katastrophal** (kaufen auf A, verkaufen auf B) | Lücken bei Ausfällen | **unmöglich** | katastrophal |
| Netzwerk zwischen Servern | 0 | 60 Nachrichten/min je Server, Limits knapp | **≈ 0** (nur seltene Events) | hoch |
| Ausfallsicherheit | hoch | Leit-Server-Wahl, Failover, Lücken | **hoch** (jeder rechnet selbst) | mittel |
| Historie/Offline-Orders | nur eigene Laufzeit | muss gespeichert werden | **jederzeit nachrechenbar** | nein |
| Studio Solo / 2 Spieler | ja | schwierig | **ja** | ja |
| Gemeinsame Momente (Crash für alle) | nein | ja | **ja** | nein |
| Manipulation durch Spieler | – | – | **keine** | hoch (Pump & Dump, Alts) |
| Aufwand | klein | groß | **mittel** | sehr groß |

**Empfehlung: C.** Option A ginge nur, wenn Depots beim Verlassen aufgelöst würden (zerstört den Tycoon-Kern).

### 8.2 Architektur von C
- **Basis-Kurs:** rein rechnerisch (§5), kein Netzwerk.
- **Geplante Events** (News, Zahlen, Crash, IPO, Dividende): deterministisch aus dem Seed (§6.6), kein Netzwerk.
- **Nicht-deterministische Events** (Admin-Abuse, Admin-IPO, Notfall-Pause): `GlobalBus`.
  - **Wahrheit:** MemoryStore SortedMap `AKX_Events_W<w>`, Schlüssel `string.format("%012d_%s", aktivierungsTick, guid)`,
    Ablauf 26 h (Offline-Fenster 24 h + Puffer). Zusätzlich DataStore `AdminLog_W<w>` (Audit, Admin-Panel-Verlauf).
  - **Schnellweg:** MessagingService-Thema `AKX_EV`, Nachricht enthält nur den Schlüssel (weit unter 1 KB).
  - **Polling:** jeder Server liest alle 5 s `GetRangeAsync(Ascending, 50, letzterSchlüssel)`.
  - **Vorlauf:** Aktivierung = jetzt + 10 s (> Poll-Intervall + Messaging-Latenz) → alle Server wenden das Event im **selben
    Tick** an. Ein Event gilt nur, wenn es im MemoryStore steht; scheitert das Schreiben, wird es abgebrochen (Admin-Panel
    zeigt „Markt-Event nicht verteilt“).

### 8.3 Limits (offizielle Formeln) und unser Verbrauch
| Dienst | Limit | Verbrauch | Reserve |
|---|---|---|---|
| MessagingService Senden je Server | 600 + 240 × Spieler / min | ≤ 20/min (nur Admin-Sessions) | riesig |
| MessagingService Empfang je Thema | (40 + 80 × Server) / min | jede Veröffentlichung = S Empfänge → bei 20/min: 20·S | ok für jedes S |
| Nachrichtengröße | 1 KB | ~80 Byte (Schlüssel) | ok |
| MemoryStore Anfragen | 1000 + 120 × CCU / min (ganzes Spiel) | 12 Polls/min je Server + Schreibvorgänge | ok |
| MemoryStore Speicher | 64 KB + 1,2 KB × CCU | Admin-Events ~300 B × ≤ 100/Tag; Tower-AG-Cache nur für **online** Eigentümer (~100 B × CCU) | ok (keine Dauer-Daten im MemoryStore!) |
| DataStore | Standard-Budgets | Seed/Close 1–2 Lesezugriffe je Serverstart | ok |

### 8.4 Verspätete Events (Messaging verloren, Poll verpasst)
Kommt ein Event nach seinem Aktivierungs-Tick an, wird es **trotzdem mit dem Original-Tick** angewendet (der Server springt auf
den globalen Kurs zurück, statt eine eigene Version zu bauen), die betroffenen Instrumente bekommen **10 s Handelspause**, und
der Kerzen-Cache des betroffenen Fensters wird neu berechnet. Da die Session-Sperre Doppel-Logins verhindert und ein
Serverwechsel deutlich länger als 10 s dauert, lässt sich die kurze Abweichung nicht ausnutzen.

**Markt-Events wirken immer global.** „Nur dieser Server“ gibt es nur für Nicht-Markt-Events (Geldregen, 2×-Einnahmen-Boost,
Konfetti) – ein lokal gepushter Kurs wäre sonst ein Hopping-Exploit.

---

## 9. Kerzen & Historie

### 9.1 Server-Ring-Buffer (buffer-basiert, 10 Byte je Kerze)
| Zeitrahmen | Tiefe | Quelle |
|---|---|---|
| 1s | 300 (5 min) | live |
| 5s | 360 (30 min) | aus 1s |
| 1m | 1440 (24 h) | aus 1s; beim Start Backfill |
| 5m / 15m / 1T / 1W | aus 1m aggregiert | 1W-Ansicht älter als 24 h: Übersichtskerzen (60-s-Stichproben, nur Anzeige, nie für Orders) |

Kerzen-Layout im `buffer`: `close u32` (Cent), `hiOff u16`, `loOff u16` (Abstand zu max/min(O,C) in 0,01 %-Einheiten),
`vol u16`; `open` = Schluss der Vorkerze, Zeit implizit (Index). Vorteil: Historien-Antwort = `buffer.copy` aus dem Ring, keine
Neu-Kodierung. Speicher: 1m-Ring 1440 × 43 × 10 B ≈ 620 KB.

### 9.2 Aggregation (identisch Server & Client, aus `market.js aggregate()`)
`open` = erste Open, `high` = max, `low` = min, `close` = letzte Close, `vol` = Summe; Bucket = `t // tfTicks · tfTicks`
(1T = 1200, 1W = 8400 Ticks).

### 9.3 Backfill beim Serverstart (Hintergrund, `Scheduler`, ≤ 2 ms je Frame)
Letzte 6 h exakt mit 1 Hz (21 600 Ticks × 620 Lerps ≈ 13 Mio. Lerps, geschätzt ~0,5–1 s CPU, verteilt auf ~10 s), dann 6–24 h
mit 10-s-Stichproben (genug für 1m+ Anzeige; Orders nutzen sie nie). Bis fertig zeigt der Chart „Historie lädt …“; der Live-Teil
läuft sofort.

### 9.4 Client
Baut 1s-Kerzen aus Frames, 5s/1m live daraus; Historie einmal je (Instrument, Zeitrahmen) per Anfrage. Lücke im Tick-Zähler
> 2 → Historie für die offenen Charts neu anfordern. Die letzte Kerze wird zwischen zwei Frames weich animiert (Tween 0,25 s
auf den neuen Schluss, iOS-Feder) – es werden **keine** erfundenen Zwischenkurse angezeigt.

---

## 10. Netzwerk & Bandbreite

### 10.1 Remotes (Ergänzung zu `Net.RemoteList`)
| Name | Klasse | Richtung | Inhalt |
|---|---|---|---|
| `MarketFrame` | RemoteEvent | S→C | buffer, 1 Hz, `FireAllClients` (einmal kodiert für alle) |
| `MarketNews` | RemoteEvent | S→C | News/Termine/Halts/Event-Start/Ende als kleine Tabelle (Schlüssel + Parameter, Client lokalisiert) |
| `Request` (vorhanden) | RemoteFunction | C→S | Aktionen `Market.Place`, `Market.Cancel`, `Market.Modify`, `Market.Candles`, `Market.Profile`, `Market.Calendar`, `Market.IpoSubscribe`, `Market.TowerAG*` → Reply-Vertrag wie im Shooter (C9) |
| `State` (vorhanden) | RemoteEvent | S→C | Depot-Deltas (Sticky-Merge) nur bei Änderung |
| `Admin` (vorhanden) | RemoteFunction | C→S | Markt-Admin-Aktionen (§17) |

### 10.2 Frame-Format (`shared/Market/QuoteCodec.luau`)
```
Header 9 Byte:  u8 version | u32 tick | u8 flags (Bit0 Halt irgendwo, Bit1 Admin-Event aktiv, Bit2 Crash, Bit3 Rallye)
                | u8 regime (R·100, geklemmt) | u8 n | u8 reserviert
Je Instrument 10 Byte: u8 id | u8 flags (Halt, News aktiv, Ex-Tag, Wochen-Hoch) | u32 close (Cent) | u8 hiOff | u8 loOff
                       (0,01 %-Einheiten, geklemmt 255) | u16 vol (10er-Lots)
Größe = 9 + 10·n  →  n = 43: 439 Byte, mit 4 IPOs (n = 47): 479 Byte
```
Absolute Kurse (keine Deltas) → ein verlorener/übersprungener Frame zerstört nichts. < 900 Byte, wäre also auch als
`UnreliableRemoteEvent` möglich; empfohlen ist zuverlässig (Konsistenz bei Fills), weil die Datenmenge winzig ist.
Angst-&-Gier-Index, Sektor-Performance, Heatmap, Ticker-Wände rechnet **jeder Client selbst** aus dem Frame (gleiche Daten →
gleiches Ergebnis).

```lua
-- QuoteCodec.EncodeFrame (Server), Decode spiegelbildlich (Client)
function QuoteCodec.EncodeFrame(tick: number, flags: number, regime: number, rows: { Row }): buffer
	local n = #rows
	local b = buffer.create(9 + 10 * n)
	buffer.writeu8(b, 0, 1)
	buffer.writeu32(b, 1, tick)
	buffer.writeu8(b, 5, flags)
	buffer.writeu8(b, 6, math.clamp(math.round(regime * 100), 0, 255))
	buffer.writeu8(b, 7, n)
	local o = 9
	for _, r in rows do
		buffer.writeu8(b, o, r.Id); buffer.writeu8(b, o + 1, r.Flags)
		buffer.writeu32(b, o + 2, r.Close)
		buffer.writeu8(b, o + 6, math.clamp(r.HiOff, 0, 255)); buffer.writeu8(b, o + 7, math.clamp(r.LoOff, 0, 255))
		buffer.writeu16(b, o + 8, math.clamp(r.Vol, 0, 65535))
		o += 10
	end
	return b
end
```

### 10.3 Budget
| Strom | Größe | Rate | je Spieler | 50 Spieler (Server-Ausgang) |
|---|---|---|---|---|
| MarketFrame | 439 B | 1 Hz | 0,44 KB/s | 22 KB/s |
| MarketNews | ~150 B | Ø 1/40 s (Spitze 3/s) | ~5 B/s | 0,3 KB/s |
| Depot-Deltas | ~150 B | nur bei Fill/Order, ≤ 1/s | ≤ 0,15 KB/s | – |
| Historie auf Anfrage | 240–360 Kerzen ≈ 2,5–3,6 KB | Chart öffnen/Zeitrahmen wechseln, ≤ 2/s | Spitzen | Crash-Moment: 50 × 3 × 3 KB ≈ 450 KB über ~5 s |
| Bestenlisten/Börsensaal-Wände | ~1 KB | 0,1 Hz | 0,1 KB/s | 5 KB/s |
| C→S Orders | ~60 B | ≤ 1,5/s | ≤ 0,1 KB/s | – |

**Dauerlast < 1 KB/s je Spieler (≈ 8 kbit/s)**, weit unter dem, was Charakter-Replikation sonst verbraucht. Historien-Antworten
werden je (Instrument, Zeitrahmen, letzte Kerze) **einmal** kodiert und für alle wiederverwendet. Remote-Rate-Grenze von Roblox
(≈ 500 Anfragen/s je Client) spielt bei unseren Token-Buckets (§13) keine Rolle.

### 10.4 Client-Chart (Vertrag für das UI-Team, nur GUI-Frames)
- Pool: sichtbare Kerzen 60 (Handy) / 120 (PC); je Kerze Körper + Docht + Volumen = 3 Frames; Linie = 1 gedrehter Frame je
  Segment; Indikatoren ≤ 3 Linien (Handy) / 6 (PC). Gesamt-Pool ≤ 900 GuiObjects, nie neu erzeugen.
- **Laufband-Scrollen:** neue Kerze → Container per Tween um eine Kerzenbreite schieben, linke Kerze nach rechts recyceln
  (O(1) statt alle neu zu setzen). Y-Achse nur neu skalieren, wenn Min/Max um > 5 % springt (Tween), höchstens 1×/s.
- Je Frame nur die letzte Kerze animieren. Ziel: < 0,3 ms/Frame Chart-Update am Handy.
- Welt-Monitore (SurfaceGui): Sparkline mit 30 Segmenten, 1 Hz, nur innerhalb 80 Studs und laut Grafik-Stufe.

---

## 11. Orders

### 11.1 Ordertypen (Kinder-Namen / Profi-Namen)
| Kinder (DE / EN) | Profi | Ab Lizenz | Regel |
|---|---|---|---|
| **Sofort kaufen/verkaufen** / Buy/Sell now | Market | Azubi | Kauf zum Ask, Verkauf zum Bid des **zuletzt gesendeten** Ticks |
| **Wunschpreis** / Target price | Limit | Azubi | Kauf wenn Ask ≤ Limit, Verkauf wenn Bid ≥ Limit |
| **Verlust-Stopp** / Loss stop | Stop-Loss | Azubi | Verkauf wenn Bid ≤ Stopp (bei Kurslücke schlechter) |
| **Gewinn-Ziel** / Profit target | Take-Profit | Azubi | Verkauf wenn Bid ≥ Ziel |
| **Schutz-Paar** / Safety pair | OCO (SL + TP) | Azubi (1-Tipp „Schutz an“: −8 % / +15 % Standard) | eine Seite ausgeführt → andere storniert |
| **Nachzieh-Stopp** / Trailing stop | Trailing Stop | Trader | Stopp folgt dem Höchstkurs mit Abstand x % |
| **Leerverkauf** / Short sell | Short 1× | Fondsmanager | Sicherheitsleistung 150 %, Leihgebühr, Zwangseindeckung (§12.4) |
| **Sparplan** / Auto-invest | Savings plan | Trader | kauft je Spieltag für Betrag X (meist ETF) |
Nicht vorhanden: Hebel, Optionen, Turbos, Binär-/Up-Down-Kontrakte, Futures, Krypto.

### 11.2 Validierung (Server, vor jeder Ausführung)
`action` in Whitelist · `args` exakt erwartete Schlüssel und Typen · Zahlen endlich (`n == n`, nicht ±inf) · `InstId` ganzzahlig,
existiert, durch Lizenz freigeschaltet, nicht pausiert (Market) · `Side ∈ {"B","S"}` · `Type ∈ {"MKT","LMT","STP","TP","OCO","TRL"}` ·
`Qty` ganzzahlig `1 … MaxQty(inst)` **oder** `Notional` (Cent) → Server rechnet `floor(Notional / ask)` · Preise →
`math.round` auf Cent, innerhalb `mid · [0,5; 1,5]` (Fehleingabe-Schutz), Stopp unter Bid/Ziel über Bid (sonst sofortige
Ausführung → Hinweis) · `ClientSeq` ganzzahlig, Duplikat (letzte 32) → gleiche Antwort wie beim ersten Mal · max. offene
Orders je Lizenz · optional `MaxPrice` (Market-Kauf) / `MinPrice` (Verkauf) als **Schutzgrenze**: Kurs schlechter →
Ablehnung „Kurs hat sich bewegt“, nie Ausführung zum alten Preis.

### 11.3 Trigger-Prüfung je Tick (genau die Kerze, die der Chart zeigt)
Prüfgrundlage = 1s-Kerze `(O, H, L, C)` + halber Spread `hs`:
| Order | Auslöser | Ausführungspreis |
|---|---|---|
| Kauf-Limit | `L + hs ≤ Limit` | `min(Limit, O + hs)` (Lücke nach unten → besser) |
| Verkauf-Limit / Gewinn-Ziel | `H − hs ≥ Limit` | `max(Limit, O − hs)` |
| Verlust-Stopp | `L − hs ≤ Stopp` | `min(Stopp, O − hs)` (Lücke → schlechter, Hinweis „Kurs ist durch deinen Stopp gefallen“) |
| Kauf-Stopp (Short-Eindeckung/Ausbruch) | `H + hs ≥ Stopp` | `max(Stopp, O + hs)` |
| Nachzieh-Stopp | wie Verlust-Stopp | Stopp-Nachführung **nach** der Prüfung mit dem H dieser Kerze (kein Blick in die Zukunft) |
**Pfad-Regel** bei SL und TP in derselben Kerze: steigende Kerze (C ≥ O) läuft `O→L→H→C`, fallende `O→H→L→C` (deterministisch,
dokumentiert). Keine Teilausführungen. Effizienz: je Instrument gecachte Schwellen `minBuyLimit`, `maxSellStop` usw. → nur
bei Überschreitung wird die Liste durchsucht (≤ 50 Orders × Spieler, trivial).

### 11.4 Laufzeit
„Bis Spieltag-Ende“ oder „24 h“ (Standard). Länger nicht (Offline-Abgleich §11.5 bleibt billig, Kinder vergessen keine
Uralt-Orders). Abgelaufen → Reservierung frei, Meldung.

### 11.5 Offline-Orders & Offline-Ereignisse (exakt wie online)
```lua
-- Beim Join, nachdem DataService die Session-Sperre hat. Läuft im Hintergrund, Depot-UI zeigt „Abgleich …“.
function OrderEngine.CatchUp(player: Player, d: Depot)
	local now = Clock.Tick()
	local from = math.max(d.LastTick + 1, now - 86400)
	Dividends.CreditRange(d, from, now)                 -- Ex-Tage im Zeitraum (Plan deterministisch)
	for inst, orders in groupByInstrument(d.Orders) do
		local cur = PriceEngine.NewCursor(inst, from)  -- eigene Field-Caches, sequentiell billig
		local t, budget = from, 0
		while t <= now do                              -- while statt for: Luau-for-Variable lässt sich nicht weitersetzen
			if Minute1Cache.CanSkip(inst, t, orders) then -- ganze Minute ohne Berührung der Schwellen überspringen
				t = Minute1Cache.EndOf(t) + 1
				cur:Seek(t)                            -- Kerze bei t braucht den Schluss von t − 1 (Seek rechnet ihn mit)
			else
				local o, h, l, c = cur:Candle(t)        -- dieselbe Funktion wie live
				OrderEngine.CheckCandle(d, inst, orders, t, o, h, l, c) -- Orders gelten erst ab Tick nach Erstellung
				t += 1
			end
			budget += 1
			if budget % 2000 == 0 then task.wait() end
		end
	end
	Bots.Replay(d, from, now)                          -- Bots entscheiden 1×/Minute, online wie offline gleich (§15)
	d.LastTick = now
end
```
Kosten: ≤ 86 400 Ticks × 14 Lerps je Instrument mit Orders; mit Minuten-Überspringen meist nur ein Bruchteil. Server-weiter
LRU-Cache für exakte 1m-Kerzen (gemeinsam für alle Spieler).

### 11.6 Grenzen je Lizenz (Startwerte, mit Tower-Ökonomie abstimmen)
| Lizenz | Instrumente | max. je Einzelwert (% Depot) | offene Orders | Gebühr | Positions-Obergrenze je Wert |
|---|---|---|---|---|---|
| Azubi I–III | 12 (Stabil/Normal) + AKX36 | 30 % | 5 | 0,10 % | LiquidityBase × 0,01 |
| Trader I–III | 24 + Sektor-ETFs + Themen-Körbe | 40 % | 15 | 0,08 % | × 0,2 |
| Fondsmanager I–III | alle 36 + IPOs + Short | 50 % | 30 | 0,05 % | × 5 |
| Börsen-Legende | alle + Tower-AGs | 60 % | 50 | 0,03 % | × 100 |
`LiquidityBase`: Stabil 5 Mio., Normal 2 Mio., Wild 0,5 Mio., ETF 20 Mio. AKY (Positionswert). Mindestgebühr 1 AKY.
Wirkung: Handelsgewinne wachsen nicht grenzenlos mit dem Vermögen (Zinseszins-Bremse) → späte Phase trägt der Tower; kleine
Konten können in der %-Liga mit großen mithalten. ETFs sind von der Klumpen-Grenze ausgenommen (Diversifikation lernen).

---

## 12. Depot-Mathematik

### 12.1 Datenmodell (DataStore, im Spieler-Profil)
```lua
Depot = {
	V = 1,                       -- Schema-Version
	Cash = 0,                    -- Cent, ganzzahlig
	Pos = { [instId] = { Q = 0, C = 0, R = 0 } },      -- Stück, Einstand gesamt inkl. Gebühren (Cent), realisiert (Cent)
	Short = { [instId] = { Q = 0, P = 0, M = 0 } },    -- Stück, Erlös (gesperrt), Sicherheitsleistung (gesperrt)
	Orders = { { Id, I, Side, Type, Q, Lim, Stp, Trl, Oco, Res, Exp, T0 } },  -- Res = reservierte Cent (exakt)
	Fills = {},                  -- Ring 100, kompakt { tick, inst, side, qty, px, fee, pnl }
	Nav = {},                    -- Ring 72 Spieltage: { day, navStart, navEnd, flow }
	Stats = { Trades, Wins, Losses, GrossWin, GrossLoss, PeakNav, MaxDD, WeekTwr, WeekDays, WeekTrades },
	LastTick = 0,                -- für Offline-Abgleich
}
```
Größe ≈ 6–10 KB JSON (Limit 4 MB).

### 12.2 Regeln für Zahlen
- Alle Geldwerte ganzzahlige **Cent**; Kurse ganzzahlige Cent; Stückzahlen ganzzahlig.
- `MaxQty(inst) = min(Lizenz-Grenze, floor(2^53 / (ask · 2)))` → `Q × Preis` immer exakt.
- **Rundung zugunsten des Hauses:** Kosten `ceil`, Erlöse `floor`, Gebühr `ceil`. Sofortiges Kaufen+Verkaufen ist immer ≤ 0.
- Einstand (`C`) beeinflusst nur die **Anzeige** von G/V, nie Geldflüsse → Rundungsrest im Einstand erzeugt kein Geld.

### 12.3 Kaufen / Verkaufen (Server, ohne Yield zwischen Prüfung und Buchung)
```lua
local function fee(gross: number, bps: number): number
	return math.max(MIN_FEE, math.ceil(gross * bps / 10000))
end

-- fromOrder: die ausführende Order (Limit/Stopp) – ihre eigene Reservierung zählt dann als verfügbar
function Portfolio.Buy(d: Depot, inst: number, qty: number, ask: number, bps: number, fromOrder: Order?)
	local gross = qty * ask
	local f = fee(gross, bps)
	local total = gross + f
	if d.Cash - Portfolio.Reserved(d, fromOrder) < total then return false, "Market.NoCash" end
	if Portfolio.WeightAfter(d, inst, gross) > Limits.MaxWeight(d) then return false, "Market.Concentration" end
	d.Cash -= total
	local p = d.Pos[inst] or { Q = 0, C = 0, R = 0 }
	p.Q += qty
	p.C += total                                    -- Einstand inkl. Gebühr
	d.Pos[inst] = p
	return true, { Px = ask, Q = qty, Fee = f }
end

function Portfolio.Sell(d: Depot, inst: number, qty: number, bid: number, bps: number, fromOrder: Order?)
	local p = d.Pos[inst]
	-- ReservedQty ohne die ausführende Order (und ohne ihren OCO-Partner), sonst blockiert sich ein Stopp selbst
	if not p or p.Q - Portfolio.ReservedQty(d, inst, fromOrder) < qty then return false, "Market.NoShares" end
	local gross = qty * bid
	local f = math.min(gross, fee(gross, bps))
	local net = gross - f
	local basis = if qty == p.Q then p.C else math.floor(p.C * (qty / p.Q) + 0.5) -- Verhältnis ≤ 1: keine Überläufe
	p.Q -= qty
	p.C -= basis
	p.R += net - basis
	d.Cash += net
	if p.Q == 0 then d.Pos[inst] = nil end
	return true, { Px = bid, Q = qty, Fee = f, Pnl = net - basis }
end
```
`Reserved(d, except)` = Summe `Res` offener Kauf-Orders (ohne `except`) (beim Platzieren: `Q·Limit + Gebühr`, Kauf-Stopp `Q·Stopp·1,05 + Gebühr`;
bei Ausführung wird die Differenz frei; reicht es bei einer Lücke nicht, wird die Menge auf das Bezahlbare gekürzt und gemeldet).
`ReservedQty` wie `broker.js` (OCO-Paar zählt einmal).

Anzeige: Ø-Einstand `C/Q`, unrealisierter G/V `Q·bid − C` (wahlweise minus geschätzte Verkaufsgebühr), G/V % = `/C`.

### 12.4 Leerverkauf (ab Fondsmanager, 1×)
Eröffnen: Erlös `Q·bid − Gebühr` → `Short.P` (gesperrt); zusätzlich 50 % des Positionswerts aus Cash → `Short.M`
(gesperrt, gesamt 150 %). Leihgebühr 0,05 % des Positionswerts je Spieltag (bei Spieltag-Ende). Automatischer Kauf-Stopp bei
Verlust = `Short.M` (**Zwangseindeckung**); springt ein Kurs darüber hinaus, ist der Verlust auf `Short.M` begrenzt (kein
negatives Konto; winziger Systemverlust, nur bei echten Lücken). Dividenden zahlt der Leerverkäufer.

### 12.5 Depotwert (NAV)
`NAV = Cash + Σ Q·bid + Σ (Short.P + Short.M − Q_s·ask)` (vorsichtig bewertet: Long zum Bid, Short zum Ask).
Client rechnet NAV/G/V für die Anzeige selbst aus Frame + Depot-Stand (keine Streams nötig); der Server rechnet NAV nur bei
Spieltag-Ende, Liga, Grenzen-Prüfung.

### 12.6 Rendite, Liga, Skill-Score
- **Spieltag-Rendite** (Modified Dietz, Einzahlungen aus der Bau-Kasse/Auszahlungen in den Tower = `F`):
  `r = (NAV_end − NAV_start − F) / (NAV_start + 0,5·F)`; zählt nur bei `NAV_start ≥ 1000 AKY`.
- **Wochen-Rendite (TWR)** `= Π(1 + r_d) − 1` → unabhängig von Kontogröße und Einzahlungen (Robux-/Alt-sicher).
- **Wochen-Liga:** Rang nach TWR, Teilnahme ab **20 Trades und 6 aktiven Spieltagen** (ein Glückstreffer reicht nicht).
- **Skill-Score 0–1000:** `400·tanh(Sharpe/1,5) + 300·(positive Tage / Tage) + 300·(1 − min(1, MaxDD/20 %))`, Sharpe =
  Mittel/Std der Spieltag-Renditen (Std-Untergrenze 0,5 %, ≥ 6 Tage). Tie-Breaker der Liga, eigene Bestenliste.
- **Turnier-Depot** (optional, Live-Events wie Crash-Freitag): alle starten mit 100 000 AKY, keine Einzahlungen.
- **Admin-Fairness:** Während eines Admin-Markt-Events (Ankündigung bis +10 min nach Abklingen) zählen Spieltage nicht für
  Liga/Skill (Markierung „Admin-Abuse aktiv – zählt nicht für die Liga“). Trades des Besitzers sind markiert.

---

## 13. Anti-Exploit

| # | Angriff | Abwehr |
|---|---|---|
| 1 | Client schickt Kurs/Preis | Client schickt nur Absicht (Instrument, Seite, Menge, Typ, Limit). Ausführung immer zum Server-Kurs. |
| 2 | Latenz-/Alter-Kurs-Arbitrage | Ausführung zum zuletzt **gesendeten** Tick; Zukunft unbekannt; `MaxPrice`/`MinPrice` nur als Schutz, nie Verbesserung. |
| 3 | Server-Hopping | globaler deterministischer Kurs, Events im selben Tick, Halts bei Verspätung, Session-Sperre. |
| 4 | Doppelte Anfragen / Retries | `ClientSeq`-Dedupe (letzte 32), gleiche Antwort. |
| 5 | Race (zwei Orders gleichzeitig) | Prüfung + Buchung synchron ohne Yield, ein Depot-Objekt je Spieler (PlayerStateService). |
| 6 | Cent-Rundungs-Schleifen | ganzzahlige Cent, Rundung zugunsten des Hauses, Mindestgebühr. |
| 7 | Dividenden-Mitnahme | Kurs fällt im Ex-Tick um die Dividende; Bestand im Ex-Tick zählt. |
| 8 | Offline-„Zeitreise“ | Orders gelten erst ab dem Tick nach Erstellung, Erstellungs-Tick setzt der Server, offline keine Änderungen, gleiche Kursfunktion. |
| 9 | Rollback nach Verlust (Server crashen) | Session-Sperre, Speichern bei Verlassen + alle 60 s + nach großen Trades (Budget-geschützt); Spieler kann keinen Server crashen. |
| 10 | Spam-Klicken / Bots per Makro | Token-Buckets (unten), Gebühren, Spread, NOVA-Warnung nach 10 Verlust-Trades in 2 min. |
| 11 | Leerverkauf ins Minus | Sicherheitsleistung, Zwangseindeckung, Verlust gedeckelt. |
| 12 | Überläufe/Präzision | `Q × Preis < 2^53` erzwungen, Clamps beim Kodieren (wie `Net.luau`: nie Fehler, auch bei NaN). |
| 13 | Gefälschte Remotes | nur C→S validiert; Honeypot-Remote (wie `GrantCoins` im Shooter) → AntiCheat-Flag. |
| 14 | Alt-Accounts schieben Geld | kein P2P-Geld, Tower-AG nur gegen System (§16), Liga in %. |
| 15 | Admin-Event-Wissen (Freunde des Besitzers) | globale Ankündigung mit 10 s Vorlauf für alle, Liga pausiert, Admin-Log. |
| 16 | IPO-Zeichnung in letzter Sekunde stornieren | Storno nur bis `T0−30 s`, Betrag bis Zuteilung gesperrt. |
| 17 | Fehler in der Engine (Geld aus dem Nichts) | **Fill-Audit:** jeder Fill wird mit `PriceAt(inst, tick)` nachgerechnet (muss exakt passen), Tages-G/V-Ausreißer (z > 6 vs. Skill-Score) → Admin-Panel „verdächtig“, keine Auto-Strafe. |
| 18 | Uhr-Manipulation | nur Server-Uhr; Client-Zeit nur für Countdowns. |

Token-Buckets je Spieler:
| Aktion | Kapazität | Nachfüllen | Überschreitung |
|---|---|---|---|
| `Market.Place` | 6 | 1,5/s | „Etwas langsamer, bitte“ + AntiCheat-Zähler (> 50/min → Flag) |
| `Market.Cancel/Modify` | 10 | 3/s | dto. |
| `Market.Candles` | 6 | 2/s | Cache-Antwort oder Fehler |
| `Market.Profile/Calendar` | 6 | 1/s | dto. |
| Admin-Markt | 1 | 1 je 3 s | Cooldown-Hinweis |

---

## 14. Einfach für Kinder (10–15), tief für Profis

### 14.1 Drei Schichten (wachsen mit der Lizenz)
| Schicht | Ansicht | Hilfen |
|---|---|---|
| **Einfach** (Azubi) | Firmen-Karten (Logo, Kurs, Trend-Pfeil, Stimmung), Linien-Chart, Kauf-Buttons mit Betrags-Knöpfen 10/25/50 %, „Schutz an“ automatisch | **NOVA-Ampel** zeigt bei Fakten-News nach 20 s die Richtung (bei Gerüchten/„wie erwartet“ ein „?“ mit Erklärung), Glossar-Tipps, Risiko-Hinweise („Du hast 80 % in einer Aktie – verteile lieber!“) |
| **Trader** | Kerzen, alle Zeitrahmen, SMA/EMA, Limit/OCO/Trailing, Termin-Kalender, Sektor-Heatmap, Themen-Körbe | Ampel optional, Academy-Lektionen zur Makro-Matrix |
| **Profi** (Fondsmanager/Legende) | RSI, MACD, Bollinger, VWAP, Stochastik, ATR, Markttiefe, Fundamentaldaten, Analysten-Trefferquoten, Korrelation, Performance-Analyse (TWR, Drawdown, Skill-Score), Leerverkauf, Multi-Chart | keine Ampel (eigener Skill), Wenn-Dann-Bots |

### 14.2 Text-Regeln für UI/News
Sätze ≤ 12 Wörter, ein Begriff pro Bildschirm, jede Fachwort-Erklärung in einem Satz („Stop-Loss: verkauft automatisch, wenn
der Kurs zu tief fällt.“), Zahlen immer mit Vorzeichen und Farbe (grün `#22c55e` / rot `#ef4444`), Beträge abgekürzt
(Tsd./Mio./Mrd. bzw. K/M/B), DE- und EN-Formatierung über `Lang`.

### 14.3 Lizenz-Prüfungen (Academy-Aufgaben, Beispiele)
Azubi → Trader: „Kaufe nach einer guten Nachricht“, „Setze ein Schutz-Paar“, „Verteile auf 3 Sektoren“, „Erkenne eine
‚wie erwartet‘-Meldung“. Trader → Fondsmanager: „Überstehe einen Crash mit < 10 % Verlust“, „Nutze einen ★★★-Analysten bei
Quartalszahlen“, „Skill-Score ≥ 500 in einer Woche“. Fondsmanager → Legende: „Wochen-Liga Top 10 %“, „Leerverkauf mit Gewinn
bei negativem Makro“, „Max. Drawdown < 8 % bei TWR > 20 %“.

### 14.4 Kein Pleite-Frust
Fällt das Depot unter 1000 AKY ohne Positionen, kommt täglich ein **Gehalt aus dem Tower** (Tower-Einnahmen laufen immer)
plus NOVA-Tipp. Kein Spieler bleibt dauerhaft handlungsunfähig.

---

## 15. Tower-Anbindung (Idle-Einnahmen, Bots)

- **Idle-Einnahmen** gehören der Tower-Ökonomie (Haupt-Design): deterministisch (Etagen × Rate × Boni), Gutschrift in die
  **Bau-Kasse**; Server sammelt je Spieler 1×/s, sendet 1×/5 s. Offline-Einnahmen mit Obergrenze laut Haupt-Design.
- **Geldfluss:** Depot ↔ Bau-Kasse frei (Kern-Schleife „Gewinne in den Tower stecken“ / „Tower-Einnahmen investieren“);
  Einzahlungen ins Depot zählen in der Liga als Fluss `F` (§12.6). Robux-Geldpakete (falls es sie gibt) nie ins Depot.
- **Bots/Mitarbeiter im Tower (Markt-Schnittstelle):**
  - **Strategie-Bots** (aus den Autopilot-Presets der Website): Regel sichtbar (z. B. „Trend: kauft wenn SMA20 > SMA50“,
    „Dividende: hält Zahler“, „Sparplan: kauft ETF je Spieltag“, „Wenn-Dann: kaufe 10 NOVA unter 200“), max. 30 % des Depots,
    Lohn je Spieltag. Bots handeln über **dieselbe** `OrderEngine` (gleiche Limits, Flag „Bot“) und entscheiden **1× je
    Minute auf 1m-Schlusskursen** → online und offline identisch (Offline-Replay max. 12 h, Ergebnis „Während du weg warst,
    hat dein Trend-Bot +3,2 % gemacht“).
  - **Research-Team:** Upgrades verbessern Hinweise (z. B. Quartals-Tendenz 5 statt 2 min vorher, Gerüchte-Sterne früher),
    nur durch Tower-Fortschritt, **nicht** mit Robux.
  - **Risiko-Manager:** setzt Standard-Schutz-Paare, warnt vor Klumpen.
- Synergie für „ultra bockt“: Tower-Fortschritt ↔ bessere Werkzeuge ↔ mehr Rendite ↔ größerer Tower.

---

## 16. Spieler-Firmen: „Tower-AG“ (machbar? Risiken?)

### 16.1 Warum keine echten Spieler-Aktien zwischen Spielern
Freier Handel mit Spieler-Anteilen hätte: Pump & Dump mit Alt-Accounts, Betrug („investier in meine Firma“) gegen Jüngere,
Geldschiebe-Kanal zwischen Konten, dünne Märkte ohne Liquidität, serverübergreifende Konsistenz-Probleme,
Text-Moderation für Firmennamen und – falls Spielgeld mit Robux zusammenhängt – Nähe zu **„Paid Item Trading“**. Nicht machbar
im Sinne von fair + sicher.

### 16.2 Empfohlen (Phase 2): Tower-AG mit Formel-Kurs
- **Börsengang** des eigenen Towers ab Stufe „Wolkenkratzer“ (großer Flex-Moment: Glocke im Börsensaal, Server-Meldung).
- **Kurs = Formel** aus Tower-Kennzahlen, nicht aus Handel:
  `Wert = (Einnahmen/h × 20 + Ausbauwert × 0,3) × Prestige-Faktor`, 1 000 000 Anteile, Kurs = Wert / Anteile,
  EMA-geglättet (Halbwertszeit 30 min), max. ±15 % je Spieltag, −2 % je Spieltag bei > 3 Tagen Inaktivität des Eigentümers.
- **System ist Gegenpartei:** Kaufen/Verkaufen nur zum **5-min-Fixing** (Einheitskurs wie bei illiquiden Aktien) → keine
  Latenz- oder Insider-Arbitrage (z. B. kurz vor einem großen Etagen-Kauf).
- **Eigentümer verkauft keine Anteile**, Investoren-Geld geht **nicht** an den Eigentümer (kein Geldschiebe-Kanal).
- Eigentümer erhält **+0,5 % Tower-Einnahmen je investiertem Freund, max. +10 %** (Investor braucht Lizenz Trader + 2 h
  Spielzeit + Mindestbetrag) → Freunde einladen lohnt sich (Reichweite), Alt-Farming gedeckelt.
- Max. 5 % des Investoren-Depots je Tower-AG, max. 20 Tower-AGs je Spieler. Keine Dividenden (Rendite nur über
  Wertzuwachs → kein Gelddrucken).
- **Name:** Tower-Name aus Bausteinen (Adjektiv + Nomen + „AG“) oder Freitext nur nach `TextService:FilterStringAsync` +
  `GetNonChatStringForBroadcastAsync`.
- **Daten:** Bewertung autoritativ im DataStore des Eigentümers (beim Speichern), heißer Cache im MemoryStore-HashMap nur für
  **online** Eigentümer (Ablauf 10 min); Investoren-Server lesen mit 60-s-Cache. Offline-Eigentümer: Kurs aus letztem
  gespeicherten Wert + deterministischer Inaktivitäts-Abschlag.
- Bestenliste „Wertvollste Tower-AG“, Ansicht „Meine Investoren“.

---

## 17. Admin-Markt-Kontrolle (nur Besitzer)

| Aktion | Parameter (geklemmt) | Wirkung |
|---|---|---|
| Crash / Rallye | Umfang (alle/Sektor/Wert), Stärke ±5…50 %, Dauer 30–300 s, Abklingen 5–60 min | Event mit Rampe, immer global, klingt zum Modellkurs zurück |
| Firma pushen / abstürzen | Wert, ±5…50 % | dto. |
| Insider-News veröffentlichen | Text DE/EN (gefiltert), Wert/Sektor, Wirkung ±%, Lesefenster | erscheint als News „Admin-Eilmeldung“ |
| Markt/Wert pausieren | Dauer 10 s … 10 min | Halt, Orders/Trigger ruhen, Banner |
| IPO starten | Vorlage aus Pipeline | Zeichnung 10 min ab jetzt |
| Volatilität | ×0,5 … ×3, Dauer ≤ 30 min | `R(t)`-Boost mit 30-s-Rampe |
| Normalisieren | alle Admin-Events | Rückkehr zum Modellkurs über 60 s |
Alle Aktionen: Owner-Check (`game.CreatorId`, Studio zählt), Cooldown 3 s, globale Ansage (Avatar + blauer Haken, ohne
Kasten – wie in den anderen Spielen), Eintrag im Admin-Log, Liga-Pause (§12.6). Statistik-Ansicht: Geldmenge in Depots,
beliebteste Werte, Fills/min, verdächtige Fill-Audits, Bus-Status (MemoryStore/Messaging erreichbar?).

---

## 18. Module, APIs, Server-Schleife, Budgets

### 18.1 Dateien (Rojo-Struktur wie im Shooter)
```
src/server/Market/
  MarketClock.luau      Tick(), DayIndex(t), WeekIndex(t), WeekStart(w)
  MarketSeed.luau       Load(w): seed (DataStore + Fallback), EnsureNext(), LoadClose(w)
  Noise.luau            NewField, FieldAt, White, Hash (§5.2)
  PriceEngine.luau      Start(), Quote(i) -> bid, ask, mid; Candle1s(i); PriceAt(i, t); NewCursor(i, t0)
  EventDirector.luau    BuildDay(d), Offset(i, t), NewsActive(i, t), Calendar(n), AddExternal(ev)
  GlobalBus.luau        Start() (Subscribe + 5-s-Poll), Publish(ev) -> ok, err
  CandleStore.luau      Push(tick), Get(i, tf, count) -> buffer (gecacht), Backfill()
  OrderEngine.luau      Place/Cancel/Modify(player, args) -> Reply; ProcessTick(tick); CatchUp(player, d)
  Portfolio.luau        Buy, Sell, Short, Cover, Reserved, ReservedQty, Nav (Server-Wahrheit)
  QuoteStream.luau      Broadcast(tick)
  Dividends.luau        ExTick(i, d), CreditRange(depot, from, to)
  MarketAdmin.luau      Aktionen §17 (von AdminService aufgerufen)
  MarketAudit.luau      VerifyFill(fill) -> boolean, Stats()
  TowerAG.luau          (Phase 2)
src/shared/Market/
  QuoteCodec.luau       EncodeFrame/DecodeFrame, EncodeCandles/DecodeCandles
  PortfolioMath.luau    Fee, BuyCost, SellProceeds, Basis, Pnl, Twr, SkillScore (pure Funktionen, Client-Vorschau)
  Indicators.luau       Port von js/indicators.js
src/shared/Config/Market.luau   Instrumente, Sektoren, Klassen, Bänder, Matrix, News-Schlüssel, Grenzen, alle Stellschrauben
src/shared/Lang/*               Market.* Texte DE/EN (News-Vorlagen, Glossar, Fehler)
src/client/Modules/Market/      MarketClient, ChartView, TradePanel, NewsFeed, Calendar, DepotView, Heatmap, TickerWall
```
`Noise`, `PriceEngine`, `EventDirector`, `MarketSeed` liegen **nur** im Server (ServerScriptService). Neue Remotes und
Request-Aktionen in `scripts/contract_check.py` eintragen (gleiches Werkzeug wie im Shooter).

### 18.2 Server-Schleife (1 Hz)
```lua
-- Markt.server: ein Job im Scheduler. Holt verpasste Ticks nach (Hänger), max. 10 je Durchlauf.
Scheduler.Every("Market", 1, function()
	local target = MarketClock.Tick()
	if target - lastTick > 60 then -- Server stand still: auf jetzt springen, Kerzen-Cache neu rechnen
		CandleStore.Rebuild(target); lastTick = target - 1
	end
	local steps = 0
	while lastTick < target and steps < 10 do
		local t = lastTick + 1
		EventDirector.Advance(t)        -- 1) News mit t_a == t senden, Events aktivieren, Bus-Events einplanen
		PriceEngine.Step(t)             -- 2) mid/bid/ask + 1s-Kerze für alle Instrumente (ETFs zuletzt)
		OrderEngine.ProcessTick(t)      -- 3) Trigger gegen die Kerze, Ex-Tag-Dividenden, Zwangseindeckungen
		CandleStore.Push(t)             -- 4) Ringe 1s/5s/1m
		if t % 1200 == 0 then DayClose.Run(t) end -- 5) Glocke, NAV, Liga, Leihgebühren, Tagesrückblick
		lastTick = t; steps += 1
	end
	QuoteStream.Broadcast(lastTick)     -- 6) ein Frame (immer der neueste Tick)
end)
```

### 18.3 Budgets
| Posten | Budget |
|---|---|
| Server-Tick gesamt | < 0,3 ms (Preis < 0,1 · Trigger < 0,05 · Kerzen < 0,02 · Kodierung < 0,05) |
| Backfill beim Start | ~0,5–1 s CPU verteilt auf ~10 s (≤ 2 ms/Frame) |
| Offline-Abgleich je Join | meist < 50 ms, max. ~0,4 s verteilt (Hintergrund) |
| Server-Speicher | Kerzen ~0,7 MB, Event-Plan ~2 MB, Orders/Depots je Spieler ~10 KB |
| Bandbreite | §10.3 |
| Client-Chart | < 0,3 ms/Frame am Handy, ≤ 900 GuiObjects im Pool |

---

## 19. Tests & Akzeptanz

Server-Selbsttests (wie `SelfTestService` im Shooter) + Python-Referenz:
1. **Determinismus:** zwei unabhängige `PriceEngine`-Instanzen mit gleichem Seed → identische Cent-Kurse für 10 000 Ticks;
   Random-Access `PriceAt` == sequentieller Live-Kurs.
2. **Referenz-Gleichheit:** Luau-`hash4`/`uni` == Python-Referenz. Die 16-Bit-Split-Multiplikation wurde gegen die volle
   32-Bit-Multiplikation geprüft (200 000 Zufallswerte, identisch, Zwischenwerte < 2^53). Feste Testvektoren
   (`hash4(seed, fid, k, n)` → `uni`):
   | seed, fid, k, n | hash4 | uni |
   |---|---|---|
   | 123456, 1, 0, 0 | 3076564673 | 0.432637066114694 |
   | 123456, 1, 0, 1 | 1222392628 | −0.430779075250030 |
   | 123456, 1, 13, 7 | 3917177298 | 0.824077823199332 |
   | 987654321, 104, 5, 123456789 | 4043101596 | 0.882715893909335 |
   | 2147483647, 9, 9001, 86399 | 2536699204 | 0.181242616847157 |
3. **Kerzen:** 1m aus 1s aggregiert == 1m aus dem Ring; Frame-Größe = 9 + 10·n ≤ 900 Byte.
4. **Depot-Invarianten:** Kaufen+sofort-Verkaufen ≤ 0; Cash nie negativ; Summe Fills == Cash-Änderung; OCO storniert Gegenseite;
   Reservierungen nach Storno = 0; `Q × Preis` nie > 2^53.
5. **Trigger:** Lücken-Fälle, Pfad-Regel, Nachzieh-Stopp ohne Blick in die Zukunft, Offline-Abgleich == Online-Ergebnis für
   denselben Zeitraum (gleiche Fills, gleiche Ticks).
6. **Skill-Gate (Balancing):** über 50 Spieltage: Zufall ≤ +0,2 %/Spieltag, Spam < −2 %, Ampel ≥ +0,5 %, Smart ≥ +1,5 %,
   Anteil positiver Tage Smart ≥ 75 %, Zufall ≤ 55 %.
7. **Global:** zwei Server (Studio-Team-Test bzw. Live-Test mit 2 Servern) → Admin-Crash wirkt im selben Tick; verlorene
   Messaging-Nachricht wird per Poll nachgeholt (Test: Messaging aus).
8. **Last:** 50 Bots × 1,5 Orders/s → Tick < 1 ms; 50 Historien-Anfragen in 1 s → aus Cache.
9. **Compliance-Check (manuell, vor Release):** Wortliste §1.2 in allen Lang-Dateien automatisch suchen (Skript), keine
   Casino-Deko in der Welt, Robux-Produkte gegen §1.4 prüfen, Namen/Kürzel gegen echte Firmen prüfen.
10. **Studio Solo & „Test → 2 Players“:** Markt läuft mit Fallback-Seed, Orders/Charts/News funktionieren, beide Clients sehen
    identische Kurse.

---

## 20. Offene Punkte / Risiken
- **Live-Wortlaut der Roblox-Regeln** konnte hier nicht direkt geladen werden (Netzwerk-Sperre) → Besitzer prüft Fragebogen
  und Community Standards beim Veröffentlichen; bei Unsicherheit Roblox-Support fragen und Antwort ablegen.
- Restrisiko „Börse = Glücksspiel?“ bei Moderatoren: durch §1.2 minimiert; Spielbeschreibung betont „Lernen, wie Börse
  funktioniert – mit Spielgeld, ohne Glücksspiel“, keine Gewinn-Versprechen in Thumbnails/Texten.
- Balancing Handel ↔ Tower-Ökonomie (Positions-Grenzen, Gebühren, News-Takt) gemeinsam mit dem Ökonomie-Design festlegen;
  `tools/market_calibrate.py` nach jeder Änderung.
- Luau-Laufzeiten sind Schätzungen → im Studio mit `Scheduler.Stats()` messen; bei Bedarf `--!native` für `Noise.luau`.
- Tower-AG erst nach stabilem Kernspiel (Phase 2).

---

## Quellen
- Roblox Community Standards (Glücksspiel): https://about.roblox.com/community-standards (Auszüge via Suche; auch
  https://en.help.roblox.com/hc/en-us/articles/203313410-Roblox-Rules-of-Conduct)
- Content Maturity: https://create.roblox.com/docs/production/promotion/content-maturity und
  https://en.help.roblox.com/hc/articles/8862768451604 (Content Maturity Labels)
- Experience Guidelines (ältere Fassung): https://create.roblox.com/docs/production/promotion/experience-guidelines
- Paid Random Items / PolicyService: https://create.roblox.com/docs/production/monetization/paid-random-items
- Experience Notifications (13+): https://create.roblox.com/docs/production/promotion/experience-notifications
- MessagingService-Limits: https://create.roblox.com/docs/reference/engine/classes/MessagingService ·
  https://create.roblox.com/docs/cloud/guides/usage-messaging
- MemoryStore-Limits: https://create.roblox.com/docs/cloud-services/memory-stores
- UnreliableRemoteEvent (900 Byte): https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent
- Roblox-Statement zu Glücksspiel (Presse): https://igamingexpert.com/news/games/bloxflip-return-roblox/
- DevForum-Diskussionen (Anekdoten, keine Regeln): https://devforum.roblox.com/t/free-to-play-slot-machines-allowed/3909513 ·
  https://devforum.roblox.com/t/creating-the-roblox-stock-exchange-would-this-be-allowed/1456324 ·
  https://devforum.roblox.com/t/why-does-gambling-making-the-experience-13/2638369
- AKYTEX-Website: `js/market.js`, `js/broker.js`, `js/ailab.js`, `js/indicators.js`, `js/chart.js`, `js/data.js`, `README.md`
