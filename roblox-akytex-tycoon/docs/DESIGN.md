# AKYTEX TYCOON – Finales Design & Umsetzungs-Spec (v1)

> **Status:** verbindlich für alle Coding-Agents (Stand 2026-10-13). Diese Datei ersetzt die drei Entwürfe
> (#1 „Fun · Addictive · BIG“, #2 „Business & Brand“, #3 „Two Worlds, One Bridge / robust“).
> **Basis = Entwurf #1** (Spielgefühl, lebendige Stadt, Rhythmen, Gänsehaut-Momente, Lizenz-Tore „Trading schaltet die
> Skyline frei“). **Gepfropft aus #3:** Robux-Firewall im Code (Modulgrenzen, Depot-Schreibtrichter, Vertrags-Prüfung,
> SelfTest), Basis-/Hochwassermarken-Brücke, Tutorial-Übungsaktie, Fahrzeug-Kollisionsgruppen, Anti-Alt-Bremsen,
> absolute Liga-Stufen, Arbeitspakete. **Gepfropft aus #2:** Marken-Regeln (keine handelbare AKYTEX-Aktie, kein NOVA, kein
> „PRO“), Ruf, Know-how, automatischer Live-Ops-Kalender mit Samstags-Show-Ersatz, Glocken-Moment, Firmen-Läden in der Stadt,
> ehrliche Pass-Rechnung, UWG-Wortregeln. **Alle Must-Fix-Punkte beider Jurys sind eingearbeitet** (Abdeckungsliste Anhang Z).
> Die Tower-Ökonomie ist mit `tools/economy_sim.py` durchgerechnet (§B5.4, §B9.10) – keine Zahl in diesem Dokument ist geraten.
>
> **Begleitdokumente (bleiben, werden referenziert):**
> - `docs/MARKET.md` – Markt-Engine (Preis-Modell, News, Orders, Depot, Netzwerk). **Verbindlich**, mit den Änderungen aus §C19
>   (dort auch am Dateianfang vermerkt).
> - `docs/REUSE.md` – was aus CLUTCH CLASH (CC, `/home/user/website-test-demo-1/roblox-shooter`) kopiert/angepasst wird, APIs,
>   UI-Kit, Runde-2-Fixes, AKYTEX-Marken-Blatt. **Verbindlich.**
> - `docs/BESITZER-WUENSCHE.md` – Wünsche 1–17 des Besitzers (Abdeckung §A6 + Anhang Z).
> - CC-Dateien `roblox-shooter/docs/ASSETS.md` (einzige erlaubte `rbxasset://`-Pfade) und `roblox-shooter/docs/STYLE-AKYTEX.md`
>   (Look; wird nach `docs/STYLE-AKYTEX.md` kopiert und erweitert, WP12).
> - `tools/market_calibrate.py` (Preis-Modell-Referenz + Backtest, WP3) und `tools/economy_sim.py` (Tower-Ökonomie, WP6).
>
> **Sprache:** Spec Deutsch, Code-Bezeichner Englisch, **Code-Kommentare Deutsch**. Alle Zahlen sind Startwerte und stehen 1:1
> in `Config` (änderbar ohne Code). Alle Spielertexte DE + EN über `Lang`.

---

## 0. Muss-Regeln (gelten für jedes Arbeitspaket)

1. **Keine Pflicht-Assets (Hybrid-Architektur, Wunsch 17).** Alles funktioniert und sieht gut aus **ohne** hochgeladene Assets:
   Parts/`Part.Shape`/WedgePart/CornerWedgePart/TrussPart/SpecialMesh (MeshType Sphere/Cylinder/Wedge/Brick), Beams, Trails,
   ParticleEmitter (Texturen nur aus `ASSETS.md` §3/§4), Terrain-Wasser, SurfaceGui/BillboardGui/UI-Frames, Path2D (wenn in
   Studio verifiziert). Sounds **nur** die 9 nutzbaren eingebauten Dateien aus `ASSETS.md` §2 über die CC-Rezept-Engine
   (`Sfx`). **Nie** `swordslash.wav`, `electronicpingshort.wav`, `uuhhh.mp3`. Jedes sichtbare Objekt mit Upgrade-Potenzial hat
   in `Config` einen optionalen Asset-Platz (`Asset = { MeshId = 0, TextureId = 0, Scale = 1, Offset = CFrame.identity }`,
   `ImageId = 0`, `SoundId = 0`); **0 = Code-Rezept**, Ladefehler → automatisch Code-Rezept (§C14.3, `Shared/AssetSlot`).
2. **Keine eigenen Animationen.** Roboter, Fahrstuhl, Kräne, Bulle/Bär, Uhrzeiger: prozedurale CFrame-/Tween-Bewegung im
   einen Client-`PreRender`-Loop. Avatare: nur Roblox-Standard (Emotes `wave/cheer/point/dance` über `Humanoid:PlayEmote`).
3. **Server ist Autorität** für Kurse, Fills, Depot, Credits, Einkommen, Bau, Belohnungen, Besitz, Events. Client sendet nur Absichten.
4. **Zwei Welten, eine Brücke (Robux-Firewall, Kern der Compliance – §0.4).** Börsengeld **AKY** (Depot) und Turmgeld **CR**
   (Credits) sind getrennt. Geld fließt nur **AKY → CR** (Gewinn-Transfer). Nichts, was Robux kaufen, beschleunigen oder
   multiplizieren kann, erreicht jemals AKY, Orders, Strategie-Bots, Lizenz, Trader-XP, Know-how, Ruf oder Marktinformation.
   Durchgesetzt durch Modulgrenzen, Vertrags-Prüfer (`FIREWALL`) und SelfTest (§C11.4).
5. **Kein Glücksspiel, auch nicht simuliert (§0.3).** Kein Einsatz-/Auszahlungs-Format, kein Hebel, keine Optionen/Binär-/
   Up-Down-Kontrakte, keine Krypto, kein Casino-Bild/-Wort/-Sound, keine Zufalls-Kisten/-Räder. Markt = Information + Skill
   (Backtest MARKET.md §7).
6. **Keine bezahlten Zufallsitems, kein Handel zwischen Spielern.** `Config.Shop.RandomItemsEnabled = false` (SelfTest).
   Freie Zufälle (z. B. Tagesquest-Auswahl) sind erlaubt, aber nie mit Robux/CR verknüpft. Keine Übertragung von AKY, CR,
   Aktien oder Items zwischen Spielern.
7. **Alles fiktiv; AKYTEX nur als eigene Spielmarke (§0.5).** Keine echten Firmen/Kürzel/Indizes/Personen/Krypto, keine URL,
   kein QR-Code, kein Hinweis auf echte AKYTEX-App/Website/Tarife/Broker/„echtes Trading“. **Keine handelbare AKYTEX-Aktie,
   kein NOVA im Spiel, kein „PRO“-Abo.** Der Spiel-Guide heißt **Tiko** (geskripteter Ticker-Roboter) – **nicht „Aky“**
   (so heißt der echte KI-Assistent der Website).
8. **Wortliste (§0.7)** gilt für alle Spielertexte; der Vertrags-Prüfer scannt sie (`BANNED_WORDS`, phrasenbasiert mit Allowlist).
9. **Ganzzahl-Geld & Grenzen.** AKY in **ganzzahligen Cent**, CR **ganzzahlig**. Kein Kontostand, Preis oder Bestenlisten-Wert
   ≥ 9e15 (`MAX_MONEY = 9e15`, Anzeige „MAX“); nie Ganzzahl-Arithmetik über 2^53; `Q × Preis < 2^53` erzwungen;
   `Config.Validate()` prüft jeden Preis/jede Kurve (teuerster Einzelpreis laut Sim 4,9e13).
10. **Remote-Hygiene** genau in dieser Reihenfolge: `p.Parent == Players` → globales Limit → Aktions-Limit (Token-Bucket) →
    `typeof`/exakte Schlüssel → `Util.IsFinite`/NaN → Clamps → Ready-Gate → `pcall(handler)` → Antwort `{Ok, Message?, …}`.
    Nie `InvokeClient`. Sequenz-/Nonce-Fenster rücken **auch bei Ablehnung** vor (CC Runde-2, kritisch).
11. **Gebundene Schleifen:** ein Server-`Scheduler` (CC 1:1), keine `while`-Schleife pro Spieler, jede Sammlung mit
    Obergrenze, jede Pro-Spieler-Tabelle bei `PlayerRemoving` leeren, Callbacks yielden nie (Yield-Arbeit in `task.spawn`).
12. **Moderne APIs:** `*Async`-Varianten (`GetProductInfoAsync`, `UserOwnsGamePassAsync`, `AwardBadgeAsync`,
    `CreateHumanoidModelFromUserIdAsync`/`…FromDescriptionAsync`, `GetGroupInfoAsync`, `IsInGroupAsync`), `RunService.PreRender`,
    `task.*`, `RaycastParams.IncludeInstances/ExcludeInstances`, `workspace:RegisterCollisionGroup`. Kein `wait/spawn/delay`,
    kein `BodyVelocity`.
13. **Minimal-Label-Inhalte:** keine Gewalt (Fahrzeuge kollidieren nie mit Figuren), kein Blut, keine Angst-Inhalte, kein
    Alkohol (Raum heißt „Smoothie-Café“, nie „Bar“), keine Erwachsenen-Orte (kein Club/Nachtclub/Hotelzimmer), keine
    Glücksspiel-Darstellung (auch nicht als Deko).
14. **Nur der Besitzer ist Admin** (§B15.1). Niemand kann Admin kaufen. Studio: Player1 (−1) Admin, **Player2 (−2) nie**.
15. **Studio-Solo voll spielbar, „Test → 2 Players“ funktioniert** (Markt mit Fallback-Seed, Bus lokal, Käufe simuliert).
16. **StreamingEnabled = true:** jeder Client-Zugriff auf Welt-Teile mit `WaitForChild(name, timeout)` und nil-sicher;
    eigene Plot-/Tower-Modelle `PersistentPerPlayer`, Wahrzeichen `Persistent` (§C1.2).
17. **Ehrliche Monetarisierung:** max. **1** Angebots-Popup pro Sitzung, **nie** in der ersten Sitzung, nie während Tutorial,
    Crash/Rally-Warnung, offenem Order-Ticket, Willkommen-zurück-Bericht oder Admin-Abuse-Countdown. Knöpfe „Ansehen“,
    „Details“, „Preis anzeigen“ – nie „JETZT KAUFEN“, „LETZTE CHANCE“, „Nur heute!“ (UWG Anhang Nr. 28). Echte Rabatte, echte
    Countdowns (feste Enddaten, kein Neustart). Robux-Artikel nie mit „Rendite“, „ROI“, „investieren“, „Gewinn“.
18. **Kein Prahlen mit Einzel-Trades.** Server-Meldungen nur für Tower-Stufen, Lizenzen, Börsengang, Liga-Stufen, Titel.
    G/V einzelner Trades ist privat; Verluste werden nie öffentlich gezeigt.
19. **Fremde Dateien nicht anfassen** (Abschnitt D). Andere Services nur zur Laufzeit über `Services.X` (Server) bzw.
    `ctx.Modules.X` (Client), optionale Dienste über `pcall`. Verträge (Abschnitt C) nicht eigenmächtig ändern.
20. **Keine Drittanbieter-HTTP-Aufrufe**, keine fremden Werbe-/Analytics-Server (Advertising Standards). `HttpService` nur
    später für Open-Cloud-Benachrichtigungen mit Schlüssel aus `HttpService:GetSecret` (v1.1, §B11.9).

### 0.1 Begriffe
| Begriff | Bedeutung |
|---|---|
| **AKY** | Börsengeld (fiktiv). Nur im **Depot**, nur für den Markt. Symbol: blaue Münze mit „Λ“, Farbe Accent `#4f8cff`. Intern Cent. |
| **CR (Credits)** | Turmgeld. Für Etagen, Abteilungen, Personal, Effizienz, Deko, Autos, Uhren. Symbol: grüner Sechskant-Chip, Farbe Up `#22c55e`. Ganzzahlig, max. 9e15. **Robux-Produkte geben nur CR, nie AKY.** Kein €/$-Zeichen. |
| **Depot** | AKY-Konto: freies Geld (`Cash`), Positionen, Orders, Alarme, Watchlists, Strategie-Bots. Einziger Schreiber: `OrderService`/`Portfolio`. |
| **Basis** | Lizenz-abhängiges Grundkapital im Depot (25.000 … 60 Mio. AKY). Hochwassermarke für den Gewinn-Transfer. |
| **Gewinn-Transfer** | AKY über der Basis → CR zum **Bau-Kurs**. Max. 1× je Börsentag, nur wenn Depotwert ≥ 1,02 × Basis, max. 6 % der Basis. Nie umgekehrt. |
| **Bau-Kurs** | Umrechnung „1 AKY → x CR“, hängt **nur von der Lizenz** ab (40 … 40.000). Wird nie mit Pässen/Boosts multipliziert. |
| **Börsentag** | 1.200 Ticks = 20 min = ein Tag/Nacht-Zyklus der Stadt. Glocke bei :00. |
| **Lizenz** | Rang Azubi I … Börsen-Legende (10 Stufen), aus Trader-XP + Prüfung. Schaltet Instrumente, Ordertypen, Basis, Bau-Kurs und **Tower-Stufen** frei. |
| **Trader-XP / Trader-Level** | Nur aus Handeln, Akademie, Handels-Quests. Level 1–100 (Anzeige). Nie mit Robux. |
| **Know-how (KH)** | Skill-Punkte aus Level/Lizenz/Akademie. Kauft Trading-Werkzeuge (Alarme, Watchlists, Multi-Chart, Bot-Stufen, Research). Nie mit Robux. |
| **Ruf** | 0–10 Stufen (5 Sterne mit Halben) aus positiven Börsentagen. Teil des Trader-Faktors. Verluste kosten nie Ruf. |
| **Trader-Faktor** | `(1 + Lizenz-Bonus) × (1 + 0,03 × Ruf)`, max. ×1,82. Multipliziert Turm-Einkommen. Reiner Skill. |
| **Börsengang (BG)** | Prestige: Turm-Neustart gegen Aktien-Sterne + dauerhaft +0,25 Einkommen. Glocken-Zeremonie. |
| **Aktien-Sterne (★)** | Prestige-Punkte für den Vorstand-Baum (nur Turm/Lifestyle). |
| **Vermögen** | Anzeige- und Bestenlistenwert: CR + Turmwert + Firmenwert + Sammlung + Depotwert × Bau-Kurs (max. 9e15). |
| **Admin-Fenster (Taint)** | Zeitraum eines Admin-Markt-Events (Ankündigung bis +10 min nach Abklingen); zählt nicht für Liga/Skill-Score. |
| **Tiko** | Geskripteter Hologramm-Roboter (Tutorial, Tipps, Ampel). Keine KI, kein Chat, keine Anlageberatung. |
| **Plot** | Einer von 10 Bauplätzen am Skyline-Ring. **Etage** 1–50, **Stufe** 1–12 (Silhouette). |
| **Tresor** | Online-Einkommensspeicher im Tower (Kapazität 20 min Einkommen). |
| **WP** | Arbeitspaket (Abschnitt D). |

### 0.2 Roblox-Regeln (Stand 2026-10; wörtlich geprüft)
Quellen: Creator-Docs-Quelltexte (GitHub-Spiegel von create.roblox.com, lokal unter `<SP>/rbxdocs/`), Community Standards /
Advertising Standards / DevForum nur als Suchauszüge (**[Auszug]**). **Der Besitzer liest vor dem Ausfüllen des Fragebogens den
Live-Wortlaut** (ANLEITUNG Kapitel „Fragebogen“).

| Thema | Regel (wörtlich bzw. [Auszug]) | Folge für uns |
|---|---|---|
| Glücksspiel | content-maturity.md: „Gambling is the practice of exchanging real-world money, Robux, or in-game items of value for a game of chance. While games cannot contain playable gambling content, including simulated gambling, you can depict unplayable gambling content, such as showing a casino or people playing cards that players cannot bet on or play.“ | Kein spielbares (auch simuliertes) Glücksspiel – nicht altersfreigebbar, sondern verboten. |
| Nicht meldepflichtig | „You do **not** need to report depictions of, and/or references to, items or activities that are typically associated with gambling, but are not games of chance/luck, such as horse racing, car racing, and poker chips.“ | Ein Skill-/Informationsmarkt ist kein „game of chance“. Wir vermeiden trotzdem jede Casino-Ästhetik (IARC). |
| Community Standards | [Auszug] „…we allow unplayable gambling content, such as references to gambling and related imagery. However, we prohibit both simulated and actual gambling activities on the platform.“ · „No real money, Robux, or in-experience items of value may be exchanged in connection with any gambling activities.“ | Robux dürfen nie in etwas fließen, dessen Ergebnis von Kursbewegungen abhängt (§0.4). |
| Labels | „Games with a **Minimal or Mild** label are eligible for Roblox Kids (ages 5–8) and Roblox Select (ages 9–15).“ „**Moderate** … eligible for Roblox Select and standard Roblox (ages 16+).“ Moderate = „…and/or unplayable gambling content“. | Ziel **Minimal**. Schon eine Casino-Deko → Moderate → Kids-Publikum weg. |
| Paid Random Items | paid-random-items.md: gilt für Zufallsitems „purchased directly or indirectly with Robux … including … paid in-game currency“; Quoten vor dem Kauf, Summe exakt 100 %, Wort-Knopf „Details“ (bloßes (i) reicht nicht); bei `ArePaidRandomItemsRestricted` blocken/ersetzen. | **Keine** bezahlten Zufallsitems (CR ist „bezahlte Währung“ → auch nichts Zufälliges für CR verkaufen). PolicyService-Pfad bleibt (fail-closed) für die Zukunft. |
| Paid Item Trading | Fragebogen-Frage + `IsPaidItemTradingAllowed`. | Kein Spielerhandel. Geschenk-Produkt (Boost für Freund) zusätzlich fail-closed gesperrt, wenn `IsPaidItemTradingAllowed ~= true`. |
| Werbung | ad-integrations.md: Werbung ist auch, was „promotes demand, attributes, information, or availability for specific off-platform products … even if you're promoting your own content inside your game“. [Auszug, Mai 2026] Finanzdienstleistungs-Werbung nicht an unter 13; selbst verwaltete Integrationen dürfen keine Finanzprodukte bewerben. | AKYTEX nur als Spielmarke (Name/Look/fiktive Börse). Nie die echte Plattform, App, Tarife, Broker, „Demo-Depot“, „echtes Trading“. |
| Links | [Auszug] Links nur über Social Links der Spielseite (sichtbar 16+); im Spiel erlaubt: „Check out our social media links on our game's page“. | Keine URL/QR im Spiel. |
| Abos | subscriptions.md: Preis in Robux (≥ 49 R$) oder Landeswährung (2,99/4,99/7,99/9,99/14,99 $, ID-/Telefon-verifiziert); `IsEligibleToPurchaseSubscription`. | „Vorstands-Club“ (§B14.3). |
| PolicyService | Felder (YAML geprüft): `ArePaidRandomItemsRestricted`, `IsPaidItemTradingAllowed`, `IsEligibleToPurchaseSubscription`, `AreAdsAllowed`, `IsContentSharingAllowed`, `IsEndlessContentLoadAllowed`, `IsEndlessContentAutoplayAllowed`, `AllowedExternalLinkReferences`, … | Immer `pcall`; unbekannt = eingeschränkt. Keine endlosen/auto-spielenden Feeds (News-Liste endlich, max. 50). |
| Kids/Select | kids-and-select.md: Creator alters-geprüft/verifiziert, 2FA, kompletter Fragebogen, Plus/Premium ≥ 2 Monate **oder** rückzahlbare Gebühr; Freigabe nach „250 unique plays by highly engaged age-checked users within a 60-day window“ (Express-Prüfung 50.000 R$ rückzahlbar). | Schritte in die ANLEITUNG; alles Soziale funktioniert ohne Chat (Kids: Chat standardmäßig aus). |
| IARC (Ende 2026) | Simuliertes Glücksspiel = „look, sound and actions“ von Glücksspiel; PEGI 18 für „Glorifizierung“, USK zählt glücksspielähnliche Inhalte. | Keine Spielautomaten-Feedbacks, keine Münz-Explosion pro Trade. |

### 0.3 Markt ≠ Glücksspiel (Konstruktionsregeln, verbindlich; Ergänzung zu MARKET.md §1.2)
1. **Kein Einsatz, keine Auszahlung:** Man kauft Anteile zum angezeigten Preis und verkauft wann man will. Keine Runden,
   keine festen Quoten, kein „Steigt/Fällt in X s?“, kein „Verdoppeln“, kein Cash-out-Multiplikator (Crash ist **nur** eine
   Markt-Nachricht, kein Crash-Spiel).
2. **Information entscheidet:** große Bewegungen nur aus vorher lesbaren News (8 s Lesefenster, 45 s Rampe), Terminen,
   Fundamentaldaten. Rauschen klein und mittelwertstabil. Backtest: Zufall −0,35 %/Börsentag (39 % positive Tage), informiert
   +5,2 … +7,7 % (89–100 %).
3. **Kein Hebel, keine Optionen/Turbos/Futures/CFDs/Krypto.** Leerverkauf erst v1.1, 1×, ab Fondsmanager.
4. **Klumpen-Grenze 30/40/50/60 %** je Einzelwert (Lizenz); Betrags-Chips **„10 % · 25 % · Max“** (Max = Grenze), nie „100 %“
   oder „All-in“. Bestätigung „Sicher? Verteilen ist klüger.“ ab 20 % des Depotwerts in einem Wert.
5. **News ohne Wett-Optik:** Karte mit ruhigem Balken „Händler lesen …“ (8 s), **kein Kauf-Knopf auf der Karte**, nur „Zum
   Chart“. Kein Blinken, keine Ausrufezeichen-Ketten.
6. **Ruhiges Feedback:** Gewinn-Verkauf = grüner G/V-Tick + sanftes Arpeggio; Verlust = neutraler grauer Tick + ein Lerntipp.
   Konfetti/Geldregen nur für Meilensteine (Stufe, Lizenz, Titel, Börsengang, Liga-Stufe). Keine Fast-gewonnen-Effekte,
   keine Serien-Flammen.
7. **Robux → Markt: nichts** (§0.4). Keine Auszahlung in Robux. Kein P2P.
8. **Gewinn-Transfer ist begrenzt:** Hochwassermarke (Basis), Schwelle 2 %, max. 1× je Börsentag, max. 6 % der Basis je
   Börsentag, Rettungsschirm nie direkt abhebbar → Zufallshandel kann keine CR „farmen“ (Freie-Option-Gate §B9.10, G5).
9. **Skill messbar:** Liga nach Skill-Score (Konstanz, Drawdown), nicht nach Kontogröße oder Aktivitätsmenge (§B11.1).

### 0.4 Robux-Firewall (exakt)
| | **AKY – Börsengeld** | **CR – Credits** |
|---|---|---|
| Quellen | Start-Basis 25.000 · Basis-Erhöhung bei Lizenzaufstieg · Rettungsschirm · Handelsgewinne · Dividenden · Tutorial-Trade · Admin (erhöht Basis mit, taint) | Turm-Einkommen (online, Tresor, offline) · Gewinn-Transfer · Quests/Login/Events/Geldregen · Robux-Bau-Gutscheine · Codes |
| Senken | Gebühren, Spread, Bot-Lohn, Handelsverluste, Gewinn-Transfer | Etagen, Abteilungen, Stufen, Personal, Effizienz, Deko, Autos, Tuning, Uhren, Accessoires |
| Robux | **nie** – kein Produkt, Pass, Abo, Saison-Stufe, Boost oder Geschenk berührt AKY, Basis, Bau-Kurs, Orders, Bots, Lizenz, XP, KH, Ruf, Marktinfo | erlaubt: Pässe/Boosts (multiplizieren Turm-Einkommen), Bau-Gutscheine (CR), Bau-Express |
| Richtung | → CR (Gewinn-Transfer, Lizenz-Bau-Kurs) | **CR → AKY unmöglich** (keine Funktion existiert) |

Zusatzregeln: (a) Turm-Multiplikatoren gelten **nie** für AKY, Bau-Kurs-Ausgabe, Dividenden, Trades. (b) Aktien-Sterne
(aus CR-Ausgaben, also Robux-beeinflussbar) kaufen **nur** Turm-/Lifestyle-Perks. (c) Research-Vorlauf, Alarme, Watchlists,
Multi-Chart, Bot-Stufen nur über Lizenz/Know-how. (d) Der Bau-Kurs hängt **nur** von der Lizenz ab (keine Stufen-/Tower-
Abhängigkeit, weil Tower-Stufen mit Robux schneller erreichbar sind → wäre ein indirekter bezahlter Gewinn-Multiplikator).
(e) Spieler-Firmen (v2) nur als Trader-AG mit Kurs aus Handelsrendite (TWR-Index), nie aus Tower-Kennzahlen.
Durchsetzung: §C11.4 (Modulgrenze, Prüfer-Regel `FIREWALL`, Depot-Schreibtrichter, `ForbiddenRobuxFields`, SelfTest
„Firewall“ byte-gleich).

### 0.5 Marke AKYTEX & NOVA (verbindlich)
- **Erlaubt im Spiel:** Name „AKYTEX TYCOON“, Wortmarke **ΛKYTEX** (aus Frames/Neon-Parts nach `icons/logo.svg`-Strichen),
  Farben/Schriften/Bewegung der Website, die fiktive Börse **„AKYTEX Exchange“**, Index **AKX36**, **ΛKYTEX Terminal**,
  Taglines „Markets move. Ideas stay.“ und „CAPITAL BUILDS TOMORROW“ (an der Börsenglocke).
- **Verboten im Spiel und auf der Spielseite:** URL, QR, „App“, „Website“, „Demo-Depot“, Tarifnamen (Free/Plus/Pro/Elite/Ultra),
  „AKYTEX AI“, „Aky“, „NOVA“, „echtes Trading“, Broker/KYC, Euro-Preise, Gründernamen/Adressen,
  „3 Minuten am Tag. Ein Leben lang reicher“ (Finanzversprechen).
- **Handelbare Instrumente:** keine Firma heißt AKYTEX oder NOVA (MARKET.md-IDs 1 und 2 umbenannt, §B6.2). Grund: der
  Besitzer plant echte Beteiligungen (`AKTIE-FAHRPLAN.md`) – eine handelbare „AKYTEX-Aktie“ vor Minderjährigen wäre
  Finanzwerbungs-Risiko; außerdem würde die Marke in Crash-/Admin-Events „abstürzen“.
- **Kanäle trennen:** eigene Social Links „AKYTEX Games“ (Discord/YouTube) für die Roblox-Spiele; die AKYTEX-Finanzkanäle
  bleiben erwachsenen-orientiert. Die Website darf auf das Spiel verlinken, aber nie neben Broker-/KYC-/Abo-Aufrufen.
  Keine Datensammlung über Spieler. Wortmarke „AKYTEX“ auch in Spiele-/Unterhaltungs-Klassen anmelden (Rat einholen).
- **Off-Platform-Werbung** (falls je gewünscht) nur als registrierte, gekennzeichnete Ad-Integration – Ablehnung bei
  Finanzprodukten erwartet. Steht so in der ANLEITUNG.

### 0.6 Fragebogen (Ziel Minimal) – ehrliche Antworten
| Frage | Antwort | Begründung |
|---|---|---|
| Gewalt / Blut / Angst / derber Humor / starke Sprache / Romantik / Alkohol | Nein | Crash-Effekte treffen nie Avatare; Bulle/Bär freundliche Part-Figuren; Smoothie-Café |
| Unplayable gambling content | **Nein** | keine Casino-/Karten-/Würfel-/Slot-/Glücksrad-Darstellung, keine Glücksspiel-Wörter |
| Social Hangout (Hauptfokus) | Nein | Tycoon-Fokus |
| Free-form user creation | Nein | Deko in festen Slots aus Vorlagen, Namen aus Wortbausteinen |
| Sensible Themen / Medien / endlose Feeds / Inhalte anderer Spiele | Nein | News-Liste endlich, keine Auto-Play-Feeds |
| Paid random items (+ `ArePaidRandomItemsRestricted` respektiert) | **Nein** (Pfad trotzdem fail-closed) | alles deterministisch |
| Paid item trading (+ `IsPaidItemTradingAllowed`) | **Nein** | kein Spielerhandel; Geschenk-Boost zusätzlich gegated |
| Generative KI | Nein | Tiko ist vollständig geskriptet |
Ergebnis: **Minimal** → Roblox Kids, Roblox Select, Standard. Nach jeder Änderung, die eine Antwort ändert: Fragebogen neu.
Voice: Roblox regelt Berechtigung (13+, verifiziert); bei Einreichung prüfen, ob der Fragebogen danach fragt.

### 0.7 Wortliste (Vertrags-Prüfer `BANNED_WORDS`, Groß/klein egal, Wortgrenzen)
- **DE verboten:** Wette, wetten, Einsatz *(Ausnahme Phrase „im Einsatz“)*, Casino, Kasino, Jackpot, Glück… *(Ausnahme
  „Glückwunsch“, „Herzlichen Glückwunsch“)*, Glücksrad, Glücksspiel, zocken, All-in, verdoppeln, „doppelt oder nichts“,
  Lotterie, Losnummer, Rubbellos, Gewinnspiel, Spielautomat, Roulette, Poker, Würfel, Hebel, Insider, Krypto, Bitcoin, NFT,
  Mondfahrt, „garantiert“.
- **EN verboten:** bet, betting, wager, stake, casino, jackpot, lucky, luck, gamble, gambling, all-in, „double or nothing“, lottery, raffle, spin, x100, „to the moon“, leverage, insider,
  crypto, bitcoin, NFT, poker, roulette, „slot machine“, dice, guaranteed.
- **Erlaubt/erwünscht:** Order, Kauf/Verkauf, Depot, Performance, Analyse, Lizenz, Börsentag, Eilmeldung, Rallye, Crash,
  Gewinn-Ziel, Gewinn-Transfer (Spielbegriffe ohne Robux-Bezug), „Los geht's“.
- Geltungsbereich: alle Werte in `src/shared/Lang/*.luau` und alle `Name`/`Desc`/`Title`-Strings in `src/shared/Config/*.luau`.
  Spielertexte stehen **nur** in Lang/Config (keine Literal-Texte in Client/Server-Code außer Debug-Ausgaben).

### 0.8 Monetarisierungs-Leitplanken (harte Regeln)
1. Robux kaufen nur: Turm-Einkommens-Multiplikatoren, CR-Gutscheine, Bau-Beschleunigung, Komfort im Turm (Auto-Kassierer,
   Offline-Tresor, Personal-Slot), Kosmetik (Fassaden, Neon, Terminal-Themes, Autos, Uhren), Server-Party, Saison-Premium, Abo.
2. **Nie** für Robux: AKY, Aktien, IPO-Zuteilung, News/Insider/Research-Vorlauf, Analysten, Alarme, Watchlists, Multi-Chart,
   Indikatoren, Handels-Multiplikatoren, Verlust-/Crash-Schutz, Rückgängig, Hebel, Lizenz/Prüfung überspringen, XP, KH, Ruf,
   Aktien-Sterne, Strategie-Bots/Bot-Leistung, Zufallsbelohnungen, Admin-Kräfte, Streak-Retter.
3. Jeder Kauf hat sofort sichtbare Wirkung (Multiplikator-Chip poppt, Fassade wechselt live, Auto fährt aus der Garage).
4. Exakte Wirkung jedes Artikels in DE/EN vor dem Kauf; Bau-Gutscheine zeigen die **exakte CR-Zahl** (Angebot 10 min gültig).
5. Kein Kauf-Druck an Kinder, keine Fake-Rabatte, kein Neustart-Countdown, keine Knappheits-Lügen.

---

# A) Name, Pitch, Art Direction, „Warum BIG und besser“

## A1. Name
**AKYTEX TYCOON** – Spielseiten-Titel **`AKYTEX TYCOON 🏙️📈 Börse & Tower`** (in Saisons `[S1] AKYTEX TYCOON 🏙️📈 Börse & Tower`).
Kein Geld-/Robux-Wort im Titel (Discovery-Regel „Don't lead titles with monetary rewards“). Name nur in `Config.GameName` und
`Lang` (`core.gameName`). Taglines: **„Markets move. Ideas stay.“** (Marke) · Spiel: DE „Lies die Eilmeldung. Bau die Skyline.“ ·
EN „Read the news. Build the skyline.“ · An der Börsenglocke graviert: „CAPITAL BUILDS TOMORROW“.

Spielseiten-Beschreibung (Vorlage in `docs/KOPIERVORLAGEN.md`): Zeile 1 Fantasie, Zeile 2 Disclaimer, Zeile 3 Event-Kalender,
letzte Zeile „Check out our social media links on our game's page“ (EN) / „Unsere Social-Links findest du auf der Spielseite“.

## A2. Pitch
- **DE:** Starte in einer Garage mitten in einer Neon-Stadt. Lies Eilmeldungen, bevor der Markt reagiert, handle 36 erfundene
  Firmen an der AKYTEX Exchange mit Spielgeld und steck deine Gewinne in deinen eigenen Wolkenkratzer – Etage für Etage, bis
  zum 50-stöckigen ΛKYTEX Orbit-Spire. Stell Roboter-Personal ein, fahr deinen Hypersportwagen über den Autobahnring, trag
  deine Uhr, läute die Glocke zu deinem eigenen Börsengang. Alle Server teilen einen Markt: Glocke alle 20 Minuten,
  Crash-Freitag, Admin-Abuse-Samstag.
- **EN:** Start in a garage in a neon city. Read breaking news before the market moves, trade 36 fictional companies on the AKYTEX
  Exchange with play money, and turn your profits into your own skyscraper, floor by floor, up to the 50-floor ΛKYTEX
  Orbit-Spire. Hire robot staff, drive your hypercar around the highway ring, ring the bell at your own IPO.
- **Disclaimer (Ladebildschirm, Terminal-Fußzeile, Einstellungen → Info, Akademie, Spielseite):**
  DE „Spiel mit Spielgeld. Alle Firmen, Kurse und Nachrichten sind frei erfunden. Spielgeld hat keinen echten Wert und kann
  nicht ausgezahlt werden. Keine Anlageberatung.“ · EN „Game with play money. All companies, prices and news are fictional. Game
  money has no real value and cannot be cashed out. Not investment advice.“ (`core.disclaimer`)

## A3. Positionierung
| Konkurrent | Stand (Recherche) | Wir |
|---|---|---|
| **Penthouse Tycoon** (Loaded Studios, ~95 Mio. Besuche, Aktien im obersten Stock) | Spieler: Kurse „korrupter als im echten Leben“ (Zufall), flach | lesbarer, fairer Markt (News mit Vorlauf, Kalender, Analysten mit echter Trefferquote), lebendige Stadt, Lizenzen/Prüfungen, Live-Events über alle Server, Autos/Uhren, Admin-Abuse |
| Roblox Stock Exchange 2 (Peak 958 CCU), RBLX Exchange (~45), Stock Trading Simulator (0) | reine Terminals, PC-Gefühl, „Leverage“/„Insider“-Pässe | das Terminal ist ein Fenster **in der Welt**; Handy zuerst; nichts davon für Robux |
| Steal a Brainrot / Grow a Garden (Rekorde 25,4 / 22,3 Mio. CCU) | sichtbare Basis, Offline-Wachstum, Server-Events, Admin-Abuse; aber Diebstahl-Tränen, bezahltes Glück, Hyperinflation | sichtbarer Tower, Offline-Tresor, synchrone Events, Admin-Abuse – **ohne** Diebstahl, ohne Zufallskisten, mit Börsengang als weichem Reset |

## A4. Art Direction „AKYTEX Neon City“ (nur Parts, Future-Licht)
| Element | Regel (Werte stehen in `Config.City.Look` bzw. `UI.Theme`) |
|---|---|
| Stimmung | dunkle Premium-Fintech-Stadt: Glas, Marmor, gebürstetes Metall; Neon nur als Akzent (≤ 8 % jeder sichtbaren Fläche). Tag: blau-graues Glas, weiche Sonne. Nacht: AKYTEX-Neon Accent `#4f8cff`, Up `#22c55e`, Down `#ef4444`, Premium/Penthouse kosmisch `#7c5cff → #b36bff`, Gold `#facc15` nur für Kronen, Glocke, Hall-of-Fame. |
| UI-Farben | exakt CC-`UI.Theme`: Bg `#0b0f17`, Bg2 `#0f141d`, Surface `#121824`, Surface2 `#1a2130`, Hover `#1f2838`, Border `#1f2937`, Text `#e6ecf5` / `#aab4c3` / Muted `#7d889a`, Accent `#4f8cff`, AccentDeep `#2962ff`, Up `#22c55e`, Down `#ef4444`, Warn `#eab308`. Nachthimmel/Hero: Space-Set `#03040a`, `#7c9cff`, Verlauf `#3b5bdb → #7c5cff → #b36bff`, Gold `#ffcf6e`. Logo-Ring `#6ea2f2`, Buchstaben `#eaf1ff`. Sektorfarben: Tech `#4f8cff`, Energie `#22d3ee`, Mobilität `#8b5cf6`, Konsum `#f59e0b`, Gaming `#ec4899`, Finanzen `#facc15`. Farbenblind-Modus: Up/Down → Accent `#4f8cff` / Orange `#f59e0b`, ▲/▼ immer sichtbar. |
| Materialien | Fassaden Glass (Transparency 0.3, Reflectance 0.2) mit Metal-Pfosten `#1f2937`; Böden Marble (Reflectance 0.12–0.18), Plaza schwarzer Marmor 0.15; Straßen Asphalt/Concrete; Showroom SmoothPlastic Reflectance 0.3; Neon nur als 0.2–0.4-Stud-Streifen. Kein `Ice`. |
| Licht (Projektdatei, Skripte dürfen `Technology` nicht setzen) | `Lighting.Technology = Future`, `EnvironmentSpecularScale = 1`, `EnvironmentDiffuseScale = 1`. GraphicsService erzeugt (alte eigene Instanzen vorher löschen): Atmosphere Density 0.30 (Tag) / 0.38 (Nacht), Haze 1.2 / 1.8, Color `#c7d6ff`; Bloom Intensity 0.55, Size 24, Threshold 1.5; SunRays Intensity 0.04; ColorCorrection Contrast 0.08, Saturation 0.05; DepthOfField nur in Menüs/Kamerafahrten (Client). Werbung/Texte: „Future-Licht“, **nie** „Raytracing“. |
| Tag/Nacht = Börsentag | Client rechnet aus `workspace:GetServerTimeNow()` (alle Server gleich): Minute :00 Sonnenaufgang (ClockTime 6.5) mit Glocke, :06 Mittag (12), :12 Sonnenuntergang (18.5), :12.5–:18.5 Nacht (21 → 4), :19.5 Dämmerung. Fenster-Lichter schalten ab ClockTime 18.5 als Kaskade von unten nach oben (0,05 s je Etage). |
| Markt-Wetter | Regime `R(t)` aus dem Frame: `R < 0.85` klar, `0.85–1.2` Wolken (`Clouds.Cover 0.45`), `> 1.2` Sturm (Regen-Partikel am Kameraort, harmlose Blitz-Flashes ohne Schaden). Crash: ColorCorrection Tint `#ffdada`, Saturation −0.15, Ticker-Wände rot, Sirenen-Rezept. Rally: grüne Polarlicht-Beams über der Plaza, warmer Tint `#fff4dc`, goldener Bulle läuft den Ring. |
| Silhouetten-Regel | jede der 12 Tower-Stufen hat eine eigene Krone/Silhouette, aus 600 Studs erkennbar (§B4.2). |
| Bausteine (Code, nie Upload) | Fassadenmodul (Glasfeld, Pfosten, Neonband), Deckenplatte, Aufzugsschacht, Kronen, Antenne + Leuchtfeuer, Helipad, LED-Wand (SurfaceGui), Hologramm (Neon + Beam + `particles/sparkles_main.dds`), Möbel aus Block/Wedge/Zylinder, Autos (Wedge/Zylinder + VehicleSeat + Constraints), Uhren (Zylinder + Neon-Zifferblatt), Roboter (Kugelkopf mit SurfaceGui-Gesicht, Kapselkörper, Schwebering). |
| Schriften | `BuilderExtended` (Display ≈ Unbounded: Logo, Fenstertitel, große Zahlen), `BuilderMono` (alle Preise, G/V, Achsen – keine zitternden Ziffern), `BuilderSans` (Fließtext). Per `FontFace` (`Font.new("rbxasset://fonts/families/BuilderExtended.json", Enum.FontWeight.Bold)`), Fallback Michroma/TitilliumWeb, falls Umlaute/„Λ“ in Studio fehlen (WP2 prüft). |
| Bewegung | iOS-Federn wie die Website: Fenster auf 0,26 s Quint Out + 8 px Gleiten, zu 0,14 s Quad In; Drücken 0,08 s auf 0,97, Loslassen 0,3 s Back Out; Zähler `alpha = 1 − e^(−7t)` ≤ 30 Hz; Federn `Spring.new(v, 25–30, 0.58)`. `ReducedFx` = Website-`prefers-reduced-motion`. |
| Sound | nur `Sfx`-Rezepte (§C14 `Config.Client.Sounds`, 0 = Rezept). Rollen: UIClick/UIHover/UIError, Buy (Tick 1.26→1.5), Sell (1.5→1.26), Profit (ruhiges Arpeggio), Loss (tiefer Einzelton), CashRegister, TickerTick (Vol 0.15), MarketBell (Tick 1.0/1.26/1.5 + Echo), CrashAlarm (0.841/0.667 + Verzerrung), RallyFanfare, ElevatorDing, Construct (Land 0.8), MoneyRain, Engine (`action_falling.ogg`-Loop, Tonhöhe nach Tempo). **Keine Casino-Klänge**, keine Münz-Kaskade pro Trade. |
| Logo & Ladebildschirm | ΛKYTEX aus gedrehten Frames (UI) bzw. Neon-Parts (Welt) nach den `logo.svg`-Strichen (REUSE §8.5). Ladebildschirm (ReplicatedFirst) spielt die Website-Splash nach: Ring zeichnet 1,3 s, Kerzen steigen (18 ms Versatz), Buchstaben 0,09 s Versatz, Taglines bei 1,25/1,45 s; max. 4 s, endet früher wenn geladen, tippen überspringt. |

## A5. Welt-Karte (2.048 × 2.048 Studs, Ursprung = Plaza-Mitte, Boden Y = 0; `Config.City`)
| Zone | Lage / Maße | Inhalt v1 |
|---|---|---|
| **Exchange Plaza** | Kreis R 130 um (0,0,0) | schwarzer Marmor mit blauem Raster, Logo-Ring im Boden (≈ 40 Parts, R 46), 12-m-ΛKYTEX-Neonbuchstaben, Brunnen, Riesen-Kerzentafel 24 Studs (AKX36 live), 4 Ticker-Wände (SurfaceGui, je 64×8), Bestenlisten-Hologramme, Hall-of-Fame (3 Statuen), Tiko-Hologramm, Glocken-Moment-Zone (R 18 vor dem Eingang) |
| **Börsensaal „AKYTEX Exchange“** | Mitte (0, 0, −190), 180 × 140, Höhe 70, Glaskuppel (SpecialMesh Sphere) | Marmor-Parkett, goldene **Börsenglocke** auf Podium (Börsengang-Zeremonie), 360°-LED-Tickerring, 6×6-Sektor-Heatmap-Wand, 12er-Monitorwand, 8 Terminal-Pulte (Sitz + ProximityPrompt „Terminal“), VIP-Balkon (Pass, Tür nur lokal offen), Akademie-Obergeschoss (4 Lern-Kapseln), Dachterrasse (Vorstands-Club) |
| **Ring-Boulevard** | Ringstraße R 230–260 (2 × 2 Spuren, 30 breit) | Laternen (Neon-Köpfe; echte Lichter nur nah am Spieler), Ampeln (optisch), Fußgängerüberwege |
| **Skyline-Ring (Plots)** | 10 Plots auf R 420, Winkel 18° + k·36°, je 110 × 110 | Tower-Fläche 56 × 56 (Mitte), Einfahrt zur Ringstraße, Garagentor, goldenes Kassen-Tor (Tresor-Sammeln), Vorplatz, Plot-Schild (Name + Tower-Name aus Wortbausteinen + Lizenz-Abzeichen + Titel), Respekt-Säule |
| **Äußerer Ring** | Ringstraße R 560 | verbindet Bezirke, Verkehr |
| **Λ Motors (Autohaus West)** | (−760, 0, 0), 160 × 100 | Glas-Showroom, 12 Drehteller, Probefahrt-Startpunkt, Lackier-/Tuning-Box |
| **Chronohaus (Luxus-Boutique)** | (−760, 0, 190), 90 × 60 | Vitrinen mit drehenden Uhren (Client-Tween), Spiegelwand, Accessoires, Deko-Showroom |
| **Marina Süd** | (0, 0, 780), Terrain-Wasser 600 × 300 | Uferpromenade, 6 Liegeplätze (Yachten v1.1 deko), Leuchtturm-Beam, Fotospot |
| **Villenhügel Nord** | (0, 60–120, −820) | Serpentine, Aussichtspunkt mit Skyline-Blick bei Sonnenuntergang (Fotospot), 4 Deko-Villen |
| **Helipad / Logistik Ost** | (780, 0, 0) | Helipad-Turm 60 hoch (Schnellreise-Pad zur Plaza), Hangar mit Deko-Jet |
| **Autobahnring** | Schleife R 950 (≈ 5.970 Studs) | 2 Rampen, Tunnel (Nord), Brücke über die Marina, Drift-Kurven |
| **Finanzviertel-Kulisse** | NE/NW-Quadranten zwischen R 600–900 | 36 Deko-Türme (5–8 Parts, Glas + Neon-Fensterbänder) mit Leuchtschildern der fiktiven Firmen; **Firmen-Läden** (Burgerplanet-Diner, Knusperix-Automaten, Velocitra-Schaufenster, Towerbank-Automaten, Arcadeon-Halle, Sneakora-Laden) bekommen einen Spot + Mini-Ticker, solange ihre Firma eine aktive News hat |

Umgebungsleben (nur Client, Budget je Grafikstufe §C16): Verkehr auf Splines (0/10/20/32 Autos), Lieferdrohnen (0/4/8/14),
Hologramm-Werbetafeln der fiktiven Firmen (Spielfiktion, keine Werbung), Luftschiff mit ΛKYTEX-Logo, Fensterlichter. **Keine**
Fußgänger-NPCs (bräuchten Animationen).

## A6. Warum BIG und besser (Besitzer-Wünsche → Lösung)
| # | Wunsch / Problem | AKYTEX TYCOON | v |
|---|---|---|---|
| 1 | „aber BIG“ (W1) | 2 km-Stadt mit 7 Bezirken + Autobahnring, 10 Plots, **50 Etagen in 12 Silhouetten**, 36 Firmen + 7 ETFs + 6 Themen-Körbe + Saison-IPOs, 11 Abteilungen, 4 Personal-Stufen, 16 Autos, 15 Uhren, 68 Deko-Teile, 60 Erfolge, 10 Lizenzen, Saison-Pass mit 50 Stufen; Etage 50 nach ≈ 6 Wochen (Sim §B5.4) | v1 |
| 2 | Krasse Details (W2, W7) | Monitore mit echten Live-Charts in jedem Büro, Roboter an Schreibtischen, fahrender Glas-Aufzug, Fensterlicht-Kaskade nachts, Kran-Zeremonie je Etage, Firmen-Läden reagieren auf News, Wetter = Markt-Regime | v1 |
| 3 | Ultra-Grafik, Future-Licht (W3, W10) | Future-Licht aus Projektdatei, Glas/Marmor/Metall mit Reflexion, Lichtbudget je Stufe, Bloom/Atmosphere/ColorCorrection, DoF in Kamerafahrten | v1 |
| 4 | Ultra smooth (W4) | Charts 60 FPS (gepoolte Frames, O(1)-Laufband), ein PreRender-Loop, Interiors nur nah, automatische Grafikstufen, kein Server-Ruckeln (Markt < 0,3 ms/Tick) | v1 |
| 5 | Neu (W5) | Trading als Skill (News lesen) + Tower als Statussymbol + Börsengang-Zeremonie + Liga nach Skill | v1 |
| 6 | Anspruchsvoll (W6) | 3 Terminal-Schichten, 9 Indikatoren, Markttiefe (simuliert), Umsätze, Fundamentaldaten, Kalender, 8 Analysten mit echter Trefferquote, Makro-Matrix, Ordertypen bis Nachzieh-Stopp/OCO/Sparplan, Lizenzprüfungen, Skill-Score, Strategie-Bots mit Regeln; Leerverkauf + Hedgefonds-Gruppen v1.1 | v1/v1.1 |
| 7 | Flagship + Admin-Panel (W8, W9) | Besitzer-Panel mit 11 Tabs, Markt-Kontrolle global, Admin-Abuse-Katalog (21 Events), Fairness-Taint, Live-Ops-Kalender, automatische Samstags-Show | v1 |
| 8 | Voice (W13) | `VoiceChatService.EnableDefaultVoice` + Treffpunkte (Börsensaal, Dachterrasse, Tower-Lobbys) | v1 |
| 9 | Open World + Lifestyle (W14) | befahrbare Stadt, 16 Autos mit Drift/Boost/Unterbodenlicht, Uhren am Handgelenk, Accessoires, Penthouse; Yacht/Heli v1.1, Jet v1.2; jugendfrei | v1 |
| 10 | Monetarisierung max (W15, W16) | 14 Pässe, 17 Developer Products, Abo, Saison-Pass, sichtbarer Multiplikator-Chip „x7,4“ mit Aufschlüsselung, ehrliche Pass-Rechnung | v1 |
| 11 | Reichweite & Sucht fair (W11, W12) | 5 Rhythmen (40 s News, 20 min Glocke + Welt-Event, täglich, wöchentlich, Saison), Einladen mit Belohnung, Freunde-Bonus, Favoriten-Abfrage, Badges, Experience Events, Notification-Opt-in (Senden v1.1), Offline-Tresor, Login-Kalender | v1 |
| 12 | Hybrid-Assets (W17) | Asset-Plätze in Config für alles Sichtbare + `docs/ASSET-LISTE.md` | v1 |
| 13 | „Penthouse-Zufall“ der Konkurrenz | Backtest-Beweis, News mit Lesefenster, ehrliche Analysten | v1 |
| 14 | Glücksspiel-/Diebstahl-Tränen anderer Spiele | kein Stehlen, kein Spielerhandel, keine Zufallskisten, Pickups pro Spieler instanziert | v1 |
| 15 | Hyperinflation (GaG) | Börsengang als weicher Reset, exponentielle Kosten in Bändern, Licence-Tore, Ganzzahl-Deckel, Log-Bestenlisten | v1 |

## A7. Gänsehaut-Momente (je genau ein Besitzer-Modul)
| # | Moment | Ablauf | Besitzer |
|---|---|---|---|
| 1 | Etage gebaut | Kran auf dem Dach hebt die Platte (2,5 s), Kamera-Orbit (überspringbar, bei ReducedFx sofort), Fenster leuchten auf, „+14 CR/s“ fliegt | `EffectsTower:BuildDone` (WP8) |
| 2 | Stufen-Morph (12×) | Hülle morpht 2,5 s (alte Teile faden, neue tweenen von Skala 0,9), Krone leuchtet, Konfetti-Beams, Server-Toast „RizzG315 hat jetzt einen Wolkenkratzer!“ | `EffectsTower:StageUp` (WP8) |
| 3 | Glocke bei Sonnenaufgang | Glocke schwingt, Lichtwelle über alle Ticker-Wände, „Gewinn-Transfer wieder frei“, Tagesbilanz-Karte federt von rechts | `EffectsMarket:Bell` (WP5) |
| 4 | „Gut gelesen!“ | Kauf ≤ 60 s nach Fakten-News in deren Richtung, ≥ 2 % Depot, ≥ 60 s gehalten → kleiner Chip + 10 XP | `EffectsMarket:ReadWell` (WP5) |
| 5 | Gewinn-Transfer | leuchtende Röhre fliegt von der Börse zum eigenen Tower, CR-Zähler rollt | `EffectsTower:TransferTube` (WP8) |
| 6 | Crash-Alarm | 3 min Warnstufe, roter Himmel, Sirenen, Bär stapft auf die Plaza; Vertrauens-Kugeln sammeln | `EffectsEvent:Bear` (WP11) + WorldLook (WP7) |
| 7 | Rally | grüne Polarlichter, goldener Bulle umrundet den Ring, Berühren = Bullen-Bonus | `EffectsEvent:GoldenBull` (WP11) |
| 8 | Börsengang | du gehst zur Glocke, läutest, dein Ticker erscheint auf der IPO-Wand, Konfetti-Beams, Server-Banner, Kräne bauen deinen Tower zurück, „Garage 2.0“ mit neuer Krone | `Prestige:IpoCeremony` (WP9) |
| 9 | Lizenz-Aufstieg | Stempel-Animation in der Akademie-Kapsel, goldene Lizenzkarte, Basis-Erhöhung „regnet“ ins Depot | `Prestige:LicenceUp` (WP9) |
| 10 | Erster Hypersportwagen | Drehteller-Enthüllung im Showroom, Fahrt direkt auf den Autobahnring | `Garage:Reveal` (WP7) |
| 11 | Millionär-Titel | goldener Kopftitel, eigene Fanfare | `Prestige:TitleUp` (WP9) |
| 12 | Hall-of-Fame-Statue | Wochen-Top-3 der Liga als goldene Avatar-Statue auf der Plaza | `LeaderboardService` (WP9) |

---

# B) Gameplay-Spezifikation

## B1. Kern-Loop, Rhythmen, Sitzungen
```
        ┌──────── EILMELDUNG LESEN (8 s „Händler lesen …“, Tiko-Ampel, Kalender) ────────┐
        ▼                                                                                  │
  HANDELN (AKY-Depot) ──Gewinn über Basis──► GEWINN-TRANSFER (Bau-Kurs der Lizenz) ──► CR ──► BAUEN
        ▲                                                                                  │  Etagen · Abteilungen · Personal · Effizienz
        │   Trader-XP → LIZENZ (Prüfung) → Basis↑, Bau-Kurs↑, Instrumente, Tower-Stufen-Tore  ▼
        └── Ruf + Lizenz = TRADER-FAKTOR (×1,00…×1,82 auf Turm-Einkommen) ◄── TURM-EINKOMMEN (Tresor, offline)
                                                                   │
                                     LIFESTYLE (Autos, Uhren, Deko) · BÖRSENGANG (Prestige) → Sterne, +0,25, neue Krone
```
| Rhythmus | Takt (alles deterministisch aus der globalen Tick-Uhr, auf allen Servern gleich) | Warum es zieht |
|---|---|---|
| Schlagzeile | Ø alle 40 s im ganzen Markt (Fakt 55 % / Gerücht 25 % / „wie erwartet“ 20 %) | ständige kleine Entscheidungen |
| Börsentag | 20 min: :00 **Glocke** bei Sonnenaufgang (Gewinn-Transfer frei, Tagesbilanz, Ruf-Punkte) · :03/:07/:11/:15 Quartalszahlen (je 3 Firmen) · :10 Makro-Termin · :10 **Welt-Event** · :19 Dividenden-Ex-Tag | Sitzungsanker, ≥ 10-min-Sitzungen (Creator Rewards) |
| Stündlich | Börsentag-Index `% 3 == 0`: **Glocken-Moment** an der Glocke (:00), **Sky-Show** in der Nacht (:15) | Treffpunkt Plaza |
| ~3,5 h (Seed-Plan) | unangekündigter Crash oder Rally mit 3-min-Warnstufe | Drama für den ganzen Server |
| Täglich 00:00 UTC | Login-Kalender, 3 Tagesquests, Akademie-Lektion, Gratis-Sofortbau-Token, Ruf-Abbau-Prüfung; 19:00 Berlin **Power-Hour** (x2 Trader-XP, 60 min) | tägliche Rückkehr |
| Wöchentlich (Berlin-Zeit, Sommer/Winterzeit automatisch §B10.4) | Mo 00:00 UTC neue Woche (Seed, Liga) · Mi 19:00 **Rally-Mittwoch** · Fr 19:00 **Crash-Freitag** · Sa 17:00 **IPO-Erstnotiz** · Sa 18:00 **Admin-Abuse** (Besitzer live, sonst 18:15 automatische Samstags-Show) · So 20:00 **Bilanz-Sonntag** (Liga-Finale, Top-10-Hologramme) | CCU-Spitzen |
| Saison | 4 Wochen (Thema, Skyline-Pass 50 Stufen, 2–4 IPO-Firmen, Deko-Set, Auto, Fassade) | langfristige Frische |

Sitzung eines Rückkehrers (Ziel Median 25–35 min):
1. **Willkommen zurück** (Glas-Sheet, 2 s Vorher/Nachher-Kamera auf den eigenen Tower via zwei ViewportFrames): Tower offline
   +X CR, Dividenden +Y AKY, ausgeführte Orders („Verlust-Stopp bei Voltaris hat dich geschützt“), Bots („Trend-Bot +2,1 %“),
   fertige Bauten, Auto-Transfers. Großer Knopf **EINSAMMELN** (Zähler rollt mit Feder).
2. Login-Kalender, Quests ansehen; Pillen oben Mitte: nächste Glocke, nächstes Welt-Event, nächster Termin der Watchlist.
3. Handeln um News/Termine, Schutz-Orders setzen; Gewinn-Transfer an der Glocke.
4. CR ausgeben: Etage, Abteilung, Personal, Effizienz, Deko; Bau starten.
5. Zur Plaza fahren (Welt-Event, Glocken-Moment), Respekt geben, Freund beim Bau helfen.
6. Vor dem Gehen: **„Zukunfts-Ich“**-Panel („In 8 h verdient dein Tower ≈ 14,2 Mio. CR · deine Orders schützen dich · Etage 21
   fertig in 41 min“).

## B2. Die ersten 10 Minuten (Skript `Tutorial`, WP9; jeder Schritt → `MetricsService.Funnel`)
Ziele: kein Absprung < 60 s, erste Automatisierung, erster Multiplikator, erster Stufen-Morph, Offline-Teaser. Jeder Schritt
ist überspringbar („Tutorial überspringen“ gibt dieselben Belohnungen). **Kein Robux-Angebot in der ersten Sitzung.**

| Zeit | Ablauf | Funnel |
|---|---|---|
| 0:00 | Ladebildschirm (ReplicatedFirst): ΛKYTEX-Splash ≤ 4 s, Disclaimer-Zeile „Spielgeld · erfundene Firmen · kein echtes Geld“ | 1 Joined, 2 SplashDone |
| 0:04 | Kamera-Anflug 4 s von der Skyline (goldene Stunde) über die Plaza auf den **eigenen Plot** (Hologramm „Hier entsteht dein Imperium“), jede Eingabe überspringt | 3 Spawned |
| 0:10 | **Tiko** erscheint (Hologramm-Roboter, Sätze ≤ 12 Wörter): „Das ist deine Garage. Lass uns dein erstes Büro bauen!“ Knopf **BAUEN** pulsiert | |
| 0:15 | **Etage 1 „Garage-Startup“** (gratis): 3-s-Kran-Szene, Neon „STARTUP“ flackert an. Einkommen 4 CR/s + 3 CR/s Gehalt, schwebende Zahlen fliegen in den Tresor | 4 Floor1 |
| 0:30 | Erstes Sammeln: durch das goldene Kassen-Tor gehen (Tresor ist mit 300 CR vorgefüllt) → Zähler rollt, CashRegister-Sound | 5 FirstCollect |
| 0:45 | Tiko: „Mehr Geld? Die Börse!“ **TRADE** öffnet das Terminal im **Übungsmodus** mit der Übungsaktie **ACAD** („Übung“-Etikett, §B8.6). Karte: „EILMELDUNG: Akademie meldet deutlich mehr Schüler“, Balken „Händler lesen …“ (8 s). Tiko: „‚deutlich' heißt: spürbare Bewegung. Tippe 10 % KAUFEN.“ | 6 TutorialTrade |
| 1:00–1:45 | Kurs steigt in 45 s um +15 % (nur für diesen Spieler berechnet). „Schutz an“ ist automatisch aktiv (Tiko erklärt in 1 Satz). Spieler tippt **VERKAUFEN** (nach 90 s automatisch bei +12 %): ruhiger grüner Tick, Profit-Arpeggio, ≈ +375 AKY | |
| 1:50 | **Gewinn in den Tower**: Bau-Kurs 40 → ≈ 15.000 CR, Röhre fliegt von der Börse zum Tower. Tiko: „Deine Börsen-Gewinne bauen deinen Tower.“ | 7 FirstTransfer |
| 2:00–2:40 | Etagen 2–5 (je 3-s-Szene, verkettet), bei Etage 4 **Stufe 3 „Loft“-Morph** – Gänsehaut-Moment #1 | 8 Stage3 |
| 2:45 | Abteilungs-Wahl auf Etage 2 (3 Karten, **Trading-Desk** empfohlen); **Praktikant P-1** rollt an den Tisch, Monitor zeigt Live-Chart | 9 FirstStaff |
| 3:15 | Gratis **Hausmeister-Bot** (sammelt den Tresor alle 60 s, solange du auf deinem Plot bist) – erste Automatisierung | 10 FirstAutomation |
| 3:45 | Echtes Terminal (Schicht „Einfach“): Tiko zeigt auf die nächste Fakten-News eines Azubi-Werts oder schlägt AKX36 vor; erster Live-Trade mit „Schutz an“ (−8 % / +15 %) | 11 FirstLiveTrade |
| 4:30 | 3 Starter-Quests gleiten ein („Baue Etage 7“, „Schließe einen Trade mit Gewinn“, „Fahr zum Börsensaal“) | |
| 5:00 | Gratis-Auto **Λ City** fährt aus der Garage; Wegpunkt-Beam zum Börsensaal (≈ 40 s Fahrt: Ring-Boulevard, Ticker-Wände, andere Tower) | 12 CarDriven |
| 6:00 | Börsensaal: Glocke, Bestenlisten, Hall of Fame; Akademie-Kapsel **Lektion 1 „Was ist eine Aktie?“** (30 s + 2 Fragen, +100 XP) | 13 Lesson1 |
| ~7:00 | 300 XP erreicht (Tutorial-XP), Mini-Prüfung „Setze ein Schutz-Paar“ schon erfüllt → **Azubi II**-Zeremonie (Stempel, kleines Konfetti, Basis 25.000 → 50.000) | 14 LicenceAzubi2 |
| 7:30 | Erste **Effizienz-Stufe** (10.000 CR) → HUD-Chip poppt „x1,10“; Tippen öffnet die Aufschlüsselung (Quelle, Wert, Restzeit) | 15 FirstMultiplier |
| 8:30 | „Zukunfts-Ich“-Teaser: „Dein Tower verdient auch offline – bis zu 8 h.“ Danach einmalig `AvatarEditorService:PromptSetFavorite` (pcall) | 16 FavoritePrompted |
| 9:30 | Glocken-Pille „Nächste Glocke in m:ss – Gewinn-Transfer wieder frei“; Login-Kalender Tag 1 abgeholt; bei 13+ einmal `ExperienceNotificationService:PromptOptIn` nach positivem Moment (§B11.9) | 17 TenMinutes |
| Tag 2 | erneuter Join | 18 Day2Return |

## B3. Stadt & Plots
- **Server-Größe 10** (Game Settings „Max Players 10“, ANLEITUNG), **10 Plots**. Beim Join: freier Plot, bevorzugt neben einem
  Freund im Server (`IsFriendsWithAsync`, pcall, gecacht), sonst der nächste freie im Uhrzeigersinn ab Plot 1.
- Beim Verlassen: 1,5-s-Kran-Abbau (Client-Effekt), Plot frei, Besucher werden höflich zur Plaza teleportiert
  (`AntiCheatService.NoteTeleport`).
- **Server baut nur die Hülle** (`TowerVisualService`, WP8): je Etage ≤ 8 Parts (Deckenplatte, 4 Glasfelder als je 1 Part,
  Ecksäulen als 2 Parts, Neonband), Aufzugskern, Krone ≤ 60 Parts, Plot-Ausstattung ≤ 40 Parts. Aufbau über Scheduler-Warteschlange
  ≤ 6 Etagen je Frame. Gesamt 10 Tower × 50 Etagen ≤ 4.600 Parts.
- **Client baut Interiors** (`TowerView`, WP8) aus dem replizierten Plot-Attribut `Layout` (kompakter String ≤ 2 KB,
  Format §C12.3): nur für den Tower, in dem man ist oder < 80 Studs davor steht, Etagen ±k um die Kamera (k je Grafikstufe
  0/1/2/4), ≤ 150 Parts je Etage aus Pools, Aufbau ≤ 1,5 ms je Frame. Andere Tower zeigen beleuchtete Fenster (Neon-Streifen).
- **Streaming:** Plaza, Börsensaal, Ringstraßen `ModelStreamingMode = Persistent`; jede Tower-Hülle `Atomic` +
  `LevelOfDetail = StreamingMesh` (Skyline bleibt aus der Ferne sichtbar; in Studio verifizieren); eigener Plot
  `PersistentPerPlayer` + `Model:AddPersistentPlayer(p)`. Stadt-Kulisse `Atomic` je Block.
- **Teilebudget Server:** Stadt statisch ≤ 12.000 (Aufbau beim Start ≤ 400 Parts je Frame) · Tower ≤ 4.600 · Events/Pickups-
  Anker ≤ 300 · gesamt ≤ 17.000.

## B4. Tower
### B4.1 Maße
Etagenhöhe 12 Studs (Platte 1 Stud), Grundfläche je Stufe: Stufen 1–4 40 × 40, ab Stufe 5 56 × 56, Rücksprung ab Etage 31
auf 52 × 52, ab Etage 41 auf 48 × 48. Aufzugskern 10 × 10 (Mitte, Glas-Kabine). 50 Etagen = 600 Studs + Krone ≤ 80 Studs.
Erdgeschoss = Lobby mit Tresor, Respekt-Säule, Aufzugstür, Etagen-Panel.

### B4.2 Die 12 Stufen (je eigene Silhouette; Tor = Lizenz, die Robux nie überspringen)
| # | Stufe (DE / EN) | Etagen | Außen-Signatur | Tor |
|---|---|---|---|---|
| 1 | Garage-Startup / Garage Startup | 1 | Rolltor, Neon „STARTUP“ | – |
| 2 | Kiosk-Büro / Kiosk Office | 2–3 | Markise, erstes Glas | – |
| 3 | Loft | 4–6 | Klinker + Glas, Dachterrasse | – |
| 4 | Bürohaus / Office Block | 7–9 | Fensterbänder, blaues Neonband | – |
| 5 | Glas-Office | 10–13 | volle Glasfassade | Azubi II |
| 6 | Business-Tower | 14–17 | abgetreppte Krone, Dach-LED | Azubi III |
| 7 | Hochhaus / High-Rise | 18–21 | senkrechte Neon-Finnen | Trader I |
| 8 | Wolkenkratzer / Skyscraper | 22–25 | Zwillingskrone, LED-Fassaden-Ticker (zeigt AKX36-Farbe, nie eigenes G/V) | Trader I |
| 9 | Skyline-Tower | 26–30 | beleuchtete Turmspitze, Himmelsgarten | Trader II |
| 10 | Mega-Tower | 31–36 | **Helipad**, Leuchtfeuer, Suchscheinwerfer | Trader III |
| 11 | Hyper-Spire | 37–43 | Sky-Lounge-Ring, Holo-Bänder | Fondsmanager I |
| 12 | ΛKYTEX Orbit-Spire | 44–50 | Antennen-Beam in die Wolken, Holo-Krone mit ΛKYTEX-Ring | Fondsmanager I **und** ≥ 1 Börsengang |
0 Etagen = Bauplatz mit Garagen-Rolltor (Stufe 1 ohne Büro). Börsengang ab abgeschlossener Etage 25 (§B9.6).

### B4.3 Abteilungen (eine je Etage; Wechsel kostet 25 % der Etagenkosten, sofort; `Config.Tower.Rooms`)
| Schlüssel | Name | Raum-Faktor auf die eigene Etage | Zusatzwirkung (nur Turm) | ab Stufe |
|---|---|---|---|---|
| `Office` | Büro | ×1,00 | – | 1 |
| `Desk` | Trading-Desk | ×1,25 | Monitore zeigen deine Live-Positionen | 1 |
| `Cafe` | Smoothie-Café | ×0,60 | Personal-Boni auf Etagen ±2 ×1,20 | 3 |
| `Garage` | Garagen-Ebene | ×0,40 | +4 Auto-Plätze, Auto-Aufzug | 3 |
| `Marketing` | Marketing-Studio | ×0,80 | +5 % Turm-Einkommen je Studio (max. 3); Respekt von Besuchern zählt doppelt | 4 |
| `Vault` | Tresor-Etage | ×0,50 | Tresor-Kapazität +50 % je Etage (max. 2) | 4 |
| `Lab` | Research-Labor | ×0,80 | Basis-Einkommen der Etagen direkt darüber/darunter ×1,15 | 5 |
| `Server` | Server-Raum | ×0,70 | alle Personal-Boni im Turm ×1,10 je Raum (max. 3) | 5 |
| `Lounge` | Lounge | ×0,50 | +1 h Offline-Deckel je Lounge (max. +4 h); Respekt wirkt 2 h statt 1 h | 6 |
| `BotLab` | Bot-Labor | ×1,10 | Zuhause der Strategie-Bots (Roboter + Live-Dashboards, rein optisch) | 6 |
| `Penthouse` | Penthouse (nur oberste Etage) | ×0 | +10 % Turm-Einkommen, 8 Deko-Slots, Pool/Balkon | 10 |
„Auto-Plan“-Knopf: Tiko schlägt eine Belegung vor (Greedy nach Einkommen). Nachbar-Effekte werden im Tower-Menü als Pfeile gezeigt.

### B4.4 Personal (Roboter aus Parts; 2 Plätze je Etage, 3 mit Pass „Personal+“; einstellen sofort; `Config.Tower.Staff`)
| Schlüssel | Name | Bonus auf die Etage | Kosten (× `max(C(n), 500)`) | ab Stufe |
|---|---|---|---|---|
| `Intern` | Praktikant P-1 | +10 % | ×1 | 2 |
| `Analyst` | Analyst A-3 | +25 % | ×3 | 3 |
| `Senior` | Senior-Droid S-7 | +50 % | ×9 | 5 |
| `Quant` | Quant-Mainframe Q-9 | +100 % | ×25 | 8 |
| `Janitor` | Hausmeister-Bot (1 je Tower, gratis im Tutorial, kein Platz) | sammelt den Tresor alle 60 s, solange der Besitzer auf dem Plot ist | 0 | 1 |
| `Security` | Sicherheits-Bot (Deko, 1 je Tower) | patrouilliert in der Lobby | 50.000 CR | 8 |
Entlassen: 0 % Rückerstattung, Bestätigung. Roboter-Animation: CFrame-Wippen/Kopfdrehen im PreRender-Loop (nur nahe Etagen).

### B4.5 Raum-Stufen L1–L5 (je Etage)
Faktor ×1,00 / ×1,25 / ×1,50 / ×1,80 / ×2,20; Kosten für die nächste Stufe ×1 / ×2,5 / ×6 / ×15 von `max(C(n), 500)`.

### B4.6 Tresor, Sammeln, Offline
- Online-Einkommen fließt in den **Tresor** (Lobby). Kapazität = **20 min** aktuelles Einkommen (+50 % je Tresor-Etage, max. 2).
  Voll → Tresor glüht rot, füllt nicht weiter. HUD-Ring zeigt Füllstand.
- Sammeln: durch das goldene Kassen-Tor gehen, HUD-Knopf (nur auf eigenem Plot, Server prüft Abstand ≤ 70 Studs zur Plot-Mitte),
  Hausmeister-Bot (60 s, nur auf dem Plot), Pass **Auto-Kassierer** (alle 3 s, überall).
- **Offline:** ab ≥ 60 s Abwesenheit aus Server-`SavedAt`: `Einkommen_dauerhaft × Rate × min(Abwesenheit, Deckel)`.
  Rate 50 % (+5 Pp je Vorstand-Stufe „Tresor“, max. +40 Pp; Pass Offline-Tresor +15 Pp; Obergrenze 90 %). Deckel 8 h
  (+1 h je „Tresor“-Stufe, +1 h je Lounge (max. 4), Club +4 h; Pass Offline-Tresor setzt mindestens 24 h; Obergrenze 24 h).
  Bauten laufen offline weiter. Zeit-Boosts gelten offline **nicht**. Auszahlung über die Willkommen-Karte.
- Einkommen tickt serverseitig 1×/s (ein Batch-Job für alle Spieler); der Client interpoliert den Zähler zwischen
  State-Updates (alle 5 s oder bei Änderung).

### B4.7 Bauen
- Eine Baustelle (Kran) gleichzeitig. Etagen 1–9: 3 s (nur Szene). Ab Etage 10: `min(90 min, 20 s × 1,33^(n−10))`
  (Etage 15 ≈ 83 s, 20 ≈ 5,8 min, 25 ≈ 24 min, ab 30: 90 min). Abteilungen, Stufen, Personal, Effizienz: sofort.
- Beschleuniger: 1 Gratis-Sofortbau-Token je UTC-Tag (Login-Kalender) · **Bau-Hilfe**: Besucher tippt die Baustelle → −10 % der
  Restzeit, max. 3 Helfer je Etage, je Helfer 1× je Etage (Helfer bekommt +25 Saison-XP, nie Trader-XP) · Pass **Bau-Crew Pro** −50 % · Vorstand „Tempo“ −10 %/Stufe (max. 5) · Produkte **Bau-Express** · Admin
  „Bau-Boom“. Untergrenze: 25 % der Grundzeit.
- Fertig, während man woanders ist: Toast + optionale Mini-Kamera „Ansehen“.

### B4.8 Deko & Komfort (v1: feste Slots; freies Raster v1.1)
- 60 Deko-Teile in 6 Sets (Startup, Corporate, Glas & Chrom, Neon-Cyber, Luxe-Gold, Zen-Garten) + Saison-Set (S1 „Neon-Skyline“
  8 Teile): Schreibtische mit Live-Mini-Monitor (SurfaceGui, budgetiert), Sofas, Pflanzen, Aquarium (getweente Fische),
  Skulpturen, Part-„Kunst“, Trophäen (Liga), Neon-Schilder (ΛKYTEX-Striche), Teppiche, Lampen (echte Lichter im Budget).
- **3 Slots je Etage**, 8 im Penthouse. Kauf in den **Lager** (Anzahl je Teil), Platzieren/Entfernen gratis.
- **Komfort**: jedes Teil 1–5 Punkte; je Etage +0,5 % Etagen-Einkommen je Punkt, max. +10 % je Etage.
- Beim Börsengang wandert alles ins Lager; „Layout merken“ stellt die Deko beim Wiederaufbau automatisch wieder auf.

### B4.9 Fassaden, Neon, Kronen, Name
- 7 Fassaden: Glas-Blau (Standard), Obsidian (Login Tag 14), Marmor-Weiß (Erfolg), Neon-Cyber (Erfolg), Gold-Luxe (Pass
  Neon-Fassaden-Kit), Holo-Prisma (Saison-Premium), Polar (Login Tag 28). Neon-Farbwahl: Accent, Up, Down, Cyan `#22d3ee`,
  Purple `#8b5cf6`, Gold `#facc15`.
- **Börsengang-Krone**: Silber (1 BG), Gold (3), Platin (5), Holo (10), Orbit-Ring (20).
- **Tower-Name** nur aus Wortbausteinen (40 Adjektive × 40 Nomen + „Tower“, DE/EN je Baustein) – kein Freitext.
- Fassaden-LED zeigt die AKX36-Farbe des Tages, **nie** das eigene G/V.

### B4.10 Aufzug, Besuche, Privat-Etagen
- **Aufzug:** Etagen-Panel (UI) → Client-Kinoszene 1,5 s (Türen zu, Kabine fährt im Schacht, Kamera innen, ElevatorDing, Türen
  auf); Server teleportiert die Figur (Ziel-CFrame + Wurzelhöhen-Versatz, `AntiCheatService.NoteTeleport`). Keine
  physikalischen Plattformen.
- **Besuchen:** Tower-Tour-Kiosk auf der Plaza (Liste nach Höhe), Spielerliste oder Hingehen. Alle Tower sind besuchbar, nichts
  kann gestohlen oder verändert werden. Besitzer kann bis zu 5 Etagen „Privat“ schalten (Aufzug-Panel zeigt sie für Besucher
  gesperrt; Türen nur lokal offen → AntiCheat ignoriert lokal versteckte Geometrie).
- Besucher können: Respekt geben (§B11.3), beim Bau helfen, Emote-Reaktionen.

## B5. Tower-Ökonomie (Formeln; Startwerte geprüft mit `tools/economy_sim.py`)
### B5.1 Etagen
- Basis-Einkommen Etage n: `I(n) = 4 × 1,30^(n−1)` CR/s. Gehalt: 3 CR/s immer.
- Kosten: Etage 1 gratis, Etage 2 = 1.000 CR, danach je Etage × Faktor des Bandes: Etagen 3–12 ×1,50 · 13–25 ×1,56 · 26–40 ×1,58 ·
  41–50 ×1,60 (gerundet auf ganze CR). Summe aller 50 Etagen 5,23e12 CR.

| Etage | Kosten CR | Basis CR/s | Bauzeit | | Etage | Kosten CR | Basis CR/s | Bauzeit |
|---|---|---|---|---|---|---|---|---|
| 1 | 0 | 4,0 | 3 s | | 22 | 4.922.192 | 988 | 10,2 min |
| 2 | 1.000 | 5,2 | 3 s | | 25 | 18.686.689 | 2.171 | 24 min |
| 4 | 2.250 | 8,8 | 3 s | | 26 | 29.524.969 | 2.823 | 32 min |
| 7 | 7.594 | 19,3 | 3 s | | 30 | 183.999.992 | 8.062 | 90 min |
| 10 | 25.629 | 42,4 | 20 s | | 31 | 290.719.987 | 10.480 | 90 min |
| 13 | 89.957 | 93,2 | 47 s | | 37 | 4.522.904.446 | 50.585 | 90 min |
| 14 | 140.334 | 121,2 | 63 s | | 40 | 17.839.746.280 | 111.135 | 90 min |
| 18 | 831.113 | 346,0 | 3,3 min | | 44 | 116.914.561.223 | 317.413 | 90 min |
| 21 | 3.155.251 | 760,2 | 7,7 min | | 50 | 1.961.500.847.186 | 1.532.090 | 90 min |
Volle Tabelle: `python3 tools/economy_sim.py --table`. `Shared/TowerMath` rechnet exakt dieselben Werte (Test vergleicht 50 Werte).

### B5.2 Etagen-Einkommen und Turm-Einkommen
```
Etage(n)      = I(n) × Raum-Faktor × Stufen-Faktor(L) × (1 + Σ Personal-Boni × Café/Server-Faktoren) × Nachbar-Faktoren × (1 + Komfort)
Basis         = 3 + Σ Etage(n)
Einkommen/s   = Basis × Perm × TraderFaktor × Pässe × VIP × Club × Premium × Zeitlich
Offline/s     = Basis × Perm_ohne_Sozial × TraderFaktor × Pässe × VIP × Club × Premium × OfflineRate   (ohne Zeitlich,
                ohne Freunde-/Respekt-Anteil – die gelten nur in der Sitzung)
```
| Gruppe | Bestandteile | Max. |
|---|---|---|
| **Perm** (additiv) | 1 + 0,10 × Effizienz-Stufen (max. 20 je Lauf) + 0,25 × Börsengänge (max. 20 gezählt) + 0,10 × Vorstand „Wachstum“ (max. 10) + 0,02 × Album-Sektorsätze (max. 6) + 0,10 × Freunde im Server (max. 4) + 0,01 × Respekt erhalten (max. 20, je 1 h; Lounge 2 h) + 0,05 × Marketing-Studios (max. 3) + 0,10 Penthouse | 9,97 |
| **Trader-Faktor** (×, nur Skill) | (1 + Lizenz-Bonus 0 … 0,40) × (1 + 0,03 × Ruf 0 … 10) | ×1,82 |
| **Pässe** (×, ehrlich) | 1 + [x2-Pass] + 2 × [x3-Pass] → x2 allein ×2, x3 allein ×3, beide ×4 („Zusammen x4“ steht vor dem Kauf im Shop) | ×4 |
| VIP / Vorstands-Club / Roblox Premium | ×1,10 / ×1,15 / ×1,10 | ×1,39 |
| **Zeitlich** (Deckel) | `min(10, Boost × Server × Event)`; Boost = stärkster aktiver persönlicher Boost (x2, x5, Bullen-Bonus x1,5; andere pausieren); Server = max(Bullen-Parade ×1,5, Glocken-Moment ×1,2); Event = Golden Hour/Admin ×2 oder ×3 (Event nie > ×3) | ×10 |
Wirkt auf: Turm-Einkommen, Gehalt, Tresor, Offline (ohne Zeitlich), einkommens-skalierte CR-Belohnungen (Quests, Events,
Bau-Gutscheine nutzen „Dauer-Einkommen ohne Zeitlich“). **Wirkt nie auf:** AKY, Gewinn-Transfer, Dividenden, Trades.

**HUD-Chip** zeigt `Perm × TraderFaktor × Pässe × VIP × Club × Premium × Zeitlich` gerundet, z. B. „x7,4“. Tippen öffnet die
Aufschlüsselung: jede Quelle mit Wert, Herkunft-Etikett („verdient“ / „Skill“ / „gekauft“ / „Event“) und Restzeit.

### B5.3 Effizienz-Stufen (CR-Senke, HUD-Multiplikator „kaufbar mit Spielgeld“, Wunsch 16)
+0,10 Perm je Stufe, max. **20** je Lauf, Kosten `10.000 × 3^k` CR (k = 0…19; Stufe 20 kostet 1,16e13). Reset beim Börsengang.

### B5.4 Ergebnisse der Simulation (Spieler „gratis, guter Trader“: 1,5 h aktiv/Tag, r = 2,5 %/Börsentag, 700 Trader-XP/h)
| Meilenstein | Zeit | Einkommen/s | Handels-Anteil aktiv (direkt / gesamt) |
|---|---|---|---|
| Etage 4 (Loft) | 2 min | 32 | 30 % / 30 % |
| Etage 7 | 6 min | 84 | 15 % / 15 % |
| Etage 10 (Azubi II) | 18 min | 298 | 15 % / 18 % |
| Etage 14 (Azubi III) | 1,3 h | 2.190 | 13 % / 23 % |
| Etage 18 (Trader I) | Tag 2 | 16.900 | 23 % / 35 % |
| Etage 25 → 1. Börsengang | Tag 3 | ≈ 50.000 | 11 % / 25 % |
| Etage 31 (Trader III) | Tag 13 | 1,8e6 | 3 % / 34 % |
| Etage 37 (Fondsmanager I) | Tag 26 | 1,0e7 | 6 % / 41 % |
| Etage 44 (Orbit-Spire) | Tag 33 | 2,8e7 | 2 % / 40 % |
| **Etage 50** | **Tag 41** | ≈ 1e8 | – |
Vergleich: Nicht-Trader (nur Akademie/Quests, 300 XP/h) 1. Börsengang Tag 6, Etage 50 Tag 79 · Pässe x2+x3+VIP Etage 50 Tag 39
(nur −5 %, weil Lizenz-Tore bremsen) · teuerster Einzelpreis 4,9e13 (Quant-Personal Etage 50) · höchster Kontostand 1,3e13.

## B6. Markt (Engine = MARKET.md; hier nur Zusammenfassung + verbindliche Änderungen)
### B6.1 Engine (bindend aus MARKET.md)
Globaler deterministischer Markt: `Preis = f(Wochen-Seed, 1-Hz-Tick, Event-Liste)` (§5); Spieler sind Preisnehmer (§0 D2);
Lesefenster 8 s + Rampe 45 s (§6.1); Stärke-Wörter leicht 1–3 % / deutlich 3–6 % / massiv 6–12 % / historisch 12–25 %;
Fakt 55 % · Gerücht 25 % (★/★★/★★★ bestätigt 35/60/85 %) · „wie erwartet“ 20 %; Sektor-News Ø 10 min; Makro :10 mit Matrix
§6.4; Quartalszahlen je Firma alle 3 Börsentage; 8 Analysten mit live gemessener Trefferquote; Dividenden-Ex-Tick senkt den
Kurs (§6.3); Crash/Rally Ø 3,5 h mit 3-min-Warnstufe, Crash −12…−30 % × β, Erholung 40–60 % (§6.5); Kerzen-Ringe 1s×300,
5s×360, 1m×1440 (§9); Frame 9 + 10·n Byte (§10.2); Geld in Cent, Rundung zugunsten des Hauses (§12.2); Offline-Abgleich exakt
(§11.5); Fill-Audit (§13 #17). Zeit: Tick = `floor(unixMs/1000) − EPOCH`, EPOCH = Mo 2026-01-05 00:00 UTC, Börsentag 1.200 Ticks.

### B6.2 Instrumente (36 Firmen + 7 ETFs; Änderungen gegenüber MARKET.md §4.2 **fett**)
| ID | Kürzel | Name | Sektor | Klasse | Start AKY | Div. % | Lizenz-Satz |
|---|---|---|---|---|---|---|---|
| 1 | **CGVO** | **Cognivo KI** (Lern-Roboter mit KI) | Tech | Normal | 240 | – | Trader |
| 2 | **KRWK** | **Kernwerk Systems** (Fabrik-Software) | Tech | Stabil | 180 | 0,4 | Azubi |
| 3 | QTRX | Quantorix Quantum | Tech | Wild | 42 | – | Fonds |
| 4 | LMRA | Lumora Chips | Tech | Normal | 115 | 0,2 | Trader |
| 5 | NMBY | Nimbusly Cloud | Tech | Stabil | 88 | 0,3 | Azubi |
| 6 | PXWK | Pixelwerk Robotics | Tech | Wild | 27 | – | Fonds |
| 7 | SNWK | Sonnwerk Solar | Energie | Normal | 64 | 0,3 | Azubi |
| 8 | FSNT | Fusionaut | Energie | Wild | 19 | – | Fonds |
| 9 | NBRZ | Nordbrise Wind | Energie | Stabil | 52 | 0,6 | Azubi |
| 10 | HDRV | Hydrava | Energie | Normal | 36 | – | Fonds |
| 11 | VLTR | Voltaris | Energie | Normal | 98 | 0,2 | Trader |
| 12 | GTHM | Geotherma | Energie | Stabil | 74 | 0,7 | Trader |
| 13 | ORBV | Orbivo Space | Mobilität | Wild | 155 | – | Fonds |
| 14 | MGLN | Magliner | Mobilität | Stabil | 61 | 0,5 | Azubi |
| 15 | VLCT | Velocitra Motors | Mobilität | Normal | 210 | 0,1 | Azubi |
| 16 | DRNR | Dronaro | Mobilität | Normal | 33 | – | Trader |
| 17 | ARLF | Aerolift | Mobilität | Wild | 24 | – | Fonds |
| 18 | RTXO | Robotaxo | Mobilität | Normal | 47 | – | Trader |
| 19 | KNSX | Knusperix | Konsum | Stabil | 58 | 0,8 | Azubi |
| 20 | BLBR | Blubbro | Konsum | Stabil | 41 | 0,9 | Fonds |
| 21 | SNKA | Sneakora | Konsum | Normal | 132 | 0,3 | Trader |
| 22 | BGPT | Burgerplanet | Konsum | Stabil | 77 | 0,7 | Azubi |
| 23 | **PFFR** | **Pfotenfreund** (Tierbedarf) | Konsum | Normal | 29 | 0,2 | Fonds |
| 24 | SPWK | Spielwerk Toys | Konsum | Normal | 45 | 0,4 | Trader |
| 25 | ARCN | Arcadeon Games | Gaming | Normal | 96 | 0,1 | Azubi |
| 26 | STMR | Streamora | Gaming | Normal | 143 | – | Trader |
| 27 | PLVO | Playverso VR | Gaming | Wild | 38 | – | Fonds |
| 28 | MEMT | Memetastic Media | Gaming | Wild | 12 | – | Fonds |
| 29 | ESPV | Esportiva Arena | Gaming | Normal | 54 | 0,2 | Trader |
| 30 | NNBT | Neonbeat Records | Gaming | Stabil | 66 | 0,5 | Azubi |
| 31 | TWBK | Towerbank | Finanzen | Stabil | 118 | 1,0 | Azubi |
| 32 | SKLA | Skylinea | Finanzen | Stabil | 84 | 1,1 | Azubi |
| 33 | GLDR | Goldader Mining | Finanzen | Normal | 71 | 0,4 | Trader |
| 34 | SCHF | Sicherhafen | Finanzen | Stabil | 102 | 1,2 | Trader |
| 35 | KLPY | Klickpay | Finanzen | Normal | 89 | – | Fonds |
| 36 | BKRZ | Baukranz | Finanzen | Normal | 49 | 0,5 | Fonds |
- **Lizenz-Sätze:** Azubi = 12 Werte (nur Stabil/Normal, je 2 pro Sektor) + AKX36 · Trader = Azubi + 12 + 6 Sektor-ETFs +
  6 Themen-Körbe · Fonds = alle 36 + IPOs. Wild-Werte erst ab Fondsmanager („Hype-Firmen“).
- **ETFs:** 40 AKX36 („AKYTEX 36“, gleichgewichtet – Einsteiger-Empfehlung, ab Azubi), 41–46 AKXT/AKXE/AKXM/AKXK/AKXG/AKXF (ab Trader).
- **Themen-Körbe** (ab Trader I, 1 Tipp kauft 4–6 Werte gleichgewichtet, je Wert eine normale Market-Order, Klumpen-Grenze
  gilt je Wert): KI-Korb (CGVO, LMRA, NMBY, KRWK), Raumfahrt-Korb (ORBV, ARLF, MGLN, DRNR), Dividenden-Korb (TWBK, SKLA, SCHF,
  NBRZ, GTHM, KNSX), Klima-Korb (SNWK, NBRZ, GTHM, VLTR, HDRV), Snack-Korb (KNSX, BGPT, BLBR, SNKA), Gaming-Korb (ARCN, STMR, ESPV, NNBT).
- **IPO-Plätze** 100–139 (nie wiederverwendet); Tutorial-Übungsaktie **ACAD = 250** (nie im Frame, nur per Spieler §B8.6).
- Jeder Name/jedes Kürzel wird vor Release einmal gesucht (keine echte bekannte Firma, kein Kürzel eines großen echten Werts) –
  Pflicht-Schritt in TESTPLAN (WP12). Logos = UI-Formen (Buchstabe + Verlauf + Grundform in Sektorfarbe).

### B6.3 Events, Kalender, Live-Termine
- Crash-Freitag Fr 19:00 Berlin (Plan-Event mit Kalender-Eintrag Tage vorher, Plaza-Countdown die ganze Woche), Rally-Mittwoch
  Mi 19:00 Berlin (telegrafierte Sektor-Rally des Sektors `Woche % 6`), Samstags-Show-Rally Sa 18:15 Berlin (+15 % Sektor der
  Woche, wird abgesagt, wenn der Besitzer vorher Admin-Abuse startet – über GlobalBus §B10.4).
- **IPO-Erstnotiz v1 (ohne Zeichnung):** Sa 17:00 Berlin + Admin. `T−24 h` Prospekt im Kalender (Fundamentaldaten, Sektor,
  Analysten-Hinweise), `T0` Instrument erscheint im Frame mit 60-s-Handelspause, Eröffnung = Ausgabepreis × (1 + pop), pop
  ∈ [−10 %, +40 %] korreliert mit Prospekt-Qualität (Skill), erster Börsentag Klasse Wild, danach eigene Klasse aus Config.
  Kaufbar ab Fondsmanager. Zeichnung mit Pro-rata-Zuteilung: **v1.1**. Saison 1: 4 IPOs (IDs 100–103): Neuronauten (T), Flora Energy (E),
  Mondwerk (M), Robochef (K).
- Handelspausen 10 s bei Admin-Aktivierung/verspäteten Bus-Events (MARKET §8.4), 60 s bei IPO-Erstnotiz.
- Markt-Events wirken **immer global**; nur Nicht-Markt-Events (Geldregen, Boosts, Konfetti) dürfen „nur dieser Server“ sein.

## B7. Trading-Terminal & Charts
### B7.1 Öffnen und Aufbau
Öffnen: HUD **TRADE** (groß, unten Mitte), Taste `T`, Gamepad Y halten, Terminal-Pult im Börsensaal, Trading-Desk-Monitor.
| Gerät | Layout |
|---|---|
| PC (≥ 1100 × 680) | links Watchlist (Sektorfarbe, Sparkline, % in BuilderMono, ▲/▼) · Mitte ChartView mit Zeitrahmen-Segment und Chart-Typ · rechts Order-Ticket + News-Feed · unten Tabs Positionen / Orders / Alarme / Kalender / Analyse |
| Handy | Vollbild-Sheet, 4 Tabs Chart · Order · Depot · News, feste Kauf/Verkauf-Leiste im Daumenbereich (Knöpfe ≥ 64 px), Wischen wechselt Instrument |
| Controller | Steuerkreuz Watchlist / Fadenkreuz kerzenweise · LB/RB Zeitrahmen · A Kauf-Sheet · X Verkauf-Sheet · Y Schutz-Paar · B zurück · rechter Stick Fadenkreuz |

### B7.2 Drei Schichten (wachsen mit der Lizenz, `Config.Progression.Licences[i].Layer`)
| Schicht | ab | Inhalt |
|---|---|---|
| **Einfach** | Azubi I | Firmen-Karten (Logo, Kurs, Trend-Pfeil, Stimmungspunkt), Linien-Chart, Chips „10 % · 25 % · Max“, „Schutz an“ standardmäßig an, **Tiko-Ampel**, Glossar-Tipps, Klumpen-Warnung |
| **Trader** | Azubi III (Kerzen), Trader I (Rest) | Kerzen/Hohl, alle Zeitrahmen, Indikatoren laut §B7.5, Kalender, Sektor-Heatmap, Themen-Körbe, Nachzieh-Stopp, freier Betrag (Stück oder AKY) |
| **Profi** | Fondsmanager I | Heikin-Ashi, Markttiefe (simuliert), Umsätze, Fundamentaldaten, Analysten-Trefferquoten, Korrelation, Performance-Analyse (TWR, Drawdown, Skill-Score); Tiko-Ampel aus |

### B7.3 Order-Ticket
- Große Knöpfe **KAUFEN** (UI-Variante Success, Up) / **VERKAUFEN** (Danger, Down). Chips **10 % · 25 % · Max** (Prozent vom
  Depotwert; Max = Klumpen-Grenze der Lizenz bzw. verfügbares Geld). Bestätigung ab 20 % Depotwert in einem Wert:
  „Sicher? Verteilen ist klüger.“ Kosten-Vorschau inkl. Gebühr und Spread (`PortfolioMath`).
- Ordertypen (nur erlaubte sichtbar): Azubi I **Sofort kaufen/verkaufen**, **Wunschpreis** (Limit), **Verlust-Stopp**,
  **Gewinn-Ziel**, **Schutz-Paar** (OCO; 1-Tipp „Schutz an“ −8 %/+15 %); Trader I + **Nachzieh-Stopp** (der **Sparplan** ist ein
  Bot-Preset ab Azubi III, §B8.5);
  Fondsmanager I (v1.1) **Leerverkauf 1×**. Laufzeit „bis Börsentag-Ende“ oder „24 h“ (Standard).
- Nie: Hebel, Optionen, Binär-/Up-Down, Futures, Krypto.

### B7.4 News-Karte, Tiko-Ampel, Drosselung
- **News-Karte („Dynamic Island“)** gleitet oben Mitte ein, **nur** wenn: Wert gehalten oder auf der Watchlist **und** Stärke ≥
  „deutlich“, oder Makro/Sektor/Crash/Rally/IPO. Höchstens **1 Karte je 30 s** (Rest in den News-Tab), Einstellung
  „Ruhemodus“ (nur Crash/Rally/Glocke). Inhalt: Schlagzeile mit fettem Stärke-Wort, Quellen-Sterne, Sektor-Chip, ruhiger
  Fortschrittsbalken **„Händler lesen …“** (8 s), danach „Markt reagiert“. **Kein Kauf-Knopf**, nur „Zum Chart“ und „×“.
- **Tiko-Ampel** (Schicht Einfach, optional bei Trader, aus bei Profi): bei Fakten-News nach 20 s grün/rot; bei Gerücht und
  „wie erwartet“ ein „?“ mit einem Erklär-Satz. (Backtest: Ampel-Strategie +5,7 %/Börsentag als Obergrenze.)
- News-Liste endlich: letzte 50 (kein endloser Feed).

### B7.5 Charts (nur GUI-Frames, 60 FPS)
- Zeitrahmen 1s · 5s · 1m · 5m · 15m · 1T (20 min) · 1W (140 min). Stile Kerzen, Hohl, Linie, Fläche (nur High/Ultra),
  Heikin-Ashi (Profi). Volumen-Streifen. Fadenkreuz + OHLC-Pille (Maus `InputChanged`, Touch ziehen, Steuerkreuz).
- Indikatoren (Port `js/indicators.js`, Farben aus `js/chart.js`: SMA20 `#f5b942`, SMA50 `#4f8cff`, SMA200 `#e056fd`, EMA9 `#00d1b2`,
  EMA21 `#ff7a45`, BB `#7c8cff`, VWAP `#ffd166`, RSI `#b388ff`): SMA/EMA ab Azubi III · Bollinger ab Trader I · RSI ab Trader II ·
  MACD, VWAP ab Trader III · Stochastik, ATR, Markttiefe, Umsätze ab Fondsmanager I. Max. 3 Indikator-Linien am Handy, 6 am PC.
- **Zeichenlinien = Preisalarme** (horizontale Linien; Trendlinien v1.1): Anzahl aus Know-how (§B9.3), Basis 3. Alarm löst
  serverseitig auf 1s-Kerzen aus → Toast (online) bzw. Willkommen-Bericht.
- **Markttiefe & Umsätze** sind clientseitig aus Frame (mid, Spread, Volumen) deterministisch erzeugt und als „simuliert“
  beschriftet (MARKET §2, `market.js`-Orderbuch-Idee).
- Split-Ansicht 1×2 ab Trader I, Multi-Chart 2×2 über Know-how (Fondsmanager I) – **nie für Robux**.
- **Renderer-Vertrag** (MARKET §10.4, REUSE §5.4): ein ungedrehter Frame mit `ClipsDescendants`; Preisfläche 72 %, Volumen 14 %,
  Indikator-Bereich optional, rechte Achse 56 px, Zeitachse 18 px; Pool beim `new()` (je Kerzen-Slot Körper + Docht + Volumen;
  60 Kerzen Handy / 90 / 120 PC je Stufe), ≤ 900 GuiObjects je Chart, nie `Instance.new` beim Ticken; Scale-Koordinaten
  `x = (i − 0,5)/N`, `y = 1 − (p − lo)/(hi − lo)`; schreiben nur bei Änderung; je Frame bewegt sich nur die Live-Kerze
  (`alpha = 1 − e^(−12·dt)`), y-Bereich `1 − e^(−6·dt)`; neue Kerze = ältesten Slot recyceln + Streifen-Container per Tween
  0,25 s Quint Out um eine Slot-Breite schieben (O(1)); Linien per `Path2D` (in Studio verifizieren) sonst gedrehte Segment-
  Frames in Pixeln, geteilt durch die akkumulierte UIScale, im Code auf das Plot-Rechteck geklemmt; **kein CanvasGroup**, kein
  `TextScaled` auf Achsen (BuilderMono, feste TextSize). Ziel < 0,3 ms je Frame am Handy.
- **Welt-Monitore** (Trading-Desk, Börsensaal, Lobby): Client-SurfaceGuis mit `Adornee` = Server-Part, die nächsten K live
  (K = 2/4/8/12 je Stufe), Rest eingefrorene Schnappschüsse; ≤ 2 Hz, 30–60 Kerzen ohne Beschriftung; `LightInfluence = 0`,
  `Brightness = 2`, `MaxDistance = 300`, `PixelsPerStud = 40`.
- **Ticker-Wände/Laufband**: gepoolte TextLabels in einem Container je Wand, Position je Frame verschoben (120-s-Schleife wie
  Website), aus dem Frame gespeist (0 extra Netz).

### B7.6 Feedback & Texte
Gewinn: grüner G/V-Tick + Profit-Arpeggio · Verlust: grauer Tick + Lerntipp („Tipp: Verlust-Stopp setzen“) · Nach 10
Verlust-Trades in 2 min: Tiko-Warnung + 30-s-Abkühl-Hinweis (keine Sperre). Sätze ≤ 12 Wörter, ein Fachwort je Bildschirm mit
Ein-Satz-Erklärung, Zahlen immer mit Vorzeichen und Farbe, Kürzel Tsd./Mio./Mrd./Bio./Brd. (DE) bzw. K/M/B/T/Qa (EN) über `Format`.

## B8. Depot & Brücke
### B8.1 Basis
Jede Lizenz hat eine **Basis** (§B9.2). Neues Depot: `Cash = Basis = 25.000 AKY`. Lizenz-Aufstieg: `Cash += neueBasis − alteBasis`,
`Basis = neueBasis` (zählt in der Liga als Fluss F, nicht als Rendite). Admin „AKY geben“: erhöht `Cash` **und** `Basis` gleich
(nie abhebbar) und taintet die Liga-Woche des Empfängers.

### B8.2 Gewinn-Transfer (AKY → CR)
```
Abhebbar   = max(0, min(FreiesCash, NAV − Basis, 0,06 × Basis))              -- Cent
Erlaubt    = NAV ≥ 1,02 × Basis  und  noch kein Transfer in diesem Börsentag  -- Fenster öffnet an jeder Glocke (:00)
CR         = floor(Abhebbar_Cent × BauKurs(Lizenz) / 100)
```
- Knopf „Gewinn in den Tower“ im Depot-Tab und im Tower-Menü zeigt: „Verfügbar 1.240 AKY → 49.600 CR (Bau-Kurs 40)“.
- **Auto-Transfer an der Glocke** (Einstellung, Standard an): im Glocken-Tick prüft das System für den **gerade beendeten**
  Börsentag (nur wenn in ihm noch kein Transfer stattfand) die Regel und überträgt – für Offline-Spieler beim Abgleich je verpasstem
  Börsentag, höchstens 72 (= 24 h). Ablauf technisch: `TowerService` hört `OrderService.OnBell` und ruft `OrderService.Withdraw(p)` –
  der Markt-Code kennt CR nicht (§C11.4).
- Die abgehobenen AKY verlassen das Depot (Fluss F in der TWR-Rechnung).
- **Einmalige Tutorial-Ausnahme:** der erste Transfer nach dem ACAD-Tutorial-Trade (§B8.6) ignoriert die 2-%-Schwelle (Grund `Tutorial`),
  damit der Lehrmoment „Börsengewinn baut den Tower“ in Minute 2 klappt (≈ 375 AKY → ≈ 15.000 CR).

### B8.3 Bau-Kurs (nur Lizenz; nie multipliziert)
Azubi I **40** · Azubi II **200** · Azubi III **800** · Trader I **1.500** · Trader II **3.000** · Trader III **6.000** · Fondsmanager I
**12.000** · Fondsmanager II **20.000** · Fondsmanager III **30.000** · Börsen-Legende **40.000** CR je AKY. Anzeige immer als
Kurs („Bau-Kurs: 1 AKY → 1.500 CR“), **nie** als „Gewinn × Faktor“. Höchstmöglicher Transfer je Börsentag (Legende, 6 % von
60 Mio.) = 1,44e11 CR.

### B8.4 Rettungsschirm („Starthilfe“)
Wenn `NAV < 0,5 × Basis` und keine offene Position/Order: 1× je UTC-Tag Knopf „Starthilfe“ → `Cash += 0,5 × Basis − NAV` +
Tiko-Lernkarte. Nie direkt abhebbar (NAV bleibt unter der Basis, bis Skill es zurückholt). Turm und Gekauftes sind von Verlusten
nie betroffen; das Gehalt (3 CR/s) läuft immer.

### B8.5 Strategie-Bots (handeln das Depot; nur Lizenz + Know-how, nie Robux)
| Preset | ab | Sichtbare Regel |
|---|---|---|
| Sparplan-Bot | Azubi III | kauft je Börsentag ein gewähltes ETF für X % (5–20 %) des freien Geldes |
| Trend-Bot | Trader I | kauft, wenn SMA20 > SMA50 (1m-Kerzen), verkauft beim Rückkreuzen, setzt automatisch Schutz-Paar |
| Dividenden-Bot | Trader III | hält die 6 Zahler mit der höchsten Rendite gleichgewichtet, gleicht je Börsentag aus |
| Dip-Käufer | Fondsmanager I | kauft nach −x % (3–8 %) Tagesrückgang eines Watchlist-Werts mit automatischem Verlust-Stopp |
| Wenn-Dann-Bot | v1.1 | 2 Bedingungen + 1 Aktion |
Plätze: Azubi III 1 · Trader I 2 · Trader III 3 · Fondsmanager I 4 · Legende 5. Kapital je Bot nach Bot-Stufe (Know-how) 10/15/20/25/30 %
des Depotwerts, alle Bots zusammen ≤ 30 %. Entscheidung 1× je Minute auf 1m-Schlusskursen über dieselbe `OrderEngine`
(Flag „Bot“) → online = offline (Offline-Abgleich max. 12 h). Lohn 0,02 % des verwalteten Kapitals je Börsentag (AKY-Senke).
**Not-Aus** je Bot und Tagesverlust-Bremse −5 % (Bot pausiert). Sichtbar als Roboter im Bot-Labor bzw. am Trading-Desk.

### B8.6 Tutorial-Übungsaktie ACAD (ID 250)
Pro Spieler serverseitig berechneter Pfad relativ zum Start-Tick `t0`: 100,00 AKY → News bei `t0 + 2 s` → nach 8 s Lesefenster
+15 % über 45 s (Smoothstep) → flach. Nie im Frame; Kurs kommt per `Replay`-Remote (1 Hz) nur an diesen Spieler. Kauf nur mit
Chip 10 % (Tutorial-Ausnahme von der Klumpen-Grenze unnötig: 10 % < 30 %). Verkauf nach 90 s automatisch bei +12 %. Ergebnis
geht ins Depot (Grund `Tutorial`); Transfer mit der einmaligen Ausnahme aus §B8.2. Einmal je Konto (`Flags.TutorialTrade`).

### B8.7 Research, Risiko, Liga-Teilnahme
- **Research-Vorlauf** (Quartals-Tendenz vor Zahlen): Basis 2 min vorher (Analysten-Urteile), über Know-how 3 min (ab Trader II)
  und 5 min (ab Fondsmanager I). Nie Robux, nie Tower.
- **Risiko-Büro** (Know-how): eigene Standard-Schutz-Paare (z. B. −5 %/+10 %), Klumpen-Warnung ab 15 %.
- Liga zählt nur Trades ≥ 2 % Depotwert, ≥ 60 s gehalten (§B11.1).

---

## B9. Fortschritt
### B9.1 Trader-XP & Trader-Level (nur Handeln/Lernen; nie Bauen, nie Robux)
| Quelle | XP | Deckel |
|---|---|---|
| Abgeschlossener Trade (Position ≥ 2 % Depotwert, ≥ 60 s gehalten) | +5 | 40 je UTC-Tag |
| … davon mit Gewinn nach Gebühren | +5 | 40 je Tag |
| Mit Schutz (Verlust-Stopp/Schutz-Paar) eröffnet | +2 | 40 je Tag |
| „Gut gelesen“ (§A7 #4) | +10 | 20 je Tag |
| Positiver Börsentag (≥ 3 zählende Trades, Rendite nach Gebühren > 0) | +40 | 12 je Tag |
| Akademie-Lektion erstmals / Wiederholung / perfektes Quiz | +100 / +10 / +30 | Wiederholung 5 je Tag |
| Tagesquest (Handels- oder Akademie-Art) / Wochenquest (Handels-Art) | +100 / +500 | 3 / 3 |
| Lizenzprüfung bestanden | +250 | – |
| Tutorial (Schritte 6–14) | +300 | einmalig |
| Liga-Stufe der Vorwoche (Bronze/Silber/Gold/Diamant) | +300 / +600 / +1.200 / +2.500 | 1 je Woche |
Ziel ≈ 700 XP je aktiver Stunde. Kostenlose Verdoppler für alle: Power-Hour (täglich 19:00 Berlin, 60 min ×2), Admin „XP-Rausch“.
**Trader-Level** (Anzeige, Know-how-Quelle): `XP_gesamt(L) = 12,5 × (L − 1)²` → L10 1.013 · L20 4.513 · L40 19.013 · L60 43.513 ·
L80 78.013 · L100 122.513. Spam bringt nichts (Deckel, Mindestgröße, Haltedauer).

### B9.2 Lizenzen (`Config.Progression.Licences`, eine Tabelle für WP4/WP6/WP9)
| # | Lizenz | XP | Prüfung (Akademie-Aufgaben, MARKET §14.3) | Basis AKY | Bau-Kurs | Turm-Bonus | Gebühr | Klumpen | offene Orders | Positions-Faktor | Schicht | Tor (Stufen / Börsengang) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Azubi I | 0 | – | 25.000 | 40 | +0 % | 0,10 % | 30 % | 5 | ×0,01 | Einfach | Stufen 1–4 |
| 2 | Azubi II | 300 | „Setze ein Schutz-Paar“ | 50.000 | 200 | +4 % | 0,10 % | 30 % | 5 | ×0,01 | Einfach | Stufe 5 |
| 3 | Azubi III | 1.200 | „Verteile auf 3 Sektoren“ + „1 geschützter Trade mit Gewinn“ | 100.000 | 800 | +8 % | 0,10 % | 30 % | 5 | ×0,01 | + Kerzen, SMA/EMA, Sparplan-Bot | Stufe 6 |
| 4 | Trader I | 3.000 | „Erkenne eine Wie-erwartet-Meldung“ + „Kaufe nach einer guten Nachricht“ | 250.000 | 1.500 | +12 % | 0,08 % | 40 % | 15 | ×0,2 | Trader | Stufen 7–8 · BG 1–2 |
| 5 | Trader II | 7.000 | – | 600.000 | 3.000 | +16 % | 0,08 % | 40 % | 15 | ×0,2 | Trader | Stufe 9 · BG 3–4 |
| 6 | Trader III | 14.000 | „Überstehe einen Crash mit < 10 % Verlust“ | 1.500.000 | 6.000 | +20 % | 0,08 % | 40 % | 15 | ×0,2 | Trader | Stufe 10 · BG 5–9 |
| 7 | Fondsmanager I | 28.000 | „Skill-Score ≥ 500 in einer Woche“ + „Nutze einen ★★★-Analysten bei Quartalszahlen“ | 4.000.000 | 12.000 | +25 % | 0,05 % | 50 % | 30 | ×5 | Profi | Stufen 11–12 · BG 10+ |
| 8 | Fondsmanager II | 50.000 | – | 10.000.000 | 20.000 | +30 % | 0,05 % | 50 % | 30 | ×5 | Profi | – |
| 9 | Fondsmanager III | 80.000 | „Liga-Stufe Gold“ | 25.000.000 | 30.000 | +35 % | 0,05 % | 50 % | 30 | ×5 | Profi | – |
| 10 | Börsen-Legende | 125.000 | „Liga-Stufe Diamant“ + „Max. Drawdown < 8 % in einer Woche mit Ø-Tagesrendite ≥ +1 %“ | 60.000.000 | 40.000 | +40 % | 0,03 % | 60 % | 50 | ×100 | Profi | – |
Positions-Faktor × `LiquidityBase` (Stabil 5 Mio., Normal 2 Mio., Wild 0,5 Mio., ETF 20 Mio. AKY) = max. Positionswert je Wert
(MARKET §11.6). Prüfungen sind gratis, nach 1 Börsentag wiederholbar, **nie** mit Robux überspringbar. Zeremonie §A7 #9.
Erwartung (Sim, 1,5 h/Tag): Azubi II ≈ 7–20 min · Azubi III ≈ 1,3 h · Trader I Tag 2 · Trader II Tag 5–6 · Trader III Tag 12 ·
Fondsmanager I Tag ≈ 25 · Fondsmanager II Tag ≈ 46 · Fondsmanager III Tag ≈ 75 · Legende Tag ≈ 118 (Elite-Flex). Legende schaltet
zusätzlich frei: Auto „Singularity“, goldenes Terminal-Theme, Titel „Börsen-Legende“.

### B9.3 Know-how (KH; Trading-Werkzeuge, nie Robux)
Quellen: +1 je Trader-Level ab 2, +3 je Lizenz, +1 je abgeschlossener Akademie-Serie (4 Lektionen) → bis zu 130 KH.
| Knoten | Stufen | Wirkung | KH je Stufe | Voraussetzung |
|---|---|---|---|---|
| `Alerts` Alarm-Linien | 5 | 3 → +3 je Stufe (max. 18 Zeichenlinien mit Alarm) | 1 | – |
| `Watch` Watchlists | 4 | 1 → +1 je Stufe (max. 5, je 12 Werte) | 1 | – |
| `Layouts` Terminal-Layouts | 3 | gespeicherte Layouts 1 → 4 | 1 | Trader I |
| `Monitors` Live-Monitore im Tower | 3 | +1 je Stufe (Grafikstufe deckelt) | 1 | – |
| `Risk` Risiko-Büro | 2 | L1 eigene Schutz-Paar-Standards · L2 Depot-Doktor + Klumpen-Warnung ab 15 % | 2 | Azubi III |
| `BotLvl.<Preset>` Bot-Stufe | 4 je Preset | Kapitalanteil 10 → 15 → 20 → 25 → 30 % | 2 | Preset freigeschaltet |
| `Research` Research-Vorlauf | 2 | Quartals-Tendenz 2 → 3 → 5 min vorher | 3 | L1 Trader II · L2 Fondsmanager I |
| `MultiChart` Multi-Chart 2×2 | 1 | 4 Charts gleichzeitig | 3 | Fondsmanager I |
Umverteilen („Know-how neu verteilen“): 1× je Woche gratis.

### B9.4 Ruf (Teil des Trader-Faktors)
- Punkte je **zählendem Börsentag** (≥ 3 zählende Trades): +1 Teilnahme, +2 wenn Rendite > 0, +2 weitere wenn ≥ +1,5 %. Erste
  Akademie-Lektion +3, Lizenzprüfung +20 (außerhalb des Deckels). **Deckel 20 Punkte je UTC-Tag.** Verluste kosten **nie** Ruf.
- Stufen-Schwellen 10 / 30 / 60 / 100 / 150 / 210 / 280 / 360 / 450 / 550 Punkte → Ruf 1–10 (Anzeige 5 Sterne mit Halben).
- Abbau: −8 % der Punkte je UTC-Tag ohne zählenden Börsentag (beim nächsten Join nachgerechnet, max. 30 Tage). Untergrenze nach
  Lizenz: Trader I ≥ Stufe 2, Fondsmanager I ≥ 4, Legende ≥ 6.
- Wirkung: Trader-Faktor × (1 + 0,03 × Ruf). Admins können Ruf **nicht** geben (nur ansehen).

### B9.5 Vermögen & Titel
`Vermögen = CR + 0,5 × Lauf-Ausgaben (Turmwert) + Firmenwert + Sammlungswert (50 % der Kaufpreise) + NAV_AKY × Bau-Kurs`,
geklemmt auf 9e15, Anzeige „Vermögen“ als leaderstats-**StringValue** (formatiert; IntValue wäre auf ±2^52 begrenzt) + IntValue „Etagen“.
Kopftitel (BillboardGui, Gold/Holo): Starter (< 10 Tsd.) · Zehntausender (1e4) · Hunderttausender (1e5) · **Millionär** (1e6) ·
Multi-Millionär (1e7) · Hundert-Millionär (1e8) · **Milliardär** (1e9) · Multi-Milliardär (1e10) · Hundert-Milliardär (1e11) ·
**Billionär** (1e12) · Multi-Billionär (1e13) · **Billiarden-Boss** (1e15). Jeder Titel: eigene Fanfare + Server-Toast.

### B9.6 Börsengang (Prestige)
- **Voraussetzung:** Etage 25 fertig **und** Lizenz-Tor (BG 1–2 Trader I · 3–4 Trader II · 5–9 Trader III · ab 10 Fondsmanager I).
- **Vorschau** ab Stufe 7 (Tower-Menü „Börsengang-Vorschau“, animiert): Sterne jetzt, was bleibt/was neu startet (Symbole),
  neue Krone, „Stufe 1–7 in ca. 15 min wieder erreicht“ (aus `TowerMath` geschätzt).
- **Zeremonie:** zur Börsenglocke gehen (oder „Aus der Ferne läuten“ mit Kinoszene) → Ticker eingeben (3–4 Buchstaben A–Z;
  `TextService:FilterStringAsync` + `GetNonChatStringForBroadcastAsync` + Sperrliste `Config.Progression.TickerBlock` mit echten
  großen Kürzeln und Wörtern wie NFT/BTC/ETH; Fallback: Initialen des Tower-Namens) → Glocke, Konfetti-Beams, Ticker 24 h
  auf der Plaza-IPO-Wand und dauerhaft in der „Hall of IPOs“-Liste, Server-Banner, Badge → Kräne bauen den Tower zurück.
- **Belohnung:** Aktien-Sterne `★ = floor(4 × log10(Lauf-Ausgaben / 1e6))` (0 unter 1e7; Lauf 1 ≈ 1e9 → 12 ★, Lauf 2 ≈ 1e13 →
  28 ★) · Perm +0,25 je BG (max. 20 gezählt) · Firmenwert += 0,5 × Lauf-Ausgaben (geklemmt 9e15) · Krone (Silber/Gold/Platin/
  Holo/Orbit bei 1/3/5/10/20) · Titel-Zusatz CEO → Serien-Gründer (5) → Tycoon (10) → Mogul (20).
- **Bleibt:** Depot (alles), Lizenz, XP, KH, Ruf, Strategie-Bots, Autos, Uhren, Accessoires, Deko (im Lager, Layout gemerkt),
  Fassaden/Kosmetik, Pässe/Käufe, Erfolge, Album, Saison, Streak, Vermögen-Bestandteil Firmenwert.
- **Neu:** CR (Start-CR 0 bzw. laut Perk), Etagen, Abteilungen, Raum-Stufen, Personal, Effizienz, Baustelle, Tresor.
- **Vorstand-Baum** (★, je Stufe 1 ★, nur Turm/Lifestyle – nie Depot/Bau-Kurs/Trading):
  | Ast | Stufen | Wirkung je Stufe |
  |---|---|---|
  | Wachstum | 10 | +0,10 Perm |
  | Blitzstart | 3 | Start mit 4 / 8 / 12 fertigen Etagen |
  | Bau | 8 | −5 % Kosten (Etagen, Raum-Stufen, Personal, Effizienz) |
  | Tempo | 5 | −10 % Bauzeit |
  | Tresor | 8 | +1 h Offline-Deckel, +5 Pp Offline-Rate |
  | Lifestyle | 5 | −5 % Auto-/Uhren-/Deko-Preise; Stufe 5: Uhr „Glocken-Tourbillon“ + Titel „CEO“ |
  Gesamt 39 ★. Umverteilen 1 ★ (bei BG 3 einmal gratis). Überzählige Sterne: Kronen-Effekte (kosmetisch).

### B9.7 Quests
- **Tages:** 3 aus 30 Vorlagen, deterministisch je Spieler/Tag `Util.Hash(userId .. ":" .. utcDay)` (freie Auswahl, keine Kosten),
  mindestens 1 Handels-/Akademie-Quest. 1 Gratis-Neuwürfeln je Tag (zeigt alle Optionen offen; kein Kauf).
  Belohnung: CR = 10/15/20 min Dauer-Einkommen (mind. 2.000) + 150 Saison-XP (+100 Trader-XP nur bei Handels-/Akademie-Art).
- **Wochen:** 3 aus 12. Belohnung 2 h Dauer-Einkommen + 600 Saison-XP (+500 Trader-XP bei Handels-Art).
- **Starter-Linie „Vom Azubi zum Millionär“:** 20 Schritte mit Tiko-Sätzen (Auto, Akademie, Abteilungs-Synergie, Bot, erste
  Liga-Woche), je Schritt 500–50.000 CR, Schritt 20: Titel „Gründer“.
- **Quest-Arten** (`Config.Progression.QuestKinds`; jede braucht einen `RewardService.Track`-Aufrufer, SelfTest prüft):
  `Collect, BuildFloor, RoomLevel, Hire, Efficiency, Transfer, TradeProtected, TradeProfit, PositiveDay, ReadNews, NewSector,
  HoldThroughBell, EarningsTrade, Lesson, Drive, VisitTower, GiveRespekt, HelpBuild, Pickup, BearOrbs, Bell`.
  Beispiele: „Kassiere 5× deinen Tresor“, „3 Trades mit Schutz-Paar“, „+1 % an einem Börsentag“, „Lies 5 Eilmeldungen“,
  „Kaufe in einem neuen Sektor“, „Fahre 2 km“, „Besuche 2 Tower und gib Respekt“, „Hilf bei einem Bau“, „Sammle 10 Geldbündel“.

### B9.8 Erfolge, Badges, Firmen-Album
- **60 Erfolge** in 6 Kategorien (Trading 14, Tower 14, Akademie/Lizenz 10, Sammlung 10, Sozial 6, Events 6), z. B. „Krisenfest“
  (Crash mit < 10 % Verlust), „Diamantkopf“ (50× gut gelesen), „Skyline-Pionier“ (erster Wolkenkratzer), „Konstanz“ (10 positive
  Börsentage in Folge). Belohnung CR, Titel oder Deko. Keine „Glücks“-Wörter.
- **15 Roblox-Badges** (`Id = 0` = aus): Willkommen, Erste Etage, Erster Gewinn, Loft, Wolkenkratzer, Orbit-Spire, Erster
  Börsengang, Trader-Lizenz, Fondsmanager-Lizenz, Börsen-Legende, Millionär, Milliardär, Crash überstanden, Liga Gold,
  7-Tage-Serie. Badge-Anlage kann Robux kosten (ANLEITUNG).
- **Firmen-Album:** einmal ≥ 1 Anteil jeder Firma/jedes ETFs besitzen (43 Karten) + IPO-Seite je Saison. Je vollständigem
  Sektor-Satz (6 Firmen) +0,02 Perm (max. +0,12), goldener Rahmen „Komplett“.

### B9.9 Login, Saison, Rückkehr
- **Login-Kalender** (deterministisch, nie Rad): 7er-Zyklus: T1 15 min Einkommen · T2 Lack „Akzentblau“ · T3 Boost x2 30 min
  (Spielzeit) · T4 Deko „Mini-Bulle“ · T5 1 h Einkommen · T6 300 Saison-XP · T7 Uhr „Wochen-Chrono“ (ab Zyklus 2: 3 h Einkommen).
  28er-Spur: T14 Fassade Obsidian · T28 Auto „Streak-GT“ + Fassade Polar. Täglicher Gratis-Sofortbau-Token. 1 Gratis-Serien-Schutz
  je Woche (Club +1, max. 2 gespeichert). **Kein bezahlter Serien-Retter.**
- **Skyline-Pass** (4 Wochen, 50 Stufen à 1.000 Saison-XP): Quellen Tagesquests 3×150, Wochenquests 3×600, Spielzeit 10 je 10 min
  (max. 60 min/Tag), zählende Börsentage 25 (max. 12/Tag), Welt-Events 50, Bau-Hilfe 25, Respekt geben 25 (max. 5) →
  ≈ 1.800/Tag → Stufe 50 in ≈ 28 Tagen. Gratis-Spur 25 Belohnungen (CR, Deko, Lack, Boost-Token, Saison-Badge-Titel);
  Premium-Spur 50 (Terminal-Theme T10, Fassade T20, Uhr T30, Tower-Skin T40, Saison-Auto T50, Neon-Kit, Lacke, Deko-Set,
  Kronen-Effekt, Boost-Token, CR). **Nie** AKY, XP, KH, Ruf. Premium rückwirkend; ehrlicher Countdown bis Saisonende.
- **Rückkehr:** ≥ 14 Tage weg: 3 h Boost x2 (Spielzeit) + Aufhol-Quest · ≥ 60 Tage weg: zusätzlich Rückkehrer-Fassaden-Neon.

### B9.10 Pacing-Ziele & Release-Gates (`tools/economy_sim.py`, `tools/market_calibrate.py`)
| Gate | Bedingung (Spieler „gratis, guter Trader“, wenn nicht anders genannt) | Ist (Sim) |
|---|---|---|
| G1 | teuerster Einzelpreis < 1e14, kein Kontostand ≥ 9e15, alle Config-Preise ganzzahlig | 4,9e13 ✓ |
| G2 | Handels-Anteil aktiv (Gewinn-Transfer + Trader-Faktor): ≥ 15 % in Stufen 4–6, 25–45 % ab Stufe 7 | 15–23 % / 25–41 % ✓ |
| G3 | Gewinn-Transfer-Anteil aktiv ≥ 10 % in Stufen 1–7 | 13–73 % ✓ |
| G4 | Etage 4 ≤ 5 min · Etage 10 ≤ 25 min · Etage 25 Tag 2–5 · Etage 50 Tag 28–56 · Pässe höchstens 15 % schneller zu Etage 50 | 2 min · 18 min · Tag 3 · Tag 41 · −5 % ✓ |
| G5 | **Freie-Option-Gate** (WP3 erweitert `market_calibrate.py`): Strategie „Zufall + Gewinn-Transfer + Starthilfe“ (Regeln §B8.2/§B8.4) zieht ≤ 15 % der CR-Menge der Strategie „Tiko-Ampel“ über 50 Börsentage × 3 Seeds; sonst Schwelle/Tageslimit anpassen | offen (WP3) |
| G6 | Skill-Gate MARKET §19.6 (Zufall ≤ +0,2 %, Spam < −2 %, Ampel ≥ +0,5 %, Smart ≥ +1,5 %, positive Tage Smart ≥ 75 %) | offen (WP3) |
Jede Änderung an Kurven/Tabellen → beide Skripte laufen lassen; Ergebnis in den Abschlussbericht.

## B10. Events & Live-Ops
### B10.1 Welt-Events (Minute :10 jedes Börsentags, Rotation `Börsentag-Index % 4`, auf allen Servern gleich)
Pickups werden **pro Spieler instanziert** (jeder sieht und sammelt eigene, kein Wegschnappen). Server vergibt Token-Ids mit
Position und Zeitfenster; Einsammeln über `EventPickup {Id}` (Abstand ≤ 12 Studs, Fenster gültig, max. 1 je Id).
| # | Event | Dauer | Ablauf / Belohnung |
|---|---|---|---|
| 0 | Geldtransporter | 120 s | gepanzerter Part-Transporter fährt den Ring-Boulevard und lässt **30 Bündel je Spieler** fallen; je Bündel 20 s Dauer-Einkommen; +50 Saison-XP für ≥ 10 |
| 1 | Drohnen-Lieferung | 120 s | 8 Drohnen-Pakete je Spieler an deterministischen Dach-/Boden-Positionen (Hash aus Tick); je Paket 60 s Dauer-Einkommen |
| 2 | Bau-Boom | 300 s | Etagen- und Raum-Stufen-Kosten −25 % (ehrlicher Timer im HUD), Kräne auf allen Towern |
| 3 | Pressekonferenz | 90 s | Roboter-CEO-Hologramm auf der Plaza zeigt Konsens + Analysten-Urteile der Quartalszahlen von :03 des **nächsten** Börsentags (13 min vor dem Termin statt 5 min) + 3-Fragen-Quiz (+50 Trader-XP); für alle Anwesenden gleich, nichts davon kaufbar |
Zusätzlich stündlich (Börsentag-Index `% 3 == 0`): **Glocken-Moment** (:00–:01): ≥ 3 Spieler (Studio ≥ 1) in der Glocken-Zone →
Server-Boost ×1,2 für 5 min (Gruppe Zeitlich/Server, zählt nicht zusätzlich zur Bullen-Parade, es gilt der größere Wert) ·
**Sky-Show** (:15, Nacht): synchrone Fassaden-Lichtshow + Feuerwerks-Beams, Respekt zählt 10 min doppelt.

### B10.2 Crash & Rally in der Welt
- **„Beruhige den Bären“** (während jeder Crash-Fallphase, serverlokal, **ohne Markteinfluss**): Part-Bär (cartoonhaft, keine
  Gewalt) stapft auf die Plaza; je Spieler erscheinen 8 Vertrauens-Kugeln (respawnen nach dem Sammeln an neuer Position);
  Server-Ziel = 25 × anwesende Spieler. Erfolg: Bär verbeugt sich und geht, jeder Teilnehmer bekommt 10 min Dauer-Einkommen +
  Erfolgs-Fortschritt „Krisenfest“.
- **Goldener Bulle** (Rally): läuft den Ring-Boulevard; Berühren = persönlicher **Bullen-Bonus** ×1,5 für 5 min (Zeitlich/Boost,
  nicht stapelbar, 1× je Rally).
- WorldLook färbt Himmel/Ticker-Wände (§A4), Sirenen-/Fanfaren-Rezept.

### B10.3 Bullen-Parade & Feuerwerk (Robux, Server-weit)
Bullen-Parade: ×1,5 Einkommen für alle im Server 15 min (Verlängerung bei erneutem Kauf, max. 60 min Warteschlange), goldene
Bullen-Parade um den Ring, Dank-Banner „Danke, <Name>!“ (ohne Robux-Betrag). Feuerwerk: 20 s Show über dem Tower des Käufers.

### B10.4 Live-Ops-Kalender (Markt-Termine `Config.Market.Weekly` (WP3), Rest `Config.Events.Weekly` (WP11); Zeiten in Berlin-Ortszeit, gerechnet in UTC)
Sommerzeit-Regel in `Shared/Clock.BerlinOffset(unix)`: +2 h vom letzten Sonntag im März 01:00 UTC bis letzten Sonntag im Oktober
01:00 UTC (2026: 29.03.–25.10.), sonst +1 h. Damit rechnen alle Server dieselben Event-Ticks (deterministisch).
| Wann (Berlin) | Event | Besitzer nötig? |
|---|---|---|
| jeder Börsentag | Glocke, Termine, Welt-Event :10, Dividenden :19 | nein |
| stündlich | Glocken-Moment, Sky-Show | nein |
| täglich 19:00 | Power-Hour (Trader-XP ×2, 60 min) | nein |
| Mi 19:00 | Rally-Mittwoch (telegrafierte Sektor-Rally, Plan-Event) | nein |
| Fr 19:00 | **Crash-Freitag** (Plan-Crash, Bär-Event) | nein |
| Sa 16:00 | wöchentliches Update veröffentlichen (Config: neue Deko/Auto/Saison-Inhalte) | ja (Publish) |
| Sa 17:00 | IPO-Erstnotiz (aus Saison-Pipeline) | nein |
| Sa 18:00 | **Admin-Abuse** mit dem Besitzer. Hat er bis 18:14:50 keine Show gestartet, läuft um 18:15 die **automatische Samstags-Show** (Banner → Golden Hour ×2 30 min → Rally +15 % Sektor der Woche → Geldregen → Feuerwerk). Die Rally ist ein Plan-Event, das per GlobalBus-Nachricht `CancelAutoShow` abgesagt wird, sobald der Besitzer eine Show startet. | optional |
| So 20:00 | Bilanz-Sonntag: Liga-Finale-Show, Top-10-Hologramme | nein |
| Mo 00:00 UTC | neue Woche (Seed, Liga), Liga-Belohnungen beim nächsten Join | nein |
Jedes wiederkehrende Event steht auch als Roblox **Experience Event** auf der Spielseite (ANLEITUNG-Anleitung).

## B11. Sozial (funktioniert komplett ohne Chat)
### B11.1 Bestenlisten & Liga
| Board | Store (OrderedDataStore) | Wert (Ganzzahl 0…9e15) |
|---|---|---|
| Vermögen (ewig) | `AT_LB_Wealth_v1` | `floor(log10(1 + Vermögen) × 1e12)` (Anzeige dekodiert ≈) |
| **Wochen-Liga** | `AT_LB_League_<IsoWeek>` | `SkillScore × 10.000 + clamp(round(Ø-Tagesrendite_bp) + 5.000, 0, 9.999)` |
| Ø-Tagesrendite (Woche) | `AT_LB_Return_<IsoWeek>` | `round(Ø-Tagesrendite_bp) + 1.000.000` |
| Skyline | `AT_LB_Skyline_v1` | `Börsengänge × 100 + Etage` |
| Firmenwert | `AT_LB_Firm_v1` | `floor(log10(1 + Firmenwert) × 1e12)` |
| Beliebtester Tower (Woche) | `AT_LB_Respekt_<IsoWeek>` | Respekt-Anzahl |
- **Liga-Wertung nach Skill-Score** (MARKET §12.6 Formel: `400·tanh(Sharpe/1,5) + 300·Anteil positiver Tage + 300·(1 − min(1,
  MaxDD/20 %))`), Tie-Break Ø-Tagesrendite `= (1 + TWR)^(1/Tage) − 1` (unabhängig von Kontogröße **und Aktivitätsmenge**).
  Teilnahme: ≥ 20 zählende Trades und ≥ 6 zählende Börsentage; Admin-Fenster ausgenommen; getaintete Spieler (Admin-Gaben)
  diese Woche ausgeschlossen. **Änderung zu MARKET §12.6** (dort Rang nach TWR – TWR über viele 20-min-Tage belohnt Masse).
- **Absolute Liga-Stufen** (jeder kann eine erreichen): Bronze ≥ 300, Silber ≥ 500, Gold ≥ 700, Diamant ≥ 850 Skill-Score.
  Belohnung beim ersten Join der Folgewoche: Trophäen-Deko in Stufenfarbe, Wochen-Titel, Trader-XP (§B9.1), 300/600/1.200/2.500
  Saison-XP.
- Schreiben ≥ 300 s Abstand und beim Verlassen, nur bei Änderung; nie für NoSave/`UserId ≤ 0`. Lesen Top 10 alle 300 s.
  Ansicht Global / Freunde / Server im Fenster „Bestenlisten“; Hologramme im Börsensaal. Neuer #1 im Server → Ansage.
- **Hall of Fame:** Liga-Top-3 der Vorwoche als goldene Statuen (`Players:CreateHumanoidModelFromUserIdAsync`, Fallback
  ohne Async, pcall; alle BaseParts Material Metal, Farbe `#facc15`, verankert; Studio/negativ: Part-Puppe).

### B11.2 Börsensaal als Treffpunkt
Hall of Fame, IPO-Wand, Heatmap, Glocken-Zeremonien, VIP-Balkon, Akademie, Dachterrasse (Club), räumlicher Voice-Chat.

### B11.3 Besuche, Respekt, Bau-Hilfe, Reaktionen
- **Respekt:** 1 je Tower je Besucher je UTC-Tag; nur wenn Besucher `AccountAge ≥ 3` Tage und ≥ 10 min in dieser Sitzung.
  Besitzer +0,01 Perm für 1 h (Lounge 2 h, max. 20 gleichzeitig; Marketing-Studio zählt jeden Respekt doppelt); Besucher +25
  Saison-XP (max. 5 je Tag). Zählt für „Beliebtester Tower“.
- **Bau-Hilfe:** §B4.7.
- **Reaktionen ohne Chat:** Radialmenü (Controller-tauglich) mit 👍 🚀 📈 👏 🔔 als BillboardGui-Bubble über dem Kopf (2 je s,
  3 s sichtbar) + Standard-Emotes wave/cheer/point/dance.
- **Fotospots:** Aussichtspunkt, Helipads, Börsenglocke; Fotomodus (CC `PhotoMode`).

### B11.4 Freunde & Wachstum
- Freunde-Bonus +0,10 Perm je Freund im Server (max. 4), `IsFriendsWithAsync` 1× je Paar und Sitzung.
- **Einladen** (`SocialService:PromptGameInvite`, Knopf ab Stufe 3): erreicht ein eingeladener Neuling (`Player:GetJoinData()
  .ReferredByPlayerId`) Etage 10 und 10 min Spielzeit, bekommen beide Boost x2 30 min (Spielzeit) + Neon „Partner“. Max. 10
  solche Belohnungen je Einlader und Woche, Einladender muss im selben Universum existieren (keine Prüfung über HTTP).
- **Gruppe „AKYTEX Games“** beitreten (`IsInGroupAsync`, pcall): Kosmetik „Community-Krone“ + Namensschild-Rahmen (kein Einkommen).
- Freunde bekommen benachbarte Plots.

### B11.5 Flex ohne Glücksspiel-Glorifizierung
„Zeigen“-Karte (Profil): Tower-Stufe, Lizenz, Skill-Score, Liga-Stufe, Titel, Lieblings-Auto. **Kein** Trade-G/V. Server-Toasts nur
für Stufen-Morph, Lizenz, Titel, Börsengang, Liga-Stufe, Hypercar-Kauf.

### B11.6 Voice
`VoiceChatService.EnableDefaultVoice = true` (Projektdatei, falls Rojo es setzt; sonst ANLEITUNG: Game Settings → Communication).
Räumlich; Roblox regelt Berechtigung (13+, verifiziert).

### B11.7 Hedgefonds-Gruppen (v1.1)
Bis 20 Mitglieder, Name aus Wortbausteinen, Wochen-Gruppenwertung = Ø Skill-Score der besten 5, gemeinsame Ziele, nur kosmetische
Belohnungen (Banner am Tower, Kronen-Licht, Plaza-Hologramm Top 10). **Kein gemeinsames Geld.** Daten `AT_Groups_v1`.

### B11.8 Bewusst nicht
Kein Stehlen/Überfallen, kein Spielerhandel, keine Geldpools, kein öffentliches Verlust-Zeigen, kein Freitext außer Roblox-Chat
(und 4-Buchstaben-Ticker gefiltert).

### B11.9 Benachrichtigungen, Favoriten, Badges
- **Experience Notifications:** v1 nur Opt-in-Gerüst: `ExperienceNotificationService:CanPromptOptInAsync()` → `PromptOptIn()`
  einmal nach positivem Moment (nie im Tutorial, frühestens Schritt 17, nur 13+ – Roblox filtert), Zeitpunkt in
  `Data.Notif.LastPrompt` (Roblox zeigt den Dialog ohnehin max. alle 30 Tage). **Senden** („Dein Tresor ist voll“, „Crash-Freitag
  in 30 min“, max. 1 je Tag) erst **v1.1**, nachdem Open-Cloud-Versand mit Schlüssel aus `HttpService:GetSecret` in Studio/Live
  verifiziert ist (`Config.Notifications.Enabled = false`).
- Favoriten-Abfrage 1× je Konto (§B2). Badges §B9.8.

## B12. Lifestyle (Haupt-CR-Senke; jugendfrei: kein Alkohol, keine Zigarren, keine Partys)
### B12.1 Autos (befahrbar, aus Parts; `Config.Vehicles`)
| Schlüssel | Name | Klasse | Quelle / Preis CR |
|---|---|---|---|
| `LamCity` | Λ City | Kompakt | gratis (Tutorial) |
| `VoltaHatch` | Volta Hatch | Kompakt | 25.000 |
| `PixelMini` | Pixel Mini | Kompakt | 120.000 |
| `LamNeon` | Λ Kompakt Neon | Kompakt | Starter-Paket |
| `Stratos` | Stratos Sedan | Limousine | 750.000 |
| `Nordlicht` | Nordlicht Executive | Limousine | 4.000.000 |
| `VelocitraS` | Velocitra S | Sport | 60.000.000 |
| `NeonCoupe` | Neon Coupé | Sport | 250.000.000 |
| `StreakGT` | Streak-GT | Sport | Login Tag 28 |
| `Kometa` | Kometa SL | Super | 6.000.000.000 |
| `AuroraGT` | Aurora GT | Super | 40.000.000.000 |
| `QuasarX` | Quasar X | Hyper | 600.000.000.000 |
| `VelocitraH` | Velocitra Hyper | Hyper | 4.000.000.000.000 |
| `Singularity` | Singularity | Hyper | Lizenz Börsen-Legende |
| `OrbitR` | Orbit-R | Hyper | Skyline-Pass S1 Premium Stufe 50 |
| `Lam1` | ΛKYTEX Λ-1 | Hyper | Pass (gleiches Tempo wie bestes erspieltes Hyper, nie schneller) |
- Bau: VehicleSeat, 4 Räder als Zylinder mit `HingeConstraint` (Motor, AngularVelocity), Lenkung per Servo-Hinge, Federung
  `SpringConstraint`; Netzwerk-Besitzer = Fahrer. Boost (Shift / Touch-Knopf) +25 % für 3 s, 8 s Abklingzeit; Handbremse (Leertaste)
  senkt Hinterrad-Reibung auf 0,3 (Drift); Neon-Unterbodenlicht (PointLight im Licht-Budget).
- Höchsttempo je Klasse (Studs/s): Kompakt 60 · Limousine 75 · Sport 95 · Super 120 · Hyper 150. Server prüft 5 Hz
  (`AntiCheatService.SetAllowance` mit Klassen-Deckel; > 1,3 × Deckel → Geschwindigkeit zurücksetzen + Verdachtspunkte).
- **Kollisionsgruppen:** `Cars` kollidiert **nicht** mit `Characters` und nicht mit `Cars`, nur mit `World` → kein Rammen,
  kein Schleudern, kein Grief.
- 1 Auto je Spieler aktiv; verschwindet 60 s nach dem Aussteigen oder beim Verlassen. Garage: 6 Plätze, +4 je Garagen-Ebene (max. 2),
  +12 Pass Mega-Garage. Tuning (CR): 24 Lacke (inkl. Metallic), 8 Felgen, 6 Unterbodenlicht-Farben, Spoiler.
- **Aktionärs-Rabatt:** wer beim Kauf ≥ 50 Anteile Velocitra (VLCT) hält, zahlt für Velocitra-Autos −10 % (Fluss Depot → Turm,
  erlaubt; nie umgekehrt).

### B12.2 Uhren (am Handgelenk für alle sichtbar; 6–10 Parts, an `LeftLowerArm` bzw. R6 `Left Arm` geschweißt, Massless,
CanCollide/CanQuery/CanTouch aus; Zeiger drehen im PreRender-Loop, nur ≤ 60 Studs)
`FirstBell` Erste Glocke (Starter-Paket) · `Copper` Kupfer Classic 50.000 · `NeonPulse` Neon Pulse 2 Mio. · `ChronoL` Chrono Λ 80 Mio. ·
`OrbitGold` Orbit Gold 3 Mrd. · `DiamondTicker` Diamant-Ticker 2 Bio. · `WeekChrono` Wochen-Chrono (Login T7) · `SkylineChrono`
(Saison-Premium T30) · `BellTourbillon` Glocken-Tourbillon (Vorstand Lifestyle 5) · 5 × Chrono-Kollektion (Pass) · `Legend` Legenden-Uhr
(Lizenz Legende) → 15 Uhren.

### B12.3 Accessoires (aus Parts, keine hochgeladene Kleidung)
Sonnenbrille 10.000 · Krawattennadel 100.000 · Aktentasche 1 Mio. · Revers-Neon 20 Mio. · Aura-Ring Blau 500 Mio. · Aura-Ring Gold
10 Mrd. · Holo-Abzeichen (Lizenz Fondsmanager) · Community-Krone (Gruppe). Max. 3 gleichzeitig.

### B12.4 Neon-Jetpack (Pass)
Flug in der Stadt: Treibstoff 8 s, Nachladen 12 s, max. 120 Studs über Boden, nicht in fremden Towern; AntiCheat-Erlaubnis
`VerticalMult`/`SpeedMult` nur während aktiv. Yacht und Helikopter v1.1, Privatjet v1.2.

## B13. Wirtschaft
| Währung | Quellen | Senken | Robux |
|---|---|---|---|
| AKY (Cent) | §0.4 | Gebühren, Spread, Bot-Lohn, Verluste, Transfer | nie |
| CR | Turm, Transfer, Quests, Login, Events, Geldregen, Codes, Bau-Gutscheine | Etagen, Stufen, Personal, Effizienz, Abteilungs-Wechsel, Deko, Autos, Tuning, Uhren, Accessoires | ja (nur CR) |
| Know-how | Level, Lizenz, Akademie | KH-Baum | nie |
| Aktien-Sterne | Börsengang | Vorstand-Baum | nie direkt |
| Saison-XP | Quests, Spielzeit, Börsentage, Events, Respekt | Pass-Stufen | Stufen-Produkt (gibt Stufen, nie AKY/XP) |
| Ruf | positive Börsentage, Akademie, Prüfung | – (Faktor) | nie |
Inflationsbremsen: Kosten-Bänder je Etagenband, Effizienz-Deckel 20, Lizenz-Tore, Börsengang-Reset, CR-Deckel 9e15, Log-Bestenlisten,
einkommens-skalierte Belohnungen statt fester Riesenbeträge, AKY durch Basis + Positions-Grenzen + Transfer-Tageslimit gebunden.
Admin-Tab Statistik zeigt CR-/AKY-Geldmenge im Server und Median je Stufe (MetricsService Source/Sink).

## B14. Monetarisierung (`Config.Shop`; `Id = 0` → „Bald verfügbar“, alle Pfade mit `SimulatePurchase` getestet)
### B14.1 Gamepasses (dauerhaft)
| Schlüssel | Name DE / EN | R$ | Wirkung |
|---|---|---|---|
| `VIP` | Börsen-VIP / Exchange VIP | 399 | VIP-Balkon im Börsensaal, goldenes Λ-Namensschild + Chat-Tag, VIP-Parkplatz, Lack „Platin“, Einkommen ×1,10 |
| `Income2x` | x2 Einnahmen / 2x Income | 499 | Pässe-Faktor +1 (allein ×2) |
| `Income3x` | x3 Einnahmen / 3x Income | 1.199 | Pässe-Faktor +2 (allein ×3; mit x2 zusammen **×4**, steht so vor dem Kauf) |
| `AutoCollect` | Auto-Kassierer / Auto Collect | 249 | Tresor sammelt alle 3 s überall |
| `OfflineVault` | Offline-Tresor 24 h | 349 | Offline-Deckel mind. 24 h, Rate +15 Pp |
| `StaffPlus` | Personal+ / Staff+ | 299 | 3. Personal-Platz je Etage (nur Turm-Personal, nie Strategie-Bots) |
| `BuildCrew` | Bau-Crew Pro | 399 | Bauzeiten −50 % |
| `TerminalDesigner` | Terminal-Designer | 249 | 6 Terminal-Themes (Space, Gold, Arctic, Mono, Midnight, Aurora), Kerzen-/Ticker-Skins, UI-Sound-Paket – **nur Kosmetik** (keine Alarme, Layouts, Indikatoren) |
| `MegaGarage` | Mega-Garage | 199 | +12 Auto-Plätze, Showroom-Etage mit Drehteller |
| `Jetpack` | Neon-Jetpack | 449 | §B12.4 |
| `Lam1` | ΛKYTEX Λ-1 Hypercar | 799 | exklusives Auto mit Neon-Spur und eigenem Motor-Rezept |
| `Chrono` | Chrono-Kollektion | 349 | 5 exklusive Uhren |
| `FacadeKit` | Neon-Fassaden-Kit | 349 | Fassade Gold-Luxe + 8 animierte Lichtmuster + Kronenfarben |
| `TycoonBundle` | Tycoon-Paket | 749 | Wirkung von Income2x + AutoCollect + OfflineVault (einzeln 1.097 R$, echt −32 %); Karte erkennt bereits besessene Teile und empfiehlt dann Einzelkäufe; Server behandelt Bundle-Besitz wie Besitz aller drei |

### B14.2 Developer Products (wiederholbar)
| Schlüssel | Name | R$ | Gewährung (deterministisch, Zahl vor dem Kauf sichtbar) |
|---|---|---|---|
| `Boost2x30` | Boost x2 · 30 min | 49 | +1.800 s x2 (Spielzeit) |
| `Boost2x120` | Boost x2 · 2 h | 149 | +7.200 s x2 |
| `Boost5x10` | Turbo x5 · 10 min | 99 | +600 s x5 (überlagert x2, x2-Zeit pausiert) |
| `BullParade` | Bullen-Parade (ganzer Server) | 199 | §B10.3 |
| `CreditsS/M/L/XL` | Bau-Gutschein S / M / L / XL | 49 / 149 / 399 / 899 | CR = 30 min / 2 h / 6 h / 16 h Dauer-Einkommen ohne Zeitlich (mind. 5.000 / 20.000 / 60.000 / 150.000), Angebot (Quote) 10 min gültig, Gewährung `max(Quote, Neuberechnung)`. **Nur CR.** |
| `ExpressS/M/L` | Bau-Express | 19 / 39 / 79 | beendet die Baustelle bei Rest ≤ 10 min / ≤ 60 min / ≤ 3 h, sonst zieht es so viel ab; ohne Baustelle → Token für den nächsten Bau (nie verfallen) |
| `Fireworks` | Feuerwerk über deinem Tower | 29 | 20-s-Show, serverweit sichtbar |
| `Starter` | Starter-Paket (1× je Konto, Server-Flag) | 99 | Auto Λ Kompakt Neon, Uhr Erste Glocke, Boost x2 2 h, Bau-Gutschein M, Fassaden-Neon „Startup“, Namensrahmen „Gründer“. Angebot frühestens Sitzung 2 nach ≥ 15 min, einmal. Zweitkauf → 2 × Gutschein M |
| `SeasonPremium` | Skyline-Pass Premium (je Saison) | 399 | Premium-Spur (CC-`PassSeasons`-Muster) |
| `SeasonTier1` / `SeasonTier10` | +1 / +10 Pass-Stufen | 39 / 299 | Stufen (Belohnungen durch `ForbiddenRobuxFields`-Filter) |
| `GiftBoost` | Geschenk-Boost | 59 | Boost x2 30 min an einen gewählten Spieler im Server; nur wenn `IsPaidItemTradingAllowed == true` für Käufer **und** Empfänger (pcall, unbekannt = gesperrt); ist der Empfänger beim Beleg weg → Käufer bekommt den Boost (steht vor dem Kauf da) |
17 Produkte. **Nicht im Angebot:** Streak-Retter, AKY-Pakete, Insider/News, Alarm-/Layout-Pakete, Zufallsartikel.

### B14.3 Abo, Pass, Server, Plattform
- **Vorstands-Club / Executive Club** (Experience Subscription, 4,99 $ Landeswährung wenn verifiziert, sonst 449 R$/Monat):
  tägliche Abholung Bau-Gutschein S, Einkommen ×1,15, +4 h Offline-Deckel, monatlicher Exklusiv-Lack + Uhren-Zifferblatt,
  Dachterrasse im Börsensaal, +1 Serien-Schutz je Woche, Tag „Club“. `IsEligibleToPurchaseSubscription` (pcall, unbekannt =
  ausblenden). Nie „PRO“ (echter AKYTEX-Tarif).
- **Skyline-Pass** §B9.9. **Private Server: gratis** zum Start (Co-Play-Signal); nach 60 Tagen prüfen (99 R$/Monat).
- **Roblox Premium:** Einkommen ×1,10 + Premium-Payouts. **Regional Pricing** an. Preis-Optimierung ab 60.000 Transaktionen/Monat.
  **Rewarded Video** erst ab 100.000 Ø-DAU, Minimal/Mild, nur 13+ („Offline-Ertrag verdoppeln“, nur CR, `AreAdsAllowed`) – v1.2.
- Live-Preise immer per `UI.FetchPrice` (`GetProductInfoAsync`), nie hart kodiert.

### B14.4 Angebots-Regeln (`MonetizationService.TryOffer`)
Max. 1 Popup je Sitzung; nie in Sitzung 1; nur nach ≥ 15 min und direkt nach positivem Moment (Stufen-Morph); nie bei Crash/Rally-
Warnung, offenem Terminal/Order-Ticket, Tutorial, Willkommen-Bericht, Admin-Abuse-Countdown. Knöpfe „Ansehen“/„Details“.

### B14.5 Firewall & Policy im Shop
`Config.Shop.ForbiddenRobuxFields = { "Depot", "AKY", "Basis", "Xp", "TraderXp", "Licence", "KnowHow", "Ruf", "Stars",
"BotSlots", "BotLevel", "Alerts", "Watchlists", "Layouts", "MultiChart", "Research", "MarketInfo", "ExamPass" }`;
`Core.Sanitize` entfernt sie aus jeder Gewährung (Produkte, Pässe, Saison-Premium-Stufen, Abo-Tagesgabe, Geschenke).
`Config.Shop.RandomItemsEnabled = false`. PolicyService-Pfad aus CC (`RandomAllowed`, unbekannt = eingeschränkt,
`SetPolicyOverride`, `Config.Debug.ForceRestricted`) bleibt für die Zukunft und den Geschenk-Gate.

## B15. Admin-Panel (nur Besitzer; CC AdminService/AdminPanel angepasst)
### B15.1 Zugriff (exakt)
- Live, Nutzer-Spiel: `game.CreatorType == Enum.CreatorType.User and p.UserId == game.CreatorId and game.CreatorId ~= 0`.
- Live, Gruppen-Spiel (falls unter „AKYTEX Games“ veröffentlicht): `GroupService:GetGroupInfoAsync(game.CreatorId).Owner.Id ==
  p.UserId` (pcall, 10 min gecacht; Fehler = kein Admin).
- Studio: `Config.Admin.StudioIsAdmin` und (`UserId > 0` oder `UserId == −1`); **−2 nie** (Ablehnungspfad testbar).
- Rate-Limit 12/s **vor** der Admin-Prüfung; unerlaubter Zugriff 1× je Spieler geloggt; `p.Parent`-Guard.
- HUD-Knopf (Reihenfolge 99) + Taste `P`; Fenster 720 × 600 im AKYTEX-Dashboard-Look mit Seitenleiste; globale Aktionen mit 5-s-
  Bestätigung; jede Aktion → `AT_Mod_v1`-Admin-Log (letzte 500 im Tab „Moderation“), 3 s Abklingzeit je Markt-Aktion.

### B15.2 Tabs
| Tab | Inhalt |
|---|---|
| Dashboard | Spieler online (Server + geschätzt global über MemoryStore-Herzschlag), aktive Events, Markt-Regime, Bus-Status (MemoryStore/Messaging erreichbar?), Scheduler-Kosten, „Lokaler Testmarkt“-Banner bei Fallback-Seed |
| Spieler | Liste + Ziel-Feld (me/all/others/Name/Präfix/UserId), Kick, Bann (1h/1d/7d/30d/perm, Grund ≤ 400 B + privat ≤ 1000 B inkl. AntiCheat-Schnappschuss, `ApplyToUniverse = true`), Unbann, Bannliste/-verlauf, Verwarnen, Einfrieren, Bring/Goto, Zuschauen (X), Spielerdaten ansehen, Belege + Nachgewähren, Daten zurücksetzen (Belege bleiben) |
| Markt | Crash/Rally, Firma pushen/abstürzen, Admin-Eilmeldung, Pause/Weiter, IPO starten, Volatilität, Normalisieren, Event-Log mit Admin-Fenstern |
| Events | Admin-Abuse-Katalog §B15.3, Ansage lokal/global (Avatar + Akzent-Name + selbst gezeichneter blauer Haken, ohne Kasten, ≈ 8 s), Samstags-Show-Knopf, Live-Ops-Kalender-Vorschau |
| Geld & Items | CR, Items, Etagen, Abteilungen, Personal, Deko, Autos, Uhren, Lizenz-Stufe, Saison-Stufen geben (me/all/…), „AKY geben“ (erhöht Basis mit) – AKY-/Lizenz-Gaben taint die Liga-Woche des Empfängers |
| Kräfte | Fliegen (G), Noclip, Speed, Unsichtbar, Fotomodus, Besuche jeden Tower (auch private Etagen), Show-Kamera (Kino für Streams), ESP über Highlights (≤ 20) |
| Welt | Tageszeit-/Wetter-Vorschau (nur lokal), Verkehrsdichte, Welt-Event jetzt starten (lokal) |
| Live-Ops | `AT_Live_v1` bearbeiten (validiert + geklemmt: News-Takt, Event-Rotation, Boost-Werte, Codes nur CR/Kosmetik, Shop-Rotation anpinnen), Notschalter (Produkt deaktivieren, Boosts pausieren, Wartungs-Banner) |
| Statistik | Online, CR-/AKY-Geldmenge, meistgehandelte Werte, Fills/min, Fill-Audit-Abweichungen, Käufe/Robux 24 h, Top-Quellen/-Senken, verdächtige Spieler |
| Moderation | AntiCheat-Flags, Meldungen, Verwerfen, Bann-Log |
| Debug | SkipDay, SimulatePurchase, SimulatePolicy, SetDebug, RunSelfTest, F8-Overlay, Crash-Freitag-Probe (lokal) |

### B15.3 Admin-Abuse-Katalog (alle geklemmt, angekündigt, geloggt; Markt-Events immer global über GlobalBus)
| Event | Parameter (Grenzen) | Welt | Regeln |
|---|---|---|---|
| Mega-Rally | Umfang alle/Sektor/Wert · +5…+50 % · Rampe 30–300 s · Abklingen 5–60 min | grünes Polarlicht, goldener Bulle | Admin-Fenster (Taint), klingt zum Modellkurs zurück |
| Mega-Crash | −5…−50 %, sonst wie oben, optional 3-min-Warnung | roter Himmel, Bär-Event aktiv | dto. |
| Firma pushen / abstürzen | Wert · ±5…50 % | Firmen-Laden + Logo-Hologramm im Spot | dto. |
| Admin-Eilmeldung | Text DE/EN ≤ 80 Zeichen (gefiltert), Ziel Wert/Sektor, Stärke-Band, Richtung | Besitzer-Banner | erscheint auf **allen** Servern im selben Tick mit normalem 8-s-Lesefenster; Besitzer-Trades ±120 s um eigene Markt-Events gesperrt |
| Handelspause / Weiter | 10 s – 10 min | Ticker-Wände „HANDELSPAUSE“ | Orders/Trigger ruhen |
| IPO starten | Firma aus Pipeline | Glocke, Logo-Hologramm | Erstnotiz in 10 min (§B6.3) |
| Volatilität | ×0,5…×3 für 5–30 min | Sturm/ruhig | Taint |
| Normalisieren | – | Wetter normal | beendet alle Admin-Markt-Effekte über 60 s |
| Geldregen | lokal/global · 60–300 s | Neon-Münzen über Plaza und Plots | pro Spieler instanziert, je Münze 2 min Dauer-Einkommen, max. 30 je Spieler, Server prüft Pickup |
| Golden Hour | ×2 oder ×3 · 5–60 min · lokal/global | Gold-Tint, HUD-Chip | Gruppe Zeitlich/Event (Deckel ×10) |
| XP-Rausch | ×2 Trader-XP · 15–60 min | Akademie leuchtet | für alle gleich, Liga unberührt |
| Bau-Boom | 10 min | Kräne auf allen Towern | Etagenkosten −50 %, Bauzeit −90 % |
| Skyline-Lightshow / Feuerwerk / Konfetti / Glocken-Show | – | Show | kosmetisch |
| Boss-Auftritt | 60–300 s | Besitzer-Avatar (`CreateHumanoidModelFromDescriptionAsync`, kein Upload) ×8 auf dem Börsensaal-Dach, getweente Winke-Pose | kosmetisch |
| Alle in den Börsensaal | lokal | Kamera-Schwenk, Teleport (NoteTeleport) | nur dieser Server |
| Samstags-Show (1 Klick) | – | Banner → Golden Hour ×2 30 min → Rally +15 % Sektor der Woche → Geldregen → Feuerwerk | sendet `CancelAutoShow` |
**Harte Regeln:** nichts wird gelöscht, kein Event trifft einzelne Spieler negativ, keine Käufe werden berührt; jedes Markt-Event
öffnet ein Admin-Fenster (Ankündigung bis +10 min nach Abklingen), das Liga/Skill-Score ausnimmt (HUD-Chip „ADMIN-ABUSE aktiv –
zählt nicht für die Liga“); globale Nachrichten feldweise validiert inkl. oberer Zeitgrenze (`Until ≤ now + max`), Dedupe per Id.

---

# C) Technische Architektur

## C1. Tooling & Projekt-Einstellungen (WP1)
### C1.1 Werkzeuge (identisch CC, Pfade geprüft)
Rojo 7.7.1 · StyLua 2.5.2 (`syntax="Luau"`, `indent_type="Tabs"`, `column_width=120`) · selene 0.31.0 (`std = "rbx"`, `rbx.yml`
liegt bereits im Projekt) · luau-lsp (`/tmp/luau-lsp/build/luau-lsp`) mit
`SP=/tmp/claude-0/-home-user-website-test-demo-1/14caf8fd-3993-54cd-bb2d-9f5bab2d1eaf/scratchpad`, Definitionen `$SP/globalTypes.d.luau` ·
Luau-CLI `$SP/luau-build/luau` · Python 3 (+ numpy für `market_calibrate.py`).

`scripts/check.sh` (WP1; Gerüst existiert) führt im Projektordner aus und endet mit „ALLE PRÜFUNGEN OK“:
```sh
stylua --check src tests
selene src
rojo sourcemap default.project.json -o sourcemap.json
/tmp/luau-lsp/build/luau-lsp analyze --platform=roblox --definitions=$SP/globalTypes.d.luau --sourcemap=sourcemap.json src
rojo build default.project.json -o AkytexTycoon.rbxlx
for t in tests/*.test.luau; do $SP/luau-build/luau "$t" || exit 1; done
python3 scripts/contract_check.py .          # NEU gegenüber CC
python3 tools/economy_sim.py --quick          # NEU: G1 muss "OK" melden (WP6)
```
**Nie** in `roblox-shooter`, `roblox-meteor-heist` oder der Website bauen oder Dateien ändern.

### C1.2 `default.project.json` (WP1; jede Property per `rojo build` + grep im `.rbxlx` prüfen)
```json
{
  "name": "AkytexTycoon",
  "tree": {
    "$className": "DataModel",
    "ReplicatedFirst": { "$path": "src/first" },
    "ReplicatedStorage": { "Shared": { "$path": "src/shared" } },
    "ServerScriptService": { "Server": { "$path": "src/server" } },
    "StarterPlayer": {
      "$properties": { "CameraMaxZoomDistance": 60, "CharacterWalkSpeed": 16, "EnableMouseLockOption": true },
      "StarterPlayerScripts": { "Client": { "$path": "src/client" } }
    },
    "Players": { "$properties": { "BanningEnabled": true, "CharacterAutoLoads": true, "RespawnTime": 3 } },
    "Lighting": { "$properties": { "Technology": "Future", "EnvironmentSpecularScale": 1, "EnvironmentDiffuseScale": 1,
      "GlobalShadows": true, "Brightness": 2, "ClockTime": 9 } },
    "Workspace": { "$properties": { "StreamingEnabled": true, "StreamingMinRadius": 192, "StreamingTargetRadius": 768,
      "StreamOutBehavior": "Opportunistic", "RejectCharacterDeletions": "Enabled", "ReplicateInstanceDestroySetting": "Enabled" } },
    "TextChatService": { "$properties": { "ChatVersion": "TextChatService" } },
    "VoiceChatService": { "$properties": { "EnableDefaultVoice": true } },
    "StarterGui": { "$properties": { "ResetPlayerGuiOnSpawn": false } }
  }
}
```
Lässt Rojo eine Property nicht bauen (z. B. `VoiceChatService.EnableDefaultVoice`, `StreamOutBehavior`), wird sie entfernt und
als Studio-Schritt in die ANLEITUNG geschrieben (WP1 meldet es WP12). Besitzer stellt in Studio ein: **Max Players 10**, Avatar R15
(R6 erlaubt, Uhren-Schweißung kann beides), Studio-Zugriff auf API-Dienste an, Genre Simulation/Tycoon, Voice an, Fragebogen §0.6.
`Lighting.Technology` (RobloxScriptSecurity) und `Players.BanningEnabled` (NotScriptable) **müssen** in der Projektdatei stehen.

### C1.3 Parallel-Regel für statische Checks
Während die Pakete parallel entstehen, darf luau-lsp in eigenen Dateien nur `Unknown require` für noch nicht existierende Module
anderer WPs melden – sonst 0. Nach der Integration überall 0. Config-/Lang-Kinder werden dynamisch geladen (kein Unknown require).

## C2. Rojo-Baum & Dateiliste (jede Datei gehört genau einem WP)
```
roblox-akytex-tycoon/
  default.project.json rbx.yml selene.toml stylua.toml .gitignore scripts/check.sh scripts/contract_check.py   WP1
  AkytexTycoon.rbxlx                                      (Build-Ergebnis, Integration)
  ANLEITUNG.md                                            WP12
  docs/DESIGN.md (Lead) · MARKET.md (Lead, §C19-Kopf) · REUSE.md · BESITZER-WUENSCHE.md   (nicht ändern)
  docs/KOPIERVORLAGEN.md TESTPLAN.md ASSET-LISTE.md STYLE-AKYTEX.md LIVEOPS.md             WP12
  tools/market_calibrate.py WP3 · tools/economy_sim.py WP6
  tests/util.test.luau format.test.luau clock.test.luau WP1 · noise.test.luau quotecodec.test.luau WP3 ·
  tests/portfoliomath.test.luau indicators.test.luau WP4 · towermath.test.luau WP6 · progressmath.test.luau WP9
  src/first/Loading.client.luau                           WP2   (-> ReplicatedFirst, Splash)
  src/shared/                                             -> ReplicatedStorage.Shared
    Types.luau Util.luau Spring.luau Net.luau Format.luau Clock.luau AssetSlot.luau                       WP1
    Config/init.luau Config/Security.luau                                                                 WP1
    Config/Client.luau Config/Quality.luau                                                                WP2
    Config/Market.luau Config/Companies.luau Config/News.luau                                             WP3
    Config/Trading.luau                                                                                   WP4
    Config/Tower.luau                                                                                     WP6
    Config/City.luau Config/Vehicles.luau                                                                 WP7
    Config/Decor.luau Config/Lifestyle.luau                                                               WP8
    Config/Progression.luau Config/Season.luau Config/Rewards.luau                                        WP9
    Config/Shop.luau                                                                                      WP10
    Config/Events.luau                                                                                    WP11
    Lang/init.luau Lang/Core.luau (core.) WP1 · Lang/Ui.luau (ui.) WP2 · Lang/Market.luau (mkt.) Lang/News.luau (news.) WP3 ·
    Lang/Trade.luau (trade.) WP4 · Lang/Terminal.luau (term.) WP5 · Lang/Tower.luau (tower.) WP6 · Lang/World.luau (world.)
    Lang/Vehicle.luau (car.) WP7 · Lang/TowerUi.luau (tui.) Lang/Life.luau (life.) WP8 · Lang/Progress.luau (prog.)
    Lang/Tutorial.luau (tut.) Lang/Social.luau (soc.) WP9 · Lang/Shop.luau (shop. item.) WP10 · Lang/Admin.luau (admin.)
    Lang/Events.luau (evt.) WP11
    Market/QuoteCodec.luau                                                                                WP3
    Market/PortfolioMath.luau Market/Indicators.luau                                                      WP4
    TowerMath.luau                                                                                        WP6
    VehicleModels.luau                                                                                    WP7
    TowerModels.luau DecorModels.luau LifestyleModels.luau                                                WP8
    ProgressMath.luau                                                                                     WP9
  src/server/                                             -> ServerScriptService.Server
    Main.server.luau Lib/Scheduler.luau                                                                   WP1
    Services/Remotes.luau DataService.luau PlayerStateService.luau MetricsService.luau SelfTestService.luau WP1
    Services/MarketService.luau  Market/MarketClock.luau MarketSeed.luau Noise.luau PriceEngine.luau EventDirector.luau
      GlobalBus.luau CandleStore.luau QuoteStream.luau Dividends.luau MarketAudit.luau MarketAdmin.luau  WP3
    Services/OrderService.luau  Market/OrderEngine.luau Portfolio.luau BotEngine.luau CatchUp.luau       WP4
    Services/TowerService.luau PlotService.luau                                                           WP6
    Services/CityService.luau GraphicsService.luau VehicleService.luau  World/CityLayout.luau World/CityKit.luau  WP7
    Services/TowerVisualService.luau LifestyleService.luau                                                WP8
    Services/ProgressionService.luau RewardService.luau CommunityService.luau LeaderboardService.luau     WP9
    Services/MonetizationService.luau ShopService.luau                                                    WP10
    Services/AdminService.luau AntiCheatService.luau EventService.luau                                    WP11
    Tests/CoreTests.luau WP1 · MarketTests WP3 · OrderTests WP4 · TowerTests WP6 · WorldTests WP7 · VisualTests WP8 ·
    ProgressionTests WP9 · EconomyTests WP10 · AdminTests WP11   (alle .luau)
  src/client/                                             -> StarterPlayer.StarterPlayerScripts.Client
    Main.client.luau                                                                                      WP2
    Modules/UI Hooks Controls TouchControls Hud Settings Sfx Effects Highlights Quality PhotoMode          WP2
    Modules/MarketClient ChartView Terminal DepotView NewsFeed Ticker Monitors EffectsMarket              WP5
    Modules/WorldLook CityLife Vehicles Garage                                                            WP7
    Modules/TowerView TowerUI Elevator WelcomeBack Boutique EffectsTower                                  WP8
    Modules/Tutorial Academy Quests Season Boards Social Prestige                                         WP9
    Modules/Shop                                                                                          WP10
    Modules/AdminPanel AdminTools Fly DebugOverlay EventsClient EffectsEvent                              WP11
```
Pfade im Code: Shared `ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Name")`; Server-Nicht-Service-Module per
`script.Parent.Parent:WaitForChild("Market")…` nur **innerhalb** des eigenen WPs (WP3 `Market/*`, WP4 `Market/OrderEngine…`,
WP7 `World/*`); fremde Server-Logik nur über `Services.X`.

## C3. Server-Ladereihenfolge & Konventionen (WP1 `Main.server.luau`, CC-Lader 1:1, Präfix `[AKYTEX Tycoon] `)
```
DataService, MonetizationService, PlayerStateService, ShopService, GraphicsService, CityService, PlotService,
MarketService, OrderService, TowerService, TowerVisualService, VehicleService, LifestyleService, EventService,
ProgressionService, RewardService, CommunityService, AntiCheatService, AdminService, LeaderboardService,
MetricsService, SelfTestService
```
- Remotes-Modul zuerst. Phase 1 alle `require` (xpcall, `FindFirstChild`). Phase 2 `Init(Services)` in Reihenfolge (Welt bauen,
  `Provide`/`Handle` registrieren). Phase 3 `Start()` für alle außer DataService (Events, Scheduler-Jobs). Phase 4
  `DataService.Start()` **zuletzt**. Danach `Config.Validate()`-Warnungen (max. 25) und „Server gestartet ✅“.
- Modul-Form: `local X = {}; local Services: any = nil; function X.Init(s) Services = s end; function X.Start() end; return X`.
  Aufrufe nur zur Laufzeit über `Services.Y.Fn` oder `call("Y", "Fn", …)` (pcall). Optionale Dienste immer per pcall.
- Schleifen nur über `Lib/Scheduler`. Bereits verbundene Spieler beim Start: `for _, p in Players:GetPlayers() do task.spawn(onJoin, p) end`.
- Jede Pro-Spieler-Tabelle bei `PlayerRemoving` leeren; Limiter `.Clear(p)`.
- Signale (`OnX(cb)`) speichern Callbacks in Listen; Aufruf jedes Callbacks in `task.spawn` + pcall (nie Yield im Aufrufer).

## C4. `Shared/Types.luau` (WP1, vollständig – alle Pakete annotieren damit)
```lua
--!strict
export type Lang = "de" | "en"
export type NotifyKind = "Info" | "Success" | "Error" | "Event" | "Alarm" | "Announce"
export type Reply = { Ok: boolean, Message: string?, [string]: any }
export type PlayerData = { [string]: any } -- Schema §C12
export type LangPair = { de: string, en: string }
export type AssetSlot = { MeshId: number, TextureId: number, Scale: number, Offset: CFrame }

-- Gewährung (nur Turm-Seite! Felder aus Config.Shop.ForbiddenRobuxFields werden bei Robux-Quellen entfernt)
export type Grant = {
	Credits: number?, Cars: { string }?, Watches: { string }?, Accessories: { string }?, Decor: { [string]: number }?,
	Cosmetics: { string }?, Titles: { string }?, BoostX2: number?, BoostX5: number?, ExpressTokens: number?,
	InstantTokens: number?, SeasonPremium: boolean?, SeasonTiers: number?, SeasonXp: number?,
}

-- Markt
export type Side = "B" | "S"
export type OrderType = "MKT" | "LMT" | "STP" | "TP" | "OCO" | "TRL"
export type Timeframe = "1s" | "5s" | "1m" | "5m" | "15m" | "1T" | "1W"
export type RiskClass = "Stabil" | "Normal" | "Wild" | "ETF"
export type InstSet = "Azubi" | "Trader" | "Fonds" | "Tutorial"
export type Instrument = {
	Id: number, Ticker: string, Name: string, Story: LangPair, Sector: string, Class: RiskClass, Start: number, -- Cent
	DivBps: number, Set: InstSet, Logo: { Letter: string, Shape: "Circle" | "Square" | "Hex" | "Diamond" }, Ipo: boolean?,
}
export type QuoteRow = { Id: number, Flags: number, Close: number, HiOff: number, LoOff: number, Vol: number }
export type Frame = { Version: number, Tick: number, Flags: number, Regime: number, Rows: { QuoteRow } }
export type Candle = { T: number, O: number, H: number, L: number, C: number, V: number } -- Cent, Volumen in 10er-Lots
export type Position = { Q: number, C: number, R: number }
export type Order = {
	Id: number, I: number, Side: Side, Type: OrderType, Q: number, Lim: number?, Stp: number?, Tp: number?, Trl: number?,
	Peak: number?, Oco: number?, Res: number, Exp: number, T0: number, Bot: number?,
}
export type Alert = { Id: number, I: number, Px: number, Dir: "Up" | "Down" }
export type BotSlot = { Preset: string, Pct: number, Target: number?, On: boolean, Paused: boolean, DayNav: number }
export type DepotStats = {
	Trades: number, Wins: number, Losses: number, GrossWin: number, GrossLoss: number, PeakNav: number, MaxDD: number,
	BestPct: number, ReadWell: number,
}
export type Depot = {
	V: number, Cash: number, Basis: number, Pos: { [string]: Position }, Short: { [string]: any }, Orders: { Order },
	Alerts: { Alert }, Watch: { { number } }, Fills: { { number } }, Nav: { { number } }, Seq: { number }, NextId: number,
	LastTick: number, LastTransferDay: number, LastRefillUtcDay: number, AutoTransfer: boolean, Bots: { BotSlot },
	Stats: DepotStats, Tutorial: { T0: number, Q: number, Done: boolean },
}
export type NewsKind = "Fact" | "Rumor" | "Confirm" | "Deny" | "AsExpected" | "Sector" | "Macro" | "Earnings" | "Dividend"
	| "Warn" | "Crash" | "Rally" | "Ipo" | "Admin" | "Halt" | "Resume"
export type NewsItem = {
	Id: number, T: number, Kind: NewsKind, I: number?, Sector: string?, Key: string, Args: { [string]: any },
	Band: number?, Stars: number?, Dir: number?, Text: LangPair?, -- Text nur bei Admin-Eilmeldung (gefiltert)
}
export type CalendarItem = { T: number, Kind: "Earnings" | "Macro" | "Dividend" | "Crash" | "Rally" | "Ipo", I: number?, Key: string }
export type MarketEvent = {
	Id: string, Kind: "Crash" | "Rally" | "Pump" | "Dump" | "Halt" | "Resume" | "Ipo" | "News" | "Vol" | "Normalize" | "CancelAutoShow",
	Scope: "All" | "Sector" | "Inst", Target: (number | string)?, Strength: number, Ramp: number, Decay: number,
	StartTick: number, Until: number, Text: LangPair?, By: number,
}
export type FillInfo = {
	I: number, Side: Side, Q: number, Px: number, Fee: number, Pnl: number?, HeldS: number?, PctNav: number,
	Protected: boolean, ReadWell: boolean, Bot: boolean, Tick: number,
}
export type DayResult = { Day: number, Return: number, Trades: number, Qualifying: boolean, Tainted: boolean }
export type LeagueStats = {
	Week: number, SkillScore: number, AvgDailyBp: number, Trades: number, Days: number, Tainted: boolean, Qualified: boolean,
}

-- Fortschritt
export type Licence = {
	Key: string, Name: LangPair, Xp: number, Exam: { string }, Basis: number, BauKurs: number, TowerBonus: number,
	FeeBps: number, MaxWeight: number, MaxOrders: number, PosFactor: number, Layer: "Simple" | "Trader" | "Pro",
	Set: InstSet, MaxStage: number, MaxIpo: number, BotSlots: number,
}
export type TradingPerks = {
	Licence: number, Layer: string, BotSlots: number, BotLevels: { [string]: number }, Alerts: number, Watchlists: number,
	Layouts: number, Monitors: number, ResearchLead: number, MultiChart: boolean, Risk: number, Indicators: { [string]: boolean },
}

-- Turm
export type FloorData = { R: string, L: number, S: { string }, D: { string } }
export type MultPart = {
	Key: string, Value: number, Group: "Perm" | "Trader" | "Pass" | "Fixed" | "Timed",
	Source: "Earned" | "Skill" | "Bought" | "Event", Until: number?,
}
export type IncomeInfo = { PerSec: number, Steady: number, Mult: number, Parts: { MultPart } }

-- Welt/Events
export type PickupToken = { Id: number, Kind: string, Pos: Vector3, Until: number }
export type EventState = { Kind: string, Started: number, Until: number, Scope: "Local" | "Global", Data: { [string]: any }? }
```

## C5. Öffentliche Server-APIs (Verträge; Aufruf über `Services.<Name>`)
### C5.1 `Lib/Scheduler` (WP1, CC 1:1)
```lua
Scheduler.Every(name: string, hz: number, fn: (dt: number) -> ()): () -> ()
Scheduler.EveryFrame(name: string, fn: (dt: number) -> ()): () -> ()
Scheduler.Staggered<T>(name: string, hz: number, items: () -> { T }, fn: (item: T, dt: number) -> ()): () -> ()
Scheduler.Stats(): { [string]: { AvgMs: number, MaxMs: number } }   -- inkl. "_Total", Fenster 5 s
```
### C5.2 WP1 (Kern)
```lua
-- Services/Remotes: erstellt idempotent alle Remotes aus Net.RemoteList unter ReplicatedStorage.Remotes
Remotes: { Notify: RemoteEvent, State: RemoteEvent, Effect: RemoteEvent, Request: RemoteFunction, Admin: RemoteFunction,
	MarketFrame: RemoteEvent, Market: RemoteEvent, World: RemoteEvent, Replay: RemoteEvent, GrantCash: RemoteEvent }

-- DataService (CC 1:1 + neues DEFAULT_DATA §C12; SavedAt = os.time() im finalen Release-Save)
DataService.Get(p: Player): Types.PlayerData?
DataService.IsLoaded(p: Player): boolean
DataService.IsNoSave(p: Player): boolean
DataService.NoSaveReason(p: Player): ("Config" | "TestPlayer" | "NoApi")?
DataService.OnProfileLoaded(cb: (p: Player, data: Types.PlayerData) -> ())
DataService.OnProfileReleasing(cb: (p: Player, data: Types.PlayerData) -> ())
DataService.Save(p: Player): boolean
DataService.Reset(p: Player): boolean           -- behält Purchases.Receipts/Starter/PassSeasons/RobuxSpent
DataService.Migrate(data: Types.PlayerData)     DataService.DefaultData(): Types.PlayerData
DataService.LastSavedAt(p: Player): number      -- SavedAt beim Laden (für Offline), 0 = neu

-- PlayerStateService (CC 1:1)
PlayerStateService.Handle(action: string, fn: (p: Player, arg: any) -> Types.Reply,
	opts: { Rate: number?, Per: number?, Bucket: { number }?, NeedsReady: boolean? }?)   -- Bucket = {Kapazität, Nachfüllen/s}
PlayerStateService.Provide(key: string, fn: (p: Player) -> any)
PlayerStateService.MarkDirty(p: Player, ...: string)      -- Flush 0,2 s, voller State alle 20 s
PlayerStateService.Notify(p: Player, key: string, args: { any }?, kind: Types.NotifyKind?)
PlayerStateService.NotifyAll(key: string, args: { any }?, kind: Types.NotifyKind?, filter: ((Player) -> boolean)?)
PlayerStateService.NotifyRaw(p: Player, text: string, kind: Types.NotifyKind?)
PlayerStateService.Effect(p: Player, name: string, strength: number, data: any?)
PlayerStateService.EffectAll(name: string, strength: number, data: any?, filter: ((Player) -> boolean)?)
PlayerStateService.IsReady(p: Player): boolean   PlayerStateService.OnReady(cb: (p: Player) -> ())
PlayerStateService.LangOf(p: Player): Types.Lang
PlayerStateService.SetLeaderstat(p: Player, name: "Vermögen" | "Etagen", value: number | string)
-- eigene Handler: GetFull (1/5 s), SaveSettings (2/s, Schema Config.Client.SettingsSchema), TutorialFlag (2/s)

MetricsService.Funnel(p, step: number, name: string)
MetricsService.Economy(p, flow: "Source" | "Sink", currency: "CR" | "AKY", amount: number, balance: number, txType: string, sku: string?)
MetricsService.Progression(p, path: string, status: "Start" | "Complete" | "Fail", level: number)
MetricsService.Custom(p, name: string, value: number?, fields: { [string]: any }?)
SelfTestService.Run(): (number, number)   SelfTestService.LastReport(): { Passed: number, Total: number, Failures: { string }, At: number }?
```
### C5.3 WP3 (Markt-Engine; Detail MARKET.md §18)
```lua
MarketService.Tick(): number                                         -- letzter verarbeiteter Markt-Tick
MarketService.Quote(i: number): (number?, number?, number?)          -- bid, ask, mid (Cent) des letzten Ticks
MarketService.Candle1s(i: number, t: number): (number, number, number, number, number)?   -- O, H, L, C, Vol
MarketService.PriceAt(i: number, t: number): number                  -- mid (Cent), Random-Access
MarketService.NewCursor(i: number, t0: number): { Candle: (self: any, t: number) -> (number, number, number, number), Seek: (self: any, t: number) -> () }
MarketService.Instrument(i: number): Types.Instrument?
MarketService.ActiveIds(): { number }                                -- 1–36, 40–46, gelistete IPOs
MarketService.IsHalted(i: number): boolean
MarketService.Regime(): number
MarketService.DayIndex(): number
MarketService.HalfSpread(i: number): number                          -- Cent
MarketService.Dividends(t0: number, t1: number): { { I: number, Tick: number, Cents: number } }
MarketService.Calendar(days: number): { Types.CalendarItem }
MarketService.RecentNews(n: number): { Types.NewsItem }              -- max. 50
MarketService.FactNewsFor(i: number, t: number, window: number): Types.NewsItem?   -- „Gut gelesen“
MarketService.AdminWindowActive(t: number?): boolean
MarketService.AdminWindowsBetween(t0: number, t1: number): { { number } }
MarketService.AutoShowCancelled(week: number): boolean
MarketService.IsLocalMarket(): boolean                               -- Fallback-Seed aktiv (Studio/Ausfall)
MarketService.OnTick(cb: (t: number) -> ())                          -- nach PriceEngine.Step, vor CandleStore/Broadcast
MarketService.OnNews(cb: (n: Types.NewsItem) -> ())
MarketService.OnDayClose(cb: (day: number, t: number) -> ())
MarketService.Admin(action: string, args: { [string]: any }, by: Player): (boolean, string)   -- nur AdminService/EventService
MarketService.Stats(): { TickMs: number, BusOk: boolean, Events: number, Instruments: number }
-- Request-Handler: MktCandles, MktProfile, MktCalendar, MktNews
```
### C5.4 WP4 (Orders, Depot, Bots – einziger Depot-Schreiber)
```lua
OrderService.Depot(p: Player): Types.Depot?                          -- nur lesen
OrderService.Nav(p: Player): number                                  -- Cent
OrderService.Withdrawable(p: Player): (number, boolean, string?)     -- Cent, jetzt erlaubt, Grund-Schlüssel wenn nicht
OrderService.Withdraw(p: Player, reason: "Manual" | "Bell" | "Offline"): (number, string?)   -- bucht ab, gibt Cent zurück
OrderService.SetLicence(p: Player, idx: number)                      -- Cash/Basis anpassen (Fluss)
OrderService.AdminCredit(p: Player, cents: number): boolean          -- Cash + Basis, taint
OrderService.TaintWeek(p: Player, reason: string)
OrderService.HoldsShares(p: Player, i: number): number
OrderService.LeagueStats(p: Player): Types.LeagueStats
OrderService.CatchUpReport(p: Player): { Fills: number, Dividends: number, Bots: { { Preset: string, Pct: number } }, Alerts: number }?
OrderService.OnTrade(cb: (p: Player, f: Types.FillInfo) -> ())       -- XP, Quests, Ruf, Album
OrderService.OnDayResult(cb: (p: Player, r: Types.DayResult) -> ())
OrderService.OnBell(cb: (p: Player) -> ())                           -- je Spieler an jeder Glocke (Auto-Transfer)
OrderService.TutorialState(p: Player): ("None" | "Running" | "Done")
-- Request-Handler: TradePlace, TradeCancel, TradeModify, TradeBasket, TradeRefill, TradeAuto, TradeWatch, AlertSet,
--   AlertRemove, BotSet, BotToggle, DepotHistory, TutorialTrade
-- Markt-Code (Market/*, OrderService) darf KEINE Turm-/Shop-/Pass-Begriffe enthalten (FIREWALL §C11.4)
```
### C5.5 WP6 (Turm-Ökonomie)
```lua
TowerService.Income(p: Player): Types.IncomeInfo                     -- PerSec inkl. Zeitlich, Steady ohne Zeitlich
TowerService.Floors(p: Player): number    TowerService.Stage(p: Player): number    TowerService.RunSpend(p: Player): number
TowerService.TowerValue(p: Player): number                           -- 0,5 × RunSpend
TowerService.AddBoost(p: Player, kind: "X2" | "X5" | "Bull", seconds: number): boolean
TowerService.SetServerBoost(kind: "Parade" | "Bell", mult: number, seconds: number)
TowerService.SetEventMult(mult: number, untilUnix: number)           -- Golden Hour (geklemmt ≤ 3)
TowerService.AddExpressToken(p: Player, maxSeconds: number)          TowerService.ApplyExpress(p: Player, maxSeconds: number): boolean
TowerService.AddInstantToken(p: Player, n: number)
TowerService.ResetForIpo(p: Player, perks: { [string]: number }): boolean
TowerService.AdminSetFloors(p: Player, n: number): boolean
TowerService.CostMult(kind: "Floor" | "RoomLevel"): number           -- Bau-Boom-Rabatt (Event)
TowerService.SetCostEvent(kind: "Floor" | "RoomLevel" | "Both", mult: number, untilUnix: number)
TowerService.OnFloorBuilt(cb: (p: Player, floor: number, stage: number) -> ())
TowerService.OnStageUp(cb: (p: Player, stage: number) -> ())
TowerService.OnTransfer(cb: (p: Player, akyCents: number, credits: number) -> ())
PlotService.PlotOf(p: Player): number?    PlotService.OwnerOf(plot: number): Player?
PlotService.PlotCFrame(plot: number): CFrame    PlotService.LobbyCFrame(plot: number): CFrame
PlotService.IsOnOwnPlot(p: Player): boolean     PlotService.Teleport(p: Player, cf: CFrame)   -- + NoteTeleport
-- Request-Handler: TowerBuild, TowerRoom, TowerLevel, TowerHire, TowerFire, TowerEfficiency, TowerCollect, TowerTransfer,
--   TowerInstant, TowerExpress, TowerHelp, TowerVisit, TowerHome, TowerElevator, TowerName, TowerSkin, TowerNeon,
--   TowerPrivate, TowerDecor, TowerLayout, TowerAutoPlan
```
### C5.6 WP7 (Stadt, Grafik, Fahrzeuge)
```lua
CityService.Anchor(name: string): CFrame?   -- "Bell","BellZone","TowerTour","Showroom","Boutique","Helipad","Marina","Lookout",
                                            -- "PressScreen","IpoWall","HallOfFame","Academy","VipBalcony","Rooftop","Spawn"
CityService.Route(name: "Ring" | "Outer" | "Highway" | "Parade"): { Vector3 }
CityService.ShopPart(instId: number): BasePart?
CityService.PlotSite(plot: number): CFrame
CityService.BoardPart(name: string): BasePart?   -- Bestenlisten-/Hall-of-Fame-Flächen
CityService.Ready(): boolean
GraphicsService.Apply()                          -- einmal in Init (Lighting-Objekte; danach nie wieder serverseitig)
VehicleService.Spawn(p: Player, key: string): (boolean, string?)    VehicleService.Despawn(p: Player)
VehicleService.Owns(p: Player, key: string): boolean                VehicleService.GrantCar(p: Player, key: string): boolean
VehicleService.Active(p: Player): Model?                            VehicleService.CollectionValue(p: Player): number
-- Request-Handler: CarSpawn, CarDespawn, CarBuy, CarTune
```
### C5.7 WP8 (Turm-Optik, Lifestyle)
```lua
TowerVisualService.Rebuild(p: Player)                -- Hülle + Plot-Attribute aus Data.Tower (Scheduler-Warteschlange)
TowerVisualService.FloorAdded(p: Player, floor: number)
TowerVisualService.Clear(plot: number)               -- Kran-Abbau
TowerVisualService.Touch(p: Player)                  -- Layout-Attribut neu schreiben (Raum/Stufe/Personal/Deko geändert)
LifestyleService.Owns(p: Player, key: string): boolean
LifestyleService.GrantWatch(p: Player, key: string): boolean   LifestyleService.GrantAccessory(p: Player, key: string): boolean
LifestyleService.GrantDecor(p: Player, key: string, n: number): boolean
LifestyleService.TakeDecor(p: Player, key: string): boolean   LifestyleService.ReturnDecor(p: Player, key: string)
LifestyleService.Comfort(key: string): number
LifestyleService.CollectionValue(p: Player): number
-- Request-Handler: LifeBuy, LifeEquip
```
### C5.8 WP9 (Fortschritt & Sozial)
```lua
ProgressionService.AddXp(p: Player, base: number, reason: string, opts: { NoMult: boolean? }?): number
ProgressionService.Licence(p: Player): number                    ProgressionService.LicenceDef(p: Player): Types.Licence
ProgressionService.TradingPerks(p: Player): Types.TradingPerks   -- liest nur Prog.* (Robux-frei)
ProgressionService.TraderFactor(p: Player): (number, number, number)   -- gesamt, Lizenz-Teil, Ruf-Teil
ProgressionService.Level(p: Player): number     ProgressionService.Ruf(p: Player): number
ProgressionService.Stars(p: Player): number     ProgressionService.Perk(p: Player, branch: string): number
ProgressionService.IpoCount(p: Player): number  ProgressionService.Wealth(p: Player): number
ProgressionService.Title(p: Player): string     ProgressionService.AlbumSets(p: Player): number
ProgressionService.Unlock(p: Player, achId: string)
ProgressionService.AdminSetLicence(p: Player, idx: number): boolean   -- ruft OrderService.TaintWeek
RewardService.Track(p: Player, kind: string, amount: number, ctx: { [string]: any }?)
RewardService.GrantSeasonXp(p: Player, amount: number, reason: string)
RewardService.SeasonPremium(p: Player): boolean     RewardService.GrantSeasonPremium(p: Player): boolean
RewardService.AddSeasonTiers(p: Player, n: number): number
CommunityService.Announce(key: string, args: { any }?, filter: ((Player) -> boolean)?)
CommunityService.FriendsInServer(p: Player): number     CommunityService.RespektActive(p: Player): number
LeaderboardService.Submit(p: Player)
LeaderboardService.Top(board: string, n: number): { { UserId: number, Name: string, Value: number } }
-- Request-Handler: ProgLesson, ProgExam, ProgKnowHow, ProgKnowHowReset, ProgIpoPreview, ProgIpo, ProgPerk, ProgRespec,
--   ProgTitle, RewardLogin, RewardQuest, RewardReroll, RewardSeason, RewardCode, RewardTutorial, SocialRespekt,
--   SocialReact, SocialShow, SocialInvited, NotifyOptIn, BoardsGet
```
### C5.9 WP10 (Monetarisierung & CR-Konto)
```lua
MonetizationService.HasPass(p: Player, key: string): boolean     -- TycoonBundle zählt für Income2x/AutoCollect/OfflineVault
MonetizationService.PassFactor(p: Player): number                -- 1 / 2 / 3 / 4
MonetizationService.FixedFactor(p: Player): number               -- VIP 1,10 × Club 1,15 × Premium 1,10
MonetizationService.IsClub(p: Player): boolean
MonetizationService.LoadPasses(p: Player)
MonetizationService.RandomAllowed(p: Player): boolean?            -- nil = unbekannt = eingeschränkt
MonetizationService.TradingAllowed(p: Player): boolean            -- IsPaidItemTradingAllowed == true (sonst false)
MonetizationService.SetPolicyOverride(p: Player, field: string, value: boolean?)
MonetizationService.SimulatePurchase(p: Player, productKey: string): (boolean, string)
MonetizationService.TryOffer(p: Player, offerKey: string): boolean
MonetizationService.Quote(p: Player, productKey: string): number? -- CR-Angebot (Bau-Gutschein), 10 min gültig
ShopService.Credit(p: Player, amount: number, source: string): boolean   -- einziger CR-Gutschreiber (kein Yield)
ShopService.Debit(p: Player, amount: number, sink: string): boolean      -- einziger CR-Abzieher (kein Yield)
ShopService.Balance(p: Player): number
ShopService.Grant(p: Player, grant: Types.Grant, reason: string): boolean   -- alles-oder-nichts, Robux-Quellen gefiltert
ShopService.RefreshPlayer(p: Player)                              -- Attribute VIP/Club, MarkDirty
ShopService.Rotation(): { string }                                -- Boutique-Rotation (4 h, deterministisch)
ShopService.Core: { Sanitize: (grant: Types.Grant, robux: boolean) -> Types.Grant, ValidateGrant: (data: any, grant: Types.Grant) -> (boolean, string?),
	ApplyGrant: (data: any, grant: Types.Grant) -> (), CanSpend: (data: any, amount: number) -> boolean }
-- Request-Handler: ShopQuote, ShopPrecheck, ShopClubClaim
-- Quellen/Senken-Whitelist: Source ∈ {Income, Vault, Offline, Transfer, Quest, Login, Event, Pickup, Rain, Code, Purchase,
--   Admin, Achievement, Season, Tutorial, Refund}; Sink ∈ {Floor, RoomLevel, Room, Staff, Efficiency, Decor, Car, Tune,
--   Watch, Accessory, Admin}
```
### C5.10 WP11 (Admin, Events, Anti-Cheat)
```lua
AdminService.IsAdmin(p: Player): boolean     AdminService.Power(p: Player, name: string): any
AdminService.IsServerLocked(): boolean       AdminService.OwnerTradeBlocked(p: Player): boolean   -- ±120 s um eigene Markt-Events
AntiCheatService.NoteTeleport(p: Player, cf: CFrame)
AntiCheatService.Grace(p: Player, kind: "Impulse" | "Launch" | "Teleport", seconds: number, maxSpeed: number?)
AntiCheatService.SetAllowance(p: Player, a: { SpeedMult: number?, VerticalMult: number?, MaxSpeed: number? }?)
AntiCheatService.Exempt(p: Player, seconds: number)
AntiCheatService.Add(p: Player, reason: string, points: number, evidence: { [string]: any }?)
AntiCheatService.Score(p: Player): number    AntiCheatService.Flags(): { any }    AntiCheatService.Snapshot(p: Player): { [string]: any }
EventService.Active(): { Types.EventState }
EventService.EventMult(): number                                  -- Golden Hour/Admin (≤ 3)
EventService.IsAdminAbuse(): boolean
EventService.Start(kind: string, args: { [string]: any }, scope: "Local" | "Global", by: Player?): (boolean, string)
EventService.StartParade(buyer: Player, seconds: number)          EventService.StartFireworks(buyer: Player)
EventService.BearActive(): boolean
-- Request-Handler: EventPickup, Report   (Admin-RemoteFunction: alle Admin-Aktionen §B15)
```

## C6. Öffentliche Shared-APIs
### C6.1 WP1
```lua
-- Util (CC 1:1, --!strict): IsFinite, IsFiniteVector, FormatNumber, FormatTime, DeepCopy, Reconcile, Snapshot,
-- WeightedPick, RateLimiter, TokenBucket, UtcDay, IsoWeek, SetDayOffset, GetDayOffset, Hash (REUSE §3.1)

-- Format (--!strict, neu)
Format.Credits(n: number, lang: Types.Lang): string          -- "1,25 Mio." / "1.25M"; ≥ 9e15 -> "MAX"
Format.Aky(cents: number, lang: Types.Lang, compact: boolean?): string   -- "1.234,56 AKY" / "1.2K AKY"
Format.Price(cents: number, lang: Types.Lang): string        -- "123,45"
Format.Pct(fraction: number, lang: Types.Lang, digits: number?, signed: boolean?): string   -- "+2,35 %"
Format.Mult(x: number, lang: Types.Lang): string             -- "x7,4"
Format.Duration(seconds: number, lang: Types.Lang): string   -- "5 h 12 min" / "3:07"
Format.Compact(n: number, lang: Types.Lang): string           -- Tsd./Mio./Mrd./Bio./Brd. bzw. K/M/B/T/Qa

-- Clock (--!strict, neu; Server und Client)
Clock.EPOCH: number            -- 1767571200 (Mo 2026-01-05 00:00 UTC)
Clock.DAY_TICKS: number        -- 1200
Clock.Now(): number            -- Server: DateTime.now().UnixTimestampMillis/1000; Client: workspace:GetServerTimeNow()
Clock.Tick(): number           -- floor(Now()) − EPOCH
Clock.DayIndex(tick: number): number          Clock.DayMinute(tick: number): number   -- 0 ≤ x < 20
Clock.WeekIndex(tick: number): number         Clock.WeekStartTick(week: number): number
Clock.ClockTime(tick: number): number         -- Tageszeit der Welt (§A4)
Clock.IsNight(tick: number): boolean
Clock.BerlinOffset(unix: number): number      -- 3600 oder 7200 (EU-Sommerzeit-Regel)
Clock.NextBerlin(dow: number?, hh: number, mm: number, afterUnix: number): number   -- dow 1 = Mo … 7 = So, nil = täglich

-- AssetSlot (neu; Hybrid-Assets)
AssetSlot.IsSet(slot: Types.AssetSlot?): boolean
AssetSlot.Mesh(key: string, slot: Types.AssetSlot?, recipe: () -> Instance): Instance
	-- Server: AssetService:CreateMeshPartAsync(rbxassetid) (pcall) + TextureID; Client: Klon aus ReplicatedStorage.AssetCache[key];
	-- Fehler/0 -> recipe(). Ergebnis immer Model oder BasePart mit gleicher Pivot-Konvention wie das Rezept.
AssetSlot.Image(id: number?, fallback: string?): string        -- "rbxassetid://id" oder fallback ("" = Code-Grafik)
AssetSlot.SoundId(id: number?): string?                        -- nil = Sfx-Rezept
AssetSlot.PreloadServer(slots: { [string]: Types.AssetSlot })  -- beim Start: Mesh-Vorlagen nach ReplicatedStorage.AssetCache
AssetSlot.Verify(ids: { string }, onFail: (id: string) -> ())  -- ContentProvider:PreloadAsync mit Status-Callback

-- Net (CC-Muster): RemoteList (C8), GetRemotes() (Client wartet je Name ≤ 10 s, cached nur vollständig)
-- Lang (CC 1:1, FILES = §C15): T(lang, key, ...), Pick(lang, pair), For(p, override?), Missing(), Has(key)
-- Spring (CC 1:1)
-- Config/init: Validate(): { string }, ApplyLive(data) (AT_Live_v1, nur Felder aus Config.LiveFields, geklemmt)
```
### C6.2 WP3 / WP4 / WP6 / WP7 / WP8 / WP9 (rein, `--!strict`, ohne Roblox-Dienste → Luau-CLI-testbar)
```lua
-- WP3 Market/QuoteCodec
QuoteCodec.EncodeFrame(tick: number, flags: number, regime: number, rows: { Types.QuoteRow }): buffer   -- 9 + 10·n Byte
QuoteCodec.DecodeFrame(b: buffer): Types.Frame?                                   -- falsche Länge -> nil
QuoteCodec.EncodeCandles(inst: number, tf: number, startTick: number, ring: buffer, from: number, n: number): buffer   -- 8 + 10·n
QuoteCodec.DecodeCandles(b: buffer): (number, number, number, { Types.Candle })?   -- inst, tf, startTick, Kerzen
QuoteCodec.EncodeReplay(tick: number, close: number, phase: number): buffer       -- 9 Byte (u32, u32, u8)
QuoteCodec.DecodeReplay(b: buffer): (number, number, number)?
QuoteCodec.TF: { [Types.Timeframe]: number }                                      -- 1s=1,5s=5,1m=60,5m=300,15m=900,1T=1200,1W=8400
QuoteCodec.Aggregate(src: { Types.Candle }, tfTicks: number): { Types.Candle }     -- MARKET §9.2
-- WP4 Market/PortfolioMath
PortfolioMath.Fee(gross: number, bps: number, minFee: number): number              -- ceil
PortfolioMath.BuyCost(q: number, ask: number, bps: number): number
PortfolioMath.SellProceeds(q: number, bid: number, bps: number): number             -- floor
PortfolioMath.Basis(p: Types.Position, q: number): number
PortfolioMath.Nav(d: Types.Depot, bids: { [number]: number }): number
PortfolioMath.Withdrawable(nav: number, free: number, basis: number, capPct: number, threshold: number): number
PortfolioMath.DayReturn(navStart: number, navEnd: number, flow: number): number    -- Modified Dietz
PortfolioMath.Twr(returns: { number }): number
PortfolioMath.AvgDaily(twr: number, days: number): number
PortfolioMath.SkillScore(returns: { number }, maxDD: number): number               -- MARKET §12.6
PortfolioMath.MaxQty(ask: number, posCap: number): number                          -- Q × Preis < 2^53
-- WP4 Market/Indicators (Port js/indicators.js; Ausgabe gleich lang wie Eingabe, nil bis Warm-up)
Indicators.SMA(v: { number }, n: number): { number? }   Indicators.EMA(v, n)   Indicators.Bollinger(v, n?, mult?)
Indicators.RSI(v, n?)   Indicators.MACD(v, fast?, slow?, sig?)   Indicators.VWAP(candles)   Indicators.ATR(candles, n?)
Indicators.Stoch(candles, k?, d?)   Indicators.HeikinAshi(candles)
-- WP6 TowerMath
TowerMath.FloorCost(n: number): number   TowerMath.FloorIncome(n: number): number   TowerMath.BuildTime(n: number): number
TowerMath.LevelCost(n: number, l: number): number   TowerMath.StaffCost(n: number, key: string): number
TowerMath.EfficiencyCost(k: number): number          TowerMath.StageOf(floors: number): number
TowerMath.BaseIncome(floors: { Types.FloorData }, ctx: { Comfort: (key: string) -> number }): number
TowerMath.Multiplier(parts: { Types.MultPart }): (number, number)   -- gesamt, ohne Zeitlich
TowerMath.Offline(steadyPerSec: number, seconds: number, rate: number, capSeconds: number): number
TowerMath.Stars(runSpend: number): number
TowerMath.Clamp(n: number): number                                   -- ganzzahlig, 0 … 9e15
-- WP7 VehicleModels.Build(key: string, paint: string?, rims: string?, glow: string?): Model   VehicleModels.Recipes
-- WP8 TowerModels.Shell(stage: number, floor: number, skin: string, neon: string): { PartSpec }
--     TowerModels.Interior(room: string, level: number, staff: { string }, decor: { string }): { PartSpec }
--     TowerModels.Crown(stage: number, crown: string): { PartSpec }   DecorModels.Build(key): Model   LifestyleModels.Watch(key): Model
-- WP9 ProgressMath
ProgressMath.LevelFromXp(xp: number): (number, number)   ProgressMath.XpForLevel(l: number): number   -- 12,5·(L−1)²
ProgressMath.LicenceFor(xp: number, exams: { [string]: boolean }, table: { Types.Licence }): number
ProgressMath.RufLevel(points: number): number             ProgressMath.RufDecay(points: number, days: number, floorLvl: number): number
ProgressMath.WealthTitle(v: number): string               ProgressMath.QuestPick(seed: number, pool: { any }, n: number): { any }
```

## C7. Client-Architektur
### C7.1 `ctx` (von `Main.client.luau`, WP2)
```lua
export type Ctx = {
	Player: Player, Config: any, Lang: any, Util: any, Net: any, Types: any, Format: any, Clock: any,
	Remotes: { [string]: Instance }, Gui: ScreenGui, TouchGui: ScreenGui,   -- Gui mit UIScale, TouchGui unskaliert
	State: { [string]: any }, StateTime: number,
	Request: (action: string, arg: any?) -> any,                          -- Toast bei Message, nil bei Fehler
	RequestFull: (action: string, arg: any?, silent: boolean?) -> Types.Reply,
	Toast: (text: string, kind: string?) -> (), T: (key: string, ...any) -> string, Lang_: () -> Types.Lang,
	Hooks: any, Windows: any, UI: any, Modules: { [string]: any },
}
```
Startreihenfolge (Init alle in pcall, fehlgeschlagene Module werden entfernt; dann Start alle; **danach** Remotes verbinden):
`UI, Hooks, Sfx, Effects, Highlights, Controls, TouchControls, Quality, Hud, Settings, PhotoMode, MarketClient, ChartView(Bibliothek,
nur Init), Ticker, Monitors, NewsFeed, Terminal, DepotView, EffectsMarket, WorldLook, CityLife, Vehicles, Garage, TowerView, TowerUI,
Elevator, WelcomeBack, Boutique, EffectsTower, Tutorial, Academy, Quests, Season, Boards, Social, Prestige, Shop, EventsClient,
EffectsEvent` – bei Attribut `IsAdmin`: `AdminPanel, AdminTools, Fly, DebugOverlay`.
`FRAME_MODULES` (ein `PreRender`): UI, Effects, ChartView-Instanzen über Terminal/Monitors, Ticker, CityLife, WorldLook, TowerView,
Vehicles, EventsClient. `TICK_MODULES` (1 s): Hud, Settings, Quests, NewsFeed, Tutorial, Garage, Season, Prestige, Quality.

### C7.2 Hooks (frozen; nur diese Namen, Vertrags-Prüfer warnt bei unbekannten)
| Hook | Argumente | feuert |
|---|---|---|
| `State` | (state, changedKeys) | Main.client |
| `Notify` | (text, kind) | Main.client |
| `Effect:<Name>` | (strength, data) | Main.client (nach `Effects.Play`) |
| `WindowOpened` / `WindowClosed` | (name) | UI |
| `Settings` | (settings) | Settings |
| `Input` | (kind: "KBM"/"Gamepad"/"Touch") | Controls |
| `PhotoMode` | (on) | PhotoMode |
| `Quality` | (tier: "Low"/"Medium"/"High"/"Ultra") | Quality |
| `Quotes` | (frame: Types.Frame) | MarketClient (nach Decode) |
| `Market:News` / `Market:Event` / `Market:Halt` / `Market:Bell` / `Market:Ipo` / `Market:Calendar` / `Market:DayClose` | (data) | Main.client (Remote `Market`) |
| `World:Pickups` / `World:PickupGone` / `World:Event` / `World:Bear` / `World:Parade` | (data) | Main.client (Remote `World`) |
| `Replay` | (tick, close, phase) | MarketClient (Remote `Replay`) |
| `Plot:Enter` / `Plot:Leave` | (plotId, ownerUserId) | TowerView |
| `Tower:Built` / `Tower:Stage` | (floor/stage) | TowerUI (aus State-Diff) |
| `Vehicle:Enter` / `Vehicle:Exit` | (model?) | Vehicles |
| `Terminal:Instrument` | (instId) | Terminal (Auswahl geändert; NewsFeed „Zum Chart“ ruft `Terminal.OpenAt`) |

### C7.3 Windows (UI-Kit, CC 1:1)
`ctx.Windows.Register(name, open, close?)`, `Open(name)`, `Close(name?)`, `IsOpen(name?)`, `Toggle(name)`; immer nur ein Fenster;
Blur + Modal-Knopf. Fensternamen (frozen): `Terminal, Tower, Shop, Quests, Academy, Season, Boards, Social, Garage, Boutique,
Prestige, Settings, Admin, Calendar, WelcomeBack`. Terminal ist ein eigener Frame (Handy: Vollbild-Sheet), registriert über `Register`.

### C7.4 Effekte (frozen Registry; `Effects.Register(name, fn)` in Init des Besitzers, `Effects.Play(name, strength, data)`)
| Name | Besitzer | Daten |
|---|---|---|
| `Announce`, `AdminWarn`, `Confetti`, `CoinFly`, `Flash`, `Shake`, `Toast` | Effects (WP2) | CC-Formate; `Announce` ohne UserId → Toast |
| `Bell`, `ReadWell`, `DayRecap` | EffectsMarket (WP5) | `{Day, Return?, Transfer?}` |
| `BuildDone`, `StageUp`, `TransferTube`, `Collect`, `Crane` | EffectsTower (WP8) | `{Plot, Floor, Stage, Amount}` |
| `Reveal` (Auto-Drehteller) | Garage (WP7) | `{Key}` |
| `IpoCeremony`, `LicenceUp`, `TitleUp`, `QuestDone`, `Achievement` | Prestige (WP9) | `{Ticker, Licence, Title, Id}` |
| `MoneyRain`, `BullParade`, `Bear`, `GoldenBull`, `SkyShow`, `Fireworks`, `BossAppear`, `AbuseBanner`, `BellMoment` | EffectsEvent (WP11) | `{Seconds, Plot?, UserId?, Text?}` |
Ein Effekt = ein Besitzer (CC-Fix „eine Meldung, ein Weg“). Server sendet Effekte über `PlayerStateService.Effect/EffectAll`.

### C7.5 Client-Modul-APIs (Verträge zwischen Client-WPs)
```lua
-- WP2
UI.*  (CC-Kit, REUSE §4) + neu: UI.Faces { Display, Mono, Body }, UI.Segmented(parent, options, onChange): {Set, Get},
	UI.Sheet(title, height): Window, UI.PriceTag(label, cents, change), UI.Sparkline(parent, n): {Set(points)},
	UI.Ticker(parent): {SetRows(rows)}, UI.Chip, UI.StatTile, UI.RowCard, UI.RowActions, UI.Slider, UI.Cycler, UI.NavItem
	(aus CC AdminPanel gehoben), UI.Toast(text, kind), UI.SetToastTop(offset), UI.FetchPrice(id, infoType, cb)
Hooks.On(name, fn): () -> ()   Hooks.Once(name, fn)   Hooks.Fire(name, ...)
Controls.Bind(action, fn(state, input?), priority?): () -> ()   Controls.IsDown(action)   Controls.Input()   Controls.SetContext(c)
	-- Aktionen: Interact, Terminal, Tower, Shop, Quests, Menu, Sprint, Boost, Handbrake, ChartTf, ChartType, React,
	-- AdminPanel, Fly, Spectate, Debug, PhotoMode; Kontexte World | Vehicle | Terminal | Menu | Spectate
TouchControls.Show(set: "World" | "Vehicle" | "Terminal" | "None")
Hud.AddRightButton(icon, captionKey, color, order, onClick)   Hud.SetVisible(on)   Hud.SetPill(key, text?, untilUnix?)
	-- Pillen-Schlüssel: Bell, WorldEvent, Earnings, Boost, AdminAbuse, Vault
Hud.CreditsAnchor(): Vector2?   Hud.PulseCredits(amount?)
Settings.Get()   Settings.Set(path, value)   Settings.Open()
Sfx.Play(role, pos?, opts?)   Sfx.Duck(amount, seconds)   Sfx.SetMusic(kind?)
Effects.Register(name, fn)   Effects.Play(name, strength, data?)   Effects.SetHidden(on)
Highlights.Acquire(owner, adornee, props): handle?   Highlights.Release(handle)   Highlights.ReleaseOwner(owner)
Quality.Tier(): string   Quality.Budget(key: string): number    -- Lights, Traffic, Drones, Monitors, Candles, Particles, InteriorRadius
PhotoMode.Toggle()   PhotoMode.IsActive()
-- WP5
MarketClient.Frame(): Types.Frame?   MarketClient.Quote(i): (number?, number?)        -- close, change seit Tagesbeginn
MarketClient.Candles(i, tf, cb: ({ Types.Candle }) -> ())                            -- Ring + Historie (MktCandles), gecacht
MarketClient.Instrument(i)   MarketClient.Allowed(i): boolean   MarketClient.Regime(): number
ChartView.new(parent, opts: { Candles: number, Volume: boolean, Pane: string?, Style: string, Labels: boolean }): View
	-- View:SetData(candles, tf)  View:PushQuote(close, tick)  View:SetIndicators(map)  View:SetStyle(s)  View:Step(dt)  View:Destroy()
Terminal.Open()   Terminal.OpenAt(instId)   Terminal.IsOpen()
NewsFeed.Recent(): { Types.NewsItem }
-- WP7
WorldLook.SetOverride(kind: string?)   CityLife.SetDensity(mult)   Vehicles.Current(): Model?   Garage.Open()
-- WP8
TowerView.InsideTower(): number?   TowerUI.Open(tab?)   Elevator.Go(floor)   WelcomeBack.Show(report)
-- WP9
Tutorial.Step(): number   Tutorial.IsActive(): boolean   Prestige.OpenPreview()   Boards.Open(board?)
-- WP10
Shop.Open(tab?)   Shop.ShowOffer(key)
-- WP11
AdminPanel.Toggle()   Fly.Toggle()   DebugOverlay.Toggle()   EventsClient.Active(): { Types.EventState }
```

## C8. Remotes (alle; `Net.RemoteList`, erzeugt von `Services/Remotes`, Ordner `ReplicatedStorage.Remotes`)
| Name | Klasse | Richtung | Nutzlast | Takt / Grenze |
|---|---|---|---|---|
| `Notify` | RemoteEvent | S→C | `(text: string ≤ 500, kind: NotifyKind)` bereits lokalisiert | ereignisgetrieben |
| `State` | RemoteEvent | S→C | `(partial: {[key]: any}, full: boolean)` Sticky-Merge | Flush 0,2 s, voll alle 20 s |
| `Effect` | RemoteEvent | S→C | `(name: string, strength: number, data: table?)` Name aus §C7.4 | – |
| `Request` | RemoteFunction | C→S | `(action: string, arg: table?) → Reply` | global 8/s + je Aktion §C9 |
| `Admin` | RemoteFunction | C→S | `(action: string, args: table?) → {Ok, Message, Data}` | 12/s **vor** Admin-Prüfung |
| `MarketFrame` | RemoteEvent (zuverlässig) | S→C | `buffer` 9 + 10·n Byte (MARKET §10.2), `FireAllClients` einmal kodiert | 1 Hz; 43 Instr. = 439 B, mit 4 IPOs 479 B |
| `Market` | RemoteEvent | S→C | `(kind, data)`: `News` (Types.NewsItem), `Event` ({Kind, Phase: "Warn"/"Run"/"End", StartTick, Until}), `Halt` ({I?, Until}), `Bell` ({Day}), `Ipo` ({I, Phase, T0}), `Calendar` (Delta {Types.CalendarItem}), `DayClose` ({Day, Return?}) – nur `DayClose` per `FireClient`, Rest `FireAllClients` | Ø 1/40 s, Spitze 3/s |
| `World` | RemoteEvent | S→C | `(kind, data)`: `Pickups` ({Types.PickupToken} nur an den Eigentümer), `PickupGone` ({Id}), `Event` (Types.EventState), `Bear` ({Have, Goal}), `Parade` ({UserId, Until}) | ereignisgetrieben, ≤ 4/s |
| `Replay` | RemoteEvent | S→C | `buffer` 9 Byte (QuoteCodec.EncodeReplay) – v1 nur Tutorial-ACAD an einen Spieler | 1 Hz während Tutorial |
| `GrantCash` | RemoteEvent | – | **Honeypot**: wird nie von unserem Code gefeuert; `OnServerEvent` → AntiCheat +100 + Kick | – |
Client wartet je Name ≤ 10 s (`Net.GetRemotes`). Remotes werden erst **nach** Init+Start aller Client-Module verbunden.

## C9. Request-Aktionen (frozen; jede registriert ihr Besitzer-WP mit `PlayerStateService.Handle`; Namen nur Buchstaben)
Alle Argumente: exakte Schlüssel, Typen, `Util.IsFinite`, Ganzzahl-Prüfung (`n == math.floor(n)`), Klemmen. Antwort immer
`{Ok, Message?}` + genannte Felder. Rate „k/s“ = RateLimiter, „B c/r“ = Token-Bucket Kapazität c, Nachfüllen r/s.
| Aktion | WP | Argumente | Rate | Antwort-Felder / Regel |
|---|---|---|---|---|
| `GetFull` | 1 | – | 1/5 s | voller State |
| `SaveSettings` | 1 | `{[key]: value}` | 2/s | Schema `Config.Client.SettingsSchema` |
| `TutorialFlag` | 1 | `{Flag: string}` | 2/s | Flags-Whitelist |
| `MktCandles` | 3 | `{I: int, Tf: Timeframe}` | B 6/2 | `{Buf: buffer}` (QuoteCodec, gecacht je I/Tf/letzte Kerze) |
| `MktProfile` | 3 | `{I: int}` | B 6/1 | Fundamentaldaten, Analysten (Trefferquote), nächste Termine |
| `MktCalendar` | 3 | `{Days: 1–3}` | B 6/1 | `{Items}` |
| `MktNews` | 3 | `{}` | 2/s | `{Items}` letzte 50 |
| `TradePlace` | 4 | `{I, Side, Type, Qty?: int, Pct?: 10/25/"Max", Lim?, Stp?, Tp?, Trl?: bp, Protect?: bool, Exp?: "DAY"/"24H", MaxPx?, MinPx?, Seq: int}` | B 6/1,5 | `{Fill?, OrderId?}`; Seq-Dedupe (letzte 32, Fenster rückt auch bei Ablehnung vor), Fehleingabe-Band ±50 % um mid, Lizenz-Instrument, Klumpen, Positions-Grenze, offene Orders, Besitzer-Sperre ±120 s |
| `TradeCancel` | 4 | `{OrderId, Seq}` | B 10/3 | – |
| `TradeModify` | 4 | `{OrderId, Lim?, Stp?, Tp?, Trl?, Seq}` | B 10/3 | – |
| `TradeBasket` | 4 | `{Basket: string, Pct: 10/25, Seq}` | 1/2 s | ab Trader I; Einzel-Orders je Wert |
| `TradeRefill` | 4 | `{}` | 1/5 s | Rettungsschirm §B8.4 |
| `TradeAuto` | 4 | `{On: bool}` | 1/s | Auto-Transfer an der Glocke |
| `TradeWatch` | 4 | `{List: int, Ids: {int} ≤ 12}` | 1/s | Watchlists ≤ Know-how |
| `AlertSet` / `AlertRemove` | 4 | `{I, Px, Dir}` / `{Id}` | 2/s | ≤ Know-how-Alarme |
| `BotSet` / `BotToggle` | 4 | `{Slot, Preset, Pct, Target?}` / `{Slot, On}` | 2/s | Slots/Stufen aus `TradingPerks` |
| `DepotHistory` | 4 | `{}` | 1/s | `{Fills, Nav}` |
| `TutorialTrade` | 4 | `{Action: "Start"/"Buy"/"Sell"}` | 2/s | ACAD §B8.6 |
| `TowerBuild` | 6 | `{}` | 4/s | nächste Etage (Tor, CR, Kran frei) |
| `TowerRoom` / `TowerLevel` | 6 | `{Floor, Room}` / `{Floor}` | 8/s | – |
| `TowerHire` / `TowerFire` | 6 | `{Floor, Staff}` / `{Floor, Slot}` | 8/s | – |
| `TowerEfficiency` | 6 | `{}` | 4/s | – |
| `TowerCollect` | 6 | `{}` | 4/s | Abstand ≤ 70 Studs zur Plot-Mitte |
| `TowerTransfer` | 6 | `{}` | 1/5 s | ruft `OrderService.Withdraw` → `ShopService.Credit(…, "Transfer")` |
| `TowerInstant` / `TowerExpress` | 6 | `{}` | 1/s | Token verbrauchen |
| `TowerHelp` | 6 | `{OwnerUserId}` | 1/s | Abstand ≤ 40 Studs zur Baustelle, AccountAge ≥ 3 |
| `TowerVisit` / `TowerHome` | 6 | `{UserId}` / `{}` | 1/2 s | Teleport + NoteTeleport |
| `TowerElevator` | 6 | `{Floor}` | 2/s | nur im eigenen/besuchten Tower, Privat-Etagen gesperrt |
| `TowerName` / `TowerSkin` / `TowerNeon` / `TowerPrivate` | 6 | `{A, N}` / `{Skin}` / `{Color}` / `{Floor, On}` | 2/s | Besitz/Freischaltung prüfen |
| `TowerDecor` | 6 | `{Floor, Slot, Key?}` | 8/s | Lager via LifestyleService |
| `TowerLayout` / `TowerAutoPlan` | 6 | `{On}` / `{}` | 1/s | – |
| `CarSpawn` / `CarDespawn` | 7 | `{Key}` / `{}` | 1/3 s | Garage/Plaza-Spawnpunkt |
| `CarBuy` / `CarTune` | 7 | `{Key}` / `{Key, Paint?, Rims?, Glow?}` | 2/s | Preis aus Config, Aktionärs-Rabatt |
| `LifeBuy` / `LifeEquip` | 8 | `{Key}` / `{Slot, Key?}` | 2/s | Uhren, Accessoires, Deko |
| `ProgLesson` | 9 | `{Id, Answers: {int}}` | 1/s | Quiz serverseitig geprüft |
| `ProgExam` | 9 | `{Licence: int}` | 1/s | Aufgaben-Fortschritt, Bestehen |
| `ProgKnowHow` / `ProgKnowHowReset` | 9 | `{Node}` / `{}` | 2/s / 1/min | – |
| `ProgIpoPreview` / `ProgIpo` | 9 | `{}` / `{Ticker: string, Token: string}` | 1/s / 1/10 s | Token aus Vorschau (60 s gültig), Filter + Sperrliste |
| `ProgPerk` / `ProgRespec` / `ProgTitle` | 9 | `{Branch}` / `{}` / `{Id}` | 2/s | – |
| `RewardLogin` / `RewardQuest` / `RewardReroll` | 9 | `{}` / `{Id}` / `{Id}` | 2/s | – |
| `RewardSeason` | 9 | `{Tier, Track: "Free"/"Premium"}` | 2/s | – |
| `RewardCode` | 9 | `{Code: string ≤ 20}` | 3/60 s | nur CR/Kosmetik |
| `RewardTutorial` | 9 | `{Step: int}` | 2/s | Schritt-Belohnungen einmalig |
| `SocialRespekt` | 9 | `{UserId}` | 1/s | 1 je Tower je UTC-Tag, AccountAge ≥ 3, ≥ 10 min Sitzung |
| `SocialReact` / `SocialShow` | 9 | `{Kind}` / `{}` | 2/s / 1/60 s | – |
| `SocialInvited` / `NotifyOptIn` | 9 | `{}` / `{Result: bool}` | 1/10 s | nur Protokoll/Metriken |
| `BoardsGet` | 9 | `{Board, Scope: "Global"/"Friends"/"Server"}` | 1/s | aus Cache |
| `ShopQuote` | 10 | `{Key}` | 1/s | `{Credits, Until}` |
| `ShopPrecheck` | 10 | `{Key, UserId?}` | 2/s | Policy-/Empfänger-/Besitz-Prüfung vor `Prompt…Purchase` |
| `ShopClubClaim` | 10 | `{}` | 1/s | tägliche Club-Gabe |
| `EventPickup` | 11 | `{Id: int}` | 10/s | Token gehört Spieler, Fenster gültig, Abstand ≤ 12 Studs |
| `Report` | 11 | `{UserId, Reason}` | 3/600 s | CC-Muster |

## C10. State-Schlüssel (frozen; `PlayerStateService.Provide` durch Besitzer, nie `nil` für „leer“)
| Schlüssel | WP | Inhalt |
|---|---|---|
| `Settings`, `Flags`, `Server` | 1 | CC; `Server = {Version, Studio, NoSave, LocalMarket}` |
| `Market` | 3 | `{Week, Day, Regime, Halts: {[I]: Until}, AdminWindow: bool, AutoShowCancelled: bool}` (nie der Seed!) |
| `Depot` | 4 | `{Cash, Basis, Nav, Pos, Orders, Alerts, Watch, Bots, AutoTransfer, Withdrawable, TransferReady, RefillReady, Stats}` |
| `League` | 4 | `Types.LeagueStats` + `{Tier, LastTier}` |
| `Credits` | 10 | Zahl (CR) |
| `Passes`, `Club`, `Boosts`, `Offers`, `RandomAllowed`, `TradingAllowed`, `Starter` | 10 | Pass-Schlüssel→bool, Club bool, `{X2, X5, Bull}` Restsekunden, … |
| `Tower` | 6 | `{Floors, Stage, Vault, VaultCap, Build: {Floor?, Until?}, Eff, Skin, Neon, Name, Private, Tokens: {Express, Instant}, CostEvent}` |
| `Income` | 6 | `Types.IncomeInfo` (alle 5 s oder bei Änderung) |
| `Plot` | 6 | `{Id, Visiting?: UserId}` |
| `Garage` | 7 | `{Cars, Active, Tune}` |
| `Life`, `Storage` | 8 | `{Watches, Accessories, Equipped}`, `{Decor: {[key]: n}}` |
| `Prog` | 9 | `{Xp, Level, Licence, Exams, KnowHow, KH, Ruf, RufPts, Title, Titles, Album, Ach, Stars, Perks, Ipos}` |
| `Quests`, `Login`, `Season`, `Social` | 9 | Tages-/Wochenquests mit Fortschritt; Kalender; Pass; Respekt/Einladungen |
| `Event` | 11 | `{Active: {Types.EventState}, Next: {Kind, At}, AdminAbuse: bool, BearHave, BearGoal}` |
Player-Attribute: `IsAdmin` (WP11), `PingMs` (WP1), `Vip`/`Club` (WP10), `Title`/`Licence`/`TowerName` (WP9/WP6, Namensschild).
Plot-Attribute (WP8 schreibt, Clients lesen): `Owner`, `Stage`, `Floors`, `Layout` (§C12.3), `Skin`, `Neon`, `Crown`, `Name`.

## C11. Sicherheit, Anti-Cheat, Firewall
### C11.1 Grundsätze
Server-Autorität für alles Wertvolle; Client sendet nur Absichten; Ausführung zum Server-Kurs des **zuletzt gesendeten** Ticks;
`MaxPx/MinPx` nur als Schutz; Ganzzahl-Geld; Session-Sperre; idempotente Belege (CC-Fluss: ≤ 60 s auf Profil warten, gleiche
PurchaseId abwarten, Beleg vorhanden → Granted, Prepare darf yielden, Grant + Beleg ohne Yield, Granted erst nach erfolgreichem Save).

### C11.2 Pro Remote/Aktion
| Bedrohung | Abwehr |
|---|---|
| gefälschte Preise/Mengen | nur Absicht; Server rechnet Preis/Fill; Mengen ganzzahlig 1…MaxQty; Fehleingabe-Band ±50 % |
| Doppelklick/Retry | Seq-Dedupe (letzte 32, gleiche Antwort), Fenster rückt bei Ablehnung vor; UI-Busy-Flag nur UX |
| Server-Hopping | globaler deterministischer Kurs, Events im selben Tick, 10-s-Halt bei Verspätung, Session-Sperre |
| Offline-Zeitreise | `SavedAt` = Server-`os.time()`; Orders gelten ab Tick nach Erstellung; Abwesenheit geklemmt [0, Deckel] |
| Tresor aus der Ferne | Abstand ≤ 70 Studs zur Plot-Mitte (Server), Auto-Kassierer nur mit Pass |
| Pickup-Fälschung | Server-Token je Spieler (Id, Position, Fenster), Abstand ≤ 12 Studs, max. je Event |
| Alt-Farming | kein Transfer zwischen Spielern; Respekt/Bau-Hilfe nur AccountAge ≥ 3 Tage + 10 min Sitzung; Einladungs-Belohnungen max. 10/Woche |
| Admin-Insider | Markt-Events global angekündigt (10 s Vorlauf), Besitzer-Trades ±120 s gesperrt + immer aus der Liga ausgenommen |
| Remote-Spam | globales Limit 8/s + Aktions-Buckets; `p.Parent`-Guard vor allem |
| gefälschte Remotes | Honeypot `GrantCash` (+100, Kick) |
| Text-Missbrauch | Ticker/Admin-Eilmeldung: `TextService:FilterStringAsync` + `GetNonChatStringForBroadcastAsync` + Sperrliste; Namen nur Bausteine |
| Engine-Fehler | `MarketAudit` prüft jeden Fill gegen `PriceAt` (muss exakt passen), Abweichungen → Admin-Statistik |

### C11.3 Bewegung & Kollisionsgruppen (WP7 registriert in `VehicleService.Init`, vor jedem Spawn)
`workspace:RegisterCollisionGroup` für `Characters`, `Cars`, `World` (Standard), `Pickups`; `PhysicsService:CollisionGroupSetCollidable`:
Cars×Characters **false**, Cars×Cars **false**, Cars×World true, Pickups×* false (Pickups sind client-lokal ohnehin nicht kollidierend).
Charakter-Teile bekommen bei `CharacterAdded` die Gruppe `Characters`. AntiCheat (CC slim, 5 Hz gestaffelt): Erlaubnisse für Auto
(Klassen-Deckel), Aufzug/Teleport (`NoteTeleport`, 1 s Gnade, Wurzelhöhen-Versatz), Jetpack (`SetAllowance{VerticalMult, SpeedMult}`
nur aktiv), Admin-Fly/Noclip (exempt). Lokal versteckte Geometrie (private Etagen-Türen) wird im Noclip-Strahltest ignoriert.

### C11.4 Firewall-Durchsetzung (macht die Fragebogen-Antwort wahr)
1. **Modulgrenze:** `src/server/Market/**`, `Services/MarketService.luau`, `Services/OrderService.luau`, `src/shared/Market/**` dürfen
   nur `Config`, `Util`, `Types`, `Clock`, `Shared/Market/*`, `Lib/Scheduler` direkt nutzen und zur Laufzeit nur
   `Services.DataService`, `Services.PlayerStateService`, `Services.MarketService`, `Services.OrderService`,
   `Services.ProgressionService` (nur `TradingPerks`, `LicenceDef`, `Licence`), `Services.AdminService` (nur `OwnerTradeBlocked`),
   `Services.MetricsService`, `Services.AntiCheatService`.
2. **Vertrags-Prüfer-Regel `FIREWALL`** (WP1): diese Dateien dürfen die Token `Credits`, `TowerService`, `ShopService`,
   `MonetizationService`, `LifestyleService`, `VehicleService`, `HasPass`, `PassFactor`, `Boost`, `Prestige`, `Grant(`
   nicht enthalten (Kommentare ausgenommen; `Stars` ist erlaubt – Quellen-Sterne der Gerüchte) → ERROR.
3. **Depot-Schreibtrichter:** nur `Portfolio.Credit(d, cents, reason)` / `Portfolio.Debit(d, cents, reason)` ändern `Depot.Cash`
   und `Depot.Basis`; Gründe-Whitelist `Start, Licence, Refill, Trade, Fee, Dividend, BotWage, Transfer, Admin, Tutorial, Migration`.
   Prüfer-Regel `DEPOT_WRITE`: Zuweisungen an `.Depot.` / `Depot.Cash` / `Depot.Basis` außerhalb `server/Market/*` und
   `Services/OrderService.luau` (und `DataService`-Default/Migration) → ERROR.
4. **Grant-Filter:** `ShopService.Core.Sanitize(grant, robux=true)` entfernt `Config.Shop.ForbiddenRobuxFields` (§B14.5); `Types.Grant`
   hat ohnehin keine AKY-/XP-Felder.
5. **SelfTest „Firewall“** (WP10 `EconomyTests`): Test-Profil; für **jedes** Produkt, jeden Pass (Refresh), jede Saison-Premium-Stufe,
   die Club-Tagesgabe, jedes Admin-Abuse-Event (Nicht-Markt) und jeden Code: `Depot`, `Prog.Licence/Xp/KnowHow/KH/Ruf`, `Depot.Bots`
   vorher/nachher **byte-gleich** (`Util.DeepCopy` + rekursiver Vergleich).
6. **SelfTest „NoPaidRandom“:** `Config.Shop.RandomItemsEnabled == false` und kein Shop-Eintrag hat `Random`/`Odds`/`Weights`.
7. **Prüfer-Regel `BANNED_WORDS`** (§0.7) über Lang + Config-Anzeigetexte.

## C12. Datenschema (WP1 `DataService`; DataStore `AT_Player_v1`, Schlüssel `P_<UserId>`, Datensatz `{Data, Lock = {JobId, Time}}`)
### C12.1 `DEFAULT_DATA` (nur String-Schlüssel; nie `nil` – leere Tabellen/`false`/`0`; Migrate zuerst, dann Reconcile, dann Sanitize)
```lua
DEFAULT_DATA = {
	V = 1, Created = 0, SavedAt = 0, LastUtcDay = 0, Playtime = 0, Sessions = 0,
	Credits = 0,                                           -- CR, ganzzahlig, ≤ 9e15
	Depot = { V = 1, Cash = 2500000, Basis = 2500000,      -- Cent (25.000 AKY)
		Pos = {}, Short = {}, Orders = {}, Alerts = {}, Watch = { {} }, Fills = {}, Nav = {}, Seq = {}, NextId = 1,
		LastTick = 0, LastTransferDay = -1, LastRefillUtcDay = -1, AutoTransfer = true, Bots = {},
		Stats = { Trades = 0, Wins = 0, Losses = 0, GrossWin = 0, GrossLoss = 0, PeakNav = 0, MaxDD = 0, BestPct = 0, ReadWell = 0 },
		Tutorial = { T0 = 0, Q = 0, Done = false } },
	League = { Week = 0, Returns = {}, Trades = 0, Days = 0, Tainted = false, LastGrantedWeek = 0, Trophies = {} },
	Tower = { Floors = {}, Vault = 0, Build = {}, Eff = 0, Skin = "GlassBlue", Neon = "Accent", Crown = "",
		Name = { A = 1, N = 1 }, Private = {}, RunSpend = 0, KeepLayout = true, Layouts = {}, Express = {}, Instant = 0,
		InstantDay = 0, Helpers = {} },
	Garage = { Cars = { LamCity = true }, Active = "LamCity", Tune = {} },
	Life = { Watches = {}, Accessories = {}, Equipped = { Watch = "", Acc = {} } },
	Storage = { Decor = {} },                              -- [key] = Anzahl
	Prog = { Xp = 0, Licence = 1, Exams = {}, ExamProgress = {}, Lessons = {}, KH = {}, KHSpent = 0, KHResetWeek = 0,
		Ruf = 0, RufDay = 0, RufToday = 0, Title = "", Titles = {}, Album = {}, Ach = {}, AchProgress = {}, Badges = {},
		XpDay = 0, XpCounts = {},
		Prestige = { Count = 0, Stars = 0, Perks = {}, Firmenwert = 0, Tickers = {}, RespecFree = false } },
	Quests = { Day = 0, Daily = {}, Rerolled = false, Week = 0, Weekly = {}, Starter = 1, StarterDone = {} },
	Login = { LastDay = 0, Streak = 0, Best = 0, Freeze = 1, FreezeWeek = 0, Cycle = 1, Track = 0 },
	Season = { Id = 1, Xp = 0, Premium = false, ClaimedFree = {}, ClaimedPremium = {}, PlayToday = 0, PlayDay = 0 },
	Social = { RespektGiven = {}, RespektDay = 0, ReferredBy = 0, ReferralDone = false, ReferralWeek = 0, ReferralCount = 0, Group = false },
	Boosts = { X2 = 0, X5 = 0, Bull = 0 },                 -- Rest-Spielsekunden
	Notif = { LastPrompt = 0, OptIn = false },
	Purchases = { Receipts = {}, RobuxSpent = 0, Starter = false, PassSeasons = {}, Quote = {}, ClubClaimDay = 0, Gifts = 0 },
	Stats = { LifetimeCredits = 0, Collected = 0, FloorsBuilt = 0, Ipos = 0, Drive = 0, Pickups = 0 },
	Settings = {}, Flags = {}, Mod = {},
}
```
- Dictionaries mit Zahl-Ids (Positionen `Pos`, `Album`) nutzen **String-Schlüssel** (`tostring(instId)`).
- Ringpuffer: `Fills` max. 100 (`{tick, inst, side, qty, px, fee, pnl}`), `Nav` max. 72 Börsentage (`{day, navStart, navEnd, flow}`),
  `League.Returns` max. 504; Belege max. 60; `Orders` ≤ 50; `Alerts` ≤ 18.
- Größe Ø ≈ 25 KB (Limit 4 MB). Marktkerzen **nie** in Spielerdaten.
- `Reset` behält `Purchases.Receipts/Starter/PassSeasons/RobuxSpent`.
### C12.2 Migration
`Data.V = 1` (`Config.Tech.DataVersion = 1`). `DataService.Migrate(data)`: `if data.V == nil then data.V = 1 end`; künftige Schritte
`if data.V < 2 then … data.V = 2 end` (nie Felder löschen, nur umbenennen/umrechnen). `Depot.V` eigenständig (Markt-Schema).
### C12.3 Plot-Attribut `Layout` (≤ 2 KB, von TowerVisualService geschrieben)
Je Etage `Raum:Stufe:Personal:Deko` mit Kurz-Codes, getrennt durch `;` – z. B. `D:3:IA:k1,s4,p2;C:1::` (`D` = Desk, Personal-Codes
`I/A/S/Q`, Deko-Codes aus `Config.Decor[key].Code`). Privat-Etagen als Präfix `!`.

## C13. Weitere DataStores, MessagingService, MemoryStore, Budget
| Speicher | Inhalt |
|---|---|
| `AT_Market_v1` (DataStore) | `Seed_W<w>` (31 Bit, `UpdateAsync` „nur setzen wenn leer“, erster Server legt auch `Seed_W<w+1>` an), `Close_W<w>` (Wochenschlusskurse), `Ipo_S<s>` (gelistete IPO-Startkurse) |
| `AT_Global` (DataStore) | Admin-Log-Kopie je Woche `AdminLog_W<w>`, Live-Kalender-Overrides |
| `AT_Live_v1` (DataStore) | LiveConfig (validiert, geklemmt; `Config.ApplyLive`) |
| `AT_Stats_v1` | 8 Shard-Zähler (Robux, Käufe, BG) |
| `AT_Mod_v1` | Flags, Meldungen, Bann-Log, Admin-Log |
| `AT_LB_*` (OrderedDataStore) | §B11.1 |
| `AT_Groups_v1` | v1.1 Hedgefonds-Gruppen |
| `AT_Bus_W<w>` (MemoryStore SortedMap) | Markt-Admin-Events, Schlüssel `string.format("%012d_%s", aktivierungsTick, guid)`, Ablauf 26 h – **Wahrheit** |
| `AT_Heartbeat` (MemoryStore HashMap) | Server-Herzschlag `{JobId → Spieler}` 60 s Ablauf (Admin-Dashboard „global online“) |
| Messaging-Thema `AT_Global` | `Announce {Text, UserId, Name, Id}`, `AdminAbuse {Kind, Until, Args, Id}` (Nicht-Markt) |
| Messaging-Thema `AT_EV` | nur Schlüssel eines neuen Bus-Events (Schnellweg); jeder Server pollt zusätzlich alle 5 s |
Grenzen (offizielle Formeln, MARKET §8.3): Messaging senden 600 + 240 × Spieler/min, empfangen (40 + 80 × Server)/min je Thema;
MemoryStore 1000 + 120 × CCU Anfragen/min, Speicher 64 KB + 1,2 KB × CCU → nur flüchtige Daten. Globale Nachrichten: jedes Feld
validiert, `Until ≤ now + Config.Events.MaxGlobalSeconds (3600)`, Dedupe per Id (letzte 200). Studio ohne API: Bus nur lokal.

## C14. Config-Schema (CC-Stil: deutscher Banner, nummerierte Abschnitte, `assert` bei doppelten Ids/Schlüsseln, jedes Kind exportiert `Validate(Config): {string}`)
### C14.1 `Config/init.luau` (WP1)
```lua
Config.GameName = "AKYTEX TYCOON"; Config.Version = "1.0.0"
Config.Admin = { OwnerIsAdmin = true, GroupOwnerIsAdmin = true, StudioIsAdmin = true, StudioAllPlayersAdmin = false }
Config.Tech = { DataStoreName = "AT_Player_v1", DataVersion = 1, KeyPrefix = "P_", MessagingTopic = "AT_Global", BusTopic = "AT_EV",
	AutoSaveSeconds = 90, AutoSaveStagger = 0.5, LoadAttempts = 6, SaveAttempts = 4, LockStaleSeconds = 1800, BindToCloseSeconds = 25,
	ReceiptKeep = 60, StateFlush = 0.2, FullStateEvery = 20, LiveStore = "AT_Live_v1", StatsStore = "AT_Stats_v1", ModStore = "AT_Mod_v1",
	MarketStore = "AT_Market_v1", Shards = 8, BoardPrefix = "AT_LB_", BoardWriteSeconds = 300, StatsFlushSeconds = 600, PingAttrEvery = 2 }
Config.Studio = { NoSave = true, SelfTest = true, LocalMarket = true, BellZoneMinPlayers = 1 }
Config.Debug = { LogRejects = false, ForceRestricted = false, ShowTriggers = false }
Config.Server = { MaxPlayers = 10, Plots = 10, MaxMoney = 9e15 }
Config.Colors = { --[[ UI.Theme-Spiegel für Server-SurfaceGuis: Bg, Surface, Surface2, Border, Text, Text2, Muted, Accent, Up, Down, Warn, Gold, Sectors = {T, E, M, K, G, F} ]] }
Config.Notifications = { Enabled = false, MaxPerDay = 1, PromptAfterStep = 17 }
Config.LiveFields = { --[[ Pfad -> {min, max}: "Market.NewsMeanGap", "Events.Rotation", "Shop.Disabled.<Key>", "Events.BoostPause" … ]] }
-- Kinder (dynamisch): Security Client Quality Market Companies News Trading Tower City Vehicles Decor Lifestyle Progression Season Rewards Shop Events
```
### C14.2 Kinder (Besitzer, Pflichtschlüssel)
```lua
-- Security (WP1): MoveHz = 5, BaseAllowedSpeed = 32, SpeedTolerance = 1.15, TeleportGrace = 1.0, Weights = { Honeypot = 100, Type = 5,
--   Rate = 1, RateBurst = 15, Speed = 2, Teleport = 8, Fly = 5, Car = 4 }, DecayEvery = 30, Review = 25, Kick = 60,
--   Rates = { Request = { 8, 1 }, Admin = { 12, 1 } }, ReportLimit = { 3, 600 }, BanPresets = { ["1h"] = 3600, ["1d"] = 86400,
--   ["7d"] = 604800, ["30d"] = 2592000, perm = -1 }, AnnounceMax = 200, AnnounceSeconds = 8, AccountAgeMin = 3, SessionMinForSocial = 600
-- Client (WP2): Keys = { Interact = {"E"}, Terminal = {"T"}, Tower = {"B"}, Shop = {"N"}, Quests = {"J"}, Menu = {"M"}, Sprint = {"LeftShift"},
--   Boost = {"LeftShift"}, Handbrake = {"Space"}, React = {"R"}, ChartTf = {"One".."Seven"}, AdminPanel = {"P"}, Fly = {"G"},
--   Spectate = {"X"}, Debug = {"F8"}, PhotoMode = {"F7"} }, Gamepad = {…}, DefaultSettings = { Lang = "auto", Sfx = 1, Music = 0.5,
--   Ui = 0.8, Quality = "auto", ReducedFx = false, ChartType = "Candles", ChartTf = "1m", Indicators = {}, NumberStyle = "short",
--   Colorblind = false, Shake = 1, ShowNet = false, TickerBar = true, NewsCards = "Normal" (Normal/Quiet/Off), AutoTransfer = true,
--   LeftHanded = false, ButtonScale = 1 }, SettingsSchema = {…}, Sounds = { UIClick = 0, …, Engine = 0, Music = 0 } (0 = Rezept),
--   TouchButtonMin = 64, AutoReducedFx = { Fps = 35, Seconds = 5 }, HighlightCap = 31
-- Quality (WP2): Tiers = { Low = { Lights = 6, Shadows = false, Traffic = 0, Drones = 0, Monitors = 2, Candles = 60, Particles = 0.3,
--   InteriorRadius = 0, AreaFill = false, DoF = false }, Medium = {16, true, 10, 4, 4, 90, 0.6, 1}, High = {32, true, 20, 8, 8, 120, 1, 2,
--   AreaFill = true, DoF = true}, Ultra = {64, true, 32, 14, 12, 120, 1, 4, true, true} }, AutoFpsDown = 35, AutoFpsUp = 55
-- Market (WP3): alle Stellschrauben MARKET §5–§13 (EPOCH-Verweis auf Clock, DayTicks 1200, Delay 8, Tau 45, NewsMeanGap 1500,
--   Bands, Classes {Sigma, SpreadBps, NewsFactor, Sigma1s, VolBase}, Macro-Matrix, CrashRate 1/12600, Weekly {CrashFriday, RallyWednesday,
--   AutoShow, Ipo}, Halts, Analysts (8 Namen + Genauigkeit), Rings, Backfill, Buckets, IpoPipeline {Season = {…}}, StudioSalt)
-- Companies (WP3): 36 Firmen §B6.2 + 7 ETFs + ACAD (250) als Types.Instrument; Sectors {Key, Name, Color}; Baskets
-- News (WP3): Vorlagen-Schlüssel je Art (news.*) mit Parametern
-- Trading (WP4): Transfer = { Threshold = 1.02, DayCapPct = 0.06 }, Refill = { Below = 0.5, To = 0.5 }, Protect = { Sl = 0.08, Tp = 0.15 },
--   Chips = { 0.10, 0.25, "Max" }, ConfirmAbove = 0.20, MinFeeCents = 100, OrderLife = { DAY = true, H24 = 86400 }, SeqWindow = 32,
--   FatFinger = 0.5, MinTradePct = 0.02, MinHoldSeconds = 60, Bots = { Sparplan = {…}, Trend = {…}, Dividend = {…}, Dip = {…} },
--   BotTotalPct = 0.30, BotWageBps = 2, BotDayStop = -0.05, OfflineBotHours = 12, OfflineOrderHours = 24, Tutorial = { Start = 10000,
--   Jump = 0.15, Ramp = 45, AutoSellAfter = 90, AutoSellAt = 0.12 }, LossStreakWarn = { Trades = 10, Seconds = 120 }
-- Tower (WP6): I0 = 4, IR = 1.30, C2 = 1000, Bands = { {3, 12, 1.50}, {13, 25, 1.56}, {26, 40, 1.58}, {41, 50, 1.60} }, Salary = 3,
--   Floors = 50, FloorHeight = 12, Stages = §B4.2, Rooms = §B4.3, Staff = §B4.4, LevelFactor = {1, 1.25, 1.5, 1.8, 2.2},
--   LevelCost = {1, 2.5, 6, 15}, RoomChangePct = 0.25, Efficiency = { Step = 0.10, Base = 10000, Ratio = 3, Max = 20 },
--   VaultMinutes = 20, VaultFloorBonus = 0.5, Offline = { Rate = 0.5, RateMax = 0.9, CapHours = 8, CapMax = 24, MinAway = 60 },
--   Build = { Instant = 9, BaseSeconds = 20, Ratio = 1.33, Cap = 5400, MinFactor = 0.25, HelpPct = 0.10, HelpMax = 3 },
--   Mult = { IpoStep = 0.25, IpoMax = 20, FriendStep = 0.10, FriendMax = 4, RespektStep = 0.01, RespektMax = 20, TimedCap = 10,
--   EventMax = 3, Bull = 1.5, Parade = 1.5, BellMoment = 1.2 }, Names = { Adj = {…40 {de,en}}, Noun = {…40} }, Skins = {…7},
--   Neon = {…6}, Crowns = {…5}, PrivateMax = 5, CollectRange = 70, Assets = { Crane = AssetSlot, Lobby = AssetSlot, … }
-- City (WP7): Look (Licht-Werte §A4), Zones (§A5 Koordinaten/Maße), Plots = { Radius = 420, Size = 110, StartAngle = 18 },
--   Routes, Billboards, Shops = { [instId] = AnchorName }, PartBudget = 12000, BuildPerFrame = 400, Assets = { Blimp, Fountain, … }
-- Vehicles (WP7): Cars = §B12.1 { Key, Name, Class, Price, Source, Recipe, Asset = AssetSlot, SoundId = 0 }, Classes = { Kompakt = 60,
--   Limousine = 75, Sport = 95, Super = 120, Hyper = 150 }, Boost = { Mult = 1.25, Seconds = 3, Cooldown = 8 }, DriftFriction = 0.3,
--   GarageBase = 6, Paints = {…24}, Rims = {…8}, Glow = {…6}, DespawnSeconds = 60, ShareholderDiscount = { I = 15, Min = 50, Pct = 0.10 }
-- Decor (WP8): 68 Teile { Key, Code, Name, Set, Price, Comfort, Recipe, Asset = AssetSlot }, SlotsPerFloor = 3, PenthouseSlots = 8,
--   ComfortPct = 0.005, ComfortMax = 0.10
-- Lifestyle (WP8): Watches (15), Accessories (8), Jetpack = { Fuel = 8, Recharge = 12, MaxHeight = 120 }, je mit Asset/ImageId
-- Progression (WP9): Licences = §B9.2 (Types.Licence), XpSources = §B9.1, LevelCurve = 12.5, KnowHow = §B9.3, Ruf = §B9.4,
--   Titles = §B9.5, Prestige = { MinFloor = 25, StarsK = 4, StarsDiv = 1e6, Perks = §B9.6 }, TickerBlock = {…}, Academy = { Lessons = 16 × {Id, Title, Cards, Quiz} },
--   Exams = {…}, QuestKinds = §B9.7, Quests = { DailyPool = 30, WeeklyPool = 12, Starter = 20 }, Achievements = 60, Badges = 15 (Id = 0),
--   Album = { SectorBonus = 0.02 }
-- Season (WP9): Seasons = { { Id = 1, Name = {de = "Neon-Skyline", en = "Neon Skyline"}, StartUtc, EndUtc, Tiers = 50, TierXp = 1000,
--   Free = {…25}, Premium = {…50} } }, XpSources = §B9.9
-- Rewards (WP9): Login = §B9.9, Codes = { LAUNCH = { Grant = { Credits = 5000 }, Expires = "2027-01-31T00:00:00Z" } }, WinBack = {14, 60}
-- Shop (WP10): GamePasses = §B14.1 { Key, Id = 0, Price, Name, Desc }, Products = §B14.2 { Key, Id = 0, Price, Grant/Kind, Once?, PerSeason?,
--   Random = false }, Subscription = { Id = "", Price = 449 }, ForbiddenRobuxFields = §B14.5, RandomItemsEnabled = false,
--   QuoteSeconds = 600, MaxOffersPerSession = 1, OfferMinMinutes = 15, BoutiqueHours = 4, BoutiqueSlots = 6, Disabled = {}
-- Events (WP11): Rotation = { "Truck", "Drones", "BuildBoom", "Press" }, Truck = { Bundles = 30, IncomeSeconds = 20, Seconds = 120 },
--   Drones = { Packages = 8, IncomeSeconds = 60 }, BuildBoom = { Pct = 0.25, Seconds = 300 }, Press = { LeadMinutes = 13, QuizXp = 50 },
--   BellMoment = { MinPlayers = 3, Mult = 1.2, Seconds = 300 }, SkyShow = { RespektMult = 2, Seconds = 600 }, Bear = { OrbsPerPlayer = 8,
--   GoalPerPlayer = 25, RewardMinutes = 10 }, Weekly = §B10.4 { {Dow, HH, MM, Kind, Args} } (Berlin-Zeit), AdminLimits = §B15.3,
--   MaxGlobalSeconds = 3600, PickupRange = 12, RainCoinsMax = 30, RainCoinMinutes = 2
```
### C14.3 Hybrid-Asset-Plätze (Wunsch 17)
Jeder Eintrag mit Upgrade-Potenzial hat genau eines der Felder: `Asset = { MeshId = 0, TextureId = 0, Scale = 1, Offset = CFrame.identity }`
(Autos, Uhren, Deko, Accessoires, Kran, Lobby-Deko, Kronen, Bulle, Bär, Luftschiff, Brunnen, Jet/Yacht/Heli-Platzhalter),
`ImageId = 0` (Firmen-Logos, UI-Icons, Ladebildschirm-Hintergrund, Lizenzkarten) oder `SoundId = 0` (alle Sfx-Rollen, Musik).
Ablauf: `AssetSlot.PreloadServer` (WP1) lädt beim Start alle Mesh-Plätze ≠ 0 per `AssetService:CreateMeshPartAsync` (pcall) als
Vorlagen nach `ReplicatedStorage.AssetCache/<Key>`; Bauer (Server und Client) rufen `AssetSlot.Mesh(key, slot, rezept)` – Vorlage
vorhanden → Klon (skaliert mit `Scale`, versetzt mit `Offset`), sonst Rezept. Bilder/Sounds: `ContentProvider:PreloadAsync` mit
Status-Callback; `Failure` → Code-Grafik bzw. Sfx-Rezept. Assets müssen dem Spiel-Ersteller gehören (ANLEITUNG). Liste aller
Plätze mit Config-Pfad, Format, Größe, Higgsfield-Prompt-Idee: `docs/ASSET-LISTE.md` (WP12). SelfTest: jeder Platz hat Typ-korrekte
Nullwerte; Bau mit `MeshId = 0` liefert das Rezept.

## C15. Sprachen (`Lang`, WP1 + Domänen-Dateien)
- `Lang/init.FILES` = `Core core.` · `Ui ui.` · `Market mkt.` · `News news.` · `Trade trade.` · `Terminal term.` · `Tower tower.` ·
  `TowerUi tui.` · `World world.` · `Vehicle car.` · `Life life.` · `Progress prog.` · `Tutorial tut.` · `Social soc.` ·
  `Shop shop.`/`item.` · `Admin admin.` · `Events evt.`. Gleiche Liste als `LANG_PREFIX` in `contract_check.py`.
- Jede Datei `{ de = {[key] = text}, en = {[key] = text} }`; Präfix-Pflicht; doppelte Schlüssel → warn. `Lang.T` = `string.format`
  in pcall; fehlend → Englisch → Schlüssel. Sprache: Einstellung `de`/`en`, sonst `LocaleId` beginnt mit `de` → de, sonst en.
- Server lokalisiert Notify/Ansagen pro Empfänger; Config-Namen sind `{de, en}`-Paare (`Lang.Pick`); News kommen als Schlüssel +
  Parameter, der **Client** lokalisiert (MARKET §6.2). SelfTest `Lang.Missing()` leer.
- Pflichtschlüssel (Auszug; jedes WP ergänzt): `core.gameName`, `core.disclaimer` (§A2), `core.loading`, `core.error`, `core.noAnswer`,
  `core.studioNoSave`, `core.localMarket` („Lokaler Testmarkt“), `trade.readingBar` („Händler lesen …“/„Traders are reading …“),
  `trade.confirmSpread` („Sicher? Verteilen ist klüger.“/„Sure? Spreading out is smarter.“), `trade.transferAvail`
  („Verfügbar %s → %s (Bau-Kurs %s)“), `trade.transferLocked`, `trade.refill`, `tower.vaultFull` („Tresor voll – einsammeln!“),
  `tower.maxMoney` („Tresor am Limit – Zeit für den Börsengang!“), `shop.notSetUp` („Bald verfügbar“/„Not set up yet“),
  `shop.together4` („x2 + x3 zusammen = x4“), `shop.restricted`, `shop.giftBlocked`, `evt.adminWindow` („ADMIN-ABUSE aktiv – zählt
  nicht für die Liga“), `admin.denied`, `tut.*` (alle Tiko-Sätze ≤ 12 Wörter).
- Zahlen: `Format` mit Sprach-Trennzeichen (DE `1.234,56`, EN `1,234.56`); Kürzel DE Tsd./Mio./Mrd./Bio./Brd., EN K/M/B/T/Qa.

## C16. Performance-Budgets
| Bereich | Budget |
|---|---|
| Server-Script | Scheduler `_Total` Ø ≤ 3 ms bei 10 Spielern (Markt-Tick < 0,3 ms, TowerIncome < 0,1 ms, Bots < 0,3 ms, AntiCheat < 0,5 ms, Rest ≤ 1,5 ms) |
| Takte | Markt 1 Hz (≤ 10 Nachhol-Ticks, Sprung bei > 60 s Stillstand) · TowerIncome 1 Hz (ein Batch) · Bots 1/min auf 1m-Schluss · StateFlush 5 Hz · AutoSave 90 s gestaffelt · Bestenlisten 300 s · Bus-Poll 0,2 Hz · Events 1 Hz (Geldregen 4 Hz aktiv) · AntiCheat 5 Hz gestaffelt · Hüllen-Bau ≤ 6 Etagen/Frame · Backfill ≤ 2 ms/Frame (~10 s) · Offline-Abgleich im Hintergrund (meist < 50 ms, max. ≈ 0,4 s verteilt) |
| Teile Server | Stadt ≤ 12.000 · Tower ≤ 4.600 · Rest ≤ 400 · gesamt ≤ 17.000 |
| Client (Handy Low/Medium) | ≥ 30 FPS; Lua ≤ 3 ms/Frame; sichtbare Teile ≤ 8.000 (Streaming); GuiObjects ≤ 2.500; Terminal-Chart < 0,3 ms/Frame (≤ 900 Objekte); CityLife < 0,5 ms; TowerView < 0,3 ms (Aufbau ≤ 1,5 ms/Frame); Speicher ≤ 900 MB (Low) |
| PC High/Ultra | 60 FPS; Lichter ≤ 32/64 |
| Netzwerk | MarketFrame 0,44 KB/s je Spieler; State 0,1–0,3 KB/s; Markt-News ≈ 0,05 KB/s; gesamt < 1 KB/s je Spieler; Historie ≤ 120 × 10 B + 8 B je Anfrage, gecacht; Crash-Spitze 10 × 3 Charts ≈ 40 KB |
| Grenzen | Orders ≤ 50/Spieler, Alarme ≤ 18, Fills-Ring 100, Belege 60, Bus-Dedupe 200, Pickup-Token ≤ 60/Spieler, Highlights ≤ 31, Namens-Cache Bestenliste 200 |
DebugOverlay (F8, Admin): Markt-Tick-ms, Frames/s, Teilezahl, Live-Monitore, Scheduler-Top-5, Speicher, Ping.

## C17. Studio-Solo, „Test → 2 Players“, SelfTest
- **Solo:** Markt mit Fallback-Seed (`hash4(StudioSalt, w, 0, 0)`), Banner „Lokaler Testmarkt“ im Admin-Dashboard; Bus lokal;
  NoSave-Toast nach 2 s; komplettes FTUE §B2; Welt-Events (Glocken-Moment ab 1 Spieler); Admin-Knopf; Käufe mit `Id = 0` → „Bald
  verfügbar“, Admin-Debug „Kauf simulieren“ läuft durch denselben Grant-Pfad; „Policy simulieren“ testet Geschenk-Gate.
- **Test → 2 Players:** Player1 (−1) Admin, Player2 (−2) nicht (Ablehnung 1× geloggt); beide sehen **identische** Kurse; Plots 1 und 2
  nebeneinander; Besuch, Respekt (AccountAge-Prüfung in Studio übersprungen, `Config.Studio`), Bau-Hilfe, Pickups pro Spieler,
  Admin-Abuse lokal + Fallback; Autos kollidieren nicht mit Figuren.
- **SelfTestService** (Studio, `Config.Studio.SelfTest`, 3 s nach Start, `[SelfTest] n/n PASS`): Pflicht-Tests je WP in Abschnitt D,
  mindestens: `Config.Validate()` leer · `Lang.Missing()` leer · DEFAULT_DATA sanitize · Net/QuoteCodec-Rundreisen + falsche Länge → nil ·
  Frame ≤ 900 B · Determinismus (zwei PriceEngine-Instanzen, 10.000 Ticks, Random-Access == sequentiell) · Noise-Vektoren MARKET §19.2 ·
  Depot-Invarianten (Kauf+Sofortverkauf ≤ 0, Cash ≥ 0, OCO storniert, Reservierungen 0 nach Storno) · Offline-Abgleich == Online ·
  Gewinn-Transfer-Regeln (Schwelle, Tageslimit, 1× je Börsentag, Starthilfe nicht abhebbar) · Firewall · NoPaidRandom · jede Quest-Art
  hat Tracker · Beleg-Idempotenz (SimulatePurchase doppelt + gleichzeitig) · TowerMath == Tabelle §B5.1 · alle Preise < 1e14 ganzzahlig ·
  Multiplikator-Deckel ×10 · Wortliste · Player2-Admin-Ablehnung · Kollisionsgruppen-Matrix.
- **Luau-CLI-Tests** (`tests/*.test.luau`, ohne Roblox-Typen) laut C2-Liste.

## C18. Wiederverwendung aus CLUTCH CLASH (Detail: `docs/REUSE.md` §1–§7; dort gilt jeder Runde-2-Fix)
| Urteil | Dateien | Paket |
|---|---|---|
| **COPY** (umbenennen `CLUTCH CLASH`→`AKYTEX TYCOON`, `CC_`→`AT_`) | `rbx.yml`, `selene.toml`, `stylua.toml`, `.gitignore` (liegen schon), `Shared/Util`, `Shared/Spring`, `Lang/init` (nur FILES), `Lib/Scheduler`, `Services/Remotes`, `MetricsService`, `SelfTestService`, `DataService` (+ DEFAULT_DATA, SavedAt), `PlayerStateService` (Leaderstats), `Main.server` (order) | WP1 |
| COPY | Client `UI` (+ neue Teile §C7.5), `Hooks`, `Highlights`, `PhotoMode`, `Sfx`-Engine (neue Rollen) | WP2 |
| COPY | `Fly` | WP11 |
| ADAPT | `Net` (neue RemoteList, Look/FX-Codecs weg), `Types`, `Config/init` (+ Kinder), `Config/Security`, `scripts/check.sh`, `scripts/contract_check.py` (LANG_PREFIX, + FIREWALL, DEPOT_WRITE, BANNED_WORDS) | WP1 |
| ADAPT | `Main.client`, `Controls`, `Hud`, `Settings`, `Effects` (+ Register), `Config/Client`; PATTERN `TouchControls` | WP2 |
| ADAPT | `MonetizationService` (Kern 1:1: ProcessReceiptWith, prepare/grant, LoadPasses, Policy fail-closed, SimulatePurchase, TryOffer; neu BuildGrant, PassFactor, Quote, TradingAllowed); PATTERN `ShopService` (Grant/Spend-Regeln, withBusy, Core-Funktionen) | WP10 |
| ADAPT | `AdminService` (Owner-Regel + Gruppen-Pfad, Bann, Ansage, publishGlobal/handleGlobal, Debug-Aktionen; Shooter-Teile raus; Markt-Aktionen über `MarketService.Admin`), `AntiCheatService` (schlank, ohne Schuss-Statistik), `AdminPanel` (Rahmen, neue Tabs), `AdminTools` (nur Noclip/Speed/ESP), `DebugOverlay` | WP11 |
| ADAPT | `LeaderboardService` (Boards §B11.1, Integer-Kodierung, SurfaceGui-Builder), PATTERN `RewardService` (ohne Glücksrad), `CommunityService` (Announce, Freunde) | WP9 |
| PATTERN | `GraphicsService` (clearOld eigener Instanzen) | WP7 |
| **DROP** | alles Kampf/Match/Bots/Arena, `Odds.luau`, Kisten, `CrateReveal`, Glücksrad, Pity, Waffen-/Kosmetik-Modelle | – |

## C19. Änderungen an `docs/MARKET.md` (verbindlich; Kopfvermerk in MARKET.md)
| # | MARKET.md | Jetzt | Grund |
|---|---|---|---|
| 1 | §4.2 ID 1 NOVA „NOVA Intelligence“, ID 2 AKYX „AKYTEX Holding“, ID 23 PFTG „Pfotenglück“ | CGVO „Cognivo KI“ (Normal, 240), KRWK „Kernwerk Systems“ (Stabil, 180, Div. 0,4), PFFR „Pfotenfreund“ | Marke/echte Beteiligungspläne, NOVA ist eigene echte Marke, Wortliste „Glück“ |
| 2 | §14 „NOVA-Ampel“, NOVA-Tipps | **Tiko-Ampel**, Tiko (geskripteter Roboter) | „Aky“/„NOVA“ sind echte KI-Produkte |
| 3 | §15 „Depot ↔ Bau-Kasse frei“ | **nur AKY → CR** über Gewinn-Transfer (Basis-Hochwassermarke, Schwelle 2 %, Tageslimit 6 %, 1× je Börsentag, Lizenz-Bau-Kurs) | Robux-Firewall |
| 4 | §15 Research durch Tower-Fortschritt | über Lizenz + Know-how | Tower ist Robux-beschleunigbar |
| 5 | §14.4 „Gehalt aus dem Tower“ ins Depot | Rettungsschirm (auf 50 % der Basis, 1×/UTC-Tag, nie abhebbar); Turm-Gehalt bleibt CR | Firewall + Freie-Option-Gate |
| 6 | §1.4 „Robux erlaubt: mehr Watchlists/Alarm-Plätze/2×2“ | nur Know-how; Robux nur Terminal-Themes/Skins | Robux kauft keine Trading-Werkzeuge |
| 7 | §12.6 Liga-Rang nach TWR | Rang nach Skill-Score, Tie-Break Ø-Tagesrendite; absolute Stufen Bronze/Silber/Gold/Diamant | TWR über viele 20-min-Tage belohnt Masse statt Können |
| 8 | §16 Tower-AG (Kurs aus Tower-Kennzahlen) | v2 **Trader-AG** (Kurs = TWR-Index der Handelsrendite), System als Gegenpartei | Tower-Werte sind Robux-beeinflusst |
| 9 | §10.1 `MarketNews`, Aktionen `Market.Place` usw. | Remote `Market` (Art `News` …), Aktionen ohne Punkt: `TradePlace`, `MktCandles` … (§C9) | Vertrags-Prüfer erkennt nur Buchstaben-Namen |
| 10 | §5.6/§8.2 Speicher `AKX_Market_v1`, `AKX_Events_W<w>`, Thema `AKX_EV` | `AT_Market_v1`, `AT_Bus_W<w>`, `AT_EV` | einheitliches Präfix |
| 11 | §6.5 IPO mit Zeichnung, §12.4 Leerverkauf | v1: IPO-Erstnotiz ohne Zeichnung; Zeichnung pro rata + Leerverkauf **v1.1** (IDs/Felder reserviert) | Fehlerrisiko v1 |
| 12 | §12.1 `Pos = {[instId] = …}` | String-Schlüssel `tostring(instId)` | DataStore/JSON |
| 13 | §11.2 Betrags-Chips 10/25/50 % | 10 % · 25 % · Max (= Klumpen-Grenze) | 50 % > Azubi-Grenze 30 %, keine All-in-Optik |
| 14 | §14.1 News-Karte mit Countdown | Balken „Händler lesen …“, kein Kauf-Knopf auf der Karte, Drosselung §B7.4 | keine Wett-Countdown-Optik |

---

# D) Arbeitspakete (11 Coding-Pakete + 1 Doku-Paket, parallel)

## D0. Regeln für alle Pakete
1. **Nur eigene Dateien** (C2) anlegen/ändern. Fremde Shared-Dateien nur lesen/`require`n. Fehlt etwas im Vertrag → defensiv
   programmieren (nil-Checks, pcall) und im Abschlussbericht melden; Verträge (C4–C10, C14, C15) **nicht** eigenmächtig ändern.
2. Server-Services nie gegenseitig `require`n – nur `Services.X` zur Laufzeit; Client-Module nur über `ctx.Modules.X` (nil-sicher)
   und `ctx.Hooks`. Effekte nur über `Effects.Register` des eigenen Moduls (§C7.4).
3. Qualitäts-Gates je Paket: `stylua --check`, `selene`, luau-lsp (C1.3-Regel), `rojo build` fehlerfrei, eigene Tests grün,
   `python3 scripts/contract_check.py .` ohne ERROR in eigenen Dateien. Datei-Kopf: deutscher Banner (Zweck, Besitzer-WP, öffentliche API).
4. CC-Teile laut `docs/REUSE.md` kopieren/anpassen inkl. aller Runde-2-Fixes (REUSE §7); **nichts** in `roblox-shooter`,
   `roblox-meteor-heist` oder der Website ändern.
5. Nur Assets aus `ASSETS.md`; jedes sichtbare Upgrade-Objekt bekommt seinen Asset-Platz (§C14.3). Keine veralteten APIs, keine
   `while`-Schleife pro Spieler, Takte über `Lib/Scheduler`, keine Spielertexte außerhalb von Lang/Config.
6. **Abhängigkeits-Reihenfolge der Lieferung:** WP1 und WP2 liefern zuerst ihre Verträge als lauffähige Stubs (Types, Net, Config/init,
   Lang/init, Clock, Format, AssetSlot, UI-Kit-Neuteile, Hooks, Effects.Register) – spätestens nach 25 % der Runde; alle anderen
   programmieren gegen die Signaturen in Abschnitt C.
7. **Integration** (nach allen WPs, Lead): `scripts/check.sh` komplett, Studio-SelfTest Solo + „2 Players“, TESTPLAN, `AkytexTycoon.rbxlx`
   bauen; Fehler in fremden Dateien gehen ans Besitzer-WP zurück. Danach Besitzer-Wunsch 7: eigene „Detail- & Grafik-Runde“.

---

## WP1 – Kern & Plattform (Server/Shared, Tooling)
- **Dateien:** `default.project.json`, `rbx.yml`, `selene.toml`, `stylua.toml`, `.gitignore`, `scripts/check.sh`, `scripts/contract_check.py`,
  `src/shared/{Types,Util,Spring,Net,Format,Clock,AssetSlot}.luau`, `src/shared/Config/{init,Security}.luau`, `src/shared/Lang/{init,Core}.luau`,
  `src/server/Main.server.luau`, `src/server/Lib/Scheduler.luau`, `src/server/Services/{Remotes,DataService,PlayerStateService,MetricsService,SelfTestService}.luau`,
  `src/server/Tests/CoreTests.luau`, `tests/{util,format,clock}.test.luau`.
- **Liefert:** C1, C2 (Gerüst), C3, C4, C5.1, C5.2, C6.1, C8 (RemoteList), C11.4-Prüferregeln, C12, C13 (Store-Namen), C14.1, C15 (Kern).
- **Braucht:** `MonetizationService.LoadPasses/RandomAllowed` (pcall, Ready-Gate) · `Config.Client.DefaultSettings/SettingsSchema` (WP2) ·
  `Child.Validate(Config)` aller Kinder.
- **Aufgaben:**
  - Projektdatei exakt C1.2; `check.sh` laut C1.1; `contract_check.py`: Docstring „AKYTEX Tycoon“, `LANG_PREFIX` §C15, neue Abschnitte
    9 `FIREWALL` (§C11.4 Punkt 2), 10 `DEPOT_WRITE` (Punkt 3), 11 `BANNED_WORDS` (§0.7, Wortgrenzen, Allowlist-Phrasen, Scan Lang-Werte +
    Config `Name/Desc/Title`), 12 `EFFECTS` (Effekt-Namen in `Effect(`/`EffectAll(`-Aufrufen ∈ §C7.4), 13 `STATE_KEYS` (Provide-Schlüssel ∈ §C10).
  - `Main.server` = CC-Lader mit `order` §C3, Präfix `[AKYTEX Tycoon] `.
  - `Config/init` §C14.1 + Laden der 17 Kinder + `Validate` (prüft u. a. `MaxMoney`, Ganzzahligkeit) + `ApplyLive` (nur `LiveFields`, geklemmt).
  - `Lang/init` (CC, FILES §C15), `Lang/Core` (core.* inkl. Disclaimer DE/EN wörtlich §A2).
  - `Util`/`Spring` CC 1:1; `Format`, `Clock` (inkl. `BerlinOffset` EU-Regel, `NextBerlin`), `AssetSlot` (§C6.1, §C14.3).
  - `Net`: RemoteList §C8 + `GetRemotes`; keine Look/FX-Codecs.
  - `DataService`: CC 1:1 + DEFAULT_DATA §C12.1 + `Migrate` §C12.2 + `SavedAt` im finalen Save + `LastSavedAt`; Studio NoSave für
    `UserId ≤ 0`; String-Schlüssel-Sanitize auch in Listen.
  - `PlayerStateService`: CC 1:1; Leaderstats `Vermögen` (StringValue) + `Etagen` (IntValue); Handle mit `Bucket`-Option (Token-Bucket);
    eigene Handler GetFull/SaveSettings/TutorialFlag; State-Keys Settings/Flags/Server.
  - `Remotes.luau` (Honeypot nur erzeugen; Handler macht WP11), `MetricsService`/`SelfTestService` CC 1:1.
- **Abnahme:** (1) `rojo build` enthält alle Properties aus C1.2 (grep) oder nicht baubare sind gemeldet. (2) Studio-Solo: Join → Toast
  „Studio: Fortschritt wird nicht gespeichert“, 10 min Join/Leave ohne Output-Fehler. (3) `Request("Unbekannt")` → `{Ok=false}`.
  (4) State ≤ 5×/s, voll alle 20 s. (5) `contract_check.py` meldet absichtlich eingebaute Verstöße (Testdateien im Scratchpad) in allen
  5 neuen Regeln korrekt. (6) `Clock.BerlinOffset` korrekt für 2026-03-29 00:59/01:00 UTC und 2026-10-25 00:59/01:00 UTC. (7) `[SelfTest]`
  Core-Tests PASS, BindToClose ohne Fehler.
- **Tests:** `util.test` (CC-Fälle FormatNumber bis 1e33, WeightedPick 0/NaN, Limiter mit künstlicher Uhr, `IsoWeek(2026-10-13) = 202642`);
  `format.test` (DE/EN-Trennzeichen, Kürzel bis Brd./Qa, „MAX“ ab 9e15, Prozent mit Vorzeichen); `clock.test` (EPOCH, DayIndex/Minute,
  Sommerzeit-Grenzen, NextBerlin über Wochen-/Jahresgrenze); `CoreTests` (Config.Validate leer, Lang.Missing leer, DEFAULT_DATA sanitize,
  Scheduler, Net-Liste vollständig, AssetSlot mit 0 → Rezept).

## WP2 – Client-Plattform & UI-Kit
- **Dateien:** `src/first/Loading.client.luau`, `src/client/Main.client.luau`, `src/client/Modules/{UI,Hooks,Controls,TouchControls,Hud,Settings,Sfx,Effects,Highlights,Quality,PhotoMode}.luau`,
  `src/shared/Config/{Client,Quality}.luau`, `src/shared/Lang/Ui.luau`.
- **Liefert:** C7.1–C7.4, C7.5 (WP2-Teil), Ladebildschirm §A4, HUD (Stats-Karte oben links: CR-Zähler, AKY-Depotwert-Chip, Vermögen;
  Multiplikator-Chip mit Aufschlüsselungs-Sheet aus `State.Income.Parts`; Tresor-Ring; Pillen oben Mitte; großer TRADE-Knopf unten Mitte;
  rechte Knöpfe Tower/Shop/Quests/Akademie/Garage/Social/Bestenlisten/Einstellungen/Admin 99; Ticker-Leiste oben (Einstellung);
  FPS/Ping), Einstellungen-Fenster mit Info-Seite (Disclaimer, Regeln, Einspruch), Grafikstufen, Sfx-Rollen §A4.
- **Braucht:** WP1 (Types, Net, Lang, Config, Format, Clock) · State-Keys §C10 · Remotes §C8 · Module anderer WPs nur über `ctx.Modules`.
- **Aufgaben:**
  - `Main.client`: CC-Struktur (ScreenGui `AkytexTycoonUI` mit UIScale, TouchGui `AkytexTycoonTouch` unskaliert, ScreenInsets DeviceSafeInsets);
    Init/Start-Reihenfolge §C7.1 (fehlgeschlagene Module entfernen); Remotes erst danach verbinden; State-Sticky-Merge mit
    changed-Liste; `Market`/`World`/`Replay`-Remotes → Hooks §C7.2; `Effect` → `Effects.Play` + Hook; Admin-Module bei `IsAdmin`; ein
    PreRender-Loop + 1-s-Tick; GetFull nach 5 s; CoreGui Backpack/Health aus (mit Wiederholung).
  - `UI`: CC-Kit 1:1 + neue Teile §C7.5 (Segmented, Sheet, PriceTag, Sparkline, Ticker, Chip/StatTile/RowCard/RowActions/Slider/Cycler/NavItem
    aus CC AdminPanel gehoben, `UI.Faces` BuilderExtended/BuilderMono/BuilderSans mit Fallback-Prüfung von „ÄÖÜß Λ“), Blur-Name
    `AkytexTycoonWindowBlur`, `SetToastTop` unter die Ticker-Leiste.
  - `Controls`/`TouchControls`/`Settings`/`Sfx`/`Effects`/`Highlights`/`PhotoMode`: CC-Muster mit neuen Aktionen, Kontexten (§C7.5), Sfx-Rollen,
    Effekt-Registry (`Register/Play`, Kern-Effekte §C7.4), Fotomodus für alle (Langdruck beendet auf Touch).
  - `Quality`: Auto-Stufe aus FPS (runter < 35 FPS 5 s, rauf > 55 FPS 30 s), manuell überschreibbar, `Budget(key)` aus `Config.Quality`,
    Hook `Quality`, ReducedFx automatisch.
  - `Loading` (ReplicatedFirst): Logo-Splash §A4, Disclaimer, `ContentProvider` nur für eigene UI, endet bei `game.Loaded` + Remotes da (max. 12 s).
- **Abnahme:** (1) Kein Modul-Fehler bricht den Start (Test: ein Modul wirft in Init → andere laufen). (2) Fenster öffnen 0,26 s Quint +
  8 px, immer nur eines. (3) Touch-Knöpfe ≥ 64 px, Linkshänder-Spiegel. (4) Multiplikator-Sheet zeigt jede Quelle mit Herkunft und Restzeit.
  (5) Ladebildschirm ≤ 4 s bei geladenem Spiel, überspringbar. (6) Grafikstufe wechselt nach 5 s < 35 FPS (Simulator).
- **Tests:** Studio Gerätesimulator (iPhone SE, Android Mittelklasse, 1080p PC, Gamepad); UI-Kit-Beispielfenster (Debug) für alle Varianten.

## WP3 – Markt-Engine (Server) & Kalibrierung
- **Dateien:** `src/server/Services/MarketService.luau`, `src/server/Market/{MarketClock,MarketSeed,Noise,PriceEngine,EventDirector,GlobalBus,CandleStore,QuoteStream,Dividends,MarketAudit,MarketAdmin}.luau`,
  `src/shared/Market/QuoteCodec.luau`, `src/shared/Config/{Market,Companies,News}.luau`, `src/shared/Lang/{Market,News}.luau`,
  `src/server/Tests/MarketTests.luau`, `tests/{noise,quotecodec}.test.luau`, `tools/market_calibrate.py`.
- **Liefert:** MARKET.md §3–§10, §13 (Markt-Teil), §17, §18 mit den Änderungen §C19; C5.3; C6.2 (QuoteCodec); §B6; Kalender; Wochen-Live-
  Events (Crash-Freitag, Rally-Mittwoch, Samstags-Show-Rally mit Absage, IPO-Erstnotiz) aus `Config.Market.Weekly` über `Clock.NextBerlin`.
- **Braucht:** WP1 · `AdminService.IsAdmin` (pcall, für `Admin`) · `OrderService` registriert sich über `MarketService.OnTick/OnDayClose`.
- **Aufgaben:**
  - Noise/Hash exakt MARKET §5.2 (16-Bit-Split, `--!native` erlaubt), PriceEngine §5.1/§5.3 inkl. Bewertungs-Bremse, ETFs, IPO-Instrumente.
  - MarketSeed §5.6 (Store `AT_Market_v1`, Fallback-Seed + `IsLocalMarket`), Wochenschluss.
  - EventDirector §6.6 (Tagesplan sequentiell gecacht, Fakt/Gerücht/„wie erwartet“, Sektor, Makro-Matrix, Quartalszahlen, Analysten
    mit gemessener Trefferquote, Dividenden-Ex-Tick, Crash/Rally mit Warnphase, Wochen-Events, IPO-Erstnotiz §B6.3), News erst bei `t_a`.
  - GlobalBus §8.2/§8.4 (`AT_Bus_W<w>`, Thema `AT_EV`, 5-s-Poll, 10 s Vorlauf, Verspätung → Original-Tick + 10-s-Halt), MarketAdmin §B15.3
    (Klemmen, 3-s-Abklingzeit, Admin-Fenster), `CancelAutoShow`.
  - CandleStore (Ringe, Backfill ≤ 2 ms/Frame), QuoteStream (ein `FireAllClients(buffer)` je Tick), `Market`-Remote-Nachrichten §C8,
    Request-Handler MktCandles/MktProfile/MktCalendar/MktNews, State-Key `Market`.
  - MarketAudit (Fill-Prüfung), `Stats`.
  - `market_calibrate.py`: Gate G5 (Strategie „Zufall + Gewinn-Transfer + Starthilfe“ mit Regeln §B8.2/§B8.4, Ausgabe Anteil vs. Tiko-Ampel)
    und G6; Firmen-Umbenennungen übernehmen.
- **Abnahme:** (1) Zwei Studio-Clients sehen identische Kurse; zwei PriceEngine-Instanzen gleich über 10.000 Ticks; Random-Access ==
  sequentiell. (2) Testvektoren MARKET §19.2 exakt. (3) Frame 439 B (43 Instr.), ≤ 900 B mit IPOs. (4) Markt-Tick < 0,3 ms in Studio
  (`Scheduler.Stats`). (5) News kommt nie vor `t_a` beim Client an. (6) Admin-Crash im Studio: Ankündigung, Rampe, Abklingen,
  Admin-Fenster; Bus-Ausfall (Messaging aus) → Poll holt nach. (7) G5 ≤ 15 % und G6 erfüllt (Ausgabe im Bericht).
- **Tests:** `noise.test` (Vektoren, mul32 gegen Referenz), `quotecodec.test` (Rundreisen, falsche Länge → nil, Klemmen statt Fehler),
  `MarketTests` (Determinismus, Kerzen-Aggregation 1m aus 1s == Ring, Dividenden-Ex-Tick, Gerüchte-Bestätigung, Wochenwechsel stetig,
  Berlin-Zeit-Events auf Tick genau, CancelAutoShow).

## WP4 – Orders, Depot, Bots (einziger Depot-Schreiber)
- **Dateien:** `src/server/Services/OrderService.luau`, `src/server/Market/{OrderEngine,Portfolio,BotEngine,CatchUp}.luau`,
  `src/shared/Market/{PortfolioMath,Indicators}.luau`, `src/shared/Config/Trading.luau`, `src/shared/Lang/Trade.luau`,
  `src/server/Tests/OrderTests.luau`, `tests/{portfoliomath,indicators}.test.luau`.
- **Liefert:** MARKET §11–§13 (Order-Teil), §B7.3, §B8 (Basis, Gewinn-Transfer-Regeln, Rettungsschirm, Bots, ACAD-Tutorial), Liga-Statistik
  (Skill-Score, Ø-Tagesrendite, Taint), C5.4, C6.2 (PortfolioMath, Indicators), State-Keys `Depot`, `League`.
- **Braucht:** `MarketService.Quote/Candle1s/PriceAt/NewCursor/HalfSpread/IsHalted/Dividends/OnTick/OnDayClose/FactNewsFor/AdminWindowActive/AdminWindowsBetween/Instrument`
  (WP3) · `ProgressionService.TradingPerks/LicenceDef/Licence` (WP9, pcall) · `AdminService.OwnerTradeBlocked` (WP11, pcall) ·
  `AntiCheatService.Add` (pcall) · QuoteCodec.EncodeReplay (WP3).
- **Aufgaben:**
  - Validierung §C9 `TradePlace` komplett (Seq-Fenster rückt bei Ablehnung vor), Ausführung zum zuletzt gesendeten Tick, Reservierungen,
    Trigger je 1s-Kerze mit Pfad-Regel, Laufzeiten, Themen-Körbe, Klumpen-/Positions-Grenzen, Gebühren laut Lizenz, Mindestgebühr 1 AKY.
  - Portfolio (Credit/Debit-Trichter mit Gründe-Whitelist, Buy/Sell exakt MARKET §12.3, NAV), `Withdraw/Withdrawable` §B8.2,
    `SetLicence`, `AdminCredit`, Rettungsschirm, Auto-Transfer-Signal `OnBell` (eigener Code schreibt **nie** CR).
  - CatchUp (Offline-Orders 24 h, Dividenden, Bots 12 h, Alarme) mit Minuten-Überspringen, `CatchUpReport`.
  - BotEngine (4 Presets §B8.5, 1×/min auf 1m-Schluss, Kapital-Deckel, Not-Aus, Tagesbremse, Lohn), Alarme (Auslösung auf 1s-Kerzen).
  - ACAD-Tutorial-Pfad §B8.6 über `Replay`-Remote.
  - Liga: zählende Trades (≥ 2 % NAV, ≥ 60 s), Börsentag-Renditen (Modified Dietz), Admin-Fenster ausnehmen, `LeagueStats`, Signale
    `OnTrade/OnDayResult`.
- **Abnahme:** (1) Kaufen+Sofortverkauf ≤ 0 (1.000 Zufallsfälle). (2) Cash nie negativ, Reservierungen nach Storno 0, OCO storniert Gegenseite.
  (3) Gewinn-Transfer: Schwelle 1,02, Limit 6 %, 1× je Börsentag, Starthilfe nicht abhebbar, Admin-AKY nicht abhebbar. (4) Offline-Abgleich
  liefert dieselben Fills wie online (gleicher Zeitraum). (5) `contract_check` FIREWALL/DEPOT_WRITE grün. (6) ACAD-Tutorial läuft in
  Studio Solo und 2 Players unabhängig. (7) 10 Orders/s eines Spielers → Bucket greift, keine Server-Last > 0,1 ms.
- **Tests:** `portfoliomath.test` (Gebühren-Rundung, Basis-Verhältnis, Withdrawable, Dietz, TWR, Skill-Score-Grenzfälle, MaxQty < 2^53),
  `indicators.test` (feste Reihen gegen `js/indicators.js`-Werte, Warm-up nil), `OrderTests` (Trigger-Lücken, Pfad-Regel, Nachzieh-Stopp ohne
  Zukunftsblick, Offline == Online, Bot-Deckel, Tagesbremse).

## WP5 – Charts, Terminal, Markt-UI (Client)
- **Dateien:** `src/client/Modules/{MarketClient,ChartView,Terminal,DepotView,NewsFeed,Ticker,Monitors,EffectsMarket}.luau`, `src/shared/Lang/Terminal.luau`.
- **Liefert:** §B7 komplett (Schichten, Layouts Handy/PC/Controller, Order-Ticket, News-Karte + Drosselung + Tiko-Ampel, Charts, Indikatoren,
  Alarm-Linien, Markttiefe/Umsätze simuliert, Heatmap, Kalender-Tab, Analyse-Tab, Depot-Tab mit Gewinn-Transfer-Knopf), Welt-Monitore,
  Ticker-Wände/Leiste, Effekte `Bell`, `ReadWell`, `DayRecap`, C7.5 (WP5-Teil).
- **Braucht:** QuoteCodec (WP3), Indicators/PortfolioMath (WP4), Requests §C9 (Mkt*, Trade*, Alert*, Bot*, TowerTransfer), State `Depot`,
  `Market`, `League`, `Prog`, Hooks `Quotes`, `Market:*`, `Replay`, UI-Kit (WP2), `CityService`-Monitor-Parts über Attribut `Monitor` im Workspace.
- **Aufgaben:** MarketClient (Frame dekodieren, 1s/5s/1m-Kerzen aus dem Strom, Lücke > 2 Ticks → Historie neu, Hook `Quotes`), ChartView
  exakt Renderer-Vertrag §B7.5 (Pools, O(1)-Laufband, Path2D mit Fallback), Terminal (3 Schichten nach `Prog.Licence`, Lizenz-gefilterte
  Instrumente/Ordertypen/Indikatoren, Chips 10/25/Max, Bestätigung ab 20 %, Kosten-Vorschau), NewsFeed (Karte §B7.4, Liste 50,
  Ruhemodus), DepotView (Positionen, Orders, Alarme, Bots, Transfer, Starthilfe, Performance), Ticker (Leiste + Wände), Monitors (nächste
  K live), Farbenblind-Modus, ACAD-Übungsansicht.
- **Abnahme:** (1) Chart < 0,3 ms/Frame am Handy (MicroProfiler) mit 60 Kerzen + 3 Indikatoren; ≤ 900 GuiObjects; kein `Instance.new`
  beim Ticken. (2) Live-Kerze gleitet ohne Sprünge; neue Kerze schiebt O(1). (3) Keine News-Karte für nicht gehaltene „leicht“-News;
  max. 1 Karte/30 s. (4) Kein Kauf-Knopf auf News-Karten; keine verbotenen Wörter. (5) Controller kann komplett handeln.
  (6) Azubi sieht nur 12 Werte + AKX36 und nur seine Ordertypen.
- **Tests:** Studio Solo + 2 Players (identische Charts), Gerätesimulator Handy, Debug-Schalter „1000 Frames abspielen“ (Leistung).

## WP6 – Turm-Ökonomie (Server)
- **Dateien:** `src/server/Services/{TowerService,PlotService}.luau`, `src/shared/TowerMath.luau`, `src/shared/Config/Tower.luau`,
  `src/shared/Lang/Tower.luau`, `src/server/Tests/TowerTests.luau`, `tests/towermath.test.luau`, `tools/economy_sim.py`.
- **Liefert:** §B3 (Plot-Zuweisung), §B4 (Daten/Regeln), §B5, Gewinn-Transfer-Ausführung (CR-Seite), Offline-Einnahmen, Tresor,
  Bau-Warteschlange, Boosts/Server-Boost/Event-Multiplikator (Deckel), C5.5, C6.2 (TowerMath), State `Tower`, `Income`, `Plot`.
- **Braucht:** `ShopService.Credit/Debit/Balance` (WP10) · `MonetizationService.PassFactor/FixedFactor/HasPass` (WP10) ·
  `ProgressionService.TraderFactor/Perk/IpoCount/AlbumSets/LicenceDef` (WP9) · `CommunityService.FriendsInServer/RespektActive` (WP9) ·
  `OrderService.Withdraw/OnBell` (WP4) · `TowerVisualService.*` (WP8) · `LifestyleService.TakeDecor/ReturnDecor/Comfort` (WP8) ·
  `EventService.EventMult` (WP11) · `RewardService.Track` · `AntiCheatService.NoteTeleport` · `MetricsService`.
- **Aufgaben:** Formeln §B5 exakt in `TowerMath` (gleiche Werte wie `economy_sim.py`); Stufen-Tore (Lizenz, Börsengang); Abteilungen inkl.
  Nachbar-Effekte, Personal, Raum-Stufen, Effizienz; Einkommens-Job 1 Hz (Batch, Tresor/Auto-Kassierer/Hausmeister), Boost-Countdown nur
  online; Offline-Abrechnung beim Join (`DataService.LastSavedAt`); Bauzeiten/Token/Bau-Hilfe/Express; Gewinn-Transfer (Request + Glocke);
  Plot-Zuweisung mit Freunde-Nachbarschaft, Besuche/Aufzug/Privat-Etagen, Deko-Slots; `ResetForIpo`; Multiplikator-Teile für den HUD;
  `economy_sim.py` pflegen (Gates G1–G4) und Ergebnis berichten.
- **Abnahme:** (1) `TowerMath` == Tabelle §B5.1 für alle 50 Etagen. (2) Kein Preis/Konto ≥ 9e15, Klemmung getestet. (3) Zeitlich-Deckel ×10,
  Event ≤ ×3. (4) x2 allein ×2, x3 allein ×3, beide ×4 (Einkommens-Test). (5) Offline: 3 h weg → exakt `Steady × Rate × 3 h`; > Deckel geklemmt.
  (6) Tresor-Sammeln aus > 70 Studs abgelehnt. (7) `economy_sim.py --quick` G1 „OK“, Voll-Lauf G2–G4 erfüllt.
- **Tests:** `towermath.test` (Kosten/Einkommen/Bauzeit-Tabellen, Multiplikator-Gruppen, Offline-Klemmen, Sterne-Formel), `TowerTests`
  (Tore, Nachbar-Effekte, Börsengang-Reset behält Depot/Lizenz/Lager, Transfer-Fluss nur AKY→CR).

## WP7 – Stadt, Grafik, Fahrzeuge
- **Dateien:** `src/server/Services/{CityService,GraphicsService,VehicleService}.luau`, `src/server/World/{CityLayout,CityKit}.luau`,
  `src/shared/VehicleModels.luau`, `src/shared/Config/{City,Vehicles}.luau`, `src/shared/Lang/{World,Vehicle}.luau`,
  `src/client/Modules/{WorldLook,CityLife,Vehicles,Garage}.luau`, `src/server/Tests/WorldTests.luau`.
- **Liefert:** §A4 (Licht, Materialien, Tag/Nacht = Börsentag, Markt-Wetter, Crash/Rally-Tönung), §A5 (Stadt mit allen Zonen, Firmen-Läden,
  Plaza, Börsensaal-Gebäude mit Anker-Parts für Glocke/IPO-Wand/Hall-of-Fame/Monitore/Akademie/VIP-Balkon/Dachterrasse, Ringstraßen,
  Autobahn, Marina, Hügel, Helipad, Kulisse), Umgebungsleben, §B12.1 Autos (Physik, Tuning, Kollisionsgruppen, Klassen-Tempo, Showroom-
  Drehteller-Effekt `Reveal`, Aktionärs-Rabatt), C5.6, Streaming-Modi §B3.
- **Braucht:** `ShopService.Debit/Grant` · `OrderService.HoldsShares` (Rabatt, pcall) · `AntiCheatService.SetAllowance/Exempt/NoteTeleport` ·
  `MarketService.Regime` (nur über Client-Frame) · Hooks `Quotes`, `Market:Event`, `Market:News` (Firmen-Läden) · `Quality.Budget`.
- **Aufgaben:** progressiver Stadtbau ≤ 400 Parts/Frame (≤ 12.000 gesamt), alle Anker (`CityService.Anchor`) mit Attributen, Monitor- und
  Board-Parts mit Attribut `Monitor`/`Board`; GraphicsService (eigene Lighting-Effekte, alte löschen); WorldLook (Uhrzeit aus `Clock`, Wetter aus
  Regime, Crash/Rally, DoF in Menüs, Fensterlicht-Kaskade); CityLife (Verkehr auf Splines, Drohnen, Luftschiff, Budget je Stufe, nur Client);
  Fahrzeuge (VehicleModels-Rezepte 16 Autos mit Asset-Plätzen, Spawn/Despawn, Boost, Drift, Tempo-Prüfung 5 Hz, Kollisionsgruppen §C11.3),
  Garage/Showroom-UI, Requests Car*.
- **Abnahme:** (1) Server-Teile ≤ 12.000 Stadt (SelfTest zählt). (2) Ein Auto fährt durch einen Spieler hindurch, ohne ihn zu bewegen.
  (3) 60 FPS PC Ultra auf der Plaza bei Nacht; ≥ 30 FPS Handy Low. (4) Streaming: Plot-Hüllen bleiben aus 600 Studs sichtbar (LOD) –
  sonst Meldung. (5) Tag/Nacht auf zwei Clients synchron (±1 s).
- **Tests:** `WorldTests` (Teilezahl, Anker vorhanden, Plot-Seiten 10, Kollisionsgruppen-Matrix, Routen geschlossen), Studio 2 Players (Autos).

## WP8 – Turm-Optik, Interiors, Lifestyle
- **Dateien:** `src/server/Services/{TowerVisualService,LifestyleService}.luau`, `src/shared/{TowerModels,DecorModels,LifestyleModels}.luau`,
  `src/shared/Config/{Decor,Lifestyle}.luau`, `src/shared/Lang/{TowerUi,Life}.luau`,
  `src/client/Modules/{TowerView,TowerUI,Elevator,WelcomeBack,Boutique,EffectsTower}.luau`, `src/server/Tests/VisualTests.luau`.
- **Liefert:** §B4.2 Silhouetten (12 Stufen, Kronen, Fassaden, Neon), Server-Hüllen ≤ 8 Parts/Etage, Plot-Attribute + `Layout` §C12.3,
  Client-Interiors (11 Abteilungen × 5 Stufen, Personal-Roboter, Deko, Live-Monitore), Tower-Menü (Etage bauen, Abteilungen mit
  Nachbar-Pfeilen, Personal, Stufen, Effizienz, Deko-Slots, Fassade/Name/Privat, Börsengang-Vorschau-Einstieg, Gewinn-Transfer-Knopf),
  Aufzug-Kinoszene, Willkommen-zurück-Bericht mit Vorher/Nachher (ViewportFrames) + Zukunfts-Ich, Boutique (Uhren, Accessoires, Deko,
  4-h-Rotation aus `ShopService.Rotation`), Uhren am Handgelenk, Effekte `BuildDone/StageUp/TransferTube/Collect/Crane`, C5.7.
- **Braucht:** State `Tower`, `Income`, `Storage`, `Life`, `Credits`, `Depot` · Requests Tower*/Life* · `ShopService.Debit/Grant` ·
  `CityService.PlotSite` · `Quality.Budget` · Hooks `Plot:*` (eigene), UI-Kit.
- **Aufgaben:** TowerModels/DecorModels/LifestyleModels als deterministische PartSpec-Rezepte (gleich auf Server/Client) mit Asset-Plätzen;
  Hüllen-Warteschlange ≤ 6 Etagen/Frame; Interiors ±k Etagen je Stufe, Pools, Aufbau ≤ 1,5 ms/Frame; Fensterlichter; Roboter-Wippen im
  PreRender; Kran-/Morph-Szenen (überspringbar, ReducedFx sofort); Lager/Uhren/Accessoires-Logik; Willkommen-Bericht aus
  `OrderService.CatchUpReport` + Offline-CR.
- **Abnahme:** (1) 10 Tower × 50 Etagen Server ≤ 4.600 Parts. (2) Interior eines vollen Towers am Handy ≤ 150 Parts je sichtbare Etage,
  < 0,3 ms/Frame. (3) Jede Stufe aus 600 Studs unterscheidbar (Screenshot-Reihe im Bericht). (4) Aufzug: Ankunft mit Füßen auf dem Boden,
  kein AntiCheat-Flag. (5) Deko-Slot-Wechsel schreibt `Layout` ≤ 2 KB.
- **Tests:** `VisualTests` (Teilebudget je Stufe, Layout-Rundreise, Rezepte deterministisch), Studio-Besuch eines fremden Towers (2 Players).

## WP9 – Fortschritt, Tutorial, Sozial, Bestenlisten
- **Dateien:** `src/server/Services/{ProgressionService,RewardService,CommunityService,LeaderboardService}.luau`, `src/shared/ProgressMath.luau`,
  `src/shared/Config/{Progression,Season,Rewards}.luau`, `src/shared/Lang/{Progress,Tutorial,Social}.luau`,
  `src/client/Modules/{Tutorial,Academy,Quests,Season,Boards,Social,Prestige}.luau`, `src/server/Tests/ProgressionTests.luau`, `tests/progressmath.test.luau`.
- **Liefert:** §B2 (Tutorial-Skript mit Tiko, Funnel 1–18), §B9 (XP, Lizenzen + Prüfungen, Know-how, Ruf, Vermögen/Titel, Börsengang +
  Vorstand, Quests, Erfolge, Badges, Album, Login, Skyline-Pass, Rückkehr), §B11 (Bestenlisten, Liga-Stufen, Hall of Fame, Respekt, Einladen,
  Gruppe, Reaktionen, Zeigen-Karte, Notification-Opt-in), Akademie (16 Lektionen à 3–5 Karten + 3 Fragen), Effekte `IpoCeremony/LicenceUp/TitleUp/
  QuestDone/Achievement`, C5.8, State `Prog`, `Quests`, `Login`, `Season`, `Social`.
- **Braucht:** `OrderService.OnTrade/OnDayResult/LeagueStats/SetLicence/TaintWeek/Nav` · `MarketService.OnNews/RecentNews` · `TowerService.ResetForIpo/RunSpend/TowerValue/OnFloorBuilt/OnStageUp/Floors` ·
  `ShopService.Credit/Grant` · `VehicleService.GrantCar/CollectionValue` · `LifestyleService.Grant*/CollectionValue` · `CityService.Anchor/BoardPart` ·
  `TextService` (Ticker) · `MetricsService.Funnel`.
- **Aufgaben:** alles wie Liefert; Track-Aufrufer für jede Quest-Art (Quellen: eigene Signale + `RewardService.Track` aus anderen WPs per pcall –
  WP9 meldet im Bericht, welche Arten welcher WP aufruft); Ticker-Filter; Liga-Belohnung beim ersten Join der Woche; Hall-of-Fame-Statuen.
- **Abnahme:** (1) Tutorial komplett in Studio Solo < 11 min, jeder Schritt überspringbar, kein Robux-Angebot. (2) Lizenz-Aufstieg ruft
  `OrderService.SetLicence`, Basis steigt, Zeremonie. (3) Börsengang behält alles laut §B9.6, Sterne-Formel korrekt, Vorstand wirkt nur auf
  Turm. (4) Ruf: Deckel 20/Tag, Abbau, Untergrenzen. (5) Jede Quest-Art hat ≥ 1 Tracker (SelfTest). (6) Bestenlisten schreiben nie in Studio.
- **Tests:** `progressmath.test` (Level-Kurve, Lizenz-Ermittlung, Ruf-Stufen/Abbau, Titel-Grenzen, Quest-Auswahl deterministisch),
  `ProgressionTests` (Quest-Tracker-Abdeckung, Börsengang-Erhalt, Know-how-Grenzen, Admin-Lizenz taintet).

## WP10 – Monetarisierung, Shop, CR-Konto
- **Dateien:** `src/server/Services/{MonetizationService,ShopService}.luau`, `src/shared/Config/Shop.luau`, `src/shared/Lang/Shop.luau`,
  `src/client/Modules/Shop.luau`, `src/server/Tests/EconomyTests.luau`.
- **Liefert:** §B14 komplett (14 Pässe, 17 Produkte, Abo, Bau-Gutschein-Quote, Bau-Express-Token, Geschenk-Gate, Starter-Paket, Saison-Premium,
  Angebots-Regeln), CR-Konto (`Credit/Debit/Balance`, Quellen/Senken-Whitelist, Metriken je 60 s gebündelt), Grant/Sanitize, Boutique-Rotation,
  Pass-/Fix-Faktoren, Shop-Fenster (Banner „Kurse kann man nicht kaufen – alles Spielgeld“, ehrliche Wirkungstexte, „Zusammen x4“),
  §C11.4 Punkte 4–6, C5.9, State `Credits`, `Passes`, `Club`, `Boosts`, `Offers`, `RandomAllowed`, `TradingAllowed`, `Starter`.
- **Braucht:** `TowerService.AddBoost/SetServerBoost/AddExpressToken/ApplyExpress/Income` · `EventService.StartParade/StartFireworks` ·
  `RewardService.GrantSeasonPremium/AddSeasonTiers` · `VehicleService.GrantCar` · `LifestyleService.GrantWatch/GrantAccessory` ·
  `DataService` · `PlayerStateService`.
- **Aufgaben:** CC-Kern 1:1 (ProcessReceiptWith, prepare/grant ohne Yield, Belege 60, LoadPasses 3 Versuche, Policy fail-closed,
  SimulatePurchase, TryOffer max. 1/Sitzung + Regeln §B14.4); BuildGrant je Produkt; Quote-Cache 10 min (`Purchases.Quote`); Bundle-Logik;
  Abo-Status (`GetUserSubscriptionStatusAsync`, pcall) + tägliche Club-Gabe; Geschenk mit Empfänger-Prüfung; Shop-UI mit Live-Preisen.
- **Abnahme:** (1) `SimulatePurchase` zweimal und gleichzeitig mit gleicher PurchaseId → genau eine Gewährung. (2) SelfTest „Firewall“
  byte-gleich für jedes Produkt/Pass/Saison-Stufe/Club-Gabe/Code. (3) „NoPaidRandom“ grün. (4) Kein Angebot in Sitzung 1 und nie während
  Crash-Warnung/Terminal offen. (5) Bau-Gutschein gewährt `max(Quote, Neu)` und nur CR. (6) Geschenk bei `TradingAllowed == false` gesperrt.
- **Tests:** `EconomyTests` (Belege, Grant all-or-nothing, Sanitize, Firewall, NoPaidRandom, Bundle, Starter einmalig, Quote-Ablauf).

## WP11 – Admin, Events, Anti-Cheat
- **Dateien:** `src/server/Services/{AdminService,AntiCheatService,EventService}.luau`, `src/shared/Config/Events.luau`,
  `src/shared/Lang/{Admin,Events}.luau`, `src/client/Modules/{AdminPanel,AdminTools,Fly,DebugOverlay,EventsClient,EffectsEvent}.luau`,
  `src/server/Tests/AdminTests.luau`.
- **Liefert:** §B15 (Zugriff inkl. Gruppen-Pfad, 11 Tabs, Admin-Abuse-Katalog 21 Events, Taint, Besitzer-Handelssperre ±120 s, globale
  Ansage CC-Stil, Live-Ops-Tab mit `AT_Live_v1` + Notschalter), §B10 (Welt-Events, Glocken-Moment, Sky-Show, Bär/Bulle, Bullen-Parade,
  Feuerwerk, Geldregen, Samstags-Show + Automatik), Anti-Cheat schlank (Verdacht, Honeypot `GrantCash`, Bewegungsbudget mit Erlaubnissen,
  Meldungen), Effekte §C7.4 (WP11-Teil), C5.10, State `Event`, Attribut `IsAdmin`.
- **Braucht:** `MarketService.Admin/AutoShowCancelled/Stats` · `TowerService.SetEventMult/SetServerBoost/SetCostEvent/Income` ·
  `ShopService.Credit/Grant` · `OrderService.AdminCredit/TaintWeek` · `ProgressionService.AdminSetLicence` · `CityService.Anchor/Route` ·
  `VehicleService` (Admin-Gaben) · alle Debug-Ziele (SelfTest, SimulatePurchase/Policy, SkipDay).
- **Aufgaben:** AdminService aus CC (Owner-Regel + `GetGroupInfoAsync`-Pfad, Rate vor Prüfung, Log, Bann-Regeln, publishGlobal/handleGlobal mit
  oberer Zeitgrenze + Dedupe), Markt-Tab ruft nur `MarketService.Admin`; EventService (Rotation `Börsentag % 4` aus `Clock`, Pickup-Token je
  Spieler, Bär-Ziel, Glocken-Moment-Zone, Sky-Show, Wochen-Kalender Nicht-Markt-Teile, Samstags-Show-Ablauf, `Event`-State); AntiCheat aus CC
  ohne Schuss-Teile; AdminPanel-Rahmen CC mit neuen Tabs; Fly CC 1:1; DebugOverlay (§C16 Werte).
- **Abnahme:** (1) „Test → 2 Players“: Player2 bekommt bei jeder Admin-Aktion `{Ok=false}`, 1 Log-Eintrag. (2) Admin-Crash wirkt global
  (zwei Live-Server oder Studio-Team-Test), Admin-Fenster setzt Liga-Taint. (3) Geldregen: jeder Spieler eigene Münzen, Fernsammeln
  abgelehnt. (4) Samstags-Show läuft automatisch, wenn der Besitzer nichts startet; startet er, wird die Auto-Rally abgesagt.
  (5) Honeypot feuern → Kick. (6) Kein Admin-Event löscht oder berührt Käufe.
- **Tests:** `AdminTests` (Owner-Regel Varianten, Klemmen aller Parameter, globale Nachricht mit zu großem `Until` verworfen, Dedupe, Taint-Fenster),
  Studio 2 Players.

## WP12 – Doku (Deutsch, für den Besitzer)
- **Dateien:** `ANLEITUNG.md`, `docs/KOPIERVORLAGEN.md`, `docs/TESTPLAN.md`, `docs/ASSET-LISTE.md`, `docs/STYLE-AKYTEX.md`, `docs/LIVEOPS.md`.
- **Liefert:**
  - **ANLEITUNG.md** (Anfänger, Mac, wie CC-Anleitung): Mac-Tastentabelle, Rojo/Studio-Schritte mit **fetten Klickpfaden**, Studio-Einstellungen
    (Max Players 10, API-Zugriff, Voice, Avatar), Veröffentlichen, Fahrplan-Tabelle, Gamepasses/Produkte/Abo/Badges anlegen und IDs eintragen
    (Verweis KOPIERVORLAGEN), **Fragebogen-Kapitel** mit Antworten §0.6 und Hinweis „Live-Wortlaut prüfen“, **Kids/Select-Schritte** (Alters-
    prüfung, 2FA, Gebühr oder Plus/Premium, 250 Plays/60 Tage), **Marken-Kapitel** §0.5 (was nie ins Spiel/auf die Seite darf, getrennte
    Kanäle, Ad-Regeln), Admin-Panel-Bedienung + Admin-Abuse-Ablauf am Samstag, Live-Ops-Kalender + Experience Events eintragen,
    Saison-Wechsel über Config, Codes, Hybrid-Assets (Higgsfield → Studio Asset Manager/3D-Importer → ID in Config, Besitzrechte),
    Glossar (AKY, CR, Basis, Bau-Kurs, …), KPI-/Funnel-Tabelle (Ziele §E3) und Umsatz-Formel, Fehlerbehebung (NoSave-Toast, „Lokaler Testmarkt“).
  - **KOPIERVORLAGEN.md:** Spielseiten-Titel/Beschreibung DE/EN mit Disclaimer, alle 14 Pässe + 17 Produkte + Abo mit Name, Beschreibung,
    Preis, Config-Schlüssel, Icon-Prompt-Idee; Badge-Texte; Experience-Event-Texte; Social-Link-Satz.
  - **TESTPLAN.md:** Solo, „Test → 2 Players“, Gerätesimulator (Handy, Tablet, PC, Controller), Netzwerk-Simulator, Compliance-Checkliste
    (Wortliste, keine Casino-Deko, Robux-Firewall, Namens-Suche aller 36 Firmen + 4 IPOs + Ticker gegen echte Firmen), Leistungs-Messpunkte §C16.
  - **ASSET-LISTE.md:** jeder Asset-Platz aus §C14.3 (Config-Pfad, Typ, empfohlene Größe/Polys/Format, Higgsfield-Prompt-Idee, Rückfall).
  - **STYLE-AKYTEX.md:** CC-Datei kopiert + Welt-Regeln (§A4), Chart-Regeln (§B7.5), Marken-Blatt (REUSE §8).
  - **LIVEOPS.md:** Wochenplan §B10.4, Saison-Plan §E4, Event-Rotation ändern, Notschalter.
- **Braucht:** Abschnitte A–C dieser Spec, Config-Schlüssel aus §C14.
- **Abnahme:** Ein Laie kann von „Rojo installieren“ bis „Spiel veröffentlicht + Pass-ID eingetragen“ ohne Rückfrage folgen; alle Zahlen
  stimmen mit dieser Spec überein; keine URL zur AKYTEX-Website im Spiel-Kontext; Wortliste eingehalten.

---

# E) v1 und später

## E1. Umfang
| Bereich | **v1 (Launch, alles poliert – keine halben Features)** | v1.1 (+2–4 Wochen) | v1.2 (+1–2 Monate) | v2 (Live-Ops-Skala) |
|---|---|---|---|---|
| Welt | 2 km-Stadt: Plaza, Börsensaal, 10 Plots, Ringstraßen, Λ Motors, Chronohaus, Marina (Deko + Wasser), Villenhügel-Aussicht, Helipad (Schnellreise), Autobahnring, Kulisse mit Firmen-Läden; Tag/Nacht = Börsentag, Markt-Wetter, Grafikstufen, Verkehr/Drohnen | Yacht befahrbar, Helikopter-Flüge (Mega-Tower-Helipad), Villen | Flughafen + Privatjet-Schnellreise, Plaza-Portal zu Meteor Heist/CLUTCH CLASH (nur wenn Altersfreigaben passen) | Orbit-Börse (Raumstation, nach 12 Börsengängen) |
| Markt | 36 Firmen + 7 ETFs + 6 Themen-Körbe, News/Gerüchte/„wie erwartet“, Sektor, Makro, Quartalszahlen, 8 Analysten, Dividenden, Crash/Rally, Crash-Freitag, Rally-Mittwoch, IPO-Erstnotiz (4 je Saison), Handelspausen, Tiko-Ampel | IPO-Zeichnung pro rata, Leerverkauf 1× (Fondsmanager), Wenn-Dann-Bot, Trendlinien, Tägliche Chart-Challenge (Server-Replay 10 Hz, eigene Bestenliste) | Parkett-Rennen (Duelle auf identischem Replay, nur Trophäen) | Trader-AG (Kurs = TWR-Index, System als Gegenpartei, kein Geld zwischen Spielern) |
| Terminal | 3 Schichten, alle Zeitrahmen, 9 Indikatoren, Alarm-Linien, Markttiefe/Umsätze (simuliert), Heatmap, Kalender, Analyse, Multi-Chart (Know-how) | Zeichen-Werkzeuge erweitert | – | – |
| Turm | 50 Etagen, 12 Stufen, 11 Abteilungen, 4+2 Personal, Raum-Stufen, Effizienz, Tresor/Offline, Bau-Hilfe, Aufzug, Besuche, Privat-Etagen, 68 Deko-Teile in festen Slots, 7 Fassaden, Kronen | freies Deko-Raster (0,25/1 Stud, Rückgängig), Etagenplan-Editor zum Ziehen | weitere Abteilungen (Rechenzentrum, Himmelsgarten) | Etagen 51–60 „Spire+“ für 10+ Börsengänge |
| Lifestyle | 16 Autos mit Tuning, 15 Uhren, 8 Accessoires, Jetpack-Pass | +6 Autos, Yacht | Helikopter-Pass, Jet | – |
| Fortschritt | Trader-Level, 10 Lizenzen + Prüfungen, Know-how, Ruf, Titel, Börsengang + Vorstand, 30+12 Quests + Starter-Linie (20), 60 Erfolge, 15 Badges, Album, Login, Skyline-Pass S1, Rückkehr-Belohnung, Akademie 16 Lektionen | Akademie +8 Lektionen, +20 Erfolge (gesamt 80), Sammlungs-Bestenliste | Legenden-Prestige-Kosmetik | Saison-Ligen mit Auf-/Abstieg |
| Sozial | 6 Bestenlisten + Liga-Stufen + Hall of Fame, Besuche, Respekt, Bau-Hilfe, Reaktionen, Freunde-Bonus, Einladen, Gruppen-Kosmetik, Zeigen-Karte, Voice, Glocken-Moment, Bär-Koop | Hedgefonds-Gruppen (Wochenwertung, nur Kosmetik), Geschenk-Kosmetik-Pässe, Experience Notifications **senden** | Clip-Momente mit `CaptureService` (nur bei `IsContentSharingAllowed`) | – |
| Monetarisierung | 14 Pässe, 17 Produkte, Vorstands-Club, Skyline-Pass, private Server gratis, Premium-Bonus | Geschenk-Versionen kosmetischer Pässe (Policy-Gate) | Rewarded Video (≥ 100k DAU, 13+), Preis-Optimierung | – |
| Admin/Live-Ops | volles Panel, 21 Admin-Abuse-Events, Live-Ops-Kalender + Automatik, LiveConfig, Notschalter | weitere Show-Vorlagen | Saison-Werkzeuge | – |
| Doku | ANLEITUNG, KOPIERVORLAGEN, TESTPLAN, ASSET-LISTE, STYLE-AKYTEX, LIVEOPS | – | – | IARC-Fragebogen-Umstellung (gleiche Regeln) |

## E2. Saison-Plan (je Saison: 2–4 IPO-Firmen, Deko-Set, 1 Auto, 1 Fassade, Pass 50 Stufen, Wochen-Thema)
S1 „Neon-Skyline“ (Launch) · S2 „Raumfahrt-Rallye“ (Mondwerk-Schwerpunkt, Raumfahrt-Deko) · S3 „Energie-Wende“ · S4 „Gaming-Boom“ ·
S5 „Winter-Börse“ (Dezember: Schnee-Partikel, Glas-Weihnachtsbaum auf der Plaza) · S6 „Neujahrs-Glocke“.

## E3. KPI-Ziele (MetricsService-Funnel §B2 + Roblox Analytics)
| KPI | Ziel |
|---|---|
| Absprung < 60 s / Tutorial-Abschluss | < 5 % / ≥ 75 % |
| D1 / D7 / D30 | ≥ 35 % / ≥ 12 % / ≥ 5 % |
| Median-Sitzung / Sitzungen ≥ 10 min | ≥ 25 min / ≥ 70 % |
| Co-Play (Sitzungen mit Freund) | ≥ 20 % der Spieler wöchentlich |
| Zahler-Konversion / Starter-Paket | 2–4 % MAU / 2–3 % der D2-Spieler |
| Fehlerhafte Käufe | 0 (idempotente Belege, SimulatePurchase getestet) |
Umsatz-Faustformel (nur Illustration, ANLEITUNG): `USD/Monat ≈ DAU × ARPDAU(R$) × 30 × 0,70 × 0,0038`.

## E4. Risiken & Gegenmittel
| Risiko | Gegenmittel |
|---|---|
| Prüfer liest den Markt als simuliertes Glücksspiel | §0.3 Regeln, Backtest (MARKET §7), Gates G5/G6, keine Robux-Wege zum Markt, keine Wett-Optik/-Wörter, ehrlicher Fragebogen; Zahlen für einen Einspruch bereithalten |
| Marke als Werbung gewertet | AKYTEX nur Spielmarke, keine handelbare AKYTEX-Aktie, kein NOVA/Aky, kein „PRO“, keine Links (§0.5) |
| Ökonomie kippt | `economy_sim.py` Gates G1–G4 vor jedem Release, alle Kurven in Config/LiveConfig |
| Handy-Leistung | Server-Hülle + Client-Interiors, Grafikstufen, Streaming + LOD, Chart-Vertrag |
| Umfang | strenge v1/v1.1-Trennung, 12 Pakete mit festen Verträgen |
| Besitzer am Samstag nicht da | automatische Samstags-Show 18:15 |
| Kinder verstehen Trading nicht | Schicht „Einfach“, Tiko-Ampel, ACAD-Übung, „Schutz an“ Standard, Rettungsschirm, Turm verdient immer |

## E5. Offene Prüfungen in Studio (UNVERIFIED → TESTPLAN)
1. `Path2D`-Darstellung und Clipping (sonst gedrehte Frames). 2. `BuilderExtended`/`BuilderMono` mit Umlauten und „Λ“ (sonst Michroma/
TitilliumWeb). 3. Rojo setzt `VoiceChatService.EnableDefaultVoice`, `StreamOutBehavior` (sonst ANLEITUNG). 4. `Model.LevelOfDetail =
StreamingMesh` für Tower-Hüllen und `AddPersistentPlayer`. 5. `AssetService:CreateMeshPartAsync` im Live-Server. 6. Markt-Tick-Kosten
messen (`Scheduler.Stats`). 7. VehicleSeat-Fahrgefühl am Handy. 8. Open-Cloud-Benachrichtigungen aus dem Spielserver (v1.1).
9. `CreateHumanoidModelFromUserIdAsync` vorhanden (sonst ohne Async). 10. **Live-Wortlaut** Community Standards (Glücksspiel), Advertising
Standards (Finanzdienste) und Fragebogen vor jeder Einreichung lesen. 11. Alle Firmen-/IPO-Namen und Kürzel gegen echte Firmen suchen.

---

# Z) Anhang: Must-Fix-Abdeckung (beide Jurys)
| # | Must-Fix | Umgesetzt in |
|---|---|---|
| 1 | Keine Prestige-Währung aus Robux-beeinflussbaren Turm-Ausgaben kauft Depot/Rahmen/Kurs/Faktor/Trading-Werkzeuge | §0.4 (b), §B9.6 Vorstand nur Turm/Lifestyle, §C11.4 SelfTest |
| 2 | Getrennte Namen/Symbole/Farben AKY (blau Λ) vs. Turmgeld (CR, grün); kein Robux-Text mit „AKY“ | §0.1, §0.4, §B14.2 („Nur CR“), Wortregel |
| 3 | Brücke begrenzen: nur Lizenz-Kurs, kein exponentieller Faktor; Sim beweist Anteile und keinen 9e15-Treffer | §B8.2–§B8.3 (Tabelle 40…40.000, Tageslimit 6 %), §B5.4 + §B9.10 G1–G4, `tools/economy_sim.py` |
| 4 | Freie-Option-Leck schließen: Hochwassermarke, ≥ 1 Börsentag Abklingzeit, ≥ 2 % Schwelle, Starthilfe nie abhebbar; Gate als Release-Blocker | §B8.2, §B8.4, §0.3 (8), §B9.10 G5 |
| 5 | Brücke als Kurs darstellen, nie „Gewinn × Faktor x3“ | §B8.3, §0.1 „Bau-Kurs“ |
| 6 | 1:1-Transfer von #1 ersetzt, damit Trading den Tower baut | §B8.3 + Trader-Faktor §B5.2, Sim-Anteile §B5.4 |
| 7 | Keine Robux-Trading-Komfortfunktionen (Alarme, Multi-Chart, Watchlists) | §B9.3 Know-how, §B14.1 Terminal-Designer nur Kosmetik, §B14.5 Felder, §C19 #6 |
| 8 | Spieler-Firmen nur mit TWR-Index | §0.4 (e), §C19 #8, §E1 v2 |
| 9 | Keine handelbare AKYTEX Holding, NOVA umbenannt, nie „AKYTEX PRO“, keine Produkt-Claims/Links | §0.5, §B6.2 (CGVO/KRWK), §B14.3 „Vorstands-Club“ |
| 10 | Pfotenglück umbenennen; Wortscan phrasenbasiert mit Allowlist | §B6.2 PFFR, §0.7, §C11.4 (7) |
| 11 | Fahrzeuge: Kollisionsgruppen, Server-Tempo-Deckel, AntiCheat für Jetpack/Aufzug | §B12.1, §B12.4, §C11.3 |
| 12 | Umfang von #1 kürzen (freies Bauen, Etagenplan-Editor, Chart-Challenge, Regatta, 120 Erfolge → später) + Arbeitspakete | §E1 (v1.1), §B4.8 feste Slots, 60 Erfolge, Abschnitt D |
| 13 | Ganzzahl-/Präzisionsgrenzen, Titel ≤ 9e15, Firmenwert geklemmt/log | Muss-Regel 9, §B9.5 (Titel bis 1e15), §B9.6 Firmenwert geklemmt, §B11.1 Log-Kodierung, §C17 SelfTest |
| 14 | Dividenden-Sonntag ×2 entfernen oder Ex-Tick verdoppeln | entfernt (kein solches Event in §B10.4) |
| 15 | Kundengeld/XP nur mit echter Order/Akademie, Mindestgröße + Haltedauer | Kundengeld gestrichen; §B9.1 (≥ 2 % NAV, ≥ 60 s, Deckel), §B9.4 Ruf nur zählende Börsentage |
| 16 | News am Handy drosseln (gehalten/Watchlist, ≥ deutlich, 1 je 30 s, Ruhemodus) | §B7.4 |
| 17 | Kein Server-Toast für Einzel-Trade-Gewinne; Flex über Lizenz/Skill/Liga/Tower | Muss-Regel 18, §B11.5 |
| 18 | Kein bezahlter Streak-Retter | §B9.9, §B14.2 „Nicht im Angebot“ |
| 19 | Chips 10/25/Max, Tutorial ≤ Klumpen-Grenze | §0.3 (4), §B7.3, §B2 (10 %), §C19 #13 |
| 20 | Überlauf-Kurven neu (Effizienz-Deckel, Kosten-Bänder, Personal Etage 50 < Deckel), Validate/SelfTest für alle Preise | §B5.1–§B5.3 (teuerster Preis 4,9e13), §C14.1 Validate, §C17 |
| 21 | Zeitlich-Multiplikator deckeln (≤ ×10, Event ≤ ×3) | §B5.2 |
| 22 | Grund-Alarme/Zeichenlinien gratis lizenzabhängig; Markttiefe, VWAP, Stochastik, ATR im Profi-Layer | §B7.5, §B9.3 (Basis 3 Alarme gratis) |
| 23 | Trading muss in der ersten Stunde zählen; Gate gegen Farmen | §B2 (Tutorial-Transfer ≈ 15.000 CR), §B5.4 (15–73 % in Stufen 1–5), G5 |
| 24 | Admin-„Lizenz geben“ taintet Liga | §B8.1, §B15.2, `ProgressionService.AdminSetLicence` |
| 25 | News-Karte ohne Countdown-Ring/Kauf-Knopf („Händler lesen …“) | §0.3 (5), §B7.4 |
| 26 | Hybrid-Asset-Architektur + ASSET-LISTE | Muss-Regel 1, §C14.3, `Shared/AssetSlot`, WP12 |
| 27 | Keine Konflikte bei geteilten Dateien: Effekte je Domäne, UI-Kit-Neuteile in WP2 zuerst, eingefrorene Verträge, WP-Entlastung | §C7.4 Effekt-Registry, §C9/§C10/§C7.2 frozen, D0 (6), Controls/Settings/TouchControls in WP2, Doku in WP12 |
| 28 | Admin-Prüfung für Gruppen-Spiele, Player2 abgelehnt; Geschenk mit `IsPaidItemTradingAllowed` fail-closed | §B15.1, §B14.2 GiftBoost |
| 29 | Maskottchen nicht „Aky“, keine KI-Wörter | Muss-Regel 7, §0.1 Tiko, §0.6 (KI: Nein) |
| 30 | Notification-Opt-in-Gerüst v1 oder dokumentierte Verschiebung; Labels bestätigt | §B11.9, §0.2 (wörtlich geprüft) |
