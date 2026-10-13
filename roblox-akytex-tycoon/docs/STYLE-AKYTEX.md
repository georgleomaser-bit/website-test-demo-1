# AKYTEX TYCOON – AKYTEX-Look (verbindlich)

> **Herkunft:** Teil 1 ist die Stil-Datei aus CLUTCH CLASH (`roblox-shooter/docs/STYLE-AKYTEX.md`, Besitzer-Entscheidung
> 12.10.2026), übernommen und an AKYTEX TYCOON angepasst. Teil 2–4 sind neu: **Welt-Regeln** (DESIGN.md §A4/§A5),
> **Chart-Regeln** (DESIGN.md §B7.5, REUSE.md §5.4) und das **AKYTEX-Marken-Blatt** (REUSE.md §8, DESIGN.md §0.5).
> Teil 5 ist eine Kurz-Prüfliste für jeden neuen Bildschirm, jedes Objekt und jedes Bild.
>
> **Unterschied zu CLUTCH CLASH:** Dort blieb die Welt bunt (Spielzeug-Arenen). In AKYTEX TYCOON ist **auch die Welt**
> im AKYTEX-Look: dunkle Premium-Fintech-Stadt aus Glas, Marmor und Metall, Neon nur als Akzent.

Der Besitzer will alles „wie AKYTEX“ (seine Trading-Plattform): dunkel, edel, modern, klar, ultra smooth.
Alle Werte stehen als Tokens im Code (`src/client/Modules/UI.luau` → `UI.Theme`, Server-Spiegel `Config.Colors`,
Welt-Werte `Config.City.Look`). **Nie Farben hart kodieren**, immer Tokens benutzen.

---

## Teil 1 – Oberfläche (aus CLUTCH CLASH übernommen, für AT angepasst)

### 1.1 Farben (Tokens in `UI.Theme`, Server: `Config.Colors`)

| Token | Hex | Verwendung |
|---|---|---|
| `Bg` / `Bg2` | #0b0f17 / #0f141d | Vollflächen, Fenster-Hintergrund, Balken-Rückseiten |
| `Surface` (= Panel) | #121824 | Fenster (Glas: BackgroundTransparency ≈ 0.08), HUD-Panels (≈ 0.12) |
| `Surface2` (= PanelLight) | #1a2130 | Karten, Zeilen, Eingabefelder |
| `Hover` | #1f2838 | Hover-Zustand von Karten/Zeilen/Knöpfen |
| `Border` | #1f2937 | 1-px-Rahmen (UIStroke Thickness 1, ApplyStrokeMode Border), Trennlinien, Chart-Raster |
| `Text` / `Text2` / `Muted` | #e6ecf5 / #aab4c3 / #7d889a | Haupttext / Nebentext / sehr leise |
| `Accent` / `AccentDeep` | #4f8cff / #2962ff | Primär-Knöpfe, aktive Tabs, Fokus, Fortschritt, TRADE-Knopf, **AKY-Symbol** |
| `Up` | #22c55e | Kursanstieg, Gewinn-Tick, Kauf-Erfolg, + Werte, **CR-Symbol** |
| `Down` | #ef4444 | Kursrückgang, Fehler, − Werte |
| `Warn` | #eab308 | Warnungen, Premium-Akzente |
| Extra (nur Akzent) | `Orange` #f59e0b · `Purple` #8b5cf6 · `Pink` #ec4899 · `Gold` #facc15 · `Cyan` #22d3ee | Sektor-Chips, Seltenheit, Kronen – nie als Vollfläche großer Fenster |

- **AKY (Börsengeld)** immer blaue Münze mit „Λ“ in `Accent`. **CR (Credits, Turmgeld)** immer grüner Sechskant-Chip in `Up`.
  Die beiden Symbole dürfen nie vertauscht oder vermischt werden (Robux-Firewall, DESIGN.md §0.1).
- **Gold `#facc15`** nur für Kronen, Börsenglocke, Hall of Fame, Titel-Schilder.
- **Farbenblind-Modus** (Einstellung): Up/Down werden zu `Accent` #4f8cff / `Orange` #f59e0b; ▲/▼ sind immer sichtbar.

