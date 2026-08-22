@preconcurrency import AppKit
import SwiftUI

struct LogcatTableView: NSViewRepresentable {
    let entries: [LogcatEntry]
    let followsLatest: Bool
    let onUserScrollAwayFromLatest: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onUserScrollAwayFromLatest: onUserScrollAwayFromLatest)
    }

    func makeNSView(context: Context) -> LogcatTableContainer {
        let tableView = CopyableLogcatTableView()
        tableView.addTableColumn(column(identifier: "time", title: "Time", width: 88))
        tableView.addTableColumn(column(identifier: "level", title: "Level", width: 42))
        tableView.addTableColumn(column(identifier: "tag", title: "Tag", width: 160))
        tableView.addTableColumn(column(identifier: "message", title: "Message", width: 480))
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.rowHeight = 18
        tableView.intercellSpacing = .zero
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.setAccessibilityLabel("Logcat entries")

        let scrollView = LogcatScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        context.coordinator.attach(tableView: tableView, scrollView: scrollView)
        return LogcatTableContainer(scrollView: scrollView)
    }

    func updateNSView(_ container: LogcatTableContainer, context: Context) {
        context.coordinator.onUserScrollAwayFromLatest = onUserScrollAwayFromLatest
        context.coordinator.update(
            entries: entries,
            followsLatest: followsLatest
        )
    }

    private func column(identifier: String, title: String, width: CGFloat) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        column.minWidth = width
        column.resizingMask = .userResizingMask
        return column
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var onUserScrollAwayFromLatest: () -> Void

        private var entries: [LogcatEntry] = []
        private weak var tableView: CopyableLogcatTableView?
        private weak var scrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var isPerformingProgrammaticScroll = false
        private var wasFollowingLatest = false

        init(onUserScrollAwayFromLatest: @escaping () -> Void) {
            self.onUserScrollAwayFromLatest = onUserScrollAwayFromLatest
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }

        fileprivate func attach(tableView: CopyableLogcatTableView, scrollView: NSScrollView) {
            self.tableView = tableView
            self.scrollView = scrollView
            tableView.copyText = { [weak self] selectedRows in
                guard let self else {
                    return ""
                }
                return selectedRows.compactMap { row in
                    guard self.entries.indices.contains(row) else {
                        return nil
                    }
                    return LogcatEntryTextFormatter.string(from: self.entries[row])
                }
                .joined(separator: "\n")
            }
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleScrollPositionChange()
                }
            }
        }

        func update(
            entries: [LogcatEntry],
            followsLatest: Bool
        ) {
            guard let tableView else {
                return
            }

            let entriesChanged = self.entries != entries
            self.entries = entries
            if entriesChanged {
                tableView.reloadData()
            }

            if followsLatest && (entriesChanged || !wasFollowingLatest) {
                scrollToLatest(in: tableView)
            }
            wasFollowingLatest = followsLatest
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            entries.count
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard let tableColumn, entries.indices.contains(row) else {
                return nil
            }

            let identifier = tableColumn.identifier
            let textField = (tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField)
                ?? makeTextField(identifier: identifier)
            let entry = entries[row]

            switch identifier.rawValue {
            case "time":
                textField.stringValue = LogcatTimestampFormatter.string(from: entry.timestamp)
                textField.alignment = .left
            case "level":
                textField.stringValue = entry.priority.rawValue
                textField.alignment = .center
            case "tag":
                textField.stringValue = entry.tag
                textField.alignment = .left
            default:
                textField.stringValue = entry.message
                textField.alignment = .left
            }

            return textField
        }

        private func makeTextField(identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
            let textField = NSTextField(labelWithString: "")
            textField.identifier = identifier
            textField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            textField.lineBreakMode = .byClipping
            textField.maximumNumberOfLines = 1
            return textField
        }

        private func scrollToLatest(in tableView: NSTableView) {
            guard !entries.isEmpty else {
                return
            }

            isPerformingProgrammaticScroll = true
            tableView.scrollRowToVisible(entries.count - 1)
            DispatchQueue.main.async { [weak self] in
                self?.isPerformingProgrammaticScroll = false
            }
        }

        private func handleScrollPositionChange() {
            guard !isPerformingProgrammaticScroll,
                  let scrollView,
                  let tableView else {
                return
            }

            let visibleHeight = scrollView.contentView.bounds.height
            let maximumOriginY = max(0, tableView.bounds.height - visibleHeight)
            let currentOriginY = scrollView.contentView.bounds.origin.y
            if currentOriginY < maximumOriginY - 1 {
                onUserScrollAwayFromLatest()
            }
        }
    }
}

private final class CopyableLogcatTableView: NSTableView {
    var copyText: ((IndexSet) -> String)?

    @objc func copy(_ sender: Any?) {
        let text = copyText?(selectedRowIndexes) ?? ""
        guard !text.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(CopyableLogcatTableView.copy(_:)) {
            return selectedRowIndexes.isEmpty == false
        }
        return super.validateUserInterfaceItem(item)
    }
}

private final class LogcatScrollView: NSScrollView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

final class LogcatTableContainer: NSView {
    private let scrollView: NSScrollView

    init(scrollView: NSScrollView) {
        self.scrollView = scrollView
        super.init(frame: .zero)
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var fittingSize: NSSize {
        intrinsicContentSize
    }
}
