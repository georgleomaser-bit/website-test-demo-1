// Geld-Akademie: jeden Tag eine 3-Minuten-Lektion mit Quiz, Streak, XP & Level, Wochen-Challenges und Abzeichen.
// Alles lokal im Browser – Finanzwissen für alle, auch ohne Trading.
const KEY = "akytex-academy";
export const LESSONS = [
  { id: "zins", t: "Zinseszins – dein stärkster Freund", icon: "🌱", body: ["Zinseszins heißt: Auch deine Erträge bringen wieder Erträge.", "100 € mit 6 % pro Jahr werden in 10 Jahren zu 179 €, in 40 Jahren zu 1.029 €.", "Das Wichtigste ist deshalb nicht der Betrag, sondern die Zeit: Wer früh anfängt, gewinnt."], q: [["Was ist beim Zinseszins am wichtigsten?", ["Viel Zeit", "Ein hoher Startbetrag", "Glück"], 0], ["Was passiert mit den Erträgen?", ["Sie werden wieder angelegt und bringen selbst Erträge", "Sie verfallen", "Sie gehen an die Bank"], 0]] },
  { id: "etf", t: "Was ist ein ETF?", icon: "🧺", body: ["Ein ETF ist ein Korb mit vielen Aktien – zum Beispiel alle 1.500 großen Firmen der Welt.", "Statt auf eine Firma zu setzen, besitzt du ein kleines Stück von allen.", "Das senkt das Risiko und kostet meist nur 0,1–0,3 % pro Jahr."], q: [["Was steckt in einem Welt-ETF?", ["Viele Firmen aus aller Welt", "Nur eine Firma", "Nur Gold"], 0], ["Warum ist ein ETF oft sicherer als eine Einzelaktie?", ["Das Risiko ist auf viele Firmen verteilt", "Er kann nicht fallen", "Der Staat garantiert ihn"], 0]] },
  { id: "risiko", t: "Rendite und Risiko gehören zusammen", icon: "⚖️", body: ["Mehr mögliche Rendite bedeutet fast immer mehr Schwankung.", "Tagesgeld schwankt kaum, bringt aber wenig. Aktien schwanken stark, bringen langfristig mehr.", "Wer dir hohe Rendite ohne Risiko verspricht, will meistens dein Geld."], q: [["Jemand verspricht 20 % im Monat ohne Risiko. Was ist das?", ["Sehr wahrscheinlich Betrug", "Ein guter Deal", "Normal an der Börse"], 0], ["Was schwankt meist stärker?", ["Aktien", "Tagesgeld", "Beides gleich"], 0]] },
  { id: "notgroschen", t: "Erst der Notgroschen", icon: "🛟", body: ["Bevor du investierst: Leg 3 Monatsausgaben als Notgroschen aufs Tagesgeld.", "Dann musst du nie Aktien im schlechtesten Moment verkaufen, wenn das Handy kaputtgeht.", "Investiert wird nur Geld, das du länger nicht brauchst."], q: [["Wofür ist der Notgroschen da?", ["Für unerwartete Ausgaben", "Zum Zocken", "Für Aktien"], 0], ["Wie viel ist eine gute Faustregel?", ["3 Monatsausgaben", "Ein Tagesgehalt", "Gar nichts"], 0]] },
  { id: "streuung", t: "Streuung: nicht alle Eier in einen Korb", icon: "🥚", body: ["Setzt du alles auf eine Aktie, kann eine schlechte Nachricht dein Depot halbieren.", "Verteilst du auf viele Firmen, Branchen und Länder, gleichen sich Ausreißer aus.", "Faustregel: keine Einzelposition über 10–15 % des Depots."], q: [["Was ist ein Klumpenrisiko?", ["Zu viel Geld in einer Position", "Zu viele verschiedene Aktien", "Ein Kontoführungsentgelt"], 0], ["Welche Obergrenze pro Aktie ist eine gute Faustregel?", ["10–15 %", "80 %", "100 %"], 0]] },
  { id: "stop", t: "Der Stop-Loss", icon: "🛑", body: ["Ein Stop-Loss verkauft automatisch, wenn der Kurs unter eine Grenze fällt.", "So begrenzt du Verluste, bevor sie groß werden – ohne ständig auf den Bildschirm zu schauen.", "Profis legen den Stop schon beim Kauf fest."], q: [["Was macht ein Stop-Loss?", ["Verkauft automatisch unter einer Grenze", "Kauft automatisch nach", "Stoppt die Börse"], 0], ["Wann setzen Profis den Stop?", ["Schon beim Kauf", "Nie", "Wenn es zu spät ist"], 0]] },
  { id: "inflation", t: "Inflation frisst Erspartes", icon: "🎈", body: ["Inflation heißt: Dinge werden teurer, dein Geld kann weniger kaufen.", "Bei 2 % Inflation sind 1.000 € nach 20 Jahren nur noch rund 670 € wert.", "Geld auf dem Girokonto verliert also leise an Wert – anlegen schützt davor."], q: [["Was passiert mit 1.000 € auf dem Girokonto bei Inflation?", ["Sie verlieren an Kaufkraft", "Sie werden mehr", "Nichts"], 0], ["Was schützt langfristig vor Inflation?", ["Geld sinnvoll anlegen", "Bargeld unter der Matratze", "Nichts tun"], 0]] },
  { id: "sparplan", t: "Der Sparplan", icon: "🔁", body: ["Ein Sparplan legt jeden Monat automatisch einen festen Betrag an – schon ab 1 €.", "Du kaufst mal teurer, mal billiger ein. Das glättet den Einstiegspreis (Durchschnittskosten).", "Das Beste: Du musst nicht über den perfekten Zeitpunkt nachdenken."], q: [["Was ist der Vorteil eines Sparplans?", ["Man muss den Markt nicht timen", "Er garantiert Gewinne", "Er ist nur für Reiche"], 0], ["Ab wie viel geht ein Sparplan oft?", ["Ab 1 €", "Ab 10.000 €", "Ab 1 Mio. €"], 0]] },
  { id: "gebuehren", t: "Kosten fressen Rendite", icon: "🧾", body: ["1 % Gebühren pro Jahr klingt wenig – kostet über 30 Jahre aber fast ein Viertel des Endbetrags.", "Achte auf Ordergebühren, Depotkosten und die laufenden Kosten (TER) von Fonds.", "Oft ist der günstigste Weg auch der beste."], q: [["Wie wirkt sich 1 % Kosten über 30 Jahre aus?", ["Kostet einen großen Teil des Endbetrags", "Merkt man gar nicht", "Bringt mehr Rendite"], 0], ["Wofür steht TER?", ["Laufende Kosten eines Fonds", "Ein Aktienindex", "Eine Steuer"], 0]] },
  { id: "emotion", t: "Gefühle sind teuer", icon: "🎢", body: ["Die meisten verkaufen aus Angst im Crash – und kaufen aus Gier ganz oben.", "Profis haben Regeln: Einstieg, Stop, Ziel – und halten sich daran.", "Deine Trader-DNA bei AKYTEX zeigt dir, wo deine Gefühle dich Geld kosten."], q: [["Was passiert oft im Crash?", ["Viele verkaufen aus Angst zum schlechtesten Zeitpunkt", "Alle kaufen günstig", "Nichts"], 0], ["Was hilft gegen Bauchentscheidungen?", ["Feste Regeln vorher", "Mehr Kaffee", "Öfter aufs Handy schauen"], 0]] },
  { id: "aktie", t: "Was ist eine Aktie?", icon: "🏢", body: ["Mit einer Aktie besitzt du ein kleines Stück einer Firma.", "Verdient die Firma mehr, steigt meist ihr Wert – und manchmal zahlt sie eine Dividende.", "Geht es ihr schlecht, kann der Kurs stark fallen."], q: [["Was besitzt du mit einer Aktie?", ["Ein Stück der Firma", "Einen Kredit an die Firma", "Einen Gutschein"], 0], ["Was ist eine Dividende?", ["Gewinnbeteiligung an Aktionäre", "Eine Strafgebühr", "Ein Kursrutsch"], 0]] },
  { id: "kgv", t: "Teuer oder günstig? Das KGV", icon: "🔍", body: ["Das Kurs-Gewinn-Verhältnis (KGV) sagt, wie viele Jahresgewinne du für die Aktie bezahlst.", "KGV 15 heißt: Du zahlst das 15-Fache des Jahresgewinns.", "Hohes KGV = hohe Erwartungen. Die müssen erst erfüllt werden."], q: [["KGV 30 bedeutet …", ["Man zahlt das 30-Fache des Jahresgewinns", "Die Aktie kostet 30 €", "30 % Rendite garantiert"], 0], ["Was zeigt ein hohes KGV meist?", ["Hohe Erwartungen an die Zukunft", "Dass die Firma pleite ist", "Nichts"], 0]] },
  { id: "schulden", t: "Konsumschulden zuerst tilgen", icon: "💳", body: ["Dispo und Ratenkäufe kosten oft 10–20 % Zinsen pro Jahr.", "Keine Anlage bringt sicher so viel – Schulden tilgen ist die beste Rendite.", "„Jetzt kaufen, später zahlen“ ist genau so ein teurer Kredit."], q: [["Was solltest du vor dem Investieren tun?", ["Teure Konsumschulden tilgen", "Einen Kredit aufnehmen", "Den Dispo ausreizen"], 0], ["Was ist „Buy now, pay later“?", ["Ein Kredit", "Geschenktes Geld", "Eine Aktie"], 0]] },
  { id: "budget", t: "Die 50-30-20-Regel", icon: "🥧", body: ["50 % deines Geldes für Fixes (Miete, Handy), 30 % für Wünsche, 20 % für dein Zukunfts-Ich.", "Als Schüler oder Azubi reicht schon: erst sparen, dann ausgeben.", "Richte einen Dauerauftrag direkt am Monatsanfang ein."], q: [["Wie viel sieht die Regel fürs Sparen vor?", ["20 %", "0 %", "90 %"], 0], ["Wann spart man am leichtesten?", ["Direkt am Monatsanfang automatisch", "Am Monatsende, was übrig bleibt", "Nie"], 0]] },
  { id: "krypto", t: "Krypto nüchtern betrachtet", icon: "🪙", body: ["Kryptowährungen schwanken extrem – minus 70 % in einem Jahr sind schon passiert.", "Sie bringen keine Gewinne wie Firmen, der Preis hängt an Angebot und Nachfrage.", "Wenn überhaupt: nur einen kleinen Teil, dessen Verlust du verkraftest."], q: [["Was stimmt bei Krypto?", ["Sehr hohe Schwankungen", "Garantierte Gewinne", "Keine Risiken"], 0], ["Wie viel sollte man, wenn überhaupt, anlegen?", ["Nur einen kleinen Teil", "Alles", "Mit Kredit"], 0]] },
  { id: "finfluencer", t: "Finfluencer richtig einordnen", icon: "📱", body: ["Viele Finanz-Accounts verdienen Provision, wenn du über ihren Link kaufst.", "Screenshots von Riesengewinnen zeigen nie die Verluste.", "Frag immer: Was verdient die Person an meiner Entscheidung?"], q: [["Was solltest du bei Finanz-Tipps im Netz fragen?", ["Was verdient die Person daran?", "Wie viele Follower hat sie?", "Nichts, einfach machen"], 0], ["Was zeigen Gewinn-Screenshots meist nicht?", ["Die Verluste", "Den Gewinn", "Das Datum"], 0]] },
  { id: "steuer", t: "Steuern auf Gewinne", icon: "🏛️", body: ["In Deutschland zahlst du auf Kapitalerträge rund 26 % Abgeltungsteuer.", "Mit dem Sparerpauschbetrag bleiben 1.000 € Gewinn pro Jahr steuerfrei.", "Dafür stellst du bei deinem Broker einen Freistellungsauftrag."], q: [["Wie viel Gewinn ist pro Jahr steuerfrei?", ["1.000 €", "0 €", "Alles"], 0], ["Womit nutzt man den Freibetrag?", ["Freistellungsauftrag", "Steuererklärung für Firmen", "Gar nicht"], 0]] },
  { id: "zeit", t: "Zeit im Markt schlägt Timing", icon: "⏳", body: ["Niemand trifft zuverlässig den tiefsten Punkt.", "Wer die 10 besten Börsentage verpasst, halbiert oft seine Rendite – und die liegen meist mitten in Krisen.", "Dabeibleiben ist wichtiger als der perfekte Einstieg."], q: [["Was ist langfristig meist wichtiger?", ["Lange investiert bleiben", "Den perfekten Tiefpunkt treffen", "Oft rein und raus"], 0], ["Wann liegen die besten Börsentage oft?", ["Mitten in Krisen", "Nur im Sommer", "Nie"], 0]] },
  { id: "ziel", t: "Ziele machen reich", icon: "🎯", body: ["„Mehr Geld“ ist kein Ziel. „10.000 € mit 25 für den Führerschein und das erste Auto“ schon.", "Ein Ziel mit Betrag und Datum verrät dir, wie viel du im Monat brauchst.", "Das Zukunfts-Ich in AKYTEX rechnet es dir aus."], q: [["Was macht ein gutes Finanz-Ziel aus?", ["Betrag und Datum", "Nur ein Gefühl", "Möglichst vage"], 0], ["Was verrät dir ein klares Ziel?", ["Wie viel du monatlich brauchst", "Die Lottozahlen", "Nichts"], 0]] },
  { id: "rebalance", t: "Rebalancing", icon: "🔄", body: ["Über die Zeit verschieben sich die Anteile in deinem Depot – Gewinner werden zu groß.", "Einmal im Jahr zurück auf die geplante Aufteilung bringen heißt Rebalancing.", "So verkaufst du automatisch etwas teuer und kaufst etwas günstig."], q: [["Was ist Rebalancing?", ["Zurück zur geplanten Aufteilung", "Alles verkaufen", "Nur noch Gewinner kaufen"], 0], ["Wie oft reicht oft?", ["Einmal im Jahr", "Jede Minute", "Nie"], 0]] },
  { id: "betrug", t: "Betrug erkennen", icon: "🚨", body: ["Warnzeichen: Zeitdruck, garantierte Gewinne, Anfrage per WhatsApp oder Instagram, Zahlung in Krypto.", "Seriöse Anbieter haben eine Aufsicht – in Deutschland die BaFin.", "Gib niemals Passwörter, TANs oder Kartendaten weiter."], q: [["Was ist ein Warnzeichen für Betrug?", ["Zeitdruck und garantierte Gewinne", "Ein Impressum", "Eine BaFin-Zulassung"], 0], ["Wer beaufsichtigt Finanzanbieter in Deutschland?", ["Die BaFin", "Instagram", "Niemand"], 0]] },
];

