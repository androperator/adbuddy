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
  MP4 path.

Destructive AVD wipe-data startup is intentionally not exposed through MCP.
Every device action requires an explicit ADB serial. Agents should use
`list_devices` or `list_emulators` first, particularly when more than one
Android target is connected.

## Media behavior

MCP screenshots and recordings use the same folder and saved recording defaults
as the ADBuddy app. The server reads the shared `com.clawperator.adbuddy`
preferences domain, so a folder selected in ADBuddy Settings applies to agent
captures as well.

Tool results provide the local absolute media path. MCP captures do not post
macOS notifications and do not copy images to the clipboard because the agent
already receives the resulting path directly.

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

The server is exercised with a stdio MCP initialization, tool discovery, and
device-list smoke flow. Live screenshot and recording checks require a usable
connected device or emulator and save media in the configured shared folder.
