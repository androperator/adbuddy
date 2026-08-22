import Foundation
import XCTest
@testable import ADBuddy

final class ScreenshotServiceTests: XCTestCase {
    func testSavesValidPNGToUniqueDestination() async {
        let fileManager = RecordingScreenshotFileManager()
        let service = ScreenshotService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: StubScreenshotProcessRunner(result: successfulProcessResult),
            fileManager: fileManager
        )
        let destination = URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true)

        let result = await service.capture(
            device: connectedDevice,
            destination: destination,
            date: Date(timeIntervalSince1970: 0)
        )

        guard case .success(let fileURL) = result else {
            return XCTFail("Expected a successful screenshot capture")
        }
        XCTAssertEqual(fileManager.createdDirectories, [destination])
        XCTAssertEqual(fileManager.writtenFiles[fileURL], validPNG)
        XCTAssertEqual(fileURL.pathExtension, "png")
    }

    func testRejectsNonPNGOutputWithoutWritingAFile() async {
        let fileManager = RecordingScreenshotFileManager()
        let result = await ScreenshotService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: StubScreenshotProcessRunner(
                result: ProcessResult(
                    standardOutput: Data("not an image".utf8),
                    standardError: Data(),
                    exitStatus: 0,
                    durationMilliseconds: 5,
                    failureDescription: nil,
                    wasCancelled: false
                )
            ),
            fileManager: fileManager
        ).capture(device: connectedDevice, destination: URL(fileURLWithPath: "/tmp/screenshots"))

        XCTAssertEqual(result, .failure(.invalidPNG))
        XCTAssertTrue(fileManager.writtenFiles.isEmpty)
    }

    func testLocalFileManagerWritesWithoutOverwriting() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("adbuddy-screenshot-test-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let fileManager = LocalScreenshotFileManager()
        let screenshotData = validPNG

        try fileManager.write(screenshotData, to: fileURL)

        XCTAssertEqual(try Data(contentsOf: fileURL), screenshotData)
        XCTAssertThrowsError(try fileManager.write(screenshotData, to: fileURL))
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

    private var successfulProcessResult: ProcessResult {
        ProcessResult(
            standardOutput: validPNG,
            standardError: Data(),
            exitStatus: 0,
            durationMilliseconds: 5,
            failureDescription: nil,
            wasCancelled: false
        )
    }

    private var validPNG: Data {
        Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1])
    }
}

private struct StubScreenshotProcessRunner: ProcessRunning {
    let result: ProcessResult

    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        result
    }
}

private final class RecordingScreenshotFileManager: ScreenshotFileManaging, @unchecked Sendable {
    private(set) var createdDirectories: [URL] = []
    private(set) var writtenFiles: [URL: Data] = [:]

    func ensureDirectoryExists(at directoryURL: URL) throws {
        createdDirectories.append(directoryURL)
    }

    func fileExists(at fileURL: URL) -> Bool {
        writtenFiles[fileURL] != nil
    }

    func write(_ data: Data, to fileURL: URL) throws {
        writtenFiles[fileURL] = data
    }
}
