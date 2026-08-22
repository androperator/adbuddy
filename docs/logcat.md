# Logcat window target

## Purpose

ADBuddy should provide a focused native Logcat viewer for developers who need
to inspect a connected Android device without opening Android Studio. Logcat is
a dedicated per-device window, not another mode inside the compact main
window.

This document defines the target behavior for the first standalone Logcat
slice. It is a product and architecture contract, not authorization to add
placeholder UI before Logcat implementation begins.

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
3. **Pause** or **Resume**;
4. **Clear**;
5. **Jump to Latest**, shown or emphasized when follow mode is disabled.

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
- PID and TID are available through optional column visibility controls.
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

All six colors are global persisted preferences. A future Logcat section in
Settings provides a native color picker for each level plus **Reset to
Defaults**. Changing a color updates all open Logcat windows.

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
unbounded stream. Add a focused streaming process service that:

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
selection, minimum level, pause state, follow state, retained entries, column
visibility, and scroll position belong to the individual window session and do
not survive app relaunch.

## First-slice exclusions

The first standalone Logcat slice does not need:

- device-buffer mutation or `adb logcat -c`;
- regex, tag, PID, or TID filters;
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
5. rows remain smooth under sustained high-volume logging;
6. the window follows new messages until the user scrolls up;
7. **Jump to Latest** restores follow mode;
8. custom colors persist and update open windows;
9. disconnecting and reconnecting a device preserves the window and resumes
   streaming.
