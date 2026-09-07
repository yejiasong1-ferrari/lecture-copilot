#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_APP="/Applications/Lecture Copilot.app"
BUNDLE_ID="com.local.lecturecopilot"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
bold() { printf '\033[1m%s\033[0m\n' "$*"; }

echo
bold "Lecture Copilot installer"
echo "This builds a local Mac app and copies it to /Applications."
echo

if [[ "$(uname -s)" != "Darwin" ]]; then
    red "This app only runs on macOS."
    exit 1
fi

os_major="$(sw_vers -productVersion | cut -d. -f1)"
if [[ "$os_major" -lt 14 ]]; then
    red "Need macOS 14 or later. This Mac is $(sw_vers -productVersion)."
    exit 1
fi

if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
    echo "Xcode Command Line Tools are missing."
    echo "A system window should appear. Click Install, wait until it finishes,"
    echo "then run this command again:"
    echo
    echo "  $ROOT/scripts/install.sh"
    echo
    xcode-select --install >/dev/null 2>&1 || true
    exit 1
fi

if [[ ! -d "/Applications/Doubao.app" && ! -d "/Applications/豆包.app" ]]; then
    echo "Note: Doubao / 豆包 was not found in /Applications."
    echo "Install the Doubao Mac app before using Lecture Copilot."
    echo
fi

"$ROOT/scripts/build_app.sh" --no-reset

echo "Installing to $INSTALL_APP"
rm -rf "$INSTALL_APP"
ditto "$ROOT/dist/Lecture Copilot.app" "$INSTALL_APP"
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$INSTALL_APP"

"$ROOT/scripts/reset_permissions.sh" "$INSTALL_APP"

echo
green "Install finished."
echo
bold "Next (required):"
echo "1. Do not open the app yet."
echo "2. System Settings should already be open."
echo "3. Screen Recording: click +, press Command-Shift-G, paste, turn the switch ON."
echo "4. Accessibility: do the same."
echo "5. After both switches are blue, tell the person who sent you this, or run:"
echo
echo "   open \"$INSTALL_APP\""
echo
echo "The first Doubao send may ask to control System Events. Click Allow."
echo
