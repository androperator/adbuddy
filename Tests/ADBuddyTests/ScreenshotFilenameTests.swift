import Foundation
import XCTest
@testable import ADBuddy

final class ScreenshotFilenameTests: XCTestCase {
    func testSanitizesDeviceNameAndAddsCollisionSuffix() {
        let directory = URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true)
        let expectedBaseName = "Pixel-9-Pro_1970-01-01_000000_000"
        let fileURL = ScreenshotFilename.uniqueURL(
            in: directory,
            deviceName: "Pixel 9 / Pro",
            date: Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            fileExists: { url in
                url.lastPathComponent == "\(expectedBaseName).png"
                    || url.lastPathComponent == "\(expectedBaseName)-2.png"
            }
        )

        XCTAssertEqual(fileURL.lastPathComponent, "\(expectedBaseName)-3.png")
    }

    func testFallsBackToAndroidDeviceForEmptySanitizedName() {
        XCTAssertEqual(ScreenshotFilename.sanitizedDeviceName("///"), "Android-Device")
    }
}
