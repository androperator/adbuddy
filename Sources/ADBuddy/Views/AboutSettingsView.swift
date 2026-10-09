import AppKit
import SwiftUI

struct AboutSettingsView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("ADBuddy")
                    .font(.largeTitle.bold())
                Text("Version \(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text("Interested in automating your Android development/testing?")
                HStack(spacing: 0) {
                    Text("Check out ")
                    Link("Androperator", destination: URL(string: "https://androperator.com")!)
                        .buttonStyle(.plain)
                        .foregroundStyle(.link)
                        .focusEffectDisabled()
                }
            }
            .font(.callout)

            HStack(spacing: 0) {
                Text("Full source available on ")
                Link("github.com/androperator/adbuddy", destination: URL(string: "https://github.com/androperator/adbuddy")!)
                    .buttonStyle(.plain)
                    .foregroundStyle(.link)
                    .focusEffectDisabled()
            }

            Text("Written by clankers / Engineered by [@chrismlacy](https://x.com/chrismlacy)")
                .font(.callout)

            Text("Copyright © Action Launcher 2026")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
