// AKYTEX Cloud: Verbindung zum eigenen AKYTEX-Server (server/akytex-server.mjs) für geteilte Clips.
// Läuft die Seite auf dem AKYTEX-Server, ist die API unter ./api erreichbar – dann sehen alle Nutzer
// die Clips aller Nutzer. Auf GitHub Pages gibt es keine API: Clips bleiben dann lokal im Browser.
const TOKEN_KEY = "akytex-cloud-token";
const base = new URL("api/", document.baseURI).href;
let available = null;
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
    available = r.ok && (await r.json()).service === "akytex";
  } catch (_) {
    available = false;
  }
  return available;
}
export const cloudOn = () => available === true;
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
