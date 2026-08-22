import CoreGraphics
import XCTest
@testable import ADBuddy

final class DeviceListLayoutTests: XCTestCase {
    func testBoundsDeviceListToFourVisibleRows() {
        XCTAssertEqual(DeviceListLayout.deviceListHeight(for: 1), 74)
        XCTAssertEqual(DeviceListLayout.deviceListHeight(for: 2), 132)
        XCTAssertEqual(DeviceListLayout.deviceListHeight(for: 10), 248)
    }

    func testClampsWindowContentToTheDeviceListWidth() {
        XCTAssertEqual(
            DeviceListLayout.contentSizeRespectingMinimumWidth(CGSize(width: 240, height: 132)),
            CGSize(width: 520, height: 132)
        )
        XCTAssertEqual(
            DeviceListLayout.contentSizeRespectingMinimumWidth(CGSize(width: 720, height: 132)),
            CGSize(width: 720, height: 132)
        )
    }

    func testUsesCompactDeviceHeightAndLargerUnavailableState() {
        XCTAssertEqual(
            DeviceListLayout.initialWindowContentSize(for: .devicesAvailable, deviceCount: 2),
            CGSize(width: 520, height: 132)
        )
        XCTAssertEqual(
            DeviceListLayout.initialWindowContentSize(for: .noDevices, deviceCount: 0),
            CGSize(width: 520, height: 240)
        )
        XCTAssertNil(DeviceListLayout.initialWindowContentSize(for: .loading, deviceCount: 0))
    }
}
