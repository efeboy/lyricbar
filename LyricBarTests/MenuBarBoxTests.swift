import Testing
import SwiftUI
import AppKit
@testable import LyricBar

@Suite("Menu bar box")
@MainActor
struct MenuBarBoxTests {

    private static let box: CGFloat = 280

    private func renderedWidth(_ text: String,
                               opacity: Double = 1.0,
                               box: CGFloat = MenuBarBoxTests.box) -> CGFloat {
        LyricImage.render(text: text, boxWidth: box, alpha: opacity).size.width
    }

    private static let states: [(name: String, text: String, state: PlaybackModel.DisplayState)] = [
        ("playing/long",  "Was the sky so grey at dawn that the rain would find its way?", .playing),
        ("playing/short", "Girl", .playing),
        ("instrumental",  "♪", .instrumental),
        ("noLyrics",      "♪", .noLyrics),
        ("paused",        "♪", .paused),
        ("idle",          "♪", .idle),
        ("empty/guard",   "", .idle),
    ]

    @Test("Every state renders at exactly the same width")
    func constantAcrossStates() {
        let widths = Self.states.map { renderedWidth($0.text, opacity: $0.state.opacity) }

        #expect(Set(widths).count == 1,
                "states differed: \(zip(Self.states.map(\.name), widths).map { "\($0)=\($1)" })")
    }

    @Test("An empty lyric occupies the full box")
    func emptyStillFillsBox() {
        #expect(renderedWidth("") == renderedWidth("Girl"))
    }

    @Test("An over-wide line cannot widen the box")
    func overflowCannotGrowBox() {
        let huge = String(repeating: "Wonderwall ", count: 40)

        #expect(renderedWidth(huge) == Self.box)
    }

    @Test("Width is independent of the lyric", arguments: [
        "Was the sky so grey at dawn",
        "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
        "iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii",
        "♪",
        "",
    ])
    func widthIgnoresContent(text: String) {
        #expect(renderedWidth(text) == Self.box)
    }

    @Test("The rendered image is exactly one menu bar tall")
    func imageMatchesBarHeight() {
        let image = LyricImage.render(text: "Girl", boxWidth: Self.box, alpha: 1)

        #expect(image.size.height == NSStatusBar.system.thickness)
        #expect(image.isTemplate)
    }

    @Test("A line that fits keeps the full menu bar font size")
    func shortLineKeepsBaseFont() {
        #expect(LyricImage.fittedFontSize(for: "Girl", boxWidth: Self.box)
                == MenuBarMetrics.baseFontSize)
        #expect(LyricImage.fittedFontSize(for: "", boxWidth: Self.box)
                == MenuBarMetrics.baseFontSize)
    }

    @Test("An over-wide line shrinks rather than overflowing", arguments: [80.0, 120.0, 250.0])
    func shrinksToFit(box: CGFloat) {
        let line = "Was the sky so grey at dawn that the rain would find its way?"
        let size = LyricImage.fittedFontSize(for: line, boxWidth: box)

        #expect(size < MenuBarMetrics.baseFontSize)
        #expect(size >= MenuBarMetrics.minimumFontSize)
    }

    @Test("The box is the resolved band, clamped by the measured fit")
    func boxMatchesMetrics() {
        #expect(MenuBarMetrics.boxWidth(.standard, fittedWidth: 600) == LyricWidth.standard.points)
        #expect(MenuBarMetrics.boxWidth(.standard, fittedWidth: 200) == 200)
        #expect(MenuBarMetrics.boxWidth(.fill, fittedWidth: 250) == 250)
        #expect(MenuBarMetrics.boxWidth(.fill, fittedWidth: 250).isFinite)
    }

    @Test("The preference is never widened by the display", arguments: LyricWidth.allCases)
    func preferenceIsOnlyClamped(width: LyricWidth) {
        #expect(MenuBarMetrics.boxWidth(width, fittedWidth: 250) <= width.points)
    }

    @Test("The box never collapses below the readable floor", arguments: [0.0, 1.0, 40.0])
    func floorHolds(fitted: CGFloat) {
        #expect(MenuBarMetrics.boxWidth(.fill, fittedWidth: fitted)
                == MenuBarMetrics.minimumBoxWidth)
    }

    @Test("The widest box leaves room for the padding AppKit adds")
    func widestBoxLeavesPadding() throws {
        let strip = MenuBarMetrics.statusStripWidth()
        try #require(strip > MenuBarMetrics.minimumBoxWidth + MenuBarMetrics.systemItemPadding)

        #expect(MenuBarMetrics.widestBox() + MenuBarMetrics.systemItemPadding <= strip)
    }
}
