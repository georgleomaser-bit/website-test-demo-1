# AKYTEX TYCOON – Asset-Liste (Hybrid-Assets, Besitzer-Wunsch 17)

## Wofür ist diese Datei?

AKYTEX TYCOON sieht **ohne ein einziges hochgeladenes Asset** fertig aus: Autos, Möbel, Uhren, Roboter, Stadt und Sounds
baut der Code aus Roblox-Bordmitteln („Code-Rezept“). Zusätzlich hat **jedes sichtbare Objekt mit Upgrade-Potenzial** in `Config`
einen **Asset-Platz**. Dort kannst du später ein eigenes 3D-Modell, Bild oder einen Sound eintragen – zum Beispiel mit
**Higgsfield** erzeugt. Diese Liste nennt **jeden Platz**: wo er in `Config` steht, welche Art Datei hineingehört, welche Größe
sinnvoll ist, eine **Prompt-Idee für Higgsfield** und was passiert, wenn nichts eingetragen ist (Rückfall).

**Die wichtigste Regel:** `0` heißt immer „Code-Rezept“. Lädt ein eingetragenes Asset nicht (gelöscht, privat, noch in der
Moderation), schaltet das Spiel **automatisch** auf das Code-Rezept zurück. Du kannst also nichts kaputt machen.

| Wort | Bedeutung |
|---|---|
| **Asset** | Eine hochgeladene Datei bei Roblox: 3D-Modell (Mesh), Bild (Image) oder Sound (Audio) |
| **Asset-Platz** | Die Stelle in `Config`, an der die Nummer (ID) des Assets steht |
| **Mesh-Platz** | `Asset = { MeshId = 0, TextureId = 0, Scale = 1, Offset = … }` – für 3D-Modelle |
| **Bild-Platz** | `ImageId = 0` – für Logos, Karten, Shop-Bilder |
| **Sound-Platz** | `SoundId = 0` bzw. eine Rolle in `Config.Client.Sounds` – für Töne und Musik |
| **MeshId** | Nummer des 3D-Modells (steht nach dem Import beim MeshPart unter **MeshId**) |
| **TextureId** | Nummer des Farbbilds für das Modell (steht beim MeshPart unter **TextureID**; 0 = keine Textur) |
| **Scale** | Vergrößerung (1 = Originalgröße, 2 = doppelt so groß) |
| **Offset** | Verschiebung/Drehung gegenüber dem Code-Modell (normal: keine) |
| **Dreiecke (Tris)** | Maß für die Detail-Menge eines 3D-Modells. Weniger = flüssiger am Handy |
| **Rückfall** | Was das Spiel zeigt, wenn der Platz `0` ist oder das Asset nicht lädt |

---

## 1. Der Weg: Higgsfield → Roblox Studio → Config

1. **Platz aussuchen** (Tabellen ab Abschnitt 5). Fang mit Dingen an, die man oft sieht: Λ City (Gratis-Auto), Börsenglocke,
   Brunnen, Luftschiff, Tiko, Firmen-Logos.
2. **In Higgsfield erzeugen.** Nimm die **Prompt-Grundlage** (Abschnitt 4) und hänge das **Motiv** aus der Tabelle an.
   - 3D-Modell: als **GLB** (oder FBX/OBJ) exportieren.
   - Bild: als **PNG** (Logos mit durchsichtigem Hintergrund).
   - Sound: als **OGG** oder **MP3**.
3. **Prüfen, bevor du hochlädst:**
   - Keine echte Marke, kein echtes Logo, kein Text mit echten Firmen, keine echten Automarken-Formen „wie …“.
   - Nichts mit Casino, Karten, Würfeln, Glücksrad, Spielautomaten, Alkohol, Waffen, Blut (sonst ist das Alters-Label weg).
   - Passt zum AKYTEX-Look (dunkles Glas, Metall, Marmor, blaues Neon `#4f8cff`) – siehe `docs/STYLE-AKYTEX.md`.
4. **In Roblox Studio hochladen** (immer mit deinem Konto **RizzG315**, siehe Abschnitt 1.1):
   - **3D-Modell:** Menüleiste **File → Import 3D…** (der „3D Importer“) → Datei wählen → im Vorschau-Fenster prüfen →
     **Import**. Das Modell erscheint in der Welt. Klick das **MeshPart** im **Explorer** an → im Fenster **Properties**
     bei **MeshId** steht `rbxassetid://123456789` → die **Zahl** ist deine **MeshId**. Bei **TextureID** steht ggf. die
     Zahl der Textur → deine **TextureId**. Danach das Modell aus der Welt löschen (es wird nur die Nummer gebraucht).
   - **Bilder und Sounds:** **View → Asset Manager** (neue Oberfläche: **Window → Asset Manager**) → Knopf **Bulk Import**
     (Pfeil nach oben) → Dateien wählen → warten. Danach Rechtsklick auf das Bild/den Sound → **Copy ID to Clipboard**
     (bzw. **Copy Asset ID**).
   - Viele Dateien auf einmal: ebenfalls **Bulk Import** im Asset Manager (geht auch für Meshes).
5. **ID eintragen** – entweder Claude schicken (Abschnitt 3, Weg A, empfohlen) oder selbst (Weg B).
6. **Play** drücken und anschauen. Passt die Größe nicht: `Scale` ändern (z. B. `1.2`). Steht es falsch: `Offset` (Weg B).
7. **Publish** (ANLEITUNG Kapitel 20).

### 1.1 Besitzrechte, Moderation, Nutzungsrechte
- **Das Asset muss dem Spiel-Ersteller gehören.** Lade alles mit **RizzG315** hoch, solange das Spiel unter RizzG315 läuft.
  Ziehst du das Spiel später in die Gruppe „AKYTEX Games“ um, lade die Assets **in die Gruppe** hoch (beim Hochladen oben
  den Ersteller „AKYTEX Games“ wählen) – sonst bleiben sie im Spiel unsichtbar bzw. stumm und das Spiel nimmt das Code-Rezept.
- **Moderation:** Roblox prüft jedes Asset. Bis es freigegeben ist, zeigt das Spiel das Code-Rezept. Abgelehnte Assets nicht
  erneut hochladen, sondern den Prompt ändern.
