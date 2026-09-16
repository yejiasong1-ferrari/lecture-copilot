#!/usr/bin/env bash
set -euo pipefail

TARGET_APP="${1:-/Applications/Lecture Copilot.app}"
LAUNCHER="$HOME/Desktop/Lecture Copilot.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$TARGET_APP" ]]; then
    echo "Lecture Copilot was not found at: $TARGET_APP" >&2
    exit 1
fi

if [[ -L "$LAUNCHER" || -d "$LAUNCHER" ]]; then
    rm -rf "$LAUNCHER"
fi

mkdir -p "$LAUNCHER/Contents/MacOS" "$LAUNCHER/Contents/Resources"
cat > "$LAUNCHER/Contents/MacOS/Lecture Copilot" <<EOF
#!/bin/bash
open "$TARGET_APP"
EOF
chmod +x "$LAUNCHER/Contents/MacOS/Lecture Copilot"

cat > "$LAUNCHER/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>Lecture Copilot</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.local.lecturecopilot.launcher</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Lecture Copilot</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
EOF

cp "$TARGET_APP/Contents/Resources/AppIcon.icns" "$LAUNCHER/Contents/Resources/AppIcon.icns"
xattr -cr "$LAUNCHER"
codesign --force --deep --sign - --identifier com.local.lecturecopilot.launcher "$LAUNCHER" >/dev/null
touch "$LAUNCHER"
"$LSREGISTER" -f "$LAUNCHER" >/dev/null
echo "Desktop shortcut created: $LAUNCHER"
