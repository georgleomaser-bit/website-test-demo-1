# AKYTEX TYCOON – Kopiervorlagen

## Wofür ist diese Datei?

Hier steht **alles, was du beim Veröffentlichen eintippen musst**: Spielname, Beschreibung, alle **14 Gamepässe**,
alle **17 Developer Products**, das **Abo „Vorstands-Club“**, die **15 Badges**, Texte für **Experience Events** und Posts.
Du musst dir nichts ausdenken: kopieren, einfügen, fertig.

Jeder Pass, jedes Produkt, das Abo und jedes Badge bekommt von Roblox eine **ID**. Die schickst du Claude mit dem Kasten
ganz unten (**Abschnitt 13**). Claude trägt alle IDs ein. (Selbst eintragen geht auch: ANLEITUNG Kapitel 9.6.)

Alle Preise und Schlüssel hier sind mit `Config → Shop` und `Config → Progression` abgeglichen (Stand dieser Datei).

---

## 📋 So kopierst du richtig

- Jeder **graue Kasten** ist genau ein Text zum Kopieren.
- Fahr mit der Maus über den Kasten. Oben rechts erscheint ein kleiner **Kopier-Knopf** (zwei Quadrate). Klick drauf.
- Geh zu Roblox, klick in das Feld und drück **Cmd + V**.
- Kein Knopf da? Text im Kasten mit der Maus markieren und **Cmd + C** drücken.
- Trag bei Roblox die **englischen** Texte ein. Die deutschen sind für dich und für die Übersetzung
  (Creator Dashboard → dein Spiel → **Localization**). Im Spiel zeigt der Shop sowieso eigene Texte auf Deutsch oder Englisch.

## 📖 Kleine Wörterliste

| Wort | Was es heißt |
|---|---|
| **Robux (R$)** | Das Geld von Roblox. Du bekommst ca. 70 % jedes Verkaufs im Spiel |
| **Gamepass** | Wird **einmal** gekauft und gilt **für immer** (z. B. VIP) |
| **Developer Product** | Kann man **immer wieder** kaufen (z. B. Boost x2 · 30 min) |
| **Experience Subscription (Abo)** | Monatliches Abo. Bei uns: „Vorstands-Club“ |
| **Badge** | Abzeichen, das Spieler für einen Meilenstein bekommen und auf ihrem Profil zeigen |
| **ID** | Die Nummer, die Roblox jedem Pass, Produkt, Abo und Badge gibt |
| **Config-Key** | Der Name im Code (z. B. `Income2x`). Daran weiß Claude, wo die ID hingehört. Bei Roblox tippst du ihn nirgends ein |
| **CR (Credits)** | Turmgeld. Robux-Artikel geben **nur CR, Boosts, Bau-Tempo und Kosmetik** |
| **AKY** | Börsengeld (Spielgeld im Depot). **Nie** für Robux – kein Artikel berührt AKY, Lizenzen, XP oder Marktinfos |
| **Icon-Idee** | Bild-Idee für das 512 × 512-Bild, als Prompt für Higgsfield (Regeln: Abschnitt 4) |

---

## 1. 🏷️ Spielname

**Beim allerersten Veröffentlichen** (leere Baseplate, ANLEITUNG Kapitel 8.1) nimmst du den einfachen Namen –
**ohne Emoji, ohne Sonderzeichen**:

```
Akytex Tycoon
```

**Danach** änderst du ihn auf den richtigen Titel:

```
AKYTEX TYCOON 🏙️📈 Börse & Tower
```

Englische Übersetzung (Creator Dashboard → **Localization** → Englisch):

```
AKYTEX TYCOON 🏙️📈 Stocks & Tower
```

In einer Saison stellst du die Saison-Nummer davor (Beispiel Saison 1):

```
[S1] AKYTEX TYCOON 🏙️📈 Börse & Tower
```

**Wo ändern?** In Studio: **Home → Game Settings → Basic Info → Name** → **Save**.
Oder im Creator Dashboard: dein Spiel → **Configure** → **Basic Info** (bzw. **Experience Details**).

**Ersatz, falls Roblox Emojis ablehnt:** `AKYTEX TYCOON Börse & Tower`

> ⚠️ Kein Geld- oder Robux-Wort im Titel („Free Robux“, „Money“, „Rich“ …). Roblox stuft solche Titel herunter.

---

## 2. 📝 Spielbeschreibung

Aufbau (Pflicht, DESIGN.md §A1): Zeile 1 Fantasie · Zeile 2 Disclaimer · Zeile 3 Event-Kalender · letzte Zeile Social-Links.

### Englisch (für Roblox)

```
🏙️ Start in a garage in a neon city. Read breaking news before the market moves, trade 36 fictional companies on the AKYTEX Exchange with play money, and turn your profits into your own skyscraper, floor by floor, up to the 50-floor ΛKYTEX Orbit-Spire. Hire robot staff, drive your hypercar around the highway ring, wear your watch and ring the bell at your own IPO.

⚠️ Game with play money. All companies, prices and news are fictional. Game money has no real value and cannot be cashed out. Not investment advice.

📅 Bell every 20 minutes · Wed 7 pm Rally Wednesday · Fri 7 pm Crash Friday · Sat 5 pm IPO · Sat 6 pm Admin Abuse · Sun 8 pm League Finale (Berlin time)

🔔 Check out our social media links on our game's page
```

### Deutsch (für die Übersetzung unter Localization)

