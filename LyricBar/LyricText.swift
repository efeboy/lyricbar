import AppKit

enum LyricText {

    private static let shrinkStep: CGFloat = 0.5

    static func fittedFontSize(for text: String, boxWidth: CGFloat) -> CGFloat {
        let base = MenuBarMetrics.baseFontSize
        let floor = MenuBarMetrics.minimumFontSize
        guard !text.isEmpty, boxWidth > 0 else { return base }

        let natural = MenuBarMetrics.textWidth(text, fontSize: base)
        guard natural > boxWidth else { return base }

        var size = min(base, max(floor, (base * boxWidth / natural).rounded(.down)))
        while size > floor, MenuBarMetrics.textWidth(text, fontSize: size) > boxWidth {
            size -= shrinkStep
        }
        return max(floor, size)
    }

    static func attributed(text: String, boxWidth: CGFloat, alpha: Double) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping

        return NSAttributedString(string: text, attributes: [
            .font: MenuBarMetrics.font(ofSize: fittedFontSize(for: text, boxWidth: boxWidth)),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(alpha),
            .paragraphStyle: paragraph,
        ])
    }
}
