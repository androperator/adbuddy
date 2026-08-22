import Foundation
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

@MainActor
final class LogcatStoreTests: XCTestCase {
    func testFiltersEveryMinimumPriorityWithoutDiscardingEntries() async throws {
        let service = ControllableLogcatService()
        let store = makeStore(service: service)
        let entries = LogcatPriority.allCases.enumerated().map { index, priority in
            entry(id: UInt64(index + 1), priority: priority)
        }

        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForStreamCount(service, expectedCount: 1)
        service.yield(.entries(entries))
        try await waitForEntryCount(store, expectedCount: entries.count)

        XCTAssertEqual(store.minimumPriority, .debug)
        XCTAssertEqual(store.visibleEntries.map(\.priority), [.debug, .info, .warn, .error, .assert])

        for minimumPriority in LogcatPriority.allCases {
            store.minimumPriority = minimumPriority
            XCTAssertEqual(
                store.visibleEntries.map(\.priority),
                LogcatPriority.allCases.filter { $0.severity >= minimumPriority.severity }
            )
        }

        store.minimumPriority = .info
        service.yield(.entries([entry(id: 7, priority: .debug)]))
        try await waitForEntryCount(store, expectedCount: 7)

        XCTAssertEqual(store.entries.count, 7)
        XCTAssertFalse(store.visibleEntries.contains(where: { $0.id == 7 }))
    }

    func testFilteringRebuildsVisibleRowsWithoutReenablingFollowMode() async throws {
        let service = ControllableLogcatService()
        let store = makeStore(service: service)
        let entries = LogcatPriority.allCases.enumerated().map { index, priority in
            entry(id: UInt64(index + 1), priority: priority)
        }

        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForStreamCount(service, expectedCount: 1)
        service.yield(.entries(entries))
        try await waitForEntryCount(store, expectedCount: entries.count)
        store.userScrolledAwayFromLatest()
        let revisionBeforeFiltering = store.displayedEntryRevision

        store.minimumPriority = .error

        XCTAssertFalse(store.isFollowing)
        XCTAssertEqual(store.visibleEntries.map(\.priority), [.error, .assert])
        XCTAssertGreaterThan(store.displayedEntryRevision, revisionBeforeFiltering)
        store.stop()
    }

    func testSearchFiltersTagsAndMessagesWithoutRestartingTheStream() async throws {
        let service = ControllableLogcatService()
        let store = makeStore(service: service)
        let entries = [
            LogcatEntry(
                id: 1,
                timestamp: .now,
                priority: .debug,
                processID: 101,
                threadID: 201,
                tag: "NetworkClient",
                message: "Request succeeded"
            ),
            LogcatEntry(
                id: 2,
                timestamp: .now,
                priority: .info,
                processID: 102,
                threadID: 202,
                tag: "Activity",
                message: "Loaded search result"
            ),
            LogcatEntry(
                id: 3,
                timestamp: .now,
                priority: .warn,
                processID: 103,
                threadID: 203,
                tag: "Database",
                message: "Retrying query"
            ),
        ]

        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForStreamCount(service, expectedCount: 1)
        service.yield(.entries(entries))
        try await waitForEntryCount(store, expectedCount: entries.count)

        store.searchText = "network"
        XCTAssertEqual(store.visibleEntries.map(\.id), [1])

        store.searchText = "SEARCH"
        XCTAssertEqual(store.visibleEntries.map(\.id), [2])

        store.searchText = "   "
        XCTAssertEqual(store.visibleEntries.map(\.id), [1, 2, 3])
        XCTAssertEqual(store.entries, entries)
        XCTAssertEqual(service.streamCount, 1)
        store.stop()
    }

