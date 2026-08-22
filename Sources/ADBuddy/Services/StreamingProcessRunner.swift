@preconcurrency import Foundation
import Dispatch

enum StreamingProcessEvent: Equatable, Sendable {
    case standardOutput(Data)
    case terminated(exitStatus: Int32, standardError: Data)
    case launchFailed(String)
    case cancelled
}

protocol StreamingProcessRunning: Sendable {
    func stream(executablePath: String, arguments: [String]) -> AsyncStream<StreamingProcessEvent>
}

final class StreamingProcessRunner: StreamingProcessRunning, @unchecked Sendable {
    private static let maximumBufferedChunks = 256

    func stream(executablePath: String, arguments: [String]) -> AsyncStream<StreamingProcessEvent> {
        let controller = StreamingProcessController()

        return AsyncStream(bufferingPolicy: .bufferingNewest(Self.maximumBufferedChunks)) { continuation in
            continuation.onTermination = { @Sendable _ in
                controller.cancel()
            }

            DispatchQueue.global(qos: .userInitiated).async {
                Self.run(
                    executablePath: executablePath,
                    arguments: arguments,
                    controller: controller,
                    continuation: continuation
                )
            }
        }
    }

    private static func run(
        executablePath: String,
        arguments: [String],
        controller: StreamingProcessController,
        continuation: AsyncStream<StreamingProcessEvent>.Continuation
    ) {
        guard !controller.isCancelled else {
            controller.finish(.cancelled, continuation: continuation)
            return
        }

        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError

        standardOutput.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            controller.yield(.standardOutput(data), continuation: continuation)
        }

        standardError.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            controller.appendStandardError(data)
        }

        process.terminationHandler = { finishedProcess in
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil

            let remainingOutput = standardOutput.fileHandleForReading.readDataToEndOfFile()
            if !remainingOutput.isEmpty {
                controller.yield(.standardOutput(remainingOutput), continuation: continuation)
            }

            let remainingError = standardError.fileHandleForReading.readDataToEndOfFile()
            controller.appendStandardError(remainingError)

            let event: StreamingProcessEvent
            if controller.isCancelled {
                event = .cancelled
            } else {
                event = .terminated(
                    exitStatus: finishedProcess.terminationStatus,
                    standardError: controller.standardError
                )
            }
            controller.finish(event, continuation: continuation)
        }

        do {
            try process.run()
            controller.register(process)
        } catch {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            controller.finish(.launchFailed(error.localizedDescription), continuation: continuation)
        }
    }
}

private final class StreamingProcessController: @unchecked Sendable {
    private static let maximumStandardErrorBytes = 64 * 1_024

    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var finished = false
    private var standardErrorData = Data()

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    var standardError: Data {
        lock.lock()
        defer { lock.unlock() }
        return standardErrorData
    }

    func register(_ process: Process) {
        lock.lock()
        let shouldTerminate = cancelled
        if !shouldTerminate {
            self.process = process
        }
        lock.unlock()

        if shouldTerminate, process.isRunning {
            process.terminate()
        }
    }

    func appendStandardError(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        let remainingCapacity = Self.maximumStandardErrorBytes - standardErrorData.count
        guard remainingCapacity > 0 else {
            return
        }
        standardErrorData.append(data.prefix(remainingCapacity))
    }

    func yield(
        _ event: StreamingProcessEvent,
        continuation: AsyncStream<StreamingProcessEvent>.Continuation
    ) {
        lock.lock()
        let canYield = !finished
        lock.unlock()

        guard canYield else {
            return
        }
        continuation.yield(event)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = process
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }

    func finish(
        _ event: StreamingProcessEvent,
        continuation: AsyncStream<StreamingProcessEvent>.Continuation
    ) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        process = nil
        lock.unlock()

        continuation.yield(event)
        continuation.finish()
    }
}
