# Bild-Generator für Meteor Heist

`generate.js` erzeugt alle Upload-Bilder für Roblox nach `vorbereitet/bilder/`:

| Bild | Größe | Woher |
|---|---|---|
| `spiel-icon.png` | 512 × 512 | Screenshot (falls vorhanden), sonst gezeichnet |
| `thumbnail-1.png` … `thumbnail-3.png` | 1920 × 1080 | Screenshot (falls vorhanden), sonst gezeichnet |
| `thumbnail-4.png`, `thumbnail-5.png` | 1920 × 1080 | **nur** mit Screenshot (sonst übersprungen) |
| 14 × `pass-*.png` / `produkt-*.png` | 512 × 512 | immer gezeichnet |

## Starten

```bash
cd roblox-meteor-heist/vorbereitet/bilder/_generator
node generate.js
```

Voraussetzung: Node.js und Playwright mit Chromium (wird automatisch über `npm root -g` gefunden).

## Mit echten In-Game-Screenshots

1. Screenshots in den Ordner **`vorbereitet/screenshots/`** legen.
2. Die Dateien genau so benennen (Endung `.png`, `.jpg` oder `.jpeg`, Groß/Klein egal):

   | Datei | Motiv | wird zu |
   |---|---|---|
   | `tragen` | Du mit einem Meteor über dem Kopf | `thumbnail-1.png` „KLAU DIE METEORE!“ |
   | `secret` | Ein Secret-Meteor ganz nah | `thumbnail-2.png` „SECRET METEOR GEFUNDEN!“ und `spiel-icon.png` |
   | `krater` | Der Krater beim Meteoritenschauer | `thumbnail-3.png` „METEORITENSCHAUER!“ (mit „3X GLÜCK“ / „KEINE LOCKS!“) |
   | `base` | Deine Base voller Meteore | `thumbnail-4.png` „WERDE REICH!“ |
   | `showcase` | Die Showcase-Reihe mit allen Seltenheiten | `thumbnail-5.png` „27 METEORE ZUM SAMMELN!“ |

3. `node generate.js` starten.

Fehlt ein Screenshot, springt ein Ersatz ein:

- `thumbnail-2.png`: `secret`, sonst `showcase`, sonst gezeichnet
- `spiel-icon.png`: `secret`, sonst `showcase`, sonst `base`, sonst gezeichnet
- `thumbnail-1.png` / `thumbnail-3.png`: sonst gezeichnet
- `thumbnail-4.png` / `thumbnail-5.png`: werden ohne ihren Screenshot übersprungen (eine alte Datei bleibt dann liegen)

Am Ende steht für jedes Bild, ob ein **Screenshot** oder die **Zeichnung** verwendet wurde.

### Was mit dem Screenshot passiert

- Er wird auf das Zielformat **zugeschnitten, nicht verzerrt**: Er wird gleichmäßig skaliert, bis er das Bild ganz füllt, und was übersteht, wird abgeschnitten. Jede Größe und jedes Seitenverhältnis geht (auch hochkant).
- **Fensterrahmen, Titelleisten und schwarze Balken** am Rand werden automatisch erkannt und entfernt (in der Ausgabe als `randEntfernt`).
- Etwas mehr Farbe und Kontrast, eine leichte Vignette und ein dunkler Verlauf hinter der Überschrift, damit der Text gut lesbar ist.
- Überschriften, Bänder und Pillen haben denselben Stil wie die gezeichneten Thumbnails. Zu lange Texte werden automatisch verkleinert.
- Spiel-Icon: ein enger Ausschnitt um die Bildmitte, darunter der Schriftzug „METEOR HEIST“.

### Tipps für gute Screenshots

- Die **Bildmitte** zählt: Oben und unten kommt Text drüber, und das Icon ist ein Ausschnitt aus der Mitte. Das Motiv gehört deshalb in die Mitte.
- Mindestens **1920 × 1080**, am besten im Vollbild. Kleinere Bilder werden vergrößert und können unscharf wirken (die Ausgabe zeigt dann einen `hinweis`).
- Wenn möglich ohne Chat, Menüs und andere eingeblendete Bedienelemente.

## Optionen

```bash
node generate.js thumbnail                    # nur Bilder, deren Name "thumbnail" enthält
node generate.js --screens ~/Bilder/roblox    # Screenshots aus einem anderen Ordner
node generate.js --out /tmp/test-bilder       # Ergebnis woanders hinschreiben (Original bleibt unberührt)
node generate.js --no-screens                 # Screenshots ignorieren, alles zeichnen
node generate.js --html                       # zusätzlich die HTML-Seiten speichern (./html/ bzw. <out>/html/)
node generate.js --help
```

Zum Ausprobieren am besten mit `--out` in einen Test-Ordner schreiben und die Bilder erst danach in `vorbereitet/bilder/` übernehmen.

## Automatische Prüfungen

- Text ragt nicht über den Bildrand (`textOutOfBounds` muss leer sein).
- Bildgröße stimmt (`size`).
- Bei den runden Pass/Produkt-Icons liegt der Inhalt im inneren 80-%-Kreis.
- Bei Problemen meldet das Skript am Ende `WARNUNG` und endet mit Exit-Code 1. Das gilt auch für einen kaputten oder unvollständig kopierten Screenshot: Er wird übersprungen, und es springt der Ersatz bzw. die Zeichnung ein.

Ohne Screenshots erzeugt das Skript Byte für Byte dieselben Bilder wie bisher.
