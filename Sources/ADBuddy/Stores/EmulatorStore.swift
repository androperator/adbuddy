import Foundation
import Observation

enum EmulatorDiscoveryStatus: Equatable {
    case loading
    case ready
    case unavailable(AndroidEmulatorFailure)
}

enum EmulatorFeedback: Equatable {
    case startRequested(AndroidVirtualDevice, AndroidEmulatorStartMode)
    case stopRequested(AndroidVirtualDevice)
    case windowActivationFailed(AndroidVirtualDevice)
    case failure(AndroidEmulatorFailure)

    var isSuccess: Bool {
        switch self {
        case .startRequested, .stopRequested:
            return true
        case .windowActivationFailed, .failure:
            return false
        }
    }

    var title: String {
        switch self {
        case .startRequested:
            "Starting Android Emulator"
        case .stopRequested:
            "Stopping Android Emulator"
        case .windowActivationFailed:
            "Could Not Reveal Host Window"
        case .failure(let failure):
            failure.title
        }
    }

    var detail: String {
        switch self {
        case .startRequested(let virtualDevice, let mode):
            "\(mode.displayName) requested for \(virtualDevice.name)."
        case .stopRequested(let virtualDevice):
            "Stop requested for \(virtualDevice.name)."
        case .windowActivationFailed(let virtualDevice):
            "No host macOS window is available for \(virtualDevice.name)."
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
    private var pollingTask: Task<Void, Never>?
    private var isLoadingVirtualDevices = false
    private var connectedEmulatorDevices: [AndroidDevice] = []
    private var resolvedSDK: AndroidSDK?
    private var runningStatusRefreshID = UUID()
    private var emulatorWindowPresentations: [String: EmulatorWindowPresentation] = [:]

    private(set) var virtualDevices: [AndroidVirtualDevice] = []
    private(set) var status: EmulatorDiscoveryStatus = .loading
    private(set) var feedback: EmulatorFeedback?
    var deleteConfirmationVirtualDevice: AndroidVirtualDevice?
    var deletionError: String?
    private(set) var deletingNames: Set<String> = []
    private var discoveryRevision = UUID()
    var wipeDataConfirmationVirtualDevice: AndroidVirtualDevice?

    init(
        sdkLocator: AndroidSDKLocator = AndroidSDKLocator(),
        processRunner: any ProcessRunning = ProcessRunner(),
        applicationLauncher: any ApplicationProcessLaunching = ApplicationProcessLauncher()
    ) {
        self.sdkLocator = sdkLocator
        self.processRunner = processRunner
        self.applicationLauncher = applicationLauncher
    }

    func start() {
        guard pollingTask == nil else {
            return
        }
        refreshVirtualDevices()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
                guard let self else {
                    return
                }
                self.refreshVirtualDevices()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refreshVirtualDevices() {
        guard !isLoadingVirtualDevices, deletingNames.isEmpty else {
            return
        }

        let revision = discoveryRevision
        isLoadingVirtualDevices = true
        AppLogger.emulator.debug("Refreshing installed Android virtual devices")

        Task { [weak self] in
            guard let self else {
                return
            }

            let result = await loadVirtualDevices()
            guard !Task.isCancelled else {
                return
            }

            if revision == discoveryRevision { apply(result) }
            isLoadingVirtualDevices = false
        }
    }

    func updateRunningStatus(using devices: [AndroidDevice], sdk: AndroidSDK?) {
        let emulatorDevices = devices.filter { $0.kind == .emulator }
        let hasChanged = connectedEmulatorDevices != emulatorDevices || resolvedSDK != sdk
        connectedEmulatorDevices = emulatorDevices
        resolvedSDK = sdk

        guard hasChanged, status == .ready else {
            return
        }

        refreshRunningStatuses()
    }

    func registerCreatedVirtualDevice(name: String, startAfterCreation: Bool = false) {
        let virtualDevice = AndroidVirtualDevice(name: name)
        if !virtualDevices.contains(where: { $0.name == name }) {
            virtualDevices.append(virtualDevice)
        }
        if startAfterCreation { start(virtualDevice) }
        refreshVirtualDevices()
    }

    func start(_ virtualDevice: AndroidVirtualDevice, mode: AndroidEmulatorStartMode = .quickBoot) {
        guard !deletingNames.contains(virtualDevice.name),
              virtualDevices.first(where: { $0.id == virtualDevice.id })?.status == .stopped,
              let sdk = resolvedSDK ?? locatedSDK else {
            return
        }

        updateStatus(.starting, for: virtualDevice)
        let service = emulatorService(using: sdk)
        switch service.start(virtualDevice, mode: mode) {
        case .launched:
            showFeedback(.startRequested(virtualDevice, mode))
        case .failure(let failure):
            updateStatus(.stopped, for: virtualDevice)
            showFeedback(.failure(failure))
        }
    }

    func requestDelete(_ virtualDevice: AndroidVirtualDevice) {
        guard deletingNames.isEmpty,
              virtualDevices.first(where: { $0.id == virtualDevice.id })?.status == .stopped else { return }
        deleteConfirmationVirtualDevice = virtualDevice
    }

    func confirmDelete(_ virtualDevice: AndroidVirtualDevice, configuration: EmulatorHelperConfiguration) async {
        deleteConfirmationVirtualDevice = nil
        guard deletingNames.isEmpty,
              virtualDevices.first(where: { $0.id == virtualDevice.id })?.status == .stopped else {
            deletionError = "The emulator is no longer stopped. Stop it before deleting."
            return
        }
        deletingNames.insert(virtualDevice.name)
        discoveryRevision = UUID()
        defer {
            deletingNames.remove(virtualDevice.name)
            discoveryRevision = UUID()
            refreshVirtualDevices()
        }
        do {
            guard let sdk = resolvedSDK ?? locatedSDK else { throw EmulatorCreationError("Android SDK not found.") }
            let service = EmulatorCreationService(invocation: try EmulatorHelperInvocation.resolve(configuration: configuration, sdk: sdk))
            _ = try await service.check(requiresCatalogs: false)
            // The helper rechecks live ADB state and refuses running/offline AVDs.
            AppLogger.emulator.info("Deleting stopped Android virtual device")
            try await service.delete(name: virtualDevice.name)
            virtualDevices.removeAll { $0.name == virtualDevice.name }
        } catch {
            deletionError = error.localizedDescription
            AppLogger.emulator.error("Emulator deletion failed")
        }
    }

    func requestWipeDataAndStart(_ virtualDevice: AndroidVirtualDevice) {
        guard !deletingNames.contains(virtualDevice.name),
              virtualDevices.first(where: { $0.id == virtualDevice.id })?.status == .stopped else {
            return
        }
        wipeDataConfirmationVirtualDevice = virtualDevice
    }

    func cancelWipeDataAndStart() {
        wipeDataConfirmationVirtualDevice = nil
    }

    func confirmWipeDataAndStart(_ virtualDevice: AndroidVirtualDevice) {
        wipeDataConfirmationVirtualDevice = nil
        start(virtualDevice, mode: .wipeData)
    }

    func stop(_ virtualDevice: AndroidVirtualDevice) {
        guard case .running(let device) = virtualDevices.first(where: { $0.id == virtualDevice.id })?.status,
              let sdk = resolvedSDK ?? locatedSDK else {
            return
        }

        updateStatus(.stopping(device), for: virtualDevice)
        let service = emulatorService(using: sdk)
        Task { [weak self] in
            let result = await service.stop(device)
            guard let self,
                  case .stopping = self.virtualDevices.first(where: { $0.id == virtualDevice.id })?.status else {
                return
            }

            switch result {
            case .stopped:
                self.showFeedback(.stopRequested(virtualDevice))
            case .failure(let failure):
                self.updateStatus(.running(device), for: virtualDevice)
                self.showFeedback(.failure(failure))
            }
        }
    }

    func windowPresentation(for virtualDevice: AndroidVirtualDevice) -> EmulatorWindowPresentation {
        emulatorWindowPresentations[virtualDevice.name] ?? .unknown
    }

    func revealHostWindow(for virtualDevice: AndroidVirtualDevice) {
        let presentation = windowPresentation(for: virtualDevice)
        let wasActivated: Bool

        switch presentation {
        case .standalone(let processIdentifier):
            wasActivated = EmulatorWindowService.activateStandaloneWindow(
                processIdentifier: processIdentifier
            )
        case .embeddedInAndroidStudio:
            wasActivated = EmulatorWindowService.activateAndroidStudioWindow()
        case .headless, .unknown:
            return
        }

        guard wasActivated else {
            showFeedback(.windowActivationFailed(virtualDevice))
            return
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
            resolvedSDK = sdk
            let service = emulatorService(using: sdk)
            return await service.listVirtualDevices()
        case .unavailable(let failure):
            return .failure(.sdkUnavailable(failure))
        }
    }

    private func apply(_ result: AndroidEmulatorVirtualDeviceListResult) {
        switch result {
        case .success(let virtualDevices):
            let currentDevices = Dictionary(uniqueKeysWithValues: self.virtualDevices.map { ($0.id, $0) })
            let deviceDetailsService = resolvedSDK.map {
                AndroidVirtualDeviceDetailsService(sdkRootPath: $0.rootPath)
            }
            let updatedDevices = virtualDevices.map { virtualDevice in
                AndroidVirtualDevice(
                    name: virtualDevice.name,
                    status: currentDevices[virtualDevice.id]?.status ?? .stopped,
                    deviceDetails: deviceDetailsService?.details(for: virtualDevice)
                        ?? currentDevices[virtualDevice.id]?.deviceDetails
                )
            }
            if self.virtualDevices != updatedDevices {
                self.virtualDevices = updatedDevices
            }
            if status != .ready {
                status = .ready
            }
            refreshRunningStatuses()
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

    private var locatedSDK: AndroidSDK? {
        guard case .found(let sdk) = sdkLocator.resolve() else {
            return nil
        }
        return sdk
    }

    private func emulatorService(using sdk: AndroidSDK) -> AndroidEmulatorService {
        AndroidEmulatorService(
            sdk: sdk,
            processRunner: processRunner,
            applicationLauncher: applicationLauncher
        )
    }

    private func refreshRunningStatuses() {
        guard status == .ready, let sdk = resolvedSDK else {
            return
        }

        let refreshID = UUID()
        runningStatusRefreshID = refreshID
        let service = emulatorService(using: sdk)
        let emulatorDevices = connectedEmulatorDevices
        let windowService = EmulatorWindowService(processRunner: processRunner)

        Task { [weak self] in
            let runningDevices = await service.runningVirtualDevices(in: emulatorDevices)
            let windowPresentations = await windowService.discoverWindowPresentations()
            guard let self, self.runningStatusRefreshID == refreshID else {
                return
            }
            self.applyRunningStatuses(runningDevices)
            self.emulatorWindowPresentations = windowPresentations
        }
    }

    private func applyRunningStatuses(_ runningDevices: [String: AndroidDevice]) {
        let updatedDevices = EmulatorVirtualDeviceStatusResolver.reconciledVirtualDevices(
            virtualDevices,
            runningDevices: runningDevices
        )

        if virtualDevices != updatedDevices {
            virtualDevices = updatedDevices
        }
    }

    private func updateStatus(_ status: AndroidVirtualDeviceStatus, for virtualDevice: AndroidVirtualDevice) {
        guard let index = virtualDevices.firstIndex(where: { $0.id == virtualDevice.id }),
              virtualDevices[index].status != status else {
            return
        }
        virtualDevices[index].status = status
    }
}
