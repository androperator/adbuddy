import Foundation
import Observation
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

@MainActor
final class EmulatorStoreTests: XCTestCase {
    func testCreatedAVDHonorsCreateAndCreateThenStart() async throws {
        let sdk = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let emulator = sdk.appendingPathComponent("emulator/emulator")
        try FileManager.default.createDirectory(at: emulator.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: emulator)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: emulator.path)
        defer { try? FileManager.default.removeItem(at: sdk) }
        let store = EmulatorStore(
            sdkLocator: AndroidSDKLocator(environment: ["ANDROID_HOME": sdk.path], pathExists: { _ in true }, isExecutable: { _ in true }),
            processRunner: VirtualDevicePollingRunner(),
            applicationLauncher: CreationTestLauncher()
        )
        store.registerCreatedVirtualDevice(name: "New_TV")
        XCTAssertEqual(store.virtualDevices.first?.status, .stopped)
        store.requestDelete(AndroidVirtualDevice(name: "New_TV"))
        XCTAssertEqual(store.deleteConfirmationVirtualDevice?.name, "New_TV")
        store.deleteConfirmationVirtualDevice = nil
        store.registerCreatedVirtualDevice(name: "New_TV", startAfterCreation: true)
        XCTAssertEqual(store.virtualDevices.first?.name, "New_TV")
        XCTAssertEqual(store.virtualDevices.first?.status, .starting)
        store.registerCreatedVirtualDevice(name: "New_TV")
        XCTAssertEqual(store.virtualDevices.count, 1)
        store.requestDelete(AndroidVirtualDevice(name: "New_TV"))
        XCTAssertNil(store.deleteConfirmationVirtualDevice)
        await store.confirmDelete(AndroidVirtualDevice(name: "New_TV"), configuration: .init(helperPath: "/must-not-run", nodePath: "/must-not-run", javaHome: ""))
        XCTAssertEqual(store.deletionError, "The emulator is no longer stopped. Stop it before deleting.")
        XCTAssertTrue(store.deletingNames.isEmpty)
    }

    func testCreationSurvivesDiscoveryStartedBeforeCreation() async throws {
        let sdk = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let emulator = sdk.appendingPathComponent("emulator/emulator")
        try FileManager.default.createDirectory(at: emulator.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: emulator)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: emulator.path)
        defer { try? FileManager.default.removeItem(at: sdk) }
        let started = expectation(description: "Pre-creation discovery started")
        let refreshed = expectation(description: "Fresh discovery follows stale result")
        let runner = DelayedCreationDiscoveryRunner(started: started, refreshed: refreshed)
        let store = EmulatorStore(
            sdkLocator: AndroidSDKLocator(environment: ["ANDROID_HOME": sdk.path], pathExists: { _ in true }, isExecutable: { _ in true }),
            processRunner: runner,
            applicationLauncher: CreationTestLauncher()
        )
        store.refreshVirtualDevices()
        await fulfillment(of: [started], timeout: 2)
        store.registerCreatedVirtualDevice(name: "New_TV", startAfterCreation: true)
        XCTAssertEqual(store.virtualDevices.first?.status, .starting)
        await runner.releaseOldDiscovery()
        await fulfillment(of: [refreshed], timeout: 2)
        for _ in 0..<100 where store.status != .ready {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.virtualDevices.map(\.name), ["New_TV"])
        XCTAssertEqual(store.virtualDevices.first?.status, .starting)
    }

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

private struct CreationTestLauncher: ApplicationProcessLaunching {
    func launch(executablePath: String, arguments: [String]) throws {}
}

private actor DelayedCreationDiscoveryRunner: ProcessRunning {
    let started: XCTestExpectation
    let refreshed: XCTestExpectation
    private var pending: CheckedContinuation<Void, Never>?
    private var requests = 0

    init(started: XCTestExpectation, refreshed: XCTestExpectation) {
        self.started = started
        self.refreshed = refreshed
    }

    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        var output = ""
        if arguments == ["-list-avds"] {
            requests += 1
            if requests == 1 {
                await withCheckedContinuation { continuation in
                    pending = continuation
                    started.fulfill()
                }
            } else {
                output = "New_TV\n"
                refreshed.fulfill()
            }
        }
        return ProcessResult(standardOutput: Data(output.utf8), standardError: Data(), exitStatus: 0,
                             durationMilliseconds: 0, failureDescription: nil, wasCancelled: false)
    }

    func releaseOldDiscovery() {
        pending?.resume()
        pending = nil
    }
}
