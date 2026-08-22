import Foundation
import XCTest
@testable import ADBuddyCore

final class AndroidDeepLinkServiceTests: XCTestCase {
    func testLaunchesViewIntentWithFixedArgumentsAndOptionalTargetPackage() async throws {
        let runner = ScriptedDeepLinkProcessRunner(results: [
            successfulResult(
                standardOutput: """
                Starting: Intent { act=android.intent.action.VIEW dat=https://techmeme.com/... pkg=com.android.chrome }
                Status: ok
                Complete
                """
            ),
        ])
        let service = AndroidDeepLinkService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: runner
        )
        let deepLink = try XCTUnwrap(
            AndroidDeepLink(uri: "https://techmeme.com", targetPackageID: "com.android.chrome")
        )

        let result = await service.launch(deepLink, on: "emulator-5554")

        XCTAssertEqual(
            result,
            .success(AndroidDeepLinkLaunchOutcome(deepLink: deepLink, deviceSerial: "emulator-5554"))
        )
        let invocations = await runner.invocations
        XCTAssertEqual(
            invocations,
            [[
                "-s", "emulator-5554",
                "shell", "am", "start", "-W",
                "-a", "android.intent.action.VIEW",
                "-d", "https://techmeme.com",
                "-p", "com.android.chrome",
            ]]
        )
    }

    func testReportsAndroidActivityManagerErrorsEvenWhenADBExitsSuccessfully() async throws {
        let runner = ScriptedDeepLinkProcessRunner(results: [
            successfulResult(standardOutput: "Error: Activity not started, unable to resolve Intent\n"),
        ])
        let service = AndroidDeepLinkService(
            adbPath: "/SDK/platform-tools/adb",
            processRunner: runner
        )
        let deepLink = try XCTUnwrap(AndroidDeepLink(uri: "example://missing"))

        let result = await service.launch(deepLink, on: "device-serial")

        XCTAssertEqual(
            result,
            .failure(.commandFailed("Error: Activity not started, unable to resolve Intent"))
        )
    }

    func testRejectsIncompleteAndWhitespaceContainingURIs() {
        XCTAssertNil(AndroidDeepLink(uri: ""))
        XCTAssertNil(AndroidDeepLink(uri: "https://"))
        XCTAssertNil(AndroidDeepLink(uri: "https://example.com/with spaces"))
        XCTAssertNil(AndroidDeepLink(uri: "https://example.com", targetPackageID: "com.example app"))
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

private actor ScriptedDeepLinkProcessRunner: ProcessRunning {
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
