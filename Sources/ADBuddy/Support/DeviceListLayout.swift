import CoreGraphics

enum DeviceListLayout {
    static let windowWidth: CGFloat = 720
    static let actionControlWidth: CGFloat = 44
    static let actionButtonLabelWidth: CGFloat = 28
    static let actionMenuLabelWidth: CGFloat = 24
    static let lifecycleControlWidth: CGFloat = 28
    static let rowHeight: CGFloat = 58
    static let verticalInsets: CGFloat = 16
    static let maximumVisibleDeviceCount = 4
    static let sectionHeaderHeight: CGFloat = 24
    static let maximumVisibleSectionedRowCount = 6
    static let unavailableContentHeight: CGFloat = 240

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

    static func contentSizeRetainingCurrentWidth(
        _ currentContentSize: CGSize,
        updatingHeight height: CGFloat
    ) -> CGSize {
        contentSizeRespectingMinimumWidth(
            CGSize(width: currentContentSize.width, height: height)
        )
    }

    static func minimumWindowFrameWidth(for _: CGFloat) -> CGFloat {
        windowWidth
    }

    static func mainWindowContentSize(
        for status: DeviceDiscoveryStatus,
        connectedDeviceCount: Int,
        virtualDeviceCount: Int
    ) -> CGSize {
        switch status {
        case .loading:
            return CGSize(width: windowWidth, height: unavailableContentHeight)
        case .sdkUnavailable, .adbFailure:
            return CGSize(width: windowWidth, height: unavailableContentHeight)
        case .noDevices, .devicesAvailable:
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
