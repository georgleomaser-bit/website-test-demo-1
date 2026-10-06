// Arbeitstaschen – Mail und Kalender: Anmeldung bei Google (Gmail, Google Kalender) und Microsoft (Outlook, Hotmail, Microsoft 365)
// Alles läuft im Browser: Die Anmeldedaten bleiben auf diesem Gerät, kein Server liest mit. Nur lesen, nie senden oder löschen.
import { CONNECT } from "./config.js";

const STORE_KEY = "taschen-connect"; // verbundene Konten (pro Gerät, wird nicht synchronisiert)
const PENDING_KEY = "taschen-connect-pending"; // laufende Anmeldung (state, PKCE-Schlüssel)
const MAX_AGE = 5 * 60000; // Termine und Mails höchstens alle 5 Minuten neu laden
const MAIL_MAX = 8;

export const PROVIDERS = {
  google: {
    id: "google",
    name: "Google",
    sub: "Gmail und Google Kalender",
    auth: "https://accounts.google.com/o/oauth2/v2/auth",
    revoke: "https://oauth2.googleapis.com/revoke",
    scopes: ["openid", "email", "https://www.googleapis.com/auth/gmail.readonly", "https://www.googleapis.com/auth/calendar.events.readonly"],
  },
  microsoft: {
    id: "microsoft",
    name: "Microsoft",
    sub: "Outlook, Hotmail und Microsoft 365",
    auth: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
    token: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
    scopes: ["openid", "profile", "offline_access", "User.Read", "Mail.Read", "Calendars.Read"],
  },
};

export const clientId = (p) => String((CONNECT && CONNECT[p]) || "").trim();
export const available = (p) => !!PROVIDERS[p] && !!clientId(p);
export const anyAvailable = () => Object.keys(PROVIDERS).some(available);

// ---------- Speicher (localStorage, mit Rückfall auf den Arbeitsspeicher) ----------
const mem = {};
function lsGet(k) {
  try {
    const v = localStorage.getItem(k);
    return v ? JSON.parse(v) : mem[k] ?? null;
  } catch (_) {
    return mem[k] ?? null;
  }
}
function lsSet(k, v) {
  mem[k] = v;
  try {
    if (v == null) localStorage.removeItem(k);
    else localStorage.setItem(k, JSON.stringify(v));
  } catch (_) {
    /* privates Surfen – bleibt im Arbeitsspeicher */
  }
}

const accountsRaw = () => lsGet(STORE_KEY) || {};
const saveAccount = (p, acc) => lsSet(STORE_KEY, { ...accountsRaw(), [p]: acc });

// Öffentliche Sicht: ohne Schlüssel
export function accounts() {
  const all = accountsRaw();
  return Object.keys(PROVIDERS)
    .filter((p) => all[p])
    .map((p) => ({ provider: p, name: PROVIDERS[p].name, email: all[p].email || "", needsLogin: !usable(all[p]) && !all[p].refresh, connected: all[p].connected || 0 }));
}
export const connected = (p) => !!accountsRaw()[p];
const usable = (acc, now = Date.now()) => !!(acc && acc.token && acc.exp && acc.exp - 60000 > now);

