import Foundation

struct AndroidVirtualDevice: Identifiable, Equatable, Sendable {
    let name: String
    var status: AndroidVirtualDeviceStatus

    init(name: String, status: AndroidVirtualDeviceStatus = .stopped) {
        self.name = name
        self.status = status
    }

    var id: String {
        name
    }
}

enum AndroidVirtualDeviceStatus: Equatable, Sendable {
    case stopped
    case starting
    case running(AndroidDevice)
    case stopping(AndroidDevice)

    var runningDevice: AndroidDevice? {
        switch self {
        case .running(let device), .stopping(let device):
            device
        case .stopped, .starting:
            nil
        }
    }
}
