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

        let annotatedScreenshotData: Data
        if framing.overlaysDeviceDetails {
            guard let deviceDetails = await AndroidDeviceDetailsService(
                adbPath: adbPath,
                processRunner: processRunner
            ).details(for: device), let overlayData = ScreenshotDeviceDetailsOverlayRenderer.overlay(
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
            framingData = await ScreenshotFrameRenderer(
                adbPath: adbPath,
                sdkRootPath: sdkRootPath,
                processRunner: processRunner
            ).framedPNG(from: annotatedScreenshotData, for: device)

            guard framingData != nil else {
                return .failure(.unableToAddFrame)
            }
        } else {
            framingData = nil
        }

        do {
            try fileManager.ensureDirectoryExists(at: destination)

            if let framingData {
                if framing.alsoSavesOriginal {
                    let fileURLs = ScreenshotFilename.uniqueOriginalAndFramedURLs(
                        in: destination,
                        deviceName: device.displayName,
                        date: date,
                        fileExists: fileManager.fileExists(at:)
                    )
                    try fileManager.write(annotatedScreenshotData, to: fileURLs.original)
                    try fileManager.write(framingData, to: fileURLs.framed)
                    return .success(ScreenshotCaptureOutput(
                        primaryFileURL: fileURLs.framed,
                        originalFileURL: fileURLs.original
                    ))
                }

                let framedURL = ScreenshotFilename.uniqueURL(
                    in: destination,
                    deviceName: device.displayName,
                    date: date,
                    suffix: "_framed",
                    fileExists: fileManager.fileExists(at:)
                )
                try fileManager.write(framingData, to: framedURL)
                return .success(ScreenshotCaptureOutput(
                    primaryFileURL: framedURL,
                    originalFileURL: nil
                ))
            }

            let fileURL = ScreenshotFilename.uniqueURL(
                in: destination,
                deviceName: device.displayName,
                date: date,
                fileExists: fileManager.fileExists(at:)
            )
            try fileManager.write(annotatedScreenshotData, to: fileURL)
            return .success(ScreenshotCaptureOutput(
                primaryFileURL: fileURL,
                originalFileURL: nil
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
