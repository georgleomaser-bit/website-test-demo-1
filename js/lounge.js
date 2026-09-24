// AKYTEX Lounge: Warteraum, Freunde adden und Sprach-/Video-Calls (WebRTC, bis zu 8 Personen).
// Der AKYTEX-Server vermittelt nur den Verbindungsaufbau; Audio und Video gehen direkt von Gerät zu Gerät
// und werden nirgends aufgezeichnet. Ohne Server (z. B. GitHub Pages) zeigt die Lounge eine Vorschau.
import * as cloud from "./cloud.js";

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const hue = (s) => [...String(s)].reduce((a, ch) => (a * 31 + ch.charCodeAt(0)) % 360, 7);
const av = (u, big = false) => `<span class="avatar ${big ? "lg-av-big" : ""}" style="--c:hsl(${hue(u.id || u.handle)} 70% 60%)">${esc((u.handle || "?").replace(/[^a-z0-9]/gi, "").slice(0, 2).toUpperCase() || "?")}</span>`;
const OK_KEY = "akytex-lounge-ok";

const L = { app: null, avail: null, visible: false, st: null, stream: null, connected: false, ice: null, call: null, joining: false, queued: [], invite: null };

// ---------- API ----------
const api = (method, path, body) => cloud.apiCall(method, path, body);
const accepted = () => {
  try {
    return localStorage.getItem(OK_KEY) === "1";
  } catch (_) {
    return false;
  }
};

// Live-Verbindung zum Server (Server-Sent Events über fetch, damit der Schlüssel im Header bleibt)
async function connect() {
  if (L.stream) return;
  const ac = new AbortController();
  L.stream = ac;
  let backoff = 1000;
  while (!ac.signal.aborted) {
    try {
      const res = await fetch(cloud.apiBase + "live", { headers: cloud.authHeaders(), signal: ac.signal, cache: "no-store" });
      if (res.status === 401) break;
      if (!res.ok || !res.body) throw new Error("stream " + res.status);
      backoff = 1000;
      setConnected(true);
      const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
      let buf = "";
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        buf += value;
        let i;
        while ((i = buf.indexOf("\n\n")) >= 0) {
          const chunk = buf.slice(0, i);
          buf = buf.slice(i + 2);
          let type = "message";
          const data = [];
          for (const line of chunk.split("\n")) {
            if (line.startsWith("event:")) type = line.slice(6).trim();
            else if (line.startsWith("data:")) data.push(line.slice(5).trimStart());
          }
          if (data.length) {
            try {
              onEvent(type, JSON.parse(data.join("\n")));
            } catch (e) {
              console.warn("Lounge-Ereignis", e);
            }
          }
        }
      }
    } catch (_) {
      if (ac.signal.aborted) break;
    }
    setConnected(false);
    await sleep(backoff);
    backoff = Math.min(15000, backoff * 2);
  }
  if (L.stream === ac) L.stream = null;
}
function setConnected(on) {
  if (L.connected === on) return;
  L.connected = on;
  const dot = $("#lg-conn");
  if (dot) {
    dot.classList.toggle("on", on);
    dot.title = on ? "Verbunden" : "Verbinde …";
  }
  if (on && L.visible) api("POST", "live/lobby", { in: true }).catch(() => {});
}

function onEvent(type, d) {
  if (type === "state") {
    const first = !L.st;
    L.st = d;
    if (L.call && (!d.room || d.room.id !== L.call.room.id) && !L.joining) endCall(false, "Der Call wurde beendet.");
    if (L.call && d.room) {
      L.call.room = d.room;
      for (const m of d.room.members) L.call.peers.get(m.id)?.setName(m.handle);
      renderCallHead();
    }
    renderLists();
    syncBadge();
    if (first && L.visible) api("POST", "live/lobby", { in: true }).catch(() => {});
    return;
  }
  if (type === "peer-joined" && L.call && d.room === L.call.room.id) {
    ensurePeer(d.peer.id, d.peer.handle);
    L.app.beep?.(660, 0.08);
    return;
  }
  if (type === "peer-left" && L.call && d.room === L.call.room.id) return removePeer(d.id);
  if (type === "signal") {
    if (L.call) return ensurePeer(d.from).receive(d.data);
    if (L.joining) L.queued.push(d);
    return;
  }
  if (type === "invite") return showInvite(d);
  if (type === "kicked") return endCall(false, "Du wurdest aus dem Call entfernt.");
  if (type === "friend-request") {
    L.app.toast(`@${d.from.handle} möchte dich adden. Schau in der Lounge vorbei.`, "info", "👋 Freundschaftsanfrage");
    L.app.beep?.(990, 0.08);
    return;
  }
  if (type === "friend-accepted") return L.app.toast(`@${d.by.handle} und du seid jetzt Freunde.`, "success", "🤝 Neuer Freund");
}
function syncBadge() {
  const b = $("#lounge-badge");
  if (!b) return;
  const n = L.st?.incoming.length || 0;
  b.hidden = !n;
  b.textContent = n;
}

