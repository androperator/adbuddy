import Foundation

enum ScreenshotFilename {
    static func uniqueScreenshotURLs(
        in directoryURL: URL,
        deviceName: String,
        date: Date,
        primarySuffix: String,
        alsoSavesOriginal: Bool,
        alsoSavesFiftyPercentCopy: Bool,
        fileExtension: String = "png",
        timeZone: TimeZone = .current,
        fileExists: (URL) -> Bool
    ) -> ScreenshotSaveFileURLs {
        let timestamp = formattedTimestamp(for: date, timeZone: timeZone)
        let baseName = "\(sanitizedDeviceName(deviceName))_\(timestamp)"

        var attempt = 1
        while true {
            let collisionSuffix = attempt == 1 ? "" : "-\(attempt)"
            let name = baseName + collisionSuffix
            let originalFileURL = alsoSavesOriginal
                ? directoryURL.appendingPathComponent("\(name).\(fileExtension)")
                : nil
            let primaryFileURL = directoryURL.appendingPathComponent(
                "\(name)\(primarySuffix).\(fileExtension)"
            )
            let fiftyPercentFileURL = alsoSavesFiftyPercentCopy
                ? directoryURL.appendingPathComponent("\(name)\(primarySuffix)_50.\(fileExtension)")
                : nil
            let requestedFileURLs = [originalFileURL, primaryFileURL, fiftyPercentFileURL].compactMap { $0 }
            if requestedFileURLs.allSatisfy({ !fileExists($0) }) {
                return ScreenshotSaveFileURLs(
                    originalFileURL: originalFileURL,
                    primaryFileURL: primaryFileURL,
                    fiftyPercentFileURL: fiftyPercentFileURL
                )
            }
            attempt += 1
        }
    }

    static func uniqueURL(
        in directoryURL: URL,
        deviceName: String,
        date: Date,
        suffix: String = "",
        fileExtension: String = "png",
        timeZone: TimeZone = .current,
        fileExists: (URL) -> Bool
    ) -> URL {
        let timestamp = formattedTimestamp(for: date, timeZone: timeZone)
        let baseName = "\(sanitizedDeviceName(deviceName))_\(timestamp)\(suffix)"

        var attempt = 1
        while true {
            let suffix = attempt == 1 ? "" : "-\(attempt)"
            let fileURL = directoryURL.appendingPathComponent("\(baseName)\(suffix).\(fileExtension)")
            if !fileExists(fileURL) {
                return fileURL
            }
            attempt += 1
        }
    }

    static func uniqueOriginalAndFramedURLs(
        in directoryURL: URL,
        deviceName: String,
        date: Date,
        fileExtension: String = "png",
        timeZone: TimeZone = .current,
        fileExists: (URL) -> Bool
    ) -> (original: URL, framed: URL) {
        let timestamp = formattedTimestamp(for: date, timeZone: timeZone)
        let baseName = "\(sanitizedDeviceName(deviceName))_\(timestamp)"

        var attempt = 1
        while true {
            let collisionSuffix = attempt == 1 ? "" : "-\(attempt)"
            let originalURL = directoryURL.appendingPathComponent(
                "\(baseName)\(collisionSuffix).\(fileExtension)"
            )
            let framedURL = directoryURL.appendingPathComponent(
                "\(baseName)\(collisionSuffix)_framed.\(fileExtension)"
            )
            if !fileExists(originalURL), !fileExists(framedURL) {
                return (originalURL, framedURL)
            }
            attempt += 1
        }
    }

    static func sanitizedDeviceName(_ deviceName: String) -> String {
        let fragments = deviceName.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }
            .joined()
            .split(separator: "-", omittingEmptySubsequences: true)

        let sanitized = fragments.joined(separator: "-")
        return sanitized.isEmpty ? "Android-Device" : sanitized
    }

    private static func formattedTimestamp(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HHmmss_SSS"
        return formatter.string(from: date)
    }
}

struct ScreenshotSaveFileURLs {
    let originalFileURL: URL?
    let primaryFileURL: URL
    let fiftyPercentFileURL: URL?
}
