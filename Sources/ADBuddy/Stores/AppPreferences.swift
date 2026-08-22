import Foundation
import Observation

@MainActor
@Observable
final class AppPreferences {
    private enum Key {
        static let screenshotDirectoryPath = "screenshotDirectoryPath"
        static let automaticallyCopyScreenshots = "automaticallyCopyScreenshots"
        static let screenRecordingBitRateMegabitsPerSecond = "screenRecordingBitRateMegabitsPerSecond"
        static let screenRecordingResolutionPercentage = "screenRecordingResolutionPercentage"
        static let screenRecordingShowsTaps = "screenRecordingShowsTaps"
    }

    private let userDefaults: UserDefaults
    private let defaultScreenshotDirectory: URL

    var screenshotDirectory: URL {
        didSet {
            userDefaults.set(screenshotDirectory.path, forKey: Key.screenshotDirectoryPath)
        }
    }

    var automaticallyCopyScreenshots: Bool {
        didSet {
            userDefaults.set(automaticallyCopyScreenshots, forKey: Key.automaticallyCopyScreenshots)
        }
    }

    var screenRecordingBitRateMegabitsPerSecond: Int {
        didSet {
            userDefaults.set(screenRecordingBitRateMegabitsPerSecond, forKey: Key.screenRecordingBitRateMegabitsPerSecond)
        }
    }

    var screenRecordingResolutionPercentage: Int {
        didSet {
            userDefaults.set(screenRecordingResolutionPercentage, forKey: Key.screenRecordingResolutionPercentage)
        }
    }

    var screenRecordingShowsTaps: Bool {
        didSet {
            userDefaults.set(screenRecordingShowsTaps, forKey: Key.screenRecordingShowsTaps)
        }
    }

    init(
        userDefaults: UserDefaults = .standard,
        defaultScreenshotDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Screenshots", isDirectory: true)
    ) {
        self.userDefaults = userDefaults
        self.defaultScreenshotDirectory = defaultScreenshotDirectory

        if let savedPath = userDefaults.string(forKey: Key.screenshotDirectoryPath), !savedPath.isEmpty {
            screenshotDirectory = URL(fileURLWithPath: savedPath, isDirectory: true)
        } else {
            screenshotDirectory = defaultScreenshotDirectory
        }

        automaticallyCopyScreenshots = userDefaults.object(forKey: Key.automaticallyCopyScreenshots) as? Bool ?? true
        screenRecordingBitRateMegabitsPerSecond = userDefaults.object(forKey: Key.screenRecordingBitRateMegabitsPerSecond) as? Int
            ?? ScreenRecordingOptions.default.bitRateMegabitsPerSecond
        screenRecordingResolutionPercentage = userDefaults.object(forKey: Key.screenRecordingResolutionPercentage) as? Int
            ?? ScreenRecordingOptions.default.resolution.rawValue
        screenRecordingShowsTaps = userDefaults.object(forKey: Key.screenRecordingShowsTaps) as? Bool
            ?? ScreenRecordingOptions.default.showsTaps
    }

    func resetScreenshotDirectory() {
        screenshotDirectory = defaultScreenshotDirectory
    }
}
