import AppKit
import UniformTypeIdentifiers

@MainActor
enum APKFilePicker {
    static func chooseAPK() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Android APK"
        panel.message = "Choose one .apk file to install on a connected Android device."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "apk") ?? .data]

        return panel.runModal() == .OK ? panel.url : nil
    }
}
