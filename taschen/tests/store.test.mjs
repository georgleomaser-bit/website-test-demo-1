// Tests für store.js – CRUD, Rückgängig, Grabsteine, Sync-Zusammenführung, Backup und Startdaten (reiner Speicher in Node)
process.env.TZ = "Europe/Berlin";
import { test, describe, beforeEach } from "node:test";
import assert from "node:assert/strict";

const store = await import("../js/store.js");
const { LIMITS, DEFAULT_PROFILE } = await import("../js/config.js");
const { todayISO, addDays } = await import("../js/dates.js");

const DAY = 86400000;
const today = () => todayISO(new Date());
const live = (arr) => arr.filter((e) => !e.deleted);

beforeEach(async () => {
  await store.load({ memory: true });
  await store.resetAll();
  await store.load({ memory: true });
});

// ---------- Laden & Grundlagen ----------
describe("Laden", () => {
  test("load liefert einen leeren, gültigen Zustand ohne Beispieldaten", () => {
    const s = store.get();
    assert.equal(s.v, 1);
    assert.deepEqual([s.bags.length, s.tasks.length, s.notes.length, s.links.length, s.files.length, s.milestones.length], [0, 0, 0, 0, 0, 0]);
    assert.equal(s.meta.seeded, false);
    assert.equal(s.profile.dayStart, DEFAULT_PROFILE.dayStart);
  });

  test("Geräte-ID beginnt mit d_ und bleibt über Neuladen und Zurücksetzen erhalten", async () => {
    const id = store.deviceId();
    assert.match(id, /^d_[0-9a-f]{16}$/);
    await store.load({ memory: true });
    assert.equal(store.deviceId(), id);
    await store.resetAll();
    await store.load({ memory: true });
    assert.equal(store.deviceId(), id);
  });

  test("Gespeichertes übersteht flush + erneutes Laden", async () => {
    const b = store.addBag({ name: "AKYTEX" });
    store.addTask({ title: "Domain verbinden", bag: b.id });
    await store.flush();
    await store.load({ memory: true });
    assert.equal(store.bags()[0].name, "AKYTEX");
    assert.equal(store.tasksOf(b.id)[0].title, "Domain verbinden");
    assert.equal(store.canUndo(), false); // Laden erzeugt keinen Rückgängig-Schritt
  });

  test("Entprelltes Speichern landet nach ~300 ms auch ohne flush", async () => {
    store.addTask({ title: "Auto-Speichern" });
    await new Promise((r) => setTimeout(r, 450));
    await store.load({ memory: true });
    assert.equal(store.tasks()[0]?.title, "Auto-Speichern");
  });

  test("migrate/normalizeState: Müll wird bereinigt, unbekannte Felder bleiben, doppelte ids → neuere gewinnt", () => {
    const s = store.migrate({ v: 1, tasks: [{ id: "a", title: "  Alt ", updated: 5, prio: 9, due: "2026-02-30", time: "9:5", extra: 42 }, { id: "a", title: "Neu", updated: 9 }, { title: "ohne id" }, null], bags: "kaputt", profile: { focusCount: 99, dayStart: "25:00", workdays: [1, 1, 9, 2] } });
    assert.equal(s.tasks.length, 1);
    assert.equal(s.tasks[0].title, "Neu");
    const raw = store.normTask({ id: "x", title: "  Alt ", prio: 9, due: "2026-02-30", time: "9:05", extra: 42 });
    assert.equal(raw.title, "Alt");
    assert.equal(raw.prio, 3);
    assert.equal(raw.due, null);
    assert.equal(raw.time, "09:05");
    assert.equal(raw.extra, 42);
    assert.deepEqual(s.bags, []);
    assert.equal(s.profile.focusCount, 10);
    assert.equal(s.profile.dayStart, DEFAULT_PROFILE.dayStart);
    assert.deepEqual(s.profile.workdays, [1, 2]);
    assert.equal(store.migrate(null).v, 1);
    assert.equal(store.migrate("Quatsch").tasks.length, 0);
  });
});

