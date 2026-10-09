import SwiftUI

struct LogcatSettingsView: View {
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
