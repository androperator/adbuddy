import Foundation
import Observation

enum LogcatStreamState: Equatable, Sendable {
    case connecting
    case streaming
    case waitingForApplication(String)
    case failed(String)
    case stopped
}

@MainActor
@Observable
final class LogcatStore {
    static let retentionLimit = 50_000
    private static let retentionTrimBatchSize = 500
    private let deviceSerial: String
    private let makeService: @Sendable (String) -> any LogcatStreaming
    private let makeApplicationService: @Sendable (String) -> any LogcatApplicationQuerying
    private let applicationRefreshInterval: Duration
    private var streamTask: Task<Void, Never>?
    private var applicationRefreshTask: Task<Void, Never>?
    private var adbPath: String?
    private var streamGeneration = 0
    private var activeStreamScope: LogcatStreamScope = .allApplications
    private var activeApplicationScope: LogcatApplicationScope = .allApplications
    private var latestRunningProcesses: [AndroidRunningProcess] = []
    private var packageUserID: Int?
    private var prefersUserIDFiltering = true

    private(set) var entries: [LogcatEntry] = []
    private(set) var streamState: LogcatStreamState = .connecting
    private(set) var applicationID: String?
    private(set) var runningApplicationIDs: [String] = []
    var minimumPriority: LogcatPriority = .debug

    var visibleEntries: [LogcatEntry] {
        entries.filter {
            $0.priority.severity >= minimumPriority.severity && activeApplicationScope.includes($0)
        }
    }

    init(
        deviceSerial: String,
        makeService: @escaping @Sendable (String) -> any LogcatStreaming = { adbPath in
            LogcatService(adbPath: adbPath, processRunner: StreamingProcessRunner())
        },
        makeApplicationService: @escaping @Sendable (String) -> any LogcatApplicationQuerying = { adbPath in
            LogcatApplicationService(adbPath: adbPath, processRunner: ProcessRunner())
        },
        applicationRefreshInterval: Duration = .seconds(1)
    ) {
        self.deviceSerial = deviceSerial
        self.makeService = makeService
        self.makeApplicationService = makeApplicationService
        self.applicationRefreshInterval = applicationRefreshInterval
    }

    func start(adbPath: String?) {
        guard let adbPath else {
            streamState = .connecting
            return
        }
        guard self.adbPath != adbPath || applicationRefreshTask == nil else {
            return
        }

        self.adbPath = adbPath
        beginApplicationMonitoring()

        if applicationID == nil {
            applyApplicationScope(.allApplications)
        } else {
            streamState = .waitingForApplication(applicationID!)
        }
    }

    func stop() {
        streamGeneration += 1
        streamTask?.cancel()
        applicationRefreshTask?.cancel()
        streamTask = nil
        applicationRefreshTask = nil
        streamState = .stopped
    }

    func selectApplicationID(_ enteredApplicationID: String) {
        let normalizedApplicationID = enteredApplicationID.trimmingCharacters(in: .whitespacesAndNewlines)
        let newApplicationID = normalizedApplicationID.isEmpty ? nil : normalizedApplicationID
        guard applicationID != newApplicationID else {
            return
        }

        applicationID = newApplicationID
        packageUserID = nil
        prefersUserIDFiltering = true
        activeApplicationScope = newApplicationID == nil ? .allApplications : .waitingForProcess
        beginApplicationMonitoring()

        if let newApplicationID {
            cancelStreamAndClearEntries()
            streamState = .waitingForApplication(newApplicationID)
        } else {
            applyApplicationScope(.allApplications)
        }
    }

    private func beginApplicationMonitoring() {
        guard let adbPath else {
            return
        }

        applicationRefreshTask?.cancel()
        let selectedApplicationID = applicationID
        let applicationService = makeApplicationService(adbPath)
        let serial = deviceSerial
        let refreshInterval = applicationRefreshInterval

        applicationRefreshTask = Task { [weak self] in
            let packageUserID: Int?
            if let selectedApplicationID {
                switch await applicationService.packageUserID(
                    for: selectedApplicationID,
                    deviceSerial: serial
                ) {
                case .success(let userID):
                    packageUserID = userID
                case .failure:
                    AppLogger.logcat.error("Could not resolve the selected Logcat application UID")
                    packageUserID = nil
                }
            } else {
                packageUserID = nil
            }

            while !Task.isCancelled {
                let result = await applicationService.runningProcesses(for: serial)
                guard !Task.isCancelled else {
                    return
                }

                switch result {
                case .success(let processes):
                    self?.receive(
                        runningProcesses: processes,
                        packageUserID: packageUserID,
                        selectedApplicationID: selectedApplicationID
                    )
                case .failure:
                    AppLogger.logcat.error("Could not refresh running Logcat applications")
                }

                do {
                    try await Task.sleep(for: refreshInterval)
                } catch {
                    return
                }
            }
        }
    }

