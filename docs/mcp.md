# MCP server

ADBuddy provides a local, stdio-only Model Context Protocol server for agents
that need a small set of Android device actions without driving the macOS UI.
It has no network listener. Standard output is reserved exclusively for
newline-delimited JSON-RPC messages. Diagnostics use the macOS unified log.

## Available tools

- `list_devices` lists all ADB-visible devices and their connection state.
- `list_emulators` lists installed Android Virtual Devices and whether each is
  running.
- `start_emulator` opens an installed AVD with `quick_boot` or `cold_boot`.
- `stop_emulator` stops a running AVD by ADB serial.
- `take_screenshot` saves a PNG from a selected usable device.
- `start_screen_recording` begins a recording and returns a `recordingId`.
- `stop_screen_recording` stops the matching recording and returns the saved
  MP4 clips in capture order, with `path` pointing to the first primary clip.

Destructive AVD wipe-data startup is intentionally not exposed through MCP.
Screenshot capture, recording start, and emulator stop require an explicit ADB
serial. Emulator start takes an installed AVD name; recording stop takes the
`recordingId` returned by recording start. Agents should use
`list_devices` or `list_emulators` first, particularly when more than one
Android target is connected.

## Media behavior

MCP screenshots and recordings use the same folder and saved recording defaults
as the ADBuddy app. The server reads the shared `com.clawperator.adbuddy`
preferences domain, so screenshot framing, device-details, and the optional
50%-size copy apply to agent captures as well.

Tool results provide local absolute paths, not inline image or video data.
Screenshot results include `serial`, `path`, `mediaType`, optional `originalPath`, and
`fiftyPercentPath` when that copy is enabled. Recording results include
`recordingId`, `path`, `mediaType`, optional `originalPath`, and a `clips` array.
Each clip has a primary `path` and, when framing succeeds, an `originalPath`.
Use `clips` to collect every saved part of a foldable recording; the top-level
`path` is only the first clip. A `warning` can accompany saved media when
framing, capture completion, or setting restoration encounters a recoverable
problem. MCP captures do not post notifications, copy media to the clipboard,
or reveal Finder windows.

Recordings use the same three-minute limit and dimension-change splitting as
the GUI. Recording IDs belong to the server process that started them. Stop
through that same process; closing its input stops its owned recordings.

## Tool arguments and responses

| Tool | Arguments |
| --- | --- |
| `list_devices`, `list_emulators` | None |
| `start_emulator` | Required `name`; optional `mode`: `quick_boot` (default) or `cold_boot` |
| `stop_emulator`, `take_screenshot` | Required `serial` |
| `start_screen_recording` | Required `serial`; optional `bitRateMegabitsPerSecond` (1-200), `resolutionPercentage` (100, 75, 50, 25), and `showsTaps` (boolean) |
| `stop_screen_recording` | Required `recordingId` |

Omitted recording options use saved defaults. Unknown arguments are rejected.
Tool responses include both `structuredContent` and a text content block
containing the same JSON. Check `isError` before using a result; tool failures
provide an `error` message. A saved result with a `warning` is still a success.

## Local setup

Build and package the local app once:

```sh
./scripts/build_and_run.sh --verify
```

The packaged helper is then available at:

```text
<repository>/dist/ADBuddy.app/Contents/MacOS/adbuddy-mcp
```

Use it as a stdio server with the `serve` argument. For example, a generic MCP
client configuration has this shape:

```json
{
  "mcpServers": {
    "adbuddy": {
      "command": "/absolute/path/to/ADBuddy.app/Contents/MacOS/adbuddy-mcp",
      "args": ["serve"]
    }
  }
}
```

Do not wrap the command in a shell script that writes to standard output. An
MCP client manages the server process and sends JSON-RPC messages through its
standard input and output streams.

## Verification

For a smoke check, start the packaged helper with `serve`, send an `initialize`
request and `notifications/initialized`, then call `tools/list` and
`tools/call` for `list_devices`. Use one JSON-RPC object per input line and
check responses by request ID. Confirm all seven documented tools are listed.
Live screenshot and recording checks require a usable connected device or
emulator and save media in the configured shared folder.

For foldable recording checks, confirm the stop result's `clips` array includes
all saved clips in capture order and that the top-level `path` matches the first
clip. Verify each returned file exists and plays independently.
