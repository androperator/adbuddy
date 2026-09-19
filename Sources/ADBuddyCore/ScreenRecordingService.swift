import Foundation

public enum ScreenRecordingResult: Equatable, Sendable {
    case success(ScreenRecordingCaptureOutput, warning: String?)
    case failure(ScreenRecordingError)
}

public enum ScreenRecordingStopResult: Equatable, Sendable {
    case stopped
    case failure(String)
}

public enum ScreenRecordingError: Equatable, Sendable {
    case deviceUnavailable
    case invalidOptions(String)
    case unableToDetermineDisplaySize
    case unableToPrepareDestination(String)
    case adbFailed(String)
    case unableToSave(String)

    public var message: String {
        switch self {
        case .deviceUnavailable:
            "The selected device is not connected and authorized."
        case .invalidOptions(let message), .adbFailed(let message):
            message
        case .unableToDetermineDisplaySize:
            "ADB could not determine the device's physical display size."
        case .unableToPrepareDestination(let message):
            "Could not prepare the media folder: \(message)"
        case .unableToSave(let message):
            "Could not save the recording: \(message)"
        }
    }
}

public protocol ScreenRecordingFileManaging: Sendable {
    func ensureDirectoryExists(at directoryURL: URL) throws
    func fileExists(at fileURL: URL) -> Bool
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws
    func removeItemIfPresent(at fileURL: URL)
}

public struct LocalScreenRecordingFileManager: ScreenRecordingFileManaging {
    public init() {}

