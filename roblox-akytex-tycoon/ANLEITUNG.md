# AKYTEX TYCOON – Schritt-für-Schritt-Anleitung

Diese Anleitung ist für dich als Besitzer des Spiels (Roblox-Konto **RizzG315**). Du brauchst keine Vorkenntnisse.
Alles ist für den **Mac** geschrieben.

**Kurz zu den Mac-Tasten:**

| Zeichen | Taste | Wo |
|---|---|---|
| **Cmd** (⌘) | Command | direkt neben der Leertaste |
| **Option** (⌥) | Option / alt | neben Cmd |
| **Shift** (⇧) | Umschalt | groß, links |
| **Ctrl** (⌃) | Control | ganz links unten (neben fn) |
| **fn** | Funktion | ganz unten links. Für **F5**, **F7**, **F8**, **F9** musst du am MacBook meist **fn** dazu drücken |
| **Enter** (↩) | Return | rechts, groß |

Klickpfade sind **fett** geschrieben. **Home → Game Settings** heißt: oben auf **Home** klicken, dann auf **Game Settings**.
Befehle für das Mac-Programm **Terminal** stehen in grauen Kästen – kopieren (Kopier-Knopf oben rechts am Kasten oder markieren +
**Cmd + C**), im Terminal einfügen (**Cmd + V**) und **Enter** drücken.

Ein Wort verstehst du nicht? Ganz unten in **Kapitel 25** steht die **Wörterliste von A bis Z**.

**Kapitel:** 1 Was ist AKYTEX TYCOON · 2 Was drin ist · 3 So spielt man · 4 Programme installieren · 5 Spiel-Datei holen ·
6 Admin-Panel · 7 Testen · 8 Veröffentlichen · 9 Robux (Pässe, Produkte, Abo, Badges) · 10 Fragebogen · 11 Roblox Kids & Select ·
12 Marke AKYTEX · 13 Spieler finden · 14 Admin-Panel-Tour & Samstag · 15 Live-Ops & Experience Events · 16 Neue Saison ·
17 Codes · 18 Eigene Assets (Higgsfield) · 19 Config & Balancing · 20 Updates · 21 Zahlen (KPIs, Umsatz) · 22 Fehlerhilfe ·
23 Technik · 24 Dateien · 25 Wörterliste

**Die anderen Dateien für dich:**
- `docs/KOPIERVORLAGEN.md` – alle Texte zum Kopieren (Titel, Beschreibung, 14 Pässe, 17 Produkte, Abo, 15 Badges, Events, ID-Kasten)
- `docs/TESTPLAN.md` – Prüfliste (allein, 2 Spieler, Geräte, Compliance, Namens-Suche, Leistung)
- `docs/LIVEOPS.md` – Wochenplan, Saisons, Samstags-Ablauf, Notschalter
- `docs/ASSET-LISTE.md` – jeder Platz für eigene 3D-Modelle, Bilder und Sounds (Higgsfield)
- `docs/STYLE-AKYTEX.md` – der AKYTEX-Look (Farben, Schriften, Regeln)

---

## 1. 🏙️ Was ist AKYTEX TYCOON?

> **Börse trifft Wolkenkratzer.** Du startest in einer Garage mitten in einer Neon-Stadt. Du liest Eilmeldungen, bevor der Markt
> reagiert, handelst 36 erfundene Firmen an der **AKYTEX Exchange** mit Spielgeld und steckst deine Gewinne in deinen eigenen
> Wolkenkratzer – Etage für Etage bis zum 50-stöckigen **ΛKYTEX Orbit-Spire**. Du stellst Roboter-Personal ein, fährst Autos über den
> Autobahnring, trägst Uhren und läutest die Glocke zu deinem eigenen Börsengang. Alle Server teilen **einen** Markt:
> Glocke alle 20 Minuten, Crash-Freitag, Admin-Abuse-Samstag.

- Spielseiten-Titel: **`AKYTEX TYCOON 🏙️📈 Börse & Tower`**
- Spruch: „**Lies die Eilmeldung. Bau die Skyline.**“ (EN: „Read the news. Build the skyline.“) · Marke: „Markets move. Ideas stay.“
- **Alles ist Spielgeld und erfunden.** Hinweis im Spiel und auf der Spielseite: „Spiel mit Spielgeld. Alle Firmen, Kurse und
  Nachrichten sind frei erfunden. Spielgeld hat keinen echten Wert und kann nicht ausgezahlt werden. Keine Anlageberatung.“
- Kein Glücksspiel, keine Zufallskisten, kein Spielerhandel. Robux kaufen **nie** Börsengeld, Aktien, Lizenzen oder Marktinfos.
- Die ganze Stadt (Plaza, Börsensaal, 10 Plots, Autohaus, Marina, Villenhügel, Autobahnring) baut sich **per Code** von selbst.
  Du musst in Studio nichts bauen.

### Dein Fahrplan (Kurzfassung)

| # | Was | Wo | Zeit |
|---|---|---|---|
| 1 | Roblox Studio, Rokit und Rojo auf dem Mac installieren | Kapitel 4 | 20 Min |
| 2 | Spiel-Datei `AkytexTycoon.rbxlx` holen (oder selbst bauen) und öffnen | Kapitel 5 | 10 Min |
| 3 | Ausprobieren: allein und mit 2 Spielern | Kapitel 6 + 7, `docs/TESTPLAN.md` Teil A/B | 60–90 Min |
| 4 | Veröffentlichen (sicherer Weg gegen „Save failed“) + Einstellungen + Voice-Chat | Kapitel 8 | 20 Min |
| 5 | 14 Pässe, 17 Produkte, Abo und Badges anlegen, IDs an Claude schicken | Kapitel 9, `docs/KOPIERVORLAGEN.md` | 60 Min |
| 6 | Neue Datei mit deinen IDs veröffentlichen | Kapitel 20 (Weg A) | 10 Min |
| 7 | Compliance-Prüfung + Namens-Suche | `docs/TESTPLAN.md` Teil D | 60 Min |
| 8 | Roblox-Fragebogen ausfüllen (Ziel: Minimal) | Kapitel 10 | 10 Min |
| 9 | Spielseite fertig machen: Titel, Beschreibung, Bilder, Social Links, Experience Events | Kapitel 13 + 15 | 30 Min |
| 10 | Spiel auf **Public** stellen | Kapitel 8.3 | 2 Min |
| 11 | Später: Roblox Kids & Select freischalten | Kapitel 11 | – |
| 12 | Jede Woche: Samstag 16:00 Update, 18:00 Admin-Abuse | Kapitel 14, `docs/LIVEOPS.md` | – |

---

## 2. 📦 Was alles drin ist

| Bereich | Inhalt |
|---|---|
| **Stadt** (2 km × 2 km) | **Exchange Plaza** mit Logo-Ring, Brunnen, Riesen-Kerzentafel, Ticker-Wänden, Hall of Fame · **Börsensaal „AKYTEX Exchange“** mit goldener Börsenglocke, Terminal-Pulten, Akademie, VIP-Balkon, Dachterrasse · **10 Plots** am Skyline-Ring · **Λ Motors** (Autohaus) · **Chronohaus** (Uhren) · **Marina** · **Villenhügel** mit Aussichtspunkt · **Helipad** · **Autobahnring** · Firmen-Läden, Verkehr, Drohnen, Luftschiff |
| **Markt** | 36 erfundene Firmen in 6 Sektoren + 7 ETFs (AKX36 und 6 Sektor-ETFs) + 6 Themen-Körbe + IPOs jede Saison. Eilmeldungen mit Lesefenster, Gerüchte, Quartalszahlen, 8 Analysten, Dividenden, Crash/Rally. **Alle Server sehen dieselben Kurse** |
| **Terminal** | 3 Schichten (Einfach · Trader · Profi), 7 Zeitrahmen, Kerzen/Linie/Heikin-Ashi, 9 Indikatoren, Alarm-Linien, Markttiefe (simuliert), Kalender, Heatmap. Charts mit 60 FPS |
| **Tower** | 50 Etagen in **12 Stufen** (jede mit eigener Silhouette), 11 Abteilungen, 4 Personal-Roboter + Hausmeister + Sicherheit, Raum-Stufen, Effizienz-Stufen, Tresor, Offline-Einnahmen, Aufzug, 68 Deko-Teile, 7 Fassaden, Kronen |
| **Lifestyle** | 16 befahrbare Autos (Drift, Boost, Tuning), 15 Uhren am Handgelenk, 8 Accessoires, Neon-Jetpack (Pass) |
| **Fortschritt** | Trader-Level, **10 Lizenzen** mit Prüfungen (Azubi I … Börsen-Legende), Know-how, Ruf, Titel, **Börsengang** (Prestige) mit Vorstand-Baum, Akademie (16 Lektionen), Tages-/Wochen-/Starter-Quests, 60 Erfolge, **15 Badges**, Firmen-Album, Login-Kalender, **Skyline-Pass** (50 Stufen je Saison) |
| **Sozial** | 6 Bestenlisten, Wochen-Liga nach **Skill** (Bronze/Silber/Gold/Diamant), Hall of Fame, Tower-Besuche, Respekt, Bau-Hilfe, Reaktionen ohne Chat, Freunde-Bonus, Einladen, **Voice-Chat** |
| **Events** | Welt-Event alle 20 min, Glocken-Moment und Sky-Show stündlich, Power-Hour täglich, Rally-Mittwoch, Crash-Freitag, IPO-Samstag, Admin-Abuse-Samstag (sonst automatische Samstags-Show), Bilanz-Sonntag |
| **Robux** | **14 Gamepässe**, **17 Developer Products**, Abo **„Vorstands-Club“**, Skyline-Pass Premium, private Server gratis. Alles nur Turm-Seite (CR, Boosts, Bau-Tempo, Kosmetik) |
| **Admin-Panel** | Nur für dich, **11 Reiter**: Markt-Kontrolle über alle Server, 21 Admin-Abuse-Events, Spieler, Geld & Items, Kräfte, Live-Ops, Statistik, Moderation, Debug |
| **Geräte** | PC/Mac, Handy, Tablet, Controller. Eigene Touch-Knöpfe, Terminal als Handy-Sheet |
| **Sprachen** | Deutsch und Englisch (automatisch nach Geräte-Sprache, umstellbar) |
| **Grafik** | Future-Licht, Glas/Marmor/Metall mit Spiegelungen, Bloom, Atmosphäre, Tag/Nacht alle 20 min, Markt-Wetter, automatische Grafikstufen |

---

## 3. 🎮 So spielt man

### 3.1 Der Kreislauf
1. **Eilmeldung lesen** – oben erscheint eine Karte „EILMELDUNG …“ mit einem ruhigen Balken „Händler lesen …“ (8 Sekunden).
   Wörter wie „leicht“, „deutlich“, „massiv“ sagen, wie stark sich der Kurs bewegt.
2. **Handeln** – im Terminal (**TRADE**) kaufst und verkaufst du Aktien mit **AKY** (Börsengeld). Schutz-Orders begrenzen Verluste.
3. **Gewinn-Transfer** – liegt dein Depot über deiner **Basis**, kannst du einmal je Börsentag (alle 20 min) Gewinn in den Tower
   schicken. Aus AKY werden **CR** (Turmgeld) zum **Bau-Kurs** deiner Lizenz.
4. **Bauen** – mit CR baust du Etagen, Abteilungen, Personal und Effizienz-Stufen. Der Tower verdient selbst CR (auch offline).
5. **Lizenz** – Handeln und Lernen geben Trader-XP. Mit genug XP und bestandener Prüfung steigt deine Lizenz: mehr Basis, besserer
   Bau-Kurs, neue Werte, höhere Tower-Stufen.
6. **Börsengang** – ab Etage 25 kannst du deinen Tower an die Börse bringen: Glocken-Zeremonie, Aktien-Sterne, dauerhaft mehr Einkommen,
   neue Krone. Der Tower startet neu, Depot/Lizenz/Autos/Uhren bleiben.

### 3.2 Die zwei Geldarten (ganz wichtig)

| Geld | Symbol | Woher | Wofür | Robux? |
|---|---|---|---|---|
| **AKY** (Börsengeld) | blaue Münze mit **Λ** | Start-Basis 25.000, Lizenz-Aufstieg, Handelsgewinne, Dividenden | nur Aktien kaufen | **nie** |
| **CR** (Credits, Turmgeld) | grüner Sechskant-Chip | Turm-Einkommen, Gewinn-Transfer, Quests, Events, Codes, Bau-Gutscheine | Etagen, Personal, Deko, Autos, Uhren | ja – aber **nur CR** |

Geld fließt nur **AKY → CR**, nie zurück. Darum kann niemand mit Robux Aktien, Lizenzen oder Marktwissen kaufen
(das ist die **Robux-Firewall** und die Grundlage für den Fragebogen).

### 3.3 Die Tasten

