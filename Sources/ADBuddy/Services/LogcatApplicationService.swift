import Foundation

enum LogcatApplicationServiceResult<Value: Sendable>: Sendable {
    case success(Value)
    case failure(LogcatApplicationServiceFailure)
}

extension LogcatApplicationServiceResult: Equatable where Value: Equatable {}

enum LogcatApplicationServiceFailure: Equatable, Sendable {
    case commandFailed(String)
}

protocol LogcatApplicationQuerying: Sendable {
    func runningProcesses(for deviceSerial: String) async -> LogcatApplicationServiceResult<[AndroidRunningProcess]>
    func packageUserID(for packageID: String, deviceSerial: String) async -> LogcatApplicationServiceResult<Int?>
}

struct LogcatApplicationService: LogcatApplicationQuerying, Sendable {
    private let adbPath: String
    private let processRunner: any ProcessRunning

    init(adbPath: String, processRunner: any ProcessRunning) {
        self.adbPath = adbPath
        self.processRunner = processRunner
    }

    func runningProcesses(for deviceSerial: String) async -> LogcatApplicationServiceResult<[AndroidRunningProcess]> {
        let result = await processRunner.run(
            executablePath: adbPath,
            arguments: ["-s", deviceSerial, "shell", "ps", "-A", "-o", "UID,PID,NAME"]
        )

        guard result.succeeded else {
            return .failure(.commandFailed(failureMessage(from: result)))
        }

        let output = String(decoding: result.standardOutput, as: UTF8.self)
        return .success(AndroidProcessParser.parse(output))
    }

    func packageUserID(
        for packageID: String,
        deviceSerial: String
    ) async -> LogcatApplicationServiceResult<Int?> {
        let result = await processRunner.run(
            executablePath: adbPath,
            arguments: [
                "-s", deviceSerial,
                "shell", "cmd", "package", "list", "packages", "-U", packageID,
            ]
        )

        guard result.succeeded else {
            return .failure(.commandFailed(failureMessage(from: result)))
        }

        let output = String(decoding: result.standardOutput, as: UTF8.self)
        return .success(AndroidPackageUserIDParser.parse(packageID: packageID, output: output))
    }

    private func failureMessage(from result: ProcessResult) -> String {
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
