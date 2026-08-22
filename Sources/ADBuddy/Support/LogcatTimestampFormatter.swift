import Foundation

enum LogcatTimestampFormatter {
    static func string(from timestamp: Date) -> String {
        formatter.string(from: timestamp)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
