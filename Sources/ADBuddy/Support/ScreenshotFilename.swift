import Foundation

enum ScreenshotFilename {
    static func uniqueURL(
        in directoryURL: URL,
        deviceName: String,
        date: Date,
        fileExtension: String = "png",
        timeZone: TimeZone = .current,
        fileExists: (URL) -> Bool
    ) -> URL {
        let timestamp = formattedTimestamp(for: date, timeZone: timeZone)
        let baseName = "\(sanitizedDeviceName(deviceName))_\(timestamp)"

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
