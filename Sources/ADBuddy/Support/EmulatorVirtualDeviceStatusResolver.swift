import Foundation

enum EmulatorVirtualDeviceStatusResolver {
    static func reconciledVirtualDevices(
        _ virtualDevices: [AndroidVirtualDevice],
        runningDevices: [String: AndroidDevice]
    ) -> [AndroidVirtualDevice] {
        virtualDevices.map { virtualDevice in
            if let device = runningDevices[virtualDevice.name] {
                if case .stopping = virtualDevice.status {
                    return virtualDevice
                }
                return AndroidVirtualDevice(name: virtualDevice.name, status: .running(device))
            }

            switch virtualDevice.status {
            case .starting:
                return virtualDevice
            case .stopped, .running, .stopping:
                return AndroidVirtualDevice(name: virtualDevice.name, status: .stopped)
            }
        }
    }
}
