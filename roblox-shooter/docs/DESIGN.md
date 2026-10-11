# CLUTCH CLASH – Finales Design & Umsetzungs-Spec (v1)

> **Status:** verbindlich für alle Coding-Agents (Stand 2026-10-11). Diese Datei ersetzt die drei Entwürfe
> (#1 „Clutch Clash“, #2 „Popshot business“, #3 „Popshot robust“). Basis = Spielgefühl/Retention von #1,
> Architektur/Robustheit von #3, Live-Ops-Leitplanken und Crown-Ring-Bühne von #2. Alle „Must-Fix“-Punkte
> beider Jurys sind eingearbeitet (Abdeckungsliste im Anhang Z).
>
> **Begleitdokumente (bleiben, werden referenziert):**
> - `docs/ASSETS.md` – einzige erlaubte `rbxasset://`-Pfade (11 Sounds, Texturen, Schriften), Sound-Rezepte §2.2.
> - `docs/REUSE.md` – was aus Meteor Heist (MH) übernommen wird, inkl. Pflicht-Fixes §14.
> - `docs/ADMIN-WUENSCHE.md` – Admin-Wünsche des Besitzers (vollständig in B25 umgesetzt).
>
> **Sprache:** Spec auf Deutsch, Code-Bezeichner Englisch, **Code-Kommentare Deutsch** (wie MH).
> Zahlen in dieser Datei sind Startwerte und stehen 1:1 in `Config` (änderbar ohne Code).

---

## 0. Muss-Regeln (gelten für jedes Arbeitspaket)

1. **Keine hochgeladenen Assets.** Alles aus Parts/`Part.Shape`/WedgePart/CornerWedgePart/SpecialMesh
   (MeshType Sphere/Cylinder/Wedge/Brick), Beams, Trails, ParticleEmitter, UI-Frames. Texturen/Sounds **nur**
   aus `docs/ASSETS.md` (Status VERIFIED). Zusätzliche Sound-IDs nur als `Config.Client.Sounds.<Rolle> = 0`
   (0 = eingebautes Rezept). **Nie** `swordslash.wav` / `electronicpingshort.wav`.
2. **Keine eigenen Animationen.** Viewmodel prozedural. 3rd-Person: Waffe als **Nicht-Tool-Modell**
   an die Hand geschweißt, Halte-Pose = Roblox-eigene Animation `rbxassetid://507768375` (toolnone).
   Bots: Roblox-Standard-IDs (idle 507766388, walk 507777826, run 507767714, jump 507765000, fall 507767968).
3. **Server ist Autorität** für HP, Munition, Treffer, Währung, Besitz, Match-Zustand. Client sendet nur Absichten.
4. **Kein Pay-to-Win, wörtlich:** Robux kaufen **nie** Waffen, Coins, Schlüssel, Splitter, Werte, Coin-Multiplikatoren.
   Boosts wirken nur auf XP / Pass-XP / Meisterschaft. Banner im Shop: „ALLE WAFFEN ERSPIELBAR – KEIN PAY-TO-WIN“.
5. **Ausschalten = „Pop to Vault“** (B13): Unser Code setzt **nie** `Humanoid.Health = 0` und ruft **nie**
   `LoadCharacter` während eines Matches.
6. **Hitboxen = analytisch, feste Größe**, aus repliziertem HRP + Head. Kein Client-Zustand verkleinert sie.
7. **Spread-Seed kommt vom Server** (`Spread.Seed(salt, shotId)`), nie vom Client.
8. **Remote-Hygiene** in genau dieser Reihenfolge: Rate-Limit → `typeof` → `math.isfinite`/NaN → Clamps →
   Zustands-/Ready-Prüfung → `pcall` → Antwort-Tabelle. Nie `FireAllClients` für Match-Daten, nie `InvokeClient`.
9. **Gebundene Schleifen:** ein Server-Scheduler, keine `while`-Schleife pro Spieler, jede Sammlung hat eine Obergrenze,
   jede Pro-Spieler-Tabelle wird bei `PlayerRemoving` geleert.
10. **Keine veralteten APIs:** `*Async`-Varianten (`CreateHumanoidModelFromDescriptionAsync`, `GetProductInfoAsync`,
    `UserOwnsGamePassAsync`, `AwardBadgeAsync`), `RunService.PreRender` statt `RenderStepped`,
    `RaycastParams.IncludeInstances/ExcludeInstances` statt `FilterDescendantsInstances`,
    `workspace:RegisterCollisionGroup`, `task.*`. Gruppen-Checks gibt es nicht.
11. **Kein Material `Ice`** (rutschig). Glass blockiert Kugeln (ist Teil der Map). Viewmodel-, Waffen-, Charm-,
    Finisher- und Accessoire-Teile: `CanQuery=false, CanTouch=false, CanCollide=false, Massless=true, CastShadow=false`.
12. **Mild-Rating:** kein Blut, keine Leichen, keine realistischen Waffen (Spielzeug-Blaster mit **oranger Spitze**).
13. **Nur der Besitzer ist Admin** (B25.1). Niemand kann Admin kaufen.
14. **Studio-Solo voll spielbar** (Bots füllen alles), „Test → 2 Players“ funktioniert (Player2 ist kein Admin).
15. **Fremde Dateien nicht anfassen** (Abschnitt D). Andere Services nur zur Laufzeit über die `Services`-Tabelle
    (Server) bzw. `ctx.Modules` (Client) aufrufen; optionale Dienste immer über `pcall`.

### 0.1 Begriffe
| Begriff | Bedeutung |
|---|---|
| **Kontext (Ctx)** | Ein Kampf-Raum mit eigenen Regeln: `"M<id>"` (Match), `"Range"` (Schießstand). |
| **Combatant** | Alles, was getroffen werden kann: Spieler, Bot, Übungspuppe (Typ `Types.Combatant`). |
| **Slot (Arena)** | Einer von 8 Arena-Plätzen weit weg von der Lobby; dazu fest: Crown Ring (Slot 0) und Range. |
| **Roster-Slot** | Nummer 1–32 eines Combatants innerhalb eines Kontexts (für Buffer-Pakete). |
| **Pop** | Ausschalten: Konfetti-Finisher, Figur wird in den Tresor (Vault) unter der Arena verschoben. |
| **Tainted** | Match, in dem der Besitzer Admin-Kräfte nutzte → zählt für niemanden negativ. |
| **WP** | Arbeitspaket (Abschnitt D). |

---

# A) Name, Pitch, Art Direction, „Besser als RIVALS“

## A1. Name
**CLUTCH CLASH** – Spielseiten-Titel: **`CLUTCH CLASH Duels [1v1-4v4]`** (Such-Suffix).
„Clutch“ = eine Runde als Letzter gewinnen; „Clash“ = Kampf. Ersatznamen (falls belegt): *Blaster Clash*, *Pop Duel*.
Der Name steht nur in `Config.GameName` und `Lang` (`core.gameName`).

Taglines: EN „Instant duels. Zero waiting. Pure skill.“ · DE „Sofort-Duelle. Null Warten. Reiner Skill.“

## A2. Pitch
- **DE:** Schnelle Ego-Duelle mit Spielzeug-Blastern, 1v1 bis 4v4. Aufs Pad – in unter 15 Sekunden kämpfst du,
  gegen echte Spieler oder ehrlich markierte Bots. Besiegte Gegner zerplatzen in Konfetti („POP!“). Jede Waffe ist
  erspielbar (ca. 6 Stunden für alle), Robux kaufen nur Style. Verteidige die Krone im Crown Ring – die ganze Lobby schaut zu.
- **EN:** Fast first-person toy-blaster duels, 1v1 to 4v4. Step on a pad and fight in under 15 seconds against players
  or honest [BOT]s. Pop rivals into confetti, earn every blaster by playing, and defend the crown while the whole lobby watches.

## A3. Welt
„Clutch Plaza“ ist eine schwebende Spielzeug-Stadt (Lobby) der „Clash League“. Duelle finden in schwebenden
Spielzeug-Arenen („Clash Pods“) statt, 4.000 Studs entfernt. Blaster sind übergroße Spielzeuge (orange Spitze,
Neon-Streifen, Glas-„Energiekammern“). Ausgeschaltete Kandidaten „poppen“ und sind nächste Runde zurück.

## A4. Art Direction (nur Parts)
| Element | Regel |
|---|---|
| Teamfarben | Team A **BLAZE** Orange `255,140,40`, Team B **FROST** Blau `60,170,255` (farbenblind-tauglich). Gegner-Umriss wählbar: Rot `255,59,59` (Standard), Magenta `255,59,216`, Gelb `255,212,59`, Weiß. |
| Flächen | Pastell-Plastik: Cream `244,235,221`, Mint `154,209,212`, Pink `247,183,200`, Lilac `185,167,242`, Sand `242,213,154`, Charcoal `43,43,51` (Kontrast-Kanten), Navy `28,32,64`. |
| Materialien | SmoothPlastic (Standard), Neon (Kanten/Pads/Zone, max. ~8 % der Map-Teile), Glass (Transparency 0.3–0.6, blockiert Kugeln), Foil (Metall-Teile der Blaster), WoodPlanks (Stege). **Nie Ice.** |
| Formen | Klobige Blöcke mit „Fake-Fase“ (kleinerer Block 0.2 Stud Lippe oben drauf), Zylinder-Säulen, Wedge-Rampen, Ball-Deko, SurfaceGui-Buchstaben (FredokaOne). Keine Unions, keine Meshes, keine Decals. |
| Licht | Lobby: ShadowMap, ClockTime 14, Atmosphere Density 0.32, Bloom 0.5/24/1.6, ColorCorrection Sat +0.15, Contrast +0.05. Match-Stimmungen (B8.2) nur **client-lokal**. |
| Figuren | Eigener Avatar. Standard-Namensschild aus, eigenes Team-Namensschild. Gegner-Umriss `Highlight` DepthMode **Occluded** (nur sichtbar, wo du ihn sehen kannst – kein Wallhack). |
| Ausschalten | Körper verschwindet sofort, Finisher des Schützen spielt (Standard „Konfetti“: SquareParticle-Würfel + sparkles-Sterne + `oof.ogg`). |
| Treffer | Cartoon-Sterne (`particles/sparkles_main.dds`), weißer Puff (`textures/explosion.png`), Schadenszahl. Nie Blut. |
| UI | MH-UI-Kit (FredokaOne, dicke schwarze UIStroke, klobige Verlaufs-Buttons). HUD-Zahlen RobotoMono, Banner LuckiestGuy, „HEADSHOT!“/„POP!“ Bangers. |
| Sound | Rezepte aus ASSETS.md §2.2 (11 eingebaute Sounds, Tonhöhe/PlaybackRegion/Effekte). |

## A5. Was wir besser machen als RIVALS (Spielseite / Thumbnails)
| # | RIVALS-Problem (Recherche) | CLUTCH CLASH | v |
|---|---|---|---|
| 1 | Warten, abgebrochene Duelle | Menschen zuerst, nach **8 s** füllen ehrliche **[BOT]s** (Studio 2 s, Neulinge 3 s). Pads brechen nie ab. „Bots jetzt“-Knopf nach 3 s. **Erster Schuss ≤ 15 s** nach vollem Pad. | v1 |
| 2 | Neulinge werden zerlegt | Tutorial-Duell gegen Rookie-Bot (erste 2 Schüsse pro Runde gehen daneben), 3 Rookie-Matches, Neulings-Schutz in der Warteschlange. Erster Kill < 60 s. | v1 |
| 3 | Pay-to-Win (350–700-Key-Waffen, Bundle-Waffen) | **Alle 15 Waffen nur mit erspielten Coins**, alle zusammen ca. 6 h. Coins werden nie verkauft. Boosts nur XP. | v1 |
| 4 | „Meine Schüsse zählen nicht“ | **Todes-Rückblick** (wer, Waffe, Rest-HP des Gegners, jeder Treffer mit Kopf/Körper/Distanz, „du hast X in N Treffern gemacht“), Lag-Kompensation, Ping im Scoreboard. | v1 |
| 5 | Camper bei Zeitablauf | **15 s Overtime-Zone** (3 s halten gewinnt), danach HP-Tiebreak; Anti-Camp-Radar nach 30 s ohne Schaden. | v1 |
| 6 | Endlose Matches | Rundenlimit `2×RoundsToWin+1`, dann **Sudden Death** (30 s, alle 50 HP, Zone offen). | v1 |
| 7 | Nur Nerfs, kein Live-Tuning | **Live-Balancing** im Besitzer-Panel (Buffs so leicht wie Nerfs, Not-Aus pro Waffe, Versionsverlauf mit Rückgängig), Statistiken pro Waffe. | v1 |
| 8 | Keine „Winner stays“-Bühne | **Crown Ring** mitten in der Lobby: Gewinner bleibt, Krone auf dem Kopf, Serien-Anzeige, die ganze Lobby sieht Tracer & Finisher. | v1 |
| 9 | Immer gleiche Maps | 6 Maps × 5 Licht-Stimmungen, **Mutator des Tages** (8 Mutatoren). | v1 |
| 10 | Cheater, falsche Banns | Server prüft jeden Schuss (Server-Seed, Rückspul-Hitbox, Munition, Feuerrate, Sichtlinie), Bewegungs-Budget, Honeypot-Remote, Verdachts-Punkte → Besitzer-Prüfliste. Statistik bannt nie automatisch. | v1 |
| 11 | Handy vs. PC unfair | Warteschlange bevorzugt gleiche Eingabeart, sanfte dokumentierte Zielhilfe (nie Maus), Auto-Feuer für Touch (85 % Feuerrate). | v1 |
| 12 | Toxischer Chat | Positive Umschreibungen (nur ganze Wörter), GG-Bonus, Loben (Honor). | v1 |
| 13 | Ranked-Sperre Lv 100 + Ausweis | Ranked ab Lv 15 + 7 Tage Account-Alter, **ohne Ausweis** (v1.1, mit „Mehr Gegner finden“-Teleport). | v1.1 |
| 14 | Custom-Games nur mit bezahltem VIP-Server | Gratis Custom-Räume mit 4-Zeichen-Code. | v1.2 |
| 15 | Glücksspiel-Druck | Kisten nur Einzel-Öffnung, Quoten exakt vor dem Kauf, Garantie (Pity), Duplikate → Splitter, jedes Item auch direkt kaufbar. Max. 1 Angebots-Popup pro Sitzung, nie in einer Runde. | v1 |

---

# B) Gameplay-Spezifikation

## B1. Kern-Loop, Sitzungen, erste 10 Minuten

| Schleife | Länge | Inhalt |
|---|---|---|
| Moment | 1–3 s | Peek, Schuss, Hitmarker, Ding, Schadenszahl |
| Runde | 20–60 s | ein Leben, Banner (CLUTCH!/ACE!/FLAWLESS!) |
| Match | 3–5 min | Erster auf 4 Runden; Ergebnis mit füllenden Balken (XP, Coins, Meisterschaft, Pass, Quests) |
| Sitzung | 20–40 min | „Nochmal spielen“ / Auto-Requeue, Krone, Freischaltungen |
| Tag | – | 3 Tagesquests, Login-Kalender, Erster-Sieg-Bonus, Gratis-Glücksrad, Mutator des Tages, Tages-Shop |
| Woche | – | 5 Wochenquests + Wochen-Truhe, Wochen-Bestenliste |
| Saison | 8 Wochen | Clutch Pass (30 Stufen), Saison-Daten in `Config/Season.luau` |

### B1.1 FTUE (erste Minuten; jeder Schritt → `MetricsService.Funnel`)
| Schritt | Zeit | Was passiert | Funnel |
|---|---|---|---|
| 1 | 0:00 | Spawn am Brunnen. 3 Karten: „Duelle!“, „Alles erspielbar“, „Fair: kein Pay-to-Win“. Knopf **„Erstes Duell!“** + „Überspringen“. | 1 Joined, 2 WelcomeSeen |
| 2 | 0:15 | Tutorial-Match: Practice 1v1 gegen **Rookie-Bot** auf PillarBox, Erster auf 3. 3 Hinweis-Karten (Bewegen/Zielen+Schießen, Nachladen/Wechseln, Rutschen). Rookie verfehlt die ersten 2 Schüsse jeder Runde. | 3 TutorialStarted, 4 FirstShot |
| 3 | ~0:45 | Erster Pop: „POPPED!“-Banner + Konfetti. | 5 FirstKill |
| 4 | ~2:30 | Sieg (≈ 90 %). Ergebnis: +250 XP (→ Level 2), +300 Coins. | 6 TutorialDone, 7 FirstWin |
| 5 | ~2:40 | Pfeil-Tour: Locker → Shop („Hummel-MP 600 Coins – im Training gratis testen“) → Pads. | 8 TourDone |
| 6 | 3–10 min | Matches 1–3 (echt) gegen Rookie-Bots oder Neulinge. Starter-Pack-Karte **einmal** im Ergebnis des ersten echten Siegs (großer „Später“-Knopf). | 9 FirstRealMatch, 10 ThirdMatch |
| 7 | ~12 min | Erste eigene Waffe bezahlbar; Anfänger-Kette führt weiter. | 11 FirstWeaponBought |

Wer loggt: Schritt 1 `MetricsService` beim Join · 2 und 8 über `Request("TutorialFlag")` (WP1 leitet per pcall weiter) · 3–7 `MatchService` ·
9–10 `ProgressionService` bei Match-Ende · 11 `ShopService` beim ersten Waffenkauf. Alle Aufrufe über `pcall`.

## B2. Lobby „Clutch Plaza“ (Code-gebaut, ≤ 2.500 Parts inkl. Crown Ring ≤ 400 und Range ≤ 400)

Welt-Koordinaten (X Ost, Z Süd, Boden-Oberkante Y = 0). Hauptboden X −130..130, Z −110..110; Range-Anbau
X −200..−130, Z −56..56. Der Boden hat ein Loch für den Crown Ring (X 70..120, Z −25..25), daher aus 5 Stücken:
West (−30,−0.5,0) 200×1×220 · Nord-Ost (100,−0.5,−67.5) 60×1×85 · Süd-Ost (100,−0.5,67.5) 60×1×85 ·
Ost (125,−0.5,0) 10×1×50 · Range-Anbau (−165,−0.5,0) 70×1×112. Rand: sichtbarer Zaun 3 hoch + unsichtbare
Barriere 60 hoch (Gruppe `ArenaBarrier`, `CanQuery=false`).

| Zone | Mitte (X,Z) | Inhalt (Maße in Studs) |
|---|---|---|
| Spawn-Platz | (0,0) | Brunnen: Zylinder Ø8 h1.5 + Ø4 h4 Wasserblau + Konfetti-Emitter (Rate 4). 6 `SpawnLocation` (Neutral, 6×1×6) auf Ring r 16 bei 0°/60°/…/300°. |
| Duell-Halle | (0,−75) | Bodenfläche Navy 140×0.1×60 bei (0,0.05,−75). Schild „DUELLE / DUELS“ bei (0,14,−50). **9 Pads** (B3.2): Reihe 1 bei Z −60: P1 1v1 (−48), P2 1v1 (−16), P3 1v1 (16), P4 2v2 (48); Reihe 2 bei Z −82: P5 2v2 (−48), P6 3v3 (−16), P7 4v4 (16), P8 Mutator (48); P9 FFA-Kreis bei (0,−100). Großer Block-Schriftzug „CLUTCH CLASH“ bei (0,16,−108). |
| Crown Ring | (95,0) | Arena-Grube 50×50, 6 tief (Map `CrownRing`, B8.3.7), Welt-Ursprung der Map (95,−6,0). Glas-Geländer 8 hoch rundum. Tribünen Nord (95,1.5,−32) 50×3×4 + (95,3,−35) 50×6×2 und Süd gespiegelt. **Herausforderer-Linie**: 6 Neon-Kreise r 1.6 bei X 64, Z −10/−6/−2/2/6/10. **Königs-Tafel** 20×10 (SurfaceGui) bei (128,10,0) Blick nach Westen: Avatar-Kopf, Name, Serie. |
| Training / Range | (−131,0) | Zone X −200..−62, Z −56..56. Schusslinie X = −66 (Blick nach −X). 6 Bahnen, Mitten Z −35/−21/−7/7/21/35, Trenner 1 hoch bei Z ±42/±28/±14/0 von X −70 bis −198. Puppen je Bahn bei X −81 (15 Studs), −96 (30), −126 (60), −166 (100). 2 Schiene-Puppen (Bahn 3 und 4, X −110, pendeln Z ±5). Rückwand X −199. **Bot-Duell-Kabine**: 4 Pads 4×0.2×4 bei Z 48, X −92/−84/−76/−68 (Leicht/Normal/Schwer/Wahnsinn). Waffen-Regal 30×8×1 bei (−64,4,−52) (öffnet Training-UI). |
| Shop-Straße | (0,70) | Kiosk-Buden 8×8×6 mit `ProximityPrompt` (Attribut `Window`): Shop (−30,70), Locker (−10,70), Pass (34,70), Quests (52,62), Täglich (Kalender+Rad) (−52,62). **Kisten-Automat** 12×16×12 bei (12,74) (nur für Spieler mit `RandomAllowed == true` sichtbar, B20.2). |
| Bestenlisten | Südrand Z 104 | 6 Tafeln 20×12 (Mitte Y 8), Blick nach Norden, bei X −75/−45/−15/15/45/75 (B16.9). |
| VIP-Balkon | (−70,−90) | Plattform 40×1×24 auf Y 14, Treppe bei (−70,·,−74); „VIP-Tür“ 6×8×1 bei (−70,4,−70): Server `CanCollide=true`, VIP-Clients setzen lokal `CanCollide=false`. Rein kosmetisch. |

**Lobby-Regeln:** Kamera Classic (3rd Person, Zoom max 14). Keine Waffen/kein PvP außer in der Range (nur gegen Puppen)
und im Crown Ring (nur die zwei Kämpfer). Spieler kollidieren in der Lobby nicht miteinander (Gruppe `LobbyPlayers`).
Gehen 16, Sprinten 22. Jede Kiosk-Bude öffnet dasselbe Fenster wie der HUD-Knopf (Handy-Spieler müssen nicht laufen).

## B3. Warteschlangen & Pads (ein Pool pro Modus – Must-Fix „Queues bündeln“)

### B3.1 Prinzip
- Pro Modus gibt es **genau eine virtuelle Warteschlange**. Pads und das PLAY-Menü sind nur **Eingänge** in diese Schlange.
- Ein **Eintrag** = 1..TeamSize Spieler, die ins selbe Team müssen (Pad-Hälfte oder später Party).
- Zwei Einträge auf **gegenüberliegenden Hälften desselben Pads** sind als Gegner fest gekoppelt (Freunde-Duell).
- **Matcher** (2 Hz) pro Modus, Reihenfolge:
  1. Volle Pads (beide Hälften voll) → sofort Match.
  2. Menschen kombinieren (über Pads und PLAY-Menü hinweg), älteste zuerst, Regeln:
     - gleiche Eingabegruppe bevorzugt (KBM | Touch+Gamepad) für die ersten `InputMatchSeconds = 6` s,
     - MMR-Fenster ±200, +50 alle 3 s,
     - **Neulings-Schutz:** Spieler mit < 5 Matches treffen nur Spieler mit < 15 Matches oder Bots.
  3. Nach `BotFillSeconds = 8` s ab dem ältesten menschlichen Eintrag (Studio 2 s; 3 s wenn ein Rookie wartet)
     oder wenn ein Mitglied „**Bots jetzt**“ drückt (frühestens nach 3 s): restliche Plätze mit Bots füllen.
  4. Kein freier Arena-Slot → Eintrag wartet, Anzeige „Arenen voll – gleich geht's los“ (Bot-Timer pausiert).
     Bot-Budget erschöpft → „Bots beschäftigt – gleich geht's los“ (kein Fehler, nur Warten).
- Spieler können in der Range weiterschießen, während sie warten („Queue while you train“).
- Anzeige überall: „**N Spieler suchen**“ (pro Modus), „BOT IN 6“.
- Ein Spieler ist in höchstens **einer** Schlange. Pad verlassen (1.5 s außerhalb des Sitzkreises) = Schlange verlassen.

### B3.2 Pads (6 Typen, 9 Pads)
| Pad | Modus | Farbe | Größe | Sitze pro Hälfte |
|---|---|---|---|---|
| P1–P3 | `Duel1` | Grün `90,220,110` | 20×0.6×12 | 1 |
| P4–P5 | `Duel2` | Blau `60,140,255` | 20×0.6×12 | 2 |
| P6 | `Duel3` | Lila `170,90,255` | 20×0.6×12 | 3 |
| P7 | `Duel4` | Rot `255,80,80` | 20×0.6×12 | 4 |
| P8 | `Mutator` | Gelb `255,210,40` (Regenbogen-Neon-Rand) | 20×0.6×12 | 1 |
| P9 | `FFA` | Pink `255,60,170` | Kreis Ø12 | 8 Punkte auf Ring r 4 |

- Pad-Hälfte A = X −10..0 (Orange-Neon), B = X 0..10 (Blau-Neon). Sitzkreise r 1.6 Neon, auf X = ±5 der Hälfte,
  Z-Versatz je nach Anzahl: 1 → 0; 2 → ±2; 3 → −3.5/0/3.5; 4 → −4.5/−1.5/1.5/4.5.
- Sitz besetzt, wenn HRP horizontal ≤ 2.2 Studs vom Sitzmittelpunkt und |ΔY| < 5. Scan 4 Hz über Positionen (kein `Touched`).
- Pad-Zustand nur als **Attribute** am Pad-Part (ändern nur bei Änderung): `Mode`, `PadId`, `NeedA`, `NeedB`,
  `CountA`, `CountB`, `BotAt` (Server-Zeit), `Searching`, `Phase` ("Idle"|"Waiting"|"Vote"|"Full"|"Held").
  Der Client (WP5 `QueueUI`) zeichnet die **lokalisierte** BillboardGui selbst.
- Wartende Bot-Plätze erscheinen client-seitig als halbtransparente Hologramm-Puppen auf den Kreisen.

### B3.3 PLAY-Menü (HUD, unten Mitte, groß, gelb)
Einträge: Duell 1v1 / 2v2 / 3v3 / 4v4, Mutator des Tages, FFA-Brawl, Krone herausfordern, Training (Teleport),
Gegen Bots üben (Schwierigkeit wählen). Jeder Eintrag zeigt „N suchen“. Auswahl = `Request("QueueJoin", mode)`.
„MATCH GEFUNDEN!“-Popup = Beginn der Kartenwahl.

## B4. Modi (alle Parameter in `Config.Modes`)

| Key | Name DE / EN | Teams | Regelwerk | Sieg | Rundenzeit | Overtime | Rundenlimit | Kartenwahl | Bots |
|---|---|---|---|---|---|---|---|---|---|
| `Duel1` | Duell / Duel | 1v1 | Rounds | Erster auf 4 | 60 s | 15 s | 9 | ja | nach 8 s |
| `Duel2` | Duell | 2v2 | Rounds | Erster auf 4 | 75 s | 15 s | 9 | ja | nach 8 s |
| `Duel3` | Duell | 3v3 | Rounds | Erster auf 4 | 90 s | 15 s | 9 | ja | nach 8 s |
| `Duel4` | Duell | 4v4 | Rounds | Erster auf 4 | 90 s | 15 s | 9 | ja | nach 8 s |
| `Mutator` | Mutator-Duell / Mutator Duel | 1v1 | Rounds + Tages-Mutator | Erster auf 3 | 50 s | 15 s | 7 | ja | nach 8 s |
| `Crown` | Kronen-Duell / Crown Duel | 1v1, Gewinner bleibt | Rounds | Erster auf 2 | 45 s | 10 s | 5 | nein (CrownRing) | Bot-Herausforderer nach 15 s Leerlauf |
| `Practice` | Training gegen Bots / Bot Practice | 1v1 vs Bot | Rounds | Erster auf 3 | 60 s | 15 s | 7 | nein (zufällige 1v1-Map) | immer |
| `FFA` | FFA-Brawl / FFA Brawl | 2–8 einzeln | Respawn | 25 Punkte (Kill 2, Assist 1) oder 5:00 | – | – | – | ja | auffüllen auf 6 |

- **Tutorial** = `Practice` mit `Tutorial=true` (Map PillarBox, Rookie, Hinweise, Sonderbelohnung B1.1).
- **Crown-Regeln:** Beitreten = auf einen Kreis der Herausforderer-Linie stellen oder PLAY → „Krone herausfordern“. König behält den Platz;
  HP zwischen Herausforderern voll. Herausforderer-Linie max. 6. Verlierer wird an den Rand der Grube (Lobby-Ebene, X 64) teleportiert.
  Kein menschlicher Herausforderer 15 s lang → Bot (Serie 0–2 Normal, 3–5 Hard, ≥ 6 Insane).
  Kein König, aber ein Herausforderer → nach 8 s ohne zweiten Menschen kämpft ein Normal-Bot; der Sieger wird König.
  Nie Bot gegen Bot. König verlässt → nächste zwei in der Linie. Krone (Part-Modell, 7 Teile, Foil-Gold) am Kopf,
  Serie im Namensschild, Lobby-Ansage bei Serie 3/5/10. Belohnung pro Verteidigung: **gegen Menschen +40 Coins +15 XP**,
  gegen Bots +10 Coins.
- **FFA:** eigenes Loadout, Respawn 3 s, Spawn-Schutz 1.5 s (endet beim ersten Schuss), Regeneration 12 HP/s nach 5 s
  ohne Schaden, Utility mit Abklingzeit. Drop-in: läuft ein FFA mit < 8 Menschen und < 4:00 Spielzeit, steigt ein neuer
  Mensch sofort ein (ersetzt einen Bot, wenn ≥ 6 Teilnehmer). Maps: BlockYard, NeonGrid, CandyDocks, SkyGarden.

## B5. Match-Ablauf & Timer (Regelwerk „Rounds“)

| Phase | Dauer | Details |
|---|---|---|
| Vote | 5 s | Startet, sobald das Match gebildet ist (Pad voll / Matcher). Spieler bleiben in der Lobby. 3 Karten = 3 verschiedene Maps passend zur Teamgröße, nie die letzten 2 dieses Servers für diesen Modus, je mit Stimmung („SUNSET BlockYard“), dazu „Zufall“ (reichen die Maps nicht, wird die Sperre der letzten 2 gelockert; gibt es nur 1–2 passende Maps, entsprechend weniger Karten). Mehrheit gewinnt, Gleichstand zufällig. Bots stimmen nach 1–3 s zufällig. **Übersprungen** bei Crown, Practice, Tutorial, Rematch. Wer in dieser Phase das Pad verlässt, fliegt raus und wird durch Bot ersetzt. |
| Load | ≤ 4 s | `ArenaService.Acquire` (warmer Slot bevorzugt). Teleport aller Combatants an ihre Spawns (+3 Y), HRP verankert. Client wartet bis `Slot_i.Map` mit Attribut `BuildId` existiert, sendet `ArenaReady(buildId)`. Weiter, wenn alle Menschen bereit sind oder nach 4 s. |
| Intro | 2 s | „BLAZE vs FROST“: Namen, Level, Titel, Finisher-Name, **Gegner-Loadout-Vorschau** (4 Icons je Gegner). |
| Prep | Runde 1: 4 s, sonst 3 s | Verankert am Spawn, umsehen und Waffe wechseln erlaubt. Loadout-Fenster (Taste L / Knopf) offen. „3-2-1-POP!“. Alle Menschen „BEREIT“ → Prep endet nach ≥ 1 s. |
| Live | Rundenzeit des Modus | Ein Leben. Gepoppte schauen zu. |
| Overtime | ≤ 15 s (Crown 10 s) | B6 |
| RoundEnd | 2.5 s | Banner, Runden-MVP (meister Schaden), Punktestand. |
| MatchEnd | 10 s | Ergebnis (B14.6), GG, Loben, **Rematch** (alle Menschen stimmen zu → gleiche Teams, gleiche Arena, gleiche Map, sofort Prep), Auto-Requeue-Haken. Danach alle zurück in die Lobby. |

- **Zeit bis zum ersten Schuss** (volles Pad): Vote 5 + Load ~0.5 (warm) bis 4 (kalt) + Intro 2 + Prep 4 = **11.5–15 s**.
  Rematch: Prep 4 s.
- **Regelwerk „Respawn“ (FFA):** Vote 5 → Load ≤ 4 → Intro 2 → Live 300 s → MatchEnd 10 s.
- **Loadout-Wechsel:** in Prep und RoundEnd beliebig (Ranked v1.1: 2 pro Match).
- **AFK:** „ohne Eingabe“ = kein `Look`/`Fire`/`WeaponAction`-Paket (`ReplicationService.LastInput`) **und** < 2 Studs Bewegung. 20 s in einer Live-Runde → Warnung; 30 s → zurück in die Lobby, Bot übernimmt (Team-Modi) bzw.
  Aufgabe (1v1). Gilt auch in Bot-Matches; AFK schaltet Auto-Requeue ab.
- **Verlassen:** Verlierer-Wertung + 60 s Pad-Sperre. 1v1: Gegner gewinnt voll. Team-Modi: Bot ersetzt nach 10 s.
- **Reset-Knopf** im Match aus (`StarterGui:SetCore("ResetButtonCallback", false)`, mit Wiederholung bis Erfolg).

## B6. Runden-Auflösung, Overtime, Sudden Death, Anti-Camp, Banner

1. Runde endet sofort, wenn nur noch ein Team lebende Mitglieder hat.
2. Zeit abgelaufen, ≥ 2 Teams leben → **OVERTIME**: Neon-Zylinder an `Map.Zone` (Radius 8, `forcefield_vortex_main.dds`-Ring, pulsiert).
   - Ein Team **hält**, wenn ≥ 1 lebendes Mitglied in der Zone und kein Gegner.
   - Fortschritt +1/s beim Halten, eingefroren bei umkämpft, −0.5/s wenn leer. **3 s** gesammelt = Rundensieg.
3. Overtime vorbei ohne Einnahme → Tiebreak in Reihenfolge: (a) mehr lebende Spieler, (b) höhere Summe der HP,
   (c) mehr Schaden in dieser Runde, (d) **Unentschieden** (kein Punkt).
4. **Rundenlimit** `2×RoundsToWin+1` erreicht ohne Sieger → mehr Rundensiege gewinnt; bei Gleichstand **Sudden Death**:
   30 s, alle starten mit 50 HP, Zone von Anfang an offen (3 s halten gewinnt). Danach Tiebreak 3a–c, sonst Match-Unentschieden
   (alle bekommen Niederlagen-Belohnung +10 %, kein MMR-Wechsel).
5. **Anti-Camp-Radar:** 1v1: 30 s ohne Schaden (Team-Modi 40 s) → jeder Gegner leuchtet 1 s durch Wände (nur für die
   Gegenseite; Highlight auf `AlwaysOnTop` umschalten), danach alle 10 s erneut bis Schaden fällt.
6. **Banner** (Server setzt Flags in `RoundEnd`/`MatchEnd`): CLUTCH! (als Letzter gegen ≥ 2 gewonnen), ACE! (ein Spieler
   hat alle Gegner einer Runde gepoppt, ab 3v3), FLAWLESS! (Team ohne Schaden), COMEBACK! (Match nach 0–3 gewonnen),
   MATCH POINT (ein Team braucht noch 1 Runde).

## B7. Mutatoren (Daten in `Config.Modes.Mutators`)

| Key | Name DE / EN | Wirkung (ContextRules) |
|---|---|---|
| `MoonJump` | Mondsprung / Moon Jump | `GravityLift = 0.55`: Client des Besitzers hängt `VectorForce` (55 % des Gewichts) an das eigene HRP, Server bei Bots. Anti-Cheat Vertikal-Toleranz ×2.5. |
| `HeadsOnly` | Nur Kopftreffer / Headshots Only | `HeadOnly = true`: Körpertreffer 0 Schaden (graue „KÖRPER“-Markierung). Nahkampf und Explosionen wirken normal. |
| `BigHeads` | Großkopf / Big Heads | `HeadRadiusMult = 1.6` (nur analytisch). Client zeichnet halbtransparenten Team-Ball um jeden Kopf (Attribut `BigHead`). **Kein echtes Kopf-Resize.** |
| `Turbo` | Turbo | `SpeedMult 1.35, IntervalMult 0.8, ReloadMult 0.7`. |
| `MeleeMayhem` | Nahkampf-Chaos / Melee Mayhem | `AllowedSlots = {Melee, Utility}`, `SpeedMult 1.2`. |
| `SnipersOnly` | Nur Scharfschützen / Snipers Only | `ForcedLoadout = {Longshot, HandCannon, BoxingGloves, SmokeBomb}`. |
| `LuckyLoadout` | Glücks-Loadout / Lucky Loadout | `RandomLoadout = true`: jede Runde zufälliges Loadout aus allen 15, für beide Seiten gleich, Besitz egal (Gratis-Probe). |
| `Instapop` | Sofort-Pop / Instapop | `ForcedLoadout = {Longshot, PipPistol, BoxingGloves, PopGrenade}`, `DamageMult 5`. |

Tages-Mutator = `Rotation[(Util.UtcDay() % #Rotation) + 1]`, Admin-Override (lokal oder global). Rotation:
`{"MoonJump","HeadsOnly","Turbo","BigHeads","MeleeMayhem","SnipersOnly","LuckyLoadout","Instapop"}`.

## B8. Maps

### B8.1 Datenformat & Bauregeln (WP2)
- Datei je Map: `src/server/World/Maps/<Key>.luau`, gibt eine Tabelle `MapLayout` zurück (Typ in C4).
- **Lokales Koordinatensystem:** Ursprung = Bodenmitte, **Boden-Oberkante Y = 0**, Team A spawnt bei −Z, Team B bei +Z.
  Positionen in den Tabellen unten = **Mittelpunkt** des Teils, Größen = (X,Y,Z).
- **Punktsymmetrie:** Die Datei beschreibt nur die A-Hälfte (z < 0, plus Teile auf z = 0 mit `Mirror=true`).
  Der Builder erzeugt zu jedem Teil mit `Mirror ~= false` die Kopie `(−x, y, −z)`, um 180° um Y gedreht.
  Teile mit `Center = true` werden genau einmal gebaut. Spawns B = gespiegelte Spawns A (Blick nach −Z).
- **Automatisch** pro Map (außer `CustomBounds`): 4 unsichtbare Seitenbarrieren + Decke bei Y 40 aus `Size`
  (Gruppe `ArenaBarrier`, `CanQuery=false`, Transparency 1). KillY = −40.
- Rampen (`Wedge`): Angabe „hohes Ende bei z = …“; der Builder dreht die WedgePart entsprechend.
- Deko-Teile: `CanTouch=false`, `CastShadow=false`. Alle Teile `Anchored`. Ganze Map **unparented** bauen, dann einmal parenten.
- **Nav-Graph** (automatisch, WP2 `NavBuilder`): Beim Template-Bau steht die Map kurz im Workspace an einer Staging-Position
  (0, 3000, 0). Raster 6 Studs: Ray nach unten (Boden finden), Kopffreiheit ≥ 5.5 prüfen, Kanten zu 8 Nachbarn per Ray
  (Höhenunterschied ≤ 4.5 oder Rampe), dazu manuelle `CoverNodes`. Unerreichbare Knoten → `warn` beim Boot.
  Ergebnis relativ zum Map-Ursprung gespeichert.
- Teilebudget: S ≤ 700, M ≤ 900, L ≤ 1.100 (Builder zählt, `warn` bei Überschreitung).

### B8.2 Licht-Stimmungen (`Config.Maps.Moods`, nur client-lokal, WP2 `ArenaLook`)
| Key | ClockTime | Ambient / OutdoorAmbient | Atmosphere Density/Haze/Color | Bloom Int/Size/Thr | ColorCorrection |
|---|---|---|---|---|---|
| `Day` | 14 | 140,140,150 / 150,150,160 | 0.32 / 1.0 / 199,210,230 | 0.5 / 24 / 1.6 | Sat 0.15, Con 0.05 |
| `Sunset` | 17.6 | 170,120,100 / 190,130,110 | 0.35 / 1.5 / 255,190,150 | 0.6 / 24 / 1.5 | Sat 0.2, Tint 255,235,215 |
| `NeonNight` | 0.5 | 60,60,90 / 40,40,70 | 0.32 / 0.8 / 60,60,120 | 1.0 / 32 / 1.2 | Sat 0.25 |
| `Fog` | 12 | 150,150,150 / 150,150,155 | 0.45 / 2.5 / 200,200,205 | 0.3 / 24 / 1.8 | Sat −0.1 |
| `Snowy` | 13 | 170,180,200 / 180,190,210 | 0.38 / 1.5 / 220,230,245 | 0.4 / 24 / 1.6 | Sat 0.05 + Schnee-Emitter (smoke_main.dds, weiß, Size 0.15, Rate 60, an Kamera) |

Da `Lighting.FogEnd` bei vorhandener Atmosphere ignoriert wird, **versteckt der Client alle fremden Welten** (B9.4).

### B8.3 Die 7 Arenen

#### B8.3.1 `PillarBox` – Säulenkiste (S, 72×72, Wände 14) · Teams 1–2 · Modi Duel1, Duel2, Mutator, Practice · Stimmungen Day 40 / Sunset 30 / NeonNight 15 / Fog 15
| Teil | Mitte | Größe | Farbe/Material | Spiegel |
|---|---|---|---|---|
| Boden | (0,−0.5,0) | 72×1×72 | Cream | Center |
| Wände N/S | (0,7,±37) | 76×14×2 | Mint | Center (2) |
| Wände W/O | (±37,7,0) | 2×14×72 | Mint | Center (2) |
| Mittel-Plattform | (0,2,0) | 16×4×16 | Lilac | Center |
| Rampe | (0,2,−13) | 6×4×10, hohes Ende z = −8 | Lilac | ja |
| Ecksäule P1 | (−18,5,−18) | 4×10×4 | Pink | ja |
| Ecksäule P2 | (18,7,−18) | 4×14×4 | Pink | ja |
| Seitensäule P3 | (−20,3,0) | 4×6×4 | Sand | ja (→ (20,3,0)) |
| Kiste C1 | (−10,1.5,−27) | 6×3×3 | Sand | ja |
| Kiste C2 | (13,1.5,−25) | 3×3×6 | Sand | ja |
| Halbwand W1 | (−28,2.5,−8) | 2×5×10 | Mint | ja |
| Rutsch-Deckung L1 | (6,1,−20) | 4×2×2 | Charcoal | ja |
- Zone (0,4,0). Spawns A (Blick +Z): (−6,3,−32), (6,3,−32), (−12,3,−33), (12,3,−33).
- CoverNodes A: (−18,0,−22), (−10,0,−30), (−31,0,−8), (18,0,−22), (13,0,−29).

#### B8.3.2 `BlockYard` – Bauklotz-Hof (M, 80×120, Wände 16) · Teams 1–4 · Duel1–4, Mutator, Practice, FFA · Day 45 / Sunset 35 / Fog 20
| Teil | Mitte | Größe | Farbe | Spiegel |
|---|---|---|---|---|
| Boden | (0,−0.5,0) | 80×1×120 | Cream | Center |
| Wände | (0,8,±61) / (±41,8,0) | 84×16×2 / 2×16×120 | White 235,238,245 | Center |
| Turm | (0,4,0) | 16×8×16 | Lilac | Center |
| Brüstungen | (±7.5,9,0) | 1×2×16 | Charcoal | Center (2) |
| Rampe R1 | (0,4,−15) | 6×8×14, hohes Ende z = −8 | Lilac | ja |
| Buchstabe A | (−24,4,−32) | 8×8×8, SurfaceGui „A“ auf ±Z | Rot 255,90,90 | ja |
| Buchstabe B | (22,3,−40) | 6×6×6, „B“ | Blau 60,140,255 | ja |
| Buchstabe C | (−8,2,−46) | 4×4×4, „C“ | Gelb 255,210,40 | ja |
| Gassenwand 1 | (−32,4,−22) | 2×8×10 | Mint | ja |
| Gassenwand 2 | (−32,4,−2) | 2×8×10 | Mint | ja |
| Bogen-Sturz | (−32,7,−12) | 2×2×10 | Mint | ja |
| Deckung D1 | (12,1.5,−22) | 8×3×2 | Sand | ja |
| Deckung D2 | (−14,1.5,−16) | 2×3×8 | Sand | ja |
| Kisten | (28,2,−18), (24,2,−54), (−20,2,−52) | je 4×4×4 | Sand | ja |
- Zone (0,8,0) (Turmdach). Spawns A: (−9,3,−54), (−3,3,−54), (3,3,−54), (9,3,−54).
- FFA-Spawns (12, Center): (−27,3,−50), (27,3,−50), (−27,3,50), (27,3,50), (0,3,−56), (0,3,56), (−27,3,0), (27,3,0), (−14,3,−32), (14,3,32), (14,3,−36), (−14,3,36).
- CoverNodes A: (−24,0,−37), (22,0,−44), (−35,0,−22), (12,0,−24), (−14,0,−19), (0,0,−24).

#### B8.3.3 `NeonGrid` – Neon-Raster (S/M, 96×96, Wände 14) · Teams 1–2 · Duel1, Duel2, Mutator, Practice, FFA · **Stimmung fest NeonNight**
| Teil | Mitte | Größe | Farbe | Spiegel |
|---|---|---|---|---|
| Boden-Platten | (0,−0.5,−30) | 96×1×36 | Navy | ja |
| Boden-Platten Seite | (−30,−0.5,0) | 36×1×24 | Navy | ja |
| Grube-Boden | (0,−4.5,0) | 24×1×24 | Navy | Center |
| Grubenwand N (2 Stücke, Lücke x −9..−3) | (−10.5,−2,−12.5) / (4.5,−2,−12.5) | 3×4×1 / 15×4×1 | Charcoal | ja |
| Grubenwand W | (−12.5,−2,0) | 1×4×24 | Charcoal | ja |
| Gruben-Rampe | (−6,−2,−8) | 6×4×8, hohes Ende z = −12 | Charcoal | ja |
| Neon-Linien längs X | z = ±16, ±24, ±32, ±40, y 0.02 | 96×0.05×0.3 | Neon 0,230,255 | Center (8) |
| Neon-Linien längs Z | x = ±16, ±24, ±32, ±40 | 0.3×0.05×96 | Neon 0,230,255 | Center (8) |
| Wände | (0,7,±49) / (±49,7,0) | 100×14×2 / 2×14×96 | Charcoal | Center |
| Niedrige Mauer LW1 | (−20,1.75,−26) | 12×3.5×1.5 | Charcoal + Neon-Kante | ja |
| LW2 | (18,1.75,−32) | 1.5×3.5×12 | dito | ja |
| LW3 | (−36,1.75,−6) | 1.5×3.5×10 | dito | ja |
| LW4 | (6,1.75,−20) | 10×3.5×1.5 | dito | ja |
| Pylon PY1 | (−26,8,−38) | 4×16×4 | Charcoal + Neon Pink Streifen | ja |
| Pylon PY2 | (30,8,−18) | 4×16×4 | dito | ja |
| Würfel | (−38,2,−34) / (36,1.5,−40) | 4×4×4 / 3×3×3 | Lilac | ja |
- Zone (0,−4,0) (Grube). Spawns A: (−6,3,−42), (6,3,−42), (−12,3,−40), (12,3,−40).
- FFA (12): (±40,3,±40) [4], (0,3,−44), (0,3,44), (−42,3,0), (42,3,0), (−20,3,−8), (20,3,8), (20,3,−8), (−20,3,8).
- CoverNodes A: hinter LW1–LW4, PY1, PY2, Grubenmitte (0,−4,0).

#### B8.3.4 `CandyDocks` – Zuckerhafen (L, 64×150, Wände 18) · Teams 2–4 · Duel2–4, FFA · Day 40 / Sunset 35 / Fog 25
| Teil | Mitte | Größe | Farbe | Spiegel |
|---|---|---|---|---|
| Steg A | (0,−0.5,−41.5) | 64×1×67 (z −75..−8) | WoodPlanks 200,160,120 | ja |
| Kanal-Bett | (0,−2.5,0) | 64×1×16 (Oberkante −2) | 90,190,255 SmoothPlastic | Center |
| Kanal-Kante | (0,−1,−8.5) | 64×2×1 | Charcoal | ja |
| Brücken | (−18,−0.25,0) / (18,−0.25,0) | 6×0.5×16 | WoodPlanks | Center (2) |
| Floß | (0,−1,0) | 10×2×10 | WoodPlanks | Center |
| Wände | (0,9,±76) / (±33,9,0) | 68×18×2 / 2×18×150 | Pink | Center |
| Container K1 | (−20,4.25,−40) | 8×8.5×20 | Pink | ja |
| Container K2 | (10,4.25,−30) | 20×8.5×8 | Mint | ja |
| Stapel K3 | (24,4.25,−56) + (24,12.75,−56) | je 8×8.5×20 | Gelb / Lilac | ja |
| Kisten-Labyrinth | (−6,2,−18), (4,2,−22), (−2,2,−26), (8,2,−14) | je 4×4×4 | Sand | ja |
| Zuckerstangen-Kran | Mast (−28,10,−20) aus 5 Segmenten 2×4×2 rot/weiß; Arm (−20,19,−20) 16×1.5×1.5 rot | – | – | ja |
| Poller | (−28,1,−10), (8,1,−10) | Zylinder Ø1.5 h2 | Charcoal | ja |
- Zone (0,0,0) (Floß). Spawns A: (−9,3,−68), (−3,3,−68), (3,3,−68), (9,3,−68).
- FFA (12): (−26,3,−66), (16,3,−70), (−16,3,70), (26,3,66), (0,3,−60), (0,3,60), (−28,3,−28), (28,3,28), (28,3,−28), (−28,3,28), (14,3,−44), (−14,3,44).
- CoverNodes A: hinter K1, K2, K3, Labyrinth (0,0,−20), Floß.
- Lange Randgassen (x ±28) = Scharfschützen-Linien; Mitte = Nahkampf-Labyrinth.

#### B8.3.5 `SnowFort` – Schneefestung (M, 90×120, Wände 16) · Teams 2–4 · Duel2–4 · **Stimmung fest Snowy**
| Teil | Mitte | Größe | Farbe | Spiegel |
|---|---|---|---|---|
| Boden | (0,−0.5,0) | 90×1×120 | 240,245,255 SmoothPlastic | Center |
| Wände | (0,8,±61) / (±46,8,0) | 94×16×2 / 2×16×120 | 225,235,250 | Center |
| Teich (Deko) | (0,0.1,0) | Zylinder Ø24 h0.2 | 180,220,255 SmoothPlastic (kein Ice!) | Center |
| Frontwand FW1/FW2/FW3 | (−14.5,4,−40) / (0,4,−40) / (14.5,4,−40) | 11×8×2 / 14×8×2 / 11×8×2 | 230,240,255 | ja |
| Schlitz unten/oben | (±8,2,−40) / (±8,6.75,−40) | 2×4×2 / 2×2.5×2 (Sehschlitz Y 4..5.5) | dito | ja (je 2) |
| Seitenwände | (±21,4,−47) | 2×8×16 | dito | ja (je 2) |
| Wehrgang | (0,5.25,−42.5) | 40×0.5×3 (Oberkante 5.5) | 200,170,130 | ja |
| Rampe zum Wehrgang | (−16,2.75,−49) | 4×5.5×10, hohes Ende z = −44 | dito | ja |
| Schneeball-Haufen | Ball Ø4 (−12,1.6,−18), Ø3 (−10,1.2,−16), Ø5 (14,2,−24), Ø3 (16,1.2,−21) | – | Weiß | ja |
| Tannen | Stamm Zylinder Ø1.5 h4 bei (−32,2,−22) und (28,2,−8); Kronen 3 Zylinder Ø6/4.5/3 h2 bei Y 5/7/9 | – | 120,80,50 / 60,140,90 | ja |
| Schneemauern | (−24,1.5,−26) 10×3×2; (22,1.5,−32) 2×3×8; (6,1.5,−14) 6×3×2 | – | Weiß | ja |
- Zone (0,0,0). Spawns A (im Fort): (−9,3,−50), (−3,3,−50), (3,3,−50), (9,3,−50).
- CoverNodes A: hinter FW1, FW3, Wehrgang (0,5.5,−42.5), Schneeball-Haufen, Schneemauern.

#### B8.3.6 `SkyGarden` – Himmelsgarten (M, Inseln, Leere darunter) · Teams 1–3 · Duel1–3, Mutator, Practice, FFA · Day 45 / Sunset 35 / NeonNight 20 · `CustomBounds`: Barrieren x ±70, z ±85, Decke Y 50
Jede Insel = Gras-Platte (1 dick, 110,200,110) + Erd-Unterseite (3 dick, 150,110,80).
| Teil | Mitte | Größe | Spiegel |
|---|---|---|---|
| Mittel-Insel | Gras (0,−0.5,0) 36×1×36; Erde (0,−2.5,0) 34×3×34 | – | Center |
| Pavillon | 4 Säulen (±5,4,±5) 1×8×1 weiß; Dach (0,8.5,0) 12×1×12 Pink | – | Center |
| Seiten-Insel | Gras (−36,−0.5,0) 14×1×14 + Erde | – | ja (→ +36) |
| Spawn-Insel A | Gras (0,−0.5,−48) 30×1×30; Erde (0,−2.5,−48) 28×3×28 | – | ja |
| Brücke A–Mitte | (0,−0.25,−25.5) 6×0.5×15 WoodPlanks | – | ja |
| Brücke Mitte–Seite | (−23.5,−0.25,0) 11×0.5×6 | – | ja |
| Diagonal-Brücke A–Seite | `CFrame.lookAt((−15,−0.25,−40),(−36,−0.25,−7))`, Länge 39, Breite 4 | – | ja |
| Hecken | (−8,1.5,−40) 6×3×2; (9,1.5,−52) 2×3×6; (−12,1.5,−8) 6×3×2; (10,1.5,−12) 2×3×6; (0,2,−61) 20×4×2 | Grün 70,150,80 | ja |
| Blumentöpfe | (−4,1.25,−14), (14,1.25,−4): Zylinder Ø3 h2.5 | Terracotta 200,110,80 | ja |
| Kiste Seiten-Insel | (−36,2,−3) 4×4×4 | Sand | ja |
- Zone (0,0,0) (im Pavillon). KillY = −40 (Sturz = Pop, gutgeschrieben dem letzten Schadensverursacher ≤ 8 s).
- Spawns A: (−5,3,−50), (5,3,−50), (−10,3,−46), (10,3,−46).
- FFA (12): (0,3,−52), (0,3,52), (−9,3,−44), (9,3,44), (9,3,−44), (−9,3,44), (−36,3,4), (36,3,−4), (−12,3,12), (12,3,−12), (−12,3,−12), (12,3,12).

#### B8.3.7 `CrownRing` – Kronen-Ring (fest in der Lobby, ≤ 400 Parts) · nur Modus Crown · Lobby-Licht
Map-Ursprung in Weltkoordinaten (95, −6, 0).
| Teil | Mitte | Größe | Farbe | Spiegel |
|---|---|---|---|---|
| Grubenboden | (0,−0.5,0) | 50×1×50 | Navy | Center |
| Grubenwände | (0,3,±26) / (±26,3,0) | 54×6×2 / 2×6×50 | Charcoal | Center |
| Glas-Geländer | (0,10,±26) / (±26,10,0) | 54×8×1 / 1×8×50 | Glass T 0.6 | Center |
| Unsichtbare Barriere | Seiten bis Y 40 + Decke | – | ArenaBarrier | Center |
| Mittelkiste | (0,2,0) | 4×4×4 | Foil Gold 255,200,60 | Center |
| Säulen | (−12,5,−12) und (12,5,−12) | 4×10×4 | Pink | ja |
| Niedrige Mauer | (0,1.5,−9) | 10×3×2 | Mint | ja |
- Zone (0,0,0) Radius 7 (um die Kiste). Spawns A: (0,3,−20), Reserve (−4,3,−20).
- Zuschauer: Lobby-Spieler ≤ 150 Studs von (95,0,0) erhalten FX, Projektile und Finisher dieses Kontexts.

## B9. Arena-Slot-System (mehrere Matches pro Server)

### B9.1 Plätze
- `Config.Server.ArenaSlots = 8`. Ursprung Slot i (1..8):
  `X = ((i−1) % 4 − 1.5) × 4000` → {−6000, −2000, 2000, 6000}; `Z = (i ≤ 4) and −4000 or 4000`; `Y = 0`.
  Lobby bei (0,0,0); nächster Slot ≥ 4.472 Studs entfernt. Alles innerhalb ±10k.
- **Vault** pro Slot: geschlossene Box 20×10×20 bei `Ursprung + (0, −250, 0)` (über FallenPartsDestroyHeight −500),
  Gruppe `Ghost`. Crown Ring Vault: (95, −250, 0).
- Ordner: `workspace.Arenas.Slot_i` (Folder, Attribute `State`, `BuildId`, `MapKey`), darin `Map` (Model).

### B9.2 Lebenszyklus
- **Boot:** Kollisionsgruppen registrieren (C12.6) → jede Map einmal als Template bauen (Staging (0,3000,0) im Workspace für
  Nav-Graph und Spawn-Prüfung) → nach `ServerStorage.MapTemplates` verschieben (nicht repliziert).
- **Acquire(mapKey, mood):** (1) freier Slot, der genau diese Map hat → sofort; (2) freier Slot ohne Map;
  (3) am längsten unbenutzter freier Slot → alte Map zerstören. Klonen, `PivotTo(Ursprung)`, Attribut `BuildId`
  (fortlaufend) **vor** dem Parenten setzen, **einmal** parenten. Zustände: `Free → Loading → Busy → Free`.
- **Release:** Slot wird `Free`, Map bleibt (warm).
- **Aufräumen** (alle 30 s): Slots `Free` mit Map, länger als `IdleMapSeconds = 180` ungenutzt, werden geleert, sobald mehr als
  `KeepWarmMaps = 3` warme freie Slots existieren.
- Alle 8 belegt → Warteschlange hält (B3.1).

### B9.3 Isolation
- Pro Kontext ein gecachtes `RaycastParams` nur mit der Map (`IncludeInstances = {Map}`) für Sichtlinien-Prüfungen.
- Fan-out nur an die Empfänger des Kontexts (Mitglieder + ggf. Crown-Zuschauer), nie `FireAllClients`.
- 3D-Sounds `RollOffMaxDistance ≤ 300`. Getrennte Zustandstabellen pro Match.

### B9.4 Sichtbarkeit (Must-Fix „fremde Arenen“)
Der Client (WP2 `ArenaLook.SetWorld`) zeigt **nur die eigene Welt**: In der Lobby/Range/Crown sind alle `Slot_i` versteckt;
im Match Slot k sind Lobby und alle anderen Slots versteckt. Verstecken = für alle Nachfahren lokal:
`BasePart.LocalTransparencyModifier = 1`, `SurfaceGui/BillboardGui.Enabled = false`, `ParticleEmitter/Beam/Trail/PointLight.Enabled = false`
(Originalwerte in schwacher Tabelle, Wiederherstellen beim Zeigen). Neue Nachfahren in versteckten Ordnern
(`DescendantAdded`) werden sofort mitversteckt. Zusätzlich Atmosphere-Dichte ≥ 0.32 in allen Stimmungen.
Spart auf dem Handy auch Render-Zeit.

### B9.5 Teilebudget Client (Must-Fix)
Lobby ≤ 2.500 + 8 Slots × ≤ 1.100 = **≤ 11.300** im schlimmsten Fall (alle 8 belegt), typisch ≤ 10.000
(warme Maps begrenzt auf 3 leere). Viewmodel ≤ 30, Finisher ≤ 25, Charm ≤ 8.

## B10. Bots

### B10.1 Wann
Pads/Schlangen nach `BotFillSeconds` (8 s; Studio 2 s; mit Rookie 3 s) oder „Bots jetzt“; FFA auffüllen auf 6;
Crown nach 15 s Leerlauf; Leaver/AFK-Ersatz in Team-Modi; Practice/Tutorial immer. **Nie** in Ranked (v1.1).
Obergrenzen: `MaxBots = 12` pro Server, `MaxBotsPerMatch = 7`.

### B10.2 Modell & Kosten
- Beim Boot in `pcall`: `Players:CreateHumanoidModelFromDescriptionAsync(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)`,
  einmal, dann geklont. Fallback: handgebautes R6-Rig (6 Parts, Motor6D mit R6-Namen, Humanoid) – gleitet ohne Animation.
- Pool von 12 Klonen in `ServerStorage.BotPool`. Nach Parenten in den Workspace: `HRP:SetNetworkOwner(nil)` (in pcall).
- `Humanoid:SetStateEnabled(false)` für Climbing, Swimming, Seated, Flying, Ragdoll, FallingDown, PlatformStanding.
- Zufällige BodyColors aus der Palette, Gesicht `rbxasset://textures/face.png`, Namensschild **„[BOT] Waffel“** (grau).
  CollectionService-Tag `Bot`, Attribute `CombatantId`, `Ctx`, `Team`, `Alive`, `IsBot=true`.
- Namen (`Config.Bots.Names`, 30): Waffel, Blinky, Pixel, Nudel, Turbo, Gizmo, Sprocket, Murmel, Keks, Bonbon, Kiwi, Fizz, Mochi,
  Nugget, Zappy, Biscuit, Mango, Pudding, Rakete, Socke, Toffee, Bolzen, Flummi, Knopf, Wolke, Brezel, Zimt, Quark, Kobold, Funke.

### B10.3 Gehirn
- Ein Server-Takt 10 Hz, gestaffelt (jeder Bot 1× pro 100 ms), pro Tick ≤ 3 Raycasts, ≤ 0.25 ms.
- **Wahrnehmung:** Sichtlinie Kopf→Kopf/Torso gegen `Map` (Rauch-Kugeln blockieren analytisch über `ProjectileService.IsSmoked`).
- **Zustände:** Patrol → Engage (strafen, Feuerstöße) → Reposition (zum Cover-Knoten) → Retreat/Heal (HP < Rückzugs-HP) →
  Push (Hard/Insane drängen nach 0.4 s, wenn der Gegner nachlädt) → Zone (in Overtime zur Zone) → Melee (Ziel ≤ 12 Studs und Nahkampfwaffe).
- **Navigation:** A* auf dem Nav-Graph (≤ 300 Knoten), neu planen alle 2 s oder bei Zielwechsel; `Humanoid:MoveTo(nächster)` jeden Tick;
  hängt fest (< 1 Stud in 1.5 s) → springen + neu planen. Strafen über `Humanoid:Move(dir)`.
- **Schießen:** ausschließlich `WeaponService.ServerFire(c, aim)` (gleiche Munition/Intervall/Nachladen/Schaden), Ziel = aktuelle Position, kein Rückspulen.
- **Zielfehler:** startet bei `AimErr`, fällt exponentiell mit τ, Minimum `MinErr`, +0.15° pro Stud/s Querbewegung des Ziels.
- **Rookie-Handicap:** in den ersten 3 Matches eines Menschen gehen die ersten 2 Schüsse jeder Runde absichtlich daneben.

| Stufe | Reaktion s | AimErr ° | τ s | MinErr ° | Kopf % | Strafe-Wechsel s | Springen/Rutschen | Utility % | Rückzug HP | Tempo × |
|---|---|---|---|---|---|---|---|---|---|---|
| `Rookie` | 0.75 | 9 | 0.9 | 3.5 | 3 | 1.5–2.5 | nein | 0 | – | 0.85 |
| `Easy` | 0.55 | 7 | 0.7 | 2.5 | 6 | 1.0–1.8 | 5 % | 10 | 25 | 0.92 |
| `Normal` | 0.40 | 5 | 0.6 | 1.5 | 12 | 0.8–1.5 | 10 % | 25 | 35 | 1.0 |
| `Hard` | 0.28 | 3 | 0.5 | 0.9 | 22 | 0.6–1.2 | 25 % | 40 | 40 | 1.0 |
| `Insane` (nur Practice/Crown) | 0.19 | 1.8 | 0.4 | 0.5 | 32 | 0.5–1.0 | 35 % | 60 | 45 | 1.0 |

- **Adaptiv (verdeckt):** Rookie solange `Stats.Matches < 3`; sonst nach MMR: < 900 Easy, 900–1150 Normal, > 1150 Hard
  (Team: Durchschnitt). 2 verlorene Bot-Matches in Folge → eine Stufe leichter (min. Easy); 3 gewonnene → eine schwerer;
  immer ±1 um die MMR-Stufe (`Data.BotTier` = Versatz −1..+1).
- **Loadouts:** Rookie/Easy nur Gratis-Set; ab Normal gewichtet zufällig aus allen 15 (`Config.Bots.LoadoutWeights`).
- **Belohnung gegen Bots:** XP und Coins ×0.6 (min. 15 Coins), Bot-Coins max. **2.500 pro UTC-Tag**; Practice: XP ×0.3, 0 Coins,
  Meisterschaft ×0.5. Quests zählen (außer „gegen Spieler“), Meisterschaft voll. **Nie** Bestenliste, MMR, Serien, Kopfgeld.
- **Animationen:** Client `BotAnimator` spielt die Standard-IDs lokal auf getaggten Bots + toolnone für die Waffe.

## B11. Waffen

### B11.1 Allgemeine Regeln
- **Loadout = 4 Slots:** Primary, Secondary, Melee, Utility. Gratis-Start: PopRifle, PipPistol, BoxingGloves, PopGrenade.
- **Munition:** Magazin pro Waffe, **unendliche Reserve**. Magazinstand bleibt bei Wechsel innerhalb der Runde; Rundenstart/Respawn füllt alles.
- **Nachladen:** R oder automatisch bei leerem Magazin (Einstellung). Wechsel bricht Nachladen ab. Erst nach `Equip`-Zeit schießen.
- **Burst-Waffen:** `BurstCount` Kugeln im Abstand `BurstInterval`, danach Pause `Interval` bis zur nächsten Salve (Auslöser einmal drücken = eine Salve).
- **Hitscan:** Client-Raycast von der Kamera. Richtungen aus `Spread.Directions(aim, def, scale, Spread.Seed(salt, shotId))`.
  `salt` = Combatant.Salt (Server, kommt per `Combat("Armed")`). Server erzeugt identische Strahlen.
- **Spread-Skala (Grad, Kegel-Halbwinkel):** `lerp(SpreadHip, SpreadAds, adsAlpha) + (bewegt ? SpreadMove : 0) + (in der Luft ? SpreadAir : 0) + Bloom`.
  Bloom = `min(BloomMax, BloomPerShot × Kettenlänge)`; Kette reißt, wenn Abstand der Schuss-Zeitstempel > `Interval × 1.6`.
- **Schaden:** `Damage.Compute(def, dist, region, rules)`:
  `base = lerp(Damage, Damage × MinMult, clamp((dist − FalloffStart)/(FalloffEnd − FalloffStart), 0, 1))`, dann × Region
  (Kopf `HeadMult`, Körper 1.0), × `rules.DamageMult`; `HeadOnly` → Körper 0. Kein Durchschuss durch Wände.
- **Rückstoß:** sichtbarer Kamera-Kick `RecoilPitch`° hoch, `RecoilYaw`° zufällig ±, Erholung über `RecoilRecover` s
  (85 %). Schussrichtung = Kamerarichtung beim Schuss + Spread → Rückstoß kontrollieren ist Skill.
- **Tempo:** `WalkSpeed = BaseSpeed × MoveMult` (× `AdsMoveMult` beim Zielen). `BaseSpeed` setzt der Server als Attribut.
- **Scharfschützen-Konter:** Zielfernrohr-Glanz (Neon-Funkeln + `textures/glow.png`-Billboard) für Gegner sichtbar nach 0.3 s ADS;
  Treffer während ADS → 2° Kamera-Kick; ADS-Zeit 0.32 s.

### B11.2 Primärwaffen (`Config.Weapons`, Ids u8)
| Id | Key | Name DE / EN | Art | Dmg | MinMult | Head× | Interval s | Mag | Reload s | Equip s | Spread Hip/ADS (+Move/+Air) | Bloom pro Schuss/max | Falloff Start→Ende | Range | ADS-Zoom/Zeit | Move× (ADS×) | Rückstoß P/Y/Erholung | Preis Coins |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `PopRifle` | Pop-Gewehr / Pop Rifle | Hitscan Auto | 15 | 0.67 | 1.5 | 0.10 | 30 | 2.0 | 0.40 | 2.0/0.5 (+1.0/+3) | 0.15/1.5 | 60→180 | 500 | 1.3/0.18 | 1.00 (0.75) | 0.32/0.12/0.35 | **gratis** |
| 2 | `BuzzSMG` | Summ-MP / Buzz SMG | Hitscan Auto | 11 | 0.55 | 1.4 | 0.065 | 35 | 1.8 | 0.30 | 2.6/1.5 (+0.6/+2) | 0.12/1.2 | 25→80 | 300 | 1.15/0.14 | 1.05 (0.85) | 0.22/0.18/0.3 | 600 |
| 3 | `BurstBlaster` | Salven-Blaster / Burst Blaster | Hitscan Burst 3 (0.07 s, dann 0.32 s Pause) | 19 | 0.68 | 1.5 | 0.32 (Burst 0.07) | 24 | 2.2 | 0.45 | 1.8/0.35 (+0.8/+3) | 0.10/0.6 | 70→200 | 600 | 1.5/0.20 | 0.97 (0.70) | 0.45/0.10/0.4 | 1.200 |
| 4 | `Scatter` | Streuer / Scatter | Hitscan, 8 Schrote | 12 je Schrot | 0.25 | 1.5 | 0.85 | 6 | 2.4 | 0.50 | Kegel 6.0/4.5 | – | 10→32 | 120 | 1.15/0.16 | 1.00 (0.80) | 3.0/0.5/0.5 | 600 |
| 5 | `Longshot` | Fernschuss / Longshot | Hitscan Einzel (Bolzen) | 55 | 1.0 | 2.5 | 1.30 | 5 | 2.6 | 0.60 | 7.0/0 (2.0 bis Fernrohr voll) | – | kein | 1500 | 4.0/0.32 | 0.92 (0.55) | 4.5/0.3/0.6 | 2.000 |
| 6 | `PopRocket` | Plopp-Rakete / Pop Rocket | Projektil 120 Studs/s, g 0, Lebensdauer 4 s | Direkt 70; Splash 60→15 in r 11; selbst ×0.4 | – | – | 0.90 | 2 | 2.4 | 0.60 | 0.5/0.2 | – | – | 480 | 1.2/0.20 | 0.90 (0.75) | 2.5/0.2/0.5 | 2.500 |

### B11.3 Sekundärwaffen
| Id | Key | Name DE / EN | Art | Dmg | MinMult | Head× | Interval | Mag | Reload | Equip | Spread Hip/ADS | Falloff | Range | ADS-Zoom | Move× | Rückstoß | Preis |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 7 | `PipPistol` | Pieps-Pistole / Pip Pistol | Hitscan Halbauto | 22 | 0.64 | 1.6 | 0.15 | 12 | 1.4 | 0.25 | 1.2/0.35 (+0.6/+2) | 40→110 | 400 | 1.25 | 1.03 | 1.0/0.2/0.25 | **gratis** |
| 8 | `HandCannon` | Hand-Kanone / Hand Cannon | Hitscan Halbauto | 42 | 0.67 | 1.75 | 0.45 | 6 | 2.3 | 0.35 | 1.2/0.2 (+0.8/+2.5) | 50→140 | 450 | 1.3 | 1.00 | 3.2/0.6/0.4 | 1.200 |
| 9 | `MiniScatter` | Mini-Streuer / Mini Scatter | Hitscan, 6 Schrote | 12 je Schrot | 0.25 | 1.4 | 0.25 | 2 | 1.9 | 0.30 | Kegel 7.5/6.5 | 8→24 | 80 | 1.1 | 1.03 | 3.5/0.8/0.4 | 600 |

### B11.4 Nahkampf (Server: Reichweite + Kegel gegen zurückgespulte Hitbox, Sichtlinie; kein Kopf-Bonus)
| Id | Key | Name DE / EN | Dmg | Intervall s | Reichweite | Kegel | Move× | Besonderheit | Preis |
|---|---|---|---|---|---|---|---|---|---|
| 10 | `BoxingGloves` | Boxhandschuhe / Boxing Gloves | 35 | 0.40 | 6.5 | 70° | 1.15 | **Doppelsprung** (1 Luftsprung, Höhe 6) solange ausgerüstet | **gratis** |
| 11 | `BonkHammer` | Bonk-Hammer / Bonk Hammer | 70 | 0.90 (0.35 Ausholen) | 7 | 80° | 1.05 | Rückstoß 55 horizontal + 30 hoch (Server → `Combat("Impulse")`), „BONK!“ | 1.500 |
| 12 | `LaserSword` | Laserschwert / Laser Sword | 45 | 0.55 | 8 | 70° | 1.10 | ADS halten = **Blocken**: Schaden von vorn (≤ 75° zur Blickrichtung) ×0.4, max. 1.5 s, danach 3 s Abklingzeit, Tempo ×0.65, kein Angriff während Block | 1.200 |

### B11.5 Utility (Duelle: Ladungen pro Runde; FFA: Abklingzeit)
| Id | Key | Name DE / EN | Wirkung | Zahlen | Ladungen / Cooldown | Preis |
|---|---|---|---|---|---|---|
| 13 | `PopGrenade` | Plopp-Granate / Pop Grenade | Wurf: Tippen 70 Studs/s, 0.5 s halten 90; Schwerkraft 90; ≤ 2 Abpraller (Restitution 0.35); Zünder 2.0 s ab Wurf | 95 Mitte → 10 am Rand r 13; Sichtlinie zur Map nötig; selbst ×0.5 | 1 / 14 s | **gratis** |
| 14 | `SmokeBomb` | Rauchbombe / Smoke Bomb | gleicher Bogen, platzt bei erster Landung (spätestens 2.0 s) | Rauchkugel r 13 für 9 s; blockiert Bot-Sicht und Zielhilfe (nicht Kugeln) | 1 / 18 s | 600 |
| 15 | `MedFizz` | Heil-Limo / Med Fizz | 0.8 s trinken (kein Schießen), dann +50 HP über 2.5 s (+5 alle 0.25 s), Abbruch bei Schaden; max 100 HP | – | 1 / 20 s | 1.200 |

**Preise gesamt:** 13.200 Coins für alle 11 nicht-gratis Waffen (≈ 6 h inkl. Quests und 3 Gratis-Waffen-Wahlen).
**Keine Level-Sperren.** Jede Waffe gratis testbar in der Range und in Practice/Bot-Duell. Gesperrte Waffen nur in echten Matches nicht nutzbar.

### B11.6 Referenz-TTK (100 HP)
| Waffe | Körper | Kopf |
|---|---|---|
| PopRifle | 7 Schüsse = 0.60 s | 5 = 0.40 s |
| BuzzSMG | 10 = 0.585 s | 7 = 0.39 s |
| BurstBlaster | 6 (2 Salven) = 0.60 s | 4 = 0.46 s |
| PipPistol | 5 = 0.60 s | 3 = 0.30 s |
| HandCannon | 3 = 0.90 s | Kopf+Körper = 0.45 s |
| Longshot | 2 = 1.30 s | 1 (137) |
| Scatter | 1 Schuss bei 8/8 Schroten + 1 Kopf-Schrot (≤ 10 Studs), sonst 2 | – |
| BoxingGloves | 3 Treffer = 0.80 s | – |

### B11.7 Admin-Waffen (nur Besitzer; nie im Shop, nie für andere; in den Primary-Slot; **taint** das Match)
| Id | Key | Name | Verhalten |
|---|---|---|---|
| 101 | `OrbitalLaser` | Orbital-Laser | Klick markiert Punkt (Ray ≤ 1000); 1.0 s roter Warnkreis, dann Himmelsstrahl r 10, 999 Schaden; Cooldown 2 s |
| 102 | `RocketMinigun` | Raketen-Minigun | 0.4 s Anlauf, dann alle 0.10 s eine Rakete (Splash r 8, 40); Mag 100, Reload 3 |
| 103 | `BlackHoleCannon` | Schwarzes-Loch-Kanone | Kugel 40 Studs/s; Aufprall → 4 s Wirbel r 18–25, zieht Bots (Server) und Spieler (Client-Impulse), 25 Schaden/s, dann 150 Implosion |
| 104 | `LightningRifle` | Blitz-Gewehr | Hitscan, springt auf bis zu 4 weitere Ziele ≤ 20 Studs, je 80; Neon-Zickzack-Beams |
Aus Parts mit Neon, Beams, Partikeln. `WeaponService` verweigert sie für Nicht-Admins.

### B11.8 Waffen-Modelle (WP4 `Shared/WeaponModels.luau`)
- Jede Waffe und jeder Skin ist ein **Rezept**: Liste `{Shape, Size, Offset: CFrame, Role, Material?, Name?}` mit
  `Shape ∈ {"Block","Cylinder","Ball","Wedge","CornerWedge","MeshSphere","MeshCylinder"}` und
  `Role ∈ {"Body","Detail","Accent","Metal","Grip","Tip"}` (Tip = orange Sicherheitsspitze, immer `255,120,0` Neon, von Wraps nie verändert).
- Pflicht-Attachments: `Grip`, `Muzzle`, `Sight`, `Charm`; ein Teil heißt `Mag` (bewegt sich beim Nachladen).
- 8–14 Teile pro Waffe (Admin-Waffen ≤ 30 + Emitter). Beispiel PopRifle: Körper 0.5×0.6×2.2 (Body), Lauf Zylinder 0.25×1.2
  (Metal, Foil), Spitzen-Ring (Tip), Magazin 0.3×0.7×0.4 (`Mag`, Detail), Schaft-Wedge (Body), Visier mit Neon-Punkt (Accent), Neon-Seitenstreifen 0.05×0.1×1.6 (Accent).
- Gleiches Rezept für Viewmodel (Skala 1.0), 3rd Person (Skala 0.8) und Shop/Locker-Vorschau.

## B12. Bewegung (`Config.Player`)
| Wert | Zahl | Hinweis |
|---|---|---|
| Gehen | 16 | `StarterPlayer.CharacterWalkSpeed` |
| Sprinten | 22 | Shift halten/umschalten; kein Schießen beim Sprinten; Sprint→Schuss 0.12 s; ADS bricht Sprint ab |
| Springen | `JumpHeight = 7.2` | `CharacterUseJumpPower = false` |
| Rutschen | aus Sprint (Tempo ≥ 18) + Ducken-Taste: 32 → exponentiell 14 in 0.75 s; Kamera −1.6 (CameraOffset), FOV +6; Cooldown 1.0 s | Schießen erlaubt (+1° Spread). **Keine Hitbox-Änderung.** Andere sehen nur Staub-Trail + Tempo. |
| Rutsch-Sprung | Sprung im Rutschen behält 90 % horizontal (max 30) | Kern-Skill |
| Doppelsprung | nur mit BoxingGloves: 1 Luftsprung Höhe 6 | |
| Ducken | **gibt es nicht** (nur Rutschen) | vermeidet Hitbox/Pose-Mismatch |
| Fallschaden | keiner | Sturz unter KillY = Pop |
| Raketen-Sprung | eigener PopRocket-Treffer ≤ 4 Studs von den Füßen → Impulse 55 nach oben; Selbstschaden ×0.4 | AC-Grace |
Bewegung läuft auf dem Client (eigene Physik). Mutatoren skalieren über `BaseSpeed` (Server-Attribut) und `GravityLift`.

## B13. Leben, Schaden, Hitboxen, Ausschalten („Pop to Vault“)

### B13.1 Leben
- HP 100, gespeichert **serverseitig** im Combatant; gespiegelt in Attribut `Hp` am Character-Modell (für UI anderer).
- `Humanoid.MaxHealth = 100`, `Health` bleibt 100 (wird fürs Gameplay nicht benutzt) – **wir schreiben nie 0**.
- Standard-Regeneration aus: leeres Script `Health` in `StarterCharacterScripts` (`src/character/Health.server.luau`).
- Keine Regeneration in Rundenmodi. FFA: +12 HP/s nach 5 s ohne Schaden.
- Spawn-Schutz (FFA) 1.5 s: Schaden wird ignoriert, Schimmer-Effekt, endet beim ersten Schuss.
- Kill-Gutschrift: letzter Schadensverursacher ≤ 8 s. Assist: ≥ 25 Schaden ≤ 8 s vor dem Pop, nicht der Killer.

### B13.2 Hitboxen (analytisch, feste Größe, fair für jeden Avatar)
- **Kopf:** Kugel am aufgezeichneten `Head.Position`, Radius `0.8 × rules.HeadRadiusMult` + Toleranz 0.35.
- **Körper:** OBB aus HRP-CFrame, Mittel-Versatz (0, −1.0, 0), Halbmaße (1.5, 2.0, 0.8) (Boden bis Schulter, Arme inklusive).
- Region = näherer Eintrittspunkt; Kopf gewinnt Gleichstand innerhalb 0.5 Studs. Behauptet der Client Kopf und nur der Körper passt → Körper.
- Accessoire-Handles, Waffenmodelle, Viewmodel, Charms, Finisher: `CanQuery=false, CanTouch=false, Massless=true` (Server setzt das bei Accessoires).
- Besitzer stellt in Game Settings → Avatar: **R15, Skalierung Standard** (Anleitung). Kein `ApplyDescriptionAsync`.
- R6 wird toleriert (Head + HRP existieren).
- 3rd-Person-Ziel-Neigung anderer (B14.8) max. Neck 0.5×Pitch, Waist 0.15×Pitch → Kopfversatz ≤ 0.4 Studs (innerhalb Toleranz).

### B13.3 Pop (Ausschalten) – Ablauf
1. `CombatService.ApplyDamage` → `Hp ≤ 0` → `CombatService.Eliminate(victim, info)`.
2. `Alive=false`, Attribut `Alive=false`, Untrack in `HistoryService`, Waffe/Namensschild aus, AntiCheat-Ausnahme.
3. `CharacterService.Pop(c)`: HRP verankern, `PivotTo(arena.Vault + Versatz Roster-Slot)`, Kollisionsgruppe `Ghost`.
4. `MatchService` sendet `Match("Elim", …)` an alle Empfänger: Killfeed + Finisher an der letzten Position (`Pos`).
5. Gepoppter Spieler: Zuschauen (B14.5), Todes-Rückblick.
6. Nächste Runde / Respawn: `CombatService.Revive(c, spawnCF)` → `CharacterService.Unpop`: `PivotTo(spawn + 3Y)`,
   Gruppe `Combatants`, entankern, `HRP:SetNetworkOwner(player)` (pcall), `AntiCheat.NoteTeleport`, HP voll, Track.
- **Fallback** (Exploit-Selbstmord, Humanoid stirbt trotzdem): `Humanoid.Died` → als Pop zählen, gutgeschrieben dem letzten
  Schadensverursacher ≤ 8 s (sonst Runde verloren für dieses Leben). `BreakJointsOnDeath=false`. Roblox respawnt automatisch
  nach 3 s (`CharacterAutoLoads=true`, `RespawnTime=3`); der **CharacterAdded-Router** (CharacterService + MatchService.Route)
  schickt den neuen Character in Vault (Runde läuft), an den Spawn (Prep) oder in die Lobby (kein Match).
- Vault und alle KillY liegen über `FallenPartsDestroyHeight = −500`.

## B14. Feedback, Killfeed, Rückblick, Zuschauen, Scoreboard, Ergebnis

### B14.1 Juice-Tabelle (Client)
| Ereignis | Bild | Ton (ASSETS §2.2) | Extra |
|---|---|---|---|
| Körpertreffer | weißes X 0.12 s, weiße Zahl (stapelt pro Ziel 0.6 s) | volume_slider 1.6 (PlayLocalSound) | Gamepad-Vibration 0.04 s |
| Kopftreffer | gelbes großes X, gelbe Zahl mit „!“, „HEADSHOT!“ (Bangers) | Ding: 2.2 dann 2.8 nach 0.05 s | Sterne am Ziel |
| Pop | rotes X, Mitte „POPPED <Name>“, Finisher am Opfer | Kill-Jingle 1.0/1.26/1.5 | FOV +3 Punch |
| Mehrfach (Team/FFA) | DOUBLE! TRIPLE! QUAD! | Tonhöhe steigt | |
| Schaden erhalten | rote Rand-Verlauf-Blende (Frame+UIGradient), Richtungs-Pfeil `textures/triangle.png` 1.2 s | `ouch.ogg` leise nur ≤ 30 HP | Herzschlag-Vignette < 30 HP |
| Runde gewonnen/verloren | Banner volle Breite in Teamfarbe | Win/Lose-Jingle | Punkt-Pips animieren |
| Level-Up | Konfetti + „LEVEL 12!“ | Win-Jingle + Echo | Belohnungskarte |
| Kiste | Rolle läuft aus, Seltenheits-Blitz, ab Legendär Schockwellen-Ring, **ehrlich** (keine Beinahe-Treffer) | Ticks | Lobby-Ansage nur an Spieler mit erlaubten Zufallsitems |
| Leer/Nachladen | Munitionsanzeige wackelt rot bei 0, „R“-Hinweis | Mag-Klacks action_jump_land 3.2/2.6, Trockenfeuer | doppelter Tick bei wenig Munition |
Der Client zeigt sofort einen vorläufigen Hitmarker; die Server-Bestätigung (`Combat("Hit")`) ersetzt ihn innerhalb eines Pings.
Lehnt der Server ab, wird kein Kill-Marker gezeigt.

### B14.2 Killfeed (oben rechts, max. 5 Zeilen, je 5 s, nur eigener Kontext)
`[Killer] [Waffen-Kurzname] [★ bei Kopf] [Opfer]` (+ „+ Assist-Name“). Eigene Zeilen gelb, Bots grau mit [BOT].
Abzeichen: Serien-Flamme (≥ 3), Kopfgeld-Münze, Meisterschafts-Stern (ab Stufe V), Krone (König).

### B14.3 Todes-Rückblick (Opfer, links, bleibt beim Zuschauen)
Killer-Avatar (`Players:GetUserThumbnailAsync(..., HeadShot, Size150x150)`, Bots `textures/face.png`), Name, Titel, Waffe + Wrap-Name,
„**REST-LEBEN: 37**“, Liste der letzten ≤ 12 erhaltenen Treffer (Waffe, Schaden, KOPF, Distanz), „**Du hast 63 Schaden in 4 Treffern gemacht (1 Kopf)**“, Knopf „Melden“ (1× pro Match).

### B14.4 Gegner-Umriss & Highlights (Budget ≤ 31 pro Client)
Gegner im eigenen Match: `Highlight` DepthMode `Occluded`, nur Umriss (FillTransparency 1), Farbe aus Einstellung (≤ 7).
Anti-Camp-Puls: dieselben Highlights 1 s auf `AlwaysOnTop`. Admin-ESP ≤ 20 (`AlwaysOnTop`). Zentraler Verteiler `Highlights` (WP10).

### B14.5 Zuschauen
Rundenmodi: 1.5 s Blick auf den Killer (Name + HP), dann Verfolger-Kamera (über die Schulter, `CameraSubject = Humanoid` des
Teamkollegen, Zoom 8) auf lebende Teamkollegen; wechseln mit Klick / LB-RB / Pfeile. 1v1: Killer 2 s, dann Rückblick.
FFA: Rückblick 2.5 s, dann Respawn.

### B14.6 Ergebnis-Bildschirm (10 s)
MVP-Karte, K/D/A, Schaden, Genauigkeit; Balken nacheinander: XP → Coins → Meisterschaft der meistgenutzten Waffe → Pass
(nächste Gratis- **und** Premium-Belohnung sichtbar, Premium mit Schloss) → Quest-Häkchen. Knöpfe GG / Loben / REMATCH /
NOCHMAL SPIELEN / Lobby. „Nur noch 40 XP bis Level 12!“, „120 Coins bis Fernschuss“. Einmalige Angebots-Karte nur wenn
der Server `Offer` mitschickt (B23).

### B14.7 Scoreboard (Tab / View / Knopf)
Pro Team: Avatar, Name, Level-Abzeichen, Titel, K/D/A, Schaden, Ping (`Player:GetNetworkPing()` × 1000, vom Server im Attribut `PingMs` alle 2 s), [BOT].
Knöpfe Loben 👍 (nach Match) und Melden ⚑. Während eines Matches ist die Roblox-PlayerList ausgeblendet.

### B14.8 3rd-Person-Darstellung
- Server schweißt beim Bewaffnen alle 4 Loadout-Modelle (Skala 0.8, Kosmetik angewendet) an `RightHand` (R15) bzw. `Right Arm` (R6),
  sichtbar nur der ausgerüstete Slot (Transparency). Keine Tools → TransparencyController versteckt sie in der Ego-Sicht automatisch.
- Eigener Client spielt toolnone `507768375` (Looped, Priority Action) solange bewaffnet.
- Neigung: Client sendet Pitch (int8) über `Look` (12 Hz, nur bei Änderung > 1°); Server bündelt pro Kontext 10 Hz `LookBatch`;
  jeder Client setzt lokal Neck-C0 (×0.5) und Waist-C0 (×0.15). Nachladen kippt die Waffen-Schweißung lokal, Nahkampf dreht die Schulter lokal.

## B15. Steuerung, Zielhilfe, Einstellungen

### B15.1 Belegung (`Config.Client.Keys`)
| Aktion | PC | Gamepad | Touch |
|---|---|---|---|
| Bewegen / Schauen | WASD / Maus | LS / RS | Standard-Stick / rechte Hälfte ziehen |
| Feuer | LMB | RT (`Position.Z ≥ 0.4`) | großer FEUER-Knopf rechts (ziehen = zielen) + kleiner links |
| Zielen (ADS) | RMB (halten/umschalten) | LT | ADS (umschalten) |
| Nachladen | R | X | NACHLADEN |
| Slot 1–4 | 1/2/3/4, Mausrad | Y wechselt Primär/Sekundär, LB Nahkampf | Slot-Leiste (4 Icons) |
| Letzte Waffe | Q | Y doppelt | aktives Icon tippen |
| Utility werfen/benutzen | **E** (halten = weiter) | RB | UTILITY |
| Sprinten | Shift | L3 | automatisch bei Stick ≥ 0.9 |
| Rutschen | C / LeftControl beim Sprinten | B | RUTSCHEN |
| Springen | Space | A | Standard |
| Scoreboard / Loadout / Inspizieren / Menü | Tab / L / V / M | View / D-Pad runter / D-Pad hoch / Menu | Knöpfe |
| Bereit | Enter | Start | BEREIT |
| Admin-Panel / Fly (nur Besitzer) | P / **G** | – | Admin-Knopf |
- Alles über `ContextActionService:BindActionAtPriority` mit `createTouchButton=false`; eigene Touch-Knöpfe in einer
  **unskalierten** ScreenGui (`TouchGui`), jeder ≥ 64 px, `ScreenInsets = DeviceSafeInsets`. Backpack- und Health-CoreGui aus.
- HUD wechselt live mit `UserInputService.PreferredInput` (+ `GetPropertyChangedSignal`).
- Fenster offen → sichtbarer `Modal=true`-Knopf (gibt die Maus frei), Kampf-Eingaben gesperrt.
- Touch-Layout-Editor: **v1.0.x**. v1: Linkshänder-Spiegelung + Knopfgröße 90–130 %.

### B15.2 Zielhilfe (nur Touch & Gamepad, **nie Maus**; Werte in `Config.Client.AimAssist`)
- **Reibung:** Blick-Eingabe ×0.55, wenn das Fadenkreuz ≤ 3.5° (Gamepad) / 4.5° (Touch) an einem **sichtbaren** Gegner
  (Sichtlinien-Ray, nicht durch Rauch) ≤ 70 Studs ist.
- **Magnetismus:** nur während Bewegung oder Blick-Eingabe, max. 4°/s (Gamepad) / 5°/s (Touch) zum Torso. Kein Einrasten.
- Stärke-Regler 0–100 %; Ranked (v1.1) ×0.5.
- **Auto-Feuer (Touch):** Standard **AN** für neue Touch-Spieler in Casual; feuert, wenn das Fadenkreuz 0.15 s auf einem
  sichtbaren Gegner liegt, mit **85 % Feuerrate**. Aus in Ranked. Abschaltbar.

### B15.3 Einstellungen (`Data.Settings`, Schema `Config.Client.SettingsSchema`)
FOV 70–100 (Std. 80) · Empfindlichkeit Maus/Gamepad/Touch je Hüfte und ADS-Faktor + Zielfernrohr-Faktor · Y invertieren ·
ADS halten/umschalten · Sprint halten/umschalten · Auto-Nachladen · Auto-Feuer · Zielhilfe-Stärke · Fadenkreuz (4 Stile:
Kreuz, Punkt, Kreis, T; Farbe Weiß/Grün/Gelb/Cyan/Pink; Größe 4–16; Lücke 0–10; Punkt an/aus) · Gegnerfarbe ·
Schadenszahlen · Treffer-Ton · Reduzierte Effekte (automatisch bei < 35 FPS für 5 s) · Kamerawackeln 0–100 % · Linkshänder ·
Knopfgröße · Sprache (Auto/DE/EN) · Lautstärke SFX/Musik/UI · Ping/FPS zeigen · Auto-Requeue · eigene Kisten-Funde öffentlich.

## B16. Fortschritt

### B16.1 XP & Level
- `XPToNext(L) = 250 + 50·(L − 1)`, Max-Level 100. Level 2 = 250 XP, Level 10 = 4.050 gesamt (≈ 1.6 h),
  Level 15 = 8.050 (≈ 3 h), Level 50 = 71.050 (≈ 27 h), Level 100 = 267.300 (≈ 100 h).
- **XP-Quellen (Casual gegen Menschen):** Match beendet 40, Sieg +60, Runde gewonnen 12, Pop 15, Assist 7, Kopf-Pop +5,
  Nahkampf-Pop +10, MVP +20, GG (beide) +5, Kronen-Verteidigung (Mensch) +15.
- **Multiplikatoren (additiv, gedeckelt ×3.0):** VIP +0.2, DoubleXP-Pass +1.0, XP-Boost-Produkt +1.0, Party-Boost +1.0,
  Admin-Abuse-Event +1.0. Danach Bot-Faktor ×0.6 bzw. Practice ×0.3. **Erster Sieg des UTC-Tages:** +200 XP flach + 150 Coins.
- Typisch: 1v1-Sieg ≈ 270 XP, Niederlage ≈ 136 → ≈ 2.600 XP/h.
- **Level-Belohnungen:** jedes Level `50 + 10·L` Coins; **Gratis-Waffen-Wahl** bei Level 4, 10, 20 (`FreeWeaponPicks`,
  im UI „Wähle eine Waffe gratis!“, keine Währung); jedes 5. Level 1 Schlüssel; jedes 10. Level 25 Gems + Titel
  (10 „Kein Neuling mehr / Rookie No More“, 25 „Scharfschütze / Sharpshooter“, 50 „Veteran“, 75 „Elite“, 100 „Clutch-Legende / Clutch Legend“).
- Level-Abzeichen-Farben: 1–9 weiß, 10–24 grün, 25–49 blau, 50–74 lila, 75–99 orange, 100 animiert gold.

### B16.2 Waffen-Meisterschaft (pro Waffe; Nahkampf- und Utility-Pops zählen ×2; Bots zählen; MasteryBoost-Pass ×2)
| Stufe | Pops | Belohnung |
|---|---|---|
| I | 10 | 150 Coins |
| II | 30 | Wrap „Bronze“ für diese Waffe |
| III | 75 | 1 Schlüssel + 250 Coins |
| IV | 150 | Wrap „Silber“ |
| V | 300 | Wrap „Gold“ + Stern im Killfeed |
| VI | 600 | 50 Gems |
| VII | 1.000 | Wrap „Diamant“ (Funkeln) |
| VIII | 2.000 | Wrap „Neon-Puls“ (animiert) |
| IX | 3.500 | Wrap „Galaxie“ (animiert) + Titel „<Waffe>-Meister“ |
| X | 6.000 | Wrap „Prisma“ + Kronen-Icon im Killfeed |
Meisterschafts-Wraps sind nicht kaufbar; Ausrüsten prüft die Stufe dieser Waffe (kein Extra-Besitz-Eintrag).

### B16.3 Quests
- **Anfänger-Kette** (eine nach der anderen, 1.250 Coins gesamt): 1 Triff 10× eine Puppe (100) · 2 Gewinne dein erstes Duell (150) ·
  3 5 Pops (100) · 4 3 Kopf-Pops (100) · 5 Hol dir eine neue Waffe (100) · 6 Bearbeite ein Loadout (50) · 7 Rutsche 5× (75) ·
  8 Spiele ein 2v2 (125) · 9 Fordere die Krone heraus (150) · 10 Erreiche Level 5 (300 + 1 Gratis-Waffen-Wahl).
- **Täglich** (3 pro UTC-Tag: Leicht/Mittel/Schwer = 150/250/400 Coins, je +300 Pass-XP; 1 Gratis-Reroll, VIP +1;
  alle 3 → +1 Glücksrad-Dreh). Pool (20, `Config.Progression.Quests.Daily`):
  `WinMatches 2` · `PlayMatches 3` · `Elims 15` · `HeadshotElims 5` · `Damage 1500` · `MeleeElims 3` · `SecondaryElims 5` ·
  `SmgShotgunElims 8` · `RoundFullHp 1` · `OvertimeRound 1` · `FfaElims 10` · `PlayMutator 1` · `CrownChallenge 1` · `Heal 150` ·
  `SlideElims 3` · `SplashElims 2` · `RoundsWon 6` · `Assists 5` · `FfaStreak3 1` · `WinOnMap SkyGarden 1`.
- **Wöchentlich** (5, Montag 00:00 UTC; je 600 Coins + 1.500 Pass-XP; alle 5 → **Wochen-Truhe**: 2 Schlüssel + 50 Gems).
  Pool (8): `WinMatches 10` · `Elims 75` · `HeadshotElims 20` · `CrownDefences 3` · `MasteryTier 3` · `DifferentMaps 5` · `PvpWins 10` · `Commend 5`.
- Fortschritt nur serverseitig: `RewardService.Track(p, kind, amount, ctx)` (immer über `pcall` aufgerufen).

### B16.4 Login, Glücksrad, Spielzeit, erster Sieg
- **7-Tage-Kalender** (rückt nur an Tagen mit Login vor; verpasster Tag setzt nur die *Serie* zurück):
  T1 150 Coins · T2 1 Schlüssel · T3 250 Coins · T4 15 Gems · T5 350 Coins · T6 1 Schlüssel · T7 2 Schlüssel + 30 Gems
  (+ beim ersten vollen Zyklus Charm „Kalender-Katze“). Serie: 1 **Serien-Freeze** pro ISO-Woche automatisch. Titel bei 7 Tagen „Brennt! / On Fire“.
- **Gratis-Glücksrad** (1 Dreh/Tag, VIP +1, alle Tagesquests +1; Quoten unter „Details“ sichtbar, Summe 100 %):
  100 Coins 30 % · 200 Coins 22 % · 1 Schlüssel 15 % · 15 min ×2 XP 12 % · 25 Gems 10 % · 500 Coins 7 % · 3 Schlüssel 3 % · 250 Gems 1 %.
  **Keine bezahlten Drehs.**
- **Spielzeit-Geschenke** pro UTC-Tag (über Besuche summiert): 5/15/30/60 min → 50 Coins / 100 Coins / 1 Schlüssel / 150 Coins.
- Sichtbare Timer: „Tages-Reset in 5h 12m“, „Morgen: 1 Schlüssel“.

### B16.5 Erfolge (12 in v1; je Titel, teils Gems)
| Id | Name DE / EN | Bedingung | Belohnung |
|---|---|---|---|
| `FirstPop` | Erster Pop / First Pop | 1 Pop | 50 Coins |
| `Headhunter` | Kopfjäger / Headhunter | 100 Kopf-Pops | Titel |
| `Untouchable` | Unberührbar / Untouchable | FLAWLESS-Runde | Titel |
| `ClutchMaster` | Clutch-Meister / Clutch Master | Runde als Letzter gegen ≥ 2 gewonnen | 50 Gems + Titel |
| `Ace` | Ass / Ace | ACE (ab 3v3) | Titel |
| `ThroneKeeper` | Kronen-Hüter / Throne Keeper | 10 Kronen-Verteidigungen gegen Menschen | Titel |
| `BountyHunter` | Kopfgeldjäger / Bounty Hunter | 3 Kopfgelder kassiert | Titel |
| `Collector` | Sammler / Collector | 8 Waffen besitzen | 25 Gems |
| `Arsenal` | Arsenal | alle 15 Waffen | Titel |
| `GoodSport` | Fairer Sportler / Good Sport | 25 Lob erhalten | Titel |
| `Marathon` | Marathon | 100 Matches | 30 Gems |
| `SkyDiver` | Himmelstaucher / Sky Diver | 10 Gegner in die Leere geschubst (Pop durch KillY ≤ 3 s nach deinem Rückstoß) | Titel |

### B16.6 Verdecktes MMR
Elo Start 1000, K = 40 in den ersten 20 PvP-Matches, dann 24; Team = Durchschnitt; nur PvP-Matches mit ≥ 1 Mensch je Seite,
**ohne** Bots auf der Gegnerseite, nicht tainted. Formel in `Shared/ProgressMath.luau` (`Expected`, `Delta`).

### B16.7 Kopfgeld, Comeback
- PvP-Siegesserie ≥ 5 → Kopfgeld `100 + 25 × (Serie − 5)`, max. 300 Coins; Münz-Icon über dem Kopf in der Lobby, Killfeed-Münze,
  Lobby-Ansage. Wer die Serie (im PvP-Match) beendet, bekommt das Kopfgeld vom System (Opfer verliert nichts).
- Nach 3 PvP-Niederlagen in Folge: nächstes Match bevorzugt schwächere Gegner, Coins +25 % („Comeback-Bonus“).

### B16.8 Ehre
GG: beide Seiten drücken → je +5 XP und +5 Coins. Loben: 1 Spieler pro Match → `Honor.Commends` +1 (max. 3 zählen pro Tag
pro Empfänger). Abzeichen ab 10/50/200. Keine Strafen in v1.

### B16.9 Globale Bestenlisten (OrderedDataStore, 6 Lobby-Tafeln, Top 10 sichtbar)
`Wins` (PvP-Siege) · `Elims` (PvP-Pops) · `BestStreak` · `TotalXP` · `WeeklyWins` (Store-Name mit ISO-Woche) · `CrownBest`.
Schreiben nur geänderte Werte, frühestens alle 300 s pro Spieler, und beim Verlassen. Tainted- und Bot-Matches schreiben nie.

## B17. Ranked (v1.1 – Daten jetzt reserviert, Code später)
Zugang Level 15 + `Player.AccountAge ≥ 7` + 20 PvP-Matches, **ohne Ausweis**. Ränge Bronze/Silber/Gold/Platin/Diamant/Neon/Kosmos
(je III–I à 100 RP) + „Clutch-Legende“ (Top 100). 5 Platzierungen, K 64 → 32, Formel-Konstanten in Config. Schild 1×/Tag unter Platin,
Verfall ab Diamant (−15 RP/Tag nach 7 inaktiven Tagen). Regeln: Erster auf 4, Map-Bann (5 zeigen, je 1 bannen), 2 Loadout-Wechsel,
Zielhilfe ×0.5, kein Auto-Feuer, nie Bots. Warteschlange serverlokal ±150 MMR; nach 90 s Knopf **„Mehr Gegner finden“**
(`TeleportService:TeleportAsync` auf einen anderen öffentlichen Server mit `TeleportData = {Queue="Ranked"}`). Cross-Server-Matchmaking: v2.

## B18. Wirtschaft

### B18.1 Währungen (genau 4)
| Währung | DE | Woher | Wofür | Für Robux? |
|---|---|---|---|---|
| **Coins** | Münzen | Matches, Quests, Level, Meisterschaft, Login, Rad, Krone, Kopfgeld | **alle Waffen**, Coin-Kosmetik (Basis-Wraps), Extra-Loadout-Plätze | **Nie** (auch nicht über Multiplikatoren) |
| **Gems** | Juwelen | Robux-Pakete; gratis: Level, Erfolge, Login T4/T7, Rad, Wochen-Truhe, Pass | Kosmetik direkt, Kisten (nur wenn erlaubt), Pass Premium (Alternative) | ja |
| **Keys** | Schlüssel | **nur gratis**: Level, Login, Rad, Spielzeit, Wochen-Truhe, Meisterschaft, Pass-Gratis-Spur | 1 Kiste öffnen (= kostenloses Zufallsitem) | **Nie**, auch nicht mit Gems |
| **Shards** | Splitter | Kisten-Duplikate | Splitter-Shop: jedes Kisten-Item gezielt | nein |
Gratis-Waffen-Wahl (Level 4/10/20, Anfänger-Kette) ist eine **Belohnung**, keine Währung.

### B18.2 Coin-Verdienst (Casual gegen Menschen)
Teilnahme 30 · Runde gewonnen 10 · Pop 6 · Assist 3 · Kopf-Pop +2 · Sieg +50 · MVP +15 · GG +5 · Siegesserie +5 pro Stufe (max +30) ·
Comeback +25 %. Bots ×0.6 (min. 15, Tageslimit 2.500), Practice 0. 1v1-Sieg ≈ 159, Niederlage ≈ 62 → **≈ 1.500 Coins/h** + ≈ 800/Tag aus Quests/Login.
Admin-Abuse-Event darf Coins ×2 geben (Besitzer, kein Robux).

### B18.3 Coin-Senken
Waffen 13.200 gesamt · Basis-Wraps (6 Stück, je 1.500–3.000 Coins) · Loadout-Platz 4 und 5 je 5.000 Coins ·
Extra-Quest-Reroll 100 Coins · v1.1: Gold-Kollektion (Coin-Gold-Wrap pro Waffe, 20.000).

## B19. Kosmetik (alles Part-/UI-basiert; Daten `Config/Cosmetics.luau`, Rezepte `CosmeticModels.luau` + Skins in `WeaponModels.luau`)

Seltenheiten: Common (grau 170,170,170), Rare (blau 60,140,255), Epic (lila 170,90,255), Legendary (gold 255,200,40), Mythic (pink 255,60,170, animiert).
Katalog-Preise in Gems (= genau ein Gem-Paket): Common 120 · Rare 250 · Epic 500 · Legendary 1.000 · Mythic 2.200.

| Klasse | Technik | v1-Anzahl |
|---|---|---|
| **Wrap** | pro Rollen-Gruppe `{Color, Material}` (Body/Detail/Accent/Metal/Grip; Tip nie), optional `Anim ∈ {"Pulse","Rainbow","Galaxy","Sparkle"}` (10 Hz, nur Viewmodel/Vorschau/3rd-Person ≤ 80 Studs) | 34 (21 + 7 Meisterschaft + 6 Pass) |
| **Skin** | alternatives Waffen-Rezept (gleiche Attachments) | 8 |
| **Charm** | 2–8-Teile-Mini-Modell am `Charm`-Attachment, Feder-Pendel im Viewmodel | 13 |
| **Finisher** | Client-Effekt am Opfer, ≤ 25 Teile/Partikel, ≤ 2.5 s, > 300 Studs ausgeblendet, max. 4 gleichzeitig (sonst Konfetti) | 8 |
| **Tracer** | Beam-Farbe/-Breite (`textures/gradient.png` oder ohne Textur), Helligkeit ≥ 0.5, Transparenz ≤ 0.3 | 6 |
| **Titel** | Text unter dem Namen, im Scoreboard, Chat-Präfix, Intro | ~25 |

**Wraps (34):**
| Id | DE / EN | Rarity | Quelle |
|---|---|---|---|
| `W_Mint`, `W_Sky`, `W_Sunny` | Minze/Mint, Himmel/Sky, Sonnig/Sunny | Common | Coins 1.500 |
| `W_Bubblegum`, `W_Grape`, `W_Charcoal` | Kaugummi/Bubblegum, Traube/Grape, Kohle/Charcoal | Common | Coins 3.000 |
| `W_Ocean`, `W_Lemonade`, `W_Cherry`, `W_ToyCamo`, `W_Peach`, `W_Forest` | Ozean, Limo, Kirsche, Spielzeug-Tarn, Pfirsich, Wald | Rare | Katalog/Kiste |
| `W_NeonGrid` (Pulse), `W_Candy`, `W_Frost`, `W_Toxic` (Pulse) | Neon-Gitter, Zuckerl, Frost, Giftgrün | Epic | Katalog/Kiste |
| `W_Lava` (Pulse + Sparkle), `W_Aurora` (Rainbow) | Lava, Polarlicht | Legendary | Katalog/Kiste |
| `W_Starlight` (Galaxy + Sparkle) | Sternenlicht / Starlight | Mythic | Katalog/Kiste |
| `W_VIPGold` | VIP-Gold | Legendary | VIP-Pass |
| `W_RookieRainbow` (Rainbow) | Neuling-Regenbogen | Epic | Starter Pack |
| `W_MBronze` … `W_MPrism` (7 Stück) | Meisterschaft | – | B16.2 (nicht kaufbar) |
Pass-S1-Wraps (6): `W_S1_Neon`, `W_S1_Sunset`, `W_S1_Ice`, `W_S1_Gold`, `W_S1_Circuit` (Pulse), `W_S1_Champion` (Rainbow).

**Skins (8, Rezepte in WeaponModels):** `S_PopRifle_WaterBlaster` (Epic, Katalog/Kiste) · `S_BuzzSMG_HairDryer` (Epic) ·
`S_Scatter_BubbleBath` (Rare) · `S_Longshot_PoolNoodle` (Legendary) · `S_BonkHammer_Baguette` (Legendary) · `S_PopGrenade_RubberDuck` (Mythic) ·
`S_PipPistol_RayGun` (Epic, **Pass S1 Premium Stufe 1**) · `S_PopRifle_CarrotCannon` (Legendary, **Pass S1 Premium Stufe 30**).

**Charms (13):** `C_Duck`, `C_Dice`, `C_Star`, `C_Heart`, `C_Donut` (Common) · `C_MiniRocket`, `C_CubeBuddy` (Rare) · `C_Ghost` (Rare, Pass S1) ·
`C_Crown`, `C_Cactus` (Epic, Pass S1) · `C_Trophy` (Legendary, Pass S1) · `C_CalendarCat` (Login) · `C_StarterStar` (Starter Pack).

**Finisher (8):** `F_Confetti` (Standard) · `F_PixelBurst` (Rare) · `F_IceCube` (Epic) · `F_BalloonFloat` (Epic, Pass S1) · `F_GoldStatue` (Legendary) ·
`F_RainbowPuff` (Legendary, Pass S1) · `F_DuckRain` (Mythic) · `F_CrownConfetti` (VIP).

**Tracer (6):** `T_Team` (Standard) · `T_Gold`, `T_Bubble` (Rare) · `T_LaserPink` (Epic) · `T_Zigzag` (Epic, Pass S1) · `T_Rainbow` (Legendary, Pass S1).

„Pass S1“-Items stehen in `Config.Cosmetics.Exclusive`: während Saison 1 nur über den Pass, danach im Katalog. Alle übrigen Items mit
Rarity und ohne Sonderquelle sind im Katalog zum Listenpreis (B19-Kopf) kaufbar.

**Titel** (Ids `TT_…`): Level-Titel `TT_Lv10/25/50/75/100` (5), Erfolgs-Titel `TT_<ErfolgsId>` (10), Meisterschaft `TT_Master_<WeaponKey>`
(15 × „<Waffe>-Meister“, in `Config/Cosmetics` per Schleife erzeugt), `TT_Frischling` (Starter),
`TT_VIP`, `TT_Supporter`, `TT_S1Veteran` (Pass Gratis 30), `TT_PassHolderS1` (Premium 20), `TT_PartyStarter` (Party-Boost-Käufer), `TT_OnFire` (Login).

## B20. Kiste „Blaster-Kiste S1“, Quoten, Garantie, Splitter, PolicyService

### B20.1 Inhalt & Quoten (exakt, Summe 100,00 %)
Gewichte in Basispunkten (Summe 10.000), Server würfelt `Random:NextInteger(1, 10000)`; Anzeige = Gewicht/100.
| Rarity | Items | je Item | gesamt | Items |
|---|---|---|---|---|
| Common | 10 | 5,00 % | 50 % | W_Mint, W_Sky, W_Sunny, W_Bubblegum, W_Grape, W_Charcoal, C_Duck, C_Dice, C_Star, C_Heart |
| Rare | 6 | 5,00 % | 30 % | W_Ocean, W_Lemonade, W_Cherry, W_ToyCamo, S_Scatter_BubbleBath, T_Gold |
| Epic | 5 | 2,80 % | 14 % | W_NeonGrid, W_Candy, S_PopRifle_WaterBlaster, S_BuzzSMG_HairDryer, F_IceCube |
| Legendary | 2 | 2,50 % | 5 % | S_Longshot_PoolNoodle, F_GoldStatue |
| Mythic | 1 | 1,00 % | 1 % | S_PopGrenade_RubberDuck |
- **Preis:** 120 Gems pro Öffnung **oder** 1 Schlüssel. **Nur Einzel-Öffnungen** (keine Packs).
- **Garantie (Pity):** Nach 29 Öffnungen ohne Legendary/Mythic würfelt die 30. nur unter Legendary+Mythic (Gewichte 250/250/100 →
  41,67/41,67/16,67 %). Steht als Satz in „Details“. Zähler sichtbar („noch 12 bis zur Garantie“).
- **Duplikate → Splitter:** Common 20, Rare 50, Epic 150, Legendary 400, Mythic 800.
- **Splitter-Shop** (jedes Kisten-Item gezielt): Common 100, Rare 250, Epic 600, Legendary 1.500, Mythic 3.000.
- Jedes Kisten-Item ist zusätzlich **direkt** im Katalog für Gems kaufbar.
- Anzeige-Tabelle und Server-Wurf kommen aus derselben Tabelle `Config.Shop.Crates.S1` über `Shared/Odds.luau`.

### B20.2 PolicyService (WP9)
- `PolicyService:GetPolicyInfoForPlayerAsync(p)` **einmal** pro Spieler in `pcall`, Ergebnis gecacht.
  **Unbekannt oder Fehler = eingeschränkt.** State-Key `RandomAllowed` (`nil` bis bekannt).
- `ArePaidRandomItemsRestricted == true` oder unbekannt → Gem-Öffnung **versteckt und vom Server abgelehnt**
  („In deiner Region nicht verfügbar“). Öffnen mit (gratis) Schlüsseln bleibt erlaubt. Katalog, Splitter-Shop, Pass, Gems bleiben erlaubt.
- Versteckt bis „erlaubt“ bekannt: Gem-Kisten-Karten, **Kisten-Automat in der Lobby** (lokal versteckt), Kisten-Funde-Ansagen
  (Server schickt sie nur an Spieler mit `RandomAllowed == true`).
- Debug: `Config.Debug.ForceRestricted` und Admin „Policy simulieren erlaubt/eingeschränkt“.
- Kein Robux-Produkt gewährt ein Zufallsitem; Pass-Belohnungen/Produkte enthalten nie Schlüssel.

## B21. Shop & Clutch Pass

### B21.1 Shop-Fenster (WP9)
Tabs: **Waffen** (Coins, „Gratis testen“-Knopf → Range) · **Täglich im Rampenlicht** (6 Items, −20 % Gems, Rotation nach UTC-Tag-Seed,
überall gleich; Timer „wechselt in 7h 40m“) · **Katalog** (alle nicht-exklusiven Kosmetik zum Listenpreis) · **Kisten** (nur wenn erlaubt; mit Schlüssel immer) ·
**Splitter** · **Gems & Pässe** (Robux, `UI.FetchPrice`). Kopf-Banner: „ALLE WAFFEN ERSPIELBAR – KEIN PAY-TO-WIN“.
Produkte mit `Id = 0` zeigen „Bald verfügbar / Not set up yet“.

### B21.2 Clutch Pass Saison 1 (`Config/Season.luau`)
- 30 Stufen × **3.000 Pass-XP** (90.000 gesamt), Saison 8 Wochen. Pass-XP = Match-XP (inkl. Multiplikatoren) + Quests (täglich 300, wöchentlich 1.500) + Login 100/Tag.
  Ein Spieler an 3 Tagen/Woche schafft alle 30 Stufen; 2 Tage/Woche ≈ Stufe 20.
- **Gratis-Spur** (jede 2. Stufe = 15 Belohnungen): Coins 300 ×5 (2,6,10,14,18), Schlüssel ×4 (4,12,20,28), 30 Gems ×5 (8,16,22,24,26 → 150 Gems), Titel `TT_S1Veteran` (30).
- **Premium-Spur** (jede Stufe, 30): Skins `S_PipPistol_RayGun` (1) und `S_PopRifle_CarrotCannon` (30), 6 Wraps W_S1_* (3,7,11,15,19,27),
  2 Finisher (`F_RainbowPuff` 13, `F_BalloonFloat` 23), 4 Charms (`C_Ghost` 5, `C_Cactus` 9, `C_Crown` 17, `C_Trophy` 25),
  2 Tracer (`T_Zigzag` 21, `T_Rainbow` 29), Titel `TT_PassHolderS1` (20), Gems 50 bei 2,6,10,14,18,22,26 + 100 bei 28 (= 450 Gems zurück),
  restliche Stufen Splitter 100. **Keine Coins, keine Schlüssel in Premium.**
- **Rückwirkend:** Premium schaltet alle bereits erreichten Premium-Stufen frei („18 Belohnungen warten“).
- Einlösen idempotent pro Stufe und Spur. Saison-Ids werden nie wiederverwendet.
- **Fallback:** Passt kein Datumsfenster, bleibt die Saison mit dem jüngsten `StartUtc ≤ jetzt` aktiv; liegt jetzt vor der ersten,
  ist Saison 1 aktiv. Das Spiel funktioniert immer.
- S1: `StartUtc = "2026-10-15T00:00:00Z"`, `EndUtc = "2026-12-10T00:00:00Z"`. Anleitung: Block kopieren für S2.

## B22. GamePasses & Developer Products (`Config.Shop`, `Id = 0` bis der Besitzer sie anlegt)

### B22.1 GamePasses (dauerhaft)
| Key | Name DE / EN | Preis | Inhalt |
|---|---|---|---|
| `VIP` | VIP | **349 R$** | +20 % XP & Pass-XP (keine Coins), goldener VIP-Chat-Tag + goldenes Namensschild + Titel `TT_VIP`, Wrap `W_VIPGold` (alle Waffen), Finisher `F_CrownConfetti`, +1 Tages-Reroll, +1 Glücksrad-Dreh, VIP-Balkon |
| `DoubleXP` | Doppelte XP / Double XP | **299 R$** | ×2 Match-XP dauerhaft (zählt in Deckel ×3) |
| `LoadoutPlus` | Loadout+ | **99 R$** | 8 Loadout-Vorlagen statt 3, Namen ändern, „Zufall aus Favoriten“ |
| `MasteryBoost` | Meisterschafts-Boost / Mastery Boost | **199 R$** | ×2 Meisterschafts-Fortschritt (nur Kosmetik-Tempo) |

### B22.2 Developer Products
| Key | Name | Preis | Gewährt | Regel |
|---|---|---|---|---|
| `Gems120` | Handvoll Gems / Handful of Gems | **99 R$** | 120 Gems | erster Kauf ×2 |
| `Gems250` | Beutel Gems / Pouch of Gems | **199 R$** | 250 | erster Kauf ×2 |
| `Gems500` | Sack Gems / Sack of Gems | **399 R$** | 500 | erster Kauf ×2 |
| `Gems1000` | Kiste Gems / Crate of Gems | **749 R$** | 1.000 | erster Kauf ×2 |
| `Gems2200` | Truhe Gems / Chest of Gems | **1.499 R$** | 2.200 | „Beliebt“, erster Kauf ×2 |
| `Gems5000` | Tresor Gems / Vault of Gems | **2.999 R$** | 5.000 | „Bester Wert“, erster Kauf ×2 |
| `StarterPack` | Starter-Paket / Starter Pack | **49 R$** | 250 Gems + `W_RookieRainbow` + `C_StarterStar` + `TT_Frischling` | einmal; Wiederholung → 120 Gems |
| `PassPremium` | Clutch Pass Premium (Saison) | **449 R$** | Premium-Spur der aktiven Saison | bereits besessen → 500 Gems |
| `PassBundle` | Clutch Pass Premium + 10 Stufen | **899 R$** | Premium + 10 Stufen | bereits besessen → 10 Stufen + 500 Gems |
| `PassTier1` | +1 Pass-Stufe | **49 R$** | 1 Stufe | gedeckelt auf Reststufen, Rest → 40 Gems je Stufe |
| `PassTier10` | +10 Pass-Stufen | **349 R$** | 10 Stufen | dito |
| `XPBoost30` | XP-Boost 30 min | **39 R$** | ×2 XP (Echtzeit), verlängert `Boosts.XP2Until`, max. 24 h | |
| `XPBoost120` | XP-Boost 2 h | **99 R$** | ×2 XP 2 h | |
| `PartyBoost` | Party-Boost (ganzer Server) | **199 R$** | **alle** auf dem Server ×2 XP für 15 min (stapelbar bis 60 min), Ansage „<Name> hat den Server geboostet!“, Titel `TT_PartyStarter` | nur XP |
| `Support49` / `Support499` | Unterstütze den Entwickler / Support the Dev | **49 / 499 R$** | Titel `TT_Supporter` + Herz im Namensschild | reine Spende |
**Nie verkauft:** Waffen, Coins, Schlüssel, Splitter, Werte, Wiederbelebungen, Matchmaking-Vorteile, Serien-Wiederherstellung.

### B22.3 ProcessReceipt (WP9, REUSE §7 + §14.3 Fixes)
1. Callback früh in `Start` setzen. Unbekanntes Produkt → `NotProcessedYet`.
2. Bis zu 60 s auf das Profil warten (nicht sofort `NotProcessedYet`).
3. Läuft dieselbe `PurchaseId` schon → warten, dann `Receipts` erneut prüfen.
4. Alles Yieldende zuerst (`prepare`), dann **ohne Yield** gewähren + Beleg einfügen (letzte 60 behalten).
5. `PurchaseGranted` erst nach erfolgreichem `DataService.Save`. Gewährungen sind alles-oder-nichts.
6. Eingeschränkter Spieler + Zufallsprodukt gibt es nicht (keins ist zufällig) – trotzdem Prüfung im Code.

## B23. Monetarisierungs-Leitplanken (harte Regeln)
1. Kein Angebot während einer Live-Runde. **Max. 1 Angebots-Popup pro Sitzung** (`MonetizationService.TryOffer`).
2. Starter-Pack-Karte **einmal** im Ergebnis des ersten echten Siegs (großer „Später“-Knopf), danach 72 h im Shop.
3. Keine Fake-Timer unter 24 h, keine Beinahe-Treffer-Animationen, keine ablaufende Premium-Währung, keine Packs, keine bezahlten Drehs.
4. Schlüssel nie mit Robux erreichbar. Jeder Gem-Preis = genau ein Gem-Paket (120/250/500/1.000/2.200/5.000).
5. Doppelte Gems beim ersten Kauf jedes Pakets. Pass rückwirkend. Gesperrte Premium-Belohnungen im Ergebnis sichtbar.
6. Kein Kauf ändert Schaden, HP, Tempo, Hitbox, Information oder Matchmaking.

## B24. Sozial & Anti-Toxizität (v1)
- **Rematch, GG, Loben, Kopfgeld, Krone, Lobby-Ansagen** (Legendary+-Funde nur an erlaubte Spieler, Level 25/50/100, Kronen-Serien 3/5/10, neue #1 einer Tafel).
- **Freund im Server:** Toast „Dein Freund Lena ist hier!“ (Freundschaft per `Player:IsFriendsWithAsync` in pcall, max. 1 Toast pro Freund und Sitzung).
  Einladen-Knopf: `SocialService:PromptGameInvite(player)` (keine Belohnung).
- **Chat** (TextChatService): Client-Hook `TextChatService.OnIncomingMessage` – **nur Anzeige, nur Nachrichten anderer**,
  nur **ganze Nachricht oder ganze Wörter** (Groß/Klein egal, Satzzeichen getrennt): `ez`→„gg wp“, `ggez`→„GG ❤“, `noob`→„Freund/friend“,
  `p2w`→„faires Loadout/fair loadout“, `trash`→„gutes Spiel/good game“. **Nie** normale deutsche Wörter (z. B. „schlecht“).
  `PrefixText`: `[Besitzer]` gold, `[VIP]` gold, Level-Abzeichen, Titel.
- **Melden:** aus Scoreboard/Rückblick, 3 pro 10 min pro Melder, Server hängt Statistik-Schnappschuss an (B25 Moderation).
- Parties & Duell-Herausforderung: v1.1.

## B25. Admin-Panel (nur Besitzer)

### B25.1 Zugriff (exakt so)
- **Live:** `game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId and game.CreatorId ~= 0`.
- **Studio:** `RunService:IsStudio() and Config.Admin.StudioIsAdmin and (player.UserId > 0 or player.UserId == -1)`.
  Player2 (`−2`) ist **nie** Admin (Ablehnungspfad testbar). `Config.Admin.StudioAllPlayersAdmin = false`.
- Keine AdminUserIds, kein Kauf, keine Gruppen. Ergebnis gecacht → Attribut `IsAdmin` (+ `CanFly`). Client baut das Panel nur bei
  `IsAdmin == true`. **Server prüft jede Aktion erneut** – Rate-Limit 12/s **vor** der Admin-Prüfung; Ablehnung einmal pro Spieler loggen.
- Öffnen: Taste **P** oder rechter HUD-Knopf (Order 99). Fenster 720×600 (MH-Rahmen: Ziel-Feld, Statuszeile, `needsConfirm` 2. Klick ≤ 5 s, Slider, Listen).

### B25.2 Fairness-Schutz
Benutzt der Besitzer im Match eine Kraft (Aimbot, Silent Aim, Triggerbot, ESP, God, One-Shot, Rapid Fire, Inf Ammo, No Reload,
Speed/Jump, Noclip, Unsichtbar) oder eine Admin-Waffe → `MatchService.Taint(id)`. Tainted: kein MMR/Ranked, keine Bestenliste,
keine Siege/Niederlagen/Pops in den Statistiken der anderen, Gegner verlieren nichts (Serie bleibt), bekommen aber volle XP/Coins;
nicht in Balance-Statistiken. Rotes „TAINTED / Admin-Show“-Schild im HUD des Besitzers und im Intro.

### B25.3 Tabs & Aktionen (Admin-RemoteFunction, `(action, args) → {Ok, Message, Data}`)
| Tab | Aktionen (args) |
|---|---|
| **Spieler** | `GetPlayers()` → Liste {UserId, Name, Level, PingMs, MatchId, Suspicion} · `Kick{Target, Reason}` · `Ban{Target\|UserId, Duration ("1h"\|"1d"\|"7d"\|"30d"\|"perm"), Reason}` · `Unban{UserId}` · `BanList()` · `BanHistory{UserId}` (nur live) · `Warn{Target, Text ≤ 150}` · `Freeze{Target, On}` · `Bring{Target}` · `Goto{Target}` · `Pop{Target}` · `Heal{Target}` · `Give{Target, Grant}` (Coins/Gems/Keys/Shards/Waffen/Kosmetik) · `GiveXp{Target, Amount}` · `SetLevel{Target, Level}` · `PlayerData{Target}` · `Receipts{Target}` · `Regrant{Target, ProductKey}` · `ResetData{Target}` (2× bestätigen, Belege bleiben). Ziele: "me", "all", "others", Name, Präfix, UserId. Nie: sich selbst bannen, den Besitzer, `UserId ≤ 0`. Spectate = Client (Taste X). |
| **Kräfte** (eigene Attribute) | `SetPower{Name, Value}` mit Name ∈ `AdminAimbot`, `AdminSilentAim`, `AdminTriggerbot`, `AdminESP`, `CanFly`, `AdminNoclip`, `AdminSpeed` (16–150), `AdminJump` (7.2–100), `AdminGod`, `AdminInvisible`, `AdminInfAmmo`, `AdminNoReload`, `AdminRapidFire` (1–5), `AdminOneShot`. Server ehrt sie nur bei `IsAdmin`. |
| **Waffen & Items** | `Give{Target, Grant{Weapons, Cosmetics}}` · `GiveAll{Target}` · `AdminWeapon{Id 101–104}` (in den Primary-Slot im aktuellen Kontext). |
| **Match & Server** | `Matches()` → {MatchId, Slot, Mode, Map, Phase, Score, Players, Bots} · `EndMatch{MatchId}` · `StartMatch{Mode, Map, Mood, Mutator, UserIds, BotDifficulty, Bots}` · `SpawnBot{Difficulty}` (im eigenen Match/Range) · `FillPads()` · `LockServer{On}` · `KickAll{Reason}` · `ServerInfo()` → Spieler, Bots, Slots, Projektile, Heartbeat-ms (Scheduler-Statistik), Speicher-MB, Uptime, Version, JobId. |
| **Events** | `Announce{Text ≤ 200, Global}` (MH-Stil: Avatar des Besitzers, blauer Name, selbstgezeichneter blauer Haken, kein Kasten, 8 s, Warteschlange 5; Filter `TextService:FilterStringAsync(..., PublicChat):GetNonChatStringForBroadcastAsync()`, Filter-Fehler → abgelehnt) · `AdminAbuse{Minutes 1–60, Coins2, Xp2, Global}` (Ende synchron `Until = GetServerTimeNow() + s`) · `Mutator{Key\|nil, Global}` · `Confetti()` · `LobbyGravity{Value 50–196.2}` · `LobbyLook{Mood}`. |
| **Balance (Live)** | `GetBalance()` → {Version, Defaults, Overrides, Disabled, History} · `SetField{Weapon, Field, Value}` (nur dieser Server, Vorschau) · `SaveBalance()` (alle Server) · `Revert{Version}` · `ResetWeapon{Weapon}` · `SetEnabled{Weapon, On}` (Not-Aus). Felder & Grenzen: C15 `Config.Weapons.BalanceFields`. |
| **Statistik** | `GetStats{Days 1\|7}` → pro Waffe Picks, Pops, Pops/Match, Siegquote wenn ausgerüstet, Kopf-%, Genauigkeit; pro Map Picks; Modus-Beliebtheit; Bot-vs-Mensch-Anteil; Ø Wartezeit. „Buff zuerst“-Markierung (Pick < 3 %). |
| **Moderation** | `Flags()` (dieser Server + gespeicherte Shards) · `DismissFlag{Id}` · `Reports()` · Aktionen aus der Liste: Spectate, Ban 1d/7d/perm, Abweisen. |
| **Debug** | `SimulatePurchase{ProductKey}` (gleiche Grant-Funktion wie ProcessReceipt) · `SimulatePolicy{Allowed: true\|false\|nil}` · `SkipDay()` (nur Studio: Tagesindex +1) · `UnlockAll()` (nur selbst, taint-frei nur in Studio) · `SetDebug{ShowHitboxes, LogRejects, BotPaths}` · `RunSelfTest()`. F8 = Debug-Overlay (Scheduler-ms, Slot-Zustände, Bots, letzter abgelehnter Schuss + Grund). |

### B25.4 Bann-Regeln (`Players:BanAsync`, in pcall)
`UserIds` (≤ 50), `Duration = math.max(60, floor(Tage × 86400))` oder `−1` (permanent; 0 ungültig), `DisplayReason` auf 400 Zeichen gekürzt,
`PrivateReason` (Beweis-Zusammenfassung) auf 1000, `ApplyToUniverse = true`, `ExcludeAltAccounts = false`. Benötigt `Players.BanningEnabled = true`
(Rojo). Unban: `UnbanAsync({UserIds, ApplyToUniverse = true})`. `GetBanHistoryAsync` nur live. Bann-Log (letzte 100) in `CC_Mod_v1` Key `BanLog`.
Regeln + Einspruchs-Hinweis im Einstellungen-Tab „Info“.

---

# C) Technische Architektur

## C1. Tooling & Projekt-Einstellungen (WP1)

### C1.1 Werkzeuge (geprüft 2026-10-11)
Rojo 7.7.1 · StyLua 2.5.2 (`syntax="Luau"`, `indent_type="Tabs"`, `column_width=120`) · selene 0.31.0 (`std = "rbx"`) ·
luau-lsp 1.70.1 (`/tmp/luau-lsp/build/luau-lsp`) · Luau-CLI `<SP>/luau-build/luau` · Typdefinitionen
`SP=/tmp/claude-0/-home-user-website-test-demo-1/14caf8fd-3993-54cd-bb2d-9f5bab2d1eaf/scratchpad`, Datei `$SP/globalTypes.d.luau`.

`scripts/check.sh` (WP1) führt im Projektordner aus:
```sh
stylua --check src tests
selene src
rojo sourcemap default.project.json -o sourcemap.json
/tmp/luau-lsp/build/luau-lsp analyze --platform=roblox --definitions=$SP/globalTypes.d.luau --sourcemap=sourcemap.json src
rojo build default.project.json -o ClutchClash.rbxlx
for t in tests/*.test.luau; do $SP/luau-build/luau "$t" || exit 1; done
```
**Nie** in `roblox-meteor-heist` bauen oder Sourcemaps schreiben.

### C1.2 `default.project.json` (verifiziert: Rojo baut alle Properties und `StarterCharacterScripts.Health`)
```json
{
  "name": "ClutchClash",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": { "Shared": { "$path": "src/shared" } },
    "ServerScriptService": { "Server": { "$path": "src/server" } },
    "StarterPlayer": {
      "$properties": {
        "CameraMode": "Classic",
        "EnableMouseLockOption": false,
        "CharacterWalkSpeed": 16,
        "CharacterUseJumpPower": false,
        "CharacterJumpHeight": 7.2,
        "CameraMaxZoomDistance": 14
      },
      "StarterPlayerScripts": { "Client": { "$path": "src/client" } },
      "StarterCharacterScripts": { "$path": "src/character" }
    },
    "Players": { "$properties": { "BanningEnabled": true, "CharacterAutoLoads": true, "RespawnTime": 3 } },
    "Lighting": { "$properties": { "Technology": "ShadowMap" } },
    "Workspace": { "$properties": { "StreamingEnabled": false, "RejectCharacterDeletions": "Enabled", "ReplicateInstanceDestroySetting": "Enabled" } },
    "TextChatService": { "$properties": { "ChatVersion": "TextChatService" } },
    "StarterGui": { "$properties": { "ResetPlayerGuiOnSpawn": false } }
  }
}
```
Besitzer stellt in Studio ein (Rojo kann es nicht): Avatar **R15 + Skalierung Standard**, **Max Players 18**, API-Zugriff an,
Genre Shooter, Maturity-Fragebogen (C19).

### C1.3 `rbx.yml`
MH-Datei kopieren und anhängen (selene-geprüft laut Tech-Recherche):
```yaml
  OverlapParams: {any: true}
  DateTime: {any: true}
  Font: {any: true}
  PhysicalProperties: {any: true}
  BrickColor: {any: true}
  Rect: {any: true}
  Region3: {any: true}
  Ray: {any: true}
  Axes: {any: true}
  Faces: {any: true}
  Vector3int16: {any: true}
  time: {any: true}
  math.isfinite:
    args:
      - type: number
  math.isnan:
    args:
      - type: number
  math.isinf:
    args:
      - type: number
  debug.profilebegin:
    args:
      - type: string
  debug.profileend:
    args: []
```

### C1.4 Parallel-Regel für statische Checks
Während die Pakete parallel entstehen, darf luau-lsp in den eigenen Dateien nur `TypeError: Unknown require` für
**noch nicht existierende Module anderer WPs** melden – alles andere muss 0 sein. Nach dem Zusammenführen (Integration) gilt überall 0.
Config- und Lang-Kindmodule werden dynamisch geladen (`pcall(require, script:FindFirstChild(name))`), daher nie „Unknown require“.

## C2. Rojo-Baum & Dateiliste (jede Datei gehört genau einem WP)
```
roblox-shooter/
  default.project.json  rbx.yml  selene.toml  stylua.toml  .gitignore  scripts/check.sh      WP1
  ClutchClash.rbxlx                                   (Build, wird committet; Integration)
  ANLEITUNG.md                                        WP11
  docs/DESIGN.md (Lead) · ASSETS.md · REUSE.md · ADMIN-WUENSCHE.md   (bestehend, nicht ändern)
  docs/KOPIERVORLAGEN.md · docs/TESTPLAN.md           WP11
  tests/util.test.luau                                WP1
  tests/progressmath.test.luau                        WP8
  tests/odds.test.luau                                WP9
  src/character/Health.server.luau                    WP1   (leer, nur Kommentar)
  src/shared/                       -> ReplicatedStorage.Shared
    Config/init.luau                WP1     Config/Weapons.luau  WP3    Config/Combat.luau   WP3
    Config/Maps.luau                WP2     Config/Modes.luau    WP5    Config/Bots.luau     WP6
    Config/Security.luau            WP7     Config/Progression.luau WP8 Config/Season.luau  WP8
    Config/Cosmetics.luau           WP9     Config/Shop.luau     WP9    Config/Client.luau   WP10
    Lang/init.luau  Lang/Core.luau  WP1     Lang/World.luau WP2   Lang/Combat.luau WP3   Lang/Match.luau WP5
    Lang/Bots.luau WP6   Lang/Admin.luau WP7   Lang/Progress.luau WP8   Lang/Shop.luau Lang/Items.luau WP9   Lang/Ui.luau WP10
    Types.luau  Util.luau  Net.luau  Spring.luau                          WP1
    Spread.luau  Hitbox.luau  Damage.luau  Ballistics.luau                WP3
    WeaponModels.luau                                                     WP4
    ProgressMath.luau                                                     WP8
    CosmeticModels.luau  Odds.luau                                        WP9
  src/server/                       -> ServerScriptService.Server
    Main.server.luau  Lib/Scheduler.luau                                  WP1
    Services/Remotes.luau  Services/DataService.luau  Services/PlayerStateService.luau  Services/SelfTestService.luau   WP1
    Services/GraphicsService.luau  Services/ArenaService.luau  Services/LobbyBuilder.luau                              WP2
    World/MapKit.luau  World/NavBuilder.luau  World/LobbyLayout.luau
    World/Maps/PillarBox.luau  BlockYard.luau  NeonGrid.luau  CandyDocks.luau  SnowFort.luau  SkyGarden.luau  CrownRing.luau  WP2
    Services/HistoryService.luau  Services/CombatService.luau  Services/CharacterService.luau
    Services/ProjectileService.luau  Services/WeaponService.luau  Services/ReplicationService.luau                     WP3
    Services/QueueService.luau  Services/MatchService.luau  Modes/Rounds.luau  Modes/Respawn.luau                       WP5
    Services/BotService.luau  Services/RangeService.luau  Bot/BotRig.luau  Bot/BotBrain.luau  Bot/Pathfind.luau         WP6
    Services/AntiCheatService.luau  Services/AdminService.luau  Services/BalanceService.luau                           WP7
    Services/ProgressionService.luau  Services/RewardService.luau  Services/CommunityService.luau
    Services/LeaderboardService.luau  Services/MetricsService.luau                                                     WP8
    Services/MonetizationService.luau  Services/ShopService.luau                                                       WP9
    Tests/CoreTests.luau WP1 · Tests/WorldTests.luau WP2 · Tests/CombatTests.luau WP3 · Tests/MatchTests.luau WP5 ·
    Tests/ProgressionTests.luau WP8 · Tests/EconomyTests.luau WP9
  src/client/                       -> StarterPlayer.StarterPlayerScripts.Client
    Main.client.luau                                                      WP10
    Modules/UI  Hooks  Controls  TouchControls  Hud  CombatHud  Settings  Effects  CombatFX  Sfx  Highlights   (.luau)  WP10
    Modules/ArenaLook.luau                                                WP2
    Modules/FpsCamera  AimAssist  Viewmodel  WeaponClient  Movement  Replication                              WP4
    Modules/QueueUI  MatchUI  Spectate  Scoreboard  Tutorial                                                  WP5
    Modules/BotAnimator  Training                                                                             WP6
    Modules/AdminPanel  AdminTools  Fly  PhotoMode  DebugOverlay                                              WP7
    Modules/Progress  ChatClient                                                                              WP8
    Modules/Shop  Locker  CrateReveal  Finishers                                                              WP9
```
Pfade im Code: Server-Services `script.Parent:WaitForChild("X")` nur für Nicht-Service-Module (`Lib`, `World`, `Bot`, `Modes`, `Tests`
über `script.Parent.Parent`). Shared: `ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Name")`.

## C3. Server-Ladereihenfolge & Konventionen (WP1 `Main.server.luau`, MH-Lader 1:1)
Reihenfolge (`order`):
```
DataService, MonetizationService, PlayerStateService, GraphicsService, ArenaService, LobbyBuilder,
HistoryService, CombatService, CharacterService, ProjectileService, WeaponService, ReplicationService,
AntiCheatService, BotService, RangeService, MatchService, QueueService, ProgressionService, RewardService,
CommunityService, ShopService, BalanceService, AdminService, LeaderboardService, MetricsService, SelfTestService
```
- Phase 1: alle `require` (xpcall). Phase 2: `Init(Services)` in Reihenfolge. Phase 3: `Start()` für alle außer DataService.
  Phase 4: `DataService.Start()` **zuletzt**. Fehler in einem Service → `warn("[Clutch Clash] …")`, Rest läuft weiter.
- Modul-Form: `local X = {}`, `local Services: any`, `function X.Init(services) Services = services end`, `function X.Start() end`, `return X`.
- **Init** baut Welt/Instanzen, keine Spieler-Logik. ArenaService.Init registriert Kollisionsgruppen und baut Templates **vor** LobbyBuilder.
- Aufrufe anderer Services nur zur Laufzeit: `Services.X.Fn(...)`. Optionale Dienste (Progression, Reward, Community, Leaderboard,
  Balance, Admin, Metrics, Shop-Kosmetik) **immer** über `pcall`.
- Schleifen nur über `Lib/Scheduler` (C5.1). Spieler, die beim Start schon da sind: `for _, p in Players:GetPlayers() do task.spawn(onPlayer, p) end`.
- Jede Pro-Spieler-Tabelle bei `PlayerRemoving` leeren.

## C4. `Shared/Types.luau` (WP1, vollständig – alle Pakete annotieren damit)
```lua
--!strict
export type Lang = "de" | "en"
export type SlotName = "Primary" | "Secondary" | "Melee" | "Utility"
export type Loadout = { Primary: string, Secondary: string, Melee: string, Utility: string }
export type NotifyKind = "Info" | "Success" | "Error" | "Event" | "Alarm" | "Announce"
export type Reply = { Ok: boolean, Message: string?, [string]: any }
export type Grant = {
	Coins: number?, Gems: number?, Keys: number?, Shards: number?,
	Weapons: { string }?, Cosmetics: { string }?, FreeWeaponPicks: number?,
	PassPremium: boolean?, PassTiers: number?, XpBoostSeconds: number?,
}
export type Currency = "Coins" | "Gems" | "Keys" | "Shards"
export type WeaponKind = "Hitscan" | "Projectile" | "Melee" | "Throwable" | "Consumable"
export type ProjectileDef = {
	Speed: number, Gravity: number, Lifetime: number, Radius: number, SplashMax: number, SplashMin: number,
	Direct: number?, Bounces: number?, Restitution: number?, Fuse: number?, SelfMult: number, PopOnLand: boolean?,
}
export type MeleeDef = {
	Range: number, Cone: number, Windup: number?, Knockback: Vector3?, AirJump: boolean?,
	Block: { Mult: number, Cone: number, Max: number, Cooldown: number, MoveMult: number }?,
}
export type WeaponDef = {
	Id: number, Key: string, Slot: SlotName, Kind: WeaponKind, Name: { de: string, en: string }, Short: string,
	Damage: number, MinMult: number, HeadMult: number, FireMode: "Auto" | "Semi" | "Burst" | "Single",
	Interval: number, BurstCount: number?, BurstInterval: number?, Pellets: number, Mag: number, Reload: number,
	Equip: number, SpreadHip: number, SpreadAds: number, SpreadMove: number, SpreadAir: number,
	BloomPerShot: number, BloomMax: number, FalloffStart: number, FalloffEnd: number, Range: number,
	AdsZoom: number, AdsTime: number, MoveMult: number, AdsMoveMult: number,
	RecoilPitch: number, RecoilYaw: number, RecoilRecover: number,
	Projectile: ProjectileDef?, Melee: MeleeDef?,
	Heal: { Amount: number, Duration: number, UseTime: number }?, Smoke: { Radius: number, Duration: number }?,
	Charges: number?, Cooldown: number?, Price: number, Free: boolean, AdminOnly: boolean?,
	Model: string, Sound: string, Enabled: boolean,
}
export type CombatantKind = "Player" | "Bot" | "Dummy"
export type AmmoState = { Mag: number, ReloadUntil: number, Charges: number, CooldownUntil: number, BurstLeft: number }
export type Combatant = {
	Id: number, -- UserId (>0 live; -1..-999 Studio) | Bot -1001 abwärts | Puppe -5001 abwärts
	Kind: CombatantKind, Player: Player?, Name: string,
	Model: Model, Root: BasePart, Head: BasePart, Humanoid: Humanoid?,
	Ctx: string, Team: number, Slot: number, -- Roster-Slot 1..32 im Kontext (u8 in Buffern)
	Hp: number, MaxHp: number, Alive: boolean, ShieldUntil: number,
	Loadout: Loadout, Equipped: SlotName, EquipReadyAt: number, Ammo: { [SlotName]: AmmoState },
	Ads: boolean, AdsSince: number, Blocking: boolean, BlockUntil: number, BlockCooldownUntil: number,
	HealUntil: number, Salt: number, LastShotId: number, LastShotT: number, ShotTimes: { number },
	LastDamagerId: number?, LastDamageAt: number, Difficulty: string?, IsAdmin: boolean,
}
export type NavGraph = { Nodes: { { P: Vector3, Cover: boolean } }, Edges: { { number } } }
export type Arena = {
	Slot: number, Key: string, BuildId: number, Model: Model, Origin: CFrame,
	Spawns: { A: { CFrame }, B: { CFrame }, FFA: { CFrame } }, Zone: Vector3, ZoneRadius: number,
	KillY: number, Vault: CFrame, Nav: NavGraph, MapParams: RaycastParams,
}
export type ContextRules = {
	DamageMult: number, HeadOnly: boolean, HeadRadiusMult: number, IntervalMult: number, ReloadMult: number,
	SpeedMult: number, GravityLift: number, AllowedSlots: { [SlotName]: boolean }?, ForcedLoadout: Loadout?,
	RandomLoadout: boolean, Regen: boolean, UtilityMode: "Charges" | "Cooldown", FriendlyFire: boolean,
	IgnoreOwnership: boolean, -- Range/Practice/LuckyLoadout: jede Waffe erlaubt
}
export type ContextInfo = {
	Ctx: string, Arena: Arena, Rules: ContextRules, Recipients: () -> { Player }, MatchId: number?,
}
export type DamageInfo = { WeaponKey: string, Head: boolean, Kind: "Hitscan" | "Splash" | "Melee" | "Void" | "Admin" | "Fallback", Dist: number, From: Vector3 }
export type ElimInfo = { WeaponKey: string, Head: boolean, Kind: string, KillerId: number?, Assists: { number }, Pos: Vector3,
	KillerSliding: boolean?, Melee: boolean?, Splash: boolean?, Void: boolean? }
export type RecapHit = { W: string, D: number, H: boolean, Dist: number, T: number }
export type RecapData = { KillerId: number?, KillerName: string, KillerHp: number, WeaponKey: string, Taken: { RecapHit }, DealtToKiller: number, DealtHits: number, DealtHeads: number }
export type BotRequest = { Bot: true, Difficulty: string }
export type MatchSpec = {
	Mode: string, Teams: { { Player | BotRequest } }, Map: string?, Mood: string?, Mutator: string?,
	Tutorial: boolean?, RematchOf: number?, AdminStarted: boolean?,
}
export type PlayerResult = {
	Team: number, Won: boolean, Draw: boolean, Left: boolean, AfkRemoved: boolean, RoundsWon: number, Elims: number,
	PvpElims: number, Headshots: number, MeleeElims: number, Assists: number, Damage: number, Deaths: number,
	Mvp: boolean, Flawless: number, Clutches: number, Aces: number, OvertimeCaps: number, CrownDefences: number,
	CrownVsHuman: number, BountyClaimed: number, WeaponKills: { [string]: number }, WeaponUsed: { [string]: boolean },
	ShotsFired: number, ShotsHit: number, Comeback: boolean,
}
export type MatchResult = {
	MatchId: number, Mode: string, Map: string, Winner: number, Draw: boolean, Tainted: boolean,
	VsBots: boolean, Practice: boolean, Tutorial: boolean, Duration: number, PerPlayer: { [Player]: PlayerResult },
}
export type MapPart = {
	Shape: "Block" | "Wedge" | "Cylinder" | "Ball" | "CornerWedge", Pos: Vector3, Size: Vector3,
	Rot: Vector3?, -- Grad (X,Y,Z)
	HighEnd: number?, -- Wedge: z-Wert des hohen Endes (lokal)
	Color: string | Color3, Material: string?, Transparency: number?, CanCollide: boolean?,
	Center: boolean?, Mirror: boolean?, Tag: string?, Text: string?, -- Text = SurfaceGui-Buchstabe
	Barrier: boolean?, -- unsichtbare ArenaBarrier
}
export type MapLayout = {
	Key: string, Size: Vector3, WallHeight: number, Parts: { MapPart },
	SpawnsA: { Vector3 }, FFA: { Vector3 }?, Zone: Vector3, ZoneRadius: number?,
	CoverNodes: { Vector3 }, CustomBounds: { Min: Vector3, Max: Vector3 }?, KillY: number?,
}
export type PlayerData = { [string]: any } -- Schema siehe C13
```

## C5. Öffentliche Server-APIs (Verträge; Aufruf über `Services.<Name>`)

### C5.1 `Lib/Scheduler` (WP1, normales Modul, per `require`)
```lua
Scheduler.Every(name: string, hz: number, fn: (dt: number) -> ())
Scheduler.EveryFrame(name: string, fn: (dt: number) -> ())
Scheduler.Staggered<T>(name: string, hz: number, items: () -> { T }, fn: (item: T, dt: number) -> ())
	-- verteilt die Items über die Frames, jedes Item hz-mal pro Sekunde
Scheduler.Stats(): { [string]: { AvgMs: number, MaxMs: number } }
```
Ein `RunService.Heartbeat`-Anschluss; jeder Callback in `pcall`; Fehler höchstens alle 10 s pro Name loggen; dt auf 0..0.25 geklemmt.

### C5.2 WP1
```lua
-- Services/Remotes.luau: erstellt idempotent alle Remotes aus Net.RemoteList (C8) unter ReplicatedStorage.Remotes
Remotes: { [string]: RemoteEvent | RemoteFunction | UnreliableRemoteEvent }

-- DataService (MH + REUSE §14.3-Fixes)
DataService.Get(p: Player): PlayerData?
DataService.IsLoaded(p: Player): boolean
DataService.IsNoSave(p: Player): boolean
DataService.OnProfileLoaded(cb: (p: Player, data: PlayerData) -> ())
DataService.OnProfileReleasing(cb: (p: Player, data: PlayerData) -> ())
DataService.Save(p: Player): boolean            -- yieldet; NoSave → true
DataService.Reset(p: Player): boolean           -- behält Purchases.Receipts/Starter/PassSeasons/FirstPack

-- PlayerStateService (MH-EconomyService-Muster)
PlayerStateService.Handle(action: string, fn: (p: Player, arg: any) -> Types.Reply,
	opts: { Rate: number?, Per: number?, NeedsReady: boolean? }?)   -- Std: 8/1 s, NeedsReady true
PlayerStateService.Provide(key: string, fn: (p: Player) -> any)    -- State-Schlüssel-Lieferant
PlayerStateService.MarkDirty(p: Player, ...: string)               -- Flush alle 0.2 s, voller State alle 20 s
PlayerStateService.Notify(p: Player, key: string, args: { any }?, kind: Types.NotifyKind?)
PlayerStateService.NotifyAll(key: string, args: { any }?, kind: Types.NotifyKind?, filter: ((Player) -> boolean)?)
PlayerStateService.NotifyRaw(p: Player, text: string, kind: Types.NotifyKind?)  -- bereits lokalisiert/gefiltert
PlayerStateService.Effect(p: Player, name: string, strength: number, data: any?)
PlayerStateService.EffectAll(name: string, strength: number, data: any?, filter: ((Player) -> boolean)?)
PlayerStateService.IsReady(p: Player): boolean
PlayerStateService.OnReady(cb: (p: Player) -> ())      -- nach Profil + LoadPasses + Policy-Anfrage gestartet
PlayerStateService.LangOf(p: Player): Types.Lang
PlayerStateService.SetLeaderstat(p: Player, name: "Level" | "Wins", value: number)
-- eigene Handler: "GetFull", "SaveSettings" (Schema Config.Client.SettingsSchema), "TutorialFlag"

-- SelfTestService (nur Studio und Config.Studio.SelfTest): lädt alle ModuleScripts in Server.Tests,
-- jedes gibt { [testName]: () -> () } zurück (Fehler = FAIL); Ausgabe "[SelfTest] n/n PASS".
SelfTestService.Run(): (number, number)
```

### C5.3 WP2
```lua
ArenaService.Acquire(mapKey: string): Types.Arena?      -- Slot 1..8, warm bevorzugt (B9.2)
ArenaService.Release(arena: Types.Arena)
ArenaService.FreeSlots(): number
ArenaService.Crown(): Types.Arena                        -- fester Slot 0
ArenaService.Range(): Types.Arena                        -- Lobby-Range als Arena (Spawns leer, Vault ungenutzt)
ArenaService.MapsFor(modeKey: string, teamSize: number): { string }
ArenaService.LobbySpawn(): CFrame                        -- zufälliger Lobby-Spawn
ArenaService.Layout(mapKey: string): Types.MapLayout?
ArenaService.SlotStates(): { { Slot: number, State: string, MapKey: string? } }

LobbyBuilder.Pads(): { { Id: number, Mode: string, Part: BasePart, Center: Vector3,
	SeatsA: { Vector3 }, SeatsB: { Vector3 } } }        -- FFA: alle Sitze in SeatsA
LobbyBuilder.RangeZone(): (CFrame, Vector3)
LobbyBuilder.RangeDummySpots(): { { Pos: Vector3, Moving: boolean } }
LobbyBuilder.CrownLine(): { Vector3 }                   -- 6 Kreise
LobbyBuilder.CrownBoard(): BasePart
LobbyBuilder.Boards(): { [string]: BasePart }           -- "Wins","Elims","BestStreak","TotalXP","WeeklyWins","CrownBest"
LobbyBuilder.VipZone(): (CFrame, Vector3)
LobbyBuilder.CrateMachine(): Model
LobbyBuilder.BotBooth(): { { Pos: Vector3, Difficulty: string } }

GraphicsService.ApplyLobbyLook()                        -- einmal in Init; Lighting danach nie wieder serverseitig ändern
```

### C5.4 WP3
```lua
HistoryService.Track(c: Types.Combatant)
HistoryService.Untrack(c: Types.Combatant)
HistoryService.Sample(c: Types.Combatant, t: number): (CFrame?, Vector3?)        -- rootCF, headPos (gelerpt)
HistoryService.SampleWindow(c: Types.Combatant, t: number): { { Root: CFrame, Head: Vector3 } } -- T-0.075, T, T+0.075
HistoryService.Speed(c: Types.Combatant, t: number): number                      -- horizontal Studs/s

CombatService.NewCombatant(p: { Kind: Types.CombatantKind, Player: Player?, Model: Model, Ctx: string, Team: number,
	Slot: number, Name: string, Loadout: Types.Loadout, Difficulty: string?, MaxHp: number? }): Types.Combatant
CombatService.Register(c: Types.Combatant)       -- setzt Attribute CombatantId/Ctx/Team/Alive/Hp, Salt, sendet Combat("Armed")
CombatService.Unregister(c: Types.Combatant)     -- sendet Combat("Disarmed")
CombatService.Get(id: number): Types.Combatant?
CombatService.OfPlayer(p: Player): Types.Combatant?
CombatService.InCtx(ctx: string): { Types.Combatant }
CombatService.RegisterContext(info: Types.ContextInfo)
CombatService.UnregisterContext(ctx: string)
CombatService.Context(ctx: string): Types.ContextInfo?
CombatService.ApplyDamage(attacker: Types.Combatant?, victim: Types.Combatant, amount: number, info: Types.DamageInfo): (number, boolean)
CombatService.Heal(c: Types.Combatant, amount: number): number
CombatService.Eliminate(victim: Types.Combatant, info: Types.ElimInfo)
CombatService.Revive(c: Types.Combatant, at: CFrame, shieldSeconds: number?)
CombatService.SetShield(c: Types.Combatant, seconds: number)
CombatService.ResetRound(ctx: string)              -- Rundenschadens-Log + Recap leeren
CombatService.Recap(victimId: number): Types.RecapData?
CombatService.RoundDamage(ctx: string): { [number]: number }
CombatService.TeamHp(ctx: string, team: number): number
CombatService.OnDamage(cb: (attacker: Types.Combatant?, victim: Types.Combatant, dealt: number, info: Types.DamageInfo) -> ())
CombatService.OnElimination(cb: (victim: Types.Combatant, killer: Types.Combatant?, info: Types.ElimInfo) -> ())

CharacterService.SetRouter(fn: (p: Player, char: Model) -> ("Lobby" | "Vault" | "Spawn", CFrame?))  -- MatchService registriert
CharacterService.Teleport(target: Player | Types.Combatant, cf: CFrame)   -- PivotTo + AntiCheat.NoteTeleport
CharacterService.Freeze(c: Types.Combatant, on: boolean)                  -- HRP verankern (Prep/Admin)
CharacterService.Pop(c: Types.Combatant)                                  -- in den Vault des Kontexts
CharacterService.Unpop(c: Types.Combatant, at: CFrame)
CharacterService.SetBaseSpeed(c: Types.Combatant, speed: number)          -- Attribut BaseSpeed (+ Humanoid.WalkSpeed bei Bots)
CharacterService.BuildGunVisuals(c: Types.Combatant)                      -- 4 Modelle, Kosmetik via ShopService.GetCosmetics (pcall)
CharacterService.ShowSlot(c: Types.Combatant, slot: Types.SlotName)
CharacterService.ClearGunVisuals(c: Types.Combatant)
CharacterService.SetNameplate(model: Model, info: { Name: string, Level: number, Title: string, Team: number?,
	IsBot: boolean, Crown: boolean?, Bounty: number?, Vip: boolean?, Supporter: boolean? })
	-- Spieler: Infos kommen automatisch aus Player-Attributen Level/Title/Vip/Supporter/Bounty (gesetzt von WP8/WP9),
	-- CharacterService hört auf deren Änderung; SetNameplate direkt nur für Bots/Puppen
CharacterService.SetHeadProp(model: Model, kind: "Crown" | nil)
CharacterService.InVault(p: Player): boolean

WeaponService.SetLoadout(c: Types.Combatant, loadout: Types.Loadout)
WeaponService.ResetForRound(c: Types.Combatant)
WeaponService.Equip(c: Types.Combatant, slot: Types.SlotName)
WeaponService.ServerFire(c: Types.Combatant, aim: Vector3, opts: { ForceMiss: boolean? }?): boolean   -- Bots
WeaponService.ServerMelee(c: Types.Combatant, target: Types.Combatant?): boolean
WeaponService.ServerThrow(c: Types.Combatant, aim: Vector3, charge: number): boolean
WeaponService.ServerUse(c: Types.Combatant): boolean
WeaponService.GiveAdminWeapon(p: Player, id: number): boolean
WeaponService.OnShot(cb: (c: Types.Combatant, def: Types.WeaponDef, hits: number, heads: number) -> ())

ProjectileService.Spawn(owner: Types.Combatant, def: Types.WeaponDef, origin: Vector3, velocity: Vector3, age: number, shotId: number): number?
ProjectileService.ClearCtx(ctx: string)
ProjectileService.IsSmoked(ctx: string, a: Vector3, b: Vector3): boolean
ProjectileService.Count(): number

ReplicationService.QueueFx(ctx: string, kind: number, slot: number, weaponId: number, origin: Vector3, endPos: Vector3)
ReplicationService.FireCtx(ctx: string, remoteName: string, ...: any)    -- zuverlässig an Context.Recipients()
ReplicationService.LastInput(p: Player): number      -- Server-Zeit der letzten Look/Fire/WeaponAction (AFK)
ReplicationService.Flags(p: Player): number          -- letzte Look-Flags (Net.LookFlags), z. B. Slide für Quests
-- zählt Rutsch-Starts (Flag-Wechsel) und ruft RewardService.Track(p, "Slide", 1) über pcall
```

### C5.5 WP5
```lua
QueueService.Join(p: Player, modeKey: string, source: { Pad: number?, Side: ("A" | "B")? }?): (boolean, string?)
QueueService.Leave(p: Player)
QueueService.StateOf(p: Player): { Mode: string, Since: number, BotAt: number?, Searching: number }?
QueueService.Searching(modeKey: string): number
QueueService.FillNow(p: Player): boolean
QueueService.CrownJoin(p: Player): (boolean, string?)
QueueService.CrownLeave(p: Player)
QueueService.CrownKing(): Player?
QueueService.ForceFillPads()                        -- Admin

MatchService.Create(spec: Types.MatchSpec): number?
MatchService.End(id: number, reason: string)
MatchService.MatchOf(p: Player): number?
MatchService.Members(id: number): { Player }
MatchService.Recipients(id: number): { Player }    -- Mitglieder + Crown-Zuschauer ≤ 150 Studs
MatchService.Info(id: number): { MatchId: number, Slot: number, Mode: string, Map: string, Phase: string,
	Score: { number }, Players: { string }, Bots: number, Tainted: boolean }?
MatchService.List(): { any }
MatchService.Taint(id: number, reason: string)
MatchService.OnMatchEnd(cb: (result: Types.MatchResult) -> ())
MatchService.Route(p: Player, char: Model): ("Lobby" | "Vault" | "Spawn", CFrame?)
MatchService.ActiveMutator(): string
MatchService.SetMutatorOverride(key: string?)
-- Modes/Rounds.luau und Modes/Respawn.luau: interne Regelwerke mit
-- { Start(m), Tick(m, dt), OnElim(m, victim, killer, info), CheckEnd(m): (boolean, number?) }
```

### C5.6 WP6
```lua
BotService.Budget(): number
BotService.Spawn(difficulty: string, ctx: string, team: number, slot: number, loadout: Types.Loadout?): Types.Combatant?
BotService.Despawn(c: Types.Combatant)
BotService.SetGoal(c: Types.Combatant, goal: { Kind: "Engage" | "Zone" | "Idle", Pos: Vector3? })
BotService.DifficultyFor(players: { Player }): string
BotService.SetHandicap(c: Types.Combatant, missShots: number)   -- je Runde zurückgesetzt von OnRoundStart
BotService.OnRoundStart(ctx: string)
BotService.RandomName(): string

RangeService.IsInRange(p: Player): boolean
RangeService.SetWeapon(p: Player, slot: Types.SlotName, key: string)
RangeService.Members(): { Player }
```

### C5.7 WP7
```lua
AntiCheatService.NoteTeleport(p: Player, cf: CFrame)                  -- 1 s Gnade
AntiCheatService.Grace(p: Player, kind: "Impulse" | "Launch" | "Teleport", seconds: number, maxSpeed: number?)
AntiCheatService.SetAllowance(p: Player, a: { SpeedMult: number?, VerticalMult: number?, AirJumps: number? })
AntiCheatService.Exempt(p: Player, seconds: number)                   -- z. B. im Vault
AntiCheatService.Add(p: Player, reason: string, points: number, evidence: { [string]: any }?)
AntiCheatService.Score(p: Player): number
AntiCheatService.Flags(): { { Id: string, UserId: number, Name: string, Score: number, Reasons: { string }, Evidence: { [string]: any }, T: number } }

AdminService.IsAdmin(p: Player): boolean
AdminService.Power(p: Player, name: string): any       -- nil, wenn kein Admin oder Attribut nicht gesetzt
AdminService.EventMult(kind: "Xp" | "Coins"): number   -- Admin-Abuse-Event, sonst 1
AdminService.IsServerLocked(): boolean

BalanceService.Stat(kind: "Pick" | "Kill" | "Head" | "WinWith" | "Map" | "Mode" | "QueueTime", key: string, n: number?)
BalanceService.Version(): number
```

### C5.8 WP8
```lua
ProgressionService.AddXp(p: Player, base: number, reason: string, opts: { NoMult: boolean? }?): number  -- gibt gutgeschriebene XP
ProgressionService.AddPassXp(p: Player, amount: number, reason: string)
ProgressionService.XpMult(p: Player): number
ProgressionService.Mmr(p: Player): number
ProgressionService.MatchesPlayed(p: Player): number
ProgressionService.IsRookie(p: Player): boolean                 -- Stats.Matches < 3
ProgressionService.TitleOf(p: Player): string
ProgressionService.LevelOf(p: Player): number
ProgressionService.AddMasteryKills(p: Player, weaponKey: string, kills: number)
ProgressionService.MasteryTier(p: Player, weaponKey: string): number
ProgressionService.GrantPassPremium(p: Player): boolean         -- false, wenn schon Premium in aktiver Saison
ProgressionService.AddPassTiers(p: Player, n: number): number   -- gibt nicht nutzbare Reststufen zurück
ProgressionService.Season(): { Id: number, Tiers: number, TierXp: number, [string]: any }
ProgressionService.Unlock(p: Player, achievementId: string)
-- registriert sich selbst auf MatchService.OnMatchEnd: XP, Coins (über ShopService.Grant), MMR, Meisterschaft, Stats

RewardService.Track(p: Player, kind: string, amount: number, ctx: { [string]: any }?)
RewardService.FirstWinToday(p: Player): boolean

CommunityService.PressGG(p: Player, matchId: number)
CommunityService.Commend(p: Player, targetUserId: number): (boolean, string?)
CommunityService.BountyOf(p: Player): number
CommunityService.Announce(key: string, args: { any }?, filter: ((Player) -> boolean)?)   -- lokalisierte Lobby-Ansage

LeaderboardService.Submit(p: Player)

MetricsService.Funnel(p: Player, step: number, name: string)
MetricsService.Economy(p: Player, flow: "Source" | "Sink", currency: Types.Currency, amount: number, balance: number, txType: string, sku: string?)
MetricsService.Progression(p: Player, path: string, status: "Start" | "Complete" | "Fail", level: number)
MetricsService.Custom(p: Player, name: string, value: number?, fields: { [string]: any }?)
```

### C5.9 WP9
```lua
MonetizationService.HasPass(p: Player, key: string): boolean
MonetizationService.LoadPasses(p: Player)                       -- 3 Versuche, loading-Guard
MonetizationService.RandomAllowed(p: Player): boolean?          -- nil = unbekannt (= eingeschränkt behandeln)
MonetizationService.SetPolicyOverride(p: Player, allowed: boolean?)
MonetizationService.SimulatePurchase(p: Player, productKey: string): (boolean, string)
MonetizationService.PartyXpActive(): boolean
MonetizationService.TryOffer(p: Player, offerKey: string): boolean   -- max. 1 Angebot pro Sitzung, nie in Live-Runde

ShopService.Grant(p: Player, grant: Types.Grant, reason: string): boolean   -- einziger Weg für Währung/Items (kein Yield)
ShopService.Spend(p: Player, currency: Types.Currency, amount: number, reason: string): boolean
ShopService.Owns(p: Player, weaponKey: string): boolean
ShopService.OwnsCosmetic(p: Player, id: string): boolean
ShopService.GetLoadout(p: Player, rules: Types.ContextRules?): Types.Loadout   -- validiert: Besitz, Enabled, Mutator
ShopService.GetCosmetics(p: Player, weaponKey: string): { Skin: string, Wrap: string, Charm: string }
ShopService.Finisher(p: Player): string
ShopService.Tracer(p: Player): string
ShopService.TodayFeatured(): { string }
```

## C6. Öffentliche Shared-APIs

### C6.1 WP1
```lua
-- Util (MH + Fix §14.2)
Util.FormatNumber(n: number): string       -- 1150 -> "1.15K", math.huge -> "MAX", -0.5 -> "0"
Util.FormatTime(seconds: number): string   -- "5h 12m", "3:07"
Util.DeepCopy<T>(v: T): T
Util.Reconcile(target: { [any]: any }, template: { [any]: any })
Util.WeightedPick<T>(list: { T }, weightOf: ((T) -> number)?, rng: Random?): T?
Util.RateLimiter(maxCalls: number, perSeconds: number): { Check: (key: any) -> boolean, Clear: (key: any) -> () }
Util.TokenBucket(capacity: number, refillPerSecond: number): { Take: (key: any, n: number?) -> boolean, Clear: (key: any) -> () }
Util.IsFinite(n: any): boolean             -- typeof number, n == n, |n| ~= huge
Util.IsFiniteVector(v: any): boolean
Util.UtcDay(now: number?): number           -- floor(os.time()/86400) + DayOffset
Util.IsoWeek(now: number?): number          -- z. B. 202642
Util.SetDayOffset(n: number)                -- nur Debug (Studio)
Util.Snapshot<K, V>(t: { [K]: V }): { K }
Util.Hash(s: string): number               -- deterministisch 0..2^31-1 (Shards)

-- Net: Remote-Namen + Buffer-Codecs (C8)
Net.RemoteList: { { Name: string, Class: "RemoteEvent" | "RemoteFunction" | "UnreliableRemoteEvent" } }
Net.GetRemotes(): { [string]: Instance }  -- Client: WaitForChild je Name (10 s)
Net.EncodeLook(pitchDeg: number, flags: number, seq: number): buffer
Net.DecodeLook(b: buffer): (number, number, number)?
Net.EncodeLookBatch(seq: number, entries: { { Slot: number, Pitch: number, Flags: number } }): buffer
Net.DecodeLookBatch(b: buffer): (number, { { Slot: number, Pitch: number, Flags: number } })?
Net.EncodeFx(entries: { { Kind: number, Slot: number, Weapon: number, O: Vector3, E: Vector3 } }, origin: Vector3): buffer
Net.DecodeFx(b: buffer, origin: Vector3): { { Kind: number, Slot: number, Weapon: number, O: Vector3, E: Vector3 } }?
Net.LookFlags: { Ads: number, Sprint: number, Slide: number, Reload: number, Block: number, Air: number, Swing: number } -- 1,2,4,8,16,32,64

-- Spring (frame-unabhängige Feder, für Kamera/Viewmodel)
Spring.new(initial: Vector3, speed: number, damper: number): SpringObj
SpringObj:Step(dt: number): Vector3   -- dt geklemmt 1/30, Unterschritte
SpringObj:Impulse(v: Vector3)  SpringObj:SetTarget(v: Vector3)

-- Config/init: siehe C15; Helfer
Config.Weapon(key: string): Types.WeaponDef?        -- Basis + Live-Balance-Overrides
Config.WeaponById(id: number): Types.WeaponDef?
Config.ApplyBalance(data: { Version: number, Weapons: { [string]: { [string]: any } }, Disabled: { [string]: boolean } })
Config.Validate(): { string }                        -- sammelt Child.Validate(Config) aller Kindmodule

-- Lang (C16)
Lang.T(lang: Types.Lang, key: string, ...: any): string
Lang.Pick(lang: Types.Lang, t: { de: string, en: string }): string
Lang.For(p: Player, override: string?): Types.Lang   -- "de" wenn LocaleId mit "de" beginnt, sonst "en"
Lang.Missing(): { string }                            -- Schlüssel, die in einer Sprache fehlen
```

### C6.2 WP3 (rein, `--!strict`)
```lua
Spread.Seed(salt: number, shotId: number): number            -- ganzzahlig, deterministisch
Spread.Directions(aim: Vector3, def: Types.WeaponDef, scaleDeg: number, seed: number): { Vector3 }  -- #= def.Pellets
Spread.Bloom(def: Types.WeaponDef, shotTimes: { number }, t: number): number
Spread.MinScale(def: Types.WeaponDef, adsOk: boolean, speed: number, airborne: boolean): number
Hitbox.Ray(origin: Vector3, dir: Vector3, range: number, root: CFrame, head: Vector3, headRadius: number, tol: number): ("Head" | "Body")?, number?
Hitbox.PointDistance(p: Vector3, root: CFrame, head: Vector3): number
Damage.Compute(def: Types.WeaponDef, dist: number, region: "Head" | "Body", rules: Types.ContextRules?): number
Damage.Splash(def: Types.WeaponDef, dist: number): number
Ballistics.Position(p0: Vector3, v: Vector3, g: number, t: number): Vector3
Ballistics.Step(p: Vector3, v: Vector3, g: number, dt: number): (Vector3, Vector3)
Ballistics.Reflect(v: Vector3, normal: Vector3, restitution: number): Vector3
```

### C6.3 WP4 / WP8 / WP9
```lua
WeaponModels.Build(key: string, opts: { Skin: string?, Scale: number?, Viewmodel: boolean? }): Model
	-- Attachments Grip/Muzzle/Sight/Charm, Teil "Mag", Attribut "Role" je Teil, alle Teile nicht abfragbar
WeaponModels.HasRecipe(key: string): boolean
WeaponModels.Recipes: { [string]: { any } }

ProgressMath.XpToNext(level: number): number
ProgressMath.LevelFromTotal(totalXp: number): (number, number)   -- Level, XP im Level
ProgressMath.Expected(a: number, b: number): number
ProgressMath.EloDelta(a: number, b: number, score: number, k: number): number
ProgressMath.MasteryTier(kills: number): number

CosmeticModels.ApplyWrap(model: Model, wrapId: string)
CosmeticModels.BuildCharm(id: string): Model
CosmeticModels.TracerStyle(id: string): { Color: ColorSequence, Width0: number, Width1: number, Texture: string }
CosmeticModels.StartAnimator()        -- Client: animiert Modelle mit Tag "AnimWrap" (10 Hz, ≤ 80 Studs)

Odds.Table(crate: { Items: { { Id: string, Weight: number } } }): { { Id: string, Percent: number } }  -- Summe exakt 100.00
Odds.Roll(crate: any, rng: Random, pityActive: boolean): string
Odds.Validate(crate: any): (boolean, string?)                    -- Gewichte summieren 10000
```

## C7. Client-Architektur

### C7.1 `ctx` (von `Main.client.luau`, WP10)
```lua
export type Ctx = {
	Player: Player, Config: any, Lang: any, Util: any, Net: any, Types: any,
	Remotes: { [string]: Instance }, Gui: ScreenGui, TouchGui: ScreenGui,  -- Gui mit UIScale, TouchGui unskaliert
	State: { [string]: any }, StateTime: number,
	Request: (action: string, arg: any?) -> any,          -- Toast bei Message, nil bei Fehler
	RequestFull: (action: string, arg: any?) -> { Ok: boolean, Message: string?, [string]: any },
	Toast: (text: string, kind: string?) -> (),
	T: (key: string, ...any) -> string,                    -- Lang.T(aktuelle Sprache, ...)
	Lang_: () -> "de" | "en",
	Hooks: Hooks, Windows: Windows, UI: any, Modules: { [string]: any },
}
```
Startreihenfolge (jedes `Init(ctx)` in pcall, danach jedes `Start()` in pcall; fehlende Module → `warn`, weiter):
`UI, Hooks, Sfx, Effects, Highlights, CombatFX, Controls, TouchControls, Hud, CombatHud, Settings, ArenaLook, FpsCamera, AimAssist,
Viewmodel, Movement, Replication, WeaponClient, QueueUI, MatchUI, Spectate, Scoreboard, Tutorial, BotAnimator, Training, Progress,
ChatClient, Shop, Locker, CrateReveal, Finishers` – dann bei `IsAdmin`: `AdminPanel, AdminTools, Fly, PhotoMode, DebugOverlay`.

### C7.2 Hooks (WP10, kleiner Signal-Hub)
```lua
Hooks.On(name: string, fn: (...any) -> ()): () -> ()   -- gibt Trenn-Funktion zurück
Hooks.Once(name: string, fn: (...any) -> ())
Hooks.Fire(name: string, ...: any)                     -- jeder Listener in pcall
```
Ereignisse: `"State"(state, changedKeys)` · `"Match:<Kind>"(data)` (für jede Match-Art aus C8) · `"Combat:<Op>"(data)` ·
`"Effect:<Name>"(strength, data)` · `"WindowOpened"(name)` · `"WindowClosed"(name)` · `"World"(world: "Lobby"|"Range"|"Crown"|"Match", slot?)` ·
`"Armed"(info)` · `"Disarmed"()` · `"LocalPopped"(recap?)` · `"LocalRevived"()` · `"Spectate"(model?)` · `"Settings"(settings)` ·
`"Input"(kind: "KBM"|"Gamepad"|"Touch")` · `"Equip"(slot, weaponKey)` · `"Shot"(weaponKey)` · `"Hitmarker"(region, killed)`.
`Main.client` leitet `Match`, `Combat`, `Effect`, `State`, `Notify` als Hooks weiter; `FX` und `LookBatch` hören CombatFX/Replication direkt.
`"World"` feuert `Main.client`: `Match:Start` → `"Match"` mit `Slot` (Slot 0 = Crown = Lobby-Welt), `Armed` mit `Ctx == "Range"` → `"Range"`,
`Match:Closed`/`Disarmed` außerhalb eines Matches → `"Lobby"`.

### C7.3 Windows (WP10, in `UI.luau`)
```lua
ctx.Windows.Register(name: string, open: () -> (), close: (() -> ())?)
ctx.Windows.Open(name: string)    ctx.Windows.Close(name: string?)    ctx.Windows.IsOpen(name: string?): boolean
```
Namen: `"Play"` (WP5), `"Shop"`, `"Locker"` (WP9), `"Quests"`, `"Pass"`, `"Daily"` (WP8), `"Settings"` (WP10), `"Training"` (WP6), `"Admin"` (WP7).
`ProximityPromptService.PromptTriggered` (Client) → `prompt:GetAttribute("Window")` → `Windows.Open`.

### C7.4 Client-Modul-APIs
```lua
-- WP10
UI: MH-Kit (REUSE §11) + UI.IsAnyWindowOpen(): boolean
Controls.Bind(action: string, fn: (state: "Begin" | "End" | "Change", input: InputObject?) -> (), priority: number?): () -> ()
Controls.IsDown(action: string): boolean
Controls.Input(): "KBM" | "Gamepad" | "Touch"
Controls.SetContext(c: "Lobby" | "Match" | "Range" | "Menu" | "Spectate")
-- Aktionen: Fire, Ads, Reload, Slot1..Slot4, NextWeapon, PrevWeapon, LastWeapon, Melee, Utility, Sprint, Slide,
-- Inspect, Scoreboard, Loadout, Menu, Ready, AdminPanel, Fly, SpecNext, SpecPrev
TouchControls.Show(set: "Match" | "Range" | "Lobby" | "None")
TouchControls.SetAutoFire(on: boolean)
Hud.AddRightButton(icon: string, captionKey: string, color: Color3, order: number, onClick: () -> ())
Hud.SetVisible(on: boolean)
CombatHud.Show(on: boolean)
CombatHud.SetHp(hp: number, max: number)
CombatHud.SetAmmo(mag: number, max: number, reloading: boolean, reloadProgress: number?)
CombatHud.SetSpread(deg: number)
CombatHud.Hitmarker(region: "Head" | "Body", killed: boolean, provisional: boolean?)
CombatHud.DamageNumber(pos: Vector3, amount: number, head: boolean)
CombatHud.Hurt(fromPos: Vector3, amount: number)
CombatHud.KillBanner(name: string)
CombatHud.SetSlots(loadout: { [string]: string }, equipped: string, charges: { [string]: number })
Settings.Get(): { [string]: any }
Effects.Play(name: string, strength: number, data: any?)   -- Announce, AdminWarn, Confetti, LevelUp, CoinFly, Shake
Effects.SetHidden(on: boolean)
CombatFX.Tracer(from: Vector3, to: Vector3, color: Color3?, tracerId: string?)
CombatFX.Impact(pos: Vector3, normal: Vector3?, kind: "Surface" | "Player" | "Head" | "Water")
CombatFX.Muzzle(cf: CFrame, weaponKey: string)
CombatFX.Explosion(pos: Vector3, radius: number)
CombatFX.Smoke(pos: Vector3, radius: number, untilT: number)
CombatFX.Projectile(id: string, weaponKey: string, origin: Vector3, velocity: Vector3, gravity: number, t0: number)
CombatFX.RemoveProjectile(id: string)
CombatFX.Pop(pos: Vector3, finisherId: string, color: Color3)   -- ruft Finishers.Play, Fallback Konfetti
Sfx.Play(role: string, pos: Vector3?, opts: { Volume: number?, Speed: number? }?)
Highlights.Acquire(owner: string, adornee: Instance, props: { Outline: Color3?, Fill: Color3?, FillTransparency: number?,
	Depth: Enum.HighlightDepthMode? }): any?    -- nil wenn Budget (31) voll
Highlights.Release(handle: any)   Highlights.ReleaseOwner(owner: string)   Highlights.Count(): number
Highlights.Pulse(owner: string, seconds: number)   -- alle Handles des Owners kurz auf AlwaysOnTop (Anti-Camp)

-- WP2
ArenaLook.SetWorld(world: "Lobby" | number)   -- Slot-Nummer; versteckt alle anderen Welten (B9.4)
ArenaLook.ApplyMood(moodKey: string)          ArenaLook.RestoreLobby()

-- WP4
FpsCamera.SetMode(mode: "Lobby" | "Match" | "Range" | "Spectate" | "Menu")
FpsCamera.Kick(pitchDeg: number, yawDeg: number)
FpsCamera.SetAds(alpha: number, zoom: number)
FpsCamera.AddLookDelta(dxRad: number, dyRad: number)     -- Touch-Feuerknopf-Ziehen
FpsCamera.Shake(intensity: number, duration: number)
FpsCamera.SetScope(on: boolean)
AimAssist.Filter(dt: number, look: Vector2, input: "Gamepad" | "Touch"): Vector2
Viewmodel.Equip(weaponKey: string, cos: { Skin: string, Wrap: string, Charm: string }?)
Viewmodel.Unequip()  Viewmodel.Fire()  Viewmodel.Reload(duration: number)  Viewmodel.Inspect()
Viewmodel.Swing(kind: string)  Viewmodel.SetAds(alpha: number)  Viewmodel.SetBlock(on: boolean)
Viewmodel.SetHidden(on: boolean)  Viewmodel.MuzzleCFrame(): CFrame?
WeaponClient.IsArmed(): boolean
WeaponClient.Current(): (string?, any?)       -- Waffen-Key, Def
Movement.ApplyImpulse(v: Vector3)  Movement.SetGravityLift(frac: number)  Movement.IsSliding(): boolean
Replication.Flags(): number

-- WP5
QueueUI.OpenPlay()   Spectate.Start(candidates: { Model })   Spectate.Stop()
-- WP6
Training.Open()
-- WP8
Progress.Open(tab: "Quests" | "Pass" | "Daily")
-- WP9
Shop.Open(tab: string?)  Shop.BuildStarterCard(parent: GuiObject): GuiObject?
Locker.Open()  CrateReveal.Play(result: { Id: string, Rarity: string, Duplicate: boolean, Shards: number })
Finishers.Play(id: string, pos: Vector3, color: Color3)
-- WP7
AdminPanel.Toggle()  Fly.Toggle()  PhotoMode.Toggle()
```

## C8. Remotes (alle; `Net.RemoteList`, erzeugt von `Services/Remotes.luau`, Ordner `ReplicatedStorage.Remotes`)

| Name | Klasse | Richtung | Payload | Server-Limit / Regel |
|---|---|---|---|---|
| `Notify` | RemoteEvent | S→C | `(text: string, kind: NotifyKind)` – bereits lokalisiert | – |
| `State` | RemoteEvent | S→C | `(partial: {[string]: any}, full: boolean)` – Sticky-Merge, voll alle 20 s | ≤ 5 Pakete/s pro Spieler |
| `Effect` | RemoteEvent | S→C | `(name: string, strength: number, data: any?)` – `Announce {Text, UserId, Name}`, `AdminWarn {Text}`, `Confetti`, `LevelUp {Level, Rewards}`, `Balance {Version}`, `CrateFound {Name, ItemId, Rarity}` (nur an erlaubte), `PartyBoost {Name, Until}`, `Event {Kind, Until, Coins2, Xp2}`, `Friend {Name, UserId}`, `Mutator {Key}` | – |
| `Request` | RemoteFunction | C→S | `(action: string, arg: any?) → Reply` (C9) | 8/s pro Spieler + aktionsspezifisch |
| `Admin` | RemoteFunction | C→S | `(action: string, args: {[string]: any}?) → {Ok, Message, Data}` (B25.3) | 12/s **vor** Admin-Prüfung |
| `Match` | RemoteEvent | S→C | `(kind: string, data: table)` – unten | nur an Empfänger des Matches |
| `Combat` | RemoteEvent | S→C | `(op: string, data: table)` – unten | an Schütze/Opfer/Kontext |
| `Fire` | RemoteEvent | C→S | `(shotId: number, weaponId: number, t: number, origin: Vector3, aim: Vector3, scale: number, targets: {number})` – `#targets == Pellets` (0 = Strahl ohne Treffer), Projektilwaffen `targets = {}`, Burst = 1 Paket pro Kugel | TokenBucket Kap. 12 / +20 pro s, dann Waffen-Intervall (C10) |
| `WeaponAction` | RemoteEvent | C→S | `(action: string, a: any?, b: any?, c: any?, d: any?, e: any?)`: `"Equip"(slot 1..4)`, `"Reload"()`, `"Ads"(on: boolean, t: number)`, `"Block"(on: boolean, t: number)`, `"Melee"(swingId: number, t: number, aim: Vector3, targetId: number?)`, `"Throw"(throwId: number, t: number, origin: Vector3, aim: Vector3, charge: number)`, `"Use"(t: number)` | TokenBucket 12 / +12 pro s |
| `Look` | UnreliableRemoteEvent | C→S | `buffer` 4 Byte: `i8 pitchDeg, u8 flags, u16 seq` (≤ 12 Hz, nur bei Änderung > 1° oder Flags) | 20/s, Rest still verworfen; ältere seq verworfen |
| `LookBatch` | UnreliableRemoteEvent | S→C | `buffer`: `u16 seq, u8 n, n × (u8 slot, i8 pitch, u8 flags)` (≤ 51 B) | 10 Hz pro Kontext |
| `FX` | UnreliableRemoteEvent | S→C | `buffer`: `u8 n, n × (u8 kind, u8 slot, u8 weapon, i16×3 origin, i16×3 end)`; Positionen relativ zum Arena-Ursprung ×10 (±3276 Studs). kind 1 = Tracer + Flächen-Treffer, 2 = Tracer + Spieler-Treffer, 3 = Nahkampf-Schwung, 4 = Wurf. Max. 58 Einträge (871 B), ältere fallen raus | 20 Hz pro Kontext |
| `GrantCoins` | RemoteEvent | C→S | **Honeypot** – unser Code feuert ihn nie | jeder Aufruf: +100 Verdacht, Kick + Flag |

**Match-Arten (`Match`, an `MatchService.Recipients(id)`):**
| kind | data |
|---|---|
| `Found` | `{MatchId, Mode, Mutator?, Teams = {{ {Slot, Id, Name, IsBot, Level, Title} }}, VoteOptions = {{Map, Mood}}?, VoteEnds?}` |
| `Vote` | `{Counts = {n1, n2, n3, nRandom}}` |
| `Start` | `{MatchId, Slot, Map, Mood, BuildId, Origin: Vector3, Mode, Mutator?, RoundsToWin, MyTeam, Roster = {{Slot, Id, Name, Team, IsBot, Level, Title, Finisher}}}` |
| `Intro` | `{EndsAt, Enemies = {{Slot, P, S, M, U}}}` (Waffen-Keys) |
| `Prep` | `{Round, Score = {a, b}, EndsAt, MatchPoint: boolean, SuddenDeath: boolean}` |
| `Live` | `{EndsAt}` |
| `Overtime` | `{EndsAt, Zone: Vector3, Radius}` |
| `Zone` | `{Team: number (0 = niemand), Progress: number (0..1), Contested: boolean}` (5 Hz) |
| `AntiCamp` | `{Until}` |
| `Elim` | `{K: number?, V: number, W: string, H: boolean, A: {number}, Fin: string, P: Vector3, C: Color3, Fl = {Streak: number?, Bounty: number?, Mastery: number?, Crown: boolean?, Void: boolean?}}` |
| `Recap` | `Types.RecapData` (nur an das Opfer) |
| `RoundEnd` | `{Winner: number, Reason: "Elim"\|"Zone"\|"Alive"\|"Hp"\|"Damage"\|"Draw", Score = {a, b}, Mvp: number?, Banners = {string}}` |
| `Score` | `{Scores = {[id]: number}, EndsAt}` (FFA, bei Änderung) |
| `End` | `{Winner, Draw, Tainted, Me = {XpGain, Level, XpInLevel, XpNext, Coins, MasteryWeapon, MasteryBefore, MasteryAfter, PassXpBefore, PassXpAfter, QuestTicks = {{Id, P, Goal}}, Mvp, Stats}, Offer: string?}` (pro Spieler eigener Teil) |
| `Rematch` | `{Votes, Needed}` |
| `Spectate` | `{TargetId}` |
| `Afk` | `{Warn: boolean}` |
| `Left` | `{Id}` |
| `Closed` | `{}` |

**Combat-Ops (`Combat`):**
| op | an | data |
|---|---|---|
| `Armed` | Spieler | `{Id, Ctx, Salt, Team, Slot, Loadout, Origin: Vector3, Map: Model, Rules = {SpeedMult, GravityLift, HeadRadiusMult, AllowedSlots, UtilityMode, IgnoreOwnership}, Ammo = {[slot]: {Mag, Charges}}}` |
| `Disarmed` | Spieler | `{}` |
| `Hit` | Schütze | `{T: number, D: number, H: boolean, K: boolean, S: number}` |
| `Hurt` | Opfer | `{D: number, F: Vector3, H: boolean, Hp: number}` |
| `Ammo` | Spieler | `{S: SlotName, M: number, R: number, C: number}` (Korrektur / Nachlade-Ende) |
| `Equip` | Spieler | `{S: SlotName}` (Korrektur) |
| `Heal` | Spieler | `{Hp}` |
| `Proj` | Kontext | `{Id: number, Own: number, Shot: number, W: number, O: Vector3, V: Vector3, G: number, T: number}` |
| `Boom` | Kontext | `{Id: number, P: Vector3, R: number, W: number}` |
| `Smoke` | Kontext | `{P: Vector3, R: number, Until: number}` |
| `Impulse` | Spieler | `{V: Vector3}` (Rückstoß/Raketensprung; Client setzt AssemblyLinearVelocity) |
| `Reject` | Spieler | `{Shot: number, Why: string}` – nur wenn `Config.Debug.LogRejects` oder Admin |

## C9. Request-Aktionen (jede registriert ihr Besitzer-WP mit `PlayerStateService.Handle`)
| Aktion | WP | Argument | Extra-Limit | Antwort |
|---|---|---|---|---|
| `GetFull` | 1 | – | 1/5 s | `{Ok, State}` |
| `SaveSettings` | 1 | `{[key]: value}` (nur Schema-Schlüssel, geklemmt) | 2/s | `{Ok}` |
| `TutorialFlag` | 1 | `"Welcome" \| "Done" \| "Skipped" \| "TourDone"` | 1/s | `{Ok}` |
| `ArenaReady` | 5 | `buildId: number` (MatchService vergleicht mit der BuildId seiner Arena) | – | `{Ok}` |
| `QueueJoin` | 5 | `modeKey: string` | – | `{Ok, Message?}` |
| `QueueLeave` | 5 | – | – | `{Ok}` |
| `FillBots` | 5 | – | 1/3 s | `{Ok}` |
| `CrownJoin` / `CrownLeave` | 5 | – | – | `{Ok}` |
| `PracticeStart` | 5 | `difficulty: string` | 1/5 s | `{Ok}` |
| `TutorialStart` | 5 | – | 1/10 s | `{Ok}` |
| `VoteMap` | 5 | `index: 1..4` | – | `{Ok}` |
| `Ready` | 5 | – | – | `{Ok}` |
| `Rematch` | 5 | – | – | `{Ok}` |
| `AutoRequeue` | 5 | `on: boolean` | – | `{Ok}` |
| `LeaveMatch` | 5 | – | – | `{Ok}` |
| `RangeWeapon` | 6 | `{Slot: SlotName, Key: string}` | 4/s | `{Ok}` |
| `Report` | 7 | `{UserId: number, Reason: "Aimbot"\|"Speed"\|"Toxic"\|"Other"}` | 3/10 min | `{Ok, Message}` |
| `ClaimQuest` / `RerollQuest` | 8 | `id: string` / `index: number` | – | `{Ok}` |
| `ClaimLogin` / `SpinWheel` / `ClaimGift` | 8 | – / – / `index 1..4` | 1/s | `{Ok, Reward}` |
| `ClaimPass` | 8 | `{Tier: number, Track: "Free"\|"Premium"}` | 4/s | `{Ok, Reward}` |
| `ClaimLevelPick` | 8 | `weaponKey: string` (Gratis-Waffen-Wahl) | 1/s | `{Ok}` |
| `RedeemCode` | 8 | `code: string` (≤ 20 Zeichen) | 5/min | `{Ok, Message}` |
| `PressGG` / `Commend` | 8 | – / `userId: number` | – | `{Ok}` |
| `SetLoadout` | 9 | `{Index: number, Loadout: Loadout}` | 4/s | `{Ok}` |
| `SelectPreset` / `RenamePreset` / `RandomLoadout` | 9 | `index` / `{Index, Name ≤ 16, gefiltert}` / – | 4/s | `{Ok}` |
| `BuyWeapon` | 9 | `weaponKey: string` | 2/s + busy | `{Ok}` |
| `BuyItem` | 9 | `{Id: string, Currency: "Gems"\|"Coins"\|"Shards", Featured: boolean?}` | 2/s + busy | `{Ok}` |
| `OpenCrate` | 9 | `{Crate: "S1", Use: "Gems"\|"Key"}` | 2/s + busy | `{Ok, Result = {Id, Rarity, Duplicate, Shards}}` |
| `EquipCosmetic` | 9 | `{Kind: "Skin"\|"Wrap"\|"Charm"\|"Finisher"\|"Tracer"\|"Title", Id: string, Weapon: string?}` | 6/s | `{Ok}` |
| `BuyPresetSlot` | 9 | – | 1/s | `{Ok}` |
Ablauf jedes Handlers (PlayerStateService): Limit → `typeof`/Finite/Clamp (im Handler) → Ready-Gate → `pcall(fn)` → Tabelle.
Fehler → `{Ok=false, Message=Lang(core.error)}`. Server ruft nie `InvokeClient`.

## C10. Treffer-Registrierung (WeaponService, billig → teuer)
**Client:** Raycast von `camera.CFrame.Position`; `RaycastParams.IncludeInstances = {Kontext-Map, Combatant-Modelle des Kontexts außer mir}`,
`ExcludeInstances = {eigener Character, Camera}` (Liste neu bei Roster-Änderung, sonst gecacht). Richtungen über
`Spread.Directions(aim, def, scale, Spread.Seed(salt, shotId))`. Treffer-Part → Modell mit Attribut `CombatantId` → Ziel-Id.
Sofort vorhersagen: Mündungsfeuer, Tracer, vorläufiger Hitmarker, Munition −1, Rückstoß. Dann `Fire` senden.

**Server-Prüfung (Grund-Codes für Reject-Log):**
1. `TYPE` – alle Typen korrekt, Zahlen endlich, `|aim| ∈ [0.99, 1.01]`, `#targets == def.Pellets` (Projektil 0), Ziel-Ids ganzzahlig,
   `scale ∈ [0, 30]`, `weaponId` = ausgerüstete Waffe. Fehler → +5 Verdacht, verwerfen.
2. `RATE` – TokenBucket `Fire` (Admin mit `AdminRapidFire = f`: Kapazität und Nachfüllung × f).
3. `STATE` – `shotId > LastShotId` und `≤ LastShotId + 4` (Lücken bis 3 = Paketverlust); lebt; Kontext in Live-Phase (Range immer);
   `EquipReadyAt ≤ t`; nicht nachladend/heilend/blockend; Server-Magazin > 0 → dekrementieren (Admin `AdminInfAmmo` überspringt).
4. `RATE` – `t − LastShotT ≥ Interval × IntervalMult × 0.75` (Burst: `BurstInterval × 0.75`); Server-Empfangsabstand ≥ 0.5 × Interval;
   Schüsse in der letzten Sekunde ≤ `1/Interval × 1.15 + 1` (Burst-Waffen: `BurstCount/Interval`). Admin `AdminRapidFire` teilt die Grenzen.
5. `TIME` – `age = workspace:GetServerTimeNow() − t ∈ [−0.05, 1.0]` und `age ≤ player:GetNetworkPing() + 0.35`.
6. `ORIGIN` – Abstand `origin` ↔ History-Kopf bei `t` ≤ `4 + Speed(t) × min(age, 0.4)`; Ray Server-Kopf → origin gegen `MapParams` trifft nichts.
7. Spread – `adsOk = c.Ads and t − c.AdsSince ≥ AdsTime − 0.1 and Speed(t) ≤ Walk × AdsMoveMult × 1.3 + 2`;
   `minScale = Spread.MinScale(def, adsOk, Speed(t), luft)`; `scale = max(claim, minScale)`;
   `dirs = Spread.Directions(aim, def, scale, Spread.Seed(c.Salt, shotId))`.
8. Pro Strahl mit Ziel (`HITBOX`, `LOS`, `RANGE`): Ziel im selben Kontext, lebt, Gegner (oder Puppe), kein Schild;
   `T = clamp(t − 0.10, now − 0.38, now)`; `HistoryService.SampleWindow(target, T)` (T−0.075/T/T+0.075); erstes Fenster mit
   `Hitbox.Ray(origin, dir, def.Range, root, head, 0.8 × HeadRadiusMult, 0.35)` → Region + Distanz; Distanz ≤ Range;
   Sichtlinie origin → Treffpunkt, um 0.75 gekürzt, nur gegen `MapParams` (Glas blockiert, Barrieren nicht).
   Abweichungen zählen für die Hitbox-Mismatch-Quote (Anti-Cheat). Admin `AdminSilentAim`: Schritt 6–8 entfallen (Ziel muss im Kontext sein).
9. Schaden pro Ziel summieren (`Damage.Compute`, Block-Faktor wenn Ziel blockt und Schuss von vorn), `CombatService.ApplyDamage`;
   `Combat("Hit")` an Schützen, `Combat("Hurt")` ans Opfer (macht CombatService), Tracer in `ReplicationService.QueueFx`
   (an alle Empfänger außer dem Schützen), `BalanceService.Stat`. Admin `AdminOneShot` → Schaden = Ziel-HP.

**Nahkampf:** Intervall-Check; Ziel zurückgespult wie oben; Abstand Server-Kopf(t) → nächster Hitbox-Punkt ≤ `Range + 1.5`;
Winkel `aim` ↔ Richtung zum Ziel ≤ `Cone/2 + 10°`; Sichtlinie. Ohne Ziel: nur Schwung-FX. BonkHammer: Ausholzeit 0.35 s serverseitig abwarten.
**Bots:** `ServerFire` nutzt dieselben Funktionen (Spread, Munition, Intervall, Schaden) ohne Paket-Checks und ohne Rückspulen.

## C11. Projektile (ProjectileService, ohne Parts auf dem Server)
- Logische Projektile `{Id, Owner, Def, P, V, G, Born, Bounces, Ctx, ShotId}` in einem Array pro Kontext, **≤ 40 pro Arena, ≤ 160 gesamt** (ältestes fällt raus).
- Spawn um `min(age, 0.15)` vorgespult. Ein `EveryFrame`-Schritt: Segment-Raycast von alter zu neuer Position gegen `MapParams` +
  analytische Hitboxen der Gegner im Kontext (Kugel-gegen-Strahl mit Projektil-Radius 0.5).
- Rakete: Direkttreffer → `Direct` auf das Ziel, Splash auf andere; Wand → Splash. Granate: `Ballistics.Reflect` mit Restitution 0.35,
  max. 2 Abpraller, Zünder 2.0 s; Rauch: platzt bei erster Landung → Rauchkugel `{P, R=13, Until}` (analytisch für Bots/Zielhilfe).
- Explosion: über alle Combatants des Kontexts iterieren (keine Spatial Queries), Sichtlinie zum Mittelpunkt gegen `MapParams`,
  linearer Abfall `Damage.Splash`, Selbstschaden × `SelfMult`; Raketensprung-Impulse an den Schützen (AC-Grace `Launch` 1.5 s).
- Clients: `Combat("Proj")` → `CombatFX.Projectile` (gepoolte Kugel/Rakete, vorgespult um `GetServerTimeNow() − T`); der Schütze
  zeigt sein Projektil sofort (vorhergesagt) und ignoriert das Echo mit `Own == ich` und gleicher `Shot`. `Boom` → Explosion.

## C12. Sicherheit & Anti-Cheat

### C12.1 Grundsätze
Server entscheidet; Schaden zuerst verhindern (Schuss verwerfen, Zurücksetzen der Position); Verdacht aus **mehreren** Signalen;
Statistik bannt **nie** automatisch; nur harte Signale eskalieren; Admins ausgenommen; Gepoppte/Vault ausgenommen.

### C12.2 Pro Remote
| Remote | Regeln |
|---|---|
| `Request` | 8/s + Aktionslimit (C9); Ready-Gate; Typprüfung je Aktion; Währung nur in Service-Funktionen ohne Yield zwischen Prüfen und Abziehen; `busy`-Flag bei Käufen |
| `Admin` | 12/s vor Admin-Check; Server-Admin-Check pro Aufruf; Ziel-Auflösung mit Schutzregeln; Texte gefiltert; Ablehnung 1× loggen |
| `Fire` | C10 komplett |
| `WeaponAction` | Bucket 12/+12; `slot ∈ 1..4`; `t` wie C10 Schritt 5; `charge ∈ [0,1]`; Throw/Use nur mit Ladung/ohne Cooldown; Block nur mit LaserSword und ohne Cooldown |
| `Look` | 20/s, Puffergröße genau 4 Byte, `pitch ∈ [−80, 80]`, nur von bewaffneten Spielern; nie für Autorität genutzt |
| `GrantCoins` | Honeypot: +100, Kick („Ungewöhnliche Aktivität erkannt“), Flag (hartes Signal) |

### C12.3 Bewegung (5 Hz gestaffelt, MH-CarryService-Muster)
- Horizontales Budget: Auffüllen mit `(32 × SpeedMult × 1.15 + 6)` Studs/s, Kapazität 1.0 s. `Grace("Impulse"/"Launch")` erlaubt bis
  `maxSpeed` (Std. 95) für die Dauer.
- Vertikal: Höhe über dem letzten Bodenkontakt ≤ `7.2 × (AirJumps + 1) × VerticalMult + 3` außer in Grace.
- Fliegen: `FloorMaterial == Air` > 3 s ohne Fallgeschwindigkeit (außer MoonJump: 6 s).
- Noclip: Ray zwischen aufeinanderfolgenden Samples gegen `MapParams`/Lobby-Geometrie.
- Teleport-Grace 1 s nach jeder Server-Teleportation (Pad→Arena, Arena→Vault, Vault→Spawn, zurück zur Lobby); Sprung > 40 Studs
  ohne Grace = Verstoß.
- Verstoß → Zurücksetzen auf letzte gültige CFrame (`NoteTeleport`) + Verdacht.

### C12.4 Verdachtspunkte (`Config.Security.Weights`, Abbau 1 Punkt je 30 s)
| Signal | Punkte | hart? |
|---|---|---|
| Honeypot | +100 | ja |
| Kaputtes Paket (`TYPE`) | +5 | nein |
| Feuerraten-Verstoß | +1 je (+15 wenn > 20/min) | ab 20/min ja |
| Ursprung zu weit (`ORIGIN`) | +2 | nein |
| Sichtlinie durch Wand (`LOS`) | +1 (+10 wenn > 10/min) | nein |
| Hitbox-Mismatch > 40 % über 30 Behauptungen | +10 | nein |
| Tempo | +2 | nein |
| Teleport > 40 Studs | +8 | ja |
| Fliegen | +5 | nein |
| Statistik: Kopf-Quote > 0.75 über ≥ 60 Treffer **und** Genauigkeit > 0.70 | +20, nur Prüfliste | nein |
Aktionen: ≥ 25 → Prüf-Flag (gespeichert, C14). ≥ 60 → Kick mit Meldung. 3 Kicks wegen harter Signale in 7 Tagen → 1-Tages-`BanAsync`
mit Beweis in `PrivateReason`. Alles andere entscheidet der Besitzer im Panel.

### C12.5 Weitere Schutzregeln
`RejectCharacterDeletions = Enabled`; Head/HRP/Humanoid fehlen → Fallback-Pop + Respawn; Reset im Match aus; Bots Server-Netzwerk-Besitz;
Accessoires/Waffen/Viewmodel `CanQuery=false`; Kisten-RNG `Random.new()` auf dem Server; Preise nur aus Server-Config;
Beleg-Idempotenz; Meldungen mit Server-Statistik-Schnappschuss (Kopf-%, Genauigkeit, Pops/min, Reject-Zähler) statt Video;
Nutzertext für andere (Ansagen, Warnungen, Preset-Namen) → `TextService:FilterStringAsync` → `GetNonChatStringForBroadcastAsync`.

### C12.6 Kollisionsgruppen (ArenaService.Init, **vor** jedem Map-Bau, `workspace:RegisterCollisionGroup`)
`LobbyPlayers`, `Combatants`, `Bots`, `Ghost`, `ArenaBarrier`, `FX` (6 von max. 32).
| | Default | LobbyPlayers | Combatants | Bots | Ghost | ArenaBarrier | FX |
|---|---|---|---|---|---|---|---|
| LobbyPlayers | ✔ | ✘ | ✘ | ✘ | ✘ | ✔ | ✘ |
| Combatants | ✔ | ✘ | ✔ | ✔ | ✘ | ✔ | ✘ |
| Bots | ✔ | ✘ | ✔ | ✔ | ✘ | ✔ | ✘ |
| Ghost | ✘ | ✘ | ✘ | ✘ | ✘ | ✘ | ✘ |
| FX | ✘ | ✘ | ✘ | ✘ | ✘ | ✘ | ✘ |
Spieler-Character-Teile wechseln die Gruppe beim Bewaffnen (`Combatants`), Entwaffnen (`LobbyPlayers`) und Pop (`Ghost`).

## C13. Datenschema (WP1 `DataService`; DataStore `CC_Player_v1`, Key `Player_<UserId>`, Record `{Data, Lock = {JobId, Time}}`)
`DATA_VERSION = 1`. Nur **String-Schlüssel** in Dictionaries (keine dünnen Zahl-Keys im JSON). Defaults = `DEFAULT_DATA` unten;
`Migrate(data)` (pcall) läuft pro Versionsschritt, danach `Util.Reconcile(data, DEFAULT_DATA)`. Feld-Besitzer in Klammern (nur dieses WP schreibt).
```lua
local DEFAULT_DATA = {
	Version = 1, Created = 0, LastJoin = 0, PlaySeconds = 0,                       -- (WP1)
	Coins = 0, Gems = 0, Keys = 0, Shards = 0,                                     -- (WP9, über ShopService.Grant/Spend)
	XP = 0, Level = 1, TotalXP = 0, FreeWeaponPicks = 0,                           -- (WP8; Picks einlösen WP8 → ShopService.Grant)
	Stats = { Matches = 0, PvpMatches = 0, Wins = 0, PvpWins = 0, Losses = 0, BotWins = 0, Draws = 0, RoundsWon = 0,
		Elims = 0, PvpElims = 0, Deaths = 0, Assists = 0, Headshots = 0, MeleeElims = 0, ShotsFired = 0, ShotsHit = 0,
		Damage = 0, Flawless = 0, Clutches = 0, Aces = 0, Streak = 0, BestStreak = 0, LossStreak = 0, BotLossStreak = 0,
		BotWinStreak = 0, CrownBest = 0, CrownDefences = 0, Bounties = 0, OvertimeCaps = 0, VoidKnocks = 0, FlickBest = 0 }, -- (WP8)
	Mmr = 1000, MmrGames = 0, BotTier = 0,                                         -- (WP8; BotTier −1..1)
	Ranked = { Season = 0, Rating = 0, Placements = 0, ShieldDay = 0, Peak = 0 },  -- reserviert v1.1 (WP8)
	Weapons = { Owned = { PopRifle = true, PipPistol = true, BoxingGloves = true, PopGrenade = true }, -- (WP9)
		Mastery = {} },                       -- [weaponKey] = { K = Pops, T = eingelöste Stufe } (WP8)
	Loadouts = { Active = 1, Slots = 3, Presets = {   -- Slots = 3 + gekaufte Coin-Plätze (max 5); LoadoutPlus-Pass → 8 (WP9)
		{ Name = "Loadout 1", P = "PopRifle", S = "PipPistol", M = "BoxingGloves", U = "PopGrenade" },
		{ Name = "Loadout 2", P = "PopRifle", S = "PipPistol", M = "BoxingGloves", U = "PopGrenade" },
		{ Name = "Loadout 3", P = "PopRifle", S = "PipPistol", M = "BoxingGloves", U = "PopGrenade" } } },
	Cosmetics = { Owned = {},                 -- [cosmeticId] = true (inkl. Titel "TT_…")                    (WP9)
		Equipped = { Finisher = "F_Confetti", Tracer = "T_Team", Title = "" },
		PerWeapon = {} },                     -- [weaponKey] = { Skin = "", Wrap = "", Charm = "" }
	Crates = { Pity = 0, Opened = 0 },                                             -- (WP9)
	Boosts = { XP2Until = 0 },                -- os.time()                                                     (WP9)
	Quests = { Day = 0, Daily = {}, Rerolls = 1, DailyBonus = false, Week = 0, Weekly = {}, WeeklyChest = false,
		Beginner = { Step = 1, P = 0 } },     -- Daily/Weekly: { {Id, Kind, Goal, P, Claimed, Tier} }          (WP8)
	Login = { LastDay = 0, CalDay = 0, Streak = 0, Best = 0, FreezeWeek = 0, CatGiven = false },        -- (WP8)
	Daily = { FirstWinDay = 0, WheelDay = 0, WheelSpins = 0, PlayDay = 0, PlaySec = 0, Gifts = {},
		BotCoinsDay = 0, BotCoins = 0 },                                           -- (WP8)
	Pass = { Season = 0, XP = 0, Premium = false, Free = {}, Prem = {} },          -- Free/Prem: ["<tier>"] = true (WP8)
	Achievements = {}, AchProgress = {},                                           -- ["Id"] = true / Zahl  (WP8)
	Honor = { Commends = 0, Day = 0, Today = 0, GG = 0 },                          -- (WP8)
	Codes = {},                                                                    -- ["CODE"] = os.time() (WP8)
	Purchases = { Receipts = {}, Starter = false, StarterOfferedAt = 0, PassSeasons = {}, FirstPack = {},
		RobuxSpent = 0, Supporter = 0 },      -- Receipts: { {Id = purchaseId, T = os.time()} } max 60 (WP9)
	Flags = { Tutorial = false, TourDone = false, FirstRealWin = false, Rules = false },                -- (WP1/WP5)
	Settings = {},                            -- Defaults aus Config.Client.DefaultSettings (Reconcile)         (WP1-Handler)
	Mod = { Warnings = 0, HardKicks = {} },   -- HardKicks: Zeitstempel, max 10                                (WP7)
}
```
- **Laden:** 6 `UpdateAsync`-Versuche; fremdes Lock jünger als 30 min → nichts schreiben, 5 s warten; letzter Versuch übernimmt
  (mit `warn`). Fehler: Backoff `Versuch × 1.5 s`. Live-Fehler → Kick mit Meldung; Studio → NoSave + Toast.
- **NoSave**, wenn `RunService:IsStudio() and (Config.Studio.NoSave or UserId <= 0)` oder Studio ohne API-Zugriff (Fehler mit
  „studio“/„publish“/„api services“/„403“ → sofort aufhören). Toast: „Studio: Fortschritt wird nicht gespeichert“.
- **Speichern:** 4 Versuche, Transform verweigert Schreiben bei fremdem Lock; Saves pro Profil **serialisiert** (keine Überholung
  durch Release). Auto-Save alle 90 s aus einer **Schnappschuss-Liste**, 0.5 s versetzt, jedes `Save` in pcall.
- **Release:** `Releasing`-Guard, Callbacks (pcall), letzter Save mit `Lock = nil`. `BindToClose`: alle parallel, max. 25 s.

## C14. Weitere DataStores, MessagingService, Budget
| Store | Key | Inhalt | Schreiber |
|---|---|---|---|
| `CC_Live_v1` | `Balance` | `{Version, Weapons = {[key] = {[field] = value}}, Disabled = {[key] = true}}` | nur Besitzer-Server (UpdateAsync) |
| `CC_Live_v1` | `BalanceHistory` | letzte 10 Versionen | nur Besitzer-Server |
| `CC_Live_v1` | `Mutator` | `{Key, Until}` (globaler Override) | nur Besitzer-Server |
| `CC_Stats_v1` | `S_<yyyymmdd>_<shard>` | Zähler pro Waffe/Map/Modus (UpdateAsync-Merge) | jeder Server alle 600 s, Shard = `Util.Hash(game.JobId) % 8` |
| `CC_Mod_v1` | `F_<yyyymmdd>_<shard>` | Prüf-Flags (max 50 je Key) | jeder Server, ereignisbasiert, max 6/min |
| `CC_Mod_v1` | `R_<yyyymmdd>_<shard>` | Meldungen (max 50 je Key) | jeder Server, max 6/min |
| `CC_Mod_v1` | `BanLog` | letzte 100 Banns | nur Besitzer-Server |
| OrderedDataStore | `CC_LB_Wins_v1`, `CC_LB_Elims_v1`, `CC_LB_BestStreak_v1`, `CC_LB_TotalXP_v1`, `CC_LB_CrownBest_v1`, `CC_LB_WeeklyWins_<IsoWeek>` | Key `<UserId>`, Wert ganzzahlig 0..9e15 | LeaderboardService |
- **MessagingService** Thema `CC_Global`, Nachrichten `{Kind, …}` < 1 kB: `Announce {Text, UserId, Name}`, `AdminAbuse {Until, Coins2, Xp2}`,
  `Balance {Version}`, `Mutator {Key, Until}`. Empfänger prüft **jedes Feld** (Typ, Länge, Bereich); Sender empfängt auch selbst.
- **Budget pro Server** (Grenze `60 + 10 × Spieler` pro Minute je Kategorie, bei 18 Spielern 240): Profile ≈ 12/min (Auto-Save) +
  Join/Leave; Bestenlisten ≤ 6 Stores × 18 / 5 min ≈ 22/min Schreiben, Lesen 6 / 5 min; Stats 1 / 10 min; Flags/Reports ≤ 12/min;
  Balance-Poll 1 / 2 min. Admin-Statistik liest 8 Shards × Tage mit 0.25 s Abstand (7 Tage = 56 Lesungen).

## C15. Config-Schema (alle Schlüssel; MH-Stil: deutscher Banner, nummerierte Abschnitte, Lookups mit `assert` bei doppelten Ids)
Jedes Kindmodul gibt eine Tabelle zurück und **darf** `Validate(Config): {string}` enthalten (Fehlertexte mit exaktem Pfad).
`Config.Validate()` sammelt alles; SelfTest und Boot-`warn` nutzen es. Config wird repliziert → **keine Geheimnisse**.

```lua
-- Config/init.luau (WP1)
Config.GameName = "CLUTCH CLASH"; Config.Version = "1.0.0"
Config.Admin = { OwnerIsAdmin = true, StudioIsAdmin = true, StudioAllPlayersAdmin = false }
Config.Tech = { DataStoreName = "CC_Player_v1", DataVersion = 1, MessagingTopic = "CC_Global", AutoSaveSeconds = 90,
	AutoSaveStagger = 0.5, LoadAttempts = 6, SaveAttempts = 4, LockStaleSeconds = 1800, BindToCloseSeconds = 25,
	ReceiptKeep = 60, StateFlush = 0.2, FullStateEvery = 20, LiveStore = "CC_Live_v1", StatsStore = "CC_Stats_v1",
	ModStore = "CC_Mod_v1", Shards = 8, BoardPrefix = "CC_LB_", BoardWriteSeconds = 300, BalancePollSeconds = 120,
	StatsFlushSeconds = 600, PingAttrEvery = 2 }
Config.Studio = { NoSave = true, BotFillSeconds = 2, SelfTest = true }
Config.Debug = { LogRejects = false, ShowHitboxes = false, BotPaths = false, ForceRestricted = false }
Config.Server = { MaxPlayers = 18, ArenaSlots = 8, SlotSpacing = 4000, SlotRowZ = 4000, VaultDepth = 250,
	IdleMapSeconds = 180, KeepWarmMaps = 3, CleanupEvery = 30, MaxBots = 12, MaxBotsPerMatch = 7,
	MaxProjectilesPerArena = 40, MaxProjectilesTotal = 160, CrownAudienceRadius = 150 }
Config.Player = { MaxHp = 100, Walk = 16, Sprint = 22, JumpHeight = 7.2, AirJumpHeight = 6, SprintToFire = 0.12,
	Slide = { MinSpeed = 18, Start = 32, End = 14, Time = 0.75, Cooldown = 1.0, JumpKeep = 0.9, JumpCap = 30,
		CamDrop = 1.6, FovKick = 6, SpreadAdd = 1 },
	SpawnShield = 1.5, Regen = { Delay = 5, Rate = 12 }, KillY = -40, LobbyZoomMax = 14 }
Config.Colors = { TeamA = Color3.fromRGB(255, 140, 40), TeamB = Color3.fromRGB(60, 170, 255),
	Enemy = { Red = Color3.fromRGB(255, 59, 59), Magenta = Color3.fromRGB(255, 59, 216), Yellow = Color3.fromRGB(255, 212, 59), White = Color3.fromRGB(255, 255, 255) },
	Rarity = { Common = Color3.fromRGB(170, 170, 170), Rare = Color3.fromRGB(60, 140, 255), Epic = Color3.fromRGB(170, 90, 255),
		Legendary = Color3.fromRGB(255, 200, 40), Mythic = Color3.fromRGB(255, 60, 170) },
	Palette = { Cream = Color3.fromRGB(244, 235, 221), Mint = Color3.fromRGB(154, 209, 212), Pink = Color3.fromRGB(247, 183, 200),
		Lilac = Color3.fromRGB(185, 167, 242), Sand = Color3.fromRGB(242, 213, 154), Charcoal = Color3.fromRGB(43, 43, 51),
		Navy = Color3.fromRGB(28, 32, 64), White = Color3.fromRGB(235, 238, 245), Tip = Color3.fromRGB(255, 120, 0) } }
-- Kindmodule (dynamisch geladen): Weapons Combat Maps Modes Bots Security Progression Season Cosmetics Shop Client

-- Config/Weapons.luau (WP3)
{ List = { --[[ 15 WeaponDef aus B11.2–B11.5 + 4 Admin-Waffen (AdminOnly = true) ]] },
  DefaultLoadout = { Primary = "PopRifle", Secondary = "PipPistol", Melee = "BoxingGloves", Utility = "PopGrenade" },
  BalanceFields = { Damage = {1, 200}, MinMult = {0.1, 1}, HeadMult = {1, 4}, Interval = {0.04, 3}, Mag = {1, 100},
	Reload = {0.3, 6}, Equip = {0.1, 2}, SpreadHip = {0, 15}, SpreadAds = {0, 10}, FalloffStart = {0, 500},
	FalloffEnd = {1, 1500}, Range = {20, 1500}, MoveMult = {0.6, 1.3}, ["Projectile.SplashMax"] = {0, 300},
	["Projectile.Radius"] = {2, 25}, ["Melee.Range"] = {3, 12} } }

-- Config/Combat.luau (WP3)
{ InterpDelay = 0.10, MaxRewind = 0.38, RewindWindow = 0.075, HistoryHz = 30, HistorySlots = 24, HitTol = 0.35,
  HeadRadius = 0.8, BodyOffset = Vector3.new(0, -1, 0), BodyHalf = Vector3.new(1.5, 2.0, 0.8), HeadTieBreak = 0.5,
  OriginTol = 4, OriginSpeedCap = 0.4, LosShorten = 0.75, AgeMin = -0.05, AgeMax = 1.0, PingSlack = 0.35,
  IntervalTolerance = 0.75, RecvTolerance = 0.5, PerSecondFactor = 1.15, ShotIdGap = 4, AimNormTol = 0.01, MaxScale = 30,
  MeleeRangeSlack = 1.5, MeleeConeSlack = 10, KillCreditWindow = 8, AssistDamage = 25, AssistWindow = 8,
  RocketJump = { Radius = 4, Up = 55 }, ImpulseGrace = 1.5, ImpulseMaxSpeed = 95, ProjectileRadius = 0.5,
  MaxFastForward = 0.15, RecapMax = 12, AntiCamp = { Duel = 30, Team = 40, Pulse = 10, Show = 1 },
  ScopeGlintAfter = 0.3, ScopeHitKick = 2 }

-- Config/Maps.luau (WP2)
{ Maps = { PillarBox = { Name = { de = "Säulenkiste", en = "Pillar Box" }, Class = "S", TeamSizes = {1, 2},
		Modes = {"Duel1", "Duel2", "Mutator", "Practice"}, Moods = { Day = 40, Sunset = 30, NeonNight = 15, Fog = 15 }, PartBudget = 700 },
	BlockYard = { Name = { de = "Bauklotz-Hof", en = "Block Yard" }, Class = "M", TeamSizes = {1, 2, 3, 4},
		Modes = {"Duel1", "Duel2", "Duel3", "Duel4", "Mutator", "Practice", "FFA"}, Moods = { Day = 45, Sunset = 35, Fog = 20 }, PartBudget = 900 },
	NeonGrid = { Name = { de = "Neon-Raster", en = "Neon Grid" }, Class = "S", TeamSizes = {1, 2},
		Modes = {"Duel1", "Duel2", "Mutator", "Practice", "FFA"}, ForcedMood = "NeonNight", PartBudget = 700 },
	CandyDocks = { Name = { de = "Zuckerhafen", en = "Candy Docks" }, Class = "L", TeamSizes = {2, 3, 4},
		Modes = {"Duel2", "Duel3", "Duel4", "FFA"}, Moods = { Day = 40, Sunset = 35, Fog = 25 }, PartBudget = 1100 },
	SnowFort = { Name = { de = "Schneefestung", en = "Snow Fort" }, Class = "M", TeamSizes = {2, 3, 4},
		Modes = {"Duel2", "Duel3", "Duel4"}, ForcedMood = "Snowy", PartBudget = 900 },
	SkyGarden = { Name = { de = "Himmelsgarten", en = "Sky Garden" }, Class = "M", TeamSizes = {1, 2, 3},
		Modes = {"Duel1", "Duel2", "Duel3", "Mutator", "Practice", "FFA"}, Moods = { Day = 45, Sunset = 35, NeonNight = 20 }, PartBudget = 800 },
	CrownRing = { Name = { de = "Kronen-Ring", en = "Crown Ring" }, Class = "S", TeamSizes = {1}, Modes = {"Crown"}, Fixed = true, PartBudget = 400 } },
  Moods = { --[[ Day, Sunset, NeonNight, Fog, Snowy – Werte B8.2:
	{ ClockTime, Ambient, OutdoorAmbient, Atmosphere = { Density, Haze, Color, Decay, Glare = 0, Offset = 0.25 },
	  Bloom = { Intensity, Size, Threshold }, ColorCorrection = { Saturation, Contrast, Brightness = 0, TintColor }, Snow = false } ]] },
  LobbyMood = "Day", StagingOrigin = Vector3.new(0, 3000, 0), CrownOrigin = Vector3.new(95, -6, 0),
  Nav = { Grid = 6, Headroom = 5.5, StepMax = 4.5, MaxNodes = 300 } }

-- Config/Modes.luau (WP5)
{ Modes = {
	Duel1 = { Name = { de = "Duell 1v1", en = "Duel 1v1" }, Teams = 2, TeamSize = 1, Ruleset = "Rounds", RoundsToWin = 4, RoundTime = 60, Overtime = 15, RoundCap = 9, Vote = true, Bots = true },
	Duel2 = { …, TeamSize = 2, RoundTime = 75 }, Duel3 = { …, TeamSize = 3, RoundTime = 90 }, Duel4 = { …, TeamSize = 4, RoundTime = 90 },
	Mutator = { TeamSize = 1, RoundsToWin = 3, RoundTime = 50, Overtime = 15, RoundCap = 7, Vote = true, Bots = true, UsesMutator = true },
	Crown = { TeamSize = 1, RoundsToWin = 2, RoundTime = 45, Overtime = 10, RoundCap = 5, Vote = false, FixedMap = "CrownRing" },
	Practice = { TeamSize = 1, RoundsToWin = 3, RoundTime = 60, Overtime = 15, RoundCap = 7, Vote = false, AlwaysBot = true,
		Rewards = { XpMult = 0.3, CoinMult = 0, MasteryMult = 0.5 } },
	FFA = { Teams = 0, MaxPlayers = 8, Ruleset = "Respawn", ScoreToWin = 25, KillPoints = 2, AssistPoints = 1, MatchTime = 300,
		RespawnDelay = 3, FillTo = 6, DropInUntil = 240, Vote = true } },
  Mutators = { --[[ B7: [Key] = { Name = {de,en}, Desc = {de,en}, Rules = { partielle ContextRules } } ]] },
  Rotation = { "MoonJump", "HeadsOnly", "Turbo", "BigHeads", "MeleeMayhem", "SnipersOnly", "LuckyLoadout", "Instapop" },
  Match = { VoteSeconds = 5, LoadTimeout = 4, IntroSeconds = 2, FirstPrep = 4, Prep = 3, ReadyMinPrep = 1, RoundEnd = 2.5,
	Results = 10, ZoneRadius = 8, ZoneCapture = 3, ZoneDecay = 0.5, SuddenDeath = 30, SuddenDeathHp = 50, AfkWarn = 20,
	AfkKick = 30, LeaverCooldown = 60, LeaverBotDelay = 10, RecentMaps = 2, ZoneHz = 5 },
  Queue = { BotFillSeconds = 8, RookieFillSeconds = 3, FillNowAfter = 3, MatcherHz = 2, PadScanHz = 4, SeatRadius = 2.2,
	SeatLeaveSeconds = 1.5, InputMatchSeconds = 6, MmrWindow = 200, MmrWiden = 50, MmrWidenEvery = 3,
	NewPlayerMatches = 5, NewPlayerPool = 15, CrownLine = 6, CrownIdleBot = 15, CrownSoloWait = 8 } }

-- Config/Bots.luau (WP6)
{ Difficulties = { --[[ Tabelle B10.3: [Name] = { Reaction, AimErr, Tau, MinErr, HeadChance, StrafeMin, StrafeMax,
	MoveTech, UtilityChance, RetreatHp, SpeedMult } ]] },
  Names = { --[[ 30 Namen B10.2 ]] }, LoadoutWeights = { --[[ [weaponKey] = Gewicht ]] }, FreeOnly = { Rookie = true, Easy = true },
  TickHz = 10, MaxRaycastsPerTick = 3, LateralErrPerStud = 0.15, RepathSeconds = 2, StuckSeconds = 1.5, PushDelay = 0.4,
  RookieMissShots = 2, RookieMatches = 3, Adaptive = { LossesDown = 2, WinsUp = 3, Range = 1 }, MmrTiers = { Easy = 900, Hard = 1150 },
  CrownTiers = { { MaxStreak = 2, Diff = "Normal" }, { MaxStreak = 5, Diff = "Hard" }, { MaxStreak = 1e9, Diff = "Insane" } },
  Range = { DummyHp = 150, DummyRegenAfter = 3, RailSpeed = 8, RailFlip = 2 } }

-- Config/Security.luau (WP7)
{ MoveHz = 5, BaseAllowedSpeed = 32, SpeedTolerance = 1.15, SpeedSlack = 6, BucketSeconds = 1.0, TeleportGrace = 1.0,
  TeleportMaxDist = 40, VerticalSlack = 3, FlyAirSeconds = 3, FlyAirSecondsMoon = 6,
  Weights = { Honeypot = 100, Type = 5, Rate = 1, RateBurst = 15, Origin = 2, Los = 1, LosBurst = 10, Mismatch = 10,
	Speed = 2, Teleport = 8, Fly = 5, Stats = 20 },
  DecayEvery = 30, Review = 25, Kick = 60, AutoBan = { Enabled = true, HardKicks = 3, WindowDays = 7, Days = 1 },
  Stats = { MinHits = 60, HeadRatio = 0.75, Accuracy = 0.70, MismatchClaims = 30, MismatchRatio = 0.4 },
  Buckets = { Fire = { 12, 20 }, WeaponAction = { 12, 12 }, Look = { 20, 20 } }, Rates = { Request = { 8, 1 }, Admin = { 12, 1 } },
  ReportLimit = { 3, 600 }, BanPresets = { ["1h"] = 3600, ["1d"] = 86400, ["7d"] = 604800, ["30d"] = 2592000, perm = -1 },
  AnnounceMax = 200, WarnMax = 150, AnnounceSeconds = 8, AnnounceQueue = 5, AdminAbuseMaxMinutes = 60 }

-- Config/Progression.luau (WP8)
{ Curve = { Base = 250, Step = 50, MaxLevel = 100 },
  Xp = { Played = 40, Win = 60, Round = 12, Elim = 15, Assist = 7, HeadElim = 5, MeleeElim = 10, Mvp = 20, GG = 5, CrownDefence = 15 },
  XpMult = { Vip = 0.2, DoubleXP = 1.0, Boost = 1.0, Party = 1.0, Event = 1.0, Cap = 3.0, Bot = 0.6, Practice = 0.3 },
  Coins = { Played = 30, Round = 10, Elim = 6, Assist = 3, HeadElim = 2, Win = 50, Mvp = 15, GG = 5, StreakStep = 5,
	StreakCap = 30, BotMult = 0.6, BotMin = 15, BotDailyCap = 2500, DrawBonus = 0.1 },
  FirstWin = { Xp = 200, Coins = 150 }, Tutorial = { Xp = 250, Coins = 300 },
  LevelRewards = { CoinsBase = 50, CoinsPerLevel = 10, FreeWeaponLevels = { 4, 10, 20 }, KeyEvery = 5, GemsEvery = 10,
	Gems = 25, Titles = { [10] = "TT_Lv10", [25] = "TT_Lv25", [50] = "TT_Lv50", [75] = "TT_Lv75", [100] = "TT_Lv100" } },
  Mastery = { Tiers = { 10, 30, 75, 150, 300, 600, 1000, 2000, 3500, 6000 }, MeleeUtilityMult = 2, BoostMult = 2,
	Rewards = { { Coins = 150 }, { Wrap = "W_MBronze" }, { Keys = 1, Coins = 250 }, { Wrap = "W_MSilver" }, { Wrap = "W_MGold" },
		{ Gems = 50 }, { Wrap = "W_MDiamond" }, { Wrap = "W_MNeon" }, { Wrap = "W_MGalaxy", Title = "Master" }, { Wrap = "W_MPrism" } } },
  Quests = { DailyCount = 3, WeeklyCount = 5, FreeRerolls = 1, RerollCoins = 100,
	DailyRewards = { Easy = { Coins = 150, PassXp = 300 }, Medium = { Coins = 250, PassXp = 300 }, Hard = { Coins = 400, PassXp = 300 } },
	WeeklyReward = { Coins = 600, PassXp = 1500 }, WeeklyChest = { Keys = 2, Gems = 50 },
	Daily = { --[[ 20 Einträge: { Id, Kind, Goal, Tier, Filter? } aus B16.3 ]] }, Weekly = { --[[ 8 ]] },
	Beginner = { --[[ 10 Schritte B16.3: { Kind, Goal, Coins, FreePick? } ]] } },
  Login = { Calendar = { { Coins = 150 }, { Keys = 1 }, { Coins = 250 }, { Gems = 15 }, { Coins = 350 }, { Keys = 1 }, { Keys = 2, Gems = 30 } },
	FirstCycleCharm = "C_CalendarCat", FreezesPerWeek = 1, PassXp = 100, OnFireDays = 7 },
  Wheel = { FreeSpins = 1, VipSpins = 1, AllDailiesSpins = 1, Prizes = { { Coins = 100, W = 30 }, { Coins = 200, W = 22 }, { Keys = 1, W = 15 },
	{ XpBoostSeconds = 900, W = 12 }, { Gems = 25, W = 10 }, { Coins = 500, W = 7 }, { Keys = 3, W = 3 }, { Gems = 250, W = 1 } } },
  Playtime = { Minutes = { 5, 15, 30, 60 }, Rewards = { { Coins = 50 }, { Coins = 100 }, { Keys = 1 }, { Coins = 150 } } },
  Achievements = { --[[ 12 aus B16.5: [Id] = { Name, Desc, Stat, Goal, Reward } ]] },
  Mmr = { Start = 1000, KNew = 40, KNewGames = 20, K = 24 },
  Bounty = { MinStreak = 5, Base = 100, Step = 25, Cap = 300 }, Comeback = { Losses = 3, CoinBonus = 0.25 },
  Crown = { DefenceCoinsHuman = 40, DefenceCoinsBot = 10, Announce = { 3, 5, 10 } },
  Honor = { CommendDailyCap = 3, Badges = { 10, 50, 200 } }, GG = { Xp = 5, Coins = 5 },
  Codes = { LAUNCH = { Grant = { Coins = 250 }, Expires = "2027-01-31T00:00:00Z" }, CLUTCH = { Grant = { Keys = 1 } } },
  Leaderboards = { "Wins", "Elims", "BestStreak", "TotalXP", "WeeklyWins", "CrownBest" },
  Chat = { Rewrites = { ez = { de = "gg wp", en = "gg wp" }, ggez = { de = "GG ❤", en = "GG ❤" }, noob = { de = "Freund", en = "friend" },
	p2w = { de = "faires Loadout", en = "fair loadout" }, trash = { de = "gutes Spiel", en = "good game" } } } }

-- Config/Season.luau (WP8)
{ Seasons = { { Id = 1, Name = { de = "Saison 1: Neon-Start", en = "Season 1: Neon Start" },
	StartUtc = "2026-10-15T00:00:00Z", EndUtc = "2026-12-10T00:00:00Z", Tiers = 30, TierXp = 3000,
	Theme = { Primary = Color3.fromRGB(255, 60, 170), Accent = Color3.fromRGB(0, 230, 255) },
	Free = { --[[ ["2"] = { Coins = 300 }, … B21.2 ]] }, Premium = { --[[ ["1"] = { Cosmetic = "S_PipPistol_RayGun" }, … ]] } } } }

-- Config/Cosmetics.luau (WP9)
{ Rarities = { "Common", "Rare", "Epic", "Legendary", "Mythic" },
  Wraps = { --[[ [Id] = { Name = {de,en}, Rarity, Roles = { Body = {Color, Material}, Detail = …, Accent = …, Metal = …, Grip = … },
	Anim = nil | "Pulse" | "Rainbow" | "Galaxy" | "Sparkle", Price = { Gems = n } | { Coins = n } | nil, Source } – B19 ]] },
  Skins = { --[[ [Id] = { Name, Rarity, Weapon, Recipe, Price?, Source } ]] },
  Charms = { --[[ [Id] = { Name, Rarity, Recipe, Price?, Source } ]] },
  Finishers = { --[[ [Id] = { Name, Rarity, Builder, Price?, Source } ]] },
  Tracers = { --[[ [Id] = { Name, Rarity, Color = Color3 | "Team" | "Rainbow", Width0, Width1, Texture = "rbxasset://textures/gradient.png" | "", Sparkle } ]] },
  Titles = { --[[ [Id] = { Name = {de,en}, Color? } ]] },
  Exclusive = { --[[ Ids, die während ihrer Saison nicht im Katalog/in Kisten sind (alle Pass-Items) ]] } }

-- Config/Shop.luau (WP9)
{ GamePasses = { { Key = "VIP", Id = 0, Price = 349, Name = { de = "VIP", en = "VIP" }, Desc = { de = "…", en = "…" } }, --[[ DoubleXP 299, LoadoutPlus 99, MasteryBoost 199 ]] },
  Products = { { Key = "Gems120", Id = 0, Price = 99, Grant = { Gems = 120 }, FirstBonus = true, Random = false }, --[[ … alle B22.2 ]]
	{ Key = "StarterPack", Id = 0, Price = 49, Grant = { Gems = 250, Cosmetics = { "W_RookieRainbow", "C_StarterStar", "TT_Frischling" } },
		Once = true, Fallback = { Gems = 120 } },
	{ Key = "PassPremium", Id = 0, Price = 449, Grant = { PassPremium = true }, PerSeason = true, Fallback = { Gems = 500 } } },
  CatalogPrices = { Common = 120, Rare = 250, Epic = 500, Legendary = 1000, Mythic = 2200 }, FeaturedDiscount = 0.2, FeaturedSlots = 6,
  Crates = { S1 = { Name = { de = "Blaster-Kiste S1", en = "Blaster Crate S1" }, GemPrice = 120,
	Items = { --[[ { Id, Weight } × 24, Summe 10000 – B20.1 ]] }, PityAfter = 29, PityRarities = { "Legendary", "Mythic" } } },
  DupeShards = { Common = 20, Rare = 50, Epic = 150, Legendary = 400, Mythic = 800 },
  ShardPrices = { Common = 100, Rare = 250, Epic = 600, Legendary = 1500, Mythic = 3000 },
  PresetSlotCoins = 5000, Presets = { Base = 3, LoadoutPlus = 8, CoinSlotsMax = 2 },
  StarterOfferHours = 72, MaxOffersPerSession = 1, TierGemFallback = 40, PassOwnedGems = 500, XpBoostCapSeconds = 86400,
  PartyBoost = { Seconds = 900, CapSeconds = 3600 } }

-- Config/Client.luau (WP10)
{ Keys = { Fire = { "MouseButton1" }, Ads = { "MouseButton2" }, Reload = { "R" }, Slot1 = { "One" }, Slot2 = { "Two" }, Slot3 = { "Three" },
	Slot4 = { "Four" }, LastWeapon = { "Q" }, Utility = { "E" }, Melee = { "F" }, Sprint = { "LeftShift" }, Slide = { "C", "LeftControl" },
	Inspect = { "V" }, Scoreboard = { "Tab" }, Loadout = { "L" }, Menu = { "M" }, Ready = { "Return" }, AdminPanel = { "P" },
	Fly = { "G" }, Spectate = { "X" }, Debug = { "F8" } },
  Gamepad = { Fire = "ButtonR2", Ads = "ButtonL2", Reload = "ButtonX", Cycle = "ButtonY", Melee = "ButtonL1", Utility = "ButtonR1",
	Sprint = "ButtonL3", Slide = "ButtonB", Scoreboard = "ButtonSelect", Ready = "ButtonStart", TriggerThreshold = 0.4 },
  AimAssist = { Gamepad = { Cone = 3.5, Friction = 0.55, Magnet = 4 }, Touch = { Cone = 4.5, Friction = 0.55, Magnet = 5 },
	Range = 70, RankedMult = 0.5, AutoFireRate = 0.85, AutoFireDwell = 0.15 },
  DefaultSettings = { Fov = 80, SensMouse = 0.5, SensPad = 0.5, SensTouch = 0.6, AdsMult = 0.8, ScopeMult = 0.6, InvertY = false,
	AdsToggle = false, SprintToggle = false, AutoReload = true, AutoFire = "auto", AimAssist = 1, Crosshair = { Style = 1,
	Color = "White", Size = 8, Gap = 4, Dot = true }, EnemyColor = "Red", DamageNumbers = true, HitSound = true, ReducedFx = false,
	Shake = 1, LeftHanded = false, ButtonScale = 1, Lang = "auto", Sfx = 1, Music = 0.5, Ui = 0.8, ShowNet = false,
	AutoRequeue = false, PublicDrops = true },
  SettingsSchema = { --[[ [Key] = { Type = "number"|"boolean"|"enum", Min?, Max?, Options? } für jeden DefaultSettings-Schlüssel;
	AutoFire Options = {"auto","on","off"} ("auto" = an bei Touch in Casual) ]] },
  Sounds = { RifleShot = 0, PistolShot = 0, SmgShot = 0, ShotgunShot = 0, SniperShot = 0, CannonShot = 0, RocketLaunch = 0,
	Explosion = 0, MagOut = 0, MagIn = 0, Equip = 0, MeleeSwing = 0, MeleeHit = 0, Hitmarker = 0, Headshot = 0, Kill = 0,
	Eliminated = 0, UIClick = 0, UIHover = 0, UIError = 0, Countdown = 0, Go = 0, Win = 0, Lose = 0, LevelUp = 0, Heal = 0,
	LobbyMusic = 0, MatchMusic = 0 },   -- 0 = Rezept aus ASSETS.md §2.2
  TouchButtonMin = 64, AutoReducedFx = { Fps = 35, Seconds = 5 }, HighlightCap = 31,
  Pools = { Tracers = 48, Impacts = 32, DamageNumbers = 24, Sounds = 24, Lights = 4, Projectiles = 40, Finishers = 4 } }
```

## C16. Sprachen (`Lang`, WP1 + Domänen-Dateien)
- Jede Domänen-Datei gibt `{ de = { [key] = string }, en = { [key] = string } }` zurück. **Präfix-Pflicht** je Datei:
  `core.` (WP1), `world.` (WP2), `combat.` (WP3, auch Texte für WP4/WP10-Kampf-HUD), `match.` (WP5), `bot.` (WP6), `admin.` (WP7),
  `prog.` (WP8), `shop.` und `item.` (WP9), `ui.` (WP10). `Lang/init` lädt dynamisch, prüft Präfix und doppelte Schlüssel (`warn`).
- `Lang.T(lang, key, ...)` = `string.format(text, ...)` in pcall; fehlt der Schlüssel → Englisch → Schlüssel selbst.
- Sprache: `Lang.For(p, Settings.Lang)`: `"de"`/`"en"` aus Einstellung, sonst `"de"` wenn `p.LocaleId` mit `"de"` beginnt, sonst `"en"`.
- Server lokalisiert Notify/Ansagen pro Empfänger. Config-Anzeigenamen sind `{de, en}`-Paare (`Lang.Pick`). SelfTest: `Lang.Missing()` leer.
- Pflicht-Schlüssel (Auszug; jedes WP ergänzt seine): `core.gameName`, `core.loading` („Lädt noch…“/„Loading…“), `core.error`,
  `core.noAnswer` („📡 Keine Antwort vom Server“), `core.studioNoSave`, `match.found` („MATCH GEFUNDEN!“/„MATCH FOUND!“),
  `match.botIn` („BOT KOMMT IN %d“/„BOT JOINS IN %d“), `match.searching` („%d suchen“/„%d searching“), `match.overtime`
  („VERLÄNGERUNG – HALTE DIE ZONE!“/„OVERTIME – HOLD THE ZONE!“), `match.clutch`, `match.ace`, `match.flawless`, `match.comeback`,
  `match.matchPoint`, `match.suddenDeath`, `match.arenasFull`, `match.botsBusy`, `combat.popped` („%s GEPOPPT“/„POPPED %s“),
  `combat.hpLeft` („REST-LEBEN: %d“/„HP LEFT: %d“), `combat.dealt` („Du hast %d Schaden in %d Treffern gemacht (%d Kopf)“),
  `shop.noP2W` („ALLE WAFFEN ERSPIELBAR – KEIN PAY-TO-WIN“/„EVERY WEAPON EARNABLE – NO PAY-TO-WIN“), `shop.notSetUp`
  („Bald verfügbar“/„Not set up yet“), `shop.restricted` („In deiner Region nicht verfügbar“/„Not available in your region“),
  `shop.oddsTitle` („Details & Quoten“/„Details & odds“), `admin.denied`, `admin.tainted`.

## C17. Performance-Budgets
| Bereich | Budget |
|---|---|
| Server-Script-Zeit | Heartbeat Ø ≤ 5 ms, p99 ≤ 12 ms bei 18 Spielern + 12 Bots + 8 Arenen (Scheduler-Statistik im Admin-Panel) |
| Takte | History 30 Hz · Projektile jeden Frame · Bots 10 Hz gestaffelt · Anti-Cheat 5 Hz gestaffelt · Pads 4 Hz · Matcher 2 Hz · Matches 5 Hz (Fristen über `GetServerTimeNow`) · State-Flush 0.2 s · FX 20 Hz · LookBatch 10 Hz · Ping-Attribut 0.5 Hz |
| Pro Schuss | Validierung ≤ 0.15 ms; ≤ 200 Raycasts pro Frame gesamt; Bots ≤ 3 Raycasts pro Tick |
| Grenzen | History 24 Slots/Combatant · Projektile 40/Arena, 160 gesamt · Bots 12 · Belege 60 · Namens-Cache Bestenliste 200 · Flags lokal 200 · Recap 12 Treffer |
| Parts Client | Lobby ≤ 2.500 · Map S ≤ 700, M ≤ 900, L ≤ 1.100 · gesamt ≤ 11.300 · Viewmodel ≤ 30 · Finisher ≤ 25 · Charm ≤ 8 |
| Client-FX | Pools: Tracer 48, Impact-Attachments 32, Schadenszahlen 24, Sounds 24, Lichter ≤ 4, Highlights ≤ 31, Finisher ≤ 4 gleichzeitig, ≤ 8 Partikel pro Schuss; ein `PreRender`-Loop für alle Effekte; UI nur bei Wertänderung schreiben; ReducedFx halbiert Partikel, schaltet Lichter/Bloom aus |
| Ziel-FPS | 60 auf Mittelklasse-PC, ≥ 30 auf 3 Jahre altem Handy; Client-Script ≤ 4 ms/Frame |
| Netzwerk | Hoch: ≤ 18 `Fire`/s + 12 Hz `Look` + Ereignisse; Runter (4v4): ≤ 25 KB/s Ø, `FX` ≤ 871 B pro Paket, `LookBatch` ≤ 51 B; keine Server-Tweens, keine Part pro Kugel, kein Instanz-Baum mitten im Match außer dem einmaligen Map-Klon |

## C18. Studio-Solo, „Test → 2 Players“, SelfTest, Debug
- **Solo (Play):** Spawn in der Lobby, Admin-Knopf sichtbar (Taste P), NoSave-Toast. 1v1-Pad → nach **2 s** Bot → komplettes Match
  (Vote, Runden, Overtime, Ergebnis). Alle Pads, PLAY-Einträge, Crown (Bot-Herausforderer), FFA (Bots), Practice, Range funktionieren.
  Tutorial startet beim ersten Join (Flag im NoSave-Profil).
- **Käufe:** Produkte mit `Id = 0` → „Bald verfügbar“; Admin-Debug „Kauf simulieren“ ruft dieselbe Grant-Funktion. Mit echten Ids gehen
  Studio-Testkäufe durch `ProcessReceipt`.
- **Policy:** in Studio schlägt `GetPolicyInfoForPlayerAsync` evtl. fehl → eingeschränkt (Kisten-Pfad mit Schlüssel testbar);
  „Policy simulieren“ im Admin-Debug testet beide Pfade; `Config.Debug.ForceRestricted`.
- **Test → 2 Players:** Player1 (`−1`) Admin, Player2 (`−2`) nicht – Admin-Aufrufe werden abgelehnt und einmal geloggt. Beide auf einem
  1v1-Pad = echtes PvP ohne Bots; 2v2-Pad mit beiden = 2 Menschen + 2 Bots; Player1 in Range, Player2 queued → kein Konflikt.
- **Netzwerk-Simulator** (Studio-Beta „New Device Simulator“): 150 ms Latenz, ±30 ms Jitter, 2 % Verlust → Treffer müssen innerhalb der
  0.38 s Rückspul-Grenze zählen; Reject-Log prüfen.
- **SelfTestService** (Studio, `Config.Studio.SelfTest`): lädt `Server/Tests/*` und meldet `[SelfTest] n/n PASS`. Pflicht-Tests:
  Hitbox-Strahlen (Kopf/Körper/vorbei), Falloff-Ränder, Spread-Determinismus (gleicher Seed → gleiche Richtungen, `#dirs == Pellets`),
  Net-Rundreisen (Look, LookBatch, FX), `Util.FormatNumber`-Fälle aus REUSE §14.2, Elo-Symmetrie, Level-Kurve, Kisten-Gewichte = 10000,
  Odds-Anzeige = 100.00, `Config.Validate()` leer, `Lang.Missing()` leer, jede Map: Teilebudget, Spawns frei (kein Part im Kopfbereich),
  Nav-Graph zusammenhängend, Zone erreichbar.
- **Debug:** F8-Overlay (Admin), Hitbox-Anzeige, Reject-Codes, Bot-Pfade, `SkipDay`, `UnlockAll`.
- **Luau-CLI-Tests** (ohne Roblox-Typen): `tests/util.test.luau`, `tests/progressmath.test.luau`, `tests/odds.test.luau`.

## C19. Compliance
- **Maturity-Fragebogen:** Gewalt = wiederholt, mild, unrealistisch (Körper verschwinden sofort in Konfetti) → **Mild**; Blut: **Nein**;
  bezahlte Zufallsitems: **Ja** (Gem-Kisten, Quoten sichtbar, PolicyService respektiert); Chat über TextChatService.
- Spielzeug-Blaster mit oranger Spitze, keine echten Waffennamen.
- Banns: Regeln + Einspruchs-Hinweis in Einstellungen → Info. `DisplayReason` wird von Roblox gefiltert.
- Nutzertext für andere immer gefiltert; `TextChannel:DisplaySystemMessage` nur für spielgenerierte Texte.
- Keine Belohnung für Einladungen, Likes oder Favoriten.

---

# D) Arbeitspakete (11 Pakete, parallel)

## D0. Regeln für alle Pakete
1. **Nur eigene Dateien** (C2) anlegen/ändern. Shared-Dateien anderer WPs nur lesen/`require`n. Fehlt etwas im Vertrag →
   defensiv programmieren (nil-Checks, `pcall`), im Abschlussbericht melden; Verträge **nicht** eigenmächtig ändern.
2. Server-Services nie gegenseitig `require`n – nur `Services.X` zur Laufzeit. Client-Module nur über `ctx.Modules.X` (nil-sicher) und `ctx.Hooks`.
3. Qualitäts-Gates pro Paket: `stylua --check`, `selene`, luau-lsp (C1.4-Regel), `rojo build` ohne Fehler, eigene Tests grün.
   Datei-Kopf: deutscher Banner-Kommentar (Zweck, Besitzer-WP, öffentliche API).
4. MH-Teile laut `docs/REUSE.md` kopieren/anpassen (inkl. §14-Fixes); **nichts** in `roblox-meteor-heist` ändern.
5. Nur Assets aus `docs/ASSETS.md`. Keine veralteten APIs (Muss-Regel 10). Keine `while`-Schleife pro Spieler; Takte über `Lib/Scheduler`.
6. **Integration** (nach allen WPs, Lead/Orchestrator): `scripts/check.sh` komplett, Studio-Testplan, `ClutchClash.rbxlx` bauen.
   Fehler in fremden Dateien gehen an das Besitzer-WP zurück.

---

## WP1 – Core & Plattform
- **Dateien:** `default.project.json`, `rbx.yml`, `selene.toml`, `stylua.toml`, `.gitignore`, `scripts/check.sh`, `src/character/Health.server.luau`,
  `src/shared/Config/init.luau`, `src/shared/Lang/init.luau`, `src/shared/Lang/Core.luau`, `src/shared/Types.luau`, `src/shared/Util.luau`,
  `src/shared/Net.luau`, `src/shared/Spring.luau`, `src/server/Main.server.luau`, `src/server/Lib/Scheduler.luau`,
  `src/server/Services/Remotes.luau`, `DataService.luau`, `PlayerStateService.luau`, `SelfTestService.luau`, `src/server/Tests/CoreTests.luau`,
  `tests/util.test.luau`.
- **Liefert:** C1, C3, C4, C5.1, C5.2, C6.1, C13, C15 (`Config/init`), C16 (`Lang/init` + `core.*`).
- **Braucht:** `MonetizationService.LoadPasses(p)` + `MonetizationService.RandomAllowed(p)` (pcall, im Ready-Gate);
  `Config.Client.DefaultSettings` / `SettingsSchema` (WP10) für `SaveSettings`; `Child.Validate(Config)` aller Config-Kinder.
- **Aufgaben:**
  - Projektdateien wie C1 (JSON exakt), `rbx.yml` = MH + Erweiterung C1.3, `.gitignore` mit `sourcemap.json`.
  - `Main.server.luau` = MH-Lader mit `order` aus C3, Prefix `[Clutch Clash]`.
  - `Config/init`: Abschnitte C15 + dynamisches Laden der 11 Kinder + `Weapon`/`WeaponById`/`ApplyBalance` (Overrides nur für
    Felder in `BalanceFields`, geklemmt; `Disabled` setzt `Enabled=false`) + `Validate`.
  - `Lang/init`: C16 inkl. Präfix-Prüfung, Fallback, `Missing()`.
  - `Util`: MH-Util + FormatNumber-Fix (REUSE §14.2, Code dort) + `TokenBucket`, `IsFinite`, `UtcDay`, `IsoWeek`, `Hash` (FNV-1a 32 Bit, auf 2^31 begrenzt).
  - `Net`: Remote-Liste C8 + Codecs mit exakten Byte-Layouts (C8) + Quantisierung (Positionen ×10 als i16, Pitch auf ±80 geklemmt).
  - `DataService`: MH 1:1 + §14.3-Fixes (Snapshot-Autosave mit pcall, serialisierte Saves, NoSave für Studio/`UserId ≤ 0`, warn bei Lock-Übernahme) + `DEFAULT_DATA` C13.
  - `PlayerStateService`: `Handle`-Registry + `Request.OnServerInvoke`-Dispatcher, `Provide`/`MarkDirty` (Sticky, 0.2 s, voll alle 20 s,
    Schnappschuss-Iteration), Ready-Gate, leaderstats (`Level`, `Wins`), Attribut `PingMs` alle 2 s, Handler `GetFull`, `SaveSettings`, `TutorialFlag`;
    eigene State-Keys: `Settings`, `Flags`, `Server = {Version, Studio, NoSave}`.
  - `Remotes.luau`: alle Remotes aus `Net.RemoteList`; Honeypot `GrantCoins` nur erzeugen (Handler macht WP7).
  - `SelfTestService` + `CoreTests` (Util, Net-Rundreisen, Config.Validate leer, Lang.Missing leer).
- **Abnahme:** (1) `rojo build` erzeugt alle Properties aus C1.2 (grep im .rbxlx). (2) Studio-Solo: Join → Toast „Studio: Fortschritt wird
  nicht gespeichert“, kein Fehler im Output über 10 min mit Join/Leave. (3) `Request("Unbekannt")` → `{Ok=false}`. (4) State kommt ≤ 5×/s,
  voll alle 20 s. (5) `[SelfTest] n/n PASS` für Core-Tests. (6) BindToClose ohne Fehler.
- **Tests:** `tests/util.test.luau`: alle FormatNumber-Fälle aus REUSE §14.2 + jede 1000er-Potenz bis 1e36, WeightedPick mit 0/NaN-Gewichten,
  RateLimiter/TokenBucket mit künstlicher Uhr, `UtcDay(0) == 0`, `IsoWeek` für 2026-10-11 = 202641.

## WP2 – Welt: Lobby, Arenen, Maps, Licht
- **Dateien:** `Config/Maps.luau`, `Lang/World.luau`, `Services/GraphicsService.luau`, `Services/ArenaService.luau`, `Services/LobbyBuilder.luau`,
  `World/MapKit.luau`, `World/NavBuilder.luau`, `World/LobbyLayout.luau`, `World/Maps/{PillarBox,BlockYard,NeonGrid,CandyDocks,SnowFort,SkyGarden,CrownRing}.luau`,
  `src/client/Modules/ArenaLook.luau`, `Tests/WorldTests.luau`.
- **Liefert:** C5.3, `ArenaLook` (C7.4), B2, B8, B9.
- **Braucht:** nur WP1 (Types, Config, Util, Lang, Scheduler). Client: `ctx.Hooks` (`Match:Start {Slot, Mood}`, `Match:Closed`, `Armed {Ctx}`, `Disarmed`).
- **Aufgaben:**
  - `MapKit` (MH-MapBuilder-Helfer: `part`, `wedge`, `cyl`, `ball`, `sign`, `surfaceLetter`, `barrier`), Spiegel-Logik B8.1, Teilezähler.
  - 7 Map-Dateien exakt nach B8.3 (Koordinaten, Größen, Farben, Spawns, FFA, CoverNodes).
  - `ArenaService.Init`: Kollisionsgruppen C12.6 registrieren (**zuerst**), Templates bauen (Staging → Nav-Graph → ServerStorage),
    Slot-Ordner + Vaults anlegen, Crown-Ring-Arena (Slot 0) an `CrownOrigin` fest einbauen, Range als Arena-Objekt.
    Acquire/Release/Aufräumen B9.2 (Aufräumen über Scheduler 1/30 Hz). Pro Arena `MapParams` (`IncludeInstances = {Map}`).
  - `LobbyBuilder`: komplette Lobby B2 (≤ 2.500 Parts), Pad-Parts mit Attributen `Mode`, `PadId` (Rest schreibt WP5), Sitzkreise,
    Kiosk-Prompts (`Window`-Attribut, `HoldDuration 0`, `MaxActivationDistance 10`), Bot-Booth-Pads mit Prompt-Attribut `Practice = "<Stufe>"`,
    Bestenlisten-Tafeln (leere SurfaceGui `Board` mit 10 Zeilen-Rahmen, Titel zweisprachig „SIEGE / WINS“ usw.), Königs-Tafel (SurfaceGui mit
    `ImageLabel` „Avatar“, Labels „Name“, „Streak“), Kisten-Automat (Model `CrateMachine`), VIP-Balkon + Tür (Part `VipDoor`).
  - `GraphicsService`: MH-Version gekürzt, Lobby-Look `Day` aus `Config.Maps.Moods`; danach nie mehr Lighting serverseitig ändern.
  - `ArenaLook`: `SetWorld` (B9.4, inkl. DescendantAdded), `ApplyMood` (eigene Atmosphere/Bloom/ColorCorrection-Instanzen `CC_Mood*`,
    Schnee-Emitter an Kamera), `RestoreLobby`; reagiert auf Hooks (Slot 0 und Range = Welt „Lobby“).
- **Abnahme:** (1) Alle 7 Maps bauen ohne Fehler, innerhalb Budget, punktsymmetrisch (SelfTest vergleicht gespiegelte Teilemittelpunkte).
  (2) Lobby ≤ 2.500 Parts. (3) Acquire derselben Map nach Release liefert den warmen Slot ohne Neubau; 9. Acquire bei 8 belegten → nil.
  (4) Aufräumen hält ≤ 3 warme freie Slots. (5) Im Match sieht der Client weder Lobby noch andere Slots; zurück in der Lobby keine Slots.
  (6) Stimmungen setzen/zurücksetzen ohne Rest. (7) Nav-Graph jeder Map zusammenhängend, Zone und alle Spawns erreichbar.
- **Tests:** `WorldTests`: Teilezahl, Spawn-Freiheit (Ray-Box 2×5×2 über jedem Spawn trifft nichts), Nav-Erreichbarkeit (BFS), Symmetrie,
  Acquire/Release-Zyklus.

## WP3 – Kampf (Server) & Treffer-Mathematik
- **Dateien:** `Config/Weapons.luau`, `Config/Combat.luau`, `Lang/Combat.luau`, `Shared/Spread.luau`, `Shared/Hitbox.luau`, `Shared/Damage.luau`,
  `Shared/Ballistics.luau`, `Services/HistoryService.luau`, `Services/CombatService.luau`, `Services/CharacterService.luau`,
  `Services/ProjectileService.luau`, `Services/WeaponService.luau`, `Services/ReplicationService.luau`, `Tests/CombatTests.luau`.
- **Liefert:** C5.4, C6.2, C10, C11, B11 (Werte), B12-Serverteile, B13, B14.8-Serverteil.
- **Braucht:** `AntiCheatService.NoteTeleport/Grace/Exempt/Add` (pcall) · `AdminService.Power(p, name)` (pcall) ·
  `ShopService.GetCosmetics(p, key)`, `ShopService.Tracer(p)` (pcall, Fallback leer/`T_Team`) · `BalanceService.Stat` (pcall) ·
  `RewardService.Track(p, kind, n)` (pcall; Kinds `Heal`, `Slide`) · `WeaponModels.Build(key, opts)` (WP4) ·
  `CosmeticModels.ApplyWrap/BuildCharm` (WP9) · Kontexte registrieren WP5/WP6 über `CombatService.RegisterContext`.
- **Aufgaben:**
  - `Config/Weapons` mit allen Werten B11.2–B11.7, `Validate` (Ids eindeutig, Pellets ≥ 1, Felder in BalanceFields-Grenzen, Modelle existieren via `WeaponModels.HasRecipe`).
  - Reine Module Spread/Hitbox/Damage/Ballistics (`--!strict`).
  - `HistoryService`: Ringpuffer 24 × 30 Hz (`{t = GetServerTimeNow(), Root, Head}`) für alle getrackten Combatants (Puppen: statisch).
  - `CombatService`: Registry, Kontexte, HP, Schild, Block-Faktor, Assists (≥ 25 in 8 s), Kill-Gutschrift (≤ 8 s), Recap-Log (≤ 12),
    `Eliminate` → `CharacterService.Pop`, Signale; `Combat("Hurt")` an Opfer; Attribute `Hp`/`Alive`; Admin `AdminGod` = kein Schaden.
  - `CharacterService`: CharacterAdded-Setup (Gruppe `LobbyPlayers`, Accessoires `CanQuery/CanTouch=false, Massless`, `DisplayDistanceType = None`,
    `BreakJointsOnDeath=false`, Namensschild aus Player-Attributen), Router (SetRouter), `Died`-Fallback, Pop/Unpop/Freeze/Teleport,
    3rd-Person-Waffen (4 Modelle, Weld an RightHand/Right Arm, C0 = Grip-Versatz), Krone, `BaseSpeed`.
  - `WeaponService`: Loadout/Munition/Equip/Reload/ADS/Block/Heal/Throw, komplette `Fire`-Validierung C10 mit Reject-Codes,
    Nahkampf, Admin-Kräfte (InfAmmo, NoReload, RapidFire, OneShot, SilentAim) und Admin-Waffen 101–104, `ServerFire` für Bots.
  - `ProjectileService`: C11 (Raketen, Granaten mit Abprall, Rauch, Explosionen, Raketensprung, Impulse an Spieler + AC-Grace).
  - `ReplicationService`: `Look` empfangen (C12.2), `LookBatch` 10 Hz, `FX` 20 Hz pro Kontext, `FireCtx`, `LastInput`, `Flags`, Slide-Zähler.
- **Abnahme:** (1) In der Range: Puppen nehmen exakt den Tabellen-Schaden (Kopf/Körper/Falloff). (2) Gefälschte Pakete (falscher Typ, NaN, zu schnell,
  Ursprung 20 Studs weg, durch Wand, falscher Seed/Spread) werden mit dem richtigen Reject-Code verworfen. (3) Bei 150 ms Netzwerk-Simulator
  treffen bewegte Ziele (Rückspulen). (4) Pop → Vault, Revive → Spawn ohne CharacterAdded, keine Lobby-Flicker. (5) Raketensprung möglich ohne
  Anti-Cheat-Kick. (6) FX-Pakete ≤ 871 B. (7) Accessoires blockieren keine Kopftreffer.
- **Tests:** `CombatTests`: Hitbox-Fälle, Damage-Ränder (Start/Ende/Min), Spread-Determinismus, Ballistics-Reflect, synthetische Validierung
  gegen eine Test-Puppe in einem Test-Kontext (gültig = akzeptiert, je Fehlertyp richtiger Code).

## WP4 – Kampf (Client): Kamera, Viewmodel, Schießen, Bewegung, Waffenmodelle
- **Dateien:** `Shared/WeaponModels.luau`, `Modules/FpsCamera.luau`, `Modules/AimAssist.luau`, `Modules/Viewmodel.luau`, `Modules/WeaponClient.luau`,
  `Modules/Movement.luau`, `Modules/Replication.luau`.
- **Liefert:** C6.3 (WeaponModels), C7.4 (WP4-Teil), B11.8, B12, B14.8-Clientteil, B15.2.
- **Braucht:** `Spread.*` (WP3) · `Config.Weapons/Combat/Player/Client.AimAssist` · Hooks `Armed`, `Disarmed`, `Combat:Hit/Ammo/Equip/Impulse/Heal`,
  `LocalPopped`, `LocalRevived` · `Controls.Bind/IsDown/Input/SetContext` · `TouchControls.Show/SetAutoFire` · `CombatHud.*` · `CombatFX.Tracer/Impact/Muzzle/Projectile` ·
  `Sfx.Play` · `CosmeticModels.ApplyWrap/BuildCharm` (WP9) · `ctx.State.Cosmetics`, `ctx.State.Settings` · Remotes `Fire`, `WeaponAction`, `Look`, `LookBatch`.
- **Aufgaben:**
  - `WeaponModels`: Rezepte für 15 Waffen + 4 Admin-Waffen + 8 Skins (B11.8, B19), `Build`, `HasRecipe`. Orange Spitze immer.
  - `FpsCamera`: Modi (Match/Range = `LockFirstPerson`, Zoom 0.5; Lobby = Classic max 14; Spectate; Menu), FOV-Besitzer (Einstellung, ADS `fov/zoom`),
    Rückstoß als Feder-**Delta** bei `RenderPriority.Camera + 1`, Wackeln/Roll absolut, Pitch ±80°, ADS-Empfindlichkeit über
    `UserInputService.MouseDeltaSensitivity` (Wert wiederherstellen), Zielfernrohr-Overlay (Viewmodel aus), `AddLookDelta` für Touch,
    `MouseIconEnabled=false` bewaffnet, Reset-Knopf im Match aus (`SetCore` mit Wiederholung).
  - `AimAssist`: B15.2 (nie Maus; Sichtlinie; Rauch über `Combat:Smoke`-Kugeln).
  - `Viewmodel`: Teile unter `workspace.CurrentCamera` (alle nicht kollidierend/abfragbar), Arme aus Blöcken in BodyColors, Sway (Feder aus
    Kamera-Rotationsdelta), Bob, Kick, Nachlade-Keyframes (Senken 20 % → Mag raus 20 % → Mag rein 30 % → Repetieren 15 % → Heben 15 %),
    Ausrüsten 0.25 s, Inspizieren 1.2 s, Nahkampf-Schwünge, Block-Pose, Trink-Pose, Wand-Rückzug (2.5-Stud-Ray), Charm-Pendel, Mündungsfeuer,
    Schritt bei `Camera + 2`.
  - `WeaponClient`: Feuer-Schleife (Auto/Semi/Burst), Seed-Vorhersage, Raycast-Params (C10), `Fire`-Pakete, Munitions-/Nachlade-Vorhersage +
    Korrektur, Equip/Quick-Swap, Nahkampf/Wurf/Benutzen/Block, Auto-Feuer (Touch), Admin-Silent-Aim/Triggerbot-Haken (nur wenn `IsAdmin`),
    Kamera-/Controls-/HUD-Umschaltung bei Armed/Disarmed/Pop/Revive.
  - `Movement`: Sprint, Rutschen, Rutsch-Sprung, Doppelsprung (Gloves), `GravityLift` (VectorForce), Impulse, `BaseSpeed × MoveMult`, Staub-Trail lokal.
  - `Replication`: `Look` senden (12 Hz, nur bei Änderung), `LookBatch` anwenden (Neck ×0.5, Waist ×0.15, R15/R6), toolnone auf dem eigenen Character,
    Nachlade-Kippen/Schwung anderer lokal, Rutsch-Staub anderer (Flag), BigHead-Bälle (Attribut `BigHead`).
- **Abnahme:** (1) Rückstoß erholt sich ohne Drift; Pitch nie > 80°. (2) Viewmodel clippt nicht in Wände; 3rd-Person-Waffe in Ego-Sicht unsichtbar.
  (3) Touch: Feuerknopf ziehen = zielen; Auto-Feuer 85 %. Gamepad: Zielhilfe spürbar, Maus nie. (4) Andere sehen Zielneigung (2 Players).
  (5) 60 FPS am PC in der Range mit Dauerfeuer. (6) Vorhergesagte und Server-Munition laufen nicht auseinander (Korrektur ≤ 1 Ping).
- **Tests:** Studio-Solo Range + Practice; 2 Players (Neigung, Waffe in der Hand); Gerätesimulator Telefon (Touch-Layout).

## WP5 – Match, Warteschlangen, Match-UI, Tutorial
- **Dateien:** `Config/Modes.luau`, `Lang/Match.luau`, `Services/QueueService.luau`, `Services/MatchService.luau`, `Modes/Rounds.luau`, `Modes/Respawn.luau`,
  `Modules/QueueUI.luau`, `Modules/MatchUI.luau`, `Modules/Spectate.luau`, `Modules/Scoreboard.luau`, `Modules/Tutorial.luau`, `Tests/MatchTests.luau`.
- **Liefert:** C5.5, B1.1, B3–B7, B14.2–B14.7 (Clientteile Killfeed/Recap/Zuschauen/Ergebnis/Scoreboard).
- **Braucht:** `ArenaService.Acquire/Release/Crown/MapsFor/FreeSlots/Layout` · `LobbyBuilder.Pads/CrownLine/CrownBoard` ·
  `CombatService.NewCombatant/Register/Unregister/RegisterContext/UnregisterContext/Revive/ResetRound/TeamHp/RoundDamage/Recap/OnElimination/OnDamage/InCtx` ·
  `CharacterService.SetRouter/Teleport/Freeze/BuildGunVisuals/ClearGunVisuals/SetHeadProp/SetBaseSpeed` · `WeaponService.SetLoadout/ResetForRound` ·
  `ProjectileService.ClearCtx` · `ReplicationService.FireCtx/LastInput` · `BotService.Spawn/Despawn/SetGoal/DifficultyFor/SetHandicap/OnRoundStart/Budget` ·
  `ShopService.GetLoadout/Finisher` (pcall) · `ProgressionService.Mmr/IsRookie/MatchesPlayed/LevelOf/TitleOf` (pcall) · `CommunityService.BountyOf/Announce` (pcall) ·
  `MonetizationService.TryOffer` (pcall) · `AntiCheatService.Exempt/SetAllowance` (pcall) · `MetricsService.Funnel` (pcall) · `AdminService.IsServerLocked` ·
  Client: `ArenaLook` reagiert auf Hooks, `Shop.BuildStarterCard`, `CombatFX.Pop`, `Highlights.Pulse`, `UI`, `Controls`.
- **Aufgaben:**
  - `QueueService`: Pad-Scan 4 Hz (Sitze, Attribute B3.2 nur bei Änderung), virtuelle Schlangen + Matcher 2 Hz (B3.1), „Bots jetzt“,
    Neulings-Schutz, Eingabegruppen, MMR-Fenster, Slot-/Bot-Budget-Halten, Crown-Linie (B4), FFA-Drop-in, Auto-Requeue, Pad-Sperre 60 s.
  - `MatchService`: Zustandsmaschine B5 (Vote während Lobby-Phase, Load mit `ArenaReady`-Handler und 4-s-Timeout, Intro, Prep mit Bereit-Überspringen,
    Live, Overtime-Zone 5 Hz, RoundEnd, Rundenlimit + Sudden Death, MatchEnd/Rematch), Kontext-Registrierung (Rules aus Modus + Mutator),
    Spawns (A/B nach Team, Respawn-Wertung FFA: `minDist − 40 × (Gegner mit Sicht)`, beste von 8 Kandidaten), Crown-Logik
    (König bleibt, Serie, Krone, Tafel per `rbxthumb://type=AvatarHeadShot&id=<id>&w=150&h=150`, Belohnungs-Flags), Banner-Flags, AFK
    (`LastInput`), Leaver, Taint, Bot-Ersatz, `Route` für den CharacterAdded-Router, Tages-Mutator + Override, `MatchResult` + `OnMatchEnd`.
    Match-Daten nur an `Recipients` (Crown: + Zuschauer ≤ 150 Studs).
  - `Modes/Rounds` + `Modes/Respawn`: reine Regelwerk-Logik (Tiebreaks B6 als reine Funktionen, testbar).
  - Client `QueueUI` (PLAY-Fenster, lokalisierte Pad-Billboards aus Attributen, Hologramm-Bots, „N suchen“, Practice-Prompts),
    `MatchUI` (Vote-Karten, Intro inkl. Gegner-Loadouts, Countdown, Timer/Score-Pips, Zonen-Balken, Banner, Killfeed, Rückblick, Ergebnis mit
    Balken + Starter-Karte nur bei `Offer`, Rematch/GG/Loben, AFK-Warnung, PlayerList-CoreGui im Match aus), `Spectate`, `Scoreboard`,
    `Tutorial` (Willkommenskarten, Hinweise, Pfeil-Tour, Funnel-Schritte über Request/Server).
- **Abnahme:** (1) Volles 1v1-Pad → erster Schuss ≤ 15 s (Stoppuhr, warmer Slot ≤ 12 s). (2) Zwei Menschen auf **verschiedenen** 1v1-Pads werden
  vor Bot-Füllung gepaart. (3) Alle Modi starten und enden in Studio-Solo; Rematch ohne Ladephase. (4) Rundenlimit + Sudden Death beenden jedes Match.
  (5) AFK nach 30 s entfernt, Bot ersetzt in Team-Modi. (6) Crown: König bleibt, Bot-Herausforderer nach 15 s, Zuschauer sehen Tracer/Finisher.
  (7) Nie `FireAllClients` für Match-Daten (Code-Suche).
- **Tests:** `MatchTests` (Tiebreak-Tabelle, Overtime-Fortschritt, Rundenlimit, Matcher-Paarung mit Fake-Einträgen); TESTPLAN Solo + 2 Players.

## WP6 – Bots & Training (Range)
- **Dateien:** `Config/Bots.luau`, `Lang/Bots.luau`, `Services/BotService.luau`, `Services/RangeService.luau`, `Bot/BotRig.luau`, `Bot/BotBrain.luau`,
  `Bot/Pathfind.luau`, `Modules/BotAnimator.luau`, `Modules/Training.luau`.
- **Liefert:** C5.6, B10, Range-Teil von B2.
- **Braucht:** `CombatService.NewCombatant/Register/Unregister/InCtx/Context/RegisterContext` · `WeaponService.SetLoadout/ServerFire/ServerMelee/ServerThrow/ServerUse/Equip` ·
  `HistoryService.Track` · `ProjectileService.IsSmoked` · `CharacterService.SetNameplate/BuildGunVisuals/SetBaseSpeed/Teleport` ·
  `ArenaService.Range/Layout` (Arena.Nav) · `LobbyBuilder.RangeZone/RangeDummySpots/BotBooth` · `ShopService.GetLoadout` (pcall) ·
  `ProgressionService.Mmr/IsRookie` (pcall) · Client: Hooks, `ctx.Windows`, `CombatHud`.
- **Aufgaben:** `BotRig` (Async-Rig + Fallback, Pool 12, Netzwerk-Besitz, Zustände aus), `BotService` (Spawn/Despawn in Kontext, Namen, Loadouts nach Stufe,
  Handicap, adaptive Stufe, Budget), `BotBrain` (B10.3, 10 Hz gestaffelt, Raycast-Budget), `Pathfind` (A* mit Binär-Heap auf `Arena.Nav`),
  `RangeService` (Zone 4 Hz: betreten → Combatant Ctx `Range` mit `IgnoreOwnership`, Team 1, `Combat("Armed")`; verlassen → `Unregister`;
  24 statische Puppen + 2 Schiene-Puppen (unverankert, `SetNetworkOwner(nil)`, `LinearVelocity` ±8 Studs/s, Wechsel alle 2 s), 150 HP, voll nach 3 s;
  Request `RangeWeapon`), Client `BotAnimator` (Standard-IDs lokal auf Tag `Bot`, toolnone), `Training` (Waffen-Regal-Fenster, DPS-Anzeige,
  Flick-Test: 10 lokale Ziele, Bestzeit nur lokal in v1).
- **Abnahme:** (1) Bots spielen jeden Modus, schießen nur über WeaponService, bleiben nie > 3 s hängen. (2) Nie mehr als 12 Bots/7 pro Match.
  (3) Rookie verfehlt die ersten 2 Schüsse pro Runde in den ersten 3 Matches. (4) Stufen fühlbar verschieden (Insane gewinnt meist gegen Easy).
  (5) Range: jede Waffe testbar, Puppen regenerieren, Spieler treffen sich gegenseitig nicht. (6) Bot-Duell-Kabine startet Practice.
- **Tests:** Studio: 4v4-Pad allein (7 Bots), Bot-Pfad-Overlay (Admin-Debug), 10 min Dauerbetrieb ohne Fehler, Bots in Rauch blind.

## WP7 – Sicherheit, Admin, Live-Balance
- **Dateien:** `Config/Security.luau`, `Lang/Admin.luau`, `Services/AntiCheatService.luau`, `Services/AdminService.luau`, `Services/BalanceService.luau`,
  `Modules/AdminPanel.luau`, `Modules/AdminTools.luau`, `Modules/Fly.luau`, `Modules/PhotoMode.luau`, `Modules/DebugOverlay.luau`.
- **Liefert:** C5.7, B25 komplett, C12.3–C12.4, Honeypot-Handler, Request `Report`.
- **Braucht:** `MatchService.List/Info/End/Create/Taint/MatchOf/SetMutatorOverride` · `QueueService.ForceFillPads` · `BotService.Spawn` ·
  `CombatService.OfPlayer/Eliminate/Heal/Get` · `CharacterService.Teleport/Freeze` · `ShopService.Grant` · `ProgressionService.AddXp/LevelOf` ·
  `DataService.Get/Reset/Save` · `MonetizationService.SimulatePurchase/SetPolicyOverride` · `WeaponService.GiveAdminWeapon` · `ArenaService.SlotStates/LobbySpawn` ·
  `Util.SetDayOffset` · `SelfTestService.Run` · `Scheduler.Stats` · `Config.ApplyBalance` · `PlayerStateService.EffectAll/NotifyRaw/Effect` · Client: `ctx.UI`, `Hud.AddRightButton`, `Highlights`.
- **Aufgaben:** `AdminService` (MH-Rahmen: Owner-Check B25.1, Cache, Attribute `IsAdmin`/`CanFly`, Ziel-Auflösung, alle Aktionen B25.3, Ansagen lokal/global
  mit Filter, Admin-Abuse synchron, Banns B25.4, Taint-Überwachung bei Kraft-Nutzung im Match, Server-Lock, Global-Nachrichten mit Feld-Validierung),
  `AntiCheatService` (C12.3/C12.4, Honeypot `GrantCoins`, Statistik-Flags, Kicks, Auto-1-Tages-Bann nur bei harten Signalen, Flags/Reports in Shards C14,
  Request `Report` mit Schnappschuss), `BalanceService` (Laden beim Boot, `CC_Global`-`Balance`, Poll 120 s, `ReplicatedStorage.LiveBalance` StringValue
  (`HttpService:JSONEncode`), Verlauf 10 Versionen, Not-Aus, Statistik-Zähler + Flush 600 s in Shards), Client `AdminPanel` (MH-Gerüst, 9 Tabs),
  `AdminTools` (ESP ≤ 20 Highlights über `Highlights`, sichtbarer Aimbot, Triggerbot, Noclip lokal), `Fly` (MH, Taste G), `PhotoMode` (MH + versteckt
  Viewmodel/Fadenkreuz/Touch-UI), `DebugOverlay` (F8).
- **Abnahme:** (1) Live-Regel/Studio-Regel exakt; Player2 abgelehnt und einmal geloggt. (2) Jede Aktion serverseitig erneut geprüft; Rate-Limit vor Check.
  (3) Kraft im Match → Taint; Gegner verlieren nichts. (4) Ansage mit Avatar + blauem Haken, gefiltert, global über MessagingService (Fehler → lokal).
  (5) Balance speichern → alle Server + Clients übernehmen Version; Revert funktioniert; Not-Aus entfernt Waffe aus Loadouts.
  (6) Speedhack/Teleport → Zurücksetzen + Punkte, keine Banns aus Statistik. (7) BanAsync in Studio ohne Absturz (pcall).
- **Tests:** 2 Players (Admin vs. Nicht-Admin), simulierte Verstöße über Debug-Befehle, Honeypot über Command-Bar feuern.

## WP8 – Fortschritt, Belohnungen, Sozial, Bestenlisten, Analytics
- **Dateien:** `Config/Progression.luau`, `Config/Season.luau`, `Lang/Progress.luau`, `Shared/ProgressMath.luau`, `Services/ProgressionService.luau`,
  `Services/RewardService.luau`, `Services/CommunityService.luau`, `Services/LeaderboardService.luau`, `Services/MetricsService.luau`,
  `Modules/Progress.luau`, `Modules/ChatClient.luau`, `tests/progressmath.test.luau`, `Tests/ProgressionTests.luau`.
- **Liefert:** C5.8, C6.3 (ProgressMath), B16, B21.2 (Pass-Logik), B24 (Chat, GG, Loben, Freunde, Ansagen), Request-Aktionen WP8 (C9).
- **Braucht:** `MatchService.OnMatchEnd` · `CombatService.OnElimination/OnDamage` · `ShopService.Grant` · `MonetizationService.HasPass/PartyXpActive` ·
  `AdminService.EventMult` · `DataService.Get` · `PlayerStateService.Provide/MarkDirty/Notify/Effect/SetLeaderstat/Handle` · `LobbyBuilder.Boards` ·
  `Players:GetUserThumbnailAsync`/`rbxthumb` · Client: `ctx.Windows`, `ctx.State`, `TextChatService`.
- **Aufgaben:** XP/Level/Multiplikatoren/Erster Sieg, Coins pro Match (über `ShopService.Grant`, Bot-Tageslimit), MMR, Meisterschaft + Belohnungen,
  Erfolge, Titel, Pass (Saison-Auswahl mit Fallback, Pass-XP, Stufen, idempotentes Einlösen, rückwirkendes Premium, `GrantPassPremium`, `AddPassTiers`),
  Quests (Anfänger/Täglich/Wöchentlich, `Track`, Reroll), Login-Kalender + Freeze, Glücksrad, Spielzeit-Geschenke, Codes, Kopfgeld, Comeback, Ehre/GG/Loben,
  Freund-Toast, Lobby-Ansagen, Player-Attribute `Level`/`Title`/`Bounty`, leaderstats, Bestenlisten (C14, Tafeln mit `rbxthumb`-Avataren, Namens-Cache 200),
  `MetricsService` (alle AnalyticsService-Aufrufe in pcall), State-Keys `Level, XP, XPNext, Stats, Quests, Login, Daily, Pass, Season, Achievements, Honor, Mastery`.
  Client `Progress` (Fenster Quests/Pass/Täglich mit Rad + Quoten-Details, Level-Up-Karte) und `ChatClient` (Umschreibungen B24, PrefixText aus Attributen).
- **Abnahme:** (1) Ein 1v1-Sieg gegen Menschen ≈ 270 XP / ≈ 159 Coins, Bot-Match ×0.6, Practice 0 Coins. (2) Bot-Coins stoppen bei 2.500/Tag.
  (3) Tainted/Bot-Matches schreiben keine Bestenliste/MMR/Serie. (4) Pass-Einlösen doppelt → zweites Mal abgelehnt. (5) Saison-Fallback ohne passendes Fenster aktiv.
  (6) Chat: „ez“ → „gg wp“, „mein Ping ist schlecht“ bleibt unverändert, eigene Nachrichten unverändert.
- **Tests:** `tests/progressmath.test.luau` (Level-Summen aus B16.1, Elo-Symmetrie, Meisterschafts-Stufen), `ProgressionTests` (Quest-Rotation pro Tag deterministisch,
  Rad-Gewichte = 100, Kalender-Logik mit `SkipDay`).

## WP9 – Wirtschaft, Monetarisierung, Kosmetik, Shop-UI
- **Dateien:** `Config/Cosmetics.luau`, `Config/Shop.luau`, `Lang/Shop.luau`, `Lang/Items.luau`, `Shared/CosmeticModels.luau`, `Shared/Odds.luau`,
  `Services/MonetizationService.luau`, `Services/ShopService.luau`, `Modules/Shop.luau`, `Modules/Locker.luau`, `Modules/CrateReveal.luau`,
  `Modules/Finishers.luau`, `tests/odds.test.luau`, `Tests/EconomyTests.luau`.
- **Liefert:** C5.9, C6.3 (CosmeticModels/Odds), B18–B23, Request-Aktionen WP9 (C9), State-Keys `Coins, Gems, Keys, Shards, Weapons, Loadouts,
  Cosmetics, Crates, Boosts, Passes, RandomAllowed, Featured, Offer`.
- **Braucht:** `DataService.Get/Save/OnProfileLoaded` · `PlayerStateService.*` · `ProgressionService.GrantPassPremium/AddPassTiers/MasteryTier/Season` ·
  `MetricsService.Economy/Funnel` (pcall) · `MatchService.MatchOf` (TryOffer: nicht in Live-Runde) · `CommunityService.Announce` (Kisten-Funde, Filter erlaubt) ·
  `WeaponModels.Build/HasRecipe` (Vorschau, Skins) · Client: `ctx.Windows`, `UI.FetchPrice`, `UI.WhenRandomItemsKnown`, `Hud.AddRightButton`, `Viewmodel` (Vorschau optional).
- **Aufgaben:** `MonetizationService` (MH-Basis: Pässe 3 Versuche, `PromptGamePassPurchaseFinished`, Policy-Cache unbekannt = eingeschränkt, ProcessReceipt B22.3,
  Erstkauf-Bonus, Saison-Idempotenz, Starter-Fenster 72 h, `TryOffer`-Sitzungsgrenze, PartyBoost serverweit + Ansage, XP-Boost-Zeiten, Simulate),
  `ShopService` (Grant/Spend ohne Yield, Waffenkauf, Gratis-Waffen-Wahl einlösen (über Grant), Katalog/Featured (UTC-Tag-Seed), Kisten (Odds, Pity,
  Duplikat → Splitter, Policy-Gate), Splitter-Shop, Ausrüsten mit Validierung (Meisterschafts-Wraps nach Stufe), Loadout-Vorlagen/Plätze, `GetLoadout` mit
  Not-Aus/Mutator, Player-Attribute `Vip`, `Supporter`), `CosmeticModels` (Wraps auf Rollen, Charms, Tracer-Stile, Animator), `Odds`, Client `Shop`
  (Tabs B21.1, „Details & Quoten“ vor jedem Kauf, Starter-Karte, Kisten-Automat lokal verstecken solange nicht erlaubt, VIP-Tür lokal öffnen),
  `Locker` (Loadouts + Kosmetik pro Waffe, Drehteller-Vorschau), `CrateReveal` (ehrliche Rolle 2.5 s, überspringbar), `Finishers` (8 Builder, ≤ 25 Teile, Pool).
- **Abnahme:** (1) Kein Weg, mit Robux Coins/Waffen/Schlüssel zu bekommen (Code-Review aller Grants). (2) Eingeschränkt/unbekannt: keine Gem-Kiste sichtbar,
  Server lehnt ab; Schlüssel-Öffnung geht. (3) Angezeigte Quoten = Server-Tabelle = 100,00 %. (4) Pity greift bei Öffnung 30. (5) Doppelter Receipt
  (gleiche PurchaseId) gewährt einmal. (6) PassPremium zweimal → 500 Gems. (7) Produkte mit Id 0 zeigen „Bald verfügbar“, Simulate gewährt korrekt.
- **Tests:** `tests/odds.test.luau` (Summe, Rundung, Pity-Tabelle), `EconomyTests` (Grant/Spend-Atomik, Receipt-Replay, Policy-Gate, Saison-Fallback-Kauf).

## WP10 – Client-Hülle: UI, Eingabe, HUD, Effekte, Sounds
- **Dateien:** `Config/Client.luau`, `Lang/Ui.luau`, `src/client/Main.client.luau`, `Modules/UI.luau`, `Modules/Hooks.luau`, `Modules/Controls.luau`,
  `Modules/TouchControls.luau`, `Modules/Hud.luau`, `Modules/CombatHud.luau`, `Modules/Settings.luau`, `Modules/Effects.luau`, `Modules/CombatFX.luau`,
  `Modules/Sfx.luau`, `Modules/Highlights.luau`.
- **Liefert:** C7.1–C7.4 (WP10-Teil), B14.1, B14.4, B15.1, B15.3, Sound-Rezepte.
- **Braucht:** `Net.GetRemotes` · `Config.*` · `Lang` · `Finishers.Play` (WP9) · Client-Module der anderen WPs über `ctx.Modules` · Remotes `Notify/State/Effect/Match/Combat/FX` ·
  `ReplicatedStorage.LiveBalance` → `Config.ApplyBalance`.
- **Aufgaben:** `Main.client` (MH-Skelett: ScreenGui `ResetOnSpawn=false`, zweite unskalierte `TouchGui` mit `ScreenInsets = DeviceSafeInsets`, ctx, Request-Wrapper,
  State-Merge, Hooks-Weiterleitung, Modul-Start C7.1, Admin-Module nur bei `IsAdmin`, CoreGui Backpack/Health aus, LiveBalance anwenden),
  `UI` (MH-Kit + `IsAnyWindowOpen` + Modal-Knopf + Windows-Registry), `Controls` (ContextActionService-Belegung B15.1, PreferredInput),
  `TouchControls` (≥ 64 px, Feuer mit Ziehen, ADS, Nachladen, Rutschen, Utility, Slot-Leiste, Linkshänder, Knopfgröße, Auto-Feuer-Standard „auto“),
  `Hud` (Lobby: Coins/Gems/Schlüssel, Level-Balken, PLAY, rechte Knöpfe), `CombatHud` (Fadenkreuz 4 Stile, HP, Munition, Slots, Hitmarker, Schadenszahlen,
  Richtungspfeil, Rand-Blende, Kill-Banner, Gegner-Umrisse über Highlights), `Settings` (Fenster, Speichern über Request, Auto-ReducedFx bei < 35 FPS),
  `Effects` (MH: announce/adminWarn/confetti/levelup/coin fly), `CombatFX` (Pools, Tracer aus `FX`-Buffer, Projektil-Visuals, Explosionen, Rauch, Finisher-Aufruf),
  `Sfx` (Rezepte ASSETS §2.2, Config-IDs, Round-Robin-Pools), `Highlights` (Budget 31).
- **Abnahme:** (1) HUD wechselt live zwischen Maus/Gamepad/Touch. (2) Fenster geben in Ego-Sicht die Maus frei. (3) Touch-Knöpfe ≥ 64 px auf kleinstem Telefon
  im Gerätesimulator, nichts unter Notch. (4) Ein Schuss erzeugt keine neue Instanz (Pools). (5) Nie mehr als 31 Highlights. (6) Kein Fehler, wenn ein
  Fremd-Modul fehlt (pcall-Start).
- **Tests:** Studio-Gerätesimulator (iPhone SE, iPad, Xbox), Dauerfeuer-Test (Instanzzähler stabil), Sprache DE/EN umschalten.

## WP11 – Dokumentation (Deutsch, Anfänger, Mac)
- **Dateien:** `ANLEITUNG.md` (Projekt-Wurzel), `docs/KOPIERVORLAGEN.md`, `docs/TESTPLAN.md`.
- **Braucht:** diese Spec (Preise, Config-Keys, Tasten, Abläufe), REUSE §15 (Struktur), ASSETS.md (Sound-IDs-Hinweis).
- **ANLEITUNG.md** (kurze Sätze, fette Klickpfade, Mac-Tasten ⌘/⌥, Emojis sparsam): 1 Was ist CLUTCH CLASH · 2 Inhalt · 3 So spielt man (Modi, Tasten-Tabelle
  PC/Controller/Handy) · 4 Schritt 1: `ClutchClash.rbxlx` öffnen · 5 Schritt 2: Admin-Panel (automatisch, Taste P; Player2 ist kein Admin) ·
  6 Schritt 3: Testen (Play solo, **Test → 2 Players**, Gerätesimulator, Netzwerk-Simulator) · 7 Schritt 4: Veröffentlichen (Speichern-Fehler → Baseplate
  „Overwrite“-Fix, **Game Settings → Security: Studio-Zugriff auf API-Dienste an**, **Avatar: R15 + Skalierung Standard**, **Places → Max Players 18**,
  Genre Shooter) · 8 Schritt 5: Robux (Pässe/Produkte aus KOPIERVORLAGEN anlegen, IDs an Claude schicken – Vorlage) · 9 Schritt 6: Maturity-Fragebogen
  (Antworten C19) · 10 Spieler finden (Spielseiten-Titel, Thumbnails, Codes) · 11 Admin-Panel-Tour (alle 9 Tabs) · 12 Balancing in Config und live ·
  13 Neue Saison anlegen (Block kopieren, Datum, Belohnungs-Ids, Play → SelfTest-Meldungen lesen) · 14 Eigene Sounds (Creator-Store-Audio von „Roblox“,
  ID in `Config.Client.Sounds`) · 15 Updates (neue .rbxlx, einzelne Skripte, Rojo) · 16 Fehlerhilfe-Tabelle · 17 Technik in einfachen Worten · 18 Dateibaum.
- **KOPIERVORLAGEN.md:** Zweck, so kopierst du, Mini-Glossar, Spielname + Untertitel, Beschreibung DE+EN (mit Fair-Play-Versprechen), Genre, Bild-Ideen;
  je GamePass/Produkt aus B22 ein Kopierblock: **Name (EN, max. 50 Zeichen), Beschreibung (EN + DE), Preis in R$, Icon-Idee, Config-Key**; Fragebogen-Hilfe;
  Spickzettel-Tabelle; Rückgabe-Vorlage mit `Key = <Id>`-Zeilen in der Reihenfolge von `Config.Shop`.
- **TESTPLAN.md:** Checkliste Studio-Solo und 2 Players: Tutorial, jedes Pad, PLAY-Einträge, Crown, FFA, Practice, Range, Overtime, Sudden Death, AFK, Leaver,
  Tod ohne Schadensquelle (Command-Bar `Humanoid.Health = 0` beim eigenen Character), Waffenkauf, Kiste mit Schlüssel, Policy eingeschränkt,
  Kauf simulieren, Receipt-Replay, Bann-Dialog an Player2, Sprache DE/EN, Netzwerk-Simulator, F8-Overlay, SelfTest-Ausgabe.
- **Abnahme:** Jeder Schritt mit Studio-Klickpfad; alle Preise/Keys stimmen mit B22/`Config.Shop` überein; keine Fachbegriffe ohne Erklärung.

---

# E) Umfang: v1 vs. spätere Updates

### v1.0 (dieses Bau-Runde, fehlerfrei)
- **Lobby** Clutch Plaza: 9 Pads (6 Typen), Crown Ring mit Tribünen und Zuschauer-FX, Range (24+2 Puppen, Bot-Duell-Kabine, Waffen-Regal, Flick-Test lokal),
  Shop-Straße mit Kiosken, 6 Bestenlisten, VIP-Balkon.
- **Modi:** Duell 1v1/2v2/3v3/4v4, Mutator des Tages (8 Mutatoren), Crown (Winner stays), FFA-Brawl, Practice gegen Bots (5 Stufen), Tutorial-Duell.
- **Welt:** 6 Maps + Crown Ring, 5 Stimmungen, 8 Arena-Slots mit Warm-Wiederverwendung und Welt-Ausblendung.
- **Kampf:** 15 Waffen + 4 Admin-Waffen, prozedurales Viewmodel, 3rd-Person-Waffen + Zielneigung, Rutschen/Rutsch-Sprung/Doppelsprung/Raketensprung,
  Server-validierte Treffer mit Server-Seed und Rückspulen, Projektile, Pop-to-Vault, Rückblick, Zuschauen, Overtime, Sudden Death, Anti-Camp, Banner, Juice.
- **Fortschritt:** Level 1–100, Meisterschaft 10 Stufen, Anfänger-Kette, Tages-/Wochenquests, Login-Kalender + Freeze, Glücksrad, Spielzeit, erster Sieg,
  12 Erfolge, Titel, verdecktes MMR, Kopfgeld, Comeback, Ehre/GG.
- **Wirtschaft:** Coins/Gems/Schlüssel/Splitter, Katalog, Featured, Blaster-Kiste S1 (Quoten, Pity, Policy), Splitter-Shop, Clutch Pass S1 (30 Stufen),
  4 GamePasses, 16 Produkte, Codes (statisch).
- **Plattform:** Admin-Panel (9 Tabs inkl. Live-Balance, Statistik, Moderation, Debug), Anti-Cheat, DataStore mit Session-Lock, Bestenlisten, Analytics-Funnel,
  DE/EN, PC/Handy/Controller, Anleitung + Kopiervorlagen + Testplan.

### v1.0.x (sobald SelfTest + Testplan grün)
Touch-Layout-Editor (Drag & Drop) · erweiterter Fadenkreuz-Editor · Gun Ladder (Arsenal-Stil, 12 Stufen, Nahkampf degradiert) · weitere 18 Erfolge (gesamt 30) ·
4 weitere Skins · Wochen-Top-100-Titel · Flick-Bestzeit speichern + Bestenliste · Lobby-Musik-Auswahl.

### v1.1 (+2–4 Wochen)
Ranked 1v1/2v2 (B17, „Mehr Gegner finden“-Teleport) · Parties (4) + Duell-Herausforderung aus der Spielerliste · Hot Zone (3v3 King of the Hill, wandernde Zone) ·
5 neue Waffen: Bubble Bow (aufgeladen), Spitfire (Maschinenpistole), Swift Knife (Rückenstich ×2), Bounce Pad, Flash Pop (mit „Reduzierter Blitz“) ·
2 Maps (Toy Factory, Pool Party) · Mutatoren Rocket Party, Vampir · Gold-Kollektion (Coin-Senke) · Clutch Pass Saison 2 (50 Stufen) · Ruhmeshalle-Statuen (Top 3) ·
Kiste S2 · Stat Tracker-Pass · Live-Codes aus dem Admin-Panel.

### v1.2
Täglicher prozeduraler „Map des Tages“-Generator (symmetrisch, Seed = UTC-Tag) · Gratis-Custom-Räume mit 4-Zeichen-Code · Stündliche 8er-Turniere im Server (Bots füllen) ·
Prestige ab Level 100 + Prestige-Shop · Tag-Team-Relay · TDM · Juggernaut · Draufsicht-Todeskarte (Killcam-lite v0) · Glory-Ranked-Shop · Killstreaks nur in Arcade-Modi.

### v2
Cross-Server-Matchmaking (MemoryStoreService + `TeleportService:ReserveServer`) für Ranked/Parties/Raum-Codes · 3-s-Killcam aus History · Lobby-TV (ViewportFrame) ·
Clans mit Tag im Killfeed und Clan-Bestenliste · saisonale Live-Events mit Event-Währung · 3rd-Person-Kamera für Casual (mit Ursprungs-Prüfung vom Kopf).

### Nie
Waffen oder Coins für Robux · Schlüssel für Robux · Handel · realistische Waffen, Blut, Ragdoll-Leichen · Admin für irgendwen außer dem Besitzer ·
bezahlte Glücksrad-Drehs · Kisten-Packs · Serien-Wiederherstellung gegen Robux · Belohnungen für Likes/Favoriten/Einladungen.

---

# Anhang Z – Abdeckung der Jury-„Must-Fix“-Punkte
| Must-Fix | Wo gelöst |
|---|---|
| Kein Client-Seed (Seed-Grinding) | Muss-Regel 7, B11.1, C10 Schritt 7, `Spread.Seed(salt, shotId)`; Statistik-Flags bleiben (C12.4), „unmöglich“ wird nicht behauptet |
| Kein Humanoid-Tod / kein LoadCharacter im Match | Muss-Regel 5, B13.3 (Pop to Vault + Router + Fallback), Vault über −500 |
| Erster Schuss ≤ 15 s, ehrliche Werbung | B5 (Vote während Lobby-Phase, kein separates Loadout-Timer, Bereit überspringt, Vote entfällt bei Crown/Practice/Tutorial/Rematch); A5 #1 |
| Queues bündeln (18-Spieler-Server) | B3: ein Pool pro Modus, Pads = Eingänge, 6 Pad-Typen, „N suchen“, Bots erst nach dem Menschen-Fenster |
| Robux nie Coins/Waffen schneller | Muss-Regel 4, B18.1, B22 (VIP/DoubleXP/Boosts/PartyBoost nur XP), A5 #3 |
| Max. 4 Währungen | B18.1 (Coins, Gems, Schlüssel, Splitter); Gratis-Waffen-Wahl als Belohnung; keine Coin-Boxen |
| Rundenlimit + Sudden Death | B6 Punkt 4, `RoundCap` in Config.Modes |
| Client-Teilebudget, keine Fog-Annahme | B9.4 (Welt-Ausblendung lokal), B9.5, Aufräumen B9.2, Map-Budgets S/M/L |
| Bot-Farming stoppen | B10.3 (×0.6, 2.500/Tag, Practice 0), Crown-Coins voll nur gegen Menschen (B4), AFK 30 s (B5), keine Bestenliste/MMR/Serie |
| StreakRestore weg, Kisten-Werbung nur für Erlaubte, keine Packs | B22.2 („Nie verkauft“), B20.2, B20.1 (nur Einzel-Öffnung) |
| Chat-Umschreibungen nur ganze Wörter, nur andere | B24, Config.Progression.Chat |
| BigHeads ohne echtes Resize, kein ApplyDescriptionAsync | B7, B13.2 |
| Ranked nicht serverlokal-tot | B17 (v1.1 mit „Mehr Gegner finden“), v1 ohne Ranked |
| Admin-Regel exakt (Studio CreatorId 0, Player2) | B25.1 |
| Pass-Produkt idempotent, Stufen gedeckelt | B22.2 (Fallbacks, Reststufen → 40 Gems), B21.2 |
| Highlight-Budget ≤ 31 | B14.4, `Highlights`-Modul, Config.Client.HighlightCap |
| Mobile-first: Auto-Feuer Standard, ≥ 64 px, Safe Insets, Editor später | B15.1, B15.2, E (v1.0.x) |
| Umfang in Stufen | E (v1.0 / v1.0.x / v1.1 / v1.2 / v2) |
| Hitbox = was andere sehen (keine Stance-Verkleinerung) | Muss-Regel 6, B12 (kein Ducken, Rutschen ohne Hitbox-Änderung), B13.2, Neigungs-Faktoren |
| DataStore-Schreiblimits (Sharding) | C14 (Stats/Flags/Reports gesharded, Budget-Rechnung) |
| Fremde Arenen unsichtbar | B9.4 |
| Kein Ice | Muss-Regel 11, SnowFort-Teich SmoothPlastic |
| Zentrale Anti-Cheat-Gnade-API | C5.7 (`NoteTeleport`, `Grace`, `SetAllowance`, `Exempt`), C12.3 |
| AFK überall + Bot-Coin-Limit | B5, B10.3 |
| Kisten nur bei bekannter Erlaubnis | B20.2 (unbekannt = eingeschränkt, Server lehnt ab) |
| Pads = Sicht auf gemeinsame Schlangen, Budget-Meldungen, Crown reserviert | B3.1, B4, B9.1 |
| Saison-Fallback, idempotente Claims, keine Id-Wiederverwendung | B21.2 |
| Remote-Hygiene-Reihenfolge, kein FireAllClients, Buffer ≤ 900 B, Honeypot | Muss-Regel 8, C8, C12.2 |
| Studio: NoSave-Toast, Bald-verfügbar, Simulate, BanAsync in pcall | C13, B21.1, B25.3 Debug, B25.4 |
| Bots: Async-Rig + Fallback, Netzwerk-Besitz, Standard-Animationen, nur ServerFire, Nav geprüft | B10.2, B10.3, B8.1 (NavBuilder + Boot-Warnung) |
| 3rd-Person-Waffe als Nicht-Tool + toolnone, Viewmodel nicht abfragbar, gepoolte FX | Muss-Regel 2/11, B14.8, C17 |
