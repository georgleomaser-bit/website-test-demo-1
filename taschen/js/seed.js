// Arbeitstaschen – Startdaten: Leos echte Projekte bei akytex united als fertig gepackte Taschen (für „Mit meinen Projekten starten“)
//
// Quelle: die Projekt-Dokumente im Repo (README, LAUNCH, GO-LIVE, BUSINESS, AKTIE-FAHRPLAN, BROKER-ANFRAGE, PAYMENTS, MARKETING,
// CLIP-SKRIPT, SERVER, nova/NOVA.md) und die Git-Historie. Keine Geheimnisse, keine Telefonnummern oder E-Mail-Adressen.
//
// Format (siehe Vertrag): SEED = { bags: [{ name, emoji, color, goal, sections, milestones: [{ title, dueIn }],
//   tasks: [{ title, notes, prio, done, section, subtasks, dueIn, time }], notes: [{ title, body }], links: [{ title, url }] }] }
// dueIn = Tage ab dem Laden (0 = heute), null = ohne Datum. store.applySeed() rechnet das in echte Daten um.
// Geschäftliches (Notar, Bank-Anfragen) liegt über werktag() immer auf Mo–Fr – dueIn wird dafür erst beim Lesen berechnet (Getter).
// Zusätzlich (optional, versteht store.applySeed ebenfalls): est (geschätzte Minuten), milestone (Titel eines Meilensteins
// derselben Tasche), waiting („Wartet auf …“), someday („Irgendwann“).
//
// Projektmanager-Plan beim Start – bewusst nur eine Handvoll Termine, alles andere bleibt ohne Datum:
//   heute:  Stripe-Konto aktivieren · Zwei-Faktor-Anmeldung einschalten · Notar in Hamburg anfragen (10:00, am Wochenende → Montag)
//   +2 Tage GbR-Vertrag mit Paul festhalten (17:00) · +3 Testkauf · +4 Mietserver bestellen · +5 Anfrage an Upvest (9:30, nächster Werktag)
//   +7 Tage Launch Tag 1: persönliche Nachrichten (18:00)
// Meilensteine bauen darauf auf: Stripe bereit (+5) → Launch (+7) → Launch-Ziel (+10); Server (+12) → Kaufprüfung (+16) → NOVA live (+18).

// ---------- Helfer ----------
const HOCH = 3;
const MITTEL = 2;
const NIEDRIG = 1;

// Tage bis zum ersten Werktag (Mo–Fr), der mindestens n Tage nach heute liegt – als Funktion, damit erst beim Laden gerechnet wird
const werktag = (n) => () => {
  const d = new Date();
  d.setHours(12, 0, 0, 0); // Mittag: Sommerzeit-Umstellungen verschieben keinen Tag
  d.setDate(d.getDate() + n);
  let k = n;
  while (d.getDay() === 0 || d.getDay() === 6) {
    d.setDate(d.getDate() + 1);
    k++;
  }
  return k;
};

// Offene Aufgabe mit allen Feldern aus dem Vertrag; „more“ überschreibt (notes, subtasks, dueIn, time, est, milestone, waiting, someday).
// dueIn als Funktion (werktag) wird zum Getter: Wer SEED liest, bekommt immer eine Zahl, passend zum Tag des Ladens.
const aufgabe = (title, prio, section, more = {}) => {
  const t = { title, notes: "", prio, done: false, section, subtasks: [], dueIn: null, time: null, ...more };
  if (typeof t.dueIn === "function") {
    Object.defineProperty(t, "dueIn", {
      get: t.dueIn,
      set(v) {
        Object.defineProperty(this, "dueIn", { value: v, writable: true, enumerable: true, configurable: true }); // überschreibbar bleiben
      },
      enumerable: true,
      configurable: true,
    });
  }
  return t;
};
// Schon Erledigtes – zählt in den Fortschritt, bekommt nie ein Datum
const erledigt = (title, prio, section, more = {}) => ({ ...aufgabe(title, prio, section, more), done: true, dueIn: null, time: null });

