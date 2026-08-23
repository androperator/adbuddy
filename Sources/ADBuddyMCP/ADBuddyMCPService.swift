import ADBuddyCore
import Foundation

enum ADBuddyMCPServiceError: LocalizedError, Sendable {
    case sdkUnavailable(AndroidSDKFailure)
    case adbFailure(String)
    case emulatorFailure(AndroidEmulatorFailure)
    case deviceNotFound(String)
    case deviceUnavailable(String)
    case notAnEmulator(String)
    case virtualDeviceNotFound(String)
    case screenshotFailure(ScreenshotCaptureError)
    case recordingAlreadyActive(String)
    case recordingNotFound(String)
    case recordingStartFailed(String)
    case recordingStopFailed(String)

    var errorDescription: String? {
        switch self {
        case .sdkUnavailable(let failure):
            failure.detail
        case .adbFailure(let message), .recordingStartFailed(let message), .recordingStopFailed(let message):
            message
        case .emulatorFailure(let failure):
            failure.detail
        case .deviceNotFound(let serial):
            "No connected Android device has serial \(serial)."
        case .deviceUnavailable(let serial):
            "Android device \(serial) is not connected and authorized."
        case .notAnEmulator(let serial):
            "Android device \(serial) is not an emulator."
        case .virtualDeviceNotFound(let name):
            "No installed Android Virtual Device is named \(name)."
        case .screenshotFailure(let error):
            error.message
        case .recordingAlreadyActive(let serial):
            "A screen recording is already active for \(serial). Stop it before starting another recording."
        case .recordingNotFound(let recordingID):
            "No active screen recording has ID \(recordingID)."
        }
    }
}

