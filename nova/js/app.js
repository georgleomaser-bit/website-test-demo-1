// NOVA – KI-Assistent zum Sprechen. Lokale Fähigkeiten laufen sofort und gratis im Browser;
// alles andere beantwortet Claude über den NOVA-Server (mit Websuche, Webseiten lesen, Fotos verstehen).
import { BRAND, PLANS, planById, STRIPE } from "./config.js";
import * as sk from "./skills.js";
import * as voice from "./voice.js";
import { createOrb } from "./orb.js";

const $ = (s, el = document) => el.querySelector(s);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const VERSION = "1.1";

// ---------- Server ----------
const API = new URL("api/", document.baseURI).href;
const srv = { on: false, ai: false, billing: false, plan: "free", used: 0, limit: 5 };
const token = () => sk.store.get("token", "");
async function call(method, path, body) {
  const t = token();
  const r = await fetch(API + path, { method, headers: { ...(t ? { Authorization: "Bearer " + t } : {}), ...(body ? { "Content-Type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || j.ok === false) throw Object.assign(new Error(j.msg || `Serverfehler (${r.status})`), { status: r.status });
  return j;
}
async function ensureAccount() {
  if (token()) return;
  const r = await call("POST", "session", {});
  sk.store.set("token", r.token);
}
async function connect() {
  if (/\.(github\.io|netlify\.app|vercel\.app)$/.test(location.hostname)) return;
  try {
    const h = await fetch(API + "health", { cache: "no-store" }).then((r) => r.json());
    if (h.service !== "nova") return;
    Object.assign(srv, { on: true, ai: !!h.ai, billing: !!h.billing, plan: h.plan || "free", limit: h.limit ?? 5 });
    if (token()) await refreshPlan();
  } catch (_) {
    /* ohne Server: lokale Fähigkeiten */
  }
  paintPlan();
}
async function refreshPlan() {
  try {
    const r = await call("GET", "me");
    Object.assign(srv, { plan: r.plan, used: r.used, limit: r.limit });
  } catch (e) {
    if (e.status === 401) sk.store.set("token", "");
  }
  paintPlan();
}

// ---------- Oberfläche ----------
const orb = createOrb($("#orb"));
const log = $("#log");
function setState(s, label) {
  orb.set(s);
  document.body.dataset.state = s;
  $("#state").textContent = label || { idle: voice.canListen ? "Tippe auf das Mikro und sprich" : "Schreib mir einfach", listen: "Ich höre zu …", think: "Ich denke nach …", speak: "", error: "" }[s] || "";
}
const caption = (t) => ($("#caption").textContent = t || "");
// Markdown wie bei Claude: Code-Blöcke (mit Kopieren), Tabellen, Überschriften, Listen, Zitate, Links
function inline(t) {
  return esc(t)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*(.+?)\*\*/g, "<b>$1</b>")
    .replace(/(^|[^*\w])\*([^*\n]+)\*(?![*\w])/g, "$1<i>$2</i>")
    .replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
}
function md(text) {
  const L = String(text || "").replace(/\r/g, "").split("\n");
  const out = [];
  let para = [];
  const flush = () => para.length && (out.push(`<p>${para.map(inline).join("<br>")}</p>`), (para = []));
  for (let i = 0; i < L.length; i++) {
    const line = L[i];
    const fence = line.match(/^\s*```\s*([\w+#.-]*)/);
    if (fence) {
      flush();
      const code = [];
      while (++i < L.length && !/^\s*```/.test(L[i])) code.push(L[i]);
      out.push(`<div class="code"><div class="code-h"><span>${esc(fence[1] || "Code")}</span><button type="button" data-copy-code>Kopieren</button></div><pre><code>${esc(code.join("\n"))}</code></pre></div>`);
      continue;
    }
    if (/^\s*\|.*\|\s*$/.test(line) && /^\s*\|?\s*:?-{2,}/.test(L[i + 1] || "")) {
      flush();
      const cells = (l) => l.trim().replace(/^\||\|$/g, "").split("|").map((c) => inline(c.trim()));
      const head = cells(line);
      i++;
      const rows = [];
      while (i + 1 < L.length && /^\s*\|.*\|\s*$/.test(L[i + 1])) rows.push(cells(L[++i]));
      out.push(`<div class="tbl"><table><thead><tr>${head.map((c) => `<th>${c}</th>`).join("")}</tr></thead><tbody>${rows.map((r) => `<tr>${r.map((c) => `<td>${c}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`);
      continue;
    }
    const h = line.match(/^(#{1,4})\s+(.*)/);
    if (h) {
      flush();
      out.push(`<h${h[1].length < 3 ? 3 : 4}>${inline(h[2])}</h${h[1].length < 3 ? 3 : 4}>`);
      continue;
    }
    if (/^\s*(---|\*\*\*)\s*$/.test(line)) {
      flush();
      out.push("<hr>");
      continue;
    }
    if (/^\s*>\s?/.test(line)) {
      flush();
      const q = [];
      for (; i < L.length && /^\s*>\s?/.test(L[i]); i++) q.push(L[i].replace(/^\s*>\s?/, ""));
      i--;
      out.push(`<blockquote>${q.map(inline).join("<br>")}</blockquote>`);
      continue;
    }
    const li = line.match(/^\s*([-*•]|\d+[.)])\s+(.*)/);
    if (li) {
      flush();
      const ordered = /\d/.test(li[1]);
      const items = [];
      for (; i < L.length; i++) {
        const m = L[i].match(/^\s*([-*•]|\d+[.)])\s+(.*)/);
        if (m && /\d/.test(m[1]) === ordered) items.push(`<li>${inline(m[2])}</li>`);
        else if (/^\s{2,}\S/.test(L[i]) && items.length) items[items.length - 1] = items[items.length - 1].replace(/<\/li>$/, `<br>${inline(L[i].trim())}</li>`);
        else break;
      }
      i--;
      out.push(ordered ? `<ol start="${parseInt(li[1], 10) || 1}">${items.join("")}</ol>` : `<ul>${items.join("")}</ul>`);
      continue;
    }
    if (!line.trim()) flush();
    else para.push(line);
  }
  flush();
  return out.join("");
}
// Zum Vorlesen: Code und Tabellen nicht vorlesen, Markdown-Zeichen weg
function forSpeech(text) {
  return String(text || "")
    .replace(/```[\s\S]*?(```|$)/g, " Den Code siehst du auf dem Bildschirm. ")
    .replace(/^\s*\|.*$/gm, "")
    .replace(/[#>*_`|]/g, "")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/\n{2,}/g, ". ")
    .replace(/\s+/g, " ")
    .trim();
}
function bubble(role, html, extra = "") {
  const el = document.createElement("div");
  el.className = `msg ${role}`;
  el.innerHTML = `<div class="bubble">${html}</div>${extra}`;
  log.appendChild(el);
  document.body.classList.add("has-log"); // Kern rückt nach oben, Platz fürs Gespräch
  el.scrollIntoView({ behavior: "smooth", block: "end" });
  $("#hello")?.remove();
  return el;
}
function toast(text) {
  const t = document.createElement("div");
  t.className = "toast";
  t.textContent = text;
  document.body.appendChild(t);
  requestAnimationFrame(() => t.classList.add("show"));
  setTimeout(() => (t.classList.remove("show"), setTimeout(() => t.remove(), 400)), 3200);
}
function chime() {
  if (voice.IOS) return;
  try {
    const c = (chime.ctx ||= new (window.AudioContext || window.webkitAudioContext)());
    const t = c.currentTime;
    for (const [f, d] of [
      [660, 0],
      [990, 0.16],
    ]) {
      const o = c.createOscillator();
      const g = c.createGain();
      o.frequency.value = f;
      g.gain.setValueAtTime(0.0001, t + d);
      g.gain.exponentialRampToValueAtTime(0.08, t + d + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, t + d + 0.3);
      o.connect(g).connect(c.destination);
      o.start(t + d);
      o.stop(t + d + 0.32);
    }
  } catch (_) {
    /* ohne Ton */
  }
}

// ---------- Sprechen ----------
let talking = false; // Gesprächsmodus: nach jeder Antwort wieder zuhören
async function say(text) {
  if (!text) return;
  setState("speak");
  caption("");
  const ok = await voice.speak(text.slice(0, 900), {
    onStart: (s) => {
      caption(s);
      orb.kick();
    },
    onBoundary: () => orb.kick(0.5),
    onFail: () => {
      caption(text.slice(0, 300));
      if (!say.hinted) toast(voice.IOS ? "Kein Ton? Lautstärke hoch und Stumm-Schalter aus." : "Dein Browser lässt mich gerade nicht sprechen.");
      say.hinted = true;
    },
  });
  caption("");
  setState("idle");
  return ok;
}
async function listenOnce(fromTap) {
  voice.unlock();
  setState("listen");
  caption("");
  const r = await voice.listen({ fromTap, onInterim: (t) => (caption(t), orb.kick(0.6)) });
  caption("");
  if (r.text) return ask(r.text, { spoken: true });
  talking = false;
  setState("idle", r.error === "needs-tap" ? "Tippe auf das Mikro und sprich" : r.error === "denied" ? "Mikrofon nicht erlaubt – schreib mir einfach" : undefined);
}

// ---------- Fragen beantworten ----------
let busy = false;
let pending = null; // angehängtes Foto oder PDF
// Blase, in die die Antwort live hineinläuft (wie bei Claude)
function liveBubble() {
  let el = null;
  let raf = 0;
  let last = "";
  const ensure = () => (el ||= bubble("nova", `<span class="typing"><i></i><i></i><i></i></span>`));
  return {
    start: ensure,
    update(text) {
      last = text;
      ensure();
      if (raf) return;
      raf = requestAnimationFrame(() => {
        raf = 0;
        el.querySelector(".bubble").innerHTML = md(last) + `<span class="cursor"></span>`;
        el.scrollIntoView({ block: "end" });
      });
    },
    done(html, extra = "", text = "") {
      cancelAnimationFrame(raf);
      ensure();
      el.querySelector(".bubble").innerHTML = html;
      if (extra) el.insertAdjacentHTML("beforeend", extra);
      if (text) {
        el.dataset.text = text;
        el.insertAdjacentHTML("beforeend", ACTS);
      }
      el.scrollIntoView({ behavior: "smooth", block: "end" });
    },
  };
}
const ACTS = `<div class="acts"><button type="button" data-copy title="Kopieren">⧉ Kopieren</button><button type="button" data-read title="Vorlesen">🔊 Vorlesen</button></div>`;
async function ask(text, { spoken = false } = {}) {
  text = String(text || "").trim();
  const file = pending;
  if ((!text && !file) || busy) return;
  busy = true;
  document.body.classList.add("busy");
  pending = null;
  paintAttach();
  bubble("user", `${file?.kind === "image" ? `<img class="thumb" src="${file.url}" alt="Foto">` : file ? `<span class="file-chip">📄 ${esc(file.name)}</span>` : ""}${esc(text)}`);
  setState("think");
  const live = liveBubble();
  let res;
  try {
    res = (!file && (await local(text))) || (srv.ai ? await llm(text, file, live) : offline(text, file));
  } catch (e) {
    res = { text: e.user ? e.message : `Das hat gerade nicht geklappt: ${e.message}` };
  }
  busy = false;
  document.body.classList.remove("busy");
  const extra = res.sources?.length ? `<div class="sources">${res.sources.slice(0, 5).map((s) => `<a href="${esc(s.url)}" target="_blank" rel="noopener">${esc(s.title || hostOf(s.url))}</a>`).join("")}</div>` : "";
  live.done((res.html || md(res.text || "")) + (res.card || ""), extra, res.text || "");
  saveChat(text || (file ? (file.kind === "pdf" ? "PDF" : "Foto") : ""), res.text || "");
  if (spoken || talking) {
    talking = spoken || talking;
    await say(res.speak || forSpeech(res.text));
    if (talking && voice.canListen && !voice.SAFARI) return listenOnce(false);
    if (talking && voice.SAFARI) setState("idle", "Tippe aufs Mikro, um weiterzureden");
  } else setState("idle");
}
const hostOf = (u) => {
  try {
    return new URL(u).hostname.replace(/^www\./, "");
  } catch (_) {
    return "Quelle";
  }
};

// Lokale Fähigkeiten – ohne Server, sofort
async function local(raw) {
  const t = raw.toLowerCase().replace(/[!?.]+$/g, "").trim();
  const p = sk.profile();
  const name = p.name ? `, ${p.name}` : "";
  // Anrede & Wohnort merken
  let m = t.match(/^(?:ich heiße|mein name ist|nenn mich)\s+([\p{L} -]{2,24})$/u);
  if (m) {
    const n = m[1].trim().replace(/^./, (c) => c.toUpperCase());
    sk.setProfile({ name: n });
    return { text: `Freut mich, ${n}! Ab jetzt nenne ich dich so.` };
  }
  m = t.match(/^(?:ich wohne in|ich lebe in|mein wohnort ist)\s+([\p{L} .-]{2,40})$/u);
  if (m) {
    const c = m[1].trim().replace(/(^|\s)\S/g, (x) => x.toUpperCase());
    sk.setProfile({ city: c });
    return { text: `Gemerkt: Du wohnst in ${c}. Beim Wetter nehme ich ab jetzt ${c}.` };
  }
  // Gedächtnis
  m = raw.match(/^(?:nova,?\s*)?(?:merk|merke|speicher|notier)\s+dir[,:]?\s*(?:bitte\s+)?(?:dass\s+)?(.{3,200})$/i);
  if (m) {
    sk.remember(m[1]);
    const dass = /\bdass\s/i.test(raw);
    return { text: `Alles klar${name}. Ich merke mir${dass ? ", dass" : ":"} ${sk.toYou(m[1].replace(/[.!]+$/, ""))}.` };
  }
  if (/(was weißt du (alles )?über mich|was hast du dir gemerkt)/.test(t)) {
    const list = sk.memory();
    return { text: list.length ? `Ich weiß über dich:\n${list.slice(-8).map((x) => `- ${sk.toYou(x.t)}`).join("\n")}` : "Noch nichts. Sag einfach „Merk dir, dass …“.", speak: list.length ? `Ich weiß: ${list.slice(-5).map((x) => sk.toYou(x.t)).join(". ")}.` : "" };
  }
  if (/^vergiss alles$/.test(t)) return sk.forget(), { text: "Erledigt – mein Gedächtnis über dich ist leer." };
  // Uhrzeit & Datum
  if (/^(wie spät|wieviel uhr|wie viel uhr|uhrzeit)/.test(t)) return { text: `Es ist ${sk.timeInfo().time} Uhr.` };
  if (/(welcher tag|welches datum|den wievielten|datum heute)/.test(t)) return { text: `Heute ist ${sk.timeInfo().date}.` };
  // Wetter
  if (/\b(wetter|regnet|regen|temperatur|wie warm|wie kalt|schirm|sonne scheint)\b/.test(t)) {
    const city = (t.match(/\b(?:in|für)\s+([\p{L}][\p{L} .-]{1,40}?)(?:\s+(?:heute|morgen|übermorgen))?$/u) || [])[1];
    const day = /übermorgen/.test(t) ? 2 : /morgen/.test(t) ? 1 : 0;
    return sk.weather({ city: city && !/^(der|die|das)$/.test(city) ? city : "", day });
  }
  // Timer & Erinnerungen
  m = raw.replace(/[!?.]+$/g, "").match(/(?:timer|wecker|erinner\w*(?: mich)?|sag mir bescheid)\D*?(\d+(?:[.,]\d+)?)\s*(sek\w*|min\w*|std|stunden?)\b(?:\s*(?:an|dass|zu|:)\s*(.+))?/i);
  if (m) {
    const n = parseFloat(m[1].replace(",", "."));
    const unit = m[2].toLowerCase();
    const mins = /^sek/.test(unit) ? n / 60 : /^(std|stunde)/.test(unit) ? n * 60 : n;
    const r = sk.addReminder(mins, m[3] ? `Erinnerung: ${m[3]}` : "Dein Timer ist abgelaufen");
    askNotify();
    paintSettings();
    return { text: `Okay${name}, ich melde mich ${sk.fmtIn(r.at - Date.now())}${m[3] ? ` – ${m[3]}` : ""}.` };
  }
  if (/(meine|welche) (timer|erinnerungen)/.test(t)) {
    const list = sk.reminders();
    return { text: list.length ? list.map((r) => `- ${r.text} (${sk.fmtIn(r.at - Date.now())})`).join("\n") : "Du hast gerade keine Timer oder Erinnerungen." };
  }
  // Ziel-Planer: „Mach mir 10k“, „Ich will 5.000 € sparen“, „mit 200 € im Monat“
  if (/(mach mir|ich will|ich möchte|ich muss|spar\w*|ziel)\b.*(\d|tausend|million|k\b)/.test(t) && /(k\b|tausend|million|€|euro|spar|ziel|geld|\d{4,})/.test(t) && !/gespart|zurückgelegt/.test(t)) {
    const target = sk.amount(t.replace(/mit\s+\d+.*?(monat|woche).*/, ""));
    const monthly = (t.match(/mit\s+(\d+(?:[.,]\d+)?)\s*(?:€|euro)?\s*(?:im|pro|jeden|je)\s*monat/) || [])[1];
    const years = (t.match(/in\s+(\d+)\s*jahr/) || [])[1];
    if (target && target >= 50) return sk.planGoal({ target, monthly: monthly ? parseFloat(monthly.replace(",", ".")) : 0, months: years ? +years * 12 : 0 });
  }
  m = t.match(/(?:ich habe|hab)\s+(\d+(?:[.,]\d+)?)\s*(?:€|euro)?\s*(?:gespart|zurückgelegt|beiseite gelegt)/);
  if (m) {
    const r = sk.addSaved(parseFloat(m[1].replace(",", ".")));
    return { text: r ? r.text : "Setz dir zuerst ein Ziel – zum Beispiel: „Ich will 10.000 Euro sparen.“" };
  }
  // Rechner
  if (/^(was ist|was sind|wie viel ist|wieviel ist|rechne|berechne)?\s*[\d(√]/.test(t) || /\b(prozent von|wurzel|geteilt durch|mal\b)/.test(t)) {
    const v = sk.calc(t.replace(/^(was ist|was sind|wie viel ist|wieviel ist|rechne|berechne)\s*/, ""));
    if (v != null) return { text: `Das ergibt ${v.toLocaleString("de-DE", { maximumFractionDigits: 6 })}.` };
  }
  // Morgen-Briefing
  if (/^(guten morgen|briefing|tagesbriefing|was steht (heute )?an|mein tag)/.test(t)) return briefing();
  // Kleines Gespräch
  if (/^(hallo|hi|hey|servus|moin)\b( nova)?$/.test(t)) return { text: `Hey${name}! Was kann ich für dich tun?` };
  if (/(wer bist du|was kannst du|hilfe)$/.test(t))
    return {
      text: `Ich bin ${BRAND.name}, dein KI-Assistent – du kannst mit mir schreiben oder sprechen.\n\n${
        srv.ai
          ? "- **Schreiben:** Nachrichten, Bewerbungen, Referate, Posts, Geschichten\n- **Erklären & Lernen:** Schule, Technik, Alltag – Schritt für Schritt\n- **Programmieren:** Code schreiben, erklären, Fehler finden\n- **Recherchieren:** aktuelle Infos aus dem Netz, mit Quellen\n- **Fotos & PDFs:** zeig mir etwas, ich erkläre es\n- **Nebenbei:** Wetter, Timer, Erinnerungen, Sparziele, ich merke mir Dinge"
          : "- Wetter, Timer und Erinnerungen\n- Rechnen und Sparziele planen\n- Mir Dinge über dich merken\n\nMit dem KI-Modus (NOVA-Server) beantworte ich außerdem **alles** – schreiben, erklären, programmieren, im Netz suchen, Fotos und PDFs lesen."
      }`,
      speak: srv.ai ? "Ich kann schreiben, erklären, programmieren, im Netz recherchieren, Fotos und PDFs lesen – und nebenbei Wetter, Timer und Erinnerungen." : "",
    };
  if (/^(danke|dankeschön|super danke)/.test(t)) return { text: "Gern! Sag Bescheid, wenn du noch was brauchst." };
  return null;
}
async function briefing() {
  const p = sk.profile();
  const h = new Date().getHours();
  const hi = h < 11 ? "Guten Morgen" : h < 18 ? "Hallo" : "Guten Abend";
  const parts = [`${hi}${p.name ? `, ${p.name}` : ""}! Heute ist ${sk.timeInfo().date}.`];
  let card = "";
  try {
    const w = await sk.weather({ city: p.city });
    parts.push(w.text);
    card = w.card;
  } catch (_) {
    /* ohne Wetter */
  }
  const rs = sk.reminders();
  if (rs.length) parts.push(`Du hast ${rs.length} ${rs.length === 1 ? "Erinnerung" : "Erinnerungen"}, die nächste ${sk.fmtIn(rs[0].at - Date.now())}: ${rs[0].text}.`);
  const g = sk.goal();
  if (g) parts.push(`Dein Sparziel: ${Math.round((g.saved / g.target) * 100)} Prozent von ${g.target.toLocaleString("de-DE")} Euro.`);
  return { text: parts.join(" "), card };
}
function offline(text, file) {
  return {
    text: `${file ? "Fotos und PDFs verstehe ich" : "Diese Frage beantworte ich"} im KI-Modus – der läuft über den ${BRAND.name}-Server mit Claude.${srv.on ? " Der Server hat noch keinen KI-Schlüssel." : ""}\n\nSofort kann ich schon: Wetter, Timer, Erinnerungen, Sparziele („Mach mir 10k“), Rechnen und mir Dinge merken.`,
  };
}

// ---------- Claude über den Server (Antwort live gestreamt, Werkzeuge laufen hier im Browser) ----------
let convo = []; // frühere Runden nur als Text – spart Kosten und Datenmenge
const TOOLS = [
  { name: "get_weather", description: "Aktuelles Wetter und Vorhersage (heute=0, morgen=1, übermorgen=2) für einen Ort. Ohne Ort: Wohnort bzw. Standort des Nutzers. Für weiter entfernte Tage: Websuche.", input_schema: { type: "object", properties: { city: { type: "string" }, day: { type: "integer", enum: [0, 1, 2] } } }, run: (i) => sk.weather(i) },
  { name: "set_reminder", description: "Stellt einen Timer oder eine Erinnerung in X Minuten (NOVA meldet sich mit Ton, Stimme und Mitteilung, solange die App offen ist).", input_schema: { type: "object", properties: { minutes: { type: "number" }, text: { type: "string" } }, required: ["minutes"] }, run: (i) => (askNotify(), setTimeout(paintSettings), { ok: true, ...sk.addReminder(i.minutes, i.text) }) },
  { name: "plan_savings_goal", description: "Sparziel planen und speichern (z. B. „Mach mir 10k“): Zielbetrag, optional Monatsrate oder Laufzeit in Monaten. Liefert Dauer beim reinen Sparen und im Szenario mit 5 % Rendite. Bewegt kein Geld, verspricht keine Gewinne.", input_schema: { type: "object", properties: { target: { type: "number" }, monthly: { type: "number" }, months: { type: "number" } }, required: ["target"] }, run: (i) => sk.planGoal(i) },
  { name: "remember_fact", description: "Merkt sich dauerhaft etwas über den Nutzer (Vorlieben, Ziele, Namen, Termine). Nur, wenn der Nutzer es möchte oder es offensichtlich nützlich ist.", input_schema: { type: "object", properties: { fact: { type: "string" } }, required: ["fact"] }, run: (i) => ({ ok: sk.remember(i.fact) }) },
  { name: "list_reminders", description: "Zeigt die anstehenden Timer und Erinnerungen.", input_schema: { type: "object", properties: {} }, run: () => sk.reminders().map((r) => ({ text: r.text, in: sk.fmtIn(r.at - Date.now()) })) },
];
// Werkzeug-Eingaben prüfen (sie werden live gestreamt und könnten unvollständig sein)
function validInput(tool, input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) return false;
  const props = tool.input_schema.properties || {};
  for (const k of tool.input_schema.required || []) if (input[k] == null) return false;
  for (const [k, v] of Object.entries(input)) {
    const t = props[k]?.type;
    if (!t) continue;
    if ((t === "number" || t === "integer") && typeof v !== "number") return false;
    if (t === "string" && typeof v !== "string") return false;
  }
  return true;
}
function context() {
  const p = sk.profile();
  const ti = sk.timeInfo();
  const g = sk.goal();
  return { name: p.name, city: p.city, now: `${ti.date}, ${ti.time} Uhr`, tz: Intl.DateTimeFormat().resolvedOptions().timeZone, memory: sk.memory().slice(-20).map((x) => x.t), goal: g ? { target: g.target, saved: g.saved, monthly: g.monthly } : null };
}
// Server-Sent Events lesen: „text“ (Wortstücke), „status“ (sucht im Netz …), „done“ (fertige Antwort), „error“
let stopper = null; // AbortController der laufenden Antwort
async function streamChat(body, onText, onStatus) {
  const t = token();
  stopper = new AbortController();
  const r = await fetch(API + "chat", { method: "POST", signal: stopper.signal, headers: { "Content-Type": "application/json", ...(t ? { Authorization: "Bearer " + t } : {}) }, body: JSON.stringify(body) });
  if (!r.ok || !r.body) {
    const j = await r.json().catch(() => ({}));
    throw Object.assign(new Error(j.msg || `Serverfehler (${r.status})`), { status: r.status });
  }
  const reader = r.body.getReader();
  const dec = new TextDecoder();
  let buf = "";
  let done = null;
  for (;;) {
    const { value, done: end } = await reader.read();
    if (end) break;
    buf += dec.decode(value, { stream: true });
    let i;
    while ((i = buf.indexOf("\n\n")) >= 0) {
      const chunk = buf.slice(0, i);
      buf = buf.slice(i + 2);
      const ev = (chunk.match(/^event: (.*)$/m) || [])[1];
      const data = (chunk.match(/^data: (.*)$/m) || [])[1];
      if (!ev || data == null) continue;
      const d = JSON.parse(data);
      if (ev === "text") onText(d.d);
      else if (ev === "status") onStatus(d);
      else if (ev === "done") done = d;
      else if (ev === "error") throw Object.assign(new Error(d.msg), { status: d.status });
    }
  }
  if (!done) throw new Error("Die Verbindung wurde unterbrochen.");
  return done;
}
async function llm(text, file, live) {
  await ensureAccount();
  const blocks = [];
  if (file?.kind === "image") blocks.push({ type: "image", source: { type: "base64", media_type: file.type, data: file.data } });
  if (file?.kind === "pdf") blocks.push({ type: "document", source: { type: "base64", media_type: "application/pdf", data: file.data }, title: file.name });
  const userContent = blocks.length ? [...blocks, { type: "text", text: text || (file.kind === "pdf" ? "Fasse das Dokument kurz zusammen." : "Was siehst du auf dem Bild?") }] : text;
  const messages = [...convo.slice(-16), { role: "user", content: userContent }];
  const turn = Math.random().toString(36).slice(2);
  const cards = [];
  const sources = [];
  let said = "";
  let streamed = "";
  for (let step = 0; step < 6; step++) {
    let r;
    try {
      r = await streamChat(
        { messages, tools: TOOLS.map(({ run, ...d }) => d), turn, context: context() },
        (d) => {
          streamed += d;
          live.update(streamed);
          if (orb.state === "think") setState("think", "");
          orb.kick(0.4);
        },
        (st) => setState("think", st.label),
      );
    } catch (e) {
      if (e.name === "AbortError") {
        said = (streamed || said).trim() + "\n\n*Gestoppt.*";
        break;
      }
      if (e.status === 401 && step === 0) {
        sk.store.set("token", "");
        await ensureAccount();
        continue;
      }
      if (e.status === 402) {
        setTimeout(openPlans, 400);
        return { text: e.message };
      }
      throw e;
    }
    Object.assign(srv, { plan: r.plan || srv.plan, used: r.used ?? srv.used, limit: r.limit ?? srv.limit });
    paintPlan();
    for (const b of r.content) {
      if (b.type === "text" && b.text) {
        said += (said && !said.endsWith("\n") ? "\n\n" : "") + b.text;
        for (const c of b.citations || []) if (c.url && !sources.some((x) => x.url === c.url)) sources.push({ url: c.url, title: c.title });
      }
    }
    if (streamed && !streamed.endsWith("\n")) streamed += "\n\n";
    if (r.stop_reason !== "tool_use") break;
    messages.push({ role: "assistant", content: r.content });
    const results = [];
    for (const b of r.content.filter((x) => x.type === "tool_use")) {
      const tool = TOOLS.find((x) => x.name === b.name);
      if (!tool || !validInput(tool, b.input)) {
        results.push({ type: "tool_result", tool_use_id: b.id, content: "INVALID_INPUT: Eingabe unvollständig oder falsch – bitte korrigiert erneut aufrufen.", is_error: true });
        continue;
      }
      setState("think", { get_weather: "Ich schaue aufs Wetter …", set_reminder: "Ich stelle die Erinnerung …", plan_savings_goal: "Ich rechne deinen Plan …", remember_fact: "Ich merke es mir …" }[b.name] || "");
      try {
        const out = await tool.run(b.input);
        if (out?.card) cards.push(out.card);
        const { card, ...data } = out || {};
        results.push({ type: "tool_result", tool_use_id: b.id, content: JSON.stringify(data).slice(0, 8000) });
      } catch (e) {
        results.push({ type: "tool_result", tool_use_id: b.id, content: String(e.message || e), is_error: true });
      }
    }
    messages.push({ role: "user", content: results });
  }
  convo.push({ role: "user", content: (file ? `(${file.kind === "pdf" ? "PDF" : "Foto"}) ` : "") + (text || "") }, { role: "assistant", content: said || "…" });
  return { text: said || "Da bin ich gerade nicht weitergekommen.", card: cards.join(""), sources };
}

// ---------- Chats wie bei Claude: Verlauf, neuer Chat, alte Chats öffnen ----------
let chatId = "";
const chats = () => sk.store.get("chats", []);
function saveChat(q, a) {
  if (!q && !a) return;
  const list = chats();
  let c = list.find((x) => x.id === chatId);
  if (!c) {
    chatId = Math.random().toString(36).slice(2, 10);
    c = { id: chatId, title: String(q || a).replace(/\s+/g, " ").slice(0, 60), items: [], convo: [] };
  }
  c.items = [...c.items, { r: "user", t: q }, { r: "nova", t: a }].slice(-120);
  c.convo = convo.slice(-24);
  c.at = Date.now();
  sk.store.set("chats", [c, ...list.filter((x) => x.id !== c.id)].slice(0, 40));
}
const HELLO = () => `<div class="hello" id="hello"><h1>Wie kann ich helfen?</h1><p>Schreiben, erklären, programmieren, recherchieren – per Text oder Stimme. Fotos und PDFs kann ich auch lesen.</p></div>`;
function newChat() {
  if (busy) stopper?.abort();
  voice.stopSpeaking();
  chatId = "";
  convo = [];
  log.innerHTML = HELLO();
  document.body.classList.remove("has-log");
  setState("idle");
  closeSheets();
  $("#input").focus();
}
function openChat(id) {
  const c = chats().find((x) => x.id === id);
  if (!c) return;
  chatId = c.id;
  convo = c.convo || [];
  log.innerHTML = "";
  for (const it of c.items) {
    const el = bubble(it.r, it.r === "user" ? esc(it.t) : md(it.t));
    if (it.r === "nova") (el.dataset.text = it.t), el.insertAdjacentHTML("beforeend", ACTS);
  }
  closeSheets();
}
function openChats() {
  const list = chats();
  const day = (t) => {
    const d = Math.floor((Date.now() - t) / 86400000);
    return d < 1 ? "Heute" : d < 2 ? "Gestern" : d < 7 ? "Diese Woche" : "Früher";
  };
  let last = "";
  $("#chats-body").innerHTML =
    `<button class="btn primary" data-new-chat>✎ Neuer Chat</button>` +
    (list.length
      ? list
          .map((c) => {
            const g = day(c.at);
            const head = g !== last ? `<h4>${g}</h4>` : "";
            last = g;
            return `${head}<div class="chat-row ${c.id === chatId ? "on" : ""}"><button type="button" data-open-chat="${c.id}">${esc(c.title || "Chat")}</button><button type="button" class="x" data-del-chat="${c.id}" aria-label="Chat löschen">✕</button></div>`;
          })
          .join("")
      : `<p class="muted">Noch keine Chats. Deine Unterhaltungen erscheinen hier – sie bleiben nur auf diesem Gerät.</p>`);
  openSheet("#sheet-chats");
}

// ---------- Foto oder PDF anhängen (Fotos verkleinert: schneller und günstiger) ----------
function paintAttach() {
  const a = $("#attach-prev");
  a.hidden = !pending;
  a.innerHTML = pending ? `${pending.kind === "image" ? `<img src="${pending.url}" alt="">` : `<span class="file-chip">📄 ${esc(pending.name)}</span>`}<button type="button" data-unattach aria-label="Anhang entfernen">✕</button>` : "";
}
async function attach(file) {
  if (!file) return;
  if (!srv.ai) return bubble("nova", md("Fotos und PDFs verstehe ich im KI-Modus über den Server. Sobald er läuft, kannst du mir alles zeigen."));
  if (file.type === "application/pdf") {
    if (file.size > 8 * 1024 * 1024) return toast("PDF ist zu groß (maximal 8 MB).");
    const data = await new Promise((ok, no) => {
      const fr = new FileReader();
      fr.onload = () => ok(String(fr.result).split(",")[1]);
      fr.onerror = no;
      fr.readAsDataURL(file);
    });
    pending = { kind: "pdf", name: file.name.slice(0, 60), data };
  } else {
    const img = await createImageBitmap(file).catch(() => null);
    if (!img) return toast("Dieses Bild kann ich nicht öffnen.");
    const k = Math.min(1, 1400 / Math.max(img.width, img.height));
    const cv = document.createElement("canvas");
    cv.width = Math.round(img.width * k);
    cv.height = Math.round(img.height * k);
    cv.getContext("2d").drawImage(img, 0, 0, cv.width, cv.height);
    const url = cv.toDataURL("image/jpeg", 0.82);
    pending = { kind: "image", url, type: "image/jpeg", data: url.split(",")[1] };
  }
  paintAttach();
  $("#input").focus();
}

// ---------- Erinnerungen ----------
function askNotify() {
  if ("Notification" in window && Notification.permission === "default") Notification.requestPermission().catch(() => {});
}
setInterval(() => {
  for (const r of sk.dueReminders()) {
    chime();
    bubble("nova", md(`⏰ **${r.text}**`));
    if (document.hidden && "Notification" in window && Notification.permission === "granted") {
      navigator.serviceWorker?.ready.then((reg) => reg.showNotification(BRAND.name, { body: r.text, icon: "icons/icon-192.png", tag: r.id })).catch(() => new Notification(BRAND.name, { body: r.text }));
    }
    say(r.text);
    paintSettings();
  }
}, 1000);

// ---------- Tarife & Kauf ----------
function paintPlan() {
  const p = planById(srv.plan);
  $("#plan-chip").textContent = srv.ai ? `${p.name} · ${Math.max(0, srv.limit - srv.used)} KI-Fragen heute` : srv.on ? "Server verbunden" : "Ohne Server";
}
function openPlans() {
  $("#plans-body").innerHTML = PLANS.map((p) => {
    const link = STRIPE.links[`${p.id}-monthly`];
    const cur = srv.plan === p.id;
    return `<div class="plan ${p.id} ${cur ? "cur" : ""}"><div class="plan-h"><b>${esc(p.name)}</b><span>${p.price ? `${p.price.toLocaleString("de-DE", { minimumFractionDigits: 2 })} €<small>/Monat</small>` : "0 €"}</span></div><ul>${p.features.map((f) => `<li>${esc(f)}</li>`).join("")}</ul>${
      cur ? `<button class="btn" disabled>Dein Tarif</button>` : p.price ? `<button class="btn primary" data-buy="${p.id}" ${link ? "" : "disabled"}>${link ? `${esc(p.name)} holen` : "Bald verfügbar"}</button>` : ""
    }</div>`;
  }).join("") + `<p class="muted small">Monatlich kündbar über das Stripe-Kundenportal. Preise inkl. MwSt.</p>`;
  openSheet("#sheet-plans");
}
async function buy(id) {
  const link = STRIPE.links[`${id}-monthly`];
  if (!link) return;
  const u = new URL(link);
  u.searchParams.set("locale", "de");
  if (token()) u.searchParams.set("client_reference_id", "nova_" + token().slice(0, 12).replace(/[^A-Za-z0-9]/g, ""));
  location.href = u.toString();
}
async function handleReturn() {
  const q = new URLSearchParams(location.search);
  if (!q.get("checkout")) return;
  window.history.replaceState(null, "", location.pathname);
  if (q.get("checkout") !== "success") return toast("Bezahlung abgebrochen – es wurde nichts berechnet.");
  const sid = q.get("session_id") || "";
  if (!srv.billing || !sid) return toast("Danke! Dein Kauf wird geprüft, sobald der Server bereit ist.");
  try {
    await ensureAccount();
    const r = await call("POST", "billing/verify", { sessionId: sid });
    sk.store.set("purchase", sid);
    await refreshPlan();
    toast(`${planById(r.plan).name} ist aktiv – danke! 🎉`);
  } catch (e) {
    toast(e.message);
  }
}

// ---------- Einstellungen ----------
function openSheet(id) {
  const s = $(id);
  s.hidden = false;
  requestAnimationFrame(() => s.classList.add("open"));
}
function closeSheets() {
  document.querySelectorAll(".sheet.open").forEach((s) => {
    s.classList.remove("open");
    setTimeout(() => (s.hidden = true), 300);
  });
}
function paintSettings() {
  const body = $("#settings-body");
  if (!body || $("#sheet-settings").hidden) return;
  const p = sk.profile();
  const vp = voice.prefs();
  const cur = voice.currentVoice()?.name;
  const vs = voice.voices();
  const g = sk.goal();
  body.innerHTML = `
    <section><h4>Über dich</h4><div class="row2"><label>Name<input data-prof="name" value="${esc(p.name)}" maxlength="24" placeholder="Wie soll ich dich nennen?"></label><label>Wohnort<input data-prof="city" value="${esc(p.city)}" maxlength="40" placeholder="Für das Wetter"></label></div></section>
    <section><h4>Stimme</h4><div class="chips">${vs.length ? vs.map((v) => `<button class="chip ${v.name === cur ? "on" : ""}" data-voice="${esc(v.name)}">▶ ${esc(v.name.replace(/\s*\(.*\)$/, "").replace(/^(Microsoft|Google)\s+/, "").slice(0, 22))}${voice.isHD(v) ? " <em>HD</em>" : ""}</button>`).join("") : `<small class="muted">Keine deutsche Stimme auf diesem Gerät.</small>`}</div>
      ${voice.IOS ? `<small class="muted">Schönere Stimmen: iPhone-Einstellungen → Bedienungshilfen → Gesprochene Inhalte → Stimmen → Deutsch → eine „Premium“-Stimme laden.</small>` : ""}
      <div class="row2"><label>Tempo<input type="range" min="0.8" max="1.3" step="0.02" value="${vp.rate}" data-vp="rate"></label><label>Tonhöhe<input type="range" min="0.6" max="1.4" step="0.02" value="${vp.pitch}" data-vp="pitch"></label></div></section>
    <section><h4>Gedächtnis</h4>${sk.memory().length ? `<ul class="plain">${sk.memory().map((x, i) => `<li>${esc(x.t)} <button class="x" data-forget="${i}" aria-label="Vergessen">✕</button></li>`).join("")}</ul>` : `<small class="muted">Sag „Merk dir, dass …“ – dann erscheint es hier.</small>`}</section>
    <section><h4>Timer & Erinnerungen</h4>${sk.reminders().length ? `<ul class="plain">${sk.reminders().map((r) => `<li>${esc(r.text)} · ${sk.fmtIn(r.at - Date.now())} <button class="x" data-unremind="${r.id}" aria-label="Löschen">✕</button></li>`).join("")}</ul>` : `<small class="muted">Keine. Sag „Erinnere mich in 10 Minuten an …“.</small>`}</section>
    ${g ? `<section><h4>Sparziel</h4><p>${g.saved.toLocaleString("de-DE")} € von ${g.target.toLocaleString("de-DE")} € (${Math.round((g.saved / g.target) * 100)} %)</p><button class="btn small" data-goal-reset>Ziel löschen</button></section>` : ""}
    <section><h4>Konto</h4><div class="row-btns"><button class="btn small" data-open-plans>Tarife</button>${srv.billing ? `<button class="btn small" data-restore>Kauf wiederherstellen</button>` : ""}<button class="btn small danger" data-wipe>Alle Daten löschen</button></div>
      <small class="muted">${BRAND.name} ${VERSION} · Deine Daten bleiben auf diesem Gerät; Fragen an die KI gehen verschlüsselt über den ${BRAND.name}-Server an Claude (Anthropic). Keine Anlageberatung.</small></section>`;
}
function bindSettings() {
  const body = $("#settings-body");
  body.addEventListener("change", (e) => {
    const k = e.target.dataset.prof;
    if (k) sk.setProfile({ [k]: e.target.value.trim() });
    const v = e.target.dataset.vp;
    if (v) {
      voice.setPrefs({ [v]: +e.target.value });
      say(v === "rate" ? "So schnell spreche ich jetzt." : "So klingt meine Stimme jetzt.");
    }
  });
  body.addEventListener("click", async (e) => {
    const t = e.target;
    const vb = t.closest("[data-voice]");
    if (vb) {
      voice.unlock();
      voice.setPrefs({ voice: vb.dataset.voice });
      paintSettings();
      return say(`Hallo${sk.profile().name ? " " + sk.profile().name : ""}, so klinge ich jetzt.`);
    }
    const f = t.closest("[data-forget]");
    if (f) return sk.forget(+f.dataset.forget), paintSettings();
    const u = t.closest("[data-unremind]");
    if (u) return sk.removeReminder(u.dataset.unremind), paintSettings();
    if (t.closest("[data-goal-reset]")) return sk.store.set("goal", null), paintSettings();
    if (t.closest("[data-open-plans]")) return closeSheets(), setTimeout(openPlans, 320);
    if (t.closest("[data-restore]")) {
      const sid = (prompt("Kaufnummer (beginnt mit „cs_“):") || sk.store.get("purchase", "")).trim();
      if (!sid) return;
      try {
        await ensureAccount();
        await call("POST", "billing/verify", { sessionId: sid });
        await refreshPlan();
        toast("Kauf wiederhergestellt 🎉");
      } catch (err) {
        toast(err.message);
      }
    }
    if (t.closest("[data-wipe]") && confirm("Wirklich alle NOVA-Daten auf diesem Gerät löschen?")) {
      if (srv.on && token()) await call("DELETE", "me").catch(() => {});
      Object.keys(localStorage)
        .filter((k) => k.startsWith("nova-"))
        .forEach((k) => localStorage.removeItem(k));
      location.reload();
    }
  });
}

// ---------- Start ----------
function bind() {
  $("#mic").addEventListener("click", () => {
    voice.unlock();
    if (voice.listening()) return voice.stopListening(true);
    if (orb.state === "speak") voice.stopSpeaking();
    if (!voice.canListen) return $("#input").focus(), toast("Dein Browser kann nicht zuhören – schreib mir oder nutze das Diktier-Mikro der Tastatur.");
    talking = true;
    listenOnce(true);
  });
  $("#orb-wrap").addEventListener("click", () => {
    if (orb.state === "speak") return voice.stopSpeaking();
    $("#mic").click();
  });
  $("#composer").addEventListener("submit", (e) => {
    e.preventDefault();
    voice.unlock();
    if (busy) return stopper?.abort(), voice.stopSpeaking();
    const v = $("#input").value;
    $("#input").value = "";
    talking = false;
    ask(v);
  });
  $("#chips").addEventListener("click", (e) => {
    const c = e.target.closest("[data-ask]");
    if (!c) return;
    voice.unlock();
    ask(c.dataset.ask, { spoken: false });
  });
  $("#photo").addEventListener("change", (e) => (attach(e.target.files[0]), (e.target.value = "")));
  $("#attach-prev").addEventListener("click", (e) => e.target.closest("[data-unattach]") && ((pending = null), paintAttach()));
  $("#settings-btn").addEventListener("click", () => (openSheet("#sheet-settings"), paintSettings()));
  $("#plan-chip").addEventListener("click", openPlans);
  const copy = (t, what = "Kopiert") =>
    navigator.clipboard?.writeText(t).then(
      () => toast(`${what} ✓`),
      () => toast("Kopieren nicht möglich."),
    );
  log.addEventListener("click", (e) => {
    const m = e.target.closest(".msg");
    if (e.target.closest("[data-copy]")) return copy(m.dataset.text || m.querySelector(".bubble").innerText);
    if (e.target.closest("[data-read]")) return voice.unlock(), say(forSpeech(m.dataset.text || m.querySelector(".bubble").innerText));
    const cb = e.target.closest("[data-copy-code]");
    if (cb) return copy(cb.closest(".code").querySelector("code").textContent, "Code kopiert");
  });
  $("#chats-btn").addEventListener("click", openChats);
  $("#new-btn").addEventListener("click", newChat);
  $("#chats-body").addEventListener("click", (e) => {
    if (e.target.closest("[data-new-chat]")) return newChat();
    const o = e.target.closest("[data-open-chat]");
    if (o) return openChat(o.dataset.openChat);
    const d = e.target.closest("[data-del-chat]");
    if (d) {
      sk.store.set("chats", chats().filter((x) => x.id !== d.dataset.delChat));
      if (d.dataset.delChat === chatId) chatId = "";
      openChats();
    }
  });
  document.addEventListener("click", (e) => {
    if (e.target.closest("[data-close]") || e.target.classList.contains("sheet")) closeSheets();
    const b = e.target.closest("[data-buy]");
    if (b) buy(b.dataset.buy);
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") closeSheets();
    if (e.code === "Space" && !e.target.closest("input, textarea, select, button") && !e.repeat) {
      e.preventDefault();
      $("#mic").click();
    }
  });
  document.addEventListener("nova-voices", paintSettings);
  bindSettings();
}
$("#brand-name").textContent = BRAND.name;
document.title = `${BRAND.name} – ${BRAND.tagline}`;
bind();
setState("idle");
connect().then(handleReturn);
if ("serviceWorker" in navigator) navigator.serviceWorker.register("sw.js", { updateViaCache: "none" }).catch(() => {});