- **Higgsfield-Nutzungsrechte:** Prüfe in deinem Higgsfield-Abo, dass **kommerzielle Nutzung** erlaubt ist (Roblox-Spiele mit
  Robux-Verkäufen sind kommerziell).
- **Sounds:** Audio-Uploads haben bei Roblox ein **Monats-Kontingent** (mit ID-Verifizierung größer). Lade nur die Töne hoch,
  die du wirklich tauschen willst.
- Asset-IDs sind **öffentlich** (stehen in `Config`, die jeder Spieler bekommt). Lade also nichts Privates hoch.

---

## 2. Formate und Größen

| Art | Format | Empfehlung | Roblox-Grenze (Stand 2026, live prüfen) |
|---|---|---|---|
| 3D-Modell (Mesh) | **GLB** (oder FBX, OBJ), **ein** Mesh je Platz | so wenige Dreiecke wie möglich – Richtwerte je Tabelle; Ursprung (Pivot) unten in der Mitte | bis 20.000 Dreiecke je MeshPart |
| Textur zum Modell | **PNG**, quadratisch | 512 × 512 (kleine Teile) bis 1024 × 1024 (Autos, Wahrzeichen) | größere Bilder verkleinert Roblox auf 1024 × 1024 |
| Bild (Logo, Karte, Shop) | **PNG** | 512 × 512 (Logos, Shop-Bilder), 1024 × 512 (Banner), durchsichtiger Hintergrund für Logos | 1024 × 1024 |
| Sound | **OGG** oder **MP3**, 44,1 kHz | UI-Töne ≤ 0,3 s, Kauf/Verkauf ≤ 0,6 s, Glocke ≤ 3 s, Alarm ≤ 4 s, Motor als **nahtlose Schleife** 2–4 s, Musik als Schleife 1–3 min | bis 7 Minuten je Datei |

**Wichtig für 3D:** Der Code nutzt nur **ein MeshPart mit Farb-Textur** (TextureID). PBR-Karten (SurfaceAppearance: Normal,
Metalness, Roughness) aus dem Importer werden **nicht** übernommen – back die Optik in die Farb-Textur ein. Bei Autos ersetzt das
Mesh nur die **Karosserie**; Räder, Sitz und Physik bleiben Code (sonst fährt nichts).

---

## 3. ID eintragen

### Weg A – Claude schicken (empfohlen)
Füll den Kasten ganz unten (Abschnitt 9) aus und kopier ihn in den Chat. Claude trägt alles ein, prüft es und baut dir eine
neue `AkytexTycoon.rbxlx`.

### Weg B – selbst eintragen
Im Studio links im **Explorer**: **ReplicatedStorage → Shared → Config →** Datei doppelklicken. Mit **Cmd + F** suchen.

**Regel für `Offset`:** In den Dateien **`Tower`**, **`Decor`** und **`Lifestyle`** schreibst du `Offset = IDENTITY`,
in **allen anderen** Dateien `Offset = CFrame.identity`. (Grund: Diese drei Dateien werden auch von automatischen Tests
ohne Roblox geladen.)

**B1 – Platz steht direkt da** (`Asset = slot()`, z. B. `Blimp = slot(),`, oder `ImageId = 0`):
Ersetze `slot()` durch eine ausgeschriebene Tabelle, zum Beispiel in `Config → City`:
```lua
	Blimp = { MeshId = 123456789, TextureId = 987654321, Scale = 1, Offset = CFrame.identity }, -- Luftschiff
```
oder in `Config → Vehicles` in der Zeile mit `Key = "LamCity"`:
```lua
		Recipe = "LamCity", Paint = "Polar", Asset = { MeshId = 123456789, TextureId = 0, Scale = 1, Offset = CFrame.identity }, SoundId = 0, Display = false },
```
Bei Bildern/Sounds nur die `0` durch die Zahl ersetzen: `ImageId = 0,` → `ImageId = 123456789,`.

**B2 – Platz wird von einer Hilfsfunktion gebaut** (Deko, Uhren, Accessoires, Firmen-Logos – dort steht kein `slot()` je Eintrag):
Füge **ganz unten in der Datei, direkt über der letzten Zeile `return …`**, eine Nachtrag-Zeile ein:
```lua
-- Meine Assets (Nachtrag)
Decor.ByKey.DeskStartup.Asset = { MeshId = 123456789, TextureId = 0, Scale = 1, Offset = IDENTITY }
```
```lua
Lifestyle.ByKey.Copper.Asset = { MeshId = 123456789, TextureId = 0, Scale = 1, Offset = IDENTITY }
Lifestyle.ByKey.Copper.ImageId = 123456789
```
```lua
Companies.ById[1].ImageId = 123456789   -- Logo von Cognivo KI (Nummer = ID in der Tabelle 5.7)
```

**Danach immer:** **Play** → im **Output** darf keine orange Zeile mit `[Config]` stehen (sonst Tippfehler, z. B. Komma vergessen).
Dann **Publish**.

---

## 4. Prompt-Grundlage für Higgsfield

Häng an jeden Prompt diese Grundlage an (englisch funktioniert meist besser):

**3D-Modelle:**
```
game-ready 3D model, single mesh, low poly but detailed silhouette, clean topology, baked lighting in the color texture,
premium dark fintech style, dark glass, brushed metal, black marble, subtle electric blue neon accents (#4f8cff),
no text, no logos, no real brands, friendly and family-safe, neutral studio background
```

**Bilder (Logos, Karten, Shop-Bilder):**
```
clean flat vector illustration, dark navy background (#0b0f17) or transparent, electric blue (#4f8cff) and green (#22c55e)
accents, minimal geometric shapes, high contrast, no text except the given letter, no real brands, family-safe
```

**Sounds:**
```
clean modern UI sound for a premium finance game, soft, short, no distortion, no casino or slot machine sounds,
no coin cascades, no voice
```

**Nie in einen Prompt schreiben:** echte Marken oder Firmen („like Lamborghini“, „Rolex style“), Casino, Würfel, Karten,
Glücksrad, Spielautomat, Geldregen pro Trade, Waffen, Blut, Alkohol, Zigarren, Party, Nachtclub, echte Personen.

---

## 5. Alle Asset-Plätze

