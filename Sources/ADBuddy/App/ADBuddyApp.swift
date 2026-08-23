import AppKit
import SwiftUI

@main
struct ADBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @FocusedValue(\.logcatSearchAction) private var logcatSearchAction
    @State private var deviceStore: DeviceStore
    @State private var emulatorStore: EmulatorStore
    @State private var preferences: AppPreferences

    init() {
        let preferences = AppPreferences()
        _preferences = State(initialValue: preferences)
        _deviceStore = State(initialValue: DeviceStore(preferences: preferences))
        _emulatorStore = State(initialValue: EmulatorStore())
        AppLogger.lifecycle.info("ADBuddy launch requested")
    }

    var body: some Scene {
        let connectedDeviceCount = deviceStore.devices.count
        let mainWindowContentSize = DeviceListLayout.mainWindowContentSize(
            for: deviceStore.status,
            connectedDeviceCount: connectedDeviceCount,
            virtualDeviceCount: displayedVirtualDeviceCount
        )

        WindowGroup("ADBuddy", id: "main") {
            ContentView()
                .frame(minWidth: DeviceListLayout.windowWidth)
                .environment(deviceStore)
                .environment(emulatorStore)
                .environment(preferences)
                .overlay(alignment: .topLeading) {
                    MainWindowSizer(targetContentSize: mainWindowContentSize)
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                }
                .task {
                    deviceStore.start()
                    emulatorStore.refreshVirtualDevices()
                }
        }
        .defaultSize(
            width: DeviceListLayout.windowWidth,
            height: DeviceListLayout.unavailableContentHeight
        )
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About ADBuddy") {
                    ADBuddyAboutPanel.present()
                }
            }
        }

        Settings {
            SettingsView(preferences: preferences)
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
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Find in Logcat") {
                    logcatSearchAction?()
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(logcatSearchAction == nil)
            }
        }

        MenuBarExtra(
            "ADBuddy",
            systemImage: deviceStore.hasActiveScreenRecording ? "stop.fill" : "camera"
        ) {
            MenuBarContentView()
                .environment(deviceStore)
                .environment(emulatorStore)
                .environment(preferences)
        }
        .menuBarExtraStyle(.menu)
    }

    private var displayedVirtualDeviceCount: Int {
        guard case .ready = emulatorStore.status else {
            return 0
        }
        return emulatorStore.virtualDevices.filter {
            if case .running = $0.status {
                return false
            }
            return true
        }.count
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
