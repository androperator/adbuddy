import Foundation
import Observation

@MainActor
@Observable
final class AppPreferences {
    private enum Key {
        static let screenshotDirectoryPath = ADBuddySharedPreferences.screenshotDirectoryPathKey
        static let screenshotAddsFrame = ADBuddySharedPreferences.screenshotAddsFrameKey
        static let screenshotAlsoSavesOriginal = ADBuddySharedPreferences.screenshotAlsoSavesOriginalKey
        static let screenshotAlsoSavesFiftyPercentCopy = ADBuddySharedPreferences.screenshotAlsoSavesFiftyPercentCopyKey
        static let screenshotOverlaysDeviceDetails = ADBuddySharedPreferences.screenshotOverlaysDeviceDetailsKey
        static let automaticallyCopyMedia = "automaticallyCopyMedia"
        static let legacyAutomaticallyCopyScreenshots = "automaticallyCopyScreenshots"
        static let revealMediaInFinder = "revealMediaInFinder"
        static let showInMenuBar = "showInMenuBar"
        static let showSuccessFeedbackBanners = "showSuccessFeedbackBanners"
        static let screenRecordingBitRateMegabitsPerSecond = ADBuddySharedPreferences.screenRecordingBitRateMegabitsPerSecondKey
        static let screenRecordingResolutionPercentage = ADBuddySharedPreferences.screenRecordingResolutionPercentageKey
        static let screenRecordingShowsTaps = ADBuddySharedPreferences.screenRecordingShowsTapsKey
        static let screenRecordingAddsFrame = ADBuddySharedPreferences.screenRecordingAddsFrameKey
        static let logcatColors = "logcatColors"
        static let logcatTablePreferences = "logcatTablePreferences"
        static let deepLinkLauncherEnabled = "deepLinkLauncherEnabled"
    }

    private let userDefaults: UserDefaults
    private let defaultScreenshotDirectory: URL

    var screenshotDirectory: URL {
        didSet {
            userDefaults.set(screenshotDirectory.path, forKey: Key.screenshotDirectoryPath)
        }
    }

    var automaticallyCopyMedia: Bool {
        didSet {
            userDefaults.set(automaticallyCopyMedia, forKey: Key.automaticallyCopyMedia)
        }
    }

    var screenshotAddsFrame: Bool {
        didSet {
            userDefaults.set(screenshotAddsFrame, forKey: Key.screenshotAddsFrame)
        }
    }

    var screenshotAlsoSavesOriginal: Bool {
        didSet {
            userDefaults.set(screenshotAlsoSavesOriginal, forKey: Key.screenshotAlsoSavesOriginal)
        }
    }

    var screenshotAlsoSavesFiftyPercentCopy: Bool {
        didSet {
            userDefaults.set(
                screenshotAlsoSavesFiftyPercentCopy,
                forKey: Key.screenshotAlsoSavesFiftyPercentCopy
            )
        }
    }

    var screenshotOverlaysDeviceDetails: Bool {
        didSet {
            userDefaults.set(screenshotOverlaysDeviceDetails, forKey: Key.screenshotOverlaysDeviceDetails)
        }
    }

    var revealMediaInFinder: Bool {
        didSet {
            userDefaults.set(revealMediaInFinder, forKey: Key.revealMediaInFinder)
        }
    }

    var showInMenuBar: Bool {
        didSet {
            userDefaults.set(showInMenuBar, forKey: Key.showInMenuBar)
        }
    }

