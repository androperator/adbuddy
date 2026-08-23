# Logcat window target

## Purpose

ADBuddy should provide a focused native Logcat viewer for developers who need
to inspect a connected Android device without opening Android Studio. Logcat is
a dedicated per-device window, not another mode inside the compact main
window.

This document defines the target behavior for the first standalone Logcat
slice. It is a product and architecture contract plus an ordered implementation
plan. Complete the tasks below in order. Do not pull behavior from a later task
into an earlier one unless that behavior is required to keep the app compiling.

## Ordered implementation plan

Each task is a small milestone that should leave the app working. Finish its
tests and manual checks before starting the next task. Use one narrow
Conventional Commit for each completed task, and stage only the files changed
for that task.

For every task:

1. read the files named in the task before editing them;
2. add or update focused deterministic tests where the task has testable logic;
3. run the smallest relevant test first, then run `swift test`;
4. for a UI or process-lifecycle task, run
   `./scripts/build_and_run.sh --verify` and perform the listed manual checks;
5. inspect `git status --short` before staging;
6. do not continue while the task leaves a build or test failure.

### Task 1: Open one dedicated Logcat window per device

**Goal:** Add the window, entry points, and per-device window identity. This
task must not start ADB Logcat, parse messages, or show filter controls.

Likely files:

- new `Models/LogcatWindowID.swift`;
- new `Views/LogcatWindowView.swift`;
- `App/ADBuddyApp.swift`;
- `Views/ContentView.swift`;
- `Views/MenuBarContentView.swift`;
- a focused test file under `Tests/ADBuddyTests` if window identity contains
  deterministic logic.

Implement it in this order:

1. Add a small `Codable` and `Hashable` value whose only identity field is the
   device serial. For example, use `LogcatWindowID(serial: device.serial)`.
   Do not include the device display name in identity. A display name can
   change while the serial remains the same.
2. Add a value-based Logcat `WindowGroup` to `ADBuddyApp`. Use the serial-based
   value with `openWindow(value:)` so SwiftUI brings the matching window
   forward when that serial is already open.
3. Give the Logcat scene the existing `DeviceStore` environment. The scene
   must own any future Logcat state instead of adding it to `DeviceStore`.
4. Add a simple `LogcatWindowView`. Resolve the current device name from the
   serial when possible, show both name and serial, and use
   `Logcat - <device name>` as the window title. A compact empty state such as
   `Logcat is not connected yet` is enough for this task.
5. Give the window a useful default size and a minimum content size, while
   leaving it freely resizable above that minimum. The app already disables
   automatic window tabbing globally; preserve that behavior.
6. Add an **Open Logcat** glyph button to each usable device row. Put a short
   vertical divider between the screenshot and recording actions and the
   Logcat button. Add an accessibility label and Help text.
7. Add an **Open Logcat** item to each usable device submenu in the menu bar.
   The action should activate ADBuddy and open the serial-based window value.
8. Keep unavailable devices unchanged. They must not offer a Logcat action.

Acceptance checks:

- A usable device has an Open Logcat action in both the main window and menu
  bar.
- The first action opens a dedicated window for the selected serial.
- Triggering the action again for that serial focuses the existing window and
  does not create a duplicate.
- Two different device serials can have two Logcat windows open together.
- Each window shows the correct device name and serial.
- Closing one Logcat window does not close the main window or another device's
  Logcat window.
- No Logcat process starts in this task.

Suggested commit: `feat: open per-device logcat windows`

### Task 2: Define typed Logcat data and parse fixed fixtures

**Goal:** Convert the chosen ADB text format into typed entries without running
a long-lived process or changing the Task 1 window.

Likely files:

- new `Models/LogcatEntry.swift`;
- new `Support/LogcatParser.swift`;
- new `Support/LogcatTimestampFormatter.swift`;
- new parser and formatter tests under `Tests/ADBuddyTests`.

Implement it in this order:

1. Define `LogcatPriority` cases for Verbose, Debug, Info, Warn, Error, and
   Assert. Give the cases an explicit severity order and their one-letter ADB
   values.
