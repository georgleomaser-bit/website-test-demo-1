// Arbeitstaschen Service Worker: Netz zuerst (immer die neueste Version), offline aus dem Speicher, Erinnerungen per Push ohne Inhalt
const VERSION = "taschen-v1.1.0";
const CORE = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./css/taschen.css",
  "./js/main.js",
  "./js/app.js",
  "./js/config.js",
  "./js/util.js",
  "./js/dates.js",
  "./js/store.js",
  "./js/pm.js",
  "./js/remind.js",
  "./js/sync.js",
  "./js/ai.js",
  "./js/ui/actions.js",
  "./js/ui/aiui.js",
  "./js/ui/bag.js",
  "./js/ui/bags.js",
  "./js/ui/capture.js",
  "./js/ui/components.js",
  "./js/ui/core.js",
  "./js/ui/focus.js",
  "./js/ui/fx.js",
  "./js/ui/gestures.js",
  "./js/ui/icons.js",
  "./js/ui/inbox.js",
  "./js/ui/install.js",
  "./js/ui/markdown.js",
  "./js/ui/nav.js",
  "./js/ui/onboarding.js",
  "./js/ui/review.js",
  "./js/ui/search.js",
  "./js/ui/settings.js",
  "./js/ui/sheet.js",
  "./js/ui/task.js",
  "./js/ui/templates.js",
  "./js/ui/today.js",
  "./js/ui/upcoming.js",
  "./icons/icon.svg",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/icon-maskable-512.png",
  "./icons/apple-touch-icon.png",
  "./icons/favicon-64.png",
  "./icons/shortcut-heute-96.png",
  "./icons/shortcut-neu-96.png",
  "./icons/shortcut-demnaechst-96.png",
];

// IndexedDB – Namen von Hand gespiegelt aus js/config.js (DB): Service Worker können hier keine Module laden
const DB_NAME = "arbeitstaschen";
const KV = "kv";
const SCOPE = self.registration.scope;
const WINDOW = 15 * 60000; // Plan-Eintrag passt zum Push, wenn er höchstens 15 Min. entfernt ist
const NOTE_DAYS = 3;

// ---------- Installieren & Aufräumen ----------
// Weitergeleitete Antworten darf Safari nicht für Seitenaufrufe benutzen → sauber kopieren
async function clean(res) {
  if (!res.redirected) return res;
  const body = await res.blob();
  return new Response(body, { status: res.status, statusText: res.statusText, headers: res.headers });
}

self.addEventListener("install", (e) => {
  e.waitUntil(
    (async () => {
      const c = await caches.open(VERSION);
      // einzeln laden: eine fehlende Datei darf die Installation nicht scheitern lassen
      await Promise.all(
        CORE.map(async (u) => {
          try {
            const res = await fetch(new Request(u, { cache: "reload" }));
            if (res.ok) await c.put(u, await clean(res));
          } catch (_) {
            /* kommt beim nächsten Online-Aufruf in den Speicher */
          }
        }),
      );
    })(),
  );
  self.skipWaiting();
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    (async () => {
      // NUR eigene alte Speicher löschen – AKYTEX und NOVA liegen auf derselben Herkunft
      const keys = await caches.keys();
      await Promise.all(keys.filter((k) => k.startsWith("taschen-") && k !== VERSION).map((k) => caches.delete(k)));
      await self.clients.claim();
    })(),
  );
});

// ---------- Netz zuerst, offline aus dem Speicher ----------
self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET" || req.headers.has("range")) return;
  let url;
  try {
    url = new URL(req.url);
  } catch (_) {
    return;
  }
  if (url.origin !== location.origin || !req.url.startsWith(SCOPE) || /\/api(\/|$)/.test(url.pathname.slice(new URL(SCOPE).pathname.length - 1))) return;
  e.respondWith(netFirst(req, e));
});

