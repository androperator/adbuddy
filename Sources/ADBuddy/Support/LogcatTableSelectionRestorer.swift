import Foundation

struct LogcatTableSelection: Equatable {
    let row: Int
    let entryID: LogcatEntry.ID
}

enum LogcatTableSelectionRestorer {
    static func selections(
        at rows: IndexSet,
        entryAt: (Int) -> LogcatEntry?
    ) -> [LogcatTableSelection] {
        rows.compactMap { row in
            entryAt(row).map { LogcatTableSelection(row: row, entryID: $0.id) }
        }
    }

    static func rows(
        for selections: [LogcatTableSelection],
        entryCount: Int,
        entryAt: (Int) -> LogcatEntry?
    ) -> IndexSet {
        guard !selections.isEmpty else {
            return []
        }

        var restoredRows = IndexSet()
        var unresolvedEntryIDs = Set(selections.map(\.entryID))

        for selection in selections {
            guard selection.row < entryCount,
                  entryAt(selection.row)?.id == selection.entryID else {
                continue
            }

            restoredRows.insert(selection.row)
            unresolvedEntryIDs.remove(selection.entryID)
        }

        guard !unresolvedEntryIDs.isEmpty else {
            return restoredRows
        }

        for row in 0..<entryCount {
            guard let entryID = entryAt(row)?.id,
                  unresolvedEntryIDs.contains(entryID) else {
                continue
            }

            restoredRows.insert(row)
            unresolvedEntryIDs.remove(entryID)

            if unresolvedEntryIDs.isEmpty {
                break
            }
        }

        return restoredRows
    }
}
