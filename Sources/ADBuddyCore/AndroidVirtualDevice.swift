import Foundation

public struct AndroidVirtualDevice: Identifiable, Equatable, Sendable {
    public let name: String
    public var status: AndroidVirtualDeviceStatus
    public var deviceDetails: AndroidDeviceDetails?

    public init(
        name: String,
        status: AndroidVirtualDeviceStatus = .stopped,
        deviceDetails: AndroidDeviceDetails? = nil
    ) {
        self.name = name
        self.status = status
        self.deviceDetails = deviceDetails
    }

    public var id: String {
        name
    }
}

public enum AndroidVirtualDeviceStatus: Equatable, Sendable {
    case stopped
    case starting
    case running(AndroidDevice)
    case stopping(AndroidDevice)

    public var runningDevice: AndroidDevice? {
        switch self {
        case .running(let device), .stopping(let device):
            device
        case .stopped, .starting:
            nil
        }
    }
}
