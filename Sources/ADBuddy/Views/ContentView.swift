import SwiftUI

struct ContentView: View {
    @Environment(DeviceStore.self) private var deviceStore

    var body: some View {
        @Bindable var deviceStore = deviceStore

        VStack(spacing: 0) {
            statusSummary

            Divider()

            deviceContent
        }
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
        .navigationTitle("ADBuddy")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    AppLogger.devices.info("Refresh button selected")
                    deviceStore.refresh()
                } label: {
                    Label("Refresh Devices", systemImage: "arrow.clockwise")
                }
                .disabled(deviceStore.isRefreshing)
            }
        }
    }

    private var statusSummary: some View {
        HStack(spacing: 10) {
            Image(systemName: deviceStore.status.symbolName)
                .foregroundStyle(deviceStore.status.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(deviceStore.status.title)
                    .font(.headline)
                Text(deviceStore.status.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if deviceStore.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding()
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
            } actions: {
                Button("Refresh Devices") {
                    deviceStore.refresh()
                }
            }
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
        }
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
                            Text("Take Screenshot")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCapturing)
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
            Label("Preparing", systemImage: "record.circle")
                .foregroundStyle(.secondary)
        } else if isScreenRecording {
            Button("Stop Recording", action: stopScreenRecording)
                .buttonStyle(.bordered)
        } else if isStoppingScreenRecording {
            Label("Stopping", systemImage: "stop.circle")
                .foregroundStyle(.secondary)
        } else {
            Button("Record Screen…", action: showScreenRecordingOptions)
                .buttonStyle(.bordered)
                .disabled(!canStartScreenRecording)
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
