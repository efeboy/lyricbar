import Testing
import SwiftUI
import AppKit
@testable import LyricBar

// The menu bar item must be ONE FIXED BOX: neighbouring status items shift, and
// can be pushed out of reach entirely, if its width tracks the lyric. This is the
// regression these tests exist for — an earlier build sized the inner Text and
// let the HStack add itself up, which left the total at the mercy of the icon's
// own metrics and of whichever screen `NSScreen.main` happened to point at.
//
// `fittingSize` is what AppKit hands the status item, so it is the honest thing
// to assert on.

@Suite("Menu bar box")
@MainActor
struct MenuBarBoxTests {

    private func renderedWidth(_ text: String,
                               opacity: Double = 1.0,
                               box: CGFloat = 302) -> CGFloat {
        NSHostingView(rootView: LyricLabel(text: text, boxWidth: box, opacity: opacity))
            .fittingSize.width
    }

    /// Every state the item can be in, with the opacity it actually renders at.
    private static let states: [(name: String, text: String, state: PlaybackModel.DisplayState)] = [
        ("playing/long",  "Was the sky so grey at dawn that the rain would find its way?", .playing),
        ("playing/short", "Girl", .playing),
        ("instrumental",  "♪", .instrumental),
        ("noLyrics",      "", .noLyrics),
        ("paused",        "", .paused),
        ("idle",          "", .idle),
    ]

    @Test("Every state renders at exactly the same width")
    func constantAcrossStates() {
        let widths = Self.states.map {
            renderedWidth($0.text, opacity: $0.state.opacity)
        }

        #expect(Set(widths).count == 1, "states differed: \(zip(Self.states.map(\.name), widths).map { "\($0)=\($1)" })")
    }

    // An empty lyric must still occupy the box — collapsing to the icon alone
    // would let every neighbour slide sideways whenever lyrics stop.
    @Test("An empty lyric occupies the full box")
    func emptyStillFillsBox() {
        #expect(renderedWidth("") == renderedWidth("Girl"))
    }

    // Lyric content is the one thing that must never reach the geometry.
    @Test("Width is independent of the lyric", arguments: [
        "Was the sky so grey at dawn",
        "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
        "iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii",
        "♪",
        "",
    ])
    func widthIgnoresContent(text: String) {
        #expect(renderedWidth(text) == 302)
    }

    @Test("The box is exactly icon + gap + lyric area")
    func boxMatchesMetrics() {
        let text = MenuBarMetrics.textWidth(LyricWidth.standard)
        let box = MenuBarMetrics.boxWidth(LyricWidth.standard)

        #expect(box == MenuBarMetrics.iconWidth + MenuBarMetrics.iconGap + text)
        #expect(renderedWidth("Girl", box: box) == box)
    }

    // The display may only ever clamp the preference DOWN. Widening it behind the
    // user's back would claim menu bar they never agreed to give up.
    @Test("The preference is never widened by the display", arguments: LyricWidth.allCases)
    func preferenceIsOnlyClamped(width: LyricWidth) {
        #expect(MenuBarMetrics.textWidth(width) <= width.points)
    }
}
