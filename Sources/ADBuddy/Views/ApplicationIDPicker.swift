@preconcurrency import AppKit
import SwiftUI

struct ApplicationIDPicker: NSViewRepresentable {
    let applicationID: String?
    let suggestions: [String]
    let onCommit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCommit: onCommit)
    }

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.isEditable = true
        comboBox.completes = true
        comboBox.controlSize = .small
        comboBox.delegate = context.coordinator
        comboBox.setAccessibilityLabel("Application ID")
        comboBox.toolTip = "Application ID"
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        context.coordinator.onCommit = onCommit

        let items = ["All Applications"] + suggestions
        if context.coordinator.items != items {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: items)
            context.coordinator.items = items
        }

        let displayedApplicationID = applicationID ?? "All Applications"
        if !context.coordinator.isEditing, comboBox.stringValue != displayedApplicationID {
            comboBox.stringValue = displayedApplicationID
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSComboBoxDelegate, NSControlTextEditingDelegate {
        var onCommit: (String) -> Void
        var items: [String] = []
        var isEditing = false

        init(onCommit: @escaping (String) -> Void) {
            self.onCommit = onCommit
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isEditing = false
            commit(from: notification)
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            commit(from: notification)
        }

        private func commit(from notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else {
                return
            }
            onCommit(comboBox.stringValue == "All Applications" ? "" : comboBox.stringValue)
        }
    }
}
