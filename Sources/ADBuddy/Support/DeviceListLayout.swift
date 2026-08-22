import CoreGraphics

enum DeviceListLayout {
    static let windowWidth: CGFloat = 520
    static let rowHeight: CGFloat = 58
    static let verticalInsets: CGFloat = 16
    static let maximumVisibleDeviceCount = 4
    static let sectionHeaderHeight: CGFloat = 24
    static let maximumVisibleSectionedRowCount = 6

    static func deviceListHeight(for deviceCount: Int) -> CGFloat {
        let visibleDeviceCount = min(max(deviceCount, 1), maximumVisibleDeviceCount)
        return CGFloat(visibleDeviceCount) * rowHeight + verticalInsets
    }

    static func sectionedListHeight(
        connectedDeviceCount: Int,
        virtualDeviceCount: Int
    ) -> CGFloat {
        let rowCount = max(connectedDeviceCount, 1) + max(virtualDeviceCount, 1)
        let visibleRowCount = min(rowCount, maximumVisibleSectionedRowCount)
        return CGFloat(visibleRowCount) * rowHeight + (sectionHeaderHeight * 2) + verticalInsets
    }

    static func contentSizeRespectingMinimumWidth(_ contentSize: CGSize) -> CGSize {
        CGSize(width: max(contentSize.width, windowWidth), height: contentSize.height)
    }

    static func minimumWindowFrameWidth(for currentFrameWidth: CGFloat) -> CGFloat {
        max(currentFrameWidth, windowWidth)
    }

    static func initialWindowContentSize(
        for status: DeviceDiscoveryStatus,
        deviceCount: Int
    ) -> CGSize? {
        switch status {
        case .loading:
            nil
        case .devicesAvailable:
            CGSize(width: windowWidth, height: deviceListHeight(for: deviceCount))
        case .sdkUnavailable, .adbFailure, .noDevices:
            CGSize(width: windowWidth, height: 240)
        }
    }

    static func initialWindowContentSize(
        for status: DeviceDiscoveryStatus,
        connectedDeviceCount: Int,
        virtualDeviceCount: Int,
        isEmulatorListReady: Bool
    ) -> CGSize? {
        switch status {
        case .loading:
            return nil
        case .sdkUnavailable, .adbFailure:
            return CGSize(width: windowWidth, height: 240)
        case .noDevices, .devicesAvailable:
            guard isEmulatorListReady else {
                return nil
            }
            return CGSize(
                width: windowWidth,
                height: sectionedListHeight(
                    connectedDeviceCount: connectedDeviceCount,
                    virtualDeviceCount: virtualDeviceCount
                )
            )
        }
    }
}
