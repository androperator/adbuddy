@preconcurrency import AppKit
import SwiftUI

struct LogcatTableView: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    let entryCount: Int
    let entryRevision: UInt64
    let entryAt: (Int) -> LogcatEntry?
    let applicationIDRevision: UInt64
    let applicationIDForProcessID: (Int) -> String?
    let followsLatest: Bool
    let showsOnlyCrashesAndExceptions: Bool
    let showsProcessID: Bool
    let showsThreadID: Bool
    let showsApplicationID: Bool
    let showsTag: Bool
    let columnOrder: [LogcatTableColumn]
    let columnWidths: [String: Double]
    let wrapsMessages: Bool
    let priorityColors: [LogcatPriority: LogcatColorComponents]
    let onUserScrollAwayFromLatest: () -> Void
    let onToggleColumnVisibility: (LogcatTableColumn) -> Void
    let onColumnOrderChanged: ([LogcatTableColumn]) -> Void
    let onColumnWidthsChanged: ([LogcatTableColumn: CGFloat]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onUserScrollAwayFromLatest: onUserScrollAwayFromLatest,
            onToggleColumnVisibility: onToggleColumnVisibility,
            onColumnOrderChanged: onColumnOrderChanged,
            onColumnWidthsChanged: onColumnWidthsChanged
        )
    }

    func makeNSView(context: Context) -> LogcatTableContainer {
        let tableView = CopyableLogcatTableView()
        let visibleColumns = Set(LogcatTableColumn.visibleColumns(
            showsProcessID: showsProcessID,
            showsThreadID: showsThreadID,
            showsApplicationID: showsApplicationID,
            showsTag: showsTag
        ))
        for definition in columnOrder {
            tableView.addTableColumn(
                column(
                    definition,
                    isHidden: !visibleColumns.contains(definition),
                    savedWidth: columnWidths[definition.identifier].map { CGFloat($0) }
                )
            )
        }

        let headerView = LogcatTableHeaderView()
        let coordinator = context.coordinator
        headerView.columnDividerDoubleClicked = { [weak coordinator] columnIndex in
            coordinator?.resizeColumnToFitContent(at: columnIndex)
        }
        headerView.columnConfigurationMenu = { [weak coordinator] in
            coordinator?.makeColumnConfigurationMenu()
        }
        tableView.headerView = headerView

        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.rowHeight = LogcatWrappedMessageLayout.compactRowHeight
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
        context.coordinator.onToggleColumnVisibility = onToggleColumnVisibility
        context.coordinator.onColumnOrderChanged = onColumnOrderChanged
        context.coordinator.onColumnWidthsChanged = onColumnWidthsChanged
        context.coordinator.update(
            entryCount: entryCount,
            entryRevision: entryRevision,
            entryAt: entryAt,
            applicationIDRevision: applicationIDRevision,
            applicationIDForProcessID: applicationIDForProcessID,
            followsLatest: followsLatest,
            showsOnlyCrashesAndExceptions: showsOnlyCrashesAndExceptions,
            colorScheme: colorScheme,
            priorityColors: priorityColors,
            showsProcessID: showsProcessID,
            showsThreadID: showsThreadID,
            showsApplicationID: showsApplicationID,
            showsTag: showsTag,
            wrapsMessages: wrapsMessages
        )
    }

    private func column(
        _ definition: LogcatTableColumn,
        isHidden: Bool,
        savedWidth: CGFloat?
    ) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(definition.identifier))
        column.title = definition.title
        column.minWidth = 40
        column.width = max(savedWidth ?? definition.width, column.minWidth)
        column.resizingMask = .userResizingMask
        column.isHidden = isHidden
        return column
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var onUserScrollAwayFromLatest: () -> Void
        var onToggleColumnVisibility: (LogcatTableColumn) -> Void
        var onColumnOrderChanged: ([LogcatTableColumn]) -> Void
        var onColumnWidthsChanged: ([LogcatTableColumn: CGFloat]) -> Void

        private var entryCount = 0
        private var entryRevision: UInt64?
        private var entryAt: (Int) -> LogcatEntry? = { _ in nil }
        private var applicationIDRevision: UInt64?
        private var applicationIDForProcessID: (Int) -> String? = { _ in nil }
        private weak var tableView: CopyableLogcatTableView?
        private weak var scrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var columnResizeObserver: NSObjectProtocol?
        private var columnMoveObserver: NSObjectProtocol?
        private var isPerformingProgrammaticScroll = false
        private var isSuppressingScrollEventsForLayout = false
        private var wasFollowingLatest = false
        private var showsOnlyCrashesAndExceptions: Bool?
        private var colorScheme: ColorScheme?
        private var priorityColors = LogcatPriority.defaultColors
        private var previouslySelectedRows = IndexSet()
        private var selectionReloadScheduler = LogcatTableSelectionReloadScheduler()
        private var wrapsMessages: Bool?
        private var messageColumnWidth: CGFloat?
        private var suppressesScrollEventOnNextReload = false
        private let textFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        init(
            onUserScrollAwayFromLatest: @escaping () -> Void,
            onToggleColumnVisibility: @escaping (LogcatTableColumn) -> Void,
            onColumnOrderChanged: @escaping ([LogcatTableColumn]) -> Void,
            onColumnWidthsChanged: @escaping ([LogcatTableColumn: CGFloat]) -> Void
        ) {
            self.onUserScrollAwayFromLatest = onUserScrollAwayFromLatest
            self.onToggleColumnVisibility = onToggleColumnVisibility
            self.onColumnOrderChanged = onColumnOrderChanged
            self.onColumnWidthsChanged = onColumnWidthsChanged
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            if let columnResizeObserver {
                NotificationCenter.default.removeObserver(columnResizeObserver)
            }
            if let columnMoveObserver {
                NotificationCenter.default.removeObserver(columnMoveObserver)
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
            tableView.selectionTrackingDidEnd = { [weak self] in
                Task { @MainActor [weak self] in
                    self?.reloadAfterSelectionTrackingIfNeeded()
                }
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
            columnResizeObserver = NotificationCenter.default.addObserver(
                forName: NSTableView.columnDidResizeNotification,
                object: tableView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleColumnResize()
                }
            }
            columnMoveObserver = NotificationCenter.default.addObserver(
                forName: NSTableView.columnDidMoveNotification,
                object: tableView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reportColumnOrder()
                }
            }
        }

        func update(
            entryCount: Int,
            entryRevision: UInt64,
            entryAt: @escaping (Int) -> LogcatEntry?,
            applicationIDRevision: UInt64,
            applicationIDForProcessID: @escaping (Int) -> String?,
            followsLatest: Bool,
            showsOnlyCrashesAndExceptions: Bool,
            colorScheme: ColorScheme,
            priorityColors: [LogcatPriority: LogcatColorComponents],
            showsProcessID: Bool,
            showsThreadID: Bool,
            showsApplicationID: Bool,
            showsTag: Bool,
            wrapsMessages: Bool
        ) {
            guard let tableView else {
                return
            }

            let entriesChanged = self.entryRevision != entryRevision
            let applicationIDsChanged = self.applicationIDRevision != applicationIDRevision
            let colorSchemeChanged = self.colorScheme != colorScheme
            let colorsChanged = self.priorityColors != priorityColors
            let wrappingChanged = self.wrapsMessages != wrapsMessages
            if wrappingChanged {
                suppressesScrollEventOnNextReload = true
            }
            let shouldReload = entriesChanged ||
                applicationIDsChanged ||
                colorSchemeChanged ||
                colorsChanged ||
                wrappingChanged
            let isExpandingCrashFilter = self.showsOnlyCrashesAndExceptions == true &&
                !showsOnlyCrashesAndExceptions
            let shouldReloadImmediately = shouldReload && selectionReloadScheduler.shouldReloadImmediately(
                isTrackingRowSelection: tableView.isTrackingRowSelection
            )
            let selectedEntries = shouldReloadImmediately
                ? LogcatTableSelectionRestorer.selections(
                    at: tableView.selectedRowIndexes,
                    entryAt: self.entryAt
                )
                : []

            self.entryCount = entryCount
            self.entryRevision = entryRevision
            self.entryAt = entryAt
            self.applicationIDRevision = applicationIDRevision
            self.applicationIDForProcessID = applicationIDForProcessID
            self.showsOnlyCrashesAndExceptions = showsOnlyCrashesAndExceptions
            self.colorScheme = colorScheme
            self.priorityColors = priorityColors
            self.wrapsMessages = wrapsMessages
            messageColumnWidth = messageColumnWidth(in: tableView)
            updateColumnVisibility(
                in: tableView,
                showsProcessID: showsProcessID,
                showsThreadID: showsThreadID,
                showsApplicationID: showsApplicationID,
                showsTag: showsTag
            )
            let selectionAnchor = isExpandingCrashFilter ? selectedEntries.first : nil
            if shouldReloadImmediately {
                reloadData(in: tableView, preserving: selectedEntries)
            }

            let didScrollToSelectionAnchor = scrollToSelectionAnchor(
                selectionAnchor,
                in: tableView
            )
            if didScrollToSelectionAnchor && followsLatest {
                onUserScrollAwayFromLatest()
            }
            if followsLatest &&
                !didScrollToSelectionAnchor &&
                !tableView.isTrackingRowSelection &&
                (entriesChanged || !wasFollowingLatest || wrappingChanged) {
                scrollToLatest(in: tableView)
            }
            wasFollowingLatest = followsLatest
        }

        private func restoreSelection(
            _ selections: [LogcatTableSelection],
            in tableView: NSTableView
        ) {
            guard !selections.isEmpty else {
                return
            }

            let restoredRows = LogcatTableSelectionRestorer.rows(
                for: selections,
                entryCount: entryCount,
                entryAt: entryAt
            )
            tableView.selectRowIndexes(restoredRows, byExtendingSelection: false)
        }

        private func reloadAfterSelectionTrackingIfNeeded() {
            guard selectionReloadScheduler.consumeDeferredReload(), let tableView else {
                return
            }

            let selectedEntries = LogcatTableSelectionRestorer.selections(
                at: tableView.selectedRowIndexes,
                entryAt: entryAt
            )
            reloadData(in: tableView, preserving: selectedEntries)
        }

        private func reloadData(
            in tableView: NSTableView,
            preserving selections: [LogcatTableSelection]
        ) {
            let suppressesScrollEvent = suppressesScrollEventOnNextReload
            suppressesScrollEventOnNextReload = false
            if suppressesScrollEvent {
                suppressScrollEventsDuringLayout()
            }
            tableView.reloadData()
            restoreSelection(selections, in: tableView)
        }

        fileprivate func resizeColumnToFitContent(at columnIndex: Int) {
            guard let tableView,
                  tableView.tableColumns.indices.contains(columnIndex) else {
                return
            }

            let column = tableView.tableColumns[columnIndex]
            guard !column.isHidden,
                  let definition = LogcatTableColumn.allCases.first(
                    where: { $0.identifier == column.identifier.rawValue }
                  ) else {
                return
            }

            var widthCalculator = LogcatTableColumnWidthCalculator(
                headerWidth: column.headerCell.cellSize.width
            )
            for row in 0..<entryCount {
                guard let entry = entryAt(row) else {
                    continue
                }
                widthCalculator.include(width: width(of: value(for: definition, in: entry)))
            }

            column.width = widthCalculator.fittedWidth(
                minimumWidth: column.minWidth,
                horizontalInsets: 8
            )
        }

        fileprivate func makeColumnConfigurationMenu() -> NSMenu {
            let menu = NSMenu()
            for column in LogcatTableColumn.configurableColumns {
                let item = NSMenuItem(
                    title: column.accessibilityLabel,
                    action: #selector(toggleColumnVisibility(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = column.identifier
                item.state = isColumnVisible(column) ? .on : .off
                menu.addItem(item)
            }
            return menu
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            entryCount
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard wrapsMessages == true,
                  let entry = entryAt(row),
                  let messageColumn = tableView.tableColumn(
                    withIdentifier: NSUserInterfaceItemIdentifier(LogcatTableColumn.message.identifier)
                  ) else {
                return LogcatWrappedMessageLayout.compactRowHeight
            }

            return LogcatWrappedMessageLayout.rowHeight(
                for: entry.message,
                availableWidth: messageColumn.width - 8,
                font: textFont
            )
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
                badge.configure(
                    priority: entry.priority,
                    color: color(for: entry.priority),
                    isSelected: tableView.isRowSelected(row)
                )
                return badge
            }

            let textField = (tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField)
                ?? makeTextField(identifier: identifier)
            let definition = LogcatTableColumn.allCases.first { $0.identifier == identifier.rawValue }
            textField.setAccessibilityLabel(definition?.accessibilityLabel ?? "Logcat entry")
            textField.textColor = tableView.isRowSelected(row) ? .selectedTextColor : .labelColor
            if identifier.rawValue == LogcatTableColumn.message.identifier {
                textField.lineBreakMode = wrapsMessages == true ? .byWordWrapping : .byClipping
                textField.maximumNumberOfLines = wrapsMessages == true ? 0 : 1
                textField.usesSingleLineMode = wrapsMessages != true
            }

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
            case "applicationID":
                textField.stringValue = applicationIDForProcessID(entry.processID) ?? ""
                textField.alignment = .left
            case "tag":
                textField.stringValue = entry.tag
                textField.alignment = .left
            default:
                textField.stringValue = entry.message
                textField.alignment = .left
                if !tableView.isRowSelected(row) {
                    textField.textColor = messageColor(for: entry.priority)
                }
            }
            textField.setAccessibilityValue(textField.stringValue)

            return textField
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView else {
                return
            }

            let rowsToRefresh = previouslySelectedRows.union(tableView.selectedRowIndexes)
            previouslySelectedRows = tableView.selectedRowIndexes
            let validRows = IndexSet(rowsToRefresh.filter { $0 < entryCount })
            guard !validRows.isEmpty else {
                return
            }

            tableView.reloadData(
                forRowIndexes: validRows,
                columnIndexes: IndexSet(integersIn: 0..<tableView.tableColumns.count)
            )
        }

        private func makeTextField(identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
            let textField = NSTextField(labelWithString: "")
            textField.identifier = identifier
            textField.font = textFont
            textField.lineBreakMode = .byClipping
            textField.maximumNumberOfLines = 1
            return textField
        }

        private func value(for column: LogcatTableColumn, in entry: LogcatEntry) -> String {
            switch column {
            case .time:
                LogcatTimestampFormatter.string(from: entry.timestamp)
            case .processID:
                String(entry.processID)
            case .threadID:
                String(entry.threadID)
            case .applicationID:
                applicationIDForProcessID(entry.processID) ?? ""
            case .level:
                entry.priority.rawValue
            case .tag:
                entry.tag
            case .message:
                entry.message
            }
        }

        private func width(of value: String) -> CGFloat {
            (value as NSString).size(
                withAttributes: [.font: textFont]
            ).width
        }

        private func color(for priority: LogcatPriority) -> NSColor {
            priorityColors[priority, default: LogcatPriority.defaultColors[priority]!].nsColor
        }

        private func messageColor(for priority: LogcatPriority) -> NSColor {
            let foregroundColor: NSColor = colorScheme == .dark ? .white : .labelColor
            let foregroundFraction: CGFloat = colorScheme == .dark ? 0.65 : 0.55
            return color(for: priority).blended(withFraction: foregroundFraction, of: foregroundColor)
                ?? foregroundColor
        }

        private func updateColumnVisibility(
            in tableView: NSTableView,
            showsProcessID: Bool,
            showsThreadID: Bool,
            showsApplicationID: Bool,
            showsTag: Bool
        ) {
            let visibleColumns = Set(LogcatTableColumn.visibleColumns(
                showsProcessID: showsProcessID,
                showsThreadID: showsThreadID,
                showsApplicationID: showsApplicationID,
                showsTag: showsTag
            ))
            for column in LogcatTableColumn.configurableColumns {
                tableView.tableColumn(
                    withIdentifier: NSUserInterfaceItemIdentifier(column.identifier)
                )?.isHidden = !visibleColumns.contains(column)
            }
        }

        @objc private func toggleColumnVisibility(_ sender: NSMenuItem) {
            guard let identifier = sender.representedObject as? String,
                  let column = LogcatTableColumn.allCases.first(
                    where: { $0.identifier == identifier }
                  ) else {
                return
            }
            onToggleColumnVisibility(column)
        }

        private func isColumnVisible(_ column: LogcatTableColumn) -> Bool {
            tableView?.tableColumn(
                withIdentifier: NSUserInterfaceItemIdentifier(column.identifier)
            )?.isHidden == false
        }

        private func handleColumnResize() {
            reportColumnWidths()

            guard wrapsMessages == true,
                  let tableView,
                  let currentMessageColumnWidth = messageColumnWidth(in: tableView),
                  currentMessageColumnWidth != messageColumnWidth else {
                return
            }

            messageColumnWidth = currentMessageColumnWidth
            guard entryCount > 0 else {
                return
            }

            suppressScrollEventsDuringLayout()
            tableView.noteHeightOfRows(
                withIndexesChanged: IndexSet(integersIn: 0..<entryCount)
            )
        }

        private func reportColumnOrder() {
            guard let tableView else {
                return
            }
            let columns = tableView.tableColumns.compactMap { column in
                LogcatTableColumn.allCases.first {
                    $0.identifier == column.identifier.rawValue
                }
            }
            onColumnOrderChanged(columns)
        }

        private func reportColumnWidths() {
            guard let tableView else {
                return
            }
            let columnWidths: [(LogcatTableColumn, CGFloat)] = tableView.tableColumns.compactMap { column -> (LogcatTableColumn, CGFloat)? in
                    guard let definition = LogcatTableColumn.allCases.first(
                        where: { $0.identifier == column.identifier.rawValue }
                    ) else {
                        return nil
                    }
                    return (definition, column.width)
                }
            let widths = Dictionary(uniqueKeysWithValues: columnWidths)
            onColumnWidthsChanged(widths)
        }

        private func messageColumnWidth(in tableView: NSTableView) -> CGFloat? {
            tableView.tableColumn(
                withIdentifier: NSUserInterfaceItemIdentifier(LogcatTableColumn.message.identifier)
            )?.width
        }

        private func suppressScrollEventsDuringLayout() {
            isPerformingProgrammaticScroll = true
            isSuppressingScrollEventsForLayout = true
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
                self?.isSuppressingScrollEventsForLayout = false
                self?.isPerformingProgrammaticScroll = false
            }
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

        private func scrollToSelectionAnchor(
            _ selection: LogcatTableSelection?,
            in tableView: NSTableView
        ) -> Bool {
            guard let selection,
                  let row = LogcatTableSelectionRestorer.rows(
                    for: [selection],
                    entryCount: entryCount,
                    entryAt: entryAt
                  ).first,
                  let scrollView else {
                return false
            }

            let contentView = scrollView.contentView
            let visibleHeight = contentView.bounds.height
            let rowMidpoint = tableView.rect(ofRow: row).midY
            let maximumOriginY = max(0, tableView.bounds.height - visibleHeight)
            let originY = min(max(0, rowMidpoint - visibleHeight / 2), maximumOriginY)

            isPerformingProgrammaticScroll = true
            contentView.scroll(to: NSPoint(x: contentView.bounds.origin.x, y: originY))
            scrollView.reflectScrolledClipView(contentView)
            DispatchQueue.main.async { [weak self] in
                guard self?.isSuppressingScrollEventsForLayout != true else {
                    return
                }
                self?.isPerformingProgrammaticScroll = false
            }
            return true
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

final class LogcatTableHeaderView: NSTableHeaderView {
    var columnDividerDoubleClicked: ((Int) -> Void)?
    var columnConfigurationMenu: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        columnConfigurationMenu?() ?? super.menu(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2,
           let columnIndex = columnIndex(forDividerAt: location) {
            columnDividerDoubleClicked?(columnIndex)
            return
        }

        super.mouseDown(with: event)
    }

    private func columnIndex(forDividerAt location: NSPoint) -> Int? {
        guard bounds.contains(location), let tableView else {
            return nil
        }

        for columnIndex in tableView.tableColumns.indices {
            let column = tableView.tableColumns[columnIndex]
            guard !column.isHidden else {
                continue
            }

            if abs(headerRect(ofColumn: columnIndex).maxX - location.x) <= 3 {
                return columnIndex
            }
        }

        return nil
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

    func configure(priority: LogcatPriority, color: NSColor, isSelected: Bool) {
        label.stringValue = priority.rawValue
        label.textColor = isSelected ? .selectedTextColor : color
        layer?.backgroundColor = color.withAlphaComponent(0.16).cgColor
        setAccessibilityLabel("Log level")
        setAccessibilityValue(priority.displayName)
    }
}

private final class CopyableLogcatTableView: NSTableView {
    var copyText: ((IndexSet) -> String)?
    var selectionTrackingDidEnd: (() -> Void)?
    private(set) var isTrackingRowSelection = false

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

    override func mouseDown(with event: NSEvent) {
        isTrackingRowSelection = true
        defer {
            isTrackingRowSelection = false
            selectionTrackingDidEnd?()
        }
        super.mouseDown(with: event)
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
