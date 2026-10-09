import Foundation
import Observation
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

@MainActor
final class DeviceStoreTests: XCTestCase {
    func testEmulatorNameSurvivesOfflineStateButClearsOnDisconnect() async {
        let runner = ScriptedDeviceStoreProcessRunner(results: [
            successfulResult(standardOutput: "List of devices attached\nemulator-5556 device model:sdk_gphone64_arm64\n"),
            successfulResult(standardOutput: "Pixel_9\nOK\n"),
            successfulResult(standardOutput: "List of devices attached\nemulator-5556 offline\n"),
            successfulResult(standardOutput: "List of devices attached\n"),
            successfulResult(standardOutput: "List of devices attached\nemulator-5556 offline\n"),
        ])
        let store = makeDeviceStore(processRunner: runner)
        for expectedNames in [["Pixel_9"], ["Pixel_9"], [], ["emulator-5556"]] {
            store.refreshFromPolling()
            for _ in 0..<100 { await Task.yield() }
            XCTAssertEqual(store.devices.map(\.displayName), expectedNames)
        }
    }

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

    func testLoadsDisplayDetailsForAUsableDevice() async throws {
        let runner = ScriptedDeviceStoreProcessRunner(results: [
            successfulResult(standardOutput: "List of devices attached\nserial\tdevice model:Pixel_9\n"),
            successfulResult(standardOutput: "16\n"),
            successfulResult(standardOutput: "36\n"),
            successfulResult(standardOutput: "Physical size: 1080x2400\n"),
            successfulResult(standardOutput: "Physical density: 420\n"),
            successfulResult(standardOutput: "en-AU\n"),
            successfulResult(),
        ])
        let store = makeDeviceStore(processRunner: runner)
        store.refreshFromPolling()
        await waitForDeviceRefresh()
        let device = try XCTUnwrap(store.devices.first)

        store.loadDeviceDetails(for: device)
        await waitForDeviceDetails(in: store, for: device)

        XCTAssertEqual(
            store.deviceDetails(for: device),
            AndroidDeviceDetails(
                androidVersion: "16",
                apiLevel: "36",
                screen: AndroidDeviceScreen(
                    physicalPixelSize: try XCTUnwrap(AndroidDisplaySize(width: 1080, height: 2400)),
                    logicalDensityDPI: 420
                ),
                languageIdentifier: "en-AU"
            )
        )
        let invocations = await runner.invocations
        XCTAssertEqual(
            invocations,
            [
                ["devices", "-l"],
                ["-s", "serial", "shell", "getprop", "ro.build.version.release"],
                ["-s", "serial", "shell", "getprop", "ro.build.version.sdk"],
                ["-s", "serial", "shell", "wm", "size"],
                ["-s", "serial", "shell", "wm", "density"],
                ["-s", "serial", "shell", "getprop", "persist.sys.locale"],
                ["-s", "serial", "shell", "dumpsys", "display"],
            ]
        )
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

    func testUpdatesTheSelectedDeviceSystemSetting() async throws {
        let runner = ScriptedDeviceStoreProcessRunner(results: [
            successfulResult(standardOutput: "List of devices attached\nserial\tdevice model:Pixel_9\n"),
            successfulResult(),
            successfulResult(standardOutput: "Result: Parcel(NULL)"),
        ])
        let store = makeDeviceStore(processRunner: runner)
        store.refreshFromPolling()
        await waitForDeviceRefresh()
        let device = try XCTUnwrap(store.devices.first)

        store.performDeviceSetting(.showGPURenderingBars, for: device)
        await waitForDeviceSettingFeedback(in: store)

        XCTAssertEqual(
            store.deviceSettingFeedback,
            .success(
                AndroidDeviceSettingOutcome(action: .showGPURenderingBars, deviceSerial: "serial"),
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
                    "shell", "setprop", "debug.hwui.profile", "visual_bars",
                ],
                ["-s", "serial", "shell", "service", "call", "activity", "1599295570"],
            ]
        )
    }

