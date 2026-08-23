import SwiftUI

struct DeviceActionControls: View {
    let isCapturing: Bool
    let isPreparingScreenRecording: Bool
    let isScreenRecording: Bool
    let isStoppingScreenRecording: Bool
    let canStartScreenRecording: Bool
    let takeScreenshot: () -> Void
    let showScreenRecordingOptions: () -> Void
    let stopScreenRecording: () -> Void
    let openLogcat: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                takeScreenshot()
            } label: {
                if isCapturing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: DeviceListLayout.actionButtonLabelWidth)
                } else {
                    Label("Take Screenshot", systemImage: "camera")
                        .labelStyle(.iconOnly)
                        .frame(width: DeviceListLayout.actionButtonLabelWidth)
                }
            }
            .frame(width: DeviceListLayout.actionControlWidth)
            .buttonStyle(.bordered)
            .disabled(isCapturing)
            .help("Take Screenshot")

            screenRecordingControl

            Divider()
                .frame(height: 20)

            Button(action: openLogcat) {
                AndroidStudioLogcatGlyph()
                    .frame(width: DeviceListLayout.actionButtonLabelWidth)
            }
            .frame(width: DeviceListLayout.actionControlWidth)
            .buttonStyle(.bordered)
            .accessibilityLabel("Open Logcat")
            .help("Open Logcat")
        }
    }

    @ViewBuilder
    private var screenRecordingControl: some View {
        if isPreparingScreenRecording {
            ProgressView()
                .controlSize(.small)
                .frame(width: DeviceListLayout.actionControlWidth)
                .help("Preparing Screen Recording")
        } else if isScreenRecording {
            Button(action: stopScreenRecording) {
                Label("Stop Recording", systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: DeviceListLayout.actionButtonLabelWidth)
            }
            .frame(width: DeviceListLayout.actionControlWidth)
            .buttonStyle(.bordered)
            .tint(.red)
            .help("Stop Recording")
        } else if isStoppingScreenRecording {
            ProgressView()
                .controlSize(.small)
                .frame(width: DeviceListLayout.actionControlWidth)
                .help("Stopping Screen Recording")
        } else {
            Button(action: showScreenRecordingOptions) {
                Label("Record Screen", systemImage: "record.circle")
                    .labelStyle(.iconOnly)
                    .frame(width: DeviceListLayout.actionButtonLabelWidth)
            }
            .frame(width: DeviceListLayout.actionControlWidth)
            .buttonStyle(.bordered)
            .disabled(!canStartScreenRecording)
            .help("Record Screen")
        }
    }
}

struct DeviceSettingsMenuContent: View {
    let perform: (AndroidDeviceSettingAction) -> Void

    var body: some View {
        Menu("Theme") {
            Button("Use Dark Theme") {
                perform(.enableDarkTheme)
            }
            Button("Use Light Theme") {
                perform(.enableLightTheme)
            }
        }

        Menu("Navigation") {
            Button("Use Gesture Navigation") {
                perform(.enableGestureNavigation)
            }
            Button("Use 3-Button Navigation") {
                perform(.enableThreeButtonNavigation)
            }
        }

        Menu("Developer Rendering") {
            Button("Show Layout Bounds") {
                perform(.showLayoutBounds)
            }
            Button("Hide Layout Bounds") {
                perform(.hideLayoutBounds)
            }

            Divider()

            Button("Show GPU Rendering Bars") {
                perform(.showGPURenderingBars)
            }
            Button("Hide GPU Rendering Bars") {
                perform(.hideGPURenderingBars)
            }
        }
    }
}