### 5.1 Autos – `Config → Vehicles → Cars` (16 × Mesh-Platz `Asset` + 16 × Sound-Platz `SoundId`)
Suche: `Key = "<Schlüssel>"`. **Asset** = nur die Karosserie (Räder/Physik bleiben Code), **SoundId** = eigener Motor-Klang
als nahtlose Schleife (sonst Code-Rezept aus `action_falling.ogg`, Tonhöhe nach Tempo).
Richtwert: Kompakt/Limousine ≤ 6.000 Dreiecke, Sport/Super/Hyper ≤ 10.000; Textur 1024 × 1024. Länge wie das Code-Auto
(in Studio messen) – sonst `Scale` anpassen. **Rückfall:** Auto aus Parts (Wedge/Zylinder) mit Neon-Unterbodenlicht.

| Schlüssel | Name | Klasse | Quelle / Preis | Motiv für den Prompt |
|---|---|---|---|---|
| `LamCity` | Λ City | Kompakt | gratis (Tutorial) | small friendly city hatchback, rounded, pearl white with blue light strip |
| `VoltaHatch` | Volta Hatch | Kompakt | 25.000 CR | electric hatchback, cyan paint, smooth panels |
| `PixelMini` | Pixel Mini | Kompakt | 120.000 CR | tiny cube-shaped city car, pink paint, playful |
| `LamNeon` | Λ Kompakt Neon | Kompakt | Starter-Paket | compact car, midnight blue, glowing neon edges |
| `Stratos` | Stratos Sedan | Limousine | 750.000 CR | clean business sedan, silver metallic |
| `Nordlicht` | Nordlicht Executive | Limousine | 4.000.000 CR | long executive limousine, black metallic, chrome line |
| `VelocitraS` | Velocitra S | Sport | 60.000.000 CR | sports coupe, red, sharp nose, rear spoiler |
| `NeonCoupe` | Neon Coupé | Sport | 250.000.000 CR | low coupe with blue neon side lines |
| `StreakGT` | Streak-GT | Sport | Login-Kalender | grand tourer, orange with dark stripe |
| `Kometa` | Kometa SL | Super | 6.000.000.000 CR | wedge-shaped supercar, titanium grey |
| `AuroraGT` | Aurora GT | Super | 40.000.000.000 CR | supercar, deep green metallic, aurora-like light strip |
| `QuasarX` | Quasar X | Hyper | 600.000.000.000 CR | futuristic hypercar, cosmic violet metallic, light bar |
| `VelocitraH` | Velocitra Hyper | Hyper | 4.000.000.000.000 CR | track hypercar, deep red, big rear wing |
| `Singularity` | Singularity | Hyper | Lizenz Börsen-Legende | black hypercar with a glowing ring motif, ultra sleek |
| `OrbitR` | Orbit-R | Hyper | Skyline-Pass S1 Stufe 50 | space-themed hypercar, nebula violet paint, orbit ring light |
| `Lam1` | ΛKYTEX Λ-1 | Hyper | Gamepass | flagship hypercar, arctic white, blue Λ-shaped light signature |

### 5.2 Tower – `Config → Tower`
**Personal-Roboter** (`Tower.Staff`, Suche `Key = "<Schlüssel>"`, darunter `Asset = slot(),`): ≤ 4.000 Dreiecke, Textur 512.
**Rückfall:** Roboter aus Parts (Kugelkopf mit Gesicht, Kapselkörper, Schwebering), bewegt per Code.

| Schlüssel | Name | Motiv für den Prompt |
|---|---|---|
| `Intern` | Praktikant P-1 | small cute hovering office robot, round head with screen face |
| `Analyst` | Analyst A-3 | slim analyst robot with tablet, blue visor |
| `Senior` | Senior-Droid S-7 | tall elegant robot in suit-like plating |
| `Quant` | Quant-Mainframe Q-9 | compact mainframe robot with glowing data panels |
| `Janitor` | Hausmeister-Bot | friendly cleaning robot with brush arms |
| `Security` | Sicherheits-Bot | calm guard robot, rounded, blue light, no weapons |

**Börsengang-Kronen** (`Tower.Crowns`, Suche `Key = "Silver"` usw.): ≤ 6.000 Dreiecke. **Rückfall:** Krone aus Neon-/Metall-Parts.

| Schlüssel | Name | ab Börsengängen | Motiv für den Prompt |
|---|---|---|---|
| `Silver` | Silber-Krone | 1 | skyscraper crown spire in silver metal |
| `Gold` | Gold-Krone | 3 | golden skyscraper crown with antenna |
| `Platinum` | Platin-Krone | 5 | platinum crown with stepped rings |
| `Holo` | Holo-Krone | 10 | holographic violet crown, translucent |
| `Orbit` | Orbit-Ring | 20 | floating orbit ring above a spire, violet glow |

**Tower-Bauteile** (`Tower.Assets`, Suche `Crane = slot()` usw.). **Rückfall:** Code-Bauteil aus Parts.

| Platz | Was | Dreiecke | Motiv für den Prompt |
|---|---|---|---|
| `Tower.Assets.Crane` | Baukran auf dem Dach | ≤ 6.000 | modern rooftop tower crane, white and blue |
| `Tower.Assets.Lobby` | Lobby-Deko im Erdgeschoss | ≤ 8.000 | luxury lobby reception desk with marble and neon line |
| `Tower.Assets.Vault` | Tresor in der Lobby | ≤ 3.000 | futuristic round vault door, brushed steel, blue ring light |
| `Tower.Assets.CashGate` | goldenes Kassen-Tor | ≤ 3.000 | golden archway gate, sleek, glowing edges |
| `Tower.Assets.RespektPillar` | Respekt-Säule | ≤ 2.000 | slim glass pillar with light stripes |
| `Tower.Assets.Elevator` | Glas-Aufzugskabine | ≤ 3.000 | glass elevator cabin, metal frame |
| `Tower.Assets.PlotSign` | Plot-Schild | ≤ 1.500 | modern glass sign stand, empty panel |