    func testCopiesCompletedRecordingWhenAutomaticMediaCopyIsEnabled() async throws {
        let suiteName = "DeviceStoreTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated user defaults")
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let mediaDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ADBuddyDeviceStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: mediaDirectory)
        }
        let preferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: mediaDirectory
        )
        let mediaClipboard = RecordingMediaClipboard()
        let store = DeviceStore(
            preferences: preferences,
            sdkLocator: sdkLocator,
            processRunner: RecordingDeviceStoreProcessRunner(),
            mediaClipboard: mediaClipboard,
            mediaNotifier: TestMediaNotifier(),
            recordingCapture: TestScreenRecordingCapture(writesFile: true)
        )
        store.refreshFromPolling()
        await waitForDeviceRefresh()
        let device = try XCTUnwrap(store.devices.first)

        store.startScreenRecording(of: device, options: .default)
        await waitForScreenRecordingFeedback(in: store)

        XCTAssertEqual(mediaClipboard.recordingURLs.count, 1)
        XCTAssertEqual(mediaClipboard.recordingURLs.first?.pathExtension, "mp4")
        XCTAssertEqual(
            store.screenRecordingFeedback,
            .success(
                try XCTUnwrap(mediaClipboard.recordingURLs.first),
                warning: nil,
                copiedToClipboard: true
            )
        )
    }

    func testReportsMultipleClipsOnceAndCopiesAllPrimaryFiles() async throws {
        let suiteName = "DeviceStoreTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated user defaults")
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let mediaDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ADBuddyDeviceStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: mediaDirectory)
        }
        let preferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: mediaDirectory
        )
        let mediaClipboard = RecordingMediaClipboard()
        let notifier = RecordingSessionNotifier()
        let store = DeviceStore(
            preferences: preferences,
            sdkLocator: sdkLocator,
            processRunner: RecordingDeviceStoreProcessRunner(),
            mediaClipboard: mediaClipboard,
            mediaNotifier: notifier,
            recordingCapture: TestScreenRecordingCapture(writesFile: true, clipCount: 3)
        )
        store.refreshFromPolling()
        await waitForDeviceRefresh()
        let device = try XCTUnwrap(store.devices.first)

        store.startScreenRecording(of: device, options: .default)
        await waitForScreenRecordingFeedback(in: store)

        XCTAssertEqual(mediaClipboard.recordingURLs.count, 3)
        XCTAssertEqual(mediaClipboard.recordingURLs.first?.pathExtension, "mp4")
        XCTAssertEqual(
            store.screenRecordingFeedback,
            .success(
                try XCTUnwrap(mediaClipboard.recordingURLs.first),
                warning: nil,
                copiedToClipboard: true,
                clipCount: 3
            )
        )
        for _ in 0..<100 {
            if await notifier.fileGroups.count > 0 { break }
            await Task.yield()
        }
        let groups = await notifier.fileGroups
        XCTAssertEqual(groups, [mediaClipboard.recordingURLs])
        XCTAssertNil(store.screenRecordingActivity)
    }

    func testRevealsSavedScreenshotsAndRecordingsWhenEnabled() async throws {
        let suiteName = "DeviceStoreTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated user defaults")
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let mediaDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ADBuddyDeviceStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: mediaDirectory)
        }
        let preferences = AppPreferences(
            userDefaults: userDefaults,
            defaultScreenshotDirectory: mediaDirectory
        )
        preferences.revealMediaInFinder = true
        let finderRevealer = RecordingMediaFinderRevealer()
        let store = DeviceStore(
            preferences: preferences,
            sdkLocator: sdkLocator,
            processRunner: RecordingDeviceStoreProcessRunner(),
            mediaClipboard: TestMediaClipboard(),
            mediaFinderRevealer: finderRevealer,
            mediaNotifier: TestMediaNotifier(),
            recordingCapture: TestScreenRecordingCapture(writesFile: true)
        )
        store.refreshFromPolling()
        await waitForDeviceRefresh()
        let device = try XCTUnwrap(store.devices.first)

        store.takeScreenshot(of: device)
        await waitForScreenshotFeedback(in: store)

        store.startScreenRecording(of: device, options: .default)
        await waitForScreenRecordingFeedback(in: store)

        XCTAssertEqual(finderRevealer.mediaURLs.map(\.pathExtension), ["png", "mp4"])
    }

    private func makeDeviceStore(
        processRunner: any ProcessRunning = DeviceListProcessRunner()
    ) -> DeviceStore {
        DeviceStore(
            sdkLocator: sdkLocator,
            processRunner: processRunner,
            mediaClipboard: TestMediaClipboard(),
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

    private func waitForDeviceDetails(in store: DeviceStore, for device: AndroidDevice) async {
        for _ in 0..<100 {
            if store.deviceDetails(for: device) != nil {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for Android device details.")
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

    private func waitForDeviceSettingFeedback(in store: DeviceStore) async {
        for _ in 0..<100 {
            if store.deviceSettingFeedback != nil {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for device setting feedback.")
    }

    private func waitForScreenRecordingFeedback(in store: DeviceStore) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while clock.now < deadline {
            if store.screenRecordingFeedback != nil {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for screen recording feedback.")
    }

    private func waitForScreenshotFeedback(in store: DeviceStore) async {
        for _ in 0..<100 {
            if store.screenshotFeedback != nil {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for screenshot feedback.")
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
private struct TestMediaClipboard: MediaClipboardCopying {
    func copyScreenshot(at fileURL: URL) -> MediaClipboardCopyResult {
        .copied
    }

    func copyRecordings(at fileURLs: [URL]) -> MediaClipboardCopyResult {
        .copied
    }
}

@MainActor
private final class RecordingMediaClipboard: MediaClipboardCopying {
    private(set) var recordingURLs: [URL] = []

    func copyScreenshot(at fileURL: URL) -> MediaClipboardCopyResult {
        .copied
    }

    func copyRecordings(at fileURLs: [URL]) -> MediaClipboardCopyResult {
        recordingURLs.append(contentsOf: fileURLs)
        return .copied
    }
}

@MainActor
private final class RecordingMediaFinderRevealer: MediaFinderRevealing {
    private(set) var mediaURLs: [URL] = []

    func revealMedia(at fileURL: URL) {
        mediaURLs.append(fileURL)
    }
}

private actor RecordingDeviceStoreProcessRunner: ProcessRunning {
    func run(executablePath: String, arguments: [String]) async -> ProcessResult {
        if arguments == ["devices", "-l"] {
            return successfulResult(
                standardOutput: "List of devices attached\nserial\tdevice model:Pixel_9\n"
            )
        }

        if arguments.contains("exec-out") {
            return successfulResult(standardOutput: Self.validPNG)
        }

        if arguments.contains("pull"), let temporaryPath = arguments.last {
            let temporaryURL = URL(fileURLWithPath: temporaryPath)
            do {
                try FileManager.default.createDirectory(
                    at: temporaryURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data([0x00, 0x01]).write(to: temporaryURL)
            } catch {
                return failedResult(error.localizedDescription)
            }
        }

        return successfulResult()
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

    private func successfulResult(standardOutput: Data) -> ProcessResult {
        ProcessResult(
            standardOutput: standardOutput,
            standardError: Data(),
            exitStatus: 0,
            durationMilliseconds: 1,
            failureDescription: nil,
            wasCancelled: false
        )
    }

    private func failedResult(_ message: String) -> ProcessResult {
        ProcessResult(
            standardOutput: Data(),
            standardError: Data(message.utf8),
            exitStatus: 1,
            durationMilliseconds: 1,
            failureDescription: message,
            wasCancelled: false
        )
    }

    private static let validPNG = Data([
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13,
        73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1,
    ])
}

private struct TestMediaNotifier: SavedMediaNotifying {
    func notifyAboutSavedMedia(at fileURLs: [URL], kind: SavedMediaNotificationKind) async {}
}

private actor RecordingSessionNotifier: SavedMediaNotifying {
    private(set) var fileGroups: [[URL]] = []
    func notifyAboutSavedMedia(at fileURLs: [URL], kind: SavedMediaNotificationKind) async {
        fileGroups.append(fileURLs)
    }
}
