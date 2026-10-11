# CLUTCH CLASH: Testplan für Roblox Studio

Mit dieser Liste prüfst du, ob alles funktioniert, bevor das Spiel öffentlich wird.
Du gehst sie von oben nach unten durch und setzt bei jedem Punkt einen Haken.

- **Teil A** testest du **allein** (Play).
- **Teil B** testest du mit **2 Spielern** (Test → 2 Players).
- **Teil C** sind Spezial-Tests (Handy, Lag, Selbsttest).

Bei jedem Punkt steht: **was du tust** → **was passieren muss**.
Klappt etwas nicht: im **Output** den roten Text kopieren (**Cmd + C**) und mit der Nummer des Punkts an Claude schicken (z. B. „A7 klappt nicht“).

Dauer: Teil A ca. 45 Minuten, Teil B ca. 30 Minuten, Teil C ca. 15 Minuten.

### Wörter in diesem Testplan

| Wort | Was es heißt |
|---|---|
| **Play / Stop** | Test im Studio starten / beenden |
| **Output** | Studio-Fenster mit Meldungen. Rot = Fehler, Orange = Warnung |
| **Command Bar** | Eingabezeile für Befehle, unten in Studio (**View → Command Bar**) |
| **Pad** | Leuchtende Platte in der Duell-Halle. Draufstellen = für diesen Modus anstellen |
| **[BOT]** | Computer-Gegner |
| **Pop / gepoppt** | Ausgeschaltet. Die Figur zerplatzt in Konfetti |
| **HUD** | Alle Anzeigen auf dem Bildschirm: Leben, Munition, Knöpfe |
| **Killfeed** | Liste oben rechts: wer wen gepoppt hat |
| **K/D/A** | Pops / eigene Tode / Mithilfen (Schaden am Gegner, den dann ein anderer poppt) |
| **AFK** | „Away from keyboard“: Der Spieler macht nichts mehr |
| **Policy** | Roblox sagt dem Spiel, ob im Land des Spielers bezahlte Kisten erlaubt sind |
| **Kauf simulieren** | Admin-Knopf: gibt ein Produkt genau wie ein echter Kauf, kostet aber nichts |
| **Receipt-Replay** | Roblox meldet denselben Kauf zweimal. Er darf trotzdem nur einmal zählen |
| **TAINTED** | Match, in dem du Admin-Kräfte benutzt hast. Es zählt für niemanden |
| **Studs** | Längen-Einheit in Roblox (eine Figur ist ca. 5 Studs groß) |
| **Latenz / Jitter / Paketverlust** | Verzögerung / Schwankung der Verzögerung / verlorene Daten im Internet |
| **Notch** | Aussparung oben am Handy-Bildschirm (für die Kamera) |

Mehr Wörter: **`ANLEITUNG.md`, Kapitel 19** (Wörterliste A–Z).

---

## Vorbereitung

- [ ] `ClutchClash.rbxlx` in Studio geöffnet (**File → Open from File…**, **Cmd + O**).
- [ ] **View → Output** ist offen (Meldungen und Fehler).
- [ ] **View → Command Bar** ist offen (eine Zeile zum Eintippen von Befehlen, unten im Fenster).
- [ ] Du weißt, wie man startet und stoppt: **Play** (**fn + F5**) und **Stop** (**fn + Shift + F5**).
  Ist die Maus im Match gefangen: **M** drücken (Menü), dann ist sie frei.

> 💡 Im Studio wird **nie gespeichert**. Nach jedem Stop fängst du mit einem neuen Spielstand an (0 Coins, Tutorial kommt wieder).
> Für Tests mit Geld: Admin-Panel (**P**) → Reiter **Spieler** → Ziel `me` → **Geben** (z. B. 20.000 Coins, 2.000 Gems, 5 Schlüssel).

---

## Teil A – Allein testen (Play)

### Start