### 5.3 Deko – `Config → Decor` (68 × Mesh-Platz, Weg B2: `Decor.ByKey.<Schlüssel>.Asset = …`)
Richtwert: ≤ 2.000 Dreiecke (große Teile wie Flügel, Aquarium, Koi-Teich, Brunnen ≤ 5.000), Textur 512 × 512.
**Rückfall:** Möbel aus Block/Wedge/Zylinder nach dem Rezept in `Config.Decor` (Farben, Material). Komfort-Punkte ändern sich nicht.
Motiv = englischer Name + Set-Stil (Startup: warm wood and blue accents · Corporate: leather, brass, dark wood ·
Glas & Chrom: reflective glass and chrome · Neon-Cyber: dark surfaces with blue and violet neon strips · Luxe-Gold: marble, gold
trim, velvet · Zen-Garten: stone, bamboo, soft light · Saison 1: dark glass, blue neon, mini skyscrapers).

| Schlüssel | Name | Set | Quelle / Preis | Komfort | Motiv für den Prompt |
|---|---|---|---|---|---|
| `DeskStartup` | Startup-Schreibtisch | Startup | 2.500 CR | 1 | startup desk |
| `BeanBag` | Sitzsack | Startup | 4.000 CR | 1 | bean bag |
| `PlantMonstera` | Monstera | Startup | 6.000 CR | 1 | monstera |
| `Whiteboard` | Ideen-Whiteboard | Startup | 8.000 CR | 1 | idea whiteboard |
| `NeonArrow` | Neon-Pfeil | Startup | 12.000 CR | 2 | neon arrow |
| `MiniBull` | Mini-Bulle | Startup | Login-Kalender | 2 | mini bull |
| `SmoothieBar` | Smoothie-Station | Startup | 15.000 CR | 2 | smoothie station |
| `RacingChair` | Racing-Stuhl | Startup | 18.000 CR | 2 | racing chair |
| `PosterRocket` | Raketen-Poster | Startup | 20.000 CR | 1 | rocket poster |
| `RugStartup` | Startup-Teppich | Startup | 25.000 CR | 2 | startup rug |
| `DeskExec` | Chef-Schreibtisch | Corporate | 60.000 CR | 2 | executive desk |
| `SofaLeather` | Ledersofa | Corporate | 90.000 CR | 3 | leather sofa |
| `Bookshelf` | Bücherregal | Corporate | 120.000 CR | 2 | bookshelf |
| `PlantFicus` | Ficus | Corporate | 150.000 CR | 2 | ficus |
| `GlobeBrass` | Messing-Globus | Corporate | 200.000 CR | 3 | brass globe |
| `ClockWall` | Börsen-Standuhr | Corporate | 250.000 CR | 2 | exchange clock |
| `MeetingTable` | Konferenztisch | Corporate | 300.000 CR | 3 | meeting table |
| `LampBrass` | Stehlampe Messing | Corporate | 400.000 CR | 2 | brass floor lamp |
| `TrophyBronze` | Liga-Pokal Bronze | Corporate | Liga-Pokal | 3 | league cup bronze |
| `TrophySilver` | Liga-Pokal Silber | Corporate | Liga-Pokal | 4 | league cup silver |
| `DeskGlass` | Glas-Schreibtisch | Glas & Chrom | 1.200.000 CR | 3 | glass desk |
| `EggChair` | Ei-Sessel Chrom | Glas & Chrom | 1.800.000 CR | 3 | chrome egg chair |
| `SculptChrome` | Chrom-Skulptur | Glas & Chrom | 2.500.000 CR | 3 | chrome sculpture |
| `AquariumSmall` | Aquarium | Glas & Chrom | 3.500.000 CR | 4 | aquarium |
| `LampArc` | Bogenlampe | Glas & Chrom | 4.500.000 CR | 2 | arc lamp |
| `TableGlass` | Glas-Couchtisch | Glas & Chrom | 5.500.000 CR | 3 | glass coffee table |
| `ArtPrism` | Prisma-Kunst | Glas & Chrom | 7.000.000 CR | 3 | prism art |
| `ChartWall` | Chart-Wand | Glas & Chrom | 9.000.000 CR | 3 | chart wall |
| `BambooGlass` | Bambus im Glas | Glas & Chrom | 11.000.000 CR | 3 | bamboo in glass |
| `RugGeo` | Geo-Teppich | Glas & Chrom | 14.000.000 CR | 3 | geo rug |
| `DeskNeon` | Neon-Desk | Neon-Cyber | 25.000.000 CR | 3 | neon desk |
| `SignLambda` | ΛKYTEX-Neonschild | Neon-Cyber | 35.000.000 CR | 4 | Λkytex neon sign |
| `HoloGlobe` | Holo-Globus | Neon-Cyber | 50.000.000 CR | 4 | holo globe |
| `CyberChair` | Cyber-Sessel | Neon-Cyber | 70.000.000 CR | 3 | cyber lounge chair |
| `TickerTotem` | Ticker-Säule | Neon-Cyber | 90.000.000 CR | 4 | ticker totem |
| `NeonTree` | Neon-Baum | Neon-Cyber | 120.000.000 CR | 4 | neon tree |
| `RoboDog` | Robo-Hund | Neon-Cyber | 150.000.000 CR | 4 | robo dog |
| `LightCube` | Licht-Kubus | Neon-Cyber | 180.000.000 CR | 3 | light cube |
| `RetroConsole` | Retro-Konsole | Neon-Cyber | 220.000.000 CR | 4 | retro console |
| `RugCircuit` | Platinen-Teppich | Neon-Cyber | 280.000.000 CR | 3 | circuit rug |
| `DeskGold` | Gold-Schreibtisch | Luxe-Gold | 500.000.000 CR | 4 | gold desk |
| `SofaVelvet` | Samt-Sofa | Luxe-Gold | 800.000.000 CR | 4 | velvet sofa |
| `StatueBull` | Gold-Bulle | Luxe-Gold | 1.200.000.000 CR | 5 | golden bull |
| `Chandelier` | Kronleuchter | Luxe-Gold | 1.800.000.000 CR | 4 | chandelier |
| `GrandPiano` | Flügel | Luxe-Gold | 2.500.000.000 CR | 5 | grand piano |
| `VaseGold` | Gold-Vase | Luxe-Gold | 3.200.000.000 CR | 3 | gold vase |
| `AquariumGrand` | Riesen-Aquarium | Luxe-Gold | 4.500.000.000 CR | 5 | grand aquarium |
| `FountainGold` | Gold-Brunnen | Luxe-Gold | 6.000.000.000 CR | 5 | gold fountain |
| `TrophyGold` | Liga-Pokal Gold | Luxe-Gold | Liga-Pokal | 5 | league cup gold |
| `TrophyDiamond` | Liga-Pokal Diamant | Luxe-Gold | Liga-Pokal | 5 | league cup diamond |
| `Bonsai` | Bonsai | Zen-Garten | 10.000.000.000 CR | 4 | bonsai |
| `SandGarden` | Sand-Garten | Zen-Garten | 15.000.000.000 CR | 4 | sand garden |
| `StoneLantern` | Steinlaterne | Zen-Garten | 22.000.000.000 CR | 3 | stone lantern |
| `WaterBowl` | Wasserschale | Zen-Garten | 30.000.000.000 CR | 4 | water bowl |
| `CherryTree` | Kirschbaum | Zen-Garten | 45.000.000.000 CR | 5 | cherry tree |
| `Gong` | Klang-Gong | Zen-Garten | 60.000.000.000 CR | 3 | sound gong |
| `TeaTable` | Tee-Tisch | Zen-Garten | 80.000.000.000 CR | 4 | tea table |
| `KoiPond` | Koi-Teich | Zen-Garten | 120.000.000.000 CR | 5 | koi pond |
| `BambooScreen` | Bambus-Paravent | Zen-Garten | 180.000.000.000 CR | 3 | bamboo screen |
| `CalmPod` | Ruhe-Kapsel | Zen-Garten | 250.000.000.000 CR | 5 | calm pod |
| `SkylineModel` | Skyline-Modell | Saison 1 | Skyline-Pass | 4 | skyline model |
| `NeonBench` | Neon-Bank | Saison 1 | Skyline-Pass | 3 | neon bench |
| `HoloTicker` | Holo-Ticker | Saison 1 | Skyline-Pass | 4 | holo ticker |
| `SkylineRug` | Skyline-Teppich | Saison 1 | Skyline-Pass | 3 | skyline rug |
| `NeonPalm` | Neon-Palme | Saison 1 | Skyline-Pass | 4 | neon palm |
| `OrbitLamp` | Orbit-Lampe | Saison 1 | Skyline-Pass | 3 | orbit lamp |
| `BlimpModel` | Luftschiff-Modell | Saison 1 | Skyline-Pass | 4 | blimp model |
| `SkylineTrophy` | Skyline-Pokal | Saison 1 | Skyline-Pass | 5 | skyline cup |

