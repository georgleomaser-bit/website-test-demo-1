// AKYTEX-Liga: Freunde und Schulklassen treten mit Übungsgeld gegeneinander an.
// Fair und nicht zu fälschen: Alle handeln am selben Markt, den nur der Server berechnet, und jedes Liga-Depot
// liegt auf dem Server. Der Browser zeigt nur an und schickt Orders.
import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";
import { STOCKS } from "../js/data.js";

export const START_CASH = 100_000;
export const SEASON_DAYS = 28;
const MAX_MEMBERS = 250;
const MAX_OWNED = 5;
const MAX_JOINED = 12;
const DAY = 86400000;
const SYMS = new Set(STOCKS.map((s) => s.s));
const fail = (status, msg) => Object.assign(new Error(msg), { status });

// ---------- Gemeinsamer Markt (Server-Kurse, alle 5 s) ----------
const TICK = 5000;
const STEPS_PER_YEAR = (252 * 8.5 * 3600 * 1000) / TICK; // ein Handelsjahr in 5-s-Schritten
const SPEED = 4; // etwas lebhafter als die echte Börse – sonst passiert in 4 Wochen zu wenig
let MARKET_FILE = "";
let px = {}; // sym -> { p, open, day }
const gauss = () => {
  let u = 0;
  let v = 0;
  while (!u) u = Math.random();
  while (!v) v = Math.random();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
};
const today = () => new Date().toISOString().slice(0, 10);
function tick() {
  const d = today();
  for (const st of STOCKS) {
    const q = px[st.s] || (px[st.s] = { p: st.p, open: st.p, day: d });
    if (q.day !== d) Object.assign(q, { open: q.p, day: d });
    const sigma = (st.v * SPEED) / Math.sqrt(STEPS_PER_YEAR);
    // leichte Rückkehr zum Referenzkurs, damit nichts dauerhaft wegläuft
    const pull = 0.02 * Math.log(st.p / q.p) / STEPS_PER_YEAR * SPEED * 50;
    q.p = Math.max(0.5, q.p * Math.exp(sigma * gauss() + pull));
  }
}
export function initLeagueMarket(dataDir) {
  MARKET_FILE = path.join(dataDir, "league-market.json");
  try {
    px = JSON.parse(fs.readFileSync(MARKET_FILE, "utf8"));
  } catch (_) {
    px = {};
  }
  tick();
  setInterval(tick, TICK).unref();
  setInterval(() => fsp.writeFile(MARKET_FILE, JSON.stringify(px)).catch(() => {}), 60000).unref();
}
export const priceOf = (sym) => px[sym]?.p ?? STOCKS.find((s) => s.s === sym)?.p ?? 0;
export function quotes() {
  const out = {};
  for (const st of STOCKS) {
    const q = px[st.s];
    out[st.s] = { p: +(q?.p ?? st.p).toFixed(2), chg: q ? +(q.p / q.open - 1).toFixed(5) : 0 };
  }
  return out;
}

// ---------- Ligen ----------
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // ohne 0/O/1/I – leicht vorzulesen
const newCode = (leagues) => {
  for (;;) {
    const c = Array.from(crypto.randomBytes(6), (b) => CODE_CHARS[b % CODE_CHARS.length]).join("");
    if (!Object.values(leagues).some((l) => l.code === c)) return c;
  }
};
const freshDepot = () => ({ cash: START_CASH, pos: {}, trades: 0, joined: Date.now() });
export function depotValue(d) {
  let v = d.cash;
  for (const [sym, p] of Object.entries(d.pos)) v += p.qty * priceOf(sym);
  return v;
}
const ended = (l) => Date.now() >= l.seasonEnd;

