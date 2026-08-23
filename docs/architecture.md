# Architecture

## Approach

ADBuddy is a SwiftPM-based SwiftUI app. It keeps platform UI, Android SDK
interaction, device state, and persistence separate without introducing a large
protocol hierarchy.

The app targets macOS 14 or newer and uses SwiftUI for scenes, window chrome,
and controls. AppKit is reserved for narrow platform needs that SwiftUI cannot
handle cleanly: the editable Logcat application picker and virtualized native
Logcat table.

## Scenes

The app has separate, explicit scene roots:

```text
WindowGroup(id: "main")
  Compact Connected Android Devices and available Android Emulators sections,
  or an explanatory unavailable state

MenuBarExtra
  Fast per-device screenshot and recording commands, installed-emulator launch,
  app navigation, and Settings

Settings window
  General menu bar visibility, shared media destination, media clipboard-copy,
  Finder reveal, screenshot framing, and Logcat colors

Logcat WindowGroup (one window per device serial)
  Dedicated streaming viewer with window-scoped filters, follow state, and retention
```

The app should retain normal application behavior with a visible main window
and a Dock presence, rather than behaving as a menu-only accessory app.
It opts out of automatic window tabbing because the main window is a focused
utility surface, not a document workspace.
Its window frame cannot be resized narrower than its initial or restored width,
so device controls and toolbar actions remain usable.

The per-device Logcat scene is specified in [`logcat.md`](logcat.md). Its state
remains isolated from the shared device-discovery store.

## Initial source layout

```text
Sources/
  ADBuddyCore/
    typed Android models, SDK discovery, process execution, emulator,
    screenshot, recording, filenames, logging, and shared preferences
  ADBuddy/
    App/, Stores/, Views/, and GUI-only services
  ADBuddyMCP/
    standalone stdio JSON-RPC transport and MCP recording ownership
Tests/
  ADBuddyTests/
```

This is a guide to responsibilities, not a mandate to create empty files. Add a
file only when its corresponding behavior is implemented.

## Data flow

```text
SwiftUI scene
    -> DeviceStore
        -> ADBClient
            -> ProcessRunner
                -> adb executable

AndroidSDKLocator -> resolved adb path -> ADBClient
AppPreferences -> screenshot destination -> ScreenshotService
AppPreferences -> screenshot framing options -> ScreenshotService -> Android SDK skins
AppPreferences -> device-details overlay -> ScreenshotService and ScreenRecordingService -> Android device properties
AppPreferences -> clipboard preference -> MediaClipboardService
AppPreferences -> Finder reveal preference -> MediaFinderRevealService
DeviceStore -> MediaNotificationService -> macOS notification center
AppPreferences -> recording options -> ScreenRecordingService
DeviceStore -> ScreenRecordingService -> ADB screenrecord, pull, cleanup
ScreenRecordingService -> AVFoundation -> framed MP4 export
DeviceStore discovery by serial -> LogcatWindowView -> LogcatStore
DeviceStore emulator entries -> EmulatorStore -> AndroidEmulatorService
EmulatorStore -> AndroidEmulatorService -> Emulator executable -> standalone Emulator window
EmulatorStore -> AndroidEmulatorService -> adb emulator-console commands
DeviceStore -> AndroidDeepLinkService -> adb activity manager ACTION_VIEW intent
DeviceStore -> AndroidDeviceSettingsService -> adb system settings and properties
DeviceStore devices -> APKInstallationStore -> APKInstallationService -> adb install
APKInstallationService -> Android SDK aapt2 -> APK package and launcher metadata
LogcatStore -> LogcatService -> StreamingProcessRunner -> adb logcat
ADBuddyMCP stdio transport -> ADBuddyCore -> Android SDK services -> adb and Emulator executable
```

`ADBuddyCore` contains the typed SDK discovery, ADB device, emulator, screenshot,
recording, process, filename, logging, and shared-preferences behavior used by
both the SwiftUI app and the standalone `adbuddy-mcp` executable. The MCP
transport is deliberately headless and owns only JSON-RPC request handling plus
the lifetime of MCP-started recordings. It never reaches into SwiftUI stores or
constructs shell command strings.

`DeviceStore` owns automatic one-second refresh timing, selected device state,
and presentation-ready errors. It does not parse process output itself.
`ADBClient` translates ADB commands and parsed output into typed domain values.
`ProcessRunner` owns
subprocess lifecycle and exposes captured stdout, stderr, exit status, and
cancellation.

`AndroidAppActionsService` resolves a device's foreground package through the
Android activity manager, then performs one app lifecycle action with fixed ADB
arguments. `DeviceStore` owns short-lived action state, non-blocking feedback,
and the exact-package confirmation required before uninstalling an app.

`AndroidDeepLinkService` receives a validated absolute URI, an optional Android
package identifier, and an explicit device serial. It starts an `ACTION_VIEW`
intent with fixed ADB arguments and reports both process failures and Android
activity-manager error output. The compact launcher sheet owns URI entry and
device selection; it delegates launch state and feedback to `DeviceStore`.

