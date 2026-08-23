import SwiftUI

struct DeviceOverflowMenu: View {
    let isPerformingAppAction: Bool
    let isPerformingDeviceSetting: Bool
    let openEmulatorWindow: (() -> Void)?
    let performAppAction: (AndroidAppAction) -> Void
    let requestUninstallForegroundApp: () -> Void
    let performDeviceSetting: (AndroidDeviceSettingAction) -> Void

    var body: some View {
        Menu {
            if let openEmulatorWindow {
                Button("Open Emulator Window", action: openEmulatorWindow)

                Divider()
            }

            Menu("Foreground App") {
                ForegroundAppActionsMenuContent(
                    perform: performAppAction,
                    requestUninstall: requestUninstallForegroundApp
                )
            }
            .disabled(isPerformingAppAction)

            Menu("Device Settings") {
                DeviceSettingsMenuContent(perform: performDeviceSetting)
            }
            .disabled(isPerformingDeviceSetting)
        } label: {
            Label("More Device Actions", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .frame(
                    width: DeviceListLayout.actionMenuLabelWidth,
                    height: DeviceListLayout.actionMenuLabelHeight
                )
        }
        .frame(
            width: DeviceListLayout.actionControlWidth,
            height: DeviceListLayout.actionControlHeight
        )
        .menuStyle(.borderedButton)
        .controlSize(.small)
        .accessibilityLabel("More Device Actions")
        .help("More Device Actions")
    }
}

struct EmulatorOverflowMenu: View {
    let coldBoot: () -> Void
    let requestWipeDataAndStart: () -> Void

    var body: some View {
        Menu {
            Button("Cold Boot", action: coldBoot)

            Divider()

            Button("Wipe Data and Start…", role: .destructive, action: requestWipeDataAndStart)
        } label: {
            Label("More Emulator Actions", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .frame(
                    width: DeviceListLayout.actionMenuLabelWidth,
                    height: DeviceListLayout.actionMenuLabelHeight
                )
        }
        .frame(
            width: DeviceListLayout.actionControlWidth,
            height: DeviceListLayout.actionControlHeight
        )
        .menuStyle(.borderedButton)
        .controlSize(.small)
        .accessibilityLabel("More Emulator Actions")
        .help("More Emulator Actions")
    }
}

private struct ForegroundAppActionsMenuContent: View {
    let perform: (AndroidAppAction) -> Void
    let requestUninstall: () -> Void

    var body: some View {
        Button("Start Foreground App") {
            perform(.start)
        }
        Button("Kill Foreground App") {
            perform(.forceStop)
        }
        Button("Restart Foreground App") {
            perform(.restart)
        }

        Divider()

        Button("Clear Foreground App Data") {
            perform(.clearData)
        }
        Button("Clear App Data and Restart") {
            perform(.clearDataAndRestart)
        }

        Divider()

        Button("Uninstall Foreground App…", role: .destructive, action: requestUninstall)
    }
}
