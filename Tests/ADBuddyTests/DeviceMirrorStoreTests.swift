import Foundation
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

@MainActor
final class DeviceMirrorStoreTests: XCTestCase {
    func testRepeatedOpenReusesSessionAndNormalCloseAllowsReopening() async {
        let backend = FakeMirrorBackend()
        var activated: [Int32] = []
        var failures: [String] = []
        let store = DeviceMirrorStore(backend: backend, activate: { activated.append($0) },
                                      reportFailure: { failures.append($0) })
        let device = device("one")
        store.open(device: device, adbPath: "/sdk/adb")
        store.open(device: device, adbPath: "/sdk/adb")
        await wait { backend.starts.count == 1 }
        store.open(device: device, adbPath: "/sdk/adb")
        XCTAssertEqual(activated, [42])
        XCTAssertEqual(backend.starts, ["one"])
        backend.finished.insert("one")
        await wait { store.activeSerials.isEmpty }
        XCTAssertTrue(failures.isEmpty)
        backend.finished.remove("one")
        store.open(device: device, adbPath: "/sdk/adb")
        await wait { backend.starts.count == 2 }
        await store.stopAll()
        XCTAssertTrue(store.activeSerials.isEmpty)
        XCTAssertTrue(failures.isEmpty)
    }

    func testShutdownCancelsEveryDeviceIncludingPendingLaunch() async {
        let backend = FakeMirrorBackend()
        var failures: [String] = []
        let store = DeviceMirrorStore(backend: backend, reportFailure: { failures.append($0) })
        store.open(device: device("one"), adbPath: "/sdk/adb")
        store.open(device: device("two"), adbPath: "/sdk/adb")
        await store.stopAll()
        XCTAssertTrue(store.activeSerials.isEmpty)
        XCTAssertTrue(failures.isEmpty)
        store.open(device: device("three"), adbPath: "/sdk/adb")
        XCTAssertTrue(store.activeSerials.isEmpty)
    }

    func testFailureClearsSessionAndReportsDeviceAndDiagnostics() async {
        let backend = FakeMirrorBackend()
        backend.exitStatus = 1
        backend.finished.insert("one")
        var failures: [String] = []
        let store = DeviceMirrorStore(backend: backend, reportFailure: { failures.append($0) })
        store.open(device: device("one"), adbPath: "/sdk/adb")
        await wait { !failures.isEmpty }
        XCTAssertTrue(store.activeSerials.isEmpty)
        XCTAssertTrue(failures.first?.contains("Phone one") == true)
        XCTAssertTrue(failures.first?.contains("disconnected") == true)
    }

    func testUnavailableDeviceAndMissingSDKDoNotLaunch() {
        let backend = FakeMirrorBackend()
        var failures: [String] = []
        let store = DeviceMirrorStore(backend: backend, reportFailure: { failures.append($0) })
        store.open(device: device("one", state: .unauthorized), adbPath: "/sdk/adb")
        store.open(device: device("two"), adbPath: nil)
        XCTAssertEqual(failures.count, 2)
        XCTAssertTrue(backend.starts.isEmpty)
        XCTAssertTrue(store.activeSerials.isEmpty)
    }

    func testMissingBundledHelperReturnsActionableFailure() async {
        let backend = ScrcpyMirroring(backendDirectory: URL(fileURLWithPath: "/missing-\(UUID())"))
        let result = await backend.mirror(device: device("one"), adbPath: "/sdk/adb") { _ in
            XCTFail("Missing helper must not start")
        }
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.failureDescription?.contains("Rebuild or reinstall") == true)
    }

    func testHelperReceivesSDKAndResourcesWithoutShellExpansion() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ADBuddyMirrorTest-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("scrcpy")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$ADB" "$SCRCPY_SERVER_PATH" "$SCRCPY_ICON_DIR" "$@"
        sleep 0.1
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try Data().write(to: directory.appendingPathComponent("scrcpy-server"))
        var processIdentifier: Int32?
        let result = await ScrcpyMirroring(backendDirectory: directory).mirror(
            device: device("serial with spaces;literal"), adbPath: "/SDK with spaces/adb"
        ) { processIdentifier = $0 }
        XCTAssertTrue(result.succeeded)
        XCTAssertNotNil(processIdentifier)
        let output = String(decoding: result.standardOutput, as: UTF8.self).split(separator: "\n").map(String.init)
        XCTAssertEqual(Array(output.prefix(3)), ["/SDK with spaces/adb",
                                               directory.appendingPathComponent("scrcpy-server").path,
                                               directory.path])
        XCTAssertTrue(output.contains("--serial=serial with spaces;literal"))
        XCTAssertTrue(output.contains("--window-title=Phone serial with spaces;literal — ADBuddy"))
        XCTAssertTrue(output.contains("--no-audio"))
        XCTAssertFalse(output.contains("--no-control"))
        XCTAssertFalse(output.contains("--no-window"))
        XCTAssertFalse(output.contains(where: { $0.hasPrefix("--record=") }))
    }

    private func device(_ serial: String, state: DeviceConnectionState = .connected) -> AndroidDevice {
        AndroidDevice(serial: serial, displayName: "Phone \(serial)", connectionState: state,
                      kind: .physical, model: nil, product: nil, deviceCodeName: nil, transportID: nil)
    }

    private func wait(until condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition(), "Mirror state did not settle")
    }
}

@MainActor
private final class FakeMirrorBackend: DeviceMirroring {
    var starts: [String] = []
    var finished: Set<String> = []
    var exitStatus: Int32 = 0

    func mirror(device: AndroidDevice, adbPath: String,
                onStarted: @escaping @MainActor @Sendable (Int32) -> Void) async -> ProcessResult {
        starts.append(device.serial)
        onStarted(42)
        while !finished.contains(device.serial), !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return ProcessResult(standardOutput: Data(), standardError: Data("disconnected".utf8),
                             exitStatus: exitStatus, durationMilliseconds: 1,
                             failureDescription: nil, wasCancelled: Task.isCancelled)
    }
}
