@preconcurrency import Foundation
import Dispatch

public struct ProcessResult: Equatable, Sendable {
    public let standardOutput: Data
    public let standardError: Data
    public let exitStatus: Int32?
    public let durationMilliseconds: Int
    public let failureDescription: String?
    public let wasCancelled: Bool

    public init(
        standardOutput: Data,
        standardError: Data,
        exitStatus: Int32?,
        durationMilliseconds: Int,
        failureDescription: String?,
        wasCancelled: Bool
    ) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitStatus = exitStatus
        self.durationMilliseconds = durationMilliseconds
        self.failureDescription = failureDescription
        self.wasCancelled = wasCancelled
    }

    public var succeeded: Bool {
        !wasCancelled && failureDescription == nil && exitStatus == 0
    }
}

public protocol ProcessRunning: Sendable {
    func run(executablePath: String, arguments: [String]) async -> ProcessResult
}

public final class ProcessRunner: ProcessRunning, @unchecked Sendable {
    private let activeProcesses = ActiveProcessRegistry()

    public init() {}

    public func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        return await run(
            executablePath: executablePath,
            arguments: arguments,
            identifier: UUID().uuidString,
            environment: nil,
            onStarted: nil
        )
    }

    public func processIdentifier(identifier: String) -> Int32? {
        activeProcesses.processIdentifier(id: identifier)
    }

    public func interrupt(identifier: String) -> Bool {
        activeProcesses.interrupt(id: identifier)
    }

    public func run(
        executablePath: String,
        arguments: [String],
        identifier executionID: String,
        environment: [String: String]?,
        onStarted: (@MainActor @Sendable () -> Void)?
    ) async -> ProcessResult {
        let cancellationFlag = CancellationFlag()
        let request = ProcessRequest(executablePath: executablePath, arguments: arguments, environment: environment)

        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Self.execute(
                        request,
                        executionID: executionID,
                        activeProcesses: self.activeProcesses,
                        cancellationFlag: cancellationFlag,
                        onStarted: onStarted
                    )
                    continuation.resume(returning: result)
                }
            }
        }, onCancel: {
            cancellationFlag.cancel()
            activeProcesses.terminate(id: executionID)
        })
    }

    private static func execute(
        _ request: ProcessRequest,
        executionID: String,
        activeProcesses: ActiveProcessRegistry,
        cancellationFlag: CancellationFlag,
        onStarted: (@MainActor @Sendable () -> Void)?
    ) -> ProcessResult {
        guard !cancellationFlag.isCancelled else {
            return ProcessResult(
                standardOutput: Data(),
                standardError: Data(),
                exitStatus: nil,
                durationMilliseconds: 0,
                failureDescription: "Process was cancelled before launch.",
                wasCancelled: true
            )
        }

        let process = Process()
        let startDate = Date()
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let standardOutputURL = temporaryDirectory.appendingPathComponent("adbuddy-output-\(UUID().uuidString)")
        let standardErrorURL = temporaryDirectory.appendingPathComponent("adbuddy-error-\(UUID().uuidString)")
        var standardOutputHandle: FileHandle?
        var standardErrorHandle: FileHandle?

        defer {
            try? standardOutputHandle?.close()
            try? standardErrorHandle?.close()
            try? FileManager.default.removeItem(at: standardOutputURL)
            try? FileManager.default.removeItem(at: standardErrorURL)
        }

        do {
            try Data().write(to: standardOutputURL, options: .withoutOverwriting)
            try Data().write(to: standardErrorURL, options: .withoutOverwriting)
            standardOutputHandle = try FileHandle(forWritingTo: standardOutputURL)
            standardErrorHandle = try FileHandle(forWritingTo: standardErrorURL)

            process.executableURL = URL(fileURLWithPath: request.executablePath)
            process.arguments = request.arguments
            process.environment = request.environment
            process.standardOutput = standardOutputHandle
            process.standardError = standardErrorHandle
            try process.run()
            activeProcesses.insert(process, id: executionID)
            if let onStarted {
                // Deliver readiness before returning even for a short-lived process.
                let notificationDelivered = DispatchSemaphore(value: 0)
                Task {
                    await onStarted()
                    notificationDelivered.signal()
                }
                notificationDelivered.wait()
            }

            if cancellationFlag.isCancelled {
                process.terminate()
            }

            process.waitUntilExit()
            activeProcesses.remove(id: executionID)
            try standardOutputHandle?.synchronize()
            try standardErrorHandle?.synchronize()

            let durationMilliseconds = Int(Date().timeIntervalSince(startDate) * 1_000)
            return ProcessResult(
                standardOutput: try Data(contentsOf: standardOutputURL),
                standardError: try Data(contentsOf: standardErrorURL),
                exitStatus: process.terminationStatus,
                durationMilliseconds: durationMilliseconds,
                failureDescription: nil,
                wasCancelled: cancellationFlag.isCancelled
            )
        } catch {
            activeProcesses.remove(id: executionID)

            return ProcessResult(
                standardOutput: (try? Data(contentsOf: standardOutputURL)) ?? Data(),
                standardError: (try? Data(contentsOf: standardErrorURL)) ?? Data(),
                exitStatus: nil,
                durationMilliseconds: Int(Date().timeIntervalSince(startDate) * 1_000),
                failureDescription: error.localizedDescription,
                wasCancelled: cancellationFlag.isCancelled
            )
        }
    }

}

private struct ProcessRequest: Sendable {
    let executablePath: String
    let arguments: [String]
    let environment: [String: String]?
}

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class ActiveProcessRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [String: Process] = [:]

    func insert(_ process: Process, id: String) {
        lock.lock()
        processes[id] = process
        lock.unlock()
    }

    func remove(id: String) {
        lock.lock()
        processes[id] = nil
        lock.unlock()
    }

    func processIdentifier(id: String) -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        guard let process = processes[id], process.isRunning else { return nil }
        return process.processIdentifier
    }

    func interrupt(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let process = processes[id], process.isRunning else {
            return false
        }
        process.interrupt()
        return true
    }

    func terminate(id: String) {
        lock.lock()
        let process = processes[id]
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }
}
