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
