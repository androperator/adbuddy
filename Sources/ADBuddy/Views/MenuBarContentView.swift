import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(DeviceStore.self) private var deviceStore

    var body: some View {
        deviceItems

        Divider()

        Button("Refresh Devices") {
            AppLogger.menuBar.info("Refresh devices selected")
            deviceStore.refresh()
        }
        .disabled(deviceStore.isRefreshing)

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
                    Text(device.connectionState.displayName)
                    Text(device.serial)
                }
            }
        }
    }
}
