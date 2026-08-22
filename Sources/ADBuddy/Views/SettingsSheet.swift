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
                    "Automatically copy screenshots to the clipboard",
                    isOn: $preferences.automaticallyCopyScreenshots
                )
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
}
