import Foundation
import Observation

@MainActor
@Observable
final class DeviceStore {
    private let sdkLocator: AndroidSDKLocator
    private let processRunner: any ProcessRunning
    private var pollingTask: Task<Void, Never>?

    private(set) var devices: [AndroidDevice] = []
    private(set) var status: DeviceDiscoveryStatus = .loading
    private(set) var resolvedSDK: AndroidSDK?
    private(set) var isRefreshing = false

    init(
        sdkLocator: AndroidSDKLocator = AndroidSDKLocator(),
        processRunner: any ProcessRunning = ProcessRunner()
    ) {
        self.sdkLocator = sdkLocator
        self.processRunner = processRunner
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
        status = .loading
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
}

private enum DeviceLoadOutcome {
    case sdkUnavailable(AndroidSDKFailure)
    case adbResult(AndroidSDK, ADBDeviceListResult)
}
