# Product scope

## Product intent

ADBuddy is a native macOS utility for Android developers who need quick access
to Android SDK and ADB capabilities without launching Android Studio. It should
feel fast, small, reliable, and obvious.

The app is not an Android Studio replacement. It should remain a focused tool
for a small number of high-value workflows.

## Supported workflows

The following capabilities are implemented. These requirements describe the
current product contract; they are not an outstanding implementation plan.

### Device discovery and app surfaces

- Build and launch a native macOS app.
- Provide both a `MenuBarExtra` and a conventional app window.
- Allow the menu bar utility to open and activate the main window.
- Locate a usable Android SDK and ADB executable.
- Refresh connected devices automatically once per second.
- Represent device serial, display name, connection state, and physical or
  emulator kind as typed data.
- Display each available device's Android version and API level as
  `Android {version} / API {apiLevel}`. Read connected-device values from
  the device and stopped AVD values from their configured system images.
- Show clear UI states for a missing SDK, missing ADB, no devices,
  unauthorized devices, offline devices, and usable devices.

### Screenshots and shared media

- Offer **Take Screenshot** for each usable connected device from the menu bar
  and basic main window.
- Capture binary PNG data with:

  ```text
  adb -s <serial> exec-out screencap -p
  ```

- Write a valid local PNG to the configured screenshot directory.
- Default the directory to `~/Screenshots` and use a safe timestamped filename,
  for example `Pixel-9-Pro_2026-08-22_121530_123.png`.
- Use a running emulator's configured AVD name, rather than its Android system
  image model, as the user-facing prefix for saved screenshots and recordings.
  If the AVD name cannot be resolved, retain the parsed device name.
- Offer a Settings preference to add a device frame to screenshots. For an
  emulator, use the matching Android SDK skin configured by its AVD when one
  is available; otherwise use a generic black frame. The preference can also
  retain the original screenshot alongside its `_framed.png` version.
- Offer an opt-in Settings preference to overlay the captured device's Android
  version and API level in the top-left corner of saved screenshots and framed
  recordings.
- Offer an opt-in Settings preference to also save a 50%-size PNG copy of the
  final screenshot. It must use the same one-device capture and preserve any
  optional frame and device-details label.
- Report a concise native success state and a useful failure if capture fails.
- All app notifications must be silent.
- Deliver a native system notification for a successful capture, including a
  preview of the saved PNG and a **Reveal in Finder** action.
- Copy successful screenshots and saved MP4 recordings to the clipboard as file
  URLs by default, so clipboard managers can reveal the saved media. This
  behavior is a persisted preference exposed by the app's Settings window.
- Optionally reveal each saved screenshot and MP4 recording in Finder through a
  persisted Settings preference.
- Let users choose the shared media destination from the Settings window. The
  selected folder is used for both screenshots and recordings.

### Device mirroring

- Offer **Mirror Device** for each usable connected physical device from the
  main-window controls, contextual menu, and menu bar. Place its row button in
  the rightmost slot used by **Stop Emulator** on emulator rows, and hide
  mirroring actions for emulators. Double-clicking a physical device
  also opens its mirror; emulator double-clicks retain their host-window action.
- Open a standalone scrcpy window titled with the device's friendly name, with
  keyboard and mouse control enabled and audio disabled.
- Keep one mirror session per device. Reopening an active mirror brings its
  window forward. Multiple devices may be mirrored independently.
- Disable automatic clipboard synchronization. Explicit scrcpy paste shortcuts
  remain available.
- Closing a mirror ends that session. Quitting ADBuddy stops its mirror sessions.
  Report launch and device-disconnection failures with a native alert.
- Use the bundled helper and resolved Android SDK ADB; no separate scrcpy
  installation is required. Mirroring does not start or replace screen recording.

### Screen recording

- Offer **Record Screen** for each usable connected device from the menu bar
  and main window.
