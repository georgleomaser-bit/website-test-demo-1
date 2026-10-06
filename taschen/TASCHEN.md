# Arbeitstaschen – dein persönlicher Projektmanager

Arbeitstaschen ist eine App, mit der du deine ganze Arbeit verwaltest: eine **digitale Arbeitstasche pro Bereich oder Projekt**, z. B. Kunden, Büro, Team oder eine Baustelle. Jede Tasche hält Aufgaben, Notizen, Links, Dateien und Meilensteine zusammen. Jeden Tag sagt sie dir wie ein Projektmanager, was ansteht und womit du anfangen solltest.

Die App ist für iPhone, iPad und Mac gebaut, funktioniert offline und gehört nur dir. Sie startet leer – du legst alles selbst an.

**Link:** https://georgleomaser-bit.github.io/website-test-demo-1/taschen/

## Installieren
- **iPhone und iPad:** Öffne den Link in Safari, tippe auf **Teilen ⬆︎** und dann auf **„Zum Home-Bildschirm“**. Erst die installierte App kann Mitteilungen schicken und eine Zahl auf dem App-Symbol zeigen.
- **Mac:** Öffne den Link in Safari und wähle **Ablage → Zum Dock hinzufügen**.

Wichtig: Auf dem iPhone hat die installierte App einen **eigenen Speicher**, getrennt von Safari. Installiere also zuerst und richte dann alles in der App ein. Mit Sync (siehe unten) sind alle Geräte auf demselben Stand.

Beim ersten Start fragt die App nach deinem Namen, nach den **Bereichen deiner Arbeit** (z. B. Kunden, Projekte, Büro & Verwaltung, Team, Termine, Finanzen – oder eigene wie „Baustelle Nord“) und nach deinem Tagesrhythmus. Für jeden Bereich legt sie eine leere Tasche an. Du kannst auch ganz leer starten.

## So arbeitest du damit
- **Heute:** Das Tagesbriefing zeigt, was ansteht, deine **Top 3 im Fokus**, einen Zeitplan, Überfälliges und Taschen, die ins Stocken geraten. Dazu kommen „Tag planen“ am Morgen, der Fokus-Timer und der Tagesabschluss am Abend.
- **Schnell erfassen:** Tippe auf **＋** (auf dem Mac die Taste **N**) und schreib einfach drauflos:
  - `Angebot schicken morgen 9 Uhr #Kunden !!!` legt die Aufgabe für morgen um 9:00 in die Tasche „Kunden“, mit hoher Priorität.
  - `Notar anrufen Freitag 14:30 30 min vorher` setzt eine Erinnerung 30 Minuten vor dem Termin.
  - `Wochenplanung jeden Montag ~45m #Büro` wiederholt die Aufgabe jeden Montag und plant 45 Minuten ein.
  - `Idee: Lager neu sortieren irgendwann` kommt in „Irgendwann“.

  Was die App erkannt hat, siehst du sofort als farbige Chips.
