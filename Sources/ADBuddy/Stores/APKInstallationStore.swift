import Foundation
import Observation

@MainActor
@Observable
final class APKInstallationStore {
    private let processRunner: any ProcessRunning
    private let buildToolsLocator: AndroidBuildToolsLocator
    private var activeDeviceSerials = Set<String>()

    private(set) var archive: AndroidPackageArchive?
    private(set) var preferredDeviceSerial: String?
    var isPresentingInstaller = false
    private(set) var deviceStates: [String: APKInstallationDeviceState] = [:]
    private(set) var installationDevices: [AndroidDevice] = []
    private(set) var feedback: APKInstallationFeedback?

    init(
        processRunner: any ProcessRunning = ProcessRunner(),
        buildToolsLocator: AndroidBuildToolsLocator = AndroidBuildToolsLocator()
    ) {
        self.processRunner = processRunner
        self.buildToolsLocator = buildToolsLocator
    }

    var isInstalling: Bool {
        !activeDeviceSerials.isEmpty
    }

    func presentInstaller(for fileURL: URL, preferredDevice: AndroidDevice? = nil) {
        guard fileURL.isFileURL,
              fileURL.pathExtension.caseInsensitiveCompare("apk") == .orderedSame else {
            showFeedback(
                APKInstallationFeedback(
                    isSuccess: false,
                    title: "Could Not Install APK",
                    detail: "Choose a local .apk file."
                )
            )
            return
        }
        guard !isInstalling else {
            showFeedback(
                APKInstallationFeedback(
                    isSuccess: false,
                    title: "APK Installation In Progress",
                    detail: "Finish the current APK installation before choosing another file."
                )
            )
            return
        }

        archive = AndroidPackageArchive(fileURL: fileURL)
        preferredDeviceSerial = preferredDevice?.serial
        deviceStates = [:]
        installationDevices = []
        feedback = nil
        isPresentingInstaller = true
        AppLogger.apkInstallation.info("APK install options requested")
    }

    func dismissInstaller() {
        guard !isInstalling else {
            return
        }
        archive = nil
        preferredDeviceSerial = nil
        deviceStates = [:]
        installationDevices = []
        isPresentingInstaller = false
    }

    func install(
        archive: AndroidPackageArchive,
        on devices: [AndroidDevice],
        sdk: AndroidSDK?,
        openAfterInstall: Bool
    ) {
        guard !devices.isEmpty else {
            showFeedback(
                APKInstallationFeedback(
                    isSuccess: false,
                    title: "No Devices Selected",
                    detail: "Select at least one usable Android device."
                )
            )
            return
        }
        guard let sdk else {
            showFeedback(
                APKInstallationFeedback(
                    isSuccess: false,
                    title: "ADB Is Not Available",
                    detail: "Device discovery will retry automatically."
                )
            )
            return
        }
        guard !isInstalling else {
            return
        }

        let aapt2Path = buildToolsLocator.aapt2Path(for: sdk)
        deviceStates = Dictionary(
            uniqueKeysWithValues: devices.map { ($0.serial, .installing) }
        )
        installationDevices = devices
        activeDeviceSerials = Set(devices.map(\.serial))
        feedback = nil

        for device in devices {
            let service = APKInstallationService(
                adbPath: sdk.adbPath,
                aapt2Path: aapt2Path,
                processRunner: processRunner
            )

            Task { [weak self] in
                let result = await service.install(
                    archive,
                    on: device.serial,
                    openAfterInstall: openAfterInstall
                )
                guard let self, !Task.isCancelled else {
                    return
                }
                finishInstallation(result, for: device)
            }
        }
    }

    func clearFeedback(ifMatching feedback: APKInstallationFeedback) {
        guard self.feedback == feedback else {
            return
        }
        self.feedback = nil
    }

    private func finishInstallation(
        _ result: APKInstallationServiceResult,
        for device: AndroidDevice
    ) {
        activeDeviceSerials.remove(device.serial)
        switch result {
        case .success(let outcome):
            deviceStates[device.serial] = .succeeded(outcome)
        case .failure(let failure):
            deviceStates[device.serial] = .failed(failure.message)
        }

        guard !isInstalling, let archive else {
            return
        }

        let successfulInstallCount = deviceStates.values.reduce(into: 0) { count, state in
            if case .succeeded = state {
                count += 1
            }
        }
        let deviceCount = deviceStates.count
        let allSucceeded = successfulInstallCount == deviceCount
        let destination = deviceCount == 1 ? "device" : "devices"
        showFeedback(
            APKInstallationFeedback(
                isSuccess: allSucceeded,
                title: allSucceeded ? "APK Installed" : "APK Installation Finished",
                detail: "\(archive.displayName) installed on \(successfulInstallCount) of \(deviceCount) \(destination)."
            )
        )
    }

    private func showFeedback(_ feedback: APKInstallationFeedback) {
        self.feedback = feedback
    }
}
