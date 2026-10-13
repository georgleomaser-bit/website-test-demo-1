#!/usr/bin/env bash
# Alle statischen Prüfungen + Build (im Projektordner ausführen)
set -e
SP=/tmp/claude-0/-home-user-website-test-demo-1/14caf8fd-3993-54cd-bb2d-9f5bab2d1eaf/scratchpad
cd "$(dirname "$0")/.."
stylua --check src tests
selene src
rojo sourcemap default.project.json -o sourcemap.json
/tmp/luau-lsp/build/luau-lsp analyze --platform=roblox --definitions=$SP/globalTypes.d.luau --sourcemap=sourcemap.json src
rojo build default.project.json -o AkytexTycoon.rbxlx
for t in tests/*.test.luau; do [ -e "$t" ] || continue; $SP/luau-build/luau "$t" || exit 1; done
echo "ALLE PRÜFUNGEN OK"
