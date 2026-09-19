#!/usr/bin/env bash
# Shared by the local build and test entrypoints. Release builds use Xcode directly.

ADBUDDY_SELECTED_DEVELOPER_DIR="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
ADBUDDY_SWIFT_FLAGS=()

if ADBUDDY_SWIFT="$(/usr/bin/xcrun --find swift 2>/dev/null)" &&
   ADBUDDY_PLATFORM_DIR="$(/usr/bin/xcrun --sdk macosx --show-sdk-platform-path 2>/dev/null)"; then
  ADBUDDY_TEST_SUPPORT="$ADBUDDY_PLATFORM_DIR/Developer"
else
  # The separately installed command-line tools remain usable while Xcode setup
  # is incomplete. Their macOS 27 SDK currently lacks the SwiftUI State macro.
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
  ADBUDDY_SWIFT="$DEVELOPER_DIR/usr/bin/swift"
  ADBUDDY_LOCAL_SDK="$DEVELOPER_DIR/SDKs/MacOSX26.5.sdk"
  if [[ ! -x "$ADBUDDY_SWIFT" || ! -d "$ADBUDDY_LOCAL_SDK" ]]; then
    echo "error: Complete Xcode setup, or install Command Line Tools with the macOS 26.5 SDK for local builds." >&2
    return 1
  fi
  echo "Using Command Line Tools with macOS 26.5 for this local build (Xcode setup is unavailable)." >&2
  ADBUDDY_SWIFT_FLAGS=(--sdk "$ADBUDDY_LOCAL_SDK")

  if [[ "$ADBUDDY_SELECTED_DEVELOPER_DIR" == */CommandLineTools ]]; then
    ADBUDDY_SELECTED_DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
  ADBUDDY_TEST_SUPPORT="$ADBUDDY_SELECTED_DEVELOPER_DIR/Platforms/MacOSX.platform/Developer"
  if [[ -d "$ADBUDDY_TEST_SUPPORT/Library/Frameworks/XCTest.framework" ]]; then
    ADBUDDY_SWIFT_FLAGS+=(
      -Xswiftc -F -Xswiftc "$ADBUDDY_TEST_SUPPORT/Library/Frameworks"
      -Xswiftc -I -Xswiftc "$ADBUDDY_TEST_SUPPORT/usr/lib"
      -Xlinker -L -Xlinker "$ADBUDDY_TEST_SUPPORT/usr/lib"
      -Xlinker -rpath -Xlinker "$ADBUDDY_TEST_SUPPORT/Library/Frameworks"
      -Xlinker -rpath -Xlinker "$ADBUDDY_TEST_SUPPORT/usr/lib"
    )
  fi
fi

adbuddy_swift() {
  local subcommand="$1"
  shift
  "$ADBUDDY_SWIFT" "$subcommand" ${ADBUDDY_SWIFT_FLAGS[@]+"${ADBUDDY_SWIFT_FLAGS[@]}"} "$@"
}
