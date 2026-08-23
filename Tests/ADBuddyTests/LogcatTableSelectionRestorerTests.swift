import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

final class LogcatTableSelectionRestorerTests: XCTestCase {
    func testRestoresSelectionAtTheSameRowsWhenEntriesAreAppended() {
        let entries = [entry(id: 1), entry(id: 2), entry(id: 3)]
        let selections = LogcatTableSelectionRestorer.selections(
            at: IndexSet([1]),
            entryAt: { entries[safe: $0] }
        )
        let updatedEntries = entries + [entry(id: 4)]

        XCTAssertEqual(
            LogcatTableSelectionRestorer.rows(
                for: selections,
                entryCount: updatedEntries.count,
                entryAt: { updatedEntries[safe: $0] }
            ),
            IndexSet([1])
        )
    }

    func testRestoresSelectionAfterRetentionRemovesEarlierEntries() {
        let entries = [entry(id: 1), entry(id: 2), entry(id: 3)]
        let selections = LogcatTableSelectionRestorer.selections(
            at: IndexSet([2]),
            entryAt: { entries[safe: $0] }
        )
        let retainedEntries = [entry(id: 2), entry(id: 3), entry(id: 4)]

        XCTAssertEqual(
            LogcatTableSelectionRestorer.rows(
                for: selections,
                entryCount: retainedEntries.count,
                entryAt: { retainedEntries[safe: $0] }
            ),
            IndexSet([1])
        )
    }

    func testDoesNotRestoreEntriesNoLongerVisible() {
        let entries = [entry(id: 1), entry(id: 2)]
        let selections = LogcatTableSelectionRestorer.selections(
            at: IndexSet([0]),
            entryAt: { entries[safe: $0] }
        )

        XCTAssertEqual(
            LogcatTableSelectionRestorer.rows(
                for: selections,
                entryCount: 1,
                entryAt: { _ in entry(id: 2) }
            ),
            []
        )
    }

    private func entry(id: UInt64) -> LogcatEntry {
        LogcatEntry(
            id: id,
            timestamp: .now,
            priority: .info,
            processID: 100,
            threadID: 200,
            tag: "Tag",
            message: "Message"
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
