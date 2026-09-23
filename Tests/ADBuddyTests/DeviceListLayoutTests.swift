import CoreGraphics
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

final class DeviceListLayoutTests: XCTestCase {
    func testBoundsDeviceListToFourVisibleRows() {
        XCTAssertEqual(DeviceListLayout.deviceListHeight(for: 1), 58)
        XCTAssertEqual(DeviceListLayout.deviceListHeight(for: 2), 116)
        XCTAssertEqual(DeviceListLayout.deviceListHeight(for: 10), 232)
    }

    func testClampsWindowContentToTheDeviceListWidth() {
        XCTAssertEqual(
            DeviceListLayout.contentSizeRespectingMinimumWidth(CGSize(width: 240, height: 132)),
            CGSize(width: 772, height: 132)
        )
        XCTAssertEqual(
            DeviceListLayout.contentSizeRespectingMinimumWidth(CGSize(width: 960, height: 132)),
            CGSize(width: 960, height: 132)
        )
    }

    func testRetainsWindowWidthWhenUpdatingContentHeight() {
        XCTAssertEqual(
            DeviceListLayout.contentSizeRetainingCurrentWidth(
                CGSize(width: 772, height: 500),
                updatingHeight: 238
            ),
            CGSize(width: 772, height: 238)
        )
    }

    func testUsesFixedMinimumWindowFrameWidth() {
        XCTAssertEqual(DeviceListLayout.minimumWindowFrameWidth(for: 240), 772)
        XCTAssertEqual(DeviceListLayout.minimumWindowFrameWidth(for: 960), 772)
    }

    func testUsesStableActionControlDimensions() {
        XCTAssertEqual(DeviceListLayout.actionControlWidth, 44)
        XCTAssertEqual(DeviceListLayout.actionControlHeight, 28)
        XCTAssertEqual(DeviceListLayout.actionControlContentHeight, 20)
        XCTAssertEqual(DeviceListLayout.actionMenuLabelHeight, 26)
        XCTAssertEqual(DeviceListLayout.actionButtonLabelWidth, 28)
        XCTAssertEqual(DeviceListLayout.lifecycleControlWidth, 28)
    }

    func testUsesContentHeightForEachMainWindowState() {
        XCTAssertEqual(
            DeviceListLayout.mainWindowContentSize(
                for: .loading,
                connectedDeviceCount: 0,
                virtualDeviceCount: 0
            ),
            CGSize(width: 772, height: 240)
        )
        XCTAssertEqual(
            DeviceListLayout.mainWindowContentSize(
                for: .noDevices,
                connectedDeviceCount: 0,
                virtualDeviceCount: 0
            ),
            CGSize(width: 772, height: 164)
        )
    }

    func testSectionedListReservesRowsForBothDeviceGroups() {
        XCTAssertEqual(
            DeviceListLayout.sectionedListHeight(
                connectedDeviceCount: 0,
                virtualDeviceCount: 3
            ),
            280
        )
        XCTAssertEqual(
            DeviceListLayout.sectionedListHeight(
                connectedDeviceCount: 4,
                virtualDeviceCount: 5
            ),
            396
        )
    }

    func testMainWindowHeightUpdatesAsVisibleRowsChange() {
        XCTAssertEqual(
            DeviceListLayout.mainWindowContentSize(
                for: .devicesAvailable,
                connectedDeviceCount: 3,
                virtualDeviceCount: 1
            ),
            CGSize(width: 772, height: 280)
        )
        XCTAssertEqual(
            DeviceListLayout.mainWindowContentSize(
                for: .devicesAvailable,
                connectedDeviceCount: 2,
                virtualDeviceCount: 1
            ),
            CGSize(width: 772, height: 222)
        )
    }
}
