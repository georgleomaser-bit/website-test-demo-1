// Käufe serverseitig prüfen: Nur Stripe entscheidet, welcher Tarif aktiv ist – nicht der Link, mit dem jemand
// von der Bezahlseite zurückkommt, und nicht der Browser.
//
//   STRIPE_SECRET_KEY  Eingeschränkter Schlüssel (rk_live_…) mit nur Leserechten auf
//                      „Checkout Sessions“, „Subscriptions“ und „Payment Links“ (Stripe → Entwickler → API-Schlüssel)
import { CONFIG } from "../js/config.js";

const KEY = process.env.STRIPE_SECRET_KEY || "";
const DAY = 86400000;
const ACTIVE = new Set(["active", "trialing"]);
const MAX_MOVES = 3; // so oft darf ein Kauf auf ein neues Konto (neues Gerät) umziehen
export const billingOn = () => /^(rk|sk)_(live|test)_[A-Za-z0-9]{10,}$/.test(KEY);

// Payment-Link-Adresse → Tarif (aus js/config.js, damit Website und Server dieselbe Liste nutzen)
const LINKS = new Map();
for (const [k, url] of Object.entries(CONFIG.stripe?.links || {})) {
  const m = /^([a-z]+)-(monthly|yearly)$/.exec(k);
  if (m && url) LINKS.set(url, { plan: m[1], billing: m[2] });
}
for (const [plan, f] of Object.entries(CONFIG.stripe?.founder || {})) if (f?.link) LINKS.set(f.link, { plan, billing: "founder" });

const fail = (status, msg) => Object.assign(new Error(msg), { status });
async function stripe(path) {
  let r;
  try {
    r = await fetch("https://api.stripe.com/v1/" + path, { headers: { Authorization: "Bearer " + KEY }, signal: AbortSignal.timeout(15000) });
  } catch (_) {
    throw fail(502, "Stripe ist gerade nicht erreichbar. Bitte gleich noch einmal versuchen.");
  }
  const j = await r.json().catch(() => ({}));
  if (r.status === 404) throw fail(404, "Diesen Kauf gibt es bei Stripe nicht.");
  if (!r.ok) {
    console.error("Stripe", r.status, j.error?.message || "");
    throw fail(502, "Der Kauf konnte gerade nicht geprüft werden.");
  }
  return j;
}
// Ende der bezahlten Periode (neuere Stripe-Versionen führen es pro Abo-Position)
const periodEnd = (sub) => (sub?.current_period_end || sub?.items?.data?.[0]?.current_period_end || 0) * 1000;

export function planOf(user) {
  const p = user?.plan;
  if (!p) return "free";
  // Abos: bis zu 3 Tage Kulanz, falls Stripe bei der Verlängerung kurz nicht erreichbar war
  return Date.now() < p.until + (p.sub ? 3 * DAY : 0) ? p.id : "free";
}
export const billingView = (user) => {
  const plan = planOf(user);
  return { enabled: billingOn(), plan, billing: plan === "free" ? null : user.plan.billing, until: plan === "free" ? null : user.plan.until };
};

// Rückkehr von Stripe: Kaufnummer (Checkout Session) prüfen und an das Konto binden
export async function verifyCheckout(user, sessionId, purchases, users) {
  if (!/^cs_(live|test)_[A-Za-z0-9]{10,200}$/.test(sessionId || "")) throw fail(400, "Ungültige Kaufnummer.");
  const bound = purchases[sessionId];
  if (bound && bound.user !== user.id && bound.moves >= MAX_MOVES) throw fail(409, "Dieser Kauf ist schon mit einem anderen Konto verknüpft. Schreib uns, wir helfen dir.");
  const s = await stripe(`checkout/sessions/${encodeURIComponent(sessionId)}?expand[]=payment_link&expand[]=subscription`);
  if (s.status !== "complete" || !["paid", "no_payment_required"].includes(s.payment_status)) throw fail(402, "Die Zahlung ist noch nicht abgeschlossen.");
  const product = LINKS.get(s.payment_link?.url || "");
  if (!product) throw fail(400, "Dieses Produkt kennt AKYTEX nicht.");
  let until;
  let sub = null;
  if (product.billing === "founder") until = s.created * 1000 + 365 * DAY;
  else {
    sub = s.subscription;
    if (!sub || typeof sub !== "object" || !ACTIVE.has(sub.status)) throw fail(402, "Das Abo ist nicht (mehr) aktiv.");
    until = periodEnd(sub) || Date.now() + DAY;
  }
  if (Date.now() >= until) throw fail(402, "Dieser Kauf ist abgelaufen.");
  // Umzug auf ein neues Gerät/Konto: altes Konto verliert den Tarif – Teilen der Kaufnummer lohnt sich nicht
  if (bound && bound.user !== user.id) {
    const old = users[bound.user];
    if (old?.plan?.session === sessionId) old.plan = null;
  }
  purchases[sessionId] = { user: user.id, moves: bound ? bound.moves + (bound.user !== user.id ? 1 : 0) : 0 };
  user.plan = { id: product.plan, billing: product.billing, until, sub: sub?.id || null, session: sessionId, checked: Date.now() };
  return billingView(user);
}

// Abo regelmäßig bei Stripe nachprüfen (Verlängerung, Kündigung, Rückbuchung). true = Konto geändert.
export async function refreshPlan(user) {
  const p = user?.plan;
  if (!p || !billingOn()) return false;
  const now = Date.now();
  if (now < p.until && now - p.checked < 12 * 3600000) return false;
  if (!p.sub) {
    if (now >= p.until) user.plan = null;
    else p.checked = now;
    return true;
  }
  try {
    const sub = await stripe(`subscriptions/${encodeURIComponent(p.sub)}`);
    if (ACTIVE.has(sub.status)) Object.assign(p, { until: Math.max(periodEnd(sub), now + 3600000), checked: now });
    else user.plan = null;
  } catch (e) {
    if (e.status === 404) user.plan = null;
    else p.checked = now - 11 * 3600000; // Stripe nicht erreichbar: in einer Stunde erneut
  }
  return true;
}
