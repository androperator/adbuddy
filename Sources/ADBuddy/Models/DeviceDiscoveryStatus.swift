import SwiftUI

enum DeviceDiscoveryStatus: Equatable, Sendable {
    case loading
    case sdkUnavailable(AndroidSDKFailure)
    case adbFailure(String)
    case noDevices
    case devicesAvailable

    var title: String {
        switch self {
        case .loading:
            "Refreshing Devices"
        case .sdkUnavailable(let failure):
            failure.title
        case .adbFailure:
            "ADB Could Not Refresh Devices"
        case .noDevices:
            "No Android Devices"
        case .devicesAvailable:
            "Android Devices"
        }
    }

    var detail: String {
        switch self {
        case .loading:
            "Checking the Android SDK and connected devices."
        case .sdkUnavailable(let failure):
            failure.detail
        case .adbFailure(let message):
            message
        case .noDevices:
            "Connect a device with USB debugging or start an emulator."
        case .devicesAvailable:
            "Choose a connected device to inspect its current state."
        }
    }

    var symbolName: String {
        switch self {
        case .loading:
            "arrow.triangle.2.circlepath"
        case .sdkUnavailable:
            "wrench.and.screwdriver"
        case .adbFailure:
            "exclamationmark.triangle"
        case .noDevices:
            "iphone.slash"
        case .devicesAvailable:
            "checkmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .loading:
            .secondary
        case .sdkUnavailable, .adbFailure:
            .orange
        case .noDevices:
            .secondary
        case .devicesAvailable:
            .green
        }
    }
}