async function netFirst(req, e) {
  try {
    const res = await fetch(req, { cache: "no-cache" });
    if (res.ok && res.type === "basic") {
      const copy = res.clone();
      e.waitUntil(
        caches
          .open(VERSION)
          .then(async (c) => c.put(req, await clean(copy)))
          .catch(() => {}),
      );
    }
    return res;
  } catch (err) {
    const c = await caches.open(VERSION);
    const hit = await c.match(req, { ignoreSearch: true });
    if (hit) return hit;
    if (req.mode === "navigate" || req.destination === "document") {
      const shell = (await c.match("./index.html")) || (await c.match("./"));
      if (shell) return shell;
    }
    return Response.error();
  }
}

// ---------- IndexedDB (nur lesen; nichts anlegen) ----------
function withTimeout(p, ms, fallback = null) {
  return Promise.race([p, new Promise((r) => setTimeout(() => r(fallback), ms))]);
}

function openDB() {
  return new Promise((resolve) => {
    let req;
    try {
      // ohne Versionsnummer: öffnet die vorhandene Datenbank, egal welche Version die App gerade nutzt
      req = indexedDB.open(DB_NAME);
    } catch (_) {
      return resolve(null);
    }
    // Gibt es die Datenbank noch nicht, legt der Service Worker sie NICHT an (das macht store.js mit den richtigen Stores)
    req.onupgradeneeded = () => {
      try {
        req.transaction.abort();
      } catch (_) {
        /* bricht ohnehin ab */
      }
    };
    req.onsuccess = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(KV)) {
        db.close();
        return resolve(null);
      }
      db.onversionchange = () => db.close(); // App will aktualisieren → sofort Platz machen
      resolve(db);
    };
    req.onerror = () => resolve(null);
    req.onblocked = () => resolve(null);
  });
}

function kvGet(db, key) {
  return new Promise((resolve) => {
    try {
      const r = db.transaction(KV, "readonly").objectStore(KV).get(key);
      r.onsuccess = () => resolve(r.result ?? null);
      r.onerror = () => resolve(null);
    } catch (_) {
      resolve(null);
    }
  });
}

function kvPut(db, key, value) {
  return new Promise((resolve) => {
    try {
      const t = db.transaction(KV, "readwrite");
      t.objectStore(KV).put(value, key);
      t.oncomplete = () => resolve(true);
      t.onerror = t.onabort = () => resolve(false);
    } catch (_) {
      resolve(false);
    }
  });
}

async function readAll() {
  const db = await withTimeout(openDB(), 5000);
  if (!db) return { db: null, plan: null, state: null, notified: null, push: null };
  const [plan, state, notified, push] = await Promise.all(["plan", "state", "notified", "push"].map((k) => withTimeout(kvGet(db, k), 5000)));
  return { db, plan, state, notified, push };
}

// Gezeigte Erinnerungen merken – die App zeigt sie dann nicht noch einmal
async function remember(db, notified, tags) {
  if (!db || !tags.length) return;
  const now = Date.now();
  const cut = now - NOTE_DAYS * 86400000;
  const fresh = (await withTimeout(kvGet(db, "notified"), 3000)) || notified || {};
  const next = {};
  for (const [k, v] of Object.entries(fresh)) if (typeof v === "number" && v >= cut) next[k] = v;
  for (const t of tags) next[t] = now;
  await withTimeout(kvPut(db, "notified", next), 3000, false);
}

// ---------- Mitteilung bauen (kleiner Projektmanager im Service Worker) ----------
const pad = (n) => String(n).padStart(2, "0");
const isoOf = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const minOf = (t, def) => {
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(t || ""));
  return m && +m[1] < 24 && +m[2] < 60 ? +m[1] * 60 + +m[2] : def;
};
const trunc = (s, n) => {
  const t = String(s || "")
    .replace(/\s+/g, " ")
    .trim();
  return t.length > n ? t.slice(0, n - 1) + "…" : t;
};
const count = (n, one, many) => `${n} ${n === 1 ? one : many}`;
const greet = (h) => (h >= 5 && h < 11 ? "Guten Morgen" : h >= 11 && h < 17 ? "Guten Tag" : h >= 17 && h < 22 ? "Guten Abend" : "Hallo");

