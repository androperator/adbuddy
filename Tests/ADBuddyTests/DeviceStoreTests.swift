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

    private func makeDeviceStore() -> DeviceStore {
        DeviceStore(
            sdkLocator: sdkLocator,
            processRunner: DeviceListProcessRunner(),
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

@MainActor
private struct TestScreenshotClipboard: ScreenshotClipboardCopying {
    func copyScreenshot(at fileURL: URL) -> ScreenshotClipboardCopyResult {
        .copied
    }
}

private struct TestMediaNotifier: SavedMediaNotifying {
    func notifyAboutSavedMedia(at fileURL: URL, kind: SavedMediaNotificationKind) async {}
}
