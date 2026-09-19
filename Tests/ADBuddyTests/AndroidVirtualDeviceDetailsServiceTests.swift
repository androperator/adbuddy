import Foundation
import XCTest
@testable import ADBuddyCore

final class AndroidVirtualDeviceDetailsServiceTests: XCTestCase {
    func testReadsAndroidVersionAndAPILevelFromTheConfiguredSystemImage() throws {
        try assertReadsDetails(separator: "=")
    }

    func testReadsAndroidStudioConfigurationWithSpacesAroundEquals() throws {
        try assertReadsDetails(separator: " = ")
    }

    private func assertReadsDetails(separator: String) throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let homeDirectory = temporaryDirectory.appendingPathComponent("home", isDirectory: true)
        let sdkDirectory = temporaryDirectory.appendingPathComponent("sdk", isDirectory: true)
        let virtualDeviceDirectory = homeDirectory
            .appendingPathComponent(".android", isDirectory: true)
            .appendingPathComponent("avd", isDirectory: true)
            .appendingPathComponent("Pixel_9_Storage.avd", isDirectory: true)
        let systemImageDirectory = sdkDirectory
            .appendingPathComponent("system-images", isDirectory: true)
            .appendingPathComponent("android-36", isDirectory: true)
            .appendingPathComponent("google_apis", isDirectory: true)
            .appendingPathComponent("arm64-v8a", isDirectory: true)
        try FileManager.default.createDirectory(at: virtualDeviceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: systemImageDirectory, withIntermediateDirectories: true)
        try "path\(separator)\(virtualDeviceDirectory.path)\n".write(
            to: virtualDeviceDirectory
                .deletingLastPathComponent()
                .appendingPathComponent("Pixel_9.ini"),
            atomically: true,
            encoding: .utf8
        )
        try """
        image.sysdir.1\(separator)system-images/android-36/google_apis/arm64-v8a/
        hw.lcd.width\(separator)1080
        hw.lcd.height\(separator)2400
        hw.lcd.density\(separator)420
        """.write(
            to: virtualDeviceDirectory.appendingPathComponent("config.ini"),
            atomically: true,
            encoding: .utf8
        )
        try "AndroidVersion.ApiLevel\(separator)36\n".write(
            to: systemImageDirectory.appendingPathComponent("source.properties"),
            atomically: true,
            encoding: .utf8
        )
        let resolver = AndroidVirtualDeviceDirectoryResolver(homeDirectory: homeDirectory)
        let service = AndroidVirtualDeviceDetailsService(
            sdkRootPath: sdkDirectory.path,
            directoryResolver: resolver
        )

        let details = service.details(for: AndroidVirtualDevice(name: "Pixel_9"))

        XCTAssertEqual(
            details,
            AndroidDeviceDetails(
                androidVersion: "16",
                apiLevel: "36",
                screen: AndroidDeviceScreen(
                    physicalPixelSize: try XCTUnwrap(AndroidDisplaySize(width: 1080, height: 2400)),
                    logicalDensityDPI: 420
                )
            )
        )
        XCTAssertEqual(details?.displayText, "Android 16 / API 36")
        XCTAssertEqual(details?.screen?.displayText, "1080 × 2400 px · 411 × 914 dp")
    }

    func testReturnsNoDetailsWhenTheAVDHasNoSystemImageMetadata() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let homeDirectory = temporaryDirectory.appendingPathComponent("home", isDirectory: true)
        let virtualDeviceDirectory = homeDirectory
            .appendingPathComponent(".android", isDirectory: true)
            .appendingPathComponent("avd", isDirectory: true)
            .appendingPathComponent("Pixel_9.avd", isDirectory: true)
        try FileManager.default.createDirectory(at: virtualDeviceDirectory, withIntermediateDirectories: true)
        let service = AndroidVirtualDeviceDetailsService(
            sdkRootPath: temporaryDirectory.appendingPathComponent("sdk", isDirectory: true).path,
            directoryResolver: AndroidVirtualDeviceDirectoryResolver(homeDirectory: homeDirectory)
        )

        XCTAssertNil(service.details(for: AndroidVirtualDevice(name: "Pixel_9")))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ADBuddyVirtualDeviceDetailsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