function urlFor(item) {
  if (item && item.taskId) return "./?task=" + encodeURIComponent(item.taskId);
  if (item && item.kind === "review") return "./?view=rueckblick";
  return "./?view=heute";
}

// Schlüssel für „schon gezeigt“ – gleiche Regel wie noteKey() in js/remind.js
const keyOf = (it) => (it && it.kind === "task" && typeof it.at === "number" ? `${it.tag}@${it.at}` : String((it && it.tag) || "taschen"));

function fromItem(it) {
  return { title: it.title || "Arbeitstaschen", body: it.body || "", tag: String(it.tag || "taschen"), url: urlFor(it), kind: it.kind || null, taskId: it.taskId || null, tags: [keyOf(it)] };
}

// Plan-Einträge nahe „jetzt“ (± 15 Min.); gleichzeitige werden zusammengefasst
function fromPlan(plan, notified, now) {
  const items = (plan && Array.isArray(plan.items) ? plan.items : []).filter((it) => it && typeof it.at === "number" && it.tag);
  const near = items.filter((it) => Math.abs(it.at - now) <= WINDOW);
  if (!near.length) return null;
  const fresh = near.filter((it) => !(notified && notified[keyOf(it)]));
  const pool = (fresh.length ? fresh : near).sort((a, b) => Math.abs(a.at - now) - Math.abs(b.at - now));
  const lead = pool[0];
  const group = pool.filter((it) => Math.abs(it.at - lead.at) <= 60000);
  if (group.length === 1) return fromItem(lead);
  const tags = group.map(keyOf);
  if (group.every((it) => it.kind === "task")) {
    const lines = group.slice(0, 4).map((it) => `• ${trunc(it.title, 50)}${it.body ? ` – ${trunc(String(it.body).split(" · ")[0], 30)}` : ""}`);
    if (group.length > 4) lines.push(`+ ${group.length - 4} weitere`);
    return { title: `⏰ ${count(group.length, "Erinnerung", "Erinnerungen")}`, body: lines.join("\n"), tag: lead.tag, url: "./?view=heute", kind: "task", taskId: null, tags };
  }
  const others = group.filter((it) => it !== lead).map((it) => `+ ${trunc(it.title, 60)}`);
  return { ...fromItem(lead), body: [lead.body, ...others].filter(Boolean).join("\n"), tags };
}

// Ohne passenden Plan-Eintrag: Tagesbriefing aus dem Plan bzw. selbst aus dem gespeicherten Stand
function fromState(state, plan, now) {
  const d = new Date(now);
  const today = isoOf(d);
  const P = Object.assign({ dayStart: "08:00", dayEnd: "18:00", name: "" }, (state && state.profile) || {});
  const mins = d.getHours() * 60 + d.getMinutes();
  const name = P.name ? `, ${trunc(P.name, 30)}` : "";
  const open = (state && Array.isArray(state.tasks) ? state.tasks : []).filter((t) => t && !t.deleted && !t.done && !t.someday);
  const over = open.filter((t) => t.due && t.due < today).sort((a, b) => String(a.due).localeCompare(String(b.due)));
  const dueToday = open.filter((t) => t.due === today).sort((a, b) => String(a.time || "99").localeCompare(String(b.time || "99")) || (b.prio || 0) - (a.prio || 0));
  const planned = open.filter((t) => t.plan && t.plan <= today && !(t.due && t.due <= today)).sort((a, b) => (b.prio || 0) - (a.prio || 0));
  const all = [...over, ...dueToday, ...planned];
  const bullets = (list) => {
    const lines = list.slice(0, 3).map((t) => `• ${t.time && t.due === today ? t.time.replace(/^0/, "") + " " : ""}${trunc(t.title, 60)}${t.due && t.due < today ? " (überfällig)" : ""}`);
    if (list.length > 3) lines.push(`+ ${list.length - 3} weitere`);
    return lines.join("\n");
  };
  // Feierabend-Zeit (oder später)
  if (state && mins >= minOf(P.dayEnd, 1080) - 30) {
    return all.length
      ? { title: `🌙 Feierabend: ${count(all.length, "Aufgabe", "Aufgaben")} offen`, body: `${bullets(all)}\nErledigen oder auf morgen schieben?`, tag: `evening-${today}`, url: "./?view=heute" }
      : { title: `🌙 Feierabend${name}`, body: "Für heute ist alles erledigt – stark! 🎉", tag: `evening-${today}`, url: "./?view=heute" };
  }
  const b = plan && plan.briefings && plan.briefings[today];
  if (b && b.title) return { title: b.title, body: b.body || "", tag: `briefing-${today}`, url: "./?view=heute" };
  if (!state) return null;
  if (!all.length) return { title: `☀️ ${greet(d.getHours())}${name}`, body: "Heute ist nichts fällig – schau, was dich voranbringt.", tag: `briefing-${today}`, url: "./?view=heute" };
  return { title: `☀️ Heute: ${count(all.length, "Aufgabe", "Aufgaben")}${over.length ? ` · ${over.length} überfällig` : ""}`, body: bullets(all), tag: `briefing-${today}`, url: "./?view=heute" };
}

