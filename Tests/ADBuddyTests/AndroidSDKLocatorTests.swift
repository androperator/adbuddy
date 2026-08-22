import Foundation
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

final class AndroidSDKLocatorTests: XCTestCase {
    func testAndroidHomeTakesPrecedenceOverOtherCandidates() {
        let homeSDK = "/SDK/from-home"
        let rootSDK = "/SDK/from-root"
        let standardSDK = "/Users/example/Library/Android/sdk"
        let executablePaths = [adbPath(for: homeSDK), adbPath(for: rootSDK), adbPath(for: standardSDK)]

        let locator = AndroidSDKLocator(
            environment: ["ANDROID_HOME": homeSDK, "ANDROID_SDK_ROOT": rootSDK],
            homeDirectoryPath: "/Users/example",
            pathExists: { _ in true },
            isExecutable: { executablePaths.contains($0) }
        )

        XCTAssertEqual(
            locator.resolve(),
            .found(AndroidSDK(rootPath: homeSDK, adbPath: adbPath(for: homeSDK), source: .androidHome))
        )
    }

    func testReportsMissingADBWhenSDKDirectoryExists() {
        let locator = AndroidSDKLocator(
            environment: ["ANDROID_HOME": "/SDK"],
            homeDirectoryPath: "/Users/example",
            pathExists: { $0 == "/SDK" },
            isExecutable: { _ in false }
        )

        XCTAssertEqual(locator.resolve(), .unavailable(.adbNotFound))
    }

    func testReportsMissingSDKWhenNoCandidateDirectoryExists() {
        let locator = AndroidSDKLocator(
            environment: [:],
            homeDirectoryPath: "/Users/example",
            pathExists: { _ in false },
            isExecutable: { _ in false }
        )

        XCTAssertEqual(locator.resolve(), .unavailable(.sdkNotFound))
    }

    private func adbPath(for rootPath: String) -> String {
        URL(fileURLWithPath: rootPath)
            .appendingPathComponent("platform-tools", isDirectory: true)
            .appendingPathComponent("adb")
            .path
    }
}
