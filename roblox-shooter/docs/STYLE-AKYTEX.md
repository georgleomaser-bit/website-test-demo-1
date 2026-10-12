# CLUTCH CLASH – AKYTEX-Look (verbindlich, Besitzer-Entscheidung 12.10.2026)

Der Besitzer will die Oberfläche „wie AKYTEX“ (seine Trading-Plattform, Ordner `/home/user/website-test-demo-1`,
Farben in `css/app.css`): dunkel, edel, modern, klar – wie die UI von RIVALS. **Die Arenen/Welt bleiben bunt**
(Spielzeug-Blaster, farbige Maps); nur Menüs, HUD, Schilder/Billboards und Effekte-Texte wechseln den Stil.
Ersetzt den bisherigen „knallig/cartoonig, FredokaOne, dicke schwarze Kontur“-Stil.

## Farben (Tokens stehen in `src/client/Modules/UI.luau` → `UI.Theme`, nie hart kodieren)
| Token | Hex | Verwendung |
|---|---|---|
| `Bg` / `Bg2` | #0b0f17 / #0f141d | Vollflächen, Fenster-Hintergrund |
| `Surface` (= Panel) | #121824 | Fenster, Panels (Glas: BackgroundTransparency 0.06–0.15) |
| `Surface2` (= PanelLight) | #1a2130 | Karten, Zeilen, Eingabefelder |
| `Hover` | #1f2838 | Hover-Zustand von Karten/Zeilen/Knöpfen |
| `Border` | #1f2937 | 1-px-Rahmen (UIStroke Thickness 1, ApplyStrokeMode Border) |
| `Text` / `Text2` / `Muted` | #e6ecf5 / #aab4c3 / #7d889a | Haupttext / Nebentext / sehr leise |
| `Accent` / `AccentDeep` | #4f8cff / #2962ff | Primär-Knöpfe, aktive Tabs, Fokus, Fortschritt, PLAY |
| `Up` | #22c55e | Sieg, Gewinn, Kauf-Erfolg, Heilung, + Werte |
| `Down` | #ef4444 | Niederlage, Schaden, Fehler, − Werte, Gegner-Markierung |
| `Warn` | #eab308 | Warnungen, Gold/Premium-Akzente |
Seltenheiten/Kosmetik-Farben dürfen kräftig bleiben (Purple/Pink/Gold/Cyan …), aber nur als Akzent (Rahmen,
Streifen, kleiner Glow), nie als Vollfläche großer Fenster.

## Schrift (`UI.Fonts`)
- `Main` BuilderSansBold (Knöpfe, Labels) · `Body` BuilderSans (Fließtext) · `Strong` BuilderSansExtraBold (große Zahlen in Karten)
- `Heading`/`Banner` Michroma (Fenstertitel, Logo „CLUTCH CLASH“, MATCH POINT, CLUTCH!, ACE) – sparsam, kurz, GROSS
- `Number` TitilliumWeb (HUD: Munition, HP, Timer, Score)
- KEINE FredokaOne/LuckiestGuy/Bangers/Gotham mehr.
- Text ohne dicke schwarze Kontur. Über der 3D-Welt (HUD, Billboards, Killfeed, Schadenszahlen) eine **feine**
  Kontur für Lesbarkeit: UIStroke Thickness 1–1.5, Farbe #000000, Transparency 0.35–0.5 (oder TextStroke 0.6).

## Formen & Flächen
- Ecken: Fenster 14–16 px, Karten/Knöpfe 10–12 px, Chips/Pills voll rund.
- Fenster = Glas: `Surface` mit Transparency ~0.08, 1-px `Border`-Rahmen, leichter Blur (BlurEffect 8–10) hinter
  offenen Fenstern, dezenter Schatten (ein unscharfes dunkles Frame dahinter, Transparency ~0.6) statt dicker Kontur.
- Fenster-Kopf: Titel links in `Heading` (GROSS, 18–22 px), rechts ein schlichtes ✕ (Ghost-Knopf, Hover = `Hover`).
- Trennlinien 1 px `Border`.

## Knöpfe
- **Primär**: Fläche `Accent`, Text weiß BuilderSansBold, Ecke 10–12, KEINE 3D-Lippe, KEINE dicke Kontur, kein Comic-Glanz.
  Hover: etwas heller (+8 %), Druck: Scale 0.97 (Feder, iOS-artig), kurzer Farb-Flash.
- **Sekundär**: Fläche `Surface2`, 1-px `Border`, Text `Text`; Hover `Hover`.
- **Gefahr**: `Down`; **Erfolg/Kaufen**: `Up`; **Premium**: Verlauf `Warn`→Orange nur dezent.
- **Ghost**: transparent, Text `Text2`, Hover-Fläche `Hover`.
- Mindestgröße am Handy 44 px (Touch-Knöpfe im Kampf ≥ 64 px wie bisher).

## Bewegung (iOS-artig, wie AKYTEX `--ease-ios`)
- Öffnen: Fade 0.18 s + Scale 0.96→1 mit Quint/Quart Out (kein starkes Überschwingen, kein Elastic).
- Schließen: 0.14 s Quad In. Hover 0.12 s. Zahlen zählen weich hoch (bestehende Counter).
- Toasts/Meldungen: schlanke Pill oben Mitte (Surface + Border, Icon-Punkt in Up/Down/Accent/Warn), gleitet
  8 px herein und blendet aus. Große Kampf-Ansagen (CLUTCH!, ACE, MATCH POINT) zentriert in Michroma mit
  Akzent-Unterstrich/Glow statt Comic-Kontur.

## HUD im Kampf
- Minimal und klar wie RIVALS: HP-Balken unten links (Up→Warn→Down je nach HP), Munition unten rechts groß in
  `Number`, Fadenkreuz weiß mit feiner dunkler Kontur, Treffer-Marker weiß / Kopfschuss `Warn` / Kill `Down`.
- Killfeed oben rechts: Glas-Pills, eigener Name `Accent`, Kopfschuss-Symbol.
- Score oben Mitte: zwei Team-Kästen (Team 1 `Accent`, Team 2 `Down`), Timer dazwischen in `Number`.

## Welt-Texte (Server-Billboards/SurfaceGuis: Pads, Bestenlisten, Namensschilder, Lobby-Schilder)
- Dunkle Glas-Tafeln (`Bg`/`Surface`, Transparency 0.1–0.2) mit 1-px Akzent-/Border-Rahmen, Text BuilderSansBold,
  Titel Michroma. Namensschilder: Name weiß, Level/Titel `Text2`, [BOT] `Muted`, Gegner-Team `Down`, eigenes Team `Accent`.
- Server-Code hat keinen Zugriff auf `UI.Theme`: dieselben Hex-Werte als lokale Konstanten verwenden (Kommentar „AKYTEX-Farbe“).