actor ADBuddyMCPService {
    private let sdkLocator: AndroidSDKLocator
    private let processRunner: any ProcessRunning
    private var recordings: [String: ManagedRecording] = [:]
    private var stoppingRecordingIDs = Set<String>()

    init(
        sdkLocator: AndroidSDKLocator = AndroidSDKLocator(),
        processRunner: any ProcessRunning = ProcessRunner()
    ) {
        self.sdkLocator = sdkLocator
        self.processRunner = processRunner
    }

    func listDevices() async throws -> Data {
        let (_, devices) = try await resolvedSDKAndDevices()
        return try encodedPayload(["devices": devices.map { device in
            [
                "serial": device.serial,
                "name": device.displayName,
                "state": device.connectionState.adbValue,
                "kind": device.kind == .emulator ? "emulator" : "physical",
            ]
        }])
    }

    func listEmulators() async throws -> Data {
        let (sdk, devices) = try await resolvedSDKAndDevices()
        let service = AndroidEmulatorService(sdk: sdk, processRunner: processRunner)
        let virtualDevices: [AndroidVirtualDevice]
        switch await service.listVirtualDevices() {
        case .success(let values):
            virtualDevices = values
        case .failure(let failure):
            throw ADBuddyMCPServiceError.emulatorFailure(failure)
        }

        let runningDevices = await service.runningVirtualDevices(in: devices)
        return try encodedPayload(["emulators": virtualDevices.map { virtualDevice in
            var result: [String: Any] = ["name": virtualDevice.name]
            if let device = runningDevices[virtualDevice.name] {
                result["state"] = "running"
                result["serial"] = device.serial
            } else {
                result["state"] = "stopped"
            }
            return result
        }])
    }

    func startEmulator(named name: String, mode: AndroidEmulatorStartMode) async throws -> Data {
        let (sdk, devices) = try await resolvedSDKAndDevices()
        let service = AndroidEmulatorService(sdk: sdk, processRunner: processRunner)
        let virtualDevices: [AndroidVirtualDevice]
        switch await service.listVirtualDevices() {
        case .success(let values):
            virtualDevices = values
        case .failure(let failure):
            throw ADBuddyMCPServiceError.emulatorFailure(failure)
        }

        guard let virtualDevice = virtualDevices.first(where: { $0.name == name }) else {
            throw ADBuddyMCPServiceError.virtualDeviceNotFound(name)
        }

        if let runningDevice = await service.runningVirtualDevices(in: devices)[name] {
            AppLogger.emulator.info("MCP emulator start resolved to an already-running AVD")
            return try encodedPayload([
                "name": name,
                "mode": mode.mcpValue,
                "serial": runningDevice.serial,
                "state": "running",
            ])
        }

        switch service.start(virtualDevice, mode: mode) {
        case .launched:
            AppLogger.emulator.info("MCP requested Android Emulator start")
            return try encodedPayload([
                "name": name,
                "mode": mode.mcpValue,
                "state": "starting",
            ])
        case .failure(let failure):
            throw ADBuddyMCPServiceError.emulatorFailure(failure)
        }
    }

    func stopEmulator(serial: String) async throws -> Data {
        let (sdk, devices) = try await resolvedSDKAndDevices()
        let device = try usableDevice(serial: serial, from: devices)
        guard device.kind == .emulator else {
            throw ADBuddyMCPServiceError.notAnEmulator(serial)
        }

        switch await AndroidEmulatorService(sdk: sdk, processRunner: processRunner).stop(device) {
        case .stopped:
            AppLogger.emulator.info("MCP requested Android Emulator stop")
            return try encodedPayload(["serial": serial, "state": "stopping"])
        case .failure(let failure):
            throw ADBuddyMCPServiceError.emulatorFailure(failure)
        }
    }

    func takeScreenshot(serial: String) async throws -> Data {
        let (sdk, devices) = try await resolvedSDKAndDevices()
        let device = try usableDevice(serial: serial, from: devices)
        let destination = ADBuddySharedPreferences.mediaDestination()
        AppLogger.screenshot.info("MCP screenshot capture requested")
        let result = await ScreenshotService(
            adbPath: sdk.adbPath,
            sdkRootPath: sdk.rootPath,
            processRunner: processRunner
        ).capture(
            device: device,
            destination: destination,
            framing: ADBuddySharedPreferences.screenshotFramingOptions()
        )

        switch result {
        case .success(let output):
            AppLogger.screenshot.info("MCP screenshot capture succeeded")
            var payload: [String: Any] = [
                "serial": serial,
                "path": output.primaryFileURL.path,
                "mediaType": "image/png",
            ]
            if let originalFileURL = output.originalFileURL {
                payload["originalPath"] = originalFileURL.path
            }
            return try encodedPayload(payload)
        case .failure(let error):
            throw ADBuddyMCPServiceError.screenshotFailure(error)
        }
    }

    func startScreenRecording(
        serial: String,
        bitRateMegabitsPerSecond: Int?,
        resolutionPercentage: Int?,
        showsTaps: Bool?
    ) async throws -> Data {
        guard recordings.values.contains(where: { $0.session.device.serial == serial }) == false else {
            throw ADBuddyMCPServiceError.recordingAlreadyActive(serial)
        }

        let (sdk, devices) = try await resolvedSDKAndDevices()
        let device = try usableDevice(serial: serial, from: devices)
        let options = try recordingOptions(
            bitRateMegabitsPerSecond: bitRateMegabitsPerSecond,
            resolutionPercentage: resolutionPercentage,
            showsTaps: showsTaps
        )
        let session = ScreenRecordingSession(device: device)
        let readiness = RecordingReadiness()
        let recordingService = ScreenRecordingService(adbPath: sdk.adbPath, processRunner: processRunner)
        let destination = ADBuddySharedPreferences.mediaDestination()
        AppLogger.recording.info("MCP screen recording requested")
        let task = Task {
            let result = await recordingService.record(
                session: session,
                options: options,
                destination: destination,
                onScreenRecorderStarted: {
                    Task {
                        await readiness.markStarted()
                    }
                }
            )
            await readiness.markFinishedIfNeeded(with: result)
            return result
        }
        let recordingID = UUID().uuidString
        recordings[recordingID] = ManagedRecording(session: session, task: task)

        switch await readiness.waitForStart() {
        case .started:
            AppLogger.recording.info("MCP screen recording started")
            return try encodedPayload([
                "recordingId": recordingID,
                "serial": serial,
                "state": "recording",
            ])
        case .failed(let message):
            recordings[recordingID] = nil
            _ = await task.value
            throw ADBuddyMCPServiceError.recordingStartFailed(message)
        case .waiting:
            fatalError("Recording readiness returned before a terminal state.")
        }
    }

    func stopScreenRecording(recordingID: String) async throws -> Data {
        guard let recording = recordings[recordingID] else {
            throw ADBuddyMCPServiceError.recordingNotFound(recordingID)
        }
        guard stoppingRecordingIDs.insert(recordingID).inserted else {
            throw ADBuddyMCPServiceError.recordingStopFailed("Screen recording \(recordingID) is already stopping.")
        }

        AppLogger.recording.info("MCP screen recording stop requested")
        defer {
            stoppingRecordingIDs.remove(recordingID)
        }

        let (_, devices) = try await resolvedSDKAndDevices()
        let sdk = try resolvedSDK()
        let recordingService = ScreenRecordingService(adbPath: sdk.adbPath, processRunner: processRunner)
        let activeDevice = try usableDevice(serial: recording.session.device.serial, from: devices)
        guard activeDevice.serial == recording.session.device.serial else {
            throw ADBuddyMCPServiceError.deviceUnavailable(recording.session.device.serial)
        }

        switch await recordingService.stop(session: recording.session) {
        case .stopped:
            break
        case .failure(let message):
            throw ADBuddyMCPServiceError.recordingStopFailed(message)
        }

        let result = await recording.task.value
        recordings[recordingID] = nil
        switch result {
        case .success(let fileURL, let warning):
            AppLogger.recording.info("MCP screen recording saved")
            var response: [String: Any] = [
                "recordingId": recordingID,
                "path": fileURL.path,
                "mediaType": "video/mp4",
            ]
            if let warning {
                response["warning"] = warning
            }
            return try encodedPayload(response)
        case .failure(let error):
            throw ADBuddyMCPServiceError.recordingStopFailed(error.message)
        }
    }

    func stopAllScreenRecordings() async {
        let activeRecordings = recordings
        let sdk: AndroidSDK?
        if case .found(let foundSDK) = sdkLocator.resolve() {
            sdk = foundSDK
        } else {
            sdk = nil
        }

        guard let sdk else {
            return
        }
        let recordingService = ScreenRecordingService(adbPath: sdk.adbPath, processRunner: processRunner)
        for recording in activeRecordings.values {
            _ = await recordingService.stop(session: recording.session)
        }
    }

    private func resolvedSDKAndDevices() async throws -> (AndroidSDK, [AndroidDevice]) {
        let sdk = try resolvedSDK()
        let result = await ADBClient(adbPath: sdk.adbPath, processRunner: processRunner).listDevices()
        switch result {
        case .success(let devices):
            return (sdk, devices)
        case .failure(let error):
            switch error {
            case .commandFailed(let message):
                throw ADBuddyMCPServiceError.adbFailure(message)
            }
        }
    }

    private func resolvedSDK() throws -> AndroidSDK {
        switch sdkLocator.resolve() {
        case .found(let sdk):
            return sdk
        case .unavailable(let failure):
            throw ADBuddyMCPServiceError.sdkUnavailable(failure)
        }
    }

    private func usableDevice(serial: String, from devices: [AndroidDevice]) throws -> AndroidDevice {
        guard let device = devices.first(where: { $0.serial == serial }) else {
            throw ADBuddyMCPServiceError.deviceNotFound(serial)
        }
        guard device.isUsable else {
            throw ADBuddyMCPServiceError.deviceUnavailable(serial)
        }
        return device
    }

    private func recordingOptions(
        bitRateMegabitsPerSecond: Int?,
        resolutionPercentage: Int?,
        showsTaps: Bool?
    ) throws -> ScreenRecordingOptions {
        let savedOptions = ADBuddySharedPreferences.screenRecordingOptions()
        let resolution = resolutionPercentage.flatMap(ScreenRecordingResolution.init(rawValue:)) ?? savedOptions.resolution
        let options = ScreenRecordingOptions(
            bitRateMegabitsPerSecond: bitRateMegabitsPerSecond ?? savedOptions.bitRateMegabitsPerSecond,
            resolution: resolution,
            showsTaps: showsTaps ?? savedOptions.showsTaps
        )
        if let message = options.validationMessage {
            throw ADBuddyMCPServiceError.recordingStartFailed(message)
        }
        if let resolutionPercentage,
           ScreenRecordingResolution(rawValue: resolutionPercentage) == nil {
            throw ADBuddyMCPServiceError.recordingStartFailed(
                "resolutionPercentage must be one of 100, 75, 50, or 25."
            )
        }
        return options
    }

    private func encodedPayload(_ payload: [String: Any]) throws -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        } catch {
            throw ADBuddyMCPServiceError.recordingStartFailed("Could not encode an MCP response.")
        }
    }
}

