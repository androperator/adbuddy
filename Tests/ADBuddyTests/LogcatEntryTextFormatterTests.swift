import Foundation
import XCTest
@testable import ADBuddy

final class LogcatEntryTextFormatterTests: XCTestCase {
    func testFormatsSelectedEntriesAsReadableText() {
        let entry = LogcatEntry(
            id: 1,
            timestamp: Date(timeIntervalSince1970: 0),
            priority: .warn,
            processID: 101,
            threadID: 201,
            tag: "Network",
            message: "Retrying connection"
        )

        XCTAssertEqual(
            LogcatEntryTextFormatter.string(from: entry),
            "00:00:00.000 W Network (PID 101, TID 201): Retrying connection"
        )
    }
}
