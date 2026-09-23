import ADBuddyCore
import Foundation

final class ADBuddyMCPServer: @unchecked Sendable {
    private let service: ADBuddyMCPService
    private let responseWriter = MCPResponseWriter()

    init(service: ADBuddyMCPService = ADBuddyMCPService()) {
        self.service = service
    }

    func run() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                while let line = readLine() {
                    Task {
                        await handle(line: line)
                    }
                }
                continuation.resume()
            }
        }
        await service.stopAllScreenRecordings()
    }

    private func handle(line: String) async {
        guard let data = line.data(using: .utf8) else {
            responseWriter.writeError(id: NSNull(), code: -32700, message: "Could not read JSON-RPC input.")
            return
        }

        let request: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MCPRequestError.invalidRequest
            }
            request = decoded
        } catch {
            responseWriter.writeError(id: NSNull(), code: -32700, message: "Invalid JSON-RPC input.")
            return
        }

        let id = request["id"]
        guard request["jsonrpc"] as? String == "2.0",
              let method = request["method"] as? String,
              !method.isEmpty else {
            respondIfNeeded(id: id, errorCode: -32600, message: "Invalid JSON-RPC request.")
            return
        }

        switch method {
        case "initialize":
            respondIfNeeded(id: id, result: initializeResult(for: request["params"]))
        case "notifications/initialized":
            break
        case "ping":
            respondIfNeeded(id: id, result: [:])
        case "tools/list":
            respondIfNeeded(id: id, result: ["tools": Self.toolDefinitions])
        case "tools/call":
            respondIfNeeded(id: id, result: await callTool(request["params"]))
        default:
            respondIfNeeded(id: id, errorCode: -32601, message: "Unknown MCP method: \(method).")
        }
    }

    private func initializeResult(for parameters: Any?) -> [String: Any] {
        let requestedVersion = (parameters as? [String: Any])?["protocolVersion"] as? String
        return [
            "protocolVersion": requestedVersion ?? "2024-11-05",
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "adbuddy", "version": "0.2.1"],
        ]
    }

    private func callTool(_ parameters: Any?) async -> [String: Any] {
        guard let values = parameters as? [String: Any],
              let name = values["name"] as? String,
              !name.isEmpty else {
            return toolError("tools/call requires a non-empty tool name.")
        }
        let arguments: [String: Any]
        if let rawArguments = values["arguments"] {
            guard let parsedArguments = rawArguments as? [String: Any] else {
                return toolError("Tool arguments must be a JSON object.")
            }
            arguments = parsedArguments
        } else {
            arguments = [:]
        }

        do {
            let payload: [String: Any]
            switch name {
            case "list_devices":
                try requireNoArguments(arguments)
                payload = try decodedPayload(await service.listDevices())
            case "list_emulators":
                try requireNoArguments(arguments)
                payload = try decodedPayload(await service.listEmulators())
            case "start_emulator":
                try requireOnly(arguments, keys: ["name", "mode"])
                payload = try decodedPayload(await service.startEmulator(
                    named: requiredString(arguments, key: "name"),
                    mode: emulatorStartMode(arguments["mode"])
                ))
            case "stop_emulator":
                try requireOnly(arguments, keys: ["serial"])
                payload = try decodedPayload(await service.stopEmulator(serial: requiredString(arguments, key: "serial")))
            case "take_screenshot":
                try requireOnly(arguments, keys: ["serial"])
                payload = try decodedPayload(await service.takeScreenshot(serial: requiredString(arguments, key: "serial")))
            case "start_screen_recording":
                try requireOnly(arguments, keys: ["serial", "bitRateMegabitsPerSecond", "resolutionPercentage", "showsTaps"])
                payload = try decodedPayload(await service.startScreenRecording(
                    serial: requiredString(arguments, key: "serial"),
                    bitRateMegabitsPerSecond: optionalInteger(arguments, key: "bitRateMegabitsPerSecond"),
                    resolutionPercentage: optionalInteger(arguments, key: "resolutionPercentage"),
                    showsTaps: optionalBoolean(arguments, key: "showsTaps")
                ))
            case "stop_screen_recording":
                try requireOnly(arguments, keys: ["recordingId"])
                payload = try decodedPayload(await service.stopScreenRecording(recordingID: requiredString(arguments, key: "recordingId")))
            default:
                return toolError("Unknown ADBuddy MCP tool: \(name).")
            }
            return toolSuccess(payload)
        } catch {
            return toolError(error.localizedDescription)
        }
    }

    private func respondIfNeeded(id: Any?, result: [String: Any]) {
        guard let id, !(id is NSNull) else {
            return
        }
        responseWriter.write(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func respondIfNeeded(id: Any?, errorCode: Int, message: String) {
        guard let id, !(id is NSNull) else {
            return
        }
        responseWriter.writeError(id: id, code: errorCode, message: message)
    }

    private func toolSuccess(_ payload: [String: Any]) -> [String: Any] {
        [
            "content": [["type": "text", "text": MCPResponseWriter.jsonString(payload)]],
            "structuredContent": payload,
            "isError": false,
        ]
    }

    private func toolError(_ message: String) -> [String: Any] {
        let payload = ["error": message]
        return [
            "content": [["type": "text", "text": MCPResponseWriter.jsonString(payload)]],
            "structuredContent": payload,
            "isError": true,
        ]
    }

    private func decodedPayload(_ data: Data) throws -> [String: Any] {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPRequestError.invalidRequest
        }
        return payload
    }
}

