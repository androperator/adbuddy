#!/usr/bin/env bash
# Ship matching sources and licenses for the statically linked recording helper.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${1:?usage: prepare_recording_sources.sh destination}"
CACHE="$ROOT_DIR/.build/recording-backend/sources"
mkdir -p "$CACHE" "$DESTINATION"

copy_source() {
  local name="$1" checksum="$2" url="$3"
  if [[ ! -f "$CACHE/$name" ]]; then
    curl --fail --location --silent --show-error "$url" --output "$CACHE/$name.download"
    mv "$CACHE/$name.download" "$CACHE/$name"
  fi
  if [[ "$(shasum -a 256 "$CACHE/$name" | cut -d ' ' -f 1)" != "$checksum" ]]; then
    echo "Recording source checksum mismatch: $name" >&2
    exit 1
  fi
  cp "$CACHE/$name" "$DESTINATION/$name"
}

# Versions and dependency checksums match scrcpy v4.1's app/deps/*.sh.
copy_source scrcpy-4.1.tar.gz \
  537b2ade623cb94b6edddfa5c61bf0b0af21484aa8365ea2531b686ea573249a \
  https://github.com/Genymobile/scrcpy/archive/refs/tags/v4.1.tar.gz
copy_source ffmpeg-8.1.2.tar.xz \
  464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c \
  https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz
copy_source SDL-3.4.12.tar.gz \
  b68381f06a7580e63400b3b6eb547ec57d8c3ebde70f9f40e0aba530ba05da27 \
  https://github.com/libsdl-org/SDL/archive/refs/tags/release-3.4.12.tar.gz
copy_source dav1d-1.5.3.tar.gz \
  cbe212b02faf8c6eed5b6d55ef8a6e363aaab83f15112e960701a9c3df813686 \
  https://code.videolan.org/videolan/dav1d/-/archive/1.5.3/dav1d-1.5.3.tar.gz
copy_source libusb-1.0.30.tar.gz \
  2ae28adb0bb9558c86135c4e1c11b320b0805461e207a64a6e520a114094bf07 \
  https://github.com/libusb/libusb/archive/refs/tags/v1.0.30.tar.gz
cp "$ROOT_DIR/docs/recording-backend.md" "$DESTINATION/README.md"

mkdir -p "$DESTINATION/adbuddy-recording"
cp "$ROOT_DIR/scripts/recording/segments.c" "$ROOT_DIR/scripts/recording/build_backend.sh" "$ROOT_DIR/scripts/prepare_recording_sources.sh" "$DESTINATION/adbuddy-recording/"
