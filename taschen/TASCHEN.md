# Arbeitstaschen – dein persönlicher Projektmanager

Arbeitstaschen ist eine App für alle deine Projekte, mit einer **digitalen Arbeitstasche pro Projekt**. Jede Tasche hält Aufgaben, Notizen, Links, Dateien und Meilensteine zusammen. Jeden Tag sagt sie dir wie ein Projektmanager, was ansteht und womit du anfangen solltest.

Die App ist für iPhone, iPad und Mac gebaut, funktioniert offline und gehört nur dir. Sie ist komplett getrennt von AKYTEX und NOVA: eigener Ordner, eigene App, eigener Server.

**Link:** https://georgleomaser-bit.github.io/website-test-demo-1/taschen/

## Installieren
- **iPhone und iPad:** Öffne den Link in Safari, tippe auf **Teilen ⬆︎** und dann auf **„Zum Home-Bildschirm“**. Erst die installierte App kann Mitteilungen schicken und eine Zahl auf dem App-Symbol zeigen.
- **Mac:** Öffne den Link in Safari und wähle **Ablage → Zum Dock hinzufügen**.

Wichtig: Auf dem iPhone hat die installierte App einen **eigenen Speicher**, getrennt von Safari. Installiere also zuerst und richte dann alles in der App ein. Mit Sync (siehe unten) sind alle Geräte auf demselben Stand.

Beim ersten Start fragt die App nach deinem Namen und deinem Tagesrhythmus. Mit **„Mit meinen Projekten starten“** lädt sie deine Projekte aus diesem Repo als 7 Taschen: AKYTEX-Plattform & Go-Live, Firma & Beteiligung, Broker-Partner & Echtgeld, Zahlungen & Stripe, Marketing & Clips, Server & Betrieb und NOVA. Darin stecken die offenen Aufgaben aus GO-LIVE, LAUNCH, dem Aktien-Fahrplan, der Broker-Anfrage, MARKETING, PAYMENTS und SERVER, mit Meilensteinen und ein paar eingeplanten nächsten Schritten.

## So arbeitest du damit
- **Heute:** Das Tagesbriefing zeigt, was ansteht, deine **Top 3 im Fokus**, einen Zeitplan, Überfälliges und Taschen, die ins Stocken geraten. Dazu kommen „Tag planen“ am Morgen, der Fokus-Timer und der Tagesabschluss am Abend.
- **Schnell erfassen:** Tippe auf **＋** (auf dem Mac die Taste **N**) und schreib einfach drauflos:
  - `Logo fertig machen morgen 9 Uhr #AKYTEX !!!` legt die Aufgabe für morgen um 9:00 in die Tasche AKYTEX, mit hoher Priorität.
  - `Notar anrufen Freitag 14:30 30 min vorher` setzt eine Erinnerung 30 Minuten vor dem Termin.
  - `Newsletter schreiben jeden Montag ~45m #Marketing` wiederholt die Aufgabe jeden Montag und plant 45 Minuten ein.
  - `Idee: Liga-Saison 2 irgendwann` kommt in „Irgendwann“.

  Was die App erkannt hat, siehst du sofort als farbige Chips.
- **Taschen:** Jede Tasche zeigt Fortschritt, Gesundheit (Gut, Achtung, Kritisch) und den nächsten Schritt. In der Tasche gibt es die Bereiche Übersicht, Aufgaben, Board, Notizen, Links, Dateien, Meilensteine und Verlauf. Neue Taschen kannst du aus Vorlagen anlegen, z. B. Produkt-Launch, Firma/Gründung oder Marketing-Kampagne.
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

## Mail und Kalender (Google und Microsoft)
Unter **Einstellungen → Mail und Kalender** verbindet jeder sein eigenes Postfach. Danach zeigt „Heute“ die **Termine von heute** und die **neuen, ungelesenen Mails**. Ein Tipp auf **＋ Aufgabe** legt die Mail als Aufgabe in den Eingang, mit Absender, Vorschau und einem Link zurück zur Mail.

- **Google:** Gmail und Google Kalender (Hauptkalender).
- **Microsoft:** Outlook.com, Hotmail und Microsoft 365.
- Die App **liest nur**. Sie verschickt, verschiebt und löscht nichts. Alles läuft direkt zwischen Gerät und Google bzw. Microsoft, kein eigener Server liest mit. Die Anmeldung gilt nur auf dem Gerät, auf dem sie gemacht wurde.
- Apple Mail und iCloud-Mail kann keine Web-App lesen (auch keine App aus dem App Store). Für iCloud-Termine gibt es weiterhin den Kalender-Export oben.
- Die Anmeldung hält bei Google etwa eine Stunde, bei Microsoft etwa einen Tag. Danach erscheint in „Heute“ **„… neu verbinden“**. Ein Tipp genügt meist, weil das Konto schon bekannt ist.

### Einmalig einrichten (nur der Betreiber der App)
Damit die Knöpfe erscheinen, braucht die App je eine öffentliche App-Kennung. Beide kommen in `js/config.js` bei `CONNECT`. Als Weiterleitungsadresse gilt überall genau die App-Adresse, z. B. `https://georgleomaser-bit.github.io/website-test-demo-1/taschen/` (mit Schrägstrich am Ende).

