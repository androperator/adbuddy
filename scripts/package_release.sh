#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ADBuddy"
BUNDLE_ID="com.clawperator.adbuddy"
MINIMUM_SYSTEM_VERSION="14.0"
DEFAULT_SIGNING_IDENTITY="Developer ID Application: Action Launcher Pty. Ltd (5ZE38CVDGY)"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
MCP_BINARY="$APP_MACOS/adbuddy-mcp"
INFO_PLIST="$APP_CONTENTS/Info.plist"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/package_release.sh [--skip-notarization]

Builds a universal, Developer ID-signed release archive. By default, the
archive is submitted to Apple's notary service using the Keychain profile named
by ADBUDDY_NOTARY_PROFILE, stapled, and verified. The release version is read
from the repository's VERSION file.

Environment variables:
  AD_BUDDY_SIGNING_IDENTITY  Developer ID identity to use for signing.
                            Defaults to the Action Launcher identity.
  ADBUDDY_NOTARY_PROFILE     Required unless --skip-notarization is supplied.
  AD_BUDDY_NOTARY_PROFILE    Deprecated alias for ADBUDDY_NOTARY_PROFILE.
USAGE
  exit 2
}

fail() {
  echo "error: $*" >&2
  exit 1
}

SKIP_NOTARIZATION=false

for argument in "$@"; do
  case "$argument" in
    --skip-notarization)
      SKIP_NOTARIZATION=true
      ;;
    --help|-h)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

VERSION_FILE="$ROOT_DIR/VERSION"
[[ -f "$VERSION_FILE" ]] || fail "release version file is missing: $VERSION_FILE"
VERSION="$(<"$VERSION_FILE")"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}([.-][0-9A-Za-z]+)*$ ]] || \
  fail "release version in $VERSION_FILE must look like 0.1.0"

SIGNING_IDENTITY="${AD_BUDDY_SIGNING_IDENTITY:-$DEFAULT_SIGNING_IDENTITY}"
NOTARY_PROFILE="${ADBUDDY_NOTARY_PROFILE:-${AD_BUDDY_NOTARY_PROFILE:-}}"

if [[ "$SKIP_NOTARIZATION" == false && -z "$NOTARY_PROFILE" ]]; then
  fail "set ADBUDDY_NOTARY_PROFILE or pass --skip-notarization for local signing validation"
fi

if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "$SIGNING_IDENTITY"; then
  fail "Developer ID signing identity is unavailable: $SIGNING_IDENTITY"
fi

cd "$ROOT_DIR"

swift build -c release --arch arm64
ARM64_BUILD_DIRECTORY="$(swift build -c release --arch arm64 --show-bin-path)"

swift build -c release --arch x86_64
X86_64_BUILD_DIRECTORY="$(swift build -c release --arch x86_64 --show-bin-path)"

ARM64_APP_BINARY="$ARM64_BUILD_DIRECTORY/$APP_NAME"
X86_64_APP_BINARY="$X86_64_BUILD_DIRECTORY/$APP_NAME"
ARM64_MCP_BINARY="$ARM64_BUILD_DIRECTORY/adbuddy-mcp"
X86_64_MCP_BINARY="$X86_64_BUILD_DIRECTORY/adbuddy-mcp"

for binary in \
  "$ARM64_APP_BINARY" \
  "$X86_64_APP_BINARY" \
  "$ARM64_MCP_BINARY" \
  "$X86_64_MCP_BINARY"; do
  [[ -x "$binary" ]] || fail "expected release binary is missing: $binary"
done

ARCHIVE_NAME="$APP_NAME-macos-universal-$VERSION.zip"
ARCHIVE_PATH="$RELEASE_DIR/$ARCHIVE_NAME"

rm -rf "$APP_BUNDLE"
rm -f "$ARCHIVE_PATH"
mkdir -p "$APP_MACOS"

/usr/bin/lipo -create "$ARM64_APP_BINARY" "$X86_64_APP_BINARY" -output "$APP_BINARY"
/usr/bin/lipo -create "$ARM64_MCP_BINARY" "$X86_64_MCP_BINARY" -output "$MCP_BINARY"

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
  <string>$MINIMUM_SYSTEM_VERSION</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Android Package Archive</string>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>com.clawperator.adbuddy.android-package-archive</string>
      </array>
    </dict>
  </array>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>com.clawperator.adbuddy.android-package-archive</string>
      <key>UTTypeDescription</key>
      <string>Android Package Archive</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <array>
          <string>apk</string>
        </array>
        <key>public.mime-type</key>
        <string>application/vnd.android.package-archive</string>
      </dict>
    </dict>
  </array>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$MCP_BINARY"
/usr/bin/codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"

/usr/bin/lipo -archs "$APP_BINARY" | /usr/bin/grep -Eq '(^| )arm64( |$)'
/usr/bin/lipo -archs "$APP_BINARY" | /usr/bin/grep -Eq '(^| )x86_64( |$)'
/usr/bin/lipo -archs "$MCP_BINARY" | /usr/bin/grep -Eq '(^| )arm64( |$)'
/usr/bin/lipo -archs "$MCP_BINARY" | /usr/bin/grep -Eq '(^| )x86_64( |$)'
/usr/bin/codesign --verify --deep --strict --verbose "$APP_BUNDLE"

/usr/bin/ditto -c -k --keepParent --norsrc "$APP_BUNDLE" "$ARCHIVE_PATH"

if [[ "$SKIP_NOTARIZATION" == true ]]; then
  echo "Created signed but unnotarized archive: $ARCHIVE_PATH"
  echo "Do not distribute this archive publicly."
  exit 0
fi

xcrun notarytool submit "$ARCHIVE_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

rm -f "$ARCHIVE_PATH"
/usr/bin/ditto -c -k --keepParent --norsrc "$APP_BUNDLE" "$ARCHIVE_PATH"
/usr/bin/codesign --verify --deep --strict --verbose "$APP_BUNDLE"
spctl --assess --type execute --verbose "$APP_BUNDLE"

echo "Created signed and notarized release archive: $ARCHIVE_PATH"
shasum -a 256 "$ARCHIVE_PATH"
