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

    public init(
        adbPath: String,
        sdkRootPath: String? = nil,
        processRunner: any ProcessRunning,
        fileManager: any ScreenRecordingFileManaging = LocalScreenRecordingFileManager(),
        recordingFramer: (any ScreenRecordingFraming)? = nil
    ) {
        self.adbPath = adbPath
        self.processRunner = processRunner
        self.fileManager = fileManager
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

        await onScreenRecorderStarted()
        let screenRecordResult = await processRunner.run(
            executablePath: adbPath,
            arguments: screenRecordArguments(
                for: session,
                bitRateBitsPerSecond: options.bitRateBitsPerSecond,
                outputSize: outputSize
            )
        )

        let showTapsRestoreFailure = await restoreShowTapsIfNeeded(
            originalShowTapsSetting,
            for: session.device
        )

        guard screenRecordResult.succeeded else {
            await removeRemoteRecording(for: session)
            return .failure(.adbFailed(adbFailureMessage(from: screenRecordResult)))
        }

        let pullResult = await processRunner.run(
            executablePath: adbPath,
            arguments: [
                "-s", session.device.serial,
                "pull", session.remoteFilePath, destinationURLs.temporaryURL.path,
            ]
        )
        await removeRemoteRecording(for: session)

        guard pullResult.succeeded else {
            fileManager.removeItemIfPresent(at: destinationURLs.temporaryURL)
            return .failure(.unableToSave(adbFailureMessage(from: pullResult)))
        }

        do {
            try fileManager.moveItem(at: destinationURLs.temporaryURL, to: destinationURLs.originalURL)
        } catch {
            fileManager.removeItemIfPresent(at: destinationURLs.temporaryURL)
            return .failure(.unableToSave(error.localizedDescription))
        }

        var warnings = showTapsRestoreFailure.map {
            ["\(destinationURLs.originalURL.lastPathComponent) was saved, but Show taps could not be restored: \($0)"]
        } ?? []

        guard let framedURL = destinationURLs.framedURL else {
            return .success(
                ScreenRecordingCaptureOutput(
                    primaryFileURL: destinationURLs.originalURL,
                    originalFileURL: nil
                ),
                warning: warnings.isEmpty ? nil : warnings.joined(separator: " ")
            )
        }

        switch await recordingFramer.frame(
            recordingAt: destinationURLs.originalURL,
            outputURL: framedURL,
            device: session.device
        ) {
        case .success:
            return .success(
                ScreenRecordingCaptureOutput(
                    primaryFileURL: framedURL,
                    originalFileURL: destinationURLs.originalURL
                ),
                warning: warnings.isEmpty ? nil : warnings.joined(separator: " ")
            )
        case .failure(let message):
            warnings.append(
                "\(destinationURLs.originalURL.lastPathComponent) was saved, but ADBuddy could not add a device frame: \(message)"
            )
        case .cancelled:
            warnings.append(
                "\(destinationURLs.originalURL.lastPathComponent) was saved, but device framing was cancelled."
            )
        }

        return .success(
            ScreenRecordingCaptureOutput(
                primaryFileURL: destinationURLs.originalURL,
                originalFileURL: nil
            ),
            warning: warnings.joined(separator: " ")
        )
    }

    public func stop(session: ScreenRecordingSession) async -> ScreenRecordingStopResult {
        let result = await processRunner.run(
            executablePath: adbPath,
            arguments: [
                "-s", session.device.serial,
                "shell", "pkill", "-INT", "-f", session.remoteFilePath,
            ]
        )

        if result.succeeded {
            return .stopped
        }
        return .failure(adbFailureMessage(from: result))
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

    private func screenRecordArguments(
        for session: ScreenRecordingSession,
        bitRateBitsPerSecond: Int,
        outputSize: AndroidDisplaySize?
    ) -> [String] {
        var arguments = [
            "-s", session.device.serial,
            "shell", "screenrecord",
            "--bit-rate", "\(bitRateBitsPerSecond)",
        ]
        if let outputSize {
            arguments.append(contentsOf: ["--size", outputSize.adbArgument])
        }
        arguments.append(session.remoteFilePath)
        return arguments
    }

    private func restoreShowTapsIfNeeded(
        _ originalSetting: ShowTapsSetting?,
        for device: AndroidDevice
    ) async -> String? {
        guard let originalSetting else {
            return nil
        }

        let result = await processRunner.run(
            executablePath: adbPath,
            arguments: originalSetting.restoreArguments(for: device.serial)
        )
        return result.succeeded ? nil : adbFailureMessage(from: result)
    }

    private func removeRemoteRecording(for session: ScreenRecordingSession) async {
        _ = await processRunner.run(
            executablePath: adbPath,
            arguments: ["-s", session.device.serial, "shell", "rm", "-f", session.remoteFilePath]
        )
    }

    private func adbFailureMessage(from result: ProcessResult) -> String {
        if result.wasCancelled {
            return "Recording was cancelled."
        }

        if let failureDescription = result.failureDescription, !failureDescription.isEmpty {
            return "Could not start ADB: \(failureDescription)"
        }

        let standardError = String(decoding: result.standardError, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !standardError.isEmpty {
            return standardError
        }

        if let exitStatus = result.exitStatus {
            return "ADB exited with status \(exitStatus)."
        }

        return "ADB did not return a result."
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
