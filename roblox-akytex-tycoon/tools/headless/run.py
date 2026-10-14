#!/usr/bin/env python3
# =====================================================================
#  AKYTEX TYCOON – Headless-Harness: Szenarien ausführen
#  python3 tools/headless/run.py boot [--client 1|2] [--studio|--live] [--seconds 120] [--seed 1] [--echo]
#                                     [--no-bundle] [--out DIR]
#  Baut out/bundle.luau (bundle.py), startet den Luau-CLI mit run.luau und zerlegt stdout anhand der Marker
#  @@BEGIN name@@ … @@END name@@ in Dateien unter tools/headless/out/ (report.txt, report.json, output.txt,
#  ui_tree.txt). Mit --out landen die Berichte in einem Unterordner (z. B. out/boot-owner-live/).
#  Exit-Code 0 = Szenario lief durch (auch wenn Spiel-Bugs gefunden wurden), 2 = Harness-Absturz.
# =====================================================================
import argparse
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SP = "/tmp/claude-0/-home-user-website-test-demo-1/14caf8fd-3993-54cd-bb2d-9f5bab2d1eaf/scratchpad"
DEFAULT_LUAU = os.environ.get("LUAU", os.path.join(SP, "luau-build", "luau"))


def main():
    ap = argparse.ArgumentParser(description="AKYTEX Headless-Harness")
    ap.add_argument("scenario", nargs="?", default="boot")
    ap.add_argument("--client", type=int, default=1, help="Spieler mit Client-Kontext (1 = Besitzer, 2 = normal)")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--studio", action="store_true", help="RunService:IsStudio() = true")
    mode.add_argument("--live", action="store_true", help="RunService:IsStudio() = false (Standard)")
    ap.add_argument("--seconds", type=float, default=120)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--echo", action="store_true", help="Fehler/Ausgaben sofort zeigen")
    ap.add_argument("--no-streaming", action="store_true", help="Instanz-Streaming aus (Standard: wie Workspace.StreamingEnabled)")
    ap.add_argument("--no-bundle", action="store_true", help="out/bundle.luau nicht neu bauen")
    ap.add_argument("--out", default=None, help="Unterordner von out/ für die Berichte")
    ap.add_argument("--luau", default=DEFAULT_LUAU)
    ap.add_argument("--timeout", type=int, default=900)
    args = ap.parse_args()

    out_dir = os.path.join(HERE, "out")
    if args.out:
        out_dir = os.path.join(out_dir, args.out)
    os.makedirs(out_dir, exist_ok=True)

    if not args.no_bundle:
        subprocess.run([sys.executable, os.path.join(HERE, "bundle.py")], cwd=ROOT, check=True)

    cmd = [args.luau, "-O2", "tools/headless/run.luau", "-a", args.scenario, "--client", str(args.client),
           "--seconds", str(args.seconds), "--seed", str(args.seed)]
    cmd.append("--studio" if args.studio else "--live")
    if args.echo:
        cmd.append("--echo")
    if args.no_streaming:
        cmd.append("--no-streaming")
    t0 = time.time()
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=args.timeout)
    wall = time.time() - t0
    out = proc.stdout
    blocks = {}
    for m in re.finditer(r"@@BEGIN (.+?)@@\n(.*?)\n@@END \1@@", out, re.S):
        blocks[m.group(1)] = m.group(2)
    rest = re.sub(r"@@BEGIN (.+?)@@\n.*?\n@@END \1@@\n?", "", out, flags=re.S)
    for name, text in blocks.items():
        with open(os.path.join(out_dir, name), "w", encoding="utf-8") as f:
            f.write(text + "\n")
    if rest.strip() or proc.stderr.strip():
        with open(os.path.join(out_dir, "stdout_rest.txt"), "w", encoding="utf-8") as f:
            f.write(rest + ("\n--- stderr ---\n" + proc.stderr if proc.stderr.strip() else ""))
    rel = os.path.relpath(out_dir, ROOT)
    if "report.txt" in blocks:
        head = blocks["report.txt"].split("\n")
        # Zusammenfassung + Prüfungen ausgeben
        show = []
        for line in head:
            if line.startswith("(A) UNBEHANDELTE"):
                break
            show.append(line)
        print("\n".join(show[:60]))
    print("Berichte: %s/ (%s) · Laufzeit %.1f s · Exit %d" % (rel, ", ".join(sorted(blocks)), wall, proc.returncode))
    if proc.returncode != 0 or "harness_crash.txt" in blocks:
        if "harness_crash.txt" in blocks:
            print("HARNESS-ABSTURZ:\n" + blocks["harness_crash.txt"])
        if proc.stderr.strip():
            print(proc.stderr[-4000:])
        sys.exit(2)


if __name__ == "__main__":
    main()
