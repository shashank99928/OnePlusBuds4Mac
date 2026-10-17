#!/bin/bash
# Builds OnePlus Buds 4.app. Compiles with the Command Line Tools; an installed Xcode.app is
# needed only for its SwiftUI macro plugin (see Package.swift). Xcode need not be selected
# with xcode-select.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG=${1:-release}
APP="OnePlus Buds 4.app"

# The SwiftUI macro plugin is located in Package.swift so the editor works too.
swift build -c "$CONFIG"
BINARY=$(swift build -c "$CONFIG" --show-bin-path)/OnePlusBuds4

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/OnePlusBuds4"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Optional: the bundle works without an icon, it just looks unfinished. Regenerate with
# `swift Tools/make-icon.swift` if this is missing.
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
    echo "warning: Resources/AppIcon.icns missing — run: swift Tools/make-icon.swift" >&2
fi

# Ad-hoc signature. The bundle identifier stays fixed across rebuilds so the granted
# Bluetooth permission survives; re-signing may still re-prompt once.
codesign --force --sign - "$APP"

echo "built $APP"
echo "run:  open \"$APP\"     (or: \"./$APP/Contents/MacOS/OnePlusBuds4\"  to see stderr)"
