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
xattr -cr "$APP"
codesign --force --deep --sign - --identifier com.local.lecturecopilot "$APP"

echo "Built: $APP"

if [[ "$RESET_TCC" == "1" ]]; then
    echo "Ad-hoc signing changes TCC identity. Resetting Lecture Copilot permissions..."
    "$ROOT/scripts/reset_permissions.sh" "$APP"
fi