// ---------- AKYTEX Plattform & Go-Live ----------
const AKYTEX = {
  name: "AKYTEX Plattform & Go-Live",
  emoji: "🚀",
  color: "blue",
  goal: "AKYTEX vom Trading-Simulator zu einer öffentlich startklaren Plattform für echte Kunden ausbauen.",
  sections: ["Sicherheit", "Start", "Technik", "Backend", "Recht", "Produkt"],
  milestones: [
    { title: "Eigene Domain live", dueIn: 21 },
    { title: "Beta mit ersten Nutzern", dueIn: 45 },
    { title: "Go-Live mit echten Kunden", dueIn: null },
  ],
  tasks: [
    aufgabe("Zwei-Faktor-Anmeldung für alle Konten einschalten", HOCH, "Sicherheit", {
      notes: "Keine Passwörter doppelt verwenden – am besten Passkeys oder einen Passwort-Manager nutzen.",
      subtasks: ["GitHub", "Stripe", "Google", "E-Mail"],
      dueIn: 0,
      est: 30,
    }),
    aufgabe("Warteliste bzw. Beta mit ausgewählten Nutzern starten", MITTEL, "Start", { notes: "Laut Roadmap: Produkt zeigen, Feedback sammeln, Warteliste aufbauen.", milestone: "Beta mit ersten Nutzern" }),
    aufgabe("Sicherheits-Audit / Penetrationstest beauftragen", MITTEL, "Start", {
      notes: "Vor dem Start mit echten Kunden. Demo-Hinweise erst entfernen, wenn echte Kurse und echtes Geld live sind.",
      milestone: "Go-Live mit echten Kunden",
    }),
    aufgabe("Status-Seite und Support-Kontakt einrichten", NIEDRIG, "Start", { milestone: "Go-Live mit echten Kunden" }),
    erledigt("Website technisch startklar machen", MITTEL, "Technik", {
      notes: "Laut LAUNCH.md abgehakt, inkl. CSP und Referrer-Policy (Git-Historie).",
      subtasks: ["Hosting-Konfiguration mit Sicherheits-Headern (netlify.toml, vercel.json)", "SEO: Open Graph, JSON-LD, robots.txt, sitemap.xml", "PWA: Manifest, Service Worker, Installations-Button", "404-Seite, Skip-Link, Fokus-Rahmen, reduzierte Bewegung"],
    }),
    erledigt("Öffentlich auf GitHub Pages veröffentlichen", MITTEL, "Technik", { notes: "Wird automatisch aus dem Standard-Branch veröffentlicht und ist nach 1–2 Minuten online." }),
    erledigt("Sichtbarkeit bei Google und KI-Assistenten verbessern", NIEDRIG, "Technik", { notes: "Über-Seite, strukturierte Daten und llms.txt (Commit #37)." }),
    aufgabe("Eigene Domain verbinden", MITTEL, "Technik", {
      notes: "Settings → Pages → Custom domain, HTTPS aktiv. Danach Adresse in robots.txt und sitemap.xml anpassen.",
      subtasks: ["Domain wählen", "Custom Domain in GitHub Pages eintragen", "HTTPS aktivieren", "robots.txt und sitemap.xml anpassen"],
      milestone: "Eigene Domain live",
    }),
    aufgabe("Monitoring und Uptime-Überwachung einrichten", NIEDRIG, "Technik", { notes: "Fehler-Tracking z. B. datenschutzfreundlich selbst gehostet." }),
    aufgabe("Benutzerkonten mit Login einführen", HOCH, "Backend", { notes: "Passkeys/2FA statt lokaler Browser-Speicherung, Voraussetzung für echte Kunden.", milestone: "Beta mit ersten Nutzern" }),
    aufgabe("Datenbank für Depots, Orders, Ideen und Clips aufsetzen", MITTEL, "Backend", { notes: "Auch Kommentare zentral speichern statt im Browser.", milestone: "Beta mit ersten Nutzern" }),
    aufgabe("Video-Speicher und Transcoding für Clips lösen", NIEDRIG, "Backend", { notes: "Mit CDN für die Auslieferung.", someday: true }),
    aufgabe("DSA-Pflichten für Clips und Ideen umsetzen", HOCH, "Recht", {
      notes: "Die Melde-Funktion ist eingebaut, der Rest fehlt noch.",
      subtasks: ["Moderationsprozess festlegen", "Kontaktstelle benennen", "Transparenzangaben ergänzen", "Jugendschutz prüfen"],
      milestone: "Go-Live mit echten Kunden",
    }),
    aufgabe("Finfluencer-Regeln umsetzen", MITTEL, "Recht", { notes: "Ideen und Clips mit Anlagebezug als Meinung kennzeichnen und Interessenkonflikte offenlegen (MAR).", milestone: "Go-Live mit echten Kunden" }),
    erledigt("Kern-Features ausbauen", MITTEL, "Produkt", {
      notes: "Laut Git-Historie umgesetzt.",
      subtasks: ["Aky-KI-Assistent mit Sprachmodus", "Liga für Freunde und Schulklassen", "Geld-Akademie mit Lektion des Tages", "Zukunfts-Ich-Sparrechner", "Neue Startseite mit Hero-Animation und Bento-Raster"],
    }),
  ],
  notes: [
    {
      title: "Go-Live-Schalter",
      body: "Alles für den Echtbetrieb steht in `js/config.js`: **company**, **stripe**, **marketData**, **trading**. Jeder Teil schaltet sich frei, sobald seine Felder gefüllt sind.\n\n- „LIVE“ statt „DEMO“ zeigt die App erst, wenn echte Kurse **und** echtes Depot angeschlossen sind.\n- Mit echtem Geld macht der Autopilot nur Vorschläge.",
    },
    {
      title: "Roadmap",
      body: "- **Jetzt:** Produkt zeigen, Feedback, Warteliste\n- **Phase 1:** echte Kursdaten, Benutzerkonten, Cloud-Sync, Beta\n- **Phase 2:** Partner-Broker, KYC, echtes Depot\n- **Phase 3:** Copy-Trading mit Umsatzbeteiligung, Sparpläne, ETFs, native Apps\n- **Phase 4:** EU-Expansion, B2B-Lizenzen",
    },
    {
      title: "Positionierung & USP",
      body: "**Zielgruppe:** 18- bis 45-jährige Selbstentscheider in DACH, danach die EU.\n\n**USP – die Ideen-Börse:** Ideen werden mit SHA-256 versiegelt, die Trefferquote wird live gemessen, und 50–70 % der Ideen-Gebühr (0,10–0,25 %) gehen als Royalty an die Autoren.",
    },
  ],
  links: [
    { title: "AKYTEX App", url: "https://georgleomaser-bit.github.io/website-test-demo-1/" },
    { title: "Über AKYTEX", url: "https://georgleomaser-bit.github.io/website-test-demo-1/ueber-akytex.html" },
    { title: "TradingView Lightweight Charts", url: "https://github.com/tradingview/lightweight-charts" },
  ],
};

