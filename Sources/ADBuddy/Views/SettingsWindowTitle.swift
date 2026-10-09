import AppKit
import SwiftUI

struct SettingsWindowTitle: NSViewRepresentable {
    let title: String

    func makeCoordinator() -> Coordinator {
        Coordinator(title: title)
    }

    func makeNSView(context: Context) -> SettingsWindowObserverView {
        let view = SettingsWindowObserverView()
        view.windowDidChange = context.coordinator.updateWindow
        return view
    }

    func updateNSView(_ nsView: SettingsWindowObserverView, context: Context) {
        context.coordinator.title = title
        context.coordinator.applyTitle()
    }

    @MainActor
    final class Coordinator: NSObject {
        var title: String

        private weak var window: NSWindow?

        init(title: String) {
            self.title = title
        }

        func updateWindow(_ window: NSWindow?) {
            guard let window else {
                return
            }

            guard self.window !== window else {
                applyTitle()
                return
            }

            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didUpdateNotification,
                object: nil
            )
            self.window = window
            window.initialFirstResponder = nil
            // Let Tab navigation establish focus instead of highlighting a toolbar tab on open.
            DispatchQueue.main.async { [weak window] in
                window?.makeFirstResponder(nil)
            }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWindowUpdate),
                name: NSWindow.didUpdateNotification,
                object: window
            )
            applyTitle()
        }

        func applyTitle() {
            guard let window, window.title != title else {
                return
            }
            window.title = title
        }

        @objc private func handleWindowUpdate() {
            applyTitle()
        }
    }
}

final class SettingsWindowObserverView: NSView {
    var windowDidChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowDidChange?(window)
    }
}