- Present native controls for the requested recording options:
  - bit rate in Mbps, defaulting to 8 Mbps;
  - resolution as 100%, 75%, 50%, or 25% of physical display size, defaulting
    to 100%;
  - Show taps, defaulting to disabled.
- Capture through a bundled headless recorder with fixed arguments, passing a
  bit rate and scaled size when selected. Keep one video in the device's natural
  orientation, allowing content to rotate inside it at full display size.
- Keep one recording session across fold transitions. When the encoded display
  dimensions change, finish the current MP4 and begin the next at a keyframe.
  Ordinary rotation within the locked capture canvas does not split a clip.
- Name multi-clip sessions with one shared timestamp and ordered `_01`, `_02`
  suffixes. A session without a dimension change keeps its ordinary filename.
- Limit each recording session to three minutes.
- Stop the selected recording with a targeted interrupt and finalize its local
  MP4 clips. Preserve completed clips if recording fails later.
- Save MP4s into the same configured destination as screenshots. Do not create
  a separate recording directory or a per-recording destination picker.
- Offer an opt-in Settings preference to add a device frame to saved screen
  recordings. For an emulator, use its configured Android SDK skin when it is
  available and compatible; otherwise use a generic black device frame. Keep
  the original MP4 and save the processed recording as a collision-safe
  `_framed.mp4` sibling.
- Deliver one silent success notification when the recording session finishes,
  including the clip count when split, a first-frame preview, and a **Reveal in
  Finder** action that selects all primary clips. Copy all primary clips together
  when clipboard copying is enabled. Frame each clip using its own dimensions.
- When Show taps is enabled, preserve the existing Android setting and restore
  it when the recording finishes.

### Emulator management

- Offer **Delete Emulator…** in stopped-AVD action and contextual menus. Confirm
  the named AVD's permanent data loss, retain shared system images, and refuse
  deletion if its state changes before confirmation. Use the optional helper's
  live running-device checks; disable launch while deletion is in progress and
  show deletion failures in a native alert.
- Offer a prototype **Create Android Emulator** window from the main-window toolbar.
  Use the optional separately installed `@androperator/emulator` helper with
  catalog capabilities; Node is not bundled. Settings provides helper, Node,
  and Java path overrides. Packaged development builds prefer a built sibling
  emulator checkout.
- Select a hardware type first (Phone, Tablet, Foldable, TV, Automotive, Wear OS,
  Desktop, XR, Glasses, or Other), then a profile from that type and a matching
  native-architecture image. Only types present in the SDK catalog are shown.
  Load installed images first and automatically fetch downloadable choices. Keep
  installed images available if the remote catalog fails, with a retry action.
  Mark installed choices with a drive icon and remote choices with a download icon. Reserve the native checkmark for the selected image; creation downloads the selected image.
- Require a unique name and internal-storage capacity, defaulting to 24 GB.
  Never replace existing AVDs or accept SDK licenses automatically. Report
  prerequisite and license failures visibly. Offer **Cancel** and **Create** actions. Creation leaves the new emulator
  stopped; start it separately from the emulator list.
- Initial loading replaces the form with a centered progress indicator while preserving
  window size. Its native red close button and Escape dismiss it except during
  creation. Cancel and Create remain hidden until local options are ready;
  Escape remains available during loading. Errors restore the controls for recovery. Downloadable images then load quietly without disabling the form or
  creation with an installed image. Creation progress, validation, and retry controls
  share a fixed-height area at the bottom left. Technical errors open in a popover without resizing
  the sheet. Image availability is shown by picker icons, with spoken status for accessibility.
  Dismissal is disabled during creation; cancellation and byte-level download progress are deferred.
  Configured capacity is not a host-disk quota, guaranteed guest capacity, or
  existing-userdata resizing. Dynamic allocation and snapshot policy use SDK defaults.

- Show all connected Android devices, physical and emulator, together in the
  compact main-window list. A connected emulator is shown once, with its AVD
  name, ADB serial, stop control, and device actions.
