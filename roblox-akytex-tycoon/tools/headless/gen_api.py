#!/usr/bin/env python3
# =====================================================================
#  AKYTEX TYCOON – Headless-Harness: API-Daten-Generator
#  Erzeugt tools/headless/api_data.luau (wird committet – die Quelldateien gibt es in späteren Sitzungen evtl. nicht).
#
#  Quellen (Pfade per Option überschreibbar):
#   --types   globalTypes.d.luau (luau-lsp)      -> Primärquelle: Klassen, Super, Member-Listen, Enum-Namen,
#                                                    CREATABLE_INSTANCES/SERVICES, Datentyp-Member + Konstruktoren
#   --dump    Full-API-Dump.json (Roblox)          -> Ergänzung: Enum-WERTE (fehlen in globalTypes!), genaue
#                                                    Zahlentypen (float/double/int/int64), Tags ReadOnly/Yields/
#                                                    Deprecated/NotReplicated, Sicherheitsstufen, skriptbare
#                                                    Member, die luau-lsp weglässt (z. B. GuiObject.Draggable)
#   --db      rbx_reflection_database.msgpack      -> Standardwerte je konkreter Klasse (Part.Size = 4,1.2,2 usw.)
#   --docs    creator-docs .../datatypes           -> BrickColor-Tabelle (Name/Nummer/Palette/RGB),
#                                                    Font.fromEnum-Zuordnung
#  Abweichung von der Spezifikation (nur globalTypes): globalTypes enthält keine Enum-Werte, keine Defaults und keine
#  ReadOnly-Kennzeichen – ohne Dump/DB wären Enum.FromValue, Defaults und „Property is read only“ nicht treu.
#
#  Aufruf:  python3 tools/headless/gen_api.py            (Standardpfade, siehe unten)
#           python3 tools/headless/gen_api.py --check    (nur Stichproben prüfen, nichts schreiben)
#  Nur Python-Standardbibliothek.
#
#  Format von api_data.luau (kompakt, siehe auch runtime/Instance/Api.luau):
#   classes[Name] = { s = Superklasse, f = Klassen-Flags, p = {Prop = "Typ|Flags"}, m = {Methode = "Flags"},
#                     e = {Event = "Flags"}, c = {Callback = "Flags"}, d = {Prop = Default (nur Abweichung zur Super)} }
#     Klassen-Flags: c = erzeugbar (Instance.new), s = Service, n = NotReplicated, d = deprecated
#     Typ: b bool, s string, f float, d double, i int, l int64, n number (unbekannt), a any/Tabelle, F Funktion,
#          C:<Datentyp>, E:<Enum>, I:<Klasse>
#     Member-Flags: r = read only, w = nicht schreibbar (Sicherheit), x = nicht zugreifbar (Sicherheit),
#                   d = deprecated, y = yieldet, h = hidden (NotReplicated wird bei Properties bewusst NICHT
#                   übernommen: bei BasePart.Size/Color repliziert in Roblox ein verstecktes Schwester-Property)
#   Default-Werte: Zahl/String/Bool direkt, Datentypen als Tabelle {"V3",x,y,z}, {"CF",12 Zahlen}, {"C3",r,g,b},
#                  {"U2",xs,xo,ys,yo}, {"U",s,o}, {"V2",x,y}, {"BC",nummer}, {"NS",t,v,e,...}, {"CS",t,r,g,b,...},
#                  {"NR",min,max}, {"FT",family,weight,style}, {"RC",x0,y0,x1,y1}, {"FA",…}, {"AX",…}, {"PP",…}
#                  Enums als Zahl (Wert), Instanz-Referenzen fehlen (= nil).
#   enums[Name] = { Item = Wert, ... }      enumOrder[Name] = { "Item", ... } (Deklarationsreihenfolge)
#   creatable = {Name = true}, services = {Name = true}
#   datatypes[Name] = { p = {...}, m = {...}, statics = {...} }   (aus globalTypes, für Vollständigkeits-Checks)
#   brickColors = { {Nummer, "Name", r, g, b, Palette-Index oder -1}, ... }   fontEnum = {EnumName = "rbxasset://…"}
# =====================================================================
import argparse
import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SP = "/tmp/claude-0/-home-user-website-test-demo-1/14caf8fd-3993-54cd-bb2d-9f5bab2d1eaf/scratchpad"
DEFAULTS = {
    "types": os.path.join(SP, "globalTypes.d.luau"),
    "dump": os.path.join(SP, "assets_dl", "Full-API-Dump.json"),
    "db": "/root/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/"
    "rbx_reflection_database-3.0.1+roblox-741/database.msgpack",
    "docs": os.path.join(SP, "cdocs", "repo", "content", "en-us", "reference", "engine", "datatypes"),
    "out": os.path.join(HERE, "api_data.luau"),
}

# ---------------------------------------------------------------------------------------------------------------
#  Minimaler MessagePack-Decoder (die Reflection-DB ist serde-msgpack: Structs als Arrays)
# ---------------------------------------------------------------------------------------------------------------


