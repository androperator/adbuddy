import Foundation
import Observation

enum LogcatStreamState: Equatable, Sendable {
    case connecting
    case streaming
    case paused
    case disconnected
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
    private let reconnectDelay: @Sendable (Int) -> Duration
    private var streamTask: Task<Void, Never>?
    private var applicationRefreshTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var adbPath: String?
    private var streamGeneration = 0
    private var reconnectGeneration = 0
    private var failedReconnectAttempts = 0
    private var isDeviceUsable = false
    private var isStopped = false
    private var activeStreamScope: LogcatStreamScope = .allApplications
    private var activeApplicationScope: LogcatApplicationScope = .allApplications
    private var latestRunningProcesses: [AndroidRunningProcess] = []
    private var applicationIDsByProcessID: [Int: String] = [:]
    private var packageUserID: Int?
    private var prefersUserIDFiltering = true
    private var pausedEntries: [LogcatEntry]?
    private var followedLatestBeforePausing = true

    private(set) var entries: [LogcatEntry] = []
    private(set) var visibleEntries: [LogcatEntry] = []
    private(set) var displayedEntryRevision: UInt64 = 0
    private(set) var applicationIDRevision: UInt64 = 0
    private(set) var streamState: LogcatStreamState = .connecting
    private(set) var applicationID: String?
    private(set) var runningApplicationIDs: [String] = []
    private(set) var isFollowing = true
    private(set) var isPaused = false
    var searchText = "" {
        didSet {
            guard oldValue != searchText else {
                return
            }
            rebuildVisibleEntries()
        }
    }
    var minimumPriority: LogcatPriority = .debug {
        didSet {
            guard oldValue != minimumPriority else {
                return
            }
            rebuildVisibleEntries()
        }
    }
    var showsOnlyCrashesAndExceptions = false {
        didSet {
            guard oldValue != showsOnlyCrashesAndExceptions else {
                return
            }
            rebuildVisibleEntries()
        }
    }

    var displayedEntries: [LogcatEntry] {
        pausedEntries ?? visibleEntries
    }

    var displayedEntryCount: Int {
        pausedEntries?.count ?? visibleEntries.count
    }

    func displayedEntry(at index: Int) -> LogcatEntry? {
        let displayedEntries = pausedEntries ?? visibleEntries
        guard displayedEntries.indices.contains(index) else {
            return nil
        }
        return displayedEntries[index]
    }

    func applicationID(for processID: Int) -> String? {
        applicationIDsByProcessID[processID]
    }

