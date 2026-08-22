import Foundation
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

final class ScreenRecordingTests: XCTestCase {
    func testParsesPhysicalDisplaySizeAndScalesToEvenDimensions() {
        let nativeSize = AndroidDisplaySizeParser.parse(
            """
            Physical size: 1080x2410
            Override size: 720x1600
            """
        )

        XCTAssertEqual(nativeSize, AndroidDisplaySize(width: 1080, height: 2410))
        XCTAssertEqual(
            ScreenRecordingResolution.fiftyPercent.outputSize(for: nativeSize!),
            AndroidDisplaySize(width: 540, height: 1206)
        )
        XCTAssertNil(ScreenRecordingResolution.native.outputSize(for: nativeSize!))
    }

    func testRecordsAtSelectedResolutionRestoresTapsAndMovesUniqueMP4() async {
        let processRunner = ScriptedScreenRecordingProcessRunner(results: [
            successfulResult(standardOutput: "Physical size: 1080x2410\n"),
            successfulResult(standardOutput: "0\n"),
            successfulResult(),
            successfulResult(),
            successfulResult(),
            successfulResult(),
            successfulResult(),
        ])
        let fileManager = RecordingScreenFileManager()
        let service = ScreenRecordingService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: processRunner,
            fileManager: fileManager
        )
        let session = ScreenRecordingSession(
            device: connectedDevice,
            remoteFilePath: "/data/local/tmp/adbuddy-recording-test.mp4"
        )
        let destination = URL(fileURLWithPath: "/tmp/media", isDirectory: true)

        let result = await service.record(
            session: session,
            options: ScreenRecordingOptions(
                bitRateMegabitsPerSecond: 8,
                resolution: .fiftyPercent,
                showsTaps: true
            ),
            destination: destination,
            date: Date(timeIntervalSince1970: 0),
            onScreenRecorderStarted: {}
        )

        guard case .success(let fileURL, let warning) = result else {
            return XCTFail("Expected a saved recording")
        }
        XCTAssertNil(warning)
        XCTAssertTrue(fileURL.lastPathComponent.hasPrefix("Pixel-9-Pro_1970-01-01_"))
        XCTAssertEqual(fileURL.pathExtension, "mp4")
        XCTAssertEqual(fileManager.createdDirectories, [destination])
        XCTAssertEqual(fileManager.movedDestination, fileURL)

        let arguments = await processRunner.invocations.map(\.arguments)
        XCTAssertEqual(arguments[0], ["-s", connectedDevice.serial, "shell", "wm", "size"])
        XCTAssertEqual(arguments[1], ["-s", connectedDevice.serial, "shell", "settings", "get", "system", "show_touches"])
        XCTAssertEqual(arguments[2], ["-s", connectedDevice.serial, "shell", "settings", "put", "system", "show_touches", "1"])
        XCTAssertEqual(
            arguments[3],
            [
                "-s", connectedDevice.serial,
                "shell", "screenrecord",
                "--bit-rate", "8000000",
                "--size", "540x1206",
                session.remoteFilePath,
            ]
        )
        XCTAssertEqual(arguments[4], ["-s", connectedDevice.serial, "shell", "settings", "put", "system", "show_touches", "0"])
        XCTAssertEqual(arguments[5].prefix(4), ["-s", connectedDevice.serial, "pull", session.remoteFilePath])
        XCTAssertEqual(arguments[6], ["-s", connectedDevice.serial, "shell", "rm", "-f", session.remoteFilePath])
    }

    func testStopsTheSpecificRemoteRecordingWithInterruptSignal() async {
        let processRunner = ScriptedScreenRecordingProcessRunner(results: [successfulResult()])
        let service = ScreenRecordingService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: processRunner
        )
        let session = ScreenRecordingSession(
            device: connectedDevice,
            remoteFilePath: "/data/local/tmp/adbuddy-recording-test.mp4"
        )

        let stopResult = await service.stop(session: session)
        XCTAssertEqual(stopResult, .stopped)
        let invocations = await processRunner.invocations
        XCTAssertEqual(
            invocations,
            [
                ProcessInvocation(
                    executablePath: "/SDK/platform-tools/adb",
                    arguments: [
                        "-s", connectedDevice.serial,
                        "shell", "pkill", "-INT", "-f", session.remoteFilePath,
                    ]
                ),
            ]
        )
    }

    func testUsesDeviceNativeResolutionWithoutSizeArgument() async {
        let processRunner = ScriptedScreenRecordingProcessRunner(results: [
            successfulResult(),
            successfulResult(),
            successfulResult(),
        ])
        let service = ScreenRecordingService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: processRunner,
            fileManager: RecordingScreenFileManager()
        )
        let session = ScreenRecordingSession(
            device: connectedDevice,
            remoteFilePath: "/data/local/tmp/adbuddy-recording-test.mp4"
        )

        _ = await service.record(
            session: session,
            options: .default,
            destination: URL(fileURLWithPath: "/tmp/media", isDirectory: true),
            onScreenRecorderStarted: {}
        )

        let invocations = await processRunner.invocations
        XCTAssertEqual(
            invocations[0].arguments,
            [
                "-s", connectedDevice.serial,
                "shell", "screenrecord",
                "--bit-rate", "8000000",
                session.remoteFilePath,
            ]
        )
    }

    private var connectedDevice: AndroidDevice {
        AndroidDevice(
            serial: "device-serial",
            displayName: "Pixel 9 Pro",
            connectionState: .connected,
            kind: .physical,
            model: "Pixel_9_Pro",
            product: nil,
            deviceCodeName: nil,
            transportID: nil
        )
    }

    private func successfulResult(standardOutput: String = "") -> ProcessResult {
        ProcessResult(
            standardOutput: Data(standardOutput.utf8),
            standardError: Data(),
            exitStatus: 0,
            durationMilliseconds: 5,
            failureDescription: nil,
            wasCancelled: false
        )
    }
}

private struct ProcessInvocation: Equatable {
    let executablePath: String
    let arguments: [String]
}

private actor ScriptedScreenRecordingProcessRunner: ProcessRunning {
    private var results: [ProcessResult]
    private var recordedInvocations: [ProcessInvocation] = []

    init(results: [ProcessResult]) {
        self.results = results
    }

    var invocations: [ProcessInvocation] {
        return recordedInvocations
    }

    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        recordedInvocations.append(ProcessInvocation(executablePath: executablePath, arguments: arguments))
        return results.removeFirst()
    }
}

private final class RecordingScreenFileManager: ScreenRecordingFileManaging, @unchecked Sendable {
    private(set) var createdDirectories: [URL] = []
    private(set) var movedDestination: URL?

    func ensureDirectoryExists(at directoryURL: URL) throws {
        createdDirectories.append(directoryURL)
    }

    func fileExists(at fileURL: URL) -> Bool {
        false
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        movedDestination = destinationURL
    }

    func removeItemIfPresent(at fileURL: URL) {}
}