| Aktion | PC / Mac | Controller | Handy / Tablet |
|---|---|---|---|
| Laufen | **W A S D** | linker Stick | Stick links |
| Sprinten | **Shift** | linken Stick drücken (**L3**) | Stick ganz nach vorn |
| Benutzen (Tür, Pult, Kiosk) | **E** | **X** | Knopf am Objekt antippen |
| Terminal (Börse) | **T** | **Y** | großer **TRADE**-Knopf unten |
| Tower-Menü | **B** | Steuerkreuz hoch | Knopf **Tower** |
| Shop | **N** | Steuerkreuz links | Knopf **Shop** |
| Aufgaben (Quests, Login, Codes) | **J** | Steuerkreuz rechts | Knopf **Aufgaben** |
| Reaktionen (👍 🚀 📈 👏 🔔) | **R** | Steuerkreuz runter | Knopf **REAKTION** |
| Menü / Einstellungen | **M** | **Menu** (≡) | Knopf **Einstellungen** |
| Zeitrahmen im Chart | **1–7** | **LB / RB** | Segment über dem Chart |
| Chart-Typ | **C** | **View** (Select) | Knopf über dem Chart |
| Auto: Boost / Handbremse | **Shift** / **Leertaste** | **R1** / **B** | **BOOST** / **HANDBREMSE** |
| Admin-Panel (nur du) | **P** | – | Knopf **Admin** (ganz unten rechts) |
| Fliegen (nur du) | **G** | – | – |
| Zuschauen beenden (nur du) | **X** | – | – |
| Fotomodus (alle Knöpfe weg, für Screenshots) | **F7** (MacBook **fn + F7**) | – | **Einstellungen → Grafik → Fotomodus** (lang drücken beendet) |
| Debug-Anzeige (nur du) | **F8** (MacBook **fn + F8**) | – | – |

### 3.4 Die 10 Lizenzen (`Config → Progression → Licences`)

| # | Lizenz | Trader-XP | Prüfung | Basis (AKY) | Bau-Kurs (1 AKY → CR) | Turm-Bonus | schaltet Tower-Stufe frei |
|---|---|---|---|---|---|---|---|
| 1 | Azubi I | 0 | – | 25.000 | 40 | +0 % | 1–4 |
| 2 | Azubi II | 300 | Schutz-Paar setzen | 50.000 | 200 | +4 % | 5 |
| 3 | Azubi III | 1.200 | 3 Sektoren + geschützter Gewinn-Trade | 100.000 | 800 | +8 % | 6 |
| 4 | Trader I | 3.000 | „Wie erwartet“ erkennen + Kauf nach guter Nachricht | 250.000 | 1.500 | +12 % | 7–8 |
| 5 | Trader II | 7.000 | – | 600.000 | 3.000 | +16 % | 9 |
| 6 | Trader III | 14.000 | Crash mit < 10 % Verlust überstehen | 1.500.000 | 6.000 | +20 % | 10 |
| 7 | Fondsmanager I | 28.000 | Skill-Score ≥ 500 + ★★★-Analyst bei Quartalszahlen | 4.000.000 | 12.000 | +25 % | 11–12 (12 nur mit ≥ 1 Börsengang) |
| 8 | Fondsmanager II | 50.000 | – | 10.000.000 | 20.000 | +30 % | – |
| 9 | Fondsmanager III | 80.000 | Liga-Stufe Gold | 25.000.000 | 30.000 | +35 % | – |
| 10 | Börsen-Legende | 125.000 | Liga Diamant + Max. Drawdown < 8 % bei Ø ≥ +1 %/Tag | 60.000.000 | 40.000 | +40 % | – |

Prüfungen sind gratis, nach 1 Börsentag wiederholbar und **nie** mit Robux überspringbar.

### 3.5 Die 12 Tower-Stufen

| # | Stufe | Etagen | Aussehen |
|---|---|---|---|
| 1 | Garage-Startup | 1 | Rolltor, Neon „STARTUP“ |
| 2 | Kiosk-Büro | 2–3 | Markise, erstes Glas |
| 3 | Loft | 4–6 | Klinker + Glas, Dachterrasse |
| 4 | Bürohaus | 7–9 | Fensterbänder, blaues Neonband |
| 5 | Glas-Office | 10–13 | volle Glasfassade |
| 6 | Business-Tower | 14–17 | abgetreppte Krone, Dach-LED |
| 7 | Hochhaus | 18–21 | senkrechte Neon-Finnen |
| 8 | Wolkenkratzer | 22–25 | Zwillingskrone, LED-Fassaden-Ticker |
| 9 | Skyline-Tower | 26–30 | beleuchtete Turmspitze, Himmelsgarten |
| 10 | Mega-Tower | 31–36 | Helipad, Leuchtfeuer, Suchscheinwerfer |
| 11 | Hyper-Spire | 37–43 | Sky-Lounge-Ring, Holo-Bänder |
| 12 | ΛKYTEX Orbit-Spire | 44–50 | Antennen-Beam in die Wolken, Holo-Krone |

### 3.6 Die ersten 10 Minuten eines neuen Spielers
Kamera-Anflug auf den eigenen Plot → **Tiko** (geskripteter Hologramm-Roboter) erklärt → Etage 1 gratis → erstes Einsammeln am
goldenen Kassen-Tor → Übungs-Trade mit der Übungsaktie **ACAD** (+15 % in 45 s) → **Gewinn in den Tower** (≈ 15.000 CR) → Etagen 2–5
mit „Loft“-Verwandlung → erstes Personal → Hausmeister-Bot → erster echter Trade → Gratis-Auto → Börsensaal + Lektion 1 →
Lizenz Azubi II → erster Multiplikator. **In der ersten Sitzung gibt es nie ein Robux-Angebot.**

### 3.7 Kleine Wörterliste (Spiel)

| Wort | Was es heißt |
|---|---|
| **Börsentag** | 20 Minuten = ein Tag/Nacht-Zyklus. Beginnt mit der **Glocke** bei Sonnenaufgang |
| **Basis** | Grundkapital im Depot je Lizenz. Nur was darüber liegt, darfst du in den Tower schicken |
| **Bau-Kurs** | Wie viele CR du für 1 AKY bekommst. Hängt **nur** von der Lizenz ab |
| **Schutz-Paar** | Verlust-Stopp + Gewinn-Ziel zusammen („Schutz an“ = −8 % / +15 %) |
| **Multiplikator-Chip** | z. B. „x7,4“ oben links. Tippen zeigt jede Quelle (verdient, Skill, gekauft, Event) |
| **Tresor** | Sammelt das Turm-Einkommen (20 Minuten voll). Leeren am Kassen-Tor |
| **Tiko** | Der Spielhelfer (geskriptet, keine KI) |

---

## 4. 💻 Schritt 1: Programme installieren (einmal)

### 4.1 Roblox Studio
1. Öffne im Browser **roblox.com** und melde dich mit **RizzG315** an.
2. Oben auf **Create** klicken → **Start Creating** (bzw. **Download Studio**). Die Datei `RobloxStudio.dmg` landet in **Downloads**.
3. Doppelklick auf die Datei → das Installationsfenster folgen (ggf. Studio in den Ordner **Programme** ziehen).
   Fragt der Mac „… aus dem Internet geladen. Öffnen?“ → **Öffnen**.
4. Roblox Studio starten. Oben rechts muss **RizzG315** stehen. Wenn nicht: **Log In** und anmelden.

### 4.2 Das Programm „Terminal“ öffnen
**Cmd + Leertaste** drücken → `Terminal` tippen → **Enter**. Es öffnet sich ein Fenster mit Text. Hier tippst du die Befehle.

### 4.3 Rokit installieren (das Werkzeug, das Rojo installiert)
Diesen Befehl ins Terminal kopieren und **Enter** drücken:
```
curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
```
Danach das Terminal **ganz schließen** (**Cmd + Q**) und neu öffnen (4.2). Prüfen:
```
rokit --version
```
Es muss eine Versionsnummer erscheinen (z. B. `rokit 1.x.x`). Steht dort „command not found“: Mac neu starten und nochmal prüfen.

### 4.4 Rojo installieren (genau Version 7.7.1)
```
rokit add --global rojo-rbx/rojo@7.7.1
```
Fragt Rokit, ob du dem Werkzeug vertraust: `y` tippen → **Enter**. Prüfen:
```
rojo --version
```
Es muss `Rojo 7.7.1` erscheinen.

### 4.5 Das Rojo-Plugin für Studio
```
rojo plugin install
```
Danach Roblox Studio schließen (**Cmd + Q**) und neu öffnen. Oben im Reiter **Plugins** ist jetzt ein **Rojo**-Knopf.

### 4.6 Das Projekt auf deinen Mac holen
Das Spiel liegt in deinem GitHub-Repo **`website-test-demo-1`** im Ordner **`roblox-akytex-tycoon`**.
1. Öffne das Repo auf **github.com** (angemeldet). Oben links den **Branch** wählen, den Claude dir nennt.
2. Grüner Knopf **Code** → **Download ZIP**. Die ZIP-Datei landet in **Downloads**.
3. Doppelklick auf die ZIP → es entsteht ein Ordner (z. B. `website-test-demo-1-main`). Darin liegt `roblox-akytex-tycoon`.
4. Im Terminal in diesen Ordner wechseln: `cd ` tippen (mit Leerzeichen), dann den Ordner **`roblox-akytex-tycoon`** aus dem Finder
   **ins Terminal-Fenster ziehen** → **Enter**.
5. Prüfen:
   ```
   ls
   ```
   Du musst u. a. `default.project.json`, `src` und `docs` sehen.

> 💡 Profi-Weg statt ZIP: `git clone <Link zu deinem Repo>`. Beim ersten Mal fragt der Mac, ob er die „Befehlszeilen-Entwicklertools“
> installieren soll → **Installieren**. Mit Git holst du Updates später mit `git pull` (Kapitel 20, Weg C).

**Kleine Wörterliste (Werkzeuge):**

| Wort | Was es heißt |
|---|---|
| **Terminal** | Mac-Programm zum Eintippen von Befehlen (**Programme → Dienstprogramme → Terminal**) |
| **Rokit** | Installiert Roblox-Werkzeuge wie Rojo in der richtigen Version |
| **Rojo** | Baut aus den Code-Dateien eine Spiel-Datei (`.rbxlx`) oder schickt sie live ins offene Studio |
| **Plugin** | Zusatzprogramm für Studio (hier: Rojo) |
| **GitHub / Repo / Branch** | Webseite mit dem Code / der Projekt-Ordner dort / eine Version des Projekts |

---

## 5. 🚀 Schritt 2: Die Spiel-Datei holen und öffnen

Du hast zwei Wege. **Weg A** ist am einfachsten, wenn Claude die fertige Datei ins Repo gelegt hat. Sonst **Weg B**.

### Weg A: fertige Datei herunterladen
Auf GitHub im Ordner `roblox-akytex-tycoon` → Datei **`AkytexTycoon.rbxlx`** anklicken → rechts oben **Download raw file**
(Pfeil nach unten). Die Datei landet in **Downloads**.

### Weg B: Datei selbst bauen (mit Rojo)
Im Terminal (du bist im Ordner `roblox-akytex-tycoon`, Kapitel 4.6):
```
rojo build default.project.json -o AkytexTycoon.rbxlx
```
Es erscheint `Built project to AkytexTycoon.rbxlx`. Die Datei liegt jetzt im Ordner `roblox-akytex-tycoon`.

### Öffnen
1. Roblox Studio → Menüleiste **File → Open from File…** (oder **Cmd + O**).
2. Die Datei **`AkytexTycoon.rbxlx`** wählen → **Open**.
3. Du siehst eine fast leere Welt. **Das ist richtig.** Die Stadt baut der Code erst, wenn du **Play** drückst (im echten Spiel beim Serverstart).

> 💡 Öffne gleich die Fenster, die du immer brauchst: **View → Output** (Meldungen und Fehler) und **View → Explorer** (alle Teile des Spiels).

**Kleine Wörterliste (Studio):**

| Wort | Was es heißt |
|---|---|
| **`.rbxlx`** | Spiel-Datei für Roblox Studio (wie ein Dokument für Word) |
| **Place** | Eine Welt in deinem Spiel. AKYTEX TYCOON hat genau einen Place |
| **Publish** | Hochladen zu Roblox. Erst dann ist eine Änderung im echten Spiel |
| **Explorer** | Fenster mit allen Teilen des Spiels als Baum |
| **Properties** | Fenster mit den Eigenschaften des ausgewählten Teils (**View → Properties**) |
| **Output** | Fenster mit Meldungen. Rot = Fehler, Orange = Warnung |
| **Config** | Die Einstellungs-Dateien (Explorer: **ReplicatedStorage → Shared → Config**) |
| **Creator Dashboard** | Roblox-Webseite für Spiele-Macher: **create.roblox.com/dashboard/creations** |

---

## 6. 👑 Schritt 3: Admin-Panel (passiert automatisch!)

Du musst **nichts** eintragen.
- **Im echten Spiel** ist nur der Besitzer Admin: der Account, unter dem das Spiel veröffentlicht ist – also **du (RizzG315)**.
  Veröffentlichst du später unter der Gruppe „AKYTEX Games“, ist automatisch der **Besitzer der Gruppe** Admin.