- [ ] **A1 Start ohne Fehler:** **Play** → im Output keine **roten** Zeilen. Kurz nach dem Start kommt die Meldung „**Studio: Fortschritt wird nicht gespeichert**“.
- [ ] **A2 Selbsttest:** Im Output steht nach ein paar Sekunden `[SelfTest] n/n PASS` (beide Zahlen gleich). Kein `FAIL`.
- [ ] **A3 Lobby:** Brunnen in der Mitte, Duell-Halle mit 9 Pads (Norden), Crown Ring (Osten), Training (Westen), Shop-Straße (Süden), 6 Bestenlisten-Tafeln (Süden).
- [ ] **A4 Admin-Knopf:** Rechts ist der Knopf **Admin**. Taste **P** öffnet das Admin-Panel mit 9 Reitern.

### Tutorial

- [ ] **A5 Begrüßung:** 3 Karten („Duelle!“, „Alles erspielbar“, „Fair: kein Pay-to-Win“), Knöpfe **Erstes Duell!** und **Überspringen**.
- [ ] **A6 Tutorial-Duell:** **Erstes Duell!** → Arena PillarBox, Gegner ist ein **[BOT]** (Rookie). Hinweis-Karten erscheinen (Bewegen, Schießen, Nachladen, Rutschen).
      Der Bot verfehlt seine ersten 2 Schüsse jeder Runde. Erster auf 3.
- [ ] **A7 Erster Pop:** Banner „**POPPED!**“ und Konfetti, wenn du den Bot besiegst.
- [ ] **A8 Ergebnis:** Nach dem Sieg +250 XP (Level 2) und +300 Coins. Danach Pfeil-Tour: Locker → Shop → Pads.

### Pads (Duell-Halle)

Für jedes Pad: auf einen leuchtenden Kreis stellen → nach **2 Sekunden** kommen Bots → „**MATCH GEFUNDEN!**“ → Kartenwahl (5 s) → Match.

- [ ] **A9 Pad P1 (1v1, grün)** → du gegen 1 Bot.
- [ ] **A10 Pad P2 (1v1)** → wie P1.
- [ ] **A11 Pad P3 (1v1)** → wie P1.
- [ ] **A12 Pad P4 (2v2, blau)** → du + 1 Bot gegen 2 Bots.
- [ ] **A13 Pad P5 (2v2)** → wie P4.
- [ ] **A14 Pad P6 (3v3, lila)** → du + 2 Bots gegen 3 Bots.
- [ ] **A15 Pad P7 (4v4, rot)** → du + 3 Bots gegen 4 Bots (7 Bots im Match). Läuft flüssig.
- [ ] **A16 Pad P8 (Mutator, gelb)** → 1v1 mit dem Mutator des Tages (Name steht im Intro). Erster auf 3.
- [ ] **A17 Pad P9 (FFA, rosa Kreis)** → alle gegen alle, Bots füllen auf 6. Wiederbelebung nach 3 s. Ende bei 25 Punkten oder nach 5 Minuten.
- [ ] **A18 Pad verlassen:** Vom Kreis runtergehen (länger als 1,5 s) → du bist nicht mehr in der Warteschlange.
- [ ] **A19 Bots jetzt:** Auf ein Pad stellen → nach 3 s ist der Knopf **Bots jetzt** da und startet sofort.
- [ ] **A20 Anzeigen am Pad:** Über dem Pad stehen Modus, „N suchen“ und „BOT KOMMT IN …“. Wartende Bot-Plätze sind halbdurchsichtige Hologramm-Puppen.

### Match-Ablauf (in einem 1v1)

- [ ] **A21 Kartenwahl:** 3 Arenen mit Licht-Stimmung + „Zufall“. Deine Stimme zählt.
- [ ] **A22 Intro:** „BLAZE vs FROST“, Namen, Level, Waffen des Gegners (4 Bilder).
- [ ] **A23 Countdown:** „3-2-1-POP!“. Vorher kannst du dich umsehen und mit **L** das Loadout ändern. **Enter** = Bereit.
- [ ] **A24 Kampf:** Schießen, Zielen (Rechtsklick), Nachladen (**R**), Waffen **1–4**, **Q**, Granate (**E**), Sprinten (**Shift**), Rutschen (**C**), Springen.
      Treffer zeigen ein weißes X und eine Zahl, Kopftreffer ein gelbes X mit „HEADSHOT!“.
