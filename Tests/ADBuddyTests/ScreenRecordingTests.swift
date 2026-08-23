import AVFoundation
import CoreGraphics
import CoreVideo
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

        guard case .success(let output, let warning) = result else {
            return XCTFail("Expected a saved recording")
        }
        XCTAssertNil(warning)
        XCTAssertTrue(output.primaryFileURL.lastPathComponent.hasPrefix("Pixel-9-Pro_1970-01-01_"))
        XCTAssertEqual(output.primaryFileURL.pathExtension, "mp4")
        XCTAssertNil(output.originalFileURL)
        XCTAssertEqual(fileManager.createdDirectories, [destination])
        XCTAssertEqual(fileManager.movedDestination, output.primaryFileURL)

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

    func testCopiedRecordingFeedbackIncludesClipboardDetail() {
        let recordingURL = URL(fileURLWithPath: "/tmp/Pixel-9-Pro.mp4")
        let feedback = ScreenRecordingFeedback.success(
            recordingURL,
            warning: nil,
            copiedToClipboard: true
        )

        XCTAssertEqual(feedback.title, "Recording Saved")
        XCTAssertEqual(feedback.detail, "Pixel-9-Pro.mp4 copied to the clipboard.")
    }

    func testRetainsTheOriginalRecordingAndSavesAFramedMP4() async {
        let processRunner = ScriptedScreenRecordingProcessRunner(results: [
            successfulResult(),
            successfulResult(),
            successfulResult(),
        ])
        let fileManager = RecordingScreenFileManager()
        let framer = ScriptedScreenRecordingFramer(result: .success)
        let service = ScreenRecordingService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: processRunner,
            fileManager: fileManager,
            recordingFramer: framer
        )
        let destination = URL(fileURLWithPath: "/tmp/media", isDirectory: true)

        let result = await service.record(
            session: ScreenRecordingSession(device: connectedDevice),
            options: .default,
            destination: destination,
            framing: ScreenRecordingFramingOptions(addsFrame: true),
            date: Date(timeIntervalSince1970: 0),
            onScreenRecorderStarted: {}
        )

        guard case .success(let output, let warning) = result,
              let originalURL = output.originalFileURL else {
            return XCTFail("Expected original and framed recordings")
        }
        XCTAssertNil(warning)
        XCTAssertEqual(fileManager.movedDestination, originalURL)
        XCTAssertTrue(output.primaryFileURL.lastPathComponent.hasSuffix("_framed.mp4"))
        XCTAssertEqual(output.savedFileURLs, [originalURL, output.primaryFileURL])
        let framingRequests = await framer.requests()
        XCTAssertEqual(
            framingRequests,
            [ScreenRecordingFramingRequest(
                inputURL: originalURL,
                outputURL: output.primaryFileURL,
                device: connectedDevice
            )]
        )
    }

    func testKeepsTheOriginalRecordingWhenFramingFails() async {
        let processRunner = ScriptedScreenRecordingProcessRunner(results: [
            successfulResult(),
            successfulResult(),
            successfulResult(),
        ])
        let framer = ScriptedScreenRecordingFramer(result: .failure("The MP4 is unreadable."))
        let service = ScreenRecordingService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: processRunner,
            fileManager: RecordingScreenFileManager(),
            recordingFramer: framer
        )

        let result = await service.record(
            session: ScreenRecordingSession(device: connectedDevice),
            options: .default,
            destination: URL(fileURLWithPath: "/tmp/media", isDirectory: true),
            framing: ScreenRecordingFramingOptions(addsFrame: true),
            onScreenRecorderStarted: {}
        )

        guard case .success(let output, let warning) = result else {
            return XCTFail("Expected the original recording to be preserved")
        }
        XCTAssertNil(output.originalFileURL)
        XCTAssertFalse(output.primaryFileURL.lastPathComponent.hasSuffix("_framed.mp4"))
        XCTAssertTrue(warning?.contains("could not add a device frame") == true)
    }

    func testKeepsTheOriginalRecordingWhenFramingIsCancelled() async {
        let processRunner = ScriptedScreenRecordingProcessRunner(results: [
            successfulResult(),
            successfulResult(),
            successfulResult(),
        ])
        let framer = ScriptedScreenRecordingFramer(result: .cancelled)
        let service = ScreenRecordingService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: processRunner,
            fileManager: RecordingScreenFileManager(),
            recordingFramer: framer
        )

        let result = await service.record(
            session: ScreenRecordingSession(device: connectedDevice),
            options: .default,
            destination: URL(fileURLWithPath: "/tmp/media", isDirectory: true),
            framing: ScreenRecordingFramingOptions(addsFrame: true),
            onScreenRecorderStarted: {}
        )

        guard case .success(let output, let warning) = result else {
            return XCTFail("Expected the original recording to be preserved")
        }
        XCTAssertNil(output.originalFileURL)
        XCTAssertFalse(output.primaryFileURL.lastPathComponent.hasSuffix("_framed.mp4"))
        XCTAssertTrue(warning?.contains("framing was cancelled") == true)
    }

    func testBuildsGenericAndSDKVideoFrameCompositionGeometry() throws {
        let genericGeometry = try XCTUnwrap(
            ScreenRecordingFrameGeometry.generic(for: CGSize(width: 100, height: 200))
        )
        XCTAssertEqual(genericGeometry.canvasSize, CGSize(width: 140, height: 240))
        XCTAssertEqual(genericGeometry.videoRect, CGRect(x: 20, y: 20, width: 100, height: 200))

        let oddGenericGeometry = try XCTUnwrap(
            ScreenRecordingFrameGeometry.generic(for: CGSize(width: 65, height: 129))
        )
        XCTAssertEqual(oddGenericGeometry.canvasSize, CGSize(width: 106, height: 170))

        let layout = AndroidSDKSkinFrameLayout(
            skinIdentifier: "pixel_test",
            canvasSize: CGSize(width: 1198, height: 2531),
            displayRect: CGRect(x: 55, y: 58, width: 1080, height: 2424),
            displayCornerRadius: 87,
            backdropImageURLs: [],
            displayMaskImageURLs: [],
            overlayImageURLs: [],
            frameOverlayImageURLs: []
        )
        let sdkFrame = try XCTUnwrap(ScreenRecordingFrameGeometry.sdk(
            layout: layout,
            videoSize: CGSize(width: 1080, height: 2424)
        ))
        XCTAssertEqual(sdkFrame.geometry.canvasSize, CGSize(width: 1198, height: 2532))
        XCTAssertEqual(sdkFrame.geometry.videoRect, CGRect(x: 55, y: 50, width: 1080, height: 2424))

        let configuration = try XCTUnwrap(ScreenRecordingVideoCompositionConfiguration(
            naturalVideoSize: CGSize(width: 1080, height: 2424),
            preferredTransform: .identity,
            frameGeometry: sdkFrame.geometry,
            nominalFrameRate: 30
        ))
        XCTAssertEqual(configuration.renderSize, CGSize(width: 1198, height: 2532))
        XCTAssertEqual(configuration.videoTransform, CGAffineTransform(translationX: 55, y: 50))
        XCTAssertEqual(configuration.frameDuration, CMTime(value: 1, timescale: 30))

        let rotatedGeometry = try XCTUnwrap(
            ScreenRecordingFrameGeometry.generic(for: CGSize(width: 1080, height: 1920))
        )
        let rotatedConfiguration = try XCTUnwrap(ScreenRecordingVideoCompositionConfiguration(
            naturalVideoSize: CGSize(width: 1920, height: 1080),
            preferredTransform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0),
            frameGeometry: rotatedGeometry,
            nominalFrameRate: 30
        ))
        XCTAssertEqual(
            CGRect(x: 0, y: 0, width: 1920, height: 1080)
                .applying(rotatedConfiguration.videoTransform)
                .standardized,
            rotatedGeometry.videoRect
        )
    }

    func testExportsAGenericFramedMP4() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ADBuddyRecordingFrameTests-\(UUID().uuidString)", isDirectory: true)
        let inputURL = temporaryDirectory.appendingPathComponent("recording.mp4")
        let outputURL = temporaryDirectory.appendingPathComponent("recording_framed.mp4")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try await writeTestVideo(to: inputURL)
        let framer = AVFoundationScreenRecordingFramer(
            adbPath: "/SDK/platform-tools/adb",
            sdkRootPath: nil,
            processRunner: ScriptedScreenRecordingProcessRunner(results: [])
        )

        let result = await framer.frame(
            recordingAt: inputURL,
            outputURL: outputURL,
            device: connectedDevice
        )

        XCTAssertEqual(result, .success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        let outputAsset = AVURLAsset(url: outputURL)
        let outputTracks = try await outputAsset.loadTracks(withMediaType: .video)
        let outputTrack = try XCTUnwrap(outputTracks.first)
        let outputSize = try await outputTrack.load(.naturalSize)
        let outputDuration = try await outputAsset.load(.duration)
        XCTAssertEqual(outputSize, CGSize(width: 104, height: 168))
        XCTAssertEqual(CMTimeGetSeconds(outputDuration), 1, accuracy: 0.01)
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

    private func writeTestVideo(to outputURL: URL) async throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 128,
            ]
        )
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 128,
            ]
        )
        guard writer.canAdd(writerInput) else {
            throw TestVideoWriterError.unableToAddInput
        }
        writer.add(writerInput)
        guard writer.startWriting() else {
            throw writer.error ?? TestVideoWriterError.unableToStart
        }
        writer.startSession(atSourceTime: .zero)

        for presentationTime in [CMTime.zero, CMTime(value: 1, timescale: 2)] {
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let pixelBuffer = makeTestPixelBuffer() else {
                throw TestVideoWriterError.unableToCreatePixelBuffer
            }
            guard pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? TestVideoWriterError.unableToAppendFrame
            }
        }
        writerInput.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? TestVideoWriterError.unableToFinish
        }
    }

    private func makeTestPixelBuffer() -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            64,
            128,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey as String: true] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess,
              let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: 64,
            height: 128,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return nil
        }
        context.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 128))
        return pixelBuffer
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

private struct ScreenRecordingFramingRequest: Equatable {
    let inputURL: URL
    let outputURL: URL
    let device: AndroidDevice
}

private actor ScriptedScreenRecordingFramer: ScreenRecordingFraming {
    private let result: ScreenRecordingFramingResult
    private var recordedRequests: [ScreenRecordingFramingRequest] = []

    init(result: ScreenRecordingFramingResult) {
        self.result = result
    }

    func frame(
        recordingAt inputURL: URL,
        outputURL: URL,
        device: AndroidDevice
    ) async -> ScreenRecordingFramingResult {
        recordedRequests.append(ScreenRecordingFramingRequest(
            inputURL: inputURL,
            outputURL: outputURL,
            device: device
        ))
        return result
    }

    func requests() -> [ScreenRecordingFramingRequest] {
        recordedRequests
    }
}

private enum TestVideoWriterError: Error {
    case unableToAddInput
    case unableToStart
    case unableToCreatePixelBuffer
    case unableToAppendFrame
    case unableToFinish
}
