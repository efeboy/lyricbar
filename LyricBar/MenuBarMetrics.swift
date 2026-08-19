import AppKit

enum MenuBarMetrics {

    static let systemItemPadding: CGFloat = 16
    static let minimumBoxWidth: CGFloat = 80
    static let minimumFontSize: CGFloat = 9
    private static let nonNotchedStripShare: CGFloat = 0.45
    private static let fallbackStripWidth: CGFloat = 400

    static func font(ofSize size: CGFloat = 0) -> NSFont {
        .menuBarFont(ofSize: size)
    }

    static var baseFontSize: CGFloat {
        font().pointSize
    }

    static func measurer(fontSize: CGFloat = 0) -> (String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font(ofSize: fontSize)]
        return { text in
            text.isEmpty ? 0 : NSAttributedString(string: text, attributes: attributes).size().width
        }
    }

    static func textWidth(_ text: String, fontSize: CGFloat = 0) -> CGFloat {
        measurer(fontSize: fontSize)(text)
    }

    static var menuBarScreen: NSScreen? {
        NSScreen.screens.first
    }

    static func statusStripWidth(on screen: NSScreen? = menuBarScreen) -> CGFloat {
        guard let screen else { return fallbackStripWidth }
        return screen.auxiliaryTopRightArea?.width ?? screen.frame.width * nonNotchedStripShare
    }

    static func statusStripLeftEdge(on screen: NSScreen? = menuBarScreen) -> CGFloat? {
        screen?.auxiliaryTopRightArea?.minX
    }

    static func widestBox(on screen: NSScreen? = menuBarScreen) -> CGFloat {
        max(minimumBoxWidth, statusStripWidth(on: screen) - systemItemPadding)
    }

    static func boxWidth(_ preference: LyricWidth, fittedWidth: CGFloat) -> CGFloat {
        max(minimumBoxWidth, min(fittedWidth, (preference.shareOfFit * fittedWidth).rounded()))
    }
}

enum LyricWidth: String, CaseIterable, Sendable {
    case compact, standard, fill

    var shareOfFit: CGFloat {
        switch self {
        case .compact:  0.5
        case .standard: 0.75
        case .fill:     1.0
        }
    }

    var title: String {
        switch self {
        case .compact:  "Compact"
        case .standard: "Standard"
        case .fill:     "Fit Menu Bar"
        }
    }
}