// ---------- Firma & Beteiligung ----------
const FIRMA = {
  name: "Firma & Beteiligung",
  emoji: "🏢",
  color: "indigo",
  goal: "akytex united von der GbR zur UG oder GmbH machen und den Weg für Investoren und eine echte Beteiligung vorbereiten.",
  sections: ["GbR jetzt", "Gründung", "Nach Eintragung", "Recht", "Investoren"],
  milestones: [
    { title: "GbR-Vertrag unterschrieben", dueIn: 9 },
    { title: "Gründung beim Notar beurkundet", dueIn: 30 },
    { title: "UG/GmbH eingetragen", dueIn: 60 },
  ],
  tasks: [
    aufgabe("Impressum auf „akytex united GbR“ ändern", HOCH, "GbR jetzt", { notes: "Tipp aus dem Fahrplan, solange keine Firma eingetragen ist.", est: 15 }),
    aufgabe("GbR-Vertrag schriftlich festhalten", HOCH, "GbR jetzt", {
      notes: "Zusammen mit Paul durchgehen und von beiden unterschreiben lassen.",
      subtasks: ["Anteile", "Aufgaben", "Entscheidungen", "Regeln bei Streit oder Ausstieg"],
      dueIn: 2,
      time: "17:00",
      est: 90,
      milestone: "GbR-Vertrag unterschrieben",
    }),
    aufgabe("Rechtsform festlegen: UG oder GmbH", HOCH, "Gründung", {
      notes: "UG ab 1 € Stammkapital (ein Viertel des Gewinns ansparen, bis 25.000 € erreicht sind). GmbH 25.000 €, davon mind. 12.500 € bei Gründung.",
      milestone: "Gründung beim Notar beurkundet",
    }),
    aufgabe("Notar in Hamburg anfragen", HOCH, "Gründung", {
      notes: "Suche über die „Notarauskunft“ der Bundesnotarkammer. Online-Gründung per Video ist möglich, dafür braucht es einen Personalausweis mit Online-Funktion und ein Smartphone.",
      dueIn: werktag(0),
      time: "10:00",
      est: 20,
      milestone: "Gründung beim Notar beurkundet",
    }),
    aufgabe("Unterlagen für den Notar vorbereiten", HOCH, "Gründung", {
      subtasks: ["Firmenname, z. B. „AKYTEX UG (haftungsbeschränkt)“", "Sitz Hamburg", "Unternehmensgegenstand formulieren", "Stammkapital und Anteile (z. B. 50/50)", "Geschäftsführer festlegen", "Ausweise und Adressen"],
      milestone: "Gründung beim Notar beurkundet",
    }),
    aufgabe("Notartermin wahrnehmen und Vertrag unterschreiben", HOCH, "Gründung", { notes: "Der Notar liest den Gesellschaftsvertrag vor, ihr unterschreibt.", milestone: "Gründung beim Notar beurkundet" }),
    aufgabe("Geschäftskonto eröffnen und Stammkapital einzahlen", HOCH, "Gründung", { notes: "Einzahlungsnachweis an den Notar, der die Firma beim Handelsregister anmeldet.", milestone: "UG/GmbH eingetragen" }),
    aufgabe("Firma nach der Eintragung anmelden", MITTEL, "Nach Eintragung", {
      subtasks: ["Gewerbe anmelden", "Finanzamt-Fragebogen (steuerliche Erfassung)", "Transparenzregister", "IHK"],
      waiting: "Eintragung ins Handelsregister",
    }),
    aufgabe("Steuerberater beauftragen", MITTEL, "Nach Eintragung", { notes: "Umsatzsteuer, Kleinunternehmerregelung ja oder nein, Buchhaltung für die Stripe-Einnahmen." }),
    aufgabe("Impressum, AGB und Stripe auf die neue Firma umstellen", MITTEL, "Nach Eintragung", {
      notes: "In js/config.js fehlen noch register, vatId, supervisory und privacyContact.",
      waiting: "Eintragung ins Handelsregister",
    }),
    erledigt("Impressum mit Daten von akytex united füllen", HOCH, "Recht", { notes: "Anschrift und verantwortliche Personen sind in js/config.js eingetragen (Commit #5). Handelsregister und USt-IdNr. fehlen noch." }),
    aufgabe("Rechtstexte anwaltlich prüfen lassen", HOCH, "Recht", {
      notes: "Die Vorlagen unter „Rechtliches“ enthalten markierte Platzhalter.",
      subtasks: ["Impressum", "Datenschutzerklärung", "AGB", "Widerrufsbelehrung", "Risikohinweise"],
    }),
    aufgabe("Businessplan und Pitch-Texte erstellen", MITTEL, "Investoren", { notes: "Grundlage sind BUSINESS.md und die Kennzahlen aus dem Business-Dashboard der App." }),
    aufgabe("Investoren-Weg wählen", NIEDRIG, "Investoren", {
      notes: "Ohne erlaubtes Angebot darf es keinen Kaufen-Knopf für Anteile in der App geben.",
      subtasks: ["Business Angels / Freunde & Familie (per Notarvertrag)", "Crowdinvesting über lizenzierte Plattform (z. B. Companisto, Seedmatch)", "Echte Aktien erst als AG (Grundkapital mind. 50.000 €)"],
    }),
    aufgabe("Investoren-Seite in der App bauen", NIEDRIG, "Investoren", {
      notes: "Erst wenn es eine erlaubte Kampagne gibt: Vision, Team, Kennzahlen und Link zur Crowdinvesting-Kampagne.",
      waiting: "eine erlaubte Crowdinvesting-Kampagne",
    }),
  ],
  notes: [
    {
      title: "Ausgangslage",
      body: "Leo Maser und Paul Jazra betreiben akytex united als **GbR ohne eingetragene Firma**.\n\n- Sie haften persönlich mit dem Privatvermögen.\n- Eine GbR kann keine Aktien ausgeben.\n- Für Stripe-Umsätze, Broker-Partner und Investoren wird eine Kapitalgesellschaft gebraucht.",
    },
    {
      title: "Kosten & Grenzen",
      body: "- **UG mit Musterprotokoll:** einige hundert Euro für Notar und Handelsregister\n- **GmbH mit eigenem Vertrag:** ca. 800–1.500 € plus Stammkapital\n- **Öffentliches Angebot:** bis 8 Mio. € ein von der BaFin gestattetes Wertpapier-Informationsblatt, darüber ein Prospekt",
    },
    {
      title: "Unternehmensgegenstand (Vorschlag)",
      body: "> „Entwicklung und Betrieb von Software und digitalen Informationsdiensten rund um Finanzmärkte; keine erlaubnispflichtigen Bank- oder Finanzdienstleistungen“\n\nSitz: Hamburg. Die Schritte 2–5 sollten Notar, Steuerberater und ein Anwalt für Kapitalmarktrecht begleiten.",
    },
  ],
  links: [
    { title: "BaFin zu Crowdfunding", url: "https://www.bafin.de/DE/verbraucherinnen-verbraucher/themen-finanzprodukte/geldanlage/crowdfunding/crowdfunding_node.html" },
    { title: "Crowdfunding-Plattformen im Vergleich 2026", url: "https://www.starting-up.de/geld/crowdfunding/crowdfunding-plattformen-im-vergleich-2026.html" },
    { title: "Crowdinvesting rechtlich", url: "https://www.mtrlegal.com/wiki/crowdinvesting/" },
  ],
};

