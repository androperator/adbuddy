import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

final class LogcatTableColumnTests: XCTestCase {
    func testColumnWidthFitsTheWidestCell() {
        var calculator = LogcatTableColumnWidthCalculator(headerWidth: 44)
        calculator.include(width: 92.25)
        calculator.include(width: 68)

        XCTAssertEqual(
            calculator.fittedWidth(minimumWidth: 40, horizontalInsets: 8),
            101
        )
    }

    func testColumnWidthDoesNotFallBelowTheMinimum() {
        let calculator = LogcatTableColumnWidthCalculator(headerWidth: 21)

        XCTAssertEqual(
            calculator.fittedWidth(minimumWidth: 40, horizontalInsets: 8),
            40
        )
    }

    func testOptionalColumnsAreHiddenByDefault() {
        XCTAssertEqual(LogcatTableColumn.visibleColumns(), [.time, .level, .tag, .message])
    }

    func testColumnConfigurationIncludesTagAndAllowsItToBeHidden() {
        XCTAssertEqual(
            LogcatTableColumn.configurableColumns,
            [.applicationID, .processID, .tag, .threadID]
        )
        XCTAssertEqual(
            LogcatTableColumn.visibleColumns(showsTag: false),
            [.time, .level, .message]
        )
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
