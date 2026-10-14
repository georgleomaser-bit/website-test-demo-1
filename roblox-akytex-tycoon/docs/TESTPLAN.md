# AKYTEX TYCOON – Testplan für Roblox Studio und das Live-Spiel

Mit dieser Liste prüfst du, ob alles funktioniert, **bevor** das Spiel öffentlich wird. Geh sie von oben nach unten durch und
setz bei jedem Punkt einen Haken.

- **Teil A** testest du **allein** (Play) – ca. 60 Minuten.
- **Teil B** mit **2 Spielern** (Test → 2 Players) – ca. 30 Minuten.
- **Teil C** Geräte (Handy, Tablet, PC, Controller) und Netzwerk – ca. 20 Minuten.
- **Teil D** Compliance (Regeln von Roblox, Marke, Robux-Firewall, Namens-Suche) – ca. 60 Minuten, einmalig vor dem Start.
- **Teil E** Leistung – ca. 15 Minuten.
- **Teil F** Live-Test nach dem Veröffentlichen – ca. 20 Minuten.
- **Teil G** offene Prüfungen, die nur in Studio gehen (für Claude) – ca. 15 Minuten.

Bei jedem Punkt steht: **was du tust** → **was passieren muss**.
Klappt etwas nicht: im **Output** den roten Text kopieren (**Cmd + C**) und mit der Nummer an Claude schicken (z. B. „A17 klappt nicht“).

### Wörter in diesem Testplan

| Wort | Was es heißt |
|---|---|
| **Play / Stop** | Test im Studio starten (**fn + F5**) / beenden (**fn + Shift + F5**) |
| **Output** | Studio-Fenster mit Meldungen (**View → Output**). Rot = Fehler, Orange = Warnung |
| **SelfTest** | Automatischer Selbsttest beim Play. Ergebnis im Output: `[SelfTest] n/n PASS` |
| **AKY / CR** | Börsengeld (blaue Münze Λ, nur im Depot) / Turmgeld (grüner Sechskant-Chip) |
| **Depot** | Dein AKY-Konto mit Aktien, Orders und freiem Geld |
| **Gewinn-Transfer** | AKY über der Basis → CR zum Bau-Kurs (nur einmal je Börsentag) |
| **Börsentag** | 20 Minuten. Beginnt mit der Glocke |
| **Kauf simulieren** | Admin-Knopf: gibt ein Produkt genau wie ein echter Kauf, kostet nichts |
| **Policy simulieren** | Admin-Knopf: tut so, als wären Geschenke im Land erlaubt bzw. verboten |
| **Admin-Fenster / Taint** | Zeit um ein Admin-Markt-Event. Zählt nicht für die Liga |
| **Pickup** | Etwas zum Einsammeln (Bündel, Paket, Münze, Kugel). Jeder Spieler hat seine eigenen |
| **Gerätesimulator** | Studio tut so, als wärst du am Handy/Tablet/an der Konsole (**Test → Device**) |

Mehr Wörter: **ANLEITUNG.md, Kapitel 25** (Wörterliste A–Z).

---

## Vorbereitung

- [ ] `AkytexTycoon.rbxlx` in Studio geöffnet (**File → Open from File…**, **Cmd + O**) – oder per Rojo verbunden (ANLEITUNG Kapitel 4).
- [ ] **View → Output** und **View → Explorer** sind offen.
- [ ] Optional für Live-Tests mit echten Diensten: **Home → Game Settings → Security → Enable Studio Access to API Services** = AN
      (geht erst, wenn das Spiel einmal veröffentlicht ist). Ohne das läuft der Markt als „Lokaler Testmarkt“ – für Teil A und B reicht das.

> 💡 Im Studio wird **nie gespeichert** (`Config.Studio.NoSave = true`). Nach jedem Stop fängst du neu an (Tutorial kommt wieder).
> Für Tests mit Geld: Admin-Panel (**P**) → Reiter **Geld & Items** → Ziel `me` → z. B. 1.000.000 CR geben.

---

## Teil A – Allein testen (Play)

### A.1 Start
- [ ] **A1** Play drücken → Ladebildschirm: ΛKYTEX-Ring zeichnet sich, Kerzen steigen, Buchstaben erscheinen, Zeile
      „Spielgeld · erfundene Firmen · kein echtes Geld“. Höchstens ca. 4 s (früher, wenn geladen). Tippen überspringt.
- [ ] **A2** Output: Zeile `[AKYTEX Tycoon] Server gestartet ✅`, **keine roten Zeilen**.
- [ ] **A3** Output nach ca. 3 s: `[SelfTest] n/n PASS` (beide Zahlen gleich). Bei `FAIL`: Zeile kopieren → Claude.
- [ ] **A4** Nach ca. 2 s Toast „**Studio: Fortschritt wird nicht gespeichert**“.
- [ ] **A5** Keine orangen Zeilen mit `[Config]` (sonst stimmt eine Einstellung nicht).

