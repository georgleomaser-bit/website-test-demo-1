// Arbeitstaschen – Einstieg für „node --test taschen/tests/“: Node 22 behandelt den Ordner als Datei und lädt diese index.js
import { run } from "node:test";
import { spec } from "node:test/reporters";
import { readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const dir = path.dirname(fileURLToPath(import.meta.url));
const files = readdirSync(dir)
  .filter((f) => f.endsWith(".test.mjs"))
  .sort()
  .map((f) => path.join(dir, f));

// Jede Testdatei läuft wie gewohnt in einem eigenen Prozess; ohne das Löschen verweigert run() den verschachtelten Lauf
delete process.env.NODE_TEST_CONTEXT;
const stream = run({ files, concurrency: true });
stream.on("test:fail", (e) => {
  if (!e.todo) process.exitCode = 1;
});
stream.compose(spec).pipe(process.stdout);
