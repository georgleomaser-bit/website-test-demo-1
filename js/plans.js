// Tarife von AKTEX – das Geschäftsmodell: Abos + Ordergebühren
export const PLANS = [
  {
    id: "free",
    name: "Free",
    price: 0,
    fee: 1,
    tagline: "Zum Einsteigen",
    limits: { indicators: 3, alerts: 3, aiDetails: false, copy: false },
    features: ["Echtzeit-Charts & Watchlist", "1 € pro Order", "3 Indikatoren gleichzeitig", "3 aktive Preisalarme", "AKTEX AI – Gesamtbewertung", "Community-Ideen lesen & teilen"],
  },
  {
    id: "pro",
    name: "Pro",
    price: 9.99,
    fee: 0,
    tagline: "Für aktive Trader",
    popular: true,
    limits: { indicators: 8, alerts: 25, aiDetails: true, copy: false },
    features: ["Alles aus Free", "0 € Ordergebühr", "8 Indikatoren gleichzeitig", "25 Preisalarme", "AKTEX AI – alle Signale, Marken & Trade-Setups", "Werbefrei & Prioritäts-Support"],
  },
  {
    id: "elite",
    name: "Elite",
    price: 24.99,
    fee: 0,
    tagline: "Für Profis & Copy-Trading",
    limits: { indicators: 99, alerts: 999, aiDetails: true, copy: true },
    features: ["Alles aus Pro", "Copy-Trading der Top-Trader", "Unbegrenzte Indikatoren & Alarme", "Profi-Datenpakete (Level 2)", "Persönlicher Account-Manager", "Frühzugang zu neuen Features"],
  },
];

export const planById = (id) => PLANS.find((p) => p.id === id) || PLANS[0];