// ---------- Ansicht ----------
export function initLounge(app) {
  L.app = app;
  const root = $("#lounge");
  root.addEventListener("click", onClick);
  root.addEventListener("submit", onSubmit);
  $("#lg-pill")?.addEventListener("click", () => app.go("lounge"));
  cloud.cloudReady().then(async (on) => {
    L.avail = on;
    if (!on || !accepted() || !cloud.hasAccount()) return;
    // Im Hintergrund verbunden bleiben, damit Einladungen überall in der App ankommen
    if (await cloud.loadMe()) connect();
  });
}
export async function showLounge() {
  L.visible = true;
  if (L.avail === null) L.avail = await cloud.cloudReady();
  if (!L.avail) return renderOffline();
  if (!accepted() || !(await cloud.loadMe())) return renderGate();
  renderShell();
  connect();
  if (L.connected) api("POST", "live/lobby", { in: true }).catch(() => {});
  syncPill();
}
export function hideLounge() {
  if (!L.visible) return;
  L.visible = false;
  if (L.connected) api("POST", "live/lobby", { in: false }).catch(() => {});
  syncPill();
}
function syncPill() {
  const p = $("#lg-pill");
  if (!p) return;
  p.hidden = !L.call || L.visible;
  if (L.call) p.querySelector("span").textContent = `Im Call · ${L.call.room.members.length} ${L.call.room.members.length === 1 ? "Person" : "Personen"}`;
}

function renderOffline() {
  $("#lounge").innerHTML = `<section class="lg-hero">
    <div class="lg-hero-ic">🎧</div>
    <h1>Die AKYTEX Lounge</h1>
    <p class="muted">Der Warteraum für Trader: Leute kennenlernen, Freunde adden und zusammen in den Call gehen, mit Sprache, Video oder geteiltem Chart.</p>
    <div class="lg-chips"><span>🎙 Voice-Calls</span><span>📷 Video</span><span>🖥 Chart teilen</span><span>👋 Freunde adden</span><span>🔒 Private Calls</span></div>
    <div class="card lg-note"><b>Bald live</b><p class="muted small">Die Lounge läuft über den eigenen AKYTEX-Server. Auf dieser Adresse ist er noch nicht aktiv. Sobald AKYTEX über den Server läuft, geht die Lounge automatisch an.</p></div>
  </section>`;
}
function renderGate() {
  const name = cloud.cloudMe()?.handle || (L.app.profileName() || "").toLowerCase().replace(/[^a-z0-9._]/g, "").slice(0, 20);
  $("#lounge").innerHTML = `<section class="lg-hero">
    <div class="lg-hero-ic">🎧</div>
    <h1>Willkommen in der Lounge</h1>
    <p class="muted">Triff andere Trader im Warteraum, add Freunde und geht zusammen in den Call.</p>
    <form class="card lg-gate" id="lg-gate">
      <label class="field"><span>Dein Name in der Lounge</span><input id="lg-gate-name" maxlength="20" placeholder="z. B. leo.trades" value="${esc(name)}" required autocomplete="nickname" /></label>
      <small class="muted">3–20 Zeichen: a–z, 0–9, Punkt, Unterstrich. So finden dich deine Freunde.</small>
      <label class="clip-check"><input type="checkbox" id="lg-gate-ok" required /> <span class="small">Ich bin mindestens 16 Jahre alt und halte mich an die Lounge-Regeln: respektvoll bleiben, keine Aufnahmen ohne Zustimmung aller, keine Anlageberatung und keine Kaufaufrufe.</span></label>
      <button class="btn primary big">Lounge betreten</button>
    </form>
  </section>`;
}
function renderShell() {
  if ($("#lg-main")) return renderLists();
  $("#lounge").innerHTML = `<div id="lg-main">
    <header class="lg-head">
      <div><h1>Lounge <i id="lg-conn" class="lg-conn ${L.connected ? "on" : ""}" title="Verbinde …"></i></h1><p class="muted">Warteraum, Freunde und Calls. Audio und Video gehen direkt von Gerät zu Gerät und werden nicht aufgezeichnet.</p></div>
      <button class="lg-me" data-lg="rename" title="Namen ändern"><span id="lg-me-av"></span><b id="lg-me-name">@${esc(cloud.cloudMe()?.handle || "")}</b> ✎</button>
    </header>
    <section class="lg-call" id="lg-call" hidden></section>
    <div class="lg-grid">
      <div class="lg-col">
        <div class="card lg-card">
          <div class="lg-card-head"><h2>🔊 Calls</h2><button class="btn primary" data-lg="new-room">＋ Call starten</button></div>
          <form class="lg-newroom" id="lg-newroom" hidden>
            <input id="lg-room-name" maxlength="40" placeholder="Name, z. B. NVDA Earnings Talk" />
            <div class="seg lg-open"><button type="button" class="active" data-open="1">🌍 Offen</button><button type="button" data-open="0">🔒 Nur Freunde</button></div>
            <button class="btn primary">Starten</button>
          </form>
          <div id="lg-rooms"></div>
        </div>
        <div class="card lg-card">
          <div class="lg-card-head"><h2>🛋 Im Warteraum</h2><span class="muted small" id="lg-lobby-n"></span></div>
          <div id="lg-lobby"></div>
        </div>
      </div>
      <div class="lg-col">
        <div class="card lg-card">
          <div class="lg-card-head"><h2>👋 Freunde</h2></div>
          <form class="lg-add" id="lg-add"><input id="lg-add-name" maxlength="21" placeholder="@name adden" autocomplete="off" /><button class="btn primary">Adden</button></form>
          <div id="lg-requests"></div>
          <div id="lg-friends"></div>
        </div>
        <div class="card lg-card lg-rules">
          <h2>📜 Lounge-Regeln</h2>
          <ul class="small muted"><li>Respektvoll bleiben: kein Mobbing, keine Belästigung.</li><li>Keine Aufnahmen oder Screenshots ohne Zustimmung aller.</li><li>Keine Anlageberatung, keine „Kauf jetzt“-Aufrufe, kein Pushen von Aktien.</li><li>Ab 16 Jahren. Teile keine privaten Daten wie Adresse, Schule oder Passwörter.</li><li>Etwas stimmt nicht? Mit ⚑ melden oder mit ⛔ blockieren.</li></ul>
          <details id="lg-blocked-wrap"><summary class="small">Blockierte Personen</summary><div id="lg-blocked"></div></details>
        </div>
      </div>
    </div>
  </div>`;
  renderLists();
  if (L.call) buildStage();
}

