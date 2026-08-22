import Foundation
import Observation

enum LogcatStreamState: Equatable, Sendable {
    case connecting
    case streaming
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
    private var streamTask: Task<Void, Never>?

    private(set) var entries: [LogcatEntry] = []
    private(set) var streamState: LogcatStreamState = .connecting
    var minimumPriority: LogcatPriority = .debug

    var visibleEntries: [LogcatEntry] {
        entries.filter { $0.priority.severity >= minimumPriority.severity }
    }

    init(
        deviceSerial: String,
        makeService: @escaping @Sendable (String) -> any LogcatStreaming = { adbPath in
            LogcatService(adbPath: adbPath, processRunner: StreamingProcessRunner())
        }
    ) {
        self.deviceSerial = deviceSerial
        self.makeService = makeService
    }

    func start(adbPath: String?) {
        guard streamTask == nil else {
            return
        }
        guard let adbPath else {
            streamState = .connecting
            return
        }

        streamState = .connecting
        let service = makeService(adbPath)
        let serial = deviceSerial
        streamTask = Task { [weak self] in
            for await event in service.stream(for: serial) {
                guard !Task.isCancelled else {
                    return
                }
                self?.receive(event)
            }
        }
        streamState = .streaming
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        streamState = .stopped
    }

    private func receive(_ event: LogcatServiceEvent) {
        switch event {
        case .entries(let newEntries):
            append(newEntries)
            streamState = .streaming
        case .failed(let failure):
            streamState = .failed(message(for: failure))
        case .stopped, .cancelled:
            streamState = .stopped
        }
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