- [ ] **A25 Pop:** Wer besiegt ist, zerplatzt in Konfetti. Killfeed oben rechts.
- [ ] **A26 Todes-Rückblick:** Wirst du gepoppt: links Name des Gegners, Waffe, „**REST-LEBEN: …**“, Liste deiner erhaltenen Treffer, „Du hast … Schaden in … Treffern gemacht“. Knopf **Melden**.
- [ ] **A27 Punktetafel:** **Tab** zeigt beide Teams mit K/D/A, Schaden, Ping, [BOT].
- [ ] **A28 Ergebnis:** Nach dem Match Balken für XP, Coins, Meisterschaft, Pass, Quests. Knöpfe **GG**, **Loben**, **REMATCH**, **NOCHMAL SPIELEN**, **Lobby**.
- [ ] **A29 Rematch:** **REMATCH** → gleiche Arena, gleiche Teams, sofort Countdown (keine Kartenwahl, kein Laden).
- [ ] **A30 Zurück in die Lobby:** Nach dem Ergebnis bist du wieder in der Lobby. Keine Arena mehr zu sehen.

### Verlängerung, Sudden Death, Anti-Camp

- [ ] **A31 Verlängerung:** In einer Runde nicht schießen und dich verstecken, bis die Zeit um ist (1v1: 60 s).
      → „**VERLÄNGERUNG – HALTE DIE ZONE!**“, leuchtende Zone erscheint. Stell dich 3 Sekunden allein hinein → Runde gewonnen.
- [ ] **A32 Anti-Camp-Radar:** 30 Sekunden kein Schaden in einer 1v1-Runde → der Gegner leuchtet kurz durch Wände auf (alle 10 s wieder).
- [ ] **A33 Sudden Death** (dauert lange, darum mit kurzer Rundenzeit):
  1. **Vor dem Play:** im Explorer **ReplicatedStorage → Shared → Config → Modes** öffnen. Bei `Duel1` vorübergehend `RoundTime = 10` und `Overtime = 5` eintragen.
  2. Am besten mit **2 Spielern** (Teil B): beide auf dasselbe 1v1-Pad, **niemand schießt**, niemand geht in die Zone.
     Lauft dabei aber herum und schaut euch um, sonst greift die AFK-Regel (A46). Jede Runde endet unentschieden. Nach 9 Runden (Rundenlimit) kommt „**SUDDEN DEATH**“: alle haben 50 Leben, die Zone ist sofort offen.
  3. → Danach endet das Match sicher (Sieg oder Unentschieden).
  4. **Wichtig:** Danach `RoundTime = 60` und `Overtime = 15` zurückstellen (oder die Datei ohne Speichern schließen). **So nie veröffentlichen!**

### Weitere Modi

- [ ] **A34 PLAY-Menü:** Unten Mitte **PLAY** → Einträge Duell 1v1 / 2v2 / 3v3 / 4v4, Mutator des Tages, FFA-Brawl, Krone herausfordern, Training, Gegen Bots üben.
      Jeder Eintrag zeigt „N suchen“. Jeden Eintrag einmal starten (das Match kurz anspielen, dann mit **M** → Match verlassen oder zu Ende spielen).
- [ ] **A35 Crown Ring:** Auf einen Kreis der Herausforderer-Linie (Westseite des Rings) stellen → ohne zweiten Menschen kämpft nach 8 s ein Bot.
      Gewinnst du: **Krone** auf dem Kopf, dein Name auf der Königs-Tafel. Nach 15 s ohne Herausforderer kommt ein Bot-Herausforderer.
      Verlierer landet am Rand der Grube.
- [ ] **A36 Practice (Bot-Kabine):** Im Training die 4 kleinen Pads (Leicht / Normal / Schwer / Wahnsinn) → Match 1v1 gegen einen Bot dieser Stufe.
      Wahnsinn trifft deutlich besser als Leicht.
- [ ] **A37 Practice (PLAY):** PLAY → Gegen Bots üben → Stufe wählen → Match startet ohne Kartenwahl.

### Training (Range)

