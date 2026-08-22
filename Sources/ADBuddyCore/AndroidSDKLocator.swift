import Foundation

public struct AndroidSDK: Equatable, Sendable {
    public let rootPath: String
    public let adbPath: String
    public let source: AndroidSDKSource

    public init(rootPath: String, adbPath: String, source: AndroidSDKSource) {
        self.rootPath = rootPath
        self.adbPath = adbPath
        self.source = source
    }
}

public enum AndroidSDKSource: Equatable, Sendable {
    case androidHome
    case androidSDKRoot
    case standardLocation
}

public enum AndroidSDKFailure: Equatable, Sendable {
    case sdkNotFound
    case adbNotFound

    public var title: String {
        switch self {
        case .sdkNotFound:
            "Android SDK Not Found"
        case .adbNotFound:
            "ADB Not Found"
        }
    }

    public var detail: String {
        switch self {
        case .sdkNotFound:
            "Set ANDROID_HOME or ANDROID_SDK_ROOT, or install the Android SDK in ~/Library/Android/sdk."
        case .adbNotFound:
            "An Android SDK location was found, but platform-tools/adb is missing or is not executable."
        }
    }
}

public enum AndroidSDKResolution: Equatable, Sendable {
    case found(AndroidSDK)
    case unavailable(AndroidSDKFailure)
}

public struct AndroidSDKLocator: Sendable {
    private let environment: [String: String]
    private let homeDirectoryPath: String
    private let pathExists: @Sendable (String) -> Bool
    private let isExecutable: @Sendable (String) -> Bool

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path,
        pathExists: @escaping @Sendable (String) -> Bool = { path in
            FileManager.default.fileExists(atPath: path)
        },
        isExecutable: @escaping @Sendable (String) -> Bool = { path in
            FileManager.default.isExecutableFile(atPath: path)
        }
    ) {
        self.environment = environment
        self.homeDirectoryPath = homeDirectoryPath
        self.pathExists = pathExists
        self.isExecutable = isExecutable
    }

    public func resolve() -> AndroidSDKResolution {
        var foundSDKDirectory = false

        for candidate in candidates {
            if pathExists(candidate.rootPath) {
                foundSDKDirectory = true
            }

            let adbPath = URL(fileURLWithPath: candidate.rootPath)
                .appendingPathComponent("platform-tools", isDirectory: true)
                .appendingPathComponent("adb")
                .path

            if isExecutable(adbPath) {
                AppLogger.androidSDK.debug("Resolved ADB from \(candidate.source.logName, privacy: .public)")
                return .found(
                    AndroidSDK(
                        rootPath: candidate.rootPath,
                        adbPath: adbPath,
                        source: candidate.source
                    )
                )
            }
        }

        let failure: AndroidSDKFailure = foundSDKDirectory ? .adbNotFound : .sdkNotFound
        AppLogger.androidSDK.error("Android SDK resolution failed: \(failure.title, privacy: .public)")
        return .unavailable(failure)
    }

    private var candidates: [Candidate] {
        var candidates: [Candidate] = []
        var seenPaths = Set<String>()

        func appendCandidate(_ rootPath: String?, source: AndroidSDKSource) {
            guard let rootPath else {
                return
            }

            let trimmedPath = rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPath.isEmpty, seenPaths.insert(trimmedPath).inserted else {
                return
            }

            candidates.append(Candidate(rootPath: trimmedPath, source: source))
        }

        appendCandidate(environment["ANDROID_HOME"], source: .androidHome)
        appendCandidate(environment["ANDROID_SDK_ROOT"], source: .androidSDKRoot)
        appendCandidate(
            URL(fileURLWithPath: homeDirectoryPath)
                .appendingPathComponent("Library/Android/sdk", isDirectory: true)
                .path,
            source: .standardLocation
        )

        return candidates
    }
}

private struct Candidate: Sendable {
    let rootPath: String
    let source: AndroidSDKSource
}

private extension AndroidSDKSource {
    var logName: String {
        switch self {
        case .androidHome:
            "ANDROID_HOME"
        case .androidSDKRoot:
            "ANDROID_SDK_ROOT"
        case .standardLocation:
            "standard location"
        }
    }
}
