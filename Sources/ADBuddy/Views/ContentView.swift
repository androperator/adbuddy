import SwiftUI

struct ContentView: View {
    @Environment(DeviceStore.self) private var deviceStore

    var body: some View {
        VStack(spacing: 0) {
            statusSummary

            Divider()

            deviceContent
        }
        .overlay(alignment: .bottom) {
            if let feedback = deviceStore.screenshotFeedback {
                ScreenshotFeedbackBanner(feedback: feedback) {
                    deviceStore.clearScreenshotFeedback(ifMatching: feedback)
                }
                .padding()
            }
        }
        .animation(.default, value: deviceStore.screenshotFeedback)
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
                    takeScreenshot: {
                        deviceStore.takeScreenshot(of: device)
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
    let takeScreenshot: () -> Void

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
            } else {
                Text(device.connectionState.displayName)
                    .font(.caption)
                    .foregroundStyle(device.connectionState.tint)
            }
        }
        .padding(.vertical, 2)
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