private struct ManagedRecording: Sendable {
    let session: ScreenRecordingSession
    let task: Task<ScreenRecordingResult, Never>
}

private actor RecordingReadiness {
    enum State {
        case waiting
        case started
        case failed(String)
    }

    private var state: State = .waiting
    private var continuation: CheckedContinuation<State, Never>?

    func markStarted() {
        guard case .waiting = state else {
            return
        }
        state = .started
        continuation?.resume(returning: state)
        continuation = nil
    }

    func markFinishedIfNeeded(with result: ScreenRecordingResult) {
        guard case .waiting = state else {
            return
        }
        let message: String
        switch result {
        case .success:
            message = "Screen recording finished before it could be started."
        case .failure(let error):
            message = error.message
        }
        state = .failed(message)
        continuation?.resume(returning: state)
        continuation = nil
    }

    func waitForStart() async -> State {
        if case .waiting = state {
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        return state
    }
}

private extension DeviceConnectionState {
    var adbValue: String {
        switch self {
        case .connected:
            "device"
        case .unauthorized:
            "unauthorized"
        case .offline:
            "offline"
        case .bootloader:
            "bootloader"
        case .recovery:
            "recovery"
        case .sideload:
            "sideload"
        case .unknown(let value):
            value
        }
    }
}

private extension AndroidEmulatorStartMode {
    var mcpValue: String {
        switch self {
        case .quickBoot:
            "quick_boot"
        case .coldBoot:
            "cold_boot"
        case .wipeData:
            "wipe_data"
        }
    }
}
