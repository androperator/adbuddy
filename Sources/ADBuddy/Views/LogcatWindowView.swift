import SwiftUI

struct LogcatWindowView: View {
    @Environment(DeviceStore.self) private var deviceStore
    @Environment(AppPreferences.self) private var preferences

    let windowID: LogcatWindowID
    @State private var logcatStore: LogcatStore
    @State private var showsProcessID = false
    @State private var showsThreadID = false
    @State private var showsApplicationID = false
    @State private var isSearchPresented = false

    init(windowID: LogcatWindowID) {
        self.windowID = windowID
        _logcatStore = State(initialValue: LogcatStore(deviceSerial: windowID.serial))
    }

    private var deviceName: String {
        deviceStore.devices.first(where: { $0.serial == windowID.serial })?.displayName ?? windowID.serial
    }

    private var deviceAvailability: LogcatDeviceAvailability {
        guard let device = deviceStore.devices.first(where: { $0.serial == windowID.serial }),
              device.isUsable,
              let adbPath = deviceStore.resolvedSDK?.adbPath else {
            return .unavailable
        }
        return .usable(adbPath: adbPath)
    }

    var body: some View {
        @Bindable var logcatStore = logcatStore

        VStack(spacing: 0) {
            LogcatContextBar(
                deviceName: deviceName,
                serial: windowID.serial,
                streamState: logcatStore.displayedStreamState,
                entryCount: logcatStore.displayedEntryCount
            )

            Divider()

            LogcatTableView(
                entryCount: logcatStore.displayedEntryCount,
                entryRevision: logcatStore.displayedEntryRevision,
                entryAt: logcatStore.displayedEntry(at:),
                applicationIDRevision: logcatStore.applicationIDRevision,
                applicationIDForProcessID: logcatStore.applicationID(for:),
                followsLatest: logcatStore.isFollowing,
                showsProcessID: showsProcessID,
                showsThreadID: showsThreadID,
                showsApplicationID: showsApplicationID,
                priorityColors: preferences.logcatColors,
                onUserScrollAwayFromLatest: logcatStore.userScrolledAwayFromLatest
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: 700,
            maxWidth: .infinity,
            minHeight: 420,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .navigationTitle("Logcat - \(deviceName)")
        .searchable(
            text: $logcatStore.searchText,
            isPresented: $isSearchPresented,
            placement: .toolbar,
            prompt: "Search Logcat"
        )
        .focusedSceneValue(\.logcatSearchAction) {
            isSearchPresented = true
        }
        .task(id: deviceAvailability) {
            logcatStore.updateDeviceAvailability(deviceAvailability)
        }
        .onDisappear {
            logcatStore.stop()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    ApplicationIDPicker(
                        applicationID: logcatStore.applicationID,
                        suggestions: logcatStore.runningApplicationIDs,
                        onCommit: logcatStore.selectApplicationID
                    )
                    .frame(width: 220)

                    Divider()
                        .frame(height: 18)

                    MinimumLogLevelMenu(priority: $logcatStore.minimumPriority)
                }
                .controlSize(.small)
            }

            ToolbarItemGroup(placement: .automatic) {
                Toggle(isOn: $logcatStore.showsOnlyCrashesAndExceptions) {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .toggleStyle(.button)
                .accessibilityLabel("Show Crashes and Exceptions")
                .accessibilityValue(
                    logcatStore.showsOnlyCrashesAndExceptions ? "On" : "Off"
                )
                .help("Show Crashes and Exceptions")

                Menu {
                    Toggle("Process ID", isOn: $showsProcessID)
                    Toggle("Thread ID", isOn: $showsThreadID)
                    Toggle("Application ID", isOn: $showsApplicationID)
                } label: {
                    Label("Columns", systemImage: "rectangle.3.group")
                }
                .accessibilityLabel("Logcat Columns")
                .help("Show Logcat Columns")

                Button {
                    logcatStore.togglePause()
                } label: {
                    Image(systemName: logcatStore.isPaused ? "play.fill" : "pause.fill")
                }
                .accessibilityLabel(logcatStore.isPaused ? "Resume Logcat" : "Pause Logcat")
                .help(logcatStore.isPaused ? "Resume Logcat" : "Pause Logcat")

                Button {
                    logcatStore.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Clear Logcat")
                .help("Clear Logcat")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    logcatStore.jumpToLatest()
                } label: {
                    Image(systemName: "arrow.down.to.line.compact")
                }
                .disabled(logcatStore.isFollowing)
                .accessibilityLabel("Jump to Latest")
                .help("Jump to Latest")
            }
        }
    }
}

private struct MinimumLogLevelMenu: View {
    @Binding var priority: LogcatPriority

    var body: some View {
        Menu {
            ForEach(LogcatPriority.allCases, id: \.self) { option in
                Button {
                    priority = option
                } label: {
                    if option == priority {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
        } label: {
            Text("Minimum: \(priority.displayName)")
        }
        .menuStyle(.borderedButton)
        .accessibilityLabel("Minimum Log Level")
        .accessibilityValue("\(priority.displayName) and above")
        .help("Show \(priority.displayName) log messages and above")
    }
}

private struct LogcatContextBar: View {
    let deviceName: String
    let serial: String
    let streamState: LogcatStreamState
    let entryCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Label(deviceName, systemImage: "iphone")
                .font(.callout.weight(.semibold))
                .lineLimit(1)

            Text(serial)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)

            Spacer(minLength: 12)

            LogcatStreamStatus(streamState: streamState)

            if entryCount > 0 {
                Text("\(entryCount.formatted()) entries")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Visible Logcat entries")
                    .accessibilityValue(entryCount.formatted())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

private struct LogcatStreamStatus: View {
    let streamState: LogcatStreamState

    var body: some View {
        Label(message, systemImage: symbolName)
            .font(.caption)
            .foregroundStyle(tint)
            .lineLimit(1)
            .accessibilityLabel("Logcat status")
            .accessibilityValue(message)
            .help(message)
    }

    private var symbolName: String {
        switch streamState {
        case .connecting:
            "arrow.triangle.2.circlepath"
        case .streaming:
            "dot.radiowaves.left.and.right"
        case .paused:
            "pause.circle"
        case .disconnected:
            "iphone.slash"
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
        case .paused:
            .secondary
        case .disconnected:
            .orange
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
        case .paused:
            "Logcat paused"
        case .disconnected:
            "Device disconnected. Waiting to reconnect."
        case .waitingForApplication(let applicationID):
            "Waiting for \(applicationID) to start"
        case .failed(let message):
            message
        case .stopped:
            "Logcat stopped"
        }
    }
}
