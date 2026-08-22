import Foundation
import XCTest
@testable import ADBuddy

final class ADBClientTests: XCTestCase {
    func testReturnsActionableFailureFromStandardError() async {
        let runner = StubProcessRunner(
            result: ProcessResult(
                standardOutput: Data(),
                standardError: Data("daemon unavailable\n".utf8),
                exitStatus: 1,
                durationMilliseconds: 5,
                failureDescription: nil,
                wasCancelled: false
            )
        )
        let client = ADBClient(adbPath: "/SDK/platform-tools/adb", processRunner: runner)

        let result = await client.listDevices()

        XCTAssertEqual(result, .failure(.commandFailed("daemon unavailable")))
    }

    func testParsesSuccessfulDeviceList() async {
        let runner = StubProcessRunner(
            result: ProcessResult(
                standardOutput: Data("List of devices attached\nserial\tdevice model:Pixel_9\n".utf8),
                standardError: Data(),
                exitStatus: 0,
                durationMilliseconds: 5,
                failureDescription: nil,
                wasCancelled: false
            )
        )
        let client = ADBClient(adbPath: "/SDK/platform-tools/adb", processRunner: runner)

        let result = await client.listDevices()

        guard case .success(let devices) = result else {
            return XCTFail("Expected successful device list")
        }
        XCTAssertEqual(devices.map(\.displayName), ["Pixel 9"])
    }
}

private struct StubProcessRunner: ProcessRunning {
    let result: ProcessResult

    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        result
    }
}
