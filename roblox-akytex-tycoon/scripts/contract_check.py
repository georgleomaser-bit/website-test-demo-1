#!/usr/bin/env python3
"""Vertrags-Prüfer für AKYTEX Tycoon: findet Lücken zwischen Paketen, die luau-lsp nicht sieht
(Services ist `any`, ctx.Modules ist dynamisch, Request-Aktionen/Lang-Schlüssel/Effekte/State-Schlüssel sind Strings)
und setzt die Compliance-Regeln der Spec durch (DESIGN.md §C11.4, §0.7, §C7.4, §C10).
Aufruf (im Projektordner):  python3 scripts/contract_check.py .
Ausgabe: eine Zeile je Problem "datei:zeile: ERROR|WARN: art: nachricht". Exit 1 bei ERRORs.

Abschnitte:
   1) Services.X.Fn / Services["X"]:Fn existiert          2) ctx.Modules.X.Fn existiert
  2b) indirekte Aufrufe: call("X","Fn")/has/tryModule, Getter-Aliase (service("X"), serviceModule(services,"X")),
      Ketten getter("X").Fn, Ein-Ziel-Hilfen (hudCall("Fn") -> Modules.Hud[fn])
  2c) Lader-Registries (MODULE_ORDER/ADMIN/FRAME/TICK/LIBRARY, Main.server order) + ctx-Felder aus Main.client
   3) require-Ziele gegen den Rojo-Baum (default.project.json) + WaitForChild auf nicht existierende Quell-Kinder
   4) Request-Aktionen (+ frozen §C9) inkl. lokaler Wrapper (request("X"), Request("X"), pcall(ctx.RequestFull, …))
  4b) Admin-Aktionen (Remote "Admin" -> AdminService Actions.X)
   5) Remotes ∈ Net.RemoteList (Felder, ["X"], FindFirstChild, Namenslisten/Handler-Tabellen)
   6) Lang-Schlüssel (LANG_PREFIX §C15): vorhanden, de/en vollständig, Präfix je Datei, keine Doppelten,
      zusammengesetzte Präfixe ("prog.les." .. id) treffen Schlüssel, Übersetzer-Literale mit gültigem Präfix
   7) Config-Abschnitte + Schlüssel der 2. Ebene (direkt und über Aliase)   8) Hooks (+ frozen §C7.2)
   9) FIREWALL (§C11.4 #1/#2)           10) DEPOT_WRITE (§C11.4 #3)          10b) FIREWALL_ROBUX (§C11.4 #4/#5)
  11) BANNED_WORDS (§0.7)              12) EFFECTS (§C7.4)                   13) STATE_KEYS (§C10)
Abdeckung je Regel (wie oft ein Muster gegriffen hat) steht auf stderr – 0 heißt: Regel versteht das Projekt nicht.
"""
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


def blank_strings(text):
    """Inhalt von String-Literalen durch Leerzeichen ersetzen (Anführungszeichen bleiben, Zeilen bleiben)."""

    def blank(m):
        return re.sub(r"[^\n]", " ", m.group(0))

    text = re.sub(r"\[(=*)\[.*?\]\1\]", blank, text, flags=re.S)
    out, i, q = [], 0, None
    while i < len(text):
        c = text[i]
        if q:
            if c == "\\" and i + 1 < len(text):
                out.append("  ")
                i += 2
                continue
            if c == q or c == "\n":
                q = None
                out.append(c)
            else:
                out.append(" ")
        else:
            if c in "\"'`":
                q = c
            out.append(c)
        i += 1
    return "".join(out)


def rel(p):
    return os.path.relpath(p, ROOT).replace(os.sep, "/")


def lineno(text, idx):
    return text.count("\n", 0, idx) + 1


# Zeilenende eines Ausdrucks, der NICHT in der nächsten Zeile weitergeht (`and …`, `.Feld`, `[i]`, `..`)
EXPR_END = r"(?=\n(?![ \t]*(?:and\b|or\b|\.\.|[.:\[(+\-*/%^])))"

problems = []
stats = {}  # Abdeckung je Regel (stderr): zeigt, dass ein Muster überhaupt greift


def report(path, line, level, kind, msg):
    problems.append((rel(path), line, level, kind, msg))


def seen(rule, n=1):
    stats[rule] = stats.get(rule, 0) + n


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


# ---------------------------------------------------------------- Lua-String-Leser (für Lang/Config-Texte)
def parse_string_at(text, i):
    """Liest ein String-Literal ab Position i ("…", '…', [[…]], [=[…]=]); gibt (wert, ende) oder (None, i)."""
    if i >= len(text):
        return None, i
    c = text[i]
    if c in "\"'":
        out, j = [], i + 1
        while j < len(text) and text[j] != c and text[j] != "\n":
            if text[j] == "\\" and j + 1 < len(text):
                nxt = text[j + 1]
                out.append({"n": "\n", "t": "\t"}.get(nxt, nxt))
                j += 2
                continue
            out.append(text[j])
            j += 1
        return "".join(out), j + 1
    m = re.match(r"\[(=*)\[", text[i:])
    if m:
        close = "]" + m.group(1) + "]"
        end = text.find(close, i + len(m.group(0)))
        if end < 0:
            return None, i
        return text[i + len(m.group(0)):end], end + len(close)
    return None, i


def parse_concat_at(text, i):
    """String-Literal inkl. Verkettung mit `..` weiterer Literale."""
    value, j = parse_string_at(text, i)
    if value is None:
        return None, i
    parts = [value]
    while True:
        m = re.match(r"\s*\.\.\s*", text[j:])
        if not m:
            break
        nxt, k = parse_string_at(text, j + len(m.group(0)))
        if nxt is None:
            break
        parts.append(nxt)
        j = k
    return "".join(parts), j


# ---------------------------------------------------------------- 1) Server-Services
service_files = {os.path.splitext(os.path.basename(p))[0]: p for p in files("server/Services")}
service_api = {}
for name, p in service_files.items():
    service_api[name], _ = exported_names(strip_comments(read(p)))

net_text = read(os.path.join(SRC, "shared", "Net.luau")) if os.path.exists(os.path.join(SRC, "shared", "Net.luau")) else ""
remote_names = set(re.findall(r'\{\s*Name\s*=\s*"(\w+)"\s*,\s*Class', net_text))
# Services/Remotes ist kein Service, sondern die Tabelle Name -> Remote (aus Net.RemoteList)
if "Remotes" in service_api:
    service_api["Remotes"] = set(remote_names)

server_files = files("server")
for p in server_files:
    t = strip_comments(read(p))
    for m in re.finditer(r'\bServices(?:\.([A-Za-z_]\w*)|\[\s*"([A-Za-z_]\w*)"\s*\])(?:[.:]([A-Za-z_]\w*))?', t):
        svc, fn = (m.group(1) or m.group(2)), m.group(3)
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
    for m in re.finditer(r'\b(?:ctx\.)?Modules(?:\.([A-Za-z_]\w*)|\[\s*"([A-Za-z_]\w*)"\s*\])(?:[.:]([A-Za-z_]\w*))?', t):
        mod, fn = (m.group(1) or m.group(2)), m.group(3)
        ln = lineno(t, m.start())
        if mod not in module_files:
            report(p, ln, "ERROR", "module", f"Modules.{mod} – Modul-Datei existiert nicht")
            continue
        if fn and fn not in module_api[mod] and fn not in ("Init", "Start"):
            report(p, ln, "ERROR", "module-api", f"Modules.{mod}.{fn} – {mod} exportiert '{fn}' nicht")
        if fn in ("Init", "Start") and fn not in module_api[mod]:
            report(p, ln, "WARN", "module-api", f"Modules.{mod}.{fn} fehlt (Main startet es per pcall?)")


# ---------------------------------------------------------------- 2b) indirekte Zugriffe: call("X","Fn"), Aliase
def iter_functions(text):
    """Funktionen im (stylua-formatierten) Text: (name, [params], body_start, body_end).
    Ende = erste Zeile mit derselben Einrückung, die mit `end` beginnt."""
    for m in re.finditer(r"(?m)^([ \t]*)(?:local\s+)?function\s+([A-Za-z_][\w.:]*)\s*\(([^)]*)\)", text):
        indent = m.group(1)
        params = [x.split(":")[0].strip() for x in m.group(3).split(",") if x.strip()]
        end = re.compile(r"(?m)^" + re.escape(indent) + r"end\b").search(text, m.end())
        yield m.group(2), params, m.end(), (end.start() if end else len(text))


def reassigned(text, name):
    """Wird `name` irgendwo neu zugewiesen (nicht die eigene `local name =`-Deklaration)?"""
    for m in re.finditer(r'(?<![\w.])' + re.escape(name) + r'\s*=(?!=)', text):
        line_start = text.rfind("\n", 0, m.start()) + 1
        if not re.search(r'\blocal\s+(?:[A-Za-z_]\w*\s*(?::[^,=]+)?,\s*)*$', text[line_start:m.start()]):
            return True
    return False


def local_decls(text, name):
    """Anzahl lokaler Deklarationen von `name`, auch in Namenslisten (`local ok, name = …`)."""
    return len(re.findall(r"\blocal\s+(?:[A-Za-z_]\w*\s*(?::[^,=\n]+)?,\s*)*" + re.escape(name) + r"\b(?!\s*\()", text))


