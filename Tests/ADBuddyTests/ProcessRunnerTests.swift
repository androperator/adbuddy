import XCTest
@testable import ADBuddy

final class ProcessRunnerTests: XCTestCase {
    func testDrainsLargeStandardOutputWithoutBlocking() async {
        let result = await ProcessRunner().run(
            executablePath: "/bin/dd",
            arguments: ["if=/dev/zero", "bs=65536", "count=32"]
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.standardOutput.count, 2_097_152)
    }
}
