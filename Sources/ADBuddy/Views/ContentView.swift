import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(DeviceStore.self) private var deviceStore
    @Environment(EmulatorStore.self) private var emulatorStore
    @Environment(AppPreferences.self) private var preferences
    @Environment(APKInstallationStore.self) private var apkInstallationStore


    var body: some View {
        @Bindable var deviceStore = deviceStore

        deviceContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if let feedback = deviceStore.screenshotFeedback,
                   preferences.showSuccessFeedbackBanners || !feedback.isSuccess {
                    ScreenshotFeedbackBanner(feedback: feedback) {
                        deviceStore.clearScreenshotFeedback(ifMatching: feedback)
                    }
                }

                if let feedback = deviceStore.screenRecordingFeedback,
                   preferences.showSuccessFeedbackBanners || !feedback.isSuccess {
                    ScreenRecordingFeedbackBanner(feedback: feedback) {
                        deviceStore.clearScreenRecordingFeedback(ifMatching: feedback)
                    }
                }

                if let feedback = deviceStore.appActionFeedback,
                   preferences.showSuccessFeedbackBanners || !feedback.isSuccess {
                    AppActionFeedbackBanner(feedback: feedback) {
                        deviceStore.clearAppActionFeedback(ifMatching: feedback)
                    }
                }

                if let feedback = deviceStore.deepLinkLaunchFeedback,
                   preferences.showSuccessFeedbackBanners || !feedback.isSuccess {
                    DeepLinkLaunchFeedbackBanner(feedback: feedback) {
                        deviceStore.clearDeepLinkLaunchFeedback(ifMatching: feedback)
                    }
                }

                if let feedback = deviceStore.deviceSettingFeedback,
                   preferences.showSuccessFeedbackBanners || !feedback.isSuccess {
                    DeviceSettingFeedbackBanner(feedback: feedback) {
                        deviceStore.clearDeviceSettingFeedback(ifMatching: feedback)
                    }
                }

                if let feedback = apkInstallationStore.feedback,
                   preferences.showSuccessFeedbackBanners || !feedback.isSuccess {
                    APKInstallationFeedbackBanner(feedback: feedback) {
                        apkInstallationStore.clearFeedback(ifMatching: feedback)
                    }
                }

                if let feedback = emulatorStore.feedback,
                   preferences.showSuccessFeedbackBanners || !feedback.isSuccess {
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
        .animation(.default, value: apkInstallationStore.feedback)
        .animation(.default, value: emulatorStore.feedback)
        .animation(.default, value: preferences.showSuccessFeedbackBanners)
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
        .sheet(isPresented: $deviceStore.isPresentingDeepLinkLauncher) {
            DeepLinkLauncherSheet(
                devices: deviceStore.devices.filter(\.isUsable),
                preferredDeviceSerial: deviceStore.deepLinkLauncherPreferredDeviceSerial,
                isLaunching: deviceStore.isLaunchingDeepLink,
                dismiss: deviceStore.dismissDeepLinkLauncher,
                launch: deviceStore.launchDeepLink
            )
        }
        .sheet(
            isPresented: Binding(
                get: { apkInstallationStore.isPresentingInstaller },
                set: { isPresented in
                    if !isPresented {
                        apkInstallationStore.dismissInstaller()
                    }
                }
            )
        ) {
            if let archive = apkInstallationStore.archive {
                APKInstallationSheet(
                    archive: archive,
                    devices: deviceStore.devices.filter(\.isUsable),
                    installationDevices: apkInstallationStore.installationDevices,
                    deviceDisplayName: { device in
                        EmulatorVirtualDeviceStatusResolver.displayName(
                            for: device,
                            among: emulatorStore.virtualDevices
                        )
                    },
                    preferredDeviceSerial: apkInstallationStore.preferredDeviceSerial,
                    deviceStates: apkInstallationStore.deviceStates,
                    isInstalling: apkInstallationStore.isInstalling,
                    dismiss: apkInstallationStore.dismissInstaller,
                    install: { devices, openAfterInstall in
                        apkInstallationStore.install(
                            archive: archive,
                            on: devices,
                            sdk: deviceStore.resolvedSDK,
                            openAfterInstall: openAfterInstall
                        )
                    }
                )
            }
        }
        .alert("Delete Emulator?", isPresented: Binding(
            get: { emulatorStore.deleteConfirmationVirtualDevice != nil },
            set: { if !$0 { emulatorStore.deleteConfirmationVirtualDevice = nil } }
        ), presenting: emulatorStore.deleteConfirmationVirtualDevice) { device in
            Button("Cancel", role: .cancel) { emulatorStore.deleteConfirmationVirtualDevice = nil }
            Button("Delete", role: .destructive) {
                Task { await emulatorStore.confirmDelete(device, configuration: preferences.emulatorHelperConfiguration) }
            }
        } message: { device in
            Text("Permanently delete \(device.name) and all its installed apps, settings and data? The shared Android system image will be kept.")
        }
        .alert("Could Not Delete Emulator", isPresented: Binding(
            get: { emulatorStore.deletionError != nil },
            set: { if !$0 { emulatorStore.deletionError = nil } }
        )) {
            Button("OK") { emulatorStore.deletionError = nil }
        } message: { Text(emulatorStore.deletionError ?? "") }
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
                    EmulatorCreationWindowController.shared.show(
                        preferences: preferences, deviceStore: deviceStore, emulatorStore: emulatorStore
                    )
                } label: {
                    Label("Create Android Emulator", systemImage: "plus.rectangle")
                }
                .help("Create Android Emulator")
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: chooseAPK) {
                    Label("Install APK", systemImage: "shippingbox")
                }
                .disabled(!deviceStore.devices.contains(where: \.isUsable))
                .help("Install APK on Android Device")
            }

            if preferences.isDeepLinkLauncherEnabled {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        deviceStore.presentDeepLinkLauncher()
                    } label: {
                        Label("Open Link", systemImage: "link")
                    }
                    .disabled(!deviceStore.devices.contains(where: \.isUsable))
                    .help("Open Link on Android Device")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
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
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Finding devices…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                apkInstallationStore: apkInstallationStore,
                openLogcat: openLogcat
            )
        }
    }

    private func openLogcat(for device: AndroidDevice) {
        AppLogger.devices.info("Logcat requested from the main window")
        openWindow(value: LogcatWindowID(serial: device.serial))
    }

    private func chooseAPK() {
        guard let fileURL = APKFilePicker.chooseAPK() else {
            return
        }
        apkInstallationStore.presentInstaller(for: fileURL)
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

private struct APKInstallationFeedbackBanner: View {
    let feedback: APKInstallationFeedback
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