    func testCrashAndExceptionFilterKeepsStackTracesWithoutRestartingTheStream() async throws {
        let service = ControllableLogcatService()
        let store = makeStore(service: service)
        let entries = [
            LogcatEntry(
                id: 1,
                timestamp: .now,
                priority: .info,
                processID: 101,
                threadID: 201,
                tag: "Activity",
                message: "Resumed activity"
            ),
            LogcatEntry(
                id: 2,
                timestamp: .now,
                priority: .warn,
                processID: 101,
                threadID: 201,
                tag: "System.err",
                message: "java.lang.IllegalStateException: Unexpected state"
            ),
            LogcatEntry(
                id: 3,
                timestamp: .now,
                priority: .warn,
                processID: 101,
                threadID: 201,
                tag: "System.err",
                message: "at com.example.app.MainActivity.onCreate(MainActivity.kt:42)"
            ),
            LogcatEntry(
                id: 4,
                timestamp: .now,
                priority: .error,
                processID: 101,
                threadID: 201,
                tag: "AndroidRuntime",
                message: "FATAL EXCEPTION: main"
            ),
            LogcatEntry(
                id: 5,
                timestamp: .now,
                priority: .error,
                processID: 101,
                threadID: 201,
                tag: "AndroidRuntime",
                message: "at android.app.ActivityThread.main(ActivityThread.java:8000)"
            ),
            LogcatEntry(
                id: 6,
                timestamp: .now,
                priority: .debug,
                processID: 102,
                threadID: 202,
                tag: "ActivityManager",
                message: "ANR in com.example.app"
            ),
        ]

        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForStreamCount(service, expectedCount: 1)
        service.yield(.entries(entries))
        try await waitForEntryCount(store, expectedCount: entries.count)

        XCTAssertFalse(store.showsOnlyCrashesAndExceptions)
        store.showsOnlyCrashesAndExceptions = true

        XCTAssertEqual(store.visibleEntries.map(\.id), [2, 3, 4, 5, 6])
        XCTAssertEqual(store.entries, entries)
        XCTAssertEqual(service.streamCount, 1)
        store.stop()
    }

    func testWaitsForADBResolutionBeforeStartingTheStream() async throws {
        let service = ControllableLogcatService()
        let store = makeStore(service: service)

        store.start(adbPath: nil)

        XCTAssertEqual(store.streamState, .connecting)
        XCTAssertEqual(service.streamCount, 0)

        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForStreamCount(service, expectedCount: 1)
    }

    func testStartsOnlyOneStreamAndRetainsEntriesAfterFailure() async throws {
        let service = ControllableLogcatService()
        let store = makeStore(service: service)

        store.start(adbPath: "/SDK/platform-tools/adb")
        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForStreamCount(service, expectedCount: 1)

        service.yield(.entries([entry(id: 1)]))
        service.yield(.failed(.terminated(exitStatus: 1, standardError: "device offline")))
        try await waitForState(store, matching: .failed("Logcat exited with status 1: device offline"))

        XCTAssertEqual(store.entries, [entry(id: 1)])
        XCTAssertEqual(service.streamCount, 1)
        store.stop()
    }

    func testDisconnectRetainsEntriesAndReconnectsTheSameWindow() async throws {
        let service = ControllableLogcatService()
        let store = makeStore(service: service)

        store.updateDeviceAvailability(.usable(adbPath: "/SDK/platform-tools/adb"))
        try await waitForStreamCount(service, expectedCount: 1)
        service.yield(.entries([entry(id: 1)]))
        try await waitForEntryCount(store, expectedCount: 1)

        store.updateDeviceAvailability(.unavailable)
        XCTAssertEqual(store.streamState, .disconnected)
        XCTAssertEqual(store.entries, [entry(id: 1)])
        try await waitForCancellation(of: service)

        store.updateDeviceAvailability(.usable(adbPath: "/SDK/platform-tools/adb"))
        try await waitForStreamCount(service, expectedCount: 2)
        XCTAssertEqual(store.entries, [entry(id: 1)])
        store.stop()
    }

    func testUnexpectedFailuresReconnectAfterTheConfiguredDelay() async throws {
        let service = ControllableLogcatService()
        let store = makeStore(
            service: service,
            reconnectDelay: { _ in .milliseconds(20) }
        )

        store.updateDeviceAvailability(.usable(adbPath: "/SDK/platform-tools/adb"))
        try await waitForStreamCount(service, expectedCount: 1)
        service.yield(.failed(.terminated(exitStatus: 1, standardError: "device offline")))
        try await waitForState(store, matching: .failed("Logcat exited with status 1: device offline"))

        try await waitForStreamCount(service, expectedCount: 2)
        store.stop()
    }

