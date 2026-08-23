import Foundation

struct LogcatTableColumnWidthCalculator {
    private var widestContentWidth: CGFloat

    init(headerWidth: CGFloat) {
        widestContentWidth = headerWidth
    }

    mutating func include(width: CGFloat) {
        widestContentWidth = max(widestContentWidth, width)
    }

    func fittedWidth(minimumWidth: CGFloat, horizontalInsets: CGFloat) -> CGFloat {
        max(minimumWidth, (widestContentWidth + horizontalInsets).rounded(.up))
    }
}
