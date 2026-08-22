import Foundation

enum LogcatPriority: String, CaseIterable, Codable, Sendable {
    case verbose = "V"
    case debug = "D"
    case info = "I"
    case warn = "W"
    case error = "E"
    case assert = "A"

    var severity: Int {
        switch self {
        case .verbose:
            0
        case .debug:
            1
        case .info:
            2
        case .warn:
            3
        case .error:
            4
        case .assert:
            5
        }
    }
}

struct LogcatEntry: Equatable, Identifiable, Sendable {
    let id: UInt64
    let timestamp: Date
    let priority: LogcatPriority
    let processID: Int
    let threadID: Int
    let tag: String
    let message: String
}

enum LogcatTableColumn: CaseIterable, Hashable {
    case time
    case processID
    case threadID
    case level
    case tag
    case message

    var identifier: String {
        switch self {
        case .time:
            "time"
        case .processID:
            "processID"
        case .threadID:
            "threadID"
        case .level:
            "level"
        case .tag:
            "tag"
        case .message:
            "message"
        }
    }

    var title: String {
        switch self {
        case .time:
            "Time"
        case .processID:
            "PID"
        case .threadID:
            "TID"
        case .level:
            "Level"
        case .tag:
            "Tag"
        case .message:
            "Message"
        }
    }

    var width: CGFloat {
        switch self {
        case .time:
            88
        case .processID, .threadID:
            56
        case .level:
            42
        case .tag:
            160
        case .message:
            720
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .time:
            "Time"
        case .processID:
            "Process ID"
        case .threadID:
            "Thread ID"
        case .level:
            "Log level"
        case .tag:
            "Tag"
        case .message:
            "Message"
        }
    }

    static func visibleColumns(
        showsProcessID: Bool = false,
        showsThreadID: Bool = false
    ) -> [LogcatTableColumn] {
        allCases.filter { column in
            switch column {
            case .processID:
                showsProcessID
            case .threadID:
                showsThreadID
            case .time, .level, .tag, .message:
                true
            }
        }
    }
}