// ---------- Taschen ----------
describe("Taschen", () => {
  test("addBag: Standardwerte, Reihenfolge, Pflichtname", () => {
    const a = store.addBag({ name: "  AKYTEX " });
    const b = store.addBag({ name: "NOVA", emoji: "✨", color: "purple" });
    assert.equal(a.name, "AKYTEX");
    assert.equal(a.emoji, "👜");
    assert.equal(a.color, "blue");
    assert.equal(a.status, "aktiv");
    assert.deepEqual(a.sections, []);
    assert.equal(b.order, a.order + 1);
    assert.equal(store.addBag({ name: "X", color: "neonpink" }).color, "blue");
    assert.throws(() => store.addBag({ name: "   " }), /Namen/);
  });

  test("bags(): angepinnte zuerst, dann Reihenfolge; reorderBags", () => {
    const a = store.addBag({ name: "A" });
    const b = store.addBag({ name: "B" });
    const c = store.addBag({ name: "C" });
    store.updateBag(c.id, { pinned: true });
    assert.deepEqual(store.bags().map((x) => x.name), ["C", "A", "B"]);
    store.updateBag(c.id, { pinned: false });
    store.reorderBags([b.id, c.id, a.id]);
    assert.deepEqual(store.bags().map((x) => x.name), ["B", "C", "A"]);
  });

  test("removeBag setzt Grabsteine für Tasche und alle Inhalte – und ist rückgängig machbar", () => {
    const b = store.addBag({ name: "Firma" });
    const t = store.addTask({ title: "Notar", bag: b.id });
    const n = store.addNote({ bag: b.id, title: "Ausgangslage" });
    const l = store.addLink({ bag: b.id, url: "https://bafin.de" });
    const m = store.addMilestone({ bag: b.id, title: "Gründung", date: "2026-12-01" });
    const other = store.addTask({ title: "Anderes" });
    store.removeBag(b.id);
    assert.equal(store.bag(b.id), null);
    assert.equal(store.task(t.id), null);
    assert.equal(store.note(n.id), null);
    assert.equal(store.link(l.id), null);
    assert.equal(store.milestones(b.id).length, 0);
    assert.ok(store.task(other.id));
    assert.ok(store.get().tasks.find((x) => x.id === t.id).deleted);
    assert.equal(store.undo(), "Tasche gelöscht");
    assert.ok(store.bag(b.id));
    assert.ok(store.task(t.id));
    assert.ok(store.note(n.id));
    assert.ok(store.link(l.id));
    assert.equal(store.milestones(b.id).length, 1);
  });

  test("updateBag: Status „fertig“ schreibt ins Logbuch; leerer Name wird ignoriert", () => {
    const b = store.addBag({ name: "Launch" });
    store.updateBag(b.id, { status: "fertig", name: "" });
    assert.equal(store.bag(b.id).name, "Launch");
    assert.equal(store.bag(b.id).status, "fertig");
    assert.match(store.logEntries(1)[0].text, /fertig/);
  });
});

