import Foundation

public struct ScreenRecordingOptions: Equatable, Sendable {
    public static let `default` = ScreenRecordingOptions(
        bitRateMegabitsPerSecond: 8,
        resolution: .native,
        showsTaps: false
    )

    public let bitRateMegabitsPerSecond: Int
    public let resolution: ScreenRecordingResolution
    public let showsTaps: Bool

    public init(
        bitRateMegabitsPerSecond: Int,
        resolution: ScreenRecordingResolution,
        showsTaps: Bool
    ) {
        self.bitRateMegabitsPerSecond = bitRateMegabitsPerSecond
        self.resolution = resolution
        self.showsTaps = showsTaps
    }

    public var bitRateBitsPerSecond: Int {
        bitRateMegabitsPerSecond * 1_000_000
    }

    public var validationMessage: String? {
        guard (1...200).contains(bitRateMegabitsPerSecond) else {
            return "Use a bit rate between 1 and 200 Mbps."
        }
        return nil
    }
}

public struct ScreenRecordingCaptureOutput: Equatable, Sendable {
    public let primaryFileURL: URL
    public let originalFileURL: URL?

    public init(primaryFileURL: URL, originalFileURL: URL?) {
        self.primaryFileURL = primaryFileURL
        self.originalFileURL = originalFileURL
    }

    public var savedFileURLs: [URL] {
        if let originalFileURL {
            [originalFileURL, primaryFileURL]
        } else {
            [primaryFileURL]
        }
    }
}

public enum ScreenRecordingResolution: Int, CaseIterable, Equatable, Identifiable, Sendable {
    case native = 100
    case seventyFivePercent = 75
    case fiftyPercent = 50
    case twentyFivePercent = 25

    public var id: Int {
        rawValue
    }

    public var displayName: String {
        "\(rawValue)"
    }

    public func outputSize(for nativeSize: AndroidDisplaySize) -> AndroidDisplaySize? {
        guard self != .native else {
            return nil
        }
        return nativeSize.scaled(to: rawValue)
    }
}

public struct AndroidDisplaySize: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init?(width: Int, height: Int) {
        guard width > 1, height > 1 else {
            return nil
        }
        self.width = width
        self.height = height
    }

    public var adbArgument: String {
        "\(width)x\(height)"
    }

    public func scaled(to percentage: Int) -> AndroidDisplaySize {
        let factor = Double(percentage) / 100
        return AndroidDisplaySize(
            width: roundedToEvenDimension(Double(width) * factor),
            height: roundedToEvenDimension(Double(height) * factor)
        )!
    }

    private func roundedToEvenDimension(_ value: Double) -> Int {
        let roundedValue = max(2, Int(value.rounded()))
        return roundedValue.isMultiple(of: 2) ? roundedValue : roundedValue + 1
    }
}

public enum AndroidDisplaySizeParser {
    public static func parse(_ output: String) -> AndroidDisplaySize? {
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedLine.hasPrefix("Physical size:") else {
                continue
            }

            let dimensions = trimmedLine.dropFirst("Physical size:".count)
                .trimmingCharacters(in: .whitespaces)
                .split(separator: "x", maxSplits: 1)
            guard dimensions.count == 2,
                  let width = Int(dimensions[0]),
                  let height = Int(dimensions[1]) else {
                return nil
            }
            return AndroidDisplaySize(width: width, height: height)
        }

        return nil
    }
}

public struct ScreenRecordingSession: Equatable, Sendable {
    public let device: AndroidDevice
    public let remoteFilePath: String

    public init(device: AndroidDevice, remoteFilePath: String? = nil) {
        self.device = device
        self.remoteFilePath = remoteFilePath
            ?? "/data/local/tmp/adbuddy-recording-\(UUID().uuidString).mp4"
    }
}

public enum ScreenRecordingActivity: Equatable {
    case preparing(ScreenRecordingSession)
    case recording(ScreenRecordingSession)
    case stopping(ScreenRecordingSession)
}

public enum ScreenRecordingFeedback: Equatable {
    case success(URL, warning: String?, copiedToClipboard: Bool)
    case failure(String)

    public var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    public var title: String {
        switch self {
        case .success(_, let warning, _):
            warning == nil ? "Recording Saved" : "Recording Saved with Warning"
        case .failure:
            "Recording Failed"
        }
    }

    public var detail: String {
        switch self {
        case .success(let fileURL, let warning, let copiedToClipboard):
            let copyDetail = copiedToClipboard
                ? "\(fileURL.lastPathComponent) copied to the clipboard."
                : fileURL.lastPathComponent
            guard let warning else {
                return copyDetail
            }
            return copiedToClipboard ? "\(warning) Copied to the clipboard." : warning
        case .failure(let message):
            return message
        }
    }
}
