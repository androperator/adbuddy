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
            screenRecordingControl

            Button {
                takeScreenshot()
            } label: {
                if isCapturing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Take Screenshot", systemImage: "camera")
                        .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCapturing)
            .help("Take Screenshot")

            Divider()
                .frame(height: 20)

            Button(action: openLogcat) {
                Label("Open Logcat", systemImage: "text.alignleft")
                    .labelStyle(.iconOnly)
            }
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
                .help("Preparing Screen Recording")
        } else if isScreenRecording {
            Button(action: stopScreenRecording) {
                Label("Stop Recording", systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .help("Stop Recording")
        } else if isStoppingScreenRecording {
            ProgressView()
                .controlSize(.small)
                .help("Stopping Screen Recording")
        } else {
            Button(action: showScreenRecordingOptions) {
                Label("Record Screen", systemImage: "record.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStartScreenRecording)
            .help("Record Screen")
        }
    }
}
