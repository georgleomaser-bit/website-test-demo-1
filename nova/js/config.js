// NOVA – Konfiguration an einer Stelle: Marke, Tarife, Zahlungslinks.
// Wird von der App UND vom Server gelesen (reines Modul ohne Browser-Abhängigkeiten).
export const BRAND = {
  name: "NOVA", // Arbeitstitel – vor dem Start Markenrecht prüfen (DPMA/EUIPO), dann nur hier ändern
  tagline: "Dein KI-Assistent, der mit dir spricht.",
  company: "akytex united",
  email: "acytex@outlook.de",
};

// Tarife: günstig für viele statt teuer für wenige
export const PLANS = [
  { id: "free", name: "Free", price: 0, ai: 5, search: false, features: ["5 KI-Fragen am Tag (Claude Sonnet)", "Wetter, Timer, Rechner, Sparziele – unbegrenzt", "Sprechen & Zuhören"] },
  { id: "plus", name: "Plus", price: 4.99, ai: 60, search: true, features: ["60 KI-Fragen am Tag (Claude Sonnet)", "Websuche & Webseiten lesen, mit Quellen", "Fotos und PDFs verstehen", "Chats & Gedächtnis ohne Grenze"] },
  { id: "pro", name: "Pro", price: 9.99, ai: 200, search: true, features: ["200 KI-Fragen am Tag", "Das stärkste Modell: Claude Opus", "Alles aus Plus", "Vorrang bei neuen Funktionen"] },
];
export const planById = (id) => PLANS.find((p) => p.id === id) || PLANS[0];

// Stripe Payment Links (je Tarif). Erfolgs-URL in Stripe: https://DEINE-NOVA-ADRESSE/?checkout=success&session_id={CHECKOUT_SESSION_ID}
// Leer = Kaufen-Knopf zeigt „bald verfügbar“.
export const STRIPE = {
  links: {
    "plus-monthly": "",
    "pro-monthly": "",
  },
  portal: "",
};