// ---------- Aufgaben ----------
describe("Aufgaben", () => {
  test("addTask: Titel Pflicht (deutsche Meldung), Standardwerte, Eingang", () => {
    assert.throws(() => store.addTask({ title: "  " }), /Titel/);
    const t = store.addTask({ title: "  Stripe-Links eintragen  " });
    assert.equal(t.title, "Stripe-Links eintragen");
    assert.equal(t.bag, null);
    assert.equal(t.done, null);
    assert.equal(t.prio, 0);
    assert.deepEqual(t.tags, []);
    assert.deepEqual(t.subtasks, []);
    assert.equal(t.someday, false);
    assert.equal(t.waiting, "");
    assert.equal(t.deleted, null);
    assert.equal(store.tasksOf(null).length, 1);
  });

  test("addTask übernimmt ein parseQuick-Ergebnis direkt (plan: true → heute, Tokens werden ignoriert)", () => {
    const b = store.addBag({ name: "Zahlungen", sections: ["Stripe-Konto"] });
    const t = store.addTask({ title: "Webhook", bag: b.id, plan: true, tokens: [{ type: "date" }], bagName: "Zahlungen", section: "stripe-konto", tags: ["#mac", "Mac", "@home"], subtasks: ["A", "", "B"] });
    assert.equal(t.plan, today());
    assert.equal(t.tokens, undefined);
    assert.equal(t.bagName, undefined);
    assert.equal(t.section, "Stripe-Konto"); // Schreibweise der Tasche
    assert.deepEqual(t.tags, ["mac", "home"]);
    assert.deepEqual(t.subtasks.map((s) => s.title), ["A", "B"]);
    assert.equal(store.addTask({ title: "X", bag: "gibts-nicht" }).bag, null);
  });

  test("neuer Abschnitt wird in der Tasche angelegt", () => {
    const b = store.addBag({ name: "Marketing" });
    store.addTask({ title: "Reel", bag: b.id, section: "Clips" });
    assert.deepEqual(store.bag(b.id).sections, ["Clips"]);
  });

  test("updated ist monoton – auch bei Änderungen in derselben Millisekunde", () => {
    const t = store.addTask({ title: "A" });
    let last = t.updated;
    for (let i = 0; i < 20; i++) {
      store.updateTask(t.id, { title: "A" + i });
      assert.ok(store.task(t.id).updated > last);
      last = store.task(t.id).updated;
    }
  });

  test("updateTask ohne echte Änderung erzeugt keinen Rückgängig-Schritt und kein Ereignis", () => {
    const t = store.addTask({ title: "A", prio: 2 });
    const before = t.updated;
    let events = 0;
    const off = store.subscribe(() => events++);
    store.updateTask(t.id, { prio: 2, title: "A" });
    off();
    assert.equal(events, 0);
    assert.equal(store.task(t.id).updated, before);
    assert.equal(store.undo(), "Aufgabe hinzugefügt");
  });

  test("updateTask: geschützte Felder bleiben, Werte werden geprüft", () => {
    const t = store.addTask({ title: "A" });
    store.updateTask(t.id, { id: "boese", created: 1, prio: 7, due: "2026-02-31", time: "25:00", est: -5, remind: -9 });
    const x = store.task(t.id);
    assert.equal(x.id, t.id);
    assert.notEqual(x.created, 1);
    assert.equal(x.prio, 3);
    assert.equal(x.due, null);
    assert.equal(x.time, null);
    assert.equal(x.est, 1);
    assert.equal(x.remind, -1);
  });

  test("completeTask ohne Wiederholung: done, Unteraufgaben abgehakt, Logbuch „done“", () => {
    const t = store.addTask({ title: "Domain", subtasks: ["DNS", "HTTPS"] });
    const r = store.completeTask(t.id);
    assert.equal(r.next, null);
    assert.ok(r.task.done > 0);
    assert.ok(r.task.subtasks.every((s) => s.done));
    assert.equal(store.logEntries(1)[0].kind, "done");
    assert.match(store.logEntries(1)[0].text, /„Domain“ erledigt/);
    assert.equal(store.completeTask(t.id).next, null); // doppelt erledigen ändert nichts
  });

  test("completeTask mit Wiederholung: Folge-Aufgabe mit nächstem Termin, Unteraufgaben zurückgesetzt, plan leer", () => {
    const due = addDays(today(), 2);
    const t = store.addTask({ title: "Wochenplanung", repeat: "weekly", due, time: "08:00", plan: true, subtasks: ["Ziele"], prio: 2 });
    const { next } = store.completeTask(t.id);
    assert.ok(next);
    assert.notEqual(next.id, t.id);
    assert.equal(next.due, addDays(due, 7));
    assert.equal(next.time, "08:00");
    assert.equal(next.prio, 2);
    assert.equal(next.plan, null);
    assert.equal(next.done, null);
    assert.deepEqual(next.subtasks.map((s) => [s.title, s.done]), [["Ziele", false]]);
    assert.notEqual(next.subtasks[0].id, t.subtasks[0].id);
  });

  test("überfällige tägliche Aufgabe springt beim Erledigen auf morgen (nicht auf gestern+1)", () => {
    const t = store.addTask({ title: "Wasser", repeat: "daily", due: addDays(today(), -5) });
    assert.equal(store.completeTask(t.id).next.due, addDays(today(), 1));
  });

  test("monatlich am 31.: Februar wird geklammert, März kehrt zum 31. zurück", () => {
    const t = store.addTask({ title: "Miete", repeat: "monthly", due: "2031-01-31" });
    const n1 = store.completeTask(t.id).next;
    assert.equal(n1.due, "2031-02-28");
    assert.equal(n1.repeatDay, 31);
    const n2 = store.completeTask(n1.id).next;
    assert.equal(n2.due, "2031-03-31");
    assert.equal(n2.repeatDay, undefined);
    store.updateTask(n2.id, { due: "2031-04-15" });
    assert.equal(store.completeTask(n2.id).next.due, "2031-05-15");
  });

  test("Erledigen rückgängig: Aufgabe wieder offen, Folge-Aufgabe weg, Logbuch-Eintrag entfernt", () => {
    const t = store.addTask({ title: "Retro", repeat: "weekly", due: addDays(today(), 1) });
    const { next } = store.completeTask(t.id);
    assert.equal(store.undo(), "Aufgabe erledigt");
    assert.equal(store.task(t.id).done, null);
    assert.equal(store.task(next.id), null);
    assert.equal(store.logEntries(10).some((e) => e.kind === "done"), false);
  });

  test("toggleTask / reopenTask: Wiederöffnen entfernt die unberührte Folge-Aufgabe", () => {
    const t = store.addTask({ title: "Standup", repeat: "daily", due: today() });
    const r1 = store.toggleTask(t.id);
    assert.equal(r1.done, true);
    assert.ok(r1.next);
    const r2 = store.toggleTask(t.id);
    assert.equal(r2.done, false);
    assert.equal(store.task(t.id).done, null);
    assert.equal(store.task(r1.next.id), null);
    assert.equal(store.task(t.id).repeat, "daily");
    assert.equal(live(store.get().tasks).filter((x) => x.title === "Standup").length, 1);
  });

  test("reopenTask: wurde die Folge-Aufgabe bearbeitet, läuft die Serie dort weiter", () => {
    const t = store.addTask({ title: "Report", repeat: "weekly", due: today() });
    const { next } = store.completeTask(t.id);
    store.updateTask(next.id, { notes: "angepasst" });
    store.reopenTask(t.id);
    assert.ok(store.task(next.id));
    assert.equal(store.task(t.id).repeat, null);
  });

  test("removeTask: Grabstein, Live-Listen ohne, Rückgängig mit neuerem Zeitstempel", () => {
    const t = store.addTask({ title: "Weg damit" });
    store.removeTask(t.id);
    const tomb = { ...store.get().tasks.find((x) => x.id === t.id) };
    assert.ok(tomb.deleted);
    assert.equal(store.task(t.id), null);
    assert.equal(store.tasks().length, 0);
    assert.equal(store.undo(), "Aufgabe gelöscht");
    const back = store.task(t.id);
    assert.ok(back);
    assert.equal(back.deleted, null);
    assert.ok(back.updated > tomb.updated);
  });

  test("moveTask: Tasche + Abschnitt, Ende der Liste, Logbuch „move“", () => {
    const a = store.addBag({ name: "A" });
    const b = store.addBag({ name: "B" });
    store.addTask({ title: "b1", bag: b.id });
    store.addTask({ title: "b2", bag: b.id });
    const t = store.addTask({ title: "wandert", bag: a.id });
    store.moveTask(t.id, b.id, "Neu");
    const x = store.task(t.id);
    assert.equal(x.bag, b.id);
    assert.equal(x.section, "Neu");
    assert.deepEqual(store.tasksOf(b.id).map((y) => y.title), ["b1", "b2", "wandert"]);
    assert.ok(store.bag(b.id).sections.includes("Neu"));
    assert.equal(store.logEntries(1)[0].kind, "move");
    store.moveTask(t.id, null);
    assert.equal(store.task(t.id).bag, null);
    assert.equal(store.task(t.id).section, "");
  });

  test("reorderTask: Kommazahlen zwischen Nachbarn, ans Ende, Neu-Nummerierung bei Gleichstand", () => {
    const a = store.addTask({ title: "a" });
    const b = store.addTask({ title: "b" });
    const c = store.addTask({ title: "c" });
    store.reorderTask(c.id, b.id);
    assert.deepEqual(store.tasksOf(null).map((x) => x.title), ["a", "c", "b"]);
    store.reorderTask(a.id, null);
    assert.deepEqual(store.tasksOf(null).map((x) => x.title), ["c", "b", "a"]);
    store.reorderTask(a.id, c.id);
    assert.deepEqual(store.tasksOf(null).map((x) => x.title), ["a", "c", "b"]);
    // Gleichstand erzwingen
    store.updateTask(c.id, { order: 5 });
    store.updateTask(b.id, { order: 5 });
    store.updateTask(a.id, { order: 1 });
    store.reorderTask(a.id, b.id);
    const order = store.tasksOf(null).map((x) => x.title);
    assert.equal(order.indexOf("a"), order.indexOf("b") - 1);
  });

  test("planTask: einplanen, true = heute, null = ausplanen; holt aus „Irgendwann“", () => {
    const t = store.addTask({ title: "Später", someday: true });
    store.planTask(t.id, true);
    assert.equal(store.task(t.id).plan, today());
    assert.equal(store.task(t.id).someday, false);
    store.planTask(t.id, "2026-12-24");
    assert.equal(store.task(t.id).plan, "2026-12-24");
    store.planTask(t.id, null);
    assert.equal(store.task(t.id).plan, null);
  });

  test("Unteraufgaben: hinzufügen, abhaken, umbenennen, löschen", () => {
    const t = store.addTask({ title: "Notar vorbereiten" });
    const s1 = store.addSubtask(t.id, " Firmenname ");
    const s2 = store.addSubtask(t.id, "Sitz");
    assert.equal(s1.title, "Firmenname");
    assert.throws(() => store.addSubtask(t.id, " "), /Titel/);
    store.toggleSubtask(t.id, s1.id);
    assert.equal(store.task(t.id).subtasks[0].done, true);
    store.updateSubtask(t.id, s2.id, "Sitz Hamburg");
    assert.equal(store.task(t.id).subtasks[1].title, "Sitz Hamburg");
    store.removeSubtask(t.id, s1.id);
    assert.deepEqual(store.task(t.id).subtasks.map((s) => s.title), ["Sitz Hamburg"]);
  });

  test("Tasche wechseln per updateTask: alter Abschnitt fällt weg, neuer wird übernommen", () => {
    const a = store.addBag({ name: "A", sections: ["Alt"] });
    const b = store.addBag({ name: "B", sections: ["Ziel"] });
    const t = store.addTask({ title: "x", bag: a.id, section: "Alt" });
    store.updateTask(t.id, { bag: b.id });
    assert.equal(store.task(t.id).section, "");
    assert.deepEqual(store.bag(b.id).sections, ["Ziel"]);
    store.updateTask(t.id, { bag: a.id, section: "alt" });
    assert.equal(store.task(t.id).section, "Alt");
    assert.equal(store.logEntries(1)[0].kind, "move");
  });

  test("Schnellerfassung → addTask: parseQuick-Ergebnis lässt sich direkt speichern", async () => {
    const { parseQuick } = await import("../js/dates.js");
    const b = store.addBag({ name: "Firmengründung", sections: ["Notar"] });
    const r = parseQuick("Notar anrufen morgen 9 Uhr #Gründ/notar !! ~15m * @Telefon", { bags: store.bags() });
    const t = store.addTask(r);
    assert.equal(t.title, "Notar anrufen");
    assert.equal(t.bag, b.id);
    assert.equal(t.section, "Notar");
    assert.equal(t.time, "09:00");
    assert.equal(t.prio, 2);
    assert.equal(t.est, 15);
    assert.equal(t.plan, today());
    assert.deepEqual(t.tags, ["Telefon"]);
    assert.equal(t.tokens, undefined);
  });

  test("duplicateTask: neue id, nicht erledigt, Unteraufgaben offen", () => {
    const t = store.addTask({ title: "Vorlage", subtasks: ["x"], prio: 3 });
    store.completeTask(t.id);
    const c = store.duplicateTask(t.id);
    assert.notEqual(c.id, t.id);
    assert.equal(c.done, null);
    assert.equal(c.prio, 3);
    assert.equal(c.subtasks[0].done, false);
  });
});

