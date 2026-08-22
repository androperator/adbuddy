import SwiftUI

struct ScreenRecordingOptionsView: View {
    let device: AndroidDevice
    let dismiss: () -> Void
    let startRecording: (ScreenRecordingOptions) -> Void

    @State private var bitRateMegabitsPerSecond: Int
    @State private var resolution: ScreenRecordingResolution
    @State private var showsTaps: Bool

    init(
        device: AndroidDevice,
        options: ScreenRecordingOptions,
        dismiss: @escaping () -> Void,
        startRecording: @escaping (ScreenRecordingOptions) -> Void
    ) {
        self.device = device
        self.dismiss = dismiss
        self.startRecording = startRecording
        _bitRateMegabitsPerSecond = State(initialValue: options.bitRateMegabitsPerSecond)
        _resolution = State(initialValue: options.resolution)
        _showsTaps = State(initialValue: options.showsTaps)
    }

    private var options: ScreenRecordingOptions {
        ScreenRecordingOptions(
            bitRateMegabitsPerSecond: bitRateMegabitsPerSecond,
            resolution: resolution,
            showsTaps: showsTaps
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Screen Recording Options")
                    .font(.title2.weight(.semibold))
                Text(device.displayName)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    Text("Bit rate (Mbps):")
                    TextField("Bit rate", value: $bitRateMegabitsPerSecond, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                }

                GridRow {
                    Text("Resolution (% of native):")
                    Picker("Resolution", selection: $resolution) {
                        ForEach(ScreenRecordingResolution.allCases) { resolution in
                            Text(resolution.displayName).tag(resolution)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
            }

            Toggle("Show taps", isOn: $showsTaps)

            if let validationMessage = options.validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button("Start Recording") {
                    startRecording(options)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(options.validationMessage != nil)
            }
        }
        .padding(24)
        .frame(width: 430)
    }
}
