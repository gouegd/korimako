#!/usr/bin/env bash
# Build the SwiftPM executable and assemble a proper, ad-hoc-signed .app bundle.
# No Xcode required — Command Line Tools are enough.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CONFIG="${1:-release}"
APP="$ROOT/sound-keko.app"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/sound-keko"

echo "==> assembling sound-keko.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/sound-keko"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> ad-hoc signing"
codesign --force --sign - "$APP"

echo "==> done: $APP"
echo "    run:     open \"$APP\""
echo "    install: cp -R \"$APP\" /Applications/"