2. Define a `Sendable` `LogcatEntry` containing timestamp, priority, process ID,
   thread ID, tag, and message. Add a stable local ID that permits repeated
   messages with identical contents.
3. Choose one ADB output format and pin the parser to it. Use
   `adb logcat -v threadtime` unless live validation proves that another fixed
   format is required.
4. Add representative fixture lines for every priority, long tags, empty
   messages, Unicode text, and malformed input.
5. Parse complete lines incrementally. Preserve an incomplete final line for
   the next data chunk. A malformed line may be reported or skipped, but it
   must not end the stream or discard later valid lines.
6. Handle continuation lines deterministically and test the chosen behavior.
7. Format visible time as `HH:mm:ss.SSS` with a fixed locale and calendar so
   tests do not depend on the machine's regional settings.

Acceptance checks:

- All six priorities parse with the correct severity.
- PID, TID, tag, and message remain separate typed fields.
- Splitting one input line across two chunks produces exactly one entry.
- A malformed line between two valid lines does not lose the valid lines.
- Timestamp formatting produces exactly the short time required by this
  document.

Suggested commit: `feat: parse typed logcat entries`

### Task 3: Add a cancellable streaming process runner

**Goal:** Add a process primitive for unbounded stdout. Do not change the
existing completion-based `ProcessRunner`, which is still appropriate for
short ADB commands.

Likely files:

- new `Services/StreamingProcessRunner.swift`;
- new `Services/StreamingProcessRunning.swift`, if keeping the protocol in a
  separate file improves clarity;
- new streaming runner tests under `Tests/ADBuddyTests`.

Implement it in this order:

1. Define the smallest interface needed to launch one executable URL or path
   with a `[String]` argument array and receive incremental stdout data.
2. Represent stdout chunks, stderr or launch failure, normal termination, and
   cancellation explicitly. Do not use a shell command string.
3. Read stdout while the process is running. Never wait for termination before
   delivering output, and never retain the entire stdout stream in the runner.
4. Capture bounded stderr and the termination status for a useful failure.
5. Make task cancellation terminate only the `Process` instance created by
   that stream.
6. Make termination idempotent so closing a window during process exit cannot
   crash or resume a continuation twice.
7. Test with a deterministic local helper process or an injected fake. Tests
   must not need ADB or an Android device.

Acceptance checks:

- More than one stdout chunk is delivered before the helper process exits.
- Cancelling the consumer stops the owned process promptly.
- Launch failure, nonzero exit, and stderr context are distinguishable.
- Running two streams and cancelling one leaves the other stream running.

Suggested commit: `feat: add streaming process runner`

### Task 4: Build an unfiltered per-device Logcat service

**Goal:** Turn one device's ADB stream into batches of typed `LogcatEntry`
values. Do not render the entries yet.

Likely files:

- new `Services/LogcatService.swift`;
- new service tests under `Tests/ADBuddyTests`;
- small additions to logging support if needed.

Implement it in this order:

1. Give the service a resolved ADB path, a `StreamingProcessRunning`
   dependency, and the parser from Task 2.
2. Build a fixed argument array containing the selected device serial and
   chosen Logcat format. A single command that requests the last 5,000 rows and
   then remains attached is preferred because it avoids a history/live gap.
   With compatible ADB versions, the intended shape is
   `adb -s <serial> logcat -v threadtime -T 5000`.
3. Feed chunks through one parser instance so partial lines survive chunk
   boundaries.
4. Deliver modest batches rather than one main-actor update per line. Flush a
   partially filled batch after a short interval so low-volume logs remain
   responsive.
5. Map launch failure, ADB termination, stderr context, and cancellation into
   typed stream events.
6. Add targeted `Logger` events without logging message contents.

Acceptance checks:

- Unit tests verify the exact executable and argument array.
- A fake stream produces the same entries regardless of chunk boundaries.
- Cancellation stops delivery and is not reported as a user-facing failure.
- The service never returns raw Logcat text to a view.

Suggested commit: `feat: stream typed device logcat entries`

### Task 5: Render an unfiltered stream in each Logcat window

**Goal:** Connect Tasks 1 through 4 so each open window shows live entries for
its own device. Keep filters, colors, pause, and advanced scrolling out of this
task.