// Wochen-Challenges: jede Woche 3 aus diesem Pool, automatisch geprüft (ctx kommt aus der App)
export const CHALLENGES = [
  { id: "stops", t: "Setz bei 3 Käufen einen Stop-Loss", icon: "🛑", xp: 60, goal: 3, prog: (c) => c.buysWithStop },
  { id: "sectors", t: "Sei in 3 Branchen gleichzeitig investiert", icon: "🧩", xp: 50, goal: 3, prog: (c) => c.sectors },
  { id: "hold", t: "Halte eine Position mindestens 2 Tage", icon: "⏳", xp: 50, goal: 1, prog: (c) => c.heldTwoDays },
  { id: "lessons", t: "Schließe 5 Lektionen ab", icon: "📚", xp: 60, goal: 5, prog: (c) => c.lessonsWeek },
  { id: "future", t: "Triff dein Zukunfts-Ich", icon: "🔮", xp: 30, goal: 1, prog: (c) => c.futureVisits },
  { id: "league", t: "Handle in einer Liga", icon: "🏆", xp: 50, goal: 1, prog: (c) => c.leagueTrades },
  { id: "dna", t: "Lass deine Trader-DNA analysieren", icon: "🧬", xp: 30, goal: 1, prog: (c) => c.dnaViews },
  { id: "winner", t: "Schließe 2 Trades mit Gewinn ab", icon: "💚", xp: 60, goal: 2, prog: (c) => c.winsWeek },
  { id: "share", t: "Teile eine Story-Karte", icon: "📲", xp: 40, goal: 1, prog: (c) => c.shares },
];

