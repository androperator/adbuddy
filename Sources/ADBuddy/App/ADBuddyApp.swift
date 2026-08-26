import AppKit
import SwiftUI

@main
struct ADBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @FocusedValue(\.logcatSearchAction) private var logcatSearchAction
    @State private var deviceStore: DeviceStore
    @State private var emulatorStore: EmulatorStore
    @State private var preferences: AppPreferences
    @State private var apkInstallationStore: APKInstallationStore

    init() {
        UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
        let preferences = AppPreferences()
        _preferences = State(initialValue: preferences)
        _deviceStore = State(initialValue: DeviceStore(preferences: preferences))
        _emulatorStore = State(initialValue: EmulatorStore())
        _apkInstallationStore = State(initialValue: APKInstallationStore())
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
                .environment(apkInstallationStore)
                .overlay(alignment: .topLeading) {
                    MainWindowSizer(targetContentSize: mainWindowContentSize)
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                }
                .task {
                    deviceStore.start()
                    emulatorStore.refreshVirtualDevices()
                }
                .onAppear {
                    appDelegate.setAPKDocumentHandler { fileURLs in
                        guard let fileURL = fileURLs.first else {
                            return
                        }
                        apkInstallationStore.presentInstaller(for: fileURL)
                    }
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

            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView(preferences: preferences)
        }

        WindowGroup(for: LogcatWindowID.self) { $windowID in
            if let windowID {
                LogcatWindowView(windowID: windowID)
                    .environment(deviceStore)
                    .environment(preferences)
                    .overlay(alignment: .topLeading) {
                        FullScreenWindowDisabler()
                            .frame(width: 0, height: 0)
                            .allowsHitTesting(false)
                    }
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

        MenuBarExtra(isInserted: $preferences.showInMenuBar) {
            MenuBarContentView(
                prepareForWindowPresentation: appDelegate.prepareForWindowPresentation
            )
                .environment(deviceStore)
                .environment(emulatorStore)
                .environment(preferences)
                .environment(apkInstallationStore)
        } label: {
            if deviceStore.hasActiveScreenRecording {
                Image(systemName: "stop.fill")
            } else {
                ADBuddyMenuBarGlyph()
            }
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
    private var apkDocumentHandler: (([URL]) -> Void)?
    private var pendingAPKDocumentURLs: [URL] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppLogger.lifecycle.info("ADBuddy application launched")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    @objc private func windowDidBecomeKey(_ notification: Notification) {
        setApplicationActivationPolicy(.regular)
    }

    @MainActor
    @objc private func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            MainWindowController.shared.unregister(window)
        }
        perform(#selector(hideDockIconIfNoWindowsRemain), with: nil, afterDelay: 0)
    }

    @MainActor
    @objc private func hideDockIconIfNoWindowsRemain() {
        guard !NSApp.windows.contains(where: \.isVisible) else {
            return
        }
        setApplicationActivationPolicy(.accessory)
    }

    @MainActor
    private func setApplicationActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) {
        guard NSApp.activationPolicy() != activationPolicy else {
            return
        }

        guard NSApp.setActivationPolicy(activationPolicy) else {
            AppLogger.lifecycle.error("Could not update the application activation policy")
            return
        }

        AppLogger.lifecycle.info("Updated the application activation policy")
    }

    @MainActor
    func prepareForWindowPresentation() {
        setApplicationActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let apkURLs = urls.filter {
            $0.isFileURL && $0.pathExtension.caseInsensitiveCompare("apk") == .orderedSame
        }
        guard !apkURLs.isEmpty else {
            return
        }

        setApplicationActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let apkDocumentHandler {
            apkDocumentHandler(apkURLs)
        } else {
            pendingAPKDocumentURLs.append(contentsOf: apkURLs)
        }
    }

    func setAPKDocumentHandler(_ handler: @escaping ([URL]) -> Void) {
        apkDocumentHandler = handler
        guard !pendingAPKDocumentURLs.isEmpty else {
            return
        }

        let pendingURLs = pendingAPKDocumentURLs
        pendingAPKDocumentURLs = []
        handler(pendingURLs)
    }
}