- [ ] **A38 Training betreten:** In den Westen laufen → du bekommst deine Waffen. In der Lobby sonst keine Waffen.
- [ ] **A39 Puppen:** Auf Puppen in 15, 30, 60 und 100 Studs Entfernung schießen. Schadenszahlen erscheinen. Puppen haben 150 Leben und sind nach 3 s wieder voll.
- [ ] **A40 Schiene-Puppen:** Die 2 fahrenden Puppen (Bahn 3 und 4) lassen sich treffen.
- [ ] **A41 Waffen-Regal:** Am Regal öffnet sich das Training-Fenster. **Jede der 15 Waffen** gratis ausprobieren, auch gesperrte.
- [ ] **A42 Flick-Test:** Im Training-Fenster (öffnet sich am Waffen-Regal) **Flick-Test** starten → 10 Ziele tauchen nacheinander auf, am Ende steht deine Zeit.
      Nochmal spielen → die Bestzeit wird angezeigt (sie wird in v1 nicht gespeichert, nach dem Verlassen ist sie weg).
- [ ] **A43 Bewegungs-Tricks:** Im Training: **Rutsch-Sprung** (**Shift** halten → **C** → im Rutschen **Leertaste**) ist schneller als normales Laufen.
      Mit den **Boxhandschuhen** in der Hand (Taste **3**): in der Luft nochmal **Leertaste** = Doppelsprung. Mit der **Plopp-Rakete** (am Regal holen)
      direkt unter die Füße schießen = Raketensprung (kann etwas Leben kosten). → Kein Kick, keine Warnung vom Anti-Cheat.
- [ ] **A44 Warten im Training:** Über PLAY in eine Warteschlange gehen und dabei weiterschießen. Match startet trotzdem.
- [ ] **A45 Training verlassen:** Raus aus der Zone → Waffen weg, Kamera wieder hinter der Figur (3rd Person).

### AFK und Verlassen

- [ ] **A46 AFK:** In einer Live-Runde nichts drücken und nicht bewegen. Nach 20 s Warnung, nach 30 s zurück in die Lobby.
- [ ] **A47 Match verlassen:** Im Match **M** → Match verlassen → du bist in der Lobby. Danach kannst du 60 s lang kein Pad benutzen (Pad-Sperre).

### Tod ohne Schadensquelle (Notfall-Weg)

- [ ] **A48 Selbst „sterben“ im Match:** In einer Live-Runde in die **Command Bar** tippen und **Enter**:

```lua
game.Players.LocalPlayer.Character.Humanoid.Health = 0
```

  (Falls `LocalPlayer` einen Fehler gibt: oben bei **Test** auf **Current: Client** umschalten, oder im Server-Fenster
  `game.Players:GetPlayers()[1].Character.Humanoid.Health = 0` benutzen.)
  → Zählt als Pop. Nach ca. 3 s bekommst du eine neue Figur: läuft die Runde noch, schaust du zu; in der nächsten Runde bist du am Spawn.
  Ohne Match landest du in der Lobby. **Keine roten Fehler** im Output.

### Shop, Kiste, Käufe

- [ ] **A49 Waffe kaufen:** Admin → Spieler → `me` → 5.000 Coins geben. Shop (Bude oder Knopf) → Reiter **Waffen** → **Summ-MP** (600) kaufen.
      → Coins −600, Waffe gehört dir, im Locker ins Loadout setzbar. Im Kopf des Shops steht „**ALLE WAFFEN ERSPIELBAR – KEIN PAY-TO-WIN**“.
- [ ] **A50 Gratis testen:** Bei einer gesperrten Waffe **Gratis testen** → Teleport ins Training mit dieser Waffe.
- [ ] **A51 Kiste mit Schlüssel:** Admin → 3 Schlüssel geben → Shop → **Kisten** → mit **Schlüssel** öffnen → Rolle läuft, Item erscheint.
      Zähler „noch … bis zur Garantie“ sinkt. Ein doppeltes Item gibt Splitter.
- [ ] **A52 Quoten:** Knopf **Details & Quoten** zeigt alle 24 Items mit Prozent, zusammen **100,00 %**.
- [ ] **A53 Policy eingeschränkt:** Admin → **Debug** → **Policy simulieren: eingeschränkt** →
      Gem-Öffnen der Kiste ist weg, der **Kisten-Automat** in der Lobby ist unsichtbar. Öffnen mit Schlüssel geht weiter.
