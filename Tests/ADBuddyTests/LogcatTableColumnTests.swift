import XCTest
@testable import ADBuddy

final class LogcatTableColumnTests: XCTestCase {
    func testProcessAndThreadColumnsAreHiddenByDefault() {
        XCTAssertEqual(LogcatTableColumn.visibleColumns(), [.time, .level, .tag, .message])
    }

    func testProcessAndThreadColumnsCanBeShownIndependently() {
        XCTAssertEqual(
            LogcatTableColumn.visibleColumns(showsProcessID: true),
            [.time, .processID, .level, .tag, .message]
        )
        XCTAssertEqual(
            LogcatTableColumn.visibleColumns(showsThreadID: true),
            [.time, .threadID, .level, .tag, .message]
        )
        XCTAssertEqual(
            LogcatTableColumn.visibleColumns(showsProcessID: true, showsThreadID: true),
            [.time, .processID, .threadID, .level, .tag, .message]
        )
    }
}