// ---------- Broker-Partner & Echtgeld ----------
const BROKER = {
  name: "Broker-Partner & Echtgeld",
  emoji: "🤝",
  color: "teal",
  goal: "Einen lizenzierten Broker-Partner gewinnen und echte Kurse sowie ein echtes Depot an AKYTEX anbinden.",
  sections: ["Anfrage", "Vorbereitung", "Regulierung", "Technik"],
  milestones: [
    { title: "Anfragen an Upvest und Baader verschickt", dueIn: 8 },
    { title: "Partnervertrag unterschrieben", dueIn: null },
  ],
  tasks: [
    aufgabe("Broker-Anbieter vergleichen", HOCH, "Anfrage", {
      notes: "Stand September 2026, bitte selbst prüfen. Mit Mindestvolumen, Einrichtungsgebühren und einer Prüfung des Unternehmens rechnen.",
      subtasks: ["Upvest (API-Plattform, Berlin)", "Baader Bank (Partnerbank für Neobroker)", "Weitere unter „Brokerage as a Service“ suchen"],
      milestone: "Anfragen an Upvest und Baader verschickt",
    }),
    aufgabe("Partnerschaftsanfrage an Upvest senden", HOCH, "Anfrage", {
      notes: "E-Mail-Vorlage in BROKER-ANFRAGE.md.",
      dueIn: werktag(5),
      time: "09:30",
      est: 30,
      milestone: "Anfragen an Upvest und Baader verschickt",
    }),
    aufgabe("Partnerschaftsanfrage an Baader Bank senden", HOCH, "Anfrage", { notes: "Dieselbe Vorlage verwenden.", est: 20, milestone: "Anfragen an Upvest und Baader verschickt" }),
    aufgabe("Termin vereinbaren und Konditionen klären", MITTEL, "Anfrage", {
      subtasks: ["Modell: gebundener Vermittler, Haftungsdach oder White-Label", "Voraussetzungen: Rechtsform, Eigenkapital, Personal, Compliance", "Kosten: Einrichtung, laufend, pro Order/Konto", "Dauer der Anbindung"],
      milestone: "Partnervertrag unterschrieben",
    }),
    aufgabe("Unterlagen für den Partner vorbereiten", HOCH, "Vorbereitung", {
      subtasks: ["Kapitalgesellschaft statt GbR (siehe Firma)", "Businessplan mit Kundenzahlen und Finanzierung", "Verantwortliche Person für Compliance/Geldwäsche", "Link zur öffentlichen App als Demo"],
      milestone: "Partnervertrag unterschrieben",
    }),
    aufgabe("Erlaubnisfragen zu AKYTEX AI und Autopilot klären", HOCH, "Regulierung", {
      notes: "Persönliche Empfehlungen sind Anlageberatung, selbstständiges Handeln ist Finanzportfolioverwaltung. Beides braucht eine BaFin-Erlaubnis oder ein Haftungsdach bzw. einen lizenzierten Partner.",
    }),
    erledigt("App-Schnittstellen für Depot und Kurse vorbereiten", MITTEL, "Technik", { notes: "Echtgeld-Adapter und die Felder trading/marketData in js/config.js (Commit #4)." }),
    erledigt("Mock-Broker zum Testen bereitstellen", NIEDRIG, "Technik", { notes: "server/mock-broker.mjs bildet die Schnittstelle ohne echtes Geld nach (localhost:8787)." }),
    aufgabe("Kursdaten-Anbieter auswählen", MITTEL, "Technik", { notes: "Echtzeitkurse sind lizenzpflichtig, verzögerte Kurse sind günstiger. Der Anbieter braucht eine API und Weiterverbreitungsrecht." }),
    aufgabe("Backend für die Partner-Anbindung bauen", MITTEL, "Technik", {
      notes: "Der Server spricht mit Partner und Datenanbieter und hält die Schlüssel geheim. GitHub Pages kann nur die App ausliefern.",
      subtasks: ["GET /auth/login", "GET /account", "POST, DELETE, PATCH /orders", "POST /transfers", "Kurshistorie und Live-Stream (SSE)"],
    }),
    aufgabe("Partner- und Kursdaten-Adressen eintragen", MITTEL, "Technik", {
      notes: "In js/config.js.",
      subtasks: ["trading.apiBase", "trading.partnerName", "marketData.streamUrl", "marketData.historyUrl"],
    }),
    aufgabe("CSP um Broker- und Kursdaten-Adressen ergänzen", MITTEL, "Technik", { notes: "connect-src im Meta-Tag von index.html und 404.html." }),
  ],
  notes: [
    {
      title: "Kandidaten",
      body: "- **Upvest** (Berlin): API-first, wird u. a. von N26, Revolut und Vivid genutzt, laut Presse jetzt auch von der DKB.\n- **Baader Bank** (Unterschleißheim): Depot- und Abwicklungspartner u. a. für Trade Republic, Scalable Capital und justTRADE.",
    },
    {
      title: "Was der Partner übernehmen soll",
      body: "Alles über eine API:\n\n- Konto- und Depoteröffnung inkl. KYC/AML\n- Orderausführung (Aktien, ETFs; Market, Limit, Stop)\n- Verwahrung\n- Ein- und Auszahlungen (SEPA, ggf. Karte/Wallets)\n- Kosten- und Steuerreporting",
    },
  ],
  links: [
    { title: "Baader Bank als Partnerbank", url: "https://www.bankdaten.de/baader-bank.html" },
    { title: "DKB und Upvest", url: "https://www.neuebanken.de/dkb-greift-neobroker-an/" },
    { title: "Baader-Partnernetzwerk", url: "https://www.finanzwire.com/press-release/baader-wertpapierhandelsbank-ag-etr-bwb-baader-bank-and-robomarkets-announce-partnership-zobO1Z2C6rb" },
  ],
};

