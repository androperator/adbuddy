import SwiftUI

private struct LogcatSearchActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var logcatSearchAction: (() -> Void)? {
        get { self[LogcatSearchActionKey.self] }
        set { self[LogcatSearchActionKey.self] = newValue }
    }
}
