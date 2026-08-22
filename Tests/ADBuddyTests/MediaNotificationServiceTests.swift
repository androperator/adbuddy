import Foundation
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
