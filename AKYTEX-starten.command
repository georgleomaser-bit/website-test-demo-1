#!/bin/bash
# AKYTEX öffentlich starten (Mac/Linux): Doppelklick oder ./AKYTEX-starten.command
cd "$(dirname "$0")" || exit 1
if ! command -v node >/dev/null 2>&1; then
  echo ""
  echo "  Node.js fehlt noch. Bitte die LTS-Version von https://nodejs.org installieren"
  echo "  und danach diese Datei erneut doppelklicken."
  open "https://nodejs.org" 2>/dev/null || xdg-open "https://nodejs.org" 2>/dev/null
  read -r -p "Enter zum Schließen …"
  exit 1
fi
node server/start-public.mjs
