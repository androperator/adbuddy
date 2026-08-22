import Foundation

public enum AndroidAppAction: CaseIterable, Equatable, Sendable {
    case start
    case forceStop
    case restart
    case clearData
    case clearDataAndRestart
    case uninstall

    public var displayName: String {
        switch self {
        case .start:
            "Start App"
        case .forceStop:
            "Kill App"
        case .restart:
            "Restart App"
        case .clearData:
            "Clear App Data"
        case .clearDataAndRestart:
            "Clear App Data and Restart"
        case .uninstall:
            "Uninstall App"
        }
    }

    public var completedDescription: String {
        switch self {
        case .start:
            "Started"
        case .forceStop:
            "Killed"
        case .restart:
            "Restarted"
        case .clearData:
            "Cleared app data for"
        case .clearDataAndRestart:
            "Cleared app data and restarted"
        case .uninstall:
            "Uninstalled"
        }
    }
}

public struct AndroidForegroundApplication: Equatable, Sendable {
    public let packageID: String

    public init(packageID: String) {
        self.packageID = packageID
    }
}

public enum AndroidAppActionServiceResult<Value: Sendable>: Sendable {
    case success(Value)
    case failure(AndroidAppActionServiceFailure)
}

extension AndroidAppActionServiceResult: Equatable where Value: Equatable {}

public enum AndroidAppActionServiceFailure: Equatable, Sendable {
    case foregroundApplicationUnavailable
    case commandFailed(String)

    public var message: String {
        switch self {
        case .foregroundApplicationUnavailable:
            "Could not determine the foreground app. Bring the app forward on the device and try again."
        case .commandFailed(let message):
            message
        }
    }
}

public struct AndroidAppActionOutcome: Equatable, Sendable {
    public let action: AndroidAppAction
    public let application: AndroidForegroundApplication

    public init(action: AndroidAppAction, application: AndroidForegroundApplication) {
        self.action = action
        self.application = application
    }
}

public struct AndroidAppActionsService: Sendable {
    private let adbPath: String
    private let processRunner: any ProcessRunning

    public init(adbPath: String, processRunner: any ProcessRunning) {
        self.adbPath = adbPath
        self.processRunner = processRunner
    }

    public func foregroundApplication(
        for deviceSerial: String
    ) async -> AndroidAppActionServiceResult<AndroidForegroundApplication> {
        let result = await processRunner.run(
            executablePath: adbPath,
            arguments: ["-s", deviceSerial, "shell", "dumpsys", "activity", "activities"]
        )

        guard result.succeeded else {
            return .failure(.commandFailed(failureMessage(from: result)))
        }

        let output = String(decoding: result.standardOutput, as: UTF8.self)
        guard let application = AndroidForegroundApplicationParser.parse(output) else {
            return .failure(.foregroundApplicationUnavailable)
        }

        return .success(application)
    }

    public func perform(
        _ action: AndroidAppAction,
        for deviceSerial: String
    ) async -> AndroidAppActionServiceResult<AndroidAppActionOutcome> {
        let applicationResult = await foregroundApplication(for: deviceSerial)
        switch applicationResult {
        case .success(let application):
            return await perform(action, on: application, deviceSerial: deviceSerial)
        case .failure(let failure):
            return .failure(failure)
        }
    }

    public func perform(
        _ action: AndroidAppAction,
        on application: AndroidForegroundApplication,
        deviceSerial: String
    ) async -> AndroidAppActionServiceResult<AndroidAppActionOutcome> {
        let operationResult: AndroidAppActionServiceResult<Void>
        switch action {
        case .start:
            operationResult = await start(application, deviceSerial: deviceSerial)
        case .forceStop:
            operationResult = await forceStop(application, deviceSerial: deviceSerial)
        case .restart:
            operationResult = await restart(application, deviceSerial: deviceSerial)
        case .clearData:
            operationResult = await clearData(application, deviceSerial: deviceSerial)
        case .clearDataAndRestart:
            operationResult = await clearDataAndRestart(application, deviceSerial: deviceSerial)
        case .uninstall:
            operationResult = await uninstall(application, deviceSerial: deviceSerial)
        }

        switch operationResult {
        case .success:
            AppLogger.appActions.info("Completed Android app action")
            return .success(AndroidAppActionOutcome(action: action, application: application))
        case .failure(let failure):
            AppLogger.appActions.error("Android app action failed: \(failure.message, privacy: .public)")
            return .failure(failure)
        }
    }