- **Im Studio** bist du beim Testen Admin. Bei **Test → 2 Players** ist **Player1** Admin und **Player2 nie** (so prüfst du, dass
  normale Spieler abgewiesen werden).
- Admin kann man **nicht kaufen**. Es gibt keine Admin-Liste. Der Server prüft **jede** Admin-Aktion neu (höchstens 12 pro Sekunde).
- Öffnen: Taste **P** oder Knopf **Admin** (ganz unten in der Knopf-Leiste).

---

## 7. ▶️ Schritt 4: Testen

### 7.1 Allein testen (Play)
1. Reiter **Home** (oder **Test**) → **Play** (oder **fn + F5**).
2. Nach ca. 2 s: Meldung „**Studio: Fortschritt wird nicht gespeichert**“. **Das ist Absicht** – im Studio wird nie gespeichert.
3. Im **Output** steht nach ein paar Sekunden **`[SelfTest] n/n PASS`** (beide Zahlen gleich = alles gut). Steht da **FAIL**: Zeile
   kopieren und an Claude schicken.
4. Das Tutorial startet (in Studio jedes Mal neu, weil nichts gespeichert wird). Durchspielen oder überspringen.
5. Ohne API-Zugriff zeigt das Admin-Dashboard „**Lokaler Testmarkt**“: Der Markt läuft mit einem Test-Startwert. Völlig normal.
6. Beenden: **Stop** (oder **fn + Shift + F5**).

### 7.2 Mit 2 Spielern testen
1. Reiter **Test** → bei **Clients and Servers** „**2 Players**“ → **Start** (neue Oberfläche: Pfeil neben **Play** → **Server & Clients**).
2. Es öffnen sich 3 Fenster: **Server**, **Player1**, **Player2**. Beide Spieler sehen **dieselben Kurse**.
3. Prüfe: **Player1** hat den Admin-Knopf, **Player2 nicht**. Besuch, Respekt, Bau-Hilfe ausprobieren.
4. Beenden: im **Server**-Fenster **Cleanup** (bzw. **Stop**).

### 7.3 Handy, Tablet, Controller (Gerätesimulator)
Reiter **Test → Device** → oben ein Gerät wählen (z. B. **iPhone SE**, **iPad**, **Xbox One**) → **Play**. Zurück: nochmal **Device**.

### 7.4 Mit Lag testen
**File → Studio Settings** (Mac: **Roblox Studio → Settings…**) → **Network** → **Incoming Replication Lag** = `0.15` → **OK**.
Nach dem Test **unbedingt wieder auf `0`**.

**Die komplette Prüfliste** (über 100 Punkte, inkl. Compliance und Namens-Suche) steht in **`docs/TESTPLAN.md`**.

---

## 8. 🌍 Schritt 5: Veröffentlichen

Wichtig: Veröffentliche **zuerst eine leere Welt** und spiel **danach** AKYTEX TYCOON darüber. Dieser Weg verhindert den Fehler
„**Save failed**“ (Speichern fehlgeschlagen). Eine kleine leere Welt lädt Roblox immer problemlos hoch; danach gibt es dein Spiel
schon bei Roblox, und die große Datei ersetzt nur noch den Inhalt.

### 8.1 Leere Welt veröffentlichen
1. Studio komplett schließen (**Cmd + Q**) und neu öffnen. Oben rechts muss **RizzG315** stehen. Kommt ein Update-Hinweis: zuerst installieren.
2. Auf der Startseite: **New** → **Baseplate** (leere Welt mit grauer Platte).
3. Menüleiste: **File → Publish to Roblox** (oder **Option + P**).
4. Im Fenster:
   - Fragt Studio „neu oder vorhanden“: **Create new experience** (neues Spiel anlegen).
   - **Name:** `Akytex Tycoon` – genau so: **ohne Emoji, ohne Klammern, ohne Sonderzeichen**.
   - **Description:** leer lassen.
   - **Creator:** **RizzG315** (dein Name, **keine Gruppe**).
   - Schalter **Team Create** (bzw. **Collaboration**): **AUS**.
   - → unten rechts **Create** (bei manchen Versionen **Publish**).
5. Warten, bis unten „Published“ / „Publish completed“ steht.
6. Fragt Studio danach, ob du **Team Create** / **Collaborate** einschalten willst: **Not now** bzw. Fenster schließen.

### 8.2 AKYTEX TYCOON darüber spielen (Overwrite)
1. Baseplate schließen: **File → Close Place**. Fragt Studio nach Speichern: **Don't Save**.
2. **File → Open from File…** (**Cmd + O**) → **`AkytexTycoon.rbxlx`** → **Open**.
3. **File → Publish to Roblox As…** (oder **Shift + Option + P**). Achtung: das **„As…“** ist wichtig.
4. Im Fenster dein Spiel **„Akytex Tycoon“** anklicken (**nicht** „Create new experience“).
5. Darunter bzw. rechts erscheint der Place. Ihn anklicken (heißt „Akytex Tycoon“ oder „Start Place“).
6. Unten **Overwrite** (überschreiben) klicken. Kommt eine Frage: bestätigen.
7. Warten, bis „Published“ steht. Fertig.
8. Ab jetzt reicht für jede Änderung: **File → Publish to Roblox** (**Option + P**).

**Prüfen:** **create.roblox.com/dashboard/creations** → dein Spiel **Akytex Tycoon** → oben **View on Roblox** → grüner **Play**-Knopf.
Als Besitzer darfst du auch ein privates Spiel spielen. Die Stadt baut sich in ein paar Sekunden auf. Taste **P** öffnet das Admin-Panel.

> 💡 **„Save failed“ später bei Option + P?** Einfach 8.2 wiederholen (**Publish to Roblox As… → dein Spiel → Place → Overwrite**).

> 💡 **Klappt nicht mal die leere Baseplate?** Dann liegt es an Roblox oder am Konto: Roblox-Status prüfen (status.roblox.com),
> VPN aus, in Studio ab- und wieder anmelden (oben rechts dein Name → **Log Out**), E-Mail auf roblox.com bestätigen.
> Dann **View → Output** öffnen und den roten Text an Claude schicken.

> 💡 **Cmd + S** speichert nur die Datei auf deinem Mac. Ins echte Spiel kommt eine Änderung **nur mit Publish**.

### 8.3 Die Einstellungen (einmal machen)
Alle Punkte sind in **Home → Game Settings** (neue Oberfläche: **File → Game Settings**). Nach jedem Punkt unten rechts **Save**.

1. **Security** (Sicherheit):
   - **Enable Studio Access to API Services** = **AN** (Studio darf beim Testen Roblox-Dienste nutzen; gespeichert wird trotzdem nicht).
   - **Allow HTTP Requests** = **AUS** lassen (das Spiel ruft keine fremden Server auf).
2. **Places** → beim Place auf **⋯** → **Edit** → **Max Players** = **10** → **Save**.
   (10 Spieler = 10 Plots pro Server. Alternativ: Creator Dashboard → dein Spiel → **Places** → Place anklicken → **Max Players** = 10.)
3. **Avatar** (neue Oberfläche: Reiter **Avatar → Avatar Settings**):
   - **Avatar Type** = **R15** (R6 geht auch – Uhren sitzen bei beiden richtig).
   - **Scale** = **Standard** (keine Riesen-/Zwerg-Avatare). Rest so lassen.
4. **Communication** → Voice-Chat einschalten (**Kapitel 8.4**).
5. **Basic Info** (Grundinfos):
   - **Name:** jetzt auf **`AKYTEX TYCOON 🏙️📈 Börse & Tower`** ändern. **Description:** aus `docs/KOPIERVORLAGEN.md` Abschnitt 2.
   - **Genre:** **Simulation** (Untergenre **Tycoon**, falls angeboten).
   - **Playable Devices:** **Computer**, **Phone**, **Tablet**, **Console** an.
   - **Game Icon** und **Thumbnails** hochladen (Ideen: KOPIERVORLAGEN Abschnitt 4).
6. **Permissions → Playability**: erst **Private** lassen. Erst nach Testplan (Teil D) und Fragebogen (Kapitel 10) auf **Public**.
7. Zum Schluss nochmal **File → Publish to Roblox** (**Option + P**).

### 8.4 Voice-Chat einschalten
Das Spiel ist voice-ready: Im Börsensaal, auf der Dachterrasse und in den Tower-Lobbys trifft man sich, räumlicher Voice-Chat
(wer nah steht, ist laut). Die Spiel-Datei setzt schon `VoiceChatService.EnableDefaultVoice = true`. Zusätzlich musst du es im Spiel
freigeben:
1. **Home → Game Settings → Communication**.
2. **Microphone** (heißt je nach Version „Enable Microphone“ bzw. „Voice Chat“) = **AN**.
3. **Camera** (Gesichts-Animation) kannst du **AUS** lassen.
4. **Save** → **Publish** (**Option + P**).

Roblox entscheidet selbst, wer Voice nutzen darf (ab 13 Jahren, verifiziert). Für Kinder ist Voice automatisch aus – das Spiel
funktioniert komplett ohne Chat und Voice. Prüfen: In Studio im **Explorer** → **VoiceChatService** anklicken → **Properties** →
**EnableDefaultVoice** hat einen Haken.

### 8.5 Private Server, Premium, Regional Pricing
- **Private Server gratis** (gut für Spielen mit Freunden): Creator Dashboard → dein Spiel → **Monetization → Private Servers** →
  **Allow Private Servers** an → Preis **Free** → **Save**. (Nach ca. 60 Tagen kannst du 99 R$/Monat überlegen.)
- **Roblox Premium:** Premium-Spieler bekommen im Spiel Einkommen ×1,10; du bekommst automatisch **Premium Payouts** für ihre Spielzeit.
- **Regional Pricing:** Bietet Roblox bei Pässen/Produkten **Regional Pricing** an: einschalten.

---

## 9. 💰 Schritt 6: Robux – Pässe, Produkte, Abo, Badges

Im Spiel sind alle Pässe und Produkte schon eingebaut. Roblox muss sie nur noch kennen. Dafür legst du sie im **Creator Dashboard**
an; jedes bekommt eine **ID**. Solange eine ID fehlt (`Id = 0`), zeigt der Shop „**Bald verfügbar**“ – das Spiel läuft trotzdem.
**Alle Texte, Preise und Icon-Ideen: `docs/KOPIERVORLAGEN.md`.**

### 9.1 Die Preise (stehen so in `Config → Shop`)

| Gamepass | Preis | | Developer Product | Preis |
|---|---|---|---|---|
| Börsen-VIP | **399 R$** | | Boost x2 · 30 min | **49 R$** |
| x2 Einnahmen | **499 R$** | | Boost x2 · 2 h | **149 R$** |
| x3 Einnahmen | **1.199 R$** | | Turbo x5 · 10 min | **99 R$** |
| Auto-Kassierer | **249 R$** | | Bullen-Parade (ganzer Server) | **199 R$** |
| Offline-Tresor 24 h | **349 R$** | | Bau-Gutschein S / M / L / XL | **49 / 149 / 399 / 899 R$** |
| Personal+ | **299 R$** | | Bau-Express S / M / L | **19 / 39 / 79 R$** |
| Bau-Crew Pro | **399 R$** | | Feuerwerk über deinem Tower | **29 R$** |
| Terminal-Designer ⏸ | **249 R$** (noch gesperrt, siehe unten) | | Starter-Paket (1× je Konto) | **99 R$** |
| Mega-Garage | **199 R$** | | Skyline-Pass Premium (je Saison) | **399 R$** |
| Neon-Jetpack | **449 R$** | | +1 / +10 Pass-Stufen | **39 / 299 R$** |
| ΛKYTEX Λ-1 Hypercar | **799 R$** | | Geschenk-Boost | **59 R$** |
| Chrono-Kollektion | **349 R$** | | | |
| Neon-Fassaden-Kit | **349 R$** | | **Abo „Vorstands-Club“** | **4,99 $** (Landeswährung, wenn ID-verifiziert) sonst **449 R$/Monat** |
| Tycoon-Paket | **749 R$** (einzeln 1.097 R$) | | | |

> ⏸ **Terminal-Designer** jetzt noch **nicht** anlegen: Die Terminal-Themes gibt es noch nicht im Spiel. Der Pass steht in
> `Config → Shop → Shop.Disabled` auf gesperrt (Shop zeigt „Gerade nicht verfügbar“). Erst wenn Claude die Themes eingebaut hat,
> anlegen und die Sperre entfernen – nie einen Pass ohne Wirkung verkaufen. Die anderen **13 Pässe** kannst du sofort anlegen.

### 9.2 Gamepässe anlegen (14 Stück, einmal kaufen = für immer – Terminal-Designer erst später)
1. **create.roblox.com/dashboard/creations** → dein Spiel **Akytex Tycoon** anklicken.
2. Links: **Monetization → Passes → Create a Pass** (ältere Ansicht: **Associated Items → Passes**).
3. **Bild** hochladen (512 × 512), **Name** und **Beschreibung** (Englisch) aus KOPIERVORLAGEN einfügen (**Cmd + V**) → **Create Pass**.
4. Den neuen Pass anklicken → links **Sales** → **Item for Sale** an → **Preis** eintippen → **Save Changes**.
   (Fragt Roblox den Preis schon beim Erstellen: gleich dort eintragen.)
