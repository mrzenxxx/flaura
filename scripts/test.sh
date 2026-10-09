#!/bin/zsh
# Runs the test suite with Swift Testing from the Command Line Tools (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")/.."

FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIBS=/Library/Developer/CommandLineTools/Library/Developer/usr/lib

if [[ -d "$FRAMEWORKS/Testing.framework" ]]; then
  exec swift test \
    -Xswiftc -F"$FRAMEWORKS" \
    -Xlinker -F"$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$LIBS" \
    "$@"
else
  exec swift test "$@"
fi
