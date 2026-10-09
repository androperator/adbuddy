import AppKit
import SwiftUI

struct MenuBarContentView: View {
    let prepareForWindowPresentation: () -> Void

    @Environment(\.openWindow) private var openWindow
    @Environment(DeviceStore.self) private var deviceStore
    @Environment(AppPreferences.self) private var preferences
    @Environment(APKInstallationStore.self) private var apkInstallationStore

    var body: some View {
        @Bindable var preferences = preferences

        if let recordingDevice = deviceStore.activeScreenRecordingDevice {
            Button("Stop Recording") {
                AppLogger.menuBar.info("Stop recording selected from menu bar")
                deviceStore.stopScreenRecording(for: recordingDevice)
            }

            Divider()
        }

        Menu("Open Android Emulator") {
            EmulatorMenuContent()
        }

        if preferences.isDeepLinkLauncherEnabled {
            Button("Open Link…") {
                AppLogger.menuBar.info("Deep link launcher selected from menu bar")
                presentMainWindow()
                deviceStore.presentDeepLinkLauncher()
            }
            .disabled(!deviceStore.devices.contains(where: \.isUsable))
        }

        Button("Install APK…") {
            presentMainWindow()
            guard let fileURL = APKFilePicker.chooseAPK() else {
                return
            }
            apkInstallationStore.presentInstaller(for: fileURL)
        }
        .disabled(!deviceStore.devices.contains(where: \.isUsable))

        Divider()

        deviceItems

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Toggle("Show in Menu Bar", isOn: $preferences.showInMenuBar)

        Button("Open ADBuddy") {
            AppLogger.menuBar.info("Open main window selected")
            presentMainWindow()
        }

        Divider()

        Button("Quit") {
            AppLogger.menuBar.info("Quit selected")
            NSApplication.shared.terminate(nil)
        }
    }

    @ViewBuilder
    private var deviceItems: some View {
        switch deviceStore.status {
        case .loading:
            Text("Refreshing devices")
        case .sdkUnavailable, .adbFailure, .noDevices:
            Text(deviceStore.status.title)
        case .devicesAvailable:
            ForEach(deviceStore.devices) { device in
                Menu(device.menuTitle) {
                    if device.isUsable {
                        if device.kind == .physical {
                            Button(deviceStore.mirrors.activeSerials.contains(device.serial)
                                   ? "Show Device Mirror" : "Mirror Device") {
                                deviceStore.mirrorDevice(device)
                            }
                        }

                        Button("Take Screenshot") {
                            AppLogger.menuBar.info("Screenshot selected from menu bar")
                            deviceStore.takeScreenshot(of: device)
                        }
                        .disabled(deviceStore.isCapturingScreenshot(for: device))

                        if deviceStore.canStopScreenRecording(for: device) {
                            Button("Stop Recording") {
                                deviceStore.stopScreenRecording(for: device)
                            }
                        } else if !deviceStore.isPreparingScreenRecording(for: device),
                                  !deviceStore.isStoppingScreenRecording(for: device) {
                            Button("Record Screen…") {
                                AppLogger.menuBar.info("Screen recording selected from menu bar")
                                presentMainWindow()
                                deviceStore.presentScreenRecordingOptions(for: device)
                            }
                            .disabled(!deviceStore.canStartScreenRecording(for: device))
                        }

                        Button("Open Logcat") {
                            AppLogger.menuBar.info("Logcat selected from menu bar")
                            prepareForWindowPresentation()
                            openWindow(value: LogcatWindowID(serial: device.serial))
                        }

                        Menu("Foreground App") {
                            Button("Start App") {
                                deviceStore.performAppAction(.start, for: device)
                            }
                            Button("Kill App") {
                                deviceStore.performAppAction(.forceStop, for: device)
                            }
                            Button("Restart App") {
                                deviceStore.performAppAction(.restart, for: device)
                            }

                            Divider()

                            Button("Clear App Data") {
                                deviceStore.performAppAction(.clearData, for: device)
                            }
                            Button("Clear App Data and Restart") {
                                deviceStore.performAppAction(.clearDataAndRestart, for: device)
                            }

                            Divider()

                            Button("Uninstall App…", role: .destructive) {
                                presentMainWindow()
                                deviceStore.requestUninstallForegroundApp(for: device)
                            }
                        }
                        .disabled(deviceStore.isPerformingAppAction(for: device))

                        Button("Toggle Dark Theme") {
                            deviceStore.performDeviceSetting(.toggleDarkTheme, for: device)
                        }
                        .disabled(deviceStore.isPerformingDeviceSetting(for: device))

                        Menu("Device Settings") {
                            DeviceSettingsMenuContent { action in
                                deviceStore.performDeviceSetting(action, for: device)
                            }
                        }
                        .disabled(deviceStore.isPerformingDeviceSetting(for: device))
                    } else {
                        Text(device.connectionState.displayName)
                    }

                    Text(device.serial)
                }
            }
        }
    }

    private func presentMainWindow() {
        prepareForWindowPresentation()
        guard MainWindowController.shared.prepareToPresent() else {
            return
        }
        openWindow(id: "main")
    }
}
