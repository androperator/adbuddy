import Foundation

enum EmulatorVirtualDeviceStatusResolver {
    static func displayName(
        for device: AndroidDevice,
        among virtualDevices: [AndroidVirtualDevice]
    ) -> String {
        guard let virtualDevice = virtualDevices.first(where: {
            $0.status.runningDevice?.serial == device.serial
        }) else {
            return device.displayName
        }

        return virtualDevice.name
    }

    static func reconciledVirtualDevices(
        _ virtualDevices: [AndroidVirtualDevice],
        runningDevices: [String: AndroidDevice]
    ) -> [AndroidVirtualDevice] {
        virtualDevices.map { virtualDevice in
            if let device = runningDevices[virtualDevice.name] {
                if case .stopping = virtualDevice.status {
                    return virtualDevice
                }
                return AndroidVirtualDevice(
                    name: virtualDevice.name,
                    status: .running(device),
                    deviceDetails: virtualDevice.deviceDetails
                )
            }

            switch virtualDevice.status {
            case .starting:
                return virtualDevice
            case .stopped, .running, .stopping:
                return AndroidVirtualDevice(
                    name: virtualDevice.name,
                    status: .stopped,
                    deviceDetails: virtualDevice.deviceDetails
                )
            }
        }
    }
}
