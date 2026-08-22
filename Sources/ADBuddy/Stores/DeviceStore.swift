import Foundation
import Observation

@MainActor
@Observable
final class DeviceStore {
    private let preferences: AppPreferences
    private let sdkLocator: AndroidSDKLocator
    private let processRunner: any ProcessRunning
    private let screenshotClipboard: any ScreenshotClipboardCopying
    private let screenshotNotifier: any ScreenshotNotifying
    private var pollingTask: Task<Void, Never>?
    private var capturingDeviceSerials = Set<String>()

    private(set) var devices: [AndroidDevice] = []
    private(set) var status: DeviceDiscoveryStatus = .loading
    private(set) var resolvedSDK: AndroidSDK?
    private(set) var isRefreshing = false
    private(set) var screenshotFeedback: ScreenshotFeedback?

    init(
        preferences: AppPreferences = AppPreferences(),
        sdkLocator: AndroidSDKLocator = AndroidSDKLocator(),
        processRunner: any ProcessRunning = ProcessRunner(),
        screenshotClipboard: any ScreenshotClipboardCopying = ScreenshotClipboardService(),
        screenshotNotifier: any ScreenshotNotifying = ScreenshotNotificationService()
    ) {
        self.preferences = preferences
        self.sdkLocator = sdkLocator
        self.processRunner = processRunner
        self.screenshotClipboard = screenshotClipboard
        self.screenshotNotifier = screenshotNotifier
    }

    func start() {
        guard pollingTask == nil else {
            return
        }

        AppLogger.devices.info("Starting device refresh polling")
        refresh()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else {
                    return
                }
                self?.refresh()
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        AppLogger.devices.info("Refreshing Android devices")

        Task { [weak self] in
            guard let self else {
                return
            }

            let outcome = await loadDevices()
            guard !Task.isCancelled else {
                return
            }

            apply(outcome)
        }
    }

    func isCapturingScreenshot(for device: AndroidDevice) -> Bool {
        capturingDeviceSerials.contains(device.serial)
    }

    func takeScreenshot(of device: AndroidDevice) {
        guard device.isUsable else {
            showScreenshotFeedback(.failure("\(device.displayName) is not available for screenshots."))
            return
        }

        guard let resolvedSDK else {
            showScreenshotFeedback(.failure("ADB is not available. Refresh device discovery and try again."))
            return
        }

        guard capturingDeviceSerials.insert(device.serial).inserted else {
            return
        }

        screenshotFeedback = nil
        AppLogger.screenshot.info("Starting screenshot capture")

        let screenshotService = ScreenshotService(
            adbPath: resolvedSDK.adbPath,
            processRunner: processRunner
        )
        let destination = preferences.screenshotDirectory

        Task { [weak self] in
            let result = await screenshotService.capture(
                device: device,
                destination: destination
            )
            guard let self, !Task.isCancelled else {
                return
            }

            capturingDeviceSerials.remove(device.serial)

            switch result {
            case .success(let fileURL):
                let copiedToClipboard = copyScreenshotToClipboardIfNeeded(at: fileURL)
                AppLogger.screenshot.info("Screenshot capture succeeded")
                showScreenshotFeedback(.success(fileURL, copiedToClipboard: copiedToClipboard))

                let screenshotNotifier = screenshotNotifier
                Task {
                    await screenshotNotifier.notifyAboutSavedScreenshot(
                        at: fileURL,
                        copiedToClipboard: copiedToClipboard
                    )
                }
            case .failure(let error):
                AppLogger.screenshot.error("Screenshot capture failed: \(error.message, privacy: .public)")
                showScreenshotFeedback(.failure(error.message))
            }
        }
    }

    func clearScreenshotFeedback(ifMatching feedback: ScreenshotFeedback) {
        guard screenshotFeedback == feedback else {
            return
        }
        screenshotFeedback = nil
    }

    private func loadDevices() async -> DeviceLoadOutcome {
        switch sdkLocator.resolve() {
        case .unavailable(let failure):
            return .sdkUnavailable(failure)
        case .found(let sdk):
            let client = ADBClient(adbPath: sdk.adbPath, processRunner: processRunner)
            let result = await client.listDevices()
            return .adbResult(sdk, result)
        }
    }

    private func apply(_ outcome: DeviceLoadOutcome) {
        isRefreshing = false

        switch outcome {
        case .sdkUnavailable(let failure):
            resolvedSDK = nil
            devices = []
            status = .sdkUnavailable(failure)
        case .adbResult(let sdk, .success(let devices)):
            resolvedSDK = sdk
            self.devices = devices
            status = devices.isEmpty ? .noDevices : .devicesAvailable
        case .adbResult(let sdk, .failure(let error)):
            resolvedSDK = sdk
            devices = []
            switch error {
            case .commandFailed(let message):
                status = .adbFailure(message)
            }
        }
    }

    private func showScreenshotFeedback(_ feedback: ScreenshotFeedback) {
        screenshotFeedback = feedback
        let timeout: Duration = feedback.isSuccess ? .seconds(4) : .seconds(8)

        Task { [weak self, feedback] in
            try? await Task.sleep(for: timeout)
            self?.clearScreenshotFeedback(ifMatching: feedback)
        }
    }

    private func copyScreenshotToClipboardIfNeeded(at fileURL: URL) -> Bool {
        guard preferences.automaticallyCopyScreenshots else {
            return false
        }

        switch screenshotClipboard.copyScreenshot(at: fileURL) {
        case .copied:
            AppLogger.screenshot.info("Copied screenshot to clipboard")
            return true
        case .failed(let message):
            AppLogger.screenshot.error("Could not copy screenshot to clipboard: \(message, privacy: .public)")
            return false
        }
    }
}

private enum DeviceLoadOutcome {
    case sdkUnavailable(AndroidSDKFailure)
    case adbResult(AndroidSDK, ADBDeviceListResult)
}
