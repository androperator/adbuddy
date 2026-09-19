# Recording backend and third-party notices

ADBuddy bundles the unmodified scrcpy 4.1 client and Android server from
[Genymobile's official release](https://github.com/Genymobile/scrcpy/releases/tag/v4.1).
This dependency replaces Android's `screenrecord`, which fits a rotated display
inside its original encoding dimensions and loses usable image resolution.
The bundled recorder locks the capture canvas to the device's natural orientation.
Display content can rotate within that canvas without shrinking into a portrait
letterbox. The device's own rotation settings are not changed.

The helper runs without a window, audio, device control, or clipboard access.
It uses ADBuddy's resolved Android SDK ADB and writes one local H.264 MP4.
The existing three-minute limit remains. The selected percentage limits the
longest dimension; the encoder may round dimensions to its required alignment.
Show taps, file naming, framing, and success notifications remain owned by ADBuddy.

## Bundling

`scripts/prepare_recording_backend.sh` downloads pinned, SHA-256-verified
macOS archives into the ignored `.build/recording-backend` cache. Local app
builds include the host architecture; release builds include both architectures.
The scripts sign each helper before signing the outer app. The helper is in
`Contents/MacOS/scrcpy-arm64` or `scrcpy-x86_64`; the matching Android server
and scrcpy license are in `Contents/Resources/Recording/<architecture>`.
Neither Homebrew nor a separate scrcpy installation is required at runtime.
Building a packaged app initially requires network access. Pure Swift unit tests
do not download or launch the helper. Run the MCP executable from the packaged
app so it can locate the same recorder resources.

## Sources, licenses, and rebuilding

The scrcpy client and server are Copyright Genymobile and contributors, licensed
under Apache License 2.0. The official static macOS client also includes:

- FFmpeg 8.1.2, Copyright the FFmpeg developers, LGPL 2.1 or later;
- SDL 3.4.12, Copyright Sam Lantinga and contributors, zlib license;
- dav1d 1.5.3, Copyright VideoLAN and contributors, BSD 2-Clause license;
- libusb 1.0.30, Copyright the libusb developers, LGPL 2.1 or later.

Release packaging includes the matching source archives, license texts inside
those archives, and this document in `Contents/Resources/Recording/Sources`.
The pinned scrcpy source contains the original build configuration and dependency
build scripts in `release/build_macos.sh` and `app/deps/`. These allow rebuilding
the helper with modified libraries. Follow scrcpy's `doc/build.md` for build
tools, unpack the dependency archives into the cache expected by `app/deps`,
and use the supplied macOS release build script for the desired architecture.
The Android server can remain unchanged when rebuilding the desktop client.
ADBuddy does not restrict modifying or reverse engineering these components
for debugging modifications. Replacing a helper invalidates the app signature;
re-sign your local app with an ad-hoc signature after replacement.

Do not update a helper binary without updating its version, checksum, matching
sources, and these notices. The app does not bundle the release's ADB executable.
