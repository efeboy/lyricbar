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

    static let menuWidth: CGFloat = 160
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

}

enum WidthLadder {

    static let rungs: [CGFloat] = [160, 200, 240, 280, 320, 360, 400]
    static let step: CGFloat = 40
    static let defaultRung: CGFloat = 240

    static func available(widest: CGFloat = MenuBarMetrics.widestBox()) -> [CGFloat] {
        let fitting = rungs.filter { $0 <= widest }
        return fitting.isEmpty ? [rungs[0]] : fitting
    }

    static func snapped(_ width: CGFloat, widest: CGFloat = MenuBarMetrics.widestBox()) -> CGFloat {
        let choices = available(widest: widest)
        return choices.min { abs($0 - width) < abs($1 - width) } ?? defaultRung
    }

    static func migrated(band: String?) -> CGFloat? {
        switch band {
        case "compact":  160
        case "standard": 200
        case "fill":     240
        default:         nil
        }
    }
}
