import Foundation

struct LogcatParser: Sendable {
    private static let entryExpression = try! NSRegularExpression(
        pattern: #"^(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})\.(\d{3})\s+(\d+)\s+(\d+)\s+([VDIWEA])\s+(.+?):(?:\s?(.*))?$"#
    )

    private let calendar: Calendar
    private let referenceYear: Int
    private var pendingLineData = Data()
    private var nextEntryID: UInt64 = 0
    private var previousEntryContext: EntryContext?

    init(referenceDate: Date = Date(), calendar: Calendar = LogcatParser.defaultCalendar) {
        self.calendar = calendar
        referenceYear = calendar.component(.year, from: referenceDate)
    }

    mutating func consume(_ chunk: Data) -> [LogcatEntry] {
        pendingLineData.append(chunk)

        var entries: [LogcatEntry] = []
        while let newlineIndex = pendingLineData.firstIndex(of: 0x0A) {
            var lineData = Data(pendingLineData[..<newlineIndex])
            pendingLineData.removeSubrange(...newlineIndex)

            if lineData.last == 0x0D {
                lineData.removeLast()
            }

            guard let line = String(data: lineData, encoding: .utf8),
                  let entry = parse(line: line) else {
                continue
            }
            entries.append(entry)
        }

        return entries
    }

    mutating func consume(_ chunk: String) -> [LogcatEntry] {
        consume(Data(chunk.utf8))
    }

    private mutating func parse(line: String) -> LogcatEntry? {
        if let context = parseEntryContext(from: line) {
            previousEntryContext = context
            return makeEntry(context: context, message: context.message)
        }

        guard line.first?.isWhitespace == true,
              let previousEntryContext else {
            return nil
        }

        let message = line.trimmingCharacters(in: .whitespaces)
        guard !message.isEmpty else {
            return nil
        }
        return makeEntry(context: previousEntryContext, message: message)
    }

    private mutating func makeEntry(context: EntryContext, message: String) -> LogcatEntry {
        nextEntryID += 1
        return LogcatEntry(
            id: nextEntryID,
            timestamp: context.timestamp,
            priority: context.priority,
            processID: context.processID,
            threadID: context.threadID,
            tag: context.tag,
            message: message
        )
    }

    private func parseEntryContext(from line: String) -> EntryContext? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = Self.entryExpression.firstMatch(in: line, range: range),
              let month = capture(1, from: match, in: line).flatMap(Int.init),
              let day = capture(2, from: match, in: line).flatMap(Int.init),
              let hour = capture(3, from: match, in: line).flatMap(Int.init),
              let minute = capture(4, from: match, in: line).flatMap(Int.init),
              let second = capture(5, from: match, in: line).flatMap(Int.init),
              let millisecond = capture(6, from: match, in: line).flatMap(Int.init),
              let processID = capture(7, from: match, in: line).flatMap(Int.init),
              let threadID = capture(8, from: match, in: line).flatMap(Int.init),
              let priorityValue = capture(9, from: match, in: line),
              let priority = LogcatPriority(rawValue: priorityValue),
              let tag = capture(10, from: match, in: line),
              let timestamp = timestamp(
                  month: month,
                  day: day,
                  hour: hour,
                  minute: minute,
                  second: second,
                  millisecond: millisecond
              ) else {
            return nil
        }

        return EntryContext(
            timestamp: timestamp,
            priority: priority,
            processID: processID,
            threadID: threadID,
            tag: tag,
            message: capture(11, from: match, in: line) ?? ""
        )
    }

    private func capture(_ index: Int, from match: NSTextCheckingResult, in line: String) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound,
              let stringRange = Range(range, in: line) else {
            return nil
        }
        return String(line[stringRange])
    }

    private func timestamp(
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int,
        millisecond: Int
    ) -> Date? {
        calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: referenceYear,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second,
                nanosecond: millisecond * 1_000_000
            )
        )
    }

    private struct EntryContext: Sendable {
        let timestamp: Date
        let priority: LogcatPriority
        let processID: Int
        let threadID: Int
        let tag: String
        let message: String
    }

    private static var defaultCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
