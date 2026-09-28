import Testing
import Foundation
@testable import LyricBar

@MainActor
private final class FakeBridge: PlaybackBridge {
    nonisolated let source: PlaybackSource
    var next: BridgeSnapshot = .unavailable
    var positionValue: Double?

    init(source: PlaybackSource) { self.source = source }

    func snapshot() async -> BridgeSnapshot { next }
    func position() async -> Double? { positionValue }
}

private struct FakeLyrics: LyricsProvider {
    let result: LyricsFetchResult

    func fetch(title: String, artist: String, album: String, duration: Double) async
    -> LyricsFetchResult { result }
}

private func track(_ id: String,
                   title: String = "Girl",
                   state: PlayerState = .playing,
                   source: PlaybackSource = .spotify) -> BridgeSnapshot {
    .now(NowPlaying(source: source, state: state, trackID: id, title: title,
                    artist: "The Beatles", album: "Rubber Soul", durationSeconds: 152))
}

@Suite("Playback model")
@MainActor
struct PlaybackModelTests {

    private static let suiteName = "net.local.lyricbar.model-tests"

    private func makeModel(bridges: [PlaybackBridge],
                           lyrics: LyricsFetchResult = .unavailable) -> PlaybackModel {
        let defaults = UserDefaults(suiteName: Self.suiteName) ?? .standard
        defaults.removePersistentDomain(forName: Self.suiteName)
        MenuBarFit.store(MenuBarFit.Fit(boxWidth: 300, rightEdge: 1000),
                         for: MenuBarFit.signature(), in: defaults)
        return PlaybackModel(defaults: defaults, bridges: bridges,
                             lyrics: FakeLyrics(result: lyrics))
    }

    private let lines = [
        LyricLine(time: 10, text: "first"),
        LyricLine(time: 20, text: "second"),
        LyricLine(time: 30, text: "third"),
    ]

    @Test("Nothing playing reads as idle, and the box does not move")
    func idleWhenNothingPlays() async {
        let model = makeModel(bridges: [FakeBridge(source: .spotify)])

        await model.refreshNow()

        #expect(model.displayState == .idle)
        #expect(model.lineText == "♪")
        #expect(model.boxWidth == model.lyricBoxWidth)
    }

    @Test("A refused Automation prompt is reported, not silently ignored")
    func automationDenialIsSurfaced() async {
        let spotify = FakeBridge(source: .spotify)
        spotify.next = .denied
        let model = makeModel(bridges: [spotify])

        await model.refreshNow()

        #expect(model.displayState == .denied)
        #expect(model.trackTitle == "Automation access denied")
        #expect(model.trackSubtitle.contains("Automation"))
        #expect(model.lineText != "♪")
        #expect(model.displayState.opacity == 1.0)
    }

    @Test("One denied source does not mask another that is playing")
    func denialIgnoredWhenSomethingElsePlays() async {
        let spotify = FakeBridge(source: .spotify)
        spotify.next = .denied
        let music = FakeBridge(source: .appleMusic)
        music.next = track("m1", title: "Blackbird", source: .appleMusic)
        let model = makeModel(bridges: [spotify, music])

        await model.refreshNow()

        #expect(model.displayState != .denied)
        #expect(model.trackTitle == "Blackbird")
    }

    @Test("A new track reports loading while the fetch is still in flight")
    func loadingBeforeTheFetchLands() async {
        let spotify = FakeBridge(source: .spotify)
        spotify.next = track("s1")
        let model = makeModel(bridges: [spotify], lyrics: .synced(lines))

        await model.refreshNow()

        #expect(model.displayState == .loading)
        #expect(model.header == "Loading lyrics…")
        #expect(model.trackTitle == "Girl")
        #expect(model.boxWidth == model.lyricBoxWidth)
    }

    @Test("No-lyrics is only reported once the fetch has actually resolved")
    func noLyricsOnlyAfterTheFetch() async {
        let spotify = FakeBridge(source: .spotify)
        spotify.next = track("s1")
        let model = makeModel(bridges: [spotify], lyrics: .unavailable)

        await model.refreshNow()
        #expect(model.displayState == .loading)

        await model.awaitPendingLyrics()

        #expect(model.displayState == .noLyrics)
        #expect(model.header == "No synced lyrics found")
        #expect(model.boxWidth == model.lyricBoxWidth)
    }

    @Test("Once lyrics land, the line at the playhead is what shows")
    func lyricsFollowThePlayhead() async {
        let spotify = FakeBridge(source: .spotify)
        spotify.next = track("s1")
        let model = makeModel(bridges: [spotify], lyrics: .synced(lines))

        await model.refreshNow()
        await model.awaitPendingLyrics()
        spotify.positionValue = 25
        await model.refreshNow()

        #expect(model.displayState == .playing)
        #expect(model.lineText == "second")
        #expect(model.currentLine == "second")
        #expect(model.nextLine == "third")
        #expect(model.boxWidth == model.lyricBoxWidth)
    }