### 1.2 Schrift (`UI.Fonts`, `UI.Faces`)
- `Main` BuilderSansBold (Knöpfe, Labels) · `Body` BuilderSans (Fließtext) · `Strong` BuilderSansExtraBold (große Zahlen in Karten).
- **Neu für AT:** `BuilderExtended` (≈ Website-Schrift Unbounded) für Logo, Fenstertitel und große Zahlen;
  `BuilderMono` für **alle Preise, G/V, Achsen und Tabellen** (gleich breite Ziffern, nichts zittert beim Ticken).
  Beide über `FontFace` (`Font.new("rbxasset://fonts/families/BuilderExtended.json", Enum.FontWeight.Bold)`).
- Rückfall, falls Umlaute oder „Λ“ in Studio fehlen: `Heading`/`Banner` = Michroma, `Number` = TitilliumWeb (TESTPLAN prüft das).
- **Keine** FredokaOne/LuckiestGuy/Bangers/Gotham.
- Keine dicke schwarze Kontur. Über der 3D-Welt (HUD, Billboards, schwebende Zahlen) eine **feine** Kontur:
  UIStroke Thickness 1–1.5, Farbe #000000, Transparency 0.35–0.5 (oder TextStroke 0.6).
- Roblox-TextLabels haben keinen Buchstaben-Abstand → breite Wortmarke „ΛKYTEX“ = ein Label je Buchstabe in einem
  waagerechten `UIListLayout` (Abstand ≈ 0,3 × Schriftgröße) oder das Frame-Logo (Teil 4.5).

### 1.3 Formen & Flächen
- Ecken: Fenster 14–16 px, Karten/Knöpfe 10–12 px, Chips/Pillen voll rund.
- Fenster = Glas: `Surface` mit Transparency ≈ 0.08, 1-px-`Border`, BlurEffect 8–10 hinter offenen Fenstern,
  dezenter Schatten (unscharfes dunkles Frame dahinter, Transparency ≈ 0.6) statt dicker Kontur.
- Fenster-Kopf: Titel links in `BuilderExtended` bzw. `Heading` (GROSS, 18–22 px), rechts ein schlichtes ✕ (Ghost-Knopf).
- Trennlinien 1 px `Border`.
- **Kein CanvasGroup um Live-Inhalte** (Charts, Zähler): macht Text am Handy unscharf und rendert bei jeder Änderung neu.

### 1.4 Knöpfe
- **Primär**: Fläche `Accent`, Text weiß BuilderSansBold, Ecke 10–12, keine 3D-Lippe, keine dicke Kontur, kein Comic-Glanz.
  Hover etwas heller (+8 %), Druck: Scale 0.97 (Feder), kurzer Farb-Flash.
- **Sekundär**: Fläche `Surface2`, 1-px-`Border`, Text `Text`; Hover `Hover`.
- **KAUFEN** (Order-Ticket): Variante Success (`Up`). **VERKAUFEN**: Variante Danger (`Down`). Gleich groß, gleich ruhig.
- **Gefahr**: `Down` · **Premium**: Verlauf `Warn` → Orange nur dezent · **Ghost**: transparent, Text `Text2`, Hover `Hover`.
- Mindestgröße am Handy 44 px; Touch-Knöpfe im Spiel (SPRINT, BOOST, HANDBREMSE, REAKTION, Kauf/Verkauf-Leiste) **≥ 64 px**.
- **Robux-Knöpfe** heißen „Ansehen“, „Details“, „Preis anzeigen“ – **nie** „JETZT KAUFEN“, „LETZTE CHANCE“, „Nur heute!“
  (DESIGN.md Muss-Regel 17).

### 1.5 Bewegung (iOS-artig, wie die Website, `ReducedFx` = `prefers-reduced-motion`)

| Bewegung | Wert |
|---|---|
| Fenster auf | Fade 0,18 s + Scale 0,96 → 1 in 0,26 s **Quint Out** + 8 px Gleiten von unten |
| Fenster zu | 0,14 s Quad In |
| Hover | 0,12 s Quad Out |
| Drücken / Loslassen | 0,08 s auf 0,97 / 0,3 s **Back Out** (leichte Feder) |
| Federn | `Spring.new(v, 25–30, 0.58)` (≈ Website `--spring`), weich: Speed 8–12, Dämpfer 0,70 (`--spring-soft`) |
| Zähler | `alpha = 1 − e^(−7t)`, höchstens 30 Hz |
| Balken füllen | 0,35 s Quart Out |
| Toast | rein 0,22 s Quint Out, raus 0,2 s Quad In |
| Blur hinter Fenstern | Größe 9, rein 0,22 s Quart Out |

