# Eigener AKYTEX-Server

`server/akytex-server.mjs` ist euer eigener Server. Er macht zwei Dinge:
1. **Liefert die komplette Website aus**, also dieselbe App wie auf GitHub Pages.
2. **Betreibt den Clip-Feed für alle:** Videos hochladen und abspielen, Likes, Kommentare, Meldungen und Moderation.

Läuft die App über diesen Server, sieht jeder Nutzer die Clips aller anderen Nutzer. Auf GitHub Pages bleibt alles wie bisher: Clips werden dort nur lokal im Browser gespeichert. Die App erkennt automatisch, welcher Fall vorliegt.

Der Server braucht nur **Node.js 20 oder neuer**, keine weiteren Pakete.

## ⚡ Einfachster Start: Doppelklick
1. **Node.js** installieren: https://nodejs.org → „LTS“, einmalig.
2. Den Code herunterladen: auf GitHub den Branch `claude/aktex-stock-trading-demo-j0lgog` wählen → **Code** → **Download ZIP** → entpacken.
3. Starten:
   - **Windows:** `AKYTEX-starten.bat` doppelklicken.
   - **Mac:** `AKYTEX-starten.command` doppelklicken. Beim ersten Mal: Rechtsklick → **Öffnen**, weil macOS unbekannte Skripte blockiert.
4. Warten, bis **„✅ AKYTEX ist LIVE“** mit einem Link `https://….trycloudflare.com` erscheint. Der Browser öffnet sich automatisch. Diesen Link an Freunde schicken.

Das Skript lädt beim ersten Start den Cloudflare Tunnel (offizielles Programm, ca. 40 MB) und erzeugt ein Moderations-Passwort in `data/admin-token.txt`. Der Link gilt, solange das Fenster offen und der Rechner an ist. Bei jedem Neustart gibt es einen neuen Link. Eine feste Adresse wie `akytex.org` geht über einen benannten Tunnel (siehe unten, Weg A).

Tipp: Energiesparen am Rechner ausschalten, damit er nicht einschläft.

## Sicherheit (schon eingebaut)
- Öffentlich sind nur Website-Dateien. Server-Code, Datenbank und Dokumente sind nicht abrufbar, Pfad-Tricks (`../`) werden blockiert.
- Sicherheits-Header: CSP, kein Einbetten in fremde Seiten, nosniff, HSTS hinter HTTPS.
- Konten sind anonym: ein Name und ein zufälliger Schlüssel. Gespeichert wird nur der Hash des Schlüssels, keine E-Mail und kein Passwort.
- Rate-Limits pro IP gegen Spam:
  - höchstens 5 neue Konten pro Stunde
  - höchstens 10 Uploads pro Tag und Konto
  - höchstens 10 Kommentare pro Minute
- Videos werden an ihrer Datei-Signatur erkannt, nicht nur an der Endung. Es gehen nur MP4, WebM und MOV bis 60 MB.
- Schreib-Anfragen von fremden Webseiten werden abgewiesen.
- **Meldungen (Digital Services Act):** Nach 3 Meldungen von verschiedenen Nutzern wird ein Clip automatisch ausgeblendet, bis ihr ihn geprüft habt.

## 1. Lokal starten (zum Testen)
```bash
ADMIN_TOKEN="$(openssl rand -hex 24)" npm start
# → http://localhost:8080
```
Den `ADMIN_TOKEN` gut aufheben, damit moderiert ihr. Er muss mindestens 24 Zeichen lang sein, sonst ist die Moderation aus.

Daten liegen in `data/`:
- `db.json`: Nutzer, Clips, Likes, Kommentare, Meldungen
- `videos/`: die Videodateien

**Regelmäßig sichern.**

## 2. Online stellen – drei Wege

### A) Kostenlos: eigener Rechner + Cloudflare Tunnel
Gut für den Start, solange ein Rechner (PC, alter Laptop, Raspberry Pi) durchläuft.
1. Kostenloses Cloudflare-Konto anlegen. Die Domain (z. B. `akytex.org`) bei Cloudflare kaufen oder dorthin umziehen.
2. Auf dem Rechner `cloudflared` installieren und einloggen:
   ```bash
   cloudflared tunnel login
   cloudflared tunnel create akytex
   cloudflared tunnel route dns akytex akytex.org
   ```
3. Server und Tunnel starten:
   ```bash
   ADMIN_TOKEN=... TRUST_PROXY=1 npm start
   cloudflared tunnel run --url http://localhost:8080 akytex
   ```
4. Fertig: https://akytex.org läuft über euren Server, mit HTTPS von Cloudflare.

Zum Ausprobieren ganz ohne Domain: `cloudflared tunnel --url http://localhost:8080` erzeugt sofort eine zufällige `https://….trycloudflare.com`-Adresse.

### B) Kostenlos in der Cloud: Oracle Cloud „Always Free“
Eine kleine Linux-VM ist dauerhaft kostenlos. Für die Anmeldung braucht ihr eine Kreditkarte zur Identitätsprüfung, belastet wird sie nicht. Auf der VM Node.js oder Docker installieren und dann wie bei C) vorgehen.

### C) Günstig und zuverlässig: eigener VPS (ca. 4–5 € im Monat, z. B. Hetzner)
```bash
docker build -t akytex .
docker run -d --restart=always -p 8080:8080 -v akytex-data:/data -e ADMIN_TOKEN=... -e TRUST_PROXY=1 akytex
```
Davor einen Reverse-Proxy mit HTTPS setzen, z. B. Caddy mit der Zeile `akytex.org { reverse_proxy localhost:8080 }`, oder wieder den Cloudflare Tunnel nutzen.

## 3. Moderieren
Ihr seid für die Inhalte auf eurem Server mitverantwortlich. Meldungen müsst ihr zügig prüfen (Digital Services Act).
```bash
export AKYTEX_URL=https://akytex.org ADMIN_TOKEN=...
npm run admin reports          # gemeldete Clips mit Gründen
npm run admin hide <clipId>    # sofort ausblenden
npm run admin restore <clipId> # nach Prüfung wieder freigeben
npm run admin delete <clipId>  # endgültig löschen
npm run admin ban <userId>     # Nutzer sperren
```
Empfehlung: jeden Tag einmal `reports` prüfen. **Strafbare Inhalte** (z. B. Gewalt, Missbrauch, Volksverhetzung) sofort löschen und gegebenenfalls anzeigen.

## 4. Rechtliches vor dem Start
- Die Datenschutzerklärung in der App enthält jetzt einen Abschnitt zum AKYTEX-Server. Den Hosting-Abschnitt anpassen, sobald ihr wisst, wo der Server läuft (z. B. Hetzner, Deutschland).
- **Junge Zielgruppe:** In die AGB ein Mindestalter aufnehmen (üblich: 16 Jahre, sonst Zustimmung der Eltern). Keine Gewinnversprechen in Clips zulassen, denn Finanz-Clips für Jugendliche sind heikel. Der Hinweis „keine Anlageberatung“ ist in App und Upload bereits eingebaut.
- Nutzer bestätigen beim Hochladen die Rechte an Video und Musik sowie die Einwilligung aller gezeigten Personen.