- [ ] **A54 Policy erlaubt:** **Policy simulieren: erlaubt** → Gem-Öffnen und Kisten-Automat sind wieder da.
      (Hinweis: Im Studio ist ohne Simulation oft „eingeschränkt“ aktiv. Das ist richtig so.)
- [ ] **A55 Bald verfügbar:** Shop → **Gems & Pässe** → solange keine IDs eingetragen sind, steht bei jedem Produkt „**Bald verfügbar**“.
- [ ] **A56 Kauf simulieren:** Admin → **Debug** → **Kauf simulieren** →
  - `Gems120` → +240 Gems (erster Kauf doppelt). Nochmal → +120 Gems.
  - `StarterPack` → +250 Gems + Wrap „Neuling-Regenbogen“ + Charm + Titel „Frischling“. Nochmal → nur +120 Gems.
  - `PassPremium` → Premium-Spur im Pass-Fenster offen. Nochmal → +500 Gems.
  - `PassTier10` → 10 Pass-Stufen mehr.
  - `PartyBoost` → Ansage „… hat den Server geboostet!“, doppelte XP für alle.
- [ ] **A57 Receipt-Replay** (gleicher Kauf zweimal gemeldet): wird automatisch im Selbsttest geprüft (A2, Wirtschafts-Tests).
      Wenn deine IDs eingetragen sind: Einen Testkauf im Studio machen (kostet im Studio keine Robux) → die Gutschrift kommt **genau einmal**.

### Fortschritt und Fenster

- [ ] **A58 Quests:** Knopf/Bude **Quests** → Anfänger-Kette, 3 Tagesquests, 5 Wochenquests. **Tauschen** geht einmal gratis.
- [ ] **A59 Täglich:** Login-Kalender (Tag 1 abholen), **Glücksrad** drehen (Quoten unter „Details“ = 100 %), Spielzeit-Geschenke.
- [ ] **A60 Tag überspringen:** Admin → Debug → **Tag überspringen** → Kalender rückt einen Tag weiter, neue Tagesquests, neuer Glücksrad-Dreh.
- [ ] **A61 Pass:** Fenster **Pass** zeigt Saison 1 „Neon-Start“, 30 Stufen, Gratis- und Premium-Spur. Stufen abholen geht nur einmal.
- [ ] **A62 Locker:** Loadout ändern, Wrap/Charm an eine Waffe, Finisher und Tracer wählen. Vorschau dreht sich.
- [ ] **A63 Code:** Fenster **Täglich** (Bude oder Knopf) → Feld **Code** → `LAUNCH` einlösen → +250 Coins. Nochmal → abgelehnt.
- [ ] **A64 Einstellungen:** Knopf **Einstellungen** rechts in der Knopf-Leiste (oder **M** → Einstellungen) → FOV (Blickwinkel), Empfindlichkeit, Fadenkreuz-Stil und -Farbe ändern → wirkt sofort.

### Sprache

- [ ] **A65 Englisch:** Einstellungen → Sprache → **EN** → Knöpfe, Fenster und Banner sind englisch („MATCH FOUND!“).
- [ ] **A66 Deutsch:** Sprache → **DE** (oder **Auto**) → wieder deutsch („MATCH GEFUNDEN!“).

### Admin-Panel allein

