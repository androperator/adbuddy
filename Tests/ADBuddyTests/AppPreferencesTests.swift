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

    func testAutomaticallyCopyMediaDefaultsToTrueAndPersistsChanges() {
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

        XCTAssertTrue(preferences.automaticallyCopyMedia)

        preferences.automaticallyCopyMedia = false

        let reloadedPreferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: fallbackDirectory
        )
        XCTAssertFalse(reloadedPreferences.automaticallyCopyMedia)
    }

    func testAutomaticallyCopyMediaMigratesTheExistingScreenshotPreference() {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated user defaults")
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        userDefaults.set(false, forKey: "automaticallyCopyScreenshots")

        let preferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: URL(fileURLWithPath: "/tmp/default-screenshots", isDirectory: true)
        )

        XCTAssertFalse(preferences.automaticallyCopyMedia)
        XCTAssertEqual(userDefaults.object(forKey: "automaticallyCopyMedia") as? Bool, false)
    }

    func testRevealMediaInFinderDefaultsToFalseAndPersistsChanges() {
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

        XCTAssertFalse(preferences.revealMediaInFinder)

        preferences.revealMediaInFinder = true

        let reloadedPreferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: fallbackDirectory
        )
        XCTAssertTrue(reloadedPreferences.revealMediaInFinder)
    }

    func testShowInMenuBarDefaultsToTrueAndPersistsChanges() {
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

        XCTAssertTrue(preferences.showInMenuBar)

        preferences.showInMenuBar = false

        let reloadedPreferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: fallbackDirectory
        )

        XCTAssertFalse(reloadedPreferences.showInMenuBar)
    }

    func testShowSuccessFeedbackBannersDefaultsToFalseAndPersistsChanges() {
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

        XCTAssertFalse(preferences.showSuccessFeedbackBanners)

        preferences.showSuccessFeedbackBanners = true

        let reloadedPreferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: fallbackDirectory
        )

        XCTAssertTrue(reloadedPreferences.showSuccessFeedbackBanners)
    }

    func testScreenshotFramingPreferencesDefaultToFalseAndPersistChanges() {
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

        XCTAssertFalse(preferences.screenshotAddsFrame)
        XCTAssertFalse(preferences.screenshotAlsoSavesOriginal)
        XCTAssertFalse(preferences.screenshotOverlaysDeviceDetails)

        preferences.screenshotAddsFrame = true
        preferences.screenshotAlsoSavesOriginal = true
        preferences.screenshotOverlaysDeviceDetails = true

        let reloadedPreferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: URL(fileURLWithPath: "/tmp/default-screenshots", isDirectory: true)
        )
        XCTAssertTrue(reloadedPreferences.screenshotAddsFrame)
        XCTAssertTrue(reloadedPreferences.screenshotAlsoSavesOriginal)
        XCTAssertTrue(reloadedPreferences.screenshotOverlaysDeviceDetails)
    }

    func testScreenshotFiftyPercentCopyDefaultsToDisabledAndPersistsChanges() {
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
        XCTAssertFalse(preferences.screenshotAlsoSavesFiftyPercentCopy)

        preferences.screenshotAlsoSavesFiftyPercentCopy = true

        let reloadedPreferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: URL(fileURLWithPath: "/tmp/default-screenshots", isDirectory: true)
        )
        XCTAssertTrue(reloadedPreferences.screenshotAlsoSavesFiftyPercentCopy)
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

    func testScreenRecordingFramingDefaultsToDisabledAndPersistsChanges() {
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
        XCTAssertFalse(preferences.screenRecordingAddsFrame)

        preferences.screenRecordingAddsFrame = true

        let reloadedPreferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: URL(fileURLWithPath: "/tmp/default-screenshots", isDirectory: true)
        )
        XCTAssertTrue(reloadedPreferences.screenRecordingAddsFrame)
    }

    func testDeepLinkLauncherIsDisabledByDefaultAndPersistsChanges() {
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

        XCTAssertFalse(preferences.isDeepLinkLauncherEnabled)

        preferences.isDeepLinkLauncherEnabled = true

        let reloadedPreferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: URL(fileURLWithPath: "/tmp/default-screenshots", isDirectory: true)
        )
        XCTAssertTrue(reloadedPreferences.isDeepLinkLauncherEnabled)
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

    func testLogcatTablePreferencesPersistAcrossAppSessions() {
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
        let expectedOrder: [LogcatTableColumn] = [
            .message,
            .tag,
            .time,
            .level,
            .applicationID,
            .processID,
            .threadID,
        ]

        XCTAssertEqual(preferences.logcatTablePreferences, LogcatTablePreferences())

        preferences.setLogcatMessageWrapping(true)
        preferences.setLogcatColumnVisibility(true, for: .applicationID)
        preferences.setLogcatColumnVisibility(true, for: .processID)
        preferences.setLogcatColumnVisibility(false, for: .tag)
        preferences.setLogcatColumnOrder(expectedOrder)
        preferences.setLogcatColumnWidths([
            .message: 640,
            .tag: 180,
        ])

        let reloadedPreferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: URL(fileURLWithPath: "/tmp/default-screenshots", isDirectory: true)
        )

        XCTAssertTrue(reloadedPreferences.logcatTablePreferences.wrapsMessages)
        XCTAssertTrue(reloadedPreferences.logcatTablePreferences.showsApplicationID)
        XCTAssertTrue(reloadedPreferences.logcatTablePreferences.showsProcessID)
        XCTAssertFalse(reloadedPreferences.logcatTablePreferences.showsTag)
        XCTAssertEqual(reloadedPreferences.logcatTablePreferences.orderedColumns, expectedOrder)
        XCTAssertEqual(reloadedPreferences.logcatTablePreferences.width(for: .message), 640)
        XCTAssertEqual(reloadedPreferences.logcatTablePreferences.width(for: .tag), 180)
    }
}
