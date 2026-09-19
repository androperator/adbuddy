# ADBuddy Agent Guide

## Mission

ADBuddy is a small, fast, native macOS utility for Android developers. It
replaces a few frequent Android Studio tasks when Android Studio does not need
to be open.

The app implements device discovery, screenshots, screen recording, emulator
lifecycle controls, app actions, APK installation, deep links, device settings,
and per-device Logcat windows. A bundled stdio MCP server exposes discovery,
emulator controls, and media capture to agents. Preserve these working flows
and consult the scope document before adding new features.

Read these documents before changing product behavior:

- `docs/product-scope.md`
- `docs/architecture.md`
- `docs/development.md`
- `docs/release.md`

Read `docs/logcat.md` before planning or changing Logcat behavior.

## Product and platform decisions

- Use Swift, SwiftUI, and macOS-native APIs. Target macOS 14 or newer.
- Keep the project package-first with SwiftPM and package the GUI executable as
  a normal `.app` bundle for local runs and releases.
- Model the main window and `MenuBarExtra` as separate SwiftUI scenes that
  share application state. Do not turn one view hierarchy into both surfaces.
- Prefer standard macOS menus, toolbars, settings, materials, keyboard paths,
  and controls. Use AppKit only for a specific behavior SwiftUI cannot express
  cleanly.
- Keep dependencies to the Swift standard library and Apple frameworks unless a
  new dependency has a compelling, documented reason. The bundled scrcpy
  recorder and its native dependencies are documented in
  `docs/recording-backend.md`.
- This is a non-Mac-App-Store app. The app does not enable App Sandbox
  because the app must locate and run the user's Android SDK tools.

## Android SDK and ADB rules

- UI code must never construct or execute shell commands.
- Send an executable URL/path and a `[String]` argument array through
  the appropriate process-running service (`ProcessRunner` or
  `StreamingProcessRunner`). Never concatenate a shell command string.
- Capture stdout, stderr, exit status, duration, and useful failure context.
  Support cancellation for long-running operations.
- Resolve the Android SDK independently of the GUI application's `PATH`.
  Check `ANDROID_HOME`, `ANDROID_SDK_ROOT`, then the standard
  `~/Library/Android/sdk` location.
- Parse ADB output into typed models. Views must not consume raw
  `adb devices` text.
- Treat no devices, unauthorized devices, offline devices, missing SDK tools,
  and failed ADB invocations as visible states, not silent failures.
- Use direct binary PNG output for screenshots:
  `adb -s <serial> exec-out screencap -p`.

## Preferences and files

- Screenshots and recordings share a destination, defaulting to `~/Screenshots`.
  Create the directory on demand if possible.
- Persist simple user preferences through a small `AppPreferences` store backed
  by `UserDefaults`. Shared media and recording settings also serve the MCP
  helper through `ADBuddySharedPreferences`.
- Pass preferences through `AppPreferences`; views must not read `UserDefaults`
  directly. Services receive explicit option values. Settings owns global
  controls, and Logcat table preferences persist across windows and launches.
- Do not use the Keychain for ordinary non-secret preferences.
- Use safe, sanitized media filenames containing a device name and
  timestamp. Never overwrite an existing capture silently.

## Code organization

Start non-trivial code in focused files and directories:

```text
Sources/ADBuddyCore/  shared SDK, process, device, media, and preference services
Sources/ADBuddy/
  App/               app entry point and scene declarations
  Views/             SwiftUI presentation and narrow AppKit bridges
  Models/            GUI and Logcat value types
  Stores/            application and window state, including polling
  Services/          GUI integrations and Logcat streaming
  Support/           parsers, formatters, layout, and platform helpers
Sources/ADBuddyMCP/   stdio transport, tool contracts, and recording ownership
Tests/ADBuddyTests/  parser, resolver, preference, store, and service tests
```

Keep scene state, application state, and service state distinct. Favor small
concrete types over protocol-heavy abstractions.

## Validation and commits

- Add focused tests for parsers, SDK discovery precedence, filename generation,
  and non-UI service behavior. Use fake process runners; unit tests must not
  require a real Android SDK or device.
- Test with live ADB only when the local environment permits it; state clearly
  what a device-dependent verification did or did not prove.
- For code changes, build and run the app through `scripts/build_and_run.sh`
  and use the smallest relevant `scripts/test.sh` scope. See
  `docs/development.md` for selectors and toolchain requirements. Documentation
  changes require source, link, and consistency checks rather than app launches.
- Add targeted `Logger` events for app launch, SDK discovery, device refresh,
  ADB failures, and major menu actions.
- Keep commits narrow, use Conventional Commit messages, inspect `git status`
  before staging, and never stage unrelated local files.
- Preserve unrelated worktree changes.
- Do not push, tag, publish a release, notarize, or update a Homebrew tap unless
  the user explicitly asks.

## Documentation validation

For documentation-only changes, compare claims with the relevant source and
scripts, check local links, and run `git diff --check`. App builds and live
device actions are not needed unless a behavior claim requires runtime
verification. Check synchronized release examples with:

```sh
python3 .agents/skills/release-adbuddy/scripts/set_release_version.py "$(cat VERSION)" --check
```
