# AKYTEX Go-Live – vom Demo zum Echtbetrieb

Alles, was für den Echtbetrieb eingetragen werden muss, steht in **einer Datei: `js/config.js`**. Jeder Teil schaltet sich einzeln frei, sobald seine Felder ausgefüllt sind:

| Teil | Felder in `js/config.js` | Was dann passiert |
| --- | --- | --- |
| Rechtstexte | `company` | Impressum, Datenschutz, AGB und Widerruf zeigen deine echten Firmendaten statt Platzhaltern |
| Abo-Zahlungen | `stripe.links` (+ `company`) | Die Tarif-Buttons führen auf die echte Stripe-Bezahlseite |
| Echte Kurse | `marketData.streamUrl`, `marketData.historyUrl` | Charts und Kurse kommen vom Datenanbieter, die Simulation stoppt |
| Echtes Depot | `trading.apiBase`, `trading.partnerName` | Login, Depot, Orders, Ein- und Auszahlungen laufen über den Broker-Partner |

Erst wenn **echte Kurse und echtes Depot** angeschlossen sind, zeigt die App „LIVE“ statt „DEMO“ und blendet das Zurücksetzen des Demo-Kontos aus. Der Autopilot macht mit echtem Geld nur Vorschläge und handelt nie selbstständig, denn das wäre erlaubnispflichtige Vermögensverwaltung.

## 1. Firma und Rechtstexte
- Firma gründen (für eine Handelsplattform z. B. eine GmbH), Geschäftskonto, Steuernummer bzw. USt-IdNr.
- Firmendaten in `company` eintragen
- AGB, Datenschutzerklärung, Widerrufsbelehrung und Risikohinweise anwaltlich prüfen lassen

## 2. Abo-Zahlungen mit Stripe
Das Stripe-Konto „akytex“ ist mit Claude verbunden, der Zugang darf aber bisher **nur lesen**. Damit Claude die Produkte und Zahlungslinks selbst anlegen kann:

1. In Stripe unter **Entwickler → API-Schlüssel** einen eingeschränkten Schlüssel mit Schreibrechten für **Products**, **Prices** und **Payment Links** anlegen, oder den Stripe-Connector in Claude mit Schreibrechten neu verbinden.
2. In Stripe unter **Einstellungen → Öffentliche Details** die Adresse deiner AGB eintragen und **Stripe Tax** bzw. die Steuereinstellungen für Deutschland (19 % MwSt., Preise inkl. Steuer) festlegen.
3. Claude legt dann an: 5 Produkte (Plus, Pro, Elite, AKYTEX AI, AI Premium), je ein Monats- und Jahrespreis, 10 Zahlungslinks mit 14 Tagen Testphase, Gutscheincodes und Rückleitung auf `?checkout=success&plan=…&billing=…`.

| Tarif | monatlich | jährlich |
| --- | --- | --- |
| Plus | 4,99 € | 47,88 € (3,99 €/Monat) |
| Pro | 12,99 € | 119,88 € (9,99 €/Monat) |
| Elite | 29,99 € | 299,88 € (24,99 €/Monat) |
| AKYTEX AI | 99,00 € | 948,00 € (79,00 €/Monat) |
| AI Premium | 249,00 € | 2.388,00 € (199,00 €/Monat) |

Später sinnvoll: ein kleiner Server mit Stripe-Webhook, der Abos serverseitig prüft (siehe `PAYMENTS.md`).

## 3. Echter Handel mit Echtgeld
Kundengeld annehmen, Depots führen und Orders ausführen ist in Deutschland erlaubnispflichtig (KWG/WpIG). Der übliche Weg für ein junges Unternehmen:

