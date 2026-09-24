# Fahrplan: Firma, Notar und eine echte AKYTEX-Beteiligung

Kurz: Eine „AKYTEX-Aktie“, in die fremde Leute Geld stecken, gibt es nur mit der richtigen **Firma** und einem **erlaubten Angebot**. Einen Kaufen-Knopf in der App ohne diese Schritte darf es nicht geben – das wäre ein unerlaubtes öffentliches Angebot von Wertpapieren. Hier ist der Weg, Schritt für Schritt. Das ist keine Rechtsberatung; lasst die Schritte 2–5 von Notar, Steuerberater und einem Anwalt für Kapitalmarktrecht begleiten.

## 1. Heute: GbR
Ihr beide (Leo Maser, Paul Jazra) betreibt akytex united gemeinsam, ohne eingetragene Firma. Rechtlich ist das eine **GbR**: Ihr haftet persönlich mit eurem Privatvermögen, und eine GbR kann keine Aktien ausgeben.
- Tipp für jetzt: Namen im Impressum auf „akytex united GbR“ ändern, einen einfachen GbR-Vertrag schriftlich festhalten (Anteile, Aufgaben, Entscheidungen, was bei Streit oder Ausstieg passiert).

## 2. Firma gründen: UG oder GmbH (beim Notar)
Für Stripe-Umsätze, Broker-Partner und Investoren braucht ihr eine Kapitalgesellschaft.

| | UG (haftungsbeschränkt) | GmbH |
| --- | --- | --- |
| Stammkapital | ab 1 € (ein Viertel des Gewinns muss angespart werden, bis 25.000 € erreicht sind) | 25.000 € (mindestens 12.500 € bei Gründung einzahlen) |
| Haftung | nur Firmenvermögen | nur Firmenvermögen |
| Gründung | Notar, Musterprotokoll möglich | Notar |

**So läuft der Notartermin:**
1. Notar in Hamburg anfragen (Suche: Bundesnotarkammer „Notarauskunft“). Viele Notare gründen UG/GmbH auch **online per Video** über die Plattform der Bundesnotarkammer – ihr braucht dafür einen Personalausweis mit Online-Funktion und ein Smartphone.
2. Der Notar braucht vorab: Firmenname (z. B. „AKYTEX UG (haftungsbeschränkt)“), Sitz (Hamburg, Alter Wall 56), Gegenstand des Unternehmens (z. B. „Entwicklung und Betrieb von Software und digitalen Informationsdiensten rund um Finanzmärkte; keine erlaubnispflichtigen Bank- oder Finanzdienstleistungen“), Stammkapital und Verteilung der Anteile (z. B. 50/50), Geschäftsführer (einer oder beide), eure Ausweise und Adressen.
3. Termin: Der Notar liest den Gesellschaftsvertrag vor, ihr unterschreibt. Danach Geschäftskonto eröffnen, Stammkapital einzahlen, Nachweis an den Notar – er meldet die Firma beim Handelsregister an.
4. Nach der Eintragung: Gewerbe anmelden, Finanzamt-Fragebogen (steuerliche Erfassung), Transparenzregister, IHK. Dann Impressum, Stripe-Konto und AGB auf die neue Firma umstellen – ich passe die App dafür in `js/config.js` an.

**Kosten (grobe Richtwerte):** UG mit Musterprotokoll einige hundert Euro für Notar und Handelsregister; GmbH mit eigenem Vertrag eher 800–1.500 € plus Stammkapital.

## 3. Investoren aufnehmen – drei Wege
1. **Business Angels / Freunde & Familie (nicht öffentlich):** Anteile der UG/GmbH werden per Notarvertrag an einzelne Investoren abgegeben. Kein Prospekt nötig, aber jede Übertragung beim Notar.
2. **Crowdinvesting über eine lizenzierte Plattform (öffentlich, am realistischsten):** Plattformen wie Companisto oder Seedmatch organisieren Angebot, Verträge, Zahlungen und Anlegerschutz. Meist als Nachrangdarlehen oder Genussrechte, nicht als Aktie. Die Plattform prüft euch vorher. In der App können wir die Kampagne dann verlinken und den Stand anzeigen.
3. **Echte Aktien:** Dafür müsst ihr eine **AG** werden (Grundkapital mindestens 50.000 €, Vorstand und Aufsichtsrat, Gründungsprüfung, Notar). Ein öffentliches Angebot braucht bis 8 Mio. € ein von der BaFin gestattetes **Wertpapier-Informationsblatt**, darüber einen **Wertpapierprospekt**. Das ist der teuerste und langsamste Weg – sinnvoll erst mit Umsatz und Investorennachfrage.

## 4. Was ich dafür vorbereiten kann
- Unterlagen: Businessplan und Pitch-Texte (Grundlage: `BUSINESS.md`), Kennzahlen aus der App, Entwürfe für Gesellschafts- und Beteiligungsverträge **zur Vorlage beim Notar/Anwalt**.
- Technik: Investoren-Seite in der App (Vision, Team, Kennzahlen, Link zur Crowdinvesting-Kampagne), sobald es eine erlaubte Kampagne gibt.
- Umstellung: Impressum, AGB, Stripe-Hinweise und Rechnungsangaben auf die neue Firma, sobald sie eingetragen ist.

## 5. Was nur ihr selbst tun könnt
- Notartermin wahrnehmen und unterschreiben (Identitätsprüfung persönlich oder per Video)
- Geschäftskonto eröffnen, Stammkapital einzahlen
- Verträge mit Plattform, Broker-Partner oder Investoren unterschreiben
- Steuerberater beauftragen (Umsatzsteuer, Kleinunternehmerregelung ja/nein, Buchhaltung für Stripe-Einnahmen)

Quellen: [BaFin zu Crowdfunding](https://www.bafin.de/DE/verbraucherinnen-verbraucher/themen-finanzprodukte/geldanlage/crowdfunding/crowdfunding_node.html), [Crowdfunding-Plattformen im Vergleich 2026](https://www.starting-up.de/geld/crowdfunding/crowdfunding-plattformen-im-vergleich-2026.html), [Crowdinvesting rechtlich](https://www.mtrlegal.com/wiki/crowdinvesting/)
