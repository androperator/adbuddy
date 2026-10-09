#!/usr/bin/env bash
# Package immutable helper bytes and checksum-verified official Node distributions.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${1:?usage: prepare_emulator_backend.sh Contents}"
MANIFEST="$ROOT_DIR/bundled-dependencies.json"
manifest_value() {
  /usr/bin/plutil -extract "$1" raw -o - "$MANIFEST"
}
mkdir -p "$DESTINATION/Resources/Emulator"
HELPER="$ROOT_DIR/$(manifest_value emulator.archive)"
HELPER_CHECKSUM="$(manifest_value emulator.sha256)"
[[ "$(shasum -a 256 "$HELPER" | cut -d ' ' -f 1)" == "$HELPER_CHECKSUM" ]] || {
  echo "Emulator helper checksum mismatch: $HELPER" >&2; exit 1;
}
rm -rf "$DESTINATION/Resources/Emulator/package"
tar -xzf "$HELPER" -C "$DESTINATION/Resources/Emulator"
cp "$MANIFEST" "$DESTINATION/Resources/Emulator/bundled-dependencies.json"
cp "$ROOT_DIR/vendor/emulator/README.md" "$DESTINATION/Resources/Emulator/Provenance.md"
