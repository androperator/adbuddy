import Foundation
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

final class EmulatorWindowServiceTests: XCTestCase {
    func testRecognizesAVDShorthandForEveryWindowPresentation() {
        let presentations = EmulatorHostProcessParser.parse("""
        15497 /SDK/emulator/qemu/darwin-aarch64/qemu-system-aarch64 @clawperator-pixel-12gb -no-snapshot-load -no-boot-anim
        15498 /SDK/emulator/qemu/darwin-aarch64/qemu-system-aarch64 @Studio_Device -qt-hide-window
        15499 /SDK/emulator/qemu/darwin-aarch64/qemu-system-aarch64 @CI_Device -no-window
        15500 /SDK/emulator/qemu/darwin-aarch64/qemu-system-aarch64 @
        """)

        XCTAssertEqual(presentations, [
            "clawperator-pixel-12gb": .standalone(processIdentifier: 15497),
            "Studio_Device": .embeddedInAndroidStudio,
            "CI_Device": .headless,
        ])
    }

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

    func testIdentifiesPresentationsWithRevealableHostWindows() {
        XCTAssertTrue(EmulatorWindowPresentation.standalone(processIdentifier: 19338).canRevealHostWindow)
        XCTAssertTrue(EmulatorWindowPresentation.embeddedInAndroidStudio.canRevealHostWindow)
        XCTAssertFalse(EmulatorWindowPresentation.headless.canRevealHostWindow)
        XCTAssertFalse(EmulatorWindowPresentation.unknown.canRevealHostWindow)
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
