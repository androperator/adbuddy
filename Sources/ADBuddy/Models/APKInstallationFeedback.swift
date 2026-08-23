struct APKInstallationFeedback: Equatable {
    let isSuccess: Bool
    let title: String
    let detail: String
}

enum APKInstallationDeviceState: Equatable {
    case installing
    case succeeded(APKInstallationOutcome)
    case failed(String)

    var isComplete: Bool {
        switch self {
        case .installing:
            false
        case .succeeded, .failed:
            true
        }
    }
}
