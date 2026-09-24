// Moderation für den AKYTEX-Server – Meldungen prüfen, Clips ausblenden/löschen, Nutzer sperren.
// Nutzung (ADMIN_TOKEN wie beim Server setzen, AKYTEX_URL = Adresse des Servers):
//   node server/admin.mjs reports              gemeldete Clips anzeigen
//   node server/admin.mjs clips                alle Clips anzeigen
//   node server/admin.mjs hide <clipId>        Clip ausblenden
//   node server/admin.mjs restore <clipId>     Clip nach Prüfung wieder freigeben
//   node server/admin.mjs delete <clipId>      Clip endgültig löschen
//   node server/admin.mjs ban <userId>         Nutzer sperren (unban zum Entsperren)
//   node server/admin.mjs user-reports         gemeldete Nutzer aus der Lounge anzeigen
const base = (process.env.AKYTEX_URL || "http://localhost:8080").replace(/\/$/, "") + "/api/admin";
const token = process.env.ADMIN_TOKEN;
const [cmd, arg] = process.argv.slice(2);
if (!token) throw new Error("Bitte ADMIN_TOKEN setzen.");
const call = async (method, path) => {
  const r = await fetch(base + path, { method, headers: { Authorization: "Bearer " + token } });
  const d = await r.json();
  if (!d.ok) throw new Error(d.msg);
  return d;
};
const show = (c) => `${c.id}  @${c.handle} (${c.author})  ${c.hidden ? "[AUSGEBLENDET] " : ""}${c.caption}  → Video: ${process.env.AKYTEX_URL || "http://localhost:8080"}/api/videos/${c.id}`;
if (cmd === "reports") {
  const { reports } = await call("GET", "/reports");
  if (!reports.length) console.log("Keine offenen Meldungen.");
  for (const r of reports) console.log(show(r.clip) + "\n  " + r.reports.map((x) => `${new Date(x.ts).toLocaleString("de-DE")}: ${x.reason}`).join("\n  "));
} else if (cmd === "user-reports") {
  const { reports } = await call("GET", "/user-reports");
  if (!reports.length) console.log("Keine Meldungen zu Nutzern.");
  for (const r of reports) console.log(`${new Date(r.ts).toLocaleString("de-DE")}  @${r.handle} (${r.user})  ${r.where ? "[" + r.where + "] " : ""}${r.reason}`);
} else if (cmd === "clips") (await call("GET", "/clips")).clips.forEach((c) => console.log(show(c)));
else if (["hide", "restore", "delete"].includes(cmd) && arg) console.log((await call("POST", `/clips/${arg}/${cmd}`)).ok ? "Erledigt." : "");
else if (["ban", "unban"].includes(cmd) && arg) console.log((await call("POST", `/users/${arg}/${cmd}`)).ok ? "Erledigt." : "");
else console.log("Befehle: reports | user-reports | clips | hide <id> | restore <id> | delete <id> | ban <userId> | unban <userId>");
