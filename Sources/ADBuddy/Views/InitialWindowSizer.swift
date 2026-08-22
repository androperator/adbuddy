import AppKit
import SwiftUI

struct InitialWindowSizer: NSViewRepresentable {
    let targetContentSize: CGSize?
    @Binding var hasAppliedCompactLayout: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.disableTabbing(for: nsView)

        guard !hasAppliedCompactLayout, let targetContentSize else {
            return
        }

        context.coordinator.apply(
            targetContentSize,
            to: nsView,
            hasAppliedCompactLayout: $hasAppliedCompactLayout
        )
    }

    @MainActor
    final class Coordinator {
        private var hasScheduledTabbingUpdate = false
        private var hasScheduledApplication = false

        func disableTabbing(for view: NSView) {
            guard !hasScheduledTabbingUpdate else {
                return
            }
            hasScheduledTabbingUpdate = true

            DispatchQueue.main.async { [weak view] in
                guard let window = view?.window else {
                    self.hasScheduledTabbingUpdate = false
                    return
                }

                window.tabbingMode = .disallowed
            }
        }

        func apply(
            _ targetContentSize: CGSize,
            to view: NSView,
            hasAppliedCompactLayout: Binding<Bool>
        ) {
            guard !hasScheduledApplication else {
                return
            }
            hasScheduledApplication = true

            DispatchQueue.main.async { [weak view] in
                guard let window = view?.window else {
                    self.hasScheduledApplication = false
                    return
                }

                window.setContentSize(targetContentSize)
                hasAppliedCompactLayout.wrappedValue = true
            }
        }
    }
}