// ---------- Notizen, Links, Meilensteine ----------
describe("Notizen, Links, Meilensteine", () => {
  test("Notizen anlegen, ändern, löschen; angepinnte zuerst", () => {
    const a = store.addNote({ title: "A", body: "x" });
    const b = store.addNote({ title: "B", pinned: true });
    assert.deepEqual(store.notes().map((n) => n.title), ["B", "A"]);
    store.updateNote(a.id, { body: "**fett**" });
    assert.equal(store.note(a.id).body, "**fett**");
    store.removeNote(b.id);
    assert.equal(store.notes().length, 1);
  });

  test("Links: nur echte Adressen, Domain ohne Schema wird ergänzt, Titel aus Domain", () => {
    const l = store.addLink({ url: "notar.de/termin" });
    assert.equal(l.url, "https://notar.de/termin");
    assert.equal(l.title, "notar.de");
    assert.throws(() => store.addLink({ url: "javascript:alert(1)" }), /gültigen Link/);
    assert.throws(() => store.addLink({ url: "nur text" }), /gültigen Link/);
    assert.throws(() => store.updateLink(l.id, { url: "ftp://x" }), /gültigen Link/);
    store.updateLink(l.id, { title: "Notar" });
    assert.equal(store.link(l.id).title, "Notar");
    store.removeLink(l.id);
    assert.equal(store.links().length, 0);
  });

  test("Meilensteine: nach Datum sortiert, abhaken mit Logbuch, Löschen entknüpft Aufgaben", () => {
    const b = store.addBag({ name: "Launch" });
    const m2 = store.addMilestone({ bag: b.id, title: "Go-Live", date: "2026-12-01" });
    const m1 = store.addMilestone({ bag: b.id, title: "Beta", date: "2026-11-01" });
    store.addMilestone({ bag: b.id, title: "Irgendwann" });
    assert.deepEqual(store.milestones(b.id).map((m) => m.title), ["Beta", "Go-Live", "Irgendwann"]);
    assert.throws(() => store.addMilestone({ bag: b.id, title: "" }), /Titel/);
    store.toggleMilestone(m1.id);
    assert.ok(store.milestones(b.id)[0].done);
    assert.match(store.logEntries(1)[0].text, /Meilenstein „Beta“ erreicht/);
    const t = store.addTask({ title: "Server", bag: b.id, milestone: m2.id });
    store.removeMilestone(m2.id);
    assert.equal(store.task(t.id).milestone, null);
    assert.equal(store.milestones(b.id).length, 2);
  });
});