def shadowed(text, name):
    """Gibt es `name` auch als Funktionsparameter oder Schleifenvariable (andere Bedeutung im selben File)?"""
    if re.search(r"function[^(\n]*\([^)]*(?<![\w.])" + re.escape(name) + r"\b", text):
        return True
    return bool(re.search(r"\bfor\s+[^=\n]*?(?<![\w.])" + re.escape(name) + r"\b[^=\n]*\bin\b|\bfor\s+" + re.escape(name) + r"\s*=", text))


def check_indirect(paths, api, side):
    names = set(api.keys())
    for p in paths:
        t = strip_comments(read(p))
        plain = blank_strings(t)  # gleiche Länge/Zeilen; Alias-Zugriffe nur außerhalb von Strings
        # a) Hilfsfunktionen mit zwei String-Argumenten: call("TowerService", "Income", ...) / has(…) / tryModule(…)
        for m in re.finditer(r'\b[A-Za-z_]\w*\(\s*"([A-Z]\w*)"\s*,\s*"([A-Za-z_]\w*)"', t):
            mod, fn = m.group(1), m.group(2)
            if mod in names:
                seen(side + "-helper-call")
            if mod in names and fn not in api[mod] and fn not in ("Init", "Start"):
                report(p, lineno(t, m.start()), "ERROR", side + "-api", f'{mod}.{fn} (über Hilfsfunktion) – {mod} exportiert "{fn}" nicht')
        # b) Aliase: local A = Services.X / Services["X"] / ctx.Modules.X / ctx and ctx.Modules and ctx.Modules.X /
        #    svc("X") / serviceModule(services, "X") – mehrere Deklarationen zählen, wenn alle auf dasselbe Ziel zeigen
        decl_targets = {}
        # Getter = Funktion, deren Rumpf Services/Modules mit einem ihrer Parameter indiziert (service(name), module(name),
        # serviceModule(services, name)) – nicht jede Funktion mit String-Argument (stateOf("Quests") ist kein Modul)
        getters = []
        for fname, fparams, b0, b1 in iter_functions(t):
            if "." in fname or ":" in fname:
                continue
            body = t[b0:b1]
            for pi, param in enumerate(fparams[:2]):
                if re.search(r'\b(?:[Ss]ervices|[Mm]odules|mods|svc)\s*\[\s*' + re.escape(param) + r'\s*\]', body):
                    getters.append((fname, pi))
                    break
        alias_patterns = [
            r'\blocal\s+([A-Za-z_]\w*)\s*(?::[^=\n]+)?=\s*(?:\(?\s*)?(?:[A-Za-z_][\w.]*\s+and\s+)*(?:ctx\.)?(?:Services|Modules|mods|modules)(?:\.([A-Z]\w*)|\[\s*"([A-Z]\w*)"\s*\])\s*(?:::\s*any\s*)?(?:' + EXPR_END + r'|(?=;|\s+or\b))',
        ]
        for gname, gi in getters:
            lead = r'(?:[A-Za-z_][\w.]*\s*,\s*)' * gi
            alias_patterns.append(r'\blocal\s+([A-Za-z_]\w*)\s*(?::[^=\n]+)?=\s*' + re.escape(gname) + r'\(\s*' + lead + r'"([A-Z]\w*)"\s*\)()\s*(?:::\s*any\s*)?(?:' + EXPR_END + r'|(?=;|\s+or\b))')
        for pattern in alias_patterns:
            for m in re.finditer(pattern, t):
                target = m.group(2) or m.group(3)
                decl_targets.setdefault(m.group(1), []).append(target)
        for alias, targets in decl_targets.items():
            target = targets[0]
            # nur eindeutige Aliase: jede Deklaration zeigt auf dasselbe Ziel, keine Neuzuweisung, kein gleichnamiger Parameter
            decls = local_decls(t, alias)
            reassign = reassigned(t, alias)
            if target not in names or any(x != target for x in targets) or decls != len(targets) or reassign or shadowed(t, alias):
                continue
            for m in re.finditer(r'(?<![\w.])' + re.escape(alias) + r'(?:\.([A-Za-z_]\w*)|:([A-Za-z_]\w*)\()', plain):
                fn = m.group(1) or m.group(2)
                seen(side + "-alias-use")
                if fn not in api[target] and fn not in ("Init", "Start"):
                    report(p, lineno(t, m.start()), "ERROR", side + "-api", f'{alias}.{fn} (Alias für {target}) – {target} exportiert "{fn}" nicht')
        # c) svc("X").Fn / svc("X"):Fn / serviceModule(services, "X").Fn
        for m in re.finditer(r'\b([A-Za-z_]\w*)\(\s*(?:[A-Za-z_]\w*\s*,\s*)?"([A-Z]\w*)"\s*\)\s*[.:]\s*([A-Za-z_]\w*)', t):
            gname, mod, fn = m.group(1), m.group(2), m.group(3)
            if gname not in {g for g, _ in getters}:
                continue
            if mod in names:
                seen(side + "-getter-chain")
            if mod in names and fn not in api[mod]:
                report(p, lineno(t, m.start()), "ERROR", side + "-api", f'{mod}.{fn} – {mod} exportiert "{fn}" nicht')
        # d) Ein-Ziel-Hilfen: local function hudCall(fnName, ...) mit ctx.Modules.Hud[fnName] -> hudCall("Toast")
        for name, params, b0, b1 in iter_functions(t):
            if not params or "." in name or ":" in name:
                continue
            body = t[b0:b1]
            targets = set(re.findall(r'\b(?:Services|Modules)(?:\.([A-Z]\w*)|\[\s*"([A-Z]\w*)"\s*\])', body))
            targets = {a or b for a, b in targets}
            first = params[0]
            if len(targets) != 1:
                continue
            target = targets.pop()
            # der Parameter muss das Modul-Objekt selbst indizieren (Modules.X[fn] oder local m = …Modules.X; m[fn])
            holders = [r'(?:ctx\.)?(?:Services|Modules)(?:\.' + target + r'|\[\s*"' + target + r'"\s*\])']
            for hm in re.finditer(r'\blocal\s+([A-Za-z_]\w*)\s*(?::[^=\n]+)?=[^\n]*\b(?:Services|Modules)(?:\.' + target + r'\b|\[\s*"' + target + r'"\s*\])\s*(?:::\s*any\s*)?(?=\n)', body):
                holders.append(re.escape(hm.group(1)))
            if not re.search(r'(?<![\w.])(?:' + "|".join(holders) + r')\s*\[\s*' + re.escape(first) + r'\s*\]', body):
                continue
            if target not in names:
                continue
            for m in re.finditer(r'(?<![\w.:])' + re.escape(name) + r'\(\s*"([A-Za-z_]\w*)"', t):
                fn = m.group(1)
                seen(side + "-single-target-helper")
                if fn not in api[target]:
                    report(p, lineno(t, m.start()), "ERROR", side + "-api", f'{name}("{fn}") (Hilfe für {target}) – {target} exportiert "{fn}" nicht')


check_indirect(server_files, service_api, "service")
check_indirect(client_files, module_api, "module")
empty = [n for n, a in list(service_api.items()) + list(module_api.items()) if not a]
for n in empty:
    print(f"(Hinweis) keine Exporte erkannt in {n}", file=sys.stderr)

# ---------------------------------------------------------------- 2c) Lader-Registries + ctx-Felder
all_files = files("")
_main_client = os.path.join(SRC, "client", "Main.client.luau")
_main_server_path = os.path.join(SRC, "server", "Main.server.luau")


IF_EXPR_BEFORE = re.compile(r"(?:[=(,{\[+\-*/%^<>~]|\.\.|\breturn|\band|\bor|\bnot)\s*$")


def skip_function(text, i):
    """i zeigt auf `function`; Position hinter dem passenden `end` (Strings übersprungen, Kommentare schon entfernt)."""
    depth, j = 0, i
    word = re.compile(r"[A-Za-z_]\w*")
    while j < len(text):
        c = text[j]
        if c in "\"'" or text.startswith("[[", j) or re.match(r"\[=+\[", text[j:j + 8]):
            _, k = parse_string_at(text, j)
            j = max(k, j + 1)
            continue
        wm = word.match(text, j)
        if wm and (j == 0 or not (text[j - 1].isalnum() or text[j - 1] in "_.:")):
            w = wm.group(0)
            if w == "if" and IF_EXPR_BEFORE.search(text[max(0, j - 40):j]):
                j = wm.end()  # Luau-if-Ausdruck `x = if a then b else c` hat kein `end`
                continue
            if w in ("function", "if", "do", "repeat"):
                depth += 1
            elif w in ("end", "until"):
                depth -= 1
                if depth == 0:
                    return wm.end()
            j = wm.end()
            continue
        j += 1
    return len(text)