**Google** (https://console.cloud.google.com):
1. Neues Projekt anlegen, dann unter „APIs und Dienste → Bibliothek“ die **Gmail API** und die **Google Calendar API** aktivieren.
2. „OAuth-Zustimmungsbildschirm“: Typ **Extern**, App-Name „Arbeitstaschen“, Bereiche `gmail.readonly` und `calendar.events.readonly` hinzufügen.
3. „Anmeldedaten → OAuth-Client-ID“: Typ **Webanwendung**. Bei „Autorisierte JavaScript-Quellen“ `https://georgleomaser-bit.github.io` eintragen, bei „Autorisierte Weiterleitungs-URIs“ die App-Adresse.
4. Die Client-ID (`….apps.googleusercontent.com`) bei `CONNECT.google` eintragen.

Wichtig: Solange die Google-App im **Testmodus** ist, können sich nur bis zu 100 Personen anmelden, die du unter „Testnutzer“ einträgst, und Google zeigt einen Warnhinweis. Für alle Menschen ohne Hinweis verlangt Google eine Prüfung der App, und für Gmail zusätzlich eine kostenpflichtige Sicherheitsprüfung.

**Microsoft** (https://entra.microsoft.com → App-Registrierungen → Neue Registrierung):
1. Kontotypen: **„Konten in einem beliebigen Organisationsverzeichnis und persönliche Microsoft-Konten“**.
2. Umleitungs-URI: Plattform **„Single-Page-Anwendung (SPA)“** und die App-Adresse.
3. Unter „API-Berechtigungen“ für Microsoft Graph (delegiert) `Mail.Read`, `Calendars.Read`, `User.Read` und `offline_access` hinzufügen.
4. Die „Anwendungs-ID (Client)“ bei `CONNECT.microsoft` eintragen.

Microsoft verlangt keine Prüfung. Ohne bestätigten Herausgeber zeigt die Anmeldung „nicht überprüft“ an; manche Firmen-Konten brauchen die Zustimmung ihres Administrators.

## Auf allen Geräten: Sync
Sync gleicht iPhone, iPad und Mac über **deinen eigenen Server** ab, **Ende-zu-Ende-verschlüsselt**. Aus deinem Sync-Code entsteht auf dem Gerät der Schlüssel. Der Server bekommt nur verschlüsselte Daten und kann nichts davon lesen.

1. Installiere den Server (unten). Am Ende zeigt er dir eine Adresse wie `https://taschen.1-2-3-4.sslip.io`.
2. Auf dem ersten Gerät: **Einstellungen → Sync auf allen Geräten → Sync einrichten**, die Server-Adresse eintragen und dann **Kopieren**.
3. Auf jedem weiteren Gerät: **„Ich habe schon einen Code“** wählen und den Code einfügen. Tipp: Auf dem Mac kopieren, auf dem iPhone einfügen; die Universelle Zwischenablage macht das automatisch.

Du kannst die App über GitHub Pages benutzen und den Server nur für Sync, Push und KI eintragen. Oder du installierst die App direkt von der Server-Adresse, dann findet sie den Server von selbst. Wer den Code hat, kann alles lesen. Teile ihn also nur mit Geräten, denen du vertraust, z. B. mit Paul, wenn ihr eine Tasche gemeinsam führt.

Dateien bis 10 MB werden mit synchronisiert, größere bleiben auf dem Gerät, auf dem sie hochgeladen wurden.

## Server installieren (ein Befehl, läuft neben AKYTEX und NOVA)
Im Terminal des Servers, zum Beispiel in der Hetzner-Konsole:
```
curl -fsSL https://raw.githubusercontent.com/georgleomaser-bit/website-test-demo-1/HEAD/taschen/server/install.sh | sudo bash
```
- **Domain:** optional. Mit Enter bekommst du eine kostenlose Adresse wie `taschen.1-2-3-4.sslip.io`.
- **Anthropic-Schlüssel:** optional, nur für den KI-Projektmanager. Den Schlüssel `sk-ant-…` holst du dir unter https://console.anthropic.com/settings/keys

Der Server läuft auf Port 8082 (AKYTEX nutzt 8080, NOVA 8081). Danach gilt:
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
- AKYTEX, NOVA und Arbeitstaschen liegen auf derselben Adresse (github.io), deshalb heißt alles der Taschen-App mit `taschen-` bzw. `arbeitstaschen`. „Alles löschen“ entfernt nur die Daten der Taschen-App.

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
| `js/connect.js` | Mail und Kalender: Anmeldung bei Google und Microsoft, Termine und Mails lesen |
| `js/ai.js` | KI-Projektmanager (über den eigenen Server) |
| `js/seed.js` | deine Projekte als Startdaten |
| `js/config.js` | Name, Farben, Speicher, Server-Adresse (eine Stelle für alles) |
| `sw.js`, `manifest.webmanifest`, `icons/` | App-Installation, Offline-Betrieb, Push |
| `server/taschen-server.mjs`, `server/install.sh` | eigener Server: App, Sync, Push, KI; Installation mit einem Befehl |
| `tests/` | automatische Tests: `node --test taschen/tests/*.test.mjs` |
