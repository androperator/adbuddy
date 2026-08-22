import AppKit
import Foundation
@preconcurrency import UserNotifications

protocol ScreenshotNotifying: Sendable {
    func notifyAboutSavedScreenshot(at fileURL: URL, copiedToClipboard: Bool) async
}

enum ScreenshotNotificationIdentifier {
    static let category = "screenshot-saved"
    static let revealInFinderAction = "reveal-screenshot-in-finder"
    static let screenshotPath = "screenshot-path"
}

final class ScreenshotNotificationService: NSObject, ScreenshotNotifying, @unchecked Sendable {
    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
        super.init()

        notificationCenter.delegate = self
        notificationCenter.setNotificationCategories([Self.makeNotificationCategory()])
    }

    static func makeNotificationCategory() -> UNNotificationCategory {
        let revealAction = UNNotificationAction(
            identifier: ScreenshotNotificationIdentifier.revealInFinderAction,
            title: "Reveal in Finder",
            options: [.foreground]
        )
        return UNNotificationCategory(
            identifier: ScreenshotNotificationIdentifier.category,
            actions: [revealAction],
            intentIdentifiers: []
        )
    }

    func notifyAboutSavedScreenshot(at fileURL: URL, copiedToClipboard: Bool) async {
        AppLogger.notifications.info("Preparing screenshot notification")
        guard await isAuthorizedToPostNotifications() else {
            AppLogger.notifications.info("Screenshot notification was not authorized")
            return
        }

        do {
            try await notificationCenter.add(
                Self.makeNotificationRequest(
                    for: fileURL,
                    copiedToClipboard: copiedToClipboard
                )
            )
            AppLogger.notifications.info("Posted screenshot notification")
        } catch {
            AppLogger.notifications.error("Could not post screenshot notification: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func makeNotificationRequest(
        for fileURL: URL,
        copiedToClipboard: Bool,
        identifier: String = UUID().uuidString
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Screenshot Saved"
        content.body = copiedToClipboard
            ? "\(fileURL.lastPathComponent) was copied to the clipboard."
            : fileURL.lastPathComponent
        content.sound = .default
        content.categoryIdentifier = ScreenshotNotificationIdentifier.category
        content.userInfo = [ScreenshotNotificationIdentifier.screenshotPath: fileURL.path]

        return UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    }

    private func isAuthorizedToPostNotifications() async -> Bool {
        let settings = await notificationCenter.notificationSettings()
        AppLogger.notifications.info("Screenshot notification authorization status: \(settings.authorizationStatus.rawValue)")

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            do {
                AppLogger.notifications.info("Requesting screenshot notification authorization")
                return try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            } catch {
                AppLogger.notifications.error("Could not request notification authorization: \(error.localizedDescription, privacy: .public)")
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}

extension ScreenshotNotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == ScreenshotNotificationIdentifier.revealInFinderAction,
              let screenshotPath = response.notification.request.content.userInfo[ScreenshotNotificationIdentifier.screenshotPath] as? String else {
            completionHandler()
            return
        }

        let screenshotURL = URL(fileURLWithPath: screenshotPath)
        completionHandler()
        DispatchQueue.main.async {
            NSWorkspace.shared.activateFileViewerSelecting([screenshotURL])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
