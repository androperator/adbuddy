# Architecture

## Approach

ADBuddy is a SwiftPM-based SwiftUI app. It keeps platform UI, Android SDK
interaction, device state, and persistence separate without introducing a large
protocol hierarchy.

The app will target macOS 14 or newer and use SwiftUI as the source of truth.
AppKit is reserved for a narrow platform need that SwiftUI cannot handle cleanly.

## Scenes

The app has separate, explicit scene roots:

```text
WindowGroup(id: "main")
  Basic device overview and actions

MenuBarExtra
  Fast per-device screenshot and recording commands, plus app navigation

Settings
  Reserved for persisted preferences as Settings UI is introduced
```

The app should retain normal application behavior with a visible main window
and a Dock presence, rather than behaving as a menu-only accessory app.

## Initial source layout

```text
App/
  ADBuddyApp.swift
  AppDelegate.swift
Views/
  ContentView.swift
  DeviceListView.swift
  MenuBarView.swift
Models/
  AndroidDevice.swift
  DeviceConnectionState.swift
  ProcessResult.swift
Stores/
  DeviceStore.swift
  AppPreferences.swift
Services/
  AndroidSDKLocator.swift
  ProcessRunner.swift
  ADBClient.swift
  ScreenshotService.swift
Support/
  ScreenshotFilename.swift
  AppLogger.swift
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
AppPreferences -> clipboard preference -> ScreenshotClipboardService
DeviceStore -> MediaNotificationService -> macOS notification center
AppPreferences -> recording options -> ScreenRecordingService
DeviceStore -> ScreenRecordingService -> ADB screenrecord, pull, cleanup
```

`DeviceStore` owns refresh timing, selected device state, and presentation-ready
errors. It does not parse process output itself. `ADBClient` translates ADB
commands and parsed output into typed domain values. `ProcessRunner` owns
subprocess lifecycle and exposes captured stdout, stderr, exit status, and
cancellation.

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
not available. A lightweight periodic refresh is sufficient for Phase 0.

## Screenshots

`ScreenshotService` receives a typed device and destination URL. It invokes ADB
with a fixed executable plus argument array, writes stdout as binary PNG data,
and returns either a saved file URL or a structured failure.

Screenshot filenames must be sanitized, timestamped, and collision-resistant.
The service must not silently replace an existing file.

After a successful screenshot save, `DeviceStore` can copy PNG bytes to the
macOS pasteboard through `ScreenshotClipboardService`. For saved screenshots
and recordings, it asks `MediaNotificationService` to post a native
notification. The service registers a **Reveal in Finder** notification action
and routes that action to `NSWorkspace` for the saved file URL.

## Preferences

`AppPreferences` is an application-owned wrapper around `UserDefaults`.
It persists a screenshot destination path and whether successful captures are
automatically copied to the clipboard. The same path is the shared media
destination for screenshots and MP4 recordings. It also stores a recording bit
rate, resolution percentage, and Show taps value for the next recording. The
directory defaults to the current user's `~/Screenshots` directory and
automatic copying defaults to enabled. The service layer receives values from
the preferences store rather than accessing `UserDefaults` itself.

Because the app is non-sandboxed, store a regular absolute path. If future
distribution requires sandboxing, replace this storage with a security-scoped
bookmark through a deliberate migration.

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
- process result to user-facing error mapping.
- display-size parsing, recording argument construction, Show taps restoration,
  and non-overwriting MP4 retrieval.

Live ADB validation supplements those tests when a device or emulator is
available.