// ---------- Rückgängig ----------
describe("Rückgängig", () => {
  test("Beschriftungen, canUndo, leerer Stapel → null", () => {
    assert.equal(store.canUndo(), false);
    assert.equal(store.undo(), null);
    const t = store.addTask({ title: "A" });
    store.completeTask(t.id);
    assert.equal(store.canUndo(), true);
    assert.equal(store.undoLabel(), "Aufgabe erledigt");
    assert.equal(store.undo(), "Aufgabe erledigt");
    assert.equal(store.undo(), "Aufgabe hinzugefügt");
    assert.equal(store.task(t.id), null);
    assert.equal(store.canUndo(), false);
  });

  test("höchstens LIMITS.undoMax Schritte", () => {
    for (let i = 0; i < LIMITS.undoMax + 10; i++) store.addTask({ title: "T" + i });
    let n = 0;
    while (store.undo()) n++;
    assert.equal(n, LIMITS.undoMax);
    assert.equal(store.tasks().length, 10);
  });

  test("Tippen im Titel wird zu einem Schritt zusammengefasst", () => {
    const t = store.addTask({ title: "S" });
    for (const s of ["St", "Str", "Stri", "Strip", "Stripe"]) store.updateTask(t.id, { title: s });
    assert.equal(store.undo(), "Aufgabe geändert");
    assert.equal(store.task(t.id).title, "S");
  });

  test("Fehler mitten in einer Aktion rollt Teiländerungen zurück", () => {
    const t = store.addTask({ title: "A" });
    assert.throws(() => store.addTask({ title: "" }));
    assert.equal(store.tasks().length, 1);
    assert.equal(store.undoLabel(), "Aufgabe hinzugefügt");
    assert.ok(store.task(t.id));
  });
});

// ---------- Ereignisse ----------
describe("subscribe", () => {
  test("Listener bekommen (state, change); ein werfender Listener blockiert die anderen nicht", () => {
    const seen = [];
    const off1 = store.subscribe(() => {
      throw new Error("kaputt");
    });
    const off2 = store.subscribe((s, c) => seen.push(c));
    const origErr = console.error;
    console.error = () => {};
    try {
      const t = store.addTask({ title: "A" });
      store.updateTask(t.id, { prio: 3 });
      store.removeTask(t.id);
      store.undo();
    } finally {
      console.error = origErr;
      off1();
      off2();
    }
    assert.deepEqual(seen.map((c) => [c.type, c.action, c.local]), [["task", "add", true], ["task", "update", true], ["task", "remove", true], ["all", "undo", true]]);
    assert.ok(seen[0].id);
  });

  test("unsubscribe beendet die Benachrichtigung; setMeta meldet local: false", () => {
    const seen = [];
    const off = store.subscribe((s, c) => seen.push(c));
    store.setMeta({ lastSync: Date.now() });
    store.setProfile({ name: "Leo" });
    off();
    store.addTask({ title: "danach" });
    assert.deepEqual(seen.map((c) => [c.type, c.local]), [["meta", false], ["profile", true]]);
    assert.ok(store.get().profile.updated > 0);
  });

  test("load meldet { type: all, action: load, local: false }", async () => {
    const seen = [];
    const off = store.subscribe((s, c) => seen.push(c));
    await store.load({ memory: true });
    off();
    assert.deepEqual(seen, [{ type: "all", action: "load", local: false }]);
  });
});