- **Taschen:** Jede Tasche zeigt Fortschritt, Gesundheit (Gut, Achtung, Kritisch) und den nächsten Schritt. In der Tasche gibt es die Bereiche Übersicht, Aufgaben, Board, Notizen, Links, Dateien, Meilensteine und Verlauf. Neue Taschen kannst du aus Vorlagen anlegen: Kunde/Auftrag, Projekt, Büro & Verwaltung, Team & Personal, Besprechung, Veranstaltung, Weiterbildung oder leer.
- **Eingang:** Alles ohne Tasche landet hier. Die App schlägt vor, wohin es gehört, und ein Tipp sortiert es ein.
- **Demnächst:** Hier siehst du Wochenstreifen und Agenda. Ziehst du eine Aufgabe auf einen Tag, wird sie verschoben.
- **Rückblick:** Ein geführter Wochenrückblick mit Erfolgen, leerem Eingang, Neuplanung, Taschen-Check und Fokus für nächste Woche.
- **Suche und Befehle:** **⌘K**, die Lupe oder **/** öffnen sie.
- **Gesten:** Wisch nach rechts = erledigt, nach links = morgen oder löschen. Langes Drücken öffnet ein Menü. Jedes Abhaken lässt sich rückgängig machen.

## Erinnerungen: was am Tag ansteht
Apple lässt Web-Apps im Hintergrund keinen eigenen Code ausführen. Deshalb gibt es mehrere Wege, die sich ergänzen:

| Weg | App offen | App geschlossen | Was du brauchst |
|---|---|---|---|
| Tagesbriefing in „Heute“ | ✅ | – | nichts |
| Banner und Mitteilung zur Uhrzeit | ✅ | – | Mitteilungen erlauben (Einstellungen → Erinnerungen) |
| Zahl auf dem App-Symbol | ✅ wird aktualisiert | ✅ bleibt stehen | Mitteilungen erlauben |
| **Apple Kalender mit Wecker** | ✅ | ✅ | Einstellungen → Erinnerungen → „Tagesbriefing in den Kalender“ bzw. „Alle Termine in den Kalender“ |
| **Apple Erinnerungen** per Kurzbefehl | ✅ | ✅ | einmal den Kurzbefehl anlegen (Anleitung in den Einstellungen) |
| **Push vom eigenen Server**, morgens und zu jedem Termin | ✅ | ✅ | Server (siehe unten) und Mitteilungen erlauben |

Der Kalender-Export ist eine Momentaufnahme. Nach größeren Änderungen exportierst du einfach neu.

## Auf allen Geräten: Sync
Sync gleicht iPhone, iPad und Mac über **deinen eigenen Server** ab, **Ende-zu-Ende-verschlüsselt**. Aus deinem Sync-Code entsteht auf dem Gerät der Schlüssel. Der Server bekommt nur verschlüsselte Daten und kann nichts davon lesen.

1. Installiere den Server (unten). Am Ende zeigt er dir eine Adresse wie `https://taschen.1-2-3-4.sslip.io`.
2. Auf dem ersten Gerät: **Einstellungen → Sync auf allen Geräten → Sync einrichten**, die Server-Adresse eintragen und dann **Kopieren**.
3. Auf jedem weiteren Gerät: **„Ich habe schon einen Code“** wählen und den Code einfügen. Tipp: Auf dem Mac kopieren, auf dem iPhone einfügen; die Universelle Zwischenablage macht das automatisch.

Du kannst die App über GitHub Pages benutzen und den Server nur für Sync, Push und KI eintragen. Oder du installierst die App direkt von der Server-Adresse, dann findet sie den Server von selbst. Wer den Code hat, kann alles lesen. Teile ihn also nur mit Geräten und Menschen, denen du vertraust.

Dateien bis 10 MB werden mit synchronisiert, größere bleiben auf dem Gerät, auf dem sie hochgeladen wurden.

## Google und Outlook verbinden
Verbinde deine Postfächer und Kalender: Outlook, Microsoft 365 und Outlook.com über **Microsoft**, Gmail, Google Kalender und Google Workspace über **Google**. Du kannst mehrere Konten verbinden, etwa Firma und privat.

1. **Einstellungen → Verbindungen → Microsoft** bzw. **Google** (unter „Kalender“ oder „E-Mail“).
2. Melde dich beim Anbieter an und erlaube den Zugriff. Danach bist du automatisch zurück in der App.
3. Das Konto ist über den Sync auch auf deinen anderen Geräten da. Auf dem iPhone verbindest du am besten einmal am Mac oder in Safari.

Das bekommst du danach:
- **Heute:** deine Termine des Tages mit **„Beitreten“** für Teams, Meet, Zoom und Webex. Sie stehen auch im Zeitplan, und das Briefing nennt sie.
- **Demnächst:** Termine der nächsten 30 Tage je Tag und als Punkte im Wochenstreifen.
- **Eingang:** markierte Mails (Gmail: Stern, Outlook: Fahne). Ein Tipp macht daraus eine Aufgabe mit Link zur Mail.
- **An jeder Aufgabe:** „In Kalender eintragen“, „E-Mail schreiben“ und „Anrufen“, sobald eine Telefonnummer im Text steht.
- **Erinnerungen** auch zu deinen Terminen, so viele Minuten vorher wie bei der Standard-Erinnerung eingestellt.

Termine und Mails gehen direkt von Google bzw. Microsoft auf dein Gerät. Der Server vermittelt nur die Anmeldung und bewahrt den Zugang verschlüsselt auf. Wenn deine Firma Microsoft 365 oder Google Workspace sperrt, muss die IT die App einmal freigeben. Ein Backup enthält die Konten ohne Schlüssel. Nach dem Einspielen auf einem neuen Gerät verbindest du sie einfach neu.

Ohne Server gehen „In Kalender eintragen“ (per Link zu Google Kalender oder Outlook oder als Kalender-Datei), „E-Mail schreiben“ und „Anrufen“ trotzdem.

**Einmalige Einrichtung:** Damit die Knöpfe „Mit Google/Microsoft verbinden“ funktionieren, braucht der Server Zugangsdaten von Google und Microsoft. Wie du sie kostenlos anlegst, steht Schritt für Schritt in [`VERBINDEN.md`](VERBINDEN.md).

## Mit allem verbinden
Unter **Einstellungen → Verbindungen** (ganz oben) findest du alles an einem Ort – mit kurzer Anleitung bei jedem Punkt.

- **Kalender per Link:** iCloud („Öffentlicher Kalender“), Google („Privatadresse im iCal-Format“), Outlook („Kalender veröffentlichen“), Firmen-, Schul- und Vereinskalender, Calendly, und die **deutschen Feiertage mit einem Tipp**. Link einfügen, **Testen** („12 Termine gefunden“), **Hinzufügen**. Die Termine erscheinen in Heute und Demnächst. Nur lesen.
- **E-Mail von GMX, WEB.DE, T-Online, iCloud, Yahoo, IONOS, Strato, freenet** oder jedem anderen Anbieter (IMAP): Anbieter antippen, Adresse und Passwort eingeben. Was du dort **markierst** (Fahne, Stern, bei GMX/WEB.DE „Wichtig“), landet im **Eingang** und wird mit einem Tipp zur Aufgabe. Bei GMX und WEB.DE musst du IMAP vorher in deren Einstellungen erlauben, iCloud und Yahoo verlangen ein App-Passwort. Gmail und Outlook verbindest du besser über Google bzw. Microsoft.
- **Nachrichten & Anrufe – ohne Einrichtung:** Steht in einer Aufgabe eine Telefonnummer, E-Mail-Adresse oder Anschrift, zeigt das Aufgaben-Detail unter „Kontakt & Kalender“ passende Knöpfe: **Anrufen, WhatsApp, SMS, FaceTime**, **E-Mail, Teams-Chat, Teams-Anruf**, **Apple Karten, Google Maps, Route**. Zoom-, Teams- und Meet-Links werden zu „Beitreten“. Dazu **Aufgabe teilen** (Teilen-Menü, WhatsApp, Mail, Kopieren).
- **Siri & Kurzbefehle:** Mit „Eingangs-Adresse erstellen“ bekommst du eine geheime Adresse. Ein Kurzbefehl „Neue Aufgabe“ (Nach Eingabe fragen → Inhalte von URL abrufen, POST, JSON `title`) – und **„Hey Siri, neue Aufgabe“** legt sie im Eingang an, „via Siri“. Die Schritt-für-Schritt-Anleitung steht in der App. „Steuerberater anrufen morgen 10 Uhr #Büro“ wird wie in der Schnellerfassung verstanden.
- **Zapier, Make, n8n, IFTTT, Formulare:** dieselbe Adresse nimmt neue Aufgaben an (JSON mit `title`, optional `notes`, `due`, `time`, `bag`, `prio`, `url`). Umgekehrt meldet ein **ausgehender Webhook** „Aufgabe neu“ und „Aufgabe erledigt“ an deinen Zap.
- **Excel & CSV:** Aufgaben als Tabelle exportieren (öffnet sich direkt in Excel, Numbers, Google Tabellen) und Listen aus Excel, **Todoist, Trello oder Asana** importieren – mit Vorschau, Spaltenzuordnung, Zieltasche und „Rückgängig“.

Ehrlich gesagt: Kalender-Links, IMAP und die Eingangs-Adresse brauchen den **Arbeitstaschen-Server**. Er lädt die Kalender-Links für dich, bewahrt IMAP-Zugänge verschlüsselt auf und reicht markierte Mails von GMX & Co. durch. Einträge für die Eingangs-Adresse liegen mit dem Server-Schlüssel verschlüsselt auf dem Server (nicht Ende-zu-Ende) und nur, bis die App sie abholt. Links, Zugänge und Adressen kommen nie ins Backup. Alles hier liest nur – in deinen Postfächern und Kalendern wird nichts gelöscht oder verschickt. Ohne Server gehen Nachrichten & Anrufe, Excel/CSV und „In Kalender eintragen“ trotzdem.

## Server installieren (ein Befehl)
Im Terminal eines eigenen Linux-Servers (z. B. bei Hetzner):
```
curl -fsSL https://raw.githubusercontent.com/georgleomaser-bit/website-test-demo-1/HEAD/taschen/server/install.sh | sudo bash
```
- **Domain:** optional. Mit Enter bekommst du eine kostenlose Adresse wie `taschen.1-2-3-4.sslip.io`.
- **Anthropic-Schlüssel:** optional, nur für den KI-Projektmanager. Den Schlüssel `sk-ant-…` holst du dir unter https://console.anthropic.com/settings/keys

Der Server läuft auf Port 8082 und verträgt sich mit anderen Diensten auf demselben Rechner. Danach gilt:
- `taschen-update` holt die neueste Version.
- `journalctl -u taschen -f` zeigt die Logs.
- Einstellungen stehen in `/etc/taschen.env`, die Daten in `/var/lib/taschen`, mit täglichem Backup.

Für Push auf iPhone und iPad braucht es iOS/iPadOS 16.4 oder neuer und die **installierte** App.

## KI-Projektmanager (optional)
Wenn auf dem Server ein Anthropic-Schlüssel hinterlegt ist, erscheinen in der App ✨-Funktionen: „Plane meinen Tag“, „In Schritte zerlegen“, „Was als Nächstes?“ und Fragen an deinen Projektmanager. Dabei antwortet Claude (`claude-opus-5-5`, änderbar mit `TASCHEN_MODEL`).
- Für eine KI-Frage gehen nur Titel, Termine, Prioritäten und Taschennamen an den Server und von dort an Anthropic. Notizen, Links und Dateien bleiben auf dem Gerät.
- Kostenbremse: `TASCHEN_AI_DAILY` (Standard 100 Anfragen pro Tag). Stell zusätzlich bei Anthropic ein Ausgabenlimit ein: https://console.anthropic.com/settings/limits

## Daten und Datenschutz
- Alles liegt zuerst **auf deinem Gerät**, und die App funktioniert offline.
- **Backup:** Einstellungen → Daten → „Backup exportieren“. Auf dem iPhone landet die Datei über „Teilen“ z. B. in iCloud Drive. Mit „Backup importieren“ holst du sie zurück, als Zusammenführung oder als Ersatz.
- Der Server speichert nur verschlüsselte Sync-Daten und für Push nur Zeitpunkte, nie Aufgabentexte. Sync-IDs tauchen in keinem Log auf.
- „Alles löschen“ entfernt nur die Daten der Taschen-App (alles beginnt mit `taschen-` bzw. `arbeitstaschen`), sonst nichts auf der Adresse.

## Dateien
| Datei | Inhalt |
|---|---|
| `index.html`, `css/taschen.css` | Oberfläche (Apple-Stil, Liquid Glass, hell/dunkel) |
| `js/app.js`, `js/ui/*.js` | Ansichten: Heute, Demnächst, Taschen, Eingang, Rückblick, Einstellungen, Schnellerfassung, Suche, Fokus-Timer … |
| `js/store.js` | Daten: Speichern (IndexedDB), Rückgängig, Backup, Zusammenführen für Sync |
| `js/pm.js` | der Projektmanager: Briefing, Fokus, Gesundheit, Erinnerungsplan, Wochenrückblick |
| `js/dates.js` | Datum, Uhrzeit und die deutsche Schnellerfassung |
| `js/remind.js` | Erinnerungen: Mitteilungen, App-Symbol-Zahl, Kalender (ICS), Kurzbefehl, Push |
| `js/sync.js` | Ende-zu-Ende-verschlüsselter Sync |
| `js/ai.js` | KI-Projektmanager (über den eigenen Server) |
| `js/connect.js`, `js/ui/connectui.js` | Google- und Microsoft-Verbindung: Termine, Calls, markierte Mails, Kalender-Eintrag, E-Mail, Anrufen |
| `js/integrations.js`, `js/ui/integrationsui.js` | „Verbindungen“: Kalender-Links (ICS), IMAP, Siri/Webhooks, WhatsApp/SMS/FaceTime/Teams/Karten, Excel/CSV |
| `js/config.js` | Name, Farben, Speicher, Server-Adresse (eine Stelle für alles) |
| `sw.js`, `manifest.webmanifest`, `icons/` | App-Installation, Offline-Betrieb, Push |
| `server/taschen-server.mjs`, `server/install.sh` | eigener Server: App, Sync, Push, KI; Installation mit einem Befehl |
| `tests/` | automatische Tests: `node --test taschen/tests/*.test.mjs` |
