import Foundation

enum LogcatCrashFilter {
    private static let diagnosticTerms = [
        "exception",
        "crash",
        "fatal",
        "anr",
    ]
    private static let stackTracePrefixes = [
        "at ",
        "caused by:",
        "suppressed:",
        "... ",
    ]

    static func includes(_ entry: LogcatEntry) -> Bool {
        switch entry.priority {
        case .error, .assert:
            return true
        case .verbose, .debug, .info, .warn:
            break
        }

        let diagnosticText = "\(entry.tag) \(entry.message)"
        if diagnosticTerms.contains(where: diagnosticText.localizedCaseInsensitiveContains) {
            return true
        }

        let message = entry.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return stackTracePrefixes.contains(where: {
            message.lowercased().hasPrefix($0)
        })
    }
}
