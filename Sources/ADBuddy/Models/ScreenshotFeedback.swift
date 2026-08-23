import Foundation

enum ScreenshotFeedback: Equatable {
    case success(ScreenshotCaptureOutput, copiedToClipboard: Bool)
    case failure(String)

    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    var title: String {
        switch self {
        case .success:
            "Screenshot Saved"
        case .failure:
            "Screenshot Failed"
        }
    }

    var detail: String {
        switch self {
        case .success(let output, let copiedToClipboard):
            let primaryDetail = copiedToClipboard
                ? "\(output.primaryFileURL.lastPathComponent) copied to the clipboard."
                : output.primaryFileURL.lastPathComponent
            guard let originalFileURL = output.originalFileURL else {
                return primaryDetail
            }
            return "\(primaryDetail) Also saved \(originalFileURL.lastPathComponent)."
        case .failure(let message):
            return message
        }
    }
}
