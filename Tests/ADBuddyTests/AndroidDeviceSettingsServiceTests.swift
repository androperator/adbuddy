import Foundation
import XCTest
@testable import ADBuddyCore

final class AndroidDeviceSettingsServiceTests: XCTestCase {
    func testUsesFixedArgumentsForEverySupportedDeviceSetting() async {
        let actions = AndroidDeviceSettingAction.allCases
        let runner = ScriptedDeviceSettingsProcessRunner(
            results: actions.map { _ in successfulResult() }
        )
        let service = AndroidDeviceSettingsService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: runner
        )

        for action in actions {
            let result = await service.apply(action, to: "device-serial")
            XCTAssertEqual(
                result,
                .success(AndroidDeviceSettingOutcome(action: action, deviceSerial: "device-serial"))
            )
        }

        let invocations = await runner.invocations
        XCTAssertEqual(
            invocations,
            [
                ["-s", "device-serial", "shell", "cmd", "uimode", "night", "yes"],
                ["-s", "device-serial", "shell", "cmd", "uimode", "night", "no"],
                ["-s", "device-serial", "shell", "settings", "put", "secure", "navigation_mode", "2"],
                ["-s", "device-serial", "shell", "settings", "put", "secure", "navigation_mode", "0"],
                ["-s", "device-serial", "shell", "setprop", "debug.layout", "true"],
                ["-s", "device-serial", "shell", "setprop", "debug.layout", "false"],
                ["-s", "device-serial", "shell", "setprop", "debug.hwui.profile", "visual_bars"],
                ["-s", "device-serial", "shell", "setprop", "debug.hwui.profile", "false"],
            ]
        )
    }

    func testReportsADBFailureWithStandardError() async {
        let runner = ScriptedDeviceSettingsProcessRunner(results: [
            ProcessResult(
                standardOutput: Data(),
                standardError: Data("Permission denial".utf8),
                exitStatus: 1,
                durationMilliseconds: 1,
                failureDescription: nil,
                wasCancelled: false
            ),
        ])
        let service = AndroidDeviceSettingsService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: runner
        )

        let result = await service.apply(.showLayoutBounds, to: "device-serial")

        XCTAssertEqual(result, .failure(.commandFailed("Permission denial")))
    }

    private func successfulResult() -> ProcessResult {
        ProcessResult(
            standardOutput: Data(),
            standardError: Data(),
            exitStatus: 0,
            durationMilliseconds: 1,
            failureDescription: nil,
            wasCancelled: false
        )
    }
}

private actor ScriptedDeviceSettingsProcessRunner: ProcessRunning {
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
