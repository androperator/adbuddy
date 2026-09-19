import Foundation
@testable import ADBuddyCore

actor TestScreenRecordingCapture: ScreenRecordingCapturing {
    struct Request {
        let outputSize: AndroidDisplaySize?
        let bitRate: Int
    }
    private(set) var requests: [Request] = []
    private(set) var stoppedSessions: [ScreenRecordingSession] = []
    private let writesFile: Bool
    private let fails: Bool

    init(writesFile: Bool = false, fails: Bool = false) {
        self.writesFile = writesFile
        self.fails = fails
    }

    func record(
        session: ScreenRecordingSession,
        bitRateBitsPerSecond: Int,
        outputSize: AndroidDisplaySize?,
        outputURL: URL,
        onStarted: @escaping @MainActor @Sendable () -> Void
    ) async -> ProcessResult {
        requests.append(Request(outputSize: outputSize, bitRate: bitRateBitsPerSecond))
        await onStarted()
        if writesFile { try? Data("test recording".utf8).write(to: outputURL) }
        return ProcessResult(
            standardOutput: Data(), standardError: Data(), exitStatus: fails ? 1 : 0,
            durationMilliseconds: 1, failureDescription: nil, wasCancelled: false
        )
    }

    func stop(session: ScreenRecordingSession) async -> ScreenRecordingStopResult {
        stoppedSessions.append(session)
        return .stopped
    }
}
