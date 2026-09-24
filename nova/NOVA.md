# NOVA – das zweite Business von akytex united

NOVA ist ein **KI-Assistent zum Sprechen und Schreiben**, so wie Claude, aber als eigene App mit professionellem Design (hell und dunkel, passend zum Gerät). Er ist komplett getrennt von AKYTEX: eigener Ordner, eigene App, eigener Server und eigene Tarife.

**Vorschau (ohne Server):** https://georgleomaser-bit.github.io/website-test-demo-1/nova/
Dort laufen schon Wetter, Timer, Erinnerungen, Rechner, Sparziele, das Gedächtnis und die Sprache. Für alles andere braucht NOVA den Server mit Claude.

## Was NOVA kann
**Mit Server und Anthropic-Schlüssel („KI-Modus“)** antwortet Claude, das Sprachmodell von Anthropic:
- Schreiben, Erklären, Programmieren (Code-Blöcke mit Kopieren), Rechnen, Ideen entwickeln
- Websuche und Webseiten lesen, mit Quellen (Plus/Pro)
- Fotos und PDFs verstehen (Plus/Pro)
- Bei schweren Fragen denkt Claude länger nach
- Antworten erscheinen live Wort für Wort und lassen sich mit der Stopp-Taste abbrechen
- Chats mit Verlauf, Kopieren und Vorlesen

**Immer und ohne KI-Kosten:**
- Wetter über Open-Meteo, kostenlos und ohne Schlüssel
- Timer und Erinnerungen, mit Ton, Stimme und Mitteilung
- Sparziele, z. B. „Mach mir 10k“
- Rechner, Gedächtnis („Merk dir …“), Tagesbriefing („Guten Morgen“)

**Sprache:** Tippe aufs Mikro (oder drück die Leertaste) und sprich. Die Stimme wählst du wie bei Siri in den Einstellungen, dazu Tempo und Tonhöhe.

## Tarife
| Tarif | Preis | KI-Fragen/Tag | Modell | Extras |
|---|---|---|---|---|
| Free | 0 € | 5 | Claude Sonnet 5 | Wetter, Timer & Co. unbegrenzt |
| Plus | 4,99 €/Monat | 60 | Claude Sonnet 5 | Websuche, Webseiten, Fotos & PDFs |
| Pro | 9,99 €/Monat | 200 | **Claude Opus 5** (das stärkste) | alles aus Plus |

**Kostenrechnung:** Claude Opus 5 kostet 5 $ pro Million Eingabe- und 25 $ pro Million Ausgabe-Tokens, eine Websuche kostet 1 Cent.
- Eine normale Frage kostet grob 3–5 Cent, mit Websuche eher 10–15 Cent. Sonnet ist günstiger.
- Deshalb bekommen Free und Plus Sonnet, und nur Pro bekommt Opus. So verdient ihr auch an Vielnutzern.
- Die Modelle stellst du in `/etc/nova.env` ein: `NOVA_MODEL`, `NOVA_MODEL_PLUS`, `NOVA_MODEL_FREE`.
- Die **tägliche Kostenbremse** für alle zusammen ist `NOVA_DAILY_LIMIT` (Standard 500 Anfragen).
- Stell zusätzlich bei Anthropic ein **Ausgabenlimit** ein: https://console.anthropic.com/settings/limits

## Server starten (ein Befehl, läuft neben AKYTEX)
Im Terminal des Servers, zum Beispiel in der Hetzner-Konsole:
```
curl -fsSL https://raw.githubusercontent.com/georgleomaser-bit/website-test-demo-1/HEAD/nova/server/install.sh | sudo bash
```
- Die **Domain** ist optional. Mit Enter bekommst du eine kostenlose Adresse wie `nova.1-2-3-4.sslip.io`.
- Den **Anthropic-Schlüssel** `sk-ant-…` holst du dir unter https://console.anthropic.com/settings/keys
- Den **Stripe-Schlüssel** kannst du vorerst weglassen.

