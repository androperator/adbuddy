import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.clawperator.adbuddy"

    static let lifecycle = Logger(subsystem: subsystem, category: "Lifecycle")
    static let androidSDK = Logger(subsystem: subsystem, category: "AndroidSDK")
    static let devices = Logger(subsystem: subsystem, category: "Devices")
    static let screenshot = Logger(subsystem: subsystem, category: "Screenshot")
    static let recording = Logger(subsystem: subsystem, category: "Recording")
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    static let menuBar = Logger(subsystem: subsystem, category: "MenuBar")
    static let settings = Logger(subsystem: subsystem, category: "Settings")
    static let logcat = Logger(subsystem: subsystem, category: "Logcat")
    static let emulator = Logger(subsystem: subsystem, category: "Emulator")
}