function badgeFrom(state, plan, now) {
  if (state && Array.isArray(state.tasks)) {
    const today = isoOf(new Date(now));
    const ids = new Set();
    for (const t of state.tasks) {
      if (!t || t.deleted || t.done) continue;
      if ((t.due && t.due <= today) || (t.plan && t.plan <= today && !t.someday)) ids.add(t.id);
    }
    return ids.size;
  }
  return plan && typeof plan.badge === "number" ? plan.badge : null;
}

function setBadge(n) {
  try {
    const nav = self.navigator;
    if (typeof n !== "number" || !nav || typeof nav.setAppBadge !== "function") return Promise.resolve();
    return (n > 0 ? nav.setAppBadge(n) : nav.clearAppBadge ? nav.clearAppBadge() : nav.setAppBadge(0)).catch(() => {});
  } catch (_) {
    return Promise.resolve();
  }
}

async function show(note, { silent = false } = {}) {
  const url = new URL(note.url || "./?view=heute", SCOPE).href;
  const tag = String(note.tag || "taschen");
  try {
    // macOS ersetzt per tag nicht zuverlässig → gleiche Mitteilung vorher schließen
    for (const n of await self.registration.getNotifications({ tag })) n.close();
  } catch (_) {
    /* egal */
  }
  return self.registration.showNotification(note.title || "Arbeitstaschen", {
    body: note.body || "",
    tag,
    renotify: true,
    lang: "de-DE",
    dir: "ltr",
    icon: new URL("icons/icon-192.png", SCOPE).href,
    silent: !!silent,
    data: { url, tag, kind: note.kind || null, taskId: note.taskId || null },
    navigate: url, // iOS/macOS 18.4+: öffnet die App direkt an der richtigen Stelle
  });
}

// ---------- Push (ohne Nutzlast): IMMER eine Mitteilung zeigen, sonst entzieht Safari das Push-Recht ----------
self.addEventListener("push", (e) => {
  e.waitUntil(onPush(e));
});

async function onPush(e) {
  const now = Date.now();
  let hint = null;
  try {
    hint = e.data ? e.data.json() : null; // falls der Server doch einmal etwas mitschickt
  } catch (_) {
    hint = null;
  }
  let data = { db: null, plan: null, state: null, notified: null };
  let note = null;
  try {
    data = (await withTimeout(readAll(), 9000)) || data;
    note = fromPlan(data.plan, data.notified, now) || fromState(data.state, data.plan, now);
  } catch (_) {
    note = null;
  }
  if (!note && hint && (hint.title || (hint.notification && hint.notification.title))) {
    const n = hint.notification || hint;
    note = { title: String(n.title), body: String(n.body || ""), tag: String(n.tag || "taschen"), url: "./?view=heute" };
  }
  if (!note) note = { title: "Arbeitstaschen", body: "Schau, was heute ansteht.", tag: "heute", url: "./?view=heute" };
  const silent = !!(data.state && data.state.profile && data.state.profile.sounds === false);
  try {
    await show(note, { silent });
  } catch (_) {
    await self.registration.showNotification("Arbeitstaschen", { body: "Schau, was heute ansteht.", tag: "heute", lang: "de-DE" }).catch(() => {});
  }
  await setBadge(badgeFrom(data.state, data.plan, now));
  try {
    await withTimeout(remember(data.db, data.notified, note.tags || [note.tag]), 4000);
  } catch (_) {
    /* nur Komfort */
  }
  try {
    if (data.db) data.db.close();
  } catch (_) {
    /* schon zu */
  }
}