```
🏙️ Starte in einer Garage mitten in einer Neon-Stadt. Lies Eilmeldungen, bevor der Markt reagiert, handle 36 erfundene Firmen an der AKYTEX Exchange mit Spielgeld und steck deine Gewinne in deinen eigenen Wolkenkratzer – Etage für Etage, bis zum 50-stöckigen ΛKYTEX Orbit-Spire. Stell Roboter-Personal ein, fahr deinen Hypersportwagen über den Autobahnring, trag deine Uhr, läute die Glocke zu deinem eigenen Börsengang.

⚠️ Spiel mit Spielgeld. Alle Firmen, Kurse und Nachrichten sind frei erfunden. Spielgeld hat keinen echten Wert und kann nicht ausgezahlt werden. Keine Anlageberatung.

📅 Glocke alle 20 Minuten · Mi 19:00 Rally-Mittwoch · Fr 19:00 Crash-Freitag · Sa 17:00 IPO · Sa 18:00 Admin-Abuse · So 20:00 Bilanz-Sonntag (Berlin-Zeit)

🔔 Unsere Social-Links findest du auf der Spielseite.
```

**Wo eintragen?** Studio: **Home → Game Settings → Basic Info → Description** → **Save**.

> ⚠️ **Nie** in die Beschreibung: eine URL, „App“, „Website“, „echtes Trading“, „Demo-Depot“, „NOVA“, „Aky“, „PRO“, Euro-Preise,
> „Raytracing“ oder Wörter aus der Wortliste (Wette, Casino, Glück, verdoppeln, garantiert, bet, luck, spin …).

---

## 3. 🎮 Genre und Geräte

- **Genre:** `Simulation`, Untergenre **Tycoon** (falls Roblox Untergenres anbietet).
- **Playable Devices:** **Computer**, **Phone**, **Tablet**, **Console** (Controller wird unterstützt). **VR:** aus.
- **Wo?** Studio: **Home → Game Settings → Basic Info**.

---

## 4. 🖼️ Bild-Ideen (Icon, Thumbnails) – Prompts für Higgsfield

**Regeln für alle Bilder:** dunkler AKYTEX-Look (Glas, Marmor, Metall, blaues Neon `#4f8cff`), keine echten Marken,
kein Robux-Symbol, keine €/$-Zeichen, kein Geld-Versprechen, nichts mit Casino/Würfeln/Karten/Glücksrad/Spielautomat,
kein „Raytracing“ (höchstens „Future-Licht“). Text im Bild kurz und groß. Größen: Icon **512 × 512**, Thumbnails **1920 × 1080**.

| Bild | Idee | Prompt für Higgsfield |
|---|---|---|
| **Icon** | Glas-Wolkenkratzer mit leuchtender ΛKYTEX-Krone bei Nacht, darunter eine steigende grüne Kerzen-Linie | `square game icon, single glowing glass skyscraper at night with a blue neon crown, rising green candlestick chart line at the bottom, dark navy background, bold, simple, high contrast, no text` |
| **Thumbnail 1** | Skyline bei Sonnenuntergang, eigener Tower im Vordergrund, Kran setzt eine Etage | `cinematic city skyline at sunset, futuristic glass towers with blue neon, crane placing a new floor on a skyscraper, roblox style, wide shot` + Text „LIES DIE NEWS. BAU DIE SKYLINE.“ |
| **Thumbnail 2** | Trading-Terminal mit Kerzen-Chart und News-Karte „EILMELDUNG“ | `sleek dark trading terminal screen with green and red candlesticks, a breaking news card at the top, blue accent, glass UI` |
| **Thumbnail 3** | Hypercar auf dem Autobahnring bei Nacht, Neon-Unterbodenlicht | `futuristic hypercar driving on a neon highway at night, city skyline behind, motion blur, blue underglow` |
| **Thumbnail 4** | Börsengang: Spieler läutet die goldene Glocke, Konfetti-Beams | `grand stock exchange hall with a golden bell on a podium, confetti light beams, marble floor, celebration` |
| **Thumbnail 5** | Samstag: goldene Bullen-Parade um die Plaza | `parade of friendly golden bull statues around a neon plaza at night, fireworks beams in the sky` + Text „SA 18:00 ADMIN-ABUSE“ |

**Wo hochladen?** Studio: **Home → Game Settings → Basic Info → Game Icon** bzw. **Thumbnails**.
Für saubere Fotos aus dem Spiel: Taste **F7** (Fotomodus, versteckt die Knöpfe), dann am Mac **Cmd + Shift + 4**.

---

## 5. 🎟️ Gamepässe (14 Stück, einmal kaufen = für immer)

**So legst du einen Gamepass an** (Details: ANLEITUNG Kapitel 9.2):
1. Creator Dashboard → dein Spiel → links **Monetization → Passes → Create a Pass**.
2. **Bild** hochladen (512 × 512), **Name** und **Beschreibung (Englisch)** einfügen → **Create Pass**.
3. Pass anklicken → links **Sales** → **Item for Sale** an → **Preis** eintippen → **Save Changes**.
4. ID holen: beim Pass auf **⋯** → **Copy Asset ID** → in den Kasten in Abschnitt 13.

### VIP – Börsen-VIP
Name:
```
Exchange VIP
```
Beschreibung (Englisch, für Roblox):
```
VIP balcony in the exchange hall, golden Λ nameplate + chat tag, "Platinum" car paint and tower income ×1.10. Tower income only – never affects stock money (AKY), trades, licences or the league.
```
Beschreibung (Deutsch):
```
VIP-Balkon im Börsensaal, goldenes Λ-Namensschild + Chat-Tag, Auto-Lack „Platin“, Turm-Einkommen ×1,10. Nur Turm-Einkommen – nie Börsengeld (AKY), Trades, Lizenzen oder Liga.
```
- Preis: **399 Robux** · Config-Key: `VIP`
- Icon-Idee: `golden Λ nameplate on dark glass, balcony railing with blue neon, VIP feeling, no text except "VIP"`

