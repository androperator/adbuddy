import Foundation
import XCTest
@testable import ADBuddy

final class LogcatApplicationServiceTests: XCTestCase {
    func testQueriesRunningProcessesAndPackageUserIDWithFixedArguments() async {
        let runner = ScriptedLogcatApplicationProcessRunner(results: [
            successfulResult(
                standardOutput: """
                UID PID NAME
                10374 5468 com.example.app
                10374 5585 com.example.app:worker
                1000 1687 system_server
                """
            ),
            successfulResult(standardOutput: "package:com.example.app uid:10374\n"),
        ])
        let service = LogcatApplicationService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: runner
        )

        let processesResult = await service.runningProcesses(for: "device-serial")
        let userIDResult = await service.packageUserID(
            for: "com.example.app",
            deviceSerial: "device-serial"
        )

        XCTAssertEqual(
            processesResult,
            .success([
                AndroidRunningProcess(userID: 10374, processID: 5468, name: "com.example.app"),
                AndroidRunningProcess(userID: 10374, processID: 5585, name: "com.example.app:worker"),
                AndroidRunningProcess(userID: 1000, processID: 1687, name: "system_server"),
            ])
        )
        XCTAssertEqual(userIDResult, .success(10374))
        let invocations = await runner.invocations
        XCTAssertEqual(
            invocations,
            [
                ApplicationProcessInvocation(
                    arguments: ["-s", "device-serial", "shell", "ps", "-A", "-o", "UID,PID,NAME"]
                ),
                ApplicationProcessInvocation(
                    arguments: [
                        "-s", "device-serial",
                        "shell", "cmd", "package", "list", "packages", "-U", "com.example.app",
                    ]
                ),
            ]
        )
    }

    func testDerivesSuggestionsAndUIDOrPIDScopesAcrossProcessRestart() {
        let primaryProcess = AndroidRunningProcess(userID: 10374, processID: 100, name: "com.example.app")
        let secondaryProcess = AndroidRunningProcess(userID: 10374, processID: 101, name: "com.example.app:worker")
        let isolatedProcess = AndroidRunningProcess(userID: 90374, processID: 102, name: "com.example.app:sandbox")

        XCTAssertEqual(primaryProcess.applicationID, "com.example.app")
        XCTAssertEqual(secondaryProcess.applicationID, "com.example.app")
        XCTAssertNil(AndroidRunningProcess(userID: 0, processID: 1, name: "init").applicationID)
        XCTAssertNil(AndroidRunningProcess(userID: 0, processID: 1, name: "[com.example.app]").applicationID)
        XCTAssertNil(AndroidRunningProcess(userID: 0, processID: 1, name: "irq/1212-c500000.pcie").applicationID)

        XCTAssertEqual(
            LogcatApplicationScope.resolve(
                packageID: "com.example.app",
                packageUserID: 10374,
                processes: [primaryProcess, secondaryProcess],
                prefersUserIDFiltering: true
            ),
            .userID(10374, isWaitingForProcess: false)
        )
        XCTAssertEqual(
            LogcatApplicationScope.resolve(
                packageID: "com.example.app",
                packageUserID: 10374,
                processes: [primaryProcess, isolatedProcess],
                prefersUserIDFiltering: true
            ),
            .processIDs([100, 102])
        )
        XCTAssertEqual(
            LogcatApplicationScope.resolve(
                packageID: "com.example.app",
                packageUserID: 10374,
                processes: [],
                prefersUserIDFiltering: true
            ),
            .userID(10374, isWaitingForProcess: true)
        )
        XCTAssertEqual(
            LogcatApplicationScope.resolve(
                packageID: "com.example.app",
                packageUserID: nil,
                processes: [],
                prefersUserIDFiltering: false
            ),
            .waitingForProcess
        )

        let restartedProcess = AndroidRunningProcess(userID: 90374, processID: 303, name: "com.example.app:sandbox")
        XCTAssertEqual(
            LogcatApplicationScope.resolve(
                packageID: "com.example.app",
                packageUserID: nil,
                processes: [restartedProcess],
                prefersUserIDFiltering: false
            ),
            .processIDs([303])
        )
    }

    private func successfulResult(standardOutput: String) -> ProcessResult {
        ProcessResult(
            standardOutput: Data(standardOutput.utf8),
            standardError: Data(),
            exitStatus: 0,
            durationMilliseconds: 1,
            failureDescription: nil,
            wasCancelled: false
        )
    }
}

private struct ApplicationProcessInvocation: Equatable {
    let arguments: [String]
}

private actor ScriptedLogcatApplicationProcessRunner: ProcessRunning {
    private var results: [ProcessResult]
    private var recordedInvocations: [ApplicationProcessInvocation] = []

    init(results: [ProcessResult]) {
        self.results = results
    }

    var invocations: [ApplicationProcessInvocation] {
        recordedInvocations
    }

    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        recordedInvocations.append(ApplicationProcessInvocation(arguments: arguments))
        return results.removeFirst()
    }
}