    func testStopPreventsAPendingReconnectAfterFailure() async throws {
        let service = ControllableLogcatService()
        let store = makeStore(
            service: service,
            reconnectDelay: { _ in .milliseconds(40) }
        )

        store.updateDeviceAvailability(.usable(adbPath: "/SDK/platform-tools/adb"))
        try await waitForStreamCount(service, expectedCount: 1)
        service.yield(.failed(.terminated(exitStatus: 1, standardError: "device offline")))
        try await waitForState(store, matching: .failed("Logcat exited with status 1: device offline"))

        store.stop()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(service.streamCount, 1)
        XCTAssertEqual(store.streamState, .stopped)
    }

    func testReconnectPolicyUsesBoundedExponentialDelays() {
        XCTAssertEqual(LogcatReconnectPolicy.delay(for: 1), .seconds(1))
        XCTAssertEqual(LogcatReconnectPolicy.delay(for: 2), .seconds(2))
        XCTAssertEqual(LogcatReconnectPolicy.delay(for: 3), .seconds(4))
        XCTAssertEqual(LogcatReconnectPolicy.delay(for: 4), .seconds(8))
        XCTAssertEqual(LogcatReconnectPolicy.delay(for: 20), .seconds(8))
    }

    func testCapsRetainedEntriesAtFiftyThousand() async throws {
        let service = ControllableLogcatService()
        let store = makeStore(service: service)
        let entries = (1...50_600).map { entry(id: UInt64($0)) }

        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForStreamCount(service, expectedCount: 1)
        service.yield(.entries(entries))
        try await waitForEntryCount(store, expectedCount: LogcatStore.retentionLimit)

        XCTAssertEqual(store.entries.first?.id, 601)
        XCTAssertEqual(store.entries.last?.id, 50_600)
    }

    func testProcessesSustainedBatchesWithoutExceedingRetention() async throws {
        let service = ControllableLogcatService()
        let store = makeStore(service: service)
        let batchSize = 250
        let batchCount = 240

        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForStreamCount(service, expectedCount: 1)

        for batch in 0..<batchCount {
            let firstID = batch * batchSize + 1
            let entries = (firstID..<firstID + batchSize).map { entry(id: UInt64($0)) }
            service.yield(.entries(entries))
        }

        try await waitForLastEntryID(store, expectedID: UInt64(batchSize * batchCount))
        XCTAssertEqual(store.entries.count, LogcatStore.retentionLimit)
        XCTAssertEqual(store.visibleEntries.count, LogcatStore.retentionLimit)
        store.stop()
    }

    func testStopCancelsOnlyTheWindowStreamAndReportsStopped() async throws {
        let service = ControllableLogcatService()
        let store = makeStore(service: service)

        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForStreamCount(service, expectedCount: 1)
        store.stop()

        XCTAssertEqual(store.streamState, .stopped)
        try await waitForCancellation(of: service)
    }

    func testApplicationSelectionUsesUIDScopeForPrimaryAndSecondaryProcesses() async throws {
        let service = ControllableLogcatService()
        let applicationService = ControllableLogcatApplicationService(
            processes: [
                AndroidRunningProcess(userID: 10374, processID: 101, name: "com.example.app"),
                AndroidRunningProcess(userID: 10374, processID: 102, name: "com.example.app:worker"),
            ],
            packageUserID: 10374
        )
        let store = makeStore(service: service, applicationService: applicationService)

        store.selectApplicationID("com.example.app")
        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForScope(of: service, matching: .userID(10374))

        service.yield(.entries([
            entry(id: 1, processID: 101),
            entry(id: 2, processID: 102),
        ]))
        try await waitForEntryCount(store, expectedCount: 2)

        XCTAssertEqual(store.runningApplicationIDs, ["com.example.app"])
        XCTAssertEqual(store.visibleEntries.map(\.processID), [101, 102])
        store.stop()
    }