### 5.4 Lifestyle – `Config → Lifestyle`
**Uhren** (15 × `Asset` + 15 × `ImageId` für das Boutique-Bild, Weg B2: `Lifestyle.ByKey.<Schlüssel>…`):
≤ 1.500 Dreiecke (sehr klein am Handgelenk), Textur 512; Boutique-Bild 512 × 512 PNG.
**Rückfall:** Uhr aus 6–10 Parts mit Neon-Zifferblatt, Zeiger drehen per Code; Bild = Code-Grafik.
Motiv: „luxury wrist watch '<englischer Name>', round case, glowing blue neon dial, no brand, no text“.

| Schlüssel | Name | Quelle / Preis |
|---|---|---|
| `FirstBell` | Erste Glocke | Starter-Paket |
| `Copper` | Kupfer Classic | 50.000 CR |
| `NeonPulse` | Neon Pulse | 2.000.000 CR |
| `ChronoL` | Chrono Λ | 80.000.000 CR |
| `OrbitGold` | Orbit Gold | 3.000.000.000 CR |
| `DiamondTicker` | Diamant-Ticker | 2.000.000.000.000 CR |
| `WeekChrono` | Wochen-Chrono | Login-Kalender (Tag 7) |
| `SkylineChrono` | Skyline-Chrono | Skyline-Pass Premium Stufe 30 |
| `BellTourbillon` | Glocken-Tourbillon | Vorstand „Lifestyle“ Stufe 5 |
| `ChronoNight` | Chrono Nacht | Gamepass Chrono-Kollektion |
| `ChronoAurora` | Chrono Aurora | Gamepass Chrono-Kollektion |
| `ChronoArctic` | Chrono Arktis | Gamepass Chrono-Kollektion |
| `ChronoSolar` | Chrono Solar | Gamepass Chrono-Kollektion |
| `ChronoMidnight` | Chrono Mitternacht | Gamepass Chrono-Kollektion |
| `Legend` | Legenden-Uhr | Lizenz Börsen-Legende |

**Accessoires** (8 × `Asset` + 8 × `ImageId`): ≤ 1.500 Dreiecke (Aura-Ringe ≤ 2.000), Textur 512.
**Rückfall:** Accessoire aus Parts.

| Schlüssel | Name | Quelle / Preis | Motiv für den Prompt |
|---|---|---|---|
| `Sunglasses` | Sonnenbrille | 10.000 CR | sleek dark sunglasses with thin blue rim |
| `TiePin` | Krawattennadel | 100.000 CR | minimal silver tie pin with small Λ-shaped bar |
| `Briefcase` | Aktentasche | 1.000.000 CR | slim black leather briefcase, metal clasps |
| `LapelNeon` | Revers-Neon | 20.000.000 CR | small glowing neon lapel pin |
| `AuraBlue` | Aura-Ring Blau | 500.000.000 CR | floating blue light ring around the body |
| `AuraGold` | Aura-Ring Gold | 10.000.000.000 CR | floating golden light ring |
| `HoloBadge` | Holo-Abzeichen | Lizenz Fondsmanager | holographic chest badge, violet glow |
| `CommunityCrown` | Community-Krone | Gruppe „AKYTEX Games“ | small floating crown, blue glass |

**Neon-Jetpack** (`Lifestyle.Jetpack.Asset`, Weg B2: `Lifestyle.Jetpack.Asset = …`): ≤ 3.000 Dreiecke.
Motiv: „compact futuristic jetpack, white and blue, glowing neon thrusters“. **Rückfall:** Jetpack aus Parts mit Neon-Spur.

