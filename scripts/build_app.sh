#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Lecture Copilot.app"
MACOS="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"
RESET_TCC=1

if [[ "${1:-}" == "--no-reset" ]]; then
    RESET_TCC=0
fi

cd "$ROOT"
echo "Building Lecture Copilot..."
swift build -c release

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$ROOT/.build/release/LectureCopilot" "$MACOS/Lecture Copilot"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/copy-icon-template.png" "$RESOURCES/copy-icon-template.png"
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
cp "$ROOT/Resources/StatusIcon.png" "$RESOURCES/StatusIcon.png"
cp "$ROOT/Resources/HUDIcon.png" "$RESOURCES/HUDIcon.png"
cp "$ROOT/Resources/AppIcon.png" "$RESOURCES/AppIcon.png"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

xattr -cr "$APP"
codesign --force --deep --sign - --identifier com.local.lecturecopilot "$APP"
touch "$APP"
"$LSREGISTER" -f "$APP" >/dev/null

echo "Built: $APP"

if [[ "$RESET_TCC" == "1" ]]; then
    echo "Ad-hoc signing changes TCC identity. Resetting Lecture Copilot permissions..."
    "$ROOT/scripts/reset_permissions.sh" "$APP"
fi
