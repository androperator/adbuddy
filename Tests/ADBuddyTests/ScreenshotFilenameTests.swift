import Foundation
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

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

    func testGeneratesACollisionFreeOriginalAndFramedPair() {
        let directory = URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true)
        let expectedBaseName = "Pixel-9-Pro_1970-01-01_000000_000"
        let fileURLs = ScreenshotFilename.uniqueOriginalAndFramedURLs(
            in: directory,
            deviceName: "Pixel 9 Pro",
            date: Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            fileExists: { url in
                url.lastPathComponent == "\(expectedBaseName).png"
                    || url.lastPathComponent == "\(expectedBaseName)_framed.png"
            }
        )

        XCTAssertEqual(fileURLs.original.lastPathComponent, "\(expectedBaseName)-2.png")
        XCTAssertEqual(fileURLs.framed.lastPathComponent, "\(expectedBaseName)-2_framed.png")
    }

    func testGeneratesCollisionFreeOriginalAndFramedRecordingNames() {
        let directory = URL(fileURLWithPath: "/tmp/recordings", isDirectory: true)
        let expectedBaseName = "Pixel-9-Pro_1970-01-01_000000_000"
        let fileURLs = ScreenshotFilename.uniqueOriginalAndFramedURLs(
            in: directory,
            deviceName: "Pixel 9 Pro",
            date: Date(timeIntervalSince1970: 0),
            fileExtension: "mp4",
            timeZone: TimeZone(secondsFromGMT: 0)!,
            fileExists: { url in
                url.lastPathComponent == "\(expectedBaseName)_framed.mp4"
            }
        )

        XCTAssertEqual(fileURLs.original.lastPathComponent, "\(expectedBaseName)-2.mp4")
        XCTAssertEqual(fileURLs.framed.lastPathComponent, "\(expectedBaseName)-2_framed.mp4")
    }
}
