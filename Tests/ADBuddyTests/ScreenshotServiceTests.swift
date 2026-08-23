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

    func testClipsTheScreenshotToTheSDKSkinsRoundedDisplayCorners() async throws {
        let fixture = try ScreenshotFrameFixture.make()
        let screenshotData = try ScreenshotFrameFixture.pngData(
            width: 400,
            height: 800,
            red: 1,
            green: 0,
            blue: 0
        )
        defer {
            try? FileManager.default.removeItem(at: fixture.temporaryDirectory)
        }

        let fileManager = RecordingScreenshotFileManager()
        let result = await ScreenshotService(
            adbPath: "/SDK/platform-tools/adb",
            sdkRootPath: fixture.sdkRootURL.path,
            processRunner: ScriptedScreenshotProcessRunner(results: [
                successfulProcessResult(standardOutput: screenshotData),
                successfulProcessResult(standardOutput: "\(fixture.avdDirectoryURL.path)\nOK\n"),
            ]),
            fileManager: fileManager
        ).capture(
            device: emulatorDevice,
            destination: URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true),
            framing: ScreenshotFramingOptions(addsFrame: true, alsoSavesOriginal: false)
        )

        guard case .success(let output) = result,
              let framedData = fileManager.writtenFiles[output.primaryFileURL],
              let framedPixels = pixelImage(in: framedData) else {
            return XCTFail("Expected a framed screenshot")
        }

        let bezelPixel = framedPixels.pixel(atX: 100, y: 100)
        XCTAssertEqual(framedPixels.pixel(atX: 200, y: 200), bezelPixel)
        XCTAssertEqual(framedPixels.pixel(atX: 599, y: 200), bezelPixel)
        XCTAssertEqual(framedPixels.pixel(atX: 200, y: 999), bezelPixel)
        XCTAssertNotEqual(framedPixels.pixel(atX: 400, y: 200), bezelPixel)
    }

    func testUsesTheSDKSkinsMaskToExcludeTheScreenshotFromTheFrameEdge() async throws {
        let fixture = try ScreenshotFrameFixture.make(includesDisplayMask: true)
        let screenshotData = try ScreenshotFrameFixture.pngData(
            width: 400,
            height: 800,
            red: 1,
            green: 0,
            blue: 0
        )
        defer {
            try? FileManager.default.removeItem(at: fixture.temporaryDirectory)
        }

        let fileManager = RecordingScreenshotFileManager()
        let result = await ScreenshotService(
            adbPath: "/SDK/platform-tools/adb",
            sdkRootPath: fixture.sdkRootURL.path,
            processRunner: ScriptedScreenshotProcessRunner(results: [
                successfulProcessResult(standardOutput: screenshotData),
                successfulProcessResult(standardOutput: "\(fixture.avdDirectoryURL.path)\nOK\n"),
            ]),
            fileManager: fileManager
        ).capture(
            device: emulatorDevice,
            destination: URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true),
            framing: ScreenshotFramingOptions(addsFrame: true, alsoSavesOriginal: false)
        )

        guard case .success(let output) = result,
              let framedData = fileManager.writtenFiles[output.primaryFileURL],
              let framedPixels = pixelImage(in: framedData) else {
            return XCTFail("Expected a framed screenshot")
        }

        let maskedFramePixel = framedPixels.pixel(atX: 450, y: 600)
        XCTAssertGreaterThan(maskedFramePixel[1], maskedFramePixel[0])
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
        let screenshotData = try ScreenshotFrameFixture.verticallySplitPNGData(width: 100, height: 200)
        defer {
            try? FileManager.default.removeItem(at: fixture.temporaryDirectory)
        }

        let fileManager = RecordingScreenshotFileManager()
        let result = await ScreenshotService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: StubScreenshotProcessRunner(
                result: successfulProcessResult(standardOutput: screenshotData)
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

        XCTAssertEqual(try XCTUnwrap(imageSize(in: framedData)), CGSize(width: 140, height: 240))

        let originalPixels = try XCTUnwrap(pixelImage(in: screenshotData))
        let framedPixels = try XCTUnwrap(pixelImage(in: framedData))
        XCTAssertNotEqual(originalPixels.pixel(atX: 50, y: 40), originalPixels.pixel(atX: 50, y: 160))
        XCTAssertEqual(framedPixels.pixel(atX: 70, y: 60), originalPixels.pixel(atX: 50, y: 40))
        XCTAssertEqual(framedPixels.pixel(atX: 70, y: 180), originalPixels.pixel(atX: 50, y: 160))
    }

    func testOverlaysDeviceDetailsOnAnUnframedScreenshot() async throws {
        let screenshotData = try ScreenshotFrameFixture.pngData(
            width: 400,
            height: 800,
            red: 0,
            green: 0,
            blue: 1
        )
        let processRunner = ScriptedScreenshotProcessRunner(results: [
            successfulProcessResult(standardOutput: screenshotData),
            successfulProcessResult(standardOutput: "16\n"),
            successfulProcessResult(standardOutput: "36\n"),
        ])
        let fileManager = RecordingScreenshotFileManager()

        let result = await ScreenshotService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: processRunner,
            fileManager: fileManager
        ).capture(
            device: connectedDevice,
            destination: URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true),
            framing: ScreenshotFramingOptions(
                addsFrame: false,
                alsoSavesOriginal: false,
                overlaysDeviceDetails: true
            )
        )

        guard case .success(let output) = result,
              let overlayData = fileManager.writtenFiles[output.primaryFileURL] else {
            return XCTFail("Expected an annotated screenshot")
        }

        XCTAssertEqual(try XCTUnwrap(imageSize(in: overlayData)), CGSize(width: 400, height: 800))
        let originalPixels = try XCTUnwrap(pixelImage(in: screenshotData))
        let overlayPixels = try XCTUnwrap(pixelImage(in: overlayData))
        let requests = await processRunner.requests()
        XCTAssertTrue(overlayPixels.differs(from: originalPixels))
        XCTAssertTrue(overlayPixels.differs(
            from: originalPixels,
            in: CGRect(x: 0, y: 0, width: 200, height: 160)
        ))
        XCTAssertFalse(overlayPixels.differs(
            from: originalPixels,
            in: CGRect(x: 0, y: 640, width: 200, height: 160)
        ))
        XCTAssertEqual(requests, [
            ["-s", "device-serial", "exec-out", "screencap", "-p"],
            ["-s", "device-serial", "shell", "getprop", "ro.build.version.release"],
            ["-s", "device-serial", "shell", "getprop", "ro.build.version.sdk"],
        ])
    }

    func testOverlaysDeviceDetailsOverTheFrame() async throws {
        let fixture = try ScreenshotFrameFixture.make()
        let screenshotData = try ScreenshotFrameFixture.pngData(
            width: 400,
            height: 800,
            red: 0,
            green: 0,
            blue: 1
        )
        defer {
            try? FileManager.default.removeItem(at: fixture.temporaryDirectory)
        }

        let unannotatedFileManager = RecordingScreenshotFileManager()
        let unannotatedResult = await ScreenshotService(
            adbPath: "/SDK/platform-tools/adb",
            sdkRootPath: fixture.sdkRootURL.path,
            processRunner: ScriptedScreenshotProcessRunner(results: [
                successfulProcessResult(standardOutput: screenshotData),
                successfulProcessResult(standardOutput: "\(fixture.avdDirectoryURL.path)\nOK\n"),
            ]),
            fileManager: unannotatedFileManager
        ).capture(
            device: emulatorDevice,
            destination: URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true),
            framing: ScreenshotFramingOptions(addsFrame: true, alsoSavesOriginal: false)
        )

        let annotatedFileManager = RecordingScreenshotFileManager()
        let annotatedResult = await ScreenshotService(
            adbPath: "/SDK/platform-tools/adb",
            sdkRootPath: fixture.sdkRootURL.path,
            processRunner: ScriptedScreenshotProcessRunner(results: [
                successfulProcessResult(standardOutput: screenshotData),
                successfulProcessResult(standardOutput: "16\n"),
                successfulProcessResult(standardOutput: "36\n"),
                successfulProcessResult(standardOutput: "\(fixture.avdDirectoryURL.path)\nOK\n"),
            ]),
            fileManager: annotatedFileManager
        ).capture(
            device: emulatorDevice,
            destination: URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true),
            framing: ScreenshotFramingOptions(
                addsFrame: true,
                alsoSavesOriginal: false,
                overlaysDeviceDetails: true
            )
        )

        guard case .success(let unannotatedOutput) = unannotatedResult,
              case .success(let annotatedOutput) = annotatedResult,
              let unannotatedFrameData = unannotatedFileManager.writtenFiles[unannotatedOutput.primaryFileURL],
              let annotatedFrameData = annotatedFileManager.writtenFiles[annotatedOutput.primaryFileURL] else {
            return XCTFail("Expected framed screenshots")
        }

        let unannotatedPixels = try XCTUnwrap(pixelImage(in: unannotatedFrameData))
        let annotatedPixels = try XCTUnwrap(pixelImage(in: annotatedFrameData))
        XCTAssertEqual(try XCTUnwrap(imageSize(in: annotatedFrameData)), CGSize(width: 800, height: 1_200))
        XCTAssertTrue(annotatedPixels.differs(
            from: unannotatedPixels,
            in: CGRect(x: 0, y: 0, width: 180, height: 160)
        ))
        XCTAssertFalse(annotatedPixels.differs(
            from: unannotatedPixels,
            in: CGRect(x: 0, y: 1_040, width: 180, height: 160)
        ))
    }

    func testDoesNotSaveWhenTheDeviceDetailsOverlayCannotBeResolved() async {
        let fileManager = RecordingScreenshotFileManager()
        let result = await ScreenshotService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: ScriptedScreenshotProcessRunner(results: [
                successfulProcessResult,
                successfulProcessResult(standardOutput: "\n"),
            ]),
            fileManager: fileManager
        ).capture(
            device: connectedDevice,
            destination: URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true),
            framing: ScreenshotFramingOptions(
                addsFrame: false,
                alsoSavesOriginal: false,
                overlaysDeviceDetails: true
            )
        )

        XCTAssertEqual(result, .failure(.unableToAddDeviceDetails))
        XCTAssertTrue(fileManager.writtenFiles.isEmpty)
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

    private func pixelImage(in data: Data) -> PixelImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let didDraw = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return didDraw ? PixelImage(width: image.width, height: image.height, pixels: pixels) : nil
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

