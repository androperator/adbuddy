import AppKit
import XCTest
@testable import ADBuddy

@MainActor
final class LogcatTableHeaderViewTests: XCTestCase {
    func testRightClickHeaderUsesColumnConfigurationMenu() throws {
        let headerView = LogcatTableHeaderView()
        let expectedMenu = NSMenu(title: "Columns")
        headerView.columnConfigurationMenu = { expectedMenu }
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )

        XCTAssertTrue(headerView.menu(for: event) === expectedMenu)
    }
}