def literal_list(text, var):
    """Einträge einer Tabelle `local VAR(: T)? = { "A", "B" }` bzw. Schlüssel von `{ A = true }` -> [(name, zeile)].
    Nur echte Eintragspositionen (nach `{`/`,`/`;`), Funktionsrümpfe und Klammern werden übersprungen."""
    m = re.search(r"\blocal\s+" + re.escape(var) + r"\s*(?::[^=]+)?=\s*\{", text)
    if not m:
        return None
    depth, paren, i, out, entry = 0, 0, m.end() - 1, [], False
    while i < len(text):
        c = text[i]
        if c == "{":
            depth += 1
            entry = depth == 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                break
        elif c in "([" and depth == 1:
            km = re.match(r'\[\s*"([^"]+)"\s*\]\s*=(?!=)', text[i:]) if c == "[" and paren == 0 else None
            if km:
                # ["Key"] = … als Schlüssel
                if entry:
                    out.append((km.group(1), lineno(text, i)))
                i += len(km.group(0))
                entry = False
                continue
            paren += 1
            entry = False
        elif c in ")]" and depth == 1:
            paren -= 1
        elif depth == 1 and paren == 0:
            if c in ",;":
                entry = True
            elif c in "\"'":
                value, j = parse_string_at(text, i)
                if entry and value is not None:
                    out.append((value, lineno(text, i)))
                entry = False
                i = max(j, i + 1)
                continue
            elif text.startswith("function", i) and not (text[i - 1].isalnum() or text[i - 1] in "_."):
                i = skip_function(text, i)
                entry = False
                continue
            elif not c.isspace():
                mm = re.match(r"([A-Za-z_]\w*)\s*=(?!=)", text[i:])
                if mm and entry:
                    out.append((mm.group(1), lineno(text, i)))
                    i += len(mm.group(0))
                    entry = False
                    continue
                entry = False
        elif depth > 1 and c in "\"'":
            _, j = parse_string_at(text, i)
            i = max(j, i + 1)
            continue
        i += 1
    return out


if os.path.exists(_main_client):
    mc = strip_comments(read(_main_client))
    lists = {v: literal_list(mc, v) for v in ("MODULE_ORDER", "ADMIN_MODULES", "FRAME_MODULES", "TICK_MODULES", "LIBRARY_MODULES")}
    loaded_names = set()
    for var, entries in lists.items():
        if entries is None:
            continue
        for name, ln in entries:
            seen("registry-client")
            if var in ("MODULE_ORDER", "ADMIN_MODULES"):
                loaded_names.add(name)
            if name not in module_files:
                report(_main_client, ln, "ERROR", "registry", f'{var}: Modul "{name}" existiert nicht in src/client/Modules')
            elif var == "FRAME_MODULES" and "Frame" not in module_api[name]:
                report(_main_client, ln, "ERROR", "registry", f'FRAME_MODULES: {name} exportiert keine Frame(dt)')
            elif var == "TICK_MODULES" and "Tick" not in module_api[name]:
                report(_main_client, ln, "ERROR", "registry", f'TICK_MODULES: {name} exportiert keine Tick()')
    if lists.get("MODULE_ORDER") is not None:
        for name, path in sorted(module_files.items()):
            if name not in loaded_names:
                report(path, 1, "ERROR", "registry", f'Client-Modul "{name}" steht weder in MODULE_ORDER noch in ADMIN_MODULES (wird nie geladen)')
    # ctx-Felder, die Module benutzen, muss Main.client anlegen
    ctx_fields = set()
    m = re.search(r"\blocal\s+ctx\s*(?::[^=]+)?=\s*\{", mc)
    if m:
        ctx_fields |= {x for x, _ in (literal_list(mc[m.start():], "ctx") or [])}
    ctx_fields |= set(re.findall(r"(?m)^\s*ctx\.([A-Za-z_]\w*)\s*=", mc)) | set(re.findall(r"\bfunction\s+ctx[.:]([A-Za-z_]\w*)", mc))
    for p in client_files:
        if p == _main_client:
            continue
        t = blank_strings(strip_comments(read(p)))
        for m in re.finditer(r"(?<![\w.])ctx\.([A-Za-z_]\w*)", t):
            seen("ctx-field")
            if m.group(1) not in ctx_fields:
                report(p, lineno(t, m.start()), "ERROR", "ctx", f"ctx.{m.group(1)} wird von Main.client nicht angelegt")

if os.path.exists(_main_server_path):
    ms = strip_comments(read(_main_server_path))
    order_entries = literal_list(ms, "order") or []
    in_order = set()
    for name, ln in order_entries:
        seen("registry-server")
        in_order.add(name)
        if name not in service_files:
            report(_main_server_path, ln, "ERROR", "registry", f'order: Service "{name}" existiert nicht in src/server/Services')
    if order_entries:
        for name, path in sorted(service_files.items()):
            if name != "Remotes" and name not in in_order:
                report(path, 1, "ERROR", "registry", f'Service "{name}" steht nicht in der Lader-Reihenfolge (Main.server order) – wird nie geladen')


# ---------------------------------------------------------------- 3) require-Ziele (gegen den Rojo-Baum aufgelöst)
class Node:
    def __init__(self, name, cls, parent=None, dynamic=False):
        self.name, self.cls, self.parent, self.children, self.dynamic = name, cls, parent, {}, dynamic


file_node = {}


def add_fs(node, path):
    """Rojo-Regeln: Ordner -> Folder (init.luau macht ihn zum ModuleScript), X.luau -> ModuleScript,
    X.server.luau -> Script, X.client.luau -> LocalScript."""
    for entry in sorted(os.listdir(path)):
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            child = Node(entry, "Folder", node)
            node.children[entry] = child
            add_fs(child, full)
            continue
        for suffix, cls in ((".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript"),
                            (".server.lua", "Script"), (".client.lua", "LocalScript"), (".lua", "ModuleScript")):
            if entry.endswith(suffix):
                base = entry[: -len(suffix)]
                if base == "init":
                    node.cls = cls
                    file_node[os.path.normpath(full)] = node
                else:
                    child = Node(base, cls, node)
                    node.children[base] = child
                    file_node[os.path.normpath(full)] = child
                break


def build_tree(spec, node):
    for key, value in spec.items():
        if key.startswith("$") or not isinstance(value, dict):
            continue
        child = Node(key, value.get("$className", "Folder"), node, dynamic=("$path" not in value))
        node.children[key] = child
        if "$path" in value:
            target = os.path.join(ROOT, value["$path"])
            if os.path.isdir(target):
                add_fs(child, target)
            elif os.path.isfile(target):
                file_node[os.path.normpath(target)] = child
                child.cls = "Script" if target.endswith(".server.luau") else "LocalScript" if target.endswith(".client.luau") else "ModuleScript"
        build_tree(value, child)


game_root = None
_project = os.path.join(ROOT, "default.project.json")
if os.path.exists(_project):
    import json

    with open(_project, encoding="utf-8") as fh:
        game_root = Node("game", "DataModel", dynamic=True)
        build_tree(json.load(fh)["tree"], game_root)

MISSING = "MISSING"
CHAIN_STEP = re.compile(
    r'\s*(?:\.\s*([A-Za-z_]\w*)'
    r'|:\s*(WaitForChild|FindFirstChild)\(\s*"([^"]+)"\s*(?:,[^()]*)?\)'
    r'|:\s*GetService\(\s*"([^"]+)"\s*\))'
)


def resolve_chain(expr, env, here, depth=0):
    """Ausdruck wie `script.Parent:WaitForChild("X")` / `Shared:WaitForChild("Util")` auflösen.
    Rückgabe: Node | (MISSING, eltern, name, art) | None (nicht statisch auflösbar)."""
    expr = re.sub(r"\s*::\s*[A-Za-z_][\w.]*\s*$", "", expr.strip())
    m = re.match(r"([A-Za-z_]\w*)", expr)
    if not m or depth > 8:
        return None
    base, rest = m.group(1), expr[m.end():]
    if base == "script":
        node = here
    elif base == "game":
        node = game_root
    elif base in env:
        node = resolve_chain(env[base], env, here, depth + 1)
        if not isinstance(node, Node):
            return node if isinstance(node, tuple) else None
    else:
        return None
    if node is None:
        return None
    pos = 0
    while pos < len(rest):
        sm = CHAIN_STEP.match(rest, pos)
        if not sm or sm.end() == pos:
            return None if rest[pos:].strip() else node
        pos = sm.end()
        prop, method, arg, service = sm.group(1), sm.group(2), sm.group(3), sm.group(4)
        if service is not None:
            if node is not game_root:
                return None
            node = game_root.children.get(service) or Node(service, service, game_root, dynamic=True)
            continue
        if prop == "Parent":
            node = node.parent
            if node is None:
                return None
            continue
        name = arg if method else prop
        if name in node.children:
            node = node.children[name]
            continue
        if node.dynamic:
            return None  # Dienst/Ordner ohne $path: Kinder entstehen evtl. zur Laufzeit
        if prop is not None and node.cls != "Folder" and not node.children:
            return None  # Eigenschaft eines Skripts (Name, Source …), kein Kind
        return (MISSING, node, name, method or "index")
    return node


def node_path(node):
    parts = []
    while node is not None and node.name != "game":
        parts.append(node.name)
        node = node.parent
    return ".".join(reversed(parts))


