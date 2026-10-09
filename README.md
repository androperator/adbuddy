# ADBuddy

ADBuddy is a lightweight native macOS utility for Android developers. Its goal
is to make common device tasks available from the menu bar without opening
Android Studio.

## Features

The native macOS app is available as a SwiftPM package with a menu-bar scene,
conventional main window, and a project-local build-and-run script. It
currently provides:

- Android SDK and ADB discovery;
- connected-device discovery with clear connection states;
- a macOS menu bar utility and a compact main-window device list;
- a dedicated Settings window for the shared screenshot and recording folder, plus
  automatic media clipboard copying and optional Finder reveal;
- direct PNG screenshot capture, optional device frames and Android-version
  labels, and an optional half-size copy;
- screen recording with configurable bit rate, native-resolution percentage,
  and Show taps, optional framing, and separate clips across fold-size changes
  within a three-minute recording session;
- native screenshot and recording notifications with media previews and a
  **Reveal in Finder** action;
- automatic screenshot and recording clipboard copy, enabled by default;
- optional screenshot and recording Finder reveal;
- installed-emulator discovery, Quick Boot, Cold Boot, confirmed wipe-and-start,
  stopping, and access to emulator windows and AVD folders;
- device information, Android Settings access, theme and navigation controls,
  and developer rendering overlays;
- a deep-link launcher with optional package targeting;
- foreground-app actions per device: start, kill, restart, clear app data,
  clear app data and restart, and confirmed uninstall;
- single-APK installation to one or more devices from the toolbar, menu bar,
  Finder's **Open With ADBuddy**, or by dropping an APK on a usable device;
- a dedicated Logcat window per device, with recent history, live streaming,
  application and minimum-level filtering, pause, copy, follow, and optional
  PID/TID/Application ID columns, search, crash filtering, and message wrapping;
- saved Logcat table layout and global severity colors;
- a local stdio MCP server for listing devices and emulators, controlling AVDs,
  and saving screenshots or screen recordings for an agent.

See [`docs/product-scope.md`](docs/product-scope.md) for the supported workflows
and scope boundaries.

## Requirements

- macOS 14 or newer;
- Xcode and the macOS SDK for building from source; see the additional build
  prerequisites in [`docs/development.md`](docs/development.md);
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
`~/Screenshots`. The destination, automatic clipboard-copy and Finder
reveal preferences, and screen-recording options are saved in `UserDefaults`.
Automatic screenshot and recording copying defaults to enabled; automatic
Finder reveal defaults to disabled. Use **ADBuddy → Settings…** to change them,
using the Screenshots tab for shared media settings or Theme for Logcat colors.
The General tab controls menu bar visibility and success banners. Recording
options are chosen when starting a recording and remembered for next time.

## Logcat

Select **Open Logcat** beside a connected device in the main window or its
menu-bar submenu. Each device serial gets its own window with up to 5,000 recent
messages followed by its live stream. The toolbar provides an editable
application-ID filter, a minimum severity, local search with `⌘F`, a one-click
crash and exception filter, pause/resume, clear, follow, and column controls.
PID, TID, and Application ID are hidden by default. Column visibility, order,
widths, and message wrapping are saved across windows and app launches.
Select rows and press `⌘C` to copy readable text.

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
same folder selected in Settings and the app's saved recording defaults. See
[`docs/mcp.md`](docs/mcp.md) for configuration and the tool contract.

## Installation

Download the macOS app ZIP from
[GitHub Releases](https://github.com/clawperator/adbuddy/releases/latest),
extract it, and move `ADBuddy.app` to Applications. Release builds support
Apple silicon and Intel Macs. Choose the download for your Mac: `arm64` for
Apple Silicon or `x86_64` for Intel. The universal ZIP supports both architectures.
The recording-source ZIP is only needed to rebuild the recorder.
Install the Android SDK separately.

Homebrew distribution is planned; use the published ZIP for installation.
See [`docs/release.md`](docs/release.md) for packaging and distribution details.

## Development

The app uses SwiftPM. From the repository root, build and launch the packaged
app and run the automated tests with:

```sh
scripts/build_and_run.sh
scripts/test.sh
```

See [`docs/development.md`](docs/development.md) for prerequisites and validation,
and [`docs/architecture.md`](docs/architecture.md) for the source layout and
service boundaries.

## Scope boundaries

AVD creation and configuration, snapshot management, saved Logcat filters, log
export, split-APK installation, and in-app automatic updates are not implemented.
These are possible extensions, not a scheduled roadmap.

## Documentation

- [`docs/product-scope.md`](docs/product-scope.md) - supported workflows
  and acceptance criteria.
- [`docs/architecture.md`](docs/architecture.md) - scene, service, and
  persistence design.
- [`docs/development.md`](docs/development.md) - local setup, build, test,
  and debugging commands.
- [`docs/release.md`](docs/release.md) - signing, notarization, GitHub Release,
  and planned Homebrew distribution.
- [`docs/recording-backend.md`](docs/recording-backend.md) - bundled recorder,
  build dependencies, and third-party notices.
- [`docs/logcat.md`](docs/logcat.md) - Logcat behavior, architecture, and
  verification contract.
- [`docs/mcp.md`](docs/mcp.md) - local MCP server setup and tool contract.

The bundled emulator-helper version, URL and checksum are pinned
in [bundled-dependencies.json](bundled-dependencies.json). See
[bundle provenance](vendor/emulator/README.md) for verification and update instructions.

Node.js 24+ must be installed separately for emulator creation and deletion.
Settings → Emulators supports an explicit Node executable override.
