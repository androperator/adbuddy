import Foundation

struct ScrcpyBackend: Sendable {
    let executableURL: URL
    let serverURL: URL

    init(backendDirectory: URL? = nil) {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let contents = executable.deletingLastPathComponent().deletingLastPathComponent()
        executableURL = backendDirectory?.appendingPathComponent("scrcpy")
            ?? contents.appendingPathComponent("MacOS/scrcpy-\(architecture)")
        serverURL = backendDirectory?.appendingPathComponent("scrcpy-server")
            ?? contents.appendingPathComponent("Resources/Recording/\(architecture)/scrcpy-server")
    }
}

public protocol DeviceMirroring: Sendable {
    func mirror(
        device: AndroidDevice,
        adbPath: String,
        onStarted: @escaping @MainActor @Sendable (Int32) -> Void
    ) async -> ProcessResult
}

public struct ScrcpyMirroring: DeviceMirroring {
    private let runner = ProcessRunner()
    private let backend: ScrcpyBackend

    public init(backendDirectory: URL? = nil) {
        backend = ScrcpyBackend(backendDirectory: backendDirectory)
    }

    public func mirror(
        device: AndroidDevice,
        adbPath: String,
        onStarted: @escaping @MainActor @Sendable (Int32) -> Void
    ) async -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: backend.executableURL.path),
              FileManager.default.fileExists(atPath: backend.serverURL.path) else {
            return ProcessResult(
                standardOutput: Data(), standardError: Data(), exitStatus: nil,
                durationMilliseconds: 0,
                failureDescription: "The bundled device mirror is missing. Rebuild or reinstall ADBuddy.",
                wasCancelled: false
            )
        }
        let identifier = UUID().uuidString
        var environment = ProcessInfo.processInfo.environment
        environment["ADB"] = adbPath
        environment["SCRCPY_SERVER_PATH"] = backend.serverURL.path
        environment["SCRCPY_ICON_DIR"] = backend.serverURL.deletingLastPathComponent().path
        environment.removeValue(forKey: "ADBUDDY_RECORDING_SEGMENTS")
        return await runner.run(
            executablePath: backend.executableURL.path,
            arguments: Self.arguments(device: device),
            identifier: identifier,
            environment: environment,
            onStarted: {
                if let pid = runner.processIdentifier(identifier: identifier) {
                    onStarted(pid)
                }
            }
        )
    }

    static func arguments(device: AndroidDevice) -> [String] {
        [
            "--serial=\(device.serial)",
            "--window-title=\(device.displayName) — ADBuddy",
            "--no-audio", "--video-codec=h264",
            "--no-clipboard-autosync",
        ]
    }
}