5. ID holen: beim Pass auf **⋯** → **Copy Asset ID**. Steht das nicht da: In der Adresszeile vom Browser stehen zwei lange Zahlen –
   die **zweite** ist die Pass-ID.

### 9.3 Developer Products anlegen (17 Stück, beliebig oft kaufbar)
1. Dein Spiel → links **Monetization → Developer Products → Create a Developer Product**.
2. Bild, Name, Beschreibung, Preis eintragen → **Create Developer Product**.
3. ID holen: beim Produkt auf **⋯** → **Copy Product ID** (oder **Copy Asset ID**).

### 9.4 Abo „Vorstands-Club“ anlegen (Experience Subscription)
1. Dein Spiel → links **Monetization → Subscriptions** → **Create Subscription**.
2. Name `Executive Club`, Beschreibung und Bild aus KOPIERVORLAGEN Abschnitt 7.
3. Preis: **4,99 $** in Landeswährung (geht nur mit ID-verifiziertem Konto) – sonst **449 Robux** pro Monat → **Create**.
4. ID holen: beim Abo **⋯** → **Copy Subscription ID**. Sie beginnt mit **`EXP-`**.
5. Gibt es den Menüpunkt **Subscriptions** bei dir noch nicht (Roblox schaltet Abos nicht für jedes Konto frei): überspringen. Der Shop
   blendet den Club dann automatisch aus bzw. zeigt „Bald verfügbar“.
6. Nie „PRO“ nennen (echter AKYTEX-Tarif).

### 9.5 Badges anlegen (15 Stück)
1. Dein Spiel → links **Engagement → Badges → Create a Badge** (ältere Ansicht: **Associated Items → Badges**).
2. Bild (512 × 512, wird rund zugeschnitten), Name, Beschreibung aus KOPIERVORLAGEN Abschnitt 10 → **Create**.
3. ID holen: beim Badge **⋯ → Copy Asset ID**.
4. **Kosten:** Roblox erlaubt pro Tag nur wenige Badges gratis; danach kostet jedes Badge Robux (der Betrag steht beim Anlegen).
   Lege sie über mehrere Tage an. Fehlende Badges (`Id = 0`) sind einfach aus; trägst du eine ID später ein, bekommen Spieler das
   Badge beim nächsten Beitritt **rückwirkend**.

### 9.6 IDs eintragen
**Am einfachsten:** Ganz unten in **`docs/KOPIERVORLAGEN.md`** (Abschnitt 13) den Kasten **„Schick mir das zurück“** ausfüllen und in den
Chat kopieren. Claude trägt alles ein und baut dir eine neue `AkytexTycoon.rbxlx`.

**Selbst eintragen geht auch:**
1. Explorer: **ReplicatedStorage → Shared → Config → Shop** doppelklicken.
2. **Cmd + F** → nach dem Key suchen, z. B. `Key = "VIP"`. In der Zeile direkt darunter steht `Id = 0,`.
3. Die `0` durch deine ID ersetzen (nur die Zahl, ohne Anführungszeichen, das Komma bleibt): `Id = 1234567890,`.
4. **Abo:** **Cmd + F** → `Shop.Subscription` → Zeile `Id = "",` → **mit** Anführungszeichen: `Id = "EXP-1234567890123456789",`.
5. **Badges:** **Config → Progression** doppelklicken → **Cmd + F** → `Key = "Welcome"` → in derselben Zeile `Id = 0` → `Id = 1234567890`.
6. **Play** → im Output darf keine orange Zeile mit `[Config]` stehen (sonst Tippfehler) → Shop zeigt statt „Bald verfügbar“ den Preis.
7. **Publish** (**Option + P**).

> ⚠️ Preise änderst du im **Creator Dashboard** – der Shop zeigt immer den echten Live-Preis von Roblox. Trag einen neuen Preis
> zusätzlich bei `Price` in `Config → Shop` ein (nur Planwert für Prüfungen und die Rabatt-Anzeige).

> 💡 **Testkauf:** Mit eingetragener ID und API-Zugriff kannst du in **Studio** kaufen – Roblox zeigt dann „Testkauf, dein Konto
> wird nicht belastet“. Ohne ID: Admin-Panel → **Debug → Kauf simulieren** (gleicher Weg wie ein echter Kauf, kostet nichts).

### 9.7 Das Fair-Versprechen (eingebaut, bitte so lassen)
- Robux kaufen **nur**: Turm-Einkommens-Multiplikatoren, CR-Gutscheine, Bau-Tempo, Komfort im Turm, Kosmetik, Server-Party,
  Saison-Premium, Abo. **Nie**: AKY, Aktien, IPO-Zuteilung, News/Insider-Vorlauf, Alarme, Watchlists, Indikatoren, Lizenz,
  XP, Know-how, Ruf, Aktien-Sterne, Strategie-Bots, Zufallsbelohnungen, Admin-Kräfte, Serien-Retter.
- **x2 + x3 zusammen = x4** (nicht x6) – steht vor dem Kauf im Shop.
- Höchstens **1 Angebots-Popup pro Besuch**, **nie** in der ersten Sitzung, nur nach einem schönen Moment (Stufen-Verwandlung),
  nie während Tutorial, Crash/Rally-Warnung, offenem Terminal oder Admin-Abuse. Knöpfe „Ansehen“/„Details“ – nie „JETZT KAUFEN“.
- Bau-Gutscheine zeigen die **exakte CR-Zahl** vor dem Kauf (Angebot 10 min gültig).
- Bezahlte Käufe werden **nie doppelt und nie gar nicht** gutgeschrieben (jeder Beleg wird gespeichert).

### 9.8 Auszahlung in echtes Geld (DevEx)
Ab 13 Jahren, verifizierte E-Mail und Ausweis, Mindestbetrag laut Roblox. Infos: Creator Dashboard → **DevEx**
(**create.roblox.com/dashboard/devex**).

---

## 10. 📋 Schritt 7: Der Roblox-Fragebogen (Ziel: Minimal)

Bevor dein Spiel **öffentlich** wird, will Roblox wissen, was drin ist. Daraus wird das Alters-Label.
Ziel ist **Minimal** – dann darf das Spiel in **Roblox Kids** (5–8), **Roblox Select** (9–15) und im normalen Roblox laufen.

> ⚠️ **Lies vor dem Ausfüllen den Live-Wortlaut** der Fragen und der Roblox-Regeln (Community Standards zum Thema Glücksspiel,
> Advertising Standards zu Finanzdiensten). Roblox ändert Fragen manchmal. Weicht eine Frage von dieser Liste ab: Claude fragen.

1. **Creator Dashboard** → dein Spiel → links **Audience** → **Maturity & Compliance** (heißt manchmal **Experience Questionnaire**).
2. Fragebogen starten und **ehrlich** antworten:

| Frage | Antwort | Warum |
|---|---|---|
| Gewalt / Blut / Angst / derber Humor / starke Sprache / Romantik / Alkohol | **Nein** | Crash-Effekte treffen nie Avatare; Bulle und Bär sind freundliche Figuren; der Raum heißt „Smoothie-Café“ |
| **Unplayable gambling content** (nur gezeigtes Glücksspiel) | **Nein** | keine Casino-, Karten-, Würfel-, Slot- oder Glücksrad-Darstellung, keine Glücksspiel-Wörter |
| Social Hangout als Hauptfokus | **Nein** | Tycoon-Spiel |
| Free-form user creation (freies Bauen/Texte) | **Nein** | Deko nur in festen Plätzen aus Vorlagen, Namen aus Wortbausteinen; der 4-Buchstaben-Ticker beim Börsengang wird von Roblox gefiltert |
| Sensible Themen / Medien / endlose Feeds / Inhalte anderer Spiele | **Nein** | News-Liste endlich (max. 50), keine Auto-Play-Feeds |
| **Paid random items** (bezahlte Zufallsartikel) | **Nein** | alles ist genau festgelegt, keine Kisten (der Policy-Schutz ist trotzdem eingebaut) |
| **Paid item trading** (Handel mit bezahlten Items) | **Nein** | kein Spielerhandel; der Geschenk-Boost ist zusätzlich gesperrt, wo Roblox Geschenke verbietet |
| Generative KI | **Nein** | Tiko ist vollständig geskriptet |
| Text-Chat | Ja, normaler Roblox-Chat (TextChatService, von Roblox gefiltert) | |
| Voice-Chat | Falls gefragt: **Ja**, Roblox-Standard (nur berechtigte, verifizierte Spieler ab 13) | |

3. Ergebnis sollte **Minimal** sein.
4. Danach **Home → Game Settings → Permissions → Playability = Public** (wenn der Testplan erledigt ist).
5. **Nach jeder Änderung, die eine Antwort ändert** (z. B. neue Inhalte), den Fragebogen neu ausfüllen.

**Warum der Markt kein Glücksspiel ist** (für eine Rückfrage von Roblox): Man kauft Anteile zum angezeigten Preis und verkauft, wann
man will – kein Einsatz, keine Auszahlung, keine Quoten, kein Hebel. Große Bewegungen kommen nur aus vorher lesbaren Nachrichten und
Terminen. Im Test verlieren Zufalls-Trader im Schnitt (−0,35 % je Börsentag), informierte Spieler gewinnen (+5,2 … +7,7 %).
Robux können nichts kaufen, was vom Markt abhängt.

---

## 11. 🧒 Roblox Kids & Roblox Select freischalten

Mit dem Label **Minimal** kann AKYTEX TYCOON in **Roblox Kids** (5–8 Jahre) und **Roblox Select** (9–15 Jahre) erscheinen.
Roblox verlangt dafür (Stand 2026, Live-Wortlaut im Creator Dashboard prüfen):

| # | Voraussetzung | So geht's |
|---|---|---|
| 1 | Dein Konto ist **alters-geprüft / verifiziert** | roblox.com → **Einstellungen** (Zahnrad) → **Account Info** → **Verify My Age** (Ausweis + Selfie) |
| 2 | **2-Schritt-Bestätigung (2FA)** ist an | roblox.com → **Einstellungen → Security** → **2-Step Verification** → Authenticator-App einschalten |
| 3 | **Kompletter Fragebogen** | Kapitel 10 |
| 4 | **Roblox Plus/Premium seit mindestens 2 Monaten** **oder** eine **rückzahlbare Gebühr** | Premium auf roblox.com abonnieren – oder die angezeigte Gebühr zahlen |
| 5 | **Freigabe nach Spielern:** „250 unique plays by highly engaged age-checked users within a 60-day window“ (250 verschiedene, alters-geprüfte, aktive Spieler in 60 Tagen) | passiert durch normales Spielen |
| 6 | Optional: **Express-Prüfung** gegen 50.000 R$ (rückzahlbar) | statt Punkt 5 |

Wo? Creator Dashboard → dein Spiel → **Audience** (dort, wo der Fragebogen ist) → Bereich **Roblox Kids / Roblox Select** (Name kann
abweichen). Das Spiel ist dafür gebaut: alles Soziale funktioniert **ohne Chat** (Reaktionen, Respekt, Bau-Hilfe), denn bei Kindern
ist der Chat standardmäßig aus.

---

## 12. ™️ Marke AKYTEX: was nie ins Spiel und nie auf die Spielseite darf

AKYTEX ist im Spiel **nur eine Spielmarke** (Name, Look, die fiktive Börse). Das schützt dich vor dem Vorwurf „Finanzwerbung an Kinder“.

**Erlaubt:** „AKYTEX TYCOON“, Wortmarke **ΛKYTEX**, die Farben/Schriften der Website, „**AKYTEX Exchange**“, Index **AKX36**,
**ΛKYTEX Terminal**, „Markets move. Ideas stay.“, „CAPITAL BUILDS TOMORROW“.

**Verboten (im Spiel, auf der Spielseite, in Bildern, in Event-Texten):**
- URL, QR-Code, „App“, „Website“, „Demo-Depot“, „echtes Trading“, Broker, KYC, Euro-Preise
- Tarifnamen der Website (Free, Plus, Pro, Elite, Ultra), „AKYTEX AI“, **„Aky“** (der Spielhelfer heißt **Tiko**), **„NOVA“**
- Gründernamen, Adressen, „3 Minuten am Tag. Ein Leben lang reicher“ (Geld-Versprechen)
- eine **handelbare AKYTEX-Aktie** oder NOVA als Firma (deshalb heißen die Firmen 1 und 2 „Cognivo KI“ und „Kernwerk Systems“)
- ein Abo namens „PRO“ (deshalb „Vorstands-Club“)

**Kanäle trennen:** Lege eigene Social Links **„AKYTEX Games“** (Discord, YouTube) für deine Roblox-Spiele an. Die AKYTEX-Finanzkanäle
bleiben für Erwachsene. Die Website darf auf das Spiel verlinken, aber **nie** neben Broker-, KYC- oder Abo-Knöpfen. Keine Daten über
Spieler sammeln. Tipp: Die Wortmarke „AKYTEX“ auch für Spiele/Unterhaltung anmelden (Rat beim Markenanwalt einholen).

