// AKYTEX Lounge: Warteraum, Freunde und Calls (Sprache/Video per WebRTC).
// Der Server vermittelt nur: Anwesenheit, Räume, Freundschaften und den Verbindungsaufbau (Signaling).
// Audio und Video laufen direkt zwischen den Geräten und werden nicht über den Server geleitet oder gespeichert.
const MAX_ROOM = 8;
const MAX_STREAMS = 3; // gleichzeitige Tabs pro Konto
const MAX_FRIENDS = 500;
const GRACE_MS = 8000; // kurze Verbindungsabbrüche überbrücken

export function createLounge({ db, save, send, fail, readJson, clean, limited, id }) {
  const streams = new Map(); // userId → Set<res>
  const where = new Map(); // userId → { lobby, room }
  const rooms = new Map(); // roomId → { id, name, owner, open, members:Set, invited:Set, banned:Set, created }
  const gone = new Map(); // userId → Timer (Abmeldung nach Verbindungsabbruch)

  const user = (uid) => db.users[uid];
  const rel = (uid) => {
    const u = user(uid);
    if (!u) return { friends: [], incoming: [], outgoing: [], blocked: [] };
    return (u.rel ||= { friends: [], incoming: [], outgoing: [], blocked: [] });
  };
  const pub = (uid) => ({ id: uid, handle: user(uid)?.handle || "gelöscht" });
  const online = (uid) => (streams.get(uid)?.size || 0) > 0;
  const blocked = (a, b) => rel(a).blocked.includes(b) || rel(b).blocked.includes(a);
  const isFriend = (a, b) => rel(a).friends.includes(b);
  const pos = (uid) => where.get(uid) || { lobby: false, room: null };
  const drop = (arr, v) => {
    const i = arr.indexOf(v);
    if (i >= 0) arr.splice(i, 1);
  };

  function emit(uid, type, data) {
    const msg = `event: ${type}\ndata: ${JSON.stringify(data)}\n\n`;
    for (const r of streams.get(uid) || []) r.write(msg);
  }

  // Räume, die jemand sehen darf: offene Räume, Räume von Freunden, Räume mit Einladung
  function canSee(r, uid) {
    if (r.banned.has(uid)) return false;
    if ([...r.members].some((m) => blocked(m, uid))) return false;
    return r.open || r.owner === uid || r.members.has(uid) || r.invited.has(uid) || [...r.members].some((m) => isFriend(m, uid));
  }
  const roomView = (r) => ({ id: r.id, name: r.name, open: r.open, owner: r.owner, members: [...r.members].map(pub), created: r.created, full: r.members.size >= MAX_ROOM });

  function snapshot(uid) {
    const R = rel(uid);
    const room = pos(uid).room && rooms.get(pos(uid).room);
    return {
      you: pub(uid),
      friends: R.friends.map((f) => ({ ...pub(f), online: online(f), room: online(f) && pos(f).room && rooms.get(pos(f).room) && canSee(rooms.get(pos(f).room), uid) ? pos(f).room : null })).sort((a, b) => b.online - a.online || a.handle.localeCompare(b.handle)),
      incoming: R.incoming.map(pub),
      outgoing: R.outgoing.map(pub),
      blocked: R.blocked.map(pub),
      lobby: [...where.entries()].filter(([u, w]) => u !== uid && w.lobby && online(u) && !blocked(u, uid)).map(([u, w]) => ({ ...pub(u), friend: isFriend(uid, u), requested: R.outgoing.includes(u), inCall: !!w.room })),
      rooms: [...rooms.values()].filter((r) => canSee(r, uid)).map(roomView),
      room: room ? roomView(room) : null,
    };
  }

  // Änderungen gesammelt an alle Verbundenen schicken
  let pending = null;
  function broadcast() {
    if (pending) return;
    pending = setTimeout(() => {
      pending = null;
      for (const uid of streams.keys()) emit(uid, "state", snapshot(uid));
    }, 120);
  }

  function leaveRoom(uid) {
    const w = pos(uid);
    const r = w.room && rooms.get(w.room);
    if (w.room) where.set(uid, { ...w, room: null });
    if (!r) return;
    r.members.delete(uid);
    for (const m of r.members) emit(m, "peer-left", { room: r.id, id: uid });
    if (!r.members.size) rooms.delete(r.id);
    else if (r.owner === uid) r.owner = [...r.members][0];
    broadcast();
  }
  function joinRoom(uid, r) {
    if (r.banned.has(uid)) throw Object.assign(new Error("Du wurdest aus diesem Call entfernt."), { status: 403 });
    if (!canSee(r, uid)) throw Object.assign(new Error("Dieser Call ist privat."), { status: 403 });
    if (r.members.size >= MAX_ROOM && !r.members.has(uid)) throw Object.assign(new Error(`Der Call ist voll (max. ${MAX_ROOM}).`), { status: 409 });
    if (pos(uid).room !== r.id) leaveRoom(uid);
    const peers = [...r.members].filter((m) => m !== uid);
    r.members.add(uid);
    r.invited.delete(uid);
    where.set(uid, { ...pos(uid), room: r.id });
    for (const m of peers) emit(m, "peer-joined", { room: r.id, peer: pub(uid) });
    broadcast();
    return { room: roomView(r), peers: peers.map(pub) };
  }

  // Nutzer vollständig trennen (Sperre, Konto gelöscht)
  function dropUser(uid) {
    leaveRoom(uid);
    where.delete(uid);
    for (const r of streams.get(uid) || []) r.end();
    streams.delete(uid);
    broadcast();
  }

  function openStream(req, res, me) {
    const set = streams.get(me.id) || new Set();
    if (set.size >= MAX_STREAMS) return fail(res, 429, "Die Lounge ist schon in mehreren Tabs offen.");
    res.writeHead(200, { "Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-store", Connection: "keep-alive", "X-Accel-Buffering": "no", "X-Content-Type-Options": "nosniff" });
    res.write("retry: 3000\n\n");
    set.add(res);
    streams.set(me.id, set);
    clearTimeout(gone.get(me.id));
    gone.delete(me.id);
    if (!where.has(me.id)) where.set(me.id, { lobby: false, room: null });
    emit(me.id, "state", snapshot(me.id));
    broadcast();
    const ping = setInterval(() => res.write(": ping\n\n"), 25000);
    req.on("close", () => {
      clearInterval(ping);
      set.delete(res);
      if (set.size) return;
      streams.delete(me.id);
      broadcast();
      gone.set(
        me.id,
        setTimeout(() => {
          gone.delete(me.id);
          if (online(me.id)) return;
          leaveRoom(me.id);
          where.delete(me.id);
          broadcast();
        }, GRACE_MS)
      );
    });
  }

  function iceConfig() {
    const ice = [{ urls: (process.env.STUN_URLS || "stun:stun.cloudflare.com:3478").split(",").map((s) => s.trim()).filter(Boolean) }];
    if (process.env.TURN_URLS) ice.push({ urls: process.env.TURN_URLS.split(",").map((s) => s.trim()), username: process.env.TURN_USER || "", credential: process.env.TURN_PASS || "" });
    return ice;
  }

  // Liefert true, wenn die Anfrage zur Lounge gehört
  async function handle(req, res, p, me, ip) {
    let m;
    const need = () => {
      if (!me) {
        fail(res, 401, "Nicht angemeldet.");
        return false;
      }
      return true;
    };
    if (p === "/live" && req.method === "GET") {
      if (need()) openStream(req, res, me);
      return true;
    }
    if (p === "/live/ice" && req.method === "GET") return send(res, 200, { ok: true, iceServers: iceConfig() }), true;

    if (p === "/live/lobby" && req.method === "POST") {
      if (!need()) return true;
      const b = await readJson(req);
      where.set(me.id, { ...pos(me.id), lobby: !!b.in });
      broadcast();
      return send(res, 200, { ok: true }), true;
    }

    if (p === "/live/rooms" && req.method === "POST") {
      if (!need()) return true;
      if (limited("room:" + me.id, 20, 3600000)) return fail(res, 429, "Zu viele neue Calls. Bitte kurz warten."), true;
      const b = await readJson(req);
      const r = { id: id(6), name: clean(b.name, 40) || `Call von @${me.handle}`, owner: me.id, open: b.open !== false, members: new Set(), invited: new Set(), banned: new Set(), created: Date.now() };
      rooms.set(r.id, r);
      leaveRoom(me.id);
      return send(res, 201, { ok: true, ...joinRoom(me.id, r) }), true;
    }
    if ((m = /^\/live\/rooms\/([A-Za-z0-9_-]{4,16})\/(join|leave|kick)$/.exec(p)) && req.method === "POST") {
      if (!need()) return true;
      const r = rooms.get(m[1]);
      if (m[2] === "leave") {
        if (pos(me.id).room === m[1]) leaveRoom(me.id);
        return send(res, 200, { ok: true }), true;
      }
      if (!r) return fail(res, 404, "Dieser Call ist schon vorbei."), true;
      if (m[2] === "join") return send(res, 200, { ok: true, ...joinRoom(me.id, r) }), true;
      // Rauswerfen: nur wer den Call gestartet hat bzw. ihn gerade leitet
      const b = await readJson(req);
      if (r.owner !== me.id) return fail(res, 403, "Nur die Leitung des Calls kann Personen entfernen."), true;
      if (!r.members.has(b.id) || b.id === me.id) return fail(res, 400, "Person ist nicht im Call."), true;
      r.banned.add(b.id);
      leaveRoom(b.id);
      emit(b.id, "kicked", { room: r.id });
      return send(res, 200, { ok: true }), true;
    }

    if (p === "/live/invite" && req.method === "POST") {
      if (!need()) return true;
      if (limited("inv:" + me.id, 20, 60000)) return fail(res, 429, "Bitte etwas langsamer einladen."), true;
      const b = await readJson(req);
      const r = rooms.get(pos(me.id).room);
      if (!r) return fail(res, 400, "Starte zuerst einen Call."), true;
      if (!isFriend(me.id, b.to) || blocked(me.id, b.to)) return fail(res, 403, "Du kannst nur Freunde einladen."), true;
      if (!online(b.to)) return fail(res, 409, "Gerade nicht online."), true;
      r.invited.add(b.to);
      r.banned.delete(b.to);
      emit(b.to, "invite", { room: roomView(r), from: pub(me.id) });
      broadcast();
      return send(res, 200, { ok: true }), true;
    }

    // Verbindungsaufbau zwischen zwei Personen im selben Call weiterreichen
    if (p === "/live/signal" && req.method === "POST") {
      if (!need()) return true;
      if (limited("sig:" + me.id, 900, 60000)) return fail(res, 429, "Zu viele Verbindungsdaten."), true;
      const b = await readJson(req, 96 * 1024);
      const room = pos(me.id).room;
      if (!room || pos(b.to).room !== room || blocked(me.id, b.to)) return send(res, 200, { ok: true, dropped: true }), true;
      emit(b.to, "signal", { from: me.id, data: b.data });
      return send(res, 200, { ok: true }), true;
    }

    // ---------- Freunde ----------
    if (p === "/friends/request" && req.method === "POST") {
      if (!need()) return true;
      if (limited("fr:" + me.id, 40, 3600000)) return fail(res, 429, "Zu viele Anfragen. Versuch es später nochmal."), true;
      const b = await readJson(req);
      const h = clean(b.handle, 30).toLowerCase().replace(/^@/, "");
      const target = b.id ? user(b.id) : Object.values(db.users).find((u) => u.handle === h);
      if (!target || target.banned) return fail(res, 404, `@${h || "?"} gibt es nicht.`), true;
      if (target.id === me.id) return fail(res, 400, "Das bist du selbst 😄"), true;
      if (blocked(me.id, target.id)) return fail(res, 403, "Nicht möglich."), true;
      const A = rel(me.id);
      const B = rel(target.id);
      if (A.friends.includes(target.id)) return send(res, 200, { ok: true, status: "friends" }), true;
      if (A.friends.length >= MAX_FRIENDS) return fail(res, 409, "Deine Freundesliste ist voll."), true;
      // Hat die andere Person schon angefragt? Dann seid ihr direkt befreundet.
      if (A.incoming.includes(target.id)) {
        drop(A.incoming, target.id);
        drop(B.outgoing, me.id);
        A.friends.push(target.id);
        B.friends.push(me.id);
        emit(target.id, "friend-accepted", { by: pub(me.id) });
        save();
        broadcast();
        return send(res, 200, { ok: true, status: "friends" }), true;
      }
      if (!A.outgoing.includes(target.id)) A.outgoing.push(target.id);
      if (!B.incoming.includes(me.id)) B.incoming.push(me.id);
      emit(target.id, "friend-request", { from: pub(me.id) });
      save();
      broadcast();
      return send(res, 200, { ok: true, status: "requested", user: pub(target.id) }), true;
    }
    if ((m = /^\/friends\/([A-Za-z0-9_-]{6,20})\/(accept|decline)$/.exec(p)) && req.method === "POST") {
      if (!need()) return true;
      const A = rel(me.id);
      const B = rel(m[1]);
      const had = A.incoming.includes(m[1]);
      drop(A.incoming, m[1]);
      drop(B.outgoing, me.id);
      if (m[2] === "decline") drop(A.outgoing, m[1]), drop(B.incoming, me.id);
      if (m[2] === "accept" && had && user(m[1]) && !A.friends.includes(m[1])) {
        A.friends.push(m[1]);
        B.friends.push(me.id);
        emit(m[1], "friend-accepted", { by: pub(me.id) });
      }
      save();
      broadcast();
      return send(res, 200, { ok: true }), true;
    }
    if ((m = /^\/friends\/([A-Za-z0-9_-]{6,20})$/.exec(p)) && req.method === "DELETE") {
      if (!need()) return true;
      drop(rel(me.id).friends, m[1]);
      drop(rel(m[1]).friends, me.id);
      save();
      broadcast();
      return send(res, 200, { ok: true }), true;
    }
    if ((m = /^\/users\/([A-Za-z0-9_-]{6,20})\/(block|unblock|report)$/.exec(p)) && req.method === "POST") {
      if (!need()) return true;
      if (!user(m[1]) || m[1] === me.id) return fail(res, 404, "Nutzer nicht gefunden."), true;
      const A = rel(me.id);
      const B = rel(m[1]);
      if (m[2] === "block") {
        if (!A.blocked.includes(m[1])) A.blocked.push(m[1]);
        for (const [X, y] of [[A, m[1]], [B, me.id]]) for (const k of ["friends", "incoming", "outgoing"]) drop(X[k], y);
      }
      if (m[2] === "unblock") drop(A.blocked, m[1]);
      if (m[2] === "report") {
        if (limited("urep:" + me.id, 20, 3600000)) return fail(res, 429, "Zu viele Meldungen."), true;
        const b = await readJson(req);
        (db.userReports ||= []).push({ user: m[1], handle: user(m[1]).handle, by: me.id, reason: clean(b.reason, 300) || "ohne Angabe", where: clean(b.where, 40), ts: Date.now() });
        if (db.userReports.length > 2000) db.userReports.shift();
      }
      save();
      broadcast();
      return send(res, 200, { ok: true }), true;
    }
    return false;
  }

  return { handle, dropUser, stats: () => ({ online: streams.size, rooms: rooms.size }) };
}
