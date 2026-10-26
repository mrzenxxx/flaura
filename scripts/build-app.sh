#!/bin/zsh
# Builds build/Flaura.app from the SwiftPM package (no Xcode needed).
#   scripts/build-app.sh            release build, stable local signature
#   scripts/build-app.sh --adhoc    ad-hoc signature
set -euo pipefail
cd "$(dirname "$0")/.."

echo "› swift build (release)"
swift build -c release --product Flaura
BIN="$(swift build -c release --show-bin-path)"

APP=build/Flaura.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Flaura" "$APP/Contents/MacOS/Flaura"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [[ ! -f build/AppIcon.icns || scripts/make-icon.swift -nt build/AppIcon.icns ]]; then
  echo "› icon"
  swift scripts/make-icon.swift build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="$(scripts/signing-identity.sh "${1:-}")"
echo "› codesign (${IDENTITY/#-/ad-hoc})"
codesign --force --sign "$IDENTITY" --identifier com.archigene.aura "$APP"
codesign --verify "$APP" 2>/dev/null || true

echo "✓ $APP"
