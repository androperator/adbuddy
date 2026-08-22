import CoreGraphics
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

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

    func testClampsWindowFrameToItsInitialWidth() {
        XCTAssertEqual(DeviceListLayout.minimumWindowFrameWidth(for: 240), 520)
        XCTAssertEqual(DeviceListLayout.minimumWindowFrameWidth(for: 640), 640)
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

    func testSectionedListReservesRowsForBothDeviceGroups() {
        XCTAssertEqual(
            DeviceListLayout.sectionedListHeight(
                connectedDeviceCount: 0,
                virtualDeviceCount: 3
            ),
            296
        )
        XCTAssertEqual(
            DeviceListLayout.sectionedListHeight(
                connectedDeviceCount: 4,
                virtualDeviceCount: 5
            ),
            412
        )
    }

    func testSectionedInitialWindowSizeWaitsForEmulatorDiscovery() {
        XCTAssertNil(
            DeviceListLayout.initialWindowContentSize(
                for: .noDevices,
                connectedDeviceCount: 0,
                virtualDeviceCount: 0,
                isEmulatorListReady: false
            )
        )
        XCTAssertEqual(
            DeviceListLayout.initialWindowContentSize(
                for: .devicesAvailable,
                connectedDeviceCount: 1,
                virtualDeviceCount: 2,
                isEmulatorListReady: true
            ),
            CGSize(width: 520, height: 238)
        )
    }
}
