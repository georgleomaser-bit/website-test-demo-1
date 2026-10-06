// Arbeitstaschen – Gesten: Wischen auf Aufgaben, langes Drücken (Kontextmenü), Ziehen & Ablegen, 3D-Neigung der Karten
import { runMenu, reducedMotion } from "./core.js";
import { toggleTask, deleteTask } from "./actions.js";
import { haptic } from "./fx.js";

let suppressClick = 0; // Klicks direkt nach einer Geste schlucken
const OPENW = 156;

export const gestureBusy = () => performance.now() < suppressClick;

// ---------- Wischen (nur Touch/Stift) ----------
let S = null;
let openRow = null;

function closeOpenRow(except) {
  if (!openRow || openRow === except) return;
  const r = openRow;
  openRow = null;
  r.classList.remove("sw-open");
  const inner = r.querySelector(".task-in");
  if (inner) inner.style.transform = "";
  setTimeout(() => {
    if (openRow !== r) r.removeAttribute("data-hold");
  }, 320);
}

function swipeDown(e) {
  if (e.pointerType === "mouse" || !e.isPrimary) return;
  const row = e.target.closest?.(".task");
  if (!row || row.closest(".board, .drag-ghost") || e.target.closest(".swipe-bg")) return;
  closeOpenRow(row);
  if (e.clientX < 24) return; // iOS-Zurück-Geste nicht stören
  S = { row, inner: row.querySelector(".task-in"), x0: e.clientX, y0: e.clientY, d: 0, base: row.classList.contains("sw-open") ? -OPENW : 0, locked: null, w: row.offsetWidth, id: row.dataset.id, pid: e.pointerId };
}

function swipeMove(e) {
  if (!S || e.pointerId !== S.pid) return;
  const dx = e.clientX - S.x0, dy = e.clientY - S.y0;
  if (!S.locked) {
    if (Math.abs(dx) > 10 && Math.abs(dx) > Math.abs(dy) * 1.4) {
      S.locked = "x";
      cancelPress();
      S.row.setAttribute("data-hold", "");
      S.row.classList.add("swiping");
      try {
        S.row.setPointerCapture(e.pointerId);
      } catch (_) {
        /* egal */
      }
    } else if (Math.abs(dy) > 10) {
      S = null;
      return;
    } else return;
  }
  let d = S.base + dx;
  const max = S.w * 0.75;
  if (d > 0) d = d < max ? d : max + (d - max) * 0.2;
  else if (d < -S.w * 0.8) d = -S.w * 0.8 + (d + S.w * 0.8) * 0.2;
  S.d = d;
  S.inner.style.transform = `translateX(${d}px)`;
  S.row.style.setProperty("--sw", d + "px");
  S.row.classList.toggle("sw-right", d > 0);
  S.row.classList.toggle("sw-left", d < 0);
  const commitR = d > S.w * 0.32, commitL = d < -S.w * 0.55;
  if (commitR !== S.row.classList.contains("sw-commit-r") || commitL !== S.row.classList.contains("sw-commit-l")) {
    S.row.classList.toggle("sw-commit-r", commitR);
    S.row.classList.toggle("sw-commit-l", commitL);
  }
}

function swipeUp(e) {
  if (!S || e.pointerId !== S.pid) return;
  const s = S;
  S = null;
  if (s.locked !== "x") return;
  suppressClick = performance.now() + 350;
  const { row, inner, d, w, id } = s;
  row.classList.remove("swiping", "sw-commit-r", "sw-commit-l");
  inner.style.transform = "";
  if (e.type === "pointercancel") {
    row.classList.remove("sw-open", "sw-right", "sw-left");
    row.removeAttribute("data-hold");
    return;
  }
  if (d > w * 0.32) {
    row.classList.remove("sw-right", "sw-left");
    row.removeAttribute("data-hold");
    toggleTask(id);
  } else if (d < -w * 0.55) {
    inner.style.transform = `translateX(${-w}px)`;
    setTimeout(() => {
      row.removeAttribute("data-hold");
      deleteTask(id);
    }, 160);
  } else if (d < -56) {
    inner.style.transform = `translateX(${-OPENW}px)`;
    row.classList.add("sw-open");
    openRow = row;
    haptic();
  } else {
    row.classList.remove("sw-open", "sw-right", "sw-left");
    setTimeout(() => row.removeAttribute("data-hold"), 300);
  }
}

// ---------- Langes Drücken (Touch) → Kontextmenü oder Ziehen ----------
let P = null;
function cancelPress() {
  if (P) clearTimeout(P.timer);
  if (P?.lifted) P.el.classList.remove("lifted");
  if (P?.el && P.onMove) P.el.removeEventListener("touchmove", P.onMove);
  P = null;
}

