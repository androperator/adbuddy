import AppKit
import SwiftUI

@main
struct ADBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        AppLogger.lifecycle.info("ADBuddy launch requested")
    }

    var body: some Scene {
        WindowGroup("ADBuddy", id: "main") {
            ContentView()
        }
        .defaultSize(width: 640, height: 420)

        MenuBarExtra("ADBuddy", systemImage: "camera") {
            MenuBarContentView()
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppLogger.lifecycle.info("ADBuddy application launched")
    }
}