- [ ] **A67 Kräfte:** Reiter **Kräfte** → **Fliegen** (Taste **G**), **Tempo**, **Super-Sprung**, **Noclip**, **God Mode**, **Unsichtbar** an und wieder aus.
- [ ] **A68 Kampf-Kräfte im Training:** **Aimbot**, **ESP**, **Unendlich Munition**, **Kein Nachladen**, **Rapid Fire**, **One-Shot** im Training testen.
- [ ] **A69 TAINTED:** Eine Kraft **im Match** benutzen → rotes Schild „**TAINTED / Admin-Show**“ in deinem HUD.
- [ ] **A70 Admin-Waffen:** Reiter **Waffen & Items** → **Orbital-Laser**, **Raketen-Minigun**, **Schwarzes-Loch-Kanone**, **Blitz-Gewehr** im Training ausprobieren.
- [ ] **A71 Ansage:** Reiter **Events** → Ansage „Test“ (nur dieser Server) → oben erscheint der Text mit deinem Avatar und blauem Haken, 8 Sekunden.
- [ ] **A72 Admin-Abuse:** Reiter **Events** → Admin-Abuse 2 Minuten, 2x Coins + 2x XP → Banner mit Restzeit. Nach 2 Minuten vorbei.
- [ ] **A73 Spaß-Events:** **Konfetti**, **Lobby-Schwerkraft** 50 (Mond), danach 196,2. **Lobby-Licht** ändern.
- [ ] **A74 Match starten:** Reiter **Match & Server** → **Match starten** (z. B. Duel2 auf SnowFort mit 3 Bots Stufe Hard) → Match beginnt.
- [ ] **A75 Pads füllen / Bot spawnen:** **Pads füllen** füllt wartende Pads mit Bots. **Bot spawnen** im Training stellt einen Bot neben dich.
- [ ] **A76 Server-Info:** Spieler, Bots, Arenen, Projektile, Server-Last (ms), Speicher, Laufzeit, Version.
- [ ] **A77 Live-Balance:** Reiter **Balance** → `PopRifle` → `Damage` = 30 → im Training macht das Pop-Gewehr 30 statt 15 pro Körpertreffer (auf die Puppen in 15 oder 30 Studs).
      **Waffe zurücksetzen** → wieder 15. **Not-Aus** für eine Waffe → sie ist aus dem Loadout verschwunden. Wieder anschalten.
- [ ] **A78 Statistik:** Reiter **Statistik** öffnet ohne Fehler (im Studio sind die Zahlen oft leer).
- [ ] **A79 F8-Anzeige:** **fn + F8** → Debug-Anzeige mit Server-Last, Zustand der 8 Arenen, Bots, letzter abgelehnter Schuss. Nochmal **fn + F8** = aus.
- [ ] **A80 Debug-Anzeigen:** Reiter **Debug** → **Hitboxen zeigen** (Kugel am Kopf, Kasten am Körper), **Bot-Wege zeigen**.
- [ ] **A81 Dauerbetrieb:** Das Spiel 10 Minuten laufen lassen (z. B. 4v4-Pad allein, mehrere Matches hintereinander). **Keine roten Fehler** im Output.

---

## Teil B – Mit 2 Spielern testen

**Starten:** Reiter **Test** → Bereich **Clients and Servers** → **2 Players** → **Start**.
(Neue Studio-Oberfläche: kleiner Pfeil neben **Play** → **Server & Clients** / **2 Players**.)
Es gehen 3 Fenster auf: **Server**, **Player1** und **Player2**. Zwischen den Fenstern wechselst du mit einem Klick auf das Fenster oder mit **Cmd + Tab**.
**Beenden:** im **Server**-Fenster auf **Cleanup** bzw. **Stop**.

> 💡 Im Studio kommen Bots schon nach 2 Sekunden. Stell beide Spieler also **schnell** auf die Pads.

### Admin-Rechte

- [ ] **B1 Player1 ist Admin:** Im Fenster Player1 gibt es den **Admin**-Knopf, **P** öffnet das Panel.
- [ ] **B2 Player2 ist kein Admin:** Im Fenster Player2 gibt es keinen Admin-Knopf, **P** macht nichts, **G** (Fliegen) geht nicht.
- [ ] **B3 Ablehnung wird geloggt:** Im **Server**-Fenster (Output) steht höchstens **eine** Zeile, dass Player2 abgelehnt wurde (nicht hunderte).

### Echte Duelle

- [ ] **B4 Gleiches Pad:** Beide auf **dasselbe 1v1-Pad**, Player1 auf die **orange**, Player2 auf die **blaue** Hälfte → sofort Match, **ohne Bots**.
- [ ] **B5 Verschiedene Pads:** Player1 auf **P1**, Player2 auf **P2** (beide 1v1, innerhalb von 2 Sekunden) → beide kommen ins selbe Match gegeneinander, bevor Bots kommen.
- [ ] **B6 2v2 zusammen:** Beide auf **dieselbe Hälfte** eines 2v2-Pads → ihr seid ein Team, 2 Bots sind die Gegner.
- [ ] **B7 2v2 gegeneinander:** Beide auf **verschiedene Hälften** eines 2v2-Pads → jeder bekommt einen Bot als Partner.
- [ ] **B8 Training + Warteschlange:** Player1 schießt im Training, Player2 geht auf ein Pad → kein Durcheinander, Player2 bekommt sein Match.