// ---------- Zahlungen & Stripe ----------
const ZAHLUNGEN = {
  name: "Zahlungen & Stripe",
  emoji: "💳",
  color: "purple",
  goal: "Das Stripe-Konto „akytex“ zahlungsfähig machen und Käufe fälschungssicher freischalten.",
  sections: ["Stripe-Konto", "Kaufprüfung", "Shop"],
  milestones: [
    { title: "Stripe nimmt Zahlungen an", dueIn: 5 },
    { title: "Kaufprüfung live auf dem Server", dueIn: 16 },
  ],
  tasks: [
    erledigt("Abo-Produkte, Preise und Payment Links anlegen", HOCH, "Stripe-Konto", { notes: "Payment Links mit 14 Tagen Testphase und Gutscheinfeld sind in js/config.js eingetragen, inkl. Ultra (Commit #6)." }),
    erledigt("Kundenportal einrichten", MITTEL, "Stripe-Konto", { notes: "Zahlungsmethode ändern, kündigen, Rechnungen." }),
    erledigt("Gutschein AKYTEXLEO anlegen", NIEDRIG, "Stripe-Konto", { notes: "50 % dauerhaft, teilbar per Link …/?code=AKYTEXLEO." }),
    erledigt("Gründer-Deal-Links anlegen", HOCH, "Stripe-Konto", { notes: "Pro 12 Monate für 49 € und AKYTEX AI 12 Monate für 199 €, je 100 Plätze per Stripe-Limit." }),
    aufgabe("Stripe-Konto aktivieren", HOCH, "Stripe-Konto", {
      notes: "Dashboard → Konto aktivieren. Solange das fehlt, schlägt jede Zahlung fehl – und der Launch hängt daran.",
      subtasks: ["Identität", "Unternehmen", "Bankkonto"],
      dueIn: 0,
      est: 30,
      milestone: "Stripe nimmt Zahlungen an",
    }),
    aufgabe("Testkauf durchführen und erstatten", HOCH, "Stripe-Konto", {
      notes: "Einen Deal selbst kaufen und danach in Stripe unter Zahlungen → Erstatten zurückbuchen.",
      dueIn: 3,
      est: 15,
      milestone: "Stripe nimmt Zahlungen an",
    }),
    aufgabe("Zahlungsmethoden einschalten", MITTEL, "Stripe-Konto", {
      notes: "Unter Einstellungen → Zahlungsmethoden, nach der Aktivierung.",
      subtasks: ["Karte", "SEPA-Lastschrift", "PayPal", "Apple Pay und Google Pay", "Klarna", "Danach Beschränkung der Links auf Karte entfernen"],
      milestone: "Stripe nimmt Zahlungen an",
    }),
    aufgabe("AGB-Adresse und Steuer in Stripe einstellen", MITTEL, "Stripe-Konto", { notes: "Einstellungen → Öffentliche Details. Stripe Tax bzw. 19 % MwSt., Preise inkl. Steuer." }),
    erledigt("Serverseitige Kaufprüfung programmieren", HOCH, "Kaufprüfung", { notes: "Der Server fragt jeden Kauf bei Stripe nach (Commit #25). Dafür braucht er noch den Schlüssel." }),
    aufgabe("Eingeschränkten Stripe-Schlüssel für den Server erstellen", HOCH, "Kaufprüfung", {
      notes: "Nur Lesen für Checkout Sessions, Subscriptions und Payment Links, nie den Hauptschlüssel. Beim Installationsskript des Servers eingeben.",
      milestone: "Kaufprüfung live auf dem Server",
    }),
    aufgabe("Rückleitung der Payment Links auf den Server umstellen", MITTEL, "Kaufprüfung", {
      notes: "Bei jedem Link unter „Nach der Zahlung“ die Server-Adresse mit ?checkout=success&session_id={CHECKOUT_SESSION_ID} eintragen.",
      milestone: "Kaufprüfung live auf dem Server",
    }),
    aufgabe("Store-Käufe im Live-Betrieb freischalten", NIEDRIG, "Shop", {
      notes: "Der Store bleibt geschlossen, bis diese Punkte geklärt sind.",
      subtasks: ["Versand und Widerruf für physische Waren", "Preisangaben nach PAngV", "Verpackungsregister LUCID für Merch", "Einlösung von Geschenkkarten"],
    }),
  ],
  notes: [
    {
      title: "Preise (monatlich / jährlich)",
      body: "- **Plus:** 4,99 € / 47,88 €\n- **Pro:** 12,99 € / 119,88 €\n- **Elite:** 29,99 € / 299,88 €\n- **AKYTEX AI:** 99 € / 948 €\n- **AI Premium:** 249 € / 2.388 €\n- **Ultra:** 299 € / 2.868 €\n\nOrdergebühr: 1 € (Free), 0,50 € (Plus), 0 € ab Pro.",
    },
    {
      title: "Gebühren & Auszahlung",
      body: "- Bei EU-Karten grob 1,5 % + 0,25 € pro Zahlung.\n- Neue Stripe-Konten zahlen erst nach ca. 7–14 Tagen aufs Bankkonto aus.\n- Kundinnen und Kunden haben 14 Tage Widerrufsrecht.",
    },
    {
      title: "Grenze ohne Server",
      body: "Ohne Server schaltet die App den Tarif nach der Rückkehr von Stripe im Browser frei – das lässt sich theoretisch fälschen. Die Kaufnummer (session_id) wird schon gespeichert und kann später geprüft werden.",
    },
  ],
  links: [
    { title: "Stripe", url: "https://stripe.com" },
    { title: "Gründer-Deal Pro (49 €)", url: "https://buy.stripe.com/cNidRbeiT1hAaKl10Y77O0a" },
    { title: "Gründer-Deal AKYTEX AI (199 €)", url: "https://buy.stripe.com/bJe28t4IjaSacStdNK77O0b" },
  ],
};

