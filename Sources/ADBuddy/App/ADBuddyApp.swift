import AppKit
import SwiftUI

@main
struct ADBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var deviceStore = DeviceStore()
    @State private var preferences = AppPreferences()

    init() {
        AppLogger.lifecycle.info("ADBuddy launch requested")
    }

    var body: some Scene {
        WindowGroup("ADBuddy", id: "main") {
            ContentView()
                .environment(deviceStore)
                .environment(preferences)
                .task {
                    deviceStore.start()
                }
        }
        .defaultSize(width: 640, height: 420)

        MenuBarExtra("ADBuddy", systemImage: "camera") {
            MenuBarContentView()
                .environment(deviceStore)
                .environment(preferences)
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