Likely files:

- new `Stores/LogcatStore.swift`;
- new `Views/LogcatTableView.swift`;
- `Views/LogcatWindowView.swift`;
- focused store tests.

Implement it in this order:

1. Create one `@MainActor` observable `LogcatStore` for each window. Initialize
   it with the serial and dependencies required by `LogcatService`.
2. Start the stream once when the window appears. Cancel it when that window
   closes. A SwiftUI view refresh must not start a second process.
3. Expose connecting, streaming, failed, and stopped states separately from
   retained entries.
4. Append incoming batches and cap retained entries at 50,000. Remove old
   entries in batches rather than one row at a time.
5. Render the initial columns in this order: short time, level letter, tag,
   message. Use a monospaced font and a dense row height.
6. Start with SwiftUI's table or list support. Move only the table surface to a
   narrow `NSTableView` bridge if measured sustained output is not smooth.
7. Show a non-blocking state banner. Do not replace already rendered rows when
   a later stream failure occurs.

Acceptance checks:

- Two open device windows run independent streams for the correct serials.
- Closing one window cancels only its stream.
- Initial history is followed by live entries without clearing the table.
- Retention never exceeds 50,000 entries.
- Re-rendering the SwiftUI view does not create another ADB process.

Suggested commit: `feat: show live logcat stream`

### Task 6: Add minimum-level filtering

**Goal:** Add the `V`, `D`, `I`, `W`, `E`, and `A` minimum selector using the
severity order from Task 2.

Implement it in this order:

1. Add window-scoped minimum-level state to `LogcatStore`. Default it to Debug.
2. Derive visible entries from retained entries. Do not discard lower-priority
   entries from retention when the visible minimum changes.
3. Add a compact segmented control to the toolbar.
4. Keep ingestion running while the filter changes.
5. Add tests for every threshold, including Assert at the top and Verbose at
   the bottom.

Acceptance checks:

- Selecting Info shows Info, Warn, Error, and Assert only.
- Each window can use a different minimum.
- Opening a new window starts at Debug.

Suggested commit: `feat: filter logcat by minimum level`

### Task 7: Add application-ID filtering

**Goal:** Let each window show all applications or one editable Android
application ID, including all processes belonging to that package.

Likely additions:

- a typed running-package or process model;
- focused ADB service methods for package discovery and UID or PID resolution;
- an application picker view;
- filtering tests with process restart fixtures.

Implement it in this order:

1. Add an **All Applications** selection and make it the default.
2. Query running application IDs for picker suggestions. Keep the control
   editable so the user can enter an ID that is not running yet.
3. Resolve the selected package to all of its processes, including
   colon-suffixed secondary processes.
4. Prefer reliable UID-based Logcat filtering. If the device or ADB version
   cannot provide it, maintain a refreshed set of matching PIDs.
5. Keep waiting when the selected package has no process, then recover when it
   starts or restarts.
6. Scope retained and visible entries consistently when selection changes.
   The UI must show a connecting or waiting state while the scoped stream is
   replaced.
7. Test a primary process, a secondary process, no process, and a process whose
   PID changes after restart.

Acceptance checks:

- **All Applications** shows the unscoped device stream.
- An entered application ID works even when it was not in the suggestions.
- Secondary processes are included.
- Filtering continues after the app process restarts.
- Two windows can select different application IDs.

Suggested commit: `feat: filter logcat by application id`

### Task 8: Add follow mode, pause, clear, and copy

**Goal:** Make the stream comfortable to inspect without changing ingestion
correctness.

Implement it in this order:

1. Add explicit window-scoped state for follow mode and pause state.
2. Begin pinned to the newest visible row.
3. Detect a user scroll away from the bottom and disable follow mode. Appending
   rows must not force the user back down.
4. Add **Jump to Latest**. It scrolls to the final visible row and enables
   follow mode.
5. Add **Pause** and **Resume**. Pausing freezes the displayed snapshot but
   keeps bounded ingestion active. Restore the pre-pause follow state on
   resume.
6. Add **Clear**. It removes only this window's retained entries and must not
   run `adb logcat -c`.