private struct PixelImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    func pixel(atX x: Int, y: Int) -> [UInt8] {
        let index = (y * width + x) * 4
        return Array(pixels[index..<(index + 4)])
    }

    func differs(from other: PixelImage) -> Bool {
        width == other.width && height == other.height && pixels != other.pixels
    }

    func differs(from other: PixelImage, in rect: CGRect) -> Bool {
        guard width == other.width,
              height == other.height,
              rect.minX >= 0,
              rect.minY >= 0,
              rect.maxX <= CGFloat(width),
              rect.maxY <= CGFloat(height) else {
            return false
        }

        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                if pixel(atX: x, y: y) != other.pixel(atX: x, y: y) {
                    return true
                }
            }
        }
        return false
    }
}

private struct ScreenshotFrameFixture {
    let temporaryDirectory: URL
    let sdkRootURL: URL
    let avdDirectoryURL: URL
    let screenshotData: Data

    static func make(includesDisplayMask: Bool = false) throws -> ScreenshotFrameFixture {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ADBuddyScreenshotFrameTests-\(UUID().uuidString)", isDirectory: true)
        let sdkRootURL = temporaryDirectory.appendingPathComponent("sdk", isDirectory: true)
        let skinDirectoryURL = sdkRootURL
            .appendingPathComponent("skins", isDirectory: true)
            .appendingPathComponent("pixel_test", isDirectory: true)
        let avdDirectoryURL = temporaryDirectory.appendingPathComponent("Pixel_Test.avd", isDirectory: true)

        try FileManager.default.createDirectory(at: skinDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: avdDirectoryURL, withIntermediateDirectories: true)

        let foreground = includesDisplayMask
            ? """
              foreground {
                mask mask.png
              }
            """
            : ""
        try Data(
            """
            parts {
              device {
                display {
                  width 4
                  height 8
                  x 0
                  y 0
                  corner_radius 1
                }
              }
              portrait {
                background {
                  image back.png
                }
            \(foreground)
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
        if includesDisplayMask {
            try displayMaskPNGData().write(to: skinDirectoryURL.appendingPathComponent("mask.png"))
        }

        return ScreenshotFrameFixture(
            temporaryDirectory: temporaryDirectory,
            sdkRootURL: sdkRootURL,
            avdDirectoryURL: avdDirectoryURL,
            screenshotData: try verticallySplitPNGData(width: 4, height: 8)
        )
    }

    static func pngData(
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

        return try encodedPNGData(from: filledImage)
    }

    static func verticallySplitPNGData(width: Int, height: Int) throws -> Data {
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
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        guard let image = context.makeImage() else {
            throw ScreenshotFrameFixtureError.unableToCreateImage
        }

        return try encodedPNGData(from: image)
    }

    private static func displayMaskPNGData() throws -> Data {
        guard let context = CGContext(
            data: nil,
            width: 4,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScreenshotFrameFixtureError.unableToCreateImage
        }
        context.clear(CGRect(x: 0, y: 0, width: 4, height: 8))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
        context.fill(CGRect(x: 2, y: 0, width: 1, height: 8))
        guard let image = context.makeImage() else {
            throw ScreenshotFrameFixtureError.unableToCreateImage
        }
        return try encodedPNGData(from: image)
    }

    private static func encodedPNGData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenshotFrameFixtureError.unableToEncodeImage
        }
        CGImageDestinationAddImage(destination, image, nil)
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