function personMenu(u, where) {
  return `<button class="lg-ic" data-lg="report" data-id="${esc(u.id)}" data-h="${esc(u.handle)}" data-w="${where}" title="Melden" aria-label="@${esc(u.handle)} melden">⚑</button><button class="lg-ic" data-lg="block" data-id="${esc(u.id)}" data-h="${esc(u.handle)}" title="Blockieren" aria-label="@${esc(u.handle)} blockieren">⛔</button>`;
}
function renderLists() {
  const st = L.st;
  if (!st || !$("#lg-main")) return;
  const me = st.you;
  $("#lg-me-av").innerHTML = av(me);
  $("#lg-me-name").textContent = "@" + me.handle;
  const inRoom = L.call?.room.id;
  $("#lg-rooms").innerHTML = st.rooms.length
    ? st.rooms
        .map(
          (r) => `<div class="lg-room ${r.id === inRoom ? "here" : ""}">
        <div class="lg-room-top"><b>${esc(r.name)}</b><span class="lg-tag">${r.open ? "🌍 Offen" : "🔒 Privat"}</span></div>
        <div class="lg-room-bottom"><div class="lg-stack">${r.members.slice(0, 5).map((m) => av(m)).join("")}</div><span class="muted small">${r.members.length}/8</span>
        ${r.id === inRoom ? `<span class="lg-here">Du bist drin</span>` : `<button class="btn ${r.full ? "" : "primary"} sm" data-lg="join" data-room="${esc(r.id)}" ${r.full ? "disabled" : ""}>${r.full ? "Voll" : "Beitreten"}</button>`}</div>
      </div>`
        )
        .join("")
    : `<p class="lg-empty">Gerade läuft kein offener Call. Starte einfach einen, die anderen im Warteraum sehen ihn sofort.</p>`;
  $("#lg-lobby-n").textContent = st.lobby.length ? `${st.lobby.length} online` : "";
  $("#lg-lobby").innerHTML = st.lobby.length
    ? st.lobby
        .map(
          (u) => `<div class="lg-person">${av(u)}<div class="lg-who"><b>@${esc(u.handle)}</b><small>${u.inCall ? "🎧 im Call" : "🛋 wartet"}${u.friend ? " · Freund" : ""}</small></div>
        <div class="lg-acts">${u.friend ? `<button class="btn primary sm" data-lg="call" data-id="${esc(u.id)}">📞</button>` : u.requested ? `<span class="lg-tag">Angefragt</span>` : `<button class="btn sm" data-lg="add" data-id="${esc(u.id)}">＋ Adden</button>`}${personMenu(u, "Warteraum")}</div></div>`
        )
        .join("")
    : `<p class="lg-empty">Außer dir ist gerade niemand im Warteraum. Schick Freunden deinen Namen <b>@${esc(me.handle)}</b>, dann können sie dich adden.</p>`;
  $("#lg-requests").innerHTML =
    (st.incoming.length ? `<h3 class="lg-sub">Anfragen</h3>` + st.incoming.map((u) => `<div class="lg-person req">${av(u)}<div class="lg-who"><b>@${esc(u.handle)}</b><small>möchte dich adden</small></div><div class="lg-acts"><button class="btn primary sm" data-lg="accept" data-id="${esc(u.id)}">Annehmen</button><button class="btn sm" data-lg="decline" data-id="${esc(u.id)}">✕</button></div></div>`).join("") : "") +
    (st.outgoing.length ? `<p class="muted small lg-pending">Angefragt: ${st.outgoing.map((u) => "@" + esc(u.handle)).join(", ")}</p>` : "");
  $("#lg-friends").innerHTML = st.friends.length
    ? `<h3 class="lg-sub">Deine Freunde · ${st.friends.filter((f) => f.online).length} online</h3>` +
      st.friends
        .map(
          (f) => `<div class="lg-person ${f.online ? "" : "off"}"><span class="lg-avw">${av(f)}<i class="lg-dot ${f.online ? "on" : ""}"></i></span><div class="lg-who"><b>@${esc(f.handle)}</b><small>${f.room ? "🎧 im Call" : f.online ? "online" : "offline"}</small></div>
        <div class="lg-acts">${f.room && f.room !== inRoom ? `<button class="btn sm" data-lg="join" data-room="${esc(f.room)}">Beitreten</button>` : ""}${f.online ? `<button class="btn primary sm" data-lg="call" data-id="${esc(f.id)}" title="${L.call ? "In den Call einladen" : "Anrufen"}">${L.call ? "＋ Einladen" : "📞"}</button>` : ""}<button class="lg-ic" data-lg="unfriend" data-id="${esc(f.id)}" data-h="${esc(f.handle)}" title="Entfernen" aria-label="@${esc(f.handle)} entfernen">✕</button>${personMenu(f, "Freunde")}</div></div>`
        )
        .join("")
    : `<p class="lg-empty">Noch keine Freunde. Add Leute aus dem Warteraum oder gib oben einen Namen ein.</p>`;
  $("#lg-blocked-wrap").hidden = !st.blocked.length;
  $("#lg-blocked").innerHTML = st.blocked.map((u) => `<div class="lg-person">${av(u)}<div class="lg-who"><b>@${esc(u.handle)}</b></div><button class="btn sm" data-lg="unblock" data-id="${esc(u.id)}">Entsperren</button></div>`).join("");
  renderInviteList();
}

