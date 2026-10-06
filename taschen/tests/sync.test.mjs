// Tests für den Krypto-Teil von sync.js – Code, Schlüsselableitung (HKDF), AES-GCM-Rundreise, falscher Schlüssel, Server-Adressen, „Vorsprung“-Erkennung
import { test, describe } from "node:test";
import assert from "node:assert/strict";

const { newCode, normalizeCode, derive, encrypt, decrypt, encryptBytes, decryptBytes, toB64, fromB64, normServer, ahead } = await import("../js/sync.js");

const CODE_RE = /^[0-9A-HJKMNP-TV-Z]{4}(-[0-9A-HJKMNP-TV-Z]{4}){5}$/;

// ---------- Code ----------
describe("Sync-Code", () => {
  test("newCode: 24 Zeichen Crockford-Base32 in 6 Gruppen à 4, zufällig", () => {
    const seen = new Set();
    for (let i = 0; i < 300; i++) {
      const c = newCode();
      assert.match(c, CODE_RE);
      assert.ok(!/[ILOU]/.test(c), "keine verwechselbaren Buchstaben");
      seen.add(c);
    }
    assert.equal(seen.size, 300, "keine Wiederholungen");
  });

  test("normalizeCode akzeptiert eigene Codes unverändert", () => {
    for (let i = 0; i < 50; i++) {
      const c = newCode();
      assert.equal(normalizeCode(c), c);
    }
  });

  test("normalizeCode toleriert Leerzeichen, fehlende Bindestriche, Kleinbuchstaben, O→0, I/L→1", () => {
    const c = "7K2M-QX9D-0A1B-CDEF-GHJK-MNPQ";
    assert.equal(normalizeCode("7k2mqx9d0a1bcdefghjkmnpq"), c);
    assert.equal(normalizeCode("  7K2M QX9D 0A1B CDEF GHJK MNPQ  "), c);
    assert.equal(normalizeCode("7K2M-QX9D-OAIB-CDEF-GHJK-MNPQ"), c, "O → 0, I → 1");
    assert.equal(normalizeCode("7K2M-QX9D-oalb-CDEF-GHJK-MNPQ"), c, "o → 0, l → 1");
    assert.equal(normalizeCode("7K2M–QX9D–0A1B–CDEF–GHJK–MNPQ"), c, "Gedankenstriche aus Notizen");
  });

  test("normalizeCode lehnt Ungültiges ab", () => {
    assert.equal(normalizeCode(""), null);
    assert.equal(normalizeCode("ABCD-EFGH"), null, "zu kurz");
    assert.equal(normalizeCode("7K2M-QX9D-0A1B-CDEF-GHJK-MNPQ-R"), null, "zu lang");
    assert.equal(normalizeCode("7K2M-QX9D-0A1B-CDEF-GHJK-MNPU"), null, "U gibt es nicht");
    assert.equal(normalizeCode("7K2M-QX9D-0A1B-CDEF-GHJK-MNP!"), null);
    assert.equal(normalizeCode(null), null);
    assert.equal(normalizeCode(12345), null);
  });
});

// ---------- Schlüssel ----------
describe("derive (HKDF-SHA-256)", () => {
  test("deterministisch: gleicher Code (auch anders geschrieben) → gleiche id", async () => {
    const c = newCode();
    const a = await derive(c);
    const b = await derive(c.toLowerCase().replace(/-/g, " "));
    assert.match(a.id, /^[0-9a-f]{64}$/);
    assert.equal(a.id, b.id);
  });

  test("verschiedene Codes → verschiedene ids; id verrät den Code nicht", async () => {
    const c1 = newCode();
    const c2 = newCode();
    const [a, b] = await Promise.all([derive(c1), derive(c2)]);
    assert.notEqual(a.id, b.id);
    assert.ok(!a.id.toUpperCase().includes(c1.replace(/-/g, "").slice(0, 8)));
  });

  test("bekannter Code ergibt stabile id (Format bleibt über Versionen gleich)", async () => {
    const { id } = await derive("0000-0000-0000-0000-0000-0000");
    const again = await derive("0000 0000 0000 0000 0000 0000");
    assert.equal(id, again.id);
    assert.match(id, /^[0-9a-f]{64}$/);
  });

  test("Schlüssel ist AES-GCM-256 und nicht exportierbar", async () => {
    const { key } = await derive(newCode());
    assert.equal(key.type, "secret");
    assert.equal(key.algorithm.name, "AES-GCM");
    assert.equal(key.algorithm.length, 256);
    assert.equal(key.extractable, false);
    assert.deepEqual([...key.usages].sort(), ["decrypt", "encrypt"]);
  });

  test("ungültiger Code wirft eine deutsche Fehlermeldung", async () => {
    await assert.rejects(() => derive("quatsch"), /Sync-Code ist ungültig/);
  });
});

