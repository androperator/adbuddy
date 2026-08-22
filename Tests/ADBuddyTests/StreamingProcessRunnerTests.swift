import Foundation
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

final class StreamingProcessRunnerTests: XCTestCase {
    func testDeliversMultipleStandardOutputChunksBeforeNormalTermination() async {
        let events = await Self.collectEvents(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf first; sleep 1; printf second"]
        )

        let chunks = events.compactMap { event -> Data? in
            guard case .standardOutput(let data) = event else {
                return nil
            }
            return data
        }

        XCTAssertGreaterThanOrEqual(chunks.count, 2)
        XCTAssertEqual(String(decoding: chunks.joined(), as: UTF8.self), "firstsecond")
        XCTAssertEqual(events.last, .terminated(exitStatus: 0, standardError: Data()))
    }

    func testReportsLaunchFailureAndNonzeroTerminationSeparately() async {
        let launchFailureEvents = await Self.collectEvents(
            executablePath: "/not/a/real/executable",
            arguments: []
        )
        let exitFailureEvents = await Self.collectEvents(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf failed >&2; exit 7"]
        )

        guard case .launchFailed = launchFailureEvents.last else {
            return XCTFail("Expected a launch failure")
        }
        XCTAssertEqual(
            exitFailureEvents.last,
            .terminated(exitStatus: 7, standardError: Data("failed".utf8))
        )
    }

    func testCancellingOneStreamTerminatesOnlyItsOwnedProcess() async throws {
        let runner = StreamingProcessRunner()
        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("adbuddy-stream-cancelled-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: markerURL)
        }

        let cancelledStream = Task {
            for await _ in runner.stream(
                executablePath: "/bin/sh",
                arguments: [
                    "-c",
                    "printf ready; trap 'touch \"$1\"; exit 0' TERM; while :; do sleep 0.1; done",
                    "streaming-process",
                    markerURL.path,
                ]
            ) {}
        }
        async let unaffectedEvents = Self.collectEvents(
            executablePath: "/bin/sh",
            arguments: ["-c", "sleep 1; printf unaffected"]
        )

        try await Task.sleep(for: .milliseconds(150))
        cancelledStream.cancel()
        await cancelledStream.value

        try await waitForFile(at: markerURL)
        let completedUnaffectedEvents = await unaffectedEvents
        let unaffectedOutput = completedUnaffectedEvents.compactMap { event -> Data? in
            guard case .standardOutput(let data) = event else {
                return nil
            }
            return data
        }

        XCTAssertEqual(String(decoding: unaffectedOutput.joined(), as: UTF8.self), "unaffected")
        XCTAssertEqual(completedUnaffectedEvents.last, .terminated(exitStatus: 0, standardError: Data()))
    }

    private static func collectEvents(executablePath: String, arguments: [String]) async -> [StreamingProcessEvent] {
        var events: [StreamingProcessEvent] = []
        for await event in StreamingProcessRunner().stream(executablePath: executablePath, arguments: arguments) {
            events.append(event)
        }
        return events
    }

    private func waitForFile(at url: URL) async throws {
        for _ in 0..<40 {
            if FileManager.default.fileExists(atPath: url.path) {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("The cancelled stream did not terminate its owned process")
    }
}
