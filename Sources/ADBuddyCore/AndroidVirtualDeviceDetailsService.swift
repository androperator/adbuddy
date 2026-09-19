import Foundation

public struct AndroidVirtualDeviceDirectoryResolver {
    private let environment: [String: String]
    private let homeDirectory: URL
    private let fileManager: FileManager

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    public func directoryURL(for virtualDeviceName: String) -> URL? {
        guard isValidVirtualDeviceName(virtualDeviceName) else {
            return nil
        }

        for avdRootURL in avdRootURLs {
            if let configuredDirectoryURL = configuredDirectoryURL(
                for: virtualDeviceName,
                in: avdRootURL
            ) {
                return configuredDirectoryURL
            }

            let directoryName = "\(virtualDeviceName).avd"
            let virtualDeviceURL = avdRootURL.appendingPathComponent(directoryName, isDirectory: true)
            if isDirectory(at: virtualDeviceURL) {
                return virtualDeviceURL
            }
        }

        return nil
    }

    private var avdRootURLs: [URL] {
        var configuredRoots: [URL] = []
        if let avdHomePath = environment["ANDROID_AVD_HOME"], !avdHomePath.isEmpty {
            configuredRoots.append(URL(fileURLWithPath: avdHomePath, isDirectory: true))
        }
        if let userHomePath = environment["ANDROID_USER_HOME"], !userHomePath.isEmpty {
            configuredRoots.append(
                URL(fileURLWithPath: userHomePath, isDirectory: true)
                    .appendingPathComponent("avd", isDirectory: true)
            )
        }
        configuredRoots.append(
            homeDirectory
                .appendingPathComponent(".android", isDirectory: true)
                .appendingPathComponent("avd", isDirectory: true)
        )

        var uniqueRootPaths = Set<String>()
        return configuredRoots.filter { rootURL in
            uniqueRootPaths.insert(rootURL.path).inserted
        }
    }

    private func isValidVirtualDeviceName(_ virtualDeviceName: String) -> Bool {
        !virtualDeviceName.isEmpty &&
            !virtualDeviceName.contains("/") &&
            !virtualDeviceName.contains("\\")
    }

    private func configuredDirectoryURL(
        for virtualDeviceName: String,
        in avdRootURL: URL
    ) -> URL? {
        let metadataURL = avdRootURL.appendingPathComponent("\(virtualDeviceName).ini")
        guard let metadata = try? String(contentsOf: metadataURL, encoding: .utf8) else {
            return nil
        }

        if let configuredPath = configurationValue(named: "path", in: metadata),
           let configuredDirectoryURL = directoryURL(for: configuredPath, relativeTo: avdRootURL),
           isDirectory(at: configuredDirectoryURL) {
            return configuredDirectoryURL
        }

        if let relativePath = configurationValue(named: "path.rel", in: metadata),
           let configuredDirectoryURL = directoryURL(
               for: relativePath,
               relativeTo: avdRootURL.deletingLastPathComponent()
           ), isDirectory(at: configuredDirectoryURL) {
            return configuredDirectoryURL
        }

        return nil
    }

    private func directoryURL(for path: String, relativeTo directoryURL: URL) -> URL? {
        guard !path.isEmpty else {
            return nil
        }

        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        return directoryURL.appendingPathComponent(path, isDirectory: true)
    }

    private func configurationValue(named name: String, in contents: String) -> String? {
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = line.firstIndex(of: "="),
                  line[..<separator].trimmingCharacters(in: .whitespaces) == name else {
                continue
            }

            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        return nil
    }

    private func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

public struct AndroidVirtualDeviceDetailsService {
    private let sdkRootURL: URL
    private let directoryResolver: AndroidVirtualDeviceDirectoryResolver

    public init(
        sdkRootPath: String,
        directoryResolver: AndroidVirtualDeviceDirectoryResolver = AndroidVirtualDeviceDirectoryResolver()
    ) {
        sdkRootURL = URL(fileURLWithPath: sdkRootPath, isDirectory: true)
        self.directoryResolver = directoryResolver
    }

    public func details(for virtualDevice: AndroidVirtualDevice) -> AndroidDeviceDetails? {
        guard let virtualDeviceDirectory = directoryResolver.directoryURL(for: virtualDevice.name),
              let systemImagePath = configurationValue(
                  named: "image.sysdir.1",
                  in: virtualDeviceDirectory.appendingPathComponent("config.ini")
              ),
              let apiLevel = systemImageAPILevel(at: systemImagePath),
              let androidVersion = AndroidPlatformVersion.version(forAPILevel: apiLevel) else {
            return nil
        }

        let configurationURL = virtualDeviceDirectory.appendingPathComponent("config.ini")
        return AndroidDeviceDetails(
            androidVersion: androidVersion,
            apiLevel: String(apiLevel),
            screen: screen(in: configurationURL)
        )
    }

    private func systemImageAPILevel(at systemImagePath: String) -> Int? {
        let systemImageURL: URL
        if systemImagePath.hasPrefix("/") {
            systemImageURL = URL(fileURLWithPath: systemImagePath, isDirectory: true)
        } else {
            systemImageURL = sdkRootURL.appendingPathComponent(systemImagePath, isDirectory: true)
        }

        guard let apiLevelText = configurationValue(
            named: "AndroidVersion.ApiLevel",
            in: systemImageURL.appendingPathComponent("source.properties")
        ) else {
            return nil
        }

        return Int(apiLevelText)
    }

    private func configurationValue(named name: String, in fileURL: URL) -> String? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = line.firstIndex(of: "="),
                  line[..<separator].trimmingCharacters(in: .whitespaces) == name else {
                continue
            }

            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        return nil
    }

    private func screen(in configurationURL: URL) -> AndroidDeviceScreen? {
        guard let widthText = configurationValue(named: "hw.lcd.width", in: configurationURL),
              let width = Int(widthText),
              let heightText = configurationValue(named: "hw.lcd.height", in: configurationURL),
              let height = Int(heightText),
              let densityText = configurationValue(named: "hw.lcd.density", in: configurationURL),
              let densityDPI = Int(densityText),
              let pixelSize = AndroidDisplaySize(width: width, height: height) else {
            return nil
        }

        return AndroidDeviceScreen(
            physicalPixelSize: pixelSize,
            logicalDensityDPI: densityDPI
        )
    }
}

private enum AndroidPlatformVersion {
    private static let versionsByAPILevel: [Int: String] = [
        1: "1.0", 2: "1.1", 3: "1.5", 4: "1.6", 5: "2.0", 6: "2.0.1",
        7: "2.1", 8: "2.2", 9: "2.3", 10: "2.3.3", 11: "3.0", 12: "3.1",
        13: "3.2", 14: "4.0", 15: "4.0.3", 16: "4.1", 17: "4.2", 18: "4.3",
        19: "4.4", 20: "4.4W", 21: "5.0", 22: "5.1", 23: "6.0", 24: "7.0",
        25: "7.1", 26: "8.0", 27: "8.1", 28: "9", 29: "10", 30: "11",
        31: "12", 32: "12", 33: "13", 34: "14", 35: "15", 36: "16", 37: "17",
    ]

    static func version(forAPILevel apiLevel: Int) -> String? {
        versionsByAPILevel[apiLevel]
    }
}
