// Arbeitstaschen – Einstieg: Service Worker früh registrieren (überdeckt den AKYTEX-Root-SW), dann die App starten
import "./app.js";

// ---------- Service Worker ----------
if ("serviceWorker" in navigator && location.protocol !== "file:") {
  const hadController = !!navigator.serviceWorker.controller;
  let reloading = false;
  navigator.serviceWorker.addEventListener("controllerchange", () => {
    // nur neu laden, wenn vorher schon eine Version lief (sonst wäre es der erste Start)
    if (!hadController || reloading) return;
    reloading = true;
    setTimeout(() => location.reload(), 600);
  });
  navigator.serviceWorker
    .register("./sw.js", { updateViaCache: "none" })
    .then((reg) => {
      const check = () => reg.update().catch(() => {});
      check();
      setInterval(check, 15 * 60000);
      document.addEventListener("visibilitychange", () => document.visibilityState === "visible" && check());
    })
    .catch(() => {
      /* ohne Service Worker – App läuft trotzdem */
    });
}
