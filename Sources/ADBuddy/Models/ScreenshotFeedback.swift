import Foundation

enum ScreenshotFeedback: Equatable {
    case success(URL)
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
        case .success(let fileURL):
            fileURL.lastPathComponent
        case .failure(let message):
            message
        }
    }
}
