# ADBuddy

ADBuddy is a lightweight native macOS utility for Android developers. Its goal
is to make common device tasks available from the menu bar without opening
Android Studio.

## Current status

The native macOS app is available as a SwiftPM package with a menu-bar scene,
conventional main window, and a project-local build-and-run script. It
currently provides:

- Android SDK and ADB discovery;
- connected-device discovery with clear connection states;
- a macOS menu bar utility and a compact main-window device list;
- direct PNG screenshot capture from a selected connected device;
- screen recording with configurable bit rate, native-resolution percentage,
  and Show taps;
- native screenshot and recording notifications with a **Reveal in Finder**
  action;
- automatic PNG clipboard copy, enabled by default.

See [`docs/product-scope.md`](docs/product-scope.md) for the defined Phase 0
and Phase 1 acceptance criteria.

## Requirements

- macOS 14 or newer;
- Xcode and the macOS SDK for building from source;
- an Android SDK containing `platform-tools/adb`;
- an Android device or emulator with ADB available for end-to-end validation.

ADBuddy will find the Android SDK through `ANDROID_HOME`, `ANDROID_SDK_ROOT`,
or the standard `~/Library/Android/sdk` installation. It will not assume that a
GUI app inherits a useful shell `PATH`.

## Media destination

Screenshots and screen recordings share one destination. It defaults to
`~/Screenshots`, which is `/Users/chrislacy/Screenshots` on the initial
development machine. The destination, automatic clipboard-copy preference, and
screen-recording options are saved in `UserDefaults`. Automatic PNG copying
defaults to enabled. These controls will be exposed through Settings in a later
UI pass.

## Planned installation

ADBuddy will be distributed outside the Mac App Store as a signed and notarized
universal macOS app. The intended Homebrew installation is:

```sh
brew install --cask clawperator/tap/adbuddy
```

That cask will be added after the first release artifact exists. Until then,
there is no installable build.

## Development

The app will use SwiftPM and a shell-first build loop. Once the app scaffold is
present, the primary local commands will be:

```sh
script/build_and_run.sh
swift test
```

See [`docs/development.md`](docs/development.md) for the planned validation
workflow and [`docs/architecture.md`](docs/architecture.md) for the intended
source layout.

## Roadmap

1. **Phase 0 - Foundation:** macOS app shell, SDK discovery, device discovery,
   visible device states, and build/run workflow.
2. **Phase 1 - Screenshots:** direct PNG capture from the menu bar or main
   window, timestamped local files, and useful success or failure feedback.
3. **Phase 2 - Screen recording:** start and stop recording, retrieval, and
   bit-rate, scaled-output, and Show taps controls.
4. **Phase 3 - Emulator management:** list, launch, stop, and refresh AVDs.
5. **Phase 4 - Logcat:** a native streaming viewer with selection, filtering,
   search, pause, copying, and scroll-follow controls.

## Documentation

- [`docs/product-scope.md`](docs/product-scope.md) - initial product boundary
  and acceptance criteria.
- [`docs/architecture.md`](docs/architecture.md) - planned scene, service, and
  persistence design.
- [`docs/development.md`](docs/development.md) - build, test, and live-device
  validation conventions.
- [`docs/release.md`](docs/release.md) - signing, notarization, GitHub Release,
  and Homebrew cask strategy.