Solange keine Kaufprüfung eingerichtet ist, haben **alle Nutzer Free** (5 Fragen am Tag). Zum Selbsttesten trägst du in `/etc/nova.env` die Zeile `NOVA_OPEN_PLAN=pro` ein und führst dann `systemctl restart nova` aus. Danach die Zeile wieder löschen, sonst zahlst du für alle Besucher.

Später:
- `nova-update` holt die neueste Version.
- `journalctl -u nova -f` zeigt die Logs.

## Bezahlen (Stripe)
1. In Stripe zwei Abo-Produkte anlegen: **NOVA Plus** (4,99 €/Monat) und **NOVA Pro** (9,99 €/Monat), dazu je einen Payment Link.
2. Bei jedem Link unter „Nach der Zahlung“ diese Adresse eintragen: `https://DEINE-NOVA-ADRESSE/?checkout=success&session_id={CHECKOUT_SESSION_ID}`
3. Die Links in `nova/js/config.js` bei `STRIPE.links` eintragen. Das kann Claude machen.
4. Einen eingeschränkten Stripe-Schlüssel `rk_live_…` erstellen, nur mit Leserechten auf Checkout Sessions, Subscriptions und Payment Links. Dann das Installationsskript erneut ausführen und den Schlüssel eingeben.

Danach prüft der Server jeden Kauf bei Stripe. Nachgebaute Links schalten nichts frei, und gekündigte Abos laufen automatisch aus.

## Sicherheit und Datenschutz
- Der Anthropic-Schlüssel liegt nur auf dem Server, nie im Browser.
- **Anfragen:**
  - Anfragen von fremden Websites werden blockiert.
  - Pro Verbindung und pro Frage gibt es Obergrenzen.
  - Anhänge sind nur als Fotos oder PDFs erlaubt, mit Größengrenze.
- **Server:** Er ist abgeschottet (systemd-Sandbox), dazu kommen Firewall, fail2ban, automatische Sicherheitsupdates und tägliche Backups.
- **Wo die Daten liegen:**
  - Chats, Gedächtnis, Erinnerungen und Sparziele bleiben **auf dem Gerät** des Nutzers.
  - Der Server speichert nur ein anonymes Konto, den Tarif und den Tageszähler.
  - Fragen an die KI gehen verschlüsselt über den Server an Anthropic.
- **Vor dem Start:**
  - eine Datenschutzerklärung schreiben, die Anthropic als Auftragsverarbeiter nennt
  - ein Impressum anlegen
  - die Altersgrenze klären, denn Anthropics Nutzungsbedingungen verlangen für Endnutzer in der Regel 18+ oder die Zustimmung der Eltern. Bitte prüfen.

## Vor dem öffentlichen Start
- **Name:** „NOVA“ ist ein Arbeitstitel. Prüft die Marke beim DPMA/EUIPO. Den Namen ändert ihr an einer Stelle, `BRAND.name` in `nova/js/config.js`. „Jarvis“ ist eine Marvel-Figur und wäre als Produktname riskant.
- **Firma:** Nutzt eure UG/GmbH (akytex united) als Anbieter.
- **Anthropic-Richtlinien:** Die Nutzungsrichtlinien für Apps mit Endkunden gelten auch für NOVA.

## Dateien
| Datei | Inhalt |
|---|---|
| `index.html`, `css/nova.css` | Oberfläche (professionell, hell/dunkel) |
| `js/app.js` | Gespräch, Chats, Tarife, Einstellungen |
| `js/voice.js` | Sprechen und Zuhören (robust auf dem iPhone) |
| `js/skills.js` | Wetter, Timer, Sparziele, Rechner, Gedächtnis |
| `js/orb.js` | animiertes NOVA-Zeichen (hört zu, denkt, spricht) |
| `js/config.js` | Name, Tarife, Stripe-Links (eine Stelle für alles) |
| `server/nova-server.mjs` | Server: Claude, Konten, Kontingente, Kaufprüfung |
| `server/install.sh` | Installation mit einem Befehl |
