import AppKit
import XCTest
@testable import ADBuddy

@MainActor
final class EmulatorCreationWindowTests: XCTestCase {
    func testOpensAtTopCenterOfMainWindow() {
        let origin = EmulatorCreationWindowController.origin(
            for: NSSize(width: 600, height: 400),
            parentFrame: NSRect(x: 200, y: 100, width: 800, height: 700),
            visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(origin, NSPoint(x: 300, y: 368))
    }

    func testKeepsWindowOnParentsDisplayAtScreenEdges() {
        let screen = NSRect(x: -1440, y: 40, width: 1440, height: 860)
        for parent in [NSRect(x: -1600, y: 0, width: 800, height: 300),
                       NSRect(x: -400, y: 800, width: 800, height: 300)] {
            let size = NSSize(width: 600, height: 400)
            let origin = EmulatorCreationWindowController.origin(for: size, parentFrame: parent, visibleFrame: screen)
            XCTAssertTrue(screen.contains(NSRect(origin: origin, size: size)))
        }
    }
}
