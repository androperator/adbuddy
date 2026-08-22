import Foundation
import Observation

@MainActor
@Observable
final class AppPreferences {
    private enum Key {
        static let screenshotDirectoryPath = "screenshotDirectoryPath"
    }

    private let userDefaults: UserDefaults
    private let defaultScreenshotDirectory: URL

    var screenshotDirectory: URL {
        didSet {
            userDefaults.set(screenshotDirectory.path, forKey: Key.screenshotDirectoryPath)
        }
    }

    init(
        userDefaults: UserDefaults = .standard,
        defaultScreenshotDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Screenshots", isDirectory: true)
    ) {
        self.userDefaults = userDefaults
        self.defaultScreenshotDirectory = defaultScreenshotDirectory

        if let savedPath = userDefaults.string(forKey: Key.screenshotDirectoryPath), !savedPath.isEmpty {
            screenshotDirectory = URL(fileURLWithPath: savedPath, isDirectory: true)
        } else {
            screenshotDirectory = defaultScreenshotDirectory
        }
    }

    func resetScreenshotDirectory() {
        screenshotDirectory = defaultScreenshotDirectory
    }
}
