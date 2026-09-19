#!/usr/bin/env bash
# Install a pinned, checksum-verified headless recorder into an app's Contents directory.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${1:?usage: prepare_recording_backend.sh destination [arm64|x86_64|universal]}"
ARCHITECTURE="${2:-$(uname -m)}"
VERSION=4.1
CACHE="$ROOT_DIR/.build/recording-backend"
mkdir -p "$CACHE" "$DESTINATION"

install_architecture() {
  local architecture="$1" upstream_architecture checksum archive extracted
  case "$architecture" in
    arm64)
      upstream_architecture=aarch64
      checksum=20fd47c9014dd5e0fa77091f3cb7adbda8445a360c4584aeaa0150b5b3988ff3
      ;;
    x86_64)
      upstream_architecture=x86_64
      checksum=ee2a7223bc8dbdc4f482db1134bcf441178dafb833492b71ca4c22090c58ce72
      ;;
    *) echo "Unsupported recording architecture: $architecture" >&2; exit 1 ;;
  esac
  archive="$CACHE/scrcpy-macos-$upstream_architecture-v$VERSION.tar.gz"
  if [[ ! -f "$archive" ]]; then
    curl --fail --location --silent --show-error \
      "https://github.com/Genymobile/scrcpy/releases/download/v$VERSION/$(basename "$archive")" \
      --output "$archive.download"
    mv "$archive.download" "$archive"
  fi
  if [[ "$(shasum -a 256 "$archive" | cut -d ' ' -f 1)" != "$checksum" ]]; then
    echo "Recording backend checksum mismatch: $archive" >&2
    exit 1
  fi
  extracted="$(mktemp -d "$CACHE/extract.XXXXXX")"
  tar -xzf "$archive" -C "$extracted"
  mkdir -p "$DESTINATION/MacOS" "$DESTINATION/Resources/Recording/$architecture"
  # Use the user's resolved Android SDK ADB, not the release's bundled ADB.
  cp "$extracted/scrcpy-macos-$upstream_architecture-v$VERSION/scrcpy" "$DESTINATION/MacOS/scrcpy-$architecture"
  cp "$extracted/scrcpy-macos-$upstream_architecture-v$VERSION/"{scrcpy-server,LICENSE} "$DESTINATION/Resources/Recording/$architecture/"
  rm -rf "$extracted"
}

case "$ARCHITECTURE" in
  universal) install_architecture arm64; install_architecture x86_64 ;;
  *) install_architecture "$ARCHITECTURE" ;;
esac

mkdir -p "$DESTINATION/Resources/Recording"
cp "$ROOT_DIR/docs/recording-backend.md" "$DESTINATION/Resources/Recording/README.md"
