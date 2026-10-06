# Google und Outlook verbinden – Einrichtung (einmalig)

Damit die Arbeitstaschen Termine, Calls und markierte Mails aus **Gmail / Google Kalender / Google Workspace** und **Outlook / Microsoft 365 / Outlook.com** übernehmen können, braucht es drei Dinge:

1. den **Arbeitstaschen-Server** (siehe `TASCHEN.md` → „Server installieren“),
2. eine kostenlose **App-Registrierung bei Google** (für Gmail und Google Kalender),
3. eine kostenlose **App-Registrierung bei Microsoft** (für Outlook und Microsoft 365).

Das richtest du einmal ein, das dauert pro Anbieter etwa 15 Minuten. Danach tippt dein Vater in der App nur noch auf **Einstellungen → Verbindungen → Google** bzw. **Microsoft** und meldet sich an.

> Die Oberflächen von Google und Microsoft ändern sich manchmal. Wenn ein Menüpunkt anders heißt, such nach dem fett gedruckten Begriff.

Im Folgenden steht `DEINE-ADRESSE` für die Server-Adresse, die das Installationsskript am Ende anzeigt, z. B. `taschen.1-2-3-4.sslip.io`.

## Teil 1: Google (Gmail, Google Kalender, Google Workspace)
1. Öffne https://console.cloud.google.com und melde dich mit **deinem** Google-Konto an.
2. Lege oben über die Projektauswahl ein **neues Projekt** an, Name: `Arbeitstaschen`.
3. Unter **APIs und Dienste → Bibliothek** schaltest du zwei APIs ein:
   - **Google Calendar API** → „Aktivieren“
   - **Gmail API** → „Aktivieren“
4. Unter **Google Auth Platform** (früher „OAuth-Zustimmungsbildschirm“) gehst du so vor:
   - **Branding:** App-Name `Arbeitstaschen`, deine E-Mail als Support- und Entwickler-Kontakt.
   - **Zielgruppe:** **Extern**.
   - Unter **Testnutzer** trägst du die Google-Adressen deines Vaters ein, privat und Firma.
   - **Datenzugriff → Bereiche hinzufügen:** `…/auth/calendar.readonly`, `…/auth/calendar.events` und `…/auth/gmail.readonly`.
5. Unter **Clients → Client erstellen** wählst du den Anwendungstyp **Webanwendung**:
   - Name: `Arbeitstaschen-Server`.
   - **Autorisierte Weiterleitungs-URI:** `https://DEINE-ADRESSE/api/connect/google/callback`
   - Nach „Erstellen“ kopierst du die **Client-ID** und den **Clientschlüssel**.
6. Auf dem Server führst du das Installationsskript noch einmal aus und fügst Client-ID und Clientschlüssel ein, wenn danach gefragt wird:
   ```
   curl -fsSL https://raw.githubusercontent.com/georgleomaser-bit/website-test-demo-1/HEAD/taschen/server/install.sh | sudo bash
   ```

**Testmodus oder veröffentlichen?**
- Im **Testmodus** dürfen sich nur die eingetragenen Testnutzer anmelden. Google beendet die Verbindung dann aber **nach 7 Tagen**, und dein Vater muss einmal pro Woche neu verbinden.
- Unter **Zielgruppe → „App veröffentlichen“** hält die Verbindung dauerhaft. Weil die App nicht von Google geprüft ist, erscheint bei der Anmeldung der Hinweis **„Google hat diese App nicht überprüft“**. Dein Vater tippt dann auf **„Erweitert“ → „Weiter zu Arbeitstaschen“**. Für die eigene Nutzung ist das in Ordnung.

**Google Workspace (Firmenkonto):** Viele Firmen sperren fremde Apps. Kommt die Meldung, dass der Administrator den Zugriff blockiert, muss die IT die App einmal freigeben. Das geht in der Admin-Konsole unter **Sicherheit → API-Steuerung → App-Zugriffssteuerung**, dort die Client-ID als vertrauenswürdig eintragen.

