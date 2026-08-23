import SwiftUI

struct APKInstallationSheet: View {
    let archive: AndroidPackageArchive
    let devices: [AndroidDevice]
    let installationDevices: [AndroidDevice]
    let deviceDisplayName: (AndroidDevice) -> String
    let preferredDeviceSerial: String?
    let deviceStates: [String: APKInstallationDeviceState]
    let isInstalling: Bool
    let dismiss: () -> Void
    let install: ([AndroidDevice], Bool) -> Void

    @State private var selectedDeviceSerials: Set<String>
    @State private var openAfterInstall = false
    @State private var validationMessage: String?

    init(
        archive: AndroidPackageArchive,
        devices: [AndroidDevice],
        installationDevices: [AndroidDevice],
        deviceDisplayName: @escaping (AndroidDevice) -> String,
        preferredDeviceSerial: String?,
        deviceStates: [String: APKInstallationDeviceState],
        isInstalling: Bool,
        dismiss: @escaping () -> Void,
        install: @escaping ([AndroidDevice], Bool) -> Void
    ) {
        self.archive = archive
        self.devices = devices
        self.installationDevices = installationDevices
        self.deviceDisplayName = deviceDisplayName
        self.preferredDeviceSerial = preferredDeviceSerial
        self.deviceStates = deviceStates
        self.isInstalling = isInstalling
        self.dismiss = dismiss
        self.install = install

        let initialDeviceSerials: Set<String>
        if let preferredDeviceSerial,
           devices.contains(where: { $0.serial == preferredDeviceSerial }) {
            initialDeviceSerials = [preferredDeviceSerial]
        } else {
            initialDeviceSerials = devices.first.map { [$0.serial] } ?? []
        }
        _selectedDeviceSerials = State(initialValue: initialDeviceSerials)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Install APK")
                .font(.title3.weight(.semibold))

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "shippingbox")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(archive.displayName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(archive.fileURL.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Install on")
                    .font(.headline)

                ForEach(devices) { device in
                    Toggle(isOn: selectionBinding(for: device)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(deviceDisplayName(device))
                            Text(device.serial)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(isInstalling)
                }
            }

            Divider()
                .padding(.vertical, 2)

            Toggle("Open after install", isOn: $openAfterInstall)
                .help("Launches the installed app after a successful install when available.")
                .disabled(isInstalling)

            if !deviceStates.isEmpty {
                Divider()
                installationStates
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                if isInstalling {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing APK…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(deviceStates.isEmpty ? "Cancel" : "Done", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isInstalling)

                if deviceStates.isEmpty {
                    Button("Install", action: submit)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isInstalling)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .onChange(of: devices) { _, devices in
            selectedDeviceSerials.formIntersection(Set(devices.map(\.serial)))
            if selectedDeviceSerials.isEmpty,
               let preferredDeviceSerial,
               devices.contains(where: { $0.serial == preferredDeviceSerial }) {
                selectedDeviceSerials = [preferredDeviceSerial]
            }
        }
    }

    private var installationStates: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Installation status")
                .font(.headline)

            ForEach(installationDevices) { device in
                if let state = deviceStates[device.serial] {
                    HStack(alignment: .top, spacing: 8) {
                        statusImage(for: state)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(deviceDisplayName(device))
                                .font(.subheadline.weight(.medium))
                            Text(statusDetail(for: state))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func selectionBinding(for device: AndroidDevice) -> Binding<Bool> {
        Binding(
            get: { selectedDeviceSerials.contains(device.serial) },
            set: { isSelected in
                if isSelected {
                    selectedDeviceSerials.insert(device.serial)
                } else {
                    selectedDeviceSerials.remove(device.serial)
                }
            }
        )
    }

    @ViewBuilder
    private func statusImage(for state: APKInstallationDeviceState) -> some View {
        switch state {
        case .installing:
            ProgressView()
                .controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func statusDetail(for state: APKInstallationDeviceState) -> String {
        switch state {
        case .installing:
            "Installing"
        case .succeeded(let outcome):
            switch outcome.launchResult {
            case .notRequested:
                "Installed"
            case .launched:
                "Installed and opened"
            case .unavailable(let message), .failed(let message):
                message
            }
        case .failed(let message):
            message
        }
    }

    private func submit() {
        let selectedDevices = devices.filter { selectedDeviceSerials.contains($0.serial) }
        guard !selectedDevices.isEmpty else {
            validationMessage = "Select at least one Android device."
            return
        }

        validationMessage = nil
        install(selectedDevices, openAfterInstall)
    }
}
