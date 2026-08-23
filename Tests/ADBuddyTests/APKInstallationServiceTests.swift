import Foundation
import XCTest
@testable import ADBuddyCore

final class APKInstallationServiceTests: XCTestCase {
    func testInstallsAPKWithReplaceFlag() async {
        let runner = ScriptedAPKProcessRunner(results: [successfulResult()])
        let archive = AndroidPackageArchive(fileURL: URL(fileURLWithPath: "/Downloads/example.apk"))
        let service = APKInstallationService(
            adbPath: "/SDK/platform-tools/adb",
            aapt2Path: nil,
            processRunner: runner,
            isReadableArchive: { _ in true }
        )

        let result = await service.install(archive, on: "device-serial", openAfterInstall: false)

        XCTAssertEqual(
            result,
            .success(
                APKInstallationOutcome(
                    archive: archive,
                    deviceSerial: "device-serial",
                    launchResult: .notRequested
                )
            )
        )
        let invocations = await runner.invocations
        XCTAssertEqual(invocations, [["-s", "device-serial", "install", "-r", "/Downloads/example.apk"]])
    }

    func testOpensInstalledAPKUsingItsLaunchActivity() async {
        let runner = ScriptedAPKProcessRunner(results: [
            successfulResult(
                standardOutput: """
                package: name='com.example.app' versionCode='1'
                launchable-activity: name='.MainActivity'  label='Example' icon=''
                """
            ),
            successfulResult(standardOutput: "Performing Streamed Install\nSuccess\n"),
            successfulResult(standardOutput: "Status: ok\n"),
        ])
        let archive = AndroidPackageArchive(fileURL: URL(fileURLWithPath: "/Downloads/example.apk"))
        let service = APKInstallationService(
            adbPath: "/SDK/platform-tools/adb",
            aapt2Path: "/SDK/build-tools/36.0.0/aapt2",
            processRunner: runner,
            isReadableArchive: { _ in true }
        )

        let result = await service.install(archive, on: "device-serial", openAfterInstall: true)

        let target = AndroidAPKLaunchTarget(
            packageID: "com.example.app",
            activityName: ".MainActivity"
        )
        XCTAssertEqual(
            result,
            .success(
                APKInstallationOutcome(
                    archive: archive,
                    deviceSerial: "device-serial",
                    launchResult: .launched(target)
                )
            )
        )
        let invocations = await runner.invocations
        XCTAssertEqual(
            invocations,
            [
                ["dump", "badging", "/Downloads/example.apk"],
                ["-s", "device-serial", "install", "-r", "/Downloads/example.apk"],
                [
                    "-s", "device-serial",
                    "shell", "am", "start", "-W",
                    "-n", "com.example.app/com.example.app.MainActivity",
                ],
            ]
        )
    }

    func testReportsSuccessfulInstallWhenAPKCannotBeOpened() async {
        let runner = ScriptedAPKProcessRunner(results: [successfulResult()])
        let archive = AndroidPackageArchive(fileURL: URL(fileURLWithPath: "/Downloads/example.apk"))
        let service = APKInstallationService(
            adbPath: "/SDK/platform-tools/adb",
            aapt2Path: nil,
            processRunner: runner,
            isReadableArchive: { _ in true }
        )

        let result = await service.install(archive, on: "device-serial", openAfterInstall: true)

        XCTAssertEqual(
            result,
            .success(
                APKInstallationOutcome(
                    archive: archive,
                    deviceSerial: "device-serial",
                    launchResult: .unavailable(
                        "Installed, but could not open the app because aapt2 was not found in the Android SDK."
                    )
                )
            )
        )
        let invocations = await runner.invocations
        XCTAssertEqual(invocations, [["-s", "device-serial", "install", "-r", "/Downloads/example.apk"]])
    }

    func testDoesNotStartADBForAnUnreadableArchive() async {
        let runner = ScriptedAPKProcessRunner(results: [])
        let service = APKInstallationService(
            adbPath: "/SDK/platform-tools/adb",
            aapt2Path: nil,
            processRunner: runner,
            isReadableArchive: { _ in false }
        )

        let result = await service.install(
            AndroidPackageArchive(fileURL: URL(fileURLWithPath: "/Downloads/example.apk")),
            on: "device-serial",
            openAfterInstall: false
        )

        XCTAssertEqual(result, .failure(.invalidArchive))
        let invocations = await runner.invocations
        XCTAssertEqual(invocations, [])
    }

    func testTreatsAndroidFailureOutputAsAnInstallationFailure() async {
        let runner = ScriptedAPKProcessRunner(results: [
            successfulResult(standardOutput: "Failure [INSTALL_FAILED_VERSION_DOWNGRADE]\n"),
        ])
        let service = APKInstallationService(
            adbPath: "/SDK/platform-tools/adb",
            aapt2Path: nil,
            processRunner: runner,
            isReadableArchive: { _ in true }
        )

        let result = await service.install(
            AndroidPackageArchive(fileURL: URL(fileURLWithPath: "/Downloads/example.apk")),
            on: "device-serial",
            openAfterInstall: false
        )

        XCTAssertEqual(
            result,
            .failure(.commandFailed("Failure [INSTALL_FAILED_VERSION_DOWNGRADE]"))
        )
    }

    func testReportsLaunchErrorWhenADBExitsSuccessfully() async {
        let runner = ScriptedAPKProcessRunner(results: [
            successfulResult(
                standardOutput: """
                package: name='com.example.app'
                launchable-activity: name='.MainActivity'
                """
            ),
            successfulResult(),
            ProcessResult(
                standardOutput: Data(),
                standardError: Data("Error: Activity class does not exist.\n".utf8),
                exitStatus: 0,
                durationMilliseconds: 1,
                failureDescription: nil,
                wasCancelled: false
            ),
        ])
        let archive = AndroidPackageArchive(fileURL: URL(fileURLWithPath: "/Downloads/example.apk"))
        let service = APKInstallationService(
            adbPath: "/SDK/platform-tools/adb",
            aapt2Path: "/SDK/build-tools/36.0.0/aapt2",
            processRunner: runner,
            isReadableArchive: { _ in true }
        )

        let result = await service.install(archive, on: "device-serial", openAfterInstall: true)

        XCTAssertEqual(
            result,
            .success(
                APKInstallationOutcome(
                    archive: archive,
                    deviceSerial: "device-serial",
                    launchResult: .failed("Error: Activity class does not exist.")
                )
            )
        )
    }

    func testParsesRelativeAndFullyQualifiedLaunchActivities() {
        XCTAssertEqual(
            AndroidAPKLaunchTargetParser.parse(
                """
                package: name='com.example.app'
                launchable-activity: name='com.example.app.MainActivity'
                """
            ),
            AndroidAPKLaunchTarget(
                packageID: "com.example.app",
                activityName: "com.example.app.MainActivity"
            )
        )
        XCTAssertNil(
            AndroidAPKLaunchTargetParser.parse("package: name='com.example.library'")
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

private actor ScriptedAPKProcessRunner: ProcessRunning {
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
        guard !results.isEmpty else {
            return ProcessResult(
                standardOutput: Data(),
                standardError: Data(),
                exitStatus: nil,
                durationMilliseconds: 0,
                failureDescription: "Unexpected process invocation.",
                wasCancelled: false
            )
        }
        return results.removeFirst()
    }
}
