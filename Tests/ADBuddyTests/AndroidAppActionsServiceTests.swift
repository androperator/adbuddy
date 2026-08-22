import Foundation
import XCTest
@testable import ADBuddyCore

final class AndroidAppActionsServiceTests: XCTestCase {
    func testResolvesForegroundAppThenRestartsItWithFixedArguments() async {
        let runner = ScriptedAppActionProcessRunner(results: [
            successfulResult(
                standardOutput: "mResumedActivity: ActivityRecord{123 u0 com.example.app/.MainActivity t42}\n"
            ),
            successfulResult(),
            successfulResult(),
        ])
        let service = AndroidAppActionsService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: runner
        )

        let result = await service.perform(.restart, for: "device-serial")

        XCTAssertEqual(
            result,
            .success(
                AndroidAppActionOutcome(
                    action: .restart,
                    application: AndroidForegroundApplication(packageID: "com.example.app")
                )
            )
        )
        let invocations = await runner.invocations
        XCTAssertEqual(
            invocations,
            [
                ["-s", "device-serial", "shell", "dumpsys", "activity", "activities"],
                ["-s", "device-serial", "shell", "am", "force-stop", "com.example.app"],
                [
                    "-s", "device-serial",
                    "shell", "monkey",
                    "-p", "com.example.app",
                    "-c", "android.intent.category.LAUNCHER",
                    "1",
                ],
            ]
        )
    }

    func testUsesTheResolvedForegroundAppForClearDataAndRestart() async {
        let runner = ScriptedAppActionProcessRunner(results: [
            successfulResult(
                standardOutput: "topResumedActivity=ActivityRecord{123 u0 com.example.app/.MainActivity t42}\n"
            ),
            successfulResult(standardOutput: "Success\n"),
            successfulResult(),
        ])
        let service = AndroidAppActionsService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: runner
        )

        let result = await service.perform(.clearDataAndRestart, for: "device-serial")

        XCTAssertEqual(
            result,
            .success(
                AndroidAppActionOutcome(
                    action: .clearDataAndRestart,
                    application: AndroidForegroundApplication(packageID: "com.example.app")
                )
            )
        )
        let invocations = await runner.invocations
        XCTAssertEqual(
            invocations,
            [
                ["-s", "device-serial", "shell", "dumpsys", "activity", "activities"],
                ["-s", "device-serial", "shell", "pm", "clear", "com.example.app"],
                [
                    "-s", "device-serial",
                    "shell", "monkey",
                    "-p", "com.example.app",
                    "-c", "android.intent.category.LAUNCHER",
                    "1",
                ],
            ]
        )
    }

    func testUninstallUsesPreviouslyResolvedForegroundAppAndRequiresAndroidSuccess() async {
        let runner = ScriptedAppActionProcessRunner(results: [
            successfulResult(standardOutput: "Success\n"),
        ])
        let service = AndroidAppActionsService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: runner
        )
        let application = AndroidForegroundApplication(packageID: "com.example.app")

        let result = await service.perform(.uninstall, on: application, deviceSerial: "device-serial")

        XCTAssertEqual(
            result,
            .success(AndroidAppActionOutcome(action: .uninstall, application: application))
        )
        let invocations = await runner.invocations
        XCTAssertEqual(invocations, [["-s", "device-serial", "uninstall", "com.example.app"]])
    }

    func testReportsUnavailableForegroundAppAndDoesNotRunAnAction() async {
        let runner = ScriptedAppActionProcessRunner(results: [successfulResult(standardOutput: "No activities\n")])
        let service = AndroidAppActionsService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: runner
        )

        let result = await service.perform(.forceStop, for: "device-serial")

        XCTAssertEqual(result, .failure(.foregroundApplicationUnavailable))
        let invocations = await runner.invocations
        XCTAssertEqual(invocations, [["-s", "device-serial", "shell", "dumpsys", "activity", "activities"]])
    }

    func testRecognizesAllSupportedForegroundActivityFormats() {
        XCTAssertEqual(
            AndroidForegroundApplicationParser.parse(
                "mFocusedApp=ActivityRecord{123 u0 com.example.focused/.MainActivity t42}"
            ),
            AndroidForegroundApplication(packageID: "com.example.focused")
        )
        XCTAssertEqual(
            AndroidForegroundApplicationParser.parse(
                "ResumedActivity: ActivityRecord{123 u0 com.example.resumed/.MainActivity t42}"
            ),
            AndroidForegroundApplication(packageID: "com.example.resumed")
        )
    }

    private func successfulResult(standardOutput: String = "") -> ProcessResult {
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

private actor ScriptedAppActionProcessRunner: ProcessRunning {
    private var results: [ProcessResult]
    private var recordedInvocations: [[String]] = []

    init(results: [ProcessResult]) {
        self.results = results
    }

    var invocations: [[String]] {
        recordedInvocations
    }

    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        recordedInvocations.append(arguments)
        return results.removeFirst()
    }
}
