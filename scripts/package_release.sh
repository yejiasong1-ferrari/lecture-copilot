#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
ASSET="$ROOT/dist/Lecture-Copilot-macOS-Apple-Silicon.zip"
CHECKSUM="$ASSET.sha256"

"$ROOT/scripts/build_app.sh" --no-reset

rm -f "$ASSET" "$CHECKSUM"
ditto -c -k --sequesterRsrc --keepParent "$ROOT/dist/Lecture Copilot.app" "$ASSET"
(
    cd "$ROOT/dist"
    shasum -a 256 "$(basename "$ASSET")" > "$(basename "$CHECKSUM")"
)

codesign --verify --deep --strict "$ROOT/dist/Lecture Copilot.app"
echo "Packaged Lecture Copilot v$VERSION:"
echo "$ASSET"
echo "$CHECKSUM"
