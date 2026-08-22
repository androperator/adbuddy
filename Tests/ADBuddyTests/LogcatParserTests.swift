import Foundation
import XCTest
@testable import ADBuddy

final class LogcatParserTests: XCTestCase {
    func testParsesAllPrioritiesAndTypedFields() {
        var parser = makeParser()

        let entries = parser.consume(
            """
            08-22 13:14:15.001   101   201 V VerboseTag: verbose message
            08-22 13:14:15.002   102   202 D DebugTag: debug message
            08-22 13:14:15.003   103   203 I VeryLongTagNameForAnAndroidComponent: Unicode \u{1F680}
            08-22 13:14:15.004   104   204 W WarnTag:
            08-22 13:14:15.005   105   205 E ErrorTag: error message
            08-22 13:14:15.006   106   206 A AssertTag: assert message
            """ + "\n"
        )

        XCTAssertEqual(entries.map(\.priority), [.verbose, .debug, .info, .warn, .error, .assert])
        XCTAssertEqual(entries.map(\.id), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(entries[2].processID, 103)
        XCTAssertEqual(entries[2].threadID, 203)
        XCTAssertEqual(entries[2].tag, "VeryLongTagNameForAnAndroidComponent")
        XCTAssertEqual(entries[2].message, "Unicode \u{1F680}")
        XCTAssertEqual(entries[3].message, "")
    }

    func testPreservesAnIncompleteLineUntilTheNextChunk() {
        var parser = makeParser()

        XCTAssertTrue(parser.consume("08-22 13:14:15.001   101   201 D Tag: partial").isEmpty)

        let entries = parser.consume(" message\n")

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].message, "partial message")
    }

    func testSkipsMalformedLinesWithoutDroppingLaterEntries() {
        var parser = makeParser()

        let entries = parser.consume(
            """
            08-22 13:14:15.001   101   201 I First: before
            this is not a logcat line
            08-22 13:14:15.002   102   202 E Second: after
            """ + "\n"
        )

        XCTAssertEqual(entries.map(\.tag), ["First", "Second"])
        XCTAssertEqual(entries.map(\.message), ["before", "after"])
    }

    func testEmitsContinuationLinesWithThePreviousEntryContext() {
        var parser = makeParser()

        let entries = parser.consume(
            """
            08-22 13:14:15.001   101   201 E Runtime: First line
                at com.example.Main.run(Main.kt:42)
            08-22 13:14:15.002   102   202 I Next: next message
            """ + "\n"
        )

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[1].priority, .error)
        XCTAssertEqual(entries[1].tag, "Runtime")
        XCTAssertEqual(entries[1].message, "at com.example.Main.run(Main.kt:42)")
        XCTAssertEqual(entries[1].id, 2)
    }

    func testFormatsTimestampWithFixedShortTimeFormat() {
        var parser = makeParser()
        let entry = try! XCTUnwrap(
            parser.consume("08-22 13:14:15.678   101   201 D Tag: message\n").first
        )

        XCTAssertEqual(LogcatTimestampFormatter.string(from: entry.timestamp), "13:14:15.678")
    }

    private func makeParser() -> LogcatParser {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 22))!
        return LogcatParser(referenceDate: referenceDate, calendar: calendar)
    }
}