if game_root is not None:
    for p in all_files:
        here = file_node.get(os.path.normpath(p))
        if here is None:
            continue
        t = strip_comments(read(p))
        env, dup = {}, set()
        for m in re.finditer(r"(?m)^\s*local\s+([A-Za-z_]\w*)\s*(?::[^=\n]+)?=\s*((?:script|game|[A-Za-z_]\w*)(?:\s*[.:][^\n]*)?)$", t):
            name, expr = m.group(1), m.group(2).strip()
            if name in env and env[name] != expr:
                dup.add(name)
            env[name] = expr
        for name in dup:
            env.pop(name, None)
        for m in re.finditer(r"\brequire\(([^()]*(?:\([^()]*\)[^()]*)*)\)", t):
            result = resolve_chain(m.group(1), env, here)
            if result is None:
                continue
            seen("require-resolved")
            if isinstance(result, tuple):
                _, parent, name, _how = result
                report(p, lineno(t, m.start()), "ERROR", "require", f'require-Ziel "{name}" existiert nicht unter {node_path(parent)}')
            elif result.cls != "ModuleScript":
                report(p, lineno(t, m.start()), "ERROR", "require", f"require({node_path(result)}) ist kein ModuleScript ({result.cls})")
        # WaitForChild auf statische Quell-Ordner, deren Kind es nicht gibt -> wartet ewig
        for m in re.finditer(r"(?<![\w.:])((?:script|[A-Za-z_]\w*)(?:\s*(?:\.\s*[A-Za-z_]\w*|:\s*(?:WaitForChild|FindFirstChild)\(\s*\"[^\"]+\"\s*(?:,[^()]*)?\)))*\s*:\s*WaitForChild\(\s*\"[^\"]+\"\s*(?:,[^()]*)?\))", t):
            result = resolve_chain(m.group(1), env, here)
            if isinstance(result, tuple):
                _, parent, name, how = result
                if how == "WaitForChild" and not parent.dynamic:
                    report(p, lineno(t, m.start()), "ERROR", "require", f'WaitForChild("{name}") unter {node_path(parent)} – Kind existiert im Projekt nicht (wartet ewig)')

# ---------------------------------------------------------------- 4) Request-Aktionen (§C9, frozen)
REQUEST_ACTIONS = {
    "GetFull", "SaveSettings", "TutorialFlag",
    "MktCandles", "MktProfile", "MktCalendar", "MktNews",
    "TradePlace", "TradeCancel", "TradeModify", "TradeBasket", "TradeRefill", "TradeAuto", "TradeWatch",
    "AlertSet", "AlertRemove", "BotSet", "BotToggle", "DepotHistory", "TutorialTrade",
    "TowerBuild", "TowerRoom", "TowerLevel", "TowerHire", "TowerFire", "TowerEfficiency", "TowerCollect",
    "TowerTransfer", "TowerInstant", "TowerExpress", "TowerHelp", "TowerVisit", "TowerHome", "TowerElevator",
    "TowerName", "TowerSkin", "TowerNeon", "TowerPrivate", "TowerDecor", "TowerLayout", "TowerAutoPlan",
    "CarSpawn", "CarDespawn", "CarBuy", "CarTune", "LifeBuy", "LifeEquip",
    "ProgLesson", "ProgExam", "ProgKnowHow", "ProgKnowHowReset", "ProgIpoPreview", "ProgIpo", "ProgPerk",
    "ProgRespec", "ProgTitle", "RewardLogin", "RewardQuest", "RewardReroll", "RewardSeason", "RewardCode",
    "RewardTutorial", "SocialRespekt", "SocialReact", "SocialShow", "SocialInvited", "NotifyOptIn", "BoardsGet",
    "ShopQuote", "ShopPrecheck", "ShopClubClaim", "EventPickup", "Report",
}
handled = {}
for p in server_files:
    t = strip_comments(read(p))
    for m in re.finditer(r'\bHandle\(\s*"(\w+)"', t):
        name = m.group(1)
        ln = lineno(t, m.start())
        if name in handled and handled[name][0] != p:
            report(p, ln, "ERROR", "request", f'Aktion "{name}" wird doppelt registriert (auch in {rel(handled[name][0])})')
        handled.setdefault(name, (p, ln))
        if not re.fullmatch(r"[A-Za-z]+", name):
            report(p, ln, "ERROR", "request", f'Aktion "{name}" – Namen nur Buchstaben (§C9)')
        if name not in REQUEST_ACTIONS:
            report(p, ln, "WARN", "request-frozen", f'Aktion "{name}" steht nicht in der frozen Liste §C9')


def first_arg_literals(text, pos, name_re=r"\w+"):
    """String-Literale des ersten Arguments ab `pos` (direkt hinter der öffnenden Klammer):
    "X" -> ["X"]; if c then "A" else "B" -> ["A", "B"]; sonst []."""
    m = re.match(r'\s*"(' + name_re + r')"\s*[,)]', text[pos:])
    if m:
        return [m.group(1)]
    m = re.match(r'\s*if\b[^,()]*?\bthen\s*"(' + name_re + r')"\s*else\s*"(' + name_re + r')"\s*[,)]', text[pos:])
    if m:
        return [m.group(1), m.group(2)]
    return []


def action_calls(path, base_heads, name_re=r"\w+"):
    """Alle Aufrufe mit Aktions-Literal: Basis-Köpfe + lokale Wrapper, die ihren 1. Parameter als Aktion
    weiterreichen (request(action, …) -> ctx.RequestFull(action, …); load(kind) -> admin(kind)). Bis zum Fixpunkt."""
    t = strip_comments(read(path))
    heads = list(base_heads)
    funcs = [(n, ps, b0, b1) for n, ps, b0, b1 in iter_functions(t) if ps and "." not in n and ":" not in n]
    wrappers = set()
    changed = True
    while changed:
        changed = False
        for name, params, b0, b1 in funcs:
            if name in wrappers:
                continue
            body, first = t[b0:b1], re.escape(params[0])
            for head in heads:
                if re.search(head + r"\(\s*" + first + r"\s*[,)]", body) or re.search(
                    r"\bpcall\(\s*" + head + r"\s*,\s*" + first + r"\s*[,)]", body
                ):
                    wrappers.add(name)
                    heads.append(r"(?<![\w.:])" + re.escape(name))
                    changed = True
                    break
    out = []
    for head in heads:
        for m in re.finditer(head + r"\(", t):
            for act in first_arg_literals(t, m.end(), name_re):
                out.append((act, lineno(t, m.start())))
        for m in re.finditer(r"\bpcall\(\s*" + head + r"\s*,", t):
            for act in first_arg_literals(t, m.end(), name_re):
                out.append((act, lineno(t, m.start())))
    return sorted(set(out), key=lambda x: x[1]), wrappers


REQUEST_HEADS = [r"\bctx\.Request(?:Full)?", r"(?<![\w.:])Request(?:Full)?"]
requested = {}
for p in client_files + [x for x in all_files if x.startswith(os.path.join(SRC, "first"))]:
    calls, _ = action_calls(p, REQUEST_HEADS)
    for act, ln in calls:
        seen("request-call")
        requested.setdefault(act, []).append((p, ln))
for act, locs in sorted(requested.items()):
    if act not in handled:
        for p, ln in locs:
            report(p, ln, "ERROR", "request", f'Request "{act}" hat keinen Server-Handler (PlayerStateService.Handle)')
for act, (p, ln) in sorted(handled.items()):
    if act not in requested:
        report(p, ln, "WARN", "request", f'Handler "{act}" wird vom Client nie direkt mit Literal angefragt')

# ---------------------------------------------------------------- 4b) Admin-Aktionen (Remote "Admin" -> AdminService Actions.X)
_admin_service = service_files.get("AdminService")
if _admin_service:
    at = strip_comments(read(_admin_service))
    admin_actions = set(re.findall(r"(?m)^\s*Actions\.([A-Za-z_]\w*)\s*=", at)) | set(
        re.findall(r"\bfunction\s+Actions[.:]([A-Za-z_]\w*)", at)
    )
    admin_requested = {}
    for p in client_files:
        t = strip_comments(read(p))
        receivers = set(re.findall(r"\blocal\s+([A-Za-z_]\w*)\s*(?::[^=\n]+)?=[^\n]*\.Admin\b", t))
        heads = [r"\b" + re.escape(r) + r"\s*:\s*InvokeServer" for r in receivers] + [r"\bRemotes\.Admin\s*:\s*InvokeServer"]
        calls, _ = action_calls(p, heads)
        for act, ln in calls:
            seen("admin-call")
            admin_requested.setdefault(act, []).append((p, ln))
            if act not in admin_actions:
                report(p, ln, "ERROR", "admin-action", f'Admin-Aktion "{act}" gibt es in AdminService (Actions.{act}) nicht')
    for act in sorted(admin_actions - set(admin_requested)):
        m = re.search(r"(?m)^\s*Actions\." + act + r"\s*=", at)
        report(_admin_service, lineno(at, m.start()) if m else 1, "WARN", "admin-action", f'Admin-Aktion "{act}" wird vom Client nie mit Literal aufgerufen')

# ---------------------------------------------------------------- 5) Remotes (Client/Server-Zugriffe)
for p in all_files:
    t = strip_comments(read(p))
    for m in re.finditer(r"\b([A-Za-z_]*[Rr]emotes)\.([A-Z]\w*)", t):
        var, nm = m.group(1), m.group(2)
        if var in ("Services",):
            continue
        seen("remote-name")
        if nm not in remote_names:
            report(p, lineno(t, m.start()), "ERROR", "remote", f"{var}.{nm} ist nicht in Net.RemoteList")
    for m in re.finditer(r'GetRemotes\(\)\s*\[\s*"(\w+)"\s*\]', t):
        if m.group(1) not in remote_names:
            report(p, lineno(t, m.start()), "ERROR", "remote", f'GetRemotes()["{m.group(1)}"] ist nicht in Net.RemoteList')
    # Remotes["X"] / ctx.Remotes["X"] / GetRemotes().X / remotes:FindFirstChild("X") / :WaitForChild("X")
    for m in re.finditer(r'\b[A-Za-z_]*[Rr]emotes\s*\[\s*"(\w+)"\s*\]|GetRemotes\(\)\s*\.\s*(\w+)'
                         r'|\b[A-Za-z_]*[Rr]emotes(?:Folder)?\s*:\s*(?:WaitForChild|FindFirstChild)\(\s*"(\w+)"', t):
        nm = m.group(1) or m.group(2) or m.group(3)
        seen("remote-name")
        if nm not in remote_names:
            report(p, lineno(t, m.start()), "ERROR", "remote", f'Remote "{nm}" ist nicht in Net.RemoteList')
    # Namenslisten/Handler-Tabellen für Remotes: local REMOTE_ORDER = { "State", … } / local remoteHandlers = { State = … }
    for m in re.finditer(r'\blocal\s+([A-Za-z_]*[Rr][Ee][Mm][Oo][Tt][Ee][A-Za-z_]*)\s*(?::[^=\n]+)?=\s*\{', t):
        entries = literal_list(t, m.group(1)) or []
        for nm, ln in entries:
            seen("remote-name")
            if nm not in remote_names:
                report(p, ln, "ERROR", "remote", f'{m.group(1)}: "{nm}" ist nicht in Net.RemoteList')

