import AppKit
import SwiftUI

@MainActor
final class EmulatorCreationWindowController: NSObject, NSWindowDelegate {
    static let shared = EmulatorCreationWindowController()
    private var window: NSWindow?
    private var store: EmulatorCreationStore?

    func show(preferences: AppPreferences, deviceStore: DeviceStore, emulatorStore: EmulatorStore) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let store = EmulatorCreationStore()
        self.store = store
        let content = EmulatorCreationView(
            dismiss: { [weak self] in self?.close() },
            creationStateChanged: { [weak self] creating in
                self?.window?.standardWindowButton(.closeButton)?.isEnabled = !creating
            },
            store: store
        )
        .environment(preferences)
        .environment(deviceStore)
        .environment(emulatorStore)
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Create Android Emulator"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        self.window = window
        if let parent = MainWindowController.shared.window, let screen = parent.screen {
            window.setFrameOrigin(Self.origin(for: window.frame.size, parentFrame: parent.frame,
                                              visibleFrame: screen.visibleFrame))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    static func origin(for size: NSSize, parentFrame: NSRect, visibleFrame: NSRect) -> NSPoint {
        // Sit just below the main window's title bar; constrain to its display.
        let desired = NSPoint(x: parentFrame.midX - size.width / 2,
                              y: parentFrame.maxY - 32 - size.height)
        return NSPoint(
            x: max(visibleFrame.minX, min(desired.x, visibleFrame.maxX - size.width)),
            y: max(visibleFrame.minY, min(desired.y, visibleFrame.maxY - size.height))
        )
    }

    private func close() {
        guard store?.isCreating != true else { return }
        window?.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        store?.isCreating != true
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        store = nil
    }
}
