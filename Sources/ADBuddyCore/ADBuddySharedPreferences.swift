import Foundation

public enum ADBuddySharedPreferences {
    public static let suiteName = "com.clawperator.adbuddy"
    public static let screenshotDirectoryPathKey = "screenshotDirectoryPath"
    public static let screenshotAddsFrameKey = "screenshotAddsFrame"
    public static let screenshotAlsoSavesOriginalKey = "screenshotAlsoSavesOriginal"
    public static let screenshotAlsoSavesFiftyPercentCopyKey = "screenshotAlsoSavesFiftyPercentCopy"
    public static let screenshotOverlaysDeviceDetailsKey = "screenshotOverlaysDeviceDetails"
    public static let screenRecordingBitRateMegabitsPerSecondKey = "screenRecordingBitRateMegabitsPerSecond"
    public static let screenRecordingResolutionPercentageKey = "screenRecordingResolutionPercentage"
    public static let screenRecordingShowsTapsKey = "screenRecordingShowsTaps"
    public static let screenRecordingAddsFrameKey = "screenRecordingAddsFrame"
    public static let showInDockKey = "showInDock"

    public static func userDefaults(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> UserDefaults {
        // ADBuddy itself owns this preferences domain, so it must use the
        // application's standard defaults rather than opening its own bundle
        // identifier as a suite. The bundled MCP executable can still open
        // that domain when it runs without ADBuddy's bundle identity.
        if bundleIdentifier == suiteName {
            return .standard
        }

        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not open ADBuddy shared preferences.")
        }
        return userDefaults
    }

    public static func mediaDestination(
        userDefaults: UserDefaults = userDefaults(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        guard let savedPath = userDefaults.string(forKey: screenshotDirectoryPathKey), !savedPath.isEmpty else {
            return homeDirectory.appendingPathComponent("Screenshots", isDirectory: true)
        }
        return URL(fileURLWithPath: savedPath, isDirectory: true)
    }

    public static func screenRecordingOptions(
        userDefaults: UserDefaults = userDefaults()
    ) -> ScreenRecordingOptions {
        let bitRate = userDefaults.object(forKey: screenRecordingBitRateMegabitsPerSecondKey) as? Int
            ?? ScreenRecordingOptions.default.bitRateMegabitsPerSecond
        let resolutionPercentage = userDefaults.object(forKey: screenRecordingResolutionPercentageKey) as? Int
            ?? ScreenRecordingOptions.default.resolution.rawValue
        let showsTaps = userDefaults.object(forKey: screenRecordingShowsTapsKey) as? Bool
            ?? ScreenRecordingOptions.default.showsTaps

        return ScreenRecordingOptions(
            bitRateMegabitsPerSecond: bitRate,
            resolution: ScreenRecordingResolution(rawValue: resolutionPercentage) ?? .native,
            showsTaps: showsTaps
        )
    }

    public static func screenshotFramingOptions(
        userDefaults: UserDefaults = userDefaults()
    ) -> ScreenshotFramingOptions {
        ScreenshotFramingOptions(
            addsFrame: userDefaults.object(forKey: screenshotAddsFrameKey) as? Bool ?? false,
            alsoSavesOriginal: userDefaults.object(forKey: screenshotAlsoSavesOriginalKey) as? Bool ?? false,
            overlaysDeviceDetails: userDefaults.object(forKey: screenshotOverlaysDeviceDetailsKey) as? Bool ?? false
        )
    }

    public static func screenshotOutputOptions(
        userDefaults: UserDefaults = userDefaults()
    ) -> ScreenshotOutputOptions {
        ScreenshotOutputOptions(
            alsoSavesFiftyPercentCopy: userDefaults.object(
                forKey: screenshotAlsoSavesFiftyPercentCopyKey
            ) as? Bool ?? false
        )
    }

    public static func screenRecordingFramingOptions(
        userDefaults: UserDefaults = userDefaults()
    ) -> ScreenRecordingFramingOptions {
        ScreenRecordingFramingOptions(
            addsFrame: userDefaults.object(forKey: screenRecordingAddsFrameKey) as? Bool ?? false,
            overlaysDeviceDetails: userDefaults.object(forKey: screenshotOverlaysDeviceDetailsKey) as? Bool ?? false
        )
    }

    public static func showsDockIcon(
        userDefaults: UserDefaults = userDefaults()
    ) -> Bool {
        userDefaults.object(forKey: showInDockKey) as? Bool ?? true
    }
}
