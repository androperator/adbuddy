import Foundation
import XCTest
@testable import ADBuddy

@MainActor
final class MediaClipboardServiceTests: XCTestCase {
    func testCopiesScreenshotAsAFileURL() throws {
        let screenshotData = Data([0x89, 0x50, 0x4E, 0x47])
        let screenshotURL = try makeTemporaryFile(named: "screenshot.png", data: screenshotData)
        defer {
            try? FileManager.default.removeItem(at: screenshotURL.deletingLastPathComponent())
        }
        let pasteboard = TestMediaPasteboard()
        let service = MediaClipboardService(pasteboard: pasteboard)

        XCTAssertEqual(service.copyScreenshot(at: screenshotURL), .copied)
        XCTAssertEqual(pasteboard.fileURL, screenshotURL)
    }

    func testCopiesRecordingAsAFileURL() throws {
        let recordingURL = try makeTemporaryFile(named: "recording.mp4", data: Data([0x00, 0x01]))
        defer {
            try? FileManager.default.removeItem(at: recordingURL.deletingLastPathComponent())
        }
        let pasteboard = TestMediaPasteboard()
        let service = MediaClipboardService(pasteboard: pasteboard)

        XCTAssertEqual(service.copyRecordings(at: [recordingURL]), .copied)
        XCTAssertEqual(pasteboard.fileURL, recordingURL)
    }

    func testCopiesAllRecordingClipsTogether() throws {
        let first = try makeTemporaryFile(named: "clip_01.mp4", data: Data([0]))
        let second = first.deletingLastPathComponent().appendingPathComponent("clip_02.mp4")
        try Data([1]).write(to: second)
        defer { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()) }
        let pasteboard = TestMediaPasteboard()
        XCTAssertEqual(MediaClipboardService(pasteboard: pasteboard).copyRecordings(at: [first, second]), .copied)
        XCTAssertEqual(pasteboard.fileURLs, [first, second])
    }

    func testReportsAUsefulFailureWhenTheRecordingIsMissing() {
        let pasteboard = TestMediaPasteboard()
        let service = MediaClipboardService(pasteboard: pasteboard)
        let missingRecordingURL = URL(fileURLWithPath: "/tmp/adbuddy-missing-recording.mp4")

        guard case .failed(let message) = service.copyRecordings(at: [missingRecordingURL]) else {
            return XCTFail("Expected the missing recording to fail clipboard copy")
        }

        XCTAssertEqual(message, "Could not find the saved recording to copy it to the clipboard.")
        XCTAssertNil(pasteboard.fileURL)
    }

    func testReportsAUsefulFailureWhenTheScreenshotIsMissing() {
        let pasteboard = TestMediaPasteboard()
        let service = MediaClipboardService(pasteboard: pasteboard)
        let missingScreenshotURL = URL(fileURLWithPath: "/tmp/adbuddy-missing-screenshot.png")

        guard case .failed(let message) = service.copyScreenshot(at: missingScreenshotURL) else {
            return XCTFail("Expected the missing screenshot to fail clipboard copy")
        }

        XCTAssertEqual(message, "Could not find the saved screenshot to copy it to the clipboard.")
        XCTAssertNil(pasteboard.fileURL)
    }

    private func makeTemporaryFile(named name: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ADBuddyMediaClipboardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(name)
        try data.write(to: fileURL)
        return fileURL
    }
}

@MainActor
private final class TestMediaPasteboard: MediaPasteboardWriting {
    private(set) var fileURLs: [URL] = []
    var fileURL: URL? { fileURLs.first }

    func writeFileURLs(_ fileURLs: [URL]) -> Bool {
        self.fileURLs = fileURLs
        return true
    }
}