// ---------- Aktionen ----------
async function run(fn, okMsg) {
  try {
    const r = await fn();
    if (okMsg) L.app.toast(okMsg, "success");
    return r;
  } catch (e) {
    L.app.toast(e.message, "error");
  }
}
async function onSubmit(e) {
  e.preventDefault();
  const f = e.target;
  if (f.id === "lg-gate") {
    const name = $("#lg-gate-name").value.trim().toLowerCase();
    if (!/^[a-z0-9._]{3,20}$/.test(name)) return L.app.toast("Name: 3–20 Zeichen, nur a–z, 0–9, Punkt und Unterstrich.", "error");
    const ok = await run(async () => {
      const me = await cloud.ensureUser(name);
      if (me.handle !== name) await cloud.renameMe(name);
      return true;
    });
    if (!ok) return;
    try {
      localStorage.setItem(OK_KEY, "1");
    } catch (_) {
      /* ohne Speicher erneut fragen */
    }
    L.app.confetti?.();
    return showLounge();
  }
  if (f.id === "lg-add") {
    const h = $("#lg-add-name").value.trim().replace(/^@/, "").toLowerCase();
    if (!h) return;
    const r = await run(() => api("POST", "friends/request", { handle: h }));
    if (!r) return;
    $("#lg-add-name").value = "";
    L.app.toast(r.status === "friends" ? `Du und @${h} seid jetzt Freunde.` : `Anfrage an @${h} geschickt.`, "success", r.status === "friends" ? "🤝 Befreundet" : "👋 Angefragt");
    return;
  }
  if (f.id === "lg-newroom") {
    const open = $(".lg-open .active")?.dataset.open !== "0";
    await startRoom($("#lg-room-name").value.trim(), open);
    f.hidden = true;
    $("#lg-room-name").value = "";
  }
}
async function onClick(e) {
  const t = e.target.closest("[data-lg], [data-open]");
  if (!t) return;
  if (t.dataset.open) {
    $$(".lg-open button").forEach((b) => b.classList.toggle("active", b === t));
    return;
  }
  const { lg: act, id, h, room } = t.dataset;
  if (act === "new-room") {
    const f = $("#lg-newroom");
    f.hidden = !f.hidden;
    if (!f.hidden) $("#lg-room-name").focus();
    return;
  }
  if (act === "rename") {
    const n = prompt("Neuer Name (3–20 Zeichen: a–z, 0–9, Punkt, Unterstrich):", L.st?.you.handle || "");
    if (!n) return;
    if (await run(() => cloud.renameMe(n.trim().toLowerCase()), "Name geändert.")) api("POST", "live/lobby", { in: L.visible }).catch(() => {});
    return;
  }
  if (act === "add") return run(() => api("POST", "friends/request", { id }), "Anfrage geschickt 👋");
  if (act === "accept") return run(() => api("POST", `friends/${id}/accept`), "Ihr seid jetzt Freunde 🤝");
  if (act === "decline") return run(() => api("POST", `friends/${id}/decline`));
  if (act === "unfriend") return confirm(`@${h} aus deinen Freunden entfernen?`) && run(() => api("DELETE", `friends/${id}`));
  if (act === "unblock") return run(() => api("POST", `users/${id}/unblock`), "Entsperrt.");
  if (act === "block") {
    if (!confirm(`@${h} blockieren? Ihr seht euch dann nicht mehr im Warteraum, und @${h} kann dich nicht mehr adden oder einladen.`)) return;
    L.call?.peers.get(id)?.close();
    return run(() => api("POST", `users/${id}/block`), `@${h} ist blockiert.`);
  }
  if (act === "report") {
    const reason = prompt(`Was ist mit @${h} passiert? (z. B. Beleidigung, Belästigung, Spam)`);
    if (reason === null) return;
    return run(() => api("POST", `users/${id}/report`, { reason, where: t.dataset.w || "Lounge" }), "Danke, wir prüfen die Meldung.");
  }
  if (act === "kick") return confirm(`@${h} aus dem Call entfernen?`) && run(() => api("POST", `live/rooms/${L.call.room.id}/kick`, { id }));
  if (act === "join") return joinRoom(room);
  if (act === "call") return callFriend(id);
  if (act === "mic") return toggleMic();
  if (act === "cam") return setVideo(L.call?.videoKind === "cam" ? null : "cam");
  if (act === "screen") return setVideo(L.call?.videoKind === "screen" ? null : "screen");
  if (act === "invite") {
    const p = $("#lg-invite-pop");
    p.hidden = !p.hidden;
    return renderInviteList();
  }
  if (act === "invite-one") {
    t.disabled = true;
    return run(() => api("POST", "live/invite", { to: id }), `Einladung an @${h} geschickt 📨`);
  }
  if (act === "leave") return endCall(true);
}

