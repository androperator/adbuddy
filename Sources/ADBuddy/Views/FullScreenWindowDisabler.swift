import AppKit
import SwiftUI

struct FullScreenWindowDisabler: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.configureWindow(for: nsView)
    }

    @MainActor
    final class Coordinator {
        private var hasScheduledWindowConfiguration = false

        func configureWindow(for view: NSView) {
            guard !hasScheduledWindowConfiguration else {
                return
            }
            hasScheduledWindowConfiguration = true

            DispatchQueue.main.async { [weak view] in
                guard let window = view?.window else {
                    self.hasScheduledWindowConfiguration = false
                    return
                }

                window.collectionBehavior.insert(.fullScreenNone)
                window.standardWindowButton(.zoomButton)?.isHidden = true
            }
        }
    }
}