    private func receive(
        runningProcesses: [AndroidRunningProcess],
        packageUserID: Int?,
        selectedApplicationID: String?
    ) {
        guard applicationID == selectedApplicationID else {
            return
        }

        latestRunningProcesses = runningProcesses
        self.packageUserID = packageUserID
        runningApplicationIDs = Array(Set(runningProcesses.compactMap(\.applicationID))).sorted()

        guard let selectedApplicationID else {
            applyApplicationScope(.allApplications)
            return
        }

        let scope = LogcatApplicationScope.resolve(
            packageID: selectedApplicationID,
            packageUserID: packageUserID,
            processes: runningProcesses,
            prefersUserIDFiltering: prefersUserIDFiltering
        )
        applyApplicationScope(scope)
    }

    private func applyApplicationScope(_ scope: LogcatApplicationScope) {
        let previousStreamScope = activeStreamScope
        activeApplicationScope = scope

        if case .waitingForProcess = scope {
            cancelStreamAndClearEntries()
            if let applicationID {
                streamState = .waitingForApplication(applicationID)
            }
            return
        }

        if streamTask == nil || previousStreamScope != scope.streamScope {
            restartStream(using: scope.streamScope)
        } else if scope.isWaitingForProcess, let applicationID {
            streamState = .waitingForApplication(applicationID)
        } else if case .waitingForApplication = streamState {
            streamState = .streaming
        }
    }

    private func restartStream(using scope: LogcatStreamScope) {
        guard let adbPath else {
            streamState = .connecting
            return
        }

        cancelStreamAndClearEntries()
        activeStreamScope = scope
        streamGeneration += 1
        let generation = streamGeneration
        let service = makeService(adbPath)
        let serial = deviceSerial

        if activeApplicationScope.isWaitingForProcess, let applicationID {
            streamState = .waitingForApplication(applicationID)
        } else {
            streamState = .connecting
        }

        streamTask = Task { [weak self] in
            for await event in service.stream(for: serial, scope: scope) {
                guard !Task.isCancelled else {
                    return
                }
                self?.receive(event, generation: generation)
            }
        }

        if !activeApplicationScope.isWaitingForProcess {
            streamState = .streaming
        }
    }

    private func cancelStreamAndClearEntries() {
        streamGeneration += 1
        streamTask?.cancel()
        streamTask = nil
        entries.removeAll(keepingCapacity: false)
    }

    private func receive(_ event: LogcatServiceEvent, generation: Int) {
        guard generation == streamGeneration else {
            return
        }

        switch event {
        case .entries(let newEntries):
            append(newEntries)
            if !activeApplicationScope.isWaitingForProcess {
                streamState = .streaming
            }
        case .failed(let failure):
            if shouldFallBackToProcessIDFiltering(for: failure) {
                prefersUserIDFiltering = false
                guard let applicationID else {
                    streamState = .failed(message(for: failure))
                    return
                }
                let scope = LogcatApplicationScope.resolve(
                    packageID: applicationID,
                    packageUserID: packageUserID,
                    processes: latestRunningProcesses,
                    prefersUserIDFiltering: false
                )
                applyApplicationScope(scope)
            } else {
                streamState = .failed(message(for: failure))
            }
        case .stopped, .cancelled:
            streamState = .stopped
        }
    }

    private func shouldFallBackToProcessIDFiltering(for failure: LogcatServiceFailure) -> Bool {
        guard case .userID = activeStreamScope else {
            return false
        }

        let message: String
        switch failure {
        case .launchFailed(let description):
            message = description
        case .terminated(_, let standardError):
            message = standardError
        }

        let normalizedMessage = message.lowercased()
        return normalizedMessage.contains("uid") && (
            normalizedMessage.contains("unknown") ||
            normalizedMessage.contains("unsupported") ||
            normalizedMessage.contains("invalid") ||
            normalizedMessage.contains("option")
        )
    }

    private func append(_ newEntries: [LogcatEntry]) {
        guard !newEntries.isEmpty else {
            return
        }

        entries.append(contentsOf: newEntries)
        while entries.count > Self.retentionLimit {
            let overflow = entries.count - Self.retentionLimit
            let removalCount = min(
                max(overflow, Self.retentionTrimBatchSize),
                entries.count
            )
            entries.removeFirst(removalCount)
        }
    }

    private func message(for failure: LogcatServiceFailure) -> String {
        switch failure {
        case .launchFailed(let description):
            "Could not start Logcat: \(description)"
        case .terminated(let exitStatus, let standardError):
            "Logcat exited with status \(exitStatus): \(standardError)"
        }
    }
}