// ---------- Calls ----------
async function iceServers() {
  if (L.ice) return L.ice;
  try {
    L.ice = (await api("GET", "live/ice")).iceServers;
  } catch (_) {
    L.ice = [{ urls: ["stun:stun.cloudflare.com:3478"] }];
  }
  return L.ice;
}
async function getMic() {
  try {
    return await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }, video: false });
  } catch (_) {
    L.app.toast("Ohne Mikrofon-Zugriff kannst du zuhören, aber nicht sprechen. Du kannst ihn in den Browser-Einstellungen erlauben.", "info", "🎙 Kein Mikrofon");
    return new MediaStream();
  }
}
async function enter(fn) {
  if (L.joining) return;
  if (!navigator.mediaDevices?.getUserMedia || typeof RTCPeerConnection === "undefined") return L.app.toast("Dein Browser unterstützt keine Calls. Probier Chrome, Safari oder Firefox.", "error");
  L.joining = true;
  L.queued = [];
  try {
    await iceServers();
    const local = await getMic();
    let r;
    try {
      r = await fn();
    } catch (e) {
      local.getTracks().forEach((t) => t.stop());
      throw e;
    }
    if (L.call) endCall(false);
    L.call = { room: r.room, local, mic: local.getAudioTracks().length > 0, videoKind: null, video: null, peers: new Map(), started: Date.now() };
    buildStage();
    for (const p of r.peers) ensurePeer(p.id, p.handle);
    for (const s of L.queued.splice(0)) ensurePeer(s.from).receive(s.data);
    L.app.haptic?.(12);
    syncPill();
    renderLists();
  } catch (e) {
    L.app.toast(e.message, "error");
  } finally {
    L.joining = false;
  }
}
const startRoom = (name, open = true) => enter(() => api("POST", "live/rooms", { name, open }));
const joinRoom = (id) => (L.call?.room.id === id ? null : enter(() => api("POST", `live/rooms/${id}/join`)));
async function callFriend(id) {
  const f = L.st?.friends.find((x) => x.id === id) || L.st?.lobby.find((x) => x.id === id);
  if (!L.call) await startRoom(`@${L.st.you.handle} & @${f?.handle || "Freund"}`, false);
  if (L.call) await run(() => api("POST", "live/invite", { to: id }), `@${f?.handle || "Freund"} wird angerufen … 📞`);
}
function endCall(notify = true, msg = "") {
  const c = L.call;
  if (!c) return;
  L.call = null;
  if (notify) api("POST", `live/rooms/${c.room.id}/leave`).catch(() => {});
  for (const p of c.peers.values()) p.close(true);
  c.local.getTracks().forEach((t) => t.stop());
  c.video?.stop();
  stopMeters();
  const st = $("#lg-call");
  if (st) {
    st.hidden = true;
    st.innerHTML = "";
  }
  if (msg) L.app.toast(msg, "info", "📞 Call beendet");
  syncPill();
  renderLists();
}

