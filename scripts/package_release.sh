#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ADBuddy"
BUNDLE_ID="com.clawperator.adbuddy"
MINIMUM_SYSTEM_VERSION="14.0"
DEFAULT_SIGNING_IDENTITY="Developer ID Application: Action Launcher Pty. Ltd (5ZE38CVDGY)"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/release"
ANDROID_STUDIO_ASSETS="$ROOT_DIR/Assets/AndroidStudio"
APP_ICON="$ROOT_DIR/Assets/AppIcon.icns"
MENU_BAR_GLYPH="$ROOT_DIR/Assets/ADBuddyMenuBarGlyph.svg"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/package_release.sh [--skip-notarization | --local]

Builds Apple Silicon, Intel, and universal Developer ID-signed app archives.
By default, each archive is submitted to Apple's notary service using the
Keychain profile named by ADBUDDY_NOTARY_PROFILE, stapled, and verified. The release version is read
from the repository's VERSION file. A separate recording-source ZIP is also
created. Use --local for an ad-hoc signed build without notarization.

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
LOCAL_BUILD=false

for argument in "$@"; do
  case "$argument" in
    --skip-notarization)
      SKIP_NOTARIZATION=true
      ;;
    --local)
      LOCAL_BUILD=true
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
[[ -d "$ANDROID_STUDIO_ASSETS" ]] || fail "Android Studio assets directory is missing: $ANDROID_STUDIO_ASSETS"
[[ -f "$APP_ICON" ]] || fail "app icon is missing: $APP_ICON"
[[ -f "$MENU_BAR_GLYPH" ]] || fail "menu bar glyph is missing: $MENU_BAR_GLYPH"
VERSION="$(<"$VERSION_FILE")"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}([.-][0-9A-Za-z]+)*$ ]] || \
  fail "release version in $VERSION_FILE must look like 0.2.1"

SIGNING_IDENTITY="${AD_BUDDY_SIGNING_IDENTITY:-$DEFAULT_SIGNING_IDENTITY}"
NOTARY_PROFILE="${ADBUDDY_NOTARY_PROFILE:-${AD_BUDDY_NOTARY_PROFILE:-}}"

if [[ "$SKIP_NOTARIZATION" == false && -z "$NOTARY_PROFILE" ]]; then
  fail "set ADBUDDY_NOTARY_PROFILE or pass --skip-notarization for local signing validation"
fi

if [[ "$LOCAL_BUILD" == true ]]; then
  SIGNING_IDENTITY="-"
  TIMESTAMP_OPTION="--timestamp=none"
else
  TIMESTAMP_OPTION="--timestamp"
fi

if [[ "$LOCAL_BUILD" == false ]] && ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "$SIGNING_IDENTITY"; then
  fail "Developer ID signing identity is unavailable: $SIGNING_IDENTITY"
fi

cd "$ROOT_DIR"

ARM64_SCRATCH_DIRECTORY="$ROOT_DIR/.build/release-arm64"
X86_64_SCRATCH_DIRECTORY="$ROOT_DIR/.build/release-x86_64"
# Swift Build can share output paths across architectures within one scratch directory.
swift build -c release --arch arm64 --scratch-path "$ARM64_SCRATCH_DIRECTORY"
ARM64_BUILD_DIRECTORY="$(swift build -c release --arch arm64 --scratch-path "$ARM64_SCRATCH_DIRECTORY" --show-bin-path)"

swift build -c release --arch x86_64 --scratch-path "$X86_64_SCRATCH_DIRECTORY"
X86_64_BUILD_DIRECTORY="$(swift build -c release --arch x86_64 --scratch-path "$X86_64_SCRATCH_DIRECTORY" --show-bin-path)"

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

SOURCES_NAME="$APP_NAME-recording-sources-$VERSION"
SOURCES_DIRECTORY="$RELEASE_DIR/$SOURCES_NAME"
SOURCES_ARCHIVE="$RELEASE_DIR/$SOURCES_NAME.zip"
rm -rf "$SOURCES_DIRECTORY"
rm -f "$SOURCES_ARCHIVE"
"$ROOT_DIR/scripts/prepare_recording_sources.sh" "$SOURCES_DIRECTORY"
/usr/bin/ditto -c -k --keepParent --norsrc "$SOURCES_DIRECTORY" "$SOURCES_ARCHIVE"
echo "Created recording source archive: $SOURCES_ARCHIVE"

