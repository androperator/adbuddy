# Architecture

## Approach

ADBuddy is a SwiftPM-based SwiftUI app. It keeps platform UI, Android SDK
interaction, device state, and persistence separate without introducing a large
protocol hierarchy.

The app targets macOS 14 or newer and uses SwiftUI for scenes, window chrome,
and controls. AppKit is reserved for narrow platform needs that SwiftUI cannot
handle cleanly, including window behavior, the editable Logcat application
picker, the virtualized native Logcat table, file panels, clipboard access,
and Finder integration.

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
  Finder reveal, screenshot and recording framing, additional PNG output,
  device-details overlays, and Logcat colors

Logcat WindowGroup (one window per device serial)
  Dedicated streaming viewer with window-scoped filters, follow state, and retention
```

The app uses normal application behavior while any ADBuddy window is open, with
Dock and Command-Tab presence. After the user closes the final ADBuddy
window, the app remains available from its menu-bar utility but transitions to
the accessory activation policy, removing its Dock and Command-Tab presence
until another ADBuddy window opens.
It opts out of automatic window tabbing because the main window is a focused
utility surface, not a document workspace.
The main window does not offer a full-screen control.
Its window frame cannot be resized narrower than its initial or restored width,
so device controls and toolbar actions remain usable.
Although it uses a `WindowGroup` so the menu-bar utility can remain running
after the main window closes, the app presents only one main window. Menu-bar
actions bring that existing window forward rather than creating another.

The per-device Logcat scene is specified in [`logcat.md`](logcat.md). Its state
remains isolated from the shared device-discovery store.

## Source layout

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
DeviceStore -> ScreenRecordingService -> bundled scrcpy capture -> local MP4
DeviceStore -> DeviceMirrorStore -> ScrcpyMirroring -> standalone scrcpy window
ScreenRecordingService -> AVFoundation -> framed MP4 export
DeviceStore discovery by serial -> LogcatWindowView -> LogcatStore
DeviceStore emulator entries -> EmulatorStore -> AndroidEmulatorService
EmulatorStore -> AndroidEmulatorService -> Emulator executable -> standalone Emulator window
EmulatorStore -> AndroidEmulatorService -> adb emulator-console commands
DeviceStore -> AndroidDeepLinkService -> adb activity manager ACTION_VIEW intent
DeviceStore -> AndroidDeviceSettingsService -> adb system settings and properties
DeviceStore devices -> APKInstallationStore -> APKInstallationService -> adb install
APKInstallationService -> Android SDK aapt2 -> APK package and launcher metadata
DeviceStore devices -> AndroidDeviceDetailsService -> adb system properties
EmulatorStore virtual devices -> AndroidVirtualDeviceDetailsService -> AVD and SDK metadata
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
device with fixed ADB arguments. The inline theme toggle reads the effective
`mComputedNightMode` from `dumpsys uimode` before applying the opposite explicit
theme, and reports an error without changing settings if it cannot read that
state. It covers dark or light system theme, gesture
or 3-button navigation, Show or Hide Layout Bounds, and Show or Hide GPU
Rendering Bars. It switches navigation using the current Android user's installed
navigation overlays and verifies the effective mode before reporting success.
Unsupported navigation modes produce an explanatory failure
without changing the device. Rendering changes notify running applications to
reload system properties without a restart. If that refresh fails, feedback
explains that the setting was saved but an app restart may be needed. It does
not run with device discovery polling: the menu starts one short-lived operation
and `DeviceStore` presents the result.

`EmulatorStore` loads installed AVD names at startup and every five seconds, without
resetting the visible list during refresh. It maps usable ADB emulator
serials back to their AVD names, and owns lifecycle state plus concise user
feedback. The main window renders every physical device and usable ADB emulator
under **Connected Android Devices**. A running AVD maps to that device row,
where it exposes its AVD name, stop control, capture, and Logcat actions. The
**Android Emulators** section keeps only stopped and transitional installed
AVDs, avoiding a second row for an already-connected emulator. Double-clicking
a stopped AVD row delegates to the same Quick Boot launch action as its Start
control.

`EmulatorWindowService` is a narrow GUI-side host-process bridge. It parses the
fixed `/bin/ps` process listing to associate an AVD with a standalone window,
an Android Studio-managed window, or a headless launch. A double-click on a
connected emulator reveals its standalone Emulator process or the running
Android Studio host application. The SwiftUI view reads the resulting
presentation state without inspecting processes itself.

The device-row contextual menus use narrow GUI-side services to copy a
connected device serial as plain text or reveal a matched or installed
emulator's local AVD directory in Finder. The directory resolver follows the
Android Emulator's AVD search order: `ANDROID_AVD_HOME`, `ANDROID_USER_HOME/avd`,
then `~/.android/avd`.

`AndroidEmulatorService` asks the SDK's `emulator` executable for
`-list-avds`, then starts a selected AVD through a short-lived foreground
process launch with a fixed argument array. Quick Boot uses `-avd <name>`, Cold
Boot adds `-no-snapshot-load`, and an explicitly confirmed reset adds
`-wipe-data`. It resolves a running AVD through the ADB emulator-console
`avd name` command and stops it with `adb -s <serial> emu kill`. It must not
use Android Studio flags that hide or embed the Emulator window. Once launched,
the Android Emulator owns its window and Dock presence independently of
ADBuddy.

Before a screenshot or recording is saved, `DeviceStore` and the MCP service
ask `AndroidEmulatorService` for the configured AVD name. They use that name
only as the media filename's user-facing prefix; the original typed device,
including its serial, remains the ADB target. If the emulator console does not
return a name, media falls back to the parsed ADB device name.

`LogcatStore` owns only one Logcat window's retained entries, application,
minimum-level, crash-and-exception, and text-search filters, pause/follow
state, and reconnect lifecycle. Table layout and wrapping are shared persisted
preferences in `AppPreferences`. The store observes the shared `DeviceStore` result by serial,
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

`AndroidSDKLocator` checks candidates in this order:

1. `ANDROID_HOME`;
2. `ANDROID_SDK_ROOT`;
3. `~/Library/Android/sdk`.

For each candidate, it verifies that `platform-tools/adb` exists and is
executable. A later preference can offer an explicit SDK path, but that is not
currently implemented.

## Device model

`AndroidDevice` is derived from `adb devices -l`, never exposed as raw command
output. Before publishing discovery results, `ADBClient` resolves each usable
emulator's configured AVD name through `emu avd name`. This shared display name
feeds Logcat titles and headers, menus, pickers, recording options, confirmations,
feedback, and MCP device discovery. Serial and raw model metadata stay unchanged.
If the console cannot resolve a name, discovery uses the serial rather than the
SDK model name. The GUI retains the last resolved name through a temporary
console failure or offline state, until that serial disconnects. The model contains:

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
ambiguous SDK skin falls back to a generic black device frame. When the
50%-size copy preference is enabled, the service resizes the final primary PNG
locally after its optional frame and device-details label are applied. It does
not take a second device screenshot.

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
to the macOS pasteboard through `MediaClipboardService`. Screenshots and
recordings copy their saved file URLs, allowing clipboard managers to reveal
the media without loading an image or video into memory. When the Finder reveal
preference is enabled,
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
original-retention preferences, the optional half-size PNG copy, device-details
overlay, recording framing, and whether successful screenshots and recordings are automatically
copied to the clipboard. The same path is the shared media destination for
screenshots and MP4 recordings. It also persists whether media is automatically
revealed in Finder, and stores a recording bit rate, resolution percentage, and
Show taps value for the next recording. The directory defaults to the current
user's `~/Screenshots` directory, automatic copying defaults to enabled,
screenshot framing, recording framing, and the device-details overlay default
to disabled, and automatic Finder reveal defaults to disabled. It also persists
whether ADBuddy is shown in the menu bar and whether successful action feedback
banners are shown. Menu bar visibility defaults to enabled, while success
banners default to disabled. The service layer
receives values from the preferences store rather than accessing `UserDefaults`
itself.

The same store persists six serializable sRGB component values for global
Logcat severity colors. Settings changes update every open Logcat window
immediately. It also persists Logcat column visibility, order, widths, and
message wrapping, shared by all Logcat windows. Application, minimum-level,
search, and crash filters, pause/follow state, retained rows, and scroll position
remain window-session state.

Because the app is non-sandboxed, store a regular absolute path. If future
distribution requires sandboxing, replace this storage with a security-scoped
bookmark through a deliberate migration.

The app presents a dedicated SwiftUI Settings window. It receives the existing
`AppPreferences` instance and uses a native folder importer to update the
shared media destination. Its tabs are General (menu bar and feedback),
Screenshots (shared media and capture output), and Theme (Logcat colors).
Recording bit rate, resolution, and Show taps are selected in the recording
options sheet.

The app writes shared media and recording settings through its standard
`com.clawperator.adbuddy` application defaults domain. The bundled MCP helper
reads that same domain when it runs headlessly, so it receives the current
settings without the GUI using its own bundle identifier as a defaults suite.

## Screen recording

`ScreenRecordingService` uses a bundled headless scrcpy capture helper through
`ProcessRunner`, with a fixed argument array and the resolved SDK ADB path.
The capture canvas stays in the device's natural orientation while screen
content rotates within it, preserving fullscreen content through portrait and
landscape transitions. It does not lock the device's own orientation.
For native resolution it leaves out the size limit; reduced percentages scale
the physical dimensions reported by `wm size` and limit the longest dimension.
The encoder may round dimensions to its supported alignment.

The helper streams into numbered temporary local MP4 clips in the shared media
folder, with a three-minute session limit. Stop sends SIGINT to the registered
process for that session so the muxer can finish the file. The recorder inspects
H.264 frame dimensions and finalizes a separate MP4 at an incoming keyframe
whenever those dimensions change. It retains one process
and session across fold transitions. Each clip has its own dimensions, codec
configuration, and timestamp origin. Ordinary rotation within the locked canvas
does not split a clip. Only finalized clips are handed to Swift; a later failure
returns completed clips with a warning. The service moves these to
collision-resistant final names, adding ordered suffixes for multi-clip sessions.
The clipboard receives all primary clips and one silent notification summarizes
the session. Its Finder action selects all primary clips. Both GUI and MCP use the same backend. Missing backend resources
produce a visible failure; there is no fallback to the rotation-broken recorder.
See [recording-backend.md](recording-backend.md) for dependency rationale,
packaging, matching sources, and third-party notices.

When recording framing is enabled, the original MP4 is retained. The service
reserves collision-safe names for each finalized clip and uses
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
  non-overwriting MP4 finalization, recording-frame filename pairs, frame geometry,
  and video-composition transforms.
- incremental Logcat parsing, filtering, retention, process cancellation,
  reconnect policy, preferences, and window-scoped inspection controls.
- installed-AVD parsing, emulator launch and lifecycle argument construction,
  and running-AVD serial mapping.

Live ADB validation supplements those tests when a device or emulator is
available.

## Device mirror sessions

`DeviceMirrorStore` owns one cancellable task and helper process identifier per
mirrored serial. It reserves the serial before launch, activates an existing
helper on repeated requests, and removes the session when the helper exits.
`ScrcpyMirroring` uses `ProcessRunner` with an explicit SDK ADB environment and
shares bundled-helper resolution with recording. The app waits for mirror
cancellation on normal quit. Mirror windows belong to the scrcpy process.

## Emulator creation prototype

`EmulatorCreationWindowController` presents one native, closable **Create Android Emulator**
window with a fresh `EmulatorCreationStore` each time it opens. `EmulatorCreationView`
presents the form. Closing is disabled while creation is in progress.
`EmulatorCreationService` calls the optional Node helper through `ProcessRunner`
with fixed argument arrays and explicit SDK/Java environment. It checks Node 24+,
protocol version 1, package identity and catalog capabilities, decodes typed JSON,
and verifies creation returns the requested AVD name and existence. Existing
emulator discovery and lifecycle operations remain native.

`EmulatorHelperInvocation` resolves a Settings override first. A packaged build
under a source checkout's `dist` directory can resolve the sibling `emulator`
checkout. Otherwise it searches PATH, standard Homebrew locations, Volta, and
installed nvm versions. Node is invoked explicitly so CLI shebang lookup does not
depend on Finder's PATH. An existing but unbuilt sibling reports an error rather
than falling back silently. Settings stores path overrides in `AppPreferences`.
The helper receives the same SDK root and ADB executable as normal app operations.
Java uses its explicit override, inherited JAVA_HOME, or Android Studio's runtime.

The catalog API is currently a local, unpublished emulator-package extension.
Creation refuses replacement, uses accepted licenses only, and refreshes discovery
on success or failure. No helper progress stream or cancellation guarantee is
assumed; the sheet remains open during an operation. ADBuddy must remain running.