### Income2x – x2 Einnahmen
Name:
```
2x Income
```
Beschreibung (Englisch):
```
Pass factor +1: your tower income ×2 on its own. Together with 3x Income ×4 (not ×6) – this is shown before you buy. Tower income only – never affects stock money (AKY), trades, licences or the league.
```
Beschreibung (Deutsch):
```
Pässe-Faktor +1: dein Turm-Einkommen allein ×2. Zusammen mit x3 Einnahmen ×4 (nicht ×6) – das steht vor dem Kauf da. Nur Turm-Einkommen – nie Börsengeld (AKY), Trades, Lizenzen oder Liga.
```
- Preis: **499 Robux** · Config-Key: `Income2x`
- Icon-Idee: `big glowing "x2" in electric blue neon in front of a glass skyscraper, dark background`

### Income3x – x3 Einnahmen
Name:
```
3x Income
```
Beschreibung (Englisch):
```
Pass factor +2: your tower income ×3 on its own. Together with 2x Income ×4 – not ×6. Tower income only – never affects stock money (AKY), trades, licences or the league.
```
Beschreibung (Deutsch):
```
Pässe-Faktor +2: dein Turm-Einkommen allein ×3. Zusammen mit x2 Einnahmen ×4 – nicht ×6. Nur Turm-Einkommen – nie Börsengeld (AKY), Trades, Lizenzen oder Liga.
```
- Preis: **1.199 Robux** · Config-Key: `Income3x`
- Icon-Idee: `big glowing "x3" in violet-blue neon in front of a tall glass tower, dark background`

### AutoCollect – Auto-Kassierer
Name:
```
Auto Collect
```
Beschreibung (Englisch):
```
Your vault is collected automatically every 3 s – wherever you are in the city.
```
Beschreibung (Deutsch):
```
Dein Tresor wird alle 3 s automatisch eingesammelt – egal, wo du in der Stadt bist.
```
- Preis: **249 Robux** · Config-Key: `AutoCollect`
- Icon-Idee: `round futuristic vault door with a circular arrow made of green light, dark glass`

### OfflineVault – Offline-Tresor 24 h
Name:
```
Offline Vault 24 h
```
Beschreibung (Englisch):
```
Offline cap at least 24 h and offline rate +15 percentage points. Your tower keeps earning CR while you are away.
```
Beschreibung (Deutsch):
```
Offline-Deckel mindestens 24 h und Offline-Rate +15 Prozentpunkte. Dein Tower verdient weiter CR, während du weg bist.
```
- Preis: **349 Robux** · Config-Key: `OfflineVault`
- Icon-Idee: `vault door under a crescent moon, night skyline, soft blue glow, "24h" label`

### StaffPlus – Personal+
Name:
```
Staff+
```
Beschreibung (Englisch):
```
3rd staff slot per floor – tower staff only, never strategy bots.
```
Beschreibung (Deutsch):
```
3. Personal-Platz je Etage – nur Turm-Personal, nie Strategie-Bots.
```
- Preis: **299 Robux** · Config-Key: `StaffPlus`
- Icon-Idee: `three cute office robots side by side at glass desks, the third one glowing, "+1" badge`

### BuildCrew – Bau-Crew Pro
Name:
```
Build Crew Pro
```
Beschreibung (Englisch):
```
Build times −50% (never below the minimum build time). Licence gates stay in place.
```
Beschreibung (Deutsch):
```
Bauzeiten −50 % (nie unter der Mindest-Bauzeit). Lizenz-Tore bleiben bestehen.
```
- Preis: **399 Robux** · Config-Key: `BuildCrew`
- Icon-Idee: `rooftop crane lifting a glowing floor slab onto a skyscraper, speed lines, blue accent`

### TerminalDesigner – Terminal-Designer
Name:
```
Terminal Designer
```
Beschreibung (Englisch):
```
6 terminal themes (Space, Gold, Arctic, Mono, Midnight, Aurora), candle/ticker skins, UI sound pack. Looks only – no alerts, layouts or indicators.
```
Beschreibung (Deutsch):
```
6 Terminal-Themes (Space, Gold, Arctic, Mono, Midnight, Aurora), Kerzen-/Ticker-Skins, UI-Sound-Paket. Nur Optik – keine Alarme, Layouts oder Indikatoren.
```
- Preis: **249 Robux** · Config-Key: `TerminalDesigner`
- **Noch NICHT anlegen/verkaufen:** Die Terminal-Themes sind noch nicht im Spiel. Der Pass steht in `Config.Shop.Disabled` auf gesperrt – erst freischalten, wenn die Themes wählbar sind (nie einen Pass ohne Wirkung verkaufen).
- Icon-Idee: `six small trading screen color swatches fanned out (space, gold, arctic, mono, midnight, aurora), glass UI`

### MegaGarage – Mega-Garage
Name:
```
Mega Garage
```
Beschreibung (Englisch):
```
+12 car slots in your garage – room for your whole collection.
```
Beschreibung (Deutsch):
```
+12 Auto-Plätze in deiner Garage – Platz für die ganze Sammlung.
```
- Preis: **199 Robux** · Config-Key: `MegaGarage`
- Icon-Idee: `glass showroom with a car on a glowing turntable, several parking bays, dark marble floor`

### Jetpack – Neon-Jetpack
Name:
```
Neon Jetpack
```
Beschreibung (Englisch):
```
Fly over the city with a neon trail: 8 s of flight, recharges in 12 s.
```
Beschreibung (Deutsch):
```
Flieg mit Neon-Spur über die Stadt: 8 s Flugzeit, lädt in 12 s nach.
```
- Preis: **449 Robux** · Config-Key: `Jetpack`
- Icon-Idee: `white and blue futuristic jetpack with glowing neon thrust trails over a night skyline`

