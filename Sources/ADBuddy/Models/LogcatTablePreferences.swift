import Foundation

struct LogcatTablePreferences: Codable, Equatable {
    var wrapsMessages = false
    var showsProcessID = false
    var showsThreadID = false
    var showsApplicationID = false
    var showsTag = true
    var columnOrderIdentifiers = LogcatTableColumn.allCases.map(\.identifier)
    var columnWidths: [String: Double] = [:]

    var orderedColumns: [LogcatTableColumn] {
        LogcatTableColumn.orderedColumns(from: columnOrderIdentifiers)
    }

    func isVisible(_ column: LogcatTableColumn) -> Bool {
        switch column {
        case .processID:
            showsProcessID
        case .threadID:
            showsThreadID
        case .applicationID:
            showsApplicationID
        case .tag:
            showsTag
        case .time, .level, .message:
            true
        }
    }

    func width(for column: LogcatTableColumn) -> CGFloat? {
        guard let width = columnWidths[column.identifier], width.isFinite, width >= 40 else {
            return nil
        }
        return CGFloat(width)
    }

    mutating func setColumnVisibility(_ isVisible: Bool, for column: LogcatTableColumn) {
        switch column {
        case .processID:
            showsProcessID = isVisible
        case .threadID:
            showsThreadID = isVisible
        case .applicationID:
            showsApplicationID = isVisible
        case .tag:
            showsTag = isVisible
        case .time, .level, .message:
            return
        }
    }

    mutating func setColumnOrder(_ columns: [LogcatTableColumn]) {
        columnOrderIdentifiers = LogcatTableColumn.orderedColumns(
            from: columns.map(\.identifier)
        )
        .map(\.identifier)
    }

    mutating func setColumnWidths(_ widths: [LogcatTableColumn: CGFloat]) {
        let validWidths: [(String, Double)] = widths.compactMap { column, width -> (String, Double)? in
                guard width.isFinite, width >= 40 else {
                    return nil
                }
                return (column.identifier, Double(width))
            }
        columnWidths = Dictionary(uniqueKeysWithValues: validWidths)
    }

    func normalized() -> LogcatTablePreferences {
        var preferences = self
        preferences.columnOrderIdentifiers = orderedColumns.map(\.identifier)
        preferences.columnWidths = columnWidths.filter { identifier, width in
            LogcatTableColumn.allCases.contains(where: { $0.identifier == identifier }) &&
                width.isFinite &&
                width >= 40
        }
        return preferences
    }
}
