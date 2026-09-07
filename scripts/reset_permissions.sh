#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="com.local.lecturecopilot"
APP="${1:-$ROOT/dist/Lecture Copilot.app}"

pkill -f "$APP/Contents/MacOS/Lecture Copilot" 2>/dev/null || true
sleep 0.3

tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
tccutil reset AppleEvents "$BUNDLE_ID" >/dev/null 2>&1 || true

printf '%s' "$APP" | pbcopy

open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" >/dev/null 2>&1 || true
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" >/dev/null 2>&1 || true

cat <<EOF
TCC reset for $BUNDLE_ID.
App path copied to clipboard:

$APP

Add it in:
1. 屏幕录制与系统音频录制 → + → Command+Shift+G → paste → turn ON
2. 辅助功能 → + → Command+Shift+G → paste → turn ON

Do not open the app until both switches are blue.
EOF
