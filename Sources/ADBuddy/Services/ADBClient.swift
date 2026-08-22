import Foundation

enum ADBDeviceListResult: Equatable, Sendable {
    case success([AndroidDevice])
    case failure(ADBError)
}

enum ADBError: Equatable, Sendable {
    case commandFailed(String)
}

struct ADBClient: Sendable {
    private let adbPath: String
    private let processRunner: any ProcessRunning

    init(adbPath: String, processRunner: any ProcessRunning) {
        self.adbPath = adbPath
        self.processRunner = processRunner
    }

    func listDevices() async -> ADBDeviceListResult {
        let result = await processRunner.run(executablePath: adbPath, arguments: ["devices", "-l"])

        guard result.succeeded else {
            let message = failureMessage(from: result)
            AppLogger.devices.error("ADB device refresh failed: \(message, privacy: .public)")
            return .failure(.commandFailed(message))
        }

        let output = String(decoding: result.standardOutput, as: UTF8.self)
        let devices = ADBDeviceParser.parse(output)
        AppLogger.devices.info("ADB device refresh returned \(devices.count, privacy: .public) devices")
        return .success(devices)
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
