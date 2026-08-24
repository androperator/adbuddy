import Foundation
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

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

    func testStartsSelectedVirtualDeviceWithQuickBootArguments() {
        let launcher = EmulatorApplicationLauncher()
        let service = AndroidEmulatorService(
            sdk: sdk,
            processRunner: EmulatorProcessRunner(result: successfulResult()),
            applicationLauncher: launcher,
            isExecutable: { $0 == "/SDK/emulator/emulator" }
        )

        let result = service.start(AndroidVirtualDevice(name: "Pixel_9_Pro"))

        XCTAssertEqual(result, .launched)
        XCTAssertEqual(
            launcher.invocation,
            EmulatorProcessInvocation(
                executablePath: "/SDK/emulator/emulator",
                arguments: ["-avd", "Pixel_9_Pro"]
            )
        )
    }

    func testStartsSelectedVirtualDeviceWithColdBootAndWipeDataArguments() {
        let launcher = EmulatorApplicationLauncher()
        let service = AndroidEmulatorService(
            sdk: sdk,
            processRunner: EmulatorProcessRunner(result: successfulResult()),
            applicationLauncher: launcher,
            isExecutable: { _ in true }
        )

        XCTAssertEqual(
            service.start(AndroidVirtualDevice(name: "Pixel_9"), mode: .coldBoot),
            .launched
        )
        XCTAssertEqual(
            launcher.invocation?.arguments,
            ["-avd", "Pixel_9", "-no-snapshot-load"]
        )

        XCTAssertEqual(
            service.start(AndroidVirtualDevice(name: "Pixel_9"), mode: .wipeData),
            .launched
        )
        XCTAssertEqual(
            launcher.invocation?.arguments,
            ["-avd", "Pixel_9", "-wipe-data"]
        )
    }

    func testMapsConnectedEmulatorSerialsToVirtualDeviceNames() async {
        let processRunner = EmulatorProcessRunner(results: [
            successfulResult(standardOutput: "Pixel_9\nOK\n"),
            successfulResult(standardOutput: "Pixel_9_Pro\nOK\n"),
        ])
        let service = AndroidEmulatorService(
            sdk: sdk,
            processRunner: processRunner,
            isExecutable: { _ in true }
        )

        let devices = await service.runningVirtualDevices(in: [
            connectedEmulator(serial: "emulator-5554"),
            physicalDevice,
            connectedEmulator(serial: "emulator-5556"),
        ])

        XCTAssertEqual(
            devices,
            [
                "Pixel_9": connectedEmulator(serial: "emulator-5554"),
                "Pixel_9_Pro": connectedEmulator(serial: "emulator-5556"),
            ]
        )
        let invocations = await processRunner.invocations
        XCTAssertEqual(
            invocations,
            [
                EmulatorProcessInvocation(
                    executablePath: "/SDK/platform-tools/adb",
                    arguments: ["-s", "emulator-5554", "emu", "avd", "name"]
                ),
                EmulatorProcessInvocation(
                    executablePath: "/SDK/platform-tools/adb",
                    arguments: ["-s", "emulator-5556", "emu", "avd", "name"]
                ),
            ]
        )
    }

    func testUsesTheConfiguredAVDNameForSavedMedia() async {
        let processRunner = EmulatorProcessRunner(
            result: successfulResult(standardOutput: "Pixel_9_Pro\nOK\n")
        )
        let service = AndroidEmulatorService(
            sdk: sdk,
            processRunner: processRunner,
            isExecutable: { _ in true }
        )
        let emulator = connectedEmulator(serial: "emulator-5554")

        let mediaDevice = await service.deviceWithUserFacingName(emulator)

        XCTAssertEqual(mediaDevice.displayName, "Pixel_9_Pro")
        XCTAssertEqual(mediaDevice.serial, emulator.serial)
        XCTAssertEqual(mediaDevice.model, emulator.model)
        let invocations = await processRunner.invocations
        XCTAssertEqual(
            invocations,
            [EmulatorProcessInvocation(
                executablePath: "/SDK/platform-tools/adb",
                arguments: ["-s", "emulator-5554", "emu", "avd", "name"]
            )]
        )
    }

    func testRetainsTheADBModelNameWhenAnAVDNameCannotBeResolved() async {
        let processRunner = EmulatorProcessRunner(
            result: successfulResult(standardOutput: "KO: unknown command\n")
        )
        let service = AndroidEmulatorService(
            sdk: sdk,
            processRunner: processRunner,
            isExecutable: { _ in true }
        )
        let emulator = connectedEmulator(serial: "emulator-5554")

        let mediaDevice = await service.deviceWithUserFacingName(emulator)

        XCTAssertEqual(mediaDevice, emulator)
    }

    func testStopsRunningVirtualDeviceWithFixedADBArguments() async {
        let processRunner = EmulatorProcessRunner(result: successfulResult())
        let service = AndroidEmulatorService(
            sdk: sdk,
            processRunner: processRunner,
            isExecutable: { _ in true }
        )

        let result = await service.stop(connectedEmulator(serial: "emulator-5556"))

        XCTAssertEqual(result, .stopped)
        let invocations = await processRunner.invocations
        XCTAssertEqual(
            invocations,
            [EmulatorProcessInvocation(
                executablePath: "/SDK/platform-tools/adb",
                arguments: ["-s", "emulator-5556", "emu", "kill"]
            )]
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

    private func connectedEmulator(serial: String) -> AndroidDevice {
        AndroidDevice(
            serial: serial,
            displayName: "sdk gphone64 arm64",
            connectionState: .connected,
            kind: .emulator,
            model: nil,
            product: nil,
            deviceCodeName: nil,
            transportID: nil
        )
    }

    private var physicalDevice: AndroidDevice {
        AndroidDevice(
            serial: "physical-device",
            displayName: "Pixel 10 Pro",
            connectionState: .connected,
            kind: .physical,
            model: nil,
            product: nil,
            deviceCodeName: nil,
            transportID: nil
        )
    }
}

private struct EmulatorProcessInvocation: Equatable {
    let executablePath: String
    let arguments: [String]
}

private actor EmulatorProcessRunner: ProcessRunning {
    private var results: [ProcessResult]
    private var recordedInvocations: [EmulatorProcessInvocation] = []

    init(result: ProcessResult) {
        results = [result]
    }

    init(results: [ProcessResult]) {
        self.results = results
    }

    var invocations: [EmulatorProcessInvocation] {
        recordedInvocations
    }

    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        recordedInvocations.append(
            EmulatorProcessInvocation(executablePath: executablePath, arguments: arguments)
        )
        return results.removeFirst()
    }
}

private final class EmulatorApplicationLauncher: ApplicationProcessLaunching, @unchecked Sendable {
    private(set) var invocation: EmulatorProcessInvocation?

    func launch(executablePath: String, arguments: [String]) throws {
        invocation = EmulatorProcessInvocation(executablePath: executablePath, arguments: arguments)
    }
}
