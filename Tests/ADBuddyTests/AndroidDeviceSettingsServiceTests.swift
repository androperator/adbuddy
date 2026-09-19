import Foundation
import XCTest
@testable import ADBuddyCore

final class AndroidDeviceSettingsServiceTests: XCTestCase {
    func testUsesFixedArgumentsForNonNavigationSettings() async {
        let actions: [AndroidDeviceSettingAction] = [
            .enableDarkTheme, .enableLightTheme,
        ]
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

    func testSwitchesAndVerifiesBothNavigationModesForTheCurrentUser() async {
        let modes: [(AndroidDeviceSettingAction, String, String)] = [
            (.enableGestureNavigation, "gestural", "2"),
            (.enableThreeButtonNavigation, "threebutton", "0"),
        ]
        for (action, name, mode) in modes {
            let package = "com.android.internal.systemui.navbar.\(name)"
            let results = [
                successfulResult(output: "[ ] \(package)\n"),
                successfulResult(),
                successfulResult(output: "\(mode)\n"),
            ]
            let runner = ScriptedDeviceSettingsProcessRunner(results: results)
            let service = AndroidDeviceSettingsService(adbPath: "/SDK/adb", processRunner: runner)
            let result = await service.apply(action, to: "emulator-5556")
            XCTAssertEqual(result, .success(AndroidDeviceSettingOutcome(action: action, deviceSerial: "emulator-5556")))
            let invocations = await runner.invocations
            let expected = [
                ["-s", "emulator-5556", "shell", "cmd", "overlay", "list", "--user", "current", package],
                ["-s", "emulator-5556", "shell", "cmd", "overlay", "enable-exclusive", "--user", "current", "--category", package],
                ["-s", "emulator-5556", "shell", "cmd", "overlay", "lookup", "--user", "current", "android", "android:integer/config_navBarInteractionMode"],
            ]
            XCTAssertEqual(invocations, expected)
        }
    }

    func testUnavailableNavigationModeDoesNotChangeTheDevice() async {
        let runner = ScriptedDeviceSettingsProcessRunner(results: [successfulResult(output: "android\n")])
        let service = AndroidDeviceSettingsService(adbPath: "/SDK/adb", processRunner: runner)
        let result = await service.apply(.enableGestureNavigation, to: "serial")
        guard case .failure(let failure) = result else {
            return XCTFail("Missing overlays must not report success")
        }
        XCTAssertTrue(failure.message.contains("does not provide"))
        let invocations = await runner.invocations
        XCTAssertEqual(invocations.count, 1)
    }

    func testRejectsNavigationChangeThatDidNotBecomeEffective() async {
        let runner = ScriptedDeviceSettingsProcessRunner(results: [
            successfulResult(output: "[ ] com.android.internal.systemui.navbar.threebutton\n"),
            successfulResult(),
            successfulResult(output: "2\n"),
        ])
        let service = AndroidDeviceSettingsService(adbPath: "/SDK/adb", processRunner: runner)
        let result = await service.apply(.enableThreeButtonNavigation, to: "serial")
        guard case .failure(let failure) = result else {
            return XCTFail("An unchanged effective mode must not report success")
        }
        XCTAssertTrue(failure.message.contains("did not activate"))
    }

    func testReportsOverlayPermissionFailureWithoutVerifying() async {
        let runner = ScriptedDeviceSettingsProcessRunner(results: [
            successfulResult(output: "[x] com.android.internal.systemui.navbar.gestural\n"),
            permissionFailure(),
        ])
        let service = AndroidDeviceSettingsService(adbPath: "/SDK/adb", processRunner: runner)
        let result = await service.apply(.enableGestureNavigation, to: "serial")
        XCTAssertEqual(result, .failure(.commandFailed("Permission denial")))
        let invocations = await runner.invocations
        XCTAssertEqual(invocations.count, 2)
    }

    func testReportsFailedVerificationInsteadOfSuccess() async {
        let runner = ScriptedDeviceSettingsProcessRunner(results: [
            successfulResult(output: "[x] com.android.internal.systemui.navbar.gestural\n"),
            successfulResult(),
            permissionFailure(),
        ])
        let service = AndroidDeviceSettingsService(adbPath: "/SDK/adb", processRunner: runner)
        let result = await service.apply(.enableGestureNavigation, to: "serial")
        guard case .failure(let failure) = result else {
            return XCTFail("Unverified mode must not report success")
        }
        XCTAssertTrue(failure.message.contains("could not be verified"))
    }

    func testRenderingChangesRefreshRunningAppsAfterWritingTheProperty() async {
        let actions: [(AndroidDeviceSettingAction, String, String)] = [
            (.showLayoutBounds, "debug.layout", "true"),
            (.hideLayoutBounds, "debug.layout", "false"),
            (.showGPURenderingBars, "debug.hwui.profile", "visual_bars"),
            (.hideGPURenderingBars, "debug.hwui.profile", "false"),
        ]
        for reply in ["Result: Parcel(NULL)", "Result: Parcel(Error: 0xffffffffffffffb6 \"Not a data message\")"] {
            for (action, property, value) in actions {
                let runner = ScriptedDeviceSettingsProcessRunner(results: [
                    successfulResult(), successfulResult(output: reply + "\n"),
                ])
                let service = AndroidDeviceSettingsService(adbPath: "/SDK/adb", processRunner: runner)
                let result = await service.apply(action, to: "serial")
                XCTAssertEqual(result, .success(AndroidDeviceSettingOutcome(action: action, deviceSerial: "serial")))
                let invocations = await runner.invocations
                XCTAssertEqual(invocations, [
                    ["-s", "serial", "shell", "setprop", property, value],
                    ["-s", "serial", "shell", "service", "call", "activity", "1599295570"],
                ])
            }
        }
    }

    func testRefreshFailureReportsThatThePropertyWasSaved() async {
        for refresh in [permissionFailure(), successfulResult(output: "Result: Parcel(ffffffff 'Permission denied')")] {
            let runner = ScriptedDeviceSettingsProcessRunner(results: [successfulResult(), refresh])
            let service = AndroidDeviceSettingsService(adbPath: "/SDK/adb", processRunner: runner)
            let result = await service.apply(.showLayoutBounds, to: "serial")
            guard case .failure(let failure) = result else {
                return XCTFail("Failed refresh must not report that the overlay is showing")
            }
            XCTAssertTrue(failure.message.contains("Setting saved"))
            XCTAssertTrue(failure.message.contains("Restart the app"))
        }
    }

    private func permissionFailure() -> ProcessResult {
        ProcessResult(
            standardOutput: Data(), standardError: Data("Permission denial".utf8),
            exitStatus: 1, durationMilliseconds: 1, failureDescription: nil, wasCancelled: false
        )
    }

    private func successfulResult(output: String = "") -> ProcessResult {
        ProcessResult(
            standardOutput: Data(output.utf8),
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
