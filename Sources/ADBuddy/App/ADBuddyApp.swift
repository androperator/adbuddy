import AppKit
import SwiftUI

@main
struct ADBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("hasAppliedSectionedWindowLayout") private var hasAppliedSectionedWindowLayout = false
    @State private var deviceStore: DeviceStore
    @State private var emulatorStore: EmulatorStore
    @State private var preferences: AppPreferences
    @State private var isShowingSettings = false

    init() {
        let preferences = AppPreferences()
        _preferences = State(initialValue: preferences)
        _deviceStore = State(initialValue: DeviceStore(preferences: preferences))
        _emulatorStore = State(initialValue: EmulatorStore())
        AppLogger.lifecycle.info("ADBuddy launch requested")
    }

    var body: some Scene {
        let connectedDeviceCount = deviceStore.devices.filter { $0.kind == .physical }.count
        let initialWindowContentSize = DeviceListLayout.initialWindowContentSize(
            for: deviceStore.status,
            connectedDeviceCount: connectedDeviceCount,
            virtualDeviceCount: emulatorStore.virtualDevices.count,
            isEmulatorListReady: emulatorStore.status != .loading
        )

        WindowGroup("ADBuddy", id: "main") {
            ContentView(isShowingSettings: $isShowingSettings)
                .environment(deviceStore)
                .environment(emulatorStore)
                .environment(preferences)
                .overlay(alignment: .topLeading) {
                    InitialWindowSizer(
                        targetContentSize: initialWindowContentSize,
                        hasAppliedCompactLayout: $hasAppliedSectionedWindowLayout
                    )
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                }
                .task {
                    deviceStore.start()
                    emulatorStore.refreshVirtualDevices()
                }
        }
        .defaultSize(width: DeviceListLayout.windowWidth, height: 280)
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
                    .environment(preferences)
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
                .environment(emulatorStore)
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
