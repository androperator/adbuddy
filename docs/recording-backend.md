# Recording backend and third-party notices

ADBuddy uses scrcpy 4.1 with a small client-side recording extension in
`scripts/recording/segments.c`. The Android server remains unmodified from
[Genymobile's official release](https://github.com/Genymobile/scrcpy/releases/tag/v4.1).
This dependency replaces Android's `screenrecord`, which fits a rotated display
inside its original encoding dimensions and loses usable image resolution.
The bundled recorder locks the capture canvas to the device's natural orientation.
Display content can rotate within that canvas without shrinking into a portrait
letterbox. The device's own rotation settings are not changed.

For recording, the helper runs without a window, audio, device control, or
clipboard access.
It uses ADBuddy's resolved Android SDK ADB and writes local H.264 MP4 clips.
The extension reads encoded frame dimensions with FFmpeg's H.264 parser. When
those dimensions change, it finishes the previous MP4 and opens the next at the
new keyframe, with fresh codec headers and timestamps starting at zero. It does
not restart capture or re-encode video. Rotation within the locked canvas and
encoder restarts that retain the same dimensions do not create another clip.
Each finalized clip is exposed through a numbered temporary filename; unfinished
files are excluded. Swift preserves completed clips on a later failure, names
and frames them separately, and reports the session once.
The existing three-minute limit remains. The selected percentage limits the
longest dimension; the encoder may round dimensions to its required alignment.
Show taps, file naming, framing, and success notifications remain owned by ADBuddy.

## Device mirroring

ADBuddy also uses the bundled helper for **Mirror Device**. Each mirror runs as
an independent process with H.264 video playback and keyboard/mouse control.
Audio and automatic clipboard synchronization are disabled. Mirroring does not
use the recording extension, orientation lock, or recording time limit.
The existing SDL and H.264 decoder build supports this mode; no additional
runtime dependency is required.

## Bundling

`scripts/prepare_recording_backend.sh` downloads pinned, SHA-256-verified
macOS archives into the ignored `.build/recording-backend` cache. Local app
builds include the host architecture. Release ZIPs for Apple Silicon or Intel
include only that architecture; the universal ZIP includes both.
`scripts/recording/build_backend.sh` builds the patched client for each target
architecture from the pinned sources, with static SDL and FFmpeg libraries.
Initial builds require CMake, pkg-config, Python 3, and Apple command-line tools;
Meson and Ninja are installed at pinned versions in an ignored build-local
virtual environment. Cached dependencies and client builds are reused. The
client build rejects non-system dynamic library dependencies.
The scripts sign each helper before signing the outer app. The helper is in
`Contents/MacOS/scrcpy-arm64` or `scrcpy-x86_64`; the matching Android server
and scrcpy license are in `Contents/Resources/Recording/<architecture>`.
Neither Homebrew nor a separate scrcpy installation is required at runtime.
Building a packaged app initially requires network access. Pure Swift unit tests
do not download or launch the helper. Run the MCP executable from the packaged
app so it can locate the same recorder resources.

## Sources, licenses, and rebuilding

The scrcpy client and server are Copyright Genymobile and contributors, licensed
under Apache License 2.0. The custom static macOS client includes:

- FFmpeg 8.1.2, Copyright the FFmpeg developers, LGPL 2.1 or later;
- SDL 3.4.12, Copyright Sam Lantinga and contributors, zlib license.

The custom client disables direct USB (AOA) control; mirror input uses ADB.
It includes the H.264 and PNG decoders and parsers, PNG image demuxer, and MP4
muxer needed by these workflows. The matching upstream window icons are bundled
beside the Android server. The client does not link dav1d or libusb. Their upstream source archives remain included with the original source
bundle for reference.

Release packaging puts the matching sources and this document in a separate
`ADBuddy-recording-sources-<version>.zip`, published alongside the app ZIP on
[the same GitHub Release](https://github.com/clawperator/adbuddy/releases).
The app keeps this document and the license texts in
`Contents/Resources/Recording/README.md` and `Licenses/`. Its `Sources.txt`
contains the download URL for the matching source archive. All app ZIPs and the shared source ZIP
must remain available together. The source archive is not needed to run the app.
The pinned scrcpy source contains the original build configuration and dependency
build scripts in `release/build_macos.sh` and `app/deps/`. ADBuddy's release source
bundle also contains its client extension and build script in `adbuddy-recording`.
From this repository, run `scripts/recording/build_backend.sh arm64` or `x86_64`
to reproduce the modified client. The script shows the one integration hook
applied to upstream `recorder.c`; all extension behavior is in `segments.c`.
The same sources may be rebuilt with modified libraries.
The Android server can remain unchanged when rebuilding the desktop client.
ADBuddy does not restrict modifying or reverse engineering these components
for debugging modifications. Replacing a helper invalidates the app signature;
re-sign your local app with an ad-hoc signature after replacement.

Do not update a helper binary without updating its version, checksum, matching
sources, and these notices. The app does not bundle the release's ADB executable.

## Manual verification

Use a connected device or emulator. Verify these checks with framing enabled
and disabled where applicable:

- a screen recording with each selected option reaching the same media folder
  as screenshots, followed by a successful Stop Recording action;
  confirm an emulator capture uses its configured AVD name rather than a
  system-image model such as `sdk-gphone64-arm64` in the saved filename;
- a successful recording notification offering **Reveal in Finder**;
- Show taps returning to its original Android setting after recording.
  Start a recording in portrait, enter fullscreen landscape playback, then
  return to portrait. Confirm content rotates within the same video canvas
  without shrinking into a portrait letterbox, with and without framing.
  On a foldable emulator, also record open, closed, then open again. Confirm
  three numbered clips with fixed dimensions, independent playback, and the
  right frame for each. Rotate without folding and confirm it stays one clip.
  Verify one final silent notification and all primary clips on the clipboard.