// Abzeichen: einmal verdient, für immer
export const BADGES = [
  { id: "first-lesson", t: "Erste Lektion", icon: "🎓", when: (s) => s.done.length >= 1 },
  { id: "streak3", t: "3 Tage in Folge", icon: "🔥", when: (s) => s.best >= 3 },
  { id: "streak7", t: "7-Tage-Streak", icon: "⚡", when: (s) => s.best >= 7 },
  { id: "streak30", t: "30-Tage-Legende", icon: "👑", when: (s) => s.best >= 30 },
  { id: "all-lessons", t: "Geld-Profi (alle Lektionen)", icon: "🧠", when: (s) => s.done.length >= LESSONS.length },
  { id: "perfect", t: "5 Quiz fehlerfrei", icon: "💯", when: (s) => s.perfect >= 5 },
  { id: "first-trade", t: "Erster Trade", icon: "🚀", when: (s, c) => c.trades >= 1 },
  { id: "disciplined", t: "Disziplin-Score 70+", icon: "🧬", when: (s, c) => (c.dnaScore || 0) >= 70 },
  { id: "challenger", t: "3 Wochen-Challenges geschafft", icon: "🏅", when: (s) => s.challengesDone >= 3 },
  { id: "league-top", t: "Platz 1 in einer Liga", icon: "🥇", when: (s, c) => c.leagueFirst },
  { id: "future-me", t: "Zukunfts-Ich getroffen", icon: "🔮", when: (s, c) => c.futureVisits >= 1 || s.futureEver },
];

