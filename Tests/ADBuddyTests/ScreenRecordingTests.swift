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
        ])
        let fileManager = RecordingScreenFileManager()
        let capture = TestScreenRecordingCapture()
        let service = ScreenRecordingService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: processRunner,
            fileManager: fileManager,
            capture: capture
        )
        let session = ScreenRecordingSession(device: connectedDevice)
        let destination = URL(fileURLWithPath: "/tmp/media", isDirectory: true)
        let result = await service.record(
            session: session,
            options: ScreenRecordingOptions(
                bitRateMegabitsPerSecond: 8, resolution: .fiftyPercent, showsTaps: true
            ),
            destination: destination,
            date: Date(timeIntervalSince1970: 0),
            onScreenRecorderStarted: {}
        )
        guard case .success(let output, let warning) = result else {
            return XCTFail("Expected a saved recording: \(result)")
        }
        XCTAssertNil(warning)
        XCTAssertTrue(output.primaryFileURL.lastPathComponent.hasPrefix("Pixel-9-Pro_1970-01-01_"))
        XCTAssertEqual(output.primaryFileURL.pathExtension, "mp4")
        XCTAssertNil(output.originalFileURL)
        XCTAssertEqual(fileManager.createdDirectories, [destination])
        XCTAssertEqual(fileManager.movedDestination, output.primaryFileURL)
        let requests = await capture.requests
        XCTAssertEqual(requests.first?.outputSize, AndroidDisplaySize(width: 540, height: 1206))
        XCTAssertEqual(requests.first?.bitRate, 8_000_000)
        let arguments = await processRunner.invocations.map(\.arguments)
        XCTAssertEqual(arguments, [
            ["-s", connectedDevice.serial, "shell", "wm", "size"],
            ["-s", connectedDevice.serial, "shell", "settings", "get", "system", "show_touches"],
            ["-s", connectedDevice.serial, "shell", "settings", "put", "system", "show_touches", "1"],
            ["-s", connectedDevice.serial, "shell", "settings", "put", "system", "show_touches", "0"],
        ])
    }

    func testSavesAndFramesEveryClipWithOneSessionAndRestoresTapsOnce() async {
        let runner = ScriptedScreenRecordingProcessRunner(results: [
            successfulResult(standardOutput: "0\n"), successfulResult(), successfulResult(),
        ])
        let files = RecordingScreenFileManager()
        let framer = ScriptedScreenRecordingFramer(result: .success)
        let capture = TestScreenRecordingCapture(clipCount: 3)
        let result = await ScreenRecordingService(
            adbPath: "/SDK/adb", processRunner: runner, fileManager: files,
            recordingFramer: framer, capture: capture
        ).record(
            session: ScreenRecordingSession(device: connectedDevice),
            options: ScreenRecordingOptions(bitRateMegabitsPerSecond: 8, resolution: .native, showsTaps: true),
            destination: URL(fileURLWithPath: "/tmp/media"),
            framing: ScreenRecordingFramingOptions(addsFrame: true, overlaysDeviceDetails: false),
            onScreenRecorderStarted: {}
        )
        guard case .success(let output, let warning) = result else {
            return XCTFail("Expected all recording clips")
        }
        XCTAssertNil(warning)
        XCTAssertEqual(output.clips.count, 3)
        XCTAssertEqual(output.savedFileURLs.count, 6)
        for (index, clip) in output.clips.enumerated() {
            XCTAssertTrue(clip.primaryFileURL.lastPathComponent.hasSuffix(String(format: "_%02d_framed.mp4", index + 1)))
            XCTAssertTrue(clip.originalFileURL?.lastPathComponent.hasSuffix(String(format: "_%02d.mp4", index + 1)) == true)
        }
        let frameRequests = await framer.requests()
        XCTAssertEqual(frameRequests.map(\.outputURL), output.primaryFileURLs)
        let captureRequests = await capture.requests
        XCTAssertEqual(captureRequests.count, 1)
        let commands = await runner.invocations
        XCTAssertEqual(commands.count, 3)
    }

    func testRetainsCompletedClipsWhenRecordingFailsLater() async {
        let result = await ScreenRecordingService(
            adbPath: "/SDK/adb", processRunner: ScriptedScreenRecordingProcessRunner(results: []),
            fileManager: RecordingScreenFileManager(),
            capture: TestScreenRecordingCapture(fails: true, clipCount: 2, retainsClipsOnFailure: true)
        ).record(
            session: ScreenRecordingSession(device: connectedDevice), options: .default,
            destination: URL(fileURLWithPath: "/tmp/media"), onScreenRecorderStarted: {}
        )
        guard case .success(let output, let warning) = result else {
            return XCTFail("Expected completed footage to survive")
        }
        XCTAssertEqual(output.clips.count, 2)
        XCTAssertTrue(warning?.contains("Completed clips were retained") == true)
    }

    func testAvoidsCollisionsAcrossTheWholeClipGroup() async {
        let files = RecordingScreenFileManager()
        files.collidingSuffix = "_02_framed.mp4"
        let result = await ScreenRecordingService(
            adbPath: "/SDK/adb", processRunner: ScriptedScreenRecordingProcessRunner(results: []),
            fileManager: files, recordingFramer: ScriptedScreenRecordingFramer(result: .success),
            capture: TestScreenRecordingCapture(clipCount: 2)
        ).record(
            session: ScreenRecordingSession(device: connectedDevice), options: .default,
            destination: URL(fileURLWithPath: "/tmp/media"),
            framing: ScreenRecordingFramingOptions(addsFrame: true, overlaysDeviceDetails: false),
            onScreenRecorderStarted: {}
        )
        guard case .success(let output, _) = result else { return XCTFail("Expected clips") }
        XCTAssertTrue(output.clips[0].primaryFileURL.lastPathComponent.hasSuffix("-2_01_framed.mp4"))
        XCTAssertTrue(output.clips[1].primaryFileURL.lastPathComponent.hasSuffix("-2_02_framed.mp4"))
    }

    func testBackendReturnsCompletedClipsAfterFailureAndRemovesUnfinishedClip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ADBuddyBackendTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("scrcpy")
        let script = """
        #!/bin/sh
        for argument in "$@"; do
          case "$argument" in --record=*) output="${argument#--record=}" ;; esac
        done
        test "$ADBUDDY_RECORDING_SEGMENTS" = 1 || exit 2
        printf 'completed clip' > "$output.0001.mp4"
        printf 'completed clip' > "$output.0002.mp4"
        printf 'unfinished clip' > "$output.0003.mp4.inprogress"
        exit 1
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try Data().write(to: directory.appendingPathComponent("scrcpy-server"))
        let output = directory.appendingPathComponent("capture.partial")
        let result = await ScrcpyScreenRecordingCapture(adbPath: "/unused", backendDirectory: directory).record(
            session: ScreenRecordingSession(device: connectedDevice), bitRateBitsPerSecond: 8_000_000,
            outputSize: nil, outputURL: output, onStarted: {}
        )
        XCTAssertEqual(result.processResult.exitStatus, 1)
        XCTAssertEqual(result.clipURLs.map(\.lastPathComponent), ["capture.partial.0001.mp4", "capture.partial.0002.mp4"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path + ".0003.mp4.inprogress"))
    }

    func testStopsOnlyTheRequestedCaptureSession() async {
        let capture = TestScreenRecordingCapture()
        let service = ScreenRecordingService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: ScriptedScreenRecordingProcessRunner(results: []),
            capture: capture
        )
        let session = ScreenRecordingSession(device: connectedDevice)
        let stopResult = await service.stop(session: session)
        XCTAssertEqual(stopResult, .stopped)
        let sessions = await capture.stoppedSessions
        XCTAssertEqual(sessions, [session])
    }

    func testLocksCaptureToPhysicalDeviceWithoutControllingItsOrientation() {
        let arguments = ScrcpyScreenRecordingCapture.arguments(
            serial: "device-serial", bitRateBitsPerSecond: 8_000_000,
            outputSize: AndroidDisplaySize(width: 540, height: 1200),
            outputURL: URL(fileURLWithPath: "/tmp/media folder/capture.mp4")
        )
        XCTAssertTrue(arguments.contains("--capture-orientation=@0"))
        XCTAssertTrue(arguments.contains("--no-control"))
        XCTAssertTrue(arguments.contains("--no-window"))
        XCTAssertTrue(arguments.contains("--no-audio"))
        XCTAssertTrue(arguments.contains("--max-size=1200"))
        XCTAssertTrue(arguments.contains("--record=/tmp/media folder/capture.mp4"))
        let nativeArguments = ScrcpyScreenRecordingCapture.arguments(
            serial: "device-serial", bitRateBitsPerSecond: 8_000_000,
            outputSize: nil, outputURL: URL(fileURLWithPath: "/tmp/native.mp4")
        )
        XCTAssertFalse(nativeArguments.contains { $0.hasPrefix("--max-size") })
    }

    func testRestoresTapsAndRemovesPartialCaptureAfterFailure() async {
        let runner = ScriptedScreenRecordingProcessRunner(results: [
            successfulResult(standardOutput: "null\n"), successfulResult(), successfulResult(),
        ])
        let files = RecordingScreenFileManager()
        let service = ScreenRecordingService(
            adbPath: "/SDK/adb", processRunner: runner, fileManager: files,
            capture: TestScreenRecordingCapture(fails: true)
        )
        let result = await service.record(
            session: ScreenRecordingSession(device: connectedDevice),
            options: ScreenRecordingOptions(bitRateMegabitsPerSecond: 8, resolution: .native, showsTaps: true),
            destination: URL(fileURLWithPath: "/tmp/media"), onScreenRecorderStarted: {}
        )
        guard case .failure = result else { return XCTFail("Expected capture failure") }
        let invocations = await runner.invocations
        XCTAssertEqual(invocations.last?.arguments.suffix(3), ["delete", "system", "show_touches"].suffix(3))
        XCTAssertNil(files.movedDestination)
        XCTAssertEqual(files.removedURLs.count, 1)
    }

    func testMissingBundledRecorderFailsWithoutReportingStarted() async {
        let capture = ScrcpyScreenRecordingCapture(
            adbPath: "/SDK/adb", backendDirectory: URL(fileURLWithPath: "/missing-adbuddy-recorder")
        )
        let result = await capture.record(
            session: ScreenRecordingSession(device: connectedDevice),
            bitRateBitsPerSecond: 8_000_000, outputSize: nil,
            outputURL: URL(fileURLWithPath: "/tmp/unused-recording.mp4"),
            onStarted: { XCTFail("A missing recorder cannot start") }
        )
        XCTAssertFalse(result.processResult.succeeded)
        XCTAssertTrue(result.processResult.failureDescription?.contains("Rebuild or reinstall") == true)
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
            recordingFramer: framer,
            capture: TestScreenRecordingCapture()
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
                device: connectedDevice,
                overlaysDeviceDetails: false
            )]
        )
    }

    func testPassesTheDeviceDetailsOverlayPreferenceToTheFramer() async {
        let processRunner = ScriptedScreenRecordingProcessRunner(results: [
            successfulResult(),
            successfulResult(),
            successfulResult(),
        ])
        let framer = ScriptedScreenRecordingFramer(result: .success)
        let service = ScreenRecordingService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: processRunner,
            fileManager: RecordingScreenFileManager(),
            recordingFramer: framer,
            capture: TestScreenRecordingCapture()
        )

        _ = await service.record(
            session: ScreenRecordingSession(device: connectedDevice),
            options: .default,
            destination: URL(fileURLWithPath: "/tmp/media", isDirectory: true),
            framing: ScreenRecordingFramingOptions(
                addsFrame: true,
                overlaysDeviceDetails: true
            ),
            onScreenRecorderStarted: {}
        )

        let requests = await framer.requests()
        XCTAssertEqual(requests.first?.overlaysDeviceDetails, true)
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
            recordingFramer: framer,
            capture: TestScreenRecordingCapture()
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
            recordingFramer: framer,
            capture: TestScreenRecordingCapture()
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
            device: connectedDevice,
            overlaysDeviceDetails: false
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
    private(set) var removedURLs: [URL] = []
    var collidingSuffix: String?

    func ensureDirectoryExists(at directoryURL: URL) throws {
        createdDirectories.append(directoryURL)
    }

    func fileExists(at fileURL: URL) -> Bool {
        guard let collidingSuffix else { return false }
        return fileURL.lastPathComponent.hasSuffix(collidingSuffix)
            && !fileURL.lastPathComponent.contains("-2_")
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        movedDestination = destinationURL
    }

    func removeItemIfPresent(at fileURL: URL) { removedURLs.append(fileURL) }
}

private struct ScreenRecordingFramingRequest: Equatable {
    let inputURL: URL
    let outputURL: URL
    let device: AndroidDevice
    let overlaysDeviceDetails: Bool
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
        device: AndroidDevice,
        overlaysDeviceDetails: Bool
    ) async -> ScreenRecordingFramingResult {
        recordedRequests.append(ScreenRecordingFramingRequest(
            inputURL: inputURL,
            outputURL: outputURL,
            device: device,
            overlaysDeviceDetails: overlaysDeviceDetails
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
