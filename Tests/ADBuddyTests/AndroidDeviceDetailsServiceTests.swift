import Foundation
import XCTest
@testable import ADBuddyCore

final class AndroidDeviceDetailsServiceTests: XCTestCase {
    func testReadsAndroidVersionAndAPILevelWithFixedADBArguments() async {
        let processRunner = RecordingDeviceDetailsProcessRunner(results: [
            successfulResult("16\n"),
            successfulResult("36\n"),
            successfulResult("Physical size: 1080x2400\n"),
            successfulResult("Physical density: 420\n"),
            successfulResult("en-AU\n"),
        ])
        let service = AndroidDeviceDetailsService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: processRunner
        )

        let details = await service.details(for: connectedDevice, includesExtendedDetails: true)
        let requests = await processRunner.requests()

        XCTAssertEqual(
            details,
            AndroidDeviceDetails(
                androidVersion: "16",
                apiLevel: "36",
                screen: makeScreen(
                    physicalWidth: 1080,
                    physicalHeight: 2400,
                    densityDPI: 420
                ),
                languageIdentifier: "en-AU"
            )
        )
        XCTAssertEqual(details?.screenshotOverlayText, "Android 16 / API 36")
        XCTAssertEqual(details?.screen?.displayText, "1080 × 2400 px · 411 × 914 dp")
        XCTAssertEqual(requests, [
            ["-s", "device-serial", "shell", "getprop", "ro.build.version.release"],
            ["-s", "device-serial", "shell", "getprop", "ro.build.version.sdk"],
            ["-s", "device-serial", "shell", "wm", "size"],
            ["-s", "device-serial", "shell", "wm", "density"],
            ["-s", "device-serial", "shell", "getprop", "persist.sys.locale"],
        ])
    }

    func testUsesDisplayOverridesForTheDPSizeWhileKeepingPhysicalPixels() async throws {
        let processRunner = RecordingDeviceDetailsProcessRunner(results: [
            successfulResult("16\n"),
            successfulResult("36\n"),
            successfulResult("Physical size: 1080x2400\nOverride size: 720x1600\n"),
            successfulResult("Physical density: 420\nOverride density: 320\n"),
            successfulResult("en-US\n"),
        ])
        let service = AndroidDeviceDetailsService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: processRunner
        )

        let details = await service.details(for: connectedDevice, includesExtendedDetails: true)
        let screen = try XCTUnwrap(details?.screen)

        XCTAssertEqual(screen.physicalPixelSize, AndroidDisplaySize(width: 1080, height: 2400))
        XCTAssertEqual(screen.dpSize, AndroidDisplaySize(width: 360, height: 800))
        XCTAssertTrue(screen.usesDisplayOverride)
        XCTAssertEqual(screen.displayText, "1080 × 2400 px · 360 × 800 dp (display override)")
    }

    func testFallsBackToTheProductLocaleWhenTheCurrentLocaleIsUnavailable() async {
        let processRunner = RecordingDeviceDetailsProcessRunner(results: [
            successfulResult("16\n"),
            successfulResult("36\n"),
            successfulResult("Physical size: 1080x2400\n"),
            successfulResult("Physical density: 420\n"),
            successfulResult("\n"),
            successfulResult("en-US\n"),
        ])
        let service = AndroidDeviceDetailsService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: processRunner
        )

        let details = await service.details(for: connectedDevice, includesExtendedDetails: true)
        let requests = await processRunner.requests()

        XCTAssertEqual(details?.languageIdentifier, "en-US")
        XCTAssertEqual(
            requests.suffix(2),
            [
                ["-s", "device-serial", "shell", "getprop", "persist.sys.locale"],
                ["-s", "device-serial", "shell", "getprop", "ro.product.locale"],
            ]
        )
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

    private func makeScreen(
        physicalWidth: Int,
        physicalHeight: Int,
        densityDPI: Int
    ) -> AndroidDeviceScreen? {
        guard let pixelSize = AndroidDisplaySize(width: physicalWidth, height: physicalHeight) else {
            return nil
        }
        return AndroidDeviceScreen(
            physicalPixelSize: pixelSize,
            logicalDensityDPI: densityDPI
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
