import SwiftUI

struct EmulatorCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @Environment(AppPreferences.self) private var preferences
    @Environment(DeviceStore.self) private var deviceStore
    @Environment(EmulatorStore.self) private var emulatorStore
    @State private var store = EmulatorCreationStore()
    @State private var showsErrorDetails = false

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
        if store.isBusy {
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
                footerStatus
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 60, alignment: .center)
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
            }.frame(height: 60)
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