// ---------- Tippen auf eine Mitteilung: App öffnen bzw. nach vorne holen ----------
self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  const d = e.notification.data || {};
  let url;
  try {
    url = new URL(d.url || "./?view=heute", SCOPE).href;
  } catch (_) {
    url = SCOPE;
  }
  e.waitUntil(
    (async () => {
      const all = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
      const mine = all.filter((c) => c.url && c.url.startsWith(SCOPE));
      const c = mine.find((x) => x.focused) || mine.find((x) => x.visibilityState === "visible") || mine[0];
      if (c) {
        try {
          await c.focus();
        } catch (_) {
          /* manche Browser erlauben das nicht */
        }
        // Zeigt das Fenster die Ansicht schon (z. B. „#heute“), reicht Fokussieren – kein Neuladen
        const target = new URL(url);
        const view = target.searchParams.get("view");
        if (view && !target.searchParams.get("task") && new URL(c.url).hash === "#" + view) return;
        if (c.url !== url && typeof c.navigate === "function") {
          try {
            await c.navigate(url);
            return;
          } catch (_) {
            /* nicht kontrolliert → neues Fenster */
          }
        } else return;
      }
      if (self.clients.openWindow) await self.clients.openWindow(url);
    })(),
  );
});

// ---------- Nachrichten aus der App ----------
self.addEventListener("message", (e) => {
  const d = e.data || {};
  if (d.type === "notify" && d.item && typeof d.item === "object") e.waitUntil(show(fromItem(d.item)).catch(() => {}));
  else if (d.type === "skip-waiting") self.skipWaiting();
});

// ---------- Abo erneuert (macOS/Chrome; iOS meldet das nicht – dort heilt die App beim Start) ----------
function keyBytes(s) {
  let t = String(s || "")
    .replace(/-/g, "+")
    .replace(/_/g, "/");
  if (t.length % 4) t += "=".repeat(4 - (t.length % 4));
  const bin = atob(t);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

self.addEventListener("pushsubscriptionchange", (e) => {
  e.waitUntil(
    (async () => {
      const { db, push } = await readAll();
      try {
        if (!push || !push.subscribed || !push.server || !push.device) return;
        let sub = e.newSubscription || null;
        if (!sub) {
          let key = e.oldSubscription && e.oldSubscription.options && e.oldSubscription.options.applicationServerKey;
          if (!key) {
            const r = await fetch(push.server + "/api/push/key", { cache: "no-store", credentials: "omit" });
            key = keyBytes((await r.json()).key);
          }
          sub = await self.registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key });
        }
        const prefs = push.prefs || {};
        await fetch(push.server + "/api/push/subscribe", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          credentials: "omit",
          body: JSON.stringify({
            device: push.device,
            subscription: sub.toJSON(),
            tz: prefs.tz || Intl.DateTimeFormat().resolvedOptions().timeZone,
            times: Array.isArray(prefs.times) ? prefs.times.filter((t) => t > Date.now()) : [],
            briefing: prefs.briefing ?? null,
            evening: prefs.evening ?? null,
            workdays: Array.isArray(prefs.workdays) ? prefs.workdays : [1, 2, 3, 4, 5],
          }),
        });
        if (db) await kvPut(db, "push", { ...push, endpoint: sub.endpoint });
      } catch (_) {
        /* die App meldet sich beim nächsten Start neu an */
      } finally {
        try {
          if (db) db.close();
        } catch (_) {
          /* schon zu */
        }
      }
    })(),
  );
});
