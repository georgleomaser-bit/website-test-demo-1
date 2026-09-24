// Service Worker: macht AKYTEX offline nutzbar und installierbar.
const VERSION = "akytex-v3.5.1";
const ASSETS = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./css/app.css",
  "./css/fonts.css",
  "./fonts/manrope-latin-400-normal.woff2",
  "./fonts/manrope-latin-500-normal.woff2",
  "./fonts/manrope-latin-600-normal.woff2",
  "./fonts/manrope-latin-700-normal.woff2",
  "./fonts/manrope-latin-800-normal.woff2",
  "./fonts/unbounded-latin-300-normal.woff2",
  "./fonts/unbounded-latin-500-normal.woff2",
  "./fonts/unbounded-latin-600-normal.woff2",
  "./fonts/unbounded-latin-700-normal.woff2",
  "./js/app.js",
  "./js/data.js",
  "./js/market.js",
  "./js/broker.js",
  "./js/chart.js",
  "./js/indicators.js",
  "./js/analysis.js",
  "./js/plans.js",
  "./js/community.js",
  "./js/ai.js",
  "./js/payments.js",
  "./js/config.js",
  "./js/live.js",
  "./js/ailab.js",
  "./js/scheduler.js",
  "./js/shop.js",
  "./js/clips.js",
  "./404.html",
  "./icons/og-image.png",
  "./js/vendor/lightweight-charts.standalone.production.js",
  "./icons/icon.svg",
  "./icons/logo.svg",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/icon-maskable-512.png",
  "./icons/apple-touch-icon.png",
  "./icons/favicon-64.png",
];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(VERSION).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k)))).then(() => self.clients.claim())
  );
});

// Netzwerk zuerst (immer aktuell), bei Offline aus dem Cache
self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET" || new URL(req.url).origin !== location.origin) return;
  e.respondWith(
    fetch(req)
      .then((res) => {
        const copy = res.clone();
        caches.open(VERSION).then((c) => c.put(req, copy));
        return res;
      })
      .catch(() => caches.match(req, { ignoreSearch: true }).then((r) => r || caches.match("./index.html")))
  );
});

self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  e.waitUntil(
    self.clients.matchAll({ type: "window" }).then((list) => (list.length ? list[0].focus() : self.clients.openWindow("./")))
  );
});
