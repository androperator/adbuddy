import Foundation
import XCTest
@testable import ADBuddyCore

final class AndroidDeviceDetailsServiceTests: XCTestCase {
    func testReadsAndroidVersionAndAPILevelWithFixedADBArguments() async {
        let processRunner = RecordingDeviceDetailsProcessRunner(results: [
            successfulResult("16\n"),
            successfulResult("36\n"),
        ])
        let service = AndroidDeviceDetailsService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: processRunner
        )

        let details = await service.details(for: connectedDevice)
        let requests = await processRunner.requests()

        XCTAssertEqual(details, AndroidDeviceDetails(androidVersion: "16", apiLevel: "36"))
        XCTAssertEqual(requests, [
            ["-s", "device-serial", "shell", "getprop", "ro.build.version.release"],
            ["-s", "device-serial", "shell", "getprop", "ro.build.version.sdk"],
        ])
    }

    func testReturnsNoDetailsWhenAPropertyIsMissing() async {
        let processRunner = RecordingDeviceDetailsProcessRunner(results: [
            successfulResult("16\n"),
            successfulResult("\n"),
        ])
        let service = AndroidDeviceDetailsService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: processRunner
        )

        let details = await service.details(for: connectedDevice)

        XCTAssertNil(details)
    }

    private var connectedDevice: AndroidDevice {
        AndroidDevice(
            serial: "device-serial",
            displayName: "Pixel 10 Pro",
            connectionState: .connected,
            kind: .physical,
            model: "Pixel_10_Pro",
            product: nil,
            deviceCodeName: nil,
            transportID: nil
        )
    }

    private func successfulResult(_ output: String) -> ProcessResult {
        ProcessResult(
            standardOutput: Data(output.utf8),
            standardError: Data(),
            exitStatus: 0,
            durationMilliseconds: 5,
            failureDescription: nil,
            wasCancelled: false
        )
    }
}

private actor RecordingDeviceDetailsProcessRunner: ProcessRunning {
    private var results: [ProcessResult]
    private var recordedRequests: [[String]] = []

    init(results: [ProcessResult]) {
        self.results = results
    }

    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        recordedRequests.append(arguments)
        return results.removeFirst()
    }

    func requests() -> [[String]] {
        recordedRequests
    }
}