Kein Elastic, kein starkes Überschwingen. Mit `ReducedFx`: Kamerafahrten sofort, Partikel aus, Bewegungen kürzer.

### 1.6 Meldungen
- Toasts: schlanke Pille oben Mitte (`Surface` + `Border`, Punkt-Icon in Up/Down/Accent/Warn), gleitet 8 px herein.
- **News-Karte („Dynamic Island“)**: oben Mitte, Schlagzeile mit **fettem Stärke-Wort**, Quellen-Sterne, Sektor-Chip,
  ruhiger Balken **„Händler lesen …“** (8 s). **Kein Kauf-Knopf**, kein Countdown-Ring, kein Blinken, keine Ausrufezeichen-Ketten.
- Große Momente (Stufen-Morph, Lizenz, Börsengang, Titel): zentriert in `BuilderExtended`, Akzent-Unterstrich/Glow.
  **Kein** großer Text für einzelne Trades.

### 1.7 HUD (ersetzt „HUD im Kampf“ aus CLUTCH CLASH)
- Oben: Ticker-Leiste (28 px, gepoolte Labels, 120-s-Schleife), Pillen in der Mitte („Glocke in m:ss“, nächstes Event,
  Boost-Restzeit, „ADMIN-ABUSE aktiv – zählt nicht für die Liga“).
- Links oben: CR-Zähler (grüner Chip) und **Multiplikator-Chip** „x7,4“ (Tippen = Aufschlüsselung mit Herkunft
  „verdient / Skill / gekauft / Event“). AKY steht nur im Terminal/Depot, nie neben dem Robux-Shop.
- Unten Mitte: großer **TRADE**-Knopf (`Accent`). Rechts: Knopf-Leiste (Tower, Shop, Aufgaben, Akademie, Garage, Freunde,
  Ranglisten, Einstellungen; Admin nur für den Besitzer, ganz unten).
- Tresor-Ring zeigt den Füllstand; voll = ruhiges Rot-Glühen, kein Blinken.

### 1.8 Welt-Texte (Server-Billboards/SurfaceGuis: Plot-Schilder, Bestenlisten, Ticker-Wände, Namensschilder)
- Dunkle Glas-Tafeln (`Bg`/`Surface`, Transparency 0.1–0.2) mit 1-px-Akzent- oder `Border`-Rahmen, Text BuilderSansBold,
  Titel BuilderExtended/Michroma, Preise BuilderMono.
- SurfaceGui: `LightInfluence = 0`, `Brightness` 1,5–3 (leuchtet mit Bloom unter Future-Licht), `MaxDistance` ≈ 300,
  `SizingMode = PixelsPerStud`, 30–50 Pixel je Stud.
- Server-Code hat kein `UI.Theme`: dieselben Hex-Werte aus `Config.Colors` benutzen.

---

## Teil 2 – Welt-Regeln „AKYTEX Neon City“ (DESIGN.md §A4/§A5, Werte in `Config.City.Look`)

### 2.1 Stimmung und Farben
- Dunkle Premium-Fintech-Stadt: **Glas, Marmor, gebürstetes Metall**. Neon **nur als Akzent: höchstens 8 %** jeder sichtbaren Fläche.
- Tag: blau-graues Glas, weiche Sonne. Nacht: AKYTEX-Neon Accent `#4f8cff`, Up `#22c55e`, Down `#ef4444`;
  Premium/Penthouse kosmisch `#7c5cff → #b36bff`; Gold `#facc15` nur für Kronen, Glocke, Hall of Fame.
- Nachthimmel/Hero-Momente: Space-Set `#03040a`, `#7c9cff`, Verlauf `#3b5bdb → #7c5cff → #b36bff`, Gold `#ffcf6e`.
- Sektorfarben (Firmen-Schilder, Heatmap, Chips): Tech `#4f8cff` · Energie `#22d3ee` · Mobilität `#8b5cf6` · Konsum `#f59e0b` ·
  Gaming `#ec4899` · Finanzen `#facc15`.

### 2.2 Materialien