    private func start(
        _ application: AndroidForegroundApplication,
        deviceSerial: String
    ) async -> AndroidAppActionServiceResult<Void> {
        await run(
            arguments: [
                "-s", deviceSerial,
                "shell", "monkey",
                "-p", application.packageID,
                "-c", "android.intent.category.LAUNCHER",
                "1",
            ]
        )
    }

    private func forceStop(
        _ application: AndroidForegroundApplication,
        deviceSerial: String
    ) async -> AndroidAppActionServiceResult<Void> {
        await run(
            arguments: ["-s", deviceSerial, "shell", "am", "force-stop", application.packageID]
        )
    }

    private func restart(
        _ application: AndroidForegroundApplication,
        deviceSerial: String
    ) async -> AndroidAppActionServiceResult<Void> {
        let stopResult = await forceStop(application, deviceSerial: deviceSerial)
        guard case .success = stopResult else {
            return stopResult
        }
        return await start(application, deviceSerial: deviceSerial)
    }

    private func clearData(
        _ application: AndroidForegroundApplication,
        deviceSerial: String
    ) async -> AndroidAppActionServiceResult<Void> {
        let result = await processRunner.run(
            executablePath: adbPath,
            arguments: ["-s", deviceSerial, "shell", "pm", "clear", application.packageID]
        )

        guard result.succeeded else {
            return .failure(.commandFailed(failureMessage(from: result)))
        }

        let output = String(decoding: result.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard output == "Success" else {
            return .failure(.commandFailed(
                output.isEmpty ? "Android did not confirm that app data was cleared." : output
            ))
        }

        return .success(())
    }

    private func clearDataAndRestart(
        _ application: AndroidForegroundApplication,
        deviceSerial: String
    ) async -> AndroidAppActionServiceResult<Void> {
        let clearResult = await clearData(application, deviceSerial: deviceSerial)
        guard case .success = clearResult else {
            return clearResult
        }
        return await start(application, deviceSerial: deviceSerial)
    }

    private func uninstall(
        _ application: AndroidForegroundApplication,
        deviceSerial: String
    ) async -> AndroidAppActionServiceResult<Void> {
        let result = await processRunner.run(
            executablePath: adbPath,
            arguments: ["-s", deviceSerial, "uninstall", application.packageID]
        )

        guard result.succeeded else {
            return .failure(.commandFailed(failureMessage(from: result)))
        }

        let output = String(decoding: result.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard output == "Success" else {
            return .failure(.commandFailed(
                output.isEmpty ? "Android did not confirm that the app was uninstalled." : output
            ))
        }

        return .success(())
    }

    private func run(arguments: [String]) async -> AndroidAppActionServiceResult<Void> {
        let result = await processRunner.run(executablePath: adbPath, arguments: arguments)
        guard result.succeeded else {
            return .failure(.commandFailed(failureMessage(from: result)))
        }
        return .success(())
    }

    private func failureMessage(from result: ProcessResult) -> String {
        if result.wasCancelled {
            return "ADB app action was cancelled."
        }

        if let failureDescription = result.failureDescription, !failureDescription.isEmpty {
            return "Could not start ADB: \(failureDescription)"
        }

        let standardError = String(decoding: result.standardError, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !standardError.isEmpty {
            return standardError
        }

        let standardOutput = String(decoding: result.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !standardOutput.isEmpty {
            return standardOutput
        }

        if let exitStatus = result.exitStatus {
            return "ADB exited with status \(exitStatus)."
        }

        return "ADB did not return a result."
    }
}

enum AndroidForegroundApplicationParser {
    private static let packageExpression = try! NSRegularExpression(
        pattern: #"(?:mResumedActivity:|topResumedActivity=|mFocusedApp=|ResumedActivity:).*? ([A-Za-z0-9._]+)/"#
    )

    static func parse(_ output: String) -> AndroidForegroundApplication? {
        let range = NSRange(output.startIndex..., in: output)
        guard let match = packageExpression.firstMatch(in: output, range: range),
              let packageRange = Range(match.range(at: 1), in: output) else {
            return nil
        }

        return AndroidForegroundApplication(packageID: String(output[packageRange]))
    }
}