// ---------- Marketing & Clips ----------
const MARKETING = {
  name: "Marketing & Clips",
  emoji: "📣",
  color: "pink",
  goal: "Mit dem 3-Tage-Launch Gründer-Plätze verkaufen und AKYTEX mit echten Clips von Leo und Paul bekannt machen.",
  sections: ["Vorbereitung", "Tag 1", "Tag 2", "Tag 3", "Clips"],
  milestones: [
    { title: "3-Tage-Launch startet", dueIn: 7 },
    { title: "Launch-Ziel: ca. 1.100 € Umsatz", dueIn: 10 },
    { title: "Erster Clip online", dueIn: 14 },
  ],
  tasks: [
    erledigt("Launch-Paket und Gründer-Deal-Banner erstellen", MITTEL, "Vorbereitung", { notes: "MARKETING.md und Banner auf der Startseite (Commit #9)." }),
    aufgabe("Persönliche Nachrichten an 30–50 Kontakte senden", HOCH, "Tag 1", {
      notes: "Per WhatsApp, Telegram oder Instagram-DM, persönlich und ohne Massen-Spam. Vorlage in MARKETING.md. Vorher muss das Stripe-Konto aktiviert sein.",
      dueIn: 7,
      time: "18:00",
      est: 60,
      milestone: "3-Tage-Launch startet",
    }),
    aufgabe("Instagram-Story mit 3 Slides posten", HOCH, "Tag 1", {
      subtasks: ["Screenshot Startseite: „Wir haben eine Trading-App gebaut“", "Screen-Aufnahme KI-Chat: „Die KI steuert die ganze App“", "Gründer-Deal-Karte mit Link-Sticker"],
      milestone: "3-Tage-Launch startet",
    }),
    aufgabe("TikTok/Reel (30 s) aufnehmen und posten", HOCH, "Tag 2", {
      notes: "Bildschirmaufnahme mit Voice-over.",
      subtasks: ["Hook 0–3 s", "Sprachbefehl-Demo: Chart springt, Post erscheint", "Clips-Feed und Ideen-Börse zeigen", "CTA: kostenlos testen, Link in Bio", "Hinweis „Keine Anlageberatung, Handel mit virtuellem Geld“"],
      milestone: "Launch-Ziel: ca. 1.100 € Umsatz",
    }),
    aufgabe("LinkedIn-Post veröffentlichen", MITTEL, "Tag 2", { notes: "Seriöser Ton, Vorlage in MARKETING.md.", milestone: "Launch-Ziel: ca. 1.100 € Umsatz" }),
    aufgabe("In passenden Communities posten", MITTEL, "Tag 2", {
      notes: "Nur dort, wo Eigenwerbung erlaubt ist (Regeln lesen). Als Bitte um Feedback formulieren, nicht als Werbung.",
      milestone: "Launch-Ziel: ca. 1.100 € Umsatz",
    }),
    aufgabe("Interessenten einmal freundlich erinnern", MITTEL, "Tag 3", { notes: "Nur schreiben, was stimmt.", milestone: "Launch-Ziel: ca. 1.100 € Umsatz" }),
    aufgabe("Käufer um Feedback bitten und echten Stand teilen", MITTEL, "Tag 3", { notes: "Keine gekauften oder erfundenen Bewertungen, nur echte Zahlen posten.", milestone: "Launch-Ziel: ca. 1.100 € Umsatz" }),
    erledigt("Clip-Skript „Wir sind AKYTEX“ schreiben", MITTEL, "Clips", { notes: "CLIP-SKRIPT.md (Commit #13)." }),
    aufgabe("Ersten Clip „Wir sind AKYTEX“ drehen", HOCH, "Clips", {
      notes: "Leo und Paul, hochkant 9:16, 45–60 s, Schnitt alle 2–3 s, Untertitel immer an.",
      subtasks: ["Hook 3- bis 5-mal in Varianten drehen", "Bildschirmaufnahme mit der App im Dunkelmodus", "In CapCut schneiden, automatische Untertitel", "Lizenzfreie Musik, ggf. Ansteckmikro"],
      milestone: "Erster Clip online",
    }),
    aufgabe("Clip im Feed und auf TikTok, Reels und Shorts posten", MITTEL, "Clips", { notes: "Caption aus CLIP-SKRIPT.md inkl. „Keine Anlageberatung“.", milestone: "Erster Clip online" }),
    aufgabe("Folge-Clips produzieren", NIEDRIG, "Clips", {
      subtasks: ["„Was ist ein RSI? In 12 Sekunden“", "„Wir tippen live: NVDA hoch oder runter?“", "„Behind the Scenes: So bauen wir AKYTEX“"],
      someday: true,
    }),
  ],
  notes: [
    {
      title: "Umsatzziel 3-Tage-Launch",
      body: "**Ziel: ca. 1.100 €** – 23 Pro-Deals (49 €) oder 6 AI-Deals (199 €), z. B. 3 × AI + 10 × Pro = 1.087 €.\n\nDavon gehen Stripe-Gebühren ab, und das Geld kommt bei neuen Konten erst nach 7–14 Tagen.",
    },
    {
      title: "Nicht machen",
      body: "- Keine Gewinnversprechen, keine falsche Knappheit oder Countdowns\n- Keine gekauften Follower, Fake-Bewertungen oder Massen-DMs\n- Nicht „Echtzeit-Kurse“ oder „echten Handel“ behaupten\n- Keine echten Depotstände und keine fremde Musik ohne Lizenz zeigen",
    },
  ],
  links: [
    { title: "AKYTEX App", url: "https://georgleomaser-bit.github.io/website-test-demo-1/" },
    { title: "Gründer-Deal Pro (49 €)", url: "https://buy.stripe.com/cNidRbeiT1hAaKl10Y77O0a" },
    { title: "Gründer-Deal AKYTEX AI (199 €)", url: "https://buy.stripe.com/bJe28t4IjaSacStdNK77O0b" },
    { title: "Gutschein-Link für Freunde (50 %)", url: "https://georgleomaser-bit.github.io/website-test-demo-1/?code=AKYTEXLEO" },
  ],
};

