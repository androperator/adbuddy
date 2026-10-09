# Development

## Setup

- macOS 14 or newer;
- Xcode, its command-line tools, and a Swift toolchain compatible with
  `Package.swift`;
- CMake, pkg-config, Python 3, and network access for the first bundled recorder
  build; see [recording-backend.md](recording-backend.md);
- an Android SDK containing `platform-tools/adb` for live-device checks.

The local scripts use the selected Xcode installation. If Xcode setup is
incomplete, they can use separately installed Command Line Tools with the
macOS 26.5 SDK. Full Xcode must still be installed for the XCTest frameworks
and runner. The scripts do not accept Xcode licenses or change the system's
developer-directory selection. Release builds require fully configured Xcode.

## Build and run

From the repository root:

```sh
scripts/build_and_run.sh
```

This stops the previous local app instance, builds the SwiftPM package, packages
and ad-hoc signs `dist/ADBuddy.app`, and launches it. Use the packaged app for
GUI testing so bundle identity and macOS activation match normal app usage.
The bundle version comes from `VERSION`.

For a launch smoke check:

```sh
scripts/build_and_run.sh --verify
```

This performs the same build and launch, then checks that the app process is
running after one second. It does not verify UI behavior or device operations.
For public signing, notarization, and packaging, see [release.md](release.md).

## Tests

Run the suite or select relevant test classes:

```sh
scripts/test.sh
scripts/test.sh ADBuddyTests.AndroidVirtualDeviceDetailsServiceTests,ADBuddyTests.AndroidEmulatorServiceTests
```

The script builds the tests and invokes XCTest directly. With fully configured
Xcode, ordinary `swift build` and `swift test` are also available. Unit tests use
fake process runners and do not require an Android SDK or connected device;
passing them does not prove live ADB behavior.

### Pull request checks

[The Tests workflow](../.github/workflows/tests.yml) runs the complete unit suite
on every pull request update and on pushes to `main`. It uses a standard
`macos-26` runner with Xcode 26.6 and invokes `scripts/test.sh`. The stable
check name is `macOS tests`; GitHub branch protection requires this check to
pass before merging into `main`. New commits cancel superseded test runs.

These checks compile the app, core library, and MCP helper, but do not package
or launch the app, build the bundled recorder, or verify live Android behavior.
No signing credentials or connected devices are required.

Manual checks live with the features they verify:

- [Product workflows](product-scope.md#manual-verification): discovery,
  screenshots, emulators, app actions, installation, and Settings.
- [Recording](recording-backend.md#manual-verification): options, rotation,
  fold transitions, saved clips, and Show taps restoration.
- [Logcat](logcat.md#verification): streaming, filtering, inspection, and layout.
- [MCP](mcp.md#verification): protocol smoke checks and agent media capture.

## Debugging

Each mode rebuilds and packages the app before starting:

| Command | Purpose |
| --- | --- |
| `scripts/build_and_run.sh --debug` | Run the packaged executable under LLDB. |
| `scripts/build_and_run.sh --logs` | Launch and stream logs for the ADBuddy process. |
| `scripts/build_and_run.sh --telemetry` | Launch and stream logs for the `com.clawperator.adbuddy` subsystem. |

Contribution and agent workflow rules are in [AGENTS.md](../AGENTS.md).

## Emulator creation prototype

Build the sibling `../emulator` project (`npm ci` and `npm run build`) on its
catalog-capable branch before using **Create Emulator**. The published 0.1.1
package does not include these catalogs. Development app bundles in `dist` find
that checkout automatically. Settings → Emulators accepts a package directory
or CLI path, Node executable, and Java home for explicit selection. Node 24+,
SDK command-line tools and an SDK-compatible Java runtime are required.

Run focused checks with:

```sh
scripts/test.sh ADBuddyTests.EmulatorCreationTests,ADBuddyTests.AppPreferencesTests,ADBuddyTests.AndroidEmulatorServiceTests
```

In the packaged app, open **Create Emulator**, choose an installed phone or TV
image, enter a unique disposable name and storage capacity, and create. Verify
success and list refresh. Verify Create leaves the emulator stopped and Create & Start
launches it after successful creation. Check duplicate-name and
invalid-capacity feedback. Verify automatic downloadable catalog loading, offline fallback to installed images, retry, and installed state
and device-family/ABI selection. A missing image may be downloaded on creation;
licenses must already be accepted. Do not accept licenses or remove an existing
user AVD as part of routine testing. Verify missing/unbuilt helper and outdated
capability errors with explicit path overrides, then restore the previous values.

Use the helper to clean up only the disposable AVD created for validation after
stopping it. Record actual boot/storage results separately from configured size.
Native helper cancellation and snapshot-free allocation remain outside this
prototype. Stopped AVD menus support confirmed deletion through the helper.

Draft validation on Apple Silicon (2026-10-04, before integration onto current main):

- Packaged app built and launched with `scripts/build_and_run.sh --verify`.
- 32 focused creation, preferences, emulator-service and emulator-store tests passed.
- Native UI created disposable TV API 36 and Pixel phone API 35 AVDs from installed
  images. Both launched as standalone emulators and reported `sys.boot_completed=1`.
- Confirmed duplicate-name protection, remote catalog loading, installed/download
  labels, and the new AVD's Starting state. Existing running devices stayed available.
- The TV image reported about 5.8 GB on `/data` with a requested 4 GB configuration;
  configured storage must not be presented as guaranteed actual capacity.
- Stopped and deleted only the two disposable AVDs after verification. No image
  packages or existing user AVDs were removed.
- Missing-image installation, license failures, Intel execution, and nonstandard
  runtime installations have not been live-verified by this prototype pass.

Stopped-emulator deletion checks: inspect the action/context menus and cancel the
named confirmation on existing AVDs. Use only a disposable AVD for a confirmed
deletion; verify disappearance, shared-image retention, and a visible error when
the helper refuses deletion. State changes before confirmation must prevent it.

Integration validation (2026-10-10):

- Reapplied the creation, hardware filtering, and stopped-emulator deletion flows
  from `avd-management-draft` onto a fresh `avd-management` branch from `main`.
- Packaged build and launch smoke check passed, along with 25 focused creation,
  preferences, and emulator-store tests.
- Confirmed the main window exposes Create Emulator alongside the newer device
  controls. Automated UI interaction was unavailable for completing the sheet
  checks in this pass; no AVD was created or deleted during integration.
- The earlier live creation results above belong to the draft validation.
