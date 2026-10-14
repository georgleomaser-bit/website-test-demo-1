#!/usr/bin/env python3
# =====================================================================
#  AKYTEX TYCOON – Headless-Harness: Bundler
#  Baut aus dem Rojo-Projekt (default.project.json) ein Luau-Modul `out/bundle.luau`:
#    return {
#      project = "AkytexTycoon",
#      tree = { name, className, properties = {…}, source = "src/…", children = { … } },  -- Instanz-Skelett
#      sources = { ["src/…/Datei.luau"] = [==[ … ]==], … },                                -- alle Skript-Quelltexte
#    }
#  Der Baum kommt aus `rojo sourcemap --include-non-scripts` (falls rojo installiert ist), sonst aus einer
#  eingebauten Nachbildung der Rojo-Regeln ($path-Ordner -> Folder, init.luau -> ModuleScript des Ordners,
#  *.server.luau -> Script, *.client.luau -> LocalScript, *.luau -> ModuleScript). `$properties` aus
#  default.project.json werden je Knoten übernommen (Luau wandelt sie gegen die API-Typen um).
#  Quelltexte stehen als Long-Strings mit passender `=`-Tiefe im Bundle; die Laufzeit kompiliert jeden mit
#  loadstring(src, "=" .. relpfad), damit Tracebacks `src/…:Zeile` zeigen.
#
#  Aufruf:  python3 tools/headless/bundle.py [--project default.project.json] [--out tools/headless/out/bundle.luau]
#  Nur Python-Standardbibliothek.
# =====================================================================
import argparse
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

SCRIPT_EXT = (".luau", ".lua")


def classify(fname):
    """Rojo-Dateiregeln: (Klasse, Name) für eine Skriptdatei, sonst None."""
    for ext in SCRIPT_EXT:
        if fname.endswith(".server" + ext):
            return "Script", fname[: -len(".server" + ext)]
        if fname.endswith(".client" + ext):
            return "LocalScript", fname[: -len(".client" + ext)]
    for ext in SCRIPT_EXT:
        if fname.endswith(ext):
            return "ModuleScript", fname[: -len(ext)]
    return None


def tree_from_dir(path, name, root):
    """Nachbildung von Rojo für einen $path (Ordner oder Datei)."""
    full = os.path.join(root, path)
    if os.path.isfile(full):
        c = classify(os.path.basename(full))
        if not c:
            return None
        return {"name": name, "className": c[0], "filePaths": [path]}
    node = {"name": name, "className": "Folder", "children": []}
    entries = sorted(os.listdir(full))
    for init in ("init.server.luau", "init.client.luau", "init.luau", "init.server.lua", "init.client.lua", "init.lua"):
        if init in entries:
            node["className"] = classify(init)[0]
            node["filePaths"] = [os.path.join(path, init)]
            break
    for e in entries:
        if e.startswith("init.") and classify(e):
            continue
        sub = os.path.join(path, e)
        if os.path.isdir(os.path.join(root, sub)):
            child = tree_from_dir(sub, e, root)
            if child:
                node["children"].append(child)
        else:
            c = classify(e)
            if c:
                node["children"].append({"name": c[1], "className": c[0], "filePaths": [sub]})
    return node


# Namen, aus denen Rojo die Klasse ableitet (Services und Sonderordner von StarterPlayer)
INFER_CLASS = {"StarterPlayerScripts", "StarterCharacterScripts"}


def tree_from_project(proj_node, name, root, is_root=False):
    cls = proj_node.get("$className")
    if cls is None and (is_root or name in INFER_CLASS):
        cls = name
    node = {"name": name, "className": cls, "children": []}
    if "$path" in proj_node:
        sub = tree_from_dir(proj_node["$path"], name, root)
        if sub:
            node["className"] = node["className"] or sub["className"]
            node["children"] = sub.get("children", [])
            if "filePaths" in sub:
                node["filePaths"] = sub["filePaths"]
    if node["className"] is None:
        node["className"] = "Folder"
    for k, v in proj_node.items():
        if not k.startswith("$"):
            node["children"].append(tree_from_project(v, k, root, is_root=(node["className"] == "DataModel")))
    return node


def rojo_sourcemap(project_file, root):
    exe = shutil.which("rojo")
    if not exe:
        return None
    try:
        out = subprocess.run(
            [exe, "sourcemap", "--include-non-scripts", project_file],
            cwd=root,
            capture_output=True,
            text=True,
            timeout=120,
        )
    except Exception:
        return None
    if out.returncode != 0:
        sys.stderr.write("rojo sourcemap fehlgeschlagen, nutze eingebaute Rojo-Regeln:\n" + out.stderr)
        return None
    return json.loads(out.stdout)