# ---------------------------------------------------------------- 6) Lang-Schlüssel (§C15: gleiche Liste wie Lang/init FILES)
LANG_PREFIX = ("core", "ui", "mkt", "news", "trade", "term", "tower", "tui", "world", "car", "life", "prog", "tut",
               "soc", "shop", "item", "admin", "evt")
lang_files = files("shared/Lang")
# Präfixe je Datei aus Lang/init FILES (dieselbe Quelle wie zur Laufzeit)
_lang_init = os.path.join(SRC, "shared", "Lang", "init.luau")
file_prefixes = {}
if os.path.exists(_lang_init):
    for m in re.finditer(r'\{\s*Name\s*=\s*"([A-Za-z]+)"\s*,\s*Prefixes\s*=\s*\{([^}]*)\}', read(_lang_init)):
        file_prefixes[m.group(1)] = re.findall(r'"([a-z]+\.)"', m.group(2))
    for name in sorted({x[:-1] for v in file_prefixes.values() for x in v} - set(LANG_PREFIX)):
        report(_lang_init, 1, "ERROR", "lang", f'Präfix "{name}." steht in Lang/init FILES, aber nicht in LANG_PREFIX (contract_check.py)')
lang_by = {"de": {}, "en": {}}  # sprache -> schlüssel -> (datei, zeile, text)
KEY_DEF = re.compile(r'\[\s*"([a-z]+\.[A-Za-z0-9_.]+)"\s*\]\s*=\s*')
for p in lang_files:
    if p == _lang_init:
        continue
    t = strip_comments(read(p))
    base = os.path.splitext(os.path.basename(p))[0]
    split = re.search(r"(?m)^\s*en\s*=\s*\{", t)
    if base not in file_prefixes:
        report(p, 1, "ERROR", "lang", f"Lang-Datei {base} steht nicht in Lang/init FILES (wird nie geladen)")
    if not re.search(r"(?m)^\s*de\s*=\s*\{", t) or not split:
        report(p, 1, "ERROR", "lang", f"Lang-Datei {base}: Tabelle de = {{…}} oder en = {{…}} fehlt")
        continue
    for m in KEY_DEF.finditer(t):
        key, ln = m.group(1), lineno(t, m.start())
        lang = "en" if m.start() > split.start() else "de"
        value, _ = parse_concat_at(t, m.end())
        if key in lang_by[lang] and lang_by[lang][key][0] != p:
            report(p, ln, "ERROR", "lang", f'Lang-Schlüssel "{key}" ({lang}) doppelt – auch in {rel(lang_by[lang][key][0])} (zweiter wird verworfen)')
        elif key in lang_by[lang]:
            report(p, ln, "ERROR", "lang", f'Lang-Schlüssel "{key}" ({lang}) doppelt in derselben Datei')
        lang_by[lang].setdefault(key, (p, ln, value or ""))
        prefixes = file_prefixes.get(base)
        if prefixes and not any(key.startswith(x) for x in prefixes):
            report(p, ln, "ERROR", "lang", f'Lang-Schlüssel "{key}" hat in Lang.{base} das falsche Präfix (erwartet {" / ".join(prefixes)})')
lang_keys = set(lang_by["de"]) | set(lang_by["en"])
PLACEHOLDER = re.compile(r"%[-+#0]*\d*(?:\.\d+)?[sdifqxXc%]")
for key in sorted(lang_keys):
    seen("lang-key-defined")
    for have, miss in (("de", "en"), ("en", "de")):
        if key in lang_by[have] and key not in lang_by[miss]:
            p, ln, _ = lang_by[have][key]
            report(p, ln, "ERROR", "lang", f'Lang-Schlüssel "{key}" fehlt in "{miss}" (nur in "{have}")')
    if key in lang_by["de"] and key in lang_by["en"]:
        a = [x for x in PLACEHOLDER.findall(lang_by["de"][key][2]) if x != "%%"]
        b = [x for x in PLACEHOLDER.findall(lang_by["en"][key][2]) if x != "%%"]
        if len(a) != len(b):
            p, ln, _ = lang_by["en"][key]
            report(p, ln, "WARN", "lang", f'Lang-Schlüssel "{key}": {len(a)} Platzhalter in de, {len(b)} in en')

key_re = re.compile(r'"((?:' + "|".join(LANG_PREFIX) + r')\.[A-Za-z0-9_.]*[A-Za-z0-9_])"')
prefix_re = re.compile(r'"((?:' + "|".join(LANG_PREFIX) + r')\.[A-Za-z0-9_.]*)"\s*\.\.')
# Übersetzer-Aufrufe mit Literal: T("k") · ctx.T("k") · L(p, "k") · Lang.T(lang, "k") · TOr("k", …)
translate_re = re.compile(r'(?<![\w.:])(?:ctx\.T|T|TOr)\(\s*"([^"\s]+)"|(?<![\w.:])(?:L|Lang\.T)\(\s*[A-Za-z_][\w.]*\s*,\s*"([^"\s]+)"')
for p in all_files:
    if p in lang_files:
        continue
    t = strip_comments(read(p))
    for m in key_re.finditer(t):
        key = m.group(1)
        after = t[m.end():m.end() + 4]
        if after.lstrip().startswith(".."):
            continue  # Präfix für zusammengesetzte Schlüssel (unten geprüft)
        seen("lang-key-used")
        if key not in lang_keys:
            report(p, lineno(t, m.start()), "ERROR", "lang", f'Lang-Schlüssel "{key}" fehlt in src/shared/Lang')
    for m in prefix_re.finditer(t):
        prefix = m.group(1)
        seen("lang-key-prefix")
        if not any(k.startswith(prefix) for k in lang_keys):
            report(p, lineno(t, m.start()), "ERROR", "lang", f'Kein Lang-Schlüssel beginnt mit "{prefix}" (zusammengesetzter Schlüssel läuft immer ins Leere)')
    for m in translate_re.finditer(t):
        key = m.group(1) or m.group(2)
        if "." in key and re.fullmatch(r"[a-z]+\.[A-Za-z0-9_.]+", key) and key.split(".")[0] not in LANG_PREFIX:
            if rel(p).startswith("src/server/Tests/"):
                continue  # Tests prüfen bewusst fehlende Schlüssel ("gibt.es.nicht")
            report(p, lineno(t, m.start()), "ERROR", "lang", f'Lang-Schlüssel "{key}" hat kein gültiges Präfix ({", ".join(LANG_PREFIX)})')

# ---------------------------------------------------------------- 7) Config-Abschnitte (+ Schlüssel der 2. Ebene)
cfg_dir = os.path.join(SRC, "shared", "Config")
cfg_children = {os.path.splitext(f)[0] for f in os.listdir(cfg_dir)} if os.path.isdir(cfg_dir) else set()
cfg_init = strip_comments(read(os.path.join(cfg_dir, "init.luau"))) if os.path.exists(os.path.join(cfg_dir, "init.luau")) else ""
cfg_top = set(re.findall(r"(?m)^\s*Config\.([A-Za-z_]\w*)\s*=", cfg_init)) | set(
    re.findall(r"\bfunction\s+Config[.:]([A-Za-z_]\w*)", cfg_init)
)
# Kind-Module werden unter ihrem Dateinamen eingehängt; die CHILDREN-Liste zählt auch, wenn die Datei noch fehlt
# (Config.Validate meldet fehlende Kinder selbst)
m_children = re.search(r"local\s+CHILDREN\s*=\s*\{(.*?)\}", cfg_init, re.S)
cfg_listed = set(re.findall(r'"([A-Za-z_]\w*)"', m_children.group(1))) if m_children else set()
cfg_known = cfg_top | (cfg_children - {"init"}) | cfg_listed
for name in sorted((cfg_children - {"init"}) - cfg_listed) if m_children else []:
    report(os.path.join(cfg_dir, name + ".luau"), 1, "ERROR", "config", f"Config-Kind {name} steht nicht in CHILDREN (Config/init) – wird nie geladen")


def table_keys_at(text, brace):
    """Schlüssel der obersten Ebene eines Tabellen-Konstruktors ab `{` (X = …, ["X"] = …)."""
    entries = literal_list("local __T = " + text[brace:], "__T") or []
    return {name for name, _ in entries}


