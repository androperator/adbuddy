import AppKit
import SwiftUI

// Floating AppKit group rows add a full-width separator to the first section.
// Keep both section headings in the list so they use the same inset separator.
struct NonFloatingListHeaders: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            guard let contentView = view?.window?.contentView else { return }
            disableFloatingHeaders(in: contentView)
        }
    }

    private func disableFloatingHeaders(in view: NSView) {
        if let tableView = view as? NSTableView {
            tableView.floatsGroupRows = false
        }
        for subview in view.subviews {
            disableFloatingHeaders(in: subview)
        }
    }
}