- Identify whether a connected emulator has a standalone macOS window, is
  displayed through Android Studio, or is headless. Double-clicking a connected
  emulator reveals its standalone Emulator window or its Android Studio host
  window when available.
- Offer a contextual menu for each connected device that copies its ADB device
  ID. For a connected emulator matched to an AVD, also offer **Reveal in
  Finder** for its local AVD data directory.
- Offer **Reveal in Finder** from the contextual menu of every displayed
  installed AVD, including stopped and transitional emulators.
- Show every installed AVD and whether it is stopped, starting, running, or
  stopping. To avoid duplicate rows, a running AVD is represented by its
  connected Android device row; the installed-emulators section keeps stopped
  and transitional AVDs.
- Let users start a stopped AVD with Quick Boot through its Start control or by
  double-clicking its row, use Cold Boot from its action menu, or stop a
  running AVD.
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

### Device information

- Show both internal displays for connected foldables, with separate physical
  pixel and default logical sizes for the larger inner and smaller outer screen.
  Refresh device information when its popover opens. If Android does not expose
  multiple internal displays, retain the default-screen information.

### Device settings

- Offer a gear button beside the connected-device information button to open
  Android system Settings on that device. Disable it while the device is unavailable
  or a device-setting action is running.

- Offer a compact per-device **Device Settings** menu from both the main window
  and menu bar utility.
- Offer an inline **Toggle Dark Theme** button for each connected device and a
  matching menu bar action. Read the effective theme on each click and switch
  to the opposite theme, including when Android uses an automatic schedule.
- Support Gesture and 3-Button navigation, and developer rendering overlays
  for layout bounds and GPU rendering bars in the Device Settings menu.
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

### Local APK installation

- Offer **Install APK** from the main-window toolbar and menu bar utility.
- Accept a local `.apk` file dropped onto a usable connected-device row.
- Register APK documents so Finder can offer **Open With ADBuddy** without
  taking over the user's preferred default application.
- Present one native install sheet that lets users select one or more usable
  devices and optionally open the app after installation.
- Install each selected device with `adb -s <serial> install -r <path>` using
  a fixed argument array. Do not allow downgrades or uninstall existing apps
  implicitly.
- For optional opening, read the APK's package and launcher activity through
  the newest available Android SDK `aapt2`, then use an explicit ADB activity
  launch. A missing `aapt2` or non-launchable APK must not turn a successful
  installation into a failure.
- Installation supports one ordinary APK at a time. Defer split APKs,
  `.apks` archives, and Android App Bundles until their install behavior can be
  presented clearly.

### Local MCP access

- Provide a local stdio MCP server for agents that need the completed device,
  emulator, screenshot, and recording actions without automating the macOS UI.
- Expose discovery before actions. Require an ADB serial for screenshots,
  recording start, and emulator stop; use an AVD name for emulator start and
  the returned recording ID for recording stop.
- Reuse the app's configured shared media folder and recording defaults.
- Keep the server local-only. Do not add HTTP, SSE, or a network listener.
- Allow Quick Boot and Cold Boot AVD launch plus stopping by serial. Do not
  expose destructive wipe-data startup through MCP.

### Logcat

- Open one native streaming Logcat window per device, with recent history,
  application and minimum-level filters, text search, and crash filtering.
- Support pause, follow, clear, copy, optional columns, and message wrapping.
- Retain at most 50,000 entries per window and reconnect after a device returns.
- Persist shared table layout and severity colors; keep filters and retained
  logs local to each window session.
- See [`logcat.md`](logcat.md) for the complete behavior and validation contract.

## Screenshot acceptance flow

1. Launch ADBuddy.
2. See its menu bar item with the default settings.
3. Connect one or more Android devices or launch an emulator.
4. See device state refresh in the menu and main window.
5. Choose **Take Screenshot** for a usable device.
6. Receive a valid PNG promptly in the configured folder (`~/Screenshots` by
   default).
