// Kleine Helfer, die alle Module teilen
export const $ = (s, el = document) => el.querySelector(s);
export const $$ = (s, el = document) => [...el.querySelectorAll(s)];
export const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
export const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

let seq = 0;
export const uid = (prefix = "") => prefix + Date.now().toString(36) + (seq++ % 1296).toString(36).padStart(2, "0") + Math.random().toString(36).slice(2, 7);

export function debounce(fn, ms) {
  let t;
  const d = (...a) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...a), ms);
  };
  d.flush = (...a) => {
    clearTimeout(t);
    fn(...a);
  };
  return d;
}

// Gut lesbare Dateigröße: 1,2 MB
export function fmtSize(n) {
  if (!Number.isFinite(n)) return "";
  if (n < 1024) return n + " B";
  if (n < 1024 * 1024) return (n / 1024).toFixed(0) + " KB";
  return (n / 1024 / 1024).toFixed(1).replace(".", ",") + " MB";
}

// Nur http(s)-Links zulassen (kein javascript:)
export function safeUrl(u) {
  try {
    const x = new URL(String(u).trim(), typeof location !== "undefined" ? location.href : "https://localhost/");
    return x.protocol === "https:" || x.protocol === "http:" || x.protocol === "mailto:" ? x.href : "";
  } catch (_) {
    return "";
  }
}
