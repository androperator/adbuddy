import Foundation
import Observation

enum EmulatorDiscoveryStatus: Equatable {
    case loading
    case ready
    case unavailable(AndroidEmulatorFailure)
}

enum EmulatorFeedback: Equatable {
    case launchRequested(AndroidVirtualDevice)
    case failure(AndroidEmulatorFailure)

    var isSuccess: Bool {
        if case .launchRequested = self {
            return true
        }
        return false
    }

    var title: String {
        switch self {
        case .launchRequested:
            "Opening Android Emulator"
        case .failure(let failure):
            failure.title
        }
    }

    var detail: String {
        switch self {
        case .launchRequested(let virtualDevice):
            "\(virtualDevice.name) will open in its own window."
        case .failure(let failure):
            failure.detail
        }
    }
}

@MainActor
@Observable
final class EmulatorStore {
    private let sdkLocator: AndroidSDKLocator
    private let processRunner: any ProcessRunning
    private let applicationLauncher: any ApplicationProcessLaunching
    private var isLoadingVirtualDevices = false

    private(set) var virtualDevices: [AndroidVirtualDevice] = []
    private(set) var status: EmulatorDiscoveryStatus = .loading
    private(set) var feedback: EmulatorFeedback?

    init(
        sdkLocator: AndroidSDKLocator = AndroidSDKLocator(),
        processRunner: any ProcessRunning = ProcessRunner(),
        applicationLauncher: any ApplicationProcessLaunching = ApplicationProcessLauncher()
    ) {
        self.sdkLocator = sdkLocator
        self.processRunner = processRunner
        self.applicationLauncher = applicationLauncher
    }

    func refreshVirtualDevices() {
        guard !isLoadingVirtualDevices else {
            return
        }

        isLoadingVirtualDevices = true
        status = .loading
        AppLogger.emulator.debug("Refreshing installed Android virtual devices")

        Task { [weak self] in
            guard let self else {
                return
            }

            let result = await loadVirtualDevices()
            guard !Task.isCancelled else {
                return
            }

            apply(result)
            isLoadingVirtualDevices = false
        }
    }

    func launch(_ virtualDevice: AndroidVirtualDevice) {
        guard virtualDevices.contains(virtualDevice) else {
            return
        }

        switch sdkLocator.resolve() {
        case .found(let sdk):
            launch(virtualDevice, using: sdk)
        case .unavailable(let failure):
            showFeedback(.failure(.sdkUnavailable(failure)))
        }
    }

    private func launch(_ virtualDevice: AndroidVirtualDevice, using sdk: AndroidSDK) {
        let service = AndroidEmulatorService(
            sdk: sdk,
            processRunner: processRunner,
            applicationLauncher: applicationLauncher
        )
        switch service.launch(virtualDevice) {
        case .launched:
            showFeedback(.launchRequested(virtualDevice))
        case .failure(let failure):
            showFeedback(.failure(failure))
        }
    }

    func clearFeedback(ifMatching feedback: EmulatorFeedback) {
        guard self.feedback == feedback else {
            return
        }
        self.feedback = nil
    }

    private func loadVirtualDevices() async -> AndroidEmulatorVirtualDeviceListResult {
        switch sdkLocator.resolve() {
        case .found(let sdk):
            let service = AndroidEmulatorService(
                sdk: sdk,
                processRunner: processRunner,
                applicationLauncher: applicationLauncher
            )
            return await service.listVirtualDevices()
        case .unavailable(let failure):
            return .failure(.sdkUnavailable(failure))
        }
    }

    private func apply(_ result: AndroidEmulatorVirtualDeviceListResult) {
        switch result {
        case .success(let virtualDevices):
            if self.virtualDevices != virtualDevices {
                self.virtualDevices = virtualDevices
            }
            if status != .ready {
                status = .ready
            }
        case .failure(let failure):
            if !virtualDevices.isEmpty {
                virtualDevices = []
            }
            let unavailableStatus = EmulatorDiscoveryStatus.unavailable(failure)
            if status != unavailableStatus {
                status = unavailableStatus
            }
        }
    }

    private func showFeedback(_ feedback: EmulatorFeedback) {
        self.feedback = feedback
        let timeout: Duration = feedback.isSuccess ? .seconds(4) : .seconds(8)

        Task { [weak self, feedback] in
            try? await Task.sleep(for: timeout)
            self?.clearFeedback(ifMatching: feedback)
        }
    }
}
