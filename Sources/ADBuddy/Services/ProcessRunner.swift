@preconcurrency import Foundation
import Dispatch

struct ProcessResult: Equatable, Sendable {
    let standardOutput: Data
    let standardError: Data
    let exitStatus: Int32?
    let durationMilliseconds: Int
    let failureDescription: String?
    let wasCancelled: Bool

    var succeeded: Bool {
        !wasCancelled && failureDescription == nil && exitStatus == 0
    }
}

protocol ProcessRunning: Sendable {
    func run(executablePath: String, arguments: [String]) async -> ProcessResult
}

final class ProcessRunner: ProcessRunning, @unchecked Sendable {
    private let activeProcesses = ActiveProcessRegistry()

    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        let executionID = UUID()
        let cancellationFlag = CancellationFlag()
        let request = ProcessRequest(executablePath: executablePath, arguments: arguments)

        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Self.execute(
                        request,
                        executionID: executionID,
                        activeProcesses: self.activeProcesses,
                        cancellationFlag: cancellationFlag
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
        executionID: UUID,
        activeProcesses: ActiveProcessRegistry,
        cancellationFlag: CancellationFlag
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
        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        let standardOutput = DataCollector()
        let standardError = DataCollector()
        let startDate = Date()

        process.executableURL = URL(fileURLWithPath: request.executablePath)
        process.arguments = request.arguments
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe

        collect(from: standardOutputPipe, into: standardOutput)
        collect(from: standardErrorPipe, into: standardError)

        do {
            try process.run()
            activeProcesses.insert(process, id: executionID)

            if cancellationFlag.isCancelled {
                process.terminate()
            }

            process.waitUntilExit()
            activeProcesses.remove(id: executionID)

            let durationMilliseconds = Int(Date().timeIntervalSince(startDate) * 1_000)
            return ProcessResult(
                standardOutput: finishReading(from: standardOutputPipe, collector: standardOutput),
                standardError: finishReading(from: standardErrorPipe, collector: standardError),
                exitStatus: process.terminationStatus,
                durationMilliseconds: durationMilliseconds,
                failureDescription: nil,
                wasCancelled: cancellationFlag.isCancelled
            )
        } catch {
            activeProcesses.remove(id: executionID)
            discard(pipe: standardOutputPipe)
            discard(pipe: standardErrorPipe)

            return ProcessResult(
                standardOutput: Data(),
                standardError: Data(),
                exitStatus: nil,
                durationMilliseconds: Int(Date().timeIntervalSince(startDate) * 1_000),
                failureDescription: error.localizedDescription,
                wasCancelled: cancellationFlag.isCancelled
            )
        }
    }

    private static func collect(from pipe: Pipe, into collector: DataCollector) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                collector.append(data)
            }
        }
    }

    private static func finishReading(from pipe: Pipe, collector: DataCollector) -> Data {
        let readHandle = pipe.fileHandleForReading
        readHandle.readabilityHandler = nil
        try? pipe.fileHandleForWriting.close()
        collector.append(readHandle.readDataToEndOfFile())
        try? readHandle.close()
        return collector.data
    }

    private static func discard(pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = nil
        try? pipe.fileHandleForWriting.close()
        try? pipe.fileHandleForReading.close()
    }
}

private struct ProcessRequest: Sendable {
    let executablePath: String
    let arguments: [String]
}

private final class DataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
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
    private var processes: [UUID: Process] = [:]

    func insert(_ process: Process, id: UUID) {
        lock.lock()
        processes[id] = process
        lock.unlock()
    }

    func remove(id: UUID) {
        lock.lock()
        processes[id] = nil
        lock.unlock()
    }

    func terminate(id: UUID) {
        lock.lock()
        let process = processes[id]
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }
}