// ---------- Sync ----------
describe("merge (Last-Writer-Wins)", () => {
  const base = () => store.addTask({ title: "Lokal" });

  test("neuere Fassung von außen gewinnt, ältere wird ignoriert, Gleichstand bleibt lokal", () => {
    const t = base();
    assert.equal(store.merge({ tasks: [{ ...t, title: "Alt", updated: t.updated - 1 }] }).changed, false);
    assert.equal(store.merge({ tasks: [{ ...t, title: "Gleich", updated: t.updated }] }).changed, false);
    assert.equal(store.task(t.id).title, "Lokal");
    assert.equal(store.merge({ tasks: [{ ...t, title: "Neu", updated: t.updated + 1000 }] }).changed, true);
    assert.equal(store.task(t.id).title, "Neu");
  });

  test("neue Einträge kommen dazu; Ereignis { all, merge, local: false }; merge erzeugt keinen Rückgängig-Schritt", () => {
    const seen = [];
    const off = store.subscribe((s, c) => seen.push(c));
    const now = Date.now();
    store.merge({ bags: [{ id: "b-remote", name: "Remote", created: now, updated: now, deleted: null }], tasks: [{ id: "t-remote", title: "Von iPhone", bag: "b-remote", created: now, updated: now, deleted: null }] });
    off();
    assert.ok(store.bag("b-remote"));
    assert.equal(store.tasksOf("b-remote")[0].title, "Von iPhone");
    assert.deepEqual(seen, [{ type: "all", action: "merge", local: false }]);
    assert.equal(store.canUndo(), false);
  });

  test("Grabstein gewinnt, wenn er neuer ist – und verliert, wenn die lokale Änderung neuer ist", () => {
    const t = base();
    store.merge({ tasks: [{ ...t, deleted: t.updated + 5, updated: t.updated + 5 }] });
    assert.equal(store.task(t.id), null);
    const u = store.addTask({ title: "Bleibt" });
    store.updateTask(u.id, { title: "Bleibt (bearbeitet)" });
    const local = store.task(u.id).updated;
    store.merge({ tasks: [{ ...u, deleted: local - 10, updated: local - 10 }] });
    assert.ok(store.task(u.id));
  });

  test("uralte Grabsteine werden nicht übernommen und lokal aufgeräumt", () => {
    const old = Date.now() - (LIMITS.tombstoneDays + 1) * DAY;
    store.merge({ tasks: [{ id: "t-old", title: "Uralt", created: old, updated: old, deleted: old }] });
    assert.equal(store.get().tasks.some((x) => x.id === "t-old"), false);
    const t = base();
    store.removeTask(t.id);
    const tomb = store.get().tasks.find((x) => x.id === t.id);
    tomb.deleted = old; // künstlich altern lassen
    store.merge({ tasks: [] , log: [{ id: "e-x", t: 1, kind: "sync", text: "x" }] });
    assert.equal(store.get().tasks.some((x) => x.id === t.id), false);
  });

  test("Profil per LWW, Logbuch als Vereinigung (max. LIMITS.logMax)", () => {
    store.setProfile({ name: "Lokal" });
    const p = store.get().profile;
    store.merge({ profile: { ...p, name: "Alt", updated: p.updated - 1 } });
    assert.equal(store.get().profile.name, "Lokal");
    store.merge({ profile: { ...p, name: "Leo", updated: p.updated + 1 } });
    assert.equal(store.get().profile.name, "Leo");
    const log = Array.from({ length: LIMITS.logMax + 50 }, (_, i) => ({ id: "e" + i, t: i + 1, kind: "add", text: "x" + i }));
    store.merge({ log });
    assert.equal(store.get().log.length, LIMITS.logMax);
    assert.equal(store.logEntries(1)[0].id, "e" + (LIMITS.logMax + 49));
  });

  test("Rückgängig nach einem Sync gewinnt gegen die synchronisierte Fassung", () => {
    const t = base();
    store.completeTask(t.id);
    const remoteDone = { ...store.task(t.id), updated: store.task(t.id).updated + 50 };
    store.merge({ tasks: [remoteDone] });
    store.undo();
    const restored = store.task(t.id);
    assert.equal(restored.done, null);
    assert.ok(restored.updated > remoteDone.updated);
    store.merge({ tasks: [remoteDone] }); // erneut eintreffende alte Fassung ändert nichts
    assert.equal(store.task(t.id).done, null);
  });

  test("syncPayload enthält Grabsteine und ist eine Kopie", () => {
    const t = base();
    store.removeTask(t.id);
    const p = store.syncPayload();
    assert.deepEqual(Object.keys(p).sort(), ["bags", "files", "links", "log", "milestones", "notes", "profile", "tasks", "v"]);
    assert.ok(p.tasks.find((x) => x.id === t.id).deleted);
    p.tasks[0].title = "verändert";
    assert.notEqual(store.get().tasks[0].title, "verändert");
  });

  test("zwei Geräte laufen per merge zusammen (Rundreise über syncPayload)", () => {
    const a = store.addTask({ title: "von A" });
    const payloadA = store.syncPayload();
    const remoteNow = Date.now() + 10;
    const payloadB = { tasks: [{ id: "t-b", title: "von B", created: remoteNow, updated: remoteNow, deleted: null }, { ...a, title: "A, auf B bearbeitet", updated: a.updated + 100 }] };
    store.merge(payloadB);
    store.merge(payloadA); // eigenes, älteres Echo ändert nichts
    assert.deepEqual(store.tasks().map((t) => t.title).sort(), ["A, auf B bearbeitet", "von B"]);
  });
});

