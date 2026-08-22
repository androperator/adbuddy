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
