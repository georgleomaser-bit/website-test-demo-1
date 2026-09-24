# Eigener AKYTEX-Server

`server/akytex-server.mjs` ist euer eigener Server. Er macht zwei Dinge:
1. **Liefert die komplette Website aus**, also dieselbe App wie auf GitHub Pages.
2. **Betreibt den Clip-Feed für alle:** Videos hochladen und abspielen, Likes, Kommentare, Meldungen und Moderation.
3. **Betreibt die Lounge:** Warteraum, Freunde adden, Sprach- und Videocalls.

Läuft die App über diesen Server, sieht jeder Nutzer die Clips aller anderen Nutzer. Auf GitHub Pages bleibt alles wie bisher: Clips werden dort nur lokal im Browser gespeichert. Die App erkennt automatisch, welcher Fall vorliegt.

Der Server braucht nur **Node.js 20 oder neuer**, keine weiteren Pakete.

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

## Lounge (Warteraum, Freunde, Calls)
Die Lounge läuft automatisch mit, sobald die App über diesen Server aufgerufen wird. Das bietet sie:
- Warteraum mit Anwesenheit
- Freundschaftsanfragen, Blockieren und Melden
- Calls mit Sprache, Video und Bildschirm teilen, bis 8 Personen pro Call
- Einladungen, die überall in der App klingeln

Datenschutz: Audio und Video laufen per WebRTC **direkt zwischen den Geräten**, verschlüsselt. Der Server vermittelt nur den Verbindungsaufbau und zeichnet nichts auf.

- **Wer darf was?**
  - Offene Calls sieht jeder im Warteraum.
  - Private Calls sehen nur Freunde und Eingeladene.
  - Einladen kann man nur Freunde.
  - Wer den Call leitet, kann Personen entfernen (🚪).
  - Blockierte Personen sehen sich nicht mehr und können sich nicht adden, einladen oder verbinden.
- **Verbindungsprobleme:** Manche Mobilfunk- und Firmennetze blockieren direkte Verbindungen. Dafür gibt es TURN-Server als Umleitung, z. B. `coturn` auf eurem VPS oder ein TURN-Dienst:
  ```bash
  TURN_URLS="turn:turn.akytex.org:3478" TURN_USER="akytex" TURN_PASS="geheim" npm start
  ```
  Ohne TURN funktionieren die meisten Calls trotzdem, über den STUN-Server von Cloudflare. Einen anderen STUN-Server stellt ihr mit `STUN_URLS` ein.
- Die Seite muss über **HTTPS** laufen, sonst erlauben Browser weder Mikrofon noch Kamera. Mit Cloudflare Tunnel oder Caddy ist das automatisch so.
- Nutzer-Meldungen aus der Lounge: `npm run admin user-reports`. Sperren mit `npm run admin ban <userId>` wirft die Person sofort aus allen Calls.

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