// ---------- Dateien ----------
describe("Dateien", () => {
  test("addFile speichert Inhalt + Metadaten, fileBlob liefert ihn zurück", async () => {
    const b = store.addBag({ name: "Docs" });
    const f = await store.addFile(b.id, new File(["Hallo Welt"], "notiz.txt", { type: "text/plain" }));
    assert.equal(f.name, "notiz.txt");
    assert.equal(f.size, 10);
    assert.equal(f.synced, false);
    assert.equal(await (await store.fileBlob(f.id)).text(), "Hallo Welt");
    assert.equal(store.files().length, 1);
    store.removeFile(f.id);
    assert.equal(store.file(f.id), null);
    store.undo();
    assert.ok(store.file(f.id));
    assert.equal(await store.fileBlob("gibts-nicht"), null);
  });

  test("zu große Datei → deutsche Fehlermeldung", async () => {
    const big = { name: "film.mov", size: LIMITS.fileMax + 1, type: "video/quicktime" };
    await assert.rejects(store.addFile(null, big), /zu groß.*höchstens 25 MB/);
    await assert.rejects(store.addFile(null, null), /keine Datei/);
  });

  test("updateFile: umbenennen und verschieben, rückgängig machbar", async () => {
    const b = store.addBag({ name: "Docs" });
    const f = await store.addFile(null, new File(["x"], "scan.pdf", { type: "application/pdf" }));
    store.updateFile(f.id, { name: "  Vertrag.pdf ", bag: b.id });
    assert.equal(store.file(f.id).name, "Vertrag.pdf");
    assert.equal(store.file(f.id).bag, b.id);
    store.updateFile(f.id, { name: "" });
    assert.equal(store.file(f.id).name, "Vertrag.pdf");
    assert.equal(store.undo(), "Datei geändert");
    assert.equal(store.file(f.id).name, "scan.pdf");
  });

  test("putFileBlob (für Sync) und markFileSynced ändern updated nicht", async () => {
    const f = await store.addFile(null, new Blob(["x"]));
    const u = store.file(f.id).updated;
    store.markFileSynced(f.id);
    assert.equal(store.file(f.id).synced, true);
    assert.equal(store.file(f.id).updated, u);
    await store.putFileBlob(f.id, new Blob(["neu"]));
    assert.equal(await (await store.fileBlob(f.id)).text(), "neu");
  });
});

// ---------- Backup ----------
describe("Backup", () => {
  test("Export → Import (ersetzen) Rundreise inkl. Datei als base64", async () => {
    const b = store.addBag({ name: "AKYTEX", emoji: "🚀" });
    const t = store.addTask({ title: "Domain", bag: b.id, subtasks: ["DNS"] });
    store.addNote({ bag: b.id, title: "Roadmap", body: "Phase 1" });
    store.addLink({ bag: b.id, url: "https://github.com" });
    const bytes = new Uint8Array(70000).map((_, i) => i % 256); // > 0x8000, damit das Stückeln greift
    const f = await store.addFile(b.id, new File([bytes], "bild.bin", { type: "application/octet-stream" }));
    const blob = await store.exportBackup();
    assert.equal(blob.type, "application/json");
    const json = JSON.parse(await blob.text());
    assert.equal(json.app, "arbeitstaschen");
    assert.equal(json.v, 1);
    assert.match(json.exported, /^\d{4}-\d{2}-\d{2}T/);
    assert.equal(json.files.length, 1);
    assert.ok(store.get().meta.lastBackup > 0);

    await store.resetAll();
    await store.load({ memory: true });
    store.addTask({ title: "kommt weg" });
    const counts = await store.importBackup(blob, { mode: "replace" });
    assert.deepEqual(counts, { bags: 1, tasks: 1, notes: 1, links: 1, files: 1 });
    assert.deepEqual(store.tasks().map((x) => x.title), ["Domain"]);
    assert.equal(store.task(t.id).subtasks[0].title, "DNS");
    const back = new Uint8Array(await (await store.fileBlob(f.id)).arrayBuffer());
    assert.deepEqual(back, bytes);
    assert.equal(store.logEntries(1)[0].kind, "import");
  });

  test("Ersetzen setzt Grabsteine für alles, was nicht im Backup ist (damit es auch auf anderen Geräten verschwindet)", async () => {
    const keep = store.addTask({ title: "Behalten" });
    const keptAt = keep.updated;
    const text = await (await store.exportBackup({ includeFiles: false })).text();
    const extra = store.addTask({ title: "Später dazugekommen" });
    await store.importBackup(text, { mode: "replace" });
    assert.equal(store.task(extra.id), null);
    assert.ok(store.get().tasks.find((x) => x.id === extra.id).deleted);
    assert.ok(store.task(keep.id).updated > keptAt);
  });

  test("Zusammenführen behält lokale Neuerungen", async () => {
    const t = store.addTask({ title: "Original" });
    const text = await (await store.exportBackup()).text();
    store.updateTask(t.id, { title: "Neuer lokal" });
    store.addTask({ title: "Nur lokal" });
    await store.importBackup(text);
    assert.equal(store.task(t.id).title, "Neuer lokal");
    assert.equal(store.tasks().length, 2);
  });

  test("Prüfung mit deutschen Fehlermeldungen", async () => {
    await assert.rejects(store.importBackup("kein json"), /kein lesbares JSON/);
    await assert.rejects(store.importBackup(JSON.stringify({ app: "nova" })), /kein Arbeitstaschen-Backup/);
    await assert.rejects(store.importBackup(JSON.stringify({ app: "arbeitstaschen", v: 2, state: {} })), /neueren Version/);
    await assert.rejects(store.importBackup(JSON.stringify({ app: "arbeitstaschen", v: 1 })), /keine Daten/);
    await assert.rejects(store.importBackup(JSON.stringify({ app: "arbeitstaschen", v: 1, state: { tasks: "x" } })), /„Aufgaben“ ist keine Liste/);
    await assert.rejects(store.importBackup(JSON.stringify({ app: "arbeitstaschen", v: 1, state: {} }), { mode: "alles" }), /Import-Modus/);
    await assert.rejects(store.importBackup(42), /Backup-Datei/);
  });
});

