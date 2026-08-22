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
        comboBox.completes = false
        comboBox.controlSize = .small
        comboBox.delegate = context.coordinator
        comboBox.target = context.coordinator
        comboBox.action = #selector(Coordinator.commitSelection(_:))
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

        @objc func commitSelection(_ sender: Any?) {
            guard let comboBox = sender as? NSComboBox else {
                return
            }
            commit(applicationID: comboBox.stringValue)
        }

        private func commit(from notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else {
                return
            }
            commit(applicationID: comboBox.stringValue)
        }

        private func commit(applicationID: String) {
            onCommit(applicationID == "All Applications" ? "" : applicationID)
        }
    }
}