// Eine Verbindung pro Person im Call („Perfect Negotiation“: nie Chaos, wenn beide gleichzeitig verbinden)
class Peer {
  constructor(id, handle) {
    this.id = id;
    this.handle = handle || L.call.room.members.find((m) => m.id === id)?.handle || "…";
    this.polite = (L.st?.you.id || cloud.cloudMe()?.id || "") < id;
    this.makingOffer = false;
    this.ignoreOffer = false;
    this.pendingIce = [];
    this.inbox = Promise.resolve();
    this.outbox = Promise.resolve();
    this.iceBatch = null;
    this.media = { mic: true, cam: false, screen: false };
    const pc = (this.pc = new RTCPeerConnection({ iceServers: L.ice || [] }));
    this.stream = new MediaStream();
    this.tile = addTile(id, this.handle);
    this.audio = document.createElement("audio");
    this.audio.autoplay = true;
    this.tile.appendChild(this.audio);
    for (const t of L.call.local.getTracks()) pc.addTrack(t, L.call.local);
    if (L.call.video) this.videoSender = pc.addTrack(L.call.video, L.call.local);
    pc.onnegotiationneeded = async () => {
      try {
        this.makingOffer = true;
        await pc.setLocalDescription();
        this.send({ description: pc.localDescription.toJSON() });
      } catch (e) {
        console.warn(e);
      } finally {
        this.makingOffer = false;
      }
    };
    pc.onicecandidate = ({ candidate }) => {
      if (!candidate) return;
      (this.iceBatch ||= []).push(candidate.toJSON());
      if (this.iceBatch.length === 1) setTimeout(() => this.send({ candidates: this.iceBatch.splice(0) }), 60);
    };
    pc.ontrack = ({ track }) => {
      this.stream.addTrack(track);
      this.audio.srcObject = this.stream;
      this.tile.querySelector("video").srcObject = this.stream;
      if (track.kind === "audio") meter(this.id, this.stream);
      track.onunmute = () => this.paint();
      this.paint();
    };
    pc.onconnectionstatechange = () => {
      this.tile.dataset.state = pc.connectionState;
      if (pc.connectionState === "failed") pc.restartIce();
    };
    this.sendMedia();
  }
  setName(h) {
    if (h && h !== this.handle) {
      this.handle = h;
      this.tile.querySelector(".lg-tname b").textContent = "@" + h;
    }
  }
  send(data) {
    this.outbox = this.outbox.then(() => api("POST", "live/signal", { to: this.id, data })).catch(() => {});
  }
  sendMedia() {
    const c = L.call;
    this.send({ media: { mic: c.mic, cam: c.videoKind === "cam", screen: c.videoKind === "screen" } });
  }
  receive(d) {
    this.inbox = this.inbox.then(() => this.handle_(d)).catch((e) => console.warn(e));
  }
  async handle_({ description, candidates, media }) {
    const pc = this.pc;
    if (media) {
      this.media = media;
      return this.paint();
    }
    if (description) {
      const collision = description.type === "offer" && (this.makingOffer || pc.signalingState !== "stable");
      this.ignoreOffer = !this.polite && collision;
      if (this.ignoreOffer) return;
      await pc.setRemoteDescription(description);
      for (const c of this.pendingIce.splice(0)) await pc.addIceCandidate(c).catch(() => {});
      if (description.type === "offer") {
        await pc.setLocalDescription();
        this.send({ description: pc.localDescription.toJSON() });
      }
    }
    for (const c of candidates || []) {
      if (!pc.remoteDescription) this.pendingIce.push(c);
      else await pc.addIceCandidate(c).catch((e) => !this.ignoreOffer && console.warn(e));
    }
  }
  paint() {
    const v = this.stream.getVideoTracks().find((t) => t.readyState === "live" && !t.muted);
    const showVideo = !!v && (this.media.cam || this.media.screen);
    this.tile.classList.toggle("has-video", showVideo);
    this.tile.classList.toggle("screen", !!this.media.screen);
    this.tile.classList.toggle("muted", !this.media.mic);
  }
  close(silent = false) {
    this.pc.close();
    this.audio.srcObject = null;
    this.tile.remove();
    stopMeter(this.id);
    L.call?.peers.delete(this.id);
    if (!silent) layout();
  }
}
function ensurePeer(id, handle) {
  let p = L.call.peers.get(id);
  if (!p) {
    p = new Peer(id, handle);
    L.call.peers.set(id, p);
    layout();
  }
  return p;
}
function removePeer(id) {
  L.call?.peers.get(id)?.close();
  L.app.beep?.(440, 0.08);
}