// ---------- Server & Betrieb ----------
const SERVER = {
  name: "Server & Betrieb",
  emoji: "🖥️",
  color: "orange",
  goal: "Den eigenen AKYTEX-Server rund um die Uhr betreiben, mit Clips für alle, Liga, echter KI und sauberer Moderation.",
  sections: ["Einrichtung", "KI", "Betrieb", "Recht"],
  milestones: [
    { title: "Server läuft rund um die Uhr", dueIn: 12 },
    { title: "Aky antwortet mit Claude", dueIn: 16 },
  ],
  tasks: [
    erledigt("Eigenen AKYTEX-Server für Clips bauen", MITTEL, "Einrichtung", { notes: "server/akytex-server.mjs mit Upload, Likes, Kommentaren und Moderation (Commit #13)." }),
    erledigt("Doppelklick-Start mit Cloudflare Tunnel", NIEDRIG, "Einrichtung", { notes: "AKYTEX-starten.bat bzw. .command (Commit #15)." }),
    erledigt("Server-Installation mit einem Befehl", MITTEL, "Einrichtung", { notes: "server/install.sh für Ubuntu/Debian mit Caddy-HTTPS, Firewall, fail2ban und täglichen Backups (Commit #23)." }),
    aufgabe("Mietserver bestellen", HOCH, "Einrichtung", {
      notes: "z. B. Hetzner CX22 mit Ubuntu 24.04 für ca. 4–5 €/Monat. Alternativen: Oracle Cloud „Always Free“ oder ein eigener Rechner mit Cloudflare Tunnel. Derselbe Server trägt auch NOVA und den Sync von Arbeitstaschen.",
      dueIn: 4,
      est: 20,
      milestone: "Server läuft rund um die Uhr",
    }),
    aufgabe("Installationsskript auf dem Server ausführen", HOCH, "Einrichtung", {
      subtasks: ["Domain angeben (ohne Domain: sslip.io-Adresse)", "Anthropic-Schlüssel eingeben (optional)", "Eingeschränkten Stripe-Schlüssel eingeben (optional)"],
      milestone: "Server läuft rund um die Uhr",
    }),
    aufgabe("Domain für den Server festlegen", MITTEL, "Einrichtung", { notes: "z. B. akytex.org über Cloudflare. Eine feste Adresse geht über einen benannten Tunnel oder Caddy." }),
    aufgabe("Arbeitstaschen-Server einrichten (Sync & Erinnerungen)", MITTEL, "Einrichtung", {
      notes: "Läuft neben AKYTEX und NOVA auf demselben Mietserver (taschen/server/install.sh). Danach sind deine Taschen auf iPhone, iPad und Mac gleich – Ende-zu-Ende-verschlüsselt – und Erinnerungen kommen auch bei geschlossener App.",
      subtasks: ["Installationsskript aus taschen/server ausführen", "In Arbeitstaschen unter Einstellungen den Sync einschalten und den Code sichern", "Code auf iPhone, iPad und Mac eingeben", "Mitteilungen auf jedem Gerät erlauben"],
    }),
    aufgabe("Anthropic-API-Konto anlegen und Schlüssel hinterlegen", MITTEL, "KI", {
      notes: "Guthaben aufladen und einen API-Key erstellen. Der Schlüssel liegt nur auf dem Server. Danach antwortet Aky mit Claude.",
      milestone: "Aky antwortet mit Claude",
    }),
    aufgabe("KI-Kostenbremse prüfen", NIEDRIG, "KI", { notes: "AI_DAILY_LIMIT 400 pro Tag gesamt, 60 pro 10 Minuten und Gerät. FREE_AI_DAILY 15, PAID_AI_DAILY 400.", milestone: "Aky antwortet mit Claude" }),
    aufgabe("Moderations-Token sicher aufbewahren", MITTEL, "Betrieb", { notes: "ADMIN_TOKEN braucht mindestens 24 Zeichen, sonst ist die Moderation aus." }),
    aufgabe("Gemeldete Clips täglich prüfen", HOCH, "Betrieb", { notes: "Mit npm run admin reports. Strafbare Inhalte sofort löschen (DSA). Nach 3 Meldungen wird ein Clip automatisch ausgeblendet." }),
    aufgabe("Backups regelmäßig kontrollieren", NIEDRIG, "Betrieb", { notes: "data/db.json und data/videos/. Das Installationsskript sichert täglich und behält 14 Tage." }),
    aufgabe("Hosting-Abschnitt im Datenschutz anpassen", MITTEL, "Recht", { notes: "Sobald klar ist, wo der Server läuft (z. B. Hetzner, Deutschland)." }),
    aufgabe("Mindestalter in die AGB aufnehmen", MITTEL, "Recht", { notes: "Für die junge Zielgruppe üblich 16 Jahre, sonst mit Zustimmung der Eltern." }),
  ],
  notes: [
    {
      title: "Befehle",
      body: "- `akytex-update` holt die neueste Version.\n- `journalctl -u akytex -f` zeigt die Logs.\n- Einstellungen stehen in `/etc/akytex.env`, danach `systemctl restart akytex`.\n- Moderation: `npm run admin reports | hide | restore | delete | ban`",
    },
    {
      title: "Kosten & KI",
      body: "Ein VPS kostet ca. 4–5 €/Monat. Jede KI-Frage kostet ein paar Cent. Standardmodell ist claude-opus-5 (AI_MODEL), der Denk-Aufwand steht auf medium (AI_EFFORT).",
    },
    {
      title: "Eingebaute Sicherheit",
      body: "- Konten sind anonym, gespeichert wird nur ein Hash.\n- Rate-Limits: 5 neue Konten pro Stunde, 10 Uploads pro Tag, 10 Kommentare pro Minute.\n- Videos nur als MP4, WebM oder MOV bis 60 MB.\n- Die Liga läuft über einen gemeinsamen Server-Markt mit Saisons von 4 Wochen.",
    },
  ],
  links: [
    { title: "AKYTEX-Installationsskript", url: "https://raw.githubusercontent.com/georgleomaser-bit/website-test-demo-1/HEAD/server/install.sh" },
    { title: "Node.js", url: "https://nodejs.org" },
    { title: "Anthropic Console", url: "https://console.anthropic.com" },
  ],
};

