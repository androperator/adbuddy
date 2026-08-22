import Foundation

public enum AndroidDeviceSettingAction: CaseIterable, Equatable, Sendable {
    case enableDarkTheme
    case enableLightTheme
    case enableGestureNavigation
    case enableThreeButtonNavigation
    case showLayoutBounds
    case hideLayoutBounds
    case showGPURenderingBars
    case hideGPURenderingBars

    public var completedDescription: String {
        switch self {
        case .enableDarkTheme:
            "Dark theme enabled"
        case .enableLightTheme:
            "Light theme enabled"
        case .enableGestureNavigation:
            "Gesture navigation enabled"
        case .enableThreeButtonNavigation:
            "Three-button navigation enabled"
        case .showLayoutBounds:
            "Layout bounds shown"
        case .hideLayoutBounds:
            "Layout bounds hidden"
        case .showGPURenderingBars:
            "GPU rendering bars shown"
        case .hideGPURenderingBars:
            "GPU rendering bars hidden"
        }
    }
}

public struct AndroidDeviceSettingOutcome: Equatable, Sendable {
    public let action: AndroidDeviceSettingAction
    public let deviceSerial: String

    public init(action: AndroidDeviceSettingAction, deviceSerial: String) {
        self.action = action
        self.deviceSerial = deviceSerial
    }
}

public enum AndroidDeviceSettingsServiceFailure: Equatable, Sendable {
    case commandFailed(String)

    public var message: String {
        switch self {
        case .commandFailed(let message):
            message
        }
    }
}

public enum AndroidDeviceSettingsServiceResult: Equatable, Sendable {
    case success(AndroidDeviceSettingOutcome)
    case failure(AndroidDeviceSettingsServiceFailure)
}

public struct AndroidDeviceSettingsService: Sendable {
    private let adbPath: String
    private let processRunner: any ProcessRunning

    public init(adbPath: String, processRunner: any ProcessRunning) {
        self.adbPath = adbPath
        self.processRunner = processRunner
    }

    public func apply(
        _ action: AndroidDeviceSettingAction,
        to deviceSerial: String
    ) async -> AndroidDeviceSettingsServiceResult {
        let result = await processRunner.run(
            executablePath: adbPath,
            arguments: arguments(for: action, deviceSerial: deviceSerial)
        )

        guard result.succeeded else {
            let message = failureMessage(from: result)
            AppLogger.deviceSettings.error("Android device setting failed: \(message, privacy: .public)")
            return .failure(.commandFailed(message))
        }

        AppLogger.deviceSettings.info("Android device setting updated")
        return .success(AndroidDeviceSettingOutcome(action: action, deviceSerial: deviceSerial))
    }

    private func arguments(
        for action: AndroidDeviceSettingAction,
        deviceSerial: String
    ) -> [String] {
        let deviceArguments = ["-s", deviceSerial, "shell"]

        return switch action {
        case .enableDarkTheme:
            deviceArguments + ["cmd", "uimode", "night", "yes"]
        case .enableLightTheme:
            deviceArguments + ["cmd", "uimode", "night", "no"]
        case .enableGestureNavigation:
            deviceArguments + ["settings", "put", "secure", "navigation_mode", "2"]
        case .enableThreeButtonNavigation:
            deviceArguments + ["settings", "put", "secure", "navigation_mode", "0"]
        case .showLayoutBounds:
            deviceArguments + ["setprop", "debug.layout", "true"]
        case .hideLayoutBounds:
            deviceArguments + ["setprop", "debug.layout", "false"]
        case .showGPURenderingBars:
            deviceArguments + ["setprop", "debug.hwui.profile", "visual_bars"]
        case .hideGPURenderingBars:
            deviceArguments + ["setprop", "debug.hwui.profile", "false"]
        }
    }

    private func failureMessage(from result: ProcessResult) -> String {
        if result.wasCancelled {
            return "Changing the device setting was cancelled."
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
