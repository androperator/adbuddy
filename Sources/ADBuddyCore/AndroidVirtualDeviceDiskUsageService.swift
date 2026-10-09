import Foundation

public struct AndroidVirtualDeviceDiskUsageService {
    private let directoryResolver: AndroidVirtualDeviceDirectoryResolver
    private let processRunner: any ProcessRunning

    public init(
        directoryResolver: AndroidVirtualDeviceDirectoryResolver = AndroidVirtualDeviceDirectoryResolver(),
        processRunner: any ProcessRunning = ProcessRunner()
    ) {
        self.directoryResolver = directoryResolver
        self.processRunner = processRunner
    }

    public func allocatedBytes(for name: String) async -> UInt64? {
        guard let directory = directoryResolver.directoryURL(for: name) else { return nil }
        // du counts allocated blocks, including snapshots, without following image symlinks.
        let result = await processRunner.run(executablePath: "/usr/bin/du", arguments: ["-sk", directory.path])
        guard result.succeeded,
              let output = String(data: result.standardOutput, encoding: .utf8),
              let count = output.split(whereSeparator: { $0.isWhitespace }).first,
              let kibibytes = UInt64(count) else { return nil }
        let bytes = kibibytes.multipliedReportingOverflow(by: 1024)
        return bytes.overflow ? nil : bytes.partialValue
    }
}