### A.2 Die ersten 10 Minuten (Tutorial, DESIGN.md §B2)
- [ ] **A6** Kamera fliegt ca. 4 s über die Skyline auf deinen Plot („Hier entsteht dein Imperium“). Jede Taste überspringt.
- [ ] **A7** **Tiko** (Hologramm-Roboter) erscheint, Sätze kurz, Knopf **BAUEN** pulsiert. Es heißt überall „Tiko“ – nie „Aky“.
- [ ] **A8** Etage 1 „Garage-Startup“ (gratis): Kran-Szene ca. 3 s, Neon „STARTUP“, schwebende Zahlen fliegen in den Tresor.
- [ ] **A9** Durch das **goldene Kassen-Tor** gehen → Zähler rollt (300 CR vorgefüllt), Kassen-Ton.
- [ ] **A10** **TRADE** öffnet das Terminal im Übungsmodus mit **ACAD** („Übung“-Etikett). News-Karte „EILMELDUNG …“ mit ruhigem
      Balken **„Händler lesen …“** (8 s). **Kein Kauf-Knopf auf der Karte.**
- [ ] **A11** Chip **10 %** → **KAUFEN**. Kurs steigt in ca. 45 s um ca. 15 %. „Schutz an“ ist automatisch aktiv.
- [ ] **A12** **VERKAUFEN** (oder nach 90 s automatisch bei +12 %): ruhiger grüner Tick, sanftes Arpeggio, ca. +375 AKY.
      **Kein** Konfetti, keine Münz-Explosion.
- [ ] **A13** „Gewinn in den Tower“: Röhre fliegt zum Tower, ca. 15.000 CR (Bau-Kurs 40).
- [ ] **A14** Etagen 2–5 verkettet, bei Etage 4 **Stufen-Morph „Loft“** (Hülle verwandelt sich ca. 2,5 s).
- [ ] **A15** Abteilungs-Wahl auf Etage 2 (3 Karten, **Trading-Desk** empfohlen); Praktikant P-1 rollt an den Tisch, Monitor zeigt Live-Chart.
- [ ] **A16** Gratis **Hausmeister-Bot** erscheint (sammelt den Tresor alle 60 s, solange du auf deinem Plot bist).
- [ ] **A17** Echtes Terminal (Schicht „Einfach“), erster Live-Trade mit „Schutz an“ (−8 % / +15 %).
- [ ] **A18** Tiko: „Deine Starter-Quests sind da“ → **QUESTS ANSEHEN** öffnet das Aufgaben-Fenster direkt auf dem Reiter **Starter**.
      Gratis-Auto **Λ City** fährt aus der Garage, Wegpunkt-Beam zum Börsensaal.
- [ ] **A19** Börsensaal: Akademie-Kapsel **Lektion 1** (30 s + 2 Fragen, +100 XP).
- [ ] **A20** Bei 300 XP: **Azubi II**-Zeremonie (Stempel, kleines Konfetti, Basis 25.000 → 50.000 AKY).
      Gegenprobe (zweites Konto): Übungsaktie **und** Live-Trade mit „Überspringen“ auslassen → Tiko sagt bei Schritt 14
      „Für Azubi II fehlt noch: ein Kauf mit Schutz an“ und zeigt **TERMINAL ÖFFNEN**; nach einem Kauf mit „Schutz an“ kommt die Zeremonie.
- [ ] **A21** Erste **Effizienz-Stufe** (10.000 CR) → HUD-Chip „x1,10“ ploppt. Tippen öffnet die Aufschlüsselung (Quelle, Wert,
      Herkunft „verdient / Skill / gekauft / Event“, Restzeit).
- [ ] **A22** „Zukunfts-Ich“-Teaser („Dein Tower verdient auch offline – bis zu 8 h.“). **Kein Robux-Angebot in der ganzen ersten Sitzung.**
- [ ] **A23** „Tutorial überspringen“ (neuer Play) gibt dieselben Belohnungen.

### A.3 Terminal und Depot
- [ ] **A24** Taste **T** öffnet/schließt das Terminal. Watchlist links, Chart Mitte, Order-Ticket + News rechts (PC).
- [ ] **A25** Zeitrahmen **1–7** (1s · 5s · 1m · 5m · 15m · 1T · 1W) wechseln flüssig, keine Achsensprünge, Preise in gleich breiten Ziffern.
- [ ] **A26** Chips heißen **„10 % · 25 % · Max“** (nie „100 %“, nie „All-in“). Ab 20 % in einem Wert: „Sicher? Verteilen ist klüger.“
- [ ] **A27** Kosten-Vorschau zeigt Gebühr und Spread. Order-Typen als Azubi: Sofort, Wunschpreis, Verlust-Stopp, Gewinn-Ziel, Schutz-Paar.
      Es gibt **keinen** Hebel, keine Optionen, kein „Steigt/Fällt in X s“.
- [ ] **A28** Verlust-Trade: grauer Tick + Lerntipp (kein rotes Drama).
- [ ] **A29** Depot-Tab: Knopf „Gewinn in den Tower“ zeigt „Verfügbar … AKY → … CR (Bau-Kurs …)“. Ein zweiter Transfer im selben
      Börsentag ist gesperrt. Nach der nächsten Glocke wieder frei.
- [ ] **A30** Depot unter 50 % der Basis und keine offene Position: Knopf **Starthilfe** (1× je Tag). Das Geld ist **nicht** abhebbar.
- [ ] **A31** Disclaimer steht in der **Terminal-Fußzeile** und unter **Einstellungen → Info**.