`APKInstallationStore` owns the short-lived local APK selection, per-device
install progress, and presentation feedback. It receives a user-selected local
file URL from an AppKit open panel, Finder document opening, or a SwiftUI drop
target, but keeps all installation work in `APKInstallationService`.
`APKInstallationService` validates the archive and invokes `adb -s <serial>
install -r <path>` with a fixed executable and argument array. When the user
asks to open the installed app, it uses the newest executable `aapt2` under
the resolved SDK's `build-tools` directory to resolve a package and launcher
activity before installation, then starts that exact activity through ADB. An
unavailable build tool or missing launcher is a launch warning after a
successful install, not an installation error. Multiple selected devices run
independently, so each device receives its own outcome.

`AndroidDeviceSettingsService` applies one explicit system setting to a usable
device with fixed ADB arguments. It covers dark or light system theme, gesture
or 3-button navigation, Show or Hide Layout Bounds, and Show or Hide GPU
Rendering Bars. It does not run with device discovery polling: the menu starts
one short-lived operation and `DeviceStore` presents the result.

`EmulatorStore` loads installed AVD names on demand, maps usable ADB emulator
serials back to their AVD names, and owns lifecycle state plus concise user
feedback. The main window renders every physical device and usable ADB emulator
under **Connected Android Devices**. A running AVD maps to that device row,
where it exposes its AVD name, stop control, capture, and Logcat actions. The
**Android Emulators** section keeps only stopped and transitional installed
AVDs, avoiding a second row for an already-connected emulator.

`EmulatorWindowService` is a narrow GUI-side host-process bridge. It parses the
fixed `/bin/ps` process listing to associate an AVD with a standalone window,
an Android Studio-managed window, or a headless launch. Only a standalone
window can be activated through `NSRunningApplication`; the SwiftUI view reads
the resulting presentation state without inspecting processes itself.

`AndroidEmulatorService` asks the SDK's `emulator` executable for
`-list-avds`, then starts a selected AVD through a short-lived foreground
process launch with a fixed argument array. Quick Boot uses `-avd <name>`, Cold
Boot adds `-no-snapshot-load`, and an explicitly confirmed reset adds
`-wipe-data`. It resolves a running AVD through the ADB emulator-console
`avd name` command and stops it with `adb -s <serial> emu kill`. It must not
use Android Studio flags that hide or embed the Emulator window. Once launched,
the Android Emulator owns its window and Dock presence independently of
ADBuddy.

`LogcatStore` owns only one Logcat window's retained entries, application,
minimum-level, crash-and-exception, and text-search filters, pause/follow
state, and reconnect lifecycle. Column visibility is likewise local to the
window session. The store observes the shared `DeviceStore` result by serial,
cancels its stream when that device is unavailable, and resumes it when the
same serial is usable again. It keeps at most 50,000 typed entries and derives
the visible list incrementally
for ordinary batches. Text search and the crash and exception toggle narrow the
retained visible result without restarting the ADB stream. `LogcatService`
parses `adb logcat -v threadtime` off the main actor and delivers modest
batches. The `NSTableView` bridge
virtualizes visible row views and reads rows by count/revision so it does not
retain a second 50,000-entry array.

## Android SDK discovery

`AndroidSDKLocator` should check candidates in this order:

1. `ANDROID_HOME`;
2. `ANDROID_SDK_ROOT`;
3. `~/Library/Android/sdk`.

For each candidate, it verifies that `platform-tools/adb` exists and is
executable. A later preference can offer an explicit SDK path, but that is not
needed for the first milestone.

## Device model

`AndroidDevice` is derived from `adb devices -l`, never exposed as raw command
output. It should contain:

- a stable serial identifier;
- an optional human-friendly name;
- typed connection state;
- device kind: physical device or emulator;
- optional transport metadata useful for troubleshooting.

The parser must retain non-usable entries so the UI can explain why an action is
not available. The app refreshes automatically once per second.
Polling must be visually silent when the discovered device state is unchanged,
so open menu hierarchies and the main-window device presentation remain stable.

## Screenshots

`ScreenshotService` receives a typed device, destination URL, and screenshot
framing options. It invokes ADB with a fixed executable plus argument array,
validates stdout as binary PNG data, and returns either a saved file result or
a structured failure. When framing is enabled for an emulator, it asks the
Emulator console for the running AVD path, reads its `config.ini`, and matches
the configured SDK skin against a cached index built from `<sdk>/skins/*/layout`.
It uses the skin's declared display rectangle and frame layers instead of a
bundled device-to-resolution map. A missing, custom, incompatible, or
ambiguous SDK skin falls back to a generic black device frame. The screenshot
pixels are not rescaled; only frame assets are scaled to the compatible display
size.

When the device-details overlay preference is enabled, `ScreenshotService` and
the recording framer use fixed ADB `getprop` arguments to read
`ro.build.version.release` and `ro.build.version.sdk`. They write the resulting
`Android 16 / API 36` label into the top-left of saved screenshots and framed
recordings. A framed result receives its label after the device frame is
composed, so it appears over the frame rather than inside the device display.

