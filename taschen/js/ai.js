// Arbeitstaschen – KI-Projektmanager (optional): fragt Claude über deinen eigenen Server – mit so wenig Daten wie möglich
import { checkServer, normServer, request } from "./sync.js";
import { deviceToken } from "./remind.js";
import { WEEKDAYS, todayISO, addDays, isISO, toISO } from "./dates.js";

// ---------- Grundlagen ----------
const KINDS = ["plan-day", "breakdown", "next", "weekly", "ask"];
const TIMEOUT = 60000;
const DAY = 86400000;
const PRIO = { 1: "niedrig", 2: "mittel", 3: "hoch" };

const cut = (s, n) => {
  const t = String(s ?? "")
    .replace(/\s+/g, " ")
    .trim();
  return t.length > n ? t.slice(0, n - 1).trimEnd() + "…" : t;
};
// leere Felder weglassen – das hält die Anfrage klein
const compact = (o) => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined && v !== null && v !== "" && v !== false && !(Array.isArray(v) && !v.length)));
const live = (a) => (Array.isArray(a) ? a.filter((e) => e && !e.deleted) : []);

// ---------- Verfügbarkeit ----------
export async function available(server) {
  if (!normServer(server)) return false;
  try {
    const c = await checkServer(server);
    return !!(c.ok && c.ai);
  } catch (_) {
    return false;
  }
}

// ---------- Fragen ----------
function aiError(r) {
  const msg = r.data?.msg || r.data?.error || "";
  switch (r.status) {
    case 400:
      return msg || "Die Anfrage war ungültig.";
    case 403:
      return msg || "Dein Server lässt diese App nicht zu (Herkunft nicht freigegeben).";
    case 404:
      return "Dein Server kennt den KI-Projektmanager nicht – bitte den Server aktualisieren.";
    case 413:
      return "Die Anfrage ist zu groß – frag lieber zu einer einzelnen Tasche.";
    case 429:
      return msg || "Für heute ist das KI-Kontingent aufgebraucht – morgen geht's weiter.";
    case 501:
    case 503:
      return msg || "Die KI ist auf deinem Server nicht eingerichtet (ANTHROPIC_API_KEY fehlt).";
    default:
      return r.status >= 500 ? msg || "Die KI hatte gerade einen Aussetzer – versuch es gleich noch mal." : msg || `Die KI ist gerade nicht erreichbar (${r.status}).`;
  }
}

// Antwort des Servers aufräumen: { text, items: [{ title, due?, prio?, est? }] }
export function normalizeAnswer(d) {
  const text = typeof d?.text === "string" ? d.text.trim().slice(0, 12000) : "";
  const items = [];
  for (const x of Array.isArray(d?.items) ? d.items : []) {
    const raw = typeof x === "string" ? { title: x } : x && typeof x === "object" ? x : null;
    if (!raw) continue;
    const title = cut(raw.title ?? raw.text ?? "", 200);
    if (!title) continue;
    const it = { title };
    if (isISO(raw.due)) it.due = raw.due;
    const p = Math.round(Number(raw.prio));
    if (p >= 1 && p <= 3) it.prio = p;
    const est = Math.round(Number(raw.est));
    if (est > 0 && est <= 1440) it.est = est;
    items.push(it);
    if (items.length >= 30) break;
  }
  return { text, items };
}

export async function ask(server, { kind = "ask", context = {}, question = "" } = {}) {
  const base = normServer(server);
  if (!base) throw new Error("Kein Server eingerichtet – der KI-Projektmanager läuft über deinen eigenen Server.");
  const k = KINDS.includes(kind) ? kind : "ask";
  const q = String(question ?? "")
    .trim()
    .slice(0, 2000);
  if (k === "ask" && !q) throw new Error("Was möchtest du wissen?");
  let device = "";
  try {
    device = await deviceToken();
  } catch (_) {
    /* ohne Token zählt der Server pro Adresse */
  }
  let r;
  try {
    r = await request(base, "/api/ai", { method: "POST", json: { device, kind: k, context: context && typeof context === "object" ? context : {}, question: q }, timeout: TIMEOUT });
  } catch (e) {
    throw new Error(e.timeout ? "Die KI braucht gerade zu lange – versuch es gleich noch mal." : e.offline ? "Du bist offline – der KI-Projektmanager braucht eine Verbindung." : "Dein Server ist gerade nicht erreichbar.");
  }
  if (!r.ok || r.data?.ok === false) throw new Error(aiError(r));
  return normalizeAnswer(r.data);
}

// ---------- Kontext (kompakt & datensparsam: Titel, Termine, Prioritäten, Taschen, Status – keine Notizen, Links oder Dateien) ----------
function statusOf(t, today) {
  if (t.done) return "erledigt";
  if (t.waiting) return "wartet";
  if (t.someday) return "irgendwann";
  if (t.due && t.due < today) return "überfällig";
  if (t.due === today) return "heute fällig";
  if (t.plan && t.plan <= today) return "für heute eingeplant";
  return "offen";
}

// Wichtigste zuerst: überfällig, heute, eingeplant, bald fällig, hohe Priorität
function rank(t, today) {
  if (t.due && t.due < today) return 0;
  if (t.due === today) return 1;
  if (t.plan && t.plan <= today) return 2;
  if (t.due && t.due <= addDays(today, 7)) return 3;
  if (t.prio === 3) return 4;
  if (t.due) return 5;
  if (t.someday || t.waiting) return 8;
  return 6;
}

