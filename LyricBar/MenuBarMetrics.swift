import AppKit
import CoreGraphics

// MARK: - Menu bar geometry
//
// The menu bar item is ONE FIXED BOX. Its width is decided from the space the
// status area actually has, once per screen configuration, and never again —
// not per track, not per line, not per state. Only the text inside it changes.
//
//   ┌──────────────────────── boxWidth ────────────────────────┐
//   │ [icon 18] gap 4 │ ──────────── textWidth ─────────────── │
//   └──────────────────────────────────────────────────────────┘
//
// `LyricReflow` is handed `textWidth` as a hard budget and divides each lyric
// line into chunks that fit it, so the text never needs the box to grow.
//
// Why the budget is points and not a character count: in the menu bar's
// proportional font a character spans 3.47pt ("i") to 12.85pt ("W") — a factor
// of 3.7. A character budget sized for average text lets a capital-heavy line
// overrun the box, and a budget sized for the worst case wastes most of the bar.
// `typicalCharacters` reports the count for display; the geometry stays in points.

enum MenuBarMetrics {

    /// The menu bar draws status item labels in the semibold system font at 13pt.
    /// Measured against 2585 Beatles lines, this averages 6.38pt per character.
    static func menuFont() -> NSFont { .systemFont(ofSize: 13, weight: .semibold) }

    /// A reusable measuring closure. Reflow measures O(words²) substrings per long
    /// line, so build the attributes once rather than per call.
    static func measurer() -> (String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: menuFont()]
        return { s in
            s.isEmpty ? 0 : NSAttributedString(string: s, attributes: attrs).size().width
        }
    }

    /// Rendered width of a single string. For bulk work use `measurer()`.
    static func textWidth(_ s: String) -> CGFloat { measurer()(s) }

    // MARK: The box

    /// Width of the `quote.closing` glyph as SwiftUI lays it out, and the gap to
    /// the lyric. Pinned rather than measured at runtime so the box cannot change
    /// size if the symbol ever renders differently.
    static let iconWidth: CGFloat = 18
    static let iconGap: CGFloat = 4

    /// Allowance for everybody else's status items. Nothing can measure them —
    /// Apple documents no API for it and warns against predicting status item
    /// position — so this is a deliberate constant, not a fake calculation.
    private static let otherItemsReserve: CGFloat = 200

    /// Never shrink below this: a lyric narrower than this is unreadable, and at
    /// that point the user should pick Compact rather than have the app guess.
    private static let floorTextWidth: CGFloat = 80

    /// The screen that owns the menu bar.
    ///
    /// Deliberately NOT `NSScreen.main` — that is the screen with the *key
    /// window*, so it follows whichever app the user focuses. On a multi-display
    /// setup it flips between displays of different widths, and the box would
    /// resize under the user for no reason they could see. The menu bar lives on
    /// `screens.first`.
    static var menuBarScreen: NSScreen? { NSScreen.screens.first }

    /// Width of the strip status items actually occupy. On a notched Mac that is
    /// exactly the region to the right of the notch — the system reports it, and
    /// it is the only hard bound available. Elsewhere the menu titles own the left
    /// side, so fall back to a share of the width.
    static func statusStripWidth(for screen: NSScreen? = menuBarScreen) -> CGFloat {
        guard let screen else { return LyricWidth.standard.points + iconWidth + iconGap }
        return screen.auxiliaryTopRightArea?.width ?? (screen.frame.width * 0.45)
    }

    /// Room the lyric may claim: the strip, less what is left for other items.
    /// The preference can only be clamped DOWN by the display, never widened
    /// behind the user's back.
    static func availableTextWidth(for screen: NSScreen? = menuBarScreen) -> CGFloat {
        max(floorTextWidth, statusStripWidth(for: screen) - otherItemsReserve - iconWidth - iconGap)
    }

    /// The lyric text area inside the box.
    static func textWidth(_ preference: LyricWidth, screen: NSScreen? = menuBarScreen) -> CGFloat {
        min(preference.points, availableTextWidth(for: screen))
    }

    /// The whole fixed box: icon, gap, and the lyric area.
    static func boxWidth(_ preference: LyricWidth, screen: NSScreen? = menuBarScreen) -> CGFloat {
        iconWidth + iconGap + textWidth(preference, screen: screen)
    }

    /// How many characters of ordinary lyric text the box holds, for display in
    /// the width menu. A readout, never a layout input — see the note above.
    static func typicalCharacters(inTextWidth width: CGFloat) -> Int {
        let em = textWidth("Was the sky so grey at dawn") / 31
        guard em > 0 else { return 0 }
        return Int((width / em).rounded(.down))
    }
}

// MARK: - Width bands
//
// Coverage measured over the Beatles corpus: 120pt shows 32.0% of lines whole,
// 280pt shows 90.5%, 360pt shows 97.9%. Anything past ~360 buys almost nothing
// and costs menu bar the user cannot get back. Lines that still do not fit are
// split by `LyricReflow`, not truncated.

enum LyricWidth: String, CaseIterable, Sendable {
    case compact, standard, wide

    var points: CGFloat {
        switch self {
        case .compact:  120
        case .standard: 280
        case .wide:     360
        }
    }

    var title: String {
        switch self {
        case .compact:  "Compact"
        case .standard: "Standard"
        case .wide:     "Wide"
        }
    }
}