### Lam1 – ΛKYTEX Λ-1 Hypercar
Name:
```
ΛKYTEX Λ-1 Hypercar
```
(Lehnt Roblox das Zeichen „Λ“ ab: `AKYTEX L-1 Hypercar`)

Beschreibung (Englisch):
```
Exclusive hypercar with a neon trail and its own shape. Drives right out of your garage. Same top speed as the best earned hypercar – never faster.
```
Beschreibung (Deutsch):
```
Exklusives Hypercar mit Neon-Spur und eigener Form. Fährt sofort aus deiner Garage. Gleiches Höchsttempo wie das beste erspielte Hypercar – nie schneller.
```
- Preis: **799 Robux** · Config-Key: `Lam1`
- Icon-Idee: `arctic white futuristic hypercar with a blue Λ-shaped light signature, low angle, neon road`

### Chrono – Chrono-Kollektion
Name:
```
Chrono Collection
```
Beschreibung (Englisch):
```
5 exclusive watches: Chrono Night, Aurora, Arctic, Solar and Midnight – visible on your wrist to everyone.
```
Beschreibung (Deutsch):
```
5 exklusive Uhren: Chrono Nacht, Aurora, Arktis, Solar und Mitternacht – am Handgelenk für alle sichtbar.
```
- Preis: **349 Robux** · Config-Key: `Chrono`
- Icon-Idee: `five luxury watches with glowing dials arranged in an arc, dark velvet, no brand`

### FacadeKit – Neon-Fassaden-Kit
Name:
```
Neon Facade Kit
```
Beschreibung (Englisch):
```
"Gold Luxe" facade, 8 animated light patterns and crown colours for your tower.
```
Beschreibung (Deutsch):
```
Fassade „Gold-Luxe“, 8 animierte Lichtmuster und Kronenfarben für deinen Tower.
```
- Preis: **349 Robux** · Config-Key: `FacadeKit`
- Icon-Idee: `skyscraper facade with animated gold and neon light patterns at night`

### TycoonBundle – Tycoon-Paket
Name:
```
Tycoon Bundle
```
Beschreibung (Englisch):
```
The effect of 2x Income + Auto Collect + Offline Vault 24 h in one pass (single passes 1,097 Robux together). If you already own a part, the shop card recommends the cheaper single passes.
```
Beschreibung (Deutsch):
```
Wirkung von x2 Einnahmen + Auto-Kassierer + Offline-Tresor 24 h in einem Pass (einzeln zusammen 1.097 Robux). Besitzt du schon ein Teil, empfiehlt die Shop-Karte die günstigeren Einzelkäufe.
```
- Preis: **749 Robux** (echt −32 % gegenüber 1.097 R$ einzeln) · Config-Key: `TycoonBundle`
- Icon-Idee: `three glowing icons (x2, circular arrow, moon) combined on one premium dark card with a star`

> 💡 Ändert sich ein Einzelpreis, stimmt die „−32 %“-Zahl nicht mehr. Der Shop rechnet den echten Rabatt aus den **Live-Preisen**;
> in der Beschreibung bei Roblox musst du die Zahl dann selbst anpassen.

---

## 6. 🛒 Developer Products (17 Stück, beliebig oft kaufbar)

**So legst du ein Produkt an** (Details: ANLEITUNG Kapitel 9.3):
1. Creator Dashboard → dein Spiel → links **Monetization → Developer Products → Create a Developer Product**.
2. Bild (512 × 512), Name, Beschreibung (Englisch), Preis → **Create Developer Product**.
3. ID holen: beim Produkt auf **⋯** → **Copy Product ID** (bzw. **Copy Asset ID**).

> **Fair-Regel:** Jedes Produkt gibt **nur Turm-Dinge** (CR, Boosts, Bau-Tempo, Kosmetik, Saison-Stufen) – **nie AKY, Aktien,
> Lizenz, Trader-XP, Know-how, Ruf oder Marktinfos**. Es gibt **keine Zufallsartikel**. Die genaue Wirkung steht vor dem Kauf im Spiel.

### Boost2x30 – Boost x2 · 30 min
Name: `Boost x2 · 30 min`
```
+30 min of x2 tower income (playtime – only counts while you are online).
```
Deutsch: „+30 min x2 Turm-Einkommen (Spielzeit – zählt nur, solange du online bist).“
- Preis: **49 Robux** · Config-Key: `Boost2x30` · Icon-Idee: `glowing blue "x2" chip with a 30 min clock ring`

### Boost2x120 – Boost x2 · 2 h
Name: `Boost x2 · 2 h`
```
+2 h of x2 tower income (playtime – only counts while you are online).
```
Deutsch: „+2 h x2 Turm-Einkommen (Spielzeit – zählt nur, solange du online bist).“
- Preis: **149 Robux** · Config-Key: `Boost2x120` · Icon-Idee: `glowing blue "x2" chip with a 2h clock ring, larger glow`

### Boost5x10 – Turbo x5 · 10 min
Name: `Turbo x5 · 10 min`
```
+10 min of x5 tower income (playtime). Overrides x2 – your x2 time pauses meanwhile.
```
Deutsch: „+10 min x5 Turm-Einkommen (Spielzeit). Überlagert x2 – deine x2-Zeit pausiert so lange.“
- Preis: **99 Robux** · Config-Key: `Boost5x10` · Icon-Idee: `violet "x5" chip with speed lines and a 10 min ring`

### BullParade – Bullen-Parade (ganzer Server)
Name: `Bull Parade (whole server)`
```
×1.5 tower income for everyone in the server, 15 min (another purchase extends it, at most 60 min ahead). Golden parade around the ring and a thank-you banner with your name.
```
Deutsch: „×1,5 Turm-Einkommen für alle im Server, 15 min (erneuter Kauf verlängert, höchstens 60 min im Voraus). Goldene Parade um den Ring und ein Danke-Banner mit deinem Namen.“
- Preis: **199 Robux** · Config-Key: `BullParade` · Icon-Idee: `friendly golden bull statue leading a parade, neon plaza, confetti beams`

