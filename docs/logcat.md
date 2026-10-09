# Logcat

ADBuddy provides a native per-device Logcat window for inspecting Android logs
without opening Android Studio. This document describes its implemented
behavior, service boundaries, and validation requirements.

## Entry points and window identity

Each usable device row in the main window has an **Open Logcat** glyph button.
It sits beside the screenshot and recording controls, separated from those
media actions by a short vertical divider. The divider communicates that
Logcat opens a separate workflow rather than creating media.

The corresponding device submenu in the menu bar also offers
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
2. a minimum-level menu that shows the selected full level name;
3. a local **Search Logcat** field, focused with `Command-F`;
4. a toggle to show crashes and exceptions;
5. a **Wrap** toggle for long messages;
6. **Pause** or **Resume**;
7. **Clear**;
8. **Jump to Latest**, shown or emphasized when follow mode is disabled.

Controls need labels in accessibility and Help text even when their visible
form is only a glyph or level letter. Filters should update the visible result
without blocking stream ingestion.

The default visible column order is:

```text
HH:MM:SS.SSS | level | tag | message
```

- Time is left-aligned and defaults to `HH:MM:SS.SSS`.
- The level is a narrow colored badge containing its single-letter value.
- Tag and message remain visually distinct without adding card chrome.
- PID, TID, and Application ID are hidden by default. Column controls can show
  them or hide Tag; column headers can be reordered and resized.
- Application ID resolves from the current process list and is blank for processes that do not
  identify as Android applications.
- Long messages remain on one line by default and can scroll horizontally.
  **Wrap** displays the full message over as many word-wrapped lines as needed.
- Double-clicking a visible column divider sizes that column to its widest
  current header or retained entry.
- Rows support selection and standard macOS copy behavior with `Command-C`.
  Live updates preserve selected entries while they remain visible.
- Selected rows use the system selected-text color, including level badges and
  severity-colored messages.

The log table uses a virtualized `NSTableView` bridge and batched updates.
Parsing runs off the main actor.

## Application-ID filtering

The application picker defaults to **All Applications**. It lists application
IDs detected from running processes on the selected device while remaining
editable for an ID that is not currently running.

Selecting an application ID includes all processes belonging to that package,
including colon-suffixed secondary processes. The filter must continue working
when the application process restarts. The service prefers package UID
filtering and falls back to locally matching process IDs when UID filtering
is unavailable. Running processes refresh once per second.

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

The level menu selects a minimum rather than independent visibility toggles.
It shows the selected full level name, with every option named in the menu.
For example, selecting Info displays Info, Warn, Error, and Assert. The default
minimum is Debug, so Verbose messages are initially hidden.

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
only entries that identify an exception, crash, fatal condition, ANR, or
stack-trace frame. Routine Error and Assert messages are excluded. It combines
with the application, minimum-level, and text-search filters. The toggle is
window-scoped and is not persisted between launches. When the filter is turned
off with a selected entry, the first selected entry remains selected and is
centered with its surrounding logs visible. This also stops following live
output.

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
contrast in both Light and Dark appearances. Message colors brighten toward
white in Dark mode. The app should avoid tinting the entire row with a
saturated background.

All six colors are global persisted preferences. The Logcat tab in Settings
provides a native color picker for each level plus **Reset to Defaults**.
Changing a color updates all open Logcat windows.

## Initial history and retention

Each stream requests recent history with `adb logcat -v threadtime -T 5000`
and continues live through the same process. When UID filtering is active, the
request also includes `--uid`. Minimum level, search, and crash filters apply
locally to retained entries, so the visible initial result can be smaller than
5,000 messages. Changing the application stream scope clears and reloads its
history.

Each Logcat window retains at most 50,000 parsed entries in memory. Once the
limit is reached, discard the oldest entries in bounded batches. The limit is
not user-configurable.

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

The window presents connecting, streaming, paused, disconnected,
waiting-for-application, stopped, and failed states without replacing retained logs unnecessarily.

- If the device disconnects, retain visible entries and show a non-modal
  disconnected banner.
- If the same serial reconnects while its window remains open, reconnect the
  stream automatically.
- If ADB fails, retain entries, show concise failure context, and retry with
  backoff while the device remains usable. Device disconnection suspends the
  stream until discovery reports that serial usable again.
- Closing the window or quitting ADBuddy cancels only the corresponding Logcat
  process or processes.

## Service and data boundaries

UI code must not construct or execute ADB commands. The Logcat service uses the
resolved ADB executable and fixed argument arrays, including the selected
device serial. It must not concatenate a shell command string.

`StreamingProcessRunner` manages the unbounded process separately from
completion-based `ProcessRunner`. Together with `LogcatService`, it:

- reads stdout incrementally;
- captures stderr and termination context;
- supports cancellation and terminates only its owned ADB process;
- does not buffer the entire process output before returning;
- delivers parsed entries in batches suitable for the main actor.

`LogcatService` parses ADB threadtime output into typed entries. Views consume
these values rather than raw output. `LogcatEntry` contains:

```text
LogcatEntry
  id
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

`AppPreferences` persists global severity colors and table preferences: column
visibility, order, widths, and message wrapping. These settings are shared
across Logcat windows and survive app relaunch.

Application selection, minimum level, text search, crash filtering, pause/follow
state, retained entries, selection, and scroll position belong to the individual
window session and are not restored after app relaunch.

## Unsupported features

The viewer does not implement:

- device-buffer mutation or `adb logcat -c`;
- regex or field-specific tag, PID, or TID filters;
- saved filter presets;
- exporting a log file;
- remote log-level configuration;
- multiple Logcat tabs inside one window.

## Verification

Automated tests should cover:

- parsing all six priorities and the chosen ADB output format;
- `HH:MM:SS.SSS` formatting;
- minimum-level ordering and filtering;
- application filtering across multiple package processes and a process
  restart;
- the 5,000-entry initial-history limit and 50,000-entry retention limit;
- follow-mode transitions when the user scrolls and jumps to latest;
- pause and resume behavior;
- stream cancellation, reconnect backoff, and failure mapping;
- table preference persistence, column sizing, wrapping, and selection
  preservation through reloads.

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
    streaming;
11. visibility, order, widths, and wrapping update across windows and persist
    after relaunch, while session filters reset;
12. crash filtering preserves selection when returning to surrounding logs.
