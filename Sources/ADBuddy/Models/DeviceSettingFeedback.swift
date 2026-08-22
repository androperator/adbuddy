import ADBuddyCore

enum DeviceSettingFeedback: Equatable {
    case success(AndroidDeviceSettingOutcome, deviceName: String)
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
            "Device Setting Updated"
        case .failure:
            "Could Not Update Device Setting"
        }
    }

    var detail: String {
        switch self {
        case .success(let outcome, let deviceName):
            "\(outcome.action.completedDescription) on \(deviceName)."
        case .failure(let message):
            message
        }
    }
}
