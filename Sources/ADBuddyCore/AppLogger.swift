import Foundation
import OSLog

public enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.clawperator.adbuddy"

    public static let lifecycle = Logger(subsystem: subsystem, category: "Lifecycle")
    public static let androidSDK = Logger(subsystem: subsystem, category: "AndroidSDK")
    public static let devices = Logger(subsystem: subsystem, category: "Devices")
    public static let screenshot = Logger(subsystem: subsystem, category: "Screenshot")
    public static let mirroring = Logger(subsystem: subsystem, category: "Mirroring")
    public static let recording = Logger(subsystem: subsystem, category: "Recording")
    public static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    public static let menuBar = Logger(subsystem: subsystem, category: "MenuBar")
    public static let settings = Logger(subsystem: subsystem, category: "Settings")
    public static let logcat = Logger(subsystem: subsystem, category: "Logcat")
    public static let emulator = Logger(subsystem: subsystem, category: "Emulator")
    public static let appActions = Logger(subsystem: subsystem, category: "AppActions")
    public static let deepLinks = Logger(subsystem: subsystem, category: "DeepLinks")
    public static let deviceSettings = Logger(subsystem: subsystem, category: "DeviceSettings")
    public static let apkInstallation = Logger(subsystem: subsystem, category: "APKInstallation")
}
