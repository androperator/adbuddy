import Foundation

public struct AndroidVirtualDevice: Identifiable, Equatable, Sendable {
    public let name: String
    public var status: AndroidVirtualDeviceStatus

    public init(name: String, status: AndroidVirtualDeviceStatus = .stopped) {
        self.name = name
        self.status = status
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
