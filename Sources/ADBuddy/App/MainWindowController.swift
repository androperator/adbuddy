import AppKit

@MainActor
final class MainWindowController {
    static let shared = MainWindowController()

    private weak var window: NSWindow?
    private var isOpeningWindow = false

    private init() {}

    func register(_ window: NSWindow) {
        self.window = window
        isOpeningWindow = false
    }

    func unregister(_ window: NSWindow) {
        guard self.window === window else {
            return
        }

        self.window = nil
        isOpeningWindow = false
    }

    /// Returns true when SwiftUI needs to create the main window.
    func prepareToPresent() -> Bool {
        if let window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return false
        }

        guard !isOpeningWindow else {
            return false
        }

        isOpeningWindow = true
        return true
    }
}
