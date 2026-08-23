import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

final class LogcatTableColumnTests: XCTestCase {
    func testOptionalColumnsAreHiddenByDefault() {
        XCTAssertEqual(LogcatTableColumn.visibleColumns(), [.time, .level, .tag, .message])
    }

    func testOptionalColumnsCanBeShownIndependently() {
        XCTAssertEqual(
            LogcatTableColumn.visibleColumns(showsProcessID: true),
            [.time, .processID, .level, .tag, .message]
        )
        XCTAssertEqual(
            LogcatTableColumn.visibleColumns(showsThreadID: true),
            [.time, .threadID, .level, .tag, .message]
        )
        XCTAssertEqual(
            LogcatTableColumn.visibleColumns(showsApplicationID: true),
            [.time, .applicationID, .level, .tag, .message]
        )
        XCTAssertEqual(
            LogcatTableColumn.visibleColumns(
                showsProcessID: true,
                showsThreadID: true,
                showsApplicationID: true
            ),
            [.time, .processID, .threadID, .applicationID, .level, .tag, .message]
        )
    }
}
