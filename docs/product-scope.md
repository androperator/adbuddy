# Product scope

## Product intent

ADBuddy is a native macOS utility for Android developers who need quick access
to Android SDK and ADB capabilities without launching Android Studio. It should
feel fast, small, reliable, and obvious.

The app is not an Android Studio replacement. It should remain a focused tool
for a small number of high-value workflows.

## Phase 0 and Phase 1

The first implementation is a complete vertical slice, not a visual mockup.

### Phase 0 - Foundation

- Build and launch a native macOS app.
- Provide both a `MenuBarExtra` and a conventional app window.
- Allow the menu bar utility to open and activate the main window.
- Locate a usable Android SDK and ADB executable.
- Refresh connected devices automatically once per second.
- Represent device serial, display name, connection state, and physical or
  emulator kind as typed data.
- Show clear UI states for a missing SDK, missing ADB, no devices,
  unauthorized devices, offline devices, and usable devices.

### Phase 1 - Screenshots

- Offer **Take Screenshot** for each usable connected device from the menu bar
  and basic main window.
- Capture binary PNG data with:

  ```text
  adb -s <serial> exec-out screencap -p
  ```

- Write a valid local PNG to the configured screenshot directory.
- Default the directory to `~/Screenshots` and use a safe timestamped filename,
  for example `Pixel-9-Pro_2026-08-22_121530_123.png`.
- Report a concise native success state and a useful failure if capture fails.
- Deliver a native system notification for a successful capture, including a
  preview of the saved PNG and a **Reveal in Finder** action.
- Copy successful PNG captures to the clipboard by default. This behavior is a
  persisted preference exposed by the app's Settings sheet.
- Let users choose the shared media destination from the Settings sheet. The
  selected folder is used for both screenshots and recordings.

### Phase 2 - Screen recording

- Offer **Record Screen** for each usable connected device from the menu bar
  and main window.
- Present native controls for the requested recording options:
  - bit rate in Mbps, defaulting to 8 Mbps;
  - resolution as 100%, 75%, 50%, or 25% of physical display size, defaulting
    to 100%;
  - Show taps, defaulting to disabled.
- Use `adb shell screenrecord` with a fixed argument array, passing a bit rate
  and scaled size when selected.
- Stop the selected device's recording with a targeted interrupt, retrieve its
  MP4, and remove its temporary device-side file.
- Save MP4s into the same configured destination as screenshots. Do not create
  a separate recording directory or a destination picker in this phase.
- Deliver a native success notification for each saved MP4, including a
  first-frame preview and a **Reveal in Finder** action.
- When Show taps is enabled, preserve the existing Android setting and restore
  it when the recording finishes.

### Phase 3 - Emulator management

- Separate usable physical devices from installed Android Virtual Devices
  (AVDs) in the compact main-window list.
- Show every installed AVD and whether it is stopped, starting, running, or
  stopping. A running AVD maps to its ADB serial before device actions appear.
- Let users start a stopped AVD with Quick Boot, use Cold Boot from its action
  menu, or stop a running AVD.
- Require an explicit confirmation before **Wipe Data and Start**, because it
  removes the AVD's installed apps and settings.
- Start each mode with the SDK's `emulator` executable and fixed arguments:
  `-avd <name>` for Quick Boot, `-no-snapshot-load` for Cold Boot, and
  `-wipe-data` for a confirmed reset. Do not use Android Studio
  embedded-window flags, so the Android Emulator owns its normal standalone
  macOS window and Dock presence.
- Stop a running AVD through `adb -s <serial> emu kill`.

### Foreground app actions

- Offer a compact **Foreground App Actions** menu for every usable device from
  the main window and menu bar.
- Resolve the foreground package from the device when an action begins; do not
  require a persistent package selection or an Android Studio project.
- Support start, kill, restart, clear app data, and clear app data and restart.
- Require a native confirmation that names the resolved package before
  uninstalling it.
- Keep all ADB invocation in a typed service using fixed argument arrays.

### Device settings

- Offer a compact per-device **Device Settings** menu from both the main window
  and menu bar utility.
- Support explicit Dark Theme and Light Theme actions, Gesture and 3-Button
  navigation, and developer rendering overlays for layout bounds and GPU
  rendering bars.
- Keep rendering overlays reversible with separate Show and Hide actions.
- Use fixed ADB arguments and show an actionable failure when a device or OEM
  does not permit one of the Android setting writes.

### Deep-link launcher

- Offer a compact **Open Link** sheet from the main-window toolbar and menu
  bar utility.
- Let developers paste an absolute URI, select any usable device, and
  optionally target a package such as `com.android.chrome`.
- Launch the URI through Android's `ACTION_VIEW` intent using fixed ADB
  arguments. Leave the target package blank to use Android's normal intent
  resolution.

### Local MCP access

- Provide a local stdio MCP server for agents that need the completed device,
  emulator, screenshot, and recording actions without automating the macOS UI.
- Expose discovery before actions, and require an explicit ADB serial for every
  device-targeting action.
- Reuse the app's configured shared media folder and recording defaults.
- Keep the first server local-only. Do not add HTTP, SSE, or a network listener.
- Allow Quick Boot and Cold Boot AVD launch plus stopping by serial. Do not
  expose destructive wipe-data startup through MCP.

## Initial acceptance flow

1. Launch ADBuddy.
2. See its menu bar item.
3. Connect one or more Android devices or launch an emulator.
4. See device state refresh in the menu and main window.
5. Choose **Take Screenshot** for a usable device.
6. Receive a valid PNG promptly in `~/Screenshots`.
7. Repeat without Android Studio running.

## Explicitly deferred work

Do not create placeholder interfaces or implementation for these until their
respective preceding slices are complete:

- AVD creation, configuration, and snapshot management;
- Logcat implementation, whose first standalone window target is specified in
  [`logcat.md`](logcat.md);
- in-app automatic updates.

The source structure should accommodate later phases without prebuilding their
features or abstractions.
