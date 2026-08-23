import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

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

        guard case .success(let output) = result else {
            return XCTFail("Expected a successful screenshot capture")
        }
        let fileURL = output.primaryFileURL
        XCTAssertEqual(fileManager.createdDirectories, [destination])
        XCTAssertEqual(fileManager.writtenFiles[fileURL], validPNG)
        XCTAssertEqual(fileURL.pathExtension, "png")
        XCTAssertNil(output.originalFileURL)
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

    func testFramesAnEmulatorScreenshotUsingItsConfiguredSDKSkin() async throws {
        let fixture = try ScreenshotFrameFixture.make()
        defer {
            try? FileManager.default.removeItem(at: fixture.temporaryDirectory)
        }

        let fileManager = RecordingScreenshotFileManager()
        let service = ScreenshotService(
            adbPath: "/SDK/platform-tools/adb",
            sdkRootPath: fixture.sdkRootURL.path,
            processRunner: ScriptedScreenshotProcessRunner(results: [
                successfulProcessResult(standardOutput: fixture.screenshotData),
                successfulProcessResult(standardOutput: "\(fixture.avdDirectoryURL.path)\nOK\n"),
            ]),
            fileManager: fileManager
        )
        let destination = URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true)

        let result = await service.capture(
            device: emulatorDevice,
            destination: destination,
            framing: ScreenshotFramingOptions(addsFrame: true, alsoSavesOriginal: false),
            date: Date(timeIntervalSince1970: 0)
        )

        guard case .success(let output) = result,
              let framedData = fileManager.writtenFiles[output.primaryFileURL] else {
            return XCTFail("Expected a framed screenshot to be saved")
        }

        XCTAssertTrue(output.primaryFileURL.lastPathComponent.hasSuffix("_framed.png"))
        XCTAssertNil(output.originalFileURL)
        XCTAssertEqual(try XCTUnwrap(imageSize(in: framedData)), CGSize(width: 8, height: 12))
    }

    func testSavesOriginalAlongsideFramedScreenshotWhenRequested() async throws {
        let fixture = try ScreenshotFrameFixture.make()
        defer {
            try? FileManager.default.removeItem(at: fixture.temporaryDirectory)
        }

        let fileManager = RecordingScreenshotFileManager()
        let result = await ScreenshotService(
            adbPath: "/SDK/platform-tools/adb",
            sdkRootPath: fixture.sdkRootURL.path,
            processRunner: ScriptedScreenshotProcessRunner(results: [
                successfulProcessResult(standardOutput: fixture.screenshotData),
                successfulProcessResult(standardOutput: "\(fixture.avdDirectoryURL.path)\nOK\n"),
            ]),
            fileManager: fileManager
        ).capture(
            device: emulatorDevice,
            destination: URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true),
            framing: ScreenshotFramingOptions(addsFrame: true, alsoSavesOriginal: true),
            date: Date(timeIntervalSince1970: 0)
        )

        guard case .success(let output) = result,
              let originalFileURL = output.originalFileURL else {
            return XCTFail("Expected the original screenshot to be saved")
        }

        XCTAssertTrue(originalFileURL.lastPathComponent.hasSuffix(".png"))
        XCTAssertFalse(originalFileURL.lastPathComponent.hasSuffix("_framed.png"))
        XCTAssertEqual(
            output.primaryFileURL.deletingPathExtension().lastPathComponent,
            originalFileURL.deletingPathExtension().lastPathComponent + "_framed"
        )
        XCTAssertEqual(fileManager.writtenFiles[originalFileURL], fixture.screenshotData)
        XCTAssertEqual(
            try XCTUnwrap(imageSize(in: try XCTUnwrap(fileManager.writtenFiles[output.primaryFileURL]))),
            CGSize(width: 8, height: 12)
        )
    }

    func testUsesGenericFrameWhenTheCaptureIsNotFromAMatchedEmulatorSkin() async throws {
        let fixture = try ScreenshotFrameFixture.make()
        defer {
            try? FileManager.default.removeItem(at: fixture.temporaryDirectory)
        }

        let fileManager = RecordingScreenshotFileManager()
        let result = await ScreenshotService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: StubScreenshotProcessRunner(
                result: successfulProcessResult(standardOutput: fixture.screenshotData)
            ),
            fileManager: fileManager
        ).capture(
            device: connectedDevice,
            destination: URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true),
            framing: ScreenshotFramingOptions(addsFrame: true, alsoSavesOriginal: false)
        )

        guard case .success(let output) = result,
              let framedData = fileManager.writtenFiles[output.primaryFileURL] else {
            return XCTFail("Expected a generically framed screenshot")
        }

        XCTAssertEqual(try XCTUnwrap(imageSize(in: framedData)), CGSize(width: 44, height: 48))
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

    private var emulatorDevice: AndroidDevice {
        AndroidDevice(
            serial: "emulator-5554",
            displayName: "Pixel 9 Pro",
            connectionState: .connected,
            kind: .emulator,
            model: "sdk_gphone64_arm64",
            product: "sdk_gphone64_arm64",
            deviceCodeName: "emu64a",
            transportID: nil
        )
    }

    private var successfulProcessResult: ProcessResult {
        successfulProcessResult(standardOutput: validPNG)
    }

    private func successfulProcessResult(standardOutput: Data) -> ProcessResult {
        ProcessResult(
            standardOutput: standardOutput,
            standardError: Data(),
            exitStatus: 0,
            durationMilliseconds: 5,
            failureDescription: nil,
            wasCancelled: false
        )
    }

    private func successfulProcessResult(standardOutput: String) -> ProcessResult {
        successfulProcessResult(standardOutput: Data(standardOutput.utf8))
    }

    private var validPNG: Data {
        Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1])
    }

    private func imageSize(in data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return CGSize(width: image.width, height: image.height)
    }
}

