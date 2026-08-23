import SwiftUI
import UniformTypeIdentifiers

struct SettingsSheet: View {
    let preferences: AppPreferences

    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingOutputDirectory = false

    var body: some View {
        @Bindable var preferences = preferences

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Save location")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Text(preferences.screenshotDirectory.path)
                            .font(.body.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)

                        Button("Choose…") {
                            isChoosingOutputDirectory = true
                        }
                        .fixedSize()
                    }

                    Text("Screenshots and recordings are saved to this folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(
                    "Automatically copy media to clipboard",
                    isOn: $preferences.automaticallyCopyMedia
                )

                Toggle(
                    "Reveal media in Finder",
                    isOn: $preferences.revealMediaInFinder
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Logcat colors")
                            .font(.headline)

                        Spacer()

                        Button("Reset to Defaults") {
                            preferences.resetLogcatColors()
                        }
                    }

                    Grid(horizontalSpacing: 24, verticalSpacing: 8) {
                        GridRow {
                            colorPicker(for: .verbose)
                            colorPicker(for: .debug)
                        }
                        GridRow {
                            colorPicker(for: .info)
                            colorPicker(for: .warn)
                        }
                        GridRow {
                            colorPicker(for: .error)
                            colorPicker(for: .assert)
                        }
                    }

                    Text("Used for Logcat level badges and message emphasis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)

            Divider()

            HStack {
                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(
            isPresented: $isChoosingOutputDirectory,
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

    private func colorPicker(for priority: LogcatPriority) -> some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func currentLogcatColor(for priority: LogcatPriority) -> Color {
        preferences.logcatColors[priority]?.color ?? LogcatPriority.defaultColors[priority]!.color
    }
}