const LEVELS = [0, 100, 250, 450, 700, 1000, 1400, 1900, 2500, 3200, 4000];
const LEVEL_NAMES = ["Neuling", "Sparfuchs", "Planer", "Investor", "Stratege", "Profi", "Portfolio-Chef", "Markt-Kenner", "Vermögens-Architekt", "Legende", "Börsen-Guru"];

const dayKey = (d = new Date()) => d.toISOString().slice(0, 10);
export function weekKey(d = new Date()) {
  const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  const day = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - day);
  const y = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  return `${t.getUTCFullYear()}-W${Math.ceil(((t - y) / 86400000 + 1) / 7)}`;
}
// Montagsbeginn der aktuellen Woche (für Prüfungen „diese Woche“)
export function weekStart(d = new Date()) {
  const t = new Date(d);
  t.setHours(0, 0, 0, 0);
  t.setDate(t.getDate() - ((t.getDay() + 6) % 7));
  return t.getTime();
}

export function load() {
  const base = { xp: 0, done: [], streak: 0, best: 0, last: "", perfect: 0, badges: [], week: "", claimed: [], challengesDone: 0, lessonsWeek: 0, counters: {}, futureEver: false };
  try {
    return { ...base, ...JSON.parse(localStorage.getItem(KEY) || "{}") };
  } catch (_) {
    return base;
  }
}
export function save(s) {
  try {
    localStorage.setItem(KEY, JSON.stringify(s));
  } catch (_) {
    /* nur für diese Sitzung */
  }
}
// Wochenwechsel: Challenge-Fortschritt und Wochenzähler zurücksetzen
export function rollWeek(s) {
  const w = weekKey();
  if (s.week !== w) Object.assign(s, { week: w, claimed: [], lessonsWeek: 0, counters: {} });
  // Streak reißt, wenn gestern keine Lektion war
  const y = new Date();
  y.setDate(y.getDate() - 1);
  if (s.last && s.last !== dayKey() && s.last !== dayKey(y)) s.streak = 0;
  return s;
}
export const bump = (s, k, n = 1) => (s.counters[k] = (s.counters[k] || 0) + n);

