#!/usr/bin/env bash
# =====================================================================
#  AKYTEX TYCOON – alle statischen Prüfungen + Build (DESIGN.md §C1.1; Besitzer WP1)
#  Aufruf im Projektordner:  bash scripts/check.sh      -> endet mit "ALLE PRÜFUNGEN OK"
#  Build-Ziel änderbar (z. B. Scratchpad statt Projektordner):  AT_BUILD_OUT=/pfad/test.rbxlx bash scripts/check.sh
#  Nie in roblox-shooter, roblox-meteor-heist oder der Website bauen oder Dateien ändern.
# =====================================================================
set -euo pipefail
SP=/tmp/claude-0/-home-user-website-test-demo-1/14caf8fd-3993-54cd-bb2d-9f5bab2d1eaf/scratchpad
OUT="${AT_BUILD_OUT:-AkytexTycoon.rbxlx}"
cd "$(dirname "$0")/.."

stylua --check src tests
selene src
rojo sourcemap default.project.json -o sourcemap.json
/tmp/luau-lsp/build/luau-lsp analyze --platform=roblox --definitions="$SP/globalTypes.d.luau" --sourcemap=sourcemap.json src
rojo build default.project.json -o "$OUT"
for t in tests/*.test.luau; do
	[ -e "$t" ] || continue
	"$SP/luau-build/luau" "$t" || exit 1
done
python3 scripts/contract_check.py .
# Ökonomie-Gate G1 (WP6): teuerster Einzelpreis < 1e14, nie ≥ 9e15
SIM_OUT="$(python3 tools/economy_sim.py --quick)"
echo "$SIM_OUT"
echo "$SIM_OUT" | grep -Eq '^G1 .*OK$' || { echo "economy_sim: G1 meldet nicht OK"; exit 1; }
echo "ALLE PRÜFUNGEN OK"
