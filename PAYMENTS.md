# Bezahlsystem – vom Testmodus zu echten Zahlungen

AKYTEX läuft standardmäßig im **Testmodus** (`js/payments.js` → `PAYMENT_CONFIG.mode = "test"`):

- Kompletter Checkout: Tarif, Laufzeit, Add-ons, Gutscheine (`AKYTEX20`, `START`, `FOUNDER`), MwSt.-Ausweis, 14 Tage Testphase
- Zahlarten: Karte (mit 3-D Secure), PayPal, Apple Pay, Google Pay, SEPA-Lastschrift, Klarna – alle **simuliert**
- **Nur Testdaten** werden akzeptiert, damit niemand echte Zahlungsdaten eingibt:

| Testkarte | Ergebnis |
| --- | --- |
| 4242 4242 4242 4242 | erfolgreich |
| 4000 0025 0000 3155 | verlangt 3-D Secure |
| 4000 0000 0000 0002 | abgelehnt |
| 4000 0000 0000 9995 | nicht genügend Deckung |
| Test-IBAN DE89 3704 0044 0532 0130 00 | SEPA erfolgreich |

- Abo-Verwaltung unter **Konto → Abo & Zahlung**, Rechnungen, Zahlungsmethode ändern
- **„Verträge hier kündigen“** (Kündigungsbutton nach § 312k BGB) in der Fußzeile und im Konto
- Button-Beschriftung „Zahlungspflichtig abonnieren“ (Buttonlösung nach § 312j BGB)

## Echte Zahlungen mit Stripe (ohne eigenen Server)

1. Konto bei [Stripe](https://stripe.com) anlegen und verifizieren.
2. Für jeden Tarif ein Produkt mit **zwei Preisen** anlegen (monatlich und jährlich): Plus, Pro, Elite, AKYTEX AI, AI Premium.
3. Pro Preis einen **Payment Link** erstellen (Abo, 14 Tage Testphase, Gutscheincodes erlauben, Steuer aktivieren).
4. Die Links in `js/payments.js` unter `stripeLinks` eintragen, z. B. `"pro-monthly": "https://buy.stripe.com/…"`.
5. Das **Kundenportal** in Stripe aktivieren und den Link bei `stripePortal` eintragen (Zahlungsmethode ändern, kündigen, Rechnungen).
6. Bei jedem Payment Link unter *Nach der Zahlung* auf deine Seite weiterleiten, z. B. `https://DEINE-DOMAIN/?checkout=success&plan=pro&billing=monthly` (Plan und Laufzeit passend zum Link). Die App schaltet den Tarif dann frei und zeigt eine Bestätigung. `?checkout=cancel` meldet einen Abbruch.
7. `mode: "live"` setzen. Die Buttons „… gratis testen“ leiten dann auf die sichere Stripe-Bezahlseite weiter. E-Mail, Sprache (Deutsch) und eine Kunden-Referenz (`client_reference_id`) werden automatisch vorbelegt.

## Wichtig vor dem Livegang

- **Freischaltung serverseitig prüfen:** Ohne Server speichert AKYTEX den Tarif im Browser. Für echte Kunden braucht es Benutzerkonten mit Login (z. B. Supabase, Firebase oder ein eigener Server) und einen **Stripe-Webhook** (`checkout.session.completed`, `customer.subscription.updated/deleted`), der den Tarif im Konto setzt. Sonst könnte jemand Funktionen ohne Zahlung freischalten.
- **Rechtstexte:** Impressum, Datenschutz, AGB, Widerrufsbelehrung und Risikohinweise unter *Rechtliches* sind Vorlagen mit markierten Platzhaltern. Vor dem Livegang ausfüllen und anwaltlich prüfen lassen.
- **Finanzaufsicht:** Echter Wertpapierhandel, Anlageberatung (AKYTEX AI) und Vermögensverwaltung (Autopilot) brauchen eine BaFin-Erlaubnis oder einen lizenzierten Partner (siehe `BUSINESS.md`).
- **Preise transparent halten:** Alle Kosten stehen im Preisverzeichnis und vor jeder Order im Ticket. Das ist gesetzlich Pflicht (MiFID II, PAngV) und schafft Vertrauen.

## Ein- und Auszahlungen aufs Depot

Wie bei Neobrokern kann man Geld aufs Depot einzahlen und wieder auszahlen (Depot → **Einzahlen/Auszahlen**, in der Kontoleiste oder im Chat: „Zahle 500 € ein“):

- **Einzahlen:** Apple Pay, Google Pay, Debit-/Kreditkarte, Echtzeitüberweisung, PayPal und SEPA-Lastschrift (sofort handelbar, bis 5.000 € pro Tag) sowie Überweisung auf die Depot-IBAN (ohne Limit)
- **Auszahlen:** Echtzeit- oder Standard-Auszahlung auf ein Referenzkonto (IBAN mit Prüfsummen-Check)
- Ziffernblock, Schnellbeträge, „Zum Einzahlen halten“, Verlauf aller Ein- und Auszahlungen im Depot
- Ein- und Auszahlungen zählen **nicht** zur Rendite: Die Performance wird auf das eingesetzte Kapital gerechnet

Das ist **Demo-Geld**: Es werden nur Testkarten und die Test-IBAN angenommen, und die angezeigte Depot-IBAN ist absichtlich ungültig. Echte Kundengelder anzunehmen, ist ein erlaubnispflichtiges Geschäft. Dafür braucht es eine Partnerbank bzw. ein Wertpapierinstitut mit BaFin-Erlaubnis, das Konten und Depots führt (Banking-/Brokerage-as-a-Service). Die Oberfläche ist so gebaut, dass dessen Schnittstellen die simulierten Schritte ersetzen können.

## Stand Live-Betrieb (Stripe-Konto „akytex“)
- 5 Produkte, 10 Preise (inkl. MwSt.), 10 Payment Links mit 14 Tagen Testphase und Gutscheinfeld, Kundenportal – eingetragen in `js/config.js`
- Gutschein **AKYTEXLEO**: 50 % dauerhaft. In der App im Tarif-Fenster eingeben oder per Link `…/?code=AKYTEXLEO` teilen – der Code wird bei Stripe vorausgefüllt.
- **Wichtig:** Solange das Stripe-Konto nicht aktiviert ist (Dashboard → Konto aktivieren: Identität, Unternehmen, Bankkonto), meldet Stripe alle Zahlungsarten als nicht verfügbar – dann kann niemand bezahlen. Nach der Aktivierung unter Einstellungen → Zahlungsmethoden Karte, SEPA-Lastschrift, PayPal, Apple Pay, Google Pay und Klarna einschalten; danach kann die feste Beschränkung der Links auf Karte entfernt werden.
- Store-Käufe (Merch, Kurse, Reports, Geschenkkarten) sind im Live-Betrieb geschlossen, bis Versand, Verpackungsregister (LUCID) und Einlösung von Geschenkkarten geklärt sind.
- Einschränkung ohne eigenen Server: Die App schaltet den Tarif nach der Rückkehr von Stripe im Browser frei. Eine fälschungssichere Prüfung braucht einen kleinen Server mit Stripe-Webhook.