7. Add row selection and standard `Command-C` copying for the selected text.
8. Test the state transitions independently from the scroll view where
   possible.

Acceptance checks:

- Scrolling upward once prevents every later batch from moving the viewport.
- **Jump to Latest** resumes automatic following.
- Paused ingestion remains capped at 50,000 entries.
- **Clear** does not affect another Logcat window or the Android device buffer.
- Selected rows copy in a readable text form.

Suggested commit: `feat: add logcat inspection controls`

### Task 9: Add severity colors and global color preferences

**Goal:** Apply the agreed default colors, then let users customize them for
all Logcat windows.

Implement it in this order:

1. Add one default color for each `LogcatPriority` using the table in this
   document.
2. Apply color to the level badge and restrained message emphasis. Keep the
   level letter visible and preserve contrast in Light and Dark appearances.
3. Add six persisted color values to `AppPreferences`. Use stable serializable
   color components rather than archiving arbitrary SwiftUI view state.
4. Add a compact Logcat color section to the existing Settings sheet with one
   native color picker per level and **Reset to Defaults**.
5. Read the shared preferences from every Logcat window so changes update open
   windows immediately.
6. Test default values, persistence, invalid stored values, and reset behavior.

Acceptance checks:

- Defaults match the intended gray, sky blue, green, ochre, red, and deep red
  mapping.
- The letter still communicates priority without color.
- A changed color updates all open Logcat windows and survives relaunch.
- Reset restores all six defaults.

Suggested commit: `feat: customize logcat severity colors`

### Task 10: Handle disconnect, reconnect, and window lifecycle

**Goal:** Keep a window useful when its device or ADB connection changes.

Implement it in this order:

1. Observe the shared device-discovery result by serial without moving Logcat
   entries or filters into `DeviceStore`.
2. When a device becomes unavailable, cancel its active stream, retain its
   entries, and show a non-modal disconnected state.
3. When the same serial becomes usable again, reconnect automatically with the
   same window-scoped filters.
4. Treat an unexpected ADB exit as a failure with concise stderr context. Retry
   only when discovery says the device is usable, using bounded backoff if
   repeated starts fail.
5. Cancel reconnect work and the owned process when the window closes or the
   app quits.
6. Add store tests using fake discovery and stream events.

Acceptance checks:

- Disconnecting retains visible logs.
- Reconnecting the same serial resumes in the same window.
- Repeated failures do not create a tight process-launch loop.
- Closing the window prevents later automatic reconnection.

Suggested commit: `fix: recover logcat after device reconnects`

### Task 11: Finish optional columns, accessibility, and performance checks

**Goal:** Complete the first standalone slice only after its behavior is
stable.

Implement it in this order:

1. Add optional PID, TID, and Application ID column visibility controls.
2. Add accessibility labels, values, keyboard focus, and Help text for every
   glyph-only or letter-only control.
3. Verify horizontal scrolling for long single-line messages and sensible
   behavior when filtering removes the current scroll anchor.
4. Measure sustained high-volume logging in a release build. Batch or
   virtualize table updates based on evidence, without moving parsing onto the
   main actor.
5. Run the complete automated and manual verification lists at the end of this
   document.
6. Update architecture and user-facing documentation to describe the finished
   behavior rather than its planned state.

Acceptance checks:

- PID, TID, and Application ID are hidden by default and can be shown without
  restarting the stream.
- Every control is usable with the keyboard and understandable to VoiceOver.
- High-volume logging remains responsive while scrolling and filtering.
- The first-slice exclusions remain excluded.

Suggested commit: `feat: finish standalone logcat viewer`

## Entry points and window identity

Each usable device row in the main window has an **Open Logcat** glyph button.
Place it beside the screenshot and recording controls, separated from those
media actions by a short vertical divider. The divider communicates that
Logcat opens a separate workflow rather than creating media.

The corresponding device submenu in the menu bar should also offer
**Open Logcat**.

Opening Logcat follows these rules:

- One Logcat window exists per device serial.
- Reopening Logcat for the same device focuses its existing window.
- Different devices can have Logcat windows open simultaneously.
- A window title uses `Logcat - <device name>` and retains the serial as
  secondary context where useful.