private extension ADBuddyMCPServer {
    static var toolDefinitions: [[String: Any]] { [
        ["name": "list_devices", "description": "List Android devices currently visible to ADB.", "inputSchema": emptyObjectSchema],
        ["name": "list_emulators", "description": "List installed Android Virtual Devices and their running state.", "inputSchema": emptyObjectSchema],
        [
            "name": "start_emulator",
            "description": "Open an installed Android Emulator in its normal standalone macOS window.",
            "inputSchema": objectSchema(
                properties: [
                    "name": stringSchema,
                    "mode": ["type": "string", "enum": ["quick_boot", "cold_boot"]],
                ],
                required: ["name"]
            ),
        ],
        [
            "name": "stop_emulator",
            "description": "Stop a running Android Emulator by its ADB serial.",
            "inputSchema": objectSchema(properties: ["serial": stringSchema], required: ["serial"]),
        ],
        [
            "name": "take_screenshot",
            "description": "Save a PNG screenshot from a connected Android device to ADBuddy's shared media folder.",
            "inputSchema": objectSchema(properties: ["serial": stringSchema], required: ["serial"]),
        ],
        [
            "name": "start_screen_recording",
            "description": "Start an Android screen recording. Returns a recordingId for stop_screen_recording.",
            "inputSchema": objectSchema(
                properties: [
                    "serial": stringSchema,
                    "bitRateMegabitsPerSecond": ["type": "integer", "minimum": 1, "maximum": 200],
                    "resolutionPercentage": ["type": "integer", "enum": [100, 75, 50, 25]],
                    "showsTaps": ["type": "boolean"],
                ],
                required: ["serial"]
            ),
        ],
        [
            "name": "stop_screen_recording",
            "description": "Stop an active Android screen recording and save its MP4 clips to ADBuddy's shared media folder. Returns clips in capture order; path remains the first clip.",
            "inputSchema": objectSchema(properties: ["recordingId": stringSchema], required: ["recordingId"]),
        ],
    ] }

    static var emptyObjectSchema: [String: Any] { ["type": "object", "additionalProperties": false] }
    static var stringSchema: [String: Any] { ["type": "string", "minLength": 1] }

    static func objectSchema(properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": properties,
            "required": required,
        ]
    }
}

private enum MCPRequestError: Error {
    case invalidRequest
}

private enum MCPArgumentError: LocalizedError {
    case unexpectedArgument(String)
    case missingString(String)
    case invalidString(String)
    case invalidInteger(String)
    case invalidBoolean(String)
    case invalidMode

    var errorDescription: String? {
        switch self {
        case .unexpectedArgument(let key): "Unknown tool argument: \(key)."
        case .missingString(let key): "Missing required string argument: \(key)."
        case .invalidString(let key): "\(key) must be a non-empty string."
        case .invalidInteger(let key): "\(key) must be an integer."
        case .invalidBoolean(let key): "\(key) must be a boolean."
        case .invalidMode: "mode must be quick_boot or cold_boot."
        }
    }
}

private func requireNoArguments(_ arguments: [String: Any]) throws {
    try requireOnly(arguments, keys: [])
}

private func requireOnly(_ arguments: [String: Any], keys: Set<String>) throws {
    for key in arguments.keys where !keys.contains(key) {
        throw MCPArgumentError.unexpectedArgument(key)
    }
}

private func requiredString(_ arguments: [String: Any], key: String) throws -> String {
    guard let value = arguments[key] else {
        throw MCPArgumentError.missingString(key)
    }
    guard let string = value as? String else {
        throw MCPArgumentError.invalidString(key)
    }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw MCPArgumentError.invalidString(key)
    }
    return trimmed
}

private func optionalInteger(_ arguments: [String: Any], key: String) throws -> Int? {
    guard let value = arguments[key] else {
        return nil
    }
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.rounded() == number.doubleValue else {
        throw MCPArgumentError.invalidInteger(key)
    }
    return number.intValue
}

private func optionalBoolean(_ arguments: [String: Any], key: String) throws -> Bool? {
    guard let value = arguments[key] else {
        return nil
    }
    guard let number = value as? NSNumber,
          CFGetTypeID(number) == CFBooleanGetTypeID() else {
        throw MCPArgumentError.invalidBoolean(key)
    }
    return number.boolValue
}

private func emulatorStartMode(_ value: Any?) throws -> AndroidEmulatorStartMode {
    guard let value else {
        return .quickBoot
    }
    switch value as? String {
    case "quick_boot": return .quickBoot
    case "cold_boot": return .coldBoot
    default: throw MCPArgumentError.invalidMode
    }
}

private final class MCPResponseWriter: @unchecked Sendable {
    private let lock = NSLock()

    func writeError(id: Any, code: Int, message: String) {
        write(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    func write(_ response: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]) else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }

    static func jsonString(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"Could not encode tool response.\"}"
        }
        return string
    }
}
