struct LogcatTableSelectionReloadScheduler {
    private(set) var hasDeferredReload = false

    mutating func shouldReloadImmediately(isTrackingRowSelection: Bool) -> Bool {
        guard !isTrackingRowSelection else {
            hasDeferredReload = true
            return false
        }

        return true
    }

    mutating func consumeDeferredReload() -> Bool {
        defer {
            hasDeferredReload = false
        }
        return hasDeferredReload
    }
}
