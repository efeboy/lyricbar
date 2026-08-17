import AppKit

enum MenuBarMetrics {

    static let systemItemPadding: CGFloat = 16
    static let minimumBoxWidth: CGFloat = 80
    static let minimumFontSize: CGFloat = 9
    private static let nonNotchedStripShare: CGFloat = 0.45
    private static let sample = "Was the sky so grey at dawn"

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
        guard let screen else { return LyricWidth.standard.points }
        return screen.auxiliaryTopRightArea?.width ?? screen.frame.width * nonNotchedStripShare
    }

    static func statusStripLeftEdge(on screen: NSScreen? = menuBarScreen) -> CGFloat? {
        screen?.auxiliaryTopRightArea?.minX
    }

    static func widestBox(on screen: NSScreen? = menuBarScreen) -> CGFloat {
        max(minimumBoxWidth, statusStripWidth(on: screen) - systemItemPadding)
    }

    static func boxWidth(_ preference: LyricWidth, fittedWidth: CGFloat) -> CGFloat {
        max(minimumBoxWidth, min(preference.points, fittedWidth))
    }

    static func typicalCharacters(inBoxWidth boxWidth: CGFloat) -> Int {
        let perCharacter = textWidth(sample) / CGFloat(sample.count)
        guard perCharacter > 0 else { return 0 }
        return Int((boxWidth / perCharacter).rounded(.down))
    }
}

enum LyricWidth: String, CaseIterable, Sendable {
    case compact, standard, wide, fill

    var points: CGFloat {
        switch self {
        case .compact:  120
        case .standard: 280
        case .wide:     360
        case .fill:     .infinity
        }
    }

    var title: String {
        switch self {
        case .compact:  "Compact"
        case .standard: "Standard"
        case .wide:     "Wide"
        case .fill:     "Fit Menu Bar"
        }
    }
}

enum UpdateSpeed: Double, CaseIterable, Sendable {
    case smooth = 0.2
    case balanced = 0.5
    case relaxed = 1.0

    var seconds: Double { rawValue }

    var title: String {
        switch self {
        case .smooth:   "Smooth (200 ms)"
        case .balanced: "Balanced (500 ms)"
        case .relaxed:  "Relaxed (1 s)"
        }
    }
}
