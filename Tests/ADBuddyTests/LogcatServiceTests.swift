import Foundation
import XCTest
@testable import ADBuddy

final class LogcatServiceTests: XCTestCase {
    func testUsesFixedADBArgumentsAndParsesEntriesAcrossChunks() async {
        let runner = RecordingStreamingProcessRunner(events: [
            .standardOutput(Data("08-22 13:14:15.001   101   201 D Tag: first".utf8)),
            .standardOutput(Data(" message\n08-22 13:14:15.002   102   202 E Tag: second\n".utf8)),
            .terminated(exitStatus: 0, standardError: Data()),
        ])
        let service = LogcatService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: runner,
            batchSize: 10
        )

        let events = await collectEvents(from: service.stream(for: "device-serial"))
        let entries = events.flatMap { event -> [LogcatEntry] in
            guard case .entries(let entries) = event else {
                return []
            }
            return entries
        }

        XCTAssertEqual(
            runner.invocations,
            [
                StreamingProcessInvocation(
                    executablePath: "/SDK/platform-tools/adb",
                    arguments: ["-s", "device-serial", "logcat", "-v", "threadtime", "-T", "5000"]
                ),
            ]
        )
        XCTAssertEqual(entries.map(\.message), ["first message", "second"])
        XCTAssertEqual(entries.map(\.priority), [.debug, .error])
        XCTAssertEqual(events.last, .stopped)
    }

    func testFlushesLowVolumeEntriesWithoutWaitingForTermination() async {
        let runner = RecordingStreamingProcessRunner(
            events: [
                .standardOutput(Data("08-22 13:14:15.001   101   201 I Tag: message\n".utf8)),
            ],
            finishesAfterEvents: false
        )
        let service = LogcatService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: runner,
            batchSize: 10,
            batchFlushInterval: .milliseconds(10)
        )

        let event = await firstEvent(from: service.stream(for: "device-serial"))

        guard case .entries(let entries) = event else {
            return XCTFail("Expected a low-volume batch")
        }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].priority, .info)
        XCTAssertEqual(entries[0].processID, 101)
        XCTAssertEqual(entries[0].threadID, 201)
        XCTAssertEqual(entries[0].tag, "Tag")
        XCTAssertEqual(entries[0].message, "message")
    }

    func testAddsUserIDFilterToTheFixedADBArguments() async {
        let runner = RecordingStreamingProcessRunner(events: [
            .terminated(exitStatus: 0, standardError: Data()),
        ])
        let service = LogcatService(adbPath: "/SDK/platform-tools/adb", processRunner: runner)

        _ = await collectEvents(
            from: service.stream(for: "device-serial", scope: .userID(10374))
        )

        XCTAssertEqual(
            runner.invocations.first?.arguments,
            ["-s", "device-serial", "logcat", "-v", "threadtime", "-T", "5000", "--uid=10374"]
        )
    }

    func testMapsFailuresAndCancellationWithoutRawTextEvents() async {
        let launchFailure = await collectEvents(
            from: LogcatService(
                adbPath: "/SDK/platform-tools/adb",
                processRunner: RecordingStreamingProcessRunner(events: [.launchFailed("not executable")])
            ).stream(for: "device-serial")
        )
        let terminationFailure = await collectEvents(
            from: LogcatService(
                adbPath: "/SDK/platform-tools/adb",
                processRunner: RecordingStreamingProcessRunner(events: [
                    .terminated(exitStatus: 1, standardError: Data("device offline\n".utf8)),
                ])
            ).stream(for: "device-serial")
        )
        let cancellation = await collectEvents(
            from: LogcatService(
                adbPath: "/SDK/platform-tools/adb",
                processRunner: RecordingStreamingProcessRunner(events: [.cancelled])
            ).stream(for: "device-serial")
        )

        XCTAssertEqual(launchFailure.last, .failed(.launchFailed("not executable")))
        XCTAssertEqual(
            terminationFailure.last,
            .failed(.terminated(exitStatus: 1, standardError: "device offline"))
        )
        XCTAssertEqual(cancellation.last, .cancelled)
    }

    private func collectEvents(from stream: AsyncStream<LogcatServiceEvent>) async -> [LogcatServiceEvent] {
        var events: [LogcatServiceEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }

    private func firstEvent(from stream: AsyncStream<LogcatServiceEvent>) async -> LogcatServiceEvent? {
        for await event in stream {
            return event
        }
        return nil
    }
}

private struct StreamingProcessInvocation: Equatable {
    let executablePath: String
    let arguments: [String]
}

private final class RecordingStreamingProcessRunner: StreamingProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let events: [StreamingProcessEvent]
    private let finishesAfterEvents: Bool
    private var recordedInvocations: [StreamingProcessInvocation] = []

    init(events: [StreamingProcessEvent], finishesAfterEvents: Bool = true) {
        self.events = events
        self.finishesAfterEvents = finishesAfterEvents
    }

    var invocations: [StreamingProcessInvocation] {
        lock.lock()
        defer { lock.unlock() }
        return recordedInvocations
    }

    func stream(executablePath: String, arguments: [String]) -> AsyncStream<StreamingProcessEvent> {
        lock.lock()
        recordedInvocations.append(
            StreamingProcessInvocation(executablePath: executablePath, arguments: arguments)
        )
        lock.unlock()

        return AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            if finishesAfterEvents {
                continuation.finish()
            }
        }
    }
}