- Closing a Logcat window stops its stream and releases its retained entries.
- Logcat windows do not participate in automatic macOS window tabbing.

The Logcat scene owns window-specific state. It must not place the selected
application, minimum level, pause state, scroll position, or retained messages
in the global `DeviceStore`.

## Window layout

The window has a compact toolbar above a dense, monospaced log table.

The toolbar contains:

1. an editable application-ID picker;
2. a minimum-level segmented control with `V`, `D`, `I`, `W`, `E`, and `A`;
3. a local **Search Logcat** field, focused with `Command-F`;
4. a toggle to show crashes and exceptions;
5. **Pause** or **Resume**;
6. **Clear**;
7. **Jump to Latest**, shown or emphasized when follow mode is disabled.

Controls need labels in accessibility and Help text even when their visible
form is only a glyph or level letter. Filters should update the visible result
without blocking stream ingestion.

Each visible row uses this order:

```text
HH:MM:SS.SSS | level | tag | message
```

- Time is left-aligned and defaults to `HH:MM:SS.SSS`.
- The level is a narrow colored badge containing its single-letter value.
- Tag and message remain visually distinct without adding card chrome.
- PID, TID, and Application ID are available through optional column visibility controls.
- Application ID resolves from the current process list and is blank for processes that do not
  identify as Android applications.
- Long messages remain on one line by default and can scroll horizontally.
- Rows support selection and standard macOS copy behavior with `Command-C`.

The log table must be virtualized and accept batched updates. The implementation
may use a narrow `NSTableView` bridge if a pure SwiftUI list cannot maintain
smooth scrolling under sustained Logcat throughput.

## Application-ID filtering

The application picker defaults to **All Applications**. It lists application
IDs detected from running processes on the selected device while remaining
editable for an ID that is not currently running.

Selecting an application ID includes all processes belonging to that package,
including colon-suffixed secondary processes. The filter must continue working
when the application process restarts. Prefer a package UID when the connected
Android version supports reliable UID filtering; otherwise refresh the set of
matching process IDs as processes change.

Changing the application filter may restart the underlying scoped stream, but
the UI should remain responsive and clearly show its reconnecting state. A
filter with no current matching process is valid and waits for the application
to start.

Application selection is window-specific and returns to **All Applications**
when a new Logcat window is created.

## Minimum-level filtering

Log levels use Android's standard severity order:

```text
Verbose < Debug < Info < Warn < Error < Assert
```

The level control selects a minimum rather than independent visibility
toggles. For example, selecting `I` displays Info, Warn, Error, and Assert.
The default minimum is Debug, so Verbose messages are initially hidden.

The selected minimum level is window-specific and does not alter device-wide
Logcat settings.

## Text search

Each Logcat window has a local text search field that matches tag and message
text case-insensitively. Press `Command-F` to focus it. Search narrows the
already retained entries, does not restart ADB Logcat, and combines with the
application and minimum-level filters. It is window-scoped and is not
persisted between launches.

## Crash and exception filter

Each Logcat window has a one-click **Show Crashes and Exceptions** toolbar
toggle. It narrows retained entries without restarting ADB Logcat, retaining
Error and Assert messages plus entries that identify an exception, crash,
fatal condition, ANR, or stack-trace frame. It combines with the application,
minimum-level, and text-search filters. The toggle is window-scoped and is not
persisted between launches.

## Color theme

Priority is communicated with color while retaining the level letter, so color
is never the only indicator. Default colors are:

| Level | Default color |
| --- | --- |
| Verbose | neutral gray |
| Debug | sky blue |
| Info | green |
| Warn | light brown or ochre |
| Error | red |
| Assert | deep red |

Colors apply to the level badge and message emphasis while preserving readable
contrast in both Light and Dark appearances. The app should avoid tinting the
entire row with a saturated background.

All six colors are global persisted preferences. The Logcat section in Settings
provides a native color picker for each level plus **Reset to Defaults**.
Changing a color updates all open Logcat windows.

## Initial history and retention