### A.4 Tower, Lifestyle, Stadt
- [ ] **A32** Taste **B** → Tower-Menü: Etage bauen (ab Etage 10 mit Bauzeit), Abteilung wechseln (kostet 25 % der Etagenkosten),
      Personal einstellen (2 Plätze je Etage), Raum-Stufe L1–L5.
- [ ] **A33** Tresor-Ring füllt sich; voll = ruhiges Rot-Glühen + „Tresor voll – einsammeln!“.
- [ ] **A34** Aufzug: Etagen-Panel → kurze Kinoszene (Türen, Fahrt, Ding) → du stehst auf der Etage.
- [ ] **A35** Deko kaufen (Lager) und in einen der 3 Slots stellen; Komfort steigt.
- [ ] **A36** Auto fahren: **W A S D**, **Shift** = Boost (3 s, 8 s Abklingzeit), **Leertaste** = Handbremse/Drift. Auto verschwindet 60 s
      nach dem Aussteigen.
- [ ] **A37** Garage, Λ Motors (Autohaus West), Chronohaus (Uhren) öffnen; Uhr kaufen → sichtbar am linken Handgelenk.
- [ ] **A37b** Probefahrt: bei **Λ Motors** in der Autoliste **„Probefahrt“** drücken → das Auto steht am Autohaus, 90 s fahren, danach
      „Probefahrt vorbei“. Gleich nochmal → „Nächste Probefahrt in … s“ (120 s Pause). Weit weg vom Autohaus → Hinweis „Λ Motors (Westen)“.
- [ ] **A37c** Neon-Jetpack (Pass, Admin: Pass geben): springen, **in der Luft nochmal springen** = zünden, Sprung **halten** = steigen,
      loslassen = gleiten; Tank-Balken unten (8 s, lädt in 12 s). Kein Anti-Cheat-Alarm bis ca. 120 Studs Höhe. In fremden Towern aus.
- [ ] **A38** Tag/Nacht: alle 20 min ein voller Zyklus; abends gehen die Fenster von unten nach oben an.
- [ ] **A39** Akademie: Lizenzprüfung „Setze ein Schutz-Paar“ erkennt den Trade.
- [ ] **A40** Aufgaben (**J**): Tagesquests, Woche, Starter, Login. Reiter **Login** → Code `LAUNCH` einlösen → +5.000 CR.
      Nochmal einlösen → „Diesen Code hast du schon eingelöst.“
- [ ] **A41** Skyline-Pass: Gratis- und Premium-Spur sichtbar, ehrlicher Countdown bis zum Saison-Ende. Jede Belohnung hat einen
      lesbaren Namen (Premium Stufe 10 und 40 = Kopftitel „Skyline-Stammgast S1“ / „Skyline-Magnat S1“) – nirgends ein roher Schlüssel.
      Abholen: Klang + kleines Konfetti, die Zeile federt; die nächste Stufe ist lila umrandet. Nur gekaufte Stufen mit CR/Boost/Token
      zeigen **„Erspielen“** (zahlen erst mit verdienter Saison-XP) – nie „Gesperrt“. Wer +10 Stufen gekauft hat und weiterspielt,
      kann am Ende trotzdem alle 50 Stufen voll abholen (verdiente XP ersetzt gekaufte, sobald der Pass voll ist).
- [ ] **A41b** Bestenlisten-Tafeln vor dem Börsensaal: nach ca. 15 s steht **dein eigener Eintrag** darauf (live, auch in Studio ohne
      DataStore). Fenster **Bestenlisten** (Knopf 🏆): eigene Zeile blau hervorgehoben (bleibt beim Darüberfahren), Plätze 1–3 mit
      Gold/Silber/Bronze-Streifen. Ø-Tagesrendite: negative Werte anderer Spieler erscheinen nie (kein öffentliches Verlust-Zeigen).

### A.5 Shop und Käufe (alle IDs sind noch 0)
- [ ] **A42** Taste **N** → Shop. Alle 14 Pässe, 17 Produkte und das Abo sind sichtbar und zeigen „**Bald verfügbar**“
      (Terminal-Designer: „Gerade nicht verfügbar“ – gesperrt, bis die Terminal-Themes im Spiel sind).
- [ ] **A43** Knöpfe heißen „Ansehen“, „Details“ oder „Preis anzeigen“ – nie „JETZT KAUFEN“, „LETZTE CHANCE“, „Nur heute!“.
- [ ] **A44** Bau-Gutscheine zeigen die **genaue CR-Zahl** vor dem Kauf; Text „Nur CR“.
- [ ] **A45** x2- und x3-Pass: Text „x2 + x3 zusammen = x4“ ist vor dem Kauf sichtbar.
- [ ] **A46** Admin-Panel → **Debug → Kauf simulieren** für **jedes** Produkt und jeden Pass: Wirkung sofort sichtbar (Chip poppt,
      Auto fährt aus der Garage, Fassade wechselt). Danach: **AKY im Depot, Lizenz, Trader-XP, Know-how, Ruf unverändert** (Teil D3).
- [ ] **A47** Starter-Paket zweimal simulieren → beim zweiten Mal 2 × Bau-Gutschein M.
- [ ] **A48** **Debug → Policy simulieren** „Geschenke verboten“ → Geschenk-Boost ist gesperrt („Geschenke sind für dich oder den
      Empfänger gerade nicht möglich.“). „Erlaubt“ → kaufbar (simuliert).