    func testPIDFilteringIncludesSecondaryProcessesAndRecoversAfterRestart() async throws {
        let service = ControllableLogcatService()
        let applicationService = ControllableLogcatApplicationService(
            processes: [
                AndroidRunningProcess(userID: 10374, processID: 101, name: "com.example.app"),
                AndroidRunningProcess(userID: 10374, processID: 102, name: "com.example.app:worker"),
            ],
            packageUserID: nil
        )
        let store = makeStore(service: service, applicationService: applicationService)

        store.selectApplicationID("com.example.app")
        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForScope(of: service, matching: .allApplications)

        service.yield(.entries([
            entry(id: 1, processID: 101),
            entry(id: 2, processID: 102),
            entry(id: 3, processID: 999),
        ]))
        try await waitForEntryCount(store, expectedCount: 3)
        XCTAssertEqual(store.visibleEntries.map(\.processID), [101, 102])

        applicationService.setProcesses([
            AndroidRunningProcess(userID: 10374, processID: 303, name: "com.example.app"),
        ])
        try await waitForVisibleProcessIDs(store, expectedProcessIDs: [])
        service.yield(.entries([entry(id: 4, processID: 303)]))
        try await waitForVisibleProcessIDs(store, expectedProcessIDs: [303])

        XCTAssertEqual(service.streamCount, 1)
        store.stop()
    }

    func testApplicationSelectionWaitsUntilANotRunningPackageStarts() async throws {
        let service = ControllableLogcatService()
        let applicationService = ControllableLogcatApplicationService(
            processes: [],
            packageUserID: nil
        )
        let store = makeStore(service: service, applicationService: applicationService)

        store.selectApplicationID("com.example.app")
        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForState(store, matching: .waitingForApplication("com.example.app"))
        XCTAssertEqual(service.streamCount, 0)

        applicationService.setProcesses([
            AndroidRunningProcess(userID: 10374, processID: 303, name: "com.example.app"),
        ])
        try await waitForScope(of: service, matching: .allApplications)
        XCTAssertEqual(store.streamState, .streaming)
        store.stop()
    }

    func testPauseFreezesDisplayedEntriesWhileIngestionContinuesAndRestoresFollowState() async throws {
        let service = ControllableLogcatService()
        let store = makeStore(service: service)

        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForStreamCount(service, expectedCount: 1)
        service.yield(.entries([entry(id: 1)]))
        try await waitForEntryCount(store, expectedCount: 1)

        store.userScrolledAwayFromLatest()
        store.togglePause()
        XCTAssertTrue(store.isPaused)
        XCTAssertEqual(store.displayedStreamState, .paused)
        XCTAssertEqual(store.displayedEntries.map(\.id), [1])

        service.yield(.entries([entry(id: 2)]))
        try await waitForEntryCount(store, expectedCount: 2)
        XCTAssertEqual(store.displayedEntries.map(\.id), [1])

        store.togglePause()
        XCTAssertFalse(store.isPaused)
        XCTAssertFalse(store.isFollowing)
        XCTAssertEqual(store.displayedEntries.map(\.id), [1, 2])

        store.jumpToLatest()
        XCTAssertTrue(store.isFollowing)
        store.stop()
    }

    func testClearRemovesOnlyTheWindowEntries() async throws {
        let service = ControllableLogcatService()
        let store = makeStore(service: service)

        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForStreamCount(service, expectedCount: 1)
        service.yield(.entries([entry(id: 1), entry(id: 2)]))
        try await waitForEntryCount(store, expectedCount: 2)
        store.togglePause()

        store.clear()

        XCTAssertEqual(store.entries, [])
        XCTAssertEqual(store.displayedEntries, [])
        XCTAssertEqual(service.streamCount, 1)
        store.stop()
    }

    func testPausedIngestionRemainsBounded() async throws {
        let service = ControllableLogcatService()
        let store = makeStore(service: service)
        let initialEntries = (1...LogcatStore.retentionLimit).map { entry(id: UInt64($0)) }
        let laterEntries = (LogcatStore.retentionLimit + 1...LogcatStore.retentionLimit + 600).map {
            entry(id: UInt64($0))
        }

        store.start(adbPath: "/SDK/platform-tools/adb")
        try await waitForStreamCount(service, expectedCount: 1)
        service.yield(.entries(initialEntries))
        try await waitForEntryCount(store, expectedCount: LogcatStore.retentionLimit)
        store.togglePause()
        service.yield(.entries(laterEntries))
        try await waitForLastEntryID(store, expectedID: 50_600)

        XCTAssertEqual(store.entries.first?.id, 601)
        XCTAssertEqual(store.entries.last?.id, 50_600)
        XCTAssertEqual(store.displayedEntries.first?.id, 1)
        XCTAssertEqual(store.displayedEntries.last?.id, 50_000)
        store.stop()
    }

