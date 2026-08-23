import SwiftUI

struct DeviceActionControls: View {
    let isCapturing: Bool
    let isPreparingScreenRecording: Bool
    let isScreenRecording: Bool
    let isStoppingScreenRecording: Bool
    let canStartScreenRecording: Bool
    let isPerformingAppAction: Bool
    let isPerformingDeviceSetting: Bool
    let takeScreenshot: () -> Void
    let showScreenRecordingOptions: () -> Void
    let stopScreenRecording: () -> Void
    let openLogcat: () -> Void
    let performAppAction: (AndroidAppAction) -> Void
    let requestUninstallForegroundApp: () -> Void
    let performDeviceSetting: (AndroidDeviceSettingAction) -> Void

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
            .frame(width: DeviceListLayout.actionControlWidth)
            .buttonStyle(.borderedProminent)
            .disabled(isCapturing)
            .help("Take Screenshot")

            Divider()
                .frame(height: 20)

            Button(action: openLogcat) {
                AndroidStudioLogcatGlyph()
            }
            .frame(width: DeviceListLayout.actionControlWidth)
            .buttonStyle(.bordered)
            .accessibilityLabel("Open Logcat")
            .help("Open Logcat")

            foregroundAppActionsMenu
            deviceSettingsMenu
        }
    }

    private var foregroundAppActionsMenu: some View {
        Menu {
            Button("Start Foreground App") {
                performAppAction(.start)
            }
            Button("Kill Foreground App") {
                performAppAction(.forceStop)
            }
            Button("Restart Foreground App") {
                performAppAction(.restart)
            }

            Divider()

            Button("Clear Foreground App Data") {
                performAppAction(.clearData)
            }
            Button("Clear App Data and Restart") {
                performAppAction(.clearDataAndRestart)
            }

            Divider()

            Button("Uninstall Foreground App…", role: .destructive) {
                requestUninstallForegroundApp()
            }
        } label: {
            Label("Foreground App Actions", systemImage: "app.badge")
                .labelStyle(.iconOnly)
        }
        .frame(width: DeviceListLayout.actionControlWidth)
        .menuStyle(.borderedButton)
        .disabled(isPerformingAppAction)
        .accessibilityLabel("Foreground App Actions")
        .help("Foreground App Actions")
    }

    private var deviceSettingsMenu: some View {
        Menu {
            DeviceSettingsMenuContent(perform: performDeviceSetting)
        } label: {
            Label("Device Settings", systemImage: "slider.horizontal.3")
                .labelStyle(.iconOnly)
        }
        .frame(width: DeviceListLayout.actionControlWidth)
        .menuStyle(.borderedButton)
        .disabled(isPerformingDeviceSetting)
        .accessibilityLabel("Device Settings")
        .help("Device Settings")
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
            }
            .frame(width: DeviceListLayout.actionControlWidth)
            .buttonStyle(.bordered)
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
            }
            .frame(width: DeviceListLayout.actionControlWidth)
            .buttonStyle(.borderedProminent)
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