export function createLeague(db, me, name) {
  const owned = Object.values(db.leagues).filter((l) => l.owner === me.id).length;
  if (owned >= MAX_OWNED) throw fail(429, `Du leitest schon ${MAX_OWNED} Ligen.`);
  if (myLeagues(db, me).length >= MAX_JOINED) throw fail(429, `Du bist schon in ${MAX_JOINED} Ligen.`);
  const id = crypto.randomBytes(6).toString("base64url");
  const now = Date.now();
  db.leagues[id] = { id, code: newCode(db.leagues), name: name || "Meine Liga", owner: me.id, created: now, season: 1, seasonStart: now, seasonEnd: now + SEASON_DAYS * DAY, members: { [me.id]: freshDepot() }, champions: [] };
  return db.leagues[id];
}
export function joinLeague(db, me, code) {
  const l = Object.values(db.leagues).find((x) => x.code === String(code || "").toUpperCase().replace(/[^A-Z0-9]/g, ""));
  if (!l) throw fail(404, "Diesen Liga-Code gibt es nicht.");
  if (l.members[me.id]) return l;
  if (Object.keys(l.members).length >= MAX_MEMBERS) throw fail(409, "Diese Liga ist voll.");
  if (myLeagues(db, me).length >= MAX_JOINED) throw fail(429, `Du bist schon in ${MAX_JOINED} Ligen.`);
  l.members[me.id] = freshDepot();
  return l;
}
export function leaveLeague(db, me, l) {
  delete l.members[me.id];
  if (!Object.keys(l.members).length) delete db.leagues[l.id];
  else if (l.owner === me.id) l.owner = Object.keys(l.members)[0]; // Leitung geht an das nächste Mitglied
}
export const myLeagues = (db, me) => Object.values(db.leagues).filter((l) => l.members[me.id]);
export function getLeague(db, me, id) {
  const l = db.leagues[id];
  if (!l || !l.members[me.id]) throw fail(404, "Liga nicht gefunden.");
  return l;
}

export function ranking(db, l) {
  return Object.entries(l.members)
    .map(([uid, d]) => ({ uid, handle: db.users[uid]?.handle || "gelöscht", value: depotValue(d), trades: d.trades }))
    .sort((a, b) => b.value - a.value)
    .map((r, i) => ({ ...r, rank: i + 1, pct: r.value / START_CASH - 1 }));
}
export function leagueView(db, me, l, full = false) {
  const rows = ranking(db, l);
  const mine = rows.find((r) => r.uid === me.id);
  const base = { id: l.id, code: l.code, name: l.name, owner: l.owner === me.id, season: l.season, seasonEnd: l.seasonEnd, ended: ended(l), members: rows.length, rank: mine?.rank ?? null, value: mine?.value ?? null, pct: mine?.pct ?? null, leader: rows[0] ? { handle: rows[0].handle, pct: rows[0].pct } : null };
  if (!full) return base;
  const d = l.members[me.id];
  return {
    ...base,
    board: rows.slice(0, 100).map(({ uid, ...r }) => ({ ...r, me: uid === me.id })),
    depot: { cash: d.cash, value: depotValue(d), pos: Object.entries(d.pos).map(([sym, p]) => ({ sym, qty: p.qty, avg: p.avg, price: priceOf(sym) })) },
    champions: l.champions.slice(-5),
  };
}
// Market-Order zum aktuellen Server-Kurs – keine Gebühren, keine Leerverkäufe
export function trade(l, me, { sym, side, qty }) {
  if (ended(l)) throw fail(409, "Die Saison ist vorbei. Die Liga-Leitung kann eine neue starten.");
  sym = String(sym || "").toUpperCase();
  qty = Math.floor(+qty);
  if (!SYMS.has(sym)) throw fail(400, "Unbekannte Aktie.");
  if (!(qty >= 1 && qty <= 1_000_000)) throw fail(400, "Stückzahl: 1 bis 1.000.000.");
  if (side !== "buy" && side !== "sell") throw fail(400, "Kauf oder Verkauf?");
  const d = l.members[me.id];
  const price = priceOf(sym);
  const p = d.pos[sym] || { qty: 0, avg: 0 };
  if (side === "buy") {
    if (price * qty > d.cash + 1e-6) throw fail(402, "Nicht genug Liga-Guthaben.");
    d.cash -= price * qty;
    p.avg = (p.avg * p.qty + price * qty) / (p.qty + qty);
    p.qty += qty;
    d.pos[sym] = p;
  } else {
    if (p.qty < qty) throw fail(409, "So viele Stücke hast du nicht.");
    d.cash += price * qty;
    p.qty -= qty;
    if (!p.qty) delete d.pos[sym];
  }
  d.trades++;
  return { sym, side, qty, price };
}
// Neue Saison (nur Leitung, erst nach Saisonende): Sieger kommt in die Ruhmeshalle, alle starten neu
export function newSeason(db, me, l) {
  if (l.owner !== me.id) throw fail(403, "Nur die Liga-Leitung kann eine neue Saison starten.");
  if (!ended(l)) throw fail(409, "Die Saison läuft noch.");
  const top = ranking(db, l)[0];
  if (top) l.champions.push({ season: l.season, handle: top.handle, pct: top.pct });
  const now = Date.now();
  Object.assign(l, { season: l.season + 1, seasonStart: now, seasonEnd: now + SEASON_DAYS * DAY });
  for (const uid of Object.keys(l.members)) l.members[uid] = freshDepot();
}
