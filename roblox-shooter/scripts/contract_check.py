#!/usr/bin/env python3
"""Vertrags-Prüfer für Clutch Clash: findet Lücken zwischen Paketen, die luau-lsp nicht sieht
(Services ist `any`, ctx.Modules ist dynamisch, Request-Aktionen/Lang-Schlüssel sind Strings).
Ausgabe: eine Zeile je Problem "datei:zeile: ERROR|WARN: art: nachricht". Exit 1 bei ERRORs."""
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
SRC = os.path.join(ROOT, "src")


def files(sub, ext=".luau"):
    out = []
    for d, _, fs in os.walk(os.path.join(SRC, sub)):
        for f in fs:
            if f.endswith(ext):
                out.append(os.path.join(d, f))
    return sorted(out)


def read(p):
    with open(p, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def strip_comments(text):
    # Block-Kommentare --[[ ... ]] und --[=[ ... ]=] entfernen, Zeilen bleiben erhalten
    def blank(m):
        return re.sub(r"[^\n]", " ", m.group(0))

    text = re.sub(r"--\[(=*)\[.*?\]\1\]", blank, text, flags=re.S)
    # Zeilenkommentare (grob: -- außerhalb von Strings)
    lines = []
    for line in text.split("\n"):
        out, i, q = [], 0, None
        while i < len(line):
            c = line[i]
            if q:
                out.append(c)
                if c == "\\":
                    if i + 1 < len(line):
                        out.append(line[i + 1])
                    i += 2
                    continue
                if c == q:
                    q = None
            else:
                if c in "\"'`":
                    q = c
                elif line.startswith("--", i):
                    break
                out.append(c)
            i += 1
        lines.append("".join(out))
    return "\n".join(lines)


def rel(p):
    return os.path.relpath(p, ROOT)


def lineno(text, idx):
    return text.count("\n", 0, idx) + 1


problems = []


def report(path, line, level, kind, msg):
    problems.append((rel(path), line, level, kind, msg))


def exported_names(text, modvar=None):
    """Felder, die ein Modul exportiert: function M.X / M.X = / function M:X."""
    names = set()
    if modvar is None:
        m = re.search(r"\breturn\s+([A-Za-z_]\w*)\s*$", text.strip())
        modvar = m.group(1) if m else None
    if modvar:
        for m in re.finditer(r"\bfunction\s+" + re.escape(modvar) + r"[.:]([A-Za-z_]\w*)", text):
            names.add(m.group(1))
        for m in re.finditer(r"(?m)^\s*" + re.escape(modvar) + r"\.([A-Za-z_]\w*)\s*=(?!=)", text):
            names.add(m.group(1))
        # Tabellen-Konstruktor: local M = { X = ..., }
        m = re.search(r"\blocal\s+" + re.escape(modvar) + r"\s*(?::[^=]+)?=\s*\{", text)
        if m:
            depth, i = 0, m.end() - 1
            while i < len(text):
                c = text[i]
                if c == "{":
                    depth += 1
                elif c == "}":
                    depth -= 1
                    if depth == 0:
                        break
                elif depth == 1:
                    mm = re.match(r"([A-Za-z_]\w*)\s*=(?!=)", text[i:])
                    if mm and (i == 0 or not (text[i - 1].isalnum() or text[i - 1] in "_.")):
                        names.add(mm.group(1))
                        i += len(mm.group(0))
                        continue
                i += 1
    return names, modvar


# ---------------------------------------------------------------- 1) Server-Services
service_files = {os.path.splitext(os.path.basename(p))[0]: p for p in files("server/Services")}
service_api = {}
for name, p in service_files.items():
    service_api[name], _ = exported_names(strip_comments(read(p)))

net_text = read(os.path.join(SRC, "shared", "Net.luau")) if os.path.exists(os.path.join(SRC, "shared", "Net.luau")) else ""
remote_names = set(re.findall(r'\{\s*Name\s*=\s*"([A-Za-z]+)"\s*,\s*Class', net_text))

server_files = files("server")
for p in server_files:
    t = strip_comments(read(p))
    for m in re.finditer(r"\bServices\.([A-Za-z_]\w*)(?:\.([A-Za-z_]\w*))?", t):
        svc, fn = m.group(1), m.group(2)
        ln = lineno(t, m.start())
        if svc == "Remotes":
            if fn and fn not in remote_names:
                report(p, ln, "ERROR", "remote", f"Services.Remotes.{fn} ist nicht in Net.RemoteList")
            continue
        if svc not in service_files:
            report(p, ln, "ERROR", "service", f"Services.{svc} – Service-Datei existiert nicht")
            continue
        if fn and fn not in service_api[svc]:
            report(p, ln, "ERROR", "service-api", f"Services.{svc}.{fn} – {svc} exportiert '{fn}' nicht")

# ---------------------------------------------------------------- 2) Client-Module
module_files = {os.path.splitext(os.path.basename(p))[0]: p for p in files("client/Modules")}
module_api = {}
for name, p in module_files.items():
    module_api[name], _ = exported_names(strip_comments(read(p)))

client_files = files("client")
for p in client_files:
    t = strip_comments(read(p))
    for m in re.finditer(r"\b(?:ctx\.)?Modules\.([A-Za-z_]\w*)(?:\.([A-Za-z_]\w*))?", t):
        mod, fn = m.group(1), m.group(2)
        ln = lineno(t, m.start())
        if mod not in module_files:
            report(p, ln, "ERROR", "module", f"Modules.{mod} – Modul-Datei existiert nicht")
            continue
        if fn and fn not in module_api[mod] and fn not in ("Init", "Start"):
            report(p, ln, "ERROR", "module-api", f"Modules.{mod}.{fn} – {mod} exportiert '{fn}' nicht")
        if fn in ("Init", "Start") and fn not in module_api[mod]:
            report(p, ln, "WARN", "module-api", f"Modules.{mod}.{fn} fehlt (Main startet es per pcall?)")

# Main.client: Modul-Registry (Strings in einer Liste)
main_client = os.path.join(SRC, "client", "Main.client.luau")
if os.path.exists(main_client):
    t = strip_comments(read(main_client))
    for m in re.finditer(r'"([A-Z][A-Za-z]+)"', t):
        name = m.group(1)
        # nur Namen, die nach Modulen aussehen und irgendwo als WaitForChild/require-Liste stehen
        if name in module_files:
            continue
    # require(Modules:WaitForChild("X"))
    for m in re.finditer(r'WaitForChild\(\s*"([A-Za-z]+)"', t):
        pass


# ---------------------------------------------------------------- 2b) indirekte Zugriffe: call("X","Fn"), Aliase
def check_indirect(paths, api, side):
    names = set(api.keys())
    for p in paths:
        t = strip_comments(read(p))
        # a) Hilfsfunktionen mit zwei String-Argumenten: try("CombatService", "OfPlayer", ...)
        for m in re.finditer(r'\b[A-Za-z_]\w*\(\s*"([A-Z]\w*)"\s*,\s*"([A-Za-z_]\w*)"', t):
            mod, fn = m.group(1), m.group(2)
            if mod in names and fn not in api[mod] and fn not in ("Init", "Start"):
                report(p, lineno(t, m.start()), "ERROR", side + "-api", f'{mod}.{fn} (über Hilfsfunktion) – {mod} exportiert "{fn}" nicht')
        # b) Aliase: local A = Services.X / Services["X"] / ctx.Modules.X / svc("X")
        aliases = {}
        for m in re.finditer(r'\blocal\s+([A-Za-z_]\w*)\s*(?::[^=\n]+)?=\s*(?:\(?\s*)?(?:ctx\.)?(?:Services|Modules|mods|modules)(?:\.([A-Z]\w*)|\[\s*"([A-Z]\w*)"\s*\])', t):
            target = m.group(2) or m.group(3)
            if target in names:
                aliases[m.group(1)] = target
        for m in re.finditer(r'\blocal\s+([A-Za-z_]\w*)\s*(?::[^=\n]+)?=\s*[A-Za-z_]\w*\(\s*"([A-Z]\w*)"\s*\)', t):
            if m.group(2) in names:
                aliases[m.group(1)] = m.group(2)
        for alias, target in aliases.items():
            # nur eindeutige Aliase: genau eine Deklaration, keine Neuzuweisung (sonst Scope-Verwechslung)
            decls = len(re.findall(r'\blocal\s+' + re.escape(alias) + r'\b', t))
            reassign = re.search(r'(?<![\w.])' + re.escape(alias) + r'\s*=(?!=)', t)
            params = re.search(r'function[^(]*\([^)]*\b' + re.escape(alias) + r'\b', t)
            if decls != 1 or reassign or params:
                continue
            for m in re.finditer(r'(?<![\w.])' + re.escape(alias) + r'(?:\.([A-Za-z_]\w*)|:([A-Za-z_]\w*)\()', t):
                fn = m.group(1) or m.group(2)
                if fn not in api[target] and fn not in ("Init", "Start"):
                    report(p, lineno(t, m.start()), "ERROR", side + "-api", f'{alias}.{fn} (Alias für {target}) – {target} exportiert "{fn}" nicht')
        # c) svc("X").Fn / svc("X"):Fn
        for m in re.finditer(r'\b[A-Za-z_]\w*\(\s*"([A-Z]\w*)"\s*\)\s*[.:]\s*([A-Za-z_]\w*)', t):
            mod, fn = m.group(1), m.group(2)
            if mod in names and fn not in api[mod]:
                report(p, lineno(t, m.start()), "ERROR", side + "-api", f'{mod}.{fn} – {mod} exportiert "{fn}" nicht')


check_indirect(server_files, service_api, "service")
check_indirect(client_files, module_api, "module")
empty = [n for n, a in list(service_api.items()) + list(module_api.items()) if not a]
for n in empty:
    print(f"(Hinweis) keine Exporte erkannt in {n}", file=sys.stderr)

# ---------------------------------------------------------------- 3) require-Ziele (WaitForChild in require-Ketten)
all_files = files("")
shared_names = {os.path.splitext(os.path.basename(p))[0] for p in files("shared")}
server_names = {os.path.splitext(os.path.basename(p))[0].replace(".server", "") for p in server_files}
client_names = {os.path.splitext(os.path.basename(p))[0].replace(".client", "") for p in client_files}
dir_names = set()
for d, ds, _ in os.walk(SRC):
    for x in ds:
        dir_names.add(x)
known = shared_names | server_names | client_names | dir_names | {"Shared", "Server", "Client", "Modules", "Remotes"}
for p in all_files:
    t = strip_comments(read(p))
    for m in re.finditer(r"require\(([^()]*(?:\([^()]*\)[^()]*)*)\)", t):
        chain = m.group(1)
        for mm in re.finditer(r'WaitForChild\(\s*"([A-Za-z_]\w*)"', chain):
            nm = mm.group(1)
            if nm not in known:
                report(p, lineno(t, m.start()), "ERROR", "require", f'require-Ziel "{nm}" existiert nicht')

# ---------------------------------------------------------------- 4) Request-Aktionen
handled = {}
for p in server_files:
    t = strip_comments(read(p))
    for m in re.finditer(r'\bHandle\(\s*"([A-Za-z]+)"', t):
        handled.setdefault(m.group(1), (p, lineno(t, m.start())))
requested = {}
for p in client_files:
    t = strip_comments(read(p))
    for m in re.finditer(r'\bRequest(?:Full)?\(\s*"([A-Za-z]+)"', t):
        requested.setdefault(m.group(1), []).append((p, lineno(t, m.start())))
    # Request-Aktion als Variable in Tabellen: Action = "X" (z.B. Knöpfe) -> nur informativ
for act, locs in sorted(requested.items()):
    if act not in handled:
        for p, ln in locs:
            report(p, ln, "ERROR", "request", f'Request "{act}" hat keinen Server-Handler (PlayerStateService.Handle)')
for act, (p, ln) in sorted(handled.items()):
    if act not in requested:
        report(p, ln, "WARN", "request", f'Handler "{act}" wird vom Client nie direkt mit Literal angefragt')

# ---------------------------------------------------------------- 5) Remotes (Client/Server-Zugriffe)
for p in all_files:
    t = strip_comments(read(p))
    for m in re.finditer(r"\b([A-Za-z_]*[Rr]emotes)\.([A-Z][A-Za-z]*)\b", t):
        var, nm = m.group(1), m.group(2)
        if var in ("Services",):
            continue
        if nm not in remote_names:
            report(p, lineno(t, m.start()), "ERROR", "remote", f"{var}.{nm} ist nicht in Net.RemoteList")
    for m in re.finditer(r'GetRemotes\(\)\s*\[\s*"([A-Za-z]+)"\s*\]', t):
        if m.group(1) not in remote_names:
            report(p, lineno(t, m.start()), "ERROR", "remote", f'GetRemotes()["{m.group(1)}"] ist nicht in Net.RemoteList')

# ---------------------------------------------------------------- 6) Lang-Schlüssel
LANG_PREFIX = ("core", "world", "combat", "match", "bot", "admin", "prog", "shop", "items", "ui")
lang_keys = set()
lang_files = files("shared/Lang")
for p in lang_files:
    t = read(p)
    for m in re.finditer(r'\[\s*"([a-z]+\.[A-Za-z0-9_.]+)"\s*\]\s*=', t):
        lang_keys.add(m.group(1))
key_re = re.compile(r'"((?:' + "|".join(LANG_PREFIX) + r')\.[A-Za-z0-9_.]*[A-Za-z0-9_])"')
for p in all_files:
    if p in lang_files:
        continue
    t = strip_comments(read(p))
    for m in key_re.finditer(t):
        key = m.group(1)
        after = t[m.end():m.end() + 4]
        if after.lstrip().startswith(".."):
            continue  # Präfix für zusammengesetzte Schlüssel
        if key not in lang_keys:
            # Nur melden, wenn der Präfix-Raum existiert (sonst eher kein Lang-Schlüssel)
            report(p, lineno(t, m.start()), "ERROR", "lang", f'Lang-Schlüssel "{key}" fehlt in src/shared/Lang')

# ---------------------------------------------------------------- 7) Config-Abschnitte
cfg_dir = os.path.join(SRC, "shared", "Config")
cfg_children = {os.path.splitext(f)[0] for f in os.listdir(cfg_dir)} if os.path.isdir(cfg_dir) else set()
cfg_init = read(os.path.join(cfg_dir, "init.luau")) if os.path.exists(os.path.join(cfg_dir, "init.luau")) else ""
cfg_top = set(re.findall(r"(?m)^\s*Config\.([A-Za-z_]\w*)\s*=", cfg_init)) | set(
    re.findall(r"\bfunction\s+Config[.:]([A-Za-z_]\w*)", cfg_init)
)
# Kind-Module werden unter ihrem Dateinamen eingehängt
cfg_known = cfg_top | (cfg_children - {"init"})
for p in all_files:
    t = strip_comments(read(p))
    for m in re.finditer(r"\bConfig\.([A-Z][A-Za-z_]\w*)", t):
        sec = m.group(1)
        if sec not in cfg_known:
            report(p, lineno(t, m.start()), "ERROR", "config", f"Config.{sec} existiert nicht (weder in Config/init noch als Kind-Modul)")

# ---------------------------------------------------------------- 8) Hooks (nur Hinweise)
fired, fired_prefix, listened = set(), set(), {}
for p in client_files:
    t = strip_comments(read(p))
    for m in re.finditer(r'\bHooks\.Fire\(\s*"([A-Za-z:]+)"\s*(\.\.)?', t):
        if m.group(2):
            fired_prefix.add(m.group(1))
        else:
            fired.add(m.group(1))
    for m in re.finditer(r'\bFire\(\s*"([A-Za-z:]+)"\s*\.\.', t):
        fired_prefix.add(m.group(1))
    for m in re.finditer(r'\bHooks\.(?:On|Once)\(\s*"([A-Za-z:]+)"', t):
        listened.setdefault(m.group(1), (p, lineno(t, m.start())))
for h, (p, ln) in sorted(listened.items()):
    if h in fired or any(h.startswith(pre) for pre in fired_prefix):
        continue
    report(p, ln, "WARN", "hook", f'Hook "{h}" wird gehört, aber nirgends mit Literal gefeuert')

problems.sort()
errors = 0
for path, line, level, kind, msg in problems:
    if level == "ERROR":
        errors += 1
    print(f"{path}:{line}: {level}: {kind}: {msg}")
print(f"-- {errors} ERRORs, {len(problems) - errors} WARNs")
sys.exit(1 if errors else 0)
