import Foundation
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

final class EmulatorWindowServiceTests: XCTestCase {
    func testMapsStandaloneEmbeddedAndHeadlessEmulatorProcesses() async {
        let runner = EmulatorWindowProcessRunner(
            result: successfulResult(
                standardOutput: """
                 19338 /Users/chrislacy/Library/Android/sdk/emulator/qemu/darwin-aarch64/qemu-system-aarch64 -avd Pixel_9_Pro
                 85149 /Users/chrislacy/Library/Android/sdk/emulator/qemu/darwin-aarch64/qemu-system-aarch64 -avd Pixel_9 -qt-hide-window -grpc-use-token
                 90000 /Users/chrislacy/Library/Android/sdk/emulator/qemu/darwin-aarch64/qemu-system-aarch64 -avd CI_Device -no-window
                 90100 /System/Library/CoreServices/Finder.app/Contents/MacOS/Finder
                """
            )
        )
        let service = EmulatorWindowService(processRunner: runner)

        let presentations = await service.discoverWindowPresentations()

        XCTAssertEqual(
            presentations,
            [
                "Pixel_9_Pro": .standalone(processIdentifier: 19338),
                "Pixel_9": .embeddedInAndroidStudio,
                "CI_Device": .headless,
            ]
        )
        let invocations = await runner.invocations
        XCTAssertEqual(invocations, [["-axo", "pid=,command="]])
    }

    func testReturnsNoPresentationWhenProcessListingFails() async {
        let runner = EmulatorWindowProcessRunner(
            result: ProcessResult(
                standardOutput: Data(),
                standardError: Data("Operation not permitted".utf8),
                exitStatus: 1,
                durationMilliseconds: 1,
                failureDescription: nil,
                wasCancelled: false
            )
        )
        let service = EmulatorWindowService(processRunner: runner)

        let presentations = await service.discoverWindowPresentations()

        XCTAssertEqual(presentations, [:])
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

private actor EmulatorWindowProcessRunner: ProcessRunning {
    private let result: ProcessResult
    private var recordedInvocations: [[String]] = []

    init(result: ProcessResult) {
        self.result = result
    }

    var invocations: [[String]] {
        recordedInvocations
    }

    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        recordedInvocations.append(arguments)
        return result
    }
}
