import Foundation
import Observation

@MainActor
@Observable
final class DeviceStore {
    static let automaticRefreshInterval: Duration = .seconds(1)

    private let preferences: AppPreferences
    private let sdkLocator: AndroidSDKLocator
    private let processRunner: any ProcessRunning
    private let mediaClipboard: any MediaClipboardCopying
    private let mediaFinderRevealer: any MediaFinderRevealing
    private let mediaNotifier: any SavedMediaNotifying
    private var pollingTask: Task<Void, Never>?
    @ObservationIgnored
    private var isLoadingDevices = false
    private var capturingDeviceSerials = Set<String>()
    private var activeScreenRecording: ScreenRecordingSession?
    private var appActionDeviceSerials = Set<String>()
    private var deepLinkLaunchDeviceSerials = Set<String>()
    private var deviceSettingDeviceSerials = Set<String>()
    private var loadingDeviceDetailSerials = Set<String>()

    private(set) var devices: [AndroidDevice] = []
    private(set) var deviceDetailsBySerial: [String: AndroidDeviceDetails] = [:]
    private(set) var status: DeviceDiscoveryStatus = .loading
    private(set) var resolvedSDK: AndroidSDK?
    private(set) var screenshotFeedback: ScreenshotFeedback?
    var screenRecordingOptionsDevice: AndroidDevice?
    private(set) var screenRecordingActivity: ScreenRecordingActivity?
    private(set) var screenRecordingFeedback: ScreenRecordingFeedback?
    private(set) var appActionFeedback: AppActionFeedback?
    private(set) var foregroundAppUninstallRequest: ForegroundAppUninstallRequest?
    var isPresentingDeepLinkLauncher = false
    private(set) var deepLinkLauncherPreferredDeviceSerial: String?
    private(set) var deepLinkLaunchFeedback: DeepLinkLaunchFeedback?
    private(set) var deviceSettingFeedback: DeviceSettingFeedback?

    init(
        preferences: AppPreferences = AppPreferences(),
        sdkLocator: AndroidSDKLocator = AndroidSDKLocator(),
        processRunner: any ProcessRunning = ProcessRunner(),
        mediaClipboard: any MediaClipboardCopying = MediaClipboardService(),
        mediaFinderRevealer: any MediaFinderRevealing = MediaFinderRevealService(),
        mediaNotifier: any SavedMediaNotifying = MediaNotificationService()
    ) {
        self.preferences = preferences
        self.sdkLocator = sdkLocator
        self.processRunner = processRunner
        self.mediaClipboard = mediaClipboard
        self.mediaFinderRevealer = mediaFinderRevealer
        self.mediaNotifier = mediaNotifier
    }

    func start() {
        guard pollingTask == nil else {
            return
        }

        AppLogger.devices.info("Starting device refresh polling")
        refreshFromPolling()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.automaticRefreshInterval)
                guard !Task.isCancelled else {
                    return
                }
                self?.refreshFromPolling()
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refreshFromPolling() {
        refreshDevices()
    }

    private func refreshDevices() {
        guard !isLoadingDevices else {
            return
        }

        isLoadingDevices = true
        AppLogger.devices.debug("Refreshing Android devices")

        Task { [weak self] in
            guard let self else {
                return
            }

            let outcome = await loadDevices()
            guard !Task.isCancelled else {
                return
            }

            apply(outcome)
            isLoadingDevices = false

        }
    }

    func isCapturingScreenshot(for device: AndroidDevice) -> Bool {
        capturingDeviceSerials.contains(device.serial)
    }

    func deviceDetails(for device: AndroidDevice) -> AndroidDeviceDetails? {
        deviceDetailsBySerial[device.serial]
    }

    func loadDeviceDetails(for device: AndroidDevice) {
        guard device.isUsable,
              let resolvedSDK,
              deviceDetailsBySerial[device.serial] == nil,
              loadingDeviceDetailSerials.insert(device.serial).inserted else {
            return
        }

        let service = AndroidDeviceDetailsService(
            adbPath: resolvedSDK.adbPath,
            processRunner: processRunner
        )
        Task { [weak self] in
            let deviceDetails = await service.details(for: device, includesExtendedDetails: true)
            guard let self, !Task.isCancelled else {
                return
            }

            self.loadingDeviceDetailSerials.remove(device.serial)
            guard self.devices.contains(device) else {
                return
            }
            if let deviceDetails {
                self.deviceDetailsBySerial[device.serial] = deviceDetails
            }
        }
    }

