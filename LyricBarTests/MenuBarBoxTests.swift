import Testing
import SwiftUI
import AppKit
@testable import LyricBar

@Suite("Menu bar box")
@MainActor
struct MenuBarBoxTests {

    private static let box: CGFloat = 280

    private func drawnWidth(_ text: String,
                            opacity: Double = 1.0,
                            box: CGFloat = MenuBarBoxTests.box) -> CGFloat {
        LyricText.attributed(text: text, boxWidth: box, alpha: opacity).size().width
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

    @Test("Every state's lyric is drawn at a legible size")
    func everyStateStaysLegible() {
        let sizes = Self.states.map { LyricText.fittedFontSize(for: $0.text, boxWidth: Self.box) }
        let illegible = zip(Self.states.map(\.name), sizes)
            .filter { $1 < MenuBarMetrics.minimumFontSize || $1 > MenuBarMetrics.baseFontSize }

        #expect(illegible.isEmpty, "outside the size range: \(illegible.map { "\($0)=\($1)" })")
    }

    @Test("A lyric holds the box open; having none does not", arguments: [
        (PlaybackModel.DisplayState.playing, true),
        (.instrumental, true),
        (.noLyrics, false),
        (.paused, false),
        (.idle, false),
    ])
    func onlyLyricStatesHoldTheBox(state: PlaybackModel.DisplayState, holds: Bool) {
        #expect(state.holdsLyric == holds)
    }

    @Test("The placeholder box stays comfortably clickable but far narrower")
    func placeholderCollapses() {
        let placeholder = MenuBarMetrics.placeholderBoxWidth(for: "♪")

        #expect(placeholder >= MenuBarMetrics.minimumPlaceholderWidth)
        #expect(placeholder < MenuBarMetrics.minimumBoxWidth)
        #expect(drawnWidth("♪", box: placeholder) <= placeholder)

    }

    @Test("An instrumental gap keeps the full box, so a song cannot make it flicker")
    func instrumentalDoesNotCollapse() {
        #expect(PlaybackModel.DisplayState.instrumental.holdsLyric)
        #expect(PlaybackModel.DisplayState.playing.holdsLyric)
    }

    @Test("The lyric is centered, and clipped rather than ellipsized")
    func centeredAndNeverEllipsized() throws {
        let drawn = LyricText.attributed(text: "Girl", boxWidth: Self.box, alpha: 1)
        let paragraph = try #require(
            drawn.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)

        #expect(paragraph.alignment == .center)
        #expect(paragraph.lineBreakMode == .byClipping)
    }

    @Test("A line far too wide to shrink into the box bottoms out at the floor")
    func overflowBottomsOutAtTheFloor() {
        let huge = String(repeating: "Wonderwall ", count: 40)

        #expect(LyricText.fittedFontSize(for: huge, boxWidth: Self.box)
                == MenuBarMetrics.minimumFontSize)
    }

    @Test("No content shape escapes the size range", arguments: [
        "Was the sky so grey at dawn",
        "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
        "iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii",
        "♪",
        "",
    ])
    func contentStaysWithinTheSizeRange(text: String) {
        let size = LyricText.fittedFontSize(for: text, boxWidth: Self.box)

        #expect(size >= MenuBarMetrics.minimumFontSize)
        #expect(size <= MenuBarMetrics.baseFontSize)
    }

    @Test("A dimmed state reaches the drawn text as a dimmed colour")
    func opacityReachesTheText() throws {
        func alpha(_ opacity: Double) throws -> CGFloat {
            let drawn = LyricText.attributed(text: "Girl", boxWidth: Self.box, alpha: opacity)
            let colour = try #require(
                drawn.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
            return colour.alphaComponent
        }

        let idle = try alpha(PlaybackModel.DisplayState.idle.opacity)
        let playing = try alpha(PlaybackModel.DisplayState.playing.opacity)

        #expect(idle < playing)
        #expect(playing == 1.0)
    }

    @Test("A line that fits keeps the full menu bar font size")
    func shortLineKeepsBaseFont() {
        #expect(LyricText.fittedFontSize(for: "Girl", boxWidth: Self.box)
                == MenuBarMetrics.baseFontSize)
        #expect(LyricText.fittedFontSize(for: "", boxWidth: Self.box)
                == MenuBarMetrics.baseFontSize)
    }

    @Test("An over-wide line shrinks rather than overflowing", arguments: [80.0, 120.0, 250.0])
    func shrinksToFit(box: CGFloat) {
        let line = "Was the sky so grey at dawn that the rain would find its way?"
        let size = LyricText.fittedFontSize(for: line, boxWidth: box)

        #expect(size < MenuBarMetrics.baseFontSize)
        #expect(size >= MenuBarMetrics.minimumFontSize)
    }

    @Test("Fit Menu Bar takes exactly the measured fit, and stays finite")
    func fillTakesTheWholeFit() {
        #expect(MenuBarMetrics.boxWidth(.fill, fittedWidth: 254) == 254)
        #expect(MenuBarMetrics.boxWidth(.fill, fittedWidth: 254).isFinite)
    }

    @Test("No band can claim more menu bar than was measured", arguments: LyricWidth.allCases)
    func neverExceedsTheFit(width: LyricWidth) {
        for fitted in [120.0, 254.0, 600.0] {
            #expect(MenuBarMetrics.boxWidth(width, fittedWidth: fitted)
                    <= max(fitted, MenuBarMetrics.minimumBoxWidth))
        }
    }

    @Test("Every band is a distinct width, on a crowded bar as much as a roomy one",
          arguments: [254.0, 400.0, 600.0, 756.0])
    func bandsStayDistinct(fitted: CGFloat) {
        let widths = LyricWidth.allCases.map { MenuBarMetrics.boxWidth($0, fittedWidth: fitted) }

        #expect(Set(widths).count == LyricWidth.allCases.count, "collapsed to \(widths)")
        #expect(widths == widths.sorted())
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
