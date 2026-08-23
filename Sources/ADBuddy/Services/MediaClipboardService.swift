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
    func writePNGData(_ data: Data) -> Bool
    func writeFileURL(_ fileURL: URL) -> Bool
}

@MainActor
struct SystemMediaPasteboard: MediaPasteboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func writePNGData(_ data: Data) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: .png)
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
        let screenshotData: Data
        do {
            screenshotData = try Data(contentsOf: fileURL)
        } catch {
            return .failed("Could not read the saved screenshot: \(error.localizedDescription)")
        }

        guard pasteboard.writePNGData(screenshotData) else {
            return .failed("macOS could not write the screenshot to the clipboard.")
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
