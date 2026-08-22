import Foundation

public struct AndroidDeepLink: Equatable, Sendable {
    public let uri: String
    public let targetPackageID: String?

    public init?(uri: String, targetPackageID: String? = nil) {
        let trimmedURI = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURI.isEmpty,
              !trimmedURI.contains(where: \.isWhitespace),
              let parsedURL = URL(string: trimmedURI),
              let scheme = parsedURL.scheme,
              !scheme.isEmpty else {
            return nil
        }

        if ["http", "https"].contains(scheme.lowercased()), parsedURL.host == nil {
            return nil
        }

        let trimmedPackageID = targetPackageID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedPackageID.contains(where: \.isWhitespace) else {
            return nil
        }

        self.uri = trimmedURI
        self.targetPackageID = trimmedPackageID.isEmpty ? nil : trimmedPackageID
    }
}

public struct AndroidDeepLinkLaunchOutcome: Equatable, Sendable {
    public let deepLink: AndroidDeepLink
    public let deviceSerial: String

    public init(deepLink: AndroidDeepLink, deviceSerial: String) {
        self.deepLink = deepLink
        self.deviceSerial = deviceSerial
    }
}

public enum AndroidDeepLinkServiceFailure: Equatable, Sendable {
    case commandFailed(String)

    public var message: String {
        switch self {
        case .commandFailed(let message):
            message
        }
    }
}

public enum AndroidDeepLinkServiceResult: Equatable, Sendable {
    case success(AndroidDeepLinkLaunchOutcome)
    case failure(AndroidDeepLinkServiceFailure)
}

public struct AndroidDeepLinkService: Sendable {
    private let adbPath: String
    private let processRunner: any ProcessRunning

    public init(adbPath: String, processRunner: any ProcessRunning) {
        self.adbPath = adbPath
        self.processRunner = processRunner
    }

    public func launch(
        _ deepLink: AndroidDeepLink,
        on deviceSerial: String
    ) async -> AndroidDeepLinkServiceResult {
        var arguments = [
            "-s", deviceSerial,
            "shell", "am", "start", "-W",
            "-a", "android.intent.action.VIEW",
            "-d", deepLink.uri,
        ]
        if let targetPackageID = deepLink.targetPackageID {
            arguments.append(contentsOf: ["-p", targetPackageID])
        }

        let result = await processRunner.run(executablePath: adbPath, arguments: arguments)
        guard result.succeeded else {
            let message = failureMessage(from: result)
            AppLogger.deepLinks.error("Android deep link launch failed: \(message, privacy: .public)")
            return .failure(.commandFailed(message))
        }

        let standardOutput = String(decoding: result.standardOutput, as: UTF8.self)
        if let errorMessage = androidActivityError(in: standardOutput) {
            AppLogger.deepLinks.error("Android deep link launch failed: \(errorMessage, privacy: .public)")
            return .failure(.commandFailed(errorMessage))
        }

        AppLogger.deepLinks.info("Android deep link launched")
        return .success(AndroidDeepLinkLaunchOutcome(deepLink: deepLink, deviceSerial: deviceSerial))
    }

    private func androidActivityError(in output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                line.hasPrefix("Error:") || line.hasPrefix("Error type")
            }
    }

    private func failureMessage(from result: ProcessResult) -> String {
        if result.wasCancelled {
            return "Opening the link was cancelled."
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
