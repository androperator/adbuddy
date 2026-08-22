@preconcurrency import AppKit
import SwiftUI

struct LogcatTableView: NSViewRepresentable {
    let entryCount: Int
    let entryRevision: UInt64
    let entryAt: (Int) -> LogcatEntry?
    let followsLatest: Bool
    let showsProcessID: Bool
    let showsThreadID: Bool
    let priorityColors: [LogcatPriority: LogcatColorComponents]
    let onUserScrollAwayFromLatest: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onUserScrollAwayFromLatest: onUserScrollAwayFromLatest)
    }

    func makeNSView(context: Context) -> LogcatTableContainer {
        let tableView = CopyableLogcatTableView()
        let visibleColumns = Set(LogcatTableColumn.visibleColumns())
        for definition in LogcatTableColumn.allCases {
            tableView.addTableColumn(column(definition, isHidden: !visibleColumns.contains(definition)))
        }
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.rowHeight = 18
        tableView.intercellSpacing = .zero
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.setAccessibilityLabel("Logcat entries")
        tableView.setAccessibilityHelp("Select one or more entries, then press Command-C to copy them.")

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
            entryCount: entryCount,
            entryRevision: entryRevision,
            entryAt: entryAt,
            followsLatest: followsLatest,
            priorityColors: priorityColors,
            showsProcessID: showsProcessID,
            showsThreadID: showsThreadID
        )
    }

    private func column(_ definition: LogcatTableColumn, isHidden: Bool) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(definition.identifier))
        column.title = definition.title
        column.width = definition.width
        column.minWidth = definition.width
        column.resizingMask = .userResizingMask
        column.isHidden = isHidden
        return column
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var onUserScrollAwayFromLatest: () -> Void

        private var entryCount = 0
        private var entryRevision: UInt64?
        private var entryAt: (Int) -> LogcatEntry? = { _ in nil }
        private weak var tableView: CopyableLogcatTableView?
        private weak var scrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var isPerformingProgrammaticScroll = false
        private var wasFollowingLatest = false
        private var priorityColors = LogcatPriority.defaultColors

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
                    self.entryAt(row).map(LogcatEntryTextFormatter.string(from:))
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
            entryCount: Int,
            entryRevision: UInt64,
            entryAt: @escaping (Int) -> LogcatEntry?,
            followsLatest: Bool,
            priorityColors: [LogcatPriority: LogcatColorComponents],
            showsProcessID: Bool,
            showsThreadID: Bool
        ) {
            guard let tableView else {
                return
            }

            let entriesChanged = self.entryRevision != entryRevision
            self.entryCount = entryCount
            self.entryRevision = entryRevision
            self.entryAt = entryAt
            let colorsChanged = self.priorityColors != priorityColors
            self.priorityColors = priorityColors
            let columnVisibilityChanged = updateColumnVisibility(
                in: tableView,
                showsProcessID: showsProcessID,
                showsThreadID: showsThreadID
            )
            if entriesChanged || colorsChanged || columnVisibilityChanged {
                tableView.reloadData()
            }

            if followsLatest && (entriesChanged || !wasFollowingLatest) {
                scrollToLatest(in: tableView)
            }
            wasFollowingLatest = followsLatest
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            entryCount
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard let tableColumn, let entry = entryAt(row) else {
                return nil
            }

            let identifier = tableColumn.identifier

            if identifier.rawValue == "level" {
                let badge = (tableView.makeView(withIdentifier: identifier, owner: nil) as? LogcatLevelBadgeView)
                    ?? LogcatLevelBadgeView(identifier: identifier)
                badge.configure(priority: entry.priority, color: color(for: entry.priority))
                return badge
            }

            let textField = (tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField)
                ?? makeTextField(identifier: identifier)
            let definition = LogcatTableColumn.allCases.first { $0.identifier == identifier.rawValue }
            textField.setAccessibilityLabel(definition?.accessibilityLabel ?? "Logcat entry")

            switch identifier.rawValue {
            case "time":
                textField.stringValue = LogcatTimestampFormatter.string(from: entry.timestamp)
                textField.alignment = .left
            case "processID":
                textField.stringValue = String(entry.processID)
                textField.alignment = .right
            case "threadID":
                textField.stringValue = String(entry.threadID)
                textField.alignment = .right
            case "tag":
                textField.stringValue = entry.tag
                textField.alignment = .left
            default:
                textField.stringValue = entry.message
                textField.alignment = .left
                textField.textColor = messageColor(for: entry.priority)
            }
            textField.setAccessibilityValue(textField.stringValue)

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

        private func color(for priority: LogcatPriority) -> NSColor {
            priorityColors[priority, default: LogcatPriority.defaultColors[priority]!].nsColor
        }

        private func messageColor(for priority: LogcatPriority) -> NSColor {
            color(for: priority).blended(withFraction: 0.55, of: .labelColor) ?? .labelColor
        }

        private func updateColumnVisibility(
            in tableView: NSTableView,
            showsProcessID: Bool,
            showsThreadID: Bool
        ) -> Bool {
            let processIDColumn = tableView.tableColumn(
                withIdentifier: NSUserInterfaceItemIdentifier(LogcatTableColumn.processID.identifier)
            )
            let threadIDColumn = tableView.tableColumn(
                withIdentifier: NSUserInterfaceItemIdentifier(LogcatTableColumn.threadID.identifier)
            )
            let processIDChanged = processIDColumn?.isHidden == showsProcessID
            let threadIDChanged = threadIDColumn?.isHidden == showsThreadID
            processIDColumn?.isHidden = !showsProcessID
            threadIDColumn?.isHidden = !showsThreadID
            return processIDChanged || threadIDChanged
        }

        private func scrollToLatest(in tableView: NSTableView) {
            guard entryCount > 0 else {
                return
            }

            isPerformingProgrammaticScroll = true
            tableView.scrollRowToVisible(entryCount - 1)
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

private final class LogcatLevelBadgeView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        wantsLayer = true
        layer?.cornerRadius = 4
        label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        label.alignment = .center
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: 3, dy: 1)
    }

    func configure(priority: LogcatPriority, color: NSColor) {
        label.stringValue = priority.rawValue
        label.textColor = color
        layer?.backgroundColor = color.withAlphaComponent(0.16).cgColor
        setAccessibilityLabel("Log level")
        setAccessibilityValue(priority.displayName)
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