### 5.5 Stadt – `Config → City → City.Assets` (11 × Mesh-Platz, Weg B1, `Offset = CFrame.identity`)
**Rückfall:** Code-Modell aus Parts.

| Platz | Was | Dreiecke | Motiv für den Prompt |
|---|---|---|---|
| `City.Assets.Blimp` | Luftschiff mit ΛKYTEX-Logo (fliegt über der Stadt) | ≤ 8.000 | sleek dark airship with blue light strips, empty side panel for a logo |
| `City.Assets.Fountain` | Brunnen auf der Plaza | ≤ 8.000 | modern black marble fountain with circular basin and blue lights |
| `City.Assets.Bell` | goldene Börsenglocke | ≤ 5.000 | large golden bell on a modern podium, elegant |
| `City.Assets.Lighthouse` | Leuchtturm in der Marina | ≤ 6.000 | modern white lighthouse with glass top |
| `City.Assets.Jet` | Deko-Jet im Hangar | ≤ 10.000 | sleek private business jet, white with blue stripe |
| `City.Assets.Yacht` | Deko-Yachten (befahrbar erst v1.1) | ≤ 10.000 | modern luxury motor yacht, white and dark glass |
| `City.Assets.Heli` | Helikopter-Platzhalter (v1.1) | ≤ 8.000 | modern executive helicopter, dark blue |
| `City.Assets.Villa` | Deko-Villen am Villenhügel | ≤ 10.000 | modern hillside villa, glass and concrete, infinity pool |
| `City.Assets.Drone` | Lieferdrohne (bis zu 14 gleichzeitig) | ≤ 1.500 | small quadcopter delivery drone with box |
| `City.Assets.TrafficCar` | Verkehrsauto (bis zu 32 gleichzeitig) | ≤ 2.500 | simple generic city car, neutral colour |
| `City.Assets.Tiko` | Tiko-Hologramm auf der Plaza | ≤ 4.000 | friendly hologram robot with ticker screen face, translucent blue |

### 5.6 Events – `Config → Events → Events.Assets` (10 × Mesh-Platz, Weg B1, `Offset = CFrame.identity`)
**Rückfall:** Code-Modell aus Parts.

| Platz | Was | Dreiecke | Motiv für den Prompt |
|---|---|---|---|
| `Events.Assets.Truck` | gepanzerter Geldtransporter | ≤ 6.000 | armored cash transport van, dark blue, cartoon-clean |
| `Events.Assets.Drone` | Liefer-Drohne (Event) | ≤ 1.500 | delivery drone carrying a glowing parcel |
| `Events.Assets.Bull` | goldener Bulle (Rally, Parade) | ≤ 6.000 | friendly stylized golden bull statue, smooth |
| `Events.Assets.Bear` | freundlicher Bär (Crash-Event) | ≤ 8.000 | friendly cartoon bear made of soft shapes, calm, not scary |
| `Events.Assets.Coin` | Neon-Münze (Geldregen, viele gleichzeitig) | ≤ 300 | glowing green hexagon token (CR chip), no symbols of real money |
| `Events.Assets.Bundle` | Geld-Bündel (Transporter) | ≤ 300 | small stack of green game notes with band, fictional |
| `Events.Assets.Package` | Drohnen-Paket | ≤ 300 | small delivery box with blue light seam |
| `Events.Assets.Orb` | Vertrauens-Kugel (Bär-Event) | ≤ 300 | soft glowing blue orb |
| `Events.Assets.Hologram` | Roboter-CEO der Pressekonferenz | ≤ 6.000 | robot CEO hologram at a lectern, translucent blue |
| `Events.Assets.Crane` | Bau-Boom-Kran | ≤ 6.000 | yellow and white construction crane, clean |

### 5.7 Bilder (`ImageId`)
**Firmen-Logos** – `Config → Companies` (48 × `ImageId`, Weg B2: `Companies.ById[<ID>].ImageId = …`).
512 × 512 PNG mit durchsichtigem Hintergrund, gut lesbar in 24 px. **Rückfall:** Code-Logo (Buchstabe + Grundform in Sektorfarbe).
Motiv: „flat vector logo for fictional company '<Name>', bold letter <Buchstabe>, <Sektorfarbe> on transparent background“.
Sektorfarben: Tech `#4f8cff` · Energie `#22d3ee` · Mobilität `#8b5cf6` · Konsum `#f59e0b` · Gaming `#ec4899` · Finanzen `#facc15`.

