import Foundation

public enum ScreenshotCaptureResult: Equatable, Sendable {
    case success(ScreenshotCaptureOutput)
    case failure(ScreenshotCaptureError)
}

public enum ScreenshotCaptureError: Equatable, Sendable {
    case deviceUnavailable
    case adbFailed(String)
    case invalidPNG
    case unableToAddDeviceDetails
    case unableToAddFrame
    case unableToCreateFiftyPercentCopy
    case unableToSave(String)

    public var message: String {
        switch self {
        case .deviceUnavailable:
            "The selected device is not connected and authorized."
        case .adbFailed(let message):
            message
        case .invalidPNG:
            "ADB did not return valid PNG screenshot data."
        case .unableToAddDeviceDetails:
            "Could not add the Android version and API level to the screenshot."
        case .unableToAddFrame:
            "Could not add a frame to the screenshot."
        case .unableToCreateFiftyPercentCopy:
            "Could not create a 50% size copy of the screenshot."
        case .unableToSave(let message):
            "Could not save the screenshot: \(message)"
        }
    }
}

public protocol ScreenshotFileManaging: Sendable {
    func ensureDirectoryExists(at directoryURL: URL) throws
    func fileExists(at fileURL: URL) -> Bool
    func write(_ data: Data, to fileURL: URL) throws
}

public struct LocalScreenshotFileManager: ScreenshotFileManaging {
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

    public func write(_ data: Data, to fileURL: URL) throws {
        try data.write(to: fileURL, options: .withoutOverwriting)
    }
}

public struct ScreenshotService: Sendable {
    private let adbPath: String
    private let sdkRootPath: String?
    private let processRunner: any ProcessRunning
    private let fileManager: any ScreenshotFileManaging

    public init(
        adbPath: String,
        sdkRootPath: String? = nil,
        processRunner: any ProcessRunning,
        fileManager: any ScreenshotFileManaging = LocalScreenshotFileManager()
    ) {
        self.adbPath = adbPath
        self.sdkRootPath = sdkRootPath
        self.processRunner = processRunner
        self.fileManager = fileManager
    }

    public func capture(
        device: AndroidDevice,
        destination: URL,
        framing: ScreenshotFramingOptions = .disabled,
        output: ScreenshotOutputOptions = .standard,
        date: Date = Date()
    ) async -> ScreenshotCaptureResult {
        guard device.isUsable else {
            return .failure(.deviceUnavailable)
        }

        let processResult = await processRunner.run(
            executablePath: adbPath,
            arguments: ["-s", device.serial, "exec-out", "screencap", "-p"]
        )

        guard processResult.succeeded else {
            return .failure(.adbFailed(adbFailureMessage(from: processResult)))
        }

        guard isPNG(processResult.standardOutput) else {
            return .failure(.invalidPNG)
        }

        let deviceDetails: AndroidDeviceDetails?
        if framing.overlaysDeviceDetails {
            guard let resolvedDeviceDetails = await AndroidDeviceDetailsService(
                adbPath: adbPath,
                processRunner: processRunner
            ).details(for: device) else {
                return .failure(.unableToAddDeviceDetails)
            }
            deviceDetails = resolvedDeviceDetails
        } else {
            deviceDetails = nil
        }

        let annotatedScreenshotData: Data
        if let deviceDetails {
            guard let overlayData = ScreenshotDeviceDetailsOverlayRenderer.overlay(
                deviceDetails: deviceDetails,
                on: processResult.standardOutput
            ) else {
                return .failure(.unableToAddDeviceDetails)
            }
            annotatedScreenshotData = overlayData
        } else {
            annotatedScreenshotData = processResult.standardOutput
        }

        let framingData: Data?
        if framing.addsFrame {
            guard let unannotatedFrameData = await ScreenshotFrameRenderer(
                adbPath: adbPath,
                sdkRootPath: sdkRootPath,
                processRunner: processRunner
            ).framedPNG(from: processResult.standardOutput, for: device) else {
                return .failure(.unableToAddFrame)
            }

            if let deviceDetails {
                guard let frameWithOverlayData = ScreenshotDeviceDetailsOverlayRenderer.overlay(
                    deviceDetails: deviceDetails,
                    on: unannotatedFrameData
                ) else {
                    return .failure(.unableToAddDeviceDetails)
                }
                framingData = frameWithOverlayData
            } else {
                framingData = unannotatedFrameData
            }
        } else {
            framingData = nil
        }

        let primaryScreenshotData = framingData ?? annotatedScreenshotData
        let fiftyPercentScreenshotData: Data?
        if output.alsoSavesFiftyPercentCopy {
            guard let resizedScreenshotData = ScreenshotImageResizer.fiftyPercentPNG(
                from: primaryScreenshotData
            ) else {
                return .failure(.unableToCreateFiftyPercentCopy)
            }
            fiftyPercentScreenshotData = resizedScreenshotData
        } else {
            fiftyPercentScreenshotData = nil
        }

        let isFramed = framingData != nil
        let fileURLs = ScreenshotFilename.uniqueScreenshotURLs(
            in: destination,
            deviceName: device.displayName,
            date: date,
            primarySuffix: isFramed ? "_framed" : "",
            alsoSavesOriginal: isFramed && framing.alsoSavesOriginal,
            alsoSavesFiftyPercentCopy: output.alsoSavesFiftyPercentCopy,
            fileExists: fileManager.fileExists(at:)
        )

        do {
            try fileManager.ensureDirectoryExists(at: destination)
            if let originalFileURL = fileURLs.originalFileURL {
                try fileManager.write(annotatedScreenshotData, to: originalFileURL)
            }
            try fileManager.write(primaryScreenshotData, to: fileURLs.primaryFileURL)
            if let fiftyPercentFileURL = fileURLs.fiftyPercentFileURL,
               let fiftyPercentScreenshotData {
                try fileManager.write(fiftyPercentScreenshotData, to: fiftyPercentFileURL)
            }
            return .success(ScreenshotCaptureOutput(
                primaryFileURL: fileURLs.primaryFileURL,
                originalFileURL: fileURLs.originalFileURL,
                fiftyPercentFileURL: fileURLs.fiftyPercentFileURL
            ))
        } catch {
            return .failure(.unableToSave(error.localizedDescription))
        }
    }

    private func isPNG(_ data: Data) -> Bool {
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        let IHDR: [UInt8] = [73, 72, 68, 82]

        guard data.count >= 24 else {
            return false
        }

        return Array(data.prefix(signature.count)) == signature
            && Array(data[12..<16]) == IHDR
    }

    private func adbFailureMessage(from result: ProcessResult) -> String {
        if result.wasCancelled {
            return "Screenshot capture was cancelled."
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