### Was der andere sieht

- [ ] **B9 Waffe in der Hand:** Player2 sieht bei Player1 die Waffe in der Hand (Spielzeug-Blaster mit oranger Spitze) und wie er nach oben/unten zielt.
- [ ] **B10 Treffer:** Player1 trifft Player2 → beide sehen den Schuss (Leuchtspur). Player2 bekommt eine rote Blende und einen Pfeil zur Schussrichtung.
- [ ] **B11 Umriss:** Gegner haben einen roten Umriss, aber **nur dort, wo man sie sieht** (nicht durch Wände).
- [ ] **B12 Kopftreffer mit Accessoire:** Hat ein Avatar Hut oder Haare: Kopftreffer zählen trotzdem normal.

### Ende, Rematch, Verlassen

- [ ] **B13 GG:** Nach dem Match drücken **beide** GG → beide +5 XP und +5 Coins.
- [ ] **B14 Loben:** Player1 lobt Player2 → kein Fehler.
- [ ] **B15 Rematch mit 2:** Beide drücken **REMATCH** → sofort neues Match, gleiche Arena.
- [ ] **B16 Verlassen im 1v1:** Player2 verlässt das laufende Match (**M** → Match verlassen) → Player1 gewinnt sofort. Player2 hat 60 s Pad-Sperre.
- [ ] **B17 Verlassen im Team:** Beide in einem 2v2 im selben Team, Player2 verlässt → nach 10 s ersetzt ihn ein Bot.
- [ ] **B18 Sudden Death:** siehe A33 (mit kurzer Rundenzeit, niemand schießt).

### Crown Ring zu zweit

- [ ] **B19 Krone:** Beide auf die Herausforderer-Linie → sie kämpfen. Der Gewinner wird König und bleibt im Ring. Der Verlierer landet am Rand.
- [ ] **B20 Zuschauer:** Wer in der Lobby am Ring steht, sieht die Schüsse und den Konfetti-Finisher der beiden.

### Sozial und Chat

- [ ] **B21 Chat-Umschreibung:** Player2 schreibt `ez` in den Chat → bei Player1 steht „**gg wp**“. Bei Player2 selbst steht weiter „ez“.
- [ ] **B22 Normale Wörter bleiben:** Player2 schreibt `mein Ping ist schlecht` → kommt bei Player1 **unverändert** an.
- [ ] **B23 Melden:** Player2 meldet Player1 (Punktetafel **Tab** → ⚑ oder im Todes-Rückblick **Melden**) → bei Player1 im Admin-Panel → **Moderation** → **Meldungen** steht die Meldung.

### Admin gegen einen normalen Spieler

- [ ] **B24 Kick:** Player1 → Admin → Spieler → Ziel `Player2` → **Kick** mit Grund „Test“ → Player2 sieht die Kick-Meldung und ist weg.
      (Danach Test neu starten, damit Player2 wieder da ist.)
- [ ] **B25 Bann-Dialog:** Player1 → Ziel `Player2` → **Ban** 1 Std mit Grund → die Statuszeile sagt, dass das **im Studio-Test nicht möglich** ist
      (Test-Spieler haben keine echte UserId). **Kein Absturz, kein roter Fehler.** Banns funktionieren erst im echten Spiel.
