import AppKit
import SwiftUI

@main
struct ADBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("hasAppliedCompactWindowLayout") private var hasAppliedCompactWindowLayout = false
    @State private var deviceStore: DeviceStore
    @State private var preferences: AppPreferences
    @State private var isShowingSettings = false

    init() {
        let preferences = AppPreferences()
        _preferences = State(initialValue: preferences)
        _deviceStore = State(initialValue: DeviceStore(preferences: preferences))
        AppLogger.lifecycle.info("ADBuddy launch requested")
    }

    var body: some Scene {
        let initialWindowContentSize = DeviceListLayout.initialWindowContentSize(
            for: deviceStore.status,
            deviceCount: deviceStore.devices.count
        )

        WindowGroup("ADBuddy", id: "main") {
            ContentView(isShowingSettings: $isShowingSettings)
                .environment(deviceStore)
                .environment(preferences)
                .overlay(alignment: .topLeading) {
                    InitialWindowSizer(
                        targetContentSize: initialWindowContentSize,
                        hasAppliedCompactLayout: $hasAppliedCompactWindowLayout
                    )
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                }
                .task {
                    deviceStore.start()
                }
        }
        .defaultSize(width: DeviceListLayout.windowWidth, height: 200)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    AppLogger.settings.info("Settings requested from the application menu")
                    isShowingSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        WindowGroup(for: LogcatWindowID.self) { $windowID in
            if let windowID {
                LogcatWindowView(windowID: windowID)
                    .environment(deviceStore)
            }
        }
        .defaultSize(width: 920, height: 600)
        .windowResizability(.contentMinSize)

        MenuBarExtra(
            "ADBuddy",
            systemImage: deviceStore.hasActiveScreenRecording ? "stop.fill" : "camera"
        ) {
            MenuBarContentView(showSettings: {
                isShowingSettings = true
            })
                .environment(deviceStore)
                .environment(preferences)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppLogger.lifecycle.info("ADBuddy application launched")
    }
}
