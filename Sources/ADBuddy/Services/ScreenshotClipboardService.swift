import AppKit
import Foundation

@MainActor
protocol ScreenshotClipboardCopying {
    func copyScreenshot(at fileURL: URL) -> ScreenshotClipboardCopyResult
}

enum ScreenshotClipboardCopyResult: Equatable {
    case copied
    case failed(String)
}

@MainActor
struct ScreenshotClipboardService: ScreenshotClipboardCopying {
    func copyScreenshot(at fileURL: URL) -> ScreenshotClipboardCopyResult {
        let screenshotData: Data
        do {
            screenshotData = try Data(contentsOf: fileURL)
        } catch {
            return .failed("Could not read the saved screenshot: \(error.localizedDescription)")
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(screenshotData, forType: .png) else {
            return .failed("macOS could not write the screenshot to the clipboard.")
        }

        return .copied
    }
}