### A.6 Events (alles automatisch, im Studio kannst du sie über das Admin-Panel starten)
- [ ] **A49** Welt-Event um :10 (oder Admin-Panel → **Welt → Welt-Event jetzt starten**): Geldtransporter (30 Bündel), Drohnen (8 Pakete),
      Bau-Boom (−25 %, Timer), Pressekonferenz (Quiz). HUD-Pille zeigt das Event.
- [ ] **A50** Volle Stunde: **Glocken-Moment** (im Studio reicht 1 Spieler in der Glocken-Zone) → Server-Boost ×1,2 für 5 min.
- [ ] **A51** Admin-Panel → **Markt → Mega-Crash** (z. B. −20 %, mit Warnung): 3-min-Warnstufe, roter Himmel, Sirene, **Bär** auf der Plaza,
      Vertrauens-Kugeln sammeln. HUD-Chip „ADMIN-ABUSE aktiv – zählt nicht für die Liga“. Danach **Normalisieren**.
- [ ] **A52** **Mega-Rally**: grünes Polarlicht, goldener Bulle läuft den Ring; Berühren = Bullen-Bonus ×1,5 für 5 min.
- [ ] **A53** **Samstags-Show (1 Klick)**: Banner → Golden Hour ×2 → Rally → Geldregen → Feuerwerk.
- [ ] **A54** Admin-Eilmeldung (≤ 80 Zeichen): erscheint mit normalem 8-s-Lesefenster.

### A.7 Admin-Panel (Taste P)
- [ ] **A55** Alle 11 Reiter öffnen sich: Dashboard, Spieler, Markt, Events, Geld & Items, Kräfte, Welt, Live-Ops, Statistik, Moderation, Debug.
- [ ] **A56** Dashboard zeigt das Banner „**Lokaler Testmarkt**“ (ohne API-Zugriff) und den Bus-Status.
- [ ] **A57** Gefährliche Knöpfe brauchen eine **Bestätigung innerhalb von 5 s**.
- [ ] **A58** Kräfte: Fliegen (**G**), Noclip, Speed, Unsichtbar, Show-Kamera – kein Anti-Cheat-Kick. Fotomodus (**F7**) blendet alle Knöpfe aus (gibt es für alle Spieler).
- [ ] **A59** **F8** (MacBook: **fn + F8**) zeigt die Debug-Anzeige (Markt-Tick-ms, FPS, Teile, Scheduler-Top-5, Speicher, Ping).
- [ ] **A60** Debug → **Tag überspringen**: Login-Kalender und Tagesquests wechseln.

### A.8 Einstellungen
- [ ] **A61** Sprache Deutsch/Englisch umschalten → alle Texte wechseln.
- [ ] **A62** Farbenblind-Modus → Up/Down werden Blau/Orange, ▲/▼ bleiben.
- [ ] **A63** Reduzierte Effekte → Kamerafahrten sofort, weniger Partikel. Grafikstufe Low/Medium/High/Ultra wechselt sichtbar.
- [ ] **A64** News-Karten „Ruhemodus“ → nur noch Crash/Rally/Glocke als Karte.

---

## Teil B – Mit 2 Spielern (Test → 2 Players)

Reiter **Test** → bei **Clients and Servers** „**2 Players**“ → **Start** (neue Oberfläche: Pfeil neben **Play** → **Server & Clients**).
Es öffnen sich 3 Fenster: **Server**, **Player1**, **Player2**.

- [ ] **B1** **Player1** hat den Admin-Knopf (Taste **P**), **Player2 nicht**. Output des Servers: genau **eine** Zeile, dass Player2
      abgelehnt wurde (wenn Player2 **P** drückt).
- [ ] **B2** Beide sehen **identische Kurse** (gleicher Wert, gleiche Sekunde, gleicher Chart).
- [ ] **B3** Plots 1 und 2 liegen nebeneinander.
- [ ] **B4** Player2 besucht den Tower von Player1 (Tower-Tour-Kiosk auf der Plaza oder hinlaufen) → kann nichts verändern oder mitnehmen.
- [ ] **B5** **Respekt** geben (im Studio ohne Kontoalter-Prüfung) → Player1 bekommt +0,01 Dauer-Multiplikator für 1 h; nur 1× je Tag.
- [ ] **B6** **Bau-Hilfe**: Player2 tippt die Baustelle von Player1 → −10 % Restzeit (max. 3 Helfer, je 1× je Etage).
- [ ] **B7** Welt-Event: **jeder** sieht seine eigenen Bündel/Pakete; was Player1 einsammelt, verschwindet bei Player2 **nicht**.
- [ ] **B8** Autos **kollidieren nicht** mit Figuren und nicht miteinander (durchfahren, kein Schubsen).
- [ ] **B9** Admin-Abuse lokal (Geldregen, Golden Hour) erreicht beide. Globale Events laufen im Studio lokal (Bus lokal).
- [ ] **B10** Reaktionen (Taste **R**, Radialmenü) erscheinen als Blase über dem Kopf; Emotes funktionieren.
- [ ] **B11** Server-Toast nur für Stufen-Morph, Lizenz, Titel, Börsengang, Liga-Stufe, Hypercar – **nie** für Trade-Gewinne.
- [ ] **B12** Bullen-Parade simulieren (Player1) → beide sehen die Parade und haben ×1,5; Danke-Banner ohne Robux-Betrag.
- [ ] **B13** Glocken-Moment mit beiden in der Zone → Server-Boost für beide.
- [ ] **B14** Freunde-Bonus: im Studio nicht testbar (Test-Spieler sind keine Freunde) – Live-Test F7.
- [ ] **B15** Beenden: im **Server**-Fenster **Cleanup** (bzw. **Stop**).

