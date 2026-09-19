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
    private let clipCount: Int
    private let retainsClipsOnFailure: Bool

    init(writesFile: Bool = false, fails: Bool = false, clipCount: Int = 1, retainsClipsOnFailure: Bool = false) {
        self.writesFile = writesFile
        self.fails = fails
        self.clipCount = clipCount
        self.retainsClipsOnFailure = retainsClipsOnFailure
    }

    func record(
        session: ScreenRecordingSession,
        bitRateBitsPerSecond: Int,
        outputSize: AndroidDisplaySize?,
        outputURL: URL,
        onStarted: @escaping @MainActor @Sendable () -> Void
    ) async -> ScreenRecordingBackendResult {
        requests.append(Request(outputSize: outputSize, bitRate: bitRateBitsPerSecond))
        await onStarted()
        let clips = (0..<clipCount).map { index in
            clipCount == 1 ? outputURL : outputURL.appendingPathExtension("\(index).mp4")
        }
        if writesFile {
            for url in clips { try? Data("test recording".utf8).write(to: url) }
        }
        return ScreenRecordingBackendResult(processResult: ProcessResult(
            standardOutput: Data(), standardError: Data(), exitStatus: fails ? 1 : 0,
            durationMilliseconds: 1, failureDescription: nil, wasCancelled: false
        ), clipURLs: fails && !retainsClipsOnFailure ? [] : clips)
    }

    func stop(session: ScreenRecordingSession) async -> ScreenRecordingStopResult {
        stoppedSessions.append(session)
        return .stopped
    }
}