function toggleMic() {
  const c = L.call;
  if (!c) return;
  const tr = c.local.getAudioTracks()[0];
  if (!tr) return L.app.toast("Kein Mikrofon verbunden.", "info");
  c.mic = !c.mic;
  tr.enabled = c.mic;
  $("#lg-tile-me")?.classList.toggle("muted", !c.mic);
  $('[data-lg="mic"]')?.classList.toggle("off", !c.mic);
  for (const p of c.peers.values()) p.sendMedia();
}
async function setVideo(kind) {
  const c = L.call;
  if (!c) return;
  let track = null;
  if (kind) {
    try {
      const s = kind === "cam" ? await navigator.mediaDevices.getUserMedia({ video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: "user" } }) : await navigator.mediaDevices.getDisplayMedia({ video: { frameRate: 15 }, audio: false });
      track = s.getVideoTracks()[0];
    } catch (_) {
      return L.app.toast(kind === "cam" ? "Kein Kamera-Zugriff." : "Bildschirm teilen wurde abgebrochen.", "info");
    }
    if (!L.call) return track.stop();
    track.onended = () => L.call?.video === track && setVideo(null);
  }
  const old = c.video;
  c.video = track;
  c.videoKind = kind;
  if (old) {
    c.local.removeTrack(old);
    old.stop();
  }
  if (track) c.local.addTrack(track);
  for (const p of c.peers.values()) {
    if (p.videoSender) await p.videoSender.replaceTrack(track).catch(() => {});
    else if (track) p.videoSender = p.pc.addTrack(track, c.local);
    p.sendMedia();
  }
  const me = $("#lg-tile-me");
  if (me) {
    me.querySelector("video").srcObject = track ? new MediaStream([track]) : null;
    me.classList.toggle("has-video", !!track);
    me.classList.toggle("mirror", kind === "cam");
    me.classList.toggle("screen", kind === "screen");
  }
  $('[data-lg="cam"]')?.classList.toggle("on", kind === "cam");
  $('[data-lg="screen"]')?.classList.toggle("on", kind === "screen");
}

// ---------- Call-Bühne ----------
function buildStage() {
  const st = $("#lg-call");
  if (!st || !L.call) return;
  st.hidden = false;
  const share = !!navigator.mediaDevices?.getDisplayMedia && matchMedia("(pointer: fine)").matches;
  st.innerHTML = `<div class="lg-call-head" id="lg-call-head"></div>
    <div class="lg-tiles" id="lg-tiles"></div>
    <div class="lg-bar">
      <button class="lg-btn ${L.call.mic ? "" : "off"}" data-lg="mic" title="Mikrofon an/aus"><span>🎙</span><small>Mikro</small></button>
      <button class="lg-btn" data-lg="cam" title="Kamera an/aus"><span>📷</span><small>Kamera</small></button>
      ${share ? `<button class="lg-btn" data-lg="screen" title="Bildschirm teilen, z. B. deinen Chart"><span>🖥</span><small>Teilen</small></button>` : ""}
      <div class="lg-inv-wrap"><button class="lg-btn" data-lg="invite" title="Freunde einladen"><span>＋</span><small>Einladen</small></button><div class="lg-invite-pop card" id="lg-invite-pop" hidden></div></div>
      <button class="lg-btn end" data-lg="leave" title="Auflegen"><span>📞</span><small>Auflegen</small></button>
    </div>`;
  const me = addTile("me", L.st?.you.handle || "du");
  me.id = "lg-tile-me";
  me.classList.toggle("muted", !L.call.mic);
  me.querySelector("video").muted = true;
  if (L.call.local.getAudioTracks().length) meter("me", L.call.local);
  for (const p of L.call.peers.values()) $("#lg-tiles").appendChild(p.tile);
  if (L.call.video) setVideo(L.call.videoKind);
  renderCallHead();
  layout();
  clearInterval(L.timer);
  L.timer = setInterval(renderCallHead, 1000);
}
function addTile(id, handle) {
  const el = document.createElement("div");
  el.className = "lg-tile";
  el.dataset.peer = id;
  const u = { id: id === "me" ? L.st?.you.id || "me" : id, handle };
  const owner = L.call?.room.owner === L.st?.you.id;
  el.innerHTML = `<video autoplay playsinline muted></video><div class="lg-tile-av">${av(u, true)}</div>
    <div class="lg-tname"><b>@${esc(handle)}</b>${id === "me" ? " (du)" : ""}<span class="lg-micoff" title="stumm">🔇</span></div>
    ${id === "me" ? "" : `<div class="lg-tmenu">${owner ? `<button class="lg-ic" data-lg="kick" data-id="${esc(id)}" data-h="${esc(handle)}" title="Aus dem Call entfernen">🚪</button>` : ""}${personMenu(u, "Call")}</div>`}`;
  $("#lg-tiles")?.appendChild(el);
  return el;
}
function layout() {
  const n = $$("#lg-tiles .lg-tile").length;
  $("#lg-tiles")?.style.setProperty("--n", n);
  syncPill();
}
function renderCallHead() {
  const c = L.call;
  const h = $("#lg-call-head");
  if (!c || !h) return;
  const s = Math.floor((Date.now() - c.started) / 1000);
  h.innerHTML = `<div><b>${esc(c.room.name)}</b><span class="lg-tag">${c.room.open ? "🌍 Offen" : "🔒 Privat"}</span></div><span class="lg-timer">● ${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")} · ${c.room.members.length}/8</span>`;
  syncPill();
}
function renderInviteList() {
  const pop = $("#lg-invite-pop");
  if (!pop || pop.hidden || !L.call) return;
  const inCall = new Set(L.call.room.members.map((m) => m.id));
  const list = (L.st?.friends || []).filter((f) => f.online && !inCall.has(f.id));
  pop.innerHTML = list.length ? `<b class="small">Freunde einladen</b>` + list.map((f) => `<div class="lg-person">${av(f)}<div class="lg-who"><b>@${esc(f.handle)}</b></div><button class="btn primary sm" data-lg="invite-one" data-id="${esc(f.id)}" data-h="${esc(f.handle)}">Einladen</button></div>`).join("") : `<p class="muted small">Gerade ist kein Freund online. Add Leute im Warteraum.</p>`;
}