def msgpack_unpack(b):
    pos = 0

    def rn(n):
        nonlocal pos
        v = int.from_bytes(b[pos : pos + n], "big")
        pos += n
        return v

    def rs(n):
        nonlocal pos
        v = bytes(b[pos : pos + n]).decode("utf-8", "replace")
        pos += n
        return v

    def rkey():
        k = rd()
        if isinstance(k, (list, dict)):
            k = json.dumps(k)
        return k

    def rd():
        nonlocal pos
        t = b[pos]
        pos += 1
        if t <= 0x7F:
            return t
        if 0x80 <= t <= 0x8F:
            return {rkey(): rd() for _ in range(t & 0x0F)}
        if 0x90 <= t <= 0x9F:
            return [rd() for _ in range(t & 0x0F)]
        if 0xA0 <= t <= 0xBF:
            return rs(t & 0x1F)
        if t >= 0xE0:
            return t - 0x100
        if t == 0xC0:
            return None
        if t == 0xC2:
            return False
        if t == 0xC3:
            return True
        if t in (0xC4, 0xC5, 0xC6):
            n = rn({0xC4: 1, 0xC5: 2, 0xC6: 4}[t])
            v = bytes(b[pos : pos + n])
            pos += n
            return v
        if t == 0xCA:
            v = struct.unpack(">f", b[pos : pos + 4])[0]
            pos += 4
            return v
        if t == 0xCB:
            v = struct.unpack(">d", b[pos : pos + 8])[0]
            pos += 8
            return v
        if t == 0xCC:
            return rn(1)
        if t == 0xCD:
            return rn(2)
        if t == 0xCE:
            return rn(4)
        if t == 0xCF:
            return rn(8)
        if t == 0xD0:
            return struct.unpack(">b", bytes([rn(1)]))[0]
        if t == 0xD1:
            v = struct.unpack(">h", b[pos : pos + 2])[0]
            pos += 2
            return v
        if t == 0xD2:
            v = struct.unpack(">i", b[pos : pos + 4])[0]
            pos += 4
            return v
        if t == 0xD3:
            v = struct.unpack(">q", b[pos : pos + 8])[0]
            pos += 8
            return v
        if t == 0xD9:
            return rs(rn(1))
        if t == 0xDA:
            return rs(rn(2))
        if t == 0xDB:
            return rs(rn(4))
        if t == 0xDC:
            return [rd() for _ in range(rn(2))]
        if t == 0xDD:
            return [rd() for _ in range(rn(4))]
        if t == 0xDE:
            return {rkey(): rd() for _ in range(rn(2))}
        if t == 0xDF:
            return {rkey(): rd() for _ in range(rn(4))}
        raise ValueError("msgpack: unbekannter Typ 0x%02x an %d" % (t, pos - 1))

    return rd()


# ---------------------------------------------------------------------------------------------------------------
#  globalTypes.d.luau parsen
# ---------------------------------------------------------------------------------------------------------------

DATATYPE_NAMES = set()  # wird beim Parsen gefüllt (Typen ohne "extends" vor "Object")


def parse_types(path):
    src = open(path, encoding="utf-8").read()
    first, rest = src.split("\n", 1)
    if not first.startswith("--#METADATA#"):
        raise SystemExit("globalTypes: METADATA-Kopfzeile fehlt")
    meta = json.loads(first[len("--#METADATA#") :])
    lines = rest.split("\n")
    classes = {}  # name -> {"super":..., "props":{name:type}, "methods":{name:dep}, "events":{}, "callbacks":{}}
    enums = {}  # name -> [items]
    datatypes = {}
    statics = {}
    i = 0
    n = len(lines)
    hdr = re.compile(r"^declare extern type (\w+)(?: extends (\w+))? with(?: end)?\s*$")
    while i < n:
        line = lines[i]
        m = hdr.match(line)
        if m:
            name, sup = m.group(1), m.group(2)
            one_line = line.rstrip().endswith(" end")
            body = []
            i += 1
            if not one_line:
                while i < n and lines[i].strip() != "end":
                    body.append(lines[i])
                    i += 1
                i += 1
            if name.startswith("Enum") and sup == "EnumItem":
                continue
            if name.startswith("Enum") and name.endswith("_INTERNAL") and sup == "Enum":
                ename = name[4 : -len("_INTERNAL")]
                items = []
                for b in body:
                    mm = re.match(r"^\s+(\w+): Enum\w+\s*$", b)
                    if mm:
                        items.append(mm.group(1))
                enums[ename] = items
                continue
            info = parse_members(body)
            if sup is None and name not in ("Object", "Enum", "EnumItem"):
                datatypes[name] = info
                continue
            if name in ("Enum", "EnumItem"):
                continue
            info["super"] = sup
            classes[name] = info
            continue
        m = re.match(r"^declare (\w+): \{\s*$", line)
        if m:
            name = m.group(1)
            body = []
            i += 1
            while i < n and not lines[i].startswith("}"):
                body.append(lines[i])
                i += 1
            i += 1
            st = []
            for b in body:
                mm = re.match(r"^\s+(\w+):", b)
                if mm:
                    st.append(mm.group(1))
            statics[name] = st
            continue
        i += 1
    return meta, classes, enums, datatypes, statics