1. **Broker-Partner** mit BaFin-Erlaubnis, der Depots und Konten für deine Kunden führt und über eine Schnittstelle angebunden wird (Brokerage- bzw. Banking-as-a-Service; bitte aktuelle Anbieter und Konditionen selbst vergleichen).
2. **Rolle klären:** Ihr seid meist vertraglich gebundener Vermittler bzw. unter dem Haftungsdach des Partners. Das legt fest, was die App sagen und tun darf (Beratung, KI-Empfehlungen, Copy-Trading).
3. **Identifizierung (KYC)** und Geldwäscheprüfung macht in der Regel der Partner beim Depot-Eröffnen.
4. **Kursdaten:** Echtzeitkurse brauchen eine Lizenz des Datenanbieters bzw. der Börse. Verzögerte Kurse sind günstiger.
5. **Eigener Server (Backend):** Er spricht mit Partner und Datenanbieter, hält die Zugangsschlüssel geheim und stellt der App die Schnittstelle unten bereit. GitHub Pages kann nur die App ausliefern, der Server muss woanders laufen.

### Schnittstelle, die die App erwartet
Alle Pfade relativ zu `trading.apiBase`, JSON, Anmeldung per Sitzungs-Cookie (CORS mit `credentials`).

| Methode & Pfad | Zweck | Antwort |
| --- | --- | --- |
| `GET /auth/login?return=URL` | Login, KYC, Depoteröffnung beim Partner, danach zurück zur App | Weiterleitung, setzt Cookie |
| `GET /account` | Depotstand | `{ user, cash, positions: {SYM: {qty, avg, realized}}, orders, orderHistory, fills, realized, fees, netDeposits, transfers }`; `401` wenn nicht angemeldet |
| `POST /orders` | Order `{symbol, side, type, qty, limitPrice, stopPrice, sl, tp}` | `{ ok, order }` oder `{ ok: false, msg }` |
| `DELETE /orders/:id` | Order stornieren | `{ ok }` |
| `PATCH /orders/:id` | Limit/Stopp ändern `{price}` | `{ ok }` |
| `POST /transfers` | Ein-/Auszahlung `{type: "in"|"out", amount, method, iban}` | `{ ok, redirectUrl? }` – bei `redirectUrl` leitet die App zur Bezahlseite weiter |
| `GET marketData.historyUrl?symbol=SAP` | Kurshistorie | `{ m1: [{time, open, high, low, close, volume}], days: […] }` (Zeit in UTC-Sekunden, Tage auf 00:00 UTC) |
| `GET marketData.streamUrl` | Live-Kurse (Server-Sent Events) | je Nachricht `{s, p, v, t}` oder eine Liste davon |

### Ausprobieren ohne Partner
`server/mock-broker.mjs` bildet diese Schnittstelle nach, ohne echtes Geld:

```bash
node server/mock-broker.mjs      # läuft auf http://localhost:8787
python3 -m http.server 8000      # App lokal ausliefern
```
Dann in `js/config.js` `trading.apiBase = "http://localhost:8787"`, `marketData.streamUrl = "http://localhost:8787/stream"` und `marketData.historyUrl = "http://localhost:8787/history"` eintragen (nur lokal, nicht veröffentlichen). Die App zeigt „LIVE“, verlangt eine Anmeldung und handelt über den Test-Server.

## 4. Eine eigene AKYTEX-Aktie
Anteile an der eigenen Firma öffentlich zu verkaufen, ist ein Wertpapierangebot. Das geht nicht über einen Kaufen-Button in der App, sondern nur mit:
- einer passenden Rechtsform (Aktien setzen eine AG voraus, alternativ z. B. Genussrechte oder Nachrangdarlehen),
- einem von der BaFin gebilligten Prospekt oder, bei kleineren Summen, einem Wertpapier-Informationsblatt,
- in der Praxis meist über eine lizenzierte **Crowdinvesting-Plattform**, die Anlegerschutz, Zahlungen und Verträge abwickelt.

Wenn es so weit ist, kann die App die Kampagne der Plattform verlinken und den Stand anzeigen. Eine simulierte AKYTEX-Aktie in der App, die wie eine echte Beteiligung wirkt, wäre irreführend und ist deshalb nicht eingebaut.
