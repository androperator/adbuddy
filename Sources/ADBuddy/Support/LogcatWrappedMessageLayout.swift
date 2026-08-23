import AppKit

enum LogcatWrappedMessageLayout {
    static let compactRowHeight: CGFloat = 18
    private static let verticalInsets: CGFloat = 4

    static func rowHeight(for message: String, availableWidth: CGFloat, font: NSFont) -> CGFloat {
        guard !message.isEmpty, availableWidth > 0 else {
            return compactRowHeight
        }

        let messageHeight = (message as NSString).boundingRect(
            with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).height
        return max(compactRowHeight, (messageHeight + verticalInsets).rounded(.up))
    }
}
