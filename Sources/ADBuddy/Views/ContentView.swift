import SwiftUI

struct ContentView: View {
    @Environment(DeviceStore.self) private var deviceStore

    var body: some View {
        VStack(spacing: 0) {
            statusSummary

            Divider()

            deviceContent
        }
        .navigationTitle("ADBuddy")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    AppLogger.devices.info("Refresh button selected")
                    deviceStore.refresh()
                } label: {
                    Label("Refresh Devices", systemImage: "arrow.clockwise")
                }
                .disabled(deviceStore.isRefreshing)
            }
        }
    }

    private var statusSummary: some View {
        HStack(spacing: 10) {
            Image(systemName: deviceStore.status.symbolName)
                .foregroundStyle(deviceStore.status.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(deviceStore.status.title)
                    .font(.headline)
                Text(deviceStore.status.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if deviceStore.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var deviceContent: some View {
        switch deviceStore.status {
        case .loading:
            ContentUnavailableView(
                "Refreshing Devices",
                systemImage: "arrow.triangle.2.circlepath",
                description: Text("Checking the Android SDK and connected devices.")
            )
        case .sdkUnavailable, .adbFailure, .noDevices:
            ContentUnavailableView {
                Label(deviceStore.status.title, systemImage: deviceStore.status.symbolName)
            } description: {
                Text(deviceStore.status.detail)
            } actions: {
                Button("Refresh Devices") {
                    deviceStore.refresh()
                }
            }
        case .devicesAvailable:
            List(deviceStore.devices) { device in
                DeviceRow(device: device)
            }
            .listStyle(.inset)
        }
    }
}

private struct DeviceRow: View {
    let device: AndroidDevice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.kind.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .fontWeight(.medium)
                Text(device.serial)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(device.connectionState.displayName)
                .font(.caption)
                .foregroundStyle(device.connectionState.tint)
        }
        .padding(.vertical, 2)
    }
}
