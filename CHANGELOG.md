# Changelog

## [0.3.0] - 2026-10-10

ADBuddy added emulator creation and safe deletion, showed emulator disk usage, and made device controls and Settings clearer. Emulator creation and deletion used the bundled helper and required a separately installed Node.js 24 or newer.

### macOS App

- **Added:** Created Android emulators in a native window with hardware and system-image choices, suggested names, configurable storage capacity, and separate **Create** and **Create & Start** actions. Installed images remained available when the online catalog failed, and creation did not accept SDK licenses automatically.
- **Added:** Deleted stopped emulators after a confirmation naming the device, while retaining shared SDK system images and checking that the emulator had not started before deletion.
- **Added:** Toggled each connected device's dark theme from its row or the menu bar.
- **Added:** Showed allocated disk usage in GiB beside Android version details for stopped and running emulators. Measurements included AVD files and snapshots, excluded shared SDK images, and refreshed in the background about every 30 seconds.
- **Added:** Guided Node.js installation and provided retry controls when the runtime was missing, unusable, or older than version 24.
- **Added:** Included an About tab with the app version, source link, credits, and Android automation information.
- **Changed:** Bundled the pinned `@androperator/emulator` 0.2.0 helper for creation and deletion. Node.js 24+ remained an external prerequisite; Settings showed the active helper and runtime paths and supported explicit overrides.
- **Changed:** Put Node.js setup first in Emulator settings, with Java, custom helper paths, and diagnostics under Advanced.
- **Changed:** Grouped severity color controls in the renamed Logcat settings tab and placed **Install APK** before **Create Emulator** and **Settings** in the main toolbar.
- **Fixed:** Rendered toolbar icons clearly at launch and kept the toolbar separator and device-section dividers visible and consistent.
- **Fixed:** Showed APK installation as clearly disabled, with an explanatory tooltip, when no usable device was connected.
- **Fixed:** Avoided automatically focusing a Settings tab when the window opened, while preserving keyboard Tab navigation.

### Documentation

- **Added:** Documented emulator creation, hardware filtering, catalog loading, storage configuration, safe deletion, and their validation steps.
- **Added:** Documented automatic macOS unit-test checks for pull requests and updates to the main branch.
- **Added:** Documented release-note authoring and a release workflow that resumed from verified completed stages without replacing tags or uploaded assets.
- **Added:** Documented emulator disk-usage measurements and their exclusions.
- **Changed:** Updated device-setting documentation for the inline dark-theme toggle.
- **Changed:** Documented the pinned emulator helper, external Node.js prerequisite, runtime discovery, override behavior, and packaging provenance.
- **Changed:** Updated the product scope for Node.js installation guidance and retry controls.
- **Changed:** Updated Settings documentation for the About tab and the dedicated Logcat tab.

Pull requests:
- [feat: add inline device dark theme toggle](https://github.com/androperator/adbuddy/pull/1)
- [feat(emulators): add creation and safe deletion workflows](https://github.com/androperator/adbuddy/pull/2)
- [ci(tests): run macOS tests on every pull request](https://github.com/androperator/adbuddy/pull/3)
- [feat(emulators): bundle pinned helper with external Node support](https://github.com/androperator/adbuddy/pull/4)
- [feat(release): add authored notes and resumable publication](https://github.com/androperator/adbuddy/pull/5)
- [feat(emulators): guide Node.js setup and clarify settings](https://github.com/androperator/adbuddy/pull/6)
- [fix(ui): stabilize main toolbar and section dividers](https://github.com/androperator/adbuddy/pull/7)
- [feat(settings): add About tab and avoid automatic keyboard focus](https://github.com/androperator/adbuddy/pull/8)
- [fix(ui): clarify APK availability and group Logcat settings](https://github.com/androperator/adbuddy/pull/9)
- [feat(emulators): show disk usage beside Android version](https://github.com/androperator/adbuddy/pull/10)
