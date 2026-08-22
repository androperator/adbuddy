import Foundation

enum LogcatEntryTextFormatter {
    static func string(from entry: LogcatEntry) -> String {
        "\(LogcatTimestampFormatter.string(from: entry.timestamp)) \(entry.priority.rawValue) \(entry.tag) (PID \(entry.processID), TID \(entry.threadID)): \(entry.message)"
    }
}
