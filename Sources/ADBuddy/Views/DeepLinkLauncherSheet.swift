import SwiftUI

struct DeepLinkLauncherSheet: View {
    let devices: [AndroidDevice]
    let preferredDeviceSerial: String?
    let isLaunching: Bool
    let dismiss: () -> Void
    let launch: (AndroidDeepLink, AndroidDevice) -> Void

    @FocusState private var isURIFocused: Bool
    @State private var uri = ""
    @State private var targetPackageID = ""
    @State private var selectedDeviceSerial: String
    @State private var validationMessage: String?

    init(
        devices: [AndroidDevice],
        preferredDeviceSerial: String?,
        isLaunching: Bool,
        dismiss: @escaping () -> Void,
        launch: @escaping (AndroidDeepLink, AndroidDevice) -> Void
    ) {
        self.devices = devices
        self.preferredDeviceSerial = preferredDeviceSerial
        self.isLaunching = isLaunching
        self.dismiss = dismiss
        self.launch = launch
        let initialDeviceSerial: String
        if let preferredDeviceSerial,
           devices.contains(where: { $0.serial == preferredDeviceSerial }) {
            initialDeviceSerial = preferredDeviceSerial
        } else {
            initialDeviceSerial = devices.first?.serial ?? ""
        }
        _selectedDeviceSerial = State(initialValue: initialDeviceSerial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Open Link")
                .font(.title3.weight(.semibold))

            Text("Open a URI on a connected Android device.")
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("URI")
                        .frame(width: 104, alignment: .trailing)
                    TextField("https://example.com", text: $uri)
                        .textFieldStyle(.roundedBorder)
                        .focused($isURIFocused)
                }

                GridRow {
                    Text("Device")
                        .frame(width: 104, alignment: .trailing)
                    Picker("Device", selection: $selectedDeviceSerial) {
                        ForEach(devices) { device in
                            Text(device.menuTitle)
                                .tag(device.serial)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GridRow {
                    Text("Target package")
                        .frame(width: 104, alignment: .trailing)
                    TextField("Optional", text: $targetPackageID)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text("Leave Target package blank to use Android’s default handler. For Chrome, use com.android.chrome.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                if isLaunching {
                    ProgressView()
                        .controlSize(.small)
                    Text("Opening link…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isLaunching)

                Button("Open", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isLaunching || selectedDevice == nil)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear {
            isURIFocused = true
        }
        .onChange(of: devices) { _, devices in
            guard !devices.contains(where: { $0.serial == selectedDeviceSerial }) else {
                return
            }
            if let preferredDeviceSerial,
               devices.contains(where: { $0.serial == preferredDeviceSerial }) {
                selectedDeviceSerial = preferredDeviceSerial
            } else {
                selectedDeviceSerial = devices.first?.serial ?? ""
            }
        }
    }

    private var selectedDevice: AndroidDevice? {
        devices.first { $0.serial == selectedDeviceSerial }
    }

    private func submit() {
        guard let deepLink = AndroidDeepLink(uri: uri, targetPackageID: targetPackageID) else {
            validationMessage = "Enter a complete URI with no spaces."
            return
        }
        guard let selectedDevice else {
            validationMessage = "Select a connected Android device."
            return
        }

        validationMessage = nil
        launch(deepLink, selectedDevice)
    }
}