// ---------- PKCE ----------
function b64url(bytes) {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
export function randomString(n = 32) {
  const a = new Uint8Array(n);
  crypto.getRandomValues(a);
  return b64url(a);
}
export async function challenge(verifier) {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  return b64url(new Uint8Array(hash));
}

// ---------- Anmelde-Adresse ----------
export const redirectUri = (href = location.href) => {
  const u = new URL(href);
  return u.origin + u.pathname;
};

export function authUrl(p, { clientId: cid, redirect, state, codeChallenge = "", loginHint = "" }) {
  const P = PROVIDERS[p];
  const q = new URLSearchParams({ client_id: cid, redirect_uri: redirect, scope: P.scopes.join(" "), state });
  if (p === "google") {
    // Google erlaubt reinen Web-Apps ohne Server nur diesen Weg; der Zugang gilt eine Stunde, danach kurz neu anmelden
    q.set("response_type", "token");
    q.set("include_granted_scopes", "true");
    q.set("prompt", loginHint ? "none" : "select_account");
  } else {
    q.set("response_type", "code");
    q.set("response_mode", "query");
    q.set("code_challenge", codeChallenge);
    q.set("code_challenge_method", "S256");
    q.set("prompt", loginHint ? "none" : "select_account");
  }
  if (loginHint) q.set("login_hint", loginHint);
  return `${P.auth}?${q}`;
}

export async function start(p, { silent = false } = {}) {
  if (!available(p)) throw new Error(`${PROVIDERS[p]?.name || p} ist in dieser App noch nicht eingerichtet.`);
  const state = randomString(16);
  const verifier = p === "microsoft" ? randomString(48) : "";
  const redirect = redirectUri();
  const hint = silent ? accountsRaw()[p]?.email || "" : "";
  lsSet(PENDING_KEY, { p, state, verifier, redirect, hash: location.hash || "", at: Date.now() });
  const url = authUrl(p, { clientId: clientId(p), redirect, state, codeChallenge: verifier ? await challenge(verifier) : "", loginHint: hint });
  location.assign(url);
}

// Antwort nach der Rückkehr lesen: Google schickt „#access_token=…“, Microsoft „?code=…“
export function parseReturn(href) {
  const u = new URL(href);
  const h = new URLSearchParams(u.hash.replace(/^#/, ""));
  const q = u.searchParams;
  if (h.get("access_token") || (h.get("error") && h.get("state"))) {
    return { kind: "token", state: h.get("state") || "", token: h.get("access_token") || "", expiresIn: Number(h.get("expires_in")) || 3600, error: h.get("error") || "" };
  }
  if ((q.get("code") || q.get("error")) && q.get("state")) {
    return { kind: "code", state: q.get("state"), code: q.get("code") || "", error: q.get("error") || "", errorText: q.get("error_description") || "" };
  }
  return null;
}

// Beim Laden des Moduls (vor dem Start der App) einsammeln und die Adresse aufräumen, damit der Router nichts davon sieht
let returned = null;
if (typeof location !== "undefined" && typeof history !== "undefined") {
  try {
    const r = parseReturn(location.href);
    if (r) {
      returned = r;
      const pend = lsGet(PENDING_KEY);
      history.replaceState(null, "", location.pathname + (pend?.hash && !/access_token|state=/.test(pend.hash) ? pend.hash : "#einstellungen/konten"));
    }
  } catch (_) {
    /* keine Rückkehr */
  }
}

// Nach dem Start aufrufen: schließt eine Anmeldung ab. Ergebnis: null | { ok, provider, email, error }
export async function finishReturn() {
  const r = returned;
  returned = null;
  if (!r) return null;
  const pend = lsGet(PENDING_KEY);
  lsSet(PENDING_KEY, null);
  if (!pend || pend.state !== r.state) return { ok: false, error: "Die Anmeldung ist abgelaufen. Bitte versuch es noch einmal." };
  const p = pend.p;
  const name = PROVIDERS[p]?.name || p;
  if (r.error) {
    // stille Neuanmeldung klappte nicht: einmal mit Kontoauswahl versuchen lassen
    const quiet = ["login_required", "interaction_required", "consent_required"].includes(r.error);
    return { ok: false, provider: p, error: quiet ? `Bitte melde dich bei ${name} noch einmal an.` : r.error === "access_denied" ? "Du hast den Zugriff nicht erlaubt." : `${name} hat die Anmeldung abgelehnt.`, retry: quiet };
  }
  try {
    let acc;
    if (r.kind === "token") acc = { token: r.token, exp: Date.now() + r.expiresIn * 1000 };
    else acc = await tokenRequest({ grant_type: "authorization_code", code: r.code, redirect_uri: pend.redirect, code_verifier: pend.verifier });
    const prev = accountsRaw()[p] || {};
    acc.email = (await whoAmI(p, acc.token)) || prev.email || "";
    acc.connected = prev.connected || Date.now();
    saveAccount(p, acc);
    reset();
    return { ok: true, provider: p, email: acc.email };
  } catch (e) {
    return { ok: false, provider: p, error: `Anmeldung bei ${name} fehlgeschlagen: ${e.message || e}` };
  }
}

async function tokenRequest(params) {
  const body = new URLSearchParams({ client_id: clientId("microsoft"), scope: PROVIDERS.microsoft.scopes.join(" "), ...params });
  const res = await fetch(PROVIDERS.microsoft.token, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body });
  const j = await res.json().catch(() => ({}));
  if (!res.ok || !j.access_token) throw new Error(j.error_description ? String(j.error_description).split("\r\n")[0] : `Fehler ${res.status}`);
  return { token: j.access_token, refresh: j.refresh_token || params.refresh_token || "", exp: Date.now() + (Number(j.expires_in) || 3600) * 1000 };
}

async function whoAmI(p, token) {
  try {
    if (p === "google") return (await api(token, "https://openidconnect.googleapis.com/v1/userinfo")).email || "";
    const me = await api(token, "https://graph.microsoft.com/v1.0/me?$select=mail,userPrincipalName");
    return me.mail || me.userPrincipalName || "";
  } catch (_) {
    return "";
  }
}

export function disconnect(p) {
  const all = accountsRaw();
  const acc = all[p];
  delete all[p];
  lsSet(STORE_KEY, all);
  if (p === "google" && acc?.token) fetch(`${PROVIDERS.google.revoke}?token=${encodeURIComponent(acc.token)}`, { method: "POST", mode: "no-cors" }).catch(() => {});
  reset();
}

// ---------- Zugriff ----------
class NeedsLogin extends Error {}

async function tokenFor(p) {
  const acc = accountsRaw()[p];
  if (!acc) throw new NeedsLogin(p);
  if (usable(acc)) return acc.token;
  if (p === "microsoft" && acc.refresh) {
    try {
      const fresh = await tokenRequest({ grant_type: "refresh_token", refresh_token: acc.refresh });
      saveAccount(p, { ...acc, ...fresh });
      return fresh.token;
    } catch (_) {
      saveAccount(p, { ...acc, token: "", refresh: "", exp: 0 });
    }
  }
  throw new NeedsLogin(p);
}

async function api(token, url, headers = {}) {
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}`, ...headers } });
  if (res.status === 401) throw new NeedsLogin();
  if (!res.ok) throw new Error(`Fehler ${res.status}`);
  return res.json();
}

// ---------- Umwandeln in ein gemeinsames Format (rein, getestet) ----------
const dayBounds = (now) => {
  const a = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const b = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
  return [a, b];
};
const localISO = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

export function googleEvent(e) {
  if (!e || e.status === "cancelled") return null;
  const allDay = !!e.start?.date;
  const start = allDay ? new Date(e.start.date + "T00:00:00") : new Date(e.start?.dateTime);
  const end = allDay ? new Date((e.end?.date || e.start.date) + "T00:00:00") : new Date(e.end?.dateTime || e.start?.dateTime);
  if (isNaN(start)) return null;
  return { id: "g:" + e.id, provider: "google", title: e.summary || "(ohne Titel)", start: +start, end: +end, allDay, where: e.location || "", link: e.htmlLink || "" };
}

export function graphEvent(e) {
  if (!e || e.isCancelled) return null;
  // mit „Prefer: outlook.timezone="UTC"“ kommen Zeiten ohne Zonenangabe in UTC
  const utc = (s) => new Date(String(s || "").replace(/(\.\d{3})\d*$/, "$1").replace(/Z?$/, "Z"));
  const allDay = !!e.isAllDay;
  let start = utc(e.start?.dateTime), end = utc(e.end?.dateTime);
  if (allDay) {
    // ganztägig: Datum gilt als Kalendertag, nicht als UTC-Zeitpunkt
    start = new Date(String(e.start?.dateTime).slice(0, 10) + "T00:00:00");
    end = new Date(String(e.end?.dateTime).slice(0, 10) + "T00:00:00");
  }
  if (isNaN(start)) return null;
  return { id: "m:" + e.id, provider: "microsoft", title: e.subject || "(ohne Titel)", start: +start, end: +end, allDay, where: e.location?.displayName || "", link: e.webLink || "" };
}

const header = (m, name) => (m.payload?.headers || []).find((h) => String(h.name).toLowerCase() === name)?.value || "";
// „Max Muster <max@example.com>“ → „Max Muster“
export function senderName(s) {
  const t = String(s || "").trim();
  const m = t.match(/^"?([^"<]*?)"?\s*<([^>]+)>$/);
  if (m) return m[1].trim() || m[2].trim();
  return t;
}

export function gmailMessage(m, email = "") {
  if (!m || !m.id) return null;
  const when = Number(m.internalDate) || Date.parse(header(m, "date")) || 0;
  return {
    id: "g:" + m.id,
    provider: "google",
    subject: header(m, "subject") || "(kein Betreff)",
    from: senderName(header(m, "from")),
    date: when,
    preview: decodeEntities(m.snippet || ""),
    link: `https://mail.google.com/mail/${email ? `?authuser=${encodeURIComponent(email)}` : "u/0/"}#all/${m.id}`,
  };
}

