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
6. `mode: "live"` setzen. Die Buttons „… gratis testen“ leiten dann auf die sichere Stripe-Bezahlseite weiter.

## Wichtig vor dem Livegang

- **Freischaltung serverseitig prüfen:** Ohne Server speichert AKYTEX den Tarif im Browser. Für echte Kunden braucht es Benutzerkonten mit Login (z. B. Supabase, Firebase oder ein eigener Server) und einen **Stripe-Webhook** (`checkout.session.completed`, `customer.subscription.updated/deleted`), der den Tarif im Konto setzt. Sonst könnte jemand Funktionen ohne Zahlung freischalten.
- **Rechtstexte:** Impressum, Datenschutz, AGB, Widerrufsbelehrung und Risikohinweise unter *Rechtliches* sind Vorlagen mit markierten Platzhaltern. Vor dem Livegang ausfüllen und anwaltlich prüfen lassen.
- **Finanzaufsicht:** Echter Wertpapierhandel, Anlageberatung (AKYTEX AI) und Vermögensverwaltung (Autopilot) brauchen eine BaFin-Erlaubnis oder einen lizenzierten Partner (siehe `BUSINESS.md`).
- **Preise transparent halten:** Alle Kosten stehen im Preisverzeichnis und vor jeder Order im Ticket. Das ist gesetzlich Pflicht (MiFID II, PAngV) und schafft Vertrauen.
