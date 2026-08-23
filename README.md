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
- a compact Settings sheet for the shared screenshot and recording folder, plus
  automatic media clipboard copying and optional Finder reveal;
- direct PNG screenshot capture from a selected connected device;
- screen recording with configurable bit rate, native-resolution percentage,
  and Show taps;
- native screenshot and recording notifications with media previews and a
  **Reveal in Finder** action;
- automatic screenshot and recording clipboard copy, enabled by default;
- optional screenshot and recording Finder reveal;
- foreground-app actions per device: start, kill, restart, clear app data,
  clear app data and restart, and confirmed uninstall;
- single-APK installation to one or more devices from the toolbar, menu bar,
  Finder's **Open With ADBuddy**, or by dropping an APK on a usable device;
- a dedicated Logcat window per device, with recent history, live streaming,
  application and minimum-level filtering, pause, copy, follow, and optional
  PID/TID columns;
- global Logcat severity colors in Settings.
- a local stdio MCP server for listing devices and emulators, controlling AVDs,
  and saving screenshots or screen recordings for an agent.

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

## Install APK

Choose **Install APK** from the toolbar or menu bar, open an APK through Finder,
or drop one onto a usable connected-device row. The install sheet supports one
ordinary `.apk` file at a time and can target multiple devices. It uses
`adb install -r`, retaining app data while replacing an existing compatible
build. ADBuddy does not enable app downgrades or uninstall an app implicitly.

Select **Open after install** to launch the app when its APK exposes a launcher
activity and the Android SDK includes `aapt2` in `build-tools`. A successful
install remains successful if that optional launch step is unavailable. Split
APKs, `.apks` archives, and Android App Bundles are not supported yet.

## Media destination

Screenshots and screen recordings share one destination. It defaults to
`~/Screenshots`, which is `/Users/chrislacy/Screenshots` on the initial
development machine. The destination, automatic clipboard-copy and Finder
reveal preferences, and screen-recording options are saved in `UserDefaults`.
Automatic screenshot and recording copying defaults to enabled; automatic
Finder reveal defaults to disabled. Use **ADBuddy → Settings…** to change them,
or to adjust the global Logcat severity colors.

## Logcat

Select **Open Logcat** beside a connected device in the main window or its
menu-bar submenu. Each device serial gets its own window with up to 5,000 recent
messages followed by its live stream. The toolbar provides an editable
application-ID filter, a minimum severity, local search with `⌘F`, a one-click
crash and exception filter, pause/resume, clear, follow, and column controls.
PID and TID are hidden by default. Select rows and press `⌘C` to copy readable
text.

Logcat keeps at most 50,000 entries per window. Disconnecting a device retains
its visible logs; reconnecting the same serial resumes that window automatically.

## Foreground app actions

Use the app-badge menu beside a usable device, or its **Foreground App** menu
in the menu bar, for lifecycle actions without entering a package name.
ADBuddy resolves the app currently in the foreground on that device when an
action begins. It can start, kill, restart, clear app data, or clear data and
restart that app. Uninstall shows a confirmation with the resolved package name
before removing it.

## MCP

The repository also builds `adbuddy-mcp`, a local stdio Model Context Protocol
server. It exposes device and emulator discovery, non-destructive emulator
start and stop, plus screenshot and screen-recording tools. MCP media uses the
same folder and recording defaults selected in ADBuddy Settings. See
[`docs/mcp.md`](docs/mcp.md) for configuration and the tool contract.

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
scripts/build_and_run.sh
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
5. **Phase 4 - Logcat:** delivered as a native per-device streaming viewer.
   Saved filters and exporting remain future work.

## Documentation

- [`docs/product-scope.md`](docs/product-scope.md) - initial product boundary
  and acceptance criteria.
- [`docs/architecture.md`](docs/architecture.md) - scene, service, and
  persistence design.
- [`docs/development.md`](docs/development.md) - build, test, and live-device
  validation conventions.
- [`docs/release.md`](docs/release.md) - signing, notarization, GitHub Release,
  and Homebrew cask strategy.
- [`docs/logcat.md`](docs/logcat.md) - Logcat behavior, architecture, and
  verification contract.
- [`docs/mcp.md`](docs/mcp.md) - local MCP server setup and tool contract.
