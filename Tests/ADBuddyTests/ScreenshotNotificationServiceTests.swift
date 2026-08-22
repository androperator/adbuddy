import Foundation
import XCTest
@testable import ADBuddy

final class ScreenshotNotificationServiceTests: XCTestCase {
    func testBuildsNotificationWithRevealActionCategoryAndClipboardDetail() {
        let screenshotURL = URL(fileURLWithPath: "/tmp/Pixel-10-Pro_2026-08-22_130934_049.png")
        let request = ScreenshotNotificationService.makeNotificationRequest(
            for: screenshotURL,
            copiedToClipboard: true,
            identifier: "screenshot-test"
        )

        XCTAssertEqual(request.identifier, "screenshot-test")
        XCTAssertEqual(request.content.title, "Screenshot Saved")
        XCTAssertEqual(
            request.content.body,
            "Pixel-10-Pro_2026-08-22_130934_049.png was copied to the clipboard."
        )
        XCTAssertEqual(request.content.categoryIdentifier, ScreenshotNotificationIdentifier.category)
        XCTAssertEqual(
            request.content.userInfo[ScreenshotNotificationIdentifier.screenshotPath] as? String,
            screenshotURL.path
        )

        let category = ScreenshotNotificationService.makeNotificationCategory()
        XCTAssertEqual(category.identifier, ScreenshotNotificationIdentifier.category)
        XCTAssertEqual(category.actions.map(\.identifier), [ScreenshotNotificationIdentifier.revealInFinderAction])
        XCTAssertEqual(category.actions.map(\.title), ["Reveal in Finder"])
    }

    func testBuildsNotificationWithoutClipboardDetailWhenCopyIsDisabled() {
        let screenshotURL = URL(fileURLWithPath: "/tmp/Pixel-10-Pro_2026-08-22_130934_049.png")
        let request = ScreenshotNotificationService.makeNotificationRequest(
            for: screenshotURL,
            copiedToClipboard: false,
            identifier: "screenshot-test"
        )

        XCTAssertEqual(request.content.body, screenshotURL.lastPathComponent)
    }
}
