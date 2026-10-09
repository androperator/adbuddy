import SwiftUI

struct EmulatorCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @Environment(AppPreferences.self) private var preferences
    @Environment(DeviceStore.self) private var deviceStore
    @Environment(EmulatorStore.self) private var emulatorStore
    @State private var store = EmulatorCreationStore()

    private var existingNames: Set<String> { Set(emulatorStore.virtualDevices.map(\.name)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Create Emulator").font(.title2.weight(.semibold))
            configurationForm
            Divider()
            footer
        }
        .padding(24)
        .frame(width: 600)
        .interactiveDismissDisabled(store.isCreating)
        .task { await load() }
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
                    ForEach(store.availableImages) { Text($0.title).tag($0.id) }
                    if store.availableImages.isEmpty { Text(store.isBusy ? "Loading images…" : "No compatible images").tag("") }
                }.labelsHidden().frame(width: 412)
            }
            GridRow(alignment: .top) {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                imageStatus.frame(height: 42, alignment: .topLeading)
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

    @ViewBuilder private var imageStatus: some View {
        if store.isLoadingCatalog {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking for more images…")
            }.font(.caption).foregroundStyle(.secondary)
        } else if store.catalogError != nil {
            VStack(alignment: .leading, spacing: 4) {
                Text("Couldn’t check for more images. Installed images are available.")
                    .foregroundStyle(.secondary)
                Button("Try Again") { Task { await store.loadDownloadableImages() } }
                    .buttonStyle(.link).disabled(store.isBusy)
            }.font(.caption)
        } else if store.selectedImage?.installed == false {
            Text("This image will be downloaded before the emulator is created.")
                .font(.caption).foregroundStyle(.secondary)
        } else if store.selectedImage != nil {
            Text("Installed and ready to use.").font(.caption).foregroundStyle(.secondary)
        } else if !store.isBusy {
            Text("No compatible images. Choose another device type.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.isReady, !store.isBusy, let message = store.validationMessage(existingNames: existingNames), !store.name.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if let error = store.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.isReady ? "Couldn’t create the emulator." : "Emulator tools need attention.")
                        .foregroundStyle(.red)
                    DisclosureGroup("Details") {
                        ScrollView { Text(error).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            .frame(maxHeight: 90)
                    }
                }
            }
            HStack(spacing: 12) {
                if store.isCreating {
                    ProgressView().controlSize(.small)
                    Text(store.activity).font(.caption).foregroundStyle(.secondary)
                } else if !store.isReady && store.isBusy {
                    ProgressView().controlSize(.small)
                    Text("Loading devices…").font(.caption).foregroundStyle(.secondary)
                } else if !store.isReady {
                    Button("Settings…") { openSettings() }
                    Button("Try Again") { Task { await load() } }
                }
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(store.isCreating)
                HStack(spacing: 4) {
                    Button(store.selectedImage?.installed == false ? "Download, Create & Start" : "Create & Start") {
                        create(startAfterCreation: true)
                    }
                    .keyboardShortcut(.defaultAction)
                    Menu {
                        Button(store.selectedImage?.installed == false ? "Download & Create Only" : "Create Only") {
                            create(startAfterCreation: false)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("More creation options")
                    .help("Create without starting the emulator")
                }
                .disabled(store.isBusy || !store.isReady || store.validationMessage(existingNames: existingNames) != nil)
                .help(store.validationMessage(existingNames: existingNames) ?? "Create emulator")
            }.frame(minHeight: 24)
        }
    }

    private func create(startAfterCreation: Bool) {
        guard !store.isBusy else { return }
        store.startAfterCreation = startAfterCreation
        Task {
            await store.create(existingNames: existingNames) { name, start in
                if let name { emulatorStore.registerCreatedVirtualDevice(name: name, startAfterCreation: start) }
                else { emulatorStore.refreshVirtualDevices() }
            }
        }
    }

    private func load() async {
        await store.load(configuration: preferences.emulatorHelperConfiguration, sdk: deviceStore.resolvedSDK)
    }
}