    var showSuccessFeedbackBanners: Bool {
        didSet {
            userDefaults.set(showSuccessFeedbackBanners, forKey: Key.showSuccessFeedbackBanners)
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

    var screenRecordingAddsFrame: Bool {
        didSet {
            userDefaults.set(screenRecordingAddsFrame, forKey: Key.screenRecordingAddsFrame)
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

    private(set) var logcatTablePreferences: LogcatTablePreferences {
        didSet {
            guard let encodedPreferences = try? JSONEncoder().encode(logcatTablePreferences) else {
                return
            }
            userDefaults.set(encodedPreferences, forKey: Key.logcatTablePreferences)
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

        if let savedValue = userDefaults.object(forKey: Key.automaticallyCopyMedia) as? Bool {
            automaticallyCopyMedia = savedValue
        } else if let legacyValue = userDefaults.object(
            forKey: Key.legacyAutomaticallyCopyScreenshots
        ) as? Bool {
            automaticallyCopyMedia = legacyValue
            userDefaults.set(legacyValue, forKey: Key.automaticallyCopyMedia)
        } else {
            automaticallyCopyMedia = true
        }
        screenshotAddsFrame = userDefaults.object(forKey: Key.screenshotAddsFrame) as? Bool ?? false
        screenshotAlsoSavesOriginal = userDefaults.object(forKey: Key.screenshotAlsoSavesOriginal) as? Bool ?? false
        screenshotAlsoSavesFiftyPercentCopy = userDefaults.object(
            forKey: Key.screenshotAlsoSavesFiftyPercentCopy
        ) as? Bool ?? false
        screenshotOverlaysDeviceDetails = userDefaults.object(forKey: Key.screenshotOverlaysDeviceDetails) as? Bool ?? false
        revealMediaInFinder = userDefaults.object(forKey: Key.revealMediaInFinder) as? Bool ?? false
        showInMenuBar = userDefaults.object(forKey: Key.showInMenuBar) as? Bool ?? true
        showSuccessFeedbackBanners = userDefaults.object(forKey: Key.showSuccessFeedbackBanners) as? Bool ?? true
        screenRecordingBitRateMegabitsPerSecond = userDefaults.object(forKey: Key.screenRecordingBitRateMegabitsPerSecond) as? Int
            ?? ScreenRecordingOptions.default.bitRateMegabitsPerSecond
        screenRecordingResolutionPercentage = userDefaults.object(forKey: Key.screenRecordingResolutionPercentage) as? Int
            ?? ScreenRecordingOptions.default.resolution.rawValue
        screenRecordingShowsTaps = userDefaults.object(forKey: Key.screenRecordingShowsTaps) as? Bool
            ?? ScreenRecordingOptions.default.showsTaps
        screenRecordingAddsFrame = userDefaults.object(forKey: Key.screenRecordingAddsFrame) as? Bool ?? false
        isDeepLinkLauncherEnabled = userDefaults.object(forKey: Key.deepLinkLauncherEnabled) as? Bool ?? false
        logcatColors = Self.loadLogcatColors(from: userDefaults) ?? LogcatPriority.defaultColors
        logcatTablePreferences = Self.loadLogcatTablePreferences(from: userDefaults)
            ?? LogcatTablePreferences()
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

    func setLogcatMessageWrapping(_ wrapsMessages: Bool) {
        updateLogcatTablePreferences { preferences in
            preferences.wrapsMessages = wrapsMessages
        }
    }

    func setLogcatColumnVisibility(_ isVisible: Bool, for column: LogcatTableColumn) {
        updateLogcatTablePreferences { preferences in
            preferences.setColumnVisibility(isVisible, for: column)
        }
    }

    func setLogcatColumnOrder(_ columns: [LogcatTableColumn]) {
        updateLogcatTablePreferences { preferences in
            preferences.setColumnOrder(columns)
        }
    }

    func setLogcatColumnWidths(_ widths: [LogcatTableColumn: CGFloat]) {
        updateLogcatTablePreferences { preferences in
            preferences.setColumnWidths(widths)
        }
    }

    private static func loadLogcatColors(from userDefaults: UserDefaults) -> [LogcatPriority: LogcatColorComponents]? {
        guard let data = userDefaults.data(forKey: Key.logcatColors),
              let colors = try? JSONDecoder().decode([LogcatPriority: LogcatColorComponents].self, from: data),
              Set(colors.keys) == Set(LogcatPriority.allCases) else {
            return nil
        }
        return colors
    }

    private func updateLogcatTablePreferences(
        _ update: (inout LogcatTablePreferences) -> Void
    ) {
        var updatedPreferences = logcatTablePreferences
        update(&updatedPreferences)
        updatedPreferences = updatedPreferences.normalized()
        guard updatedPreferences != logcatTablePreferences else {
            return
        }
        logcatTablePreferences = updatedPreferences
    }

    private static func loadLogcatTablePreferences(
        from userDefaults: UserDefaults
    ) -> LogcatTablePreferences? {
        guard let data = userDefaults.data(forKey: Key.logcatTablePreferences),
              let preferences = try? JSONDecoder().decode(LogcatTablePreferences.self, from: data) else {
            return nil
        }
        return preferences.normalized()
    }
}
