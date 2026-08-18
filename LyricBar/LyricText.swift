import AppKit

enum LyricText {

    static func attributed(text: String, boxWidth: CGFloat, alpha: Double) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping

        return NSAttributedString(string: text, attributes: [
            .font: MenuBarMetrics.font(ofSize: LyricImage.fittedFontSize(for: text, boxWidth: boxWidth)),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(alpha),
            .paragraphStyle: paragraph,
        ])
    }
}
