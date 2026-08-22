import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.clawperator.adbuddy"

    static let lifecycle = Logger(subsystem: subsystem, category: "Lifecycle")
    static let androidSDK = Logger(subsystem: subsystem, category: "AndroidSDK")
    static let devices = Logger(subsystem: subsystem, category: "Devices")
    static let screenshot = Logger(subsystem: subsystem, category: "Screenshot")
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    static let menuBar = Logger(subsystem: subsystem, category: "MenuBar")
}
