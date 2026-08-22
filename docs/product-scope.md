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

## Initial acceptance flow

1. Launch ADBuddy.
2. See its menu bar item.
3. Connect one or more Android devices or launch an emulator.
4. See device state refresh in the menu and main window.
5. Choose **Take Screenshot** for a usable device.
6. Receive a valid PNG promptly in `~/Screenshots`.
7. Repeat without Android Studio running.

## Explicitly deferred work

Do not create placeholder interfaces or implementation for these until the
screenshot slice is complete:

- screen recording and resolution scaling;
- installed AVD listing and emulator launch or stop controls;
- Logcat streaming, filters, search, pause, and export;
- configurable screenshot directory UI;
- copy-to-clipboard and Reveal in Finder enhancements;
- in-app automatic updates.

The source structure should accommodate later phases without prebuilding their
features or abstractions.