# API je Abschnitt: Kind-Module = exportierte Felder; Init-Tabellen Config.X = { … } = Konstruktor-Schlüssel + Config.X.Y =
cfg_api = {}
for name in cfg_children - {"init"}:
    path = os.path.join(cfg_dir, name + ".luau")
    if os.path.exists(path):
        cfg_api[name], _ = exported_names(strip_comments(read(path)))
for m in re.finditer(r"(?m)^Config\.([A-Za-z_]\w*)\s*=\s*(\{)?", cfg_init):
    if m.group(2) and m.group(1) not in cfg_api:
        cfg_api[m.group(1)] = table_keys_at(cfg_init, m.end() - 1)
for m in re.finditer(r"(?m)^\s*Config\.([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*=", cfg_init):
    if m.group(1) in cfg_api:
        cfg_api[m.group(1)].add(m.group(2))
# Live-Felder (Config.ApplyLive) und Validate-Helfer sind Teil jeder API
for name in cfg_api:
    cfg_api[name] |= {"Validate"}

CFG_ROOT = r"(?:(?<![\w.])(?:ctx\.)?Config)"
for p in all_files:
    t = blank_strings(strip_comments(read(p)))
    # lokale Wurzel-Aliase: local config = ctx.Config / local cfg = Config
    roots = [CFG_ROOT]
    for m in re.finditer(r"\blocal\s+([A-Za-z_]\w*)\s*(?::[^=\n]+)?=\s*(?:ctx\.)?Config\s*(?:or\s*\{\s*\}\s*)?" + EXPR_END, t):
        if not reassigned(t, m.group(1)) and not shadowed(t, m.group(1)) and local_decls(t, m.group(1)) == 1:
            roots.append(r"(?<![\w.])" + re.escape(m.group(1)))
    root = "(?:" + "|".join(roots) + ")"
    for m in re.finditer(root + r"\.([A-Z][A-Za-z_]\w*)(?:\.([A-Za-z_]\w*))?", t):
        sec, key = m.group(1), m.group(2)
        seen("config-section")
        if sec not in cfg_known:
            report(p, lineno(t, m.start()), "ERROR", "config", f"Config.{sec} existiert nicht (weder in Config/init noch als Kind-Modul)")
        elif key and sec in cfg_api and key not in cfg_api[sec]:
            seen("config-key")
            report(p, lineno(t, m.start()), "ERROR", "config", f"Config.{sec}.{key} existiert nicht")
        elif key:
            seen("config-key")
    # Abschnitts-Aliase: local MCFG = Config.Market -> MCFG.Key
    done_alias = set()
    for m in re.finditer(r"\blocal\s+([A-Za-z_]\w*)\s*(?::[^=\n]+)?=\s*" + root + r"\.([A-Z]\w*)\s*(?:or\s*\{\s*\}\s*)?(?:::\s*any\s*)?" + EXPR_END, t):
        alias, sec = m.group(1), m.group(2)
        if sec not in cfg_api or alias in done_alias or reassigned(t, alias) or shadowed(t, alias):
            continue
        done_alias.add(alias)
        decls = re.findall(r"\blocal\s+" + re.escape(alias) + r"\s*(?::[^=\n]+)?=\s*([^\n]*)", t)
        if local_decls(t, alias) != len(decls):
            continue  # weitere Deklaration in einer Namensliste (local ok, alias = …)
        if any(not re.search(r"\b(?:Config|" + "|".join(re.escape(x[len("(?<![\\w.])"):]) for x in roots[1:]) + r")\." + sec + r"\b", d) if len(roots) > 1 else not re.search(r"\bConfig\." + sec + r"\b", d) for d in decls):
            continue  # gleichnamige lokale Variable mit anderem Wert
        for mm in re.finditer(r"(?<![\w.])" + re.escape(alias) + r"\.([A-Za-z_]\w*)", t):
            seen("config-alias-key")
            if mm.group(1) not in cfg_api[sec]:
                report(p, lineno(t, mm.start()), "ERROR", "config", f"{alias}.{mm.group(1)} (Alias für Config.{sec}) existiert nicht")

# ---------------------------------------------------------------- 12a) Effekt-Registry (§C7.4) – auch für Hooks gebraucht
EFFECTS = {
    "Announce": "Effects", "AdminWarn": "Effects", "Confetti": "Effects", "CoinFly": "Effects", "Flash": "Effects",
    "Shake": "Effects", "Toast": "Effects",
    "Bell": "EffectsMarket", "ReadWell": "EffectsMarket", "DayRecap": "EffectsMarket",
    "BuildDone": "EffectsTower", "StageUp": "EffectsTower", "TransferTube": "EffectsTower", "Collect": "EffectsTower",
    "Crane": "EffectsTower",
    "Reveal": "Garage",
    "IpoCeremony": "Prestige", "LicenceUp": "Prestige", "TitleUp": "Prestige", "QuestDone": "Prestige",
    "Achievement": "Prestige",
    "MoneyRain": "EffectsEvent", "BullParade": "EffectsEvent", "Bear": "EffectsEvent", "GoldenBull": "EffectsEvent",
    "SkyShow": "EffectsEvent", "Fireworks": "EffectsEvent", "BossAppear": "EffectsEvent", "AbuseBanner": "EffectsEvent",
    "BellMoment": "EffectsEvent",
}

# ---------------------------------------------------------------- 8) Hooks (§C7.2, frozen; nur Hinweise)
HOOKS = {
    "State", "Notify", "WindowOpened", "WindowClosed", "Settings", "Input", "PhotoMode", "Quality", "Quotes",
    "Market:News", "Market:Event", "Market:Halt", "Market:Bell", "Market:Ipo", "Market:Calendar", "Market:DayClose",
    "World:Pickups", "World:PickupGone", "World:Event", "World:Bear", "World:Parade", "Replay",
    "Plot:Enter", "Plot:Leave", "Tower:Built", "Tower:Stage", "Vehicle:Enter", "Vehicle:Exit", "Terminal:Instrument",
} | {"Effect:" + name for name in EFFECTS}
HOOK_PREFIXES = ("Effect:", "Market:", "World:")
fired, fired_prefix, listened = set(), set(), {}
HOOK_NAME = r"[A-Za-z:]+"
for p in client_files:
    t = strip_comments(read(p))
    # Feuern: Hooks.Fire / hooks.Fire / ctx.Hooks.Fire + lokale Wrapper (fireHook("WindowOpened", …) in UI)
    calls, _ = action_calls(p, [r"\b[Hh]ooks\.Fire"], HOOK_NAME)
    for name, ln in calls:
        seen("hook-fire")
        fired.add(name)
        if name not in HOOKS:
            report(p, ln, "WARN", "hook-frozen", f'Hook "{name}" ist nicht in der frozen Liste §C7.2')
    for m in re.finditer(r'\b(?:[Hh]ooks\.)?Fire\(\s*"([A-Za-z:]+)"\s*\.\.', t):
        fired_prefix.add(m.group(1))
        if m.group(1) not in HOOK_PREFIXES:
            report(p, lineno(t, m.start()), "WARN", "hook-frozen", f'Hook-Präfix "{m.group(1)}" ist nicht frozen (§C7.2)')
    # Hören: Hooks.On / hooks.Once / ctx.Hooks.On
    for name, ln in action_calls(p, [r"\b[Hh]ooks\.(?:On|Once)"], HOOK_NAME)[0]:
        seen("hook-listen")
        listened.setdefault(name, (p, ln))
        if name not in HOOKS:
            report(p, ln, "WARN", "hook-frozen", f'Hook "{name}" ist nicht in der frozen Liste §C7.2')
for h, (p, ln) in sorted(listened.items()):
    if h in fired or any(h.startswith(pre) for pre in fired_prefix):
        continue
    report(p, ln, "WARN", "hook", f'Hook "{h}" wird gehört, aber nirgends mit Literal gefeuert')

# ---------------------------------------------------------------- 9) FIREWALL (§C11.4 #1 Modulgrenze, #2 Token)
FIREWALL_TOKENS = [
    ("Credits", r"(?<![A-Za-z0-9_])Credits"),
    ("TowerService", r"(?<![A-Za-z0-9_])TowerService(?![A-Za-z0-9_])"),
    ("ShopService", r"(?<![A-Za-z0-9_])ShopService(?![A-Za-z0-9_])"),
    ("MonetizationService", r"(?<![A-Za-z0-9_])MonetizationService(?![A-Za-z0-9_])"),
    ("LifestyleService", r"(?<![A-Za-z0-9_])LifestyleService(?![A-Za-z0-9_])"),
    ("VehicleService", r"(?<![A-Za-z0-9_])VehicleService(?![A-Za-z0-9_])"),
    ("HasPass", r"(?<![A-Za-z0-9_])HasPass"),
    ("PassFactor", r"(?<![A-Za-z0-9_])PassFactor"),
    ("Boost", r"(?<![A-Za-z0-9_])Boost"),
    ("Prestige", r"(?<![A-Za-z0-9_])Prestige"),
    ("Grant(", r"(?<![A-Za-z0-9_])Grant\s*\("),
]
FIREWALL_SERVICES = {
    "DataService": None, "PlayerStateService": None, "MarketService": None, "OrderService": None,
    "ProgressionService": {"TradingPerks", "LicenceDef", "Licence"}, "AdminService": {"OwnerTradeBlocked"},
    "MetricsService": None, "AntiCheatService": None,
}


