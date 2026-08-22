import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(DeviceStore.self) private var deviceStore
    private let showSettings: () -> Void

    init(showSettings: @escaping () -> Void) {
        self.showSettings = showSettings
    }

    var body: some View {
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

        Divider()

        deviceItems

        Divider()

        Button("Settings…") {
            AppLogger.settings.info("Settings requested from the menu bar")
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            showSettings()
        }

        Button("Open ADBuddy") {
            AppLogger.menuBar.info("Open main window selected")
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit ADBuddy") {
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
                                openWindow(id: "main")
                                NSApp.activate(ignoringOtherApps: true)
                                deviceStore.presentScreenRecordingOptions(for: device)
                            }
                            .disabled(!deviceStore.canStartScreenRecording(for: device))
                        }

                        Button("Open Logcat") {
                            AppLogger.menuBar.info("Logcat selected from menu bar")
                            openWindow(value: LogcatWindowID(serial: device.serial))
                            NSApp.activate(ignoringOtherApps: true)
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
                                openWindow(id: "main")
                                NSApp.activate(ignoringOtherApps: true)
                                deviceStore.requestUninstallForegroundApp(for: device)
                            }
                        }
                        .disabled(deviceStore.isPerformingAppAction(for: device))
                    } else {
                        Text(device.connectionState.displayName)
                    }

                    Text(device.serial)
                }
            }
        }
    }
}
