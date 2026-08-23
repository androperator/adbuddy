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
            let additionalFileNames = [
                output.originalFileURL?.lastPathComponent,
                output.fiftyPercentFileURL?.lastPathComponent,
            ].compactMap { $0 }
            guard !additionalFileNames.isEmpty else {
                return primaryDetail
            }
            return "\(primaryDetail) Also saved \(additionalFileNames.joined(separator: " and "))."
        case .failure(let message):
            return message
        }
    }
}