def is_firewall_file(path):
    r = rel(path)
    return (r.startswith("src/server/Market/") or r.startswith("src/shared/Market/")
            or r in ("src/server/Services/MarketService.luau", "src/server/Services/OrderService.luau"))


firewall_files = [p for p in all_files if is_firewall_file(p)]
# AT-Services = Lader-Reihenfolge in Main.server + vorhandene Service-Dateien (Roblox-Dienste wie RunService zählen nie)
_main_server = os.path.join(SRC, "server", "Main.server.luau")
_order = re.search(r"local\s+order\s*=\s*\{(.*?)\}", read(_main_server), re.S) if os.path.exists(_main_server) else None
AT_SERVICE_NAMES = set(service_files) | (set(re.findall(r'"([A-Za-z]+Service)"', _order.group(1))) if _order else set())
market_modules = {os.path.splitext(os.path.basename(p))[0] for p in files("server/Market") + files("shared/Market")}
firewall_requires = {"Shared", "Config", "Util", "Types", "Clock", "Lib", "Scheduler", "Market", "Remotes"} | market_modules
for p in firewall_files:
    t = strip_comments(read(p))
    for token, pattern in FIREWALL_TOKENS:
        for m in re.finditer(pattern, t):
            report(p, lineno(t, m.start()), "ERROR", "firewall", f'Token "{token}" ist im Markt-Code verboten (§C11.4)')
    # Modulgrenze: erlaubte Services (+ erlaubte Funktionen)
    uses = [(m.group(1), m.group(2), m.start()) for m in re.finditer(r"\bServices\.([A-Za-z_]\w*)(?:\.([A-Za-z_]\w*))?", t)]
    uses += [(m.group(2), m.group(3), m.start()) for m in re.finditer(r'\b([A-Za-z_]\w*)\(\s*"([A-Z]\w*Service)"\s*(?:,\s*"([A-Za-z_]\w*)")?', t)
             if m.group(1) not in ("GetService", "FindService")]
    uses += [(m.group(1), None, m.start()) for m in re.finditer(r'\bServices\[\s*"([A-Za-z_]\w*)"\s*\]', t)]
    for svc, fn, pos in uses:
        if svc == "Remotes" or svc not in AT_SERVICE_NAMES:
            continue
        if svc not in FIREWALL_SERVICES:
            report(p, lineno(t, pos), "ERROR", "firewall", f"Services.{svc} ist für Markt-Code nicht erlaubt (Modulgrenze §C11.4 #1)")
        elif fn and FIREWALL_SERVICES[svc] is not None and fn not in FIREWALL_SERVICES[svc]:
            report(p, lineno(t, pos), "ERROR", "firewall", f"{svc}.{fn} ist für Markt-Code nicht erlaubt (nur {', '.join(sorted(FIREWALL_SERVICES[svc]))})")
    for m in re.finditer(r"require\(([^()]*(?:\([^()]*\)[^()]*)*)\)", t):
        for mm in re.finditer(r'WaitForChild\(\s*"([A-Za-z_]\w*)"', m.group(1)):
            if mm.group(1) not in firewall_requires:
                report(p, lineno(t, m.start()), "WARN", "firewall", f'require "{mm.group(1)}" liegt außerhalb der Markt-Modulgrenze (§C11.4 #1)')

# ---------------------------------------------------------------- 10) DEPOT_WRITE (§C11.4 #3)
DEPOT_TARGET = re.compile(r'\.Depot\.|\.Depot\s*$|\[\s*["\']Depot["\']\s*\]|\b[Dd]epot\.(?:Cash|Basis)\b')
ASSIGN_OP = re.compile(r"(?<![=~<>!])(?:\+|-|\*|//|/|%|\^|\.\.)?=(?!=)")
STATEMENT_BREAK = re.compile(r"\b(?:then|do|else|end|return|repeat|until)\b|;")


def depot_writer_allowed(path):
    r = rel(path)
    return (r.startswith("src/server/Market/")
            or r in ("src/server/Services/OrderService.luau", "src/server/Services/DataService.luau"))


for p in all_files:
    if depot_writer_allowed(p):
        continue
    stripped = strip_comments(read(p))
    blanked = blank_strings(stripped)  # gleiche Länge: Operatoren nur außerhalb von Strings suchen
    for idx, (line, plain) in enumerate(zip(stripped.split("\n"), blanked.split("\n")), start=1):
        if "epot" not in line:
            continue
        prev = 0
        for m in ASSIGN_OP.finditer(plain):
            cut = STATEMENT_BREAK.split(plain[prev:m.start()])[-1]
            segment = line[m.start() - len(cut):m.start()].strip()
            prev = m.end()
            if segment.startswith("local ") or segment.startswith("type ") or segment.startswith("export "):
                continue
            if DEPOT_TARGET.search(segment):
                # Selbsttests bauen Depot-Attrappen auf Kopien von DefaultData -> dort nur Hinweis
                level = "WARN" if rel(p).startswith("src/server/Tests/") else "ERROR"
                report(p, idx, level, "depot-write",
                       f'Zuweisung an "{segment}" – nur OrderService/Portfolio schreiben das Depot (§C11.4 #3)')

# ---------------------------------------------------------------- 10b) FIREWALL_ROBUX (§C11.4 #4/#5, §B14.5): Robux nie -> Depot/Aktien
_shop_cfg = os.path.join(cfg_dir, "Shop.luau")
if os.path.exists(_shop_cfg):
    sc = strip_comments(read(_shop_cfg))
    fm = re.search(r"Shop\.ForbiddenRobuxFields\s*=\s*\{(.*?)\}", sc, re.S)
    forbidden = set(re.findall(r'"([A-Za-z_]\w*)"', fm.group(1))) if fm else set()
    gm = re.search(r"Shop\.GrantFields\s*=\s*\{", sc)
    grant_fields = {k for k, _ in (literal_list("local __T = " + sc[gm.end() - 1:], "__T") or [])} if gm else set()
    if not fm:
        report(_shop_cfg, 1, "ERROR", "firewall-robux", "Shop.ForbiddenRobuxFields fehlt (§B14.5)")
    for field in sorted(grant_fields & forbidden):
        report(_shop_cfg, lineno(sc, gm.start()), "ERROR", "firewall-robux", f'Shop.GrantFields erlaubt das verbotene Feld "{field}"')
    for must in ("Depot", "AKY", "Basis", "Xp", "Licence"):
        if fm and must not in forbidden:
            report(_shop_cfg, lineno(sc, fm.start()), "ERROR", "firewall-robux", f'"{must}" fehlt in Shop.ForbiddenRobuxFields')
    # Jede Gewährung in Shop (Robux), Saison-Spuren (Premium = Robux) und Codes: keine verbotenen Felder
    for cfg_name in ("Shop", "Season", "Rewards"):
        path = os.path.join(cfg_dir, cfg_name + ".luau")
        if not os.path.exists(path):
            continue
        ct = strip_comments(read(path))
        tables = [(m.group(1), m.end() - 1) for m in re.finditer(r"\b(Grant|Repeat)\s*=\s*\{", ct)]
        for m in re.finditer(r"\blocal\s+((?:PREMIUM|FREE)_\w+)\s*=\s*\{", ct):
            depth, i = 0, m.end() - 1
            while i < len(ct):
                if ct[i] == "{":
                    depth += 1
                    if depth == 2:
                        tables.append((m.group(1), i))
                elif ct[i] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
        for label, brace in tables:
            keys = literal_list("local __T = " + ct[brace:], "__T") or []
            seen("robux-grant-table")
            for key, _ in keys:
                if key in forbidden:
                    report(path, lineno(ct, brace), "ERROR", "firewall-robux", f'{cfg_name}: {label} enthält das verbotene Feld "{key}" (Robux/Codes nie -> Depot/XP/Lizenz)')
# Robux-Code (Kauf-Abwicklung) darf Depot, Orders, Markt, Lizenz nie berühren
ROBUX_FILES = ("src/server/Services/MonetizationService.luau", "src/server/Services/ShopService.luau")
ROBUX_TOKENS = [
    ("OrderService", r"(?<![A-Za-z0-9_])OrderService(?![A-Za-z0-9_])"), ("MarketService", r"(?<![A-Za-z0-9_])MarketService(?![A-Za-z0-9_])"),
    ("Portfolio", r"(?<![A-Za-z0-9_])Portfolio(?![A-Za-z0-9_])"), ("AdminCredit", r"(?<![A-Za-z0-9_])AdminCredit\b"),
    ("SetLicence", r"(?<![A-Za-z0-9_])SetLicence\b"), ("GiveAky", r"(?<![A-Za-z0-9_])GiveAky\b"),
    (".Depot", r"\.Depot\b|\[\s*[\"']Depot[\"']\s*\]"), ("Prog.Licence/Xp", r"\.Prog\s*\.\s*(?:Licence|Xp|KnowHow|KH|Ruf)\b"),
]
for p in all_files:
    if rel(p) not in ROBUX_FILES:
        continue
    t = blank_strings(strip_comments(read(p)))
    seen("robux-code-file")
    for token, pattern in ROBUX_TOKENS:
        for m in re.finditer(pattern, t):
            report(p, lineno(t, m.start()), "ERROR", "firewall-robux", f'Token "{token}" im Robux-Code verboten (Robux nie -> Depot/Aktien/Lizenz, §C11.4)')

