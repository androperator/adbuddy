import Foundation
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

@MainActor
final class APKInstallationStoreTests: XCTestCase {
    func testInstallsAPKOnEverySelectedDeviceAndPreservesIndividualOutcomes() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ADBuddyAPKInstallationStoreTests-\(UUID().uuidString)")
        let archiveURL = temporaryDirectory.appendingPathComponent("example.apk")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try Data([0x00]).write(to: archiveURL)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let store = APKInstallationStore(
            processRunner: SuccessfulAPKInstallProcessRunner(),
            buildToolsLocator: AndroidBuildToolsLocator(
                directoryContents: { _ in [] },
                isExecutable: { _ in false }
            )
        )
        let devices = [makeDevice(serial: "one"), makeDevice(serial: "two")]
        let archive = AndroidPackageArchive(fileURL: archiveURL)

        store.presentInstaller(for: archiveURL)
        XCTAssertTrue(store.isPresentingInstaller)

        store.install(
            archive: archive,
            on: devices,
            sdk: AndroidSDK(
                rootPath: "/SDK",
                adbPath: "/SDK/platform-tools/adb",
                source: .androidHome
            ),
            openAfterInstall: false
        )

        for _ in 0..<100 {
            if !store.isInstalling, store.feedback != nil {
                break
            }
            await Task.yield()
        }

        XCTAssertEqual(
            store.deviceStates["one"],
            .succeeded(
                APKInstallationOutcome(
                    archive: archive,
                    deviceSerial: "one",
                    launchResult: .notRequested
                )
            )
        )
        XCTAssertEqual(
            store.deviceStates["two"],
            .succeeded(
                APKInstallationOutcome(
                    archive: archive,
                    deviceSerial: "two",
                    launchResult: .notRequested
                )
            )
        )
        XCTAssertEqual(store.installationDevices, devices)
        XCTAssertEqual(
            store.feedback,
            APKInstallationFeedback(
                isSuccess: true,
                title: "APK Installed",
                detail: "example.apk installed on 2 of 2 devices."
            )
        )
    }

    private func makeDevice(serial: String) -> AndroidDevice {
        AndroidDevice(
            serial: serial,
            displayName: "Device \(serial)",
            connectionState: .connected,
            kind: .physical,
            model: nil,
            product: nil,
            deviceCodeName: nil,
            transportID: nil
        )
    }
}

private struct SuccessfulAPKInstallProcessRunner: ProcessRunning {
    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        ProcessResult(
            standardOutput: Data("Success\n".utf8),
            standardError: Data(),
            exitStatus: 0,
            durationMilliseconds: 1,
            failureDescription: nil,
            wasCancelled: false
        )
    }
}
