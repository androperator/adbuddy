import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let preferences: AppPreferences

    var body: some View {
        TabView {
            GeneralSettingsView(preferences: preferences)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ScreenshotSettingsView(preferences: preferences)
                .tabItem {
                    Label("Screenshots", systemImage: "camera")
                }

            EmulatorSettingsView(preferences: preferences)
                .tabItem { Label("Emulators", systemImage: "desktopcomputer") }

            ThemeSettingsView(preferences: preferences)
                .tabItem {
                    Label("Theme", systemImage: "paintpalette")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 580, height: 420)
        .background {
            SettingsWindowTitle(title: "ADBuddy Settings")
                .frame(width: 0, height: 0)
        }
    }
}

private struct GeneralSettingsView: View {
    let preferences: AppPreferences

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section {
                Toggle("Show in Menu Bar", isOn: $preferences.showInMenuBar)
            }

            Section {
                Toggle("Show success banners", isOn: $preferences.showSuccessFeedbackBanners)
            } footer: {
                Text("Shows temporary confirmations for completed actions. Errors are always shown.")
            }
        }
        .formStyle(.grouped)
        .scenePadding()
    }
}

private struct ScreenshotSettingsView: View {
    let preferences: AppPreferences

    @State private var isChoosingMediaDirectory = false

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section {
                LabeledContent("Save location") {
                    HStack(spacing: 12) {
                        Text(preferences.screenshotDirectory.path)
                            .font(.body.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)

                        Button("Choose Folder…") {
                            isChoosingMediaDirectory = true
                        }
                        .fixedSize()
                    }
                }

                Toggle(
                    "Automatically copy saved media to the clipboard",
                    isOn: $preferences.automaticallyCopyMedia
                )

                Toggle(
                    "Reveal saved media in Finder",
                    isOn: $preferences.revealMediaInFinder
                )
            } header: {
                Text("Media")
            } footer: {
                Text("Screenshots and recordings are saved to the same folder.")
            }

            Section {
                Toggle(
                    "Also save a 50% size copy",
                    isOn: $preferences.screenshotAlsoSavesFiftyPercentCopy
                )
            } header: {
                Text("Screenshot Output")
            } footer: {
                Text("Creates an additional PNG at half the dimensions of the final screenshot, including an optional frame and device details.")
            }

            Section {
                Toggle(
                    "Add a device frame to screenshots",
                    isOn: $preferences.screenshotAddsFrame
                )

                Toggle(
                    "Also save the original screenshot",
                    isOn: $preferences.screenshotAlsoSavesOriginal
                )
                .disabled(!preferences.screenshotAddsFrame)

                Toggle(
                    "Add a device frame to screen recordings",
                    isOn: $preferences.screenRecordingAddsFrame
                )
            } header: {
                Text("Device Frame")
            } footer: {
                Text("ADBuddy uses the matching Android SDK emulator frame when available, otherwise a generic black frame. Framed recordings retain the original MP4 alongside the _framed version.")
            }

            Section {
                Toggle(
                    "Overlay device details",
                    isOn: $preferences.screenshotOverlaysDeviceDetails
                )
            } header: {
                Text("Device Details")
            } footer: {
                Text("Adds “Android 16 / API 36” to the top-left of saved screenshots and framed recordings.")
            }
        }
        .formStyle(.grouped)
        .scenePadding()
        .fileImporter(
            isPresented: $isChoosingMediaDirectory,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let directoryURLs) = result,
                  let directoryURL = directoryURLs.first else {
                return
            }

            preferences.screenshotDirectory = directoryURL
            AppLogger.settings.info("Selected a shared media save location")
        }
    }
}

private struct ThemeSettingsView: View {
    let preferences: AppPreferences

    var body: some View {
        Form {
            Section {
                ForEach(LogcatPriority.allCases, id: \.self) { priority in
                    ColorPicker(
                        priority.displayName,
                        selection: Binding(
                            get: { currentLogcatColor(for: priority) },
                            set: { color in
                                guard let components = LogcatColorComponents(color: color) else {
                                    return
                                }
                                preferences.setLogcatColor(components, for: priority)
                            }
                        ),
                        supportsOpacity: false
                    )
                }
            } header: {
                HStack {
                    Text("Logcat Severity Colors")

                    Spacer()

                    Button("Reset to Defaults") {
                        preferences.resetLogcatColors()
                    }
                }
            } footer: {
                Text("These colors appear in Logcat level badges and message emphasis.")
            }
        }
        .formStyle(.grouped)
        .scenePadding()
    }

    private func currentLogcatColor(for priority: LogcatPriority) -> Color {
        preferences.logcatColors[priority]?.color ?? LogcatPriority.defaultColors[priority]!.color
    }
}

private struct EmulatorSettingsView: View {
    @Bindable var preferences: AppPreferences
    @State private var helperStatus = "Checking emulator tools…"
    @State private var diagnosticDetails = ""

    var body: some View {
        Form {
            Section("Node.js") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Node.js 24 or newer is required to create and delete emulators.")
                    Link("Node.js installation instructions", destination: URL(string: "https://nodejs.org/en/download")!)
                    TextField("Node executable path", text: $preferences.emulatorNodePath, prompt: Text("Find automatically"))
                    Text("Leave blank to find Node automatically. If it isn’t found, enter the full path to the node executable.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !preferences.emulatorNodePath.isEmpty {
                        Button("Use Automatic Detection") { preferences.emulatorNodePath = "" }
                    }
                }.padding(.vertical, 4)
            }
            Section("Status") {
                Text(helperStatus).font(.callout)
            }
            Section {
                DisclosureGroup("Advanced") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Java").font(.headline)
                        TextField("Java home folder", text: $preferences.emulatorJavaHome, prompt: Text("Find automatically"))
                        Text("Usually detected from Android Studio or JAVA_HOME. Set a Java installation’s home folder only if automatic detection fails.")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Text("Custom emulator helper").font(.headline)
                        TextField("Helper path", text: $preferences.emulatorHelperPath, prompt: Text("Use ADBuddy’s default"))
                        Text("For developing the emulator helper. Enter a built @androperator/emulator project folder or its dist/cli.js file. Leave blank for normal use.")
                            .font(.caption).foregroundStyle(.secondary)
                        if !diagnosticDetails.isEmpty {
                            Divider()
                            Text("Diagnostics").font(.headline)
                            Text(diagnosticDetails).font(.caption).textSelection(.enabled)
                        }
                    }.padding(.vertical, 8)
                }
            }
        }
        .formStyle(.grouped)
        .scenePadding()
        .task(id: [preferences.emulatorHelperPath, preferences.emulatorNodePath]) {
            helperStatus = "Checking emulator tools…"
            diagnosticDetails = ""
            do {
                let invocation = try EmulatorHelperInvocation.resolve(
                    configuration: preferences.emulatorHelperConfiguration,
                    sdk: AndroidSDK(rootPath: "", adbPath: "", source: .standardLocation))
                let version = try await EmulatorCreationService(invocation: invocation).check()
                guard !Task.isCancelled else { return }
                helperStatus = "Node.js is ready for emulator creation."
                diagnosticDetails = "Helper: \(version.version)\n\(invocation.script)\nNode: \(invocation.node)"
            } catch {
                guard !Task.isCancelled else { return }
                helperStatus = (error as? EmulatorCreationError)?.kind == .nodeRuntime
                    ? "Node.js 24 or newer wasn’t found or couldn’t run. Install Node.js or check the executable path above."
                    : "The emulator helper couldn’t run. See Advanced for details."
                diagnosticDetails = error.localizedDescription
            }
        }
    }
}