    private func entry(
        id: UInt64,
        priority: LogcatPriority = .debug,
        processID: Int = 101
    ) -> LogcatEntry {
        LogcatEntry(
            id: id,
            timestamp: Date(timeIntervalSince1970: TimeInterval(id)),
            priority: priority,
            processID: processID,
            threadID: 201,
            tag: "Tag",
            message: "Message \(id)"
        )
    }

    private func makeStore(
        service: ControllableLogcatService,
        applicationService: any LogcatApplicationQuerying = EmptyLogcatApplicationService(),
        reconnectDelay: @escaping @Sendable (Int) -> Duration = { _ in .seconds(1) }
    ) -> LogcatStore {
        LogcatStore(
            deviceSerial: "device-serial",
            makeService: { _ in service },
            makeApplicationService: { _ in applicationService },
            applicationRefreshInterval: .milliseconds(10),
            reconnectDelay: reconnectDelay
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

    private func waitForScope(
        of service: ControllableLogcatService,
        matching expectedScope: LogcatStreamScope
    ) async throws {
        for _ in 0..<80 {
            if service.scopes.last == expectedScope {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected Logcat stream scope \(expectedScope)")
    }

    private func waitForVisibleProcessIDs(
        _ store: LogcatStore,
        expectedProcessIDs: [Int]
    ) async throws {
        for _ in 0..<80 {
            if store.visibleEntries.map(\.processID) == expectedProcessIDs {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected visible process IDs \(expectedProcessIDs)")
    }

    private func waitForLastEntryID(_ store: LogcatStore, expectedID: UInt64) async throws {
        for _ in 0..<80 {
            if store.entries.last?.id == expectedID {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected last retained Logcat entry \(expectedID)")
    }
}

private final class ControllableLogcatService: LogcatStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<LogcatServiceEvent>.Continuation?
    private var recordedStreamCount = 0
    private var recordedScopes: [LogcatStreamScope] = []
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

    var scopes: [LogcatStreamScope] {
        lock.lock()
        defer { lock.unlock() }
        return recordedScopes
    }

    func stream(
        for deviceSerial: String,
        scope: LogcatStreamScope
    ) -> AsyncStream<LogcatServiceEvent> {
        lock.lock()
        recordedStreamCount += 1
        recordedScopes.append(scope)
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

private struct EmptyLogcatApplicationService: LogcatApplicationQuerying {
    func runningProcesses(for deviceSerial: String) async -> LogcatApplicationServiceResult<[AndroidRunningProcess]> {
        .success([])
    }

    func packageUserID(
        for packageID: String,
        deviceSerial: String
    ) async -> LogcatApplicationServiceResult<Int?> {
        .success(nil)
    }
}

private final class ControllableLogcatApplicationService: LogcatApplicationQuerying, @unchecked Sendable {
    private let lock = NSLock()
    private var currentProcesses: [AndroidRunningProcess]
    private let currentPackageUserID: Int?

    init(processes: [AndroidRunningProcess], packageUserID: Int?) {
        currentProcesses = processes
        currentPackageUserID = packageUserID
    }

    func setProcesses(_ processes: [AndroidRunningProcess]) {
        lock.lock()
        currentProcesses = processes
        lock.unlock()
    }

    func runningProcesses(for deviceSerial: String) async -> LogcatApplicationServiceResult<[AndroidRunningProcess]> {
        .success(lock.withLock { currentProcesses })
    }

    func packageUserID(
        for packageID: String,
        deviceSerial: String
    ) async -> LogcatApplicationServiceResult<Int?> {
        .success(currentPackageUserID)
    }
}
