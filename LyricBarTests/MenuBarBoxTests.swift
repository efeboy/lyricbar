import Testing
import SwiftUI
import AppKit
@testable import LyricBar

@Suite("Menu bar box")
@MainActor
struct MenuBarBoxTests {

    private static let box: CGFloat = 280

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
    func onlyLyricStatesRenderALyric(state: PlaybackModel.DisplayState, holds: Bool) {
        #expect(state.holdsLyric == holds)
    }

    @Test("An instrumental gap still counts as a lyric state")
    func instrumentalRendersAsALyricState() {
        #expect(PlaybackModel.DisplayState.instrumental.holdsLyric)
        #expect(PlaybackModel.DisplayState.playing.holdsLyric)
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

    @Test("Dimmed states rank below playing, which stays full strength")
    func dimmedStatesRankBelowPlaying() {
        let idle = PlaybackModel.DisplayState.idle.opacity
        let paused = PlaybackModel.DisplayState.paused.opacity
        let playing = PlaybackModel.DisplayState.playing.opacity

        #expect(idle < paused)
        #expect(paused < playing)
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
