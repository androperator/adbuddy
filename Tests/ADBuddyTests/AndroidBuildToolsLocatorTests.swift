import XCTest
@testable import ADBuddyCore

final class AndroidBuildToolsLocatorTests: XCTestCase {
    func testPrefersNewestExecutableAAPT2() {
        let locator = AndroidBuildToolsLocator(
            directoryContents: { path in
                XCTAssertEqual(path, "/SDK/build-tools")
                return ["34.0.0", "36.0.0", "35.0.0"]
            },
            isExecutable: { path in
                path == "/SDK/build-tools/36.0.0/aapt2"
            }
        )
        let sdk = AndroidSDK(
            rootPath: "/SDK",
            adbPath: "/SDK/platform-tools/adb",
            source: .androidHome
        )

        XCTAssertEqual(locator.aapt2Path(for: sdk), "/SDK/build-tools/36.0.0/aapt2")
    }

    func testReturnsNilWhenAAPT2IsUnavailable() {
        let locator = AndroidBuildToolsLocator(
            directoryContents: { _ in ["36.0.0"] },
            isExecutable: { _ in false }
        )
        let sdk = AndroidSDK(
            rootPath: "/SDK",
            adbPath: "/SDK/platform-tools/adb",
            source: .androidHome
        )

        XCTAssertNil(locator.aapt2Path(for: sdk))
    }
}
