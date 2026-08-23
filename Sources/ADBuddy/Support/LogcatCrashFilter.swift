import Foundation

enum LogcatCrashFilter {
    private static let diagnosticTerms = [
        "exception",
        "crash",
        "fatal",
    ]
    private static let stackTracePrefixes = [
        "at ",
        "caused by:",
        "suppressed:",
        "... ",
    ]

    static func includes(_ entry: LogcatEntry) -> Bool {
        let diagnosticText = "\(entry.tag) \(entry.message)"
        if diagnosticTerms.contains(where: diagnosticText.localizedCaseInsensitiveContains) ||
            containsANR(in: diagnosticText) {
            return true
        }

        let message = entry.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return stackTracePrefixes.contains(where: {
            message.lowercased().hasPrefix($0)
        })
    }

    private static func containsANR(in text: String) -> Bool {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { word in
            String(word).localizedCaseInsensitiveCompare("ANR") == .orderedSame
        }
    }
}
