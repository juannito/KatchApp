#!/bin/bash
# Builds KatchApp.app (release) into dist/ and signs it ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG" --product KatchApp

BIN=".build/$CONFIG/KatchApp"
APP="dist/KatchApp.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/KatchApp"
cp Sources/KatchApp/Resources/Info.plist "$APP/Contents/Info.plist"
# SwiftPM resource bundles (FluidAudio ships one) are looked up in Contents/Resources.
for b in .build/"$CONFIG"/*.bundle; do
  [ -d "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done
# Dynamic frameworks (if any) go next to the binary.
for f in .build/"$CONFIG"/*.framework; do
  [ -d "$f" ] && cp -R "$f" "$APP/Contents/Frameworks/"
done
if [ -f scripts/AppIcon.icns ]; then
  cp scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi
# Sign with a real Apple Development identity when one exists: a stable identity keeps the
# macOS privacy grants (microphone, system audio, Documents) across rebuilds. Ad hoc otherwise.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')}"
if [ -n "$IDENTITY" ]; then
  echo "signing with: $IDENTITY"
  codesign --force --deep --options runtime --timestamp=none --entitlements scripts/KatchApp.entitlements --sign "$IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi
echo "OK -> $APP"