| Fläche | Regel |
|---|---|
| Fassaden | Glass (Transparency 0.3, Reflectance 0.2) mit Metal-Pfosten `#1f2937` |
| Böden | Marble (Reflectance 0.12–0.18); Plaza schwarzer Marmor 0.15 mit blauem Raster |
| Straßen | Asphalt / Concrete |
| Showroom | SmoothPlastic Reflectance 0.3 |
| Neon | nur als 0,2–0,4-Stud-Streifen |
| Verboten | `Ice` (sieht billig aus), Neon-Vollflächen |

### 2.3 Licht (Projektdatei, Skripte setzen `Technology` nie)
- `Lighting.Technology = Future`, `EnvironmentSpecularScale = 1`, `EnvironmentDiffuseScale = 1` (steht in `default.project.json`).
- GraphicsService (löscht vorher eigene alte Instanzen): Atmosphere Density 0,30 Tag / 0,38 Nacht, Haze 1,2 / 1,8, Color `#c7d6ff`;
  Bloom Intensity 0,55, Size 24, Threshold 1,5; SunRays Intensity 0,04; ColorCorrection Contrast 0,08, Saturation 0,05;
  DepthOfField nur in Menüs/Kamerafahrten (Client).
- Lichtbudget je Grafikstufe (`Config.Quality.Tiers`): Low 6 · Medium 16 · High 32 · Ultra 64 echte Lichter.
- **Wort-Regel:** in Texten, Thumbnails und Werbung „**Future-Licht**“ – **nie „Raytracing“** (Roblox bietet kein echtes Raytracing).

### 2.4 Tag/Nacht = Börsentag (20 min, auf allen Servern gleich)
Minute :00 Sonnenaufgang (ClockTime 6,5) mit Glocke · :06 Mittag (12) · :12 Sonnenuntergang (18,5) · :12,5–:18,5 Nacht (21 → 4) ·
:19,5 Dämmerung. Fensterlichter schalten ab ClockTime 18,5 als Kaskade von unten nach oben (0,05 s je Etage).

### 2.5 Markt-Wetter
Regime < 0,85 klar · 0,85–1,2 Wolken (`Clouds.Cover 0.45`) · > 1,2 Sturm (Regen-Partikel am Kameraort, harmlose Blitz-Flashes).
**Crash:** ColorCorrection Tint `#ffdada`, Saturation −0,15, Ticker-Wände rot, Sirenen-Rezept, freundlicher Part-Bär.
**Rally:** grüne Polarlicht-Beams über der Plaza, warmer Tint `#fff4dc`, goldener Bulle läuft den Ring.
Kein Effekt trifft je einen Avatar (keine Gewalt, keine Angst-Inhalte).

### 2.6 Silhouetten, Bausteine, Bewegung in der Welt
- Jede der **12 Tower-Stufen** hat eine eigene Krone/Silhouette, aus 600 Studs erkennbar (Garage-Rolltor … Orbit-Spire mit Antennen-Beam).
- Bausteine **aus Code** (nie Pflicht-Upload): Fassadenmodul (Glasfeld, Pfosten, Neonband), Deckenplatte, Aufzugsschacht,
  Kronen, Antenne + Leuchtfeuer, Helipad, LED-Wand (SurfaceGui), Hologramm (Neon + Beam + `particles/sparkles_main.dds`),
  Möbel aus Block/Wedge/Zylinder, Autos (Wedge/Zylinder + VehicleSeat + Constraints), Uhren (Zylinder + Neon-Zifferblatt),
  Roboter (Kugelkopf mit SurfaceGui-Gesicht, Kapselkörper, Schwebering).
- **Keine eigenen Animationen:** Roboter, Aufzug, Kräne, Bulle/Bär, Uhrzeiger bewegen sich prozedural (CFrame/Tween im einen
  `PreRender`-Loop). Avatare nur Roblox-Standard-Emotes (wave/cheer/point/dance). Keine Fußgänger-NPCs.
- Jedes sichtbare Objekt mit Upgrade-Potenzial hat einen **Asset-Platz** in `Config` (0 = Code-Rezept) – Liste: `docs/ASSET-LISTE.md`.

