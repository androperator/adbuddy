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
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Emulator").font(.title2.weight(.semibold))
            Text("Choose a device and Android image. Existing emulators are never replaced.")
                .foregroundStyle(.secondary)

            if let created = store.createdName {
                Label("Created \(created)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(store.startAfterCreation ? "Start requested. The emulator will appear in the device list as it boots." : "Your emulator is ready in the Android Emulators list.")
            } else if !store.profiles.isEmpty {
                configurationForm
            } else if !store.isBusy {
                Text("Creation requires Node.js 24+, Android SDK command-line tools, and the optional emulator package with catalog support.")
                Text("npm install -g @androperator/emulator")
                    .font(.body.monospaced()).textSelection(.enabled)
                Text("For this prototype, use the built sibling emulator checkout. Configure other helper, Node or Java locations in Settings → Emulators.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let error = store.errorMessage {
                ScrollView { Text(error).foregroundStyle(.red).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 100)
            }
            if store.isBusy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(store.activity).font(.callout)
                }
                Text("Keep ADBuddy open until the operation finishes.").font(.caption).foregroundStyle(.secondary)
            }
            if let helper = store.helperDescription {
                Text(helper).font(.caption2).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
            }
            HStack {
                Button("Settings…") { openSettings() }.disabled(store.isBusy)
                if store.createdName == nil {
                    Button("Reload") { Task { await load() } }.disabled(store.isBusy)
                }
                Spacer()
                Button(store.createdName == nil ? "Cancel" : "Done") { dismiss() }
                    .keyboardShortcut(.cancelAction).disabled(store.isBusy)
                if store.createdName == nil {
                    Button(store.selectedImage?.installed == false ? "Download & Create" : "Create") {
                        Task { await store.create(existingNames: existingNames) { name, start in
                            if let name { emulatorStore.registerCreatedVirtualDevice(name: name, startAfterCreation: start) }
                            else { emulatorStore.refreshVirtualDevices() }
                        } }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.isBusy || store.validationMessage(existingNames: existingNames) != nil || store.helperDescription == nil)
                }
            }
        }
        .padding(24)
        .frame(width: 620)
        .interactiveDismissDisabled(store.isBusy)
        .task { await load() }
    }

    private var configurationForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Picker("Hardware type", selection: $store.hardwareType) {
                    ForEach(store.availableHardwareTypes) { type in Text(type.rawValue).tag(type) }
                }
                .onChange(of: store.hardwareType) { _, _ in store.selectHardwareType() }
                Picker("Hardware", selection: $store.profileID) {
                    ForEach(store.availableProfiles) { profile in Text(profile.name).tag(profile.id) }
                }
                .onChange(of: store.profileID) { _, _ in store.selectProfile() }
                Picker("Android image", selection: $store.imageID) {
                    if store.availableImages.isEmpty { Text("No matching images").tag("") }
                    ForEach(store.availableImages) { image in Text(image.title).tag(image.id) }
                }
                TextField("Name", text: $store.name)
                TextField("Maximum internal storage (GB)", text: $store.storageGB)
                Toggle("Start after creation", isOn: $store.startAfterCreation)
            }
            .disabled(store.isBusy)
            if !store.includesDownloads {
                Button("Browse Downloadable Images…") { Task { await store.loadDownloadableImages() } }
                    .disabled(store.isBusy)
            }
            if store.availableImages.isEmpty {
                Text("No matching \(EmulatorImageSelection.hostABI) image is available for this profile. Try downloadable images or another profile.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if store.selectedImage?.installed == false {
                Text("The image will be downloaded into your Android SDK. SDK licenses must already be accepted; this prototype does not accept licenses automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Disk space is used as needed, rather than reserved upfront.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = store.validationMessage(existingNames: existingNames), !store.name.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        await store.load(configuration: preferences.emulatorHelperConfiguration, sdk: deviceStore.resolvedSDK)
    }
}