---

## Teil C – Geräte und Netzwerk

### C.1 Gerätesimulator (Reiter **Test → Device**)

| # | Gerät | Prüfen |
|---|---|---|
| [ ] **C1** | **iPhone SE** (kleines Handy) | Knöpfe ≥ 64 px, nichts unter der Notch, Terminal als Vollbild-Sheet mit 4 Tabs (Chart · Order · Depot · News), feste Kauf/Verkauf-Leiste unten, Wischen wechselt den Wert |
| [ ] **C2** | **großes Handy quer** (z. B. iPhone 14 Pro Max) | HUD passt, Ticker-Leiste lesbar, TRADE-Knopf erreichbar |
| [ ] **C3** | **iPad** | Terminal-Layout wie PC oder Sheet, Texte nicht zu klein |
| [ ] **C4** | **PC 1920 × 1080** | Terminal mit Watchlist · Chart · Ticket · Tabs unten; 6 Indikatoren möglich |
| [ ] **C5** | **Xbox-Controller** (Console) | Y = Terminal, Steuerkreuz = Menüs (hoch Tower, rechts Aufgaben, links Shop, runter Reaktionen), LB/RB Zeitrahmen, A Kauf-Sheet, X Verkauf-Sheet, B zurück; im Auto R1 Boost, B Handbremse |
| [ ] **C6** | Handy: Auto fahren | Touch-Knöpfe BOOST und HANDBREMSE, Lenken mit dem Stick, Fahrgefühl ok |
| [ ] **C7** | Handy: Grafikstufe automatisch | bei < 35 FPS schaltet das Spiel einmal „Reduzierte Effekte“ an |

### C.2 Netzwerk-Simulator
1. **File → Beta Features** → falls vorhanden „New Device Simulator“ (o. ä.) an → Studio neu starten → bei **Test → Device** Netzwerk:
   **Latenz 150 ms**, **Jitter 30 ms**, **Paketverlust 2 %**.
2. Falls nicht vorhanden: **File → Studio Settings** (Mac: **Roblox Studio → Settings…**) → **Network** → **Incoming Replication Lag** = `0.15`.
- [ ] **C8** Kurse laufen flüssig weiter (Lücken werden vom nächsten Paket geheilt), Chart springt nicht.
- [ ] **C9** Kauf/Verkauf mit Lag: genau **eine** Ausführung je Klick (Doppelklick erzeugt keine zweite Order).
- [ ] **C10** Aufzug, Kassen-Tor, Pickups funktionieren mit Lag.
- [ ] **C11** **Danach unbedingt wieder auf `0` stellen.**

---

## Teil D – Compliance-Checkliste (einmal vor dem Start, danach bei jedem großen Update)

### D1 Wortliste (DESIGN.md §0.7)
- [ ] Im Spiel (DE **und** EN durchklicken: Shop, Terminal, News, Akademie, Quests, Ansagen) kommt **keins** dieser Wörter vor:
      DE Wette/wetten, Einsatz (außer „im Einsatz“), Casino/Kasino, Jackpot, Glück… (außer „Glückwunsch“), Glücksrad, Glücksspiel,
      zocken, All-in, verdoppeln, „doppelt oder nichts“, Lotterie, Losnummer, Rubbellos, Gewinnspiel, Spielautomat, Roulette, Poker,
      Würfel, Hebel, Insider, Krypto, Bitcoin, NFT, Mondfahrt, „garantiert“ · EN bet, betting, wager, stake, casino, jackpot, lucky, luck,
      gamble, gambling, all-in, „double or nothing“, lottery, raffle, spin, x100, „to the moon“, leverage, insider, crypto, bitcoin, NFT,
      poker, roulette, „slot machine“, dice, guaranteed.
- [ ] Automatisch (Claude bzw. Terminal im Projektordner): `python3 scripts/contract_check.py .` meldet **keinen** `banned-word`-Fehler.
- [ ] Spielseite (Titel, Beschreibung, Pass-/Produkt-/Badge-Texte, Event-Texte) ebenfalls ohne diese Wörter (KOPIERVORLAGEN ist geprüft).

### D2 Keine Glücksspiel-Darstellung (Alters-Label Minimal)
- [ ] Nirgends Casino, Spielkarten, Würfel, Glücksrad, Spielautomat, Roulette, Pokerchips – auch nicht als Deko oder auf Postern.
- [ ] Keine Zufalls-Kisten, keine Räder, keine bezahlten Zufallsartikel (`Config.Shop.RandomItemsEnabled = false`, SelfTest „NoPaidRandom“ PASS).
- [ ] Kein Spielautomaten-Feedback: keine Münz-Explosion pro Trade, keine Fast-gewonnen-Effekte, keine Serien-Flammen.
- [ ] News-Karte ohne Kauf-Knopf und ohne Countdown-Ring; nur „Zum Chart“ und „×“.
- [ ] Kein Hebel, keine Optionen, kein „Steigt/Fällt in X s?“, kein „Verdoppeln“.
- [ ] Keine Gewalt (Bär und Bulle freundlich, Autos treffen nie Figuren), kein Alkohol (Raum heißt „Smoothie-Café“), keine Club-/Party-Orte.

