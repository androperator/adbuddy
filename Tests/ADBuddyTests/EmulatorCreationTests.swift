import Foundation
import XCTest
@testable import ADBuddy
@testable import ADBuddyCore

final class EmulatorCreationTests: XCTestCase {
    private let profile = EmulatorHardwareProfile(id: "tv_720p", name: "Television", manufacturer: "Google", tag: "android-tv")
    private let image = EmulatorSystemImage(id: "system-images;android-36;android-tv;arm64-v8a", platform: "android-36", apiLevel: 36, tag: "android-tv", abi: "arm64-v8a", description: "TV", installed: true)

    func testValidationPreventsReplacementAndInvalidCapacity() throws {
        let request = EmulatorCreationRequest(name: "TV_Dev", profile: profile, image: image, storageGB: 24)
        try request.validate(existingNames: [])
        XCTAssertThrowsError(try request.validate(existingNames: ["TV_Dev"]))
        for name in ["", "../escape", "--force", "has spaces", String(repeating: "a", count: 81)] {
            XCTAssertThrowsError(try EmulatorCreationRequest(name: name, profile: profile, image: image, storageGB: 24).validate(existingNames: []))
        }
        XCTAssertThrowsError(try EmulatorCreationRequest(name: "TV", profile: profile, image: image, storageGB: 0).validate(existingNames: []))
        XCTAssertEqual(request.arguments, ["create", "TV_Dev", "--profile", "tv_720p", "--image", image.id, "--storage-size", "24G"])
    }

    func testImageTitlesUseStablePackageTagsInsteadOfMalformedDescriptions() {
        let image = EmulatorSystemImage(id: "image", platform: "android-37.2", apiLevel: 37,
            tag: "google_apis_playstore_ps16k", abi: "arm64-v8a", description: "->", installed: true)
        XCTAssertEqual(image.title, "API 37.2 · Google Play · 16 KB pages · Installed")
    }

    func testHardwareTypesSeparateSDKProfiles() {
        let cases: [(String, String?, EmulatorHardwareType)] = [
            ("pixel_7", nil, .phone), ("pixel_tablet", nil, .tablet),
            ("Nexus 7 2013", nil, .tablet), ("pixel_c", nil, .tablet),
            ("pixel_9_pro_fold", nil, .foldable), ("tv_720p", "android-tv", .tv),
            ("automotive_1024p_landscape", "android-automotive-playstore", .automotive),
            ("wearos_large_round", "android-wear", .wearOS),
            ("desktop_medium", "android-desktop", .desktop),
            ("xr_headset_device", "android-xr", .xr), ("ai_glasses_device", "ai-glasses", .glasses),
            ("future_device", "future-tag", .other), ("resizable", nil, .other)
        ]
        for (id, tag, expected) in cases {
            XCTAssertEqual(EmulatorHardwareProfile(id: id, name: id, manufacturer: nil, tag: tag).hardwareType, expected, id)
        }
    }

    func testTabletImagesAreExcludedFromPhoneAndAutomotiveImagesStaySeparate() {
        let tabletImage = EmulatorSystemImage(id: "tablet", platform: "android-35", apiLevel: 35, tag: "google_apis", abi: "arm64-v8a", description: "Google APIs Tablet", installed: false)
        let carImage = EmulatorSystemImage(id: "car", platform: "android-35", apiLevel: 35, tag: "android-automotive", abi: "arm64-v8a", description: "Automotive", installed: false)
        let images = [tabletImage, carImage, image]
        let phone = EmulatorHardwareProfile(id: "pixel_7", name: "Pixel 7", manufacturer: nil, tag: nil)
        let tablet = EmulatorHardwareProfile(id: "pixel_tablet", name: "Pixel Tablet", manufacturer: nil, tag: nil)
        let car = EmulatorHardwareProfile(id: "automotive_1080p", name: "Automotive", manufacturer: nil, tag: "android-automotive")
        XCTAssertTrue(EmulatorImageSelection.images(images, for: phone, abi: "arm64-v8a").isEmpty)
        XCTAssertEqual(EmulatorImageSelection.images(images, for: tablet, abi: "arm64-v8a").map(\.id), ["tablet"])
        XCTAssertEqual(EmulatorImageSelection.images(images, for: car, abi: "arm64-v8a").map(\.id), ["car"])
    }

    func testFiltersArchitectureAndDeviceFamily() {
        let phone = EmulatorSystemImage(id: "phone", platform: "android-35", apiLevel: 35, tag: "google_apis_playstore", abi: "arm64-v8a", description: "Phone", installed: true)
        let intel = EmulatorSystemImage(id: "intel", platform: "android-36", apiLevel: 36, tag: "android-tv", abi: "x86_64", description: "TV", installed: true)
        XCTAssertEqual(EmulatorImageSelection.images([phone, intel, image], for: profile, abi: "arm64-v8a").map(\.id), [image.id])
        let pixel = EmulatorHardwareProfile(id: "pixel_7", name: "Pixel", manufacturer: nil, tag: nil)
        XCTAssertEqual(EmulatorImageSelection.images([phone, image], for: pixel, abi: "arm64-v8a").map(\.id), ["phone"])
    }

