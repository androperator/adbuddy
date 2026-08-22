import AppKit
import Foundation
@preconcurrency import UserNotifications

enum SavedMediaNotificationKind: Sendable {
    case screenshot(copiedToClipboard: Bool)
    case recording

    var title: String {
        switch self {
        case .screenshot:
            "Screenshot Saved"
        case .recording:
            "Recording Saved"
        }
    }

    func body(for fileURL: URL) -> String {
        switch self {
        case .screenshot(let copiedToClipboard):
            copiedToClipboard
                ? "\(fileURL.lastPathComponent) was copied to the clipboard."
                : fileURL.lastPathComponent
        case .recording:
            fileURL.lastPathComponent
        }
    }
}

protocol SavedMediaNotifying: Sendable {
    func notifyAboutSavedMedia(at fileURL: URL, kind: SavedMediaNotificationKind) async
}

enum MediaNotificationIdentifier {
    static let category = "saved-media"
    static let revealInFinderAction = "reveal-saved-media-in-finder"
    static let savedMediaPath = "saved-media-path"
}

final class MediaNotificationService: NSObject, SavedMediaNotifying, @unchecked Sendable {
    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
        super.init()

        notificationCenter.delegate = self
        notificationCenter.setNotificationCategories([Self.makeNotificationCategory()])
    }

    static func makeNotificationCategory() -> UNNotificationCategory {
        let revealAction = UNNotificationAction(
            identifier: MediaNotificationIdentifier.revealInFinderAction,
            title: "Reveal in Finder",
            options: [.foreground]
        )
        return UNNotificationCategory(
            identifier: MediaNotificationIdentifier.category,
            actions: [revealAction],
            intentIdentifiers: []
        )
    }

    func notifyAboutSavedMedia(at fileURL: URL, kind: SavedMediaNotificationKind) async {
        AppLogger.notifications.info("Preparing saved media notification")
        guard await isAuthorizedToPostNotifications() else {
            AppLogger.notifications.info("Saved media notification was not authorized")
            return
        }

        do {
            try await notificationCenter.add(Self.makeNotificationRequest(for: fileURL, kind: kind))
            AppLogger.notifications.info("Posted saved media notification")
        } catch {
            AppLogger.notifications.error("Could not post saved media notification: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func makeNotificationRequest(
        for fileURL: URL,
        kind: SavedMediaNotificationKind,
        identifier: String = UUID().uuidString
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = kind.title
        content.body = kind.body(for: fileURL)
        content.sound = .default
        content.categoryIdentifier = MediaNotificationIdentifier.category
        content.userInfo = [MediaNotificationIdentifier.savedMediaPath: fileURL.path]
        if let attachment = makeMediaAttachment(for: fileURL, kind: kind) {
            content.attachments = [attachment]
        }

        return UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    }

    static func notificationAttachmentOptions(
        for kind: SavedMediaNotificationKind
    ) -> [AnyHashable: Any]? {
        switch kind {
        case .screenshot:
            nil
        case .recording:
            [UNNotificationAttachmentOptionsThumbnailTimeKey: 0]
        }
    }

    private static func makeMediaAttachment(
        for fileURL: URL,
        kind: SavedMediaNotificationKind
    ) -> UNNotificationAttachment? {
        let attachmentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("adbuddy-notification-\(UUID().uuidString)")
            .appendingPathExtension(fileURL.pathExtension)

        do {
            try FileManager.default.copyItem(at: fileURL, to: attachmentURL)
            return try UNNotificationAttachment(
                identifier: "saved-media-preview",
                url: attachmentURL,
                options: notificationAttachmentOptions(for: kind)
            )
        } catch {
            try? FileManager.default.removeItem(at: attachmentURL)
            AppLogger.notifications.error("Could not attach saved media preview: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func isAuthorizedToPostNotifications() async -> Bool {
        let settings = await notificationCenter.notificationSettings()
        AppLogger.notifications.info("Saved media notification authorization status: \(settings.authorizationStatus.rawValue)")

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            do {
                AppLogger.notifications.info("Requesting saved media notification authorization")
                return try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            } catch {
                AppLogger.notifications.error("Could not request saved media notification authorization: \(error.localizedDescription, privacy: .public)")
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}

extension MediaNotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == MediaNotificationIdentifier.revealInFinderAction,
              let savedMediaPath = response.notification.request.content.userInfo[MediaNotificationIdentifier.savedMediaPath] as? String else {
            completionHandler()
            return
        }

        let savedMediaURL = URL(fileURLWithPath: savedMediaPath)
        completionHandler()
        DispatchQueue.main.async {
            NSWorkspace.shared.activateFileViewerSelecting([savedMediaURL])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        AppLogger.notifications.info("Presenting saved media notification")
        completionHandler([.banner, .list, .sound])
    }
}
