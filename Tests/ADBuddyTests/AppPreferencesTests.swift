import Foundation
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testPersistsConfiguredScreenshotDirectory() {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated user defaults")
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let fallbackDirectory = URL(fileURLWithPath: "/tmp/default-screenshots", isDirectory: true)
        let configuredDirectory = URL(fileURLWithPath: "/tmp/configured-screenshots", isDirectory: true)
        let preferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: fallbackDirectory
        )

        XCTAssertEqual(preferences.screenshotDirectory, fallbackDirectory)

        preferences.screenshotDirectory = configuredDirectory

        let reloadedPreferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: fallbackDirectory
        )
        XCTAssertEqual(reloadedPreferences.screenshotDirectory, configuredDirectory)
    }

    func testAutomaticallyCopyScreenshotsDefaultsToTrueAndPersistsChanges() {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated user defaults")
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let fallbackDirectory = URL(fileURLWithPath: "/tmp/default-screenshots", isDirectory: true)
        let preferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: fallbackDirectory
        )

        XCTAssertTrue(preferences.automaticallyCopyScreenshots)

        preferences.automaticallyCopyScreenshots = false

        let reloadedPreferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: fallbackDirectory
        )
        XCTAssertFalse(reloadedPreferences.automaticallyCopyScreenshots)
    }

    func testScreenRecordingOptionsUseStableDefaultsAndPersistChanges() {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated user defaults")
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: URL(fileURLWithPath: "/tmp/default-screenshots", isDirectory: true)
        )

        XCTAssertEqual(preferences.screenRecordingBitRateMegabitsPerSecond, 8)
        XCTAssertEqual(preferences.screenRecordingResolutionPercentage, 100)
        XCTAssertFalse(preferences.screenRecordingShowsTaps)

        preferences.screenRecordingBitRateMegabitsPerSecond = 12
        preferences.screenRecordingResolutionPercentage = 50
        preferences.screenRecordingShowsTaps = true

        let reloadedPreferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: URL(fileURLWithPath: "/tmp/default-screenshots", isDirectory: true)
        )
        XCTAssertEqual(reloadedPreferences.screenRecordingBitRateMegabitsPerSecond, 12)
        XCTAssertEqual(reloadedPreferences.screenRecordingResolutionPercentage, 50)
        XCTAssertTrue(reloadedPreferences.screenRecordingShowsTaps)
    }

    func testLogcatColorsUseDefaultsPersistChangesAndReset() {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated user defaults")
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: URL(fileURLWithPath: "/tmp/default-screenshots", isDirectory: true)
        )
        let customDebug = LogcatColorComponents(red: 0.1, green: 0.2, blue: 0.3)

        XCTAssertEqual(preferences.logcatColors, LogcatPriority.defaultColors)
        XCTAssertEqual(
            preferences.logcatColors[.verbose],
            LogcatColorComponents(red: 0.48, green: 0.49, blue: 0.51)
        )
        XCTAssertEqual(
            preferences.logcatColors[.assert],
            LogcatColorComponents(red: 0.55, green: 0.10, blue: 0.12)
        )
        preferences.setLogcatColor(customDebug, for: .debug)

        let reloadedPreferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: URL(fileURLWithPath: "/tmp/default-screenshots", isDirectory: true)
        )
        XCTAssertEqual(reloadedPreferences.logcatColors[.debug], customDebug)

        reloadedPreferences.resetLogcatColors()
        XCTAssertEqual(reloadedPreferences.logcatColors, LogcatPriority.defaultColors)
    }

    func testLogcatColorsFallBackToDefaultsWhenTheStoredDataIsInvalid() {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated user defaults")
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        userDefaults.set(Data("not valid color data".utf8), forKey: "logcatColors")

        let preferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: URL(fileURLWithPath: "/tmp/default-screenshots", isDirectory: true)
        )

        XCTAssertEqual(preferences.logcatColors, LogcatPriority.defaultColors)
    }
}