Screenshot filenames must be sanitized, timestamped, and collision-resistant.
The service must not silently replace an existing file. A framed capture uses
the `_framed.png` suffix; when the user also saves the original, the service
selects a collision-free pair before either file is written.

After a successful screenshot or recording save, `DeviceStore` can copy media
to the macOS pasteboard through `MediaClipboardService`. Screenshots copy PNG
bytes, while recordings copy the saved MP4's file URL without loading the
entire video into memory. When the Finder reveal preference is enabled,
`DeviceStore` uses `MediaFinderRevealService` to ask Finder to select each
saved item. For saved screenshots and recordings, it asks
`MediaNotificationService` to post a native
notification. The service registers a **Reveal in Finder** notification action
and routes that action to `NSWorkspace` for the saved file URL. It attaches the
preview from a disposable copy of the saved PNG or MP4, then asks macOS to use
time zero as the thumbnail for attached MP4 recordings. The original saved
media must never be supplied directly as a notification attachment because
macOS consumes writable attachment files.

## Preferences

`AppPreferences` is an application-owned wrapper around `UserDefaults`.
It persists a screenshot destination path, screenshot framing and
original-retention preferences, the optional device-details overlay, recording
framing, and whether successful screenshots and recordings are automatically
copied to the clipboard. The same path is the shared media destination for
screenshots and MP4 recordings. It also persists whether media is automatically
revealed in Finder, and stores a recording bit rate, resolution percentage, and
Show taps value for the next recording. The directory defaults to the current
user's `~/Screenshots` directory, automatic copying defaults to enabled,
screenshot framing, recording framing, and the device-details overlay default
to disabled, and automatic Finder reveal defaults to disabled. It also persists
whether ADBuddy is shown in the menu bar and whether successful action feedback
banners are shown, both of which default to enabled. The service layer receives
values from the preferences store rather than accessing `UserDefaults` itself.

The same store persists six serializable sRGB component values for global
Logcat severity colors. Settings changes update every open Logcat window
immediately; application filters, pause/follow state, retained rows, and
column visibility remain window-session state.

Because the app is non-sandboxed, store a regular absolute path. If future
distribution requires sandboxing, replace this storage with a security-scoped
bookmark through a deliberate migration.

The app presents a dedicated SwiftUI Settings window. It receives the existing
`AppPreferences` instance and uses a native folder importer to update the
shared media destination.

The app writes shared media and recording settings through its standard
`com.clawperator.adbuddy` application defaults domain. The bundled MCP helper
reads that same domain when it runs headlessly, so it receives the current
settings without the GUI using its own bundle identifier as a defaults suite.

## Screen recording

`ScreenRecordingService` constructs direct ADB calls through `ProcessRunner`.
For native resolution it leaves out `--size`; for a reduced percentage it asks
ADB for `wm size`, parses the physical dimensions, and supplies an even-sized
scaled `--size` value. It passes `--bit-rate` in bits per second.

The recording itself writes to a generated file in `/data/local/tmp`. The
service asks `pkill` to send `SIGINT` only to the process that contains that
generated path, allowing Android's recorder to finish the MP4. It pulls to a
temporary local file in the shared media directory, then moves that file to a
collision-resistant final name. This avoids replacing an existing media file.

When recording framing is enabled, the original MP4 is retained. The service
reserves an original and `_framed.mp4` pair before capture, then uses
AVFoundation and Core Animation to export the framed sibling without external
executables. It preserves the video timing, preferred orientation, and source
audio tracks. An emulator recording uses the same locally discovered SDK skin
layout as screenshots; an unavailable, incompatible, or ambiguous skin uses
the generic black frame. When the device-details preference is enabled, the
same Android-version and API-level label is rendered above the frame. Export
work writes to a temporary MP4, supports task cancellation, and only moves the
completed export into its reserved final name. If framing fails, the original
recording remains and the user receives a warning.

Show taps is implemented through Android's `show_touches` system setting. The
service reads the prior setting, enables it for the recording, and restores the
saved value after the recorder exits. If restoration fails, the saved recording
is retained and the user receives a warning.

## Logging and tests

Use Apple's `Logger` for app launch, SDK resolution, refresh attempts, ADB
failures, screenshot actions, and major window or menu actions. Do not log
screenshot image bytes or sensitive command input.

Test pure behavior without a device:

- `adb devices -l` parsing;
- SDK candidate precedence and error classification;
- filename sanitization and collision handling;
- SDK skin layout matching, generic-frame fallback, and PNG composition;
- process result to user-facing error mapping.
- display-size parsing, recording argument construction, Show taps restoration,
  non-overwriting MP4 retrieval, recording-frame filename pairs, frame geometry,
  and video-composition transforms.
- incremental Logcat parsing, filtering, retention, process cancellation,
  reconnect policy, preferences, and window-scoped inspection controls.
- installed-AVD parsing, emulator launch and lifecycle argument construction,
  and running-AVD serial mapping.

Live ADB validation supplements those tests when a device or emulator is
available.