def parse_members(body):
    props, methods, events, callbacks = {}, {}, {}, {}
    deprecated_next = False
    for raw in body:
        s = raw.strip()
        if not s:
            continue
        if s.startswith("@"):
            if "deprecated" in s:
                deprecated_next = True
            continue
        m = re.match(r"^function (\w+)\(", s)
        if m:
            nm = m.group(1)
            if nm.startswith("__"):
                deprecated_next = False
                continue
            # Overloads (z. B. WaitForChild) zusammenfassen; deprecated nur wenn alle Varianten deprecated
            if nm in methods:
                methods[nm] = methods[nm] and deprecated_next
            else:
                methods[nm] = deprecated_next
            deprecated_next = False
            continue
        m = re.match(r"^(\w+): (.+)$", s)
        if m:
            nm, ty = m.group(1), m.group(2).strip()
            if ty.startswith("RBXScriptSignal"):
                events[nm] = deprecated_next
            elif ty.startswith("("):
                callbacks[nm] = deprecated_next
            else:
                props[nm] = (ty, deprecated_next)
            deprecated_next = False
            continue
        deprecated_next = False
    return {"props": props, "methods": methods, "events": events, "callbacks": callbacks}


def lsp_type_code(ty, classes, enums):
    t = ty.strip()
    opt = t.endswith("?")
    if opt:
        t = t[:-1].strip()
    if t.startswith("(") and t.endswith(")") and "->" not in t:
        t = t[1:-1].strip()
    if t in ("number",):
        return "n"
    if t in ("string", "ContentId", "ProtectedString", "BinaryString", "QDir", "QFont"):
        return "s"
    if t == "boolean":
        return "b"
    if t.startswith("Enum") and t[4:] in enums:
        return "E:" + t[4:]
    if t in classes:
        return "I:" + t
    if t in DATATYPE_NAMES:
        return "C:" + t
    if "->" in t:
        return "F"
    return "a"


# ---------------------------------------------------------------------------------------------------------------
#  API-Dump
# ---------------------------------------------------------------------------------------------------------------

PRIM = {"bool": "b", "string": "s", "float": "f", "double": "d", "int": "i", "int64": "l"}
STRINGISH = {"ContentId", "ProtectedString", "BinaryString", "QDir", "QFont", "SharedString"}


def dump_type_code(vt):
    cat, nm = vt.get("Category"), vt.get("Name")
    if cat == "Primitive":
        return PRIM.get(nm, "a")
    if cat == "Enum":
        return "E:" + nm
    if cat == "Class":
        return "I:" + nm
    if cat == "DataType":
        if nm in STRINGISH:
            return "s"
        if nm in ("Color3uint8",):
            return "C:Color3"
        return "C:" + nm
    return "a"


def member_tags(m):
    tags = set()
    for t in m.get("Tags") or []:
        if isinstance(t, str):
            tags.add(t)
    return tags


def security_flags(m, kind):
    sec = m.get("Security")
    flags = ""
    if isinstance(sec, dict):
        r, w = sec.get("Read", "None"), sec.get("Write", "None")
        if r != "None":
            flags += "x"
        elif kind == "Property" and w != "None":
            flags += "w"
    elif isinstance(sec, str) and sec != "None":
        flags += "x"
    return flags


# ---------------------------------------------------------------------------------------------------------------
#  Reflection-DB-Defaults -> Luau-Literal-Struktur (Python-Werte, später serialisiert)
# ---------------------------------------------------------------------------------------------------------------


def f32(x):
    return struct.unpack("<f", struct.pack("<f", float(x)))[0]


def convert_variant(v, tcode):
    """rbx_types-Variant (dict mit genau einem Schlüssel) -> Python-Repräsentation oder None (= kein Default)."""
    if not isinstance(v, dict) or len(v) != 1:
        return None
    (k, x), = v.items()
    if k == "Bool":
        return bool(x)
    if k in ("Float32", "Float64", "Int32", "Int64"):
        if tcode == "b":
            return None
        return x
    if k in ("String", "ContentId"):
        if isinstance(x, (bytes, bytearray)):
            try:
                x = x.decode("utf-8")
            except Exception:
                return None
        return x if isinstance(x, str) else None
    if k == "Content":
        # Content-Variant: {"None": ...} | {"Uri": "..."} – als String-Property behandeln
        if tcode == "s":
            if isinstance(x, dict) and "Uri" in x:
                return x["Uri"]
            return ""
        return None
    if k == "Enum":
        return int(x)
    if k == "Vector3":
        return ["V3", *x]
    if k == "Vector2":
        return ["V2", *x]
    if k == "Vector3int16":
        return ["V3i", *x]
    if k == "Vector2int16":
        return ["V2i", *x]
    if k == "CFrame":
        pos, rot = x
        return ["CF", pos[0], pos[1], pos[2], *rot[0], *rot[1], *rot[2]]
    if k == "Color3":
        return ["C3", *x]
    if k == "Color3uint8":
        return ["C3", x[0] / 255, x[1] / 255, x[2] / 255]
    if k == "BrickColor":
        return ["BC", int(x)]
    if k == "UDim":
        return ["U", x[0], x[1]]
    if k == "UDim2":
        return ["U2", x[0][0], x[0][1], x[1][0], x[1][1]]
    if k == "NumberRange":
        return ["NR", x[0], x[1]]
    if k in ("NumberSequence", "ColorSequence"):
        # serde: Struct {keypoints} -> [ [kp, kp, ...] ]; NumberSequenceKeypoint = (time, value, envelope),
        # ColorSequenceKeypoint = (time, [r, g, b])
        kps = x[0] if isinstance(x, list) and len(x) == 1 and isinstance(x[0], list) else x
        out = ["NS" if k == "NumberSequence" else "CS"]
        for kp in kps:
            if k == "NumberSequence":
                t, val, env = kp
                out += [t, val, env]
            else:
                t, c = kp
                out += [t, c[0], c[1], c[2]]
        return out
    if k == "Rect":
        (a, b), (c, d) = x
        return ["RC", a, b, c, d]
    if k == "Font":
        fam, weight, style = x[0], x[1], x[2]
        return ["FT", fam, weight, style]
    if k == "PhysicalProperties":
        if x == "Default" or x is None:
            return None
        if isinstance(x, dict) and "Custom" in x:
            c = x["Custom"]
            if isinstance(c, list):
                return ["PP", *c]
        return None
    if k == "Faces":
        return ["FA", int(x)]
    if k == "Axes":
        return ["AX", int(x)]
    if k == "Ray":
        (o, dd) = x
        return ["RY", *o, *dd]
    return None