## Teil 2: Microsoft (Outlook, Microsoft 365, Outlook.com)
1. Öffne https://entra.microsoft.com, also das Microsoft-Entra-Admin-Center.
   - Du brauchst dafür ein Verzeichnis (einen „Mandanten“). Hast du keins, legst du kostenlos ein Azure-Konto an (https://azure.microsoft.com/free). App-Registrierungen kosten nichts.
2. Unter **Anwendungen → App-Registrierungen → Neue Registrierung** trägst du ein:
   - Name: `Arbeitstaschen`.
   - **Unterstützte Kontotypen:** „Konten in einem beliebigen Organisationsverzeichnis **und persönliche Microsoft-Konten**“. Nur so funktionieren Firmenkonto und Outlook.com.
   - **Umleitungs-URI:** Plattform **Web**, Adresse `https://DEINE-ADRESSE/api/connect/microsoft/callback`.
   - Dann auf „Registrieren“.
3. Kopiere die **Anwendungs-ID (Client-ID)** von der Übersichtsseite.
4. Unter **Zertifikate & Geheimnisse → Neuer geheimer Clientschlüssel** wählst du die Gültigkeit **24 Monate**. Kopiere den **Wert** sofort, er wird nur einmal angezeigt.
5. Unter **API-Berechtigungen → Berechtigung hinzufügen → Microsoft Graph → Delegierte Berechtigungen** fügst du hinzu:
   - `offline_access`, `openid`, `email`, `User.Read`, `Calendars.ReadWrite`, `Mail.Read`
6. Führe das Installationsskript auf dem Server noch einmal aus und füge Client-ID und geheimen Schlüssel ein.

**Microsoft 365 (Firmenkonto):** In den meisten Firmen dürfen Mitarbeiter fremde Apps nicht selbst erlauben. Dann erscheint **„Administratorgenehmigung erforderlich“**, und die App zeigt einen Hinweis dazu. Die IT der Firma gibt die App einmal frei: im Entra-Admin-Center unter **Unternehmensanwendungen → Arbeitstaschen → Berechtigungen → „Administratorzustimmung erteilen“**.

**Erinnerung:** Der geheime Schlüssel läuft nach spätestens 24 Monaten ab. Leg dir einen Kalendertermin an, dann erstellst du einen neuen und trägst ihn per Installationsskript ein.

## Was die App damit macht
- **Termine und Calls:**
  - Seine Termine erscheinen in „Heute“ und „Demnächst“.
  - Bei Teams-, Meet- und Zoom-Terminen gibt es einen **„Beitreten“**-Knopf.
  - Die App erinnert ihn vor jedem Termin.
- **Mails zu Aufgaben:** Mails mit **Stern** (Gmail) oder **Fahne** (Outlook) stehen im Eingang und werden mit einem Tipp zur Aufgabe.
- **Aufgaben in den Kalender:** Eine Aufgabe lässt sich direkt in seinen Google- oder Outlook-Kalender eintragen.
- **E-Mail schreiben und anrufen:** Aus jeder Aufgabe heraus kann er eine Mail beginnen oder eine Telefonnummer antippen.

Die Funktionen „E-Mail schreiben“, „Anrufen“ und „In Kalender eintragen“ (per Link) gehen auch **ohne** Server und ohne Anmeldung.

## Datenschutz
- Der Server speichert nur den **Anmelde-Schlüssel** (Refresh-Token), und den **verschlüsselt**.
- Mails und Termine holt die App **direkt** von Google bzw. Microsoft; sie laufen nicht über den Server.
- Trennen: **Einstellungen → Verbindungen → Konto antippen → Trennen**.
  - Bei Google wird der Zugriff dabei auch beim Anbieter entzogen.
  - Bei Microsoft entfernst du ihn zusätzlich unter https://account.microsoft.com/privacy/app-access bzw. bei Firmenkonten unter https://myapps.microsoft.com.
