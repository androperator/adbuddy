# Development workflow

## Development model

ADBuddy will use SwiftPM and a shell-first macOS development loop. The GUI
binary must be packaged and launched as an `.app` bundle, not only run as a raw
SwiftPM executable, so local testing reflects normal macOS activation and
bundle behavior.

The initial scaffold will add:

```text
script/build_and_run.sh
.codex/environments/environment.toml
```

`script/build_and_run.sh` will stop a prior local app instance, build the
project, package the `.app`, launch it, and report the app location or failure.

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
script/build_and_run.sh
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
5. a failed ADB invocation presenting an actionable error.

## Change discipline

- Keep platform process work in services, not views.
- Preserve unrelated work in a dirty worktree.
- Run `git status --short` before staging and stage files explicitly.
- Use a Conventional Commit message for each coherent completed change.
- Do not push, tag, create a GitHub release, notarize, or update a Homebrew tap
  unless explicitly requested.
