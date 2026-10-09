# Development

## Setup

- macOS 14 or newer;
- Xcode, its command-line tools, and a Swift toolchain compatible with
  `Package.swift`;
- CMake, pkg-config, Python 3, and network access for the first bundled recorder
  build; see [recording-backend.md](recording-backend.md);
- an Android SDK containing `platform-tools/adb` for live-device checks;
- externally installed Node.js 24+ for emulator creation and deletion.

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

Normal packaged launches use the pinned catalog-capable helper inside ADBuddy.
The helper version, URL and checksum are defined in
[the root dependency manifest](../bundled-dependencies.json), which is copied
into the app. No global helper installation is required. Node.js 24+ must be
installed separately for creation and deletion. See
[the bundle pin and rebuild instructions](../vendor/emulator/README.md).

For local helper development, build the checkout explicitly (`npm ci` and
`npm run build`), then set **Settings → Emulators → Package folder or CLI**
to that checkout's absolute path or compiled `dist/cli.js`. Blank selects the
bundled helper. The Node executable override is independent; blank discovers
installed Node through PATH, Homebrew, Volta and nvm locations. Node 24+ is required. Invalid paths,
wrong package identity, protocol mismatch, or missing catalog capabilities fail
visibly without fallback. Settings displays the checked active version and both
paths. Reopen Create Emulator after changing settings. Nearby checkouts and
global helper installations are never selected automatically.

Android SDK tools, images, accepted licenses and SDK-compatible Java remain
external. Existing SDK, Android user home, AVD home and Java discovery apply.
Packaging does not download or include Node, build or read the sibling helper
checkout. SDK tools, images and Java remain external. The rest of ADBuddy does
not require Node; creation and deletion show actionable errors when it is absent
or incompatible. A dedicated Node setup UI is deferred.

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

Safe bundled-runtime verification (no SDK calls or AVD mutations):

```sh
scripts/build_and_run.sh --verify
ADBUDDY_EMULATOR_TEST_BUNDLE="$PWD/dist/ADBuddy.app" \
ADBUDDY_EMULATOR_TEST_NODE="$(command -v node)" \
  scripts/test.sh ADBuddyTests.EmulatorCreationTests
```

The runtime test uses a restricted PATH, the packaged helper with an explicitly selected external Node, a copied
local package override, and disposable incompatible helper fixtures. It checks
version, protocol, package identity and capabilities. Resolver tests also prove
missing overrides and missing bundled components cannot fall back to a sibling.
The runtime test skips explicitly when a bundle or external Node path is not supplied.

External Node validation (2026-10-10):

- The app packages only the pinned emulator helper, manifest and license notices.
  Node downloads, binaries and signing entitlements are removed.
- Isolated tests cover external Node discovery, explicit overrides, old runtimes,
  helper protocol/capabilities and absence of Node in the packaged app.
- No SDK licenses or user emulators are changed by these checks. Native Intel,
  macOS 14 runtime and Developer ID notarization remain unverified.
