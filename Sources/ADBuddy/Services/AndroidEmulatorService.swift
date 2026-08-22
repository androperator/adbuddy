import Foundation

enum AndroidEmulatorVirtualDeviceListResult: Equatable, Sendable {
    case success([AndroidVirtualDevice])
    case failure(AndroidEmulatorFailure)
}

enum AndroidEmulatorLaunchResult: Equatable, Sendable {
    case launched
    case failure(AndroidEmulatorFailure)
}

enum AndroidEmulatorFailure: Equatable, Sendable {
    case sdkUnavailable(AndroidSDKFailure)
    case emulatorNotFound
    case commandFailed(String)
    case launchFailed(String)

    var title: String {
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

    var detail: String {
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

struct AndroidEmulatorService: Sendable {
    private let emulatorPath: String
    private let processRunner: any ProcessRunning
    private let applicationLauncher: any ApplicationProcessLaunching
    private let isExecutable: @Sendable (String) -> Bool

    init(
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
        self.processRunner = processRunner
        self.applicationLauncher = applicationLauncher
        self.isExecutable = isExecutable
    }

    func listVirtualDevices() async -> AndroidEmulatorVirtualDeviceListResult {
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

    func launch(_ virtualDevice: AndroidVirtualDevice) -> AndroidEmulatorLaunchResult {
        guard isExecutable(emulatorPath) else {
            AppLogger.emulator.error("Android Emulator executable is unavailable")
            return .failure(.emulatorNotFound)
        }

        do {
            try applicationLauncher.launch(
                executablePath: emulatorPath,
                arguments: ["-avd", virtualDevice.name]
            )
            AppLogger.emulator.info("Requested standalone Android Emulator launch")
            return .launched
        } catch {
            let message = error.localizedDescription
            AppLogger.emulator.error("Could not start Android Emulator: \(message, privacy: .public)")
            return .failure(.launchFailed(message))
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
