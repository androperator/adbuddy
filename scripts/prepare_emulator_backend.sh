#!/usr/bin/env bash
# Package immutable helper bytes and checksum-verified official Node distributions.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${1:?usage: prepare_emulator_backend.sh Contents [arm64|x86_64|universal]}"
VARIANT="${2:-$(uname -m)}"
CACHE="$ROOT_DIR/.build/emulator-backend"
NODE_VERSION=24.21.0
mkdir -p "$CACHE" "$DESTINATION/MacOS" "$DESTINATION/Resources/Emulator"
HELPER="$ROOT_DIR/vendor/emulator/androperator-emulator-0.2.0.tgz"
HELPER_CHECKSUM=eaa2f002b3d658acd3ffa99ba054e8be470588eface47a1586f946e95c36f2c9
[[ "$(shasum -a 256 "$HELPER" | cut -d ' ' -f 1)" == "$HELPER_CHECKSUM" ]] || {
  echo "Emulator helper checksum mismatch: $HELPER" >&2; exit 1;
}
rm -rf "$DESTINATION/Resources/Emulator/package"
tar -xzf "$HELPER" -C "$DESTINATION/Resources/Emulator"
cp "$ROOT_DIR/vendor/emulator/README.md" "$DESTINATION/Resources/Emulator/Provenance.md"
install_node() {
  local architecture="$1" upstream checksum archive extracted
  case "$architecture" in
    arm64) upstream=arm64; checksum=bed7eea5325e1108f32ce5228ddd6a5f0f08a499ee42aa7442aea583702f6057 ;;
    x86_64) upstream=x64; checksum=1462cb3b3046b815cf8ea436d3da450ec1a9f11dac7e5a46b0ada5305d7e8097 ;;
    *) echo "Unsupported Node architecture: $architecture" >&2; exit 1 ;;
  esac
  archive="$CACHE/node-v$NODE_VERSION-darwin-$upstream.tar.gz"
  if [[ ! -f "$archive" ]]; then
    curl --fail --location --silent --show-error "https://nodejs.org/dist/v$NODE_VERSION/$(basename "$archive")" -o "$archive.download"
    mv "$archive.download" "$archive"
  fi
  [[ "$(shasum -a 256 "$archive" | cut -d ' ' -f 1)" == "$checksum" ]] || {
    echo "Node checksum mismatch: $archive" >&2; exit 1;
  }
  extracted="$(mktemp -d "$CACHE/extract.XXXXXX")"
  tar -xzf "$archive" -C "$extracted"
  cp "$extracted/node-v$NODE_VERSION-darwin-$upstream/bin/node" "$DESTINATION/MacOS/node-$architecture"
  cp "$extracted/node-v$NODE_VERSION-darwin-$upstream/LICENSE" "$DESTINATION/Resources/Emulator/Node-LICENSE-$architecture.txt"
  /usr/bin/lipo -verify_arch "$architecture" "$DESTINATION/MacOS/node-$architecture"
  rm -rf "$extracted"
}
case "$VARIANT" in
  universal) install_node arm64; install_node x86_64 ;;
  arm64|x86_64) install_node "$VARIANT" ;;
  *) echo "Unsupported emulator backend variant: $VARIANT" >&2; exit 1 ;;
esac
