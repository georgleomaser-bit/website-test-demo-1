# ΛKTEX – Geschäftsmodell & Weg zum echten Produkt

*Markets move. Ideas stay.*

Dieses Dokument beschreibt, wie aus der Demo ein echtes Unternehmen werden kann: womit AKTEX Geld verdient, welche Größenordnungen realistisch sind und was rechtlich und technisch nötig ist, bevor echtes Geld fließt.

> Alle Zahlen sind **Beispielrechnungen mit Annahmen**, keine Prognosen. Ob AKTEX Milliarden umsetzt, hängt von Nutzerwachstum, Kapital, Team, Lizenzen und Marketing ab. Die Rechnung zeigt nur, *wie* Plattformen dieser Art skalieren.

---

## 1. Positionierung

AKTEX verbindet drei Produkte, die heute meist getrennt sind:

| Baustein | Vorbild | AKTEX-Vorteil |
| --- | --- | --- |
| Profi-Charts & Analyse | TradingView | im Broker integriert, kein Wechsel zwischen Apps |
| Günstiger Handel | Neobroker (1 €/Trade) | 0 € im Abo, Trade direkt aus dem Chart |
| Community & Copy-Trading | Social-Trading-Plattformen | „Ideas stay“: Ideen mit Chart, Rangliste, 1-Klick-Kopieren |
| KI-Analyse | Research-Tools | AKTEX AI bewertet jede Aktie in Echtzeit, mit Trade-Setup |

**Zielgruppe:** 18–45-jährige Selbstentscheider in DACH, dann EU. Einstieg über das kostenlose Demo-Depot, das es bereits gibt.

## 2. Einnahmequellen (schon in der App abgebildet)

| Quelle | Umsetzung in der Demo | Hebel |
| --- | --- | --- |
| **Abos** | Free / Pro 9,99 € / Elite 24,99 € pro Monat | wiederkehrender, planbarer Umsatz |
| **Ordergebühren** | 1 € pro Order im Free-Tarif | skaliert mit Aktivität |
| **Copy-Trading** | Elite-Funktion | Umsatzbeteiligung für Top-Trader, Plattformanteil |
| **Zinsmarge auf Guthaben** | (noch nicht in der Demo) | Kundengeld verzinst anlegen, Teil weitergeben |
| **Premium-Daten** | Level-2-Orderbuch im Elite-Tarif | Datenpakete, Realtime-Börsenlizenzen |
| **B2B / Partner** | – | Widgets und Charts für Banken und Medien lizenzieren |

⚠️ *Payment for Order Flow* (Rückvergütungen von Handelsplätzen) wird in der EU verboten und sollte nicht Teil des Modells sein.

## 3. Beispielrechnung

Annahmen: 8 % der Nutzer zahlen ein Abo (Ø 14 €/Monat), 20 % handeln im Free-Tarif 4× pro Monat, Ø 2.000 € Guthaben pro Nutzer, 1 % Zinsmarge.

| Nutzer | Abos / Jahr | Ordergebühren / Jahr | Zinsmarge / Jahr | **Umsatz / Jahr** |
| ---: | ---: | ---: | ---: | ---: |
| 100.000 | 1,3 Mio. € | 1,0 Mio. € | 2 Mio. € | **≈ 4,3 Mio. €** |
| 1 Mio. | 13,4 Mio. € | 9,6 Mio. € | 20 Mio. € | **≈ 43 Mio. €** |
| 10 Mio. | 134 Mio. € | 96 Mio. € | 200 Mio. € | **≈ 430 Mio. €** |

Fintechs dieser Art werden oft mit einem Vielfachen des Jahresumsatzes bewertet. Plattformen wie TradingView, Trade Republic oder Robinhood haben Bewertungen im Milliardenbereich erreicht, allerdings mit vielen Millionen Nutzern, großen Teams und hohen Finanzierungsrunden.

**Wachstumsmotoren, die in AKTEX schon angelegt sind:**
- **Teilen-Links** für Aktien und Charts, jeder geteilte Chart wirbt neue Nutzer
- **Community-Ideen und Rangliste**, Nutzer kommen täglich wieder
- **Kostenloses Demo-Depot** ohne Anmeldung, Einstieg ohne Hürde; Umstieg auf ein echtes Depot als nächster Schritt
- **Installierbare App** ohne App-Store-Hürde (PWA), später zusätzlich native Apps

## 4. Weg zum echten Handel (Pflicht vor echtem Geld)

1. **Regulierung:** Wertpapierhandel für Kunden braucht eine Erlaubnis der BaFin (Wertpapierinstitut nach WpIG), oder schneller eine Kooperation mit einem lizenzierten Partner (Broker-/Bank-API, „Broker-as-a-Service“). Dabei gelten MiFID-II-Pflichten (Angemessenheitsprüfung, Kosteninformationen, Best Execution).
2. **KYC & Geldwäsche:** Video-/eID-Identifizierung, GwG-Prozesse, Steuer-ID, Abgeltungsteuer-Abführung (über den Partner).
3. **Marktdaten:** Echtzeitkurse sind lizenzpflichtig (Börsen- bzw. Datenanbieter-Verträge). Für den Start eignen sich Datenanbieter mit API und Weiterverbreitungsrecht.
4. **Backend:** Benutzerkonten, sichere Anmeldung (2FA/Passkeys), Server für Orders, Datenbank, WebSocket-Kursstrom statt Simulation, Audit-Logs, Penetrationstests.
5. **Recht & Vertrauen:** Impressum, AGB, Datenschutzerklärung (DSGVO), Risikohinweise, Einlagensicherung über die Partnerbank.
6. **Team & Kapital:** Gründerteam (Tech, Compliance, Growth), Pre-Seed/Seed-Finanzierung für Lizenz- bzw. Partnerkosten, Marketing und Entwicklung.

## 5. Roadmap

| Phase | Ziel |
| --- | --- |
| **Jetzt (Demo)** | Produkt zeigen, Feedback sammeln, Warteliste aufbauen |
| **Phase 1** | Echte Kursdaten (verzögert/Realtime), Benutzerkonten, Cloud-Sync, Warteliste → Beta |
| **Phase 2** | Partner-Broker anbinden, KYC, echtes Depot, Abos über Zahlungsanbieter |
| **Phase 3** | Copy-Trading mit Umsatzbeteiligung, Sparpläne, ETFs, native Apps |
| **Phase 4** | EU-Expansion, B2B-Lizenzen der Chart-/AI-Technologie |
