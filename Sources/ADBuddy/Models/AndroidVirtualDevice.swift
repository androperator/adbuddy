import Foundation

struct AndroidVirtualDevice: Identifiable, Equatable, Sendable {
    let name: String

    var id: String {
        name
    }
}
