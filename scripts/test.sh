#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/local_toolchain.sh"

if [[ "$#" -gt 1 ]]; then
  echo "usage: $0 [ADBuddyTests.TestClass[,ADBuddyTests.OtherTestClass]]" >&2
  exit 2
fi

TEST_RUNNER="$ADBUDDY_TEST_SUPPORT/Library/Xcode/Agents/xctest"
if [[ ! -x "$TEST_RUNNER" ]]; then
  echo "error: Install full Xcode to provide the XCTest runner and frameworks." >&2
  exit 1
fi

adbuddy_swift build --build-tests
BUILD_DIRECTORY="$(adbuddy_swift build --show-bin-path)"
shopt -s nullglob
TEST_BUNDLES=("$BUILD_DIRECTORY"/*.xctest)
if [[ "${#TEST_BUNDLES[@]}" != 1 ]]; then
  echo "error: Expected one XCTest bundle in $BUILD_DIRECTORY; found ${#TEST_BUNDLES[@]}." >&2
  exit 1
fi

# Invoke XCTest directly: SwiftPM's test discovery needs Xcode platform metadata
# that is absent when DEVELOPER_DIR points to Command Line Tools.
exec "$TEST_RUNNER" -XCTest "${1:-All}" "${TEST_BUNDLES[0]}"
