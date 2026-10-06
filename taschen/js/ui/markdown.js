// Arbeitstaschen – einfaches, sicheres Markdown für Notizen (erst escapen, dann formatieren; Links nur über safeUrl)
import { esc, safeUrl } from "../util.js";

// ---------- Zeilen-Formatierung ----------
function fmt(s) {
  return esc(s)
    .replace(/\*\*(?=\S)(.+?)\*\*/g, "<b>$1</b>")
    .replace(/__(?=\S)(.+?)__/g, "<b>$1</b>")
    .replace(/(^|[^*\w])\*(?=\S)([^*]+?)\*(?!\w)/g, "$1<i>$2</i>")
    .replace(/(^|[^_\w])_(?=\S)([^_]+?)_(?!\w)/g, "$1<i>$2</i>")
    .replace(/~~(?=\S)(.+?)~~/g, "<s>$1</s>");
}

function shortUrl(u) {
  try {
    const x = new URL(u);
    const p = x.pathname.length > 1 ? x.pathname.replace(/\/$/, "") : "";
    const s = x.hostname.replace(/^www\./, "") + p;
    return s.length > 42 ? s.slice(0, 40) + "…" : s;
  } catch (_) {
    return u;
  }
}

const link = (u, label) => `<a href="${esc(u)}" target="_blank" rel="noopener noreferrer">${label}</a>`;

export function inline(raw) {
  const re = /`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)|((?:https?:\/\/|www\.)[^\s<]+[^\s<.,;:!?)\]'"„“])/g;
  let out = "", last = 0, m;
  while ((m = re.exec(raw))) {
    out += fmt(raw.slice(last, m.index));
    if (m[1] != null) out += `<code>${esc(m[1])}</code>`;
    else if (m[2] != null) {
      const u = safeUrl(m[3].startsWith("www.") ? "https://" + m[3] : m[3]);
      out += u ? link(u, fmt(m[2])) : fmt(m[0]);
    } else {
      const u = safeUrl(m[4].startsWith("www.") ? "https://" + m[4] : m[4]);
      out += u ? link(u, esc(shortUrl(u))) : esc(m[4]);
    }
    last = re.lastIndex;
  }
  return out + fmt(raw.slice(last));
}

// ---------- Blöcke ----------
// opts.checkAct: data-act für Checkboxen (Zeilennummer in data-line)
export function markdown(src, { checkAct = "md-check", attrs = "" } = {}) {
  const lines = String(src || "").replace(/\r\n?/g, "\n").split("\n");
  let html = "", list = null, para = [], code = null;
  const flushPara = () => {
    if (para.length) html += `<p>${para.map(inline).join("<br>")}</p>`;
    para = [];
  };
  const closeList = () => {
    if (list) html += `</${list}>`;
    list = null;
  };
  lines.forEach((line, i) => {
    if (code !== null) {
      if (/^\s*```/.test(line)) {
        html += `<pre><code>${esc(code.join("\n"))}</code></pre>`;
        code = null;
      } else code.push(line);
      return;
    }
    if (/^\s*```/.test(line)) {
      flushPara();
      closeList();
      code = [];
      return;
    }
    const t = line.trim();
    if (!t) {
      flushPara();
      closeList();
      return;
    }
    let m;
    if ((m = t.match(/^(#{1,3})\s+(.*)$/))) {
      flushPara();
      closeList();
      const lv = m[1].length + 2;
      html += `<h${lv}>${inline(m[2])}</h${lv}>`;
      return;
    }
    if (/^(-{3,}|\*{3,}|_{3,})$/.test(t)) {
      flushPara();
      closeList();
      html += "<hr>";
      return;
    }
    if ((m = t.match(/^>\s?(.*)$/))) {
      flushPara();
      closeList();
      html += `<blockquote>${inline(m[1])}</blockquote>`;
      return;
    }
    if ((m = t.match(/^[-*+]\s+\[( |x|X)\]\s*(.*)$/))) {
      flushPara();
      if (list !== "ul") {
        closeList();
        html += `<ul class="md-checks">`;
        list = "ul";
      }
      const on = m[1] !== " ";
      html += `<li class="md-cb${on ? " on" : ""}"><button type="button" class="md-box" data-act="${checkAct}" data-line="${i}" ${attrs} aria-pressed="${on}" aria-label="${on ? "Erledigt" : "Offen"}"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 12.5l4 4 8-9"/></svg></button><span>${inline(m[2])}</span></li>`;
      return;
    }
    if ((m = t.match(/^[-*+•]\s+(.*)$/))) {
      flushPara();
      if (list !== "ul") {
        closeList();
        html += "<ul>";
        list = "ul";
      }
      html += `<li>${inline(m[1])}</li>`;
      return;
    }
    if ((m = t.match(/^\d+[.)]\s+(.*)$/))) {
      flushPara();
      if (list !== "ol") {
        closeList();
        html += "<ol>";
        list = "ol";
      }
      html += `<li>${inline(m[1])}</li>`;
      return;
    }
    closeList();
    para.push(t);
  });
  if (code !== null) html += `<pre><code>${esc(code.join("\n"))}</code></pre>`;
  flushPara();
  closeList();
  return html;
}

// Checkbox in Zeile n umschalten
export function toggleCheckLine(src, n) {
  const lines = String(src || "").replace(/\r\n?/g, "\n").split("\n");
  if (n < 0 || n >= lines.length) return src;
  lines[n] = lines[n].replace(/^(\s*[-*+]\s+\[)( |x|X)(\])/, (_, a, b, c) => a + (b === " " ? "x" : " ") + c);
  return lines.join("\n");
}

// Klartext-Auszug für Karten
export function plain(src, max = 160) {
  const s = String(src || "")
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/^\s*#{1,6}\s+/gm, "")
    .replace(/^\s*[-*+]\s+\[( |x|X)\]\s*/gm, (m, x) => (x === " " ? "○ " : "✓ "))
    .replace(/^\s*[-*+•]\s+/gm, "• ")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/[*_~`>]/g, "")
    .replace(/\s+/g, " ")
    .trim();
  return s.length > max ? s.slice(0, max - 1) + "…" : s;
}

// Fortschritt der Checkboxen einer Notiz
export function checkStats(src) {
  const all = String(src || "").match(/^\s*[-*+]\s+\[( |x|X)\]/gm) || [];
  const done = all.filter((x) => /\[(x|X)\]/.test(x)).length;
  return { total: all.length, done };
}