| ID | Kürzel | Name | Sektor | Logo |
|---|---|---|---|---|
| 1 | `CGVO` | Cognivo KI | Tech & KI | Buchstabe „C“ |
| 2 | `KRWK` | Kernwerk Systems | Tech & KI | Buchstabe „K“ |
| 3 | `QTRX` | Quantorix Quantum | Tech & KI | Buchstabe „Q“ |
| 4 | `LMRA` | Lumora Chips | Tech & KI | Buchstabe „L“ |
| 5 | `NMBY` | Nimbusly Cloud | Tech & KI | Buchstabe „N“ |
| 6 | `PXWK` | Pixelwerk Robotics | Tech & KI | Buchstabe „P“ |
| 7 | `SNWK` | Sonnwerk Solar | Energie & Klima | Buchstabe „S“ |
| 8 | `FSNT` | Fusionaut | Energie & Klima | Buchstabe „F“ |
| 9 | `NBRZ` | Nordbrise Wind | Energie & Klima | Buchstabe „N“ |
| 10 | `HDRV` | Hydrava | Energie & Klima | Buchstabe „H“ |
| 11 | `VLTR` | Voltaris | Energie & Klima | Buchstabe „V“ |
| 12 | `GTHM` | Geotherma | Energie & Klima | Buchstabe „G“ |
| 13 | `ORBV` | Orbivo Space | Mobilität & Raumfahrt | Buchstabe „O“ |
| 14 | `MGLN` | Magliner | Mobilität & Raumfahrt | Buchstabe „M“ |
| 15 | `VLCT` | Velocitra Motors | Mobilität & Raumfahrt | Buchstabe „V“ |
| 16 | `DRNR` | Dronaro | Mobilität & Raumfahrt | Buchstabe „D“ |
| 17 | `ARLF` | Aerolift | Mobilität & Raumfahrt | Buchstabe „A“ |
| 18 | `RTXO` | Robotaxo | Mobilität & Raumfahrt | Buchstabe „R“ |
| 19 | `KNSX` | Knusperix | Konsum & Food | Buchstabe „K“ |
| 20 | `BLBR` | Blubbro | Konsum & Food | Buchstabe „B“ |
| 21 | `SNKA` | Sneakora | Konsum & Food | Buchstabe „S“ |
| 22 | `BGPT` | Burgerplanet | Konsum & Food | Buchstabe „B“ |
| 23 | `PFFR` | Pfotenfreund | Konsum & Food | Buchstabe „P“ |
| 24 | `SPWK` | Spielwerk Toys | Konsum & Food | Buchstabe „S“ |
| 25 | `ARCN` | Arcadeon Games | Gaming & Medien | Buchstabe „A“ |
| 26 | `STMR` | Streamora | Gaming & Medien | Buchstabe „S“ |
| 27 | `PLVO` | Playverso VR | Gaming & Medien | Buchstabe „P“ |
| 28 | `MEMT` | Memetastic Media | Gaming & Medien | Buchstabe „M“ |
| 29 | `ESPV` | Esportiva Arena | Gaming & Medien | Buchstabe „E“ |
| 30 | `NNBT` | Neonbeat Records | Gaming & Medien | Buchstabe „N“ |
| 31 | `TWBK` | Towerbank | Finanzen & Immobilien | Buchstabe „T“ |
| 32 | `SKLA` | Skylinea | Finanzen & Immobilien | Buchstabe „S“ |
| 33 | `GLDR` | Goldader Mining | Finanzen & Immobilien | Buchstabe „G“ |
| 34 | `SCHF` | Sicherhafen | Finanzen & Immobilien | Buchstabe „S“ |
| 35 | `KLPY` | Klickpay | Finanzen & Immobilien | Buchstabe „K“ |
| 36 | `BKRZ` | Baukranz | Finanzen & Immobilien | Buchstabe „B“ |
| 40 | `AKX36` | AKYTEX 36 | ETF / Übung | Buchstabe „Λ“ |
| 41 | `AKXT` | AKYTEX Tech | ETF / Übung | Buchstabe „Λ“ |
| 42 | `AKXE` | AKYTEX Energie | ETF / Übung | Buchstabe „Λ“ |
| 43 | `AKXM` | AKYTEX Mobilität | ETF / Übung | Buchstabe „Λ“ |
| 44 | `AKXK` | AKYTEX Konsum | ETF / Übung | Buchstabe „Λ“ |
| 45 | `AKXG` | AKYTEX Gaming | ETF / Übung | Buchstabe „Λ“ |
| 46 | `AKXF` | AKYTEX Finanzen | ETF / Übung | Buchstabe „Λ“ |
| 100 | `NRNT` | Neuronauten | Tech & KI | Buchstabe „N“ |
| 101 | `FLRA` | Flora Energy | Energie & Klima | Buchstabe „F“ |
| 102 | `MNDW` | Mondwerk | Mobilität & Raumfahrt | Buchstabe „M“ |
| 103 | `RBCF` | Robochef | Konsum & Food | Buchstabe „R“ |
| 250 | `ACAD` | Akademie Übungsaktie | ETF / Übung | Buchstabe „A“ |

**Lizenzkarten** – `Config → Progression → Progression.Licences` (10 × `ImageId`, am Ende der Zeile mit `Key = "<Schlüssel>"`).
1024 × 640 PNG (Karte im Querformat). **Rückfall:** Code-Karte (goldener Rahmen, Name, Stempel).
Motiv: „premium licence card design '<Name>', dark glass card, gold foil border, stamp seal, no real institution“.

| Schlüssel | Lizenz | Schlüssel | Lizenz |
|---|---|---|---|
| `Azubi1` | Azubi I | `Trader3` | Trader III |
| `Azubi2` | Azubi II | `Fonds1` | Fondsmanager I |
| `Azubi3` | Azubi III | `Fonds2` | Fondsmanager II |
| `Trader1` | Trader I | `Fonds3` | Fondsmanager III |
| `Trader2` | Trader II | `Legende` | Börsen-Legende |

**Shop-Bilder** – `Config → Shop` (14 Pässe + 17 Produkte + Abo = 32 × `ImageId`, Weg B1: unter `Key = "<Schlüssel>"` steht
`ImageId = 0,`). 512 × 512 PNG. Das ist das Bild **im Spiel-Shop**. (Das Icon im Creator Dashboard lädst du dort separat hoch –
du kannst dasselbe PNG nehmen, KOPIERVORLAGEN Abschnitt 5/6.) **Rückfall:** Code-Karte mit dem Symbol aus `Icon`.
Motive: siehe Icon-Ideen in `docs/KOPIERVORLAGEN.md` (bei jedem Pass und Produkt).

| Pässe | Produkte | Abo |
|---|---|---|
| `VIP`, `Income2x`, `Income3x`, `AutoCollect`, `OfflineVault`, `StaffPlus`, `BuildCrew`, `TerminalDesigner`, `MegaGarage`, `Jetpack`, `Lam1`, `Chrono`, `FacadeKit`, `TycoonBundle` | `Boost2x30`, `Boost2x120`, `Boost5x10`, `BullParade`, `CreditsS`, `CreditsM`, `CreditsL`, `CreditsXL`, `ExpressS`, `ExpressM`, `ExpressL`, `Fireworks`, `Starter`, `SeasonPremium`, `SeasonTier1`, `SeasonTier10`, `GiftBoost` | `Club` (in `Shop.Subscription`) |

**Saison-Bild** – `Config → Season → Season.Seasons` (je Saison 1 × `ImageId`, unter `Id = 1`): 1024 × 512 PNG, Banner im
Pass-Fenster. Motiv S1: „neon skyline at night, dark glass skyscrapers, blue and violet neon, wide banner, no text“.
**Rückfall:** Code-Banner mit Verlauf.

### 5.8 Sounds – `Config → Client → Client.Sounds` (23 Rollen, Weg B1: `UIClick = 0,` → `UIClick = 123456789,`)
**Rückfall:** eingebautes Rezept aus den Roblox-Bordmitteln (umgestimmt, mit Effekten). `0` = Rezept, `Music = 0` = keine Musik.

