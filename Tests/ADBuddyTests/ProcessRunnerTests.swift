import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

final class ProcessRunnerTests: XCTestCase {
    func testDrainsLargeStandardOutputWithoutBlocking() async {
        let result = await ProcessRunner().run(
            executablePath: "/bin/dd",
            arguments: ["if=/dev/zero", "bs=65536", "count=32"]
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.standardOutput.count, 2_097_152)
    }
    func testInterruptsRegisteredProcessWithoutCancellingOtherProcesses() async {
        let runner = ProcessRunner()
        async let other = runner.run(executablePath: "/bin/sleep", arguments: ["0.2"])
        let result = await runner.run(
            executablePath: "/bin/sleep", arguments: ["30"], identifier: "recording-under-test",
            environment: nil,
            onStarted: { XCTAssertTrue(runner.interrupt(identifier: "recording-under-test")) }
        )
        let otherResult = await other
        XCTAssertTrue(otherResult.succeeded)
        XCTAssertEqual(result.exitStatus, 2)
        XCTAssertFalse(result.wasCancelled)
        XCTAssertFalse(runner.interrupt(identifier: "recording-under-test"))
    }

    func testPassesExplicitEnvironmentToManagedProcess() async {
        let result = await ProcessRunner().run(
            executablePath: "/usr/bin/printenv", arguments: ["ADBUDDY_TEST_VALUE"],
            identifier: "environment-test", environment: ["ADBUDDY_TEST_VALUE": "path with spaces"],
            onStarted: {}
        )
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(String(decoding: result.standardOutput, as: UTF8.self), "path with spaces\n")
    }
}
