#!/bin/zsh
# Builds Flaura.app, installs it to ~/Applications and (re)starts it.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh "$@"

DEST="$HOME/Applications"
mkdir -p "$DEST"

# Versions before the rename ran as "Aura"; the bundle id is the same for both.
running() { pgrep -x Flaura >/dev/null || pgrep -x Aura >/dev/null; }

if running; then
  echo "› stopping running Flaura"
  osascript -e 'tell application id "com.archigene.aura" to quit' >/dev/null 2>&1 || pkill -x Flaura || pkill -x Aura || true
  for _ in {1..20}; do running || break; sleep 0.2; done
  if running; then
    pkill -x Flaura || pkill -x Aura || true
    sleep 0.5
  fi
fi

rm -rf "$DEST/Flaura.app" "$DEST/Aura.app"
cp -R build/Flaura.app "$DEST/Flaura.app"
echo "› installed to $DEST/Flaura.app"

open "$DEST/Flaura.app"
echo "✓ Flaura is running — look for the flame in the menu bar"