**Werbung für AKYTEX im Spiel** (falls du das je willst): nur als registrierte, gekennzeichnete Roblox-Ad-Integration – Roblox lehnt
Finanzprodukte dort sehr wahrscheinlich ab. Im Spiel nur der Satz „Unsere Social-Links findest du auf der Spielseite“.

---

## 13. 📈 Spieler finden

Die Technik ist für viele Spieler gebaut. **Ob viele kommen, hängt vom Auftritt und vom Roblox-Algorithmus ab** – das kann niemand
garantieren. Was am meisten hilft:

1. **Titel und Beschreibung** aus KOPIERVORLAGEN (Abschnitt 1 + 2). Kein Geld-Wort im Titel. In Saisons `[S1] …` davor.
2. **Icon und Thumbnails** (KOPIERVORLAGEN Abschnitt 4): Skyline bei Nacht, Terminal mit Eilmeldung, Hypercar, Glocken-Zeremonie.
   Für saubere Bilder: Taste **F7** (Fotomodus, versteckt alle Knöpfe; als Admin auch **Kräfte → Show-Kamera**), dann am Mac **Cmd + Shift + 4** und einen Bereich aufziehen.
3. **Die ersten Minuten:** Das Tutorial bringt den ersten Gewinn in den Tower in ca. 2 Minuten – perfekt für die Spielzeit-Werte.
4. **Experience Events** für jeden festen Termin (Kapitel 15) – Spieler können „Benachrichtigen“ drücken.
5. **Codes** für deine Kanäle (Kapitel 17): `LAUNCH` = 5.000 CR, läuft am 31.01.2027 (0:00 UTC) ab.
6. **Admin-Abuse jeden Samstag 18:00** vorher ankündigen (Post-Vorlagen: KOPIERVORLAGEN Abschnitt 9).
7. **TikTok / YouTube Shorts:** Börsengang-Zeremonie, Crash-Freitag mit Bär, Hypercar auf dem Autobahnring, Orbit-Spire bei Nacht.
8. **Roblox-Werbung** (Ads Manager auf **ads.roblox.com**): mit kleinem Budget testen, wenn die Spielzeit pro Spieler gut ist.
9. **Gruppe „AKYTEX Games“**: Wer beitritt, bekommt im Spiel die **Community-Krone** und einen blauen **Namensschild-Rahmen** (nur
   Kosmetik, kein Einkommen). **Einrichten (einmal):**
   1. **roblox.com** → links **Communities** (früher „Groups“) → **Create Community** → Name `AKYTEX Games` → Bild → **Create**
      (Roblox verlangt dafür einmalig Robux; der Betrag steht im Fenster).
   2. Die Gruppe öffnen. In der Adresszeile steht `roblox.com/communities/`**`12345678`**`/AKYTEX-Games` – die Zahl ist die **Gruppen-ID**.
   3. ID an Claude schicken (KOPIERVORLAGEN Abschnitt 13, Zeile `GroupId =`) **oder selbst eintragen:** Explorer → **Config → Progression**
      → **Cmd + F** → `GroupId = 0` → `GroupId = 12345678` → **Play** → **Publish**.
   4. Ab dann gibt es im Spiel **Sozial → Einladen → „Gruppe beitreten“** (Roblox-Fenster). Die Krone kommt nach dem Beitritt
      innerhalb von ca. 2 Minuten – ohne neu beitreten zu müssen.
10. **Teilen-Links mit Tower-Besuch:** Der Knopf **„Freunde einladen“** (Sozial → Einladen) schickt automatisch die Info „besuche den
    Tower von …“ mit. Nimmt dein Freund die Einladung an, landet er auf deinem Server und – nach seinem Tutorial – direkt in deiner
    Tower-Lobby. Für deine Kanäle geht dasselbe als Link (nur sinnvoll, wenn der Freund auf **deinem** Server landet, z. B. in deinem
    Private Server):
    ```
    https://www.roblox.com/games/start?placeId=DEINE-PLACE-ID&launchData=visit%3ADEINE-USERID
    ```
    **Place-ID:** Creator Dashboard → dein Spiel → **Places** → Place anklicken → Zahl in der Adresszeile. **UserId:** dein Profil auf
    roblox.com → Zahl in der Adresszeile (`roblox.com/users/`**`123456`**`/profile`). Ist der Tower-Besitzer gerade nicht auf dem Server,
    sagt das Spiel das freundlich und der Spieler startet normal.

**Eingebaut (du musst nichts tun):** Einladen-Knopf mit Belohnung für beide, sobald der Eingeladene wirklich spielt (Etage 10 + 10 min,
max. 10 je Woche) und mit Tower-Besuch (Punkt 10) · Freunde-Bonus · Favoriten-Abfrage einmal je Konto (nach dem Tutorial; wer das
Tutorial überspringt, bekommt sie nach seiner ersten Lizenz-Zeremonie) · Benachrichtigungs-Zustimmung einmal nach einem schönen Moment
(Tutorial-Ende oder Lizenz-Zeremonie; Senden von Benachrichtigungen kommt erst in v1.1) · Bestenlisten-Tafeln im Börsensaal zeigen
die Spieler auf dem Server live (alle 15 s) zusammen mit der globalen Top-Liste.

> ⚠️ Roblox-Regel: **Keine Belohnungen für Likes, Favoriten oder Gruppen-Beitritte außerhalb der eingebauten Funktionen**, keine
> Druck-Sprüche („Nur heute!“) für Robux-Artikel.

---

## 14. 🛠️ Admin-Panel-Tour & Samstags-Ablauf

Öffnen mit **P** oder dem Knopf **Admin**. Fenster im AKYTEX-Dashboard-Look mit Seitenleiste und **11 Reitern**.
- **Ziel-Feld:** Wen eine Aktion trifft: `me` (du), `all` (alle), `others` (alle außer dir), ein Name, der Anfang eines Namens oder eine UserId.
- **Gefährliche/globale Aktionen** brauchen eine **Bestätigung innerhalb von 5 Sekunden**. Markt-Aktionen haben 3 s Abklingzeit.
- **Jede Aktion wird protokolliert** (Reiter **Moderation**, letzte 500).

| Reiter | Was du dort machst |
|---|---|
| **Dashboard** | Spieler online (Server + geschätzt global), aktive Events, Markt-Regime, Bus-Status (erreichen sich die Server?), Server-Last, Banner „Lokaler Testmarkt“ im Studio |
| **Spieler** | Liste + Ziel-Feld, **Kick**, **Bann** (1 h / 1 Tag / 7 Tage / 30 Tage / für immer, Grund ≤ 400 Zeichen + privater Vermerk, gilt fürs ganze Spiel), **Unbann**, Bann-Liste/-Verlauf, **Verwarnen**, **Einfrieren**, **Herholen/Hingehen**, **Zuschauen** (Ende mit **X**), **Spielerdaten**, **Belege + Kauf nachliefern**, **Daten zurücksetzen** (Kauf-Belege bleiben) |
| **Markt** | **Crash/Rally**, Firma **pushen/abstürzen**, **Admin-Eilmeldung**, **Pause/Weiter**, **IPO starten**, **Volatilität**, **Normalisieren**, Event-Log mit Admin-Fenstern. **Markt-Events gelten immer auf allen Servern** |
| **Events** | Admin-Abuse-Katalog (21 Events), **Ansage** lokal/global (mit deinem Avatar, blauem Namen und selbst gezeichnetem blauem Haken, ca. 8 s, gefiltert), **Samstags-Show-Knopf**, Vorschau des Live-Ops-Kalenders |
| **Geld & Items** | CR, Items, Etagen, Abteilungen, Personal, Deko, Autos, Uhren, Lizenz-Stufe, Saison-Stufen geben (`me`/`all`/…), **„AKY geben“** (erhöht die Basis mit). AKY- und Lizenz-Gaben nehmen den Empfänger diese Woche aus der Liga |
| **Kräfte** | Fliegen (**G**), Noclip, Speed, Unsichtbar, **Fotomodus**, jeden Tower besuchen (auch private Etagen), **Show-Kamera** (Kino für Streams), Umrisse durch Wände (max. 20) |
| **Welt** | Tageszeit-/Wetter-Vorschau (nur bei dir), Verkehrsdichte, Welt-Event jetzt starten (nur dieser Server) |
| **Live-Ops** | Live-Werte ohne neue Datei ändern (News-Takt, Event-Rotation, Boost-Werte, Codes), **Notschalter** (Produkt sperren, Boosts pausieren, Wartungs-Banner) – Liste: `docs/LIVEOPS.md` Abschnitt 6–7 |
| **Statistik** | Online, CR-/AKY-Geldmenge, meistgehandelte Werte, Orders je Minute, Prüf-Abweichungen, Käufe/Robux 24 h, Top-Quellen/-Senken, verdächtige Spieler |
| **Moderation** | Anti-Cheat-Hinweise, Meldungen, Verwerfen, Bann-Log, Admin-Log |
| **Debug** | **Tag überspringen**, **Kauf simulieren**, **Policy simulieren**, Debug-Schalter, **Selbsttest starten**, **F8**-Anzeige, Crash-Freitag-Probe (lokal) |

**Niemals möglich:** dich selbst oder den Besitzer bannen, Test-Spieler im Studio bannen (keine echte UserId), Spielern etwas
wegnehmen per Event, Käufe verändern.

### 14.1 Fairness-Schutz (automatisch)
- Jedes Markt-Event von dir wird **10 s vorher auf allen Servern angekündigt** und öffnet ein **Admin-Fenster** (bis 10 min nach dem
  Abklingen). Alle sehen den Chip „**ADMIN-ABUSE aktiv – zählt nicht für die Liga**“. Trades in dieser Zeit zählen nicht für Liga/Skill-Score.
- **Deine eigenen Trades** sind 120 s vor und nach deinen Markt-Events gesperrt, und du zählst nie für die Liga.

### 14.2 Samstags-Ablauf (Kurzfassung – ausführlich in `docs/LIVEOPS.md` Abschnitt 3)

| Uhrzeit (Berlin) | Was |
|---|---|
| 16:00 | Wochen-Update veröffentlichen (Kapitel 20), falls es eins gibt |
| 17:00 | IPO-Erstnotiz läuft automatisch |
| vorher | Auf deinen Kanälen ankündigen: „Heute 18:00 Admin-Abuse!“ |
| 17:55 | Ins Spiel, **P** → Reiter **Dashboard**: Bus-Status ok? |
| 18:00–18:14 | Show starten: **Events → Samstags-Show (1 Klick)** oder eigene Mischung (Mega-Rally, Geldregen, Golden Hour, Boss-Auftritt, Feuerwerk). **Damit fällt die Automatik-Show aus.** |
| bis 19:00 | Show durchziehen, Ansagen machen |
| danach | **Markt → Normalisieren**, falls noch etwas läuft |
| Du bist nicht da? | Um **18:15** startet die **automatische Samstags-Show** (Banner → Golden Hour ×2 30 min → Rally +15 % Sektor der Woche → Geldregen → Feuerwerk) |

---

## 15. 🗓️ Live-Ops-Kalender & Experience Events

### 15.1 Was automatisch passiert (Berlin-Zeit, Sommer-/Winterzeit stellt sich selbst um)

| Wann | Event |
|---|---|
| alle 20 min | **Glocke** (Gewinn-Transfer wieder frei), Quartalszahlen, **Welt-Event** um :10 (Geldtransporter → Drohnen → Bau-Boom → Pressekonferenz), Dividenden um :19 |
| stündlich | **Glocken-Moment** (hh:00, ≥ 3 Spieler an der Glocke → ×1,2 für 5 min), **Sky-Show** (hh:15) |
| täglich 19:00 | **Power-Hour** (Trader-XP ×2, 60 min) |
| Mi 19:00 | **Rally-Mittwoch** |
| Fr 19:00 | **Crash-Freitag** + Bär-Event |
| Sa 16:00 | Wochen-Update (**du**) |
| Sa 17:00 | **IPO-Erstnotiz** |
| Sa 18:00 / 18:15 | **Admin-Abuse** mit dir / sonst **automatische Samstags-Show** |
| So 20:00 | **Bilanz-Sonntag** (Liga-Finale, Top-10-Hologramme) |
| Mo 00:00 UTC | neue Woche (Markt-Seed, Liga) |

Details, IPO-Termine, Saisons und Notschalter: **`docs/LIVEOPS.md`**.

### 15.2 Experience Events auf der Spielseite eintragen
1. **Creator Dashboard** → dein Spiel → links **Engagement → Events** (heißt je nach Version auch **Events and Updates**).
2. **Create Event** (bzw. **Create**).
3. **Titel** und **Beschreibung** aus `docs/KOPIERVORLAGEN.md` Abschnitt 8 (Englisch; Deutsch unter Localization).
4. **Start** und **Ende** einstellen (das Dashboard zeigt deine Ortszeit – also Berlin-Zeit eintragen), z. B. Fr 19:00–19:30 für Crash-Freitag.
5. **Kategorie/Typ** passend wählen (z. B. „Live Event“), **Thumbnail** 1920 × 1080 hochladen.
6. **Publish** / **Schedule**.
7. Für die **nächsten 4 Wochen** anlegen; einmal im Monat ergänzen (Liste: LIVEOPS Abschnitt 5).

