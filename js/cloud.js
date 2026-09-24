// AKYTEX Cloud: Verbindung zum eigenen AKYTEX-Server (server/akytex-server.mjs) für geteilte Clips.
// Läuft die Seite auf dem AKYTEX-Server, ist die API unter ./api erreichbar – dann sehen alle Nutzer
// die Clips aller Nutzer. Auf GitHub Pages gibt es keine API: Clips bleiben dann lokal im Browser.
const TOKEN_KEY = "akytex-cloud-token";
const base = new URL("api/", document.baseURI).href;
let available = null;
let info = {};
let me = null;

function token() {
  try {
    return localStorage.getItem(TOKEN_KEY) || "";
  } catch (_) {
    return "";
  }
}
async function call(method, path, body, headers = {}) {
  const t = token();
  const res = await fetch(base + path, {
    method,
    headers: { ...(t ? { Authorization: "Bearer " + t } : {}), ...(body && !(body instanceof Blob) ? { "Content-Type": "application/json" } : {}), ...headers },
    body: body instanceof Blob ? body : body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || data.ok === false) throw Object.assign(new Error(data.msg || `Serverfehler (${res.status})`), { status: res.status });
  return data;
}

export async function cloudReady() {
  if (available !== null) return available;
  // Statische Hosts (GitHub Pages, Netlify, Vercel) haben keine AKYTEX-API – gar nicht erst anfragen
  if (/\.(github\.io|netlify\.app|vercel\.app)$/.test(location.hostname)) return (available = false);
  try {
    const r = await fetch(base + "health", { cache: "no-store" });
    info = r.ok ? await r.json() : {};
    available = info.service === "akytex";
  } catch (_) {
    available = false;
  }
  return available;
}
export const cloudOn = () => available === true;
export const aiOnServer = () => available === true && info.ai === true;
// Prüft der Server Käufe bei Stripe? Dann gilt nur der Tarif, den der Server bestätigt.
export const billingOnServer = () => available === true && info.billing === true;

// Sprachmodell über den eigenen Server – gleiche Schnittstelle wie die Claude-Umgebung:
// llm(turns, { tools, signal, onText }) → { text }. Die Werkzeuge laufen hier im Browser.
export async function serverLLM(turns, { tools = [], signal, onText } = {}) {
  const defs = tools.map((t) => ({ name: t.name, description: t.description, input_schema: t.inputSchema || { type: "object", properties: {} } }));
  const messages = turns.map((t) => ({ role: t.role, content: t.content }));
  const stop = () => {
    if (signal?.aborted) throw Object.assign(new Error("Abgebrochen"), { code: "cancelled" });
  };
  let text = "";
  for (let step = 0; step < 8; step++) {
    stop();
    let r;
    try {
      if (billingOnServer() && !me) await ensureUser();
      r = await call("POST", "ai/chat", { messages, tools: defs });
    } catch (e) {
      throw Object.assign(e, { code: e.status === 429 ? "rate_limited" : e.status === 402 ? "quota" : e.status === 503 ? "not_granted" : "server" });
    }
    stop();
    const content = r.content || [];
    const said = content.filter((b) => b.type === "text" && b.text).map((b) => b.text).join("\n");
    if (said) {
      text = text ? `${text}\n\n${said}` : said;
      onText?.({ text });
    }
    if (r.stop_reason !== "tool_use") return { text };
    // Antwort unverändert zurückgeben (inkl. Denk-Blöcken) und die Werkzeuge ausführen
    messages.push({ role: "assistant", content });
    const results = await Promise.all(
      content
        .filter((b) => b.type === "tool_use")
        .map(async (b) => {
          const tool = tools.find((t) => t.name === b.name);
          try {
            const out = tool ? await tool.execute(b.input || {}) : { error: "Unbekanntes Werkzeug" };
            return { type: "tool_result", tool_use_id: b.id, content: JSON.stringify(out ?? null).slice(0, 12000) };
          } catch (e) {
            return { type: "tool_result", tool_use_id: b.id, content: String(e?.message || e), is_error: true };
          }
        })
    );
    messages.push({ role: "user", content: results });
  }
  return { text: text || "Da bin ich gerade nicht weitergekommen." };
}
export const cloudMe = () => me;
export const videoUrl = (id) => base + "videos/" + encodeURIComponent(id);

// Konto automatisch anlegen (anonym, nur ein Name) – beim ersten Hochladen, Liken oder Kommentieren
export async function ensureUser(handle) {
  if (me) return me;
  if (token()) {
    try {
      return (me = (await call("GET", "me")).user);
    } catch (e) {
      if (e.status !== 401) throw e;
    }
  }
  const r = await call("POST", "session", { handle });
  try {
    localStorage.setItem(TOKEN_KEY, r.token);
  } catch (_) {
    /* ohne Speicher gilt das Konto nur bis zum Neuladen */
  }
  return (me = r.user);
}
export async function loadMe() {
  if (!token()) return null;
  try {
    return (me = (await call("GET", "me")).user);
  } catch (_) {
    return null;
  }
}
// Kauf von Stripe bestätigen lassen (Kaufnummer aus der Rückleitung) und Tarif abfragen
export async function verifyPurchase(sessionId) {
  await ensureUser();
  return call("POST", "billing/verify", { sessionId });
}
export const serverBilling = () => call("GET", "billing");
// Liga: gemeinsamer Server-Markt, Depots und Rangliste liegen auf dem Server
export const hasToken = () => !!token();
export const leagueQuotes = async () => (await call("GET", "league/quotes")).quotes;
export const leagues = async () => (token() ? (await call("GET", "leagues")).leagues : []);
export const leagueGet = (id) => call("GET", `leagues/${encodeURIComponent(id)}`);
export async function leagueCreate(name, handle) {
  await ensureUser(handle);
  return (await call("POST", "leagues", { name })).league;
}
export async function leagueJoin(code, handle) {
  await ensureUser(handle);
  return (await call("POST", "leagues/join", { code })).league;
}
export const leagueTrade = (id, order) => call("POST", `leagues/${encodeURIComponent(id)}/trade`, order);
export const leagueLeave = (id) => call("POST", `leagues/${encodeURIComponent(id)}/leave`);
export const leagueSeason = (id) => call("POST", `leagues/${encodeURIComponent(id)}/season`);
export const renameMe = async (handle) => (me = (await call("PATCH", "me", { handle })).user);
export async function deleteMe() {
  await call("DELETE", "me");
  me = null;
  try {
    localStorage.removeItem(TOKEN_KEY);
  } catch (_) {
    /* ignorieren */
  }
}

export const feed = async (q = {}) => (await call("GET", "clips?" + new URLSearchParams(q))).clips;
export const upload = async (blob, { caption, sym }) =>
  (await call("POST", "clips", blob, { "Content-Type": blob.type || "video/mp4", "X-Caption": encodeURIComponent(caption), "X-Symbol": sym || "", "X-Rights": "1" })).clip;
export const like = (id) => call("POST", `clips/${encodeURIComponent(id)}/like`);
export const comments = async (id) => (await call("GET", `clips/${encodeURIComponent(id)}/comments`)).comments;
export const comment = async (id, text) => (await call("POST", `clips/${encodeURIComponent(id)}/comments`, { text })).comment;
export const report = (id, reason) => call("POST", `clips/${encodeURIComponent(id)}/report`, { reason });
export const remove = (id) => call("DELETE", `clips/${encodeURIComponent(id)}`);
