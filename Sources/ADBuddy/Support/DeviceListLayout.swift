import CoreGraphics

enum DeviceListLayout {
    static let windowWidth: CGFloat = 520
    static let rowHeight: CGFloat = 58
    static let verticalInsets: CGFloat = 16
    static let maximumVisibleDeviceCount = 4

    static func deviceListHeight(for deviceCount: Int) -> CGFloat {
        let visibleDeviceCount = min(max(deviceCount, 1), maximumVisibleDeviceCount)
        return CGFloat(visibleDeviceCount) * rowHeight + verticalInsets
    }

    static func contentSizeRespectingMinimumWidth(_ contentSize: CGSize) -> CGSize {
        CGSize(width: max(contentSize.width, windowWidth), height: contentSize.height)
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
}
