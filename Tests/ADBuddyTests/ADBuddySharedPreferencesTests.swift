import Foundation
import XCTest
@testable import ADBuddyCore

final class ADBuddySharedPreferencesTests: XCTestCase {
    func testUsesStandardDefaultsWhenRunningInsideADBuddy() {
        let userDefaults = ADBuddySharedPreferences.userDefaults(
            bundleIdentifier: ADBuddySharedPreferences.suiteName
        )

        XCTAssertTrue(userDefaults === UserDefaults.standard)
    }

    func testMediaDestinationUsesSavedSharedPath() {
        let userDefaults = makeUserDefaults()
        userDefaults.set("/tmp/adbuddy-media", forKey: ADBuddySharedPreferences.screenshotDirectoryPathKey)

        XCTAssertEqual(
            ADBuddySharedPreferences.mediaDestination(
                userDefaults: userDefaults,
                homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)
            ).path,
            "/tmp/adbuddy-media"
        )
    }

    func testScreenRecordingOptionsUseSharedSavedValues() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(12, forKey: ADBuddySharedPreferences.screenRecordingBitRateMegabitsPerSecondKey)
        userDefaults.set(50, forKey: ADBuddySharedPreferences.screenRecordingResolutionPercentageKey)
        userDefaults.set(true, forKey: ADBuddySharedPreferences.screenRecordingShowsTapsKey)

        XCTAssertEqual(
            ADBuddySharedPreferences.screenRecordingOptions(userDefaults: userDefaults),
            ScreenRecordingOptions(
                bitRateMegabitsPerSecond: 12,
                resolution: .fiftyPercent,
                showsTaps: true
            )
        )
    }

    func testScreenshotFramingOptionsUseSharedSavedValues() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(true, forKey: ADBuddySharedPreferences.screenshotAddsFrameKey)
        userDefaults.set(true, forKey: ADBuddySharedPreferences.screenshotAlsoSavesOriginalKey)

        XCTAssertEqual(
            ADBuddySharedPreferences.screenshotFramingOptions(userDefaults: userDefaults),
            ScreenshotFramingOptions(addsFrame: true, alsoSavesOriginal: true)
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "ADBuddySharedPreferencesTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create test UserDefaults suite.")
        }
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return userDefaults
    }
}
