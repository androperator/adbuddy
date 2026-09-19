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
        let navigation = action.navigationConfiguration
        if let navigation {
            let availability = await processRunner.run(
                executablePath: adbPath,
                arguments: ["-s", deviceSerial, "shell", "cmd", "overlay", "list", "--user", "current", navigation.package]
            )
            guard availability.succeeded else {
                return .failure(.commandFailed(failureMessage(from: availability)))
            }
            let overlays = String(decoding: availability.standardOutput, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard overlays.contains("[ ] \(navigation.package)") ||
                    overlays.contains("[x] \(navigation.package)") else {
                return .failure(.commandFailed(
                    "This Android image does not provide the requested navigation mode. Choose another navigation mode."
                ))
            }
        }

        let result = await processRunner.run(
            executablePath: adbPath,
            arguments: arguments(for: action, deviceSerial: deviceSerial)
        )

        guard result.succeeded else {
            let message = failureMessage(from: result)
            AppLogger.deviceSettings.error("Android device setting failed: \(message, privacy: .public)")
            return .failure(.commandFailed(message))
        }

        if action.requiresApplicationRefresh {
            // IBinder.SYSPROPS_TRANSACTION ('_SPR') tells ActivityManager to
            // forward the property-change notification to running applications.
            let refresh = await processRunner.run(
                executablePath: adbPath,
                arguments: ["-s", deviceSerial, "shell", "service", "call", "activity", "1599295570"]
            )
            let output = String(decoding: refresh.standardOutput, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // This transaction has no reply payload. Android versions print
            // either NULL or BAD_TYPE ("Not a data message") for the empty parcel.
            let hasEmptyReply = output == "Result: Parcel(NULL)" ||
                output == "Result: Parcel(Error: 0xffffffffffffffb6 \"Not a data message\")"
            guard refresh.succeeded, hasEmptyReply else {
                let message = "Setting saved, but running apps could not be refreshed. Restart the app to apply it. \(failureMessage(from: refresh))"
                AppLogger.deviceSettings.error("Application refresh failed: \(message, privacy: .public)")
                return .failure(.commandFailed(message))
            }
        }

        if let navigation {
            let verification = await processRunner.run(
                executablePath: adbPath,
                arguments: [
                    "-s", deviceSerial, "shell", "cmd", "overlay", "lookup", "--user", "current",
                    "android", "android:integer/config_navBarInteractionMode",
                ]
            )
            guard verification.succeeded else {
                return .failure(.commandFailed(
                    "The navigation change was sent, but could not be verified: \(failureMessage(from: verification))"
                ))
            }
            let activeMode = String(decoding: verification.standardOutput, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard activeMode == navigation.mode else {
                return .failure(.commandFailed(
                    "Android did not activate the requested navigation mode. Try changing System navigation in Android Settings."
                ))
            }
        }

        AppLogger.deviceSettings.info("Android device setting updated")
        return .success(AndroidDeviceSettingOutcome(action: action, deviceSerial: deviceSerial))
    }

    private func arguments(
        for action: AndroidDeviceSettingAction,
        deviceSerial: String
    ) -> [String] {
        let deviceArguments = ["-s", deviceSerial, "shell"]
        let navigationArguments = deviceArguments + ["cmd", "overlay", "enable-exclusive", "--user", "current", "--category"]

        return switch action {
        case .enableDarkTheme:
            deviceArguments + ["cmd", "uimode", "night", "yes"]
        case .enableLightTheme:
            deviceArguments + ["cmd", "uimode", "night", "no"]
        case .enableGestureNavigation:
            navigationArguments + ["com.android.internal.systemui.navbar.gestural"]
        case .enableThreeButtonNavigation:
            navigationArguments + ["com.android.internal.systemui.navbar.threebutton"]
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

private extension AndroidDeviceSettingAction {
    var requiresApplicationRefresh: Bool {
        switch self {
        case .showLayoutBounds, .hideLayoutBounds, .showGPURenderingBars, .hideGPURenderingBars:
            true
        default:
            false
        }
    }

    var navigationConfiguration: (package: String, mode: String)? {
        switch self {
        case .enableGestureNavigation:
            ("com.android.internal.systemui.navbar.gestural", "2")
        case .enableThreeButtonNavigation:
            ("com.android.internal.systemui.navbar.threebutton", "0")
        default:
            nil
        }
    }
}
