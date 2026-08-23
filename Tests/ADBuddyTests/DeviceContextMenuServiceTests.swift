import Foundation
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

@MainActor
final class DeviceContextMenuServiceTests: XCTestCase {
    func testCopiesDeviceIdentifierAsPlainText() {
        let pasteboard = TestDeviceIdentifierPasteboard()
        let service = DeviceIdentifierClipboardService(pasteboard: pasteboard)

        service.copyDeviceIdentifier("emulator-5554")

        XCTAssertEqual(pasteboard.string, "emulator-5554")
    }

    func testUsesAndroidAVDHomeBeforeOtherAVDDirectories() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let androidAVDHome = temporaryDirectory.appendingPathComponent("configured-avds", isDirectory: true)
        let userHome = temporaryDirectory.appendingPathComponent("android-user", isDirectory: true)
        let defaultHome = temporaryDirectory.appendingPathComponent("home", isDirectory: true)
        let configuredVirtualDevice = try createVirtualDevice(
            named: "Pixel_9",
            in: androidAVDHome
        )
        _ = try createVirtualDevice(named: "Pixel_9", in: userHome.appendingPathComponent("avd", isDirectory: true))
        _ = try createVirtualDevice(
            named: "Pixel_9",
            in: defaultHome
                .appendingPathComponent(".android", isDirectory: true)
                .appendingPathComponent("avd", isDirectory: true)
        )
        let resolver = AndroidVirtualDeviceDirectoryResolver(
            environment: [
                "ANDROID_AVD_HOME": androidAVDHome.path,
                "ANDROID_USER_HOME": userHome.path,
            ],
            homeDirectory: defaultHome
        )

        XCTAssertEqual(resolver.directoryURL(for: "Pixel_9"), configuredVirtualDevice)
    }

    func testUsesConfiguredUserAndDefaultAVDDirectoriesWhenNeeded() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let userHome = temporaryDirectory.appendingPathComponent("android-user", isDirectory: true)
        let defaultHome = temporaryDirectory.appendingPathComponent("home", isDirectory: true)
        let userVirtualDevice = try createVirtualDevice(
            named: "Pixel_9",
            in: userHome.appendingPathComponent("avd", isDirectory: true)
        )
        let defaultVirtualDevice = try createVirtualDevice(
            named: "Pixel_9_Pro",
            in: defaultHome
                .appendingPathComponent(".android", isDirectory: true)
                .appendingPathComponent("avd", isDirectory: true)
        )
        let resolver = AndroidVirtualDeviceDirectoryResolver(
            environment: ["ANDROID_USER_HOME": userHome.path],
            homeDirectory: defaultHome
        )

        XCTAssertEqual(resolver.directoryURL(for: "Pixel_9"), userVirtualDevice)
        XCTAssertEqual(resolver.directoryURL(for: "Pixel_9_Pro"), defaultVirtualDevice)
    }

    func testRejectsVirtualDeviceNamesThatCouldEscapeTheAVDDirectory() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let resolver = AndroidVirtualDeviceDirectoryResolver(homeDirectory: temporaryDirectory)

        XCTAssertNil(resolver.directoryURL(for: "../Pixel_9"))
        XCTAssertNil(resolver.directoryURL(for: "Pixel_9/child"))
        XCTAssertNil(resolver.directoryURL(for: "Pixel_9\\child"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ADBuddyDeviceContextMenuTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func createVirtualDevice(named name: String, in avdRoot: URL) throws -> URL {
        let virtualDeviceDirectory = avdRoot.appendingPathComponent("\(name).avd", isDirectory: true)
        try FileManager.default.createDirectory(at: virtualDeviceDirectory, withIntermediateDirectories: true)
        return virtualDeviceDirectory
    }
}

@MainActor
private final class TestDeviceIdentifierPasteboard: DeviceIdentifierPasteboardWriting {
    private(set) var string: String?

    func writeString(_ string: String) -> Bool {
        self.string = string
        return true
    }
}
