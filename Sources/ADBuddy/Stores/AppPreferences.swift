import Foundation
import Observation

@MainActor
@Observable
final class AppPreferences {
    private enum Key {
        static let screenshotDirectoryPath = ADBuddySharedPreferences.screenshotDirectoryPathKey
        static let automaticallyCopyScreenshots = "automaticallyCopyScreenshots"
        static let screenRecordingBitRateMegabitsPerSecond = ADBuddySharedPreferences.screenRecordingBitRateMegabitsPerSecondKey
        static let screenRecordingResolutionPercentage = ADBuddySharedPreferences.screenRecordingResolutionPercentageKey
        static let screenRecordingShowsTaps = ADBuddySharedPreferences.screenRecordingShowsTapsKey
        static let logcatColors = "logcatColors"
        static let deepLinkLauncherEnabled = "deepLinkLauncherEnabled"
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

    var isDeepLinkLauncherEnabled: Bool {
        didSet {
            userDefaults.set(isDeepLinkLauncherEnabled, forKey: Key.deepLinkLauncherEnabled)
        }
    }

    private(set) var logcatColors: [LogcatPriority: LogcatColorComponents] {
        didSet {
            guard let encodedColors = try? JSONEncoder().encode(logcatColors) else {
                return
            }
            userDefaults.set(encodedColors, forKey: Key.logcatColors)
        }
    }

    init(
        userDefaults: UserDefaults = ADBuddySharedPreferences.userDefaults(),
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
        isDeepLinkLauncherEnabled = userDefaults.object(forKey: Key.deepLinkLauncherEnabled) as? Bool ?? false
        logcatColors = Self.loadLogcatColors(from: userDefaults) ?? LogcatPriority.defaultColors
    }

    func resetScreenshotDirectory() {
        screenshotDirectory = defaultScreenshotDirectory
    }

    func setLogcatColor(_ color: LogcatColorComponents, for priority: LogcatPriority) {
        logcatColors[priority] = color
    }

    func resetLogcatColors() {
        logcatColors = LogcatPriority.defaultColors
    }

    private static func loadLogcatColors(from userDefaults: UserDefaults) -> [LogcatPriority: LogcatColorComponents]? {
        guard let data = userDefaults.data(forKey: Key.logcatColors),
              let colors = try? JSONDecoder().decode([LogcatPriority: LogcatColorComponents].self, from: data),
              Set(colors.keys) == Set(LogcatPriority.allCases) else {
            return nil
        }
        return colors
    }
}
