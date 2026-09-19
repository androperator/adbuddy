import Foundation
@preconcurrency import UserNotifications
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

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
        XCTAssertNil(request.content.sound)
        XCTAssertFalse(
            MediaNotificationService.presentationOptions.contains(.sound)
        )

        let category = MediaNotificationService.makeNotificationCategory()
        XCTAssertEqual(category.identifier, MediaNotificationIdentifier.category)
        XCTAssertEqual(category.actions.map(\.identifier), [MediaNotificationIdentifier.revealInFinderAction])
        XCTAssertEqual(category.actions.map(\.title), ["Reveal in Finder"])
    }

    func testUsesDisposableCopyForScreenshotNotificationAttachment() throws {
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
        guard let attachmentURL = request.content.attachments.first?.url else {
            return XCTFail("Expected a notification attachment")
        }
        defer {
            try? FileManager.default.removeItem(at: attachmentURL)
        }

        XCTAssertNotEqual(attachmentURL, screenshotURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotURL.path))
        XCTAssertEqual(try Data(contentsOf: attachmentURL), screenshotData)
    }

    func testBuildsRecordingNotificationWithRevealAction() {
        let recordingURL = URL(fileURLWithPath: "/tmp/Pixel-10-Pro_2026-08-22_134419_174.mp4")
        let request = MediaNotificationService.makeNotificationRequest(
            for: recordingURL,
            kind: .recording(copiedToClipboard: true),
            identifier: "recording-test"
        )

        XCTAssertEqual(request.identifier, "recording-test")
        XCTAssertEqual(request.content.title, "Recording Saved")
        XCTAssertEqual(
            request.content.body,
            "Pixel-10-Pro_2026-08-22_134419_174.mp4 was copied to the clipboard."
        )
        XCTAssertEqual(request.content.categoryIdentifier, MediaNotificationIdentifier.category)
        XCTAssertEqual(
            request.content.userInfo[MediaNotificationIdentifier.savedMediaPath] as? String,
            recordingURL.path
        )
        XCTAssertNil(request.content.sound)
        XCTAssertFalse(
            MediaNotificationService.presentationOptions.contains(.sound)
        )
    }

    func testRecordingClipSummaryIsSilent() {
        let request = MediaNotificationService.makeNotificationRequest(
            for: URL(fileURLWithPath: "/tmp/clip_01.mp4"),
            kind: .recording(copiedToClipboard: true, clipCount: 3),
            relatedFileURLs: ["/tmp/clip_01.mp4", "/tmp/clip_02.mp4", "/tmp/clip_03.mp4"].map { URL(fileURLWithPath: $0) }
        )
        XCTAssertEqual(
            request.content.userInfo[MediaNotificationIdentifier.savedMediaPaths] as? [String],
            ["/tmp/clip_01.mp4", "/tmp/clip_02.mp4", "/tmp/clip_03.mp4"]
        )
        XCTAssertEqual(request.content.title, "Recording Clips Saved")
        XCTAssertEqual(request.content.body, "Saved 3 recording clips and copied them to the clipboard.")
        XCTAssertNil(request.content.sound)
        XCTAssertFalse(MediaNotificationService.presentationOptions.contains(.sound))
    }

    func testUsesTheFirstVideoFrameForRecordingNotificationThumbnail() {
        let options = MediaNotificationService.notificationAttachmentOptions(
            for: .recording(copiedToClipboard: false)
        )

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
