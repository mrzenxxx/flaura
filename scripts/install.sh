#!/bin/zsh
# Builds Aura.app, installs it to ~/Applications and (re)starts it.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh "$@"

DEST="$HOME/Applications"
mkdir -p "$DEST"

if pgrep -x Aura >/dev/null; then
  echo "› stopping running Aura"
  osascript -e 'tell application id "com.archigene.aura" to quit' >/dev/null 2>&1 || pkill -x Aura || true
  for _ in {1..20}; do pgrep -x Aura >/dev/null || break; sleep 0.2; done
  if pgrep -x Aura >/dev/null; then
    pkill -x Aura || true
    sleep 0.5
  fi
fi

rm -rf "$DEST/Aura.app"
cp -R build/Aura.app "$DEST/Aura.app"
echo "› installed to $DEST/Aura.app"

open "$DEST/Aura.app"
echo "✓ Aura is running — look for the flame in the menu bar"
