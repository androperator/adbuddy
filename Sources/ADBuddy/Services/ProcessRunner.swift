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
            process.standardOutput = standardOutputHandle
            process.standardError = standardErrorHandle
            try process.run()
            activeProcesses.insert(process, id: executionID)

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
