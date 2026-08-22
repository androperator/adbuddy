import XCTest
@testable import ADBuddy

final class ADBDeviceParserTests: XCTestCase {
    func testParsesConnectedEmulatorAndUnavailableDevices() {
        let output = """
        List of devices attached
        1234567890\tdevice product:panther model:Pixel_7 device:panther transport_id:3
        emulator-5554\tdevice product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:1
        ABCDEF\tunauthorized transport_id:7
        offline-device\toffline model:Pixel_8 transport_id:9

        """

        let devices = ADBDeviceParser.parse(output)

        XCTAssertEqual(devices.count, 4)
        XCTAssertEqual(devices[0].displayName, "Pixel 7")
        XCTAssertEqual(devices[0].connectionState, .connected)
        XCTAssertEqual(devices[0].kind, .physical)
        XCTAssertEqual(devices[0].transportID, "3")

        XCTAssertEqual(devices[1].kind, .emulator)
        XCTAssertEqual(devices[1].displayName, "sdk gphone64 arm64")
        XCTAssertEqual(devices[2].connectionState, .unauthorized)
        XCTAssertFalse(devices[2].isUsable)
        XCTAssertEqual(devices[3].connectionState, .offline)
    }

    func testIgnoresOutputWithoutDeviceHeader() {
        XCTAssertTrue(ADBDeviceParser.parse("adb: failed to connect to daemon").isEmpty)
    }
}
