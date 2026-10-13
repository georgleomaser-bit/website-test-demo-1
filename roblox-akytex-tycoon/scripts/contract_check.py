#!/usr/bin/env python3
"""Vertrags-Prüfer für AKYTEX Tycoon: findet Lücken zwischen Paketen, die luau-lsp nicht sieht
(Services ist `any`, ctx.Modules ist dynamisch, Request-Aktionen/Lang-Schlüssel/Effekte/State-Schlüssel sind Strings)
und setzt die Compliance-Regeln der Spec durch (DESIGN.md §C11.4, §0.7, §C7.4, §C10).
Aufruf (im Projektordner):  python3 scripts/contract_check.py .
Ausgabe: eine Zeile je Problem "datei:zeile: ERROR|WARN: art: nachricht". Exit 1 bei ERRORs.

Abschnitte:
   1) Services.X.Fn existiert            2) ctx.Modules.X.Fn existiert        2b) indirekte Aufrufe/Aliase
   3) require-Ziele                      4) Request-Aktionen (+ frozen §C9)    5) Remotes ∈ Net.RemoteList
   6) Lang-Schlüssel (LANG_PREFIX §C15)  7) Config-Abschnitte                  8) Hooks (+ frozen §C7.2)
   9) FIREWALL (§C11.4 #1/#2)           10) DEPOT_WRITE (§C11.4 #3)          11) BANNED_WORDS (§0.7)
  12) EFFECTS (§C7.4)                   13) STATE_KEYS (§C10)
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


# ---------------------------------------------------------------- 2b) indirekte Zugriffe: call("X","Fn"), Aliase
def check_indirect(paths, api, side):
    names = set(api.keys())
    for p in paths:
        t = strip_comments(read(p))
        # a) Hilfsfunktionen mit zwei String-Argumenten: call("TowerService", "Income", ...)
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
    for m in re.finditer(r'\bHandle\(\s*"([A-Za-z]+)"', t):
        name = m.group(1)
        ln = lineno(t, m.start())
        if name in handled and handled[name][0] != p:
            report(p, ln, "ERROR", "request", f'Aktion "{name}" wird doppelt registriert (auch in {rel(handled[name][0])})')
        handled.setdefault(name, (p, ln))
        if name not in REQUEST_ACTIONS:
            report(p, ln, "WARN", "request-frozen", f'Aktion "{name}" steht nicht in der frozen Liste §C9')
requested = {}
for p in client_files:
    t = strip_comments(read(p))
    for m in re.finditer(r'\bRequest(?:Full)?\(\s*"([A-Za-z]+)"', t):
        requested.setdefault(m.group(1), []).append((p, lineno(t, m.start())))
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

# ---------------------------------------------------------------- 6) Lang-Schlüssel (§C15: gleiche Liste wie Lang/init FILES)
LANG_PREFIX = ("core", "ui", "mkt", "news", "trade", "term", "tower", "tui", "world", "car", "life", "prog", "tut",
               "soc", "shop", "item", "admin", "evt")
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
            report(p, lineno(t, m.start()), "ERROR", "lang", f'Lang-Schlüssel "{key}" fehlt in src/shared/Lang')

# ---------------------------------------------------------------- 7) Config-Abschnitte
cfg_dir = os.path.join(SRC, "shared", "Config")
cfg_children = {os.path.splitext(f)[0] for f in os.listdir(cfg_dir)} if os.path.isdir(cfg_dir) else set()
cfg_init = read(os.path.join(cfg_dir, "init.luau")) if os.path.exists(os.path.join(cfg_dir, "init.luau")) else ""
cfg_top = set(re.findall(r"(?m)^\s*Config\.([A-Za-z_]\w*)\s*=", cfg_init)) | set(
    re.findall(r"\bfunction\s+Config[.:]([A-Za-z_]\w*)", cfg_init)
)
# Kind-Module werden unter ihrem Dateinamen eingehängt; die CHILDREN-Liste zählt auch, wenn die Datei noch fehlt
# (Config.Validate meldet fehlende Kinder selbst)
m_children = re.search(r"local\s+CHILDREN\s*=\s*\{(.*?)\}", cfg_init, re.S)
cfg_listed = set(re.findall(r'"([A-Za-z_]\w*)"', m_children.group(1))) if m_children else set()
cfg_known = cfg_top | (cfg_children - {"init"}) | cfg_listed
for p in all_files:
    t = strip_comments(read(p))
    for m in re.finditer(r"\bConfig\.([A-Z][A-Za-z_]\w*)", t):
        sec = m.group(1)
        if sec not in cfg_known:
            report(p, lineno(t, m.start()), "ERROR", "config", f"Config.{sec} existiert nicht (weder in Config/init noch als Kind-Modul)")

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
for p in client_files:
    t = strip_comments(read(p))
    for m in re.finditer(r'\bHooks\.Fire\(\s*"([A-Za-z:]+)"\s*(\.\.)?', t):
        name = m.group(1)
        if m.group(2):
            fired_prefix.add(name)
            if name not in HOOK_PREFIXES:
                report(p, lineno(t, m.start()), "WARN", "hook-frozen", f'Hook-Präfix "{name}" ist nicht frozen (§C7.2)')
        else:
            fired.add(name)
            if name not in HOOKS:
                report(p, lineno(t, m.start()), "WARN", "hook-frozen", f'Hook "{name}" ist nicht in der frozen Liste §C7.2')
    for m in re.finditer(r'\bFire\(\s*"([A-Za-z:]+)"\s*\.\.', t):
        fired_prefix.add(m.group(1))
    for m in re.finditer(r'\bHooks\.(?:On|Once)\(\s*"([A-Za-z:]+)"', t):
        name = m.group(1)
        listened.setdefault(name, (p, lineno(t, m.start())))
        if name not in HOOKS:
            report(p, lineno(t, m.start()), "WARN", "hook-frozen", f'Hook "{name}" ist nicht in der frozen Liste §C7.2')
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
    r'\bEffect\(\s*[^,()]+?,\s*"([A-Za-z]+)"',  # PlayerStateService.Effect(p, "Name", …)
    r'\bEffectAll\(\s*"([A-Za-z]+)"',  # PlayerStateService.EffectAll("Name", …)
    r'"Effect"\s*,\s*[^,()]+?,\s*"([A-Za-z]+)"',  # call("PlayerStateService", "Effect", p, "Name")
    r'"EffectAll"\s*,\s*"([A-Za-z]+)"',
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
    for m in re.finditer(r'\bEffects[.:]Register\(\s*"([A-Za-z]+)"', t):
        name = m.group(1)
        ln = lineno(t, m.start())
        if name not in EFFECTS:
            report(p, ln, "ERROR", "effects", f'Effekt "{name}" ist nicht in der Registry §C7.4')
        elif EFFECTS[name] != owner and not (owner == "Effects" and EFFECTS[name] == "Effects"):
            report(p, ln, "ERROR", "effects", f'Effekt "{name}" gehört {EFFECTS[name]} (ein Effekt = ein Besitzer)')
        if name in registered and registered[name] != p:
            report(p, ln, "ERROR", "effects", f'Effekt "{name}" wird doppelt registriert (auch in {rel(registered[name])})')
        registered.setdefault(name, p)
    for m in re.finditer(r'\bEffects[.:]Play\(\s*"([A-Za-z]+)"', t):
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
    for pattern in (r'\bProvide\(\s*"([A-Za-z]+)"', r'"Provide"\s*,\s*"([A-Za-z]+)"'):
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

problems.sort()
errors = 0
for path, line, level, kind, msg in problems:
    if level == "ERROR":
        errors += 1
    print(f"{path}:{line}: {level}: {kind}: {msg}")
print(f"-- {errors} ERRORs, {len(problems) - errors} WARNs")
sys.exit(1 if errors else 0)
