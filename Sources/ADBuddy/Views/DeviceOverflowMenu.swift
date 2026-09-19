import SwiftUI

struct DeviceOverflowMenu: View {
    let isPerformingAppAction: Bool
    let isPerformingDeviceSetting: Bool
    let performAppAction: (AndroidAppAction) -> Void
    let requestUninstallForegroundApp: () -> Void
    let performDeviceSetting: (AndroidDeviceSettingAction) -> Void

    var body: some View {
        Menu {
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
            OverflowMenuLabel()
        }
        .modifier(OverflowMenuControlStyle())
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
            OverflowMenuLabel()
        }
        .modifier(OverflowMenuControlStyle())
        .accessibilityLabel("More Emulator Actions")
        .help("More Emulator Actions")
    }
}

private struct OverflowMenuLabel: View {
    var body: some View {
        HStack(spacing: 4.2) {
            Image(systemName: "ellipsis")
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .frame(
            width: DeviceListLayout.actionMenuControlWidth,
            height: DeviceListLayout.actionMenuLabelHeight
        )
    }
}

private struct OverflowMenuControlStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(
                width: DeviceListLayout.actionMenuControlWidth,
                height: DeviceListLayout.actionControlHeight
            )
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 5.5)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: DeviceListLayout.actionMenuLabelHeight)
            }
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