### D3 Robux-Firewall (das Herz der Fragebogen-Antworten)
- [ ] SelfTest „Firewall“ ist PASS (Output).
- [ ] Hand-Test: Depot-Wert, freies AKY, Basis, Lizenz, Trader-XP, Know-how und Ruf aufschreiben → **jedes** Produkt und jeden Pass
      simulieren (A46) → alle Werte **genau gleich**. Nur CR, Boosts, Bau-Tempo, Kosmetik ändern sich.
- [ ] Kein Robux-Artikel nennt „Rendite“, „ROI“, „investieren“ oder „Gewinn“.
- [ ] Bau-Kurs ändert sich **nur** mit der Lizenz (nicht mit Pässen, Boosts oder Tower-Stufe).
- [ ] Multiplikator-Aufschlüsselung sagt: „Multiplikatoren wirken nur auf das Turm-Einkommen – nie auf Börsengeld, Kurse oder Trades.“
- [ ] Kein Spielerhandel, keine Übertragung von AKY/CR/Aktien/Items zwischen Spielern.

### D4 Ehrliche Angebote
- [ ] Erste Sitzung: **kein** Angebots-Popup. Ab Sitzung 2: höchstens **1** Popup, frühestens nach 15 min, direkt nach einem Stufen-Morph.
- [ ] Nie ein Popup während Tutorial, Crash/Rally-Warnung, offenem Terminal/Order-Ticket, Willkommen-zurück-Bericht oder Admin-Abuse-Countdown.
- [ ] Countdowns sind echt (feste Enddaten, kein Neustart). Rabatt beim Tycoon-Paket ist echt (aus Live-Preisen).

### D5 Marke AKYTEX
- [ ] Nirgends (Spiel, Spielseite, Bilder): URL, QR-Code, „App“, „Website“, „Demo-Depot“, „echtes Trading“, Broker, Euro-Preise,
      Tarifnamen (Free/Plus/Pro/Elite/Ultra), „AKYTEX AI“, „Aky“, „NOVA“, „PRO“, Gründernamen, „3 Minuten am Tag. Ein Leben lang reicher“.
- [ ] Keine handelbare Firma heißt AKYTEX oder NOVA (die ETFs „AKYTEX 36“ usw. sind Index-Körbe der fiktiven Börse – ok).
- [ ] Disclaimer (DE/EN) steht: **Ladebildschirm**, **Terminal-Fußzeile**, **Einstellungen → Info**, **Akademie**, **Spielseite**.
- [ ] Social-Hinweis im Spiel nur: „Unsere Social-Links findest du auf der Spielseite“.

### D6 Namens-Suche (Pflicht vor dem Start)
**So suchst du:** Für jeden Namen und jedes Kürzel im Browser suchen: `"<Name>" company`, `"<Name>" Firma`, `<Kürzel> stock`,
`<Kürzel> ETF`. Zusätzlich die EU-Markensuche **TMview** und beim deutschen Markenamt **DPMAregister** nach dem Namen suchen.
**Treffer** = eine bekannte echte Firma/Marke mit (fast) gleichem Namen in einer ähnlichen Branche, oder ein Börsen-Kürzel eines
echten Werts. Bei einem Treffer: Claude schreiben „Firma/Kürzel <X> umbenennen“ (Datei `Config → Companies`, Paket WP3).

> ⚠️ **Schon bekannte Verdachtsfälle (bitte zuerst prüfen):** `QTRX` (Kürzel von Quanterix, Nasdaq), `SCHF` (großer
> Schwab-ETF), `PFFR` (InfraCap-ETF), `MGLN` (früheres Kürzel von Magellan Health), `ACAD` (Kürzel von ACADIA Pharmaceuticals).
> Diese Kürzel stehen so in `Config → Companies` und sollten **vor dem Start** geändert werden.

