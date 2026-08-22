import XCTest
@testable import ADBuddy

final class LogcatWindowIDTests: XCTestCase {
    func testSerialIsTheWindowIdentity() throws {
        let identity = LogcatWindowID(serial: "emulator-5554")

        XCTAssertEqual(identity, LogcatWindowID(serial: "emulator-5554"))
        XCTAssertNotEqual(identity, LogcatWindowID(serial: "device-1234"))

        let encodedIdentity = try JSONEncoder().encode(identity)
        XCTAssertEqual(try JSONDecoder().decode(LogcatWindowID.self, from: encodedIdentity), identity)
    }
}