// Sprech-Anzeige: leuchtet, wenn jemand redet
const meters = new Map();
let meterCtx = null;
let meterTimer = 0;
function meter(id, stream) {
  try {
    meterCtx ||= new (window.AudioContext || window.webkitAudioContext)();
    if (meterCtx.state === "suspended") meterCtx.resume();
    stopMeter(id);
    const src = meterCtx.createMediaStreamSource(stream);
    const an = meterCtx.createAnalyser();
    an.fftSize = 512;
    src.connect(an);
    meters.set(id, { src, an, buf: new Uint8Array(an.fftSize) });
    if (!meterTimer)
      meterTimer = setInterval(() => {
        for (const [pid, m] of meters) {
          m.an.getByteTimeDomainData(m.buf);
          let sum = 0;
          for (const v of m.buf) sum += (v - 128) ** 2;
          const on = Math.sqrt(sum / m.buf.length) > 6;
          $(`#lg-tiles [data-peer="${pid}"]`)?.classList.toggle("speaking", on && (pid !== "me" || L.call?.mic));
        }
      }, 120);
  } catch (_) {
    /* ohne Web Audio keine Anzeige */
  }
}
function stopMeter(id) {
  const m = meters.get(id);
  if (!m) return;
  m.src.disconnect();
  meters.delete(id);
}
function stopMeters() {
  for (const id of [...meters.keys()]) stopMeter(id);
  clearInterval(meterTimer);
  meterTimer = 0;
  clearInterval(L.timer);
}

// ---------- Einladungen (klingeln überall in der App) ----------
function showInvite({ room, from }) {
  if (L.call?.room.id === room.id) return;
  closeInvite();
  const el = document.createElement("div");
  el.className = "lg-ring";
  el.setAttribute("role", "alertdialog");
  el.innerHTML = `${av(from, true)}<div class="lg-ring-txt"><b>@${esc(from.handle)} ruft dich an</b><small>${esc(room.name)} · ${room.members.length} im Call</small></div>
    <button class="lg-btn ok" data-ring="accept" aria-label="Annehmen"><span>📞</span></button><button class="lg-btn end" data-ring="decline" aria-label="Ablehnen"><span>✕</span></button>`;
  document.body.appendChild(el);
  requestAnimationFrame(() => el.classList.add("show"));
  el.addEventListener("click", async (e) => {
    const b = e.target.closest("[data-ring]");
    if (!b) return;
    closeInvite();
    if (b.dataset.ring === "accept") {
      L.app.go("lounge");
      await joinRoom(room.id);
    }
  });
  let n = 0;
  const ring = () => {
    L.app.beep?.(n % 2 ? 660 : 880, 0.18);
    n++;
  };
  ring();
  L.invite = { el, timer: setInterval(ring, 1200), stop: setTimeout(closeInvite, 30000) };
  L.app.haptic?.([30, 80, 30]);
}
function closeInvite() {
  if (!L.invite) return;
  clearInterval(L.invite.timer);
  clearTimeout(L.invite.stop);
  const el = L.invite.el;
  el.classList.remove("show");
  setTimeout(() => el.remove(), 300);
  L.invite = null;
}
