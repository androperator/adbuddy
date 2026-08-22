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
        context.coordinator.configureWindow(for: nsView)

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
        private var hasScheduledWindowConfiguration = false
        private var hasScheduledApplication = false

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

                window.tabbingMode = .disallowed
                window.contentMinSize = CGSize(width: DeviceListLayout.windowWidth, height: 0)

                if let contentView = window.contentView {
                    let correctedContentSize = DeviceListLayout.contentSizeRespectingMinimumWidth(
                        contentView.bounds.size
                    )
                    if correctedContentSize != contentView.bounds.size {
                        window.setContentSize(correctedContentSize)
                    }
                }

                window.minSize.width = DeviceListLayout.minimumWindowFrameWidth(
                    for: window.frame.width
                )
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
