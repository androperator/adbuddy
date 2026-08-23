#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="ADBuddy"
BUNDLE_ID="com.clawperator.adbuddy"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
VERSION_FILE="$ROOT_DIR/VERSION"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
MCP_BINARY="$APP_MACOS/adbuddy-mcp"
INFO_PLIST="$APP_CONTENTS/Info.plist"
LOGCAT_ICON="$ROOT_DIR/Assets/AndroidStudio/Logcat@20x20.svg"

cd "$ROOT_DIR"

[[ -f "$VERSION_FILE" ]] || {
  echo "error: release version file is missing: $VERSION_FILE" >&2
  exit 1
}
[[ -f "$LOGCAT_ICON" ]] || {
  echo "error: Android Studio Logcat icon is missing: $LOGCAT_ICON" >&2
  exit 1
}
VERSION="$(<"$VERSION_FILE")"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_DIRECTORY="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_DIRECTORY/$APP_NAME"
BUILD_MCP_BINARY="$BUILD_DIRECTORY/adbuddy-mcp"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_CONTENTS/Resources"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$BUILD_MCP_BINARY" "$MCP_BINARY"
chmod +x "$MCP_BINARY"
cp "$LOGCAT_ICON" "$APP_CONTENTS/Resources/Logcat@20x20.svg"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © Action Launcher Pty Ltd</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --sign - "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