export function graphMessage(m) {
  if (!m || !m.id) return null;
  return {
    id: "m:" + m.id,
    provider: "microsoft",
    subject: m.subject || "(kein Betreff)",
    from: m.from?.emailAddress?.name || m.from?.emailAddress?.address || "",
    date: Date.parse(m.receivedDateTime) || 0,
    preview: String(m.bodyPreview || "").replace(/\s+/g, " ").trim(),
    link: m.webLink || "",
  };
}

function decodeEntities(s) {
  return String(s)
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&quot;/g, '"')
    .replace(/&apos;|&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&");
}

// Aus einer Mail eine Aufgabe machen (für store.addTask)
export function mailToTask(m) {
  const lines = [m.from ? `Von: ${m.from}` : "", m.preview ? `> ${m.preview}` : "", m.link ? `[Mail öffnen](${m.link})` : ""].filter(Boolean);
  return { title: m.subject, notes: lines.join("\n\n") };
}

// ---------- Laden ----------
async function loadGoogle(now) {
  const token = await tokenFor("google");
  const email = accountsRaw().google?.email || "";
  const [a, b] = dayBounds(now);
  const cal = `https://www.googleapis.com/calendar/v3/calendars/primary/events?${new URLSearchParams({ timeMin: a.toISOString(), timeMax: b.toISOString(), singleEvents: "true", orderBy: "startTime", maxResults: "25" })}`;
  const list = `https://gmail.googleapis.com/gmail/v1/users/me/messages?${new URLSearchParams({ q: "in:inbox is:unread newer_than:7d", maxResults: String(MAIL_MAX) })}`;
  const [ev, ids] = await Promise.all([api(token, cal), api(token, list)]);
  const msgs = await Promise.all(
    (ids.messages || []).map((x) => api(token, `https://gmail.googleapis.com/gmail/v1/users/me/messages/${x.id}?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Date`).catch(() => null)),
  );
  return { events: (ev.items || []).map(googleEvent), mails: msgs.map((m) => gmailMessage(m, email)) };
}

