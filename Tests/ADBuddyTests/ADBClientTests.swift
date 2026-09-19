import Foundation
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

final class ADBClientTests: XCTestCase {
    func testResolvesEmulatorNamesWithoutChangingIdentityOrPhysicalNames() async throws {
        let runner = NameProcessRunner(outputs: [
            "List of devices attached\nemulator-5554 device model:sdk_gphone16k_arm64\nemulator-5556 device model:sdk_gphone64_arm64\nphone device model:Pixel_9\n",
            "Pixel_10_Pro_Fold\nOK\n",
            "Pixel_9\nOK\n",
        ])
        guard case .success(let devices) = await ADBClient(adbPath: "/adb", processRunner: runner).listDevices() else {
            return XCTFail("Expected successful discovery")
        }
        XCTAssertEqual(devices.map(\.displayName), ["Pixel_10_Pro_Fold", "Pixel_9", "Pixel 9"])
        XCTAssertEqual(devices.map(\.serial), ["emulator-5554", "emulator-5556", "phone"])
        XCTAssertEqual(devices.first?.model, "sdk_gphone16k_arm64")
        let calls = await runner.arguments
        XCTAssertEqual(calls, [
            ["devices", "-l"],
            ["-s", "emulator-5554", "emu", "avd", "name"],
            ["-s", "emulator-5556", "emu", "avd", "name"],
        ])
    }

    func testUnresolvedAndOfflineEmulatorsUseSerialInsteadOfSDKModel() async throws {
        let runner = NameProcessRunner(outputs: [
            "List of devices attached\nemulator-5554 device model:sdk_gphone64_arm64\nemulator-5556 offline model:sdk_gphone64_arm64\n",
            "OK\n",
        ])
        guard case .success(let devices) = await ADBClient(adbPath: "/adb", processRunner: runner).listDevices() else {
            return XCTFail("Expected successful discovery")
        }
        XCTAssertEqual(devices.map(\.displayName), ["emulator-5554", "emulator-5556"])
        let calls = await runner.arguments
        XCTAssertEqual(calls.count, 2)
    }

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

private actor NameProcessRunner: ProcessRunning {
    var outputs: [String]
    var arguments: [[String]] = []

    init(outputs: [String]) { self.outputs = outputs }

    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        self.arguments.append(arguments)
        return ProcessResult(
            standardOutput: Data(outputs.removeFirst().utf8), standardError: Data(),
            exitStatus: 0, durationMilliseconds: 1, failureDescription: nil, wasCancelled: false
        )
    }
}
