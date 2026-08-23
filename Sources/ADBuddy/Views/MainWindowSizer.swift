import AppKit
import SwiftUI

struct MainWindowSizer: NSViewRepresentable {
    let targetContentSize: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.configureWindow(for: nsView)
        context.coordinator.resizeWindow(to: targetContentSize, for: nsView)
    }

    @MainActor
    final class Coordinator {
        private var hasScheduledWindowConfiguration = false
        private var hasScheduledResize = false
        private var pendingContentSize: CGSize?
        private var appliedContentHeight: CGFloat?

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
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.collectionBehavior.insert(.fullScreenNone)
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

        func resizeWindow(to targetContentSize: CGSize, for view: NSView) {
            guard appliedContentHeight != targetContentSize.height else {
                return
            }

            pendingContentSize = targetContentSize
            guard !hasScheduledResize else {
                return
            }
            hasScheduledResize = true

            DispatchQueue.main.async { [weak view] in
                defer {
                    self.hasScheduledResize = false
                }
                guard let window = view?.window,
                      let pendingContentSize = self.pendingContentSize else {
                    return
                }

                let currentContentSize = window.contentView?.bounds.size ?? pendingContentSize
                let contentSize = DeviceListLayout.contentSizeRetainingCurrentWidth(
                    currentContentSize,
                    updatingHeight: pendingContentSize.height
                )
                let frameSize = window.frameRect(
                    forContentRect: NSRect(origin: .zero, size: contentSize)
                ).size
                let minimumFrameWidth = DeviceListLayout.minimumWindowFrameWidth(
                    for: window.minSize.width
                )

                // Keep the window vertically fitted to the visible rows while preserving width.
                window.contentMinSize = CGSize(
                    width: DeviceListLayout.windowWidth,
                    height: 0
                )
                window.minSize = CGSize(width: minimumFrameWidth, height: 0)
                window.setContentSize(contentSize)
                window.contentMaxSize = CGSize(
                    width: .greatestFiniteMagnitude,
                    height: contentSize.height
                )
                window.maxSize = CGSize(
                    width: .greatestFiniteMagnitude,
                    height: frameSize.height
                )
                window.contentMinSize = CGSize(
                    width: DeviceListLayout.windowWidth,
                    height: contentSize.height
                )
                window.minSize = CGSize(width: minimumFrameWidth, height: frameSize.height)
                self.appliedContentHeight = contentSize.height
            }
        }
    }
}