def default_kind_ok(conv, tcode):
    """Prüft, ob ein DB-Default zum Property-Typ passt (sonst verwerfen)."""
    if conv is None:
        return False
    if tcode == "b":
        return isinstance(conv, bool)
    if tcode in ("f", "d", "i", "l", "n"):
        return isinstance(conv, (int, float)) and not isinstance(conv, bool)
    if tcode == "s":
        return isinstance(conv, str)
    if tcode.startswith("E:"):
        return isinstance(conv, int) and not isinstance(conv, bool)
    if tcode.startswith("C:"):
        want = tcode[2:]
        tag = {
            "Vector3": "V3", "Vector2": "V2", "CFrame": "CF", "Color3": "C3", "BrickColor": "BC", "UDim": "U",
            "UDim2": "U2", "NumberRange": "NR", "NumberSequence": "NS", "ColorSequence": "CS", "Rect": "RC",
            "Font": "FT", "PhysicalProperties": "PP", "Faces": "FA", "Axes": "AX", "Ray": "RY",
            "Vector3int16": "V3i", "Vector2int16": "V2i",
        }.get(want)
        return isinstance(conv, list) and tag is not None and conv[0] == tag
    return False


# ---------------------------------------------------------------------------------------------------------------
#  Docs: BrickColor-Tabelle + Font.fromEnum
# ---------------------------------------------------------------------------------------------------------------


def parse_brickcolors(docs):
    path = os.path.join(docs, "BrickColor.yaml")
    if not os.path.exists(path):
        return None
    txt = open(path, encoding="utf-8").read()
    rows = re.findall(r"<tr>(.*?)</tr>", txt, re.S)
    out = []
    for r in rows:
        cells = re.findall(r"<td>(.*?)</td>", r, re.S)
        if len(cells) < 5:
            continue
        name = re.sub(r"<.*?>", "", cells[1]).strip()
        num = re.sub(r"<.*?>", "", cells[2]).strip()
        pal = re.sub(r"<.*?>", "", cells[3]).strip()
        rgb = re.sub(r"<.*?>", "", cells[4]).strip()
        if not num.isdigit():
            continue
        try:
            r_, g_, b_ = [int(x.strip()) for x in rgb.split(",")]
        except ValueError:
            continue
        out.append([int(num), name, r_, g_, b_, int(pal) if pal.isdigit() else -1])
    return out


def parse_font_enum(docs):
    path = os.path.join(docs, "Font.yaml")
    if not os.path.exists(path):
        return None
    txt = open(path, encoding="utf-8").read()
    sec = txt.split("name: Font.fromEnum", 1)
    if len(sec) < 2:
        return None
    sec = sec[1].split("name: Font.fromName", 1)[0]
    rows = re.findall(r"<tr>(.*?)</tr>", sec, re.S)
    out = {}
    for r in rows:
        cells = re.findall(r"<td>(.*?)</td>", r, re.S)
        if len(cells) < 2:
            continue
        names = re.findall(r"Enum\.Font\.(\w+)\|", cells[0])
        fam = re.findall(r"(rbxasset://[^<]+)", cells[1])
        if names and fam:
            for nm in names:
                out[nm] = fam[0].strip()
    return out


# ---------------------------------------------------------------------------------------------------------------
#  Luau-Ausgabe
# ---------------------------------------------------------------------------------------------------------------

FONT_ENUM_SUPPLEMENT = {
    "Arial": "rbxasset://fonts/families/Arial.json",
    "ArialBold": "rbxasset://fonts/families/Arial.json",
    "Gotham": "rbxasset://fonts/families/GothamSSm.json",
    "GothamMedium": "rbxasset://fonts/families/GothamSSm.json",
    "GothamBold": "rbxasset://fonts/families/GothamSSm.json",
    "GothamBlack": "rbxasset://fonts/families/GothamSSm.json",
    "GothamSemibold": "rbxasset://fonts/families/GothamSSm.json",
    "Legacy": "rbxasset://fonts/families/LegacyArial.json",
}

IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
LUAU_KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil", "not",
    "or", "repeat", "return", "then", "true", "until", "while", "continue", "type", "export",
}


def lkey(k):
    if IDENT.match(k) and k not in LUAU_KEYWORDS:
        return k
    return "[" + lstr(k) + "]"


def lstr(s):
    out = ['"']
    for ch in s:
        o = ord(ch)
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif o < 32 or o == 127:
            out.append("\\%03d" % o)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def lnum(x):
    if isinstance(x, bool):
        return "true" if x else "false"
    if isinstance(x, int):
        return str(x)
    if x != x:
        return "0/0"
    if x == float("inf"):
        return "math.huge"
    if x == float("-inf"):
        return "-math.huge"
    if x == int(x) and abs(x) < 1e15:
        return str(int(x))
    r = repr(x)
    return r


def lval(v):
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return lnum(v)
    if isinstance(v, str):
        return lstr(v)
    if isinstance(v, list):
        return "{" + ",".join(lval(x) for x in v) + "}"
    if isinstance(v, dict):
        return "{" + ",".join(lkey(k) + "=" + lval(x) for k, x in sorted(v.items())) + "}"
    raise TypeError(type(v))


# ---------------------------------------------------------------------------------------------------------------
#  Hauptlogik
# ---------------------------------------------------------------------------------------------------------------