def attach_properties(sm_node, proj_node):
    """$properties (und $attributes) aus default.project.json an die Sourcemap-Knoten hängen."""
    props = proj_node.get("$properties")
    if props:
        sm_node["properties"] = props
    attrs = proj_node.get("$attributes")
    if attrs:
        sm_node["attributes"] = attrs
    children = {c["name"]: c for c in sm_node.get("children", [])}
    for k, v in proj_node.items():
        if k.startswith("$") or not isinstance(v, dict):
            continue
        child = children.get(k)
        if child is None:
            # Knoten ohne Inhalt (z. B. Service nur mit $properties) – rojo lässt ihn evtl. weg
            child = {"name": k, "className": v.get("$className") or k, "children": []}
            sm_node.setdefault("children", []).append(child)
        attach_properties(child, v)


def lua_long_string(s):
    level = 0
    while ("]" + "=" * level + "]") in s or s.endswith("]" + "=" * level):
        level += 1
    eq = "=" * level
    # Führender Zeilenumbruch wird von Lua nach "[==[" verschluckt -> immer einen voranstellen
    return "[" + eq + "[\n" + s + "]" + eq + "]"


def lua_value(v, indent=""):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        return "{ " + ", ".join(lua_value(x, indent) for x in v) + " }"
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            parts.append("[" + json.dumps(k, ensure_ascii=False) + "] = " + lua_value(x, indent))
        return "{ " + ", ".join(parts) + " }"
    if v is None:
        return "nil"
    raise TypeError("nicht unterstützter Property-Wert: %r" % (v,))


def emit_tree(node, out, sources, root, depth=1):
    ind = "\t" * depth
    out.append(ind + "{")
    out.append(ind + "\tname = " + json.dumps(node["name"], ensure_ascii=False) + ",")
    out.append(ind + "\tclassName = " + json.dumps(node["className"]) + ",")
    fps = [p for p in node.get("filePaths", []) if p.endswith(SCRIPT_EXT)]
    if fps and node["className"] in ("Script", "LocalScript", "ModuleScript"):
        rel = fps[0].replace(os.sep, "/")
        with open(os.path.join(root, rel), "r", encoding="utf-8") as f:
            sources[rel] = f.read()
        out.append(ind + "\tsource = " + json.dumps(rel) + ",")
    if node.get("properties"):
        out.append(ind + "\tproperties = " + lua_value(node["properties"]) + ",")
    if node.get("attributes"):
        out.append(ind + "\tattributes = " + lua_value(node["attributes"]) + ",")
    kids = node.get("children", [])
    if kids:
        out.append(ind + "\tchildren = {")
        for c in kids:
            emit_tree(c, out, sources, root, depth + 2)
        out.append(ind + "\t},")
    out.append(ind + "},")


def main():
    ap = argparse.ArgumentParser(description="Headless-Harness: Rojo-Projekt -> out/bundle.luau")
    ap.add_argument("--project", default="default.project.json")
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--out", default=os.path.join(HERE, "out", "bundle.luau"))
    ap.add_argument("--no-rojo", action="store_true", help="eingebaute Rojo-Regeln statt `rojo sourcemap`")
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    with open(os.path.join(root, args.project), "r", encoding="utf-8") as f:
        project = json.load(f)

    sm = None if args.no_rojo else rojo_sourcemap(args.project, root)
    via = "rojo sourcemap"
    if sm is None:
        sm = tree_from_project(project["tree"], project.get("name", "Game"), root, is_root=True)
        via = "eingebaute Rojo-Regeln"
    sm["name"] = project.get("name", sm.get("name", "Game"))
    attach_properties(sm, project["tree"])

    out = ["--!nocheck", "-- ERZEUGT von tools/headless/bundle.py (" + via + ") – nicht von Hand ändern.", "return {"]
    out.append("\tproject = " + json.dumps(sm["name"]) + ",")
    out.append("\ttree =")
    sources = {}
    body = []
    emit_tree(sm, body, sources, root, 1)
    body[0] = body[0].lstrip()
    out.extend(body)
    out.append("\tsources = {")
    for rel in sorted(sources):
        out.append("\t\t[" + json.dumps(rel) + "] = " + lua_long_string(sources[rel]) + ",")
    out.append("\t},")
    out.append("}")
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    total = sum(s.count("\n") + 1 for s in sources.values())
    print("bundle: %d Skripte, %d Zeilen -> %s (%s)" % (len(sources), total, os.path.relpath(args.out, root), via))


if __name__ == "__main__":
    main()
