import Foundation

struct ScreenRecordingOptions: Equatable, Sendable {
    static let `default` = ScreenRecordingOptions(
        bitRateMegabitsPerSecond: 8,
        resolution: .native,
        showsTaps: false
    )

    let bitRateMegabitsPerSecond: Int
    let resolution: ScreenRecordingResolution
    let showsTaps: Bool

    var bitRateBitsPerSecond: Int {
        bitRateMegabitsPerSecond * 1_000_000
    }

    var validationMessage: String? {
        guard (1...200).contains(bitRateMegabitsPerSecond) else {
            return "Use a bit rate between 1 and 200 Mbps."
        }
        return nil
    }
}

enum ScreenRecordingResolution: Int, CaseIterable, Equatable, Identifiable, Sendable {
    case native = 100
    case seventyFivePercent = 75
    case fiftyPercent = 50
    case twentyFivePercent = 25

    var id: Int {
        rawValue
    }

    var displayName: String {
        "\(rawValue)"
    }

    func outputSize(for nativeSize: AndroidDisplaySize) -> AndroidDisplaySize? {
        guard self != .native else {
            return nil
        }
        return nativeSize.scaled(to: rawValue)
    }
}

struct AndroidDisplaySize: Equatable, Sendable {
    let width: Int
    let height: Int

    init?(width: Int, height: Int) {
        guard width > 1, height > 1 else {
            return nil
        }
        self.width = width
        self.height = height
    }

    var adbArgument: String {
        "\(width)x\(height)"
    }

    func scaled(to percentage: Int) -> AndroidDisplaySize {
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

enum AndroidDisplaySizeParser {
    static func parse(_ output: String) -> AndroidDisplaySize? {
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

struct ScreenRecordingSession: Equatable, Sendable {
    let device: AndroidDevice
    let remoteFilePath: String

    init(device: AndroidDevice, remoteFilePath: String? = nil) {
        self.device = device
        self.remoteFilePath = remoteFilePath
            ?? "/data/local/tmp/adbuddy-recording-\(UUID().uuidString).mp4"
    }
}

enum ScreenRecordingActivity: Equatable {
    case preparing(ScreenRecordingSession)
    case recording(ScreenRecordingSession)
    case stopping(ScreenRecordingSession)
}

enum ScreenRecordingFeedback: Equatable {
    case success(URL, warning: String?)
    case failure(String)

    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    var title: String {
        switch self {
        case .success(_, let warning):
            warning == nil ? "Recording Saved" : "Recording Saved with Warning"
        case .failure:
            "Recording Failed"
        }
    }

    var detail: String {
        switch self {
        case .success(let fileURL, let warning):
            warning ?? fileURL.lastPathComponent
        case .failure(let message):
            message
        }
    }
}