// ---------- NOVA – KI-Assistent ----------
const NOVA = {
  name: "NOVA – KI-Assistent",
  emoji: "✨",
  color: "green",
  goal: "NOVA als zweites Business von akytex united mit eigenem Server, Claude und Stripe-Abos startklar machen.",
  sections: ["Server", "Bezahlen", "Vor dem Start", "Produkt"],
  milestones: [
    { title: "NOVA-Server live mit Claude", dueIn: 18 },
    { title: "NOVA Plus & Pro buchbar", dueIn: 30 },
    { title: "Öffentlicher Start von NOVA", dueIn: null },
  ],
  tasks: [
    aufgabe("NOVA-Server installieren", HOCH, "Server", {
      notes: "Ein Befehl in der Server-Konsole, z. B. bei Hetzner. Läuft neben AKYTEX. Domain optional (sonst nova.…sslip.io).",
      milestone: "NOVA-Server live mit Claude",
    }),
    aufgabe("Anthropic-Schlüssel hinterlegen", HOCH, "Server", {
      notes: "Den Schlüssel unter console.anthropic.com erstellen und nur beim Installationsskript eingeben.",
      milestone: "NOVA-Server live mit Claude",
    }),
    aufgabe("Ausgabenlimit bei Anthropic setzen", HOCH, "Server", { notes: "Zusätzlich zur Tagesbremse NOVA_DAILY_LIMIT (Standard 500 Anfragen).", est: 10, milestone: "NOVA-Server live mit Claude" }),
    aufgabe("Selbsttest mit dem Pro-Tarif", MITTEL, "Server", {
      notes: "NOVA_OPEN_PLAN=pro in /etc/nova.env eintragen und systemctl restart nova ausführen. Danach die Zeile wieder löschen, sonst zahlt ihr für alle Besucher.",
      milestone: "NOVA-Server live mit Claude",
    }),
    aufgabe("Stripe-Produkte NOVA Plus und NOVA Pro anlegen", MITTEL, "Bezahlen", {
      subtasks: ["NOVA Plus 4,99 €/Monat + Payment Link", "NOVA Pro 9,99 €/Monat + Payment Link", "Rückleitung mit session_id eintragen"],
      milestone: "NOVA Plus & Pro buchbar",
    }),
    aufgabe("Payment Links in die NOVA-Konfiguration eintragen", MITTEL, "Bezahlen", { notes: "STRIPE.links und portal in nova/js/config.js sind noch leer. Das kann Claude übernehmen.", milestone: "NOVA Plus & Pro buchbar" }),
    aufgabe("Eingeschränkten Stripe-Schlüssel für NOVA hinterlegen", MITTEL, "Bezahlen", {
      notes: "Nur Leserechte auf Checkout Sessions, Subscriptions und Payment Links, dann das Installationsskript erneut ausführen. Bis dahin haben alle Nutzer Free.",
      milestone: "NOVA Plus & Pro buchbar",
    }),
    aufgabe("Marke „NOVA“ prüfen", HOCH, "Vor dem Start", {
      notes: "Beim DPMA bzw. EUIPO. „NOVA“ ist ein Arbeitstitel, die Änderung erfolgt nur in BRAND.name (nova/js/config.js).",
      milestone: "Öffentlicher Start von NOVA",
    }),
    aufgabe("Datenschutzerklärung für NOVA schreiben", HOCH, "Vor dem Start", { notes: "Anthropic als Auftragsverarbeiter nennen.", milestone: "Öffentlicher Start von NOVA" }),
    aufgabe("Impressum für NOVA anlegen", HOCH, "Vor dem Start", {
      notes: "Als Anbieter die UG/GmbH von akytex united nutzen, sobald sie eingetragen ist.",
      waiting: "Eintragung der UG/GmbH",
      milestone: "Öffentlicher Start von NOVA",
    }),
    aufgabe("Altersgrenze klären", MITTEL, "Vor dem Start", {
      notes: "Anthropics Nutzungsbedingungen verlangen für Endnutzer in der Regel 18+ oder die Zustimmung der Eltern. Bitte prüfen.",
      milestone: "Öffentlicher Start von NOVA",
    }),
    aufgabe("Anthropic-Richtlinien für Endkunden-Apps prüfen", MITTEL, "Vor dem Start", { milestone: "Öffentlicher Start von NOVA" }),
    erledigt("NOVA-App mit Basis-Skills bauen", MITTEL, "Produkt", { notes: "Wetter, Timer, Erinnerungen, Rechner, Sparziele, Gedächtnis und Sprache laufen in der Vorschau (Commit #31)." }),
    erledigt("Professionelles Design in Hell und Dunkel", NIEDRIG, "Produkt", { notes: "Commit #32." }),
  ],
  notes: [
    {
      title: "Tarife",
      body: "- **Free (0 €):** 5 KI-Fragen/Tag mit Claude Sonnet, Wetter, Timer & Co. unbegrenzt\n- **Plus (4,99 €/Monat):** 60/Tag mit Sonnet, Websuche, Fotos und PDFs\n- **Pro (9,99 €/Monat):** 200/Tag mit Claude Opus 5",
    },
    {
      title: "Kostenrechnung",
      body: "Claude Opus 5 kostet 5 $ pro Million Eingabe- und 25 $ pro Million Ausgabe-Tokens, eine Websuche 1 Cent.\n\n- Normale Frage: ca. 3–5 Cent\n- Mit Websuche: 10–15 Cent\n\nDeshalb bekommt nur Pro Opus. Die Modelle stehen in `/etc/nova.env`.",
    },
    {
      title: "Datenschutz",
      body: "Chats, Gedächtnis, Erinnerungen und Sparziele bleiben auf dem Gerät. Der Server speichert nur ein anonymes Konto, den Tarif und den Tageszähler. Der Anthropic-Schlüssel liegt nur auf dem Server.",
    },
  ],
  links: [
    { title: "NOVA-Vorschau", url: "https://georgleomaser-bit.github.io/website-test-demo-1/nova/" },
    { title: "Anthropic Ausgabenlimit", url: "https://console.anthropic.com/settings/limits" },
    { title: "Anthropic API-Keys", url: "https://console.anthropic.com/settings/keys" },
    { title: "NOVA-Installationsskript", url: "https://raw.githubusercontent.com/georgleomaser-bit/website-test-demo-1/HEAD/nova/server/install.sh" },
  ],
};

// ---------- Export ----------
// Reihenfolge = Reihenfolge der Taschen in der App (das Hauptprodukt zuerst, dann was es zum Start braucht)
export const SEED = { bags: [AKYTEX, FIRMA, ZAHLUNGEN, MARKETING, BROKER, SERVER, NOVA] };
