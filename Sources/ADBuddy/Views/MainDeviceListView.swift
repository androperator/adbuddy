import SwiftUI

struct MainDeviceListView: View {
    let connectedDevices: [AndroidDevice]
    let virtualDevices: [AndroidVirtualDevice]
    let emulatorStatus: EmulatorDiscoveryStatus
    let deviceStore: DeviceStore
    let emulatorStore: EmulatorStore
    let openLogcat: (AndroidDevice) -> Void

    var body: some View {
        List {
            Section {
                if connectedDevices.isEmpty {
                    EmptyDeviceSectionRow(
                        title: "No physical devices connected",
                        systemImage: "cable.connector.slash"
                    )
                } else {
                    ForEach(connectedDevices) { device in
                        ConnectedDeviceRow(
                            device: device,
                            deviceStore: deviceStore,
                            openLogcat: openLogcat
                        )
                    }
                }
            } header: {
                Text("Connected Devices")
                    .textCase(nil)
            }

            Section {
                emulatorContent
            } header: {
                Text("Android Emulators")
                    .textCase(nil)
            }
        }
        .listStyle(.inset)
        .frame(height: listHeight)
    }

    @ViewBuilder
    private var emulatorContent: some View {
        switch emulatorStatus {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading installed emulators")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        case .ready:
            if virtualDevices.isEmpty {
                EmptyDeviceSectionRow(
                    title: "No Android Virtual Devices",
                    systemImage: "laptopcomputer.slash"
                )
            } else {
                ForEach(virtualDevices) { virtualDevice in
                    VirtualDeviceRow(
                        virtualDevice: virtualDevice,
                        deviceStore: deviceStore,
                        start: { mode in
                            emulatorStore.start(virtualDevice, mode: mode)
                        },
                        stop: {
                            emulatorStore.stop(virtualDevice)
                        },
                        requestWipeDataAndStart: {
                            emulatorStore.requestWipeDataAndStart(virtualDevice)
                        },
                        openLogcat: openLogcat
                    )
                }
            }
        case .unavailable(let failure):
            EmptyDeviceSectionRow(
                title: failure.title,
                systemImage: "exclamationmark.triangle"
            )
        }
    }

    private var listHeight: CGFloat {
        DeviceListLayout.sectionedListHeight(
            connectedDeviceCount: connectedDevices.count,
            virtualDeviceCount: virtualDevices.count
        )
    }
}

private struct ConnectedDeviceRow: View {
    let device: AndroidDevice
    let deviceStore: DeviceStore
    let openLogcat: (AndroidDevice) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.kind.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            DeviceIdentityView(
                name: device.displayName,
                detail: device.serial
            )

            Spacer()

            if device.isUsable {
                DeviceActionControls(
                    isCapturing: deviceStore.isCapturingScreenshot(for: device),
                    isPreparingScreenRecording: deviceStore.isPreparingScreenRecording(for: device),
                    isScreenRecording: deviceStore.canStopScreenRecording(for: device),
                    isStoppingScreenRecording: deviceStore.isStoppingScreenRecording(for: device),
                    canStartScreenRecording: deviceStore.canStartScreenRecording(for: device),
                    takeScreenshot: { deviceStore.takeScreenshot(of: device) },
                    showScreenRecordingOptions: { deviceStore.presentScreenRecordingOptions(for: device) },
                    stopScreenRecording: { deviceStore.stopScreenRecording(for: device) },
                    openLogcat: { openLogcat(device) }
                )
            } else {
                Text(device.connectionState.displayName)
                    .font(.caption)
                    .foregroundStyle(device.connectionState.tint)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct VirtualDeviceRow: View {
    let virtualDevice: AndroidVirtualDevice
    let deviceStore: DeviceStore
    let start: (AndroidEmulatorStartMode) -> Void
    let stop: () -> Void
    let requestWipeDataAndStart: () -> Void
    let openLogcat: (AndroidDevice) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "laptopcomputer")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            DeviceIdentityView(
                name: virtualDevice.name,
                detail: statusDetail,
                detailTint: statusTint
            )

            Spacer()

            lifecycleControls
        }
        .padding(.vertical, 2)
    }

    private var statusDetail: String {
        switch virtualDevice.status {
        case .stopped:
            "Stopped"
        case .starting:
            "Starting"
        case .running(let device):
            "Running · \(device.serial)"
        case .stopping(let device):
            "Stopping · \(device.serial)"
        }
    }

    private var statusTint: Color {
        switch virtualDevice.status {
        case .stopped:
            .secondary
        case .starting, .stopping:
            .orange
        case .running:
            .green
        }
    }

    @ViewBuilder
    private var lifecycleControls: some View {
        switch virtualDevice.status {
        case .stopped:
            Button {
                start(.quickBoot)
            } label: {
                Label("Start Emulator", systemImage: "play.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderedProminent)
            .help("Start Emulator (Quick Boot)")

            actionsMenu
        case .starting:
            ProgressView()
                .controlSize(.small)
                .help("Starting Emulator")
        case .running(let device):
            Button(action: stop) {
                Label("Stop Emulator", systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .help("Stop Emulator")

            DeviceActionControls(
                isCapturing: deviceStore.isCapturingScreenshot(for: device),
                isPreparingScreenRecording: deviceStore.isPreparingScreenRecording(for: device),
                isScreenRecording: deviceStore.canStopScreenRecording(for: device),
                isStoppingScreenRecording: deviceStore.isStoppingScreenRecording(for: device),
                canStartScreenRecording: deviceStore.canStartScreenRecording(for: device),
                takeScreenshot: { deviceStore.takeScreenshot(of: device) },
                showScreenRecordingOptions: { deviceStore.presentScreenRecordingOptions(for: device) },
                stopScreenRecording: { deviceStore.stopScreenRecording(for: device) },
                openLogcat: { openLogcat(device) }
            )
        case .stopping:
            ProgressView()
                .controlSize(.small)
                .help("Stopping Emulator")
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button("Start (Quick Boot)") {
                start(.quickBoot)
            }
            Button("Cold Boot") {
                start(.coldBoot)
            }

            Divider()

            Button("Wipe Data and Start…", role: .destructive) {
                requestWipeDataAndStart()
            }
        } label: {
            Label("Emulator Actions", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
        .help("Emulator Actions")
    }
}

private struct EmptyDeviceSectionRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }
}

private struct DeviceIdentityView: View {
    let name: String
    let detail: String
    var detailTint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .fontWeight(.medium)
            Text(detail)
                .font(.caption)
                .foregroundStyle(detailTint)
        }
    }
}
