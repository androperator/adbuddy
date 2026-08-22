import Foundation
import XCTest
@testable import ADBuddyCore

final class ADBuddySharedPreferencesTests: XCTestCase {
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