    public func ensureDirectoryExists(at directoryURL: URL) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    public func fileExists(at fileURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    public func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    public func removeItemIfPresent(at fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

public struct ScreenRecordingService: Sendable {
    private let adbPath: String
    private let processRunner: any ProcessRunning
    private let fileManager: any ScreenRecordingFileManaging
    private let recordingFramer: any ScreenRecordingFraming
    private let capture: any ScreenRecordingCapturing

    public init(
        adbPath: String,
        sdkRootPath: String? = nil,
        processRunner: any ProcessRunning,
        fileManager: any ScreenRecordingFileManaging = LocalScreenRecordingFileManager(),
        recordingFramer: (any ScreenRecordingFraming)? = nil,
        capture: (any ScreenRecordingCapturing)? = nil
    ) {
        self.adbPath = adbPath
        self.processRunner = processRunner
        self.fileManager = fileManager
        self.capture = capture ?? ScrcpyScreenRecordingCapture(adbPath: adbPath)
        self.recordingFramer = recordingFramer ?? AVFoundationScreenRecordingFramer(
            adbPath: adbPath,
            sdkRootPath: sdkRootPath,
            processRunner: processRunner
        )
    }

    public func record(
        session: ScreenRecordingSession,
        options: ScreenRecordingOptions,
        destination: URL,
        framing: ScreenRecordingFramingOptions = .disabled,
        date: Date = Date(),
        onScreenRecorderStarted: @escaping @MainActor @Sendable () -> Void
    ) async -> ScreenRecordingResult {
        guard session.device.isUsable else {
            return .failure(.deviceUnavailable)
        }

        if let validationMessage = options.validationMessage {
            return .failure(.invalidOptions(validationMessage))
        }

        let destinationURLs: RecordingDestinationURLs
        do {
            try fileManager.ensureDirectoryExists(at: destination)
            destinationURLs = makeDestinationURLs(
                directory: destination,
                deviceName: session.device.displayName,
                date: date,
                addsFrame: framing.addsFrame
            )
        } catch {
            return .failure(.unableToPrepareDestination(error.localizedDescription))
        }

        let outputSize: AndroidDisplaySize?
        if options.resolution == .native {
            outputSize = nil
        } else {
            let sizeResult = await processRunner.run(
                executablePath: adbPath,
                arguments: ["-s", session.device.serial, "shell", "wm", "size"]
            )
            guard sizeResult.succeeded,
                  let nativeSize = AndroidDisplaySizeParser.parse(
                    String(decoding: sizeResult.standardOutput, as: UTF8.self)
                  ) else {
                return .failure(.unableToDetermineDisplaySize)
            }
            outputSize = options.resolution.outputSize(for: nativeSize)
        }

        let originalShowTapsSetting: ShowTapsSetting?
        if options.showsTaps {
            let settingResult = await processRunner.run(
                executablePath: adbPath,
                arguments: ["-s", session.device.serial, "shell", "settings", "get", "system", "show_touches"]
            )
            guard settingResult.succeeded else {
                return .failure(.adbFailed(adbFailureMessage(from: settingResult)))
            }

            originalShowTapsSetting = ShowTapsSetting(
                rawValue: String(decoding: settingResult.standardOutput, as: UTF8.self)
            )
            let enableTapsResult = await processRunner.run(
                executablePath: adbPath,
                arguments: ["-s", session.device.serial, "shell", "settings", "put", "system", "show_touches", "1"]
            )
            guard enableTapsResult.succeeded else {
                return .failure(.adbFailed(adbFailureMessage(from: enableTapsResult)))
            }
        } else {
            originalShowTapsSetting = nil
        }

        let backendResult = await capture.record(
            session: session,
            bitRateBitsPerSecond: options.bitRateBitsPerSecond,
            outputSize: outputSize,
            outputURL: destinationURLs.temporaryURL,
            onStarted: onScreenRecorderStarted
        )

        let showTapsRestoreFailure = await restoreShowTapsIfNeeded(
            originalShowTapsSetting,
            for: session.device
        )

        let screenRecordResult = backendResult.processResult
        guard !backendResult.clipURLs.isEmpty else {
            fileManager.removeItemIfPresent(at: destinationURLs.temporaryURL)
            var message = screenRecordResult.succeeded
                ? "The recorder did not produce a complete video clip."
                : adbFailureMessage(from: screenRecordResult)
            if let showTapsRestoreFailure {
                message += " Show taps could not be restored: \(showTapsRestoreFailure)"
            }
            return .failure(.adbFailed(message))
        }

        var warnings: [String] = []
        if !screenRecordResult.succeeded {
            warnings.append("Recording ended early: \(adbFailureMessage(from: screenRecordResult)) Completed clips were retained.")
        }
        if let showTapsRestoreFailure {
            warnings.append("Show taps could not be restored: \(showTapsRestoreFailure)")
        }
        let destinations = clipDestinations(for: destinationURLs, count: backendResult.clipURLs.count)
        var clips: [ScreenRecordingClip] = []
        for (temporaryURL, urls) in zip(backendResult.clipURLs, destinations) {
            do {
                try fileManager.moveItem(at: temporaryURL, to: urls.originalURL)
            } catch {
                // Keep completed footage recoverable even if final naming fails.
                warnings.append("Could not move a completed clip to \(urls.originalURL.lastPathComponent): \(error.localizedDescription). It remains at \(temporaryURL.path).")
                clips.append(ScreenRecordingClip(primaryFileURL: temporaryURL, originalFileURL: nil))
                continue
            }
            var clip = ScreenRecordingClip(primaryFileURL: urls.originalURL, originalFileURL: nil)
            if let framedURL = urls.framedURL {
                switch await recordingFramer.frame(
                    recordingAt: urls.originalURL,
                    outputURL: framedURL,
                    device: session.device,
                    overlaysDeviceDetails: framing.overlaysDeviceDetails
                ) {
                case .success:
                    clip = ScreenRecordingClip(primaryFileURL: framedURL, originalFileURL: urls.originalURL)
                case .failure(let message):
                    warnings.append("\(urls.originalURL.lastPathComponent) was saved, but ADBuddy could not add a device frame: \(message)")
                case .cancelled:
                    warnings.append("\(urls.originalURL.lastPathComponent) was saved, but device framing was cancelled.")
                }
            }
            clips.append(clip)
        }
        return .success(
            ScreenRecordingCaptureOutput(clips: clips),
            warning: warnings.isEmpty ? nil : warnings.joined(separator: " ")
        )
    }

    private func clipDestinations(
        for urls: RecordingDestinationURLs,
        count: Int
    ) -> [(originalURL: URL, framedURL: URL?)] {
        guard count > 1 else { return [(urls.originalURL, urls.framedURL)] }
        let base = urls.originalURL.deletingPathExtension()
        var attempt = 1
        while true {
            let collisionSuffix = attempt == 1 ? "" : "-\(attempt)"
            let destinations = (1...count).map { index in
                let path = base.path + collisionSuffix + String(format: "_%02d", index)
                return (
                    originalURL: URL(fileURLWithPath: path + ".mp4"),
                    framedURL: urls.framedURL == nil ? nil : URL(fileURLWithPath: path + "_framed.mp4")
                )
            }
            if destinations.allSatisfy({
                !fileManager.fileExists(at: $0.originalURL)
                    && ($0.framedURL.map { !fileManager.fileExists(at: $0) } ?? true)
            }) {
                return destinations
            }
            attempt += 1
        }
    }

    public func stop(session: ScreenRecordingSession) async -> ScreenRecordingStopResult {
        await capture.stop(session: session)
    }

    private func makeDestinationURLs(
        directory: URL,
        deviceName: String,
        date: Date,
        addsFrame: Bool
    ) -> RecordingDestinationURLs {
        let originalURL: URL
        let framedURL: URL?
        if addsFrame {
            let urls = ScreenshotFilename.uniqueOriginalAndFramedURLs(
                in: directory,
                deviceName: deviceName,
                date: date,
                fileExtension: "mp4",
                fileExists: fileManager.fileExists(at:)
            )
            originalURL = urls.original
            framedURL = urls.framed
        } else {
            originalURL = ScreenshotFilename.uniqueURL(
                in: directory,
                deviceName: deviceName,
                date: date,
                fileExtension: "mp4",
                fileExists: fileManager.fileExists(at:)
            )
            framedURL = nil
        }
        let temporaryURL = directory.appendingPathComponent(
            ".adbuddy-recording-\(UUID().uuidString).partial"
        )
        return RecordingDestinationURLs(
            originalURL: originalURL,
            framedURL: framedURL,
            temporaryURL: temporaryURL
        )
    }

    private func restoreShowTapsIfNeeded(
        _ originalSetting: ShowTapsSetting?,
        for device: AndroidDevice
    ) async -> String? {
        guard let originalSetting else {
            return nil
        }

        let result = await Task.detached {
            await processRunner.run(
                executablePath: adbPath,
                arguments: originalSetting.restoreArguments(for: device.serial)
            )
        }.value
        return result.succeeded ? nil : adbFailureMessage(from: result)
    }

    private func adbFailureMessage(from result: ProcessResult) -> String {
        if result.wasCancelled {
            return "Recording was cancelled."
        }

        if let failureDescription = result.failureDescription, !failureDescription.isEmpty {
            return failureDescription
        }

        let standardError = String(decoding: result.standardError, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !standardError.isEmpty {
            return standardError
        }

        if let exitStatus = result.exitStatus {
            return "The recording command exited with status \(exitStatus)."
        }

        return "The recording command did not return a result."
    }
}

private struct RecordingDestinationURLs {
    let originalURL: URL
    let framedURL: URL?
    let temporaryURL: URL
}

private enum ShowTapsSetting {
    case value(String)
    case notSet

    init(rawValue: String) {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self = trimmedValue.isEmpty || trimmedValue == "null" ? .notSet : .value(trimmedValue)
    }

    func restoreArguments(for serial: String) -> [String] {
        switch self {
        case .value(let value):
            ["-s", serial, "shell", "settings", "put", "system", "show_touches", value]
        case .notSet:
            ["-s", serial, "shell", "settings", "delete", "system", "show_touches"]
        }
    }
}