| Rolle | Wann | Motiv für den Prompt |
|---|---|---|
| `UIClick` | Knopf gedrückt | soft glassy click |
| `UIHover` | Maus über Knopf | very subtle tick |
| `UIError` | Fehler/abgelehnt | low soft double blip |
| `Buy` | Kauf ausgeführt | short rising two-tone tick |
| `Sell` | Verkauf ausgeführt | short falling two-tone tick |
| `Profit` | Verkauf mit Gewinn | calm gentle three-note arpeggio |
| `Loss` | Verkauf mit Verlust | single low neutral tone |
| `CashRegister` | Tresor eingesammelt | soft register chime, no coin cascade |
| `TickerTick` | Ticker-Laufband | barely audible tick |
| `MarketBell` | Börsenglocke (jede 20 min) | elegant bell strike with short echo |
| `CrashAlarm` | Crash-Warnung | gentle two-tone alert, not scary |
| `RallyFanfare` | Rally | short bright fanfare |
| `ElevatorDing` | Aufzug angekommen | classic elevator ding |
| `Construct` | Etage fertig | soft construction thud with sparkle |
| `MoneyRain` | Geldregen | light sparkly shimmer |
| `Engine` | Auto-Motor (Schleife) | smooth electric engine hum, seamless loop |
| `LevelUp` | Level/Lizenz | uplifting short chime |
| `Achievement` | Erfolg | bright two-note success |
| `Pickup` | Bündel/Paket/Münze eingesammelt | tiny pop |
| `Whoosh` | Fenster/Kamera | short air whoosh |
| `Countdown` | Countdown-Ticks | soft clock tick |
| `Notify` | Hinweis/Toast | soft notification blip |
| `Music` | Hintergrund-Musik (Schleife) | calm lo-fi electronic city music, seamless loop |

Zusätzlich je Auto ein **Motor-Klang** über `SoundId` in `Config → Vehicles` (Abschnitt 5.1).

---

## 6. Plätze, die die Spec nennt, die es in `Config` aber (noch) nicht gibt

DESIGN.md §C14.3 nennt auch einen **Ladebildschirm-Hintergrund** und **UI-Icons** (HUD-Knöpfe) als Bild-Plätze. In den aktuellen
Config-Dateien gibt es dafür **keinen** Eintrag (`Config.Client.Splash` hat nur Zeiten). Der Ladebildschirm und die Knöpfe sind
komplett aus Code gebaut. Willst du dort eigene Bilder: Claude schreiben „Bild-Platz für Ladebildschirm und HUD-Icons anlegen“.

Deine Bild-Ideen dafür schon jetzt: Ladebildschirm 1920 × 1080 „dark neon city skyline at dawn, blue haze, no text“;
HUD-Icons 256 × 256 je „simple white line icon of a tower / shopping bag / checklist / graduation cap / car / two people /
trophy / gear on transparent background“.

---

## 7. Bilder für die Spielseite (keine Config-Plätze, aber Higgsfield hilft)

| Bild | Größe | Wo hochladen |
|---|---|---|
| Spiel-Icon | 512 × 512 PNG | Studio: **Home → Game Settings → Basic Info → Game Icon** |
| Thumbnails (bis zu 10) | 1920 × 1080 PNG/JPG | Studio: **Home → Game Settings → Basic Info → Thumbnails** (bzw. **Screenshots & Videos**) |
| Gamepass-, Produkt-, Badge-Icons | 512 × 512 PNG (Badges werden rund zugeschnitten) | beim Anlegen (ANLEITUNG Kapitel 9) |

Ideen und Regeln stehen in `docs/KOPIERVORLAGEN.md`, Abschnitt 4. **Kein Text, der Geld verspricht**, keine Robux-Bilder,
kein „Raytracing“, keine echten Marken.

---

## 8. Reihenfolge-Empfehlung (größter Effekt zuerst)

1. `City.Assets.Bell`, `City.Assets.Fountain`, `City.Assets.Blimp` (sieht jeder in der ersten Minute)
2. `Vehicles` → `LamCity` (Gratis-Auto) und `Lam1` (Gamepass-Auto)
3. `City.Assets.Tiko` und `Tower.Staff` → `Intern`, `Janitor` (Tutorial)
4. Firmen-Logos der 12 Azubi-Werte + `AKX36` (Einsteiger sehen die zuerst)
5. `Events.Assets.Bull` und `Events.Assets.Bear` (Rally/Crash, Clips für TikTok)
6. Deko-Set „Startup“ (erste Etagen), dann die teuren Sets
7. Sounds `MarketBell`, `Profit`, `CashRegister`, `Engine`

---

## 9. 📨 Asset-IDs zurückschicken (für Weg A)

Kopier den Kasten, schreib hinter jedes `=` die Nummer und schick ihn Claude. Leere Zeilen einfach weglassen.
Bei 3D-Modellen: MeshId und TextureId (0, wenn keine Textur). `Scale` nur, wenn es nicht 1 sein soll.

```
-- 3D-Modelle (MeshId / TextureId / Scale)
Vehicles.LamCity = MeshId    / TextureId    / Scale
Vehicles.Lam1 = MeshId    / TextureId    / Scale
City.Bell = MeshId    / TextureId    / Scale
City.Fountain = MeshId    / TextureId    / Scale
City.Blimp = MeshId    / TextureId    / Scale
City.Tiko = MeshId    / TextureId    / Scale
Events.Bull = MeshId    / TextureId    / Scale
Events.Bear = MeshId    / TextureId    / Scale
Tower.Crane = MeshId    / TextureId    / Scale
Decor.DeskStartup = MeshId    / TextureId    / Scale
Lifestyle.Copper = MeshId    / TextureId    / Scale
(weitere nach demselben Muster: <Datei>.<Schlüssel> = MeshId … / TextureId … / Scale …)

-- Bilder (ImageId)
Companies.1 = 
Companies.40 = 
Licences.Azubi1 = 
Shop.VIP = 
Lifestyle.Copper.Image = 
Season.1 = 

-- Sounds (SoundId)
Sounds.MarketBell = 
Sounds.Profit = 
Sounds.Music = 
Vehicles.Lam1.Sound = 
```
