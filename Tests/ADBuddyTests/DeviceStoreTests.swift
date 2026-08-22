import Foundation
import Observation
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

@MainActor
final class DeviceStoreTests: XCTestCase {
    func testUsesOneSecondAutomaticRefreshInterval() {
        XCTAssertEqual(DeviceStore.automaticRefreshInterval, .seconds(1))
    }

    func testPollingRefreshUpdatesDeviceState() async {
        let store = makeDeviceStore()

        store.refreshFromPolling()

        await waitForDeviceRefresh()
        XCTAssertNotEqual(store.status, .loading)
    }

    func testUnchangedPollingRefreshDoesNotInvalidateDevicePresentation() async {
        let store = makeDeviceStore()
        store.refreshFromPolling()
        await waitForDeviceRefresh()

        let changeExpectation = expectation(description: "unchanged polling refresh")
        changeExpectation.isInverted = true
        withObservationTracking {
            _ = store.devices
            _ = store.status
        } onChange: {
            changeExpectation.fulfill()
        }

        store.refreshFromPolling()

        await fulfillment(of: [changeExpectation], timeout: 0.1)
    }

    func testRunsForegroundAppActionAndReportsTheResolvedPackage() async throws {
        let runner = ScriptedDeviceStoreProcessRunner(results: [
            successfulResult(standardOutput: "List of devices attached\nserial\tdevice model:Pixel_9\n"),
            successfulResult(
                standardOutput: "mResumedActivity: ActivityRecord{123 u0 com.example.app/.MainActivity t42}\n"
            ),
            successfulResult(),
        ])
        let store = makeDeviceStore(processRunner: runner)
        store.refreshFromPolling()
        await waitForDeviceRefresh()
        let device = try XCTUnwrap(store.devices.first)

        store.performAppAction(.forceStop, for: device)
        await waitForAppActionFeedback(in: store)

        XCTAssertEqual(
            store.appActionFeedback,
            .success(
                AndroidAppActionOutcome(
                    action: .forceStop,
                    application: AndroidForegroundApplication(packageID: "com.example.app")
                )
            )
        )
        let invocations = await runner.invocations
        XCTAssertEqual(
            invocations,
            [
                ["devices", "-l"],
                ["-s", "serial", "shell", "dumpsys", "activity", "activities"],
                ["-s", "serial", "shell", "am", "force-stop", "com.example.app"],
            ]
        )
    }

    func testRequestsUninstallConfirmationForTheResolvedForegroundApp() async throws {
        let runner = ScriptedDeviceStoreProcessRunner(results: [
            successfulResult(standardOutput: "List of devices attached\nserial\tdevice model:Pixel_9\n"),
            successfulResult(
                standardOutput: "topResumedActivity=ActivityRecord{123 u0 com.example.app/.MainActivity t42}\n"
            ),
        ])
        let store = makeDeviceStore(processRunner: runner)
        store.refreshFromPolling()
        await waitForDeviceRefresh()
        let device = try XCTUnwrap(store.devices.first)

        store.requestUninstallForegroundApp(for: device)
        await waitForUninstallRequest(in: store)

        XCTAssertEqual(
            store.foregroundAppUninstallRequest,
            ForegroundAppUninstallRequest(
                device: device,
                application: AndroidForegroundApplication(packageID: "com.example.app")
            )
        )
    }

    func testLaunchesDeepLinkOnTheSelectedDevice() async throws {
        let runner = ScriptedDeviceStoreProcessRunner(results: [
            successfulResult(standardOutput: "List of devices attached\nserial\tdevice model:Pixel_9\n"),
            successfulResult(standardOutput: "Status: ok\nComplete\n"),
        ])
        let store = makeDeviceStore(processRunner: runner)
        store.refreshFromPolling()
        await waitForDeviceRefresh()
        let device = try XCTUnwrap(store.devices.first)
        let deepLink = try XCTUnwrap(
            AndroidDeepLink(uri: "https://techmeme.com", targetPackageID: "com.android.chrome")
        )

        store.launchDeepLink(deepLink, on: device)
        await waitForDeepLinkLaunchFeedback(in: store)

        XCTAssertEqual(
            store.deepLinkLaunchFeedback,
            .success(
                AndroidDeepLinkLaunchOutcome(deepLink: deepLink, deviceSerial: "serial"),
                deviceName: "Pixel 9"
            )
        )
        let invocations = await runner.invocations
        XCTAssertEqual(
            invocations,
            [
                ["devices", "-l"],
                [
                    "-s", "serial",
                    "shell", "am", "start", "-W",
                    "-a", "android.intent.action.VIEW",
                    "-d", "https://techmeme.com",
                    "-p", "com.android.chrome",
                ],
            ]
        )
    }

    private func makeDeviceStore(
        processRunner: any ProcessRunning = DeviceListProcessRunner()
    ) -> DeviceStore {
        DeviceStore(
            sdkLocator: sdkLocator,
            processRunner: processRunner,
            screenshotClipboard: TestScreenshotClipboard(),
            mediaNotifier: TestMediaNotifier()
        )
    }

    private var sdkLocator: AndroidSDKLocator {
        AndroidSDKLocator(
            environment: ["ANDROID_HOME": "/SDK"],
            homeDirectoryPath: "/Users/example",
            pathExists: { $0 == "/SDK" },
            isExecutable: { $0 == "/SDK/platform-tools/adb" }
        )
    }

    private func waitForDeviceRefresh() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    private func waitForAppActionFeedback(in store: DeviceStore) async {
        for _ in 0..<100 {
            if store.appActionFeedback != nil {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for foreground app action feedback.")
    }

    private func waitForUninstallRequest(in store: DeviceStore) async {
        for _ in 0..<100 {
            if store.foregroundAppUninstallRequest != nil {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for foreground app uninstall request.")
    }

    private func waitForDeepLinkLaunchFeedback(in store: DeviceStore) async {
        for _ in 0..<100 {
            if store.deepLinkLaunchFeedback != nil {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for deep link launch feedback.")
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

private struct DeviceListProcessRunner: ProcessRunning {
    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        ProcessResult(
            standardOutput: Data("List of devices attached\\nserial\\tdevice model:Pixel_9\\n".utf8),
            standardError: Data(),
            exitStatus: 0,
            durationMilliseconds: 5,
            failureDescription: nil,
            wasCancelled: false
        )
    }
}

private actor ScriptedDeviceStoreProcessRunner: ProcessRunning {
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

@MainActor
private struct TestScreenshotClipboard: ScreenshotClipboardCopying {
    func copyScreenshot(at fileURL: URL) -> ScreenshotClipboardCopyResult {
        .copied
    }
}

private struct TestMediaNotifier: SavedMediaNotifying {
    func notifyAboutSavedMedia(at fileURL: URL, kind: SavedMediaNotificationKind) async {}
}
