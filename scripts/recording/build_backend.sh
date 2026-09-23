#!/usr/bin/env bash
# Build the patched recorder with static libraries; no Homebrew runtime dependencies.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARCH="${1:?architecture required}"
CACHE="$ROOT/.build/recording-backend"
BUILD="$CACHE/build-$ARCH"
PREFIX="$BUILD/install"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
export MACOSX_DEPLOYMENT_TARGET=14.0
SDK="$(xcrun --sdk macosx --show-sdk-path)"
export CC="$(xcrun --find clang)"
export CXX="$(xcrun --find clang++)"
export CFLAGS="-arch $ARCH -isysroot $SDK -mmacosx-version-min=14.0"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="$CFLAGS"
JOBS="$(sysctl -n hw.ncpu)"
case "$ARCH" in arm64|x86_64) ;; *) exit 1 ;; esac
for tool in cmake pkg-config python3; do
  command -v "$tool" >/dev/null || { echo "Install $tool to build the recording helper." >&2; exit 1; }
done
mkdir -p "$BUILD" "$PREFIX"
FINGERPRINT="$(cat "$ROOT/scripts/recording/segments.c" "$ROOT/scripts/recording/build_backend.sh" | shasum -a 256 | cut -d ' ' -f1)"
# Increment when changing pinned library versions or their configure options.
LIBRARY_BUILD_VERSION=3
if [[ -f "$BUILD/library-build-version" && "$(cat "$BUILD/library-build-version")" != "$LIBRARY_BUILD_VERSION" ]]; then
  rm -rf "$PREFIX" "$BUILD/sdl" "$BUILD/ffmpeg"
  mkdir -p "$PREFIX"
fi
if [[ -f "$BUILD/fingerprint" && "$(cat "$BUILD/fingerprint")" == "$FINGERPRINT" && -x "$BUILD/client/app/scrcpy" ]]; then
  echo "$BUILD/client/app/scrcpy"
  exit 0
fi
"$ROOT/scripts/prepare_recording_sources.sh" "$CACHE/source-archives" >&2
if [[ ! -x "$CACHE/build-tools/bin/meson" ]]; then
  python3 -m venv "$CACHE/build-tools" >&2
  "$CACHE/build-tools/bin/pip" install 'meson==1.9.1' 'ninja==1.13.0' >&2
fi
export PATH="$CACHE/build-tools/bin:$PATH"
if [[ ! -d "$BUILD/scrcpy-4.1" ]]; then
  tar -xzf "$CACHE/sources/scrcpy-4.1.tar.gz" -C "$BUILD"
fi
if [[ ! -f "$PREFIX/lib/libSDL3.a" ]]; then
  tar -xzf "$CACHE/sources/SDL-3.4.12.tar.gz" -C "$BUILD"
  cmake -S "$BUILD/SDL-release-3.4.12" -B "$BUILD/sdl" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_OSX_SYSROOT="$SDK" -DSDL_SHARED=OFF -DSDL_STATIC=ON \
    -DSDL_TEST_LIBRARY=OFF -DSDL_TESTS=OFF >&2
  cmake --build "$BUILD/sdl" --parallel "$JOBS" >&2
  cmake --install "$BUILD/sdl" >&2
fi
if [[ ! -f "$PREFIX/lib/libavformat.a" ]]; then
  tar -xf "$CACHE/sources/ffmpeg-8.1.2.tar.xz" -C "$BUILD"
  mkdir -p "$BUILD/ffmpeg"
  (
    cd "$BUILD/ffmpeg"
    "$BUILD/ffmpeg-8.1.2/configure" --prefix="$PREFIX" \
      --cc="$CC" --arch="$ARCH" --target-os=darwin --enable-cross-compile \
      --extra-cflags="$CFLAGS" --extra-ldflags="$LDFLAGS" \
      --disable-autodetect --disable-everything --disable-programs --disable-doc \
      --disable-shared --enable-static --disable-x86asm \
      --disable-avdevice --disable-avfilter --disable-swscale \
      --enable-swresample --enable-decoder=h264,png --enable-parser=h264,png --enable-demuxer=image_png_pipe \
      --enable-muxer=mp4 --enable-protocol=file --enable-zlib >&2
    make -j "$JOBS" >&2
    make install >&2
  )
fi
printf '%s\n' "$LIBRARY_BUILD_VERSION" > "$BUILD/library-build-version"
# Refresh the upstream file before applying our one integration hook.
tar -xzf "$CACHE/sources/scrcpy-4.1.tar.gz" -C "$BUILD" scrcpy-4.1/app/src/recorder.c
cp "$ROOT/scripts/recording/segments.c" "$BUILD/scrcpy-4.1/app/src/adbuddy_segments.c"
python3 - "$BUILD/scrcpy-4.1/app/src/recorder.c" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
needle = 'static bool\nsc_recorder_record(struct sc_recorder *recorder) {'
assert s.count(needle) == 1
s = s.replace(needle, '#include "adbuddy_segments.c"\n\n' + needle + '\n    if (getenv("ADBUDDY_RECORDING_SEGMENTS")) {\n        return adbuddy_record_segments(recorder);\n    }')
p.write_text(s)
PY
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
unset PKG_CONFIG_PATH
rm -rf "$BUILD/client"
MESON_ARCH_ARGS=()
if [[ "$ARCH" != "$(uname -m)" ]]; then
  CPU_FAMILY="$ARCH"
  [[ "$ARCH" != arm64 ]] || CPU_FAMILY=aarch64
  cat > "$BUILD/cross.ini" <<CROSS
[binaries]
c = '$CC'
cpp = '$CXX'
pkg-config = '$(command -v pkg-config)'
[host_machine]
system = 'darwin'
cpu_family = '$CPU_FAMILY'
cpu = '$CPU_FAMILY'
endian = 'little'
[properties]
needs_exe_wrapper = true
CROSS
  MESON_ARCH_ARGS=(--cross-file "$BUILD/cross.ini")
fi
meson setup "$BUILD/client" "$BUILD/scrcpy-4.1" ${MESON_ARCH_ARGS[@]+"${MESON_ARCH_ARGS[@]}"} \
  --buildtype=release -Dcompile_server=false -Dportable=true -Dstatic=true \
  -Dusb=false -Dv4l2=false -Dc_args="$CFLAGS -I$PREFIX/include" \
  -Dc_link_args="$LDFLAGS -L$PREFIX/lib" >&2
ninja -C "$BUILD/client" >&2
# A release helper must depend only on Apple system libraries.
if otool -L "$BUILD/client/app/scrcpy" | tail -n +2 | awk '{print $1}' | grep -vE '^(/usr/lib/|/System/Library/)' ; then
  echo "Unexpected non-system recording helper dependency" >&2
  exit 1
fi
printf '%s\n' "$FINGERPRINT" > "$BUILD/fingerprint"
echo "$BUILD/client/app/scrcpy"
