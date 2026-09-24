// AKYTEX Go-Live-Konfiguration: Alles, was für den Echtbetrieb eingetragen werden muss, steht hier.
// Leere Felder = die App bleibt für diesen Teil im Demo- bzw. Testmodus. Anleitung: GO-LIVE.md
export const CONFIG = {
  // Öffentliche Adresse der Seite (für Stripe-Rückleitungen, Sitemap, Teilen-Links)
  siteUrl: "https://georgleomaser-bit.github.io/website-test-demo-1/",

  // Anbieterkennzeichnung (Impressum, AGB, Rechnungen). Pflicht vor dem ersten zahlenden Kunden.
  company: {
    name: "", // z. B. "AKYTEX GmbH"
    representative: "", // Geschäftsführung
    street: "",
    zipCity: "",
    country: "Deutschland",
    email: "",
    phone: "",
    register: "", // z. B. "Amtsgericht München, HRB 123456"
    vatId: "", // z. B. "DE123456789"
    supervisory: "", // z. B. "Bundesanstalt für Finanzdienstleistungsaufsicht (BaFin)" bzw. Partner
    privacyContact: "", // Datenschutz-Kontakt
  },

  // Echte Abo-Zahlungen über Stripe Payment Links (je Tarif monatlich und jährlich).
  // Sobald hier Links stehen, gehen die Abo-Buttons automatisch auf die echte Stripe-Bezahlseite.
  stripe: {
    links: {
      "plus-monthly": "",
      "plus-yearly": "",
      "pro-monthly": "",
      "pro-yearly": "",
      "elite-monthly": "",
      "elite-yearly": "",
      "ai-monthly": "",
      "ai-yearly": "",
      "aiprem-monthly": "",
      "aiprem-yearly": "",
    },
    portal: "", // Stripe-Kundenportal (Zahlungsmethode ändern, kündigen, Rechnungen)
  },

  // Echter Handel über den Server des lizenzierten Broker-Partners (API siehe GO-LIVE.md).
  // Leer = Handel mit virtuellem Geld.
  trading: {
    apiBase: "", // z. B. "https://api.akytex.de"
    partnerName: "", // wird im Depot und in den Rechtstexten genannt
  },

  // Echte Kurse (lizenzierter Datenanbieter, über deinen Server als Server-Sent Events).
  // Leer = simulierte Kurse.
  marketData: {
    streamUrl: "", // z. B. "https://api.akytex.de/stream" (Nachrichten: {"s":"SAP","p":241.3,"v":120,"t":1727170000000})
    historyUrl: "", // z. B. "https://api.akytex.de/history" (?symbol=SAP → {"m1":[…], "days":[…]})
  },
};

const filled = (o) => Object.values(o).some(Boolean);
export const LIVE = {
  payments: filled(CONFIG.stripe.links),
  trading: !!CONFIG.trading.apiBase,
  data: !!(CONFIG.marketData.streamUrl && CONFIG.marketData.historyUrl),
  legal: !!(CONFIG.company.name && CONFIG.company.street && CONFIG.company.email),
};
// Echtgeld-Betrieb nur, wenn Handel UND echte Kurse angeschlossen sind
LIVE.money = LIVE.trading && LIVE.data;
