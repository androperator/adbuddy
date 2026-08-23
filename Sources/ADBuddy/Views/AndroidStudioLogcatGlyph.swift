import AppKit
import SwiftUI

/// The Android Studio Logcat glyph from `Assets/AndroidStudio/Logcat@20x20.svg`.
struct AndroidStudioLogcatGlyph: View {
    @ViewBuilder
    var body: some View {
        if let icon = templateIcon {
            Image(nsImage: icon)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(.primary)
                .scaledToFit()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        }
    }

    private var templateIcon: NSImage? {
        guard let iconURL = Bundle.main.url(
            forResource: "Logcat@20x20",
            withExtension: "svg"
        ), let icon = NSImage(contentsOf: iconURL) else {
            return nil
        }
        icon.isTemplate = true
        return icon
    }
}