| ID | Kürzel | Name | Name-Suche ok? | Kürzel-Suche ok? |
|---|---|---|---|---|
| 1 | CGVO | Cognivo KI | [ ] | [ ] |
| 2 | KRWK | Kernwerk Systems | [ ] | [ ] |
| 3 | QTRX | Quantorix Quantum | [ ] | [ ] ⚠️ Verdacht |
| 4 | LMRA | Lumora Chips | [ ] | [ ] |
| 5 | NMBY | Nimbusly Cloud | [ ] | [ ] |
| 6 | PXWK | Pixelwerk Robotics | [ ] | [ ] |
| 7 | SNWK | Sonnwerk Solar | [ ] | [ ] |
| 8 | FSNT | Fusionaut | [ ] | [ ] |
| 9 | NBRZ | Nordbrise Wind | [ ] | [ ] |
| 10 | HDRV | Hydrava | [ ] | [ ] |
| 11 | VLTR | Voltaris | [ ] | [ ] |
| 12 | GTHM | Geotherma | [ ] | [ ] |
| 13 | ORBV | Orbivo Space | [ ] | [ ] |
| 14 | MGLN | Magliner | [ ] | [ ] ⚠️ Verdacht |
| 15 | VLCT | Velocitra Motors | [ ] | [ ] |
| 16 | DRNR | Dronaro | [ ] | [ ] |
| 17 | ARLF | Aerolift | [ ] | [ ] |
| 18 | RTXO | Robotaxo | [ ] | [ ] |
| 19 | KNSX | Knusperix | [ ] | [ ] |
| 20 | BLBR | Blubbro | [ ] | [ ] |
| 21 | SNKA | Sneakora | [ ] | [ ] |
| 22 | BGPT | Burgerplanet | [ ] | [ ] |
| 23 | PFFR | Pfotenfreund | [ ] | [ ] ⚠️ Verdacht |
| 24 | SPWK | Spielwerk Toys | [ ] | [ ] |
| 25 | ARCN | Arcadeon Games | [ ] | [ ] |
| 26 | STMR | Streamora | [ ] | [ ] |
| 27 | PLVO | Playverso VR | [ ] | [ ] |
| 28 | MEMT | Memetastic Media | [ ] | [ ] |
| 29 | ESPV | Esportiva Arena | [ ] | [ ] |
| 30 | NNBT | Neonbeat Records | [ ] | [ ] |
| 31 | TWBK | Towerbank | [ ] | [ ] |
| 32 | SKLA | Skylinea | [ ] | [ ] |
| 33 | GLDR | Goldader Mining | [ ] | [ ] |
| 34 | SCHF | Sicherhafen | [ ] | [ ] ⚠️ Verdacht |
| 35 | KLPY | Klickpay | [ ] | [ ] |
| 36 | BKRZ | Baukranz | [ ] | [ ] |
| 100 | NRNT | Neuronauten (IPO S1) | [ ] | [ ] |
| 101 | FLRA | Flora Energy (IPO S1) | [ ] | [ ] |
| 102 | MNDW | Mondwerk (IPO S1) | [ ] | [ ] |
| 103 | RBCF | Robochef (IPO S1) | [ ] | [ ] |
| 40–46 | AKX36, AKXT, AKXE, AKXM, AKXK, AKXG, AKXF | AKYTEX-ETFs (eigene Spielmarke) | – | [ ] |
| 250 | ACAD | Akademie Übungsaktie | – | [ ] ⚠️ Verdacht |

Empfohlen zusätzlich (kurz suchen): Spielhelfer **Tiko**, **Λ Motors**, **Chronohaus**, Autos (Volta Hatch, Pixel Mini, Stratos,
Nordlicht Executive, Velocitra, Kometa SL, Aurora GT, Quasar X, Singularity, Orbit-R) – keine echten Modellnamen bekannter Hersteller.
Die Sperrliste für Spieler-Ticker beim Börsengang steht in `Config → Progression → TickerBlock` (echte große Kürzel, NFT/BTC/ETH).

### D7 Fragebogen und Live-Regeln
- [ ] Vor dem Ausfüllen den **Live-Wortlaut** gelesen: Community Standards (Glücksspiel), Advertising Standards (Finanzdienste),
      Fragebogen-Fragen (ANLEITUNG Kapitel 10).
- [ ] Antworten genau wie ANLEITUNG Kapitel 10 → Ergebnis **Minimal**.

---

## Teil E – Leistung (DESIGN.md §C16)

Messen mit **F8** (Debug-Anzeige, nur Admin), in Studio zusätzlich **View → Script Performance** und **View → MicroProfiler**;
im Live-Spiel mit der **Developer Console** (**F9**, MacBook **fn + F9**) → Reiter **Memory**, **Network**, **ServerStats**.

| # | Messpunkt | Ziel |
|---|---|---|
| [ ] **E1** | Server-Scheduler gesamt (F8 „Scheduler“) bei 10 Spielern | Ø ≤ 3 ms |
| [ ] **E2** | Markt-Tick (F8) | < 0,3 ms |
| [ ] **E3** | Turm-Einkommen / Bots / Anti-Cheat | < 0,1 ms / < 0,3 ms / < 0,5 ms |
| [ ] **E4** | Teile auf dem Server (F8 „Teile“) | Stadt ≤ 12.000 · Tower ≤ 4.600 · gesamt ≤ 17.000 |
| [ ] **E5** | FPS Handy (Low/Medium) | ≥ 30 |
| [ ] **E6** | FPS PC (High/Ultra) | 60 |
| [ ] **E7** | Client-Lua je Frame | ≤ 3 ms |
| [ ] **E8** | Terminal-Chart je Frame (offen, 1s-Zeitrahmen) | < 0,3 ms, ≤ 900 GuiObjects je Chart |
| [ ] **E9** | GuiObjects gesamt | ≤ 2.500 |
| [ ] **E10** | Speicher Client (Low) | ≤ 900 MB |
| [ ] **E11** | Netzwerk je Spieler (F9 → Network) | < 1 KB/s (Markt ≈ 0,44 KB/s) |
| [ ] **E12** | Crash-Spitze (Admin-Crash, 3 Charts offen) | kein Ruckeln, kurz ≈ 40 KB |
| [ ] **E13** | Lichter (Ultra) | ≤ 64 (High ≤ 32) |

