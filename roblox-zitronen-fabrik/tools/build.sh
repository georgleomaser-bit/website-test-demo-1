#!/usr/bin/env bash
# Baut build/ZitronenFabrikTycoon.rbxl aus den Quellen und testet alles.
# Benötigt: rojo (https://rojo.space) und lune (https://lune-org.github.io)
set -euo pipefail
cd "$(dirname "$0")/.."

ROJO="${ROJO:-rojo}"
LUNE="${LUNE:-lune}"
mkdir -p build

"$ROJO" build default.project.json -o build/_rojo.rbxlx
"$LUNE" run tests/shared.test.luau build/_rojo.rbxlx
"$LUNE" run tests/world.test.luau build/_rojo.rbxlx
"$LUNE" run tools/bake.luau build/_rojo.rbxlx build/ZitronenFabrikTycoon.rbxl
rm -f build/_rojo.rbxlx
echo "Fertig: build/ZitronenFabrikTycoon.rbxl"