def build(args):
    meta, gt_classes, gt_enums, gt_datatypes, statics = parse_types(args.types)
    DATATYPE_NAMES.update(gt_datatypes.keys())
    DATATYPE_NAMES.update(["RBXScriptSignal", "RBXScriptConnection", "Content", "SharedTable", "RaycastResult"])
    dump = json.load(open(args.dump, encoding="utf-8"))
    dclasses = {c["Name"]: c for c in dump["Classes"]}
    denums = {e["Name"]: e for e in dump["Enums"]}

    db = msgpack_unpack(open(args.db, "rb").read())
    db_classes = db[1]
    db_enums = db[2]

    # ---------------- Klassen ----------------
    names = set(gt_classes) | set(dclasses)
    classes = {}
    creatable = set(meta.get("CREATABLE_INSTANCES", []))
    services = set(meta.get("SERVICES", []))
    for cn, c in dclasses.items():
        tags = set(t for t in (c.get("Tags") or []) if isinstance(t, str))
        if "Service" in tags:
            services.add(cn)
    for cn in sorted(names):
        g = gt_classes.get(cn)
        dc = dclasses.get(cn)
        sup = None
        if g is not None:
            sup = g["super"]
        elif dc is not None:
            sup = dc.get("Superclass")
            if sup == "<<<ROOT>>>":
                sup = None
        if cn == "Instance":
            sup = "Object" if "Object" in gt_classes else None
        if cn == "Object":
            sup = None
        ctags = set(t for t in ((dc or {}).get("Tags") or []) if isinstance(t, str))
        flags = ""
        if cn in creatable:
            flags += "c"
        if cn in services:
            flags += "s"
        if "NotReplicated" in ctags:
            flags += "n"
        if "Deprecated" in ctags:
            flags += "d"
        entry = {"s": sup, "f": flags, "p": {}, "m": {}, "e": {}, "c": {}}
        dmembers = {}
        if dc is not None:
            for m in dc["Members"]:
                dmembers.setdefault(m["Name"], m)
        # 1) globalTypes-Member
        if g is not None:
            for nm, (ty, dep) in g["props"].items():
                dm = dmembers.get(nm)
                fl = ""
                if dm is not None and dm["MemberType"] == "Property":
                    code = dump_type_code(dm["ValueType"])
                    if code == "a":
                        code = lsp_type_code(ty, gt_classes, gt_enums)
                    tg = member_tags(dm)
                    if "ReadOnly" in tg:
                        fl += "r"
                    fl += security_flags(dm, "Property")
                    if "Deprecated" in tg or dep:
                        fl += "d"
                    if "Hidden" in tg:
                        fl += "h"
                else:
                    code = lsp_type_code(ty, gt_classes, gt_enums)
                    if dep:
                        fl += "d"
                entry["p"][nm] = code + ("|" + fl if fl else "")
            for kind_key, gt_key, mtype in (("m", "methods", "Function"), ("e", "events", "Event"), ("c", "callbacks", "Callback")):
                for nm, dep in g[gt_key].items():
                    dm = dmembers.get(nm)
                    fl = ""
                    if dm is not None and dm["MemberType"] == mtype:
                        tg = member_tags(dm)
                        fl += security_flags(dm, mtype)
                        if "Deprecated" in tg or dep:
                            fl += "d"
                        if "Yields" in tg or "CanYield" in tg:
                            fl += "y"
                        if "Hidden" in tg:
                            fl += "h"
                    elif dep:
                        fl += "d"
                    entry[kind_key][nm] = fl
        # 2) skriptbare Dump-Member, die luau-lsp weglässt (deprecated Aliase usw.)
        for nm, dm in dmembers.items():
            mt = dm["MemberType"]
            key = {"Property": "p", "Function": "m", "Event": "e", "Callback": "c"}[mt]
            if nm in entry["p"] or nm in entry["m"] or nm in entry["e"] or nm in entry["c"]:
                continue
            tg = member_tags(dm)
            if "NotScriptable" in tg:
                continue
            sec = security_flags(dm, mt)
            if "x" in sec:
                continue
            fl = sec
            if mt == "Property":
                if "ReadOnly" in tg:
                    fl += "r"
                if "Deprecated" in tg:
                    fl += "d"
                if "Hidden" in tg:
                    fl += "h"
                if "WriteOnly" in tg:
                    continue
                entry["p"][nm] = dump_type_code(dm["ValueType"]) + ("|" + fl if fl else "")
            else:
                if "Deprecated" in tg:
                    fl += "d"
                if "Yields" in tg:
                    fl += "y"
                if "Hidden" in tg:
                    fl += "h"
                entry[key][nm] = fl
        classes[cn] = entry

    # Object-Member (luau-lsp) gehören in Roblox zu Instance – Instance erbt ohnehin von Object.
    # ---------------- Defaults ----------------
    def all_props(cn):
        out = {}
        chain = []
        c = cn
        while c is not None and c in classes:
            chain.append(c)
            c = classes[c]["s"]
        for c in reversed(chain):
            for nm, spec in classes[c]["p"].items():
                out[nm] = spec.split("|")[0]
        return out

    children = {}
    for cn, e in classes.items():
        if e["s"]:
            children.setdefault(e["s"], []).append(cn)

    flat_db = {}
    for cn in classes:
        dbc = db_classes.get(cn)
        if dbc is None:
            continue
        defaults = dbc[4] if isinstance(dbc, list) and len(dbc) > 4 else {}
        if not defaults:
            continue
        props = all_props(cn)
        conv = {}
        for pn, var in defaults.items():
            if pn not in props:
                continue
            code = props[pn]
            cv = convert_variant(var, code)
            if default_kind_ok(cv, code):
                conv[pn] = cv
        if conv:
            flat_db[cn] = conv

    # abstrakte Klassen: häufigster Wert unter allen konkreten Nachfahren (nur für eigene + geerbte Props)
    def descendants(cn):
        out = []
        st = list(children.get(cn, []))
        while st:
            x = st.pop()
            out.append(x)
            st.extend(children.get(x, []))
        return out

    flat = {}

    def key_of(v):
        return json.dumps(v, sort_keys=True)

    order = []
    seen = set()

    def visit(cn):
        if cn in seen or cn not in classes:
            return
        seen.add(cn)
        if classes[cn]["s"]:
            visit(classes[cn]["s"])
        order.append(cn)

    for cn in classes:
        visit(cn)
    for cn in order:
        if cn in flat_db:
            flat[cn] = dict(flat_db[cn])
            continue
        props = all_props(cn)
        votes = {}
        for dcn in descendants(cn):
            dd = flat_db.get(dcn)
            if not dd:
                continue
            for pn in props:
                if pn in dd:
                    votes.setdefault(pn, {}).setdefault(key_of(dd[pn]), [0, dd[pn]])[0] += 1
        res = {}
        for pn, vs in votes.items():
            best = max(vs.values(), key=lambda x: x[0])
            res[pn] = best[1]
        flat[cn] = res

    for cn in order:
        sup = classes[cn]["s"]
        base = flat.get(sup, {}) if sup else {}
        own = {}
        for pn, v in flat.get(cn, {}).items():
            if pn not in base or key_of(base[pn]) != key_of(v):
                own[pn] = v
        # Props, die die Super hat, diese Klasse (konkret, laut DB) aber anders/gar nicht: nichts tun
        if own:
            classes[cn]["d"] = own

    # ---------------- Enums ----------------
    enums = {}
    enum_order = {}
    for en in sorted(set(gt_enums) | set(denums)):
        items = {}
        order_l = []
        de = denums.get(en)
        if de is not None:
            for it in de["Items"]:
                items[it["Name"]] = it["Value"]
                order_l.append(it["Name"])
        dbe = db_enums.get(en)
        if isinstance(dbe, list) and len(dbe) > 1 and isinstance(dbe[1], dict):
            for nm, val in dbe[1].items():
                if nm not in items:
                    items[nm] = val
                    order_l.append(nm)
        for nm in gt_enums.get(en, []):
            if nm not in items:
                # Wert unbekannt: hinter den bekannten einsortieren (eindeutig, damit FromValue nichts verwechselt)
                items[nm] = 100000 + len(items)
                order_l.append(nm)
        enums[en] = items
        enum_order[en] = order_l

    # ---------------- Datentypen ----------------
    dts = {}
    for dn, info in gt_datatypes.items():
        dts[dn] = {
            "p": sorted(info["props"].keys()),
            "m": sorted(info["methods"].keys()),
            "statics": sorted(statics.get(dn, [])),
        }
    for dn, st in statics.items():
        if dn not in dts and dn[0].isupper() and dn not in ("Enum",) and dn not in classes:
            dts[dn] = {"p": [], "m": [], "statics": sorted(st)}

    brick = parse_brickcolors(args.docs) or []
    font_enum = parse_font_enum(args.docs) or {}
    # Die Docs-Tabelle lässt die ältesten Enum.Font-Werte weg; bekannte Zuordnungen ergänzen.
    for nm, fam in FONT_ENUM_SUPPLEMENT.items():
        if nm in enums.get("Font", {}):
            font_enum.setdefault(nm, fam)

    return {
        "version": "roblox-db-%s / api-dump" % ".".join(str(x) for x in db[0]),
        "classes": classes,
        "enums": enums,
        "enumOrder": enum_order,
        "creatable": sorted(c for c in creatable if c in classes),
        "services": sorted(s for s in services if s in classes),
        "datatypes": dts,
        "brickColors": brick,
        "fontEnum": font_enum,
    }


