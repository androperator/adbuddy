import Foundation
import ADBuddyCore

enum AppActionFeedback: Equatable {
    case success(AndroidAppActionOutcome)
    case failure(String)

    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    var title: String {
        switch self {
        case .success(let outcome):
            "\(outcome.action.displayName) Completed"
        case .failure:
            "App Action Failed"
        }
    }

    var detail: String {
        switch self {
        case .success(let outcome):
            "\(outcome.action.completedDescription) \(outcome.application.packageID)."
        case .failure(let message):
            message
        }
    }
}

struct ForegroundAppUninstallRequest: Equatable, Identifiable {
    let device: AndroidDevice
    let application: AndroidForegroundApplication

    var id: String {
        "\(device.serial)-\(application.packageID)"
    }
}
