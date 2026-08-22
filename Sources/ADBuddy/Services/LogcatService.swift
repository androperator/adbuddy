import Foundation

enum LogcatServiceEvent: Equatable, Sendable {
    case entries([LogcatEntry])
    case failed(LogcatServiceFailure)
    case stopped
    case cancelled
}

enum LogcatServiceFailure: Equatable, Sendable {
    case launchFailed(String)
    case terminated(exitStatus: Int32, standardError: String)
}

protocol LogcatStreaming: Sendable {
    func stream(for deviceSerial: String) -> AsyncStream<LogcatServiceEvent>
}

struct LogcatService: LogcatStreaming, Sendable {
    static let initialHistoryLimit = 5_000

    private let adbPath: String
    private let processRunner: any StreamingProcessRunning
    private let batchSize: Int
    private let batchFlushInterval: Duration

    init(
        adbPath: String,
        processRunner: any StreamingProcessRunning,
        batchSize: Int = 250,
        batchFlushInterval: Duration = .milliseconds(250)
    ) {
        self.adbPath = adbPath
        self.processRunner = processRunner
        self.batchSize = batchSize
        self.batchFlushInterval = batchFlushInterval
    }

    func stream(for deviceSerial: String) -> AsyncStream<LogcatServiceEvent> {
        let processEvents = processRunner.stream(
            executablePath: adbPath,
            arguments: Self.arguments(for: deviceSerial)
        )
        let taskController = LogcatStreamTaskController()

        return AsyncStream { continuation in
            let emitter = LogcatBatchEmitter(continuation: continuation, batchSize: batchSize)
            AppLogger.logcat.info("Starting Logcat stream")

            let streamTask = Task.detached(priority: .userInitiated) {
                var parser = LogcatParser()

                for await event in processEvents {
                    guard !Task.isCancelled else {
                        return
                    }

                    switch event {
                    case .standardOutput(let data):
                        await emitter.append(parser.consume(data))
                    case .launchFailed(let description):
                        AppLogger.logcat.error("Logcat process could not start")
                        await emitter.finish(with: .failed(.launchFailed(description)))
                        return
                    case .terminated(let exitStatus, let standardError):
                        if exitStatus == 0 {
                            AppLogger.logcat.info("Logcat process stopped normally")
                            await emitter.finish(with: .stopped)
                        } else {
                            AppLogger.logcat.error("Logcat process exited with status \(exitStatus, privacy: .public)")
                            let failure = LogcatServiceFailure.terminated(
                                exitStatus: exitStatus,
                                standardError: Self.failureContext(from: standardError)
                            )
                            await emitter.finish(with: .failed(failure))
                        }
                        return
                    case .cancelled:
                        AppLogger.logcat.info("Logcat process was cancelled")
                        await emitter.finish(with: .cancelled)
                        return
                    }
                }

                guard !Task.isCancelled else {
                    return
                }
                await emitter.finish(with: .stopped)
            }

            let flushTask = Task.detached(priority: .utility) {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: batchFlushInterval)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else {
                        return
                    }
                    await emitter.flush()
                }
            }

            taskController.set(streamTask: streamTask, flushTask: flushTask)
            continuation.onTermination = { @Sendable _ in
                taskController.cancel()
            }
        }
    }

    static func arguments(for deviceSerial: String) -> [String] {
        [
            "-s", deviceSerial,
            "logcat",
            "-v", "threadtime",
            "-T", String(initialHistoryLimit),
        ]
    }

    private static func failureContext(from standardError: Data) -> String {
        let context = String(decoding: standardError, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return context.isEmpty ? "ADB logcat did not provide error output." : context
    }
}

private actor LogcatBatchEmitter {
    private let continuation: AsyncStream<LogcatServiceEvent>.Continuation
    private let batchSize: Int
    private var entries: [LogcatEntry] = []
    private var finished = false

    init(continuation: AsyncStream<LogcatServiceEvent>.Continuation, batchSize: Int) {
        self.continuation = continuation
        self.batchSize = max(batchSize, 1)
    }

    func append(_ newEntries: [LogcatEntry]) {
        guard !finished, !newEntries.isEmpty else {
            return
        }

        entries.append(contentsOf: newEntries)
        if entries.count >= batchSize {
            flush()
        }
    }

    func flush() {
        guard !finished, !entries.isEmpty else {
            return
        }

        continuation.yield(.entries(entries))
        entries.removeAll(keepingCapacity: true)
    }

    func finish(with event: LogcatServiceEvent) {
        guard !finished else {
            return
        }

        flush()
        finished = true
        continuation.yield(event)
        continuation.finish()
    }
}

private final class LogcatStreamTaskController: @unchecked Sendable {
    private let lock = NSLock()
    private var streamTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var cancelled = false

    func set(streamTask: Task<Void, Never>, flushTask: Task<Void, Never>) {
        lock.lock()
        let shouldCancel = cancelled
        self.streamTask = streamTask
        self.flushTask = flushTask
        lock.unlock()

        if shouldCancel {
            streamTask.cancel()
            flushTask.cancel()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let streamTask = streamTask
        let flushTask = flushTask
        lock.unlock()

        streamTask?.cancel()
        flushTask?.cancel()
    }
}