### CreditsS – Bau-Gutschein S
Name: `Build Voucher S`
```
CR = 30 min of your steady income (without boosts), at least 5,000 CR. CR only. The exact amount is shown before you buy.
```
Deutsch: „CR = 30 min deines Dauer-Einkommens (ohne Boosts), mindestens 5.000 CR. Nur CR. Die genaue Zahl steht vor dem Kauf da.“
- Preis: **49 Robux** · Config-Key: `CreditsS` · Icon-Idee: `green hexagon CR chip on a blueprint card with letter "S"`

### CreditsM – Bau-Gutschein M
Name: `Build Voucher M`
```
CR = 2 h of your steady income (without boosts), at least 20,000 CR. CR only. The exact amount is shown before you buy.
```
Deutsch: „CR = 2 h deines Dauer-Einkommens (ohne Boosts), mindestens 20.000 CR. Nur CR. Die genaue Zahl steht vor dem Kauf da.“
- Preis: **149 Robux** · Config-Key: `CreditsM` · Icon-Idee: `stack of green hexagon CR chips on a blueprint card with letter "M"`

### CreditsL – Bau-Gutschein L
Name: `Build Voucher L`
```
CR = 6 h of your steady income (without boosts), at least 60,000 CR. CR only. The exact amount is shown before you buy.
```
Deutsch: „CR = 6 h deines Dauer-Einkommens (ohne Boosts), mindestens 60.000 CR. Nur CR. Die genaue Zahl steht vor dem Kauf da.“
- Preis: **399 Robux** · Config-Key: `CreditsL` · Icon-Idee: `crate of green hexagon CR chips on a blueprint card with letter "L"`

### CreditsXL – Bau-Gutschein XL
Name: `Build Voucher XL`
```
CR = 16 h of your steady income (without boosts), at least 150,000 CR. CR only. The exact amount is shown before you buy.
```
Deutsch: „CR = 16 h deines Dauer-Einkommens (ohne Boosts), mindestens 150.000 CR. Nur CR. Die genaue Zahl steht vor dem Kauf da.“
- Preis: **899 Robux** · Config-Key: `CreditsXL` · Icon-Idee: `glowing vault full of green hexagon CR chips, blueprint card "XL"`

### ExpressS – Bau-Express S
Name: `Build Express S`
```
Finishes your build with ≤ 10 min left, otherwise −10 min. No build running: token for the next build (never expires).
```
Deutsch: „Beendet deine Baustelle bei ≤ 10 min Restzeit, sonst −10 min. Ohne Baustelle: Token für den nächsten Bau (verfällt nie).“
- Preis: **19 Robux** · Config-Key: `ExpressS` · Icon-Idee: `small crane with a fast-forward arrow, "S"`

### ExpressM – Bau-Express M
Name: `Build Express M`
```
Finishes your build with ≤ 60 min left, otherwise −60 min. No build running: token for the next build (never expires).
```
Deutsch: „Beendet deine Baustelle bei ≤ 60 min Restzeit, sonst −60 min. Ohne Baustelle: Token für den nächsten Bau (verfällt nie).“
- Preis: **39 Robux** · Config-Key: `ExpressM` · Icon-Idee: `crane with double fast-forward arrows, "M"`

### ExpressL – Bau-Express L
Name: `Build Express L`
```
Finishes your build with ≤ 3 h left, otherwise −3 h. No build running: token for the next build (never expires).
```
Deutsch: „Beendet deine Baustelle bei ≤ 3 h Restzeit, sonst −3 h. Ohne Baustelle: Token für den nächsten Bau (verfällt nie).“
- Preis: **79 Robux** · Config-Key: `ExpressL` · Icon-Idee: `big crane with triple fast-forward arrows, "L"`

### Fireworks – Feuerwerk über deinem Tower
Name: `Fireworks over your tower`
```
20-second show above your tower, visible to everyone in the server.
```
Deutsch: „20-s-Show über deinem Tower, für alle im Server sichtbar.“
- Preis: **29 Robux** · Config-Key: `Fireworks` · Icon-Idee: `blue and violet firework bursts above a glass skyscraper at night`

### Starter – Starter-Paket (einmal je Konto)
Name: `Starter Pack`
```
"Λ Compact Neon" car, "First Bell" watch, Boost x2 · 2 h, Build Voucher M, "Startup" facade neon, "Founder" name frame. Once per account – a second purchase gives 2 × Build Voucher M.
```
Deutsch: „Auto „Λ Kompakt Neon“, Uhr „Erste Glocke“, Boost x2 · 2 h, Bau-Gutschein M, Fassaden-Neon „Startup“, Namensrahmen „Gründer“. Einmal je Konto – ein zweiter Kauf gibt 2 × Bau-Gutschein M.“
- Preis: **99 Robux** · Config-Key: `Starter` · Icon-Idee: `compact neon car, a watch and a small garage with "STARTUP" neon sign, premium card`
- Das Spiel bietet es frühestens in der **2. Sitzung** nach ≥ 15 min an, einmal, mit Knopf „Ansehen“ – nie mit Druck.

### SeasonPremium – Skyline-Pass Premium (je Saison)
Name: `Skyline Pass Premium (season)`
```
Unlocks this season's premium track – retroactively for every tier you reached. Tower rewards only (CR, decor, cosmetics, boosts, car).
```
Deutsch: „Schaltet die Premium-Spur dieser Saison frei – rückwirkend für alle erreichten Stufen. Nur Turm-Belohnungen (CR, Deko, Kosmetik, Boosts, Auto).“
- Preis: **399 Robux** · Config-Key: `SeasonPremium` · Icon-Idee: `diamond-shaped premium badge over a neon skyline, violet gradient`
- Gilt automatisch immer für die **aktive** Saison. Du musst für eine neue Saison **nichts** Neues bei Roblox anlegen.