// ---------- Verschlüsseln ----------
describe("encrypt/decrypt (AES-GCM)", () => {
  const state = () => ({
    v: 1,
    profile: { name: "Georg", updated: 5 },
    bags: [{ id: "b_1", name: "AKYTEX 📈", updated: 10, deleted: null }],
    tasks: [{ id: "t_1", title: "Größte Baustelle: „Pitch“ – fertig machen ✅", due: "2026-10-15", updated: 11, deleted: null }],
    notes: [],
    links: [],
    files: [],
    milestones: [],
    log: [],
  });

  test("Rundreise mit Umlauten und Emojis", async () => {
    const { key } = await derive(newCode());
    const obj = state();
    const b64 = await encrypt(key, obj);
    assert.equal(typeof b64, "string");
    assert.match(b64, /^[A-Za-z0-9+/]+=*$/);
    assert.deepEqual(await decrypt(key, b64), obj);
  });

  test("Aufbau: base64(iv(12) || Chiffretext mit 16-Byte-Prüfsumme); jedes Mal anderer IV", async () => {
    const { key } = await derive(newCode());
    const a = await encrypt(key, { x: 1 });
    const b = await encrypt(key, { x: 1 });
    assert.notEqual(a, b);
    const raw = fromB64(a);
    assert.equal(raw.length, 12 + JSON.stringify({ x: 1 }).length + 16);
    assert.notDeepEqual(fromB64(a).subarray(0, 12), fromB64(b).subarray(0, 12));
  });

  test("große Daten werden gepackt und kommen vollständig zurück", async () => {
    const { key } = await derive(newCode());
    const big = state();
    for (let i = 0; i < 2000; i++) big.tasks.push({ id: "t_" + i, title: `Aufgabe Nr. ${i} – „wichtig“ äöü`, updated: i, deleted: null });
    const json = JSON.stringify(big);
    const b64 = await encrypt(key, big);
    assert.ok(fromB64(b64).length < json.length / 3, "deutlich kleiner als das JSON");
    assert.deepEqual(await decrypt(key, b64), big);
  });

  test("falscher Schlüssel schlägt fehl", async () => {
    const a = await derive(newCode());
    const b = await derive(newCode());
    const b64 = await encrypt(a.key, state());
    await assert.rejects(() => decrypt(b.key, b64), /Entschlüsseln fehlgeschlagen/);
  });

  test("veränderte Daten schlagen fehl (Integrität)", async () => {
    const { key } = await derive(newCode());
    const raw = fromB64(await encrypt(key, state()));
    raw[raw.length - 20] ^= 1;
    await assert.rejects(() => decrypt(key, toB64(raw)), /Entschlüsseln fehlgeschlagen/);
    await assert.rejects(() => decrypt(key, "AAAA"), /unvollständig|beschädigt/);
  });

  test("Datei-Chiffretext ist an die Datei gebunden (AAD)", async () => {
    const { key } = await derive(newCode());
    const bytes = new Uint8Array(5000).map((_, i) => i % 251);
    const enc = await encryptBytes(key, bytes, "taschen/file/v1/f_a");
    assert.deepEqual(await decryptBytes(key, enc, "taschen/file/v1/f_a"), bytes);
    await assert.rejects(() => decryptBytes(key, enc, "taschen/file/v1/f_b"), /Entschlüsseln fehlgeschlagen/);
  });

  test("base64 hin und zurück (auch base64url, auch große Puffer)", () => {
    const u = new Uint8Array(200000).map((_, i) => (i * 7) % 256);
    assert.deepEqual(fromB64(toB64(u)), u);
    assert.deepEqual(fromB64(toB64(u).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")), u);
  });
});

// ---------- Server-Adresse & Abgleich ----------
describe("Server-Adresse", () => {
  test("normServer: https ergänzen, Schrägstriche und /api entfernen, http nur lokal", () => {
    assert.equal(normServer("taschen.1-2-3-4.sslip.io"), "https://taschen.1-2-3-4.sslip.io");
    assert.equal(normServer(" https://taschen.example.com/ "), "https://taschen.example.com");
    assert.equal(normServer("https://example.com/taschen/api/health"), "https://example.com/taschen");
    assert.equal(normServer("https://example.com/taschen/index.html"), "https://example.com/taschen");
    assert.equal(normServer("http://localhost:8082"), "http://localhost:8082");
    assert.equal(normServer("http://example.com"), "");
    assert.equal(normServer("https://user:pw@example.com"), "");
    assert.equal(normServer("javascript:alert(1)"), "");
    assert.equal(normServer(""), "");
  });
});

describe("Vorsprung erkennen (ahead)", () => {
  const base = () => ({ profile: { updated: 5 }, bags: [{ id: "b", updated: 10 }], tasks: [{ id: "t", updated: 20 }], notes: [], links: [], files: [], milestones: [], log: [{ id: "e1" }] });

  test("gleich → nichts hochzuladen; neuer/zusätzlicher Eintrag, Profil oder Logbuch → hochladen", () => {
    assert.equal(ahead(base(), base()), false);
    assert.equal(ahead(base(), null), true);
    const a = base();
    a.tasks[0].updated = 21;
    assert.equal(ahead(a, base()), true);
    const b = base();
    b.notes.push({ id: "n", updated: 1 });
    assert.equal(ahead(b, base()), true);
    const c = base();
    c.profile.updated = 6;
    assert.equal(ahead(c, base()), true);
    const d = base();
    d.log.push({ id: "e2" });
    assert.equal(ahead(d, base()), true);
  });

  test("älterer Stand oder fehlende Einträge lokal → nichts hochzuladen", () => {
    const remote = base();
    remote.tasks.push({ id: "t2", updated: 30 });
    remote.tasks[0].updated = 25;
    assert.equal(ahead(base(), remote), false);
  });
});