    var displayedStreamState: LogcatStreamState {
        guard isPaused else {
            return streamState
        }

        switch streamState {
        case .disconnected, .failed:
            return streamState
        default:
            return .paused
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
        applicationRefreshInterval: Duration = .seconds(1),
        reconnectDelay: @escaping @Sendable (Int) -> Duration = { failedAttempts in
            LogcatReconnectPolicy.delay(for: failedAttempts)
        }
    ) {
        self.deviceSerial = deviceSerial
        self.makeService = makeService
        self.makeApplicationService = makeApplicationService
        self.applicationRefreshInterval = applicationRefreshInterval
        self.reconnectDelay = reconnectDelay
    }

    func start(adbPath: String?) {
        guard let adbPath else {
            streamState = .connecting
            return
        }

        updateDeviceAvailability(.usable(adbPath: adbPath))
    }

    func updateDeviceAvailability(_ availability: LogcatDeviceAvailability) {
        guard !isStopped else {
            return
        }

        guard case .usable(let adbPath) = availability else {
            handleDeviceUnavailable()
            return
        }

        let needsConnection = !isDeviceUsable || self.adbPath != adbPath || applicationRefreshTask == nil
        isDeviceUsable = true
        self.adbPath = adbPath
        guard needsConnection else {
            return
        }

        cancelReconnectWork()
        beginApplicationMonitoring()

        if applicationID == nil {
            applyApplicationScope(.allApplications, clearingEntries: false)
        } else {
            streamState = .waitingForApplication(applicationID!)
        }
    }

    func stop() {
        isStopped = true
        isDeviceUsable = false
        cancelReconnectWork()
        cancelStream()
        applicationRefreshTask?.cancel()
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
        let initialScope: LogcatApplicationScope = newApplicationID == nil ? .allApplications : .waitingForProcess
        if activeApplicationScope != initialScope {
            activeApplicationScope = initialScope
            rebuildVisibleEntries()
        }
        guard isDeviceUsable, !isStopped else {
            streamState = .disconnected
            return
        }

        beginApplicationMonitoring()

        if let newApplicationID {
            cancelStreamAndClearEntries()
            streamState = .waitingForApplication(newApplicationID)
        } else {
            applyApplicationScope(.allApplications, clearingEntries: true)
        }
    }

    func userScrolledAwayFromLatest() {
        isFollowing = false
    }

    func jumpToLatest() {
        isFollowing = true
    }

    func togglePause() {
        if isPaused {
            isPaused = false
            pausedEntries = nil
            isFollowing = followedLatestBeforePausing
            markDisplayedEntriesChanged()
        } else {
            followedLatestBeforePausing = isFollowing
            pausedEntries = visibleEntries
            isPaused = true
        }
    }

    func clear() {
        entries.removeAll(keepingCapacity: true)
        visibleEntries.removeAll(keepingCapacity: true)
        pausedEntries = isPaused ? [] : nil
        markDisplayedEntriesChanged()
    }

    private func beginApplicationMonitoring() {
        guard isDeviceUsable, !isStopped, let adbPath else {
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
        updateApplicationIDsByProcessID(from: runningProcesses)

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

    private func updateApplicationIDsByProcessID(from processes: [AndroidRunningProcess]) {
        let updatedApplicationIDs = processes.reduce(into: [Int: String]()) { applicationIDs, process in
            guard let applicationID = process.applicationID else {
                return
            }
            applicationIDs[process.processID] = applicationID
        }
        guard applicationIDsByProcessID != updatedApplicationIDs else {
            return
        }

        applicationIDsByProcessID = updatedApplicationIDs
        applicationIDRevision &+= 1
    }

    private func applyApplicationScope(_ scope: LogcatApplicationScope) {
        applyApplicationScope(scope, clearingEntries: activeStreamScope != scope.streamScope)
    }

    private func applyApplicationScope(
        _ scope: LogcatApplicationScope,
        clearingEntries: Bool
    ) {
        guard isDeviceUsable, !isStopped else {
            streamState = .disconnected
            return
        }

        let previousStreamScope = activeStreamScope
        let scopeChanged = activeApplicationScope != scope
        activeApplicationScope = scope
        if scopeChanged {
            rebuildVisibleEntries()
        }

        if case .waitingForProcess = scope {
            cancelStreamAndClearEntries()
            if let applicationID {
                streamState = .waitingForApplication(applicationID)
            }
            return
        }

        if streamTask == nil || previousStreamScope != scope.streamScope {
            guard reconnectTask == nil else {
                return
            }
            restartStream(using: scope.streamScope, clearingEntries: clearingEntries)
        } else if scope.isWaitingForProcess, let applicationID {
            streamState = .waitingForApplication(applicationID)
        } else if case .waitingForApplication = streamState {
            streamState = .streaming
        }
    }

    private func restartStream(using scope: LogcatStreamScope, clearingEntries: Bool) {
        guard isDeviceUsable, !isStopped, let adbPath else {
            streamState = .disconnected
            return
        }

        cancelStream()
        if clearingEntries {
            clearEntries()
        }
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
        cancelStream()
        clearEntries()
    }

    private func cancelStream() {
        streamGeneration += 1
        streamTask?.cancel()
        streamTask = nil
    }

    private func clearEntries() {
        entries.removeAll(keepingCapacity: false)
        visibleEntries.removeAll(keepingCapacity: false)
        pausedEntries = isPaused ? [] : nil
        markDisplayedEntriesChanged()
    }

    private func receive(_ event: LogcatServiceEvent, generation: Int) {
        guard generation == streamGeneration else {
            return
        }

        switch event {
        case .entries(let newEntries):
            append(newEntries)
            failedReconnectAttempts = 0
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
                handleUnexpectedStreamEnd(message: message(for: failure))
            }
        case .stopped:
            handleUnexpectedStreamEnd(message: "Logcat stopped unexpectedly.")
        case .cancelled:
            handleUnexpectedStreamEnd(message: "Logcat was cancelled unexpectedly.")
        }
    }

    private func handleDeviceUnavailable() {
        guard isDeviceUsable || streamState != .disconnected else {
            return
        }

        isDeviceUsable = false
        cancelReconnectWork()
        cancelStream()
        applicationRefreshTask?.cancel()
        applicationRefreshTask = nil
        streamState = .disconnected
        AppLogger.logcat.info("Logcat device became unavailable")
    }

    private func handleUnexpectedStreamEnd(message: String) {
        streamTask = nil
        streamState = .failed(message)
        guard isDeviceUsable, !isStopped else {
            return
        }

        failedReconnectAttempts += 1
        scheduleReconnect(after: reconnectDelay(failedReconnectAttempts))
    }

    private func scheduleReconnect(after delay: Duration) {
        guard reconnectTask == nil else {
            return
        }

        reconnectGeneration += 1
        let generation = reconnectGeneration
        AppLogger.logcat.info("Scheduling Logcat reconnect attempt \(self.failedReconnectAttempts, privacy: .public)")
        reconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            guard let self,
                  self.reconnectGeneration == generation,
                  self.isDeviceUsable,
                  !self.isStopped else {
                return
            }
            self.reconnectTask = nil
            self.restartStream(using: self.activeStreamScope, clearingEntries: false)
        }
    }

    private func cancelReconnectWork() {
        reconnectGeneration += 1
        reconnectTask?.cancel()
        reconnectTask = nil
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
        var trimmedEntries = false
        while entries.count > Self.retentionLimit {
            let overflow = entries.count - Self.retentionLimit
            let removalCount = min(
                max(overflow, Self.retentionTrimBatchSize),
                entries.count
            )
            entries.removeFirst(removalCount)
            trimmedEntries = true
        }

        if trimmedEntries {
            rebuildVisibleEntries()
            return
        }

        let newlyVisibleEntries = newEntries.filter(matchesVisibleFilters)
        guard !newlyVisibleEntries.isEmpty else {
            return
        }

        visibleEntries.append(contentsOf: newlyVisibleEntries)
        if !isPaused {
            markDisplayedEntriesChanged()
        }
    }

    private func rebuildVisibleEntries() {
        visibleEntries = entries.filter(matchesVisibleFilters)
        guard !isPaused else {
            return
        }
        markDisplayedEntriesChanged()
    }

    private func matchesVisibleFilters(_ entry: LogcatEntry) -> Bool {
        guard entry.priority.severity >= minimumPriority.severity,
              activeApplicationScope.includes(entry),
              !showsOnlyCrashesAndExceptions || LogcatCrashFilter.includes(entry) else {
            return false
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return true
        }

        return entry.tag.localizedCaseInsensitiveContains(query) ||
            entry.message.localizedCaseInsensitiveContains(query)
    }

    private func markDisplayedEntriesChanged() {
        displayedEntryRevision &+= 1
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
