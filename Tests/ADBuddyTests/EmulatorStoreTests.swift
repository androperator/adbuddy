import Foundation
import Observation
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

@MainActor
final class EmulatorStoreTests: XCTestCase {
    func testPollingDiscoversNewAVDsWithoutInvalidatingUnchangedPresentation() async throws {
        let sdk = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let emulator = sdk.appendingPathComponent("emulator/emulator")
        try FileManager.default.createDirectory(at: emulator.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: emulator)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: emulator.path)
        defer { try? FileManager.default.removeItem(at: sdk) }
        let runner = VirtualDevicePollingRunner()
        let store = EmulatorStore(
            sdkLocator: AndroidSDKLocator(
                environment: ["ANDROID_HOME": sdk.path],
                pathExists: { _ in true },
                isExecutable: { _ in true }
            ),
            processRunner: runner
        )
        store.start()
        defer { store.stopPolling() }
        for _ in 0..<100 where store.status != .ready {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.virtualDevices.map(\.name), ["Pixel_9"])

        let unchanged = expectation(description: "Unchanged refresh preserves presentation")
        unchanged.isInverted = true
        withObservationTracking {
            _ = store.virtualDevices
            _ = store.status
        } onChange: {
            unchanged.fulfill()
        }
        store.refreshVirtualDevices()
        await fulfillment(of: [unchanged], timeout: 0.2)

        await runner.addFold()
        for _ in 0..<600 where store.virtualDevices.count != 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.virtualDevices.map(\.name), ["Pixel_9", "Pixel_10_Pro_Fold"])
        XCTAssertEqual(store.status, .ready)
    }
}

private actor VirtualDevicePollingRunner: ProcessRunning {
    private var names = "Pixel_9\n"

    func addFold() {
        names += "Pixel_10_Pro_Fold\n"
    }

    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        ProcessResult(
            standardOutput: Data((arguments == ["-list-avds"] ? names : "").utf8),
            standardError: Data(),
            exitStatus: 0,
            durationMilliseconds: 0,
            failureDescription: nil,
            wasCancelled: false
        )
    }
}
