#!/usr/bin/env bash
set -euo pipefail

RELEASE_URL="${LECTURE_COPILOT_RELEASE_URL:-https://github.com/yejiasong1-ferrari/lecture-copilot/releases/latest/download/Lecture-Copilot-macOS-Apple-Silicon.zip}"
CHECKSUM_URL="${LECTURE_COPILOT_CHECKSUM_URL:-${RELEASE_URL}.sha256}"
INSTALL_APP="${LECTURE_COPILOT_INSTALL_APP:-/Applications/Lecture Copilot.app}"
BUNDLE_ID="com.local.lecturecopilot"
CREATE_DESKTOP="${LECTURE_COPILOT_CREATE_DESKTOP:-1}"
RESET_PERMISSIONS="${LECTURE_COPILOT_RESET_PERMISSIONS:-1}"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
bold() { printf '\033[1m%s\033[0m\n' "$*"; }

echo
bold "Lecture Copilot installer"
echo "Downloads the latest release and installs it in Applications."
echo

if [[ "$(uname -s)" != "Darwin" ]]; then
    red "Lecture Copilot only runs on macOS."
    exit 1
fi

os_major="$(sw_vers -productVersion | cut -d. -f1)"
if [[ "$os_major" -lt 14 ]]; then
    red "Need macOS 14 or later. This Mac is $(sw_vers -productVersion)."
    exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
    red "The downloadable build currently supports Apple Silicon (M1 or newer)."
    echo "Intel Mac users can build from source:"
    echo "https://github.com/yejiasong1-ferrari/lecture-copilot#从源码安装"
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    red "curl is required but was not found."
    exit 1
fi

TEMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TEMP_DIR"; }
trap cleanup EXIT
ZIP_PATH="$TEMP_DIR/Lecture-Copilot.zip"
CHECKSUM_PATH="$TEMP_DIR/Lecture-Copilot.zip.sha256"
UNPACK_DIR="$TEMP_DIR/unpacked"
BACKUP_APP="$TEMP_DIR/Lecture Copilot.previous.app"

echo "Downloading the latest release..."
curl --fail --location --progress-bar "$RELEASE_URL" --output "$ZIP_PATH"
curl --fail --location --silent --show-error "$CHECKSUM_URL" --output "$CHECKSUM_PATH"
(
    cd "$TEMP_DIR"
    expected="$(awk '{print $1}' "$(basename "$CHECKSUM_PATH")")"
    actual="$(shasum -a 256 "$(basename "$ZIP_PATH")" | awk '{print $1}')"
    if [[ -z "$expected" || "$actual" != "$expected" ]]; then
        red "The downloaded package failed SHA-256 verification. Installation stopped."
        exit 1
    fi
)
mkdir -p "$UNPACK_DIR"
ditto -x -k "$ZIP_PATH" "$UNPACK_DIR"

SOURCE_APP="$UNPACK_DIR/Lecture Copilot.app"
if [[ ! -d "$SOURCE_APP" ]]; then
    red "The downloaded package did not contain Lecture Copilot.app."
    exit 1
fi

if ! codesign --verify --deep --strict "$SOURCE_APP" >/dev/null 2>&1; then
    red "The downloaded app failed signature verification. Installation stopped."
    exit 1
fi

pkill -f "$INSTALL_APP/Contents/MacOS/Lecture Copilot" 2>/dev/null || true
if [[ -d "$INSTALL_APP" ]]; then
    mv "$INSTALL_APP" "$BACKUP_APP"
fi

if ! ditto "$SOURCE_APP" "$INSTALL_APP"; then
    red "Could not install into /Applications."
    if [[ -d "$BACKUP_APP" ]]; then
        mv "$BACKUP_APP" "$INSTALL_APP"
        echo "The previous version was restored."
    fi
    exit 1
fi

xattr -cr "$INSTALL_APP"
codesign --verify --deep --strict "$INSTALL_APP"

if [[ "$CREATE_DESKTOP" == "1" ]]; then
    LAUNCHER="$HOME/Desktop/Lecture Copilot.app"
    if [[ -L "$LAUNCHER" || -d "$LAUNCHER" ]]; then
        rm -rf "$LAUNCHER"
    fi
    mkdir -p "$LAUNCHER/Contents/MacOS" "$LAUNCHER/Contents/Resources"
    cat > "$LAUNCHER/Contents/MacOS/Lecture Copilot" <<EOF
#!/bin/bash
open "$INSTALL_APP"
EOF
    chmod +x "$LAUNCHER/Contents/MacOS/Lecture Copilot"
    cat > "$LAUNCHER/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Lecture Copilot</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>com.local.lecturecopilot.launcher</string>
<key>CFBundleName</key><string>Lecture Copilot</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
EOF
    cp "$INSTALL_APP/Contents/Resources/AppIcon.icns" "$LAUNCHER/Contents/Resources/AppIcon.icns"
    xattr -cr "$LAUNCHER"
    codesign --force --deep --sign - --identifier com.local.lecturecopilot.launcher "$LAUNCHER" >/dev/null
fi

if [[ "$RESET_PERMISSIONS" == "1" ]]; then
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
    tccutil reset AppleEvents "$BUNDLE_ID" >/dev/null 2>&1 || true
    printf '%s' "$INSTALL_APP" | pbcopy

    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" >/dev/null 2>&1 || true
    sleep 1
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" >/dev/null 2>&1 || true
fi

echo
green "Lecture Copilot is installed."
echo
if [[ "$RESET_PERMISSIONS" == "1" ]]; then
    bold "Finish these two permission steps before opening it:"
    echo "1. Screen Recording: click +, press Command-Shift-G, paste, add the app, turn it ON."
    echo "2. Accessibility: repeat the same steps and turn it ON."
    echo "3. Open Lecture Copilot from the desktop or Applications after both are ON."
    echo
    echo "The app path is already in your clipboard:"
    echo "$INSTALL_APP"
fi
