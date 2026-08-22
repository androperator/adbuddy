import Foundation

enum LogcatDeviceAvailability: Equatable, Hashable, Sendable {
    case unavailable
    case usable(adbPath: String)
}

enum LogcatReconnectPolicy {
    static func delay(for failedAttempts: Int) -> Duration {
        let seconds = min(8, 1 << min(max(failedAttempts - 1, 0), 3))
        return .seconds(seconds)
    }
}
