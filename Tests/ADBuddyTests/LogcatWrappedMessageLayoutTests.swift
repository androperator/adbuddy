import AppKit
import XCTest
@testable import ADBuddy

final class LogcatWrappedMessageLayoutTests: XCTestCase {
    func testUsesCompactRowForShortMessages() {
        XCTAssertEqual(
            LogcatWrappedMessageLayout.rowHeight(
                for: "Short message",
                availableWidth: 500,
                font: .monospacedSystemFont(ofSize: 11, weight: .regular)
            ),
            LogcatWrappedMessageLayout.compactRowHeight
        )
    }

    func testExpandsForNarrowColumns() {
        let height = LogcatWrappedMessageLayout.rowHeight(
            for: "A message that needs more than one line when the column is narrow.",
            availableWidth: 80,
            font: .monospacedSystemFont(ofSize: 11, weight: .regular)
        )

        XCTAssertGreaterThan(height, LogcatWrappedMessageLayout.compactRowHeight)
    }
}
