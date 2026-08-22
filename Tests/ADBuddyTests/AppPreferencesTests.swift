import Foundation
import XCTest
@testable import ADBuddy

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
}