// Lektion des Tages: die erste noch nicht erledigte (sonst Wiederholung nach Datum)
export function todays(s) {
  const open = LESSONS.filter((l) => !s.done.includes(l.id));
  if (open.length) return open[0];
  const n = Math.floor(Date.now() / 86400000);
  return LESSONS[n % LESSONS.length];
}
export const doneToday = (s) => s.last === dayKey();
// Quiz abgeschlossen → XP, Streak, Fortschritt
export function finishLesson(s, lesson, correct, total) {
  const first = !s.done.includes(lesson.id);
  if (first) s.done.push(lesson.id);
  let xp = 10 + correct * 10 + (correct === total ? 10 : 0);
  if (correct === total) s.perfect++;
  if (!doneToday(s)) {
    s.streak = (s.streak || 0) + 1;
    s.best = Math.max(s.best, s.streak);
    s.last = dayKey();
    xp += Math.min(50, s.streak * 5); // Streak-Bonus
  }
  s.lessonsWeek++;
  s.xp += xp;
  return xp;
}
export function level(xp) {
  let i = 0;
  while (i + 1 < LEVELS.length && xp >= LEVELS[i + 1]) i++;
  const next = LEVELS[i + 1];
  return { n: i + 1, name: LEVEL_NAMES[i], xp, from: LEVELS[i], to: next ?? null, pct: next ? (xp - LEVELS[i]) / (next - LEVELS[i]) : 1 };
}
// Die 3 Challenges dieser Woche – für alle gleich (aus der Kalenderwoche abgeleitet)
export function weekly() {
  const w = weekKey();
  let h = 0;
  for (const ch of w) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  const pool = CHALLENGES.slice();
  const out = [];
  while (out.length < 3) out.push(pool.splice(h % pool.length, 1)[0]), (h = (h * 1103515245 + 12345) >>> 0);
  return out;
}
export function challengeState(s, ctx) {
  return weekly().map((c) => {
    const v = Math.min(c.goal, c.prog({ ...ctx, ...s.counters, lessonsWeek: s.lessonsWeek }) || 0);
    return { ...c, v, done: v >= c.goal, claimed: s.claimed.includes(c.id) };
  });
}
export function claim(s, c) {
  if (s.claimed.includes(c.id) || !c.done) return 0;
  s.claimed.push(c.id);
  s.challengesDone++;
  s.xp += c.xp;
  return c.xp;
}
// Neue Abzeichen vergeben; gibt die neu verdienten zurück
export function award(s, ctx) {
  const fresh = BADGES.filter((b) => !s.badges.includes(b.id) && b.when(s, ctx));
  for (const b of fresh) {
    s.badges.push(b.id);
    s.xp += 25;
  }
  return fresh;
}