export function contextFor(state, { bagId = null, taskId = null, now = new Date() } = {}) {
  const S = state && typeof state === "object" ? state : {};
  const n = now instanceof Date && !Number.isNaN(now.getTime()) ? now : new Date();
  const today = todayISO(n);
  const P = S.profile || {};
  const bags = live(S.bags);
  const byId = new Map(bags.map((b) => [b.id, b]));
  const tasks = live(S.tasks);
  const open = tasks.filter((t) => !t.done);
  const bagName = (id) => (id && byId.get(id)?.name) || "Eingang";
  const slim = (t, { withBag = true } = {}) =>
    compact({
      title: cut(t.title, 140),
      bag: withBag ? bagName(t.bag) : undefined,
      section: t.section ? cut(t.section, 40) : undefined,
      due: t.due || undefined,
      time: t.time || undefined,
      prio: PRIO[t.prio],
      status: statusOf(t, today),
      est: Number.isFinite(t.est) && t.est > 0 ? t.est : undefined,
      repeat: t.repeat || undefined,
      waiting: t.waiting ? cut(t.waiting, 60) : undefined,
      subtasks: Array.isArray(t.subtasks) && t.subtasks.length ? `${t.subtasks.filter((s) => s.done).length}/${t.subtasks.length}` : undefined,
    });
  const byRank = (a, b) => rank(a, today) - rank(b, today) || (a.due || "9999").localeCompare(b.due || "9999") || (b.prio || 0) - (a.prio || 0) || (a.order || 0) - (b.order || 0);
  const weekAgo = n.getTime() - 7 * DAY;
  const doneWeek = tasks.filter((t) => t.done && t.done >= weekAgo);

  const ctx = {
    app: "Arbeitstaschen",
    today,
    weekday: WEEKDAYS[n.getDay()],
    time: `${String(n.getHours()).padStart(2, "0")}:${String(n.getMinutes()).padStart(2, "0")}`,
    user: compact({ name: cut(P.name, 40) || undefined, dayStart: P.dayStart, dayEnd: P.dayEnd, workdays: Array.isArray(P.workdays) ? P.workdays.map((d) => WEEKDAYS[d]).filter(Boolean) : undefined, focusCount: P.focusCount }),
    counts: {
      open: open.length,
      overdue: open.filter((t) => t.due && t.due < today).length,
      today: open.filter((t) => t.due === today).length,
      planned: open.filter((t) => t.plan && t.plan <= today).length,
      inbox: open.filter((t) => !t.bag).length,
      doneLast7Days: doneWeek.length,
    },
    bags: bags
      .filter((b) => b.status !== "fertig" || b.id === bagId)
      .slice(0, 30)
      .map((b) => {
        const bt = open.filter((t) => t.bag === b.id);
        return compact({ name: cut(b.name, 60), emoji: b.emoji, goal: cut(b.goal, 160), status: b.status, deadline: b.deadline || undefined, open: bt.length, overdue: bt.filter((t) => t.due && t.due < today).length });
      }),
  };

  const bag = bagId ? byId.get(bagId) : null;
  if (bag) {
    const bt = open.filter((t) => t.bag === bag.id).sort(byRank);
    ctx.bag = compact({
      name: cut(bag.name, 60),
      goal: cut(bag.goal, 300),
      status: bag.status,
      deadline: bag.deadline || undefined,
      sections: Array.isArray(bag.sections) ? bag.sections.slice(0, 20).map((s) => cut(s, 40)) : undefined,
      milestones: live(S.milestones)
        .filter((m) => m.bag === bag.id)
        .sort((a, b) => (a.date || "9999").localeCompare(b.date || "9999"))
        .slice(0, 15)
        .map((m) => compact({ title: cut(m.title, 100), date: m.date || undefined, done: !!m.done })),
      tasks: bt.slice(0, 60).map((t) => slim(t, { withBag: false })),
      moreTasks: bt.length > 60 ? bt.length - 60 : undefined,
      recentlyDone: tasks
        .filter((t) => t.bag === bag.id && t.done && t.done >= n.getTime() - 14 * DAY)
        .sort((a, b) => b.done - a.done)
        .slice(0, 10)
        .map((t) => cut(t.title, 100)),
    });
  }

  const task = taskId ? tasks.find((t) => t.id === taskId) : null;
  if (task) {
    ctx.task = compact({
      ...slim(task),
      subtasks: Array.isArray(task.subtasks) && task.subtasks.length ? task.subtasks.slice(0, 30).map((s) => compact({ title: cut(s.title, 100), done: !!s.done })) : undefined,
      bagGoal: task.bag ? cut(byId.get(task.bag)?.goal, 200) || undefined : undefined,
    });
  }

  // Übrige wichtige Aufgaben (ohne die der gewählten Tasche, die stehen oben schon)
  const rest = open.filter((t) => !bag || t.bag !== bag.id).sort(byRank);
  const limit = bag || task ? 25 : 80;
  ctx.tasks = rest.slice(0, limit).map((t) => slim(t));
  if (rest.length > limit) ctx.moreTasks = rest.length - limit;
  ctx.doneRecently = doneWeek
    .sort((a, b) => b.done - a.done)
    .slice(0, 15)
    .map((t) => compact({ title: cut(t.title, 100), bag: bagName(t.bag), day: toISO(t.done) }));
  return ctx;
}
