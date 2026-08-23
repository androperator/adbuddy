import AppKit
import Foundation

@MainActor
protocol DeviceIdentifierPasteboardWriting {
    func writeString(_ string: String) -> Bool
}

@MainActor
struct SystemDeviceIdentifierPasteboard: DeviceIdentifierPasteboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func writeString(_ string: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    }
}

@MainActor
struct DeviceIdentifierClipboardService {
    private let pasteboard: any DeviceIdentifierPasteboardWriting

    init(pasteboard: any DeviceIdentifierPasteboardWriting = SystemDeviceIdentifierPasteboard()) {
        self.pasteboard = pasteboard
    }

    func copyDeviceIdentifier(_ identifier: String) {
        guard pasteboard.writeString(identifier) else {
            AppLogger.devices.error("Could not copy Android device identifier to the clipboard")
            return
        }

        AppLogger.devices.debug("Copied Android device identifier to the clipboard")
    }
}

struct AndroidVirtualDeviceDirectoryResolver {
    private let environment: [String: String]
    private let homeDirectory: URL
    private let fileManager: FileManager

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    func directoryURL(for virtualDeviceName: String) -> URL? {
        guard isValidVirtualDeviceName(virtualDeviceName) else {
            return nil
        }

        let directoryName = "\(virtualDeviceName).avd"
        for avdRootURL in avdRootURLs {
            let virtualDeviceURL = avdRootURL.appendingPathComponent(directoryName, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: virtualDeviceURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            return virtualDeviceURL
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
}

@MainActor
struct AndroidVirtualDeviceFinderRevealService {
    private let directoryResolver: AndroidVirtualDeviceDirectoryResolver

    init(directoryResolver: AndroidVirtualDeviceDirectoryResolver = AndroidVirtualDeviceDirectoryResolver()) {
        self.directoryResolver = directoryResolver
    }

    func revealVirtualDevice(named virtualDeviceName: String) {
        guard let directoryURL = directoryResolver.directoryURL(for: virtualDeviceName) else {
            AppLogger.emulator.error("Could not locate Android Virtual Device directory")
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([directoryURL])
        AppLogger.emulator.info("Revealed Android Virtual Device in Finder")
    }
}
