@preconcurrency import Foundation

public protocol ApplicationProcessLaunching: Sendable {
    func launch(executablePath: String, arguments: [String]) throws
}

public struct ApplicationProcessLauncher: ApplicationProcessLaunching {
    public init() {}

    public func launch(executablePath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
