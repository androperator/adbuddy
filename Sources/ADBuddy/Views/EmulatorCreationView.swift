import SwiftUI

struct EmulatorCreationView: View {
    let dismiss: () -> Void
    let creationStateChanged: (Bool) -> Void
    @Environment(\.openSettings) private var openSettings
    @Environment(AppPreferences.self) private var preferences
    @Environment(DeviceStore.self) private var deviceStore
    @Environment(EmulatorStore.self) private var emulatorStore
    @State var store: EmulatorCreationStore
    @State private var showsErrorDetails = false
    @FocusState private var isDeviceTypeFocused: Bool
    @State private var hasSetInitialFocus = false

    private var existingNames: Set<String> { Set(emulatorStore.virtualDevices.map(\.name)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            configurationForm
                .opacity(store.isReady ? 1 : 0)
                .allowsHitTesting(store.isReady)
                .accessibilityHidden(!store.isReady)
                .overlay {
                    if !store.isReady {
                        if store.errorMessage == nil {
                            ProgressView("Loading emulator options…")
                        } else {
                            Text("Emulator options couldn’t be loaded.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            Divider()
            footer
        }
        .padding(24)
        .frame(width: 600)
        .onChange(of: store.isCreating) { _, creating in creationStateChanged(creating) }
        .onExitCommand {
            if !store.isCreating { dismiss() }
        }
        .task { await load() }
        .onChange(of: store.isReady) { _, ready in
            guard ready, !hasSetInitialFocus else { return }
            hasSetInitialFocus = true
            isDeviceTypeFocused = true
        }
        .onChange(of: store.createdName) { _, name in
            if name != nil { dismiss() }
        }
    }

    private var configurationForm: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                fieldLabel("Device type")
                Picker("Device type", selection: $store.hardwareType) {
                    ForEach(store.availableHardwareTypes) { Text($0.rawValue).tag($0) }
                    if store.profiles.isEmpty { Text("Loading devices…").tag(store.hardwareType) }
                }
                .labelsHidden().frame(width: 412)
                .focused($isDeviceTypeFocused)
                .onChange(of: store.hardwareType) { _, _ in store.selectHardwareType() }
            }
            GridRow {
                fieldLabel("Device")
                Picker("Device", selection: $store.profileID) {
                    ForEach(store.availableProfiles) { Text($0.name).tag($0.id) }
                    if store.availableProfiles.isEmpty { Text("Choose a device").tag("") }
                }
                .labelsHidden().frame(width: 412)
                .onChange(of: store.profileID) { _, _ in store.selectProfile() }
            }
            GridRow {
                fieldLabel("Android image")
                Picker("Android image", selection: $store.imageID) {
                    ForEach(store.availableImages) { image in
                        Label(image.title, systemImage: image.installed ? "internaldrive" : "arrow.down.circle")
                            .accessibilityLabel("\(image.title), \(image.installed ? "Installed" : "Download required")")
                            .tag(image.id)
                    }
                    if store.availableImages.isEmpty { Text(store.isLoadingCatalog ? "Loading images…" : "No compatible images").tag("") }
                }.labelsHidden().frame(width: 412)
            }
            GridRow {
                fieldLabel("Name")
                TextField("Name", text: $store.name).labelsHidden()
            }
            GridRow {
                fieldLabel("Maximum storage")
                HStack {
                    TextField("Maximum internal storage", text: $store.storageGB)
                        .frame(width: 70)
                    Text("GB").foregroundStyle(.secondary)
                    Spacer()
                }
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Text("Disk space is used as needed, rather than reserved upfront.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .disabled(!store.isReady || store.isCreating)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).frame(width: 124, alignment: .trailing)
    }

    @ViewBuilder private var footerStatus: some View {
        if store.isCreating {
            HStack(alignment: .top, spacing: 8) {
                ProgressView().controlSize(.small)
                Text(store.activity)
            }
        } else if store.errorMessage != nil {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.isReady ? "Couldn’t create emulator." : "Emulator tools need attention.")
                HStack {
                    Button("Details") { showsErrorDetails = true }
                        .popover(isPresented: $showsErrorDetails) {
                            ScrollView {
                                Text(store.errorMessage ?? "").textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.padding().frame(width: 360, height: 180)
                        }
                    if !store.isReady {
                        Button("Settings…") { openSettings() }
                        Button("Retry") { Task { await load() } }
                    }
                }.buttonStyle(.link)
            }
        } else if store.catalogError != nil {
            VStack(alignment: .leading, spacing: 4) {
                Text("Couldn’t load more images.")
                Button("Retry") { Task { await store.loadDownloadableImages() } }.buttonStyle(.link)
            }
        } else if let message = store.validationMessage(existingNames: existingNames), store.isReady {
            Text(message)
        }
    }

    private var footer: some View {
            HStack(spacing: 12) {
                ZStack(alignment: .leading) {
                    Color.clear
                    footerStatus
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                if store.isReady || store.errorMessage != nil {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(store.isCreating)
                    Button("Create") {
                        create()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.isBusy || !store.isReady || store.validationMessage(existingNames: existingNames) != nil)
                    .help(store.validationMessage(existingNames: existingNames) ?? "Create emulator")
                }
            }.frame(height: 36)
    }

    private func create() {
        guard !store.isBusy else { return }
        Task {
            await store.create(existingNames: existingNames) { name in
                if let name { emulatorStore.registerCreatedVirtualDevice(name: name) }
                else { emulatorStore.refreshVirtualDevices() }
            }
        }
    }

    private func load() async {
        await store.load(configuration: preferences.emulatorHelperConfiguration, sdk: deviceStore.resolvedSDK)
    }
}