### SeasonTier1 – +1 Pass-Stufe
Name: `+1 Pass Tier`
```
One Skyline Pass tier. Bought tiers only unlock cosmetics – CR, boosts and tokens require earned season XP.
```
Deutsch: „Eine Skyline-Pass-Stufe. Gekaufte Stufen schalten nur Kosmetik frei – CR, Boosts und Token gibt es nur mit verdienter Saison-XP.“
- Preis: **39 Robux** · Config-Key: `SeasonTier1` · Icon-Idee: `single glowing step of a staircase made of light, "+1"`

### SeasonTier10 – +10 Pass-Stufen
Name: `+10 Pass Tiers`
```
Ten Skyline Pass tiers. Bought tiers only unlock cosmetics – CR, boosts and tokens require earned season XP.
```
Deutsch: „Zehn Skyline-Pass-Stufen. Gekaufte Stufen schalten nur Kosmetik frei – CR, Boosts und Token gibt es nur mit verdienter Saison-XP.“
- Preis: **299 Robux** · Config-Key: `SeasonTier10` · Icon-Idee: `staircase of ten glowing light steps, "+10"`

### GiftBoost – Geschenk-Boost
Name: `Gift Boost`
```
Boost x2 · 30 min for a player of your choice in this server. If they have left when the purchase completes, you get the boost yourself. Only where gifts are allowed.
```
Deutsch: „Boost x2 · 30 min für einen Spieler deiner Wahl in diesem Server. Ist er beim Abschluss nicht mehr da, bekommst du den Boost selbst. Nur, wo Geschenke erlaubt sind.“
- Preis: **59 Robux** · Config-Key: `GiftBoost` · Icon-Idee: `gift box with a glowing "x2" ribbon, blue and green`
- Das Spiel sperrt den Kauf automatisch, wenn Roblox Geschenke für Käufer oder Empfänger nicht erlaubt.

---

## 7. ♛ Abo „Vorstands-Club“ (Experience Subscription)

**So legst du es an** (Details: ANLEITUNG Kapitel 9.4):
Creator Dashboard → dein Spiel → links **Monetization → Subscriptions** → **Create Subscription**.

Name:
```
Executive Club
```
Beschreibung (Englisch):
```
A Build Voucher S to claim every day, tower income ×1.15, +4 h offline cap, exclusive "Club Noir" car paint, rooftop terrace in the exchange hall, +1 streak shield per week and the "Club" tag. Tower and cosmetics only – never stock money (AKY), trades or licences.
```
Beschreibung (Deutsch):
```
Täglich ein Bau-Gutschein S zum Abholen, Turm-Einkommen ×1,15, +4 h Offline-Deckel, exklusiver Auto-Lack „Club Noir“, Dachterrasse im Börsensaal, +1 Serien-Schutz je Woche, Tag „Club“. Nur Turm und Kosmetik – nie Börsengeld (AKY), Trades oder Lizenzen.
```
- Preis: **4,99 $ in Landeswährung**, wenn dein Konto ID-verifiziert ist – sonst **449 Robux pro Monat** · Config-Key: `Club`
- Icon-Idee: `elegant crown symbol on a dark glass rooftop terrace at night, gold and blue, no text`
- ID holen: beim Abo auf **⋯** → **Copy Subscription ID**. Sie sieht so aus: `EXP-1234567890123456789` (mit Buchstaben vorne).
- **Nie** „PRO“ oder „AKYTEX PRO“ nennen (das ist ein echter Tarif der Website).

---

## 8. 📅 Experience Events (Texte für die Spielseite)

Anlegen: ANLEITUNG Kapitel 15.2. Titel kurz halten. Zeiten: Berlin-Zeit (Roblox zeigt sie jedem in seiner Ortszeit).

| Event | Titel (EN) | Beschreibung (EN) | Titel (DE) | Beschreibung (DE) |
|---|---|---|---|---|
| Rally-Mittwoch (Mi 19:00, 30 min) | `Rally Wednesday 📈` | `A sector rally announced days ahead – read the calendar, plan your trades and watch the green aurora over the plaza.` | `Rally-Mittwoch 📈` | `Eine Sektor-Rally, die Tage vorher im Kalender steht – lies den Kalender, plane deine Trades und sieh das grüne Polarlicht über der Plaza.` |
| Crash-Freitag (Fr 19:00, 30 min) | `Crash Friday 🐻` | `The planned market crash of the week. Protect your depot with stop orders and calm the bear on the plaza together.` | `Crash-Freitag 🐻` | `Der geplante Markt-Crash der Woche. Schütz dein Depot mit Verlust-Stopps und beruhigt gemeinsam den Bären auf der Plaza.` |
| IPO-Erstnotiz (Sa 17:00, 30 min) | `IPO Saturday 🔔` | `A new fictional company lists on the AKYTEX Exchange. The prospectus is in the calendar 24 h before.` | `IPO-Samstag 🔔` | `Eine neue erfundene Firma kommt an die AKYTEX Exchange. Der Prospekt steht 24 h vorher im Kalender.` |
| Admin-Abuse (Sa 18:00, 60 min) | `Admin Abuse Saturday ⚡` | `The owner goes live: rallies, money rain, golden hour and fireworks for everyone. Admin market events never count for the league.` | `Admin-Abuse-Samstag ⚡` | `Der Besitzer ist live: Rallys, Geldregen, Golden Hour und Feuerwerk für alle. Admin-Markt-Events zählen nie für die Liga.` |
| Bilanz-Sonntag (So 20:00, 30 min) | `League Finale Sunday 🏆` | `The weekly league finale: the top 10 traders by skill score appear as holograms in the exchange hall.` | `Bilanz-Sonntag 🏆` | `Das Liga-Finale der Woche: die Top 10 nach Skill-Score erscheinen als Hologramme im Börsensaal.` |
| Saison-Start (Mo 18:00, 2 h) | `Season 1: Neon Skyline 🏙️` | `New Skyline Pass with 50 tiers, new decor set, new car and new IPO companies.` | `Saison 1: Neon-Skyline 🏙️` | `Neuer Skyline-Pass mit 50 Stufen, neues Deko-Set, neues Auto und neue IPO-Firmen.` |

