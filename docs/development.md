# Development workflow

## Development model

ADBuddy uses SwiftPM and a shell-first macOS development loop. The GUI
binary must be packaged and launched as an `.app` bundle, not only run as a raw
SwiftPM executable, so local testing reflects normal macOS activation and
bundle behavior.

The project includes:

```text
scripts/build_and_run.sh
scripts/package_release.sh
VERSION
.codex/environments/environment.toml
```

`scripts/build_and_run.sh` stops a prior local app instance, builds the project,
packages and ad-hoc signs the `.app`, launches it, and reports the app location
or failure. The local signature binds the bundle identity for services such as
macOS user notifications; it is not a substitute for the Developer ID signing
required for release.

`scripts/package_release.sh` is a separate release-only command. It builds
universal release binaries, signs them with the configured Developer ID
identity, and notarizes a versioned ZIP archive. It reads the release version
from the repository's `VERSION` file and never launches the app.

Both packaging scripts use `VERSION` when writing the app bundle's version
metadata, so local and release app bundles report the same version.

## Local prerequisites

- macOS 14 or newer;
- Xcode command-line tools and a selected Xcode installation;
- Swift toolchain compatible with the package manifest;
- Android SDK with `platform-tools/adb` for live-device checks.

The app must still locate ADB successfully when launched outside an interactive
shell, where common shell initialization and `PATH` entries may be absent.

## Validation loop

Run the smallest relevant check after each coherent change:

```sh
swift build
swift test
scripts/build_and_run.sh
```

Once the script exists, prefer it for end-to-end local launches. Do not claim
that live screenshot capture was verified unless an actual connected device or
emulator produced a valid PNG.

For runtime diagnostics, use unified logging with an app subsystem and inspect
only the targeted messages. Add logs around SDK resolution, device refresh,
process failures, menu actions, and screenshot outcomes.

## Testing boundaries

Unit tests should cover deterministic code and use fake process runners for
service behavior. They must not require a real Android SDK or device.

Manual verification should cover, where locally available:

1. SDK found through each supported discovery path;
2. no-device and non-usable-device UI states;
3. a physical device or emulator becoming visible after a refresh;
4. direct screenshot capture creating a valid PNG;
5. a successful screenshot notification offering **Reveal in Finder**;
6. automatic clipboard copy when that preference is enabled;
7. a failed ADB invocation presenting an actionable error.
8. a screen recording with each selected option reaching the same media folder
   as screenshots, followed by a successful Stop Recording action;
9. a successful recording notification offering **Reveal in Finder**;
10. Show taps returning to its original Android setting after recording.
11. Installed AVDs appearing in the **Android Emulators** section with correct
    stopped or running status.
12. Quick Boot and Cold Boot opening an AVD in the Android Emulator's own
    standalone window, with its ADB serial shown after discovery.
13. A running AVD stopping through its control. Exercise **Wipe Data and
    Start** only as far as its confirmation in routine manual testing; do not
    erase a developer's AVD unless that reset is intentional.
14. Each foreground-app action resolves the active package on the selected
    device, shows success or actionable failure feedback, and uses the resolved
    package in the uninstall confirmation. Do not confirm an uninstall during
    routine verification unless that removal is intentional.
15. Open the Link sheet, select a usable device, and launch a URI. Verify an
    optional package target such as `com.android.chrome` receives
    `https://techmeme.com` when Chrome is installed on the selected device.
16. On an emulator, apply each Device Settings action, check the corresponding
    Android system value, then restore light mode, gesture navigation, and
    disabled rendering overlays. Do not change a physical device's system
    settings during routine verification unless that is intentional.
17. Check a standalone emulator displays **Open Emulator Window** and brings
    that window to the front. Check Android Studio-managed and headless
    emulators clearly state that no standalone window can be opened.

## Change discipline

- Keep platform process work in services, not views.
- Preserve unrelated work in a dirty worktree.
- Run `git status --short` before staging and stage files explicitly.
- Use a Conventional Commit message for each coherent completed change.
- Do not push, tag, create a GitHub release, notarize, or update a Homebrew tap
  unless explicitly requested.
