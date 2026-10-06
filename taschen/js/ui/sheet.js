// Arbeitstaschen – Sheets (von unten mit Feder, Ziehen zum Schließen), Dialoge, Kontextmenüs und Bestätigungen
import { esc } from "../util.js";
import { icon } from "./icons.js";
import { render, app } from "./core.js";

const stack = [];
const layer = () => document.getElementById("layer");

// ---------- Sheets ----------
// openSheet({ key, render: () => html, label, size: ""|"large"|"full"|"wide", cls, onClose, onMount })
export function openSheet(o) {
  if (o.key) {
    const ex = stack.find((s) => s.key === o.key && !s.closing);
    if (ex) {
      if (o.render) ex.render = o.render;
      ex.refresh();
      return ex;
    }
  }
  const wrap = document.createElement("div");
  wrap.className = `sheet-wrap ${o.size || ""} ${o.cls || ""}`.trim();
  wrap.innerHTML = `<div class="sheet-backdrop" data-backdrop></div><section class="sheet" role="dialog" aria-modal="true" aria-label="${esc(o.label || "Fenster")}" tabindex="-1"><div class="grabber" aria-hidden="true"></div><div class="sheet-content"></div></section>`;
  layer().append(wrap);
  const s = {
    key: o.key || null,
    wrap,
    box: wrap.querySelector(".sheet"),
    body: wrap.querySelector(".sheet-content"),
    render: o.render,
    onClose: o.onClose,
    restore: document.activeElement,
    closing: false,
    refresh() {
      if (this.closing || !this.render) return;
      try {
        render(this.body, this.render());
      } catch (e) {
        console.error(e);
      }
    },
    close: () => closeSheet(s),
  };
  s.refresh();
  stack.push(s);
  document.documentElement.style.setProperty("--sy", window.scrollY + "px");
  document.documentElement.classList.add("sheet-open");
  if (stack.length > 1) document.documentElement.classList.add("sheet-stacked");
  dragToClose(s);
  // Fokus SOFORT setzen (iOS öffnet die Tastatur nur innerhalb der Nutzergeste)
  const af = s.body.querySelector("[autofocus]");
  try {
    (af || s.box).focus({ preventScroll: true });
  } catch (_) {
    /* ältere Browser */
  }
  requestAnimationFrame(() => requestAnimationFrame(() => wrap.classList.add("open")));
  o.onMount?.(s);
  return s;
}

export function closeSheet(s = stack[stack.length - 1]) {
  if (!s || s.closing) return;
  s.closing = true;
  const i = stack.indexOf(s);
  if (i >= 0) stack.splice(i, 1);
  s.wrap.classList.remove("open");
  s.wrap.classList.add("closing");
  s.box.style.transform = "";
  setTimeout(() => s.wrap.remove(), 480);
  if (!stack.length) document.documentElement.classList.remove("sheet-open");
  if (stack.length < 2) document.documentElement.classList.remove("sheet-stacked");
  try {
    s.onClose?.();
  } catch (e) {
    console.error(e);
  }
  try {
    if (s.restore && document.contains(s.restore)) s.restore.focus({ preventScroll: true });
  } catch (_) {
    /* Fokus nicht wiederherstellbar */
  }
}

export const topSheet = () => stack[stack.length - 1] || null;
export const sheetOpen = (key) => stack.some((s) => s.key === key && !s.closing);
export const getSheet = (key) => stack.find((s) => s.key === key && !s.closing) || null;
export const closeAll = () => [...stack].reverse().forEach((s) => closeSheet(s));
export const refreshSheets = () => stack.forEach((s) => s.refresh());

// Ziehen nach unten schließt (nur Touch, nur wenn ganz oben gescrollt)
function dragToClose(s) {
  const box = s.box;
  let y0 = 0, dy = 0, active = false, armed = false, t0 = 0;
  box.addEventListener(
    "touchstart",
    (e) => {
      if (app.wide || e.touches.length !== 1) return;
      if (e.target.closest("input, textarea, select, [data-nodrag], .seg, .hscroll")) return;
      armed = box.scrollTop <= 0;
      y0 = e.touches[0].clientY;
      dy = 0;
      t0 = Date.now();
      active = false;
    },
    { passive: true },
  );
  box.addEventListener(
    "touchmove",
    (e) => {
      if (!armed) return;
      dy = e.touches[0].clientY - y0;
      if (!active) {
        if (dy > 6 && box.scrollTop <= 0) {
          active = true;
          box.classList.add("dragging");
        } else if (dy < -6) {
          armed = false;
          return;
        } else return;
      }
      e.preventDefault();
      const d = Math.max(0, dy);
      box.style.transform = `translateY(${d < 120 ? d : 120 + (d - 120) * 0.55}px)`;
    },
    { passive: false },
  );
  const end = () => {
    if (!active) {
      armed = false;
      return;
    }
    active = armed = false;
    box.classList.remove("dragging");
    const v = dy / Math.max(1, Date.now() - t0);
    if (dy > 130 || (dy > 50 && v > 0.6)) closeSheet(s);
    else box.style.transform = "";
  };
  box.addEventListener("touchend", end);
  box.addEventListener("touchcancel", end);
}

