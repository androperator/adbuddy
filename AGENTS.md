# ADBuddy Agent Guide

## Mission

ADBuddy is a small, fast, native macOS utility for Android developers. It
replaces a few frequent Android Studio tasks when Android Studio does not need
to be open.

The first implementation milestone is intentionally narrow:

1. discover Android devices through ADB;
2. show their usable and failure states in a menu bar utility and main window;
3. capture a valid PNG screenshot from a selected usable device.

Do not implement screen recording, emulator management, or Logcat before the
Phase 0 and Phase 1 vertical slice is complete.

Read these documents before changing product behavior:

- `docs/product-scope.md`
- `docs/architecture.md`
- `docs/development.md`
- `docs/release.md`

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
  new dependency has a compelling, documented reason.
- This is a non-Mac-App-Store app. App Sandbox is not an initial requirement
  because the app must locate and run the user's Android SDK tools.

## Android SDK and ADB rules

- UI code must never construct or execute shell commands.
- Send an executable URL/path and a `[String]` argument array through one
  process-running service. Never concatenate a shell command string.
- Capture stdout, stderr, exit status, duration, and useful failure context.
  Support cancellation for operations that will become long-running.
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

- The default screenshot destination is `~/Screenshots` (currently
  `/Users/chrislacy/Screenshots`). Create the directory on demand if possible.
- Persist simple user preferences through a small `AppPreferences` store backed
  by `UserDefaults`. The initial preference is the screenshot destination.
- Keep preference access out of feature views. Settings UI can arrive later
  without changing the services that consume a destination URL.
- Do not use the Keychain for ordinary non-secret preferences.
- Use safe, sanitized screenshot filenames containing a device name and
  timestamp. Never overwrite an existing capture silently.

## Code organization

Start non-trivial code in focused files and directories:

```text
App/          app entry point and scene declarations
Views/        SwiftUI presentation only
Models/       device and result value types
Stores/       app and UI state, including polling ownership
Services/     SDK discovery, process execution, ADB, screenshots
Support/      formatters, file helpers, logging glue
Tests/        parser, resolver, filename, and service tests
```

Keep scene state, application state, and service state distinct. Favor small
concrete types over protocol-heavy abstractions.

## Validation and commits

- Add focused tests for parsers, SDK discovery precedence, filename generation,
  and non-UI service behavior.
- Test with live ADB only when the local environment permits it; state clearly
  what a device-dependent verification did or did not prove.
- Build and run the app through `script/build_and_run.sh` once it exists. Use
  the smallest relevant `swift test` scope before claiming a change complete.
- Add targeted `Logger` events for app launch, SDK discovery, device refresh,
  ADB failures, and major menu actions.
- Keep commits narrow, use Conventional Commit messages, inspect `git status`
  before staging, and never stage unrelated local files.
- Do not push or publish releases unless the user explicitly asks.