---

## 16. 🆕 Neue Saison anlegen (über Config)

Saison 1 **„Neon-Skyline“** läuft vom **12.10.2026** bis **09.11.2026** (je Saison 4 Wochen, Skyline-Pass mit 50 Stufen à 1.000 Saison-XP).
Keine Panik: Trägst du keine neue Saison ein, startet automatisch „Saison 2, 3, …“ mit den Belohnungen der letzten Saison
(`Season.Rolling`, 28 Tage). **Das Spiel funktioniert immer.**

1. Explorer: **ReplicatedStorage → Shared → Config → Season** doppelklicken.
2. **Cmd + F** → `Season.Seasons`. Den Block von Saison 1 markieren: von der Zeile `{` direkt über `Id = 1,` bis zur passenden
   Zeile `},` (unter `ImageId = 0,`). **Cmd + C**.
3. Direkt unter diesem `},` einfügen (**Cmd + V**). Im neuen Block ändern:
   - `Id = 2,` und `Key = "S2",` (**jede Saison bekommt eine neue Zahl, nie eine alte wiederverwenden!**)
   - `Name = { de = "Raumfahrt-Rallye", en = "Space Rally" },` (Themen-Ideen: LIVEOPS Abschnitt 4)
   - `StartUtc = "2026-11-09T00:00:00Z",` und `EndUtc = "2026-12-07T00:00:00Z",` (Start = Ende der letzten Saison, 4 Wochen).
     Format genau so: Jahr-Monat-Tag, dann `T00:00:00Z`. Die Zeit ist UTC (Deutschland: Winter +1 h, Sommer +2 h).
   - `Tiers = 50,` und `TierXp = 1000,` so lassen.
   - `Free = FREE_S1,` / `Premium = PREMIUM_S1,`: Du kannst dieselben Belohnungen behalten. Für **neue** Belohnungen (neues Deko-Set,
     neues Auto, neue Fassade) braucht es Code → Claude fragen. Erlaubt in Belohnungen sind nur: `Credits`, `Decor`, `Cosmetics`,
     `Watches`, `Cars`, `Accessories`, `BoostX2`, `InstantTokens`, `Title` – **nie** AKY, XP, Lizenz (der Selbsttest meldet Verstöße).
   - `ImageId = 0,` (oder dein Saison-Bild, ASSET-LISTE 5.7).
4. **Play** → Output: `[SelfTest] … PASS` und keine orangen `[Config]`-Zeilen. Sonst korrigieren oder an Claude schicken.
5. **Publish**. Titel auf `[S2] AKYTEX TYCOON 🏙️📈 Börse & Tower` ändern, Experience Event „Saison-Start“ anlegen.

Das Produkt **Skyline-Pass Premium** bleibt dasselbe und gilt automatisch für die aktive Saison – bei Roblox musst du nichts Neues anlegen.
**IPO-Firmen** für die neue Saison (IDs ab 104, nie wiederverwenden) legt Claude in `Config → Companies` und `Config → Market` an.

---

## 17. 🎟️ Codes

Codes geben **nur CR oder Kosmetik** (nie AKY, XP oder Lizenz). Eingelöst wird im Spiel: **Aufgaben** (**J**) → Reiter **Login** → Code
eintippen → **Einlösen**. Jeder Spieler kann jeden Code nur einmal einlösen.

**Vorhanden:** `LAUNCH` = **5.000 CR**, läuft am **31.01.2027** ab.

**Neuen Code anlegen – live (ohne neue Datei, empfohlen):** Admin-Panel → **Live-Ops** → `Rewards.Codes.<DEINCODE>` → Belohnung
(höchstens 1.000.000 CR) und Ablaufdatum → **Speichern**. Gilt sofort auf allen Servern.

**Dauerhaft in der Datei:** Explorer → **Config → Rewards** → **Cmd + F** → `Rewards.Codes` → unter der Zeile mit `LAUNCH` eine neue Zeile:
```lua
	SKYLINE = { Grant = { Credits = 10000 }, Expires = "2027-03-01T00:00:00Z" },
```
Regeln: Code in **GROSSBUCHSTABEN**, nur Buchstaben/Ziffern/`_`, höchstens 20 Zeichen; `Grant` nur `Credits` (ganze Zahl) oder
`Cosmetics`; `Expires` im Format oben (oder weglassen = läuft nie ab). Dann **Play** → **Publish**.

> 💡 `Config` wird an alle Spieler geschickt. Codes sind also öffentlich – leg nie einen „geheimen“ Code für dich allein an.

---

## 18. 🎨 Eigene Assets (Hybrid) mit Higgsfield

Das Spiel sieht ohne hochgeladene Dateien fertig aus. **Jedes** sichtbare Objekt mit Upgrade-Potenzial (Autos, Uhren, Deko, Roboter,
Kronen, Brunnen, Glocke, Luftschiff, Bulle, Bär, Firmen-Logos, Lizenzkarten, Sounds, Musik …) hat in `Config` einen **Asset-Platz**.
`0` = Code-Rezept. Trägst du eine ID ein, nimmt das Spiel dein Modell/Bild/deinen Sound – lädt es nicht, automatisch wieder das Rezept.

