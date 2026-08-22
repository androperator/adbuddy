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

            LogcatTableView(entries: logcatStore.entries)
        }
        .frame(minWidth: 700, minHeight: 420, alignment: .topLeading)
        .navigationTitle("Logcat - \(deviceName)")
        .task(id: deviceStore.resolvedSDK?.adbPath) {
            logcatStore.start(adbPath: deviceStore.resolvedSDK?.adbPath)
        }
        .onDisappear {
            logcatStore.stop()
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
        case .failed(let message):
            message
        case .stopped:
            "Logcat stopped"
        }
    }
}
