import Foundation
@preconcurrency import UserNotifications
import XCTest
@testable import ADBuddy

final class MediaNotificationServiceTests: XCTestCase {
    func testBuildsScreenshotNotificationWithRevealActionAndClipboardDetail() {
        let screenshotURL = URL(fileURLWithPath: "/tmp/Pixel-10-Pro_2026-08-22_130934_049.png")
        let request = MediaNotificationService.makeNotificationRequest(
            for: screenshotURL,
            kind: .screenshot(copiedToClipboard: true),
            identifier: "screenshot-test"
        )

        XCTAssertEqual(request.identifier, "screenshot-test")
        XCTAssertEqual(request.content.title, "Screenshot Saved")
        XCTAssertEqual(
            request.content.body,
            "Pixel-10-Pro_2026-08-22_130934_049.png was copied to the clipboard."
        )
        XCTAssertEqual(request.content.categoryIdentifier, MediaNotificationIdentifier.category)
        XCTAssertEqual(
            request.content.userInfo[MediaNotificationIdentifier.savedMediaPath] as? String,
            screenshotURL.path
        )

        let category = MediaNotificationService.makeNotificationCategory()
        XCTAssertEqual(category.identifier, MediaNotificationIdentifier.category)
        XCTAssertEqual(category.actions.map(\.identifier), [MediaNotificationIdentifier.revealInFinderAction])
        XCTAssertEqual(category.actions.map(\.title), ["Reveal in Finder"])
    }

    func testAttachesSavedScreenshotToItsNotification() throws {
        let screenshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("adbuddy-notification-")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try FileManager.default.createDirectory(
            at: screenshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: screenshotURL.deletingLastPathComponent())
        }
        guard let screenshotData = Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Jv7wAAAAASUVORK5CYII="
        ) else {
            return XCTFail("Could not create a PNG test fixture")
        }
        try screenshotData.write(to: screenshotURL)

        let request = MediaNotificationService.makeNotificationRequest(
            for: screenshotURL,
            kind: .screenshot(copiedToClipboard: true)
        )

        XCTAssertEqual(request.content.attachments.count, 1)
        XCTAssertEqual(request.content.attachments.first?.url, screenshotURL)
    }

    func testBuildsRecordingNotificationWithRevealAction() {
        let recordingURL = URL(fileURLWithPath: "/tmp/Pixel-10-Pro_2026-08-22_134419_174.mp4")
        let request = MediaNotificationService.makeNotificationRequest(
            for: recordingURL,
            kind: .recording,
            identifier: "recording-test"
        )

        XCTAssertEqual(request.identifier, "recording-test")
        XCTAssertEqual(request.content.title, "Recording Saved")
        XCTAssertEqual(request.content.body, recordingURL.lastPathComponent)
        XCTAssertEqual(request.content.categoryIdentifier, MediaNotificationIdentifier.category)
        XCTAssertEqual(
            request.content.userInfo[MediaNotificationIdentifier.savedMediaPath] as? String,
            recordingURL.path
        )
    }

    func testUsesTheFirstVideoFrameForRecordingNotificationThumbnail() {
        let options = MediaNotificationService.notificationAttachmentOptions(for: .recording)

        XCTAssertEqual(options?[UNNotificationAttachmentOptionsThumbnailTimeKey] as? Int, 0)
        XCTAssertNil(
            MediaNotificationService.notificationAttachmentOptions(
                for: .screenshot(copiedToClipboard: false)
            )
        )
    }

    func testBuildsScreenshotNotificationWithoutClipboardDetailWhenCopyIsDisabled() {
        let screenshotURL = URL(fileURLWithPath: "/tmp/Pixel-10-Pro_2026-08-22_130934_049.png")
        let request = MediaNotificationService.makeNotificationRequest(
            for: screenshotURL,
            kind: .screenshot(copiedToClipboard: false),
            identifier: "screenshot-test"
        )

        XCTAssertEqual(request.content.body, screenshotURL.lastPathComponent)
    }
}