async function loadMicrosoft(now) {
  const token = await tokenFor("microsoft");
  const [a, b] = dayBounds(now);
  const cal = `https://graph.microsoft.com/v1.0/me/calendarView?${new URLSearchParams({ startDateTime: a.toISOString(), endDateTime: b.toISOString(), $orderby: "start/dateTime", $top: "25", $select: "subject,start,end,isAllDay,isCancelled,location,webLink" })}`;
  const mail = `https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages?${new URLSearchParams({ $filter: "isRead eq false", $top: String(MAIL_MAX), $select: "subject,from,receivedDateTime,bodyPreview,webLink" })}`;
  const [ev, ms] = await Promise.all([api(token, cal, { Prefer: 'outlook.timezone="UTC"' }), api(token, mail)]);
  return { events: (ev.value || []).map(graphEvent), mails: (ms.value || []).map(graphMessage) };
}

let cache = null; // { at, day, events, mails, needsLogin: [p], errors: [{p, text}] }
let loading = null;
let gen = 0; // steigt, wenn Konten dazukommen oder wegfallen: laufendes Laden ist dann veraltet
function reset() {
  gen++;
  cache = null;
  changed();
}
let listeners = [];
export function onChange(fn) {
  listeners.push(fn);
}
function changed() {
  for (const fn of listeners) {
    try {
      fn();
    } catch (_) {
      /* egal */
    }
  }
}

// Was gerade bekannt ist (sofort, ohne zu warten); stößt bei Bedarf ein Nachladen an
export function snapshot(now = new Date()) {
  if (!accounts().length) return null;
  const stale = !cache || cache.day !== localISO(now) || Date.now() - cache.at > MAX_AGE;
  if (stale && !loading) refresh(now);
  return cache || { at: 0, day: localISO(now), events: [], mails: [], needsLogin: [], errors: [], loading: true };
}

export function refresh(now = new Date()) {
  if (loading) return loading;
  const g = gen;
  loading = (async () => {
    const out = { at: Date.now(), day: localISO(now), events: [], mails: [], needsLogin: [], errors: [] };
    await Promise.all(
      accounts().map(async ({ provider: p }) => {
        try {
          const r = await (p === "google" ? loadGoogle(now) : loadMicrosoft(now));
          out.events.push(...r.events.filter(Boolean));
          out.mails.push(...r.mails.filter(Boolean));
        } catch (e) {
          if (e instanceof NeedsLogin) out.needsLogin.push(p);
          else out.errors.push({ p, text: navigator.onLine === false ? "offline" : e.message || String(e) });
        }
      }),
    );
    out.events.sort((x, y) => Number(y.allDay) - Number(x.allDay) || x.start - y.start);
    const hidden = taken();
    out.mails = out.mails.filter((m) => !hidden.has(m.id)).sort((x, y) => y.date - x.date).slice(0, MAIL_MAX);
    if (g !== gen) return cache; // Konten haben sich geändert: Ergebnis verwerfen, snapshot() lädt neu
    // offline: alte Daten behalten statt leerer Liste
    if (cache && out.errors.length && !out.events.length && !out.mails.length) cache = { ...cache, at: out.at, errors: out.errors };
    else cache = out;
    return cache;
  })().finally(() => {
    loading = null;
    changed();
  });
  return loading;
}

// Mails, aus denen schon eine Aufgabe wurde, nicht noch einmal zeigen
const TAKEN_KEY = "taschen-connect-taken";
const taken = () => new Set(lsGet(TAKEN_KEY) || []);
export function hideMail(id) {
  lsSet(TAKEN_KEY, [...taken(), id].slice(-200));
  if (cache) cache = { ...cache, mails: cache.mails.filter((m) => m.id !== id) };
  changed();
}
