import AppKit
import SwiftUI

/// The ADBuddy template glyph displayed in the macOS menu bar.
struct ADBuddyMenuBarGlyph: View {
    @ViewBuilder
    var body: some View {
        if let icon = templateIcon {
            Image(nsImage: icon)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 18, height: 18)
                .accessibilityLabel("ADBuddy")
        }
    }

    private var templateIcon: NSImage? {
        guard let iconURL = Bundle.main.url(
            forResource: "ADBuddyMenuBarGlyph",
            withExtension: "svg"
        ), let icon = NSImage(contentsOf: iconURL) else {
            return nil
        }
        icon.isTemplate = true
        return icon
    }
}
