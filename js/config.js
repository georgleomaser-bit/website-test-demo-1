// AKYTEX Go-Live-Konfiguration: Alles, was für den Echtbetrieb eingetragen werden muss, steht hier.
// Leere Felder = die App bleibt für diesen Teil im Demo- bzw. Testmodus. Anleitung: GO-LIVE.md
export const CONFIG = {
  // Öffentliche Adresse der Seite (für Stripe-Rückleitungen, Sitemap, Teilen-Links)
  siteUrl: "https://georgleomaser-bit.github.io/website-test-demo-1/",

  // Anbieterkennzeichnung (Impressum, AGB, Rechnungen). Pflicht vor dem ersten zahlenden Kunden.
  company: {
    name: "akytex united",
    representative: "Leo Maser, Paul Jazra", // Pflicht: vollständiger Name der verantwortlichen Person(en)
    contentResponsible: "Paul Jazra", // Verantwortlich für den Inhalt nach § 18 Abs. 2 MStV
    street: "Alter Wall 56",
    zipCity: "20457 Hamburg",
    country: "Deutschland",
    email: "acytex@outlook.de",
    phone: "+49 151 10681903",
    register: "", // z. B. "Amtsgericht München, HRB 123456"
    vatId: "", // z. B. "DE123456789"
    supervisory: "", // z. B. "Bundesanstalt für Finanzdienstleistungsaufsicht (BaFin)" bzw. Partner
    privacyContact: "", // Datenschutz-Kontakt
  },

  // Echte Abo-Zahlungen über Stripe Payment Links (je Tarif monatlich und jährlich).
  // Sobald hier Links stehen, gehen die Abo-Buttons automatisch auf die echte Stripe-Bezahlseite.
  stripe: {
    links: {
      "plus-monthly": "https://buy.stripe.com/3cI4gB6Qr1hA6u5gZW77O00",
      "plus-yearly": "https://buy.stripe.com/cNifZj8Yze4mf0B9xu77O01",
      "pro-monthly": "https://buy.stripe.com/cNi9AV2Ab3pI8Cd39677O02",
      "pro-yearly": "https://buy.stripe.com/5kQdRbgr1f8q2dPeRO77O03",
      "elite-monthly": "https://buy.stripe.com/6oU9AVa2D9O67y910Y77O04",
      "elite-yearly": "https://buy.stripe.com/14A00l7UvbWe19L5he77O05",
      "ai-monthly": "https://buy.stripe.com/cNifZjb6Hgcu5q16li77O06",
      "ai-yearly": "https://buy.stripe.com/7sYfZjfmXf8q2dP39677O07",
      "aiprem-monthly": "https://buy.stripe.com/5kQ4gB1w72lEbOp5he77O08",
      "aiprem-yearly": "https://buy.stripe.com/9B6aEZ6Qr1hAbOp7pm77O09",
      "ultra-monthly": "https://buy.stripe.com/7sYcN7dePgcu4lX39677O0c",
      "ultra-yearly": "https://buy.stripe.com/00w4gB7Uv3pI05HfVS77O0d",
    },
    portal: "https://billing.stripe.com/p/login/3cI4gB6Qr1hA6u5gZW77O00", // Stripe-Kundenportal (Zahlungsmethode ändern, kündigen, Rechnungen)
    // Gründer-Deal: Einmalzahlung für 12 Monate, kein Abo, je 100 Plätze (Limit bei Stripe). Leere Links blenden den Deal aus.
    founder: {
      pro: { link: "https://buy.stripe.com/cNidRbeiT1hAaKl10Y77O0a", price: 49 },
      ai: { link: "https://buy.stripe.com/bJe28t4IjaSacStdNK77O0b", price: 199 },
      spots: 100,
    },
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
  // Ein Impressum braucht immer eine verantwortliche Person bzw. Firma mit Rechtsform, Anschrift und Kontakt
  legal: !!(CONFIG.company.name && CONFIG.company.representative && CONFIG.company.street && CONFIG.company.zipCity && CONFIG.company.email && CONFIG.company.phone),
};
// Echtgeld-Betrieb nur, wenn Handel UND echte Kurse angeschlossen sind
LIVE.money = LIVE.trading && LIVE.data;
