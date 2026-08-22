import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open ADBuddy") {
            AppLogger.menuBar.info("Open main window selected")
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit ADBuddy") {
            AppLogger.menuBar.info("Quit selected")
            NSApplication.shared.terminate(nil)
        }
    }
}
