import AppKit
import SwiftUI

/// The Android Studio Logcat glyph from `Assets/AndroidStudio/Logcat@20x20.svg`.
struct AndroidStudioLogcatGlyph: View {
    @ViewBuilder
    var body: some View {
        if let iconURL = Bundle.main.url(forResource: "Logcat@20x20", withExtension: "svg"),
           let icon = NSImage(contentsOf: iconURL) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        }
    }
}