---

## Teil F – Live-Test nach dem Veröffentlichen

- [ ] **F1** Spielseite öffnen → **Play** (als RizzG315 darfst du auch ein privates Spiel spielen). Welt baut sich in wenigen Sekunden auf.
- [ ] **F2** Taste **P** öffnet das Admin-Panel (Spiel muss unter **RizzG315** veröffentlicht sein).
- [ ] **F3** **Speichern:** CR verdienen, Spiel verlassen, nach 1 Minute wieder beitreten → CR, Etagen, Depot sind noch da;
      „Willkommen zurück“-Karte zeigt Offline-Einnahmen.
- [ ] **F4** Admin-Dashboard: **kein** „Lokaler Testmarkt“-Banner mehr; Bus-Status grün.
- [ ] **F5** Mit eingetragenen IDs: in **Studio** (mit API-Zugriff) einen Pass kaufen → Roblox zeigt „Testkauf, dein Konto wird nicht belastet“.
      Wirkung kommt an; erneuter Beitritt: Pass bleibt.
- [ ] **F6** Badges (mit IDs): „Willkommen“ kommt beim Beitritt, „Erste Etage“ nach Etage 1.
- [ ] **F7** Mit einem Freund: Freunde-Bonus +0,10 im Multiplikator, benachbarte Plots.
- [ ] **F8** **Voice:** Mit einem berechtigten Konto (13+, verifiziert) ist das Mikrofon-Symbol über dem Kopf da; Nähe = lauter.
- [ ] **F9** Zweiter Server (z. B. über einen Freund): Admin-Ansage „alle Server“ kommt dort an; Markt-Event gleichzeitig auf beiden.
- [ ] **F10** Experience Events sind auf der Spielseite sichtbar; Private Server sind gratis aktivierbar.
- [ ] **F11** **Einladen mit Tower-Besuch:** Sozial → Einladen → „Freunde einladen“ → Freund nimmt an → er landet auf deinem Server und
      (nach seinem Tutorial bzw. sofort, wenn er es schon kennt) in deiner Tower-Lobby. Im Tutorial sieht er „Nach dem Tutorial geht
      es zum Tower von …“.
- [ ] **F12** **Gruppe** (erst mit eingetragener `GroupId`): Sozial → Einladen → „Gruppe beitreten“ → Roblox-Fenster → beitreten →
      innerhalb von ca. 2 min Meldung „Willkommen in der Gruppe …“, Community-Krone in der Boutique (Accessoires) freigeschaltet,
      blauer Rahmen am Namensschild (für andere sichtbar).
- [ ] **F13** Zweites Konto, Tutorial **überspringen** → bei der ersten Lizenz-Zeremonie (Azubi II) kommt einmal die Favoriten-Abfrage;
      bei der nächsten Zeremonie stattdessen (falls Roblox es erlaubt) die Benachrichtigungs-Zustimmung.

---

## Teil G – Offene Prüfungen in Studio (DESIGN.md §E5; Ergebnis an Claude)

| # | Prüfen | Wenn es nicht klappt |
|---|---|---|
| [ ] **G1** | Linien in Charts (Path2D) werden korrekt dargestellt und am Rand abgeschnitten | Claude: „Path2D aus, Segment-Frames an“ |
| [ ] **G2** | Schriften BuilderExtended/BuilderMono zeigen **Umlaute** (ä ö ü ß) und **„Λ“** | Rückfall Michroma/TitilliumWeb |
| [ ] **G3** | `VoiceChatService.EnableDefaultVoice` und `StreamOutBehavior` stehen nach dem Öffnen der Datei richtig (Explorer → VoiceChatService / Workspace → Properties) | Game Settings → Communication (ANLEITUNG Kapitel 8.4) |
| [ ] **G4** | Tower-Hüllen bleiben aus der Ferne sichtbar (Streaming, `LevelOfDetail = StreamingMesh`), eigener Plot bleibt geladen | Claude melden |
| [ ] **G5** | Ein eingetragenes Mesh-Asset (ASSET-LISTE) erscheint im Live-Server | Asset-Besitz/Moderation prüfen |
| [ ] **G6** | Markt-Tick-Kosten (F8) unter 0,3 ms | Claude melden |
| [ ] **G7** | Auto fahren am Handy fühlt sich gut an | Claude: Fahrwerte anpassen |
| [ ] **G8** | (v1.1) Benachrichtigungen senden – erst nach Freigabe | bleibt aus |
| [ ] **G9** | Hall-of-Fame-Statuen erscheinen (Avatar-Modell) | Claude melden |
| [ ] **G10** | Live-Wortlaut Community Standards, Advertising Standards, Fragebogen gelesen | vor jeder Einreichung |
| [ ] **G11** | Namens-Suche D6 erledigt | Umbenennen lassen |

---

## Ergebnis

| Teil | Erledigt am | Probleme (Nummern) |
|---|---|---|
| A Allein | | |
| B 2 Spieler | | |
| C Geräte/Netz | | |
| D Compliance | | |
| E Leistung | | |
| F Live | | |
| G Offen | | |

Alles abgehakt? Dann: Fragebogen ausfüllen (ANLEITUNG Kapitel 10) → **Playability = Public** (ANLEITUNG Kapitel 8.3).
