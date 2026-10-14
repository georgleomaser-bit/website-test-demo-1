# Bild-Generator für AKYTEX TYCOON

`generate.js` zeichnet die Upload-Bilder für Roblox nach `vorbereitet/bilder/`:

| Bild | Größe | Motiv |
|---|---|---|
| `thumbnail-1-de.png` | 1920 × 1080 | Nacht-Skyline, eigener Tower mit Kran setzt „+1 ETAGE“, Wahrzeichen Orbit Spire mit Neon-Ring, steigender Kerzen-Chart, Lichtspuren, Spiegelung im Wasser. Text: „ΛKYTEX TYCOON – LIES DIE NEWS. BAU DIE SKYLINE.“ + News-Karte „EILMELDUNG“ |
| `thumbnail-1-en.png` | 1920 × 1080 | dasselbe auf Englisch („READ THE NEWS. BUILD THE SKYLINE.“, „BREAKING“) |
| `spiel-icon.png` | 512 × 512 | Glas-Tower mit Λ-Krone und Neon-Ring, grüner Kerzen-Chart, Schriftzug ΛKYTEX |

Alles ist mit HTML/SVG/CSS gezeichnet (keine KI-Bilder, keine fremden Fotos) und wird mit Playwright (Chromium) fotografiert.
Die Firmen im Bild (Kernwerk Systems, Tiko, Cognivo) sind die fiktiven Firmen aus dem Spiel.

## Starten

```bash
cd roblox-akytex-tycoon/vorbereitet/bilder/_generator
node generate.js                 # alle Bilder
node generate.js thumbnail       # nur Bilder, deren Name "thumbnail" enthält
node generate.js --out /tmp/test # woanders hinschreiben (Original bleibt unberührt)
node generate.js --html          # zusätzlich die HTML-Seiten speichern
```

Voraussetzung: Node.js und Playwright mit Chromium (wird automatisch über `npm root -g` gefunden).

## Automatische Prüfungen

- Kein Text ragt über den Bildrand (`textOutOfBounds` muss leer sein); zu lange Texte werden automatisch verkleinert.
- Alle Schriften sind geladen (`fehlendeSchriften` muss leer sein).
- Bei Problemen meldet das Skript `WARNUNG` und endet mit Exit-Code 1.

## Schriften (`fonts/`, alle SIL Open Font License 1.1)

Michroma (wie die Überschriften im Spiel), Titillium Web (Zahlen), Unbounded und Manrope (wie die AKYTEX-Website).
Lizenztexte liegen daneben (`OFL-*.txt`).

## Regeln (docs/KOPIERVORLAGEN.md §4)

Keine echten Marken, kein Robux-Symbol, keine Währungszeichen, kein Geld-Versprechen, nichts mit Casino/Würfeln/Karten/Glücksrad,
kein „Raytracing“.
