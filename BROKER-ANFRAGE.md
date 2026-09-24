# Broker-Partner für echten Handel – Anfrage

Damit AKYTEX echten Aktienhandel anbieten darf, braucht ihr einen **lizenzierten Partner**, der Konten und Depots für eure Kunden führt, Orders ausführt und die Kunden identifiziert (KYC). Die App ist technisch vorbereitet: Sobald der Partner angebunden ist, trägt man seine Adressen in `js/config.js` ein (siehe `GO-LIVE.md`).

## Wen anfragen (Stand September 2026, bitte selbst prüfen)
| Anbieter | Was sie machen | Passt, weil |
| --- | --- | --- |
| **Upvest** (Berlin) | API-Plattform für Wertpapierhandel, genutzt u. a. von N26, Revolut, Vivid; laut Presse jetzt auch DKB | API-first, für Apps wie AKYTEX gebaut |
| **Baader Bank** (Unterschleißheim) | Wertpapierbank, Depot- und Abwicklungspartner u. a. für Trade Republic, Scalable Capital, justTRADE | etablierte Partnerbank für Neobroker |

Weitere Anbieter findet ihr unter dem Stichwort „Brokerage as a Service“ bzw. „Banking as a Service“. Rechnet mit Mindestvolumen, Einrichtungsgebühren und einer Prüfung eures Unternehmens (Rechtsform, Finanzierung, Compliance).

## Anfrage-E-Mail (zum Kopieren)

**Betreff:** Partnerschaftsanfrage – Trading-App AKYTEX (Brokerage as a Service)

> Sehr geehrte Damen und Herren,
>
> wir sind akytex united aus Hamburg und entwickeln **AKYTEX**, eine Trading-App mit Profi-Charts, KI-Analyse (AKYTEX AI), einer Community-Ideen-Börse und Clips. Die App läuft bereits als Web-App und PWA; der Handel erfolgt derzeit in einem virtuellen Depot, Abonnements rechnen wir über Stripe ab.
>
> Für den nächsten Schritt suchen wir einen lizenzierten Partner, der für unsere Kundinnen und Kunden
> - Konto- und Depoteröffnung inkl. Identifizierung (KYC/AML),
> - Orderausführung (Aktien und ETFs, Market/Limit/Stop),
> - Verwahrung sowie Ein- und Auszahlungen (SEPA, ggf. Karte/Wallets),
> - Kosten- und Steuerreporting
>
> über eine API bereitstellt. Unsere App ist technisch bereits dafür vorbereitet (Login, Konto-Abgleich, Orders, Stornos, Überweisungen, Echtzeitkurse per Stream).
>
> Wir würden gern verstehen:
> 1. welches Modell Sie anbieten (z. B. vertraglich gebundener Vermittler, Haftungsdach, White-Label),
> 2. welche Voraussetzungen wir erfüllen müssen (Rechtsform, Eigenkapital, Personal, Compliance),
> 3. welche Kosten anfallen (Einrichtung, laufend, pro Order/Konto) und
> 4. wie lange eine Anbindung typischerweise dauert.
>
> Über einen kurzen Termin in den nächsten Wochen würden wir uns freuen.
>
> Mit freundlichen Grüßen
> Leo Maser und Paul Jazra
> akytex united · Alter Wall 56 · 20457 Hamburg
> acytex@outlook.de · +49 151 10681903

## Was die Partner meist von euch sehen wollen
- eine Kapitalgesellschaft (GmbH/UG oder AG) statt einer GbR – siehe `AKTIE-FAHRPLAN.md`
- Businessplan mit Kundenzahlen und Finanzierung (Vorlage: `BUSINESS.md`)
- Verantwortliche Person für Compliance/Geldwäsche
- eine Demo der App (die öffentliche Seite reicht)

Quellen: [Baader Bank als Partnerbank](https://www.bankdaten.de/baader-bank.html), [DKB und Upvest](https://www.neuebanken.de/dkb-greift-neobroker-an/), [Baader-Partnernetzwerk](https://www.finanzwire.com/press-release/baader-wertpapierhandelsbank-ag-etr-bwb-baader-bank-and-robomarkets-announce-partnership-zobO1Z2C6rb)
