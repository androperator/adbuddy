import Foundation

public enum ADBDeviceListResult: Equatable, Sendable {
    case success([AndroidDevice])
    case failure(ADBError)
}

public enum ADBError: Equatable, Sendable {
    case commandFailed(String)
}

public struct ADBClient: Sendable {
    private let adbPath: String
    private let processRunner: any ProcessRunning

    public init(adbPath: String, processRunner: any ProcessRunning) {
        self.adbPath = adbPath
        self.processRunner = processRunner
    }

    public func listDevices() async -> ADBDeviceListResult {
        let result = await processRunner.run(executablePath: adbPath, arguments: ["devices", "-l"])

        guard result.succeeded else {
            let message = failureMessage(from: result)
            AppLogger.devices.error("ADB device refresh failed: \(message, privacy: .public)")
            return .failure(.commandFailed(message))
        }

        let output = String(decoding: result.standardOutput, as: UTF8.self)
        var devices: [AndroidDevice] = []
        for device in ADBDeviceParser.parse(output) {
            if device.kind == .emulator {
                let name = await virtualDeviceName(for: device)
                devices.append(device.replacingDisplayName(with: name ?? device.serial))
            } else {
                devices.append(device)
            }
        }
        AppLogger.devices.debug("ADB device refresh returned \(devices.count, privacy: .public) devices")
        return .success(devices)
    }

    /// Resolves the configured AVD name without changing any ADB identity fields.
    func virtualDeviceName(for device: AndroidDevice) async -> String? {
        guard device.kind == .emulator, device.isUsable else {
            return nil
        }

        let result = await processRunner.run(
            executablePath: adbPath,
            arguments: ["-s", device.serial, "emu", "avd", "name"]
        )

        guard result.succeeded else {
            let message = failureMessage(from: result)
            AppLogger.emulator.debug(
                "Could not identify running Android Emulator \(device.serial, privacy: .public): \(message, privacy: .public)"
            )
            return nil
        }

        guard let virtualDeviceName = AndroidEmulatorConsoleParser.virtualDeviceName(
            from: String(decoding: result.standardOutput, as: UTF8.self)
        ) else {
            AppLogger.emulator.debug(
                "Android Emulator \(device.serial, privacy: .public) did not report an AVD name"
            )
            return nil
        }

        return virtualDeviceName
    }

    private func failureMessage(from result: ProcessResult) -> String {
        if result.wasCancelled {
            return "ADB refresh was cancelled."
        }

        if let failureDescription = result.failureDescription, !failureDescription.isEmpty {
            return "Could not start ADB: \(failureDescription)"
        }

        let standardError = String(decoding: result.standardError, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !standardError.isEmpty {
            return standardError
        }

        if let exitStatus = result.exitStatus {
            return "ADB exited with status \(exitStatus)."
        }

        return "ADB did not return a result."
    }
}

enum ADBDeviceParser {
    static func parse(_ output: String) -> [AndroidDevice] {
        var foundHeader = false
        var devices: [AndroidDevice] = []

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            if line == "List of devices attached" {
                foundHeader = true
                continue
            }

            guard foundHeader else {
                continue
            }

            let columns = line.split(
                maxSplits: 2,
                omittingEmptySubsequences: true,
                whereSeparator: \.isWhitespace
            )
            guard columns.count >= 2 else {
                continue
            }

            let serial = String(columns[0])
            let connectionState = DeviceConnectionState(adbValue: String(columns[1]))
            let metadata = columns.count == 3 ? parseMetadata(String(columns[2])) : [:]
            let model = metadata["model"]

            devices.append(
                AndroidDevice(
                    serial: serial,
                    displayName: displayName(for: model, serial: serial),
                    connectionState: connectionState,
                    kind: serial.hasPrefix("emulator-") ? .emulator : .physical,
                    model: model,
                    product: metadata["product"],
                    deviceCodeName: metadata["device"],
                    transportID: metadata["transport_id"]
                )
            )
        }

        return devices
    }

    private static func parseMetadata(_ value: String) -> [String: String] {
        var metadata: [String: String] = [:]

        for token in value.split(whereSeparator: \.isWhitespace) {
            guard let separator = token.firstIndex(of: ":") else {
                continue
            }

            let key = String(token[..<separator])
            let value = String(token[token.index(after: separator)...])
            guard !key.isEmpty, !value.isEmpty else {
                continue
            }

            metadata[key] = value
        }

        return metadata
    }

    private static func displayName(for model: String?, serial: String) -> String {
        guard let model, !model.isEmpty else {
            return serial
        }

        return model.replacingOccurrences(of: "_", with: " ")
    }
}