Für spätere Saisons nur Nummer und Thema tauschen (Themen: `docs/LIVEOPS.md` Abschnitt 4).

---

## 9. 📣 Social-Link-Satz und Post-Vorlagen

**Der einzige erlaubte Hinweis im Spiel und in der Beschreibung** (Links nur über die Social Links der Spielseite):
```
Check out our social media links on our game's page
```
```
Unsere Social-Links findest du auf der Spielseite
```

**Social Links eintragen:** Creator Dashboard → dein Spiel → **Configure → Social Links** (bzw. **Experience Details → Social Links**)
→ nur die Kanäle **„AKYTEX Games“** (Discord, YouTube …), **nie** die Finanz-Kanäle oder die AKYTEX-Website.

**Post-Vorlagen für deine Kanäle „AKYTEX Games“** (immer mit dem Hinweis „Spielgeld · erfundene Firmen“):
```
⚡ Heute 18:00 Admin-Abuse in AKYTEX TYCOON! Rallys, Geldregen, Golden Hour und Feuerwerk – sei dabei. (Spielgeld · erfundene Firmen)
```
```
🐻 Heute 19:00 Crash-Freitag in AKYTEX TYCOON. Setz deine Verlust-Stopps und beruhige den Bären! (Spielgeld · erfundene Firmen)
```
```
📈 Neuer Code: LAUNCH = 5.000 CR für deinen Tower (läuft am 31.01.2027 ab). Einlösen im Spiel: Knopf Aufgaben → Reiter Login → Code eintippen → Einlösen.
```

> ⚠️ **Keine Belohnungen für Likes, Favoriten oder Abos** versprechen (Roblox-Regel). Keine „Nur heute!“-Druck-Sprüche für
> Robux-Artikel.

---

## 10. 🏅 Badges (15 Stück)

**So legst du ein Badge an** (Details: ANLEITUNG Kapitel 9.5):
Creator Dashboard → dein Spiel → links **Engagement → Badges → Create a Badge** (ältere Ansicht: **Associated Items → Badges**) → Bild (512 × 512, wird rund zugeschnitten),
Name, Beschreibung → **Create** → beim Badge **⋯ → Copy Asset ID**.
Roblox erlaubt nur eine kleine Zahl Badges pro Tag gratis; danach kostet jedes Badge Robux (Betrag steht beim Anlegen).
Lege sie also über mehrere Tage an – fehlende Badges (`Id = 0`) sind einfach aus. **Wird eine ID später eingetragen, bekommen
Spieler das Badge beim nächsten Beitritt rückwirkend.**

| Config-Key | Name (EN) | Beschreibung (EN) | Name (DE) | Beschreibung (DE) | Icon-Idee |
|---|---|---|---|---|---|
| `Welcome` | Welcome | `You arrived in the AKYTEX city.` | Willkommen | Du bist in der AKYTEX-Stadt angekommen. | neon city gate with Λ |
| `FirstFloor` | First Floor | `Build your first floor.` | Erste Etage | Baue deine erste Etage. | garage with "STARTUP" neon |
| `FirstProfit` | First Profit | `Close your first trade in profit.` | Erster Gewinn | Schließe deinen ersten Trade mit Gewinn ab. | green rising candle |
| `Loft` | Loft | `Reach tower stage 3 "Loft".` | Loft | Erreiche Tower-Stufe 3 „Loft“. | brick-and-glass loft |
| `Skyscraper` | Skyscraper | `Reach tower stage 8 "Skyscraper".` | Wolkenkratzer | Erreiche Tower-Stufe 8 „Wolkenkratzer“. | twin-crown skyscraper |
| `OrbitSpire` | Orbit Spire | `Reach the top stage: ΛKYTEX Orbit-Spire.` | Orbit-Spire | Erreiche die höchste Stufe: ΛKYTEX Orbit-Spire. | spire with beam into clouds |
| `FirstIpo` | First Listing | `Ring the bell at your first IPO.` | Erster Börsengang | Läute die Glocke zu deinem ersten Börsengang. | golden bell |
| `TraderLicence` | Trader Licence | `Pass the Trader I licence.` | Trader-Lizenz | Bestehe die Lizenz Trader I. | blue licence card |
| `FondsLicence` | Fund Licence | `Pass the Fund Manager I licence.` | Fondsmanager-Lizenz | Bestehe die Lizenz Fondsmanager I. | violet licence card |
| `Legend` | Exchange Legend | `Become an Exchange Legend – the highest licence.` | Börsen-Legende | Werde Börsen-Legende – die höchste Lizenz. | gold licence card with stars |
| `Millionaire` | Millionaire | `Reach a net worth of 1 million.` | Millionär | Erreiche 1 Mio. Vermögen. | golden head title "1M" |
| `Billionaire` | Billionaire | `Reach a net worth of 1 billion.` | Milliardär | Erreiche 1 Mrd. Vermögen. | golden head title "1B" |
| `CrashSurvived` | Crash Survived | `Get through a market crash with less than 10% loss.` | Crash überstanden | Überstehe einen Crash mit weniger als 10 % Verlust. | calm bear with a shield |
| `LeagueGold` | League Gold | `Reach the Gold tier in a weekly league (skill score 700+).` | Liga Gold | Erreiche in einer Wochen-Liga die Stufe Gold (Skill-Score ab 700). | gold trophy |
| `Streak7` | 7-Day Streak | `Play 7 days in a row.` | 7-Tage-Serie | Spiel 7 Tage in Folge. | calendar with 7 glowing days |