### 2.7 Sound
Nur `Sfx`-Rezepte aus den eingebauten Dateien (`roblox-shooter/docs/ASSETS.md` §2) oder eigene IDs in `Config.Client.Sounds`.
Rollen: UIClick/UIHover/UIError, Buy (Tick 1,26 → 1,5), Sell (1,5 → 1,26), Profit (ruhiges Arpeggio), Loss (tiefer Einzelton),
CashRegister, TickerTick (Lautstärke 0,15), MarketBell (1,0/1,26/1,5 + Echo), CrashAlarm, RallyFanfare, ElevatorDing, Construct,
MoneyRain, Engine (Loop, Tonhöhe nach Tempo) u. a. **Keine Casino-Klänge**, keine Münz-Kaskade pro Trade, keine Spielautomaten-Töne.

### 2.8 Logo & Ladebildschirm
ΛKYTEX aus gedrehten Frames (UI) bzw. Neon-Parts (Welt) nach den `logo.svg`-Strichen (Teil 4.5). Ladebildschirm spielt die
Website-Splash nach: Ring zeichnet 1,3 s, Kerzen steigen (18 ms Versatz), Buchstaben 0,09 s Versatz, Taglines bei 1,25/1,45 s;
höchstens 4 s, endet früher wenn geladen, Tippen überspringt. Disclaimer-Zeile „Spielgeld · erfundene Firmen · kein echtes Geld“.

---

## Teil 3 – Chart-Regeln (DESIGN.md §B7.5, REUSE.md §5.4) – „ultra smooth“, 60 FPS

### 3.1 Aufbau
- Ein **ungedrehter** Frame mit `ClipsDescendants = true`: Preisfläche ≈ 72 %, Volumen-Streifen ≈ 14 % (Balken 35 % transparent),
  optionaler Indikator-Bereich, rechte Preisachse 56 px, Zeitachse 18 px.
- Zeitrahmen 1s · 5s · 1m · 5m · 15m · 1T (20 min) · 1W (140 min). Stile Kerzen, Hohl, Linie, Fläche (nur High/Ultra),
  Heikin-Ashi (Profi-Schicht).
- Fadenkreuz + OHLC-Pille: Maus (`InputChanged`), Touch ziehen, Steuerkreuz kerzenweise.

### 3.2 Farben

| Teil | Farbe |
|---|---|
| Raster | `Border` #1f2937 |
| Achsentext | `Muted` #7d889a, BuilderMono, feste TextSize (**kein** `TextScaled`) |
| Steigende / fallende Kerze | `Up` #22c55e / `Down` #ef4444 (Farbenblind: Accent / Orange) |
| Letzter Kurs (Linie + Pille) | `Up` oder `Down` je Richtung |
| SMA20 / SMA50 / SMA200 | `#f5b942` / `#4f8cff` / `#e056fd` |
| EMA9 / EMA21 | `#00d1b2` / `#ff7a45` |
| Bollinger / VWAP / RSI | `#7c8cff` / `#ffd166` / `#b388ff` |
| Markttiefe/Umsätze | Beschriftung „simuliert“ |

### 3.3 Darstellungs-Vertrag (Pflicht für jeden Chart, auch Welt-Monitore)
1. **Alles einmal anlegen** (Pool im `new()`): je Kerzen-Slot Körper + Docht + Volumen; 60 (Handy) / 90 / 120 (PC) Kerzen;
   **≤ 900 GuiObjects** je Chart; nie `Instance.new` beim Ticken.
2. **Scale-Koordinaten:** `x = (i − 0,5) / N`, `y = 1 − (p − lo) / (hi − lo)` → auflösungsunabhängig, auch in SurfaceGuis.
3. **Nur bei Änderung schreiben** (Werte cachen, vergleichen).
4. **Pro Frame bewegt sich nur die Live-Kerze** (`alpha = 1 − e^(−12·dt)`), y-Bereich gleitet mit `1 − e^(−6·dt)` (keine Achsensprünge).
5. **Neue Kerze = O(1):** ältesten Slot recyceln, Streifen-Container per Tween 0,25 s Quint Out um eine Slot-Breite schieben.
6. **Linien** per `Path2D` (in Studio verifizieren), sonst gedrehte Segment-Frames in Pixeln (geteilt durch die akkumulierte UIScale),
   im Code auf das Plot-Rechteck geklemmt (gedrehte Frames ignorieren `ClipsDescendants`).