    @Test("The intro before the first timestamp is instrumental, and holds the box")
    func introIsInstrumental() async {
        let spotify = FakeBridge(source: .spotify)
        spotify.next = track("s1")
        let model = makeModel(bridges: [spotify], lyrics: .synced(lines))

        await model.refreshNow()
        await model.awaitPendingLyrics()
        spotify.positionValue = 2
        await model.refreshNow()

        #expect(model.displayState == .instrumental)
        #expect(model.boxWidth == model.lyricBoxWidth)
    }

    @Test("Spotify wins when both apps are playing")
    func spotifyWinsTies() async {
        let spotify = FakeBridge(source: .spotify)
        spotify.next = track("s1", title: "Girl")
        let music = FakeBridge(source: .appleMusic)
        music.next = track("m1", title: "Blackbird", source: .appleMusic)
        let model = makeModel(bridges: [spotify, music])

        await model.refreshNow()

        #expect(model.trackTitle == "Girl")
    }

    @Test("A paused source still shows its track")
    func pausedSourceStillShows() async {
        let spotify = FakeBridge(source: .spotify)
        spotify.next = track("s1", state: .paused)
        let model = makeModel(bridges: [spotify], lyrics: .synced(lines))

        await model.refreshNow()
        await model.awaitPendingLyrics()
        await model.refreshNow()

        #expect(model.displayState == .paused)
        #expect(model.trackTitle == "Girl")
        #expect(model.boxWidth == model.lyricBoxWidth)
    }

    @Test("Hiding lyrics freezes the item and restores the header when shown again")
    func hideAndShow() async {
        let spotify = FakeBridge(source: .spotify)
        spotify.next = track("s1")
        let model = makeModel(bridges: [spotify], lyrics: .synced(lines))

        await model.refreshNow()
        await model.awaitPendingLyrics()

        model.isHidden = true
        #expect(model.displayState == .paused)
        #expect(model.header == "Lyrics hidden")

        spotify.positionValue = 25
        await model.refreshNow()
        #expect(model.displayState == .paused)

        model.isHidden = false
        #expect(model.header == "Girl — The Beatles")
    }

    @Test("Hiding clears the lyric rather than leaving a stale one on screen")
    func hidingClearsTheLyric() async {
        let spotify = FakeBridge(source: .spotify)
        spotify.next = track("s1")
        let model = makeModel(bridges: [spotify], lyrics: .synced(lines))

        spotify.positionValue = 25
        await model.refreshNow()
        await model.awaitPendingLyrics()
        await model.refreshNow()
        try? #require(model.lineText == "second")

        model.isHidden = true

        #expect(!model.displayState.holdsLyric)
        #expect(model.lineText == "♪")
        #expect(model.boxWidth == model.lyricBoxWidth)
    }

    @Test("Playback stopping clears the lyric rather than leaving a stale one on screen")
    func stoppingClearsTheLyric() async {
        let spotify = FakeBridge(source: .spotify)
        spotify.next = track("s1")
        let model = makeModel(bridges: [spotify], lyrics: .synced(lines))

        spotify.positionValue = 25
        await model.refreshNow()
        await model.awaitPendingLyrics()
        await model.refreshNow()
        try? #require(model.lineText == "second")

        spotify.next = .unavailable
        await model.refreshNow()

        #expect(model.displayState == .idle)
        #expect(!model.displayState.holdsLyric)
        #expect(model.lineText == "♪")
        #expect(model.boxWidth == model.lyricBoxWidth)
    }

    @Test("A calibration probe never renders a lyric into the probe box")
    func probingShowsThePlaceholder() {
        let lyric = "Somewhere a long train is leaving the station"

        #expect(PlaybackModel.displayText(chunk: lyric, probing: true, state: .playing) == "♪")
        #expect(PlaybackModel.displayText(chunk: lyric, probing: false, state: .playing) == lyric)
    }

    @Test("A state with nothing to say never renders a lyric", arguments: [
        PlaybackModel.DisplayState.noLyrics,
        .paused,
        .idle,
    ])
    func collapsedStatesShowThePlaceholder(state: PlaybackModel.DisplayState) {
        #expect(!state.holdsLyric)
        #expect(PlaybackModel.displayText(chunk: "a stale lyric", probing: false, state: state) == "♪")
    }

    @Test("A denial outranks a stale lyric")
    func denialShowsItsOwnPlaceholder() {
        #expect(PlaybackModel.displayText(chunk: "a stale lyric",
                                          probing: false, state: .denied) == "⚠\u{FE0E}")
    }

    @Test("Lyric-holding states still show the lyric when not probing", arguments: [
        PlaybackModel.DisplayState.playing,
        .instrumental,
        .loading,
    ])
    func lyricStatesShowTheLyric(state: PlaybackModel.DisplayState) {
        #expect(state.holdsLyric)
        #expect(PlaybackModel.displayText(chunk: "second", probing: false, state: state) == "second")
        #expect(PlaybackModel.displayText(chunk: "", probing: false, state: state) == "♪")
    }
}