function touchStart(e) {
  if (e.touches.length !== 1) return cancelPress();
  const t = e.touches[0];
  const el = e.target.closest?.("[data-drag], [data-menu]");
  if (!el || e.target.closest("input, textarea, select, .swipe-bg")) return;
  cancelPress();
  P = { el, x0: t.clientX, y0: t.clientY, x: t.clientX, y: t.clientY, lifted: false, drag: el.hasAttribute("data-drag") };
  P.onMove = (ev) => {
    if (!P) return;
    const tt = ev.touches[0];
    P.x = tt.clientX;
    P.y = tt.clientY;
    if (!P.lifted) {
      if (Math.hypot(P.x - P.x0, P.y - P.y0) > 9) cancelPress();
      return;
    }
    ev.preventDefault(); // kein Scrollen während des Ziehens
    if (!D && Math.hypot(P.x - P.x0, P.y - P.y0) > 6) startDrag(P.el, P.x0, P.y0);
    if (D) moveDrag(P.x, P.y);
  };
  el.addEventListener("touchmove", P.onMove, { passive: false });
  P.timer = setTimeout(() => {
    if (!P) return;
    P.lifted = true;
    suppressClick = performance.now() + 700;
    if (P.drag) {
      P.el.classList.add("lifted");
      try {
        navigator.vibrate?.(10);
      } catch (_) {
        /* ohne Vibration */
      }
    } else {
      const el2 = P.el, x = P.x, y = P.y;
      cancelPress();
      runMenu(el2, { x, y });
    }
  }, 420);
}

function touchEnd() {
  if (!P) return;
  const p = P;
  if (D) {
    endDrag(true);
    suppressClick = performance.now() + 400;
  } else if (p.lifted && p.el.hasAttribute("data-menu")) {
    suppressClick = performance.now() + 400;
    runMenu(p.el, { x: p.x, y: p.y });
  }
  cancelPress();
}

// ---------- Ziehen & Ablegen (Maus und Touch) ----------
// Ablagezonen: [data-drop="<name>"]; Handler: onDrop(name, (id, zone, beforeId) => …)
const drops = {};
export function onDrop(name, fn) {
  drops[name] = fn;
}

let D = null;
let line = null;

function startDrag(el, x, y) {
  const r = el.getBoundingClientRect();
  const ghost = el.cloneNode(true);
  ghost.classList.add("drag-ghost");
  ghost.classList.remove("lifted");
  ghost.removeAttribute("data-key");
  ghost.style.width = r.width + "px";
  ghost.style.left = "0px";
  ghost.style.top = "0px";
  document.body.append(ghost);
  el.classList.remove("lifted");
  el.classList.add("drag-src");
  el.setAttribute("data-hold", "");
  D = { el, id: el.dataset.id, kind: el.dataset.drag, ghost, offX: x - r.left, offY: y - r.top, zone: null, before: null, x, y };
  document.documentElement.classList.add("is-dragging");
  moveDrag(x, y);
}

function moveDrag(x, y) {
  if (!D) return;
  D.x = x;
  D.y = y;
  D.ghost.style.transform = `translate(${x - D.offX}px, ${y - D.offY}px) rotate(${reducedMotion() ? 0 : 1.6}deg) scale(1.03)`;
  const hit = document.elementFromPoint(x, y);
  const zone = hit?.closest?.("[data-drop]") || null;
  if (zone !== D.zone) {
    D.zone?.classList.remove("drop-over");
    zone?.classList.add("drop-over");
    D.zone = zone;
  }
  // Einfügestelle in Listen-Zonen
  D.before = null;
  if (zone && zone.hasAttribute("data-drop-list")) {
    const items = [...zone.querySelectorAll("[data-drag]")].filter((n) => n !== D.el);
    const next = items.find((n) => {
      const rr = n.getBoundingClientRect();
      return y < rr.top + rr.height / 2;
    });
    D.before = next ? next.dataset.id : null;
    if (!line) {
      line = document.createElement("div");
      line.className = "drop-line";
      document.body.append(line);
    }
    const zr = zone.getBoundingClientRect();
    let ly;
    if (next) ly = next.getBoundingClientRect().top - 4;
    else if (items.length) ly = items[items.length - 1].getBoundingClientRect().bottom + 3;
    else ly = zr.top + 40;
    line.style.cssText = `left:${zr.left + 10}px;width:${zr.width - 20}px;top:${ly}px`;
    line.hidden = false;
  } else if (line) line.hidden = true;
  autoScroll(x, y, zone);
}

let asT = 0;
function autoScroll(x, y, zone) {
  cancelAnimationFrame(asT);
  const H = window.innerHeight, W = window.innerWidth;
  const edge = 70;
  let vy = 0, vx = 0;
  if (y < edge) vy = -Math.ceil((edge - y) / 6);
  else if (y > H - edge) vy = Math.ceil((y - (H - edge)) / 6);
  // Board: Ränder des sichtbaren Board-Bereichs (auf dem Mac endet er vor dem Fensterrand), nicht des Fensters
  const board = D?.el?.closest?.(".board-scroll") || (zone || document.elementFromPoint(x, y))?.closest?.(".board-scroll");
  if (board) {
    const br = board.getBoundingClientRect();
    const l = Math.max(0, br.left), r = Math.min(W, br.right);
    if (y > br.top - 60 && y < br.bottom + 60) {
      if (x < l + edge) vx = -Math.min(28, Math.ceil((l + edge - x) / 5));
      else if (x > r - edge) vx = Math.min(28, Math.ceil((x - (r - edge)) / 5));
    }
  }
  if (!vx && !vy) return;
  asT = requestAnimationFrame(() => {
    if (!D) return;
    if (vy) window.scrollBy(0, vy);
    if (vx && board) board.scrollLeft += vx;
    moveDrag(D.x, D.y);
  });
}

