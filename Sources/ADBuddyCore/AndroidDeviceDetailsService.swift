import Foundation

public struct AndroidDeviceDetails: Equatable, Sendable {
    public let androidVersion: String
    public let apiLevel: String

    public init(androidVersion: String, apiLevel: String) {
        self.androidVersion = androidVersion
        self.apiLevel = apiLevel
    }

    public var screenshotOverlayText: String {
        "\(androidVersion) / \(apiLevel)"
    }
}

public struct AndroidDeviceDetailsService: Sendable {
    private let adbPath: String
    private let processRunner: any ProcessRunning

    public init(adbPath: String, processRunner: any ProcessRunning) {
        self.adbPath = adbPath
        self.processRunner = processRunner
    }

    public func details(for device: AndroidDevice) async -> AndroidDeviceDetails? {
        guard device.isUsable else {
            return nil
        }

        guard let androidVersion = await deviceProperty(
            "ro.build.version.release",
            for: device
        ), let apiLevel = await deviceProperty(
            "ro.build.version.sdk",
            for: device
        ) else {
            AppLogger.screenshot.error("Could not read Android version details for screenshot overlay")
            return nil
        }

        return AndroidDeviceDetails(androidVersion: androidVersion, apiLevel: apiLevel)
    }

    private func deviceProperty(_ name: String, for device: AndroidDevice) async -> String? {
        let result = await processRunner.run(
            executablePath: adbPath,
            arguments: ["-s", device.serial, "shell", "getprop", name]
        )
        guard result.succeeded else {
            return nil
        }

        let value = String(decoding: result.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