private struct StubScreenshotProcessRunner: ProcessRunning {
    let result: ProcessResult

    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        result
    }
}

private actor ScriptedScreenshotProcessRunner: ProcessRunning {
    private var results: [ProcessResult]

    init(results: [ProcessResult]) {
        self.results = results
    }

    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        results.removeFirst()
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

private struct ScreenshotFrameFixture {
    let temporaryDirectory: URL
    let sdkRootURL: URL
    let avdDirectoryURL: URL
    let screenshotData: Data

    static func make() throws -> ScreenshotFrameFixture {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ADBuddyScreenshotFrameTests-\(UUID().uuidString)", isDirectory: true)
        let sdkRootURL = temporaryDirectory.appendingPathComponent("sdk", isDirectory: true)
        let skinDirectoryURL = sdkRootURL
            .appendingPathComponent("skins", isDirectory: true)
            .appendingPathComponent("pixel_test", isDirectory: true)
        let avdDirectoryURL = temporaryDirectory.appendingPathComponent("Pixel_Test.avd", isDirectory: true)

        try FileManager.default.createDirectory(at: skinDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: avdDirectoryURL, withIntermediateDirectories: true)

        try Data(
            """
            parts {
              device {
                display {
                  width 4
                  height 8
                  x 0
                  y 0
                }
              }
              portrait {
                background {
                  image back.png
                }
              }
            }
            layouts {
              portrait {
                width 8
                height 12
                part1 {
                  name portrait
                  x 0
                  y 0
                }
                part2 {
                  name device
                  x 2
                  y 2
                }
              }
            }
            """.utf8
        ).write(to: skinDirectoryURL.appendingPathComponent("layout"))
        try Data("skin.name=pixel_test\n".utf8).write(
            to: avdDirectoryURL.appendingPathComponent("config.ini")
        )
        try pngData(width: 8, height: 12, red: 0, green: 1, blue: 0).write(
            to: skinDirectoryURL.appendingPathComponent("back.png")
        )

        return ScreenshotFrameFixture(
            temporaryDirectory: temporaryDirectory,
            sdkRootURL: sdkRootURL,
            avdDirectoryURL: avdDirectoryURL,
            screenshotData: try pngData(width: 4, height: 8, red: 1, green: 0, blue: 0)
        )
    }

    private static func pngData(
        width: Int,
        height: Int,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
    ) throws -> Data {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScreenshotFrameFixtureError.unableToCreateImage
        }
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let filledImage = context.makeImage() else {
            throw ScreenshotFrameFixtureError.unableToCreateImage
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenshotFrameFixtureError.unableToEncodeImage
        }
        CGImageDestinationAddImage(destination, filledImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotFrameFixtureError.unableToEncodeImage
        }
        return data as Data
    }
}

private enum ScreenshotFrameFixtureError: Error {
    case unableToCreateImage
    case unableToEncodeImage
}