function endDrag(commit) {
  cancelAnimationFrame(asT);
  if (!D) return;
  const d = D;
  D = null;
  d.ghost.remove();
  if (line) line.hidden = true;
  d.zone?.classList.remove("drop-over");
  d.el.classList.remove("drag-src");
  d.el.removeAttribute("data-hold");
  document.documentElement.classList.remove("is-dragging");
  // Board-Position merken: Verschwindet eine Spalte (z. B. „Ohne Abschnitt“ leer), rastet der Browser sonst irgendwo neu ein
  const sc = d.el.closest?.(".board-scroll");
  const left = sc ? sc.scrollLeft : null;
  if (commit && d.zone) {
    const fn = drops[d.zone.dataset.drop];
    if (fn) {
      try {
        fn(d.id, d.zone, d.before, d.kind);
        haptic();
      } catch (e) {
        console.error(e);
      }
    }
  }
  if (left != null) keepBoardScroll(left);
}

function keepBoardScroll(left) {
  const fix = () => {
    const b = document.querySelector(".board-scroll");
    if (!b || D) return;
    const want = Math.min(left, b.scrollWidth - b.clientWidth);
    if (Math.abs(b.scrollLeft - want) > 2) b.scrollTo({ left: want, behavior: "instant" });
  };
  requestAnimationFrame(() => requestAnimationFrame(fix));
  setTimeout(fix, 220);
}

// Maus: ab 6 px Bewegung mit gedrückter Taste
let M = null;
function mouseDown(e) {
  if (e.pointerType !== "mouse" || e.button !== 0) return;
  const el = e.target.closest?.("[data-drag]");
  if (!el || e.target.closest("input, textarea, select, .check, .hv, .task-hover")) return;
  M = { el, x0: e.clientX, y0: e.clientY };
}
function mouseMove(e) {
  if (!M || e.pointerType !== "mouse") return;
  if (!D) {
    if (Math.hypot(e.clientX - M.x0, e.clientY - M.y0) < 6) return;
    startDrag(M.el, M.x0, M.y0);
  }
  moveDrag(e.clientX, e.clientY);
}
function mouseUp(e) {
  if (e.pointerType !== "mouse") return;
  if (D) {
    endDrag(e.type === "pointerup");
    suppressClick = performance.now() + 300;
  }
  M = null;
}

// ---------- 3D-Neigung für Karten (nur Maus) ----------
let tiltEl = null, tiltRaf = 0;
function tilt(e) {
  if (e.pointerType !== "mouse" || reducedMotion() || D) return;
  const el = e.target.closest?.(".tilt");
  if (tiltEl && tiltEl !== el) {
    tiltEl.style.removeProperty("--rx");
    tiltEl.style.removeProperty("--ry");
    tiltEl.classList.remove("tilting");
  }
  tiltEl = el;
  if (!el) return;
  cancelAnimationFrame(tiltRaf);
  tiltRaf = requestAnimationFrame(() => {
    const r = el.getBoundingClientRect();
    const px = (e.clientX - r.left) / r.width, py = (e.clientY - r.top) / r.height;
    el.style.setProperty("--rx", ((0.5 - py) * 7).toFixed(2) + "deg");
    el.style.setProperty("--ry", ((px - 0.5) * 9).toFixed(2) + "deg");
    el.style.setProperty("--mx", (px * 100).toFixed(1) + "%");
    el.style.setProperty("--my", (py * 100).toFixed(1) + "%");
    el.classList.add("tilting");
  });
}

// ---------- Start ----------
export function initGestures() {
  document.addEventListener("pointerdown", (e) => {
    swipeDown(e);
    mouseDown(e);
  });
  document.addEventListener("pointermove", (e) => {
    swipeMove(e);
    mouseMove(e);
    tilt(e);
  });
  document.addEventListener("pointerup", (e) => {
    swipeUp(e);
    mouseUp(e);
  });
  document.addEventListener("pointercancel", (e) => {
    swipeUp(e);
    mouseUp(e);
  });
  document.addEventListener("touchstart", touchStart, { passive: true });
  document.addEventListener("touchend", touchEnd);
  document.addEventListener("touchcancel", () => {
    if (D) endDrag(false);
    cancelPress();
  });
  // Klick nach Geste schlucken; offene Wisch-Zeile bei Tipp daneben schließen
  document.addEventListener(
    "click",
    (e) => {
      if (performance.now() < suppressClick) {
        e.preventDefault();
        e.stopPropagation();
        return;
      }
      if (openRow && !e.target.closest(".sw-acts")) {
        if (openRow.contains(e.target)) {
          e.preventDefault();
          e.stopPropagation();
        }
        closeOpenRow();
      } else if (openRow) setTimeout(() => closeOpenRow(), 0);
    },
    true,
  );
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && D) endDrag(false);
  });
  window.addEventListener("blur", () => D && endDrag(false));
}
