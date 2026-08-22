import SwiftUI

struct LogcatWindowView: View {
    @Environment(DeviceStore.self) private var deviceStore

    let windowID: LogcatWindowID
    @State private var logcatStore: LogcatStore

    init(windowID: LogcatWindowID) {
        self.windowID = windowID
        _logcatStore = State(initialValue: LogcatStore(deviceSerial: windowID.serial))
    }

    private var deviceName: String {
        deviceStore.devices.first(where: { $0.serial == windowID.serial })?.displayName ?? windowID.serial
    }

    var body: some View {
        @Bindable var logcatStore = logcatStore

        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(deviceName)
                    .font(.headline)

                Text(windowID.serial)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            LogcatStateBanner(streamState: logcatStore.streamState)

            Divider()

            LogcatTableView(entries: logcatStore.visibleEntries)
        }
        .frame(minWidth: 700, minHeight: 420, alignment: .topLeading)
        .navigationTitle("Logcat - \(deviceName)")
        .task(id: deviceStore.resolvedSDK?.adbPath) {
            logcatStore.start(adbPath: deviceStore.resolvedSDK?.adbPath)
        }
        .onDisappear {
            logcatStore.stop()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                ApplicationIDPicker(
                    applicationID: logcatStore.applicationID,
                    suggestions: logcatStore.runningApplicationIDs,
                    onCommit: logcatStore.selectApplicationID
                )
                .frame(width: 260)
            }

            ToolbarItem(placement: .principal) {
                Picker("Minimum Log Level", selection: $logcatStore.minimumPriority) {
                    ForEach(LogcatPriority.allCases, id: \.self) { priority in
                        Text(priority.rawValue)
                            .tag(priority)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .accessibilityLabel("Minimum Log Level")
                .help("Minimum Log Level")
            }
        }
    }
}

private struct LogcatStateBanner: View {
    let streamState: LogcatStreamState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .foregroundStyle(tint)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var symbolName: String {
        switch streamState {
        case .connecting:
            "arrow.triangle.2.circlepath"
        case .streaming:
            "dot.radiowaves.left.and.right"
        case .waitingForApplication:
            "hourglass"
        case .failed:
            "exclamationmark.triangle"
        case .stopped:
            "stop.circle"
        }
    }

    private var tint: Color {
        switch streamState {
        case .connecting:
            .secondary
        case .streaming:
            .green
        case .waitingForApplication:
            .secondary
        case .failed:
            .orange
        case .stopped:
            .secondary
        }
    }

    private var message: String {
        switch streamState {
        case .connecting:
            "Connecting to Logcat…"
        case .streaming:
            "Streaming Logcat"
        case .waitingForApplication(let applicationID):
            "Waiting for \(applicationID) to start"
        case .failed(let message):
            message
        case .stopped:
            "Logcat stopped"
        }
    }
}
