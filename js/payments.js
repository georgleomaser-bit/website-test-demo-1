// AKYTEX Bezahlsystem: Checkout, Abo-Verwaltung, Rechnungen.
// Standard ist der TESTMODUS: Es fließt kein Geld, und es werden nur Testkarten/Test-IBANs angenommen,
// damit niemand echte Zahlungsdaten eingibt. Für echte Zahlungen Stripe-Zahlungslinks eintragen (siehe PAYMENTS.md).
import { planById, planPrice, ADDONS } from "./plans.js";
import { CONFIG, LIVE } from "./config.js";

export const PAYMENT_CONFIG = {
  // "live", sobald in js/config.js Stripe-Links UND die Firmendaten fürs Impressum eingetragen sind –
  // ohne Anbieterkennzeichnung darf in Deutschland nichts verkauft werden
  mode: LIVE.payments && LIVE.legal ? "live" : "test",
  vatRate: 0.19,
  trialDays: 14,
  stripeLinks: CONFIG.stripe.links,
  stripePortal: CONFIG.stripe.portal,
  promos: {
    AKYTEXLEO: { pct: 0.5, label: "50 % Rabatt dauerhaft" },
    AKYTEX20: { pct: 0.2, label: "20 % Rabatt im ersten Jahr" },
    START: { freeMonths: 1, label: "1 zusätzlicher Monat gratis" },
    FOUNDER: { pct: 0.5, label: "50 % Gründer-Rabatt (Demo)" },
  },
};

// Ein- und Auszahlungen aufs Depot (wie bei Neobrokern). Im Demo- und Testmodus wird kein echtes Geld bewegt.
// Echte Einzahlungen brauchen einen lizenzierten Partner (Bank bzw. Wertpapierinstitut), siehe PAYMENTS.md.
export const FUNDING = {
  min: 1,
  max: 100000,
  instantDailyLimit: 5000, // sofort verfügbare Einzahlungen pro Tag (Karte, Wallets, PayPal)
  // Bewusst ungültige IBAN, damit niemand echtes Geld überweist
  demoIban: "DE00 AKYT EX00 DEMO 0000 00",
  in: [
    { id: "apple", name: "Apple Pay", icon: "Pay", eta: "sofort", instant: true, wallet: true },
    { id: "google", name: "Google Pay", icon: "G", eta: "sofort", instant: true, wallet: true },
    { id: "card", name: "Debit- oder Kreditkarte", icon: "💳", eta: "sofort", instant: true },
    { id: "instant", name: "Echtzeitüberweisung", icon: "⚡", eta: "in Sekunden", instant: true, wallet: true },
    { id: "paypal", name: "PayPal", icon: "P", eta: "sofort", instant: true, wallet: true },
    { id: "sepa", name: "SEPA-Lastschrift", icon: "🏦", eta: "sofort verfügbar · Einzug in 1–3 Tagen", instant: true },
    { id: "transfer", name: "Überweisung auf deine IBAN", icon: "🧾", eta: "1 Werktag · ohne Limit" },
  ],
  out: [
    { id: "instant", name: "Echtzeit-Auszahlung", icon: "⚡", eta: "in Sekunden auf dein Referenzkonto" },
    { id: "standard", name: "Standard-Auszahlung", icon: "🏦", eta: "1–2 Werktage" },
  ],
};

// IBAN-Prüfsumme (ISO 13616, Modulo 97)
export function ibanValid(iban) {
  const s = iban.replace(/\s/g, "").toUpperCase();
  if (!/^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/.test(s)) return false;
  const r = (s.slice(4) + s.slice(0, 4)).replace(/[A-Z]/g, (c) => c.charCodeAt(0) - 55);
  let m = 0;
  for (const d of r) m = (m * 10 + +d) % 97;
  return m === 1;
}

// Offizielle Testnummern (Stripe-Konvention) – echte Karten werden abgelehnt
export const TEST_CARDS = {
  "4242424242424242": { brand: "visa", result: "ok" },
  "5555555555554444": { brand: "mastercard", result: "ok" },
  "378282246310005": { brand: "amex", result: "ok" },
  "4000002500003155": { brand: "visa", result: "3ds" },
  "4000000000000002": { brand: "visa", result: "declined" },
  "4000000000009995": { brand: "visa", result: "funds" },
};
export const TEST_IBAN = "DE89370400440532013000";

