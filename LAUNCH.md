# Launch-Checkliste – AKYTEX öffentlich machen

Stand der Demo: Die Website ist technisch startklar (SEO, Vorschaubild, Sicherheits-Header, 404-Seite, PWA, Barrierefreiheits-Grundlagen). Für einen **öffentlichen Start mit echten Kunden** fehlen die Punkte unten, die nur du bzw. dein Unternehmen erledigen kann.

## 1. Technik (in diesem Repository vorbereitet)
- [x] Hosting-Konfiguration: `netlify.toml` und `vercel.json` mit Sicherheits-Headern (CSP, HSTS, X-Frame-Options, Permissions-Policy)
- [x] SEO: Titel, Beschreibung, Open-Graph/Twitter-Karten, `og-image.png` (1200×630), strukturierte Daten (JSON-LD), `robots.txt`, `sitemap.xml`
- [x] PWA: Manifest mit Icons, Screenshots und Shortcuts, Service Worker (offline), Installations-Button
- [x] `404.html`, Skip-Link, sichtbare Fokus-Rahmen, reduzierte Bewegung (`prefers-reduced-motion`)
- [ ] `DEINE-DOMAIN.de` in `robots.txt` und `sitemap.xml` ersetzen
- [ ] Deployment auf Netlify oder Vercel (siehe README), eigene Domain verbinden, HTTPS aktiv
- [ ] Monitoring & Fehler-Tracking (z. B. datenschutzfreundlich selbst gehostet) und Uptime-Überwachung

## 2. Backend (nötig für echte Kunden)
- [ ] Benutzerkonten mit Login (Passkeys/2FA) statt lokaler Browser-Speicherung
- [ ] Datenbank für Depots, Orders, Ideen, Clips, Kommentare
- [ ] Echte Kursdaten (lizenzierter Anbieter, WebSocket-Stream)
- [ ] Video-Speicher und -Transcoding für Clips (CDN)
- [ ] Stripe-Anbindung mit Webhooks (siehe `PAYMENTS.md`)

## 3. Recht & Regulierung
- [ ] **BaFin**: Wertpapierhandel, Anlageberatung (AKYTEX AI) und Vermögensverwaltung (Autopilot) nur mit Erlaubnis oder lizenziertem Partner/Haftungsdach
- [ ] Impressum, Datenschutzerklärung, AGB, Widerrufsbelehrung, Risikohinweise ausfüllen (Vorlagen unter *Rechtliches*) und anwaltlich prüfen
- [ ] **Clips & Ideen = nutzergenerierte Inhalte**: Melde-Funktion ist eingebaut; zusätzlich Moderationsprozess, Kontaktstelle und Transparenzangaben nach dem Digital Services Act (DSA), Jugendschutz prüfen
- [ ] Finfluencer-Regeln: Ideen und Clips mit Anlagebezug müssen als Meinung gekennzeichnet sein, Interessenkonflikte offenlegen (MAR)
- [ ] Shop: Versand, Widerruf für physische Waren, Preisangaben (PAngV), Verpackungsregister (LUCID) für Merch
- [ ] Cookie-/Tracking-Banner nur nötig, wenn Tracking eingebaut wird (aktuell keins)

## 4. Vertrauen & Start
- [ ] Demo-Hinweise („DEMO“, „simuliert“) erst entfernen, wenn echte Kurse und echtes Geld live sind
- [ ] Warteliste / Beta mit ausgewählten Nutzern
- [ ] Status-Seite und Support-Kontakt
- [ ] Sicherheits-Audit / Penetrationstest vor dem Start
