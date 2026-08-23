import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

final class EmulatorVirtualDeviceStatusResolverTests: XCTestCase {
    func testUsesUserSpecifiedNameForRunningEmulator() {
        let device = connectedEmulator(serial: "emulator-5554")
        let virtualDevice = AndroidVirtualDevice(
            name: "Pixel_9",
            status: .running(device)
        )

        XCTAssertEqual(
            EmulatorVirtualDeviceStatusResolver.displayName(
                for: device,
                among: [virtualDevice]
            ),
            "Pixel_9"
        )
    }

    func testUsesADBNameWhenDeviceIsNotAMappedEmulator() {
        let device = AndroidDevice(
            serial: "physical-device",
            displayName: "Pixel 9",
            connectionState: .connected,
            kind: .physical,
            model: nil,
            product: nil,
            deviceCodeName: nil,
            transportID: nil
        )

        XCTAssertEqual(
            EmulatorVirtualDeviceStatusResolver.displayName(
                for: device,
                among: []
            ),
            "Pixel 9"
        )
    }

    func testStoppingVirtualDeviceBecomesStoppedAfterItDisconnects() {
        let device = connectedEmulator(serial: "emulator-5558")
        let virtualDevice = AndroidVirtualDevice(
            name: "clawperator-pixel",
            status: .stopping(device)
        )

        let reconciledDevices = EmulatorVirtualDeviceStatusResolver.reconciledVirtualDevices(
            [virtualDevice],
            runningDevices: [:]
        )

        XCTAssertEqual(reconciledDevices, [
            AndroidVirtualDevice(name: "clawperator-pixel", status: .stopped),
        ])
    }

    func testStoppingVirtualDeviceRemainsStoppingWhileItIsStillConnected() {
        let device = connectedEmulator(serial: "emulator-5558")
        let virtualDevice = AndroidVirtualDevice(
            name: "clawperator-pixel",
            status: .stopping(device)
        )

        let reconciledDevices = EmulatorVirtualDeviceStatusResolver.reconciledVirtualDevices(
            [virtualDevice],
            runningDevices: ["clawperator-pixel": device]
        )

        XCTAssertEqual(reconciledDevices, [virtualDevice])
    }

    private func connectedEmulator(serial: String) -> AndroidDevice {
        AndroidDevice(
            serial: serial,
            displayName: "clawperator-pixel",
            connectionState: .connected,
            kind: .emulator,
            model: nil,
            product: nil,
            deviceCodeName: nil,
            transportID: nil
        )
    }
}
