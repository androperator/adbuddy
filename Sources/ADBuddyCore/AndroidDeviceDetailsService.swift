import Foundation

public struct AndroidDeviceDetails: Equatable, Sendable {
    public let androidVersion: String
    public let apiLevel: String
    public let screen: AndroidDeviceScreen?
    public let languageIdentifier: String?
    public let displays: [AndroidDeviceDisplay]

    public init(
        androidVersion: String,
        apiLevel: String,
        screen: AndroidDeviceScreen? = nil,
        languageIdentifier: String? = nil,
        displays: [AndroidDeviceDisplay] = []
    ) {
        self.androidVersion = androidVersion
        self.apiLevel = apiLevel
        self.screen = screen
        self.languageIdentifier = languageIdentifier
        self.displays = displays
    }

    public var displayText: String {
        "Android \(androidVersion) / API \(apiLevel)"
    }

    public var screenshotOverlayText: String {
        displayText
    }

    public var languageDisplayText: String? {
        guard let languageIdentifier else {
            return nil
        }

        let languageName = Locale.current.localizedString(forIdentifier: languageIdentifier)
        return languageName.map { "\($0) (\(languageIdentifier))" } ?? languageIdentifier
    }
}

public struct AndroidDeviceScreen: Equatable, Sendable {
    public let physicalPixelSize: AndroidDisplaySize
    public let dpSize: AndroidDisplaySize
    public let usesDisplayOverride: Bool

    public init?(
        physicalPixelSize: AndroidDisplaySize,
        logicalPixelSize: AndroidDisplaySize? = nil,
        logicalDensityDPI: Int,
        usesDisplayOverride: Bool = false
    ) {
        guard logicalDensityDPI > 0 else {
            return nil
        }

        let logicalPixelSize = logicalPixelSize ?? physicalPixelSize
        guard let dpSize = AndroidDisplaySize(
            width: Int((Double(logicalPixelSize.width) * 160 / Double(logicalDensityDPI)).rounded()),
            height: Int((Double(logicalPixelSize.height) * 160 / Double(logicalDensityDPI)).rounded())
        ) else {
            return nil
        }

        self.physicalPixelSize = physicalPixelSize
        self.dpSize = dpSize
        self.usesDisplayOverride = usesDisplayOverride
    }

    public var displayText: String {
        let overrideDetail = usesDisplayOverride ? " (display override)" : ""
        return "\(physicalPixelSize.width) × \(physicalPixelSize.height) px · \(dpSize.width) × \(dpSize.height) dp\(overrideDetail)"
    }
}

public struct AndroidDeviceDetailsService: Sendable {
    private let adbPath: String
    private let processRunner: any ProcessRunning

    public init(adbPath: String, processRunner: any ProcessRunning) {
        self.adbPath = adbPath
        self.processRunner = processRunner
    }

    public func details(
        for device: AndroidDevice,
        includesExtendedDetails: Bool = false
    ) async -> AndroidDeviceDetails? {
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
            AppLogger.devices.error("Could not read Android version details")
            return nil
        }

        return AndroidDeviceDetails(
            androidVersion: androidVersion,
            apiLevel: apiLevel,
            screen: includesExtendedDetails ? await screen(for: device) : nil,
            languageIdentifier: includesExtendedDetails
                ? await languageIdentifier(for: device)
                : nil,
            displays: includesExtendedDetails ? await displays(for: device) : []
        )
    }

    private func displays(for device: AndroidDevice) async -> [AndroidDeviceDisplay] {
        let result = await processRunner.run(
            executablePath: adbPath,
            arguments: ["-s", device.serial, "shell", "dumpsys", "display"]
        )
        guard result.succeeded else { return [] }
        return AndroidDeviceDisplayParser.parse(String(decoding: result.standardOutput, as: UTF8.self))
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

    private func languageIdentifier(for device: AndroidDevice) async -> String? {
        if let currentLanguage = await deviceProperty("persist.sys.locale", for: device) {
            return currentLanguage
        }

        return await deviceProperty("ro.product.locale", for: device)
    }

    private func screen(for device: AndroidDevice) async -> AndroidDeviceScreen? {
        let sizeResult = await processRunner.run(
            executablePath: adbPath,
            arguments: ["-s", device.serial, "shell", "wm", "size"]
        )
        guard sizeResult.succeeded else {
            return nil
        }

        let sizeOutput = String(decoding: sizeResult.standardOutput, as: UTF8.self)
        guard let physicalPixelSize = AndroidDisplaySizeParser.parse(sizeOutput) else {
            return nil
        }

        let densityResult = await processRunner.run(
            executablePath: adbPath,
            arguments: ["-s", device.serial, "shell", "wm", "density"]
        )
        guard densityResult.succeeded else {
            return nil
        }

        let densityOutput = String(decoding: densityResult.standardOutput, as: UTF8.self)
        guard let physicalDensityDPI = density(in: densityOutput, prefix: "Physical density:") else {
            return nil
        }

        let overrideSize = AndroidDisplaySizeParser.parseOverride(sizeOutput)
        let overrideDensityDPI = density(in: densityOutput, prefix: "Override density:")
        return AndroidDeviceScreen(
            physicalPixelSize: physicalPixelSize,
            logicalPixelSize: overrideSize,
            logicalDensityDPI: overrideDensityDPI ?? physicalDensityDPI,
            usesDisplayOverride: overrideSize != nil || overrideDensityDPI != nil
        )
    }

    private func density(in output: String, prefix: String) -> Int? {
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedLine.hasPrefix(prefix) else {
                continue
            }

            let value = trimmedLine.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespaces)
            return Int(value)
        }

        return nil
    }
}