7. **Kein CanvasGroup**, kein `TextScaled` auf Achsen.
8. Budget: < 0,3 ms je Frame am Handy; Indikator-Linien höchstens 3 am Handy, 6 am PC.

### 3.4 Welt-Monitore und Ticker-Wände
- Client-SurfaceGuis mit `Adornee` = Server-Part; die nächsten K live (K = 2/4/8/12 je Grafikstufe), Rest eingefrorene Schnappschüsse;
  ≤ 2 Hz, 30–60 Kerzen ohne Beschriftung; `LightInfluence = 0`, `Brightness = 2`, `MaxDistance = 300`, `PixelsPerStud = 40`.
- Ticker-Wände/Laufband: gepoolte TextLabels, Position je Frame verschoben (120-s-Schleife wie die Website), gespeist aus dem
  Markt-Frame (kein Extra-Netzverkehr).
- Fassaden-LED eines Towers zeigt die **AKX36-Farbe des Tages**, **nie** das eigene G/V.

### 3.5 Ruhiges Feedback (kein Glücksspiel-Look, DESIGN.md §0.3)
- Gewinn-Verkauf: grüner G/V-Tick + sanftes Arpeggio. Verlust: neutraler grauer Tick + ein Lerntipp.
- Konfetti/Geldregen nur für Meilensteine (Stufe, Lizenz, Titel, Börsengang, Liga-Stufe) – nie für einzelne Trades.
- Keine Fast-gewonnen-Effekte, keine Serien-Flammen, keine Münz-Explosionen, keine Spielautomaten-Optik.
- Betrags-Chips **„10 % · 25 % · Max“** – nie „100 %“ oder „All-in“.

---

## Teil 4 – AKYTEX-Marken-Blatt (REUSE.md §8, DESIGN.md §0.5)

### 4.1 Namen
- Spiel: **AKYTEX TYCOON**. Wortmarke **ΛKYTEX** (griechisches großes Lambda U+039B als „A“, ohne Querstrich).
- Im Spiel erlaubt: die fiktive Börse **„AKYTEX Exchange“**, Index **AKX36**, **ΛKYTEX Terminal**, Sektor-ETFs „AKYTEX Tech“ usw.
- Spielhelfer: **Tiko** (geskripteter Ticker-Roboter, keine KI, kein Chat, keine Anlageberatung) – **nie „Aky“** (so heißt der echte
  KI-Assistent der Website).
- **Verboten im Spiel und auf der Spielseite:** URL, QR-Code, „App“, „Website“, „Demo-Depot“, Tarifnamen (Free/Plus/Pro/Elite/Ultra),
  „AKYTEX AI“, „Aky“, „NOVA“, „echtes Trading“, Broker/KYC, Euro-Preise, Gründernamen/Adressen,
  „3 Minuten am Tag. Ein Leben lang reicher“. **Keine handelbare AKYTEX-Aktie**, kein NOVA, kein „PRO“-Abo (das Abo heißt
  „Vorstands-Club“).

### 4.2 Taglines und Tonfall
- Marke: **„Markets move. Ideas stay.“** · An der Börsenglocke graviert: **„CAPITAL BUILDS TOMORROW“**.
- Spiel: DE „Lies die Eilmeldung. Bau die Skyline.“ · EN „Read the news. Build the skyline.“
- Stil: zweiteilige Überschriften mit Punkt, Zahlen als Beweis („36 Firmen“, „50 Etagen“), Emoji nur als kleines Symbol
  (📈 🏙️ 🔔 ⚡), „du“-Ansprache, Sätze ≤ 12 Wörter bei Tiko.
- Disclaimer-Stimme: „Spielgeld · erfundene Firmen · kein echtes Geld“ (lang: `core.disclaimer`).

### 4.3 Farben (Website → Spiel)

