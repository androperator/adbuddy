import Foundation

public struct ScreenRecordingBackendResult: Sendable {
    public let processResult: ProcessResult
    public let clipURLs: [URL]

    public init(processResult: ProcessResult, clipURLs: [URL]) {
        self.processResult = processResult
        self.clipURLs = clipURLs
    }
}

/// Captures completed temporary MP4 clips. The service owns naming, taps, and framing.
public protocol ScreenRecordingCapturing: Sendable {
    func record(
        session: ScreenRecordingSession,
        bitRateBitsPerSecond: Int,
        outputSize: AndroidDisplaySize?,
        outputURL: URL,
        onStarted: @escaping @MainActor @Sendable () -> Void
    ) async -> ScreenRecordingBackendResult
    func stop(session: ScreenRecordingSession) async -> ScreenRecordingStopResult
}

public struct ScrcpyScreenRecordingCapture: ScreenRecordingCapturing {
    // Services are recreated for Stop, so recording processes must have shared ownership.
    private static let processRunner = ProcessRunner()
    private let adbPath: String
    private let executableURL: URL
    private let serverURL: URL

    public init(adbPath: String, backendDirectory: URL? = nil) {
        self.adbPath = adbPath
        let backend = ScrcpyBackend(backendDirectory: backendDirectory)
        executableURL = backend.executableURL
        serverURL = backend.serverURL
    }

    public func record(
        session: ScreenRecordingSession,
        bitRateBitsPerSecond: Int,
        outputSize: AndroidDisplaySize?,
        outputURL: URL,
        onStarted: @escaping @MainActor @Sendable () -> Void
    ) async -> ScreenRecordingBackendResult {
        let executable = executableURL
        let server = serverURL
        guard FileManager.default.isExecutableFile(atPath: executable.path),
              FileManager.default.fileExists(atPath: server.path) else {
            return ScreenRecordingBackendResult(processResult: ProcessResult(
                standardOutput: Data(), standardError: Data(), exitStatus: nil,
                durationMilliseconds: 0,
                failureDescription: "The bundled screen recorder is missing. Rebuild or reinstall ADBuddy.",
                wasCancelled: false
            ), clipURLs: [])
        }
        var environment = ProcessInfo.processInfo.environment
        environment["ADB"] = adbPath
        environment["SCRCPY_SERVER_PATH"] = server.path
        environment["ADBUDDY_RECORDING_SEGMENTS"] = "1"
        AppLogger.recording.info("Starting rotation-aware screen capture")
        let result = await Self.processRunner.run(
            executablePath: executable.path,
            arguments: Self.arguments(
                serial: session.device.serial,
                bitRateBitsPerSecond: bitRateBitsPerSecond,
                outputSize: outputSize,
                outputURL: outputURL
            ),
            identifier: session.identifier,
            environment: environment,
            onStarted: onStarted
        )
        var clips: [URL] = []
        var index = 1
        while true {
            let clipURL = URL(fileURLWithPath: outputURL.path + String(format: ".%04d.mp4", index))
            try? FileManager.default.removeItem(at: clipURL.appendingPathExtension("inprogress"))
            guard FileManager.default.fileExists(atPath: clipURL.path) else { break }
            clips.append(clipURL)
            index += 1
        }
        return ScreenRecordingBackendResult(processResult: result, clipURLs: clips)
    }

    static func arguments(
        serial: String,
        bitRateBitsPerSecond: Int,
        outputSize: AndroidDisplaySize?,
        outputURL: URL
    ) -> [String] {
        var arguments = [
            "--serial=\(serial)",
            "--no-window", "--no-audio", "--no-control",
            // Fix the canvas to the physical device, while allowing its content to rotate.
            "--capture-orientation=@0",
            "--video-codec=h264",
            "--video-bit-rate=\(bitRateBitsPerSecond)",
            "--record-format=mp4", "--record=\(outputURL.path)",
            "--time-limit=180",
        ]
        if let outputSize {
            arguments.append("--max-size=\(max(outputSize.width, outputSize.height))")
        }
        return arguments
    }

    public func stop(session: ScreenRecordingSession) async -> ScreenRecordingStopResult {
        // SIGINT lets the local muxer finalize its MP4. Never signal another session.
        if Self.processRunner.interrupt(identifier: session.identifier) {
            AppLogger.recording.info("Interrupted screen capture to finalize MP4")
        }
        // A recorder that reached its time limit may already have exited.
        return .stopped
    }
}
