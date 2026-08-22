import SwiftUI

struct LogcatTableView: View {
    let entries: [LogcatEntry]

    var body: some View {
        Table(entries) {
            TableColumn("Time") { entry in
                Text(LogcatTimestampFormatter.string(from: entry.timestamp))
            }
            .width(88)

            TableColumn("Level") { entry in
                Text(entry.priority.rawValue)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .width(42)

            TableColumn("Tag") { entry in
                Text(entry.tag)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 160)

            TableColumn("Message") { entry in
                Text(entry.message)
                    .lineLimit(1)
            }
            .width(min: 240, ideal: 480)
        }
        .font(.system(size: 11, design: .monospaced))
    }
}
