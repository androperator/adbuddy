import SwiftUI

struct ContentView: View {
    @Environment(DeviceStore.self) private var deviceStore
    @Environment(AppPreferences.self) private var preferences
    @Binding var isShowingSettings: Bool

    var body: some View {
        @Bindable var deviceStore = deviceStore

        deviceContent
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if let feedback = deviceStore.screenshotFeedback {
                    ScreenshotFeedbackBanner(feedback: feedback) {
                        deviceStore.clearScreenshotFeedback(ifMatching: feedback)
                    }
                }

                if let feedback = deviceStore.screenRecordingFeedback {
                    ScreenRecordingFeedbackBanner(feedback: feedback) {
                        deviceStore.clearScreenRecordingFeedback(ifMatching: feedback)
                    }
                }
            }
            .padding()
        }
        .animation(.default, value: deviceStore.screenshotFeedback)
        .animation(.default, value: deviceStore.screenRecordingFeedback)
        .sheet(item: $deviceStore.screenRecordingOptionsDevice) { device in
            ScreenRecordingOptionsView(
                device: device,
                options: deviceStore.screenRecordingOptions,
                dismiss: deviceStore.dismissScreenRecordingOptions,
                startRecording: { options in
                    deviceStore.startScreenRecording(of: device, options: options)
                }
            )
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsSheet(preferences: preferences)
        }
        .navigationTitle("ADBuddy")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    AppLogger.settings.info("Settings requested from the toolbar")
                    isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
    }

    @ViewBuilder
    private var deviceContent: some View {
        switch deviceStore.status {
        case .loading:
            ContentUnavailableView(
                "Refreshing Devices",
                systemImage: "arrow.triangle.2.circlepath",
                description: Text("Checking the Android SDK and connected devices.")
            )
        case .sdkUnavailable, .adbFailure, .noDevices:
            ContentUnavailableView {
                Label(deviceStore.status.title, systemImage: deviceStore.status.symbolName)
            } description: {
                Text(deviceStore.status.detail)
            }
            .frame(minWidth: 440, minHeight: 220)
        case .devicesAvailable:
            List(deviceStore.devices) { device in
                DeviceRow(
                    device: device,
                    isCapturing: deviceStore.isCapturingScreenshot(for: device),
                    isPreparingScreenRecording: deviceStore.isPreparingScreenRecording(for: device),
                    isScreenRecording: deviceStore.canStopScreenRecording(for: device),
                    isStoppingScreenRecording: deviceStore.isStoppingScreenRecording(for: device),
                    canStartScreenRecording: deviceStore.canStartScreenRecording(for: device),
                    takeScreenshot: {
                        deviceStore.takeScreenshot(of: device)
                    },
                    showScreenRecordingOptions: {
                        deviceStore.presentScreenRecordingOptions(for: device)
                    },
                    stopScreenRecording: {
                        deviceStore.stopScreenRecording(for: device)
                    }
                )
            }
            .listStyle(.inset)
            .frame(height: deviceListHeight)
        }
    }

    private var deviceListHeight: CGFloat {
        DeviceListLayout.deviceListHeight(for: deviceStore.devices.count)
    }
}

private struct DeviceRow: View {
    let device: AndroidDevice
    let isCapturing: Bool
    let isPreparingScreenRecording: Bool
    let isScreenRecording: Bool
    let isStoppingScreenRecording: Bool
    let canStartScreenRecording: Bool
    let takeScreenshot: () -> Void
    let showScreenRecordingOptions: () -> Void
    let stopScreenRecording: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.kind.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .fontWeight(.medium)
                Text(device.serial)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if device.isUsable {
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
                }
            } else {
                Text(device.connectionState.displayName)
                    .font(.caption)
                    .foregroundStyle(device.connectionState.tint)
            }
        }
        .padding(.vertical, 2)
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
                .buttonStyle(.bordered)
                .disabled(!canStartScreenRecording)
                .help("Record Screen")
        }
    }
}

private struct ScreenshotFeedbackBanner: View {
    let feedback: ScreenshotFeedback
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: feedback.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(feedback.isSuccess ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(feedback.title)
                    .font(.subheadline.weight(.medium))
                Text(feedback.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Button("Dismiss", action: dismiss)
                .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 4, y: 2)
    }
}

private struct ScreenRecordingFeedbackBanner: View {
    let feedback: ScreenRecordingFeedback
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: feedback.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(feedback.isSuccess ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(feedback.title)
                    .font(.subheadline.weight(.medium))
                Text(feedback.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Button("Dismiss", action: dismiss)
                .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 4, y: 2)
    }
}