// Kopfzeile eines Sheets (Titel + Knöpfe)
export function sheetHead(title, { left = "", right = "", sub = "" } = {}) {
  return `<header class="sheet-head"><div class="sh-l">${left}</div><div class="sh-t"><h2>${esc(title)}</h2>${sub ? `<p>${esc(sub)}</p>` : ""}</div><div class="sh-r">${right || `<button class="btn-round" type="button" data-act="sheet-close" aria-label="Schließen">${icon("x")}</button>`}</div></header>`;
}

// ---------- Kontextmenü ----------
// items: [{ icon, label, run, danger, sub: items, check, hint, disabled } | "-"]
let menuEl = null;
export function openMenu(items, { x = null, y = null, el = null, title = "" } = {}) {
  closeMenu();
  const wrap = document.createElement("div");
  wrap.className = "menu-wrap";
  wrap.innerHTML = `<div class="menu-backdrop"></div><div class="menu" role="menu" tabindex="-1"></div>`;
  document.body.append(wrap);
  menuEl = wrap;
  const box = wrap.querySelector(".menu");
  const stackM = [{ items, title }];
  const paint = () => {
    const top = stackM[stackM.length - 1];
    box.innerHTML =
      (stackM.length > 1 ? `<button class="mi back" type="button" role="menuitem" data-back>${icon("chevronLeft")}<span>${esc(top.title || "Zurück")}</span></button><div class="msep"></div>` : top.title ? `<div class="mtitle">${esc(top.title)}</div>` : "") +
      top.items
        .map((it, i) => {
          if (it === "-") return `<div class="msep"></div>`;
          if (!it) return "";
          return `<button class="mi${it.danger ? " danger" : ""}${it.check ? " checked" : ""}" type="button" role="menuitem" data-i="${i}"${it.disabled ? " disabled" : ""}><span class="mi-l">${esc(it.label)}${it.hint ? `<small>${esc(it.hint)}</small>` : ""}</span><span class="mi-i">${it.sub ? icon("chevronRight") : it.check ? icon("check") : it.emoji ? `<span class="mi-emoji">${esc(it.emoji)}</span>` : it.icon ? icon(it.icon) : ""}</span></button>`;
        })
        .join("");
  };
  paint();
  // Position
  const place = () => {
    const W = window.innerWidth, Hh = window.innerHeight;
    const r = box.getBoundingClientRect();
    let px = x, py = y;
    if (el) {
      const er = el.getBoundingClientRect();
      px = er.right - r.width;
      py = er.bottom + 6;
      if (py + r.height > Hh - 12) py = er.top - r.height - 6;
    }
    if (px == null) px = (W - r.width) / 2;
    if (py == null) py = (Hh - r.height) / 2;
    px = Math.max(10, Math.min(px, W - r.width - 10));
    py = Math.max(10 + (parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--sat")) || 0), Math.min(py, Hh - r.height - 12));
    box.style.left = px + "px";
    box.style.top = py + "px";
    box.style.transformOrigin = `${x != null ? x - px : r.width}px ${y != null ? y - py : 0}px`;
  };
  place();
  requestAnimationFrame(() => wrap.classList.add("open"));
  box.addEventListener("click", (e) => {
    const b = e.target.closest(".mi");
    if (!b || b.disabled) return;
    if (b.hasAttribute("data-back")) {
      stackM.pop();
      paint();
      place();
      return;
    }
    const it = stackM[stackM.length - 1].items[+b.dataset.i];
    if (!it) return;
    if (it.sub) {
      stackM.push({ items: it.sub, title: it.label });
      paint();
      place();
      box.querySelector(".mi:not([data-back])")?.focus();
      return;
    }
    closeMenu();
    try {
      it.run?.();
    } catch (err) {
      console.error(err);
    }
  });
  let down = false;
  wrap.querySelector(".menu-backdrop").addEventListener("pointerdown", () => (down = true));
  wrap.querySelector(".menu-backdrop").addEventListener("click", () => down && closeMenu());
  wrap.querySelector(".menu-backdrop").addEventListener("contextmenu", (e) => {
    e.preventDefault();
    closeMenu();
  });
  box.addEventListener("keydown", (e) => {
    const list = [...box.querySelectorAll(".mi:not([disabled])")];
    const i = list.indexOf(document.activeElement);
    if (e.key === "ArrowDown") {
      e.preventDefault();
      list[(i + 1) % list.length]?.focus();
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      list[(i - 1 + list.length) % list.length]?.focus();
    } else if (e.key === "Escape") {
      e.preventDefault();
      e.stopPropagation();
      closeMenu();
    }
  });
  setTimeout(() => (matchMedia("(pointer: fine)").matches ? box.querySelector(".mi")?.focus({ preventScroll: true }) : box.focus({ preventScroll: true })), 30);
  return wrap;
}

export function closeMenu() {
  if (!menuEl) return false;
  const m = menuEl;
  menuEl = null;
  m.classList.remove("open");
  m.classList.add("closing");
  setTimeout(() => m.remove(), 220);
  return true;
}

export const menuOpen = () => !!menuEl;

// ---------- Hinweis-, Bestätigungs- und Eingabe-Dialoge (iOS-Alert) ----------
function alertBox({ title, text = "", input = null, buttons }) {
  return new Promise((resolve) => {
    const wrap = document.createElement("div");
    wrap.className = "alert-wrap";
    wrap.innerHTML = `<div class="alert" role="alertdialog" aria-modal="true" aria-label="${esc(title)}"><div class="alert-body"><h3>${esc(title)}</h3>${text ? `<p>${esc(text)}</p>` : ""}${input ? `<input class="alert-input" type="${input.type || "text"}" value="${esc(input.value || "")}" placeholder="${esc(input.placeholder || "")}" autocomplete="off" enterkeyhint="done" />` : ""}</div><div class="alert-btns${buttons.length > 2 ? " stacked" : ""}">${buttons.map((b, i) => `<button type="button" class="${b.cls || ""}" data-i="${i}">${esc(b.label)}</button>`).join("")}</div></div>`;
    document.body.append(wrap);
    const inp = wrap.querySelector(".alert-input");
    const prev = document.activeElement;
    const done = (v) => {
      wrap.classList.remove("open");
      setTimeout(() => wrap.remove(), 220);
      document.removeEventListener("keydown", key, true);
      try {
        prev?.focus?.({ preventScroll: true });
      } catch (_) {
        /* egal */
      }
      resolve(v);
    };
    const key = (e) => {
      if (e.key === "Escape") {
        e.preventDefault();
        e.stopPropagation();
        done(buttons.find((b) => b.cancel)?.value ?? null);
      } else if (e.key === "Enter" && (inp ? document.activeElement === inp : true)) {
        e.preventDefault();
        e.stopPropagation();
        const b = buttons.find((x) => x.default) || buttons[buttons.length - 1];
        done(inp ? (b.cancel ? null : inp.value) : b.value);
      }
    };
    document.addEventListener("keydown", key, true);
    wrap.querySelectorAll(".alert-btns button").forEach((btn) =>
      btn.addEventListener("click", () => {
        const b = buttons[+btn.dataset.i];
        done(inp ? (b.cancel ? null : inp.value) : b.value);
      }),
    );
    if (inp) {
      inp.focus();
      inp.select();
    }
    requestAnimationFrame(() => requestAnimationFrame(() => wrap.classList.add("open")));
    if (!inp) setTimeout(() => wrap.querySelector(".alert-btns button:last-child")?.focus({ preventScroll: true }), 40);
  });
}

export function confirmBox({ title, text = "", ok = "OK", cancel = "Abbrechen", danger = false }) {
  return alertBox({ title, text, buttons: [{ label: cancel, value: false, cancel: true }, { label: ok, value: true, cls: danger ? "danger" : "bold", default: true }] });
}

export function promptBox({ title, text = "", value = "", placeholder = "", ok = "OK", type = "text" }) {
  return alertBox({ title, text, input: { value, placeholder, type }, buttons: [{ label: "Abbrechen", cancel: true }, { label: ok, cls: "bold", default: true }] });
}

export function infoBox({ title, text = "", ok = "OK" }) {
  return alertBox({ title, text, buttons: [{ label: ok, value: true, cls: "bold", default: true }] });
}

// Auswahl als Aktionsblatt (Optionen als Knöpfe)
export function chooseBox({ title, text = "", options = [] }) {
  return alertBox({ title, text, buttons: [...options.map((o) => ({ label: o.label, value: o.value, cls: o.danger ? "danger" : o.bold ? "bold" : "" })), { label: "Abbrechen", value: null, cancel: true }] });
}