---

## 11. ❓ Fragebogen-Hilfe (Kurzfassung)

Die vollständigen Antworten mit Begründung stehen in **ANLEITUNG Kapitel 10**. Kurz: Gewalt, Blut, Angst, derber Humor, starke
Sprache, Romantik, Alkohol → **Nein** · Unplayable gambling content → **Nein** · Social Hangout → **Nein** · Free-form user creation →
**Nein** · Sensible Themen / endlose Feeds → **Nein** · Paid random items → **Nein** · Paid item trading → **Nein** ·
Generative KI → **Nein**. Ergebnis: **Minimal**. **Vor dem Ausfüllen den Live-Wortlaut lesen** – Roblox ändert Fragen manchmal.

---

## 12. ✅ Spickzettel: alles auf einen Blick

| | Name bei Roblox | Preis (R$) | Config-Key |
|---|---|---|---|
| Pass | Exchange VIP | 399 | `VIP` |
| Pass | 2x Income | 499 | `Income2x` |
| Pass | 3x Income | 1.199 | `Income3x` |
| Pass | Auto Collect | 249 | `AutoCollect` |
| Pass | Offline Vault 24 h | 349 | `OfflineVault` |
| Pass | Staff+ | 299 | `StaffPlus` |
| Pass | Build Crew Pro | 399 | `BuildCrew` |
| Pass | Terminal Designer ⏸ (noch nicht anlegen) | 249 | `TerminalDesigner` |
| Pass | Mega Garage | 199 | `MegaGarage` |
| Pass | Neon Jetpack | 449 | `Jetpack` |
| Pass | ΛKYTEX Λ-1 Hypercar | 799 | `Lam1` |
| Pass | Chrono Collection | 349 | `Chrono` |
| Pass | Neon Facade Kit | 349 | `FacadeKit` |
| Pass | Tycoon Bundle | 749 | `TycoonBundle` |
| Produkt | Boost x2 · 30 min | 49 | `Boost2x30` |
| Produkt | Boost x2 · 2 h | 149 | `Boost2x120` |
| Produkt | Turbo x5 · 10 min | 99 | `Boost5x10` |
| Produkt | Bull Parade (whole server) | 199 | `BullParade` |
| Produkt | Build Voucher S | 49 | `CreditsS` |
| Produkt | Build Voucher M | 149 | `CreditsM` |
| Produkt | Build Voucher L | 399 | `CreditsL` |
| Produkt | Build Voucher XL | 899 | `CreditsXL` |
| Produkt | Build Express S | 19 | `ExpressS` |
| Produkt | Build Express M | 39 | `ExpressM` |
| Produkt | Build Express L | 79 | `ExpressL` |
| Produkt | Fireworks over your tower | 29 | `Fireworks` |
| Produkt | Starter Pack | 99 | `Starter` |
| Produkt | Skyline Pass Premium (season) | 399 | `SeasonPremium` |
| Produkt | +1 Pass Tier | 39 | `SeasonTier1` |
| Produkt | +10 Pass Tiers | 299 | `SeasonTier10` |
| Produkt | Gift Boost | 59 | `GiftBoost` |
| Abo | Executive Club | 4,99 $ bzw. 449 R$/Monat | `Club` |

Zusammen: **14 Gamepässe** (davon 13 sofort, Terminal Designer erst später), **17 Developer Products**, **1 Abo**, dazu **15 Badges**. Robux-Preise änderst du im Creator Dashboard;
der Shop zeigt immer den **Live-Preis** von Roblox. Trag einen neuen Preis zusätzlich in `Config → Shop` bei `Price` ein
(nur Planwert für Prüfungen).

---

## 13. 📨 Schick mir das zurück

Kopier den Kasten. Schreib hinter jedes `=` die passende ID. Noch nicht angelegt? Stelle leer lassen.

```
-- Gamepässe
VIP = 
Income2x = 
Income3x = 
AutoCollect = 
OfflineVault = 
StaffPlus = 
BuildCrew = 
TerminalDesigner = 
MegaGarage = 
Jetpack = 
Lam1 = 
Chrono = 
FacadeKit = 
TycoonBundle = 

-- Developer Products
Boost2x30 = 
Boost2x120 = 
Boost5x10 = 
BullParade = 
CreditsS = 
CreditsM = 
CreditsL = 
CreditsXL = 
ExpressS = 
ExpressM = 
ExpressL = 
Fireworks = 
Starter = 
SeasonPremium = 
SeasonTier1 = 
SeasonTier10 = 
GiftBoost = 

-- Abo (beginnt mit EXP-)
Club = 

-- Gruppe "AKYTEX Games" (Zahl aus roblox.com/communities/<ID>/…, ANLEITUNG Kapitel 13 Punkt 9)
GroupId = 

-- Badges
Welcome = 
FirstFloor = 
FirstProfit = 
Loft = 
Skyscraper = 
OrbitSpire = 
FirstIpo = 
TraderLicence = 
FondsLicence = 
Legend = 
Millionaire = 
Billionaire = 
CrashSurvived = 
LeagueGold = 
Streak7 = 
```

**Kopier den ausgefüllten Kasten in den Chat.** Claude trägt alles in `Config → Shop` und `Config → Progression` ein und baut dir
eine neue `AkytexTycoon.rbxlx`. Wie die neue Version in dein Spiel kommt: ANLEITUNG Kapitel 20 (Weg A).