def emit(data, out):
    w = []
    w.append("-- AUTOMATISCH ERZEUGT von tools/headless/gen_api.py – nicht von Hand ändern.")
    w.append("-- Quellen: globalTypes.d.luau (luau-lsp), Full-API-Dump.json, rbx_reflection_database (" + data["version"] + "),")
    w.append("-- creator-docs (BrickColor-Tabelle, Font.fromEnum). Format: siehe Kopf von gen_api.py.")
    w.append("--!nocheck")
    w.append("local D = {}")
    w.append("D.version = " + lstr(data["version"]))
    w.append("local C = {}")
    w.append("D.classes = C")
    for cn in sorted(data["classes"]):
        e = data["classes"][cn]
        parts = []
        if e["s"]:
            parts.append("s=" + lstr(e["s"]))
        if e["f"]:
            parts.append("f=" + lstr(e["f"]))
        for k in ("p", "m", "e", "c"):
            if e[k]:
                parts.append(k + "={" + ",".join(lkey(nm) + "=" + lstr(v) for nm, v in sorted(e[k].items())) + "}")
        if e.get("d"):
            parts.append("d=" + lval(e["d"]))
        w.append("C[" + lstr(cn) + "]={" + ",".join(parts) + "}")
    w.append("local E = {}")
    w.append("D.enums = E")
    for en in sorted(data["enums"]):
        items = data["enums"][en]
        w.append("E[" + lstr(en) + "]={" + ",".join(lkey(k) + "=" + lnum(v) for k, v in sorted(items.items(), key=lambda kv: (kv[1], kv[0]))) + "}")
    w.append("local EO = {}")
    w.append("D.enumOrder = EO")
    for en in sorted(data["enumOrder"]):
        w.append("EO[" + lstr(en) + "]={" + ",".join(lstr(x) for x in data["enumOrder"][en]) + "}")
    w.append("D.creatable = {" + ",".join(lkey(c) + "=true" for c in data["creatable"]) + "}")
    w.append("D.services = {" + ",".join(lkey(c) + "=true" for c in data["services"]) + "}")
    w.append("local DT = {}")
    w.append("D.datatypes = DT")
    for dn in sorted(data["datatypes"]):
        x = data["datatypes"][dn]
        w.append(
            "DT[" + lstr(dn) + "]={p={" + ",".join(lstr(s) for s in x["p"]) + "},m={" + ",".join(lstr(s) for s in x["m"])
            + "},statics={" + ",".join(lstr(s) for s in x["statics"]) + "}}"
        )
    w.append("D.brickColors = {")
    for row in data["brickColors"]:
        w.append("\t" + lval(row) + ",")
    w.append("}")
    w.append("D.fontEnum = " + lval(data["fontEnum"]))
    w.append("return D")
    txt = "\n".join(w) + "\n"
    with open(out, "w", encoding="utf-8") as f:
        f.write(txt)
    return txt


