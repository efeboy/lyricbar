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

    @Test("The ladder climbs in even steps from narrowest to widest")
    func ladderIsEven() {
        let rungs = WidthLadder.rungs

        #expect(rungs == rungs.sorted())
        #expect(zip(rungs, rungs.dropFirst()).allSatisfy { $1 - $0 == WidthLadder.step })
        #expect(rungs.contains(WidthLadder.defaultRung))
    }

    @Test("Rungs wider than the room beside the notch are left out")
    func ladderHidesRungsThatDoNotFit() {
        #expect(WidthLadder.available(widest: 755) == WidthLadder.rungs)
        #expect(WidthLadder.available(widest: 300) == [160, 200, 240, 280])
    }

    @Test("A screen too narrow for any rung still offers the narrowest")
    func ladderNeverEmpty() {
        #expect(WidthLadder.available(widest: 100) == [WidthLadder.rungs[0]])
    }

    @Test("A width snaps to the nearest rung that fits", arguments: [
        (CGFloat(250), CGFloat(755), CGFloat(240)),
        (CGFloat(270), CGFloat(755), CGFloat(280)),
        (CGFloat(400), CGFloat(300), CGFloat(280)),
        (CGFloat(0), CGFloat(755), CGFloat(160)),
    ])
    func snapsToRung(width: CGFloat, widest: CGFloat, expected: CGFloat) {
        #expect(WidthLadder.snapped(width, widest: widest) == expected)
    }

    @Test("The old width bands map onto nearby rungs")
    func migratesBands() {
        #expect(WidthLadder.migrated(band: "compact") == 160)
        #expect(WidthLadder.migrated(band: "standard") == 200)
        #expect(WidthLadder.migrated(band: "fill") == 240)
        #expect(WidthLadder.migrated(band: "wide") == nil)
        #expect(WidthLadder.migrated(band: nil) == nil)
    }

    @Test("The widest box leaves room for the padding AppKit adds")
    func widestBoxLeavesPadding() throws {
        let strip = MenuBarMetrics.statusStripWidth()
        try #require(strip > MenuBarMetrics.minimumBoxWidth + MenuBarMetrics.systemItemPadding)

        #expect(MenuBarMetrics.widestBox() + MenuBarMetrics.systemItemPadding <= strip)
    }
}
