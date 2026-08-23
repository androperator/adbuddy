import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(DeviceStore.self) private var deviceStore
    @Environment(EmulatorStore.self) private var emulatorStore
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

                if let feedback = deviceStore.appActionFeedback {
                    AppActionFeedbackBanner(feedback: feedback) {
                        deviceStore.clearAppActionFeedback(ifMatching: feedback)
                    }
                }

                if let feedback = deviceStore.deepLinkLaunchFeedback {
                    DeepLinkLaunchFeedbackBanner(feedback: feedback) {
                        deviceStore.clearDeepLinkLaunchFeedback(ifMatching: feedback)
                    }
                }

                if let feedback = deviceStore.deviceSettingFeedback {
                    DeviceSettingFeedbackBanner(feedback: feedback) {
                        deviceStore.clearDeviceSettingFeedback(ifMatching: feedback)
                    }
                }

                if let feedback = emulatorStore.feedback {
                    EmulatorFeedbackBanner(feedback: feedback) {
                        emulatorStore.clearFeedback(ifMatching: feedback)
                    }
                }
            }
            .padding()
        }
        .animation(.default, value: deviceStore.screenshotFeedback)
        .animation(.default, value: deviceStore.screenRecordingFeedback)
        .animation(.default, value: deviceStore.appActionFeedback)
        .animation(.default, value: deviceStore.deepLinkLaunchFeedback)
        .animation(.default, value: deviceStore.deviceSettingFeedback)
        .animation(.default, value: emulatorStore.feedback)
        .onChange(of: deviceStore.devices) { _, devices in
            emulatorStore.updateRunningStatus(using: devices, sdk: deviceStore.resolvedSDK)
        }
        .onChange(of: deviceStore.resolvedSDK) { _, sdk in
            emulatorStore.updateRunningStatus(using: deviceStore.devices, sdk: sdk)
        }
        .task {
            emulatorStore.updateRunningStatus(
                using: deviceStore.devices,
                sdk: deviceStore.resolvedSDK
            )
        }
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
        .sheet(isPresented: $deviceStore.isPresentingDeepLinkLauncher) {
            DeepLinkLauncherSheet(
                devices: deviceStore.devices.filter(\.isUsable),
                preferredDeviceSerial: deviceStore.deepLinkLauncherPreferredDeviceSerial,
                isLaunching: deviceStore.isLaunchingDeepLink,
                dismiss: deviceStore.dismissDeepLinkLauncher,
                launch: deviceStore.launchDeepLink
            )
        }
        .alert(
            "Wipe Emulator Data?",
            isPresented: Binding(
                get: { emulatorStore.wipeDataConfirmationVirtualDevice != nil },
                set: { isPresented in
                    if !isPresented {
                        emulatorStore.cancelWipeDataAndStart()
                    }
                }
            ),
            presenting: emulatorStore.wipeDataConfirmationVirtualDevice
        ) { virtualDevice in
            Button("Cancel", role: .cancel) {
                emulatorStore.cancelWipeDataAndStart()
            }
            Button("Wipe Data and Start", role: .destructive) {
                emulatorStore.confirmWipeDataAndStart(virtualDevice)
            }
        } message: { virtualDevice in
            Text("This removes all installed apps and settings from \(virtualDevice.name).")
        }
        .alert(
            "Uninstall Foreground App?",
            isPresented: Binding(
                get: { deviceStore.foregroundAppUninstallRequest != nil },
                set: { isPresented in
                    if !isPresented {
                        deviceStore.cancelForegroundAppUninstall()
                    }
                }
            ),
            presenting: deviceStore.foregroundAppUninstallRequest
        ) { request in
            Button("Cancel", role: .cancel) {
                deviceStore.cancelForegroundAppUninstall()
            }
            Button("Uninstall", role: .destructive) {
                deviceStore.confirmForegroundAppUninstall(request)
            }
        } message: { request in
            Text("This removes \(request.application.packageID) from \(request.device.displayName).")
        }
        .navigationTitle("ADBuddy")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    deviceStore.presentDeepLinkLauncher()
                } label: {
                    Label("Open Link", systemImage: "link")
                }
                .disabled(!deviceStore.devices.contains(where: \.isUsable))
                .help("Open Link on Android Device")
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    EmulatorMenuContent()
                } label: {
                    Label("Open Android Emulator", systemImage: "play.rectangle")
                        .labelStyle(.iconOnly)
                }
                .help("Open Android Emulator")
            }

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
        case .sdkUnavailable, .adbFailure:
            ContentUnavailableView {
                Label(deviceStore.status.title, systemImage: deviceStore.status.symbolName)
            } description: {
                Text(deviceStore.status.detail)
            }
            .frame(minWidth: 440, minHeight: 220)
        case .noDevices, .devicesAvailable:
            MainDeviceListView(
                connectedDevices: deviceStore.devices,
                virtualDevices: emulatorStore.virtualDevices,
                emulatorStatus: emulatorStore.status,
                deviceStore: deviceStore,
                emulatorStore: emulatorStore,
                openLogcat: openLogcat
            )
        }
    }

    private func openLogcat(for device: AndroidDevice) {
        AppLogger.devices.info("Logcat requested from the main window")
        openWindow(value: LogcatWindowID(serial: device.serial))
    }
}

private struct EmulatorFeedbackBanner: View {
    let feedback: EmulatorFeedback
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

private struct AppActionFeedbackBanner: View {
    let feedback: AppActionFeedback
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

private struct DeepLinkLaunchFeedbackBanner: View {
    let feedback: DeepLinkLaunchFeedback
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

private struct DeviceSettingFeedbackBanner: View {
    let feedback: DeviceSettingFeedback
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
