#!/usr/bin/env bash
# Package immutable helper bytes and checksum-verified official Node distributions.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${1:?usage: prepare_emulator_backend.sh Contents [arm64|x86_64|universal]}"
VARIANT="${2:-$(uname -m)}"
CACHE="$ROOT_DIR/.build/emulator-backend"
MANIFEST="$ROOT_DIR/bundled-dependencies.json"
manifest_value() {
  /usr/bin/plutil -extract "$1" raw -o - "$MANIFEST"
}
mkdir -p "$CACHE" "$DESTINATION/MacOS" "$DESTINATION/Resources/Emulator"
HELPER="$ROOT_DIR/$(manifest_value emulator.archive)"
HELPER_CHECKSUM="$(manifest_value emulator.sha256)"
[[ "$(shasum -a 256 "$HELPER" | cut -d ' ' -f 1)" == "$HELPER_CHECKSUM" ]] || {
  echo "Emulator helper checksum mismatch: $HELPER" >&2; exit 1;
}
rm -rf "$DESTINATION/Resources/Emulator/package"
tar -xzf "$HELPER" -C "$DESTINATION/Resources/Emulator"
cp "$MANIFEST" "$DESTINATION/Resources/Emulator/bundled-dependencies.json"
cp "$ROOT_DIR/vendor/emulator/README.md" "$DESTINATION/Resources/Emulator/Provenance.md"
install_node() {
  local architecture="$1" url checksum archive extracted
  url="$(manifest_value "node.archives.$architecture.url")"
  checksum="$(manifest_value "node.archives.$architecture.sha256")"
  archive="$CACHE/$(basename "$url")"
  if [[ ! -f "$archive" ]]; then
    curl --fail --location --silent --show-error "$url" -o "$archive.download"
    mv "$archive.download" "$archive"
  fi
  [[ "$(shasum -a 256 "$archive" | cut -d ' ' -f 1)" == "$checksum" ]] || {
    echo "Node checksum mismatch: $archive" >&2; exit 1;
  }
  extracted="$(mktemp -d "$CACHE/extract.XXXXXX")"
  tar -xzf "$archive" --strip-components=1 -C "$extracted"
  cp "$extracted/bin/node" "$DESTINATION/MacOS/node-$architecture"
  cp "$extracted/LICENSE" "$DESTINATION/Resources/Emulator/Node-LICENSE-$architecture.txt"
  /usr/bin/lipo -verify_arch "$architecture" "$DESTINATION/MacOS/node-$architecture"
  rm -rf "$extracted"
}
case "$VARIANT" in
  universal) install_node arm64; install_node x86_64 ;;
  arm64|x86_64) install_node "$VARIANT" ;;
  *) echo "Unsupported emulator backend variant: $VARIANT" >&2; exit 1 ;;
esac