- [ ] **B26 Warnen / Einfrieren / Herholen:** Player2 warnen (roter Text bei Player2), einfrieren (kann nicht laufen), auftauen, herholen.
- [ ] **B27 Geben:** Player2 1.000 Coins geben → Player2 sieht +1.000.
- [ ] **B28 Ansage für alle:** Ansage → erscheint **in beiden** Fenstern mit Avatar und blauem Haken.
- [ ] **B29 Admin-Abuse für alle:** Admin-Abuse 1 Minute → Banner in **beiden** Fenstern.
- [ ] **B30 Fairness:** Player1 schaltet im Match gegen Player2 den **Aimbot** an → bei Player1 steht „TAINTED“. Player2 verliert, aber im Ergebnis steht kein Nachteil (keine Niederlage in der Statistik).
- [ ] **B31 Live-Balance für alle:** Player1 setzt `PopRifle Damage = 30` → Player1 trifft Player2 im Match mit 30 Schaden. Danach **Waffe zurücksetzen**.
- [ ] **B32 Zuschauen:** Player1 → Ziel `Player2` → **Zuschauen** → Kamera folgt Player2. Mit **X** beenden.
- [ ] **B33 Anti-Cheat-Falle (optional):** Das Spiel hat einen unsichtbaren „Gratis-Coins“-Befehl, den es selbst **nie** benutzt.
      Nur Hacker würden ihn auslösen. So testest du die Falle: im Fenster **Player2** in die Command Bar tippen:

```lua
game.ReplicatedStorage.Remotes.GrantCoins:FireServer()
```

  → Player2 wird mit „**Ungewöhnliche Aktivität erkannt**“ gekickt. Bei Player1 im Admin → **Moderation** → **Prüfliste** steht ein Eintrag.

---

## Teil C – Spezial-Tests

### Handy und Controller (Gerätesimulator)

- [ ] **C1 Handy-Knöpfe:** **Test → Device** → **iPhone SE** → Play. Knöpfe FEUER, ADS, NACHLADEN, RUTSCHEN, UTILITY und die Waffen-Leiste sind da,
      nicht zu klein, nichts unter dem Rand/der Notch.
- [ ] **C2 Ziehen = Zielen:** Den FEUER-Knopf gedrückt halten und ziehen → du schießt und drehst dich dabei.
- [ ] **C3 Auto-Feuer:** Im Match Fadenkreuz auf einen Gegner halten → es wird automatisch geschossen (langsamer als normal). In den Einstellungen abschaltbar.
- [ ] **C4 Tablet:** Gerät **iPad** → Layout passt.
- [ ] **C5 Controller:** Gerät **Xbox One** (oder echter Controller am Mac) → HUD zeigt Controller-Tasten, **RT** schießt, **LT** zielt, sanfte Zielhilfe ist spürbar.
- [ ] **C6 Live-Wechsel:** Während des Spiels zwischen Maus und Controller wechseln → das HUD wechselt mit.
- [ ] **C7 Linkshänder:** Einstellungen → **Linkshänder** → die Handy-Knöpfe sind gespiegelt.

### Lag (Netzwerk-Simulator)

- [ ] **C8 Lag einstellen:** **File → Beta Features** → „New Device Simulator“ (falls vorhanden) → bei **Test → Device**: Latenz **150 ms**, Jitter **30 ms**, Paketverlust **2 %**.
      Sonst: **File → Studio Settings → Network → Incoming Replication Lag** = `0.15`.
- [ ] **C9 Treffer mit Lag:** Im Training auf die **fahrenden** Puppen schießen und in einem Bot-Match auf laufende Bots → Treffer zählen.
- [ ] **C10 Abgelehnte Schüsse:** Admin → Debug → **abgelehnte Schüsse zeigen** an → es kommen höchstens selten Meldungen (nicht bei jedem Schuss).
- [ ] **C11 Zurückstellen:** Lag wieder auf `0` / Simulator aus.

### Selbsttest und Leistung

- [ ] **C12 Selbsttest:** Admin → Debug → **Selbsttest** → im Output `[SelfTest] n/n PASS`.
- [ ] **C13 Leistung:** 4v4-Pad allein starten (7 Bots), **fn + F8** → Server-Last im Schnitt unter **5 ms**. Das Spiel läuft flüssig.

---

## Wenn alles abgehakt ist

1. Studio-Änderungen aus A33 wieder zurückgestellt? (`RoundTime = 60`, `Overtime = 15`)
2. Lag-Einstellung wieder auf `0`?
3. Dann weiter mit **`ANLEITUNG.md`, Kapitel 7** (Veröffentlichen).

Etwas hat nicht geklappt? Schick Claude die **Nummer des Punkts** (z. B. „B5“), was passiert ist und den roten Text aus dem Output.
