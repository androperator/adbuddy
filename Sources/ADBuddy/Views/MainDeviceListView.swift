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
                        title: "No Android devices connected",
                        systemImage: "cable.connector.slash"
                    )
                } else {
                    ForEach(connectedDevices) { device in
                        ConnectedDeviceRow(
                            device: device,
                            virtualDevice: runningVirtualDevice(for: device),
                            emulatorWindowPresentation: runningVirtualDevice(for: device).map {
                                emulatorStore.windowPresentation(for: $0)
                            },
                            deviceStore: deviceStore,
                            stopEmulator: {
                                guard let virtualDevice = runningVirtualDevice(for: device) else {
                                    return
                                }
                                emulatorStore.stop(virtualDevice)
                            },
                            showEmulatorWindow: {
                                guard let virtualDevice = runningVirtualDevice(for: device) else {
                                    return
                                }
                                emulatorStore.openStandaloneWindow(for: virtualDevice)
                            },
                            openLogcat: openLogcat
                        )
                    }
                }
            } header: {
                Text("Connected Android Devices")
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
            if availableVirtualDevices.isEmpty {
                EmptyDeviceSectionRow(
                    title: virtualDevices.isEmpty
                        ? "No Android Virtual Devices"
                        : "All installed emulators are connected",
                    systemImage: "laptopcomputer.slash"
                )
            } else {
                ForEach(availableVirtualDevices) { virtualDevice in
                    VirtualDeviceRow(
                        virtualDevice: virtualDevice,
                        start: { mode in
                            emulatorStore.start(virtualDevice, mode: mode)
                        },
                        requestWipeDataAndStart: {
                            emulatorStore.requestWipeDataAndStart(virtualDevice)
                        }
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
            virtualDeviceCount: displayedVirtualDeviceCount
        )
    }

    private var displayedVirtualDeviceCount: Int {
        guard case .ready = emulatorStatus else {
            return 0
        }
        return availableVirtualDevices.count
    }

    private var availableVirtualDevices: [AndroidVirtualDevice] {
        virtualDevices.filter {
            if case .running = $0.status {
                return false
            }
            return true
        }
    }

    private func runningVirtualDevice(for device: AndroidDevice) -> AndroidVirtualDevice? {
        virtualDevices.first {
            guard case .running(let runningDevice) = $0.status else {
                return false
            }
            return runningDevice.serial == device.serial
        }
    }
}

private struct ConnectedDeviceRow: View {
    let device: AndroidDevice
    let virtualDevice: AndroidVirtualDevice?
    let emulatorWindowPresentation: EmulatorWindowPresentation?
    let deviceStore: DeviceStore
    let stopEmulator: () -> Void
    let showEmulatorWindow: () -> Void
    let openLogcat: (AndroidDevice) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.kind.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(virtualDevice?.name ?? device.displayName)
                    .fontWeight(.medium)
                deviceDetail
            }

            Spacer()

            if device.isUsable {
                HStack(spacing: 8) {
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

                    DeviceOverflowMenu(
                        isPerformingAppAction: deviceStore.isPerformingAppAction(for: device),
                        isPerformingDeviceSetting: deviceStore.isPerformingDeviceSetting(for: device),
                        openEmulatorWindow: openEmulatorWindow,
                        performAppAction: { deviceStore.performAppAction($0, for: device) },
                        requestUninstallForegroundApp: {
                            deviceStore.requestUninstallForegroundApp(for: device)
                        },
                        performDeviceSetting: { deviceStore.performDeviceSetting($0, for: device) }
                    )

                    lifecycleControl
                }
            } else {
                Text(device.connectionState.displayName)
                    .font(.caption)
                    .foregroundStyle(device.connectionState.tint)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var deviceDetail: some View {
        HStack(spacing: 4) {
            Text(device.serial)
                .foregroundStyle(.secondary)

            if let emulatorWindowPresentation {
                Text("·")
                    .foregroundStyle(.secondary)

                Text(emulatorWindowPresentation.detail)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var openEmulatorWindow: (() -> Void)? {
        guard case .standalone = emulatorWindowPresentation else {
            return nil
        }
        return showEmulatorWindow
    }

    @ViewBuilder
    private var lifecycleControl: some View {
        if virtualDevice != nil {
            Button(action: stopEmulator) {
                Label("Stop Emulator", systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
            }
            .frame(
                width: DeviceListLayout.lifecycleControlWidth,
                height: DeviceListLayout.actionControlHeight
            )
            .buttonStyle(.bordered)
            .tint(.red)
            .help("Stop Emulator")
        } else {
            Color.clear
                .frame(
                    width: DeviceListLayout.lifecycleControlWidth,
                    height: DeviceListLayout.actionControlHeight
                )
                .accessibilityHidden(true)
        }
    }
}

private struct VirtualDeviceRow: View {
    let virtualDevice: AndroidVirtualDevice
    let start: (AndroidEmulatorStartMode) -> Void
    let requestWipeDataAndStart: () -> Void

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
            HStack(spacing: 8) {
                EmulatorOverflowMenu(
                    coldBoot: { start(.coldBoot) },
                    requestWipeDataAndStart: requestWipeDataAndStart
                )

                Button {
                    start(.quickBoot)
                } label: {
                    Label("Start Emulator", systemImage: "play.fill")
                        .labelStyle(.iconOnly)
                }
                .frame(
                    width: DeviceListLayout.lifecycleControlWidth,
                    height: DeviceListLayout.actionControlHeight
                )
                .buttonStyle(.bordered)
                .help("Start Emulator (Quick Boot)")
            }
        case .starting:
            ProgressView()
                .controlSize(.small)
                .help("Starting Emulator")
        case .running:
            EmptyView()
        case .stopping:
            ProgressView()
                .controlSize(.small)
                .help("Stopping Emulator")
        }
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
                .lineLimit(1)
                .truncationMode(.tail)
            Text(detail)
                .font(.caption)
                .foregroundStyle(detailTint)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
