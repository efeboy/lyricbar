import AppKit

enum LyricImage {

    private static let shrinkStep: CGFloat = 0.5

    static var barHeight: CGFloat {
        NSStatusBar.system.thickness
    }

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

    static func render(text: String, boxWidth: CGFloat, alpha: Double) -> NSImage {
        let size = NSSize(width: max(1, boxWidth.rounded()), height: barHeight)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping

        let line = NSAttributedString(string: text, attributes: [
            .font: MenuBarMetrics.font(ofSize: fittedFontSize(for: text, boxWidth: size.width)),
            .foregroundColor: NSColor.black.withAlphaComponent(alpha),
            .paragraphStyle: paragraph,
        ])
        let lineHeight = line.size().height

        let image = NSImage(size: size, flipped: false) { rect in
            line.draw(with: NSRect(x: 0, y: (rect.height - lineHeight) / 2,
                                  width: rect.width, height: lineHeight),
                      options: [.usesLineFragmentOrigin])
            return true
        }
        image.isTemplate = true
        return image
    }
}
