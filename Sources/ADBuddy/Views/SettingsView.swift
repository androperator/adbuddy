import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let preferences: AppPreferences
    let setDockIconVisible: (Bool) -> Void

    var body: some View {
        TabView {
            GeneralSettingsView(
                preferences: preferences,
                setDockIconVisible: setDockIconVisible
            )
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ScreenshotSettingsView(preferences: preferences)
                .tabItem {
                    Label("Screenshots", systemImage: "camera")
                }

            ThemeSettingsView(preferences: preferences)
                .tabItem {
                    Label("Theme", systemImage: "paintpalette")
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
    let setDockIconVisible: (Bool) -> Void

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section {
                Toggle("Show in Menu Bar", isOn: $preferences.showInMenuBar)

                Toggle("Show in Dock", isOn: $preferences.showInDock)
                    .onChange(of: preferences.showInDock) { _, isVisible in
                        setDockIconVisible(isVisible)
                    }

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