export function cardBrand(num) {
  const n = num.replace(/\D/g, "");
  if (/^4/.test(n)) return "visa";
  if (/^(5[1-5]|2[2-7])/.test(n)) return "mastercard";
  if (/^3[47]/.test(n)) return "amex";
  return "";
}
export function luhn(num) {
  const n = num.replace(/\D/g, "");
  let sum = 0;
  for (let i = 0; i < n.length; i++) {
    let d = +n[n.length - 1 - i];
    if (i % 2) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  return n.length >= 13 && sum % 10 === 0;
}
export function formatCard(num) {
  const n = num.replace(/\D/g, "").slice(0, 16);
  return cardBrand(n) === "amex" ? n.replace(/^(\d{0,4})(\d{0,6})(\d{0,5}).*/, (_, a, b, c) => [a, b, c].filter(Boolean).join(" ")) : n.replace(/(\d{4})(?=\d)/g, "$1 ");
}

// Preisberechnung (alle Preise inkl. MwSt.)
export function quote({ planId, billing, addons = [], promo = null }) {
  const p = planById(planId);
  const months = billing === "yearly" ? 12 : 1;
  const lines = [{ label: `AKYTEX ${p.name} (${billing === "yearly" ? "jährlich" : "monatlich"})`, amount: planPrice(p, billing) * months }];
  for (const id of addons) {
    const a = ADDONS.find((x) => x.id === id);
    if (a && !a.includedIn.includes(p.id)) lines.push({ label: `Add-on ${a.name}`, amount: a.price * months });
  }
  const subtotal = lines.reduce((s, l) => s + l.amount, 0);
  const pr = promo && PAYMENT_CONFIG.promos[promo];
  let discount = 0;
  if (pr?.pct) discount = subtotal * pr.pct;
  if (pr?.freeMonths) discount = (subtotal / months) * Math.min(months, pr.freeMonths);
  const total = Math.max(0, subtotal - discount);
  const vat = total - total / (1 + PAYMENT_CONFIG.vatRate);
  const perMonth = total / months;
  return { plan: p, billing, months, lines, subtotal, discount, promo: pr ? { code: promo, ...pr } : null, total, vat, net: total - vat, perMonth, renewal: (subtotal / months) * months };
}

export const stripeLinkFor = (planId, billing) => PAYMENT_CONFIG.stripeLinks[`${planId}-${billing}`] || "";

// Konto, Profil, Abo und Rechnungen (lokal im Browser)
const KEY = "akytex-v2-account-profile";
export class AccountStore {
  constructor() {
    this.state = this.load();
  }
  load() {
    const base = { profile: null, sub: null, invoices: [], method: null, prefs: { push: true, email: true, ai: true, fills: true, twofa: false, passkey: false }, onboarding: null };
    try {
      const s = JSON.parse(localStorage.getItem(KEY) || "{}");
      return { ...base, ...s, prefs: { ...base.prefs, ...(s.prefs || {}) } };
    } catch (_) {
      return base;
    }
  }
  save() {
    try {
      localStorage.setItem(KEY, JSON.stringify(this.state));
    } catch (_) {
      /* ignorieren */
    }
  }
  get signedIn() {
    return !!this.state.profile;
  }
  setProfile(p) {
    this.state.profile = { since: Date.now(), ...this.state.profile, ...p };
    this.save();
  }
  signOut() {
    this.state.profile = null;
    this.save();
  }
  // Abo nach erfolgreichem (Test-)Checkout anlegen
  subscribe(q, method) {
    const now = Date.now();
    const trialEnds = now + PAYMENT_CONFIG.trialDays * 86400000;
    const renews = trialEnds;
    this.state.sub = { plan: q.plan.id, billing: q.billing, status: "trial", started: now, trialEnds, renews, promo: q.promo?.code || null, perMonth: q.perMonth, total: q.total, cancelAt: null };
    this.state.method = method;
    this.addInvoice({ date: now, lines: [...q.lines.map((l) => ({ ...l })), ...(q.discount ? [{ label: `Rabatt ${q.promo.code}`, amount: -q.discount }] : []), { label: `Testphase (${PAYMENT_CONFIG.trialDays} Tage)`, amount: -q.total }], total: 0, note: `Erste Abbuchung am ${new Date(trialEnds).toLocaleDateString("de-DE")}: ${q.total.toLocaleString("de-DE", { style: "currency", currency: "EUR" })}` });
    this.save();
  }
  addInvoice({ date, lines, total, note }) {
    const no = `AKX-${new Date(date).getFullYear()}-${String(this.state.invoices.length + 1).padStart(5, "0")}`;
    const vat = total - total / (1 + PAYMENT_CONFIG.vatRate);
    this.state.invoices.unshift({ no, date, lines, total, vat, net: total - vat, note, status: total > 0 ? "bezahlt (Test)" : "0,00 € – Testphase" });
  }
  cancel(reason) {
    if (!this.state.sub) return null;
    this.state.sub.status = "canceled";
    this.state.sub.cancelAt = this.state.sub.renews;
    this.state.sub.reason = reason;
    this.save();
    return this.state.sub;
  }
  resume() {
    if (!this.state.sub) return;
    this.state.sub.status = Date.now() < this.state.sub.trialEnds ? "trial" : "active";
    this.state.sub.cancelAt = null;
    this.save();
  }
}
