import SwiftUI

struct MainDeviceListView: View {
    let connectedDevices: [AndroidDevice]
    let virtualDevices: [AndroidVirtualDevice]
    let emulatorStatus: EmulatorDiscoveryStatus
    let deviceStore: DeviceStore
    let emulatorStore: EmulatorStore
    let apkInstallationStore: APKInstallationStore
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
                            deviceDetails: deviceStore.deviceDetails(for: device),
                            virtualDevice: runningVirtualDevice(for: device),
                            emulatorWindowPresentation: runningVirtualDevice(for: device).map {
                                emulatorStore.windowPresentation(for: $0)
                            },
                            deviceStore: deviceStore,
                            apkInstallationStore: apkInstallationStore,
                            stopEmulator: {
                                guard let virtualDevice = runningVirtualDevice(for: device) else {
                                    return
                                }
                                emulatorStore.stop(virtualDevice)
                            },
                            revealEmulatorHostWindow: {
                                guard let virtualDevice = runningVirtualDevice(for: device) else {
                                    return
                                }
                                emulatorStore.revealHostWindow(for: virtualDevice)
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
    let deviceDetails: AndroidDeviceDetails?
    let virtualDevice: AndroidVirtualDevice?
    let emulatorWindowPresentation: EmulatorWindowPresentation?
    let deviceStore: DeviceStore
    let apkInstallationStore: APKInstallationStore
    let stopEmulator: () -> Void
    let revealEmulatorHostWindow: () -> Void
    let openLogcat: (AndroidDevice) -> Void

    private let deviceIdentifierClipboard = DeviceIdentifierClipboardService()
    private let virtualDeviceFinderRevealer = AndroidVirtualDeviceFinderRevealService()

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: device.kind.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    DeviceNameWithDetails(
                        name: virtualDevice?.name ?? device.displayName,
                        deviceDetails: deviceDetails
                    )
                    deviceDetail
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard emulatorWindowPresentation?.canRevealHostWindow == true else {
                    return
                }
                revealEmulatorHostWindow()
            }

            if let deviceDetails {
                DeviceInformationButton(deviceDetails: deviceDetails)
            }

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
        .task(id: device) {
            deviceStore.loadDeviceDetails(for: device)
        }
        .apkDropTarget(isEnabled: device.isUsable) { fileURL in
            apkInstallationStore.presentInstaller(for: fileURL, preferredDevice: device)
        }
        .contextMenu {
            Button("Copy Device ID") {
                deviceIdentifierClipboard.copyDeviceIdentifier(device.serial)
            }

            if let virtualDevice {
                Button("Reveal in Finder") {
                    virtualDeviceFinderRevealer.revealVirtualDevice(named: virtualDevice.name)
                }
            }
        }
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

    @ViewBuilder
    private var lifecycleControl: some View {
        if virtualDevice != nil {
            Button(action: stopEmulator) {
                Label("Stop Emulator", systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
                    .frame(
                        width: DeviceListLayout.actionControlContentHeight,
                        height: DeviceListLayout.actionControlContentHeight
                    )
            }
            .frame(
                width: DeviceListLayout.lifecycleControlWidth,
                height: DeviceListLayout.actionControlHeight
            )
            .buttonStyle(.bordered)
            .controlSize(.small)
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

    private let virtualDeviceFinderRevealer = AndroidVirtualDeviceFinderRevealService()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "laptopcomputer")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            DeviceIdentityView(
                name: virtualDevice.name,
                detail: statusDetail,
                deviceDetails: virtualDevice.deviceDetails,
                detailTint: statusTint
            )

            Spacer()

            if let deviceDetails = virtualDevice.deviceDetails {
                DeviceInformationButton(deviceDetails: deviceDetails)
            }

            lifecycleControls
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
        .onTapGesture(count: 2) {
            guard case .stopped = virtualDevice.status else {
                return
            }
            start(.quickBoot)
        }
        .contextMenu {
            Button("Reveal in Finder") {
                virtualDeviceFinderRevealer.revealVirtualDevice(named: virtualDevice.name)
            }
        }
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
                        .frame(
                            width: DeviceListLayout.actionControlContentHeight,
                            height: DeviceListLayout.actionControlContentHeight
                        )
                }
                .frame(
                    width: DeviceListLayout.lifecycleControlWidth,
                    height: DeviceListLayout.actionControlHeight
                )
                .buttonStyle(.bordered)
                .controlSize(.small)
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
    var deviceDetails: AndroidDeviceDetails?
    var detailTint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            DeviceNameWithDetails(name: name, deviceDetails: deviceDetails)
            Text(detail)
                .font(.caption)
                .foregroundStyle(detailTint)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

private struct DeviceNameWithDetails: View {
    let name: String
    let deviceDetails: AndroidDeviceDetails?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(name)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)

            if let deviceDetails {
                Text(deviceDetails.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

private struct DeviceInformationButton: View {
    let deviceDetails: AndroidDeviceDetails

    @State private var isPresentingDeviceInformation = false

    var body: some View {
        Button {
            isPresentingDeviceInformation = true
        } label: {
            Label("Show Device Information", systemImage: "info.circle")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .accessibilityLabel("Show Device Information")
        .help("Show Device Information")
        .popover(isPresented: $isPresentingDeviceInformation) {
            DeviceInformationPopover(deviceDetails: deviceDetails)
        }
    }
}

private struct DeviceInformationPopover: View {
    let deviceDetails: AndroidDeviceDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Device Information")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                if let language = deviceDetails.languageDisplayText {
                    GridRow {
                        Text("Language")
                            .foregroundStyle(.secondary)
                        Text(language)
                    }
                }

                if let screen = deviceDetails.screen {
                    GridRow {
                        Text("Physical pixels")
                            .foregroundStyle(.secondary)
                        Text("\(screen.physicalPixelSize.width) × \(screen.physicalPixelSize.height) px")
                    }

                    GridRow {
                        Text("Logical size")
                            .foregroundStyle(.secondary)
                        Text("\(screen.dpSize.width) × \(screen.dpSize.height) dp")
                    }
                }
            }

            if deviceDetails.screen?.usesDisplayOverride == true {
                Text("Android display overrides are active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(minWidth: 280, alignment: .leading)
    }
}
