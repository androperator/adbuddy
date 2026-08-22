import SwiftUI
import UniformTypeIdentifiers

struct SettingsSheet: View {
    let preferences: AppPreferences

    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingOutputDirectory = false

    var body: some View {
        @Bindable var preferences = preferences

        VStack(spacing: 0) {
            Form {
                LabeledContent("Save location") {
                    HStack(spacing: 8) {
                        Text(preferences.screenshotDirectory.path)
                            .font(.body.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)

                        Button("Choose…") {
                            isChoosingOutputDirectory = true
                        }
                    }
                }

                Text("Screenshots and recordings are saved to this folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(
                    "Automatically copy screenshots to the clipboard",
                    isOn: $preferences.automaticallyCopyScreenshots
                )
            }
            .formStyle(.grouped)
            .padding(.horizontal)
            .padding(.top)

            Divider()

            HStack {
                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: 230)
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
}