# ---------------------------------------------------------------- 11) BANNED_WORDS (§0.7)
ALLOW_PHRASES = [r"\bim\s+einsatz\b", r"\bherzlichen\s+glückw\w*", r"\bglückw\w*"]
BANNED = [
    # DE
    (r"\bwett(?:e|en|est|et)\b", "Wette/wetten"), (r"\bgewettet\b", "wetten"),
    (r"\beinsatz(?:es|e)?\b|\beinsätze\b", "Einsatz"),
    (r"\b(?:casino|kasino)\w*", "Casino"), (r"\bjackpot\w*", "Jackpot"), (r"\bglück\w*", "Glück…"),
    (r"\bzock\w*", "zocken"), (r"\ball-in\b", "All-in"), (r"\bverdopp(?:el|l)\w*", "verdoppeln"),
    (r"\bdoppelt\s+oder\s+nichts\b", "doppelt oder nichts"), (r"\blotterie\w*", "Lotterie"),
    (r"\blosnummer\w*", "Losnummer"), (r"\brubbellos\w*", "Rubbellos"), (r"\bgewinnspiel\w*", "Gewinnspiel"),
    (r"\bspielautomat\w*", "Spielautomat"), (r"\broulette\w*", "Roulette"), (r"\bpoker\w*", "Poker"),
    (r"\bwürfel\w*", "Würfel"), (r"\bhebel\w*", "Hebel"), (r"\binsider\w*", "Insider"), (r"\bkrypto\w*", "Krypto"),
    (r"\bbitcoin\w*", "Bitcoin"), (r"\bnfts?\b", "NFT"), (r"\bmondfahrt\w*", "Mondfahrt"),
    (r"\bgarantier\w*", "garantiert"),
    # EN
    (r"\bbet(?:s|ting|ted)?\b", "bet"), (r"\bwager\w*", "wager"), (r"\bstake(?:s|d)?\b", "stake"),
    (r"\b(?:un)?luck(?:y|ily)?\b", "luck/lucky"), (r"\bgambl\w*", "gamble/gambling"),
    (r"\bdouble\s+or\s+nothing\b", "double or nothing"), (r"\blotter(?:y|ies)\b", "lottery"),
    (r"\braffles?\b", "raffle"), (r"\bspin(?:s|ning)?\b", "spin"), (r"\bx100\b", "x100"),
    (r"\bto\s+the\s+moon\b", "to the moon"), (r"\bleverag\w*", "leverage"), (r"\bcrypto\w*", "crypto"),
    (r"\bslot\s+machines?\b", "slot machine"), (r"\bdice\b", "dice"), (r"\bguarantee\w*", "guaranteed"),
]
BANNED_RE = [(re.compile(pattern, re.I), label) for pattern, label in BANNED]
ALLOW_RE = [re.compile(pattern, re.I) for pattern in ALLOW_PHRASES]


def banned_hits(text):
    clean = text
    for allow in ALLOW_RE:
        clean = allow.sub(lambda mm: " " * len(mm.group(0)), clean)
    hits = []
    for regex, label in BANNED_RE:
        for mm in regex.finditer(clean):
            hits.append((label, mm.group(0)))
    return hits


def scan_text(path, line, text, where):
    for label, word in banned_hits(text):
        report(path, line, "ERROR", "banned-word", f'"{word}" ({label}) in {where} – Wortliste §0.7')


for p in lang_files:
    t = strip_comments(read(p))
    for m in re.finditer(r'\[\s*"([a-z]+\.[A-Za-z0-9_.]+)"\s*\]\s*=\s*', t):
        value, _ = parse_concat_at(t, m.end())
        if value is not None:
            scan_text(p, lineno(t, m.start()), value, f'Lang "{m.group(1)}"')

for p in files("shared/Config"):
    t = strip_comments(read(p))
    for m in re.finditer(r"\b(Name|Desc|Title)\s*=\s*", t):
        start = m.end()
        value, _ = parse_concat_at(t, start)
        if value is not None:
            scan_text(p, lineno(t, m.start()), value, f"Config-{m.group(1)}")
        elif start < len(t) and t[start] == "{":
            depth, j = 0, start
            while j < len(t):
                if t[j] == "{":
                    depth += 1
                elif t[j] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            k = start + 1
            while k < j:
                if t[k] in "\"'" or t.startswith("[[", k) or re.match(r"\[=+\[", t[k:]):
                    value, nk = parse_string_at(t, k)
                    if value is not None:
                        scan_text(p, lineno(t, k), value, f"Config-{m.group(1)}")
                        k = nk
                        continue
                k += 1

# ---------------------------------------------------------------- 12) EFFECTS (§C7.4)
effect_patterns = [
    r'\bEffect\(\s*[^,()]+?,\s*"(\w+)"',  # PlayerStateService.Effect(p, "Name", …)
    r'\bEffectAll\(\s*"(\w+)"',  # PlayerStateService.EffectAll("Name", …)
    r'"Effect"\s*,\s*[^,()]+?,\s*"(\w+)"',  # call("PlayerStateService", "Effect", p, "Name")
    r'"EffectAll"\s*,\s*"(\w+)"',
]
for p in server_files:
    t = strip_comments(read(p))
    for pattern in effect_patterns:
        for m in re.finditer(pattern, t):
            if m.group(1) not in EFFECTS:
                report(p, lineno(t, m.start()), "ERROR", "effects", f'Effekt "{m.group(1)}" ist nicht in der Registry §C7.4')
registered = {}
for p in client_files:
    t = strip_comments(read(p))
    owner = os.path.splitext(os.path.basename(p))[0]
    for m in re.finditer(r'\bEffects[.:]Register\(\s*"(\w+)"', t):
        name = m.group(1)
        ln = lineno(t, m.start())
        if name not in EFFECTS:
            report(p, ln, "ERROR", "effects", f'Effekt "{name}" ist nicht in der Registry §C7.4')
        elif EFFECTS[name] != owner and not (owner == "Effects" and EFFECTS[name] == "Effects"):
            report(p, ln, "ERROR", "effects", f'Effekt "{name}" gehört {EFFECTS[name]} (ein Effekt = ein Besitzer)')
        if name in registered and registered[name] != p:
            report(p, ln, "ERROR", "effects", f'Effekt "{name}" wird doppelt registriert (auch in {rel(registered[name])})')
        registered.setdefault(name, p)
    for m in re.finditer(r'\bEffects[.:]Play\(\s*"(\w+)"', t):
        if m.group(1) not in EFFECTS:
            report(p, lineno(t, m.start()), "ERROR", "effects", f'Effekt "{m.group(1)}" ist nicht in der Registry §C7.4')

# ---------------------------------------------------------------- 13) STATE_KEYS (§C10)
STATE_KEYS = {
    "Settings": {"PlayerStateService"}, "Flags": {"PlayerStateService"}, "Server": {"PlayerStateService"},
    "Market": {"MarketService"},
    "Depot": {"OrderService"}, "League": {"OrderService"},
    "Credits": {"MonetizationService", "ShopService"}, "Passes": {"MonetizationService", "ShopService"},
    "Club": {"MonetizationService", "ShopService"}, "Boosts": {"MonetizationService", "ShopService"},
    "Offers": {"MonetizationService", "ShopService"}, "RandomAllowed": {"MonetizationService", "ShopService"},
    "TradingAllowed": {"MonetizationService", "ShopService"}, "Starter": {"MonetizationService", "ShopService"},
    "Tower": {"TowerService", "PlotService"}, "Income": {"TowerService", "PlotService"},
    "Plot": {"TowerService", "PlotService"},
    "Garage": {"VehicleService"},
    "Life": {"LifestyleService"}, "Storage": {"LifestyleService"},
    "Prog": {"ProgressionService", "RewardService", "CommunityService", "LeaderboardService"},
    "Quests": {"ProgressionService", "RewardService", "CommunityService", "LeaderboardService"},
    "Login": {"ProgressionService", "RewardService", "CommunityService", "LeaderboardService"},
    "Season": {"ProgressionService", "RewardService", "CommunityService", "LeaderboardService"},
    "Social": {"ProgressionService", "RewardService", "CommunityService", "LeaderboardService"},
    "Event": {"EventService"},
}
provided = {}
for p in server_files:
    t = strip_comments(read(p))
    owner = os.path.splitext(os.path.basename(p))[0]
    for pattern in (r'\bProvide\(\s*"(\w+)"', r'"Provide"\s*,\s*"(\w+)"'):
        for m in re.finditer(pattern, t):
            key = m.group(1)
            ln = lineno(t, m.start())
            if key not in STATE_KEYS:
                report(p, ln, "ERROR", "state-keys", f'State-Schlüssel "{key}" ist nicht in §C10')
                continue
            if key in provided and provided[key] != p:
                report(p, ln, "ERROR", "state-keys", f'State-Schlüssel "{key}" wird doppelt geliefert (auch in {rel(provided[key])})')
            provided.setdefault(key, p)
            if owner not in STATE_KEYS[key]:
                report(p, ln, "WARN", "state-keys", f'State-Schlüssel "{key}" gehört laut §C10 zu {"/".join(sorted(STATE_KEYS[key]))}')

for rule in sorted(stats):
    print(f"(Abdeckung) {rule}: {stats[rule]}", file=sys.stderr)
problems.sort()
errors = 0
for path, line, level, kind, msg in problems:
    if level == "ERROR":
        errors += 1
    print(f"{path}:{line}: {level}: {kind}: {msg}")
print(f"-- {errors} ERRORs, {len(problems) - errors} WARNs")
sys.exit(1 if errors else 0)