# Each app contains only the executable slices and recorder resources it needs.
for variant in arm64 x86_64 universal; do
  APP_BUNDLE="$RELEASE_DIR/$variant/$APP_NAME.app"
  APP_CONTENTS="$APP_BUNDLE/Contents"
  APP_MACOS="$APP_CONTENTS/MacOS"
  APP_BINARY="$APP_MACOS/$APP_NAME"
  MCP_BINARY="$APP_MACOS/adbuddy-mcp"
  INFO_PLIST="$APP_CONTENTS/Info.plist"
  ARCHIVE_PATH="$RELEASE_DIR/$APP_NAME-macos-$variant-$VERSION.zip"
  case "$variant" in
    arm64) ARCHITECTURES=(arm64); BUILD_DIRECTORY="$ARM64_BUILD_DIRECTORY" ;;
    x86_64) ARCHITECTURES=(x86_64); BUILD_DIRECTORY="$X86_64_BUILD_DIRECTORY" ;;
    universal) ARCHITECTURES=(arm64 x86_64) ;;
  esac

  rm -rf "$APP_BUNDLE"
  rm -f "$ARCHIVE_PATH"
  mkdir -p "$APP_MACOS" "$APP_CONTENTS/Resources"

  if [[ "$variant" == universal ]]; then
    /usr/bin/lipo -create "$ARM64_APP_BINARY" "$X86_64_APP_BINARY" -output "$APP_BINARY"
    /usr/bin/lipo -create "$ARM64_MCP_BINARY" "$X86_64_MCP_BINARY" -output "$MCP_BINARY"
  else
    cp "$BUILD_DIRECTORY/$APP_NAME" "$APP_BINARY"
    cp "$BUILD_DIRECTORY/adbuddy-mcp" "$MCP_BINARY"
  fi
  cp -R "$ANDROID_STUDIO_ASSETS"/. "$APP_CONTENTS/Resources/"
  cp "$APP_ICON" "$APP_CONTENTS/Resources/AppIcon.icns"
  cp "$MENU_BAR_GLYPH" "$APP_CONTENTS/Resources/ADBuddyMenuBarGlyph.svg"

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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
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

  "$ROOT_DIR/scripts/prepare_recording_backend.sh" "$APP_CONTENTS" "$variant"
  LICENSES_DIRECTORY="$APP_CONTENTS/Resources/Recording/Licenses"
  mkdir -p "$LICENSES_DIRECTORY"
  tar -xOf "$SOURCES_DIRECTORY/scrcpy-4.1.tar.gz" scrcpy-4.1/LICENSE > "$LICENSES_DIRECTORY/scrcpy.txt"
  tar -xOf "$SOURCES_DIRECTORY/SDL-3.4.12.tar.gz" SDL-release-3.4.12/LICENSE.txt > "$LICENSES_DIRECTORY/SDL.txt"
  for license in COPYING.LGPLv2.1 COPYING.LGPLv3 LICENSE.md; do
    tar -xOf "$SOURCES_DIRECTORY/ffmpeg-8.1.2.tar.xz" "ffmpeg-8.1.2/$license" > "$LICENSES_DIRECTORY/FFmpeg-$license"
  done
  cat > "$APP_CONTENTS/Resources/Recording/Sources.txt" <<SOURCES
Matching recording sources and rebuild instructions for ADBuddy $VERSION:
https://github.com/clawperator/adbuddy/releases/download/v$VERSION/$SOURCES_NAME.zip

The source archive is distributed alongside the app ZIP on the same release.
See README.md and Licenses/ in this directory for notices and license texts.
SOURCES
  for architecture in "${ARCHITECTURES[@]}"; do
    /usr/bin/codesign --force --options runtime "$TIMESTAMP_OPTION" --sign "$SIGNING_IDENTITY" \
      "$APP_MACOS/scrcpy-$architecture"
  done
  /usr/bin/codesign --force --options runtime "$TIMESTAMP_OPTION" --sign "$SIGNING_IDENTITY" "$MCP_BINARY"
  /usr/bin/codesign --force --options runtime "$TIMESTAMP_OPTION" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"

  for binary in "$APP_BINARY" "$MCP_BINARY"; do
    actual_architectures="$(/usr/bin/lipo -archs "$binary" | tr ' ' '\n' | sort)"
    expected_architectures="$(printf '%s\n' "${ARCHITECTURES[@]}" | sort)"
    [[ "$actual_architectures" == "$expected_architectures" ]] || fail "unexpected architectures in $binary"
  done
  /usr/bin/codesign --verify --deep --strict --verbose "$APP_BUNDLE"

  /usr/bin/ditto -c -k --keepParent --norsrc "$APP_BUNDLE" "$ARCHIVE_PATH"

  if [[ "$SKIP_NOTARIZATION" == true ]]; then
    echo "Created signed but unnotarized archive: $ARCHIVE_PATH"
    echo "Do not distribute this archive publicly."
    continue
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
done
shasum -a 256 "$SOURCES_ARCHIVE"
