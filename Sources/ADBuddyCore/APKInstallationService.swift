import Foundation

public struct AndroidPackageArchive: Equatable, Sendable, Identifiable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public var id: String {
        fileURL.path
    }

    public var displayName: String {
        fileURL.lastPathComponent
    }
}

public struct AndroidAPKLaunchTarget: Equatable, Sendable {
    public let packageID: String
    public let activityName: String

    public init(packageID: String, activityName: String) {
        self.packageID = packageID
        self.activityName = activityName
    }

    var componentName: String {
        let resolvedActivityName: String
        if activityName.hasPrefix(".") {
            resolvedActivityName = packageID + activityName
        } else if activityName.contains(".") {
            resolvedActivityName = activityName
        } else {
            resolvedActivityName = "\(packageID).\(activityName)"
        }

        return "\(packageID)/\(resolvedActivityName)"
    }
}

public enum APKInstallationLaunchResult: Equatable, Sendable {
    case notRequested
    case launched(AndroidAPKLaunchTarget)
    case unavailable(String)
    case failed(String)

    public var detail: String? {
        switch self {
        case .notRequested, .launched:
            nil
        case .unavailable(let message), .failed(let message):
            message
        }
    }
}

public struct APKInstallationOutcome: Equatable, Sendable {
    public let archive: AndroidPackageArchive
    public let deviceSerial: String
    public let launchResult: APKInstallationLaunchResult

    public init(
        archive: AndroidPackageArchive,
        deviceSerial: String,
        launchResult: APKInstallationLaunchResult
    ) {
        self.archive = archive
        self.deviceSerial = deviceSerial
        self.launchResult = launchResult
    }
}

public enum APKInstallationFailure: Equatable, Sendable {
    case invalidArchive
    case commandFailed(String)

    public var message: String {
        switch self {
        case .invalidArchive:
            "Choose a readable .apk file."
        case .commandFailed(let message):
            message
        }
    }
}

public enum APKInstallationServiceResult: Equatable, Sendable {
    case success(APKInstallationOutcome)
    case failure(APKInstallationFailure)
}

public struct APKInstallationService: Sendable {
    private let adbPath: String
    private let aapt2Path: String?
    private let processRunner: any ProcessRunning
    private let isReadableArchive: @Sendable (URL) -> Bool

    public init(
        adbPath: String,
        aapt2Path: String?,
        processRunner: any ProcessRunning,
        isReadableArchive: @escaping @Sendable (URL) -> Bool = { fileURL in
            fileURL.isFileURL &&
                fileURL.pathExtension.caseInsensitiveCompare("apk") == .orderedSame &&
                FileManager.default.fileExists(atPath: fileURL.path) &&
                FileManager.default.isReadableFile(atPath: fileURL.path)
        }
    ) {
        self.adbPath = adbPath
        self.aapt2Path = aapt2Path
        self.processRunner = processRunner
        self.isReadableArchive = isReadableArchive
    }

    public func install(
        _ archive: AndroidPackageArchive,
        on deviceSerial: String,
        openAfterInstall: Bool
    ) async -> APKInstallationServiceResult {
        guard isReadableArchive(archive.fileURL) else {
            return .failure(.invalidArchive)
        }

        let launchTargetResult = openAfterInstall
            ? await launchTarget(for: archive)
            : .notRequested

        let installResult = await processRunner.run(
            executablePath: adbPath,
            arguments: ["-s", deviceSerial, "install", "-r", archive.fileURL.path]
        )
        let installOutput = combinedOutput(from: installResult)
        guard installResult.succeeded,
              !installOutput.localizedCaseInsensitiveContains("failure [") else {
            let message = failureMessage(
                from: installResult,
                action: "install the APK"
            )
            AppLogger.apkInstallation.error("APK installation failed: \(message, privacy: .public)")
            return .failure(.commandFailed(message))
        }

        let launchResult: APKInstallationLaunchResult
        switch launchTargetResult {
        case .notRequested:
            launchResult = .notRequested
        case .unavailable(let message):
            launchResult = .unavailable(message)
        case .target(let target):
            launchResult = await launch(target, on: deviceSerial)
        }

        AppLogger.apkInstallation.info("APK installation completed")
        return .success(
            APKInstallationOutcome(
                archive: archive,
                deviceSerial: deviceSerial,
                launchResult: launchResult
            )
        )
    }

    private func launchTarget(for archive: AndroidPackageArchive) async -> LaunchTargetResolution {
        guard let aapt2Path else {
            return .unavailable(
                "Installed, but could not open the app because aapt2 was not found in the Android SDK."
            )
        }

        let result = await processRunner.run(
            executablePath: aapt2Path,
            arguments: ["dump", "badging", archive.fileURL.path]
        )
        guard result.succeeded else {
            return .unavailable(
                "Installed, but could not read the APK's launch activity."
            )
        }

        let output = combinedOutput(from: result)
        guard let target = AndroidAPKLaunchTargetParser.parse(output) else {
            return .unavailable(
                "Installed, but this APK does not declare a launchable activity."
            )
        }

        return .target(target)
    }

    private func launch(
        _ target: AndroidAPKLaunchTarget,
        on deviceSerial: String
    ) async -> APKInstallationLaunchResult {
        let result = await processRunner.run(
            executablePath: adbPath,
            arguments: [
                "-s", deviceSerial,
                "shell", "am", "start", "-W",
                "-n", target.componentName,
            ]
        )
        guard result.succeeded else {
            return .failed(failureMessage(from: result, action: "open the installed app"))
        }

        let output = combinedOutput(from: result)
        if output.localizedCaseInsensitiveContains("error:") {
            return .failed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return .launched(target)
    }

    private func failureMessage(from result: ProcessResult, action: String) -> String {
        if result.wasCancelled {
            return "ADB was cancelled while trying to \(action)."
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
            return "ADB exited with status \(exitStatus) while trying to \(action)."
        }

        return "ADB did not return a result while trying to \(action)."
    }

    private func combinedOutput(from result: ProcessResult) -> String {
        let standardOutput = String(decoding: result.standardOutput, as: UTF8.self)
        let standardError = String(decoding: result.standardError, as: UTF8.self)
        return [standardOutput, standardError]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum AndroidAPKLaunchTargetParser {
    static func parse(_ output: String) -> AndroidAPKLaunchTarget? {
        guard let packageID = quotedValue(named: "name", inLineStartingWith: "package:", output: output),
              let activityName = quotedValue(
                  named: "name",
                  inLineStartingWith: "launchable-activity:",
                  output: output
              ) else {
            return nil
        }

        return AndroidAPKLaunchTarget(packageID: packageID, activityName: activityName)
    }

    private static func quotedValue(
        named name: String,
        inLineStartingWith prefix: String,
        output: String
    ) -> String? {
        guard let line = output.split(whereSeparator: \.isNewline).first(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
        }) else {
            return nil
        }

        let expression = "\(name)='([^']+)'"
        guard let range = String(line).range(of: expression, options: .regularExpression) else {
            return nil
        }

        let match = String(line)[range]
        return match
            .dropFirst(name.count + 2)
            .dropLast()
            .description
    }
}

private enum LaunchTargetResolution {
    case notRequested
    case target(AndroidAPKLaunchTarget)
    case unavailable(String)
}
