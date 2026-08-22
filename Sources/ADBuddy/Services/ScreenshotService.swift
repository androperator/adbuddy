import Foundation

enum ScreenshotCaptureResult: Equatable, Sendable {
    case success(URL)
    case failure(ScreenshotCaptureError)
}

enum ScreenshotCaptureError: Equatable, Sendable {
    case deviceUnavailable
    case adbFailed(String)
    case invalidPNG
    case unableToSave(String)

    var message: String {
        switch self {
        case .deviceUnavailable:
            "The selected device is not connected and authorized."
        case .adbFailed(let message):
            message
        case .invalidPNG:
            "ADB did not return valid PNG screenshot data."
        case .unableToSave(let message):
            "Could not save the screenshot: \(message)"
        }
    }
}

protocol ScreenshotFileManaging: Sendable {
    func ensureDirectoryExists(at directoryURL: URL) throws
    func fileExists(at fileURL: URL) -> Bool
    func write(_ data: Data, to fileURL: URL) throws
}

struct LocalScreenshotFileManager: ScreenshotFileManaging {
    func ensureDirectoryExists(at directoryURL: URL) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func fileExists(at fileURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    func write(_ data: Data, to fileURL: URL) throws {
        try data.write(to: fileURL, options: .withoutOverwriting)
    }
}

struct ScreenshotService: Sendable {
    private let adbPath: String
    private let processRunner: any ProcessRunning
    private let fileManager: any ScreenshotFileManaging

    init(
        adbPath: String,
        processRunner: any ProcessRunning,
        fileManager: any ScreenshotFileManaging = LocalScreenshotFileManager()
    ) {
        self.adbPath = adbPath
        self.processRunner = processRunner
        self.fileManager = fileManager
    }

    func capture(
        device: AndroidDevice,
        destination: URL,
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

        do {
            try fileManager.ensureDirectoryExists(at: destination)
            let fileURL = ScreenshotFilename.uniqueURL(
                in: destination,
                deviceName: device.displayName,
                date: date,
                fileExists: fileManager.fileExists(at:)
            )
            try fileManager.write(processResult.standardOutput, to: fileURL)
            return .success(fileURL)
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