Opening a window loads up to 5,000 recent messages for its active application
and minimum-level scope, then continues streaming live. Loading history and
starting the live stream must avoid a visible gap or duplicate rows.

Each Logcat window retains at most 50,000 parsed entries in memory. Once the
limit is reached, discard the oldest entries in bounded batches. The limit is
not initially user-configurable.

**Clear** removes the retained entries from this ADBuddy window only. It does
not run `adb logcat -c` or alter the device-wide Logcat buffers.

## Follow, scrolling, and pause behavior

The window begins in follow mode, pinned to the newest visible message.

- New visible messages scroll into view while follow mode is active.
- Scrolling upward disables follow mode immediately.
- New messages continue to stream and accumulate while follow mode is off.
- The app must never pull the user back to the bottom after they scroll up.
- **Jump to Latest** returns to the bottom and enables follow mode.
- If filtering removes the current scroll anchor, preserve the nearest sensible
  visible position rather than jumping to the bottom.

**Pause** freezes the displayed snapshot but continues bounded ingestion in the
background. **Resume** applies accumulated messages. Resuming does not enable
follow mode unless it was active when the user paused.

## Stream states and failures

The window presents explicit connecting, streaming, paused, disconnected, and
failed states without replacing retained logs unnecessarily.

- If the device disconnects, retain visible entries and show a non-modal
  disconnected banner.
- If the same serial reconnects while its window remains open, reconnect the
  stream automatically.
- If ADB fails, retain entries, show concise failure context, and retry when
  device discovery reports the device usable again.
- Closing the window or quitting ADBuddy cancels only the corresponding Logcat
  process or processes.

## Service and data boundaries

UI code must not construct or execute ADB commands. The Logcat service uses the
resolved ADB executable and fixed argument arrays, including the selected
device serial. It must not concatenate a shell command string.

The existing completion-based process runner is not sufficient for an
unbounded stream. The focused streaming process service:

- reads stdout incrementally;
- captures stderr and termination context;
- supports cancellation and terminates only its owned ADB process;
- does not buffer the entire process output before returning;
- delivers parsed entries in batches suitable for the main actor.

Use an ADB Logcat format that exposes date, time, PID, TID, priority, tag, and
message as distinct parseable fields. Views consume typed entries rather than
raw text. A representative model contains:

```text
LogcatEntry
  timestamp
  priority
  processID
  threadID
  tag
  message
```

Parsing retains valid messages when individual lines are malformed and handles
continuation lines without crashing or silently terminating the stream.

## Persistence

Persist only global Logcat color preferences in the first slice. Application
selection, minimum level, crash and exception filter, pause state, follow
state, retained entries, column visibility, and scroll position belong to the
individual window session and do not survive app relaunch.

## First-slice exclusions

The first standalone Logcat slice does not need:

- device-buffer mutation or `adb logcat -c`;
- regex or field-specific tag, PID, or TID filters;
- saved filter presets;
- exporting a log file;
- remote log-level configuration;
- multiple Logcat tabs inside one window.

These can be considered after the streaming, application filtering, minimum
level filtering, color theming, bounded retention, and follow behavior are
reliable.

## Verification target

Automated tests should cover:

- parsing all six priorities and the chosen ADB output format;
- `HH:MM:SS.SSS` formatting;
- minimum-level ordering and filtering;
- application filtering across multiple package processes and a process
  restart;
- the 5,000-entry initial-history limit and 50,000-entry retention limit;
- follow-mode transitions when the user scrolls and jumps to latest;
- pause and resume behavior;
- stream cancellation and failure mapping.

Manual verification should confirm:

1. a device-row or menu-bar action opens the correct device's Logcat window;
2. reopening focuses the existing window, while a second device opens another;
3. recent history appears before live messages continue;
4. application and minimum-level filters update correctly;
5. `Command-F` focuses search and filters tag and message text without
   restarting the stream;
6. rows remain smooth under sustained high-volume logging;
7. the window follows new messages until the user scrolls up;
8. **Jump to Latest** restores follow mode;
9. custom colors persist and update open windows;
10. disconnecting and reconnecting a device preserves the window and resumes
   streaming.
