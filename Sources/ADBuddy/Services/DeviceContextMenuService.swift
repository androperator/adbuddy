import AppKit
import ADBuddyCore
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
