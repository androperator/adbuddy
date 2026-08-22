import Foundation
import XCTest
@testable import ADBuddy

final class AndroidEmulatorServiceTests: XCTestCase {
    func testListsInstalledVirtualDevicesWithFixedArguments() async {
        let processRunner = EmulatorProcessRunner(
            result: successfulResult(
                standardOutput: """
                Pixel_9

                Pixel_9_Pro
                Pixel_9
                """
            )
        )
        let service = AndroidEmulatorService(
            sdk: sdk,
            processRunner: processRunner,
            isExecutable: { $0 == "/SDK/emulator/emulator" }
        )

        let result = await service.listVirtualDevices()

        XCTAssertEqual(
            result,
            .success([
                AndroidVirtualDevice(name: "Pixel_9"),
                AndroidVirtualDevice(name: "Pixel_9_Pro"),
            ])
        )
        let invocations = await processRunner.invocations
        XCTAssertEqual(
            invocations,
            [EmulatorProcessInvocation(
                executablePath: "/SDK/emulator/emulator",
                arguments: ["-list-avds"]
            )]
        )
    }

    func testReportsListingFailureFromStandardError() async {
        let service = AndroidEmulatorService(
            sdk: sdk,
            processRunner: EmulatorProcessRunner(
                result: ProcessResult(
                    standardOutput: Data(),
                    standardError: Data("Unable to find AVD\n".utf8),
                    exitStatus: 1,
                    durationMilliseconds: 2,
                    failureDescription: nil,
                    wasCancelled: false
                )
            ),
            isExecutable: { _ in true }
        )

        let result = await service.listVirtualDevices()

        XCTAssertEqual(result, .failure(.commandFailed("Unable to find AVD")))
    }

    func testLaunchesSelectedVirtualDeviceWithStandaloneArguments() {
        let launcher = EmulatorApplicationLauncher()
        let service = AndroidEmulatorService(
            sdk: sdk,
            processRunner: EmulatorProcessRunner(result: successfulResult()),
            applicationLauncher: launcher,
            isExecutable: { $0 == "/SDK/emulator/emulator" }
        )

        let result = service.launch(AndroidVirtualDevice(name: "Pixel_9_Pro"))

        XCTAssertEqual(result, .launched)
        XCTAssertEqual(
            launcher.invocation,
            EmulatorProcessInvocation(
                executablePath: "/SDK/emulator/emulator",
                arguments: ["-avd", "Pixel_9_Pro"]
            )
        )
    }

    func testReportsMissingEmulatorExecutable() async {
        let service = AndroidEmulatorService(
            sdk: sdk,
            processRunner: EmulatorProcessRunner(result: successfulResult()),
            isExecutable: { _ in false }
        )

        let result = await service.listVirtualDevices()

        XCTAssertEqual(result, .failure(.emulatorNotFound))
    }

    func testDescribesUnavailableSDK() {
        XCTAssertEqual(
            AndroidEmulatorFailure.sdkUnavailable(.adbNotFound).title,
            "ADB Not Found"
        )
        XCTAssertEqual(
            AndroidEmulatorFailure.sdkUnavailable(.adbNotFound).detail,
            "An Android SDK location was found, but platform-tools/adb is missing or is not executable."
        )
    }

    private var sdk: AndroidSDK {
        AndroidSDK(
            rootPath: "/SDK",
            adbPath: "/SDK/platform-tools/adb",
            source: .androidHome
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

private struct EmulatorProcessInvocation: Equatable {
    let executablePath: String
    let arguments: [String]
}

private actor EmulatorProcessRunner: ProcessRunning {
    private let result: ProcessResult
    private var recordedInvocations: [EmulatorProcessInvocation] = []

    init(result: ProcessResult) {
        self.result = result
    }

    var invocations: [EmulatorProcessInvocation] {
        recordedInvocations
    }

    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        recordedInvocations.append(
            EmulatorProcessInvocation(executablePath: executablePath, arguments: arguments)
        )
        return result
    }
}

private final class EmulatorApplicationLauncher: ApplicationProcessLaunching, @unchecked Sendable {
    private(set) var invocation: EmulatorProcessInvocation?

    func launch(executablePath: String, arguments: [String]) throws {
        invocation = EmulatorProcessInvocation(executablePath: executablePath, arguments: arguments)
    }
}