    func testEnvelopeRequiresProtocolAndProcessSuccess() throws {
        let good = result(#"{"protocolVersion":1,"ok":true,"data":{"name":"@androperator/emulator","version":"0.1.1","capabilities":[]}}"#)
        let value: EmulatorHelperVersion = try EmulatorCreationService.decode(good)
        XCTAssertEqual(value.version, "0.1.1")
        for raw in [#"{"protocolVersion":2,"ok":true,"data":{}}"#, "noise", #"{"protocolVersion":1,"ok":false,"error":{"message":"Choose another name"}}"#] {
            XCTAssertThrowsError(try EmulatorCreationService.decode(result(raw)) as EmulatorHelperVersion)
        }
        XCTAssertThrowsError(try EmulatorCreationService.decode(result(String(decoding: good.standardOutput, as: UTF8.self), status: 1)) as EmulatorHelperVersion)
    }

    func testDeletionUsesExactNameAndRequiresConfirmedResult() async throws {
        let recorder = CreationInvocationRecorder()
        let service = EmulatorCreationService(invocation: .init(node: "/node", script: "/cli.js", environment: [:])) { executable, arguments, environment in
            await recorder.record(executable, arguments, environment)
            let output = #"{"protocolVersion":1,"ok":true,"data":{"avdName":"TV_Test","deleted":true}}"#
            return ProcessResult(standardOutput: Data(output.utf8), standardError: Data(), exitStatus: 0, durationMilliseconds: 0, failureDescription: nil, wasCancelled: false)
        }
        try await service.delete(name: "TV_Test")
        let calls = await recorder.arguments
        XCTAssertEqual(calls, [["/cli.js", "delete", "TV_Test"]])
        do {
            try await service.delete(name: "Different_AVD")
            XCTFail("Deletion must confirm the selected name")
        } catch { XCTAssertTrue(error.localizedDescription.contains("did not confirm deletion")) }
    }

    func testChecksCapabilitiesAndVerifiesCreatedIdentity() async throws {
        let recorder = CreationInvocationRecorder()
        let invocation = EmulatorHelperInvocation(node: "/node", script: "/cli.js", environment: ["ANDROID_HOME": "/SDK"])
        let service = EmulatorCreationService(invocation: invocation) { executable, arguments, environment in
            await recorder.record(executable, arguments, environment)
            let output: String
            if arguments == ["--version"] { output = "v24.0.0" }
            else if arguments.last == "--version" { output = #"{"protocolVersion":1,"ok":true,"data":{"name":"@androperator/emulator","version":"0.1.1","capabilities":["catalog.profiles","catalog.images"]}}"# }
            else { output = #"{"protocolVersion":1,"ok":true,"data":{"name":"TV_Dev","exists":true}}"# }
            return ProcessResult(standardOutput: Data(output.utf8), standardError: Data(), exitStatus: 0, durationMilliseconds: 0, failureDescription: nil, wasCancelled: false)
        }
        _ = try await service.check()
        try await service.create(EmulatorCreationRequest(name: "TV_Dev", profile: profile, image: image, storageGB: 24))
        let calls = await recorder.arguments
        XCTAssertEqual(calls.last?.prefix(3), ["/cli.js", "create", "TV_Dev"])
        XCTAssertFalse(calls.flatMap { $0 }.contains("--replace"))
        XCTAssertFalse(calls.flatMap { $0 }.contains("--accept-licenses"))
        do {
            try await service.create(EmulatorCreationRequest(name: "Other", profile: profile, image: image, storageGB: 24))
            XCTFail("Expected mismatched creation result to fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("did not confirm")) }
    }

    func testResolvesDevelopmentSiblingAndExplicitOverridesWithoutTerminalPATH() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("adbuddy")
        let helper = root.appendingPathComponent("emulator")
        let node = root.appendingPathComponent("node")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helper.appendingPathComponent("dist"), withIntermediateDirectories: true)
        try Data().write(to: repo.appendingPathComponent("Package.swift"))
        try Data().write(to: helper.appendingPathComponent("dist/cli.js"))
        try Data().write(to: node)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        let sdk = AndroidSDK(rootPath: "/chosen-sdk", adbPath: "/chosen-sdk/platform-tools/adb", source: .standardLocation)
        let resolved = try EmulatorHelperInvocation.resolve(configuration: .init(helperPath: "", nodePath: node.path, javaHome: "/chosen-java"), sdk: sdk, environment: [:], bundleURL: repo.appendingPathComponent("dist/ADBuddy.app"), home: root)
        XCTAssertEqual(resolved.script, helper.appendingPathComponent("dist/cli.js").resolvingSymlinksInPath().path)
        XCTAssertEqual(resolved.environment["JAVA_HOME"], "/chosen-java")
        XCTAssertEqual(resolved.environment["SDKMANAGER_PATH"], "/chosen-sdk/cmdline-tools/latest/bin/sdkmanager")
        XCTAssertEqual(resolved.environment["ANDROID_HOME"], "/chosen-sdk")
        let avdEnvironments: [([String: String], String?)] = [
            ([:], nil),
            (["ANDROID_USER_HOME": "/custom-android"], "/custom-android/avd"),
            (["ANDROID_USER_HOME": "/custom-android", "ANDROID_AVD_HOME": ""], "/custom-android/avd"),
            (["ANDROID_USER_HOME": "/custom-android", "ANDROID_AVD_HOME": "/explicit-avds"], "/explicit-avds")
        ]
        for (environment, expectedRoot) in avdEnvironments {
            let invocation = try EmulatorHelperInvocation.resolve(
                configuration: .init(helperPath: helper.path, nodePath: node.path, javaHome: ""),
                sdk: sdk, environment: environment, home: root
            )
            XCTAssertEqual(invocation.environment["ANDROID_AVD_HOME"], expectedRoot)
        }
        XCTAssertThrowsError(try EmulatorHelperInvocation.resolve(configuration: .init(helperPath: "/missing-helper", nodePath: node.path, javaHome: ""), sdk: sdk, environment: [:], bundleURL: repo.appendingPathComponent("dist/ADBuddy.app"), home: root))
    }

    @MainActor
    func testAutomaticCatalogFailurePreservesInstalledImagesAndCanRetry() async throws {
        let responses = CatalogResponses()
        let service = EmulatorCreationService(invocation: .init(node: "/node", script: "/cli.js", environment: [:])) { _, arguments, _ in
            await responses.respond(arguments)
        }
        let store = EmulatorCreationStore(makeService: { _, _ in service })
        await store.load(configuration: .init(helperPath: "", nodePath: "", javaHome: ""),
                         sdk: AndroidSDK(rootPath: "/sdk", adbPath: "/sdk/adb", source: .standardLocation))
        XCTAssertEqual(store.images.map(\.id), ["installed"])
        XCTAssertEqual(store.imageID, "installed")
        XCTAssertNotNil(store.catalogError)
        XCTAssertNil(store.validationMessage(existingNames: []))
        XCTAssertFalse(store.isBusy)
        await store.loadDownloadableImages()
        XCTAssertNil(store.catalogError)
        XCTAssertEqual(store.images.map(\.id), ["installed", "download"])
        XCTAssertEqual(store.imageID, "installed")
        let attempts = await responses.catalogAttempts
        XCTAssertEqual(attempts, 2)
    }

    private func result(_ text: String, status: Int32 = 0) -> ProcessResult {
        ProcessResult(standardOutput: Data(text.utf8), standardError: Data(), exitStatus: status, durationMilliseconds: 0, failureDescription: nil, wasCancelled: false)
    }
}

private actor CreationInvocationRecorder {
    var arguments: [[String]] = []
    func record(_ executable: String, _ arguments: [String], _ environment: [String: String]) {
        self.arguments.append(arguments)
    }
}

private actor CatalogResponses {
    var catalogAttempts = 0
    func respond(_ arguments: [String]) -> ProcessResult {
        let output: String
        if arguments == ["--version"] { output = "v24.0.0" }
        else if arguments.last == "--version" {
            output = #"{"protocolVersion":1,"ok":true,"data":{"name":"@androperator/emulator","version":"0.1.1","capabilities":["catalog.profiles","catalog.images"]}}"#
        } else if arguments.last == "profiles" {
            output = #"{"protocolVersion":1,"ok":true,"data":{"profiles":[{"id":"pixel_7","name":"Pixel 7"}]}}"#
        } else {
            let installed = arguments.last == "--installed"
            if !installed { catalogAttempts += 1 }
            if !installed && catalogAttempts == 1 {
                return ProcessResult(standardOutput: Data(), standardError: Data(), exitStatus: 1, durationMilliseconds: 0, failureDescription: "Offline", wasCancelled: false)
            }
            let id = installed ? "installed" : "download"
            output = """
            {"protocolVersion":1,"ok":true,"data":{"images":[{"id":"\(id)","platform":"android-35","apiLevel":35,"tag":"google_apis","abi":"\(EmulatorImageSelection.hostABI)","description":"Phone","installed":\(installed)}]}}
            """
        }
        return ProcessResult(standardOutput: Data(output.utf8), standardError: Data(), exitStatus: 0, durationMilliseconds: 0, failureDescription: nil, wasCancelled: false)
    }
}
