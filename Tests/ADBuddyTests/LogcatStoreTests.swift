import Foundation
import XCTest
@testable import ADBuddy

@MainActor
final class LogcatStoreTests: XCTestCase {
    func testWaitsForADBResolutionBeforeStartingTheStream() async throws {
        let service = ControllableLogcatService()
        let store = LogcatStore(deviceSerial: "device-serial", makeService: { _ in service })

        store.start(adbPath: nil)

        XCTAssertEqual(store.streamState, .connecting)
        XCTAssertEqual(service.streamCount, 0)

        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForStreamCount(service, expectedCount: 1)
    }

    func testStartsOnlyOneStreamAndRetainsEntriesAfterFailure() async throws {
        let service = ControllableLogcatService()
        let store = LogcatStore(deviceSerial: "device-serial", makeService: { _ in service })

        store.start(adbPath: "/SDK/platform-tools/adb")
        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForStreamCount(service, expectedCount: 1)

        service.yield(.entries([entry(id: 1)]))
        service.yield(.failed(.terminated(exitStatus: 1, standardError: "device offline")))
        try await waitForState(store, matching: .failed("Logcat exited with status 1: device offline"))

        XCTAssertEqual(store.entries, [entry(id: 1)])
        XCTAssertEqual(service.streamCount, 1)
    }

    func testCapsRetainedEntriesAtFiftyThousand() async throws {
        let service = ControllableLogcatService()
        let store = LogcatStore(deviceSerial: "device-serial", makeService: { _ in service })
        let entries = (1...50_600).map(entry)

        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForStreamCount(service, expectedCount: 1)
        service.yield(.entries(entries))
        try await waitForEntryCount(store, expectedCount: LogcatStore.retentionLimit)

        XCTAssertEqual(store.entries.first?.id, 601)
        XCTAssertEqual(store.entries.last?.id, 50_600)
    }

    func testStopCancelsOnlyTheWindowStreamAndReportsStopped() async throws {
        let service = ControllableLogcatService()
        let store = LogcatStore(deviceSerial: "device-serial", makeService: { _ in service })

        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForStreamCount(service, expectedCount: 1)
        store.stop()

        XCTAssertEqual(store.streamState, .stopped)
        try await waitForCancellation(of: service)
    }

    private func entry(id: UInt64) -> LogcatEntry {
        LogcatEntry(
            id: id,
            timestamp: Date(timeIntervalSince1970: TimeInterval(id)),
            priority: .debug,
            processID: 101,
            threadID: 201,
            tag: "Tag",
            message: "Message \(id)"
        )
    }

    private func waitForStreamCount(_ service: ControllableLogcatService, expectedCount: Int) async throws {
        for _ in 0..<40 {
            if service.streamCount == expectedCount {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected \(expectedCount) Logcat stream starts")
    }

    private func waitForState(_ store: LogcatStore, matching expectedState: LogcatStreamState) async throws {
        for _ in 0..<40 {
            if store.streamState == expectedState {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected Logcat state \(expectedState)")
    }

    private func waitForEntryCount(_ store: LogcatStore, expectedCount: Int) async throws {
        for _ in 0..<80 {
            if store.entries.count == expectedCount {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected \(expectedCount) retained Logcat entries")
    }

    private func waitForCancellation(of service: ControllableLogcatService) async throws {
        for _ in 0..<40 {
            if service.wasCancelled {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected the Logcat stream to be cancelled")
    }
}

private final class ControllableLogcatService: LogcatStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<LogcatServiceEvent>.Continuation?
    private var recordedStreamCount = 0
    private var cancelled = false

    var streamCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedStreamCount
    }

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func stream(for deviceSerial: String) -> AsyncStream<LogcatServiceEvent> {
        lock.lock()
        recordedStreamCount += 1
        lock.unlock()

        return AsyncStream { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            continuation.onTermination = { @Sendable _ in
                self.lock.lock()
                self.cancelled = true
                self.lock.unlock()
            }
        }
    }

    func yield(_ event: LogcatServiceEvent) {
        lock.lock()
        let continuation = continuation
        lock.unlock()
        continuation?.yield(event)
    }
}
