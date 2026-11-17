#!/bin/bash
# Builds and bundles SoundBar.app (a bundle is required for the audio-capture permission).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/SoundBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/SoundBar" "$APP/Contents/MacOS/SoundBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP  (run: open $APP)"
