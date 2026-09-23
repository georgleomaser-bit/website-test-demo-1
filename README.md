# aktex – Aktienhandel (Demo)

Demo-Website zum Handeln mit Aktien in Echtzeit.

## Funktionen
- **Live-Markt**: 22 Aktien (US & DAX u. a.), Kurse aktualisieren sich jede Sekunde
- **Suche** nach Symbol oder Firmenname
- **Live-Chart** mit Eröffnung, Tageshoch/-tief
- **Kaufen & Verkaufen** mit Mengenwahl (inkl. „Max“)
- **Depot** mit Durchschnittskurs und Gewinn/Verlust je Position
- **Transaktionsverlauf**
- Demo-Konto mit 10.000 € Startguthaben, im Browser gespeichert (zurücksetzbar)

> Hinweis: Die Kurse sind **simuliert** – keine echten Marktdaten, kein echtes Geld.

## Starten
Reine statische Seite ohne Abhängigkeiten – einfach `index.html` im Browser öffnen oder:

```bash
python3 -m http.server 8000
# dann http://localhost:8000 öffnen
```