    func takeScreenshot(of device: AndroidDevice) {
        guard device.isUsable else {
            showScreenshotFeedback(.failure("\(device.displayName) is not available for screenshots."))
            return
        }

        guard let resolvedSDK else {
            showScreenshotFeedback(.failure("ADB is not currently available. Device discovery will retry automatically."))
            return
        }

        guard capturingDeviceSerials.insert(device.serial).inserted else {
            return
        }

        screenshotFeedback = nil
        AppLogger.screenshot.info("Starting screenshot capture")

        let screenshotService = ScreenshotService(
            adbPath: resolvedSDK.adbPath,
            sdkRootPath: resolvedSDK.rootPath,
            processRunner: processRunner
        )
        let emulatorService = AndroidEmulatorService(
            sdk: resolvedSDK,
            processRunner: processRunner
        )
        let destination = preferences.screenshotDirectory
        let framing = ScreenshotFramingOptions(
            addsFrame: preferences.screenshotAddsFrame,
            alsoSavesOriginal: preferences.screenshotAlsoSavesOriginal,
            overlaysDeviceDetails: preferences.screenshotOverlaysDeviceDetails
        )
        let output = ScreenshotOutputOptions(
            alsoSavesFiftyPercentCopy: preferences.screenshotAlsoSavesFiftyPercentCopy
        )

        Task { [weak self] in
            let mediaDevice = await emulatorService.deviceWithUserFacingName(device)
            let result = await screenshotService.capture(
                device: mediaDevice,
                destination: destination,
                framing: framing,
                output: output
            )
            guard let self, !Task.isCancelled else {
                return
            }

            capturingDeviceSerials.remove(device.serial)

            switch result {
            case .success(let output):
                let copiedToClipboard = copyScreenshotToClipboardIfNeeded(at: output.primaryFileURL)
                revealMediaInFinderIfNeeded(at: output.savedFileURLs)
                AppLogger.screenshot.info("Screenshot capture succeeded")
                showScreenshotFeedback(.success(output, copiedToClipboard: copiedToClipboard))

                let mediaNotifier = mediaNotifier
                Task {
                    await mediaNotifier.notifyAboutSavedMedia(
                        at: output.primaryFileURL,
                        kind: .screenshot(copiedToClipboard: copiedToClipboard)
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

    var screenRecordingOptions: ScreenRecordingOptions {
        ScreenRecordingOptions(
            bitRateMegabitsPerSecond: preferences.screenRecordingBitRateMegabitsPerSecond,
            resolution: ScreenRecordingResolution(rawValue: preferences.screenRecordingResolutionPercentage) ?? .native,
            showsTaps: preferences.screenRecordingShowsTaps
        )
    }

    func presentScreenRecordingOptions(for device: AndroidDevice) {
        guard device.isUsable else {
            showScreenRecordingFeedback(.failure("\(device.displayName) is not available for recording."))
            return
        }
        guard activeScreenRecording == nil else {
            showScreenRecordingFeedback(.failure("Finish the current recording before starting another one."))
            return
        }

        AppLogger.recording.info("Screen recording options requested")
        screenRecordingOptionsDevice = device
    }

    func dismissScreenRecordingOptions() {
        screenRecordingOptionsDevice = nil
    }

    func startScreenRecording(of device: AndroidDevice, options: ScreenRecordingOptions) {
        screenRecordingOptionsDevice = nil

        guard device.isUsable else {
            showScreenRecordingFeedback(.failure("\(device.displayName) is not available for recording."))
            return
        }
        guard let resolvedSDK else {
            showScreenRecordingFeedback(.failure("ADB is not currently available. Device discovery will retry automatically."))
            return
        }
        guard activeScreenRecording == nil else {
            showScreenRecordingFeedback(.failure("Finish the current recording before starting another one."))
            return
        }
        if let validationMessage = options.validationMessage {
            showScreenRecordingFeedback(.failure(validationMessage))
            return
        }

        preferences.screenRecordingBitRateMegabitsPerSecond = options.bitRateMegabitsPerSecond
        preferences.screenRecordingResolutionPercentage = options.resolution.rawValue
        preferences.screenRecordingShowsTaps = options.showsTaps

        let session = ScreenRecordingSession(device: device)
        activeScreenRecording = session
        screenRecordingActivity = .preparing(session)
        screenRecordingFeedback = nil
        AppLogger.recording.info("Preparing screen recording")

        let screenRecordingService = ScreenRecordingService(
            adbPath: resolvedSDK.adbPath,
            sdkRootPath: resolvedSDK.rootPath,
            processRunner: processRunner
        )
        let emulatorService = AndroidEmulatorService(
            sdk: resolvedSDK,
            processRunner: processRunner
        )
        let destination = preferences.screenshotDirectory
        let framing = ScreenRecordingFramingOptions(
            addsFrame: preferences.screenRecordingAddsFrame,
            overlaysDeviceDetails: preferences.screenshotOverlaysDeviceDetails
        )

        Task { [weak self] in
            let mediaDevice = await emulatorService.deviceWithUserFacingName(device)
            let mediaSession = ScreenRecordingSession(
                device: mediaDevice,
                remoteFilePath: session.remoteFilePath
            )
            let result = await screenRecordingService.record(
                session: mediaSession,
                options: options,
                destination: destination,
                framing: framing,
                onScreenRecorderStarted: { @MainActor [weak self] in
                    self?.markScreenRecordingStarted(session)
                }
            )
            guard let self else {
                return
            }
            self.finishScreenRecording(session: session, result: result)
        }
    }

    func canStartScreenRecording(for device: AndroidDevice) -> Bool {
        device.isUsable && activeScreenRecording == nil
    }

    var hasActiveScreenRecording: Bool {
        if case .recording = screenRecordingActivity {
            return true
        }
        return false
    }

    var activeScreenRecordingDevice: AndroidDevice? {
        guard case .recording(let session) = screenRecordingActivity else {
            return nil
        }
        return session.device
    }

    func canStopScreenRecording(for device: AndroidDevice) -> Bool {
        guard case .recording(let session) = screenRecordingActivity else {
            return false
        }
        return session.device.serial == device.serial
    }

    func isPreparingScreenRecording(for device: AndroidDevice) -> Bool {
        guard case .preparing(let session) = screenRecordingActivity else {
            return false
        }
        return session.device.serial == device.serial
    }

    func isStoppingScreenRecording(for device: AndroidDevice) -> Bool {
        guard case .stopping(let session) = screenRecordingActivity else {
            return false
        }
        return session.device.serial == device.serial
    }

    func stopScreenRecording(for device: AndroidDevice) {
        guard case .recording(let session) = screenRecordingActivity,
              session.device.serial == device.serial,
              let resolvedSDK else {
            return
        }

        screenRecordingActivity = .stopping(session)
        AppLogger.recording.info("Stopping screen recording")
        let screenRecordingService = ScreenRecordingService(
            adbPath: resolvedSDK.adbPath,
            processRunner: processRunner
        )

        Task { [weak self] in
            let result = await screenRecordingService.stop(session: session)
            guard let self, self.activeScreenRecording == session else {
                return
            }

            switch result {
            case .stopped:
                break
            case .failure(let message):
                self.screenRecordingActivity = .recording(session)
                AppLogger.recording.error("Could not stop screen recording: \(message, privacy: .public)")
                self.showScreenRecordingFeedback(.failure("Could not stop recording: \(message)"))
            }
        }
    }

    func clearScreenRecordingFeedback(ifMatching feedback: ScreenRecordingFeedback) {
        guard screenRecordingFeedback == feedback else {
            return
        }
        screenRecordingFeedback = nil
    }

    func isPerformingAppAction(for device: AndroidDevice) -> Bool {
        appActionDeviceSerials.contains(device.serial)
    }

    func performAppAction(_ action: AndroidAppAction, for device: AndroidDevice) {
        guard let service = beginAppAction(for: device) else {
            return
        }

        Task { [weak self] in
            let result = await service.perform(action, for: device.serial)
            guard let self, !Task.isCancelled else {
                return
            }
            finishAppAction(for: device, result: result)
        }
    }

    func requestUninstallForegroundApp(for device: AndroidDevice) {
        guard let service = beginAppAction(for: device) else {
            return
        }

        Task { [weak self] in
            let result = await service.foregroundApplication(for: device.serial)
            guard let self, !Task.isCancelled else {
                return
            }

            appActionDeviceSerials.remove(device.serial)
            switch result {
            case .success(let application):
                foregroundAppUninstallRequest = ForegroundAppUninstallRequest(
                    device: device,
                    application: application
                )
            case .failure(let failure):
                AppLogger.appActions.error("Could not resolve foreground Android app: \(failure.message, privacy: .public)")
                showAppActionFeedback(.failure(failure.message))
            }
        }
    }

    func cancelForegroundAppUninstall() {
        foregroundAppUninstallRequest = nil
    }

    func confirmForegroundAppUninstall(_ request: ForegroundAppUninstallRequest) {
        guard foregroundAppUninstallRequest == request,
              let service = beginAppAction(for: request.device) else {
            return
        }
        foregroundAppUninstallRequest = nil

        Task { [weak self] in
            let result = await service.perform(
                .uninstall,
                on: request.application,
                deviceSerial: request.device.serial
            )
            guard let self, !Task.isCancelled else {
                return
            }
            finishAppAction(for: request.device, result: result)
        }
    }

    func clearAppActionFeedback(ifMatching feedback: AppActionFeedback) {
        guard appActionFeedback == feedback else {
            return
        }
        appActionFeedback = nil
    }

    func isPerformingDeviceSetting(for device: AndroidDevice) -> Bool {
        deviceSettingDeviceSerials.contains(device.serial)
    }

    func performDeviceSetting(_ action: AndroidDeviceSettingAction, for device: AndroidDevice) {
        guard device.isUsable else {
            showDeviceSettingFeedback(.failure("\(device.displayName) is not available for device settings."))
            return
        }
        guard let resolvedSDK else {
            showDeviceSettingFeedback(.failure("ADB is not currently available. Device discovery will retry automatically."))
            return
        }
        guard deviceSettingDeviceSerials.insert(device.serial).inserted else {
            return
        }

        deviceSettingFeedback = nil
        AppLogger.deviceSettings.info("Android device setting requested")
        let service = AndroidDeviceSettingsService(
            adbPath: resolvedSDK.adbPath,
            processRunner: processRunner
        )

        Task { [weak self] in
            let result = await service.apply(action, to: device.serial)
            guard let self, !Task.isCancelled else {
                return
            }

            deviceSettingDeviceSerials.remove(device.serial)
            switch result {
            case .success(let outcome):
                showDeviceSettingFeedback(.success(outcome, deviceName: device.displayName))
            case .failure(let failure):
                showDeviceSettingFeedback(.failure(failure.message))
            }
        }
    }

    func clearDeviceSettingFeedback(ifMatching feedback: DeviceSettingFeedback) {
        guard deviceSettingFeedback == feedback else {
            return
        }
        deviceSettingFeedback = nil
    }

    var isLaunchingDeepLink: Bool {
        !deepLinkLaunchDeviceSerials.isEmpty
    }

    func presentDeepLinkLauncher(preselecting device: AndroidDevice? = nil) {
        let usableDevices = devices.filter(\.isUsable)
        guard !usableDevices.isEmpty else {
            showDeepLinkLaunchFeedback(.failure("Connect a usable Android device before opening a link."))
            return
        }

        if let device, device.isUsable {
            deepLinkLauncherPreferredDeviceSerial = device.serial
        } else {
            deepLinkLauncherPreferredDeviceSerial = usableDevices.first?.serial
        }
        isPresentingDeepLinkLauncher = true
    }

    func dismissDeepLinkLauncher() {
        guard !isLaunchingDeepLink else {
            return
        }
        isPresentingDeepLinkLauncher = false
    }

    func launchDeepLink(_ deepLink: AndroidDeepLink, on device: AndroidDevice) {
        guard device.isUsable else {
            showDeepLinkLaunchFeedback(.failure("\(device.displayName) is not available for opening links."))
            return
        }
        guard let resolvedSDK else {
            showDeepLinkLaunchFeedback(.failure("ADB is not currently available. Device discovery will retry automatically."))
            return
        }
        guard deepLinkLaunchDeviceSerials.insert(device.serial).inserted else {
            return
        }

        deepLinkLaunchFeedback = nil
        AppLogger.deepLinks.info("Android deep link launch requested")
        let service = AndroidDeepLinkService(adbPath: resolvedSDK.adbPath, processRunner: processRunner)

        Task { [weak self] in
            let result = await service.launch(deepLink, on: device.serial)
            guard let self, !Task.isCancelled else {
                return
            }

            deepLinkLaunchDeviceSerials.remove(device.serial)
            isPresentingDeepLinkLauncher = false
            switch result {
            case .success(let outcome):
                showDeepLinkLaunchFeedback(.success(outcome, deviceName: device.displayName))
            case .failure(let failure):
                showDeepLinkLaunchFeedback(.failure(failure.message))
            }
        }
    }

    func clearDeepLinkLaunchFeedback(ifMatching feedback: DeepLinkLaunchFeedback) {
        guard deepLinkLaunchFeedback == feedback else {
            return
        }
        deepLinkLaunchFeedback = nil
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
        switch outcome {
        case .sdkUnavailable(let failure):
            applyDeviceState(
                sdk: nil,
                devices: [],
                status: .sdkUnavailable(failure)
            )
        case .adbResult(let sdk, .success(let devices)):
            applyDeviceState(
                sdk: sdk,
                devices: devices,
                status: devices.isEmpty ? .noDevices : .devicesAvailable
            )
        case .adbResult(let sdk, .failure(let error)):
            switch error {
            case .commandFailed(let message):
                applyDeviceState(
                    sdk: sdk,
                    devices: [],
                    status: .adbFailure(message)
                )
            }
        }
    }

    private func applyDeviceState(
        sdk: AndroidSDK?,
        devices: [AndroidDevice],
        status: DeviceDiscoveryStatus
    ) {
        if resolvedSDK != sdk {
            resolvedSDK = sdk
        }
        if self.devices != devices {
            self.devices = devices
        }
        let activeDeviceSerials = Set(devices.map(\.serial))
        let currentDetails = deviceDetailsBySerial.filter { activeDeviceSerials.contains($0.key) }
        if deviceDetailsBySerial != currentDetails {
            deviceDetailsBySerial = currentDetails
        }
        loadingDeviceDetailSerials.formIntersection(activeDeviceSerials)
        if self.status != status {
            self.status = status
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

    private func markScreenRecordingStarted(_ session: ScreenRecordingSession) {
        guard activeScreenRecording == session else {
            return
        }
        screenRecordingActivity = .recording(session)
        AppLogger.recording.info("Screen recording started")
    }

    private func finishScreenRecording(
        session: ScreenRecordingSession,
        result: ScreenRecordingResult
    ) {
        guard activeScreenRecording == session else {
            return
        }

        activeScreenRecording = nil
        screenRecordingActivity = nil

        switch result {
        case .success(let output, let warning):
            let copiedToClipboard = copyRecordingToClipboardIfNeeded(at: output.primaryFileURL)
            revealMediaInFinderIfNeeded(at: output.savedFileURLs)
            AppLogger.recording.info("Screen recording saved")
            showScreenRecordingFeedback(
                .success(output.primaryFileURL, warning: warning, copiedToClipboard: copiedToClipboard)
            )

            let mediaNotifier = mediaNotifier
            Task {
                await mediaNotifier.notifyAboutSavedMedia(
                    at: output.primaryFileURL,
                    kind: .recording(copiedToClipboard: copiedToClipboard)
                )
            }
        case .failure(let error):
            AppLogger.recording.error("Screen recording failed: \(error.message, privacy: .public)")
            showScreenRecordingFeedback(.failure(error.message))
        }
    }

    private func showScreenRecordingFeedback(_ feedback: ScreenRecordingFeedback) {
        screenRecordingFeedback = feedback
        let timeout: Duration = feedback.isSuccess ? .seconds(6) : .seconds(8)

        Task { [weak self, feedback] in
            try? await Task.sleep(for: timeout)
            self?.clearScreenRecordingFeedback(ifMatching: feedback)
        }
    }

    private func beginAppAction(for device: AndroidDevice) -> AndroidAppActionsService? {
        guard device.isUsable else {
            showAppActionFeedback(.failure("\(device.displayName) is not available for app actions."))
            return nil
        }
        guard let resolvedSDK else {
            showAppActionFeedback(.failure("ADB is not currently available. Device discovery will retry automatically."))
            return nil
        }
        guard appActionDeviceSerials.insert(device.serial).inserted else {
            return nil
        }

        appActionFeedback = nil
        AppLogger.appActions.info("Foreground Android app action requested")
        return AndroidAppActionsService(adbPath: resolvedSDK.adbPath, processRunner: processRunner)
    }

    private func finishAppAction(
        for device: AndroidDevice,
        result: AndroidAppActionServiceResult<AndroidAppActionOutcome>
    ) {
        appActionDeviceSerials.remove(device.serial)

        switch result {
        case .success(let outcome):
            showAppActionFeedback(.success(outcome))
        case .failure(let failure):
            showAppActionFeedback(.failure(failure.message))
        }
    }

    private func showAppActionFeedback(_ feedback: AppActionFeedback) {
        appActionFeedback = feedback
        let timeout: Duration = feedback.isSuccess ? .seconds(4) : .seconds(8)

        Task { [weak self, feedback] in
            try? await Task.sleep(for: timeout)
            self?.clearAppActionFeedback(ifMatching: feedback)
        }
    }

    private func showDeepLinkLaunchFeedback(_ feedback: DeepLinkLaunchFeedback) {
        deepLinkLaunchFeedback = feedback
        let timeout: Duration = feedback.isSuccess ? .seconds(4) : .seconds(8)

        Task { [weak self, feedback] in
            try? await Task.sleep(for: timeout)
            self?.clearDeepLinkLaunchFeedback(ifMatching: feedback)
        }
    }

    private func showDeviceSettingFeedback(_ feedback: DeviceSettingFeedback) {
        deviceSettingFeedback = feedback
        let timeout: Duration = feedback.isSuccess ? .seconds(4) : .seconds(8)

        Task { [weak self, feedback] in
            try? await Task.sleep(for: timeout)
            self?.clearDeviceSettingFeedback(ifMatching: feedback)
        }
    }

    private func copyScreenshotToClipboardIfNeeded(at fileURL: URL) -> Bool {
        guard preferences.automaticallyCopyMedia else {
            return false
        }

        switch mediaClipboard.copyScreenshot(at: fileURL) {
        case .copied:
            AppLogger.screenshot.info("Copied screenshot to clipboard")
            return true
        case .failed(let message):
            AppLogger.screenshot.error("Could not copy screenshot to clipboard: \(message, privacy: .public)")
            return false
        }
    }

    private func copyRecordingToClipboardIfNeeded(at fileURL: URL) -> Bool {
        guard preferences.automaticallyCopyMedia else {
            return false
        }

        switch mediaClipboard.copyRecording(at: fileURL) {
        case .copied:
            AppLogger.recording.info("Copied recording to clipboard")
            return true
        case .failed(let message):
            AppLogger.recording.error("Could not copy recording to clipboard: \(message, privacy: .public)")
            return false
        }
    }

    private func revealMediaInFinderIfNeeded(at fileURLs: [URL]) {
        guard preferences.revealMediaInFinder else {
            return
        }
        for fileURL in fileURLs {
            mediaFinderRevealer.revealMedia(at: fileURL)
        }
        AppLogger.devices.info("Revealed saved media in Finder")
    }
}

private enum DeviceLoadOutcome {
    case sdkUnavailable(AndroidSDKFailure)
    case adbResult(AndroidSDK, ADBDeviceListResult)
}
