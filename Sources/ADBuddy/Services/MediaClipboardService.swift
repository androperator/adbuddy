import AppKit
import Foundation

@MainActor
protocol MediaClipboardCopying {
    func copyScreenshot(at fileURL: URL) -> MediaClipboardCopyResult
    func copyRecording(at fileURL: URL) -> MediaClipboardCopyResult
}

enum MediaClipboardCopyResult: Equatable {
    case copied
    case failed(String)
}

@MainActor
protocol MediaPasteboardWriting {
    func writeFileURL(_ fileURL: URL) -> Bool
}

@MainActor
struct SystemMediaPasteboard: MediaPasteboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func writeFileURL(_ fileURL: URL) -> Bool {
        pasteboard.clearContents()
        return pasteboard.writeObjects([fileURL as NSURL])
    }
}

@MainActor
struct MediaClipboardService: MediaClipboardCopying {
    private let pasteboard: any MediaPasteboardWriting

    init(pasteboard: any MediaPasteboardWriting = SystemMediaPasteboard()) {
        self.pasteboard = pasteboard
    }

    func copyScreenshot(at fileURL: URL) -> MediaClipboardCopyResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failed("Could not find the saved screenshot to copy it to the clipboard.")
        }
        guard pasteboard.writeFileURL(fileURL) else {
            return .failed("macOS could not write the screenshot file to the clipboard.")
        }

        return .copied
    }

    func copyRecording(at fileURL: URL) -> MediaClipboardCopyResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failed("Could not find the saved recording to copy it to the clipboard.")
        }
        guard pasteboard.writeFileURL(fileURL) else {
            return .failed("macOS could not write the recording to the clipboard.")
        }

        return .copied
    }
}