**Der Weg in Kurzform** (ausführlich mit allen Plätzen, Größen und Prompts: **`docs/ASSET-LISTE.md`**):
1. Platz in der ASSET-LISTE aussuchen (Empfehlung: Glocke, Brunnen, Luftschiff, Gratis-Auto, Tiko zuerst).
2. In **Higgsfield** erzeugen (Prompt-Grundlage + Motiv aus der Liste). 3D als **GLB**, Bilder als **PNG**, Sounds als **OGG/MP3**.
3. Prüfen: keine echten Marken, nichts mit Casino/Würfeln/Waffen/Alkohol, AKYTEX-Look.
4. In Studio hochladen: 3D über **File → Import 3D…** (MeshPart anklicken → **Properties** → Zahl bei **MeshId**/**TextureID** kopieren);
   Bilder und Sounds über **View → Asset Manager → Bulk Import** → Rechtsklick → **Copy ID to Clipboard**.
5. ID an Claude schicken (Kasten in ASSET-LISTE Abschnitt 9) oder selbst eintragen (ASSET-LISTE Abschnitt 3).
6. **Play** → ansehen → **Publish**.

**Besitzrechte:** Assets müssen dem Spiel-Ersteller gehören – lade alles mit **RizzG315** hoch (bzw. in die Gruppe, falls das Spiel
später der Gruppe gehört). Prüfe in deinem Higgsfield-Abo, dass **kommerzielle Nutzung** erlaubt ist. Roblox prüft jedes Asset
(Moderation); bis zur Freigabe zeigt das Spiel das Code-Rezept.

---

## 19. ⚙️ Config & Balancing

Im Studio links im **Explorer**: **ReplicatedStorage → Shared → Config**. Darunter liegen die Teile. Doppelklick öffnet eine Datei.
Jede Zahl ist kommentiert. Nach einer Änderung: **Play** zum Testen, dann **Publish**.

| Datei | Was drinsteht |
|---|---|
| `Config` (oben) | Admin-Regeln, Technik (DataStore-Namen), Studio-Einstellungen (`NoSave`, `SelfTest`, `LocalMarket`), Server (10 Spieler/Plots, Geld-Obergrenze), Farben, Live-Werte (`LiveFields`) |
| `Security` | Anti-Cheat-Grenzen, Bann-Dauern, Ansagen-Länge |
| `Client` / `Quality` | Tasten, Standard-Einstellungen, **Sounds** (Kapitel 18) / Grafikstufen (Lichter, Verkehr, Monitore je Stufe) |
| `Market` / `Companies` / `News` | Markt-Engine, Wochen-Termine, IPO-Liste / die 36 Firmen, ETFs, Körbe / Nachrichten-Vorlagen. **Nur mit Claude ändern** |
| `Trading` | Gewinn-Transfer (Schwelle 2 %, Tageslimit 6 %), Starthilfe, Schutz-Paar, Chips, Bots |
| `Tower` | Etagen-Kosten und -Einkommen, Stufen, Abteilungen, Personal, Effizienz, Tresor, Offline, Multiplikatoren, Fassaden, Kronen |
| `City` / `Vehicles` | Stadt-Plan und Look / die 16 Autos, Tuning, Höchsttempo |
| `Decor` / `Lifestyle` | 68 Deko-Teile / Uhren, Accessoires, Jetpack |
| `Progression` / `Season` / `Rewards` | Lizenzen, XP, Know-how, Ruf, Titel, Börsengang, Akademie, Quests, Erfolge, **Badges** / Skyline-Pass / Login-Kalender, **Codes** |
| `Shop` | **Robux-Pässe, -Produkte, Abo (IDs, Planpreise)**, Firewall-Liste, Angebots-Regeln |
| `Events` | Welt-Events, Wochen-Kalender, Admin-Abuse-Grenzen |

**Live ändern (empfohlen für Event-Werte):** Admin-Panel → **Live-Ops** (Liste mit Grenzen: LIVEOPS Abschnitt 6.3).

> ⚠️ **Nie ändern:**
> - `DataStoreName` (`AT_Player_v1`) und `KeyPrefix` in `Config` – sonst sind **alle Spielstände weg**.
> - Die **Keys** von Pässen, Produkten, Autos, Uhren, Deko, Badges, Saisons und die **IDs** von Firmen (sie stehen in den Spielständen).
>   IPO-Nummern 100–139 und Saison-Ids werden **nie wiederverwendet**.
> - Turm-Kosten und -Einkommen (`Config → Tower`) nur zusammen mit Claude (er prüft danach mit `tools/economy_sim.py`, dass nichts kippt).
> - Die Firewall-Liste `ForbiddenRobuxFields` und `RandomItemsEnabled = false` in `Config → Shop`.
>
> 💡 `Config` wird an alle Spieler geschickt. Schreib dort **nie** Geheimnisse rein.

Unsicher? Schreib Claude, was anders sein soll („Bau-Boom ist zu stark“). Claude ändert es.

---

## 20. 🔄 Updates veröffentlichen

Schreib Claude im Chat, was du willst („neues Auto“, „Fehler XY“). Claude ändert den Code im GitHub-Repo. Danach gibt es 3 Wege:

**A) Am einfachsten: neue `AkytexTycoon.rbxlx`**
1. Neue Datei holen (Kapitel 5: herunterladen **oder** im Terminal neu bauen mit `rojo build default.project.json -o AkytexTycoon.rbxlx`,
   nachdem du das neue ZIP geladen bzw. `git pull` gemacht hast).
2. In Studio öffnen (**Cmd + O**).
3. **File → Publish to Roblox As…** → dein Spiel → den Place → **Overwrite**.
4. Kurz prüfen: **Home → Game Settings → Places** (Max Players 10), **Avatar** (R15), **Communication** (Microphone an) stehen noch richtig.

Das klappt, weil alles per Code gebaut ist. Deine IDs stehen in der neuen Datei, wenn du sie Claude geschickt hast. Hast du selbst etwas
in `Config` geändert (IDs, Codes, Sounds): sag es Claude vorher, damit es in die neue Datei kommt. Live-Werte aus dem Admin-Panel bleiben
sowieso (sie liegen bei Roblox, nicht in der Datei).

**B) Nur einzelne Skripte ersetzen**
Claude nennt dir die geänderte Datei (z. B. `src/server/Services/TowerService.luau`). In Studio das gleichnamige Skript öffnen
(**ServerScriptService → Server → Services → TowerService**), alles markieren (**Cmd + A**), neuen Inhalt von GitHub einfügen (**Cmd + V**),
dann **Publish**. Neue Datei: im passenden Ordner Rechtsklick → **Insert Object** → **ModuleScript** → genau so umbenennen. Bei vielen
Dateien ist Weg A einfacher.

**C) Profi-Weg mit Live-Sync (Rojo)**
1. Projekt per Git geholt (Kapitel 4.6), im Terminal im Ordner `roblox-akytex-tycoon`: `git pull`.
2. `AkytexTycoon.rbxlx` in Studio öffnen, dann im Terminal:
   ```
   rojo serve
   ```
3. In Studio: Reiter **Plugins → Rojo → Connect**. Studio übernimmt alle Code-Änderungen sofort.
4. **Publish** (**Option + P**). Terminal mit **Ctrl + C** beenden.

**„Kann Claude direkt in mein Studio?“** Aus diesem Cloud-Chat nicht. Mit **Claude Code** auf deinem Mac gibt es den offiziellen
**Roblox Studio MCP Server**, damit kann Claude Studio direkt bedienen.

---

## 21. 📊 Zahlen: KPIs, Funnel, Umsatz

Wo? **Creator Dashboard** → dein Spiel → links **Analytics** (Bereiche wie **Retention**, **Engagement**, **Monetization**, **Economy**,
**Funnels** bzw. **Onboarding**). Das Spiel meldet die Tutorial-Schritte als **Onboarding-Funnel** und alle CR-Quellen/-Senken als
**Economy-Events**. Im Spiel: Admin-Panel → **Statistik**.

### 21.1 Ziele (DESIGN.md §E3)

| KPI | Ziel |
|---|---|
| Absprung in den ersten 60 s / Tutorial-Abschluss | < 5 % / ≥ 75 % |
| D1 / D7 / D30 (wie viele kommen nach 1/7/30 Tagen wieder) | ≥ 35 % / ≥ 12 % / ≥ 5 % |
| Median-Sitzung / Sitzungen ≥ 10 min | ≥ 25 min / ≥ 70 % |
| Co-Play (Sitzungen mit Freund) | ≥ 20 % der Spieler wöchentlich |
| Zahler-Konversion / Starter-Paket | 2–4 % der monatlichen Spieler / 2–3 % der Spieler am Tag 2 |
| Fehlerhafte Käufe | 0 |

### 21.2 Der Onboarding-Funnel (18 Schritte, `Config → Progression → Tutorial`)

| # | Schritt | Bedeutung | | # | Schritt | Bedeutung |
|---|---|---|---|---|---|---|
| 1 | Joined | Spieler betritt das Spiel | | 10 | FirstAutomation | Hausmeister-Bot da |
| 2 | SplashDone | Ladebildschirm fertig | | 11 | FirstLiveTrade | erster echter Trade |
| 3 | Spawned | Kamera-Anflug fertig | | 12 | CarDriven | Gratis-Auto gefahren |
| 4 | Floor1 | Etage 1 gebaut | | 13 | Lesson1 | Akademie-Lektion 1 |
| 5 | FirstCollect | Tresor eingesammelt | | 14 | LicenceAzubi2 | Lizenz Azubi II |
| 6 | TutorialTrade | Übungs-Trade (ACAD) | | 15 | FirstMultiplier | erste Effizienz-Stufe |
| 7 | FirstTransfer | erster Gewinn in den Tower | | 16 | FavoritePrompted | Favoriten-Abfrage gezeigt |
| 8 | Stage3 | Loft-Verwandlung | | 17 | TenMinutes | 10 Minuten gespielt |
| 9 | FirstStaff | erstes Personal | | 18 | Day2Return | am nächsten Tag zurück |

Fällt zwischen zwei Schritten auffällig viel ab: Schritt-Nummern an Claude schicken – der Tutorial-Text oder die Zeit wird angepasst.

### 21.3 Umsatz-Faustformel (nur zur Orientierung)
```
USD pro Monat ≈ DAU × ARPDAU (in R$) × 30 × 0,70 × 0,0038
```
- **DAU** = Spieler pro Tag · **ARPDAU** = Robux-Umsatz pro Spieler und Tag · **0,70** = dein Anteil an Käufen im Spiel ·
  **0,0038** = ungefährer DevEx-Kurs (USD je Robux).
- Beispiel: 2.000 DAU × 1,5 R$ × 30 × 0,70 × 0,0038 ≈ **239 USD/Monat**. Bei 20.000 DAU × 2 R$ ≈ **3.192 USD/Monat**.
- Premium Payouts und Abos kommen dazu. Das ist **keine Garantie** – nur eine Rechenhilfe.

---

## 22. 🧯 Fehlerhilfe

| Problem | Lösung |
|---|---|
| „**Save failed**“ beim Veröffentlichen | Kapitel 8.1 + 8.2: erst leere **Baseplate** (Name `Akytex Tycoon`, ohne Emoji, Team Create AUS), dann `AkytexTycoon.rbxlx` mit **Publish to Roblox As… → Overwrite** darüberspielen |
| Nach dem Öffnen ist die Welt fast leer | Richtig so. Die Stadt baut sich erst beim **Play** (bzw. beim Serverstart) |
| Toast „**Studio: Fortschritt wird nicht gespeichert**“ | Richtig so. Im Studio wird absichtlich nie gespeichert (`Config.Studio.NoSave = true`) |
| Meldung „**Studio: Speichern ist AUS – aktiviere in Game Settings → Security „Studio Access to API Services“**“ | Kommt nur, wenn du `NoSave` auf `false` gestellt hast. Dann Kapitel 8.3 Punkt 1. Danach `NoSave` am besten wieder `true` |
| Banner „**Lokaler Testmarkt**“ im Admin-Dashboard | Normal im Studio ohne API-Zugriff: Der Markt läuft mit einem Test-Startwert. Im echten Spiel (oder mit API-Zugriff) verschwindet es |
| Tutorial kommt im Studio jedes Mal | Richtig so (nichts wird gespeichert). Im echten Spiel nur beim ersten Mal |
| `[SelfTest] … FAIL` im Output | Die Zeile darüber sagt, welcher Test. Kopieren und Claude schicken |
| Orange Zeilen mit `[Config]` im Output | Tippfehler in einer Config-Datei (Komma, Anführungszeichen). Zeile kopieren → Claude, oder die letzte Änderung rückgängig machen (**Cmd + Z**) |
| Admin-Panel fehlt im echten Spiel | Spiel muss unter **deinem** Account (RizzG315) veröffentlicht sein – oder du bist Besitzer der Gruppe, der es gehört |
| Player2 hat kein Admin-Panel | Richtig so. Nur Player1 (du) ist Admin |
| Shop zeigt „**Bald verfügbar**“ | Die ID in `Config → Shop` ist noch `0` (Abo: `""`). IDs an Claude schicken (Kapitel 9.6) |
| Geschenk-Boost ist gesperrt | Roblox erlaubt Geschenke für Käufer oder Empfänger gerade nicht (Land/Konto). Absicht. Testen: Admin → **Debug → Policy simulieren** |
| Kauf kam nicht an | Roblox wiederholt den Kauf automatisch, bis er verbucht ist. Notfalls: Admin → **Spieler → Belege** ansehen → **Kauf nachliefern** |
| „Gewinn in den Tower“ ist grau | Schon ein Transfer in diesem Börsentag (nächste Glocke abwarten) – oder das Depot liegt nicht mindestens 2 % über der Basis |
| Trades zählen nicht für die Liga | Admin-Fenster aktiv (Chip „ADMIN-ABUSE aktiv“), Trade zu klein (< 2 % des Depots) oder zu kurz gehalten (< 60 s), oder Admin-Geschenk diese Woche |
| Glocken-Moment startet nicht | Im echten Spiel müssen **3 Spieler** zur vollen Stunde in der Glocken-Zone stehen (Studio: 1) |
| „📡 Keine Antwort vom Server“ | Kurzer Netz-Hänger. Nochmal versuchen. Kommt es oft: Output-Text an Claude |
| „Dein Spielstand konnte nicht geladen werden …“ | Roblox-Speicher ist gerade überlastet. Spieler soll neu beitreten. Der Spielstand ist sicher (Session-Lock) |
| Eigenes Asset ist unsichtbar / Sound stumm | Asset noch in der Moderation, privat oder gehört nicht dem Spiel-Ersteller. Das Spiel zeigt dann automatisch das Code-Rezept (ASSET-LISTE 1.1) |
| Kein Voice-Chat | Game Settings → **Communication → Microphone** an (Kapitel 8.4). Roblox erlaubt Voice nur für berechtigte, verifizierte Spieler ab 13 |
| Server ist bei 10 Spielern voll | Richtig so (10 Plots). Roblox startet automatisch neue Server |
| Es ruckelt auf einem alten Handy | Das Spiel senkt die Grafikstufe automatisch und schaltet unter 35 FPS einmal „Reduzierte Effekte“ an. Zusätzlich: Einstellungen → Grafik **Low** |
| Avatare riesig oder winzig | **Game Settings → Avatar**: R15 und Skalierung **Standard** (Kapitel 8.3) |
| Bann im Studio klappt nicht | Richtig so. Test-Spieler haben keine echte UserId. Banns gehen nur im echten Spiel |
| Spieler mit „Ungewöhnliche Aktivität“ gekickt | Der Anti-Cheat hat gefälschte Befehle bemerkt. Prüfen: Admin → **Moderation**. Gute Statistik allein führt **nie** zu einem Bann |
| `rojo` / `rokit`: „command not found“ | Terminal ganz schließen (**Cmd + Q**) und neu öffnen; sonst Mac neu starten; dann Kapitel 4.3/4.4 wiederholen |
| `rojo build` meldet einen Fehler | Du bist nicht im Ordner `roblox-akytex-tycoon` (Kapitel 4.6, mit `ls` prüfen). Sonst Text an Claude |
| Rote Fehler im **Output** | Text markieren, kopieren (**Cmd + C**) und Claude schicken |

---

## 23. 🧠 Technik in einfachen Worten

- **Ein Markt für alle Server:** Die Kurse werden aus einem gemeinsamen Wochen-Startwert und der Uhrzeit berechnet. Jeder Server
  rechnet dasselbe – darum sehen alle zur selben Sekunde denselben Kurs. Admin-Markt-Events gehen über einen gemeinsamen Speicher
  (MemoryStore) an alle Server und starten überall im selben Moment.
- **Der Server entscheidet:** Dein Gerät schickt nur Wünsche („kaufen“). Preis, Ausführung, Geld, Bauen, Belohnungen rechnet der Server.
- **Geld in ganzen Zahlen:** AKY in Cent, CR ganzzahlig, nie über 9 Billiarden (Anzeige „MAX“) – es gibt keine Rundungsfehler.
- **Robux-Firewall im Code:** Der Markt-Code kennt CR und Robux gar nicht; ein automatischer Prüfer und der Selbsttest stellen sicher,
  dass kein Kauf das Depot berührt.
- **Sicheres Speichern:** Alle 90 Sekunden und beim Verlassen. Ein **Session-Lock** verhindert, dass zwei Server gleichzeitig speichern.
  Beim Herunterfahren speichert der Server alle noch einmal.
- **Käufe:** Jeder Kauf wird mit seiner Nummer gespeichert – **nie doppelt, nie gar nicht** gutgeschrieben.
- **Offline-Einnahmen:** Beim nächsten Beitritt rechnet der Server aus, wie lange du weg warst (höchstens 8 h, mit Pass/Club mehr).
- **Große Welt, flüssig:** Streaming lädt nur, was in deiner Nähe ist; Innenräume der Tower baut nur dein Gerät, und nur nah an dir;
  Grafikstufen passen sich automatisch an. Charts benutzen wiederverwendete Bausteine (60 FPS).
- **Anti-Cheat:** Verdachts-Punkte für zu schnell, Teleport, gefälschte Befehle. Ab 25 Punkten Prüfliste, ab 60 Kick. Nie automatischer Bann
  wegen Statistik.
- **Ein Takt-Geber** auf dem Server für alle wiederkehrenden Aufgaben, feste Obergrenzen für alles (Orders, Pickups, Effekte).

---

## 24. 📁 Dateien

```
roblox-akytex-tycoon/
├── AkytexTycoon.rbxlx         ← diese Datei in Studio öffnen (oder mit Rojo selbst bauen)
├── ANLEITUNG.md               ← du bist hier
├── default.project.json       ← Bauplan für Rojo (inkl. Future-Licht, Streaming, Voice)
├── docs/
│   ├── KOPIERVORLAGEN.md      ← alle Texte für Roblox + ID-Kasten
│   ├── TESTPLAN.md            ← Prüfliste (Studio, 2 Spieler, Geräte, Compliance, Namens-Suche, Leistung)
│   ├── LIVEOPS.md             ← Wochenplan, Saisons, Samstag, Notschalter
│   ├── ASSET-LISTE.md         ← alle Asset-Plätze + Higgsfield-Prompts
│   ├── STYLE-AKYTEX.md        ← der AKYTEX-Look
│   ├── DESIGN.md              ← der komplette Bauplan (für Claude)
│   ├── MARKET.md              ← die Markt-Engine (für Claude)
│   ├── REUSE.md               ← was aus CLUTCH CLASH übernommen wurde
│   └── BESITZER-WUENSCHE.md   ← deine Wünsche
├── scripts/                   ← Prüf-Skripte (für Claude)
├── tools/                     ← Rechner für Wirtschaft und Markt (für Claude)
├── tests/                     ← automatische Tests (für Claude)
└── src/
    ├── first/     (ReplicatedFirst)      Ladebildschirm
    ├── shared/    (ReplicatedStorage → Shared)
    │   ├── Config/            ← ALLE Einstellungen (Shop, Season, Rewards, Events, Tower …)
    │   ├── Lang/              ← alle Texte auf Deutsch und Englisch
    │   └── …                  Rechen-Module (Turm, Fortschritt, Depot, Indikatoren), Modelle aus Code
    ├── server/    (ServerScriptService → Server)
    │   ├── Main.server.luau   ← startet alles
    │   ├── Services/          Daten, Markt, Orders, Tower, Stadt, Fahrzeuge, Fortschritt, Shop, Käufe, Admin, Events, Anti-Cheat …
    │   └── Market/  World/  Lib/  Tests/
    └── client/    (StarterPlayer → StarterPlayerScripts → Client)
        ├── Main.client.luau   ← startet die Oberfläche
        └── Modules/           HUD, Terminal, Charts, Tower-Menü, Shop, Akademie, Admin-Panel …
```

---

## 25. 📖 Wörterliste A–Z

| Wort | Was es heißt |
|---|---|
| **ACAD** | Die Übungsaktie im Tutorial (nur für dich berechnet, nicht im echten Markt) |
| **Admin / Admin-Panel** | Chef-Rechte im Spiel. Hat nur der Besitzer (du). Das Admin-Panel ist dein Chef-Fenster (Taste **P**) |
| **Admin-Abuse** | Show-Events vom Admin: Rallys, Geldregen, Golden Hour, Feuerwerk … – samstags 18:00 |
| **Admin-Fenster (Taint)** | Zeit rund um ein Admin-Markt-Event. Zählt nicht für die Liga |
| **Aktien-Sterne (★)** | Prestige-Punkte aus dem Börsengang. Kaufen nur Turm-/Lifestyle-Vorteile im Vorstand-Baum |
| **AKX36** | Index-ETF der 36 Firmen, gleich gewichtet – Einsteiger-Empfehlung |
| **AKY** | Börsengeld (Spielgeld) im Depot. Blaue Münze mit Λ. Nie für Robux |
| **Akademie** | Lern-Kapseln im Börsensaal: Lektionen + Quiz, Lizenzprüfungen |
| **Analyst** | Einer von 8 erfundenen Analysten mit echter, live gemessener Trefferquote |
| **API Services** | Roblox-Dienste wie Speichern und Bestenlisten. „Studio Access to API Services“ erlaubt Studio, sie beim Testen zu benutzen |
| **Asset / Asset-ID** | Hochgeladene Datei bei Roblox (3D-Modell, Bild, Sound) / ihre Nummer |
| **Asset-Platz** | Stelle in `Config` für eine eigene Datei; `0` = Code-Rezept (ASSET-LISTE) |
| **Badge** | Abzeichen für einen Meilenstein, sichtbar im Roblox-Profil |
| **Baseplate** | Die leere Start-Welt in Studio (graue Platte) |
| **Basis** | Grundkapital im Depot je Lizenz (25.000 … 60 Mio. AKY). Nur was darüber liegt, darf in den Tower |
| **Bau-Gutschein** | Robux-Produkt, gibt CR (Minuten deines Dauer-Einkommens, mit Mindestwert). Nur CR |
| **Bau-Hilfe** | Besucher tippen deine Baustelle an → −10 % Restzeit |
| **Bau-Kurs** | Wie viele CR du für 1 AKY bekommst (40 … 40.000). Hängt nur von der Lizenz ab |
| **Beleg (Receipt)** | Roblox' Nachweis über einen Kauf. Das Spiel merkt sich jeden Beleg |
| **Bilanz-Sonntag** | So 20:00: Liga-Finale mit Top-10-Hologrammen |
| **Boost** | Zeitlicher Multiplikator aufs Turm-Einkommen (x2, x5, Bullen-Bonus x1,5). Zählt nur Spielzeit |
| **Börsengang (BG)** | Prestige: Tower startet neu, du bekommst Aktien-Sterne, +0,25 dauerhaft und eine neue Krone |
| **Börsentag** | 20 Minuten = ein Tag/Nacht-Zyklus. Beginnt mit der Glocke |
| **Bullen-Parade** | Robux-Produkt: ×1,5 Einkommen für den ganzen Server, 15 min, goldene Parade |
| **Creator Dashboard** | Roblox-Webseite für Spiele-Macher (**create.roblox.com/dashboard/creations**) |
| **CR (Credits)** | Turmgeld. Grüner Sechskant-Chip. Für Etagen, Personal, Deko, Autos, Uhren |
| **Crash / Rally** | Starker Fall / Anstieg des Markts, mit 3 Minuten Warnstufe. Crash-Freitag und Rally-Mittwoch sind geplant |
| **DataStore** | Roblox-Speicher im Internet für die Spielstände |
| **Depot** | Dein AKY-Konto: freies Geld, Aktien, Orders, Alarme, Bots |
| **Developer Product** | Etwas, das man im Spiel **immer wieder** mit Robux kaufen kann |
| **DevEx** | Verdiente Robux in echtes Geld tauschen |
| **Drawdown** | Größter Rückgang des Depots vom Höchststand (kleiner = besser) |
| **Effizienz-Stufe** | Mit CR kaufbar, je +0,10 dauerhafter Multiplikator (max. 20 je Tower-Lauf) |
| **Eilmeldung / Gerücht / „wie erwartet“** | Nachrichten-Arten: Fakt (bewegt den Kurs) / unsicher (Quellen-Sterne) / ändert kaum etwas |
| **ETF** | Korb aus vielen Firmen in einem Wert (AKX36 und 6 Sektor-ETFs) |
| **Experience** | Das englische Roblox-Wort für „Spiel“ |
| **Experience Event** | Termin auf der Spielseite, Spieler können sich erinnern lassen |
| **Experience Subscription** | Monatliches Abo (bei uns: Vorstands-Club) |
| **Explorer / Properties / Output** | Studio-Fenster: Teile des Spiels / Eigenschaften / Meldungen |
| **Firewall (Robux-Firewall)** | Regel im Code: Nichts, was Robux kaufen, erreicht je AKY, Aktien, Lizenz, XP, Know-how, Ruf oder Marktinfos |
| **Firmen-Album** | Sammelalbum: einmal jeden Wert besitzen; volle Sektoren geben +0,02 |
| **Future-Licht** | Die beste Roblox-Lichttechnik (echte Schatten). Nicht „Raytracing“ nennen |
| **Gamepass** | Etwas, das man **einmal** mit Robux kauft und **für immer** behält |
| **Gerätesimulator** | Studio tut so, als wärst du am Handy/Tablet/an der Konsole (**Test → Device**) |
| **Gewinn-Transfer** | AKY über der Basis → CR zum Bau-Kurs. Höchstens 1× je Börsentag, max. 6 % der Basis, erst ab 2 % über der Basis |
| **Glocke** | Börsenglocke, läutet alle 20 min (Sonnenaufgang). Auch Börsengang-Zeremonie |
| **Glocken-Moment** | Volle Stunde: ≥ 3 Spieler an der Glocke → ganzer Server ×1,2 für 5 min |
| **Golden Hour** | Admin-Event: Einkommen ×2 oder ×3 für 5–60 min |
| **Hall of Fame** | Goldene Statuen der Top-3 der Liga-Vorwoche auf der Plaza |
| **Higgsfield** | KI-Werkzeug, mit dem du Bilder, 3D-Modelle und Sounds für die Asset-Plätze erzeugen kannst |
| **HUD** | Alle Anzeigen auf dem Bildschirm (Geld, Multiplikator, Knöpfe, Pillen) |
| **IPO-Erstnotiz** | Neue erfundene Firma kommt an die Börse (Sa 17:00, kaufbar ab Fondsmanager) |
| **Klumpen-Grenze** | Höchstanteil eines einzelnen Werts im Depot (30 / 40 / 50 / 60 % je Lizenz) |
| **Know-how (KH)** | Punkte aus Level, Lizenz und Akademie. Kaufen Trading-Werkzeuge (Alarme, Watchlists, Bots). Nie Robux |
| **Lizenz** | Rang vom Azubi I bis zur Börsen-Legende (10 Stufen), mit Prüfungen |
| **Liga / Skill-Score** | Wochen-Wertung nach Können (Konstanz, Drawdown), nicht nach Kontogröße. Stufen Bronze 300, Silber 500, Gold 700, Diamant 850 |
| **LiveConfig / Live-Ops** | Werte, die du im Admin-Panel ohne neue Datei änderst (gelten sofort auf allen Servern) |
| **Lokaler Testmarkt** | Markt im Studio ohne API-Zugriff, mit Test-Startwert |
| **MeshId / TextureId** | Nummer eines 3D-Modells / seines Farbbilds bei Roblox |
| **Multiplikator** | Faktor aufs Turm-Einkommen. Gruppen: dauerhaft (Effizienz, Börsengänge …), Trader-Faktor (Skill), Pässe, VIP/Club/Premium, zeitlich (Deckel ×10) |
| **Offline-Tresor** | Turm verdient auch, wenn du weg bist (8 h, mit Pass mindestens 24 h) |
| **Order-Arten** | **Sofort** kaufen/verkaufen · **Wunschpreis** (Limit) · **Verlust-Stopp** · **Gewinn-Ziel** · **Schutz-Paar** (beides) · **Nachzieh-Stopp** (wandert mit, ab Trader I) |
| **Overwrite** | Überschreiben. Die Datei ersetzt den Inhalt deines Spiels bei Roblox |
| **Paid Random Items** | Man bezahlt und bekommt etwas Zufälliges. Gibt es bei uns **nicht** |
| **Personal** | Roboter je Etage (Praktikant, Analyst, Senior-Droid, Quant-Mainframe) – mehr Einkommen |
| **Place** | Eine Welt in deinem Spiel (wir haben genau einen) |
| **Playability (Private / Public)** | Wer dein Spiel spielen darf: nur du / alle |
| **Plot** | Einer von 10 Bauplätzen am Skyline-Ring |
| **Policy** | Roblox sagt dem Spiel, was im Land des Spielers erlaubt ist (z. B. Geschenke) |
| **Power-Hour** | Täglich 19:00–20:00: Trader-XP ×2 |
| **Premium Payouts** | Roblox zahlt dir Robux für die Spielzeit von Premium-Mitgliedern |
| **Publish** | Hochladen zu Roblox (**Option + P**) |
| **R15 / R6** | Die heutige Roblox-Figur mit 15 Teilen / die alte Klötzchen-Figur |
| **Respekt** | Besucher geben deinem Tower Respekt → +0,01 Multiplikator für 1 h |
| **Rettungsschirm (Starthilfe)** | Depot unter 50 % der Basis: einmal am Tag auffüllen. Nicht abhebbar |
| **Robux (R$)** | Das Geld von Roblox. Du bekommst ca. 70 % jedes Kaufs im Spiel |
| **Rojo / Rokit** | Werkzeuge: Rojo baut die Spiel-Datei aus dem Code / Rokit installiert Rojo (Kapitel 4) |
| **Ruf** | 0–10 Stufen aus positiven Börsentagen. Teil des Trader-Faktors. Verluste kosten nie Ruf |
| **Saison / Skyline-Pass** | 4 Wochen mit Thema; Pass mit 50 Stufen (Gratis- und Premium-Spur), Saison-XP aus Quests und Spielzeit |
| **Samstags-Show** | Automatische Show Sa 18:15, wenn du nicht live bist |
| **Schutz-Paar** | Verlust-Stopp + Gewinn-Ziel in einem („Schutz an“ = −8 % / +15 %) |
| **Selbsttest (SelfTest)** | Automatische Prüfung beim **Play** im Studio: `[SelfTest] n/n PASS` |
| **Server** | Ein Roblox-Computer, auf dem ein Durchgang deines Spiels läuft (bis 10 Spieler) |
| **Session-Lock** | Sperre: Ein Spielstand kann nur von einem Server gleichzeitig gespeichert werden |
| **Sky-Show** | Stündlich hh:15: Lichtshow, Respekt zählt doppelt |
| **Spread / Gebühr** | Unterschied zwischen Kauf- und Verkaufskurs / kleine Order-Gebühr in AKY |
| **Strategie-Bot** | Handelt einen Teil deines Depots nach sichtbaren Regeln (Sparplan, Trend, Dividende, Dip). Nur über Lizenz + Know-how |
| **Streaming (StreamingEnabled)** | Roblox lädt nur die Teile der Welt in deiner Nähe – wichtig für die große Stadt |
| **Studs** | Längen-Einheit in Roblox (eine Figur ist ca. 5 Studs groß) |
| **Team Create** | Studio-Funktion für gemeinsames Bauen. Für dich: **aus** |
| **Terminal** | 1) Das Börsen-Fenster im Spiel (Taste **T**) · 2) Mac-Programm für Befehle |
| **Themen-Korb** | Ein Tipp kauft 4–6 Werte zu einem Thema gleich verteilt (ab Trader I) |
| **Tiko / Tiko-Ampel** | Der geskriptete Spielhelfer / grün-rote Ampel bei Fakten-Nachrichten (Schicht „Einfach“) |
| **Trader-Faktor** | (1 + Lizenz-Bonus) × (1 + 0,03 × Ruf), max. ×1,82 – reiner Skill-Multiplikator aufs Turm-Einkommen |
| **Trader-XP / Trader-Level** | Erfahrung nur aus Handeln und Lernen (nie Bauen, nie Robux) |
| **Tresor** | Sammelt das Online-Einkommen (Kapazität 20 min). Leeren am goldenen Kassen-Tor |
| **UTC** | Weltzeit. Deutschland ist im Winter 1 Stunde und im Sommer 2 Stunden weiter |
| **Vermögen** | Anzeige- und Bestenlisten-Wert aus CR, Tower, Firmenwert, Sammlung und Depot |
| **Vorstands-Club** | Das Abo (Experience Subscription) |
| **Welt-Event** | Alle 20 min um :10: Geldtransporter, Drohnen, Bau-Boom oder Pressekonferenz |