// ---------- Startdaten ----------
describe("applySeed", () => {
  const SEED = {
    bags: [
      {
        name: "AKYTEX Plattform & Go-Live", emoji: "🚀", color: "blue", goal: "Startklar", milestones: [{ title: "Go-Live", dueIn: 14 }, { title: "Irgendwann", dueIn: null }],
        tasks: [
          { title: "Website startklar", notes: "", prio: 2, done: true, section: "Technik", subtasks: ["Header", "SEO"], dueIn: null, time: null },
          { title: "Domain verbinden", notes: "Pages", prio: 2, done: false, section: "Technik", subtasks: ["Domain wählen"], dueIn: 2, time: "10:00" },
          { title: "Login einführen", notes: "", prio: 3, done: false, section: "Backend", subtasks: [], dueIn: null, time: null },
        ],
        notes: [{ title: "Roadmap", body: "Phase 1" }], links: [{ title: "App", url: "https://georgleomaser-bit.github.io/website-test-demo-1/" }, { title: "Böse", url: "javascript:alert(1)" }],
      },
      { name: "NOVA", emoji: "✨", color: "purple", goal: "", sections: ["Produkt"], tasks: [{ title: "Datenschutz", prio: "hoch", done: false, section: "Recht" }], notes: [], links: [] },
    ],
  };

  test("wandelt das Seed-Format in Entitäten um (dueIn → Datum, done → vor ein paar Tagen, Abschnitte abgeleitet)", () => {
    const c = store.applySeed(SEED);
    assert.deepEqual(c, { bags: 2, tasks: 4, notes: 1, links: 1, milestones: 2 });
    const [aky, nova] = store.bags();
    assert.equal(aky.name, "AKYTEX Plattform & Go-Live");
    assert.deepEqual(aky.sections, ["Technik", "Backend"]);
    assert.deepEqual(nova.sections, ["Produkt", "Recht"]);
    const tasks = store.tasksOf(aky.id);
    const done = tasks.find((t) => t.title === "Website startklar");
    assert.ok(done.done < Date.now() - DAY && done.done > Date.now() - 10 * DAY);
    assert.ok(done.created < done.done);
    assert.ok(done.subtasks.every((s) => s.done));
    const dom = tasks.find((t) => t.title === "Domain verbinden");
    assert.equal(dom.due, addDays(today(), 2));
    assert.equal(dom.time, "10:00");
    assert.equal(dom.subtasks[0].done, false);
    assert.equal(tasks.find((t) => t.title === "Login einführen").due, null);
    assert.equal(store.tasksOf(nova.id)[0].prio, 3);
    assert.equal(store.milestones(aky.id)[0].date, addDays(today(), 14));
    assert.equal(store.get().meta.seeded, true);
    assert.equal(store.logEntries(1)[0].kind, "seed");
    assert.equal(store.canUndo(), false);
  });

  test("merge-Modus legt nichts doppelt an; replace ersetzt", () => {
    store.applySeed(SEED);
    store.addTask({ title: "Eigene Aufgabe" });
    const c = store.applySeed(SEED, { mode: "merge" });
    assert.deepEqual(c, { bags: 0, tasks: 0, notes: 0, links: 0, milestones: 0 });
    assert.equal(store.bags().length, 2);
    store.applySeed({ bags: [SEED.bags[1]] }, { mode: "replace" });
    assert.deepEqual(store.bags().map((b) => b.name), ["NOVA"]);
    assert.equal(store.tasks().some((t) => t.title === "Eigene Aufgabe"), false);
  });
});

// ---------- Logbuch, KV, Zurücksetzen ----------
describe("Logbuch, KV-Speicher, Zurücksetzen", () => {
  test("logEntries: neueste zuerst, Limit, Filter nach Tasche, addLog", () => {
    const b = store.addBag({ name: "A" });
    store.addTask({ title: "1", bag: b.id });
    store.addTask({ title: "2" });
    store.addLog("review", "Wochenrückblick erledigt");
    assert.equal(store.logEntries(1)[0].kind, "review");
    assert.equal(store.logEntries(2).length, 2);
    assert.deepEqual(store.logEntries(50, b.id).map((e) => e.kind), ["add", "bag"]);
  });

  test("kvGet/kvSet; „state“ ist geschützt", async () => {
    await store.kvSet("plan", { at: 1, items: [] });
    assert.deepEqual(await store.kvGet("plan"), { at: 1, items: [] });
    assert.equal(await store.kvGet("gibts-nicht"), undefined);
    await assert.rejects(store.kvSet("state", {}), /Store/);
  });

  test("resetAll löscht Daten und KV (außer Geräte-ID)", async () => {
    store.addTask({ title: "A" });
    await store.kvSet("sync", { enabled: true });
    await store.flush();
    await store.resetAll();
    assert.equal(store.tasks().length, 0);
    assert.equal(await store.kvGet("sync"), undefined);
    await store.load({ memory: true });
    assert.equal(store.tasks().length, 0);
    assert.match(store.deviceId(), /^d_/);
  });

  test("requestPersist ohne navigator.storage → false; storageInfo meldet den Speicher", async () => {
    assert.equal(await store.requestPersist(), false);
    assert.equal((await store.storageInfo()).kind, "memory");
  });
});
