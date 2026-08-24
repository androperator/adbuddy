import Foundation

public enum AndroidEmulatorVirtualDeviceListResult: Equatable, Sendable {
    case success([AndroidVirtualDevice])
    case failure(AndroidEmulatorFailure)
}

public enum AndroidEmulatorLaunchResult: Equatable, Sendable {
    case launched
    case failure(AndroidEmulatorFailure)
}

public enum AndroidEmulatorStopResult: Equatable, Sendable {
    case stopped
    case failure(AndroidEmulatorFailure)
}

public enum AndroidEmulatorStartMode: Equatable, Sendable {
    case quickBoot
    case coldBoot
    case wipeData

    public var displayName: String {
        switch self {
        case .quickBoot:
            "Start"
        case .coldBoot:
            "Cold Boot"
        case .wipeData:
            "Wipe Data and Start"
        }
    }
}

public enum AndroidEmulatorFailure: Equatable, Sendable {
    case sdkUnavailable(AndroidSDKFailure)
    case emulatorNotFound
    case commandFailed(String)
    case launchFailed(String)

    public var title: String {
        switch self {
        case .sdkUnavailable(let failure):
            failure.title
        case .emulatorNotFound:
            "Android Emulator Not Found"
        case .commandFailed:
            "Could Not List Android Emulators"
        case .launchFailed:
            "Could Not Open Android Emulator"
        }
    }

    public var detail: String {
        switch self {
        case .sdkUnavailable(let failure):
            failure.detail
        case .emulatorNotFound:
            "Install the Android Emulator package in the Android SDK."
        case .commandFailed(let message), .launchFailed(let message):
            message
        }
    }
}

public struct AndroidEmulatorService: Sendable {
    private let emulatorPath: String
    private let adbPath: String
    private let processRunner: any ProcessRunning
    private let applicationLauncher: any ApplicationProcessLaunching
    private let isExecutable: @Sendable (String) -> Bool

    public init(
        sdk: AndroidSDK,
        processRunner: any ProcessRunning,
        applicationLauncher: any ApplicationProcessLaunching = ApplicationProcessLauncher(),
        isExecutable: @escaping @Sendable (String) -> Bool = {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    ) {
        emulatorPath = URL(fileURLWithPath: sdk.rootPath)
            .appendingPathComponent("emulator", isDirectory: true)
            .appendingPathComponent("emulator")
            .path
        adbPath = sdk.adbPath
        self.processRunner = processRunner
        self.applicationLauncher = applicationLauncher
        self.isExecutable = isExecutable
    }

    public func listVirtualDevices() async -> AndroidEmulatorVirtualDeviceListResult {
        guard isExecutable(emulatorPath) else {
            AppLogger.emulator.error("Android Emulator executable is unavailable")
            return .failure(.emulatorNotFound)
        }

        let result = await processRunner.run(
            executablePath: emulatorPath,
            arguments: ["-list-avds"]
        )

        guard result.succeeded else {
            let message = failureMessage(from: result)
            AppLogger.emulator.error("Could not list Android virtual devices: \(message, privacy: .public)")
            return .failure(.commandFailed(message))
        }

        let virtualDevices = AndroidVirtualDeviceParser.parse(
            String(decoding: result.standardOutput, as: UTF8.self)
        )
        AppLogger.emulator.debug("Found \(virtualDevices.count, privacy: .public) Android virtual devices")
        return .success(virtualDevices)
    }

    public func start(
        _ virtualDevice: AndroidVirtualDevice,
        mode: AndroidEmulatorStartMode = .quickBoot
    ) -> AndroidEmulatorLaunchResult {
        guard isExecutable(emulatorPath) else {
            AppLogger.emulator.error("Android Emulator executable is unavailable")
            return .failure(.emulatorNotFound)
        }

        do {
            try applicationLauncher.launch(
                executablePath: emulatorPath,
                arguments: startArguments(for: virtualDevice, mode: mode)
            )
            AppLogger.emulator.info("Requested standalone Android Emulator start")
            return .launched
        } catch {
            let message = error.localizedDescription
            AppLogger.emulator.error("Could not start Android Emulator: \(message, privacy: .public)")
            return .failure(.launchFailed(message))
        }
    }

    public func runningVirtualDevices(in devices: [AndroidDevice]) async -> [String: AndroidDevice] {
        var runningVirtualDevices: [String: AndroidDevice] = [:]

        for device in devices where device.kind == .emulator && device.isUsable {
            guard let virtualDeviceName = await virtualDeviceName(for: device) else {
                continue
            }

            runningVirtualDevices[virtualDeviceName] = device
        }

        return runningVirtualDevices
    }

    /// Returns the configured AVD name reported by a running emulator.
    ///
    /// ADB's device list reports the system-image model (for example,
    /// `sdk_gphone64_arm64`) rather than the name the developer gave the AVD.
    /// Saved media uses this value when it is available.
    public func virtualDeviceName(for device: AndroidDevice) async -> String? {
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

    /// Replaces an emulator's system-image model name with its configured AVD
    /// name, while preserving the device serial and all ADB-facing metadata.
    public func deviceWithUserFacingName(_ device: AndroidDevice) async -> AndroidDevice {
        guard let virtualDeviceName = await virtualDeviceName(for: device) else {
            return device
        }
        return device.replacingDisplayName(with: virtualDeviceName)
    }

    public func stop(_ device: AndroidDevice) async -> AndroidEmulatorStopResult {
        let result = await processRunner.run(
            executablePath: adbPath,
            arguments: ["-s", device.serial, "emu", "kill"]
        )

        guard result.succeeded else {
            let message = failureMessage(from: result)
            AppLogger.emulator.error(
                "Could not stop Android Emulator \(device.serial, privacy: .public): \(message, privacy: .public)"
            )
            return .failure(.commandFailed(message))
        }

        AppLogger.emulator.info("Requested Android Emulator stop")
        return .stopped
    }

    private func startArguments(
        for virtualDevice: AndroidVirtualDevice,
        mode: AndroidEmulatorStartMode
    ) -> [String] {
        switch mode {
        case .quickBoot:
            ["-avd", virtualDevice.name]
        case .coldBoot:
            ["-avd", virtualDevice.name, "-no-snapshot-load"]
        case .wipeData:
            ["-avd", virtualDevice.name, "-wipe-data"]
        }
    }

    private func failureMessage(from result: ProcessResult) -> String {
        if result.wasCancelled {
            return "Listing installed Android Virtual Devices was cancelled."
        }

        if let failureDescription = result.failureDescription, !failureDescription.isEmpty {
            return "Could not start the Android Emulator: \(failureDescription)"
        }

        let standardError = String(decoding: result.standardError, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !standardError.isEmpty {
            return standardError
        }

        if let exitStatus = result.exitStatus {
            return "Android Emulator exited with status \(exitStatus)."
        }

        return "Android Emulator did not return a result."
    }
}

enum AndroidEmulatorConsoleParser {
    static func virtualDeviceName(from output: String) -> String? {
        firstValue(from: output)
    }

    static func firstValue(from output: String) -> String? {
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, line != "OK", !line.hasPrefix("KO:") else {
                continue
            }
            return line
        }
        return nil
    }
}

enum AndroidVirtualDeviceParser {
    static func parse(_ output: String) -> [AndroidVirtualDevice] {
        var virtualDevices: [AndroidVirtualDevice] = []
        var seenNames = Set<String>()

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let name = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seenNames.insert(name).inserted else {
                continue
            }
            virtualDevices.append(AndroidVirtualDevice(name: name))
        }

        return virtualDevices
    }
}
