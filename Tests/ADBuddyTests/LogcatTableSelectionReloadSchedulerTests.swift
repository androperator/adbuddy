import XCTest
@testable import ADBuddy

final class LogcatTableSelectionReloadSchedulerTests: XCTestCase {
    func testDefersReloadUntilRowSelectionTrackingEnds() {
        var scheduler = LogcatTableSelectionReloadScheduler()

        XCTAssertFalse(scheduler.shouldReloadImmediately(isTrackingRowSelection: true))
        XCTAssertTrue(scheduler.hasDeferredReload)
        XCTAssertTrue(scheduler.consumeDeferredReload())
        XCTAssertFalse(scheduler.hasDeferredReload)
    }

    func testReloadsImmediatelyOutsideRowSelectionTracking() {
        var scheduler = LogcatTableSelectionReloadScheduler()

        XCTAssertTrue(scheduler.shouldReloadImmediately(isTrackingRowSelection: false))
        XCTAssertFalse(scheduler.consumeDeferredReload())
    }
}
