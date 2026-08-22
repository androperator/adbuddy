import ADBuddyCore

enum DeepLinkLaunchFeedback: Equatable {
    case success(AndroidDeepLinkLaunchOutcome, deviceName: String)
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
            "Link Opened"
        case .failure:
            "Could Not Open Link"
        }
    }

    var detail: String {
        switch self {
        case .success(let outcome, let deviceName):
            "\(outcome.deepLink.uri) opened on \(deviceName)."
        case .failure(let message):
            message
        }
    }
}