def check(data):
    """Stichproben – bricht mit Exit-Code 1 ab, wenn etwas Grundlegendes fehlt."""
    C = data["classes"]
    problems = []

    def need(cond, msg):
        if not cond:
            problems.append(msg)

    def flat(cn, key):
        out = {}
        while cn:
            for k, v in C[cn][key].items():
                out.setdefault(k, v)
            cn = C[cn]["s"]
        return out

    def flat_d(cn):
        chain = []
        c = cn
        while c:
            chain.append(c)
            c = C[c]["s"]
        out = {}
        for c in reversed(chain):
            out.update(C[c].get("d", {}))
        return out

    need(C["Part"]["s"] == "FormFactorPart", "Part.Super")
    need(C["FormFactorPart"]["s"] == "BasePart", "FormFactorPart.Super")
    need(C["BasePart"]["s"] == "PVInstance", "BasePart.Super")
    need("c" in C["Part"]["f"], "Part creatable")
    need("c" not in C["BasePart"]["f"], "BasePart nicht creatable")
    pp = flat("Part", "p")
    need(pp.get("Size", "").startswith("C:Vector3"), "Part.Size Typ")
    need(pp.get("Anchored", "").startswith("b"), "Part.Anchored Typ")
    need(pp.get("Transparency", "").startswith("f"), "Part.Transparency float")
    need(pp.get("Material", "").startswith("E:Material"), "Part.Material Enum")
    need(pp.get("Parent", "").startswith("I:Instance"), "Instance.Parent")
    need("r" in pp.get("ClassName", "").split("|")[-1], "ClassName read only")
    need(pp.get("Shape", "").startswith("E:PartType"), "Part.Shape")
    pm = flat("Part", "m")
    need("FindFirstChild" in pm and "GetMass" in pm and "SetNetworkOwner" in pm, "Part Methoden")
    pe = flat("Part", "e")
    need("Touched" in pe and "ChildAdded" in pe and "Changed" in pe, "Part Events")
    dd = flat_d("Part")
    need(dd.get("Size") == ["V3", 4.0, f32(1.2), 2.0], "Part.Size Default %r" % dd.get("Size"))
    need(dd.get("Anchored") is False, "Part.Anchored Default")
    need(dd.get("Material") == 256, "Part.Material Default")
    tl = flat("TextLabel", "p")
    need(tl.get("Text", "").startswith("s"), "TextLabel.Text")
    need(tl.get("TextSize", "").startswith("f"), "TextLabel.TextSize")
    need(tl.get("Size", "").startswith("C:UDim2"), "TextLabel.Size")
    need(tl.get("FontFace", "").startswith("C:Font"), "TextLabel.FontFace")
    need(tl.get("TextBounds", "").startswith("C:Vector2") and "r" in tl["TextBounds"].split("|")[-1], "TextBounds ro")
    tld = flat_d("TextLabel")
    need(tld.get("Text") == "Label", "TextLabel.Text Default")
    hu = flat("Humanoid", "p")
    need(hu.get("WalkSpeed", "").startswith("f") and hu.get("Health", "").startswith("f"), "Humanoid Props")
    need("MoveTo" in flat("Humanoid", "m") and "Died" in flat("Humanoid", "e"), "Humanoid MoveTo/Died")
    hud = flat_d("Humanoid")
    need(hud.get("WalkSpeed") == 16 and hud.get("MaxHealth") == 100, "Humanoid Defaults %r" % [hud.get("WalkSpeed"), hud.get("MaxHealth")])
    tcs = C["TextChatService"]
    need("s" in tcs["f"], "TextChatService Service")
    need("OnIncomingMessage" in tcs["c"], "TextChatService.OnIncomingMessage Callback")
    need("SendingMessage" in flat("TextChatService", "e") or "MessageReceived" in flat("TextChatService", "e"), "TCS Events")
    prp = flat("ProximityPrompt", "p")
    need(prp.get("HoldDuration", "").startswith("f") and prp.get("KeyboardKeyCode", "").startswith("E:KeyCode"), "ProximityPrompt Props")
    need("Triggered" in flat("ProximityPrompt", "e") and "InputHoldBegin" in flat("ProximityPrompt", "m"), "ProximityPrompt Member")
    prd = flat_d("ProximityPrompt")
    need(prd.get("MaxActivationDistance") == 10 and prd.get("ActionText") == "Interact", "ProximityPrompt Defaults %r" % [prd.get("MaxActivationDistance"), prd.get("ActionText")])
    need(data["enums"]["Material"].get("Neon") == 288, "Enum.Material.Neon = 288")
    need(data["enums"]["KeyCode"].get("E") == 101, "Enum.KeyCode.E = 101")
    need("Player" in C and "y" in flat("Players", "m").get("GetUserIdFromNameAsync", ""), "Yields-Flag")
    need("x" in flat("Player", "p").get("OsPlatform", "x"), "Sicherheits-Flag OsPlatform")
    need("Draggable" in flat("Frame", "p"), "Dump-only Member (GuiObject.Draggable)")
    need(len(data["brickColors"]) > 150, "BrickColor-Tabelle")
    need(data["fontEnum"].get("GothamBold", "").endswith("GothamSSm.json"), "Font.fromEnum GothamBold")
    for dn in ("Vector3", "CFrame", "Color3", "UDim2", "DateTime", "Random", "TweenInfo", "Font"):
        need(dn in data["datatypes"], "Datentyp " + dn)
    if problems:
        print("CHECK FEHLGESCHLAGEN:")
        for p in problems:
            print("  -", p)
        return False
    print("CHECK OK: Part/BasePart/TextLabel/Humanoid/TextChatService/ProximityPrompt + Enums + Defaults stimmen.")
    return True


def main():
    ap = argparse.ArgumentParser(description="Erzeugt tools/headless/api_data.luau")
    for k in ("types", "dump", "db", "docs", "out"):
        ap.add_argument("--" + k, default=DEFAULTS[k])
    ap.add_argument("--check", action="store_true", help="nur prüfen, nichts schreiben")
    args = ap.parse_args()
    for k in ("types", "dump", "db"):
        if not os.path.exists(getattr(args, k)):
            sys.exit("Quelle fehlt: --%s %s (api_data.luau bleibt unverändert)" % (k, getattr(args, k)))
    data = build(args)
    ok = check(data)
    if not args.check:
        txt = emit(data, args.out)
        print("geschrieben: %s (%d Klassen, %d Enums, %d KB)" % (args.out, len(data["classes"]), len(data["enums"]), len(txt) // 1024))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
