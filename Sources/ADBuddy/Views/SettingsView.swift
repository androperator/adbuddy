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

            ThemeSettingsView(preferences: preferences)
                .tabItem {
                    Label("Theme", systemImage: "paintpalette")
                }
        }
        .frame(width: 580, height: 370)
        .background {
            SettingsWindowTitle(title: "ADBuddy Settings")
                .frame(width: 0, height: 0)
        }
    }
}

private struct GeneralSettingsView: View {
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

private struct ScreenshotSettingsView: View {
    let preferences: AppPreferences

    var body: some View {
        @Bindable var preferences = preferences

        Form {
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
            } header: {
                Text("Device Frame")
            } footer: {
                Text("ADBuddy uses the matching Android SDK emulator frame when available, otherwise a generic black frame.")
            }
        }
        .formStyle(.grouped)
        .scenePadding()
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