7. Repeat without Android Studio running.

## Manual verification

Use a local device or emulator where available. Run checks relevant to the
changed behavior and record which device-dependent checks were performed.
Check SDK discovery when launching outside an interactive shell as well.

### Discovery and screenshots

- SDK found through each supported discovery path;
- no-device and non-usable-device UI states;
- a physical device or emulator becoming visible after a refresh;
- direct screenshot capture creating a valid PNG;
- a successful screenshot notification offering **Reveal in Finder**;
- automatic clipboard copy for successful screenshots and recordings when
  that preference is enabled;
- automatic Finder reveal for successful screenshots and recordings when that
  preference is enabled;
- a failed ADB invocation presenting an actionable error.

### Emulator lifecycle and windows

- Stopped and transitional AVDs appearing in **Android Emulators**, with
  running AVDs represented once in **Connected Android Devices**.
- Quick Boot and Cold Boot opening an AVD in the Android Emulator's own
  standalone window, with its ADB serial shown after discovery.
- A running AVD stopping through its control. Exercise **Wipe Data and
  Start** only as far as its confirmation in routine manual testing; do not
  erase a developer's AVD unless that reset is intentional.
- Double-click a connected standalone emulator to reveal its window. For
  an Android Studio-managed emulator, verify the Android Studio host opens.
  Headless or unidentified hosts must not offer a window-reveal action.
  Check device-ID copying and AVD-folder reveal from contextual menus.

### Device mirroring

- Open a mirror from the device row, contextual menu, and menu bar. Confirm
  keyboard and mouse input on a connected test device and no audio playback.
- Reopen the same device and verify its existing window is brought forward;
  mirror two devices and confirm each action selects the correct window.
- Close and reopen a mirror, disconnect a mirrored device, and quit ADBuddy
  with mirrors open. Confirm session cleanup and actionable disconnect feedback.
- Double-click a physical device to mirror it and an emulator to reveal its
  existing host window. Verify screenshots and recordings still work while
  mirroring, including orientation changes.

### App actions, links, and installation

- Each foreground-app action resolves the active package on the selected
  device, shows success or actionable failure feedback, and uses the resolved
  package in the uninstall confirmation. Do not confirm an uninstall during
  routine verification unless that removal is intentional.
- Open the Link sheet, select a usable device, and launch a URI. Verify an
  optional package target such as `com.android.chrome` receives
  `https://techmeme.com` when Chrome is installed on the selected device.
- On an emulator, apply each Device Settings action, check the corresponding
  Android system value, then restore light mode, gesture navigation, and
  disabled rendering overlays. Do not change a physical device's system
  settings during routine verification unless that is intentional.
- Choose **Install APK**, select a single APK and one or more usable devices,
  then verify each device reports its own installation outcome. If `aapt2` is
  available and the APK has a launcher activity, verify **Open after install**
  opens the installed app. Also drag an APK onto a usable device row and open
  the packaged app from Finder using **Open With ADBuddy**.

### Settings

- Check Settings tabs, shared media destination, framing, original retention,
  device-details overlay, half-size PNG output, menu bar visibility, and
  success-banner preferences. Relaunch to verify persistence.

Recording checks are in [recording-backend.md](recording-backend.md#manual-verification).
Use the dedicated [Logcat](logcat.md#verification) and [MCP](mcp.md#verification)
checks when changing those features.

## Outside the current scope

The following capabilities are not implemented. Add them only as deliberate
scope changes, without placeholder interfaces:

- Advanced AVD configuration, resizing, and snapshot management;
- saved Logcat filter presets, log export, advanced field or regex filters,
  device-buffer mutation, and multiple Logcat tabs per window;
- split APKs, `.apks` archives, and Android App Bundles;
- in-app automatic updates.

Keep the source structure focused on implemented behavior rather than
prebuilding abstractions for these possible extensions.