| Satz | Werte |
|---|---|
| Klassisch dunkel (= `UI.Theme`, für die Oberfläche) | bg #0b0f17 · bg-2 #0f141d · panel #121824 · panel-2 #1a2130 · hover #1f2838 · border #1f2937 · text #e6ecf5 · text-2 #aab4c3 · muted #7d889a · accent #4f8cff · up #22c55e · down #ef4444 · warn #eab308 |
| Space-Design (Nachthimmel, Hero-Momente, Penthouse) | bg #03040a · accent #7c9cff · kosmischer Verlauf #3b5bdb → #7c5cff → #b36bff · Text-Verlauf #9db4ff → #c8a8ff → #ffcf6e |
| Logo | Hintergrund radial #0d2345 → #081630 → #040a16 · Ring #6ea2f2 (Glow) · Buchstaben #eaf1ff · Kerzen #3f74c4 (10–43 %) · MA-Linie #4f86dc |
| Nicht fürs Spiel | helles Theme (accent #2962ff, up #089981, down #f23645) · NOVA-Farben (eigene Marke) |

### 4.4 Schriften
Website: Manrope (Text) und Unbounded (Display). Roblox hat beide nicht → `BuilderExtended` (Display), `BuilderSans`/`Montserrat`
(Text), `BuilderMono` (Zahlen), Michroma als Rückfall.

### 4.5 Logo ohne Upload (Striche aus `icons/logo.svg`, 512 × 512)
```
Λ  M60 285 L81 227 L102 285
K  M132 227 V285   M170 227 L134 258   M144 250 L172 285
Y  M200 227 L221 256 L242 227   M221 256 V285
T  M270 230 H312   M291 230 V285
E  M377 230 H340 V282 H377   M340 256 H372
X  M410 227 L452 285   M452 227 L410 285
Ring: Kreis cx 256 cy 256 r 228, Strich #6ea2f2 2,6 px; Ring-Texte „MARKETS / MOVE / IDEAS / STAY“ und
„CAPITAL / BUILDS / TOMORROW“ in #5c7fb8 (70 %); Hintergrund: 46 steigende Kerzen + MA-Linie, Deckkraft 0,10 → 0,43.
```
UI: gedrehte Frames. Welt: dünne Neon-/Glas-Parts (Plaza-Boden ≈ 40 Parts, R 46; 12-m-Neonbuchstaben; Luftschiff).

### 4.6 Bewegung & Haptik der Website
`--ease-ios` (Quint Out), `--spring` (Overshoot ≈ 10,8 %), Druck-Feedback auf jedem Knopf, Modal rein = 18 px nach oben +
Scale 0,94 → Feder, Rollziffern bei Preisen, „Dynamic-Island“-Meldungen, Laufband 120 s, `prefers-reduced-motion` = `ReducedFx`.

### 4.7 Was nie von der Website übernommen wird
Echte Firmennamen/Kürzel (Apple, NVIDIA, SAP …), Euro-Preise, Abos, Bezahl-Seiten, „14 Tage kostenlos“, URLs, „App installieren“,
jede Aufforderung, Roblox zu verlassen, Geld-/Anlage-Versprechen, Gründernamen/Adresse/E-Mail.

### 4.8 Kanäle trennen
Eigene Social Links **„AKYTEX Games“** (Discord/YouTube) nur für die Roblox-Spiele; die AKYTEX-Finanzkanäle bleiben erwachsenen-
orientiert. Im Spiel nur der Satz „Unsere Social-Links findest du auf der Spielseite“ / „Check out our social media links on our
game's page“. Keine Datensammlung über Spieler.

---

## Teil 5 – Kurz-Prüfliste für jeden neuen Inhalt

| Frage | Muss |
|---|---|
| Farben nur aus `UI.Theme` / `Config.Colors`? | ja |
| AKY blau mit Λ, CR grün mit Sechskant, nie vertauscht? | ja |
| Preise/Zahlen in BuilderMono, keine zitternden Ziffern? | ja |
| Neon ≤ 8 % der Fläche, Gold nur Krone/Glocke/Hall of Fame? | ja |
| Wort aus der Wortliste (DESIGN.md §0.7) im Text? | **nein** |
| Casino-, Karten-, Würfel-, Glücksrad- oder Spielautomaten-Bild/Klang? | **nein** |
| Echte Firma, echtes Kürzel, URL, QR, „App“, „NOVA“, „Aky“, „PRO“? | **nein** |
| Robux-Knopf mit „Ansehen/Details/Preis anzeigen“ (nie Druck-Wörter)? | ja |
| Funktioniert ohne hochgeladenes Asset (Code-Rezept)? | ja |
| `ReducedFx` und Farbenblind-Modus beachtet? | ja |
| Handy: Knöpfe ≥ 44 px (Spiel-Knöpfe ≥ 64 px), 60/30 FPS-Budget eingehalten? | ja |
