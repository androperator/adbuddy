import Foundation
import XCTest
@testable import ADBuddyCore

final class AndroidVirtualDeviceDiskUsageServiceTests: XCTestCase {
    func testAllocatedKibibytesAreConvertedToBytesWithSafeArguments() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = DiskUsageRunner(output: "1048576\t\(root.path)/Pixel.avd\n")
        let service = makeService(root: root, runner: runner)
        let bytes = await service.allocatedBytes(for: "Pixel")
        XCTAssertEqual(bytes, 1_073_741_824)
        let invocation = await runner.invocation
        XCTAssertEqual(invocation?.0, "/usr/bin/du")
        XCTAssertEqual(invocation?.1, ["-sk", root.appendingPathComponent("Pixel.avd").path])
    }

    func testUnusableOutputAndProcessFailureDoNotReportZeroUsage() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for output in ["", "invalid", "-1\tpath", "18446744073709551615\tpath"] {
            let bytes = await makeService(root: root, runner: DiskUsageRunner(output: output)).allocatedBytes(for: "Pixel")
            XCTAssertNil(bytes)
        }
        let bytes = await makeService(root: root, runner: DiskUsageRunner(output: "12\tpath", status: 1)).allocatedBytes(for: "Pixel")
        XCTAssertNil(bytes)
    }

    func testMissingOrInvalidNameDoesNotInvokeProcess() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = DiskUsageRunner(output: "0\tpath")
        let service = makeService(root: root, runner: runner)
        let missing = await service.allocatedBytes(for: "Missing")
        let invalid = await service.allocatedBytes(for: "../Pixel")
        XCTAssertNil(missing)
        XCTAssertNil(invalid)
        let invocation = await runner.invocation
        XCTAssertNil(invocation)
    }

    func testSparseImageAndExternalSymlinkDoNotCountApparentSize() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("Pixel.avd/userdata.img")
        XCTAssertTrue(FileManager.default.createFile(atPath: image.path, contents: nil))
        let handle = try FileHandle(forWritingTo: image)
        try handle.truncate(atOffset: 1_073_741_824)
        try handle.close()
        let external = root.appendingPathComponent("shared.img")
        try Data(repeating: 1, count: 4 * 1_048_576).write(to: external)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Pixel.avd/system.img"), withDestinationURL: external)
        let bytes = await makeService(root: root, runner: ProcessRunner()).allocatedBytes(for: "Pixel")
        XCTAssertNotNil(bytes)
        XCTAssertLessThan(try XCTUnwrap(bytes), 1_048_576)
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("disk usage \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Pixel.avd"), withIntermediateDirectories: true)
        return root
    }

    private func makeService(root: URL, runner: any ProcessRunning) -> AndroidVirtualDeviceDiskUsageService {
        AndroidVirtualDeviceDiskUsageService(
            directoryResolver: AndroidVirtualDeviceDirectoryResolver(environment: ["ANDROID_AVD_HOME": root.path], homeDirectory: root),
            processRunner: runner
        )
    }
}

private actor DiskUsageRunner: ProcessRunning {
    let output: String
    let status: Int32
    var invocation: (String, [String])?

    init(output: String, status: Int32 = 0) {
        self.output = output
        self.status = status
    }

    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        invocation = (executablePath, arguments)
        return ProcessResult(standardOutput: Data(output.utf8), standardError: Data(), exitStatus: status,
                             durationMilliseconds: 0, failureDescription: nil, wasCancelled: false)
    }
}
