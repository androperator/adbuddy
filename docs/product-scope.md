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
- Refresh connected devices with a lightweight polling strategy.
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
  **Reveal in Finder** action.
- Copy successful PNG captures to the clipboard by default. This behavior is a
  persisted preference that the future Settings UI will expose.

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
- When Show taps is enabled, preserve the existing Android setting and restore
  it when the recording finishes.

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

- installed AVD listing and emulator launch or stop controls;
- Logcat streaming, filters, search, pause, and export;
- configurable screenshot directory UI;
- in-app automatic updates.

The source structure should accommodate later phases without prebuilding their
features or abstractions.
