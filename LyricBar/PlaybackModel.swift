import Foundation
import AppKit
import CoreGraphics
import Observation

// MARK: - Playback model
//
// The single source of truth the menu bar observes. One async loop drives the
// whole app:
//
//   sleep(tick) → pick active player (Spotify | Music) → track changed?
//                                                      → fetch lyrics (async)
//                 player position ──────────────────────→ index(at:) → lineText
//
// Metadata (track identity, which app is playing) is probed about once a second;
// only `player position` runs at the finer tick, and even that is extrapolated
// between probes. Each AppleScript call is an Apple Event round-trip and is by
// far the dominant cost, so we make as few as possible.

@MainActor
@Observable
final class PlaybackModel {

    // MARK: Published, read by the menu bar and the popover

    /// The lyric chunk (or a placeholder) shown next to the icon. May be empty.
    private(set) var lineText: String = ""
    /// Menu header: what is playing, or why nothing shows. Never lyric text.
    private(set) var header: String = "Starting…"
    /// Mirrors the login-item registration so the menu toggle reflects reality.
    private(set) var loginEnabled: Bool = LoginItem.isEnabled
    /// Whether lyric updates are paused.
    private(set) var isPaused: Bool = false

    /// What the item is currently conveying. Drives the label's opacity so the
    /// three "nothing to show" cases are distinguishable — previously they all
    /// rendered as a bare icon and looked identical.
    private(set) var displayState: DisplayState = .idle

    /// Popover fields. The bridges expose no artwork, so there is no art here.
    private(set) var trackTitle: String = "Nothing playing"
    private(set) var trackArtist: String = ""
    private(set) var trackSubtitle: String = ""
    /// Surrounding context for the popover, taken from the *unsplit* lines —
    /// the popover has room to wrap, so it never shows a half line.
    private(set) var previousLine: String = ""
    private(set) var currentLine: String = ""
    private(set) var nextLine: String = ""

    /// Chosen width band.
    private(set) var widthPreference: LyricWidth
    /// Poll interval in seconds.
    private(set) var tickInterval: Double

    /// Width reserved for the lyric text. Held constant across every state so the
    /// item never resizes and neighbouring status items never shift.
    /// The lyric text area inside the box.
    private(set) var lyricWidth: CGFloat = LyricWidth.standard.points

    /// The whole fixed menu bar box — icon, gap and lyric area. The view pins
    /// this and nothing else; every state renders at exactly this width.
    private(set) var boxWidth: CGFloat =
        MenuBarMetrics.iconWidth + MenuBarMetrics.iconGap + LyricWidth.standard.points

    enum DisplayState {
        case playing, instrumental, noLyrics, paused, idle

        /// Full strength when there is something to read; dimmed when the item is
        /// only reporting that there is not.
        var opacity: Double {
            switch self {
            case .playing, .instrumental, .noLyrics: 1.0
            case .paused:                            0.55
            case .idle:                              0.30
            }
        }
    }

    // MARK: Internals (not part of the observable UI surface)

    @ObservationIgnored private let bridges: [PlaybackBridge] = [SpotifyBridge(), MusicBridge()]
    @ObservationIgnored private let lrclib = LRCLibClient()

    @ObservationIgnored private var activeBridge: PlaybackBridge?
    /// Lines exactly as parsed — what the popover shows.
    @ObservationIgnored private var lines: [LyricLine] = []
    /// The same lines with over-wide ones split to fit `lyricWidth` — what the
    /// menu bar shows. Rebuilt whenever the width changes.
    @ObservationIgnored private var menuLines: [LyricLine] = []
    @ObservationIgnored private var trackDuration: Double = 0
    @ObservationIgnored private var currentTrackID: String?
    @ObservationIgnored private var shownMenuIndex = -1
    @ObservationIgnored private var shownLyricIndex = -2

    @ObservationIgnored private var lastSnapshot: NowPlaying?
    @ObservationIgnored private var lastPosition: Double?
    @ObservationIgnored private var lastPositionAt: Date?
    @ObservationIgnored private var tickCount = 0

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var screenObserver: (any NSObjectProtocol)?

    private var gapPlaceholder: String { "♪" }

    private enum Keys {
        static let width = "lyricWidth"
        static let tick = "tickInterval"
    }

    init() {
        let storedWidth = UserDefaults.standard.string(forKey: Keys.width) ?? ""
        widthPreference = LyricWidth(rawValue: storedWidth) ?? .standard
        let storedTick = UserDefaults.standard.double(forKey: Keys.tick)
        tickInterval = [0.2, 0.5, 1.0].contains(storedTick) ? storedTick : 0.5

        lyricWidth = MenuBarMetrics.textWidth(widthPreference)
        boxWidth = MenuBarMetrics.boxWidth(widthPreference)

        if !Self.isRunningTests {
            observeScreenChanges()
            start()
        }
    }

    /// The unit tests are hosted by this app, so `xcodebuild test` launches it.
    /// Starting the poll loop there would fire Apple Events at Spotify/Music from
    /// a test run — prompting for Automation permission and making results depend
    /// on whatever happens to be playing. The tests cover the pure logic instead,
    /// so the loop simply stays off.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    // MARK: Width
    //
    // Recomputed on display/scaling change and on preference change only — never
    // per line. Auto-sizing per line would shove every neighbouring status item
    // sideways: line-to-line width change averages 67pt and reaches 404pt.

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshWidth() }
        }
    }

    private func refreshWidth() {
        let resolved = MenuBarMetrics.textWidth(widthPreference)
        guard resolved != lyricWidth else { return }
        lyricWidth = resolved
        boxWidth = MenuBarMetrics.boxWidth(widthPreference)
        rebuildMenuLines()
    }

    /// Re-split the parsed lines for the current width.
    private func rebuildMenuLines() {
        menuLines = LyricReflow.expand(lines, trackDuration: trackDuration, width: lyricWidth)
        shownMenuIndex = -1
    }

    // MARK: Poll loop

    private func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(for: .seconds(self.tickInterval))
            }
        }
    }

    private func tick() {
        if isPaused { return }
        tickCount += 1
        let metadataEvery = max(1, Int((1.0 / tickInterval).rounded()))
        let metadataTick = tickCount % metadataEvery == 1 || metadataEvery == 1 || lastSnapshot == nil

        if metadataTick {
            if let (bridge, snap) = pickActive() {
                activeBridge = bridge
                lastSnapshot = snap
            } else {
                activeBridge = nil
                lastSnapshot = nil
            }
        }

        guard let snap = lastSnapshot, let bridge = activeBridge else {
            currentTrackID = nil
            clear()
            header = "Nothing playing"
            trackTitle = "Nothing playing"
            trackArtist = ""
            trackSubtitle = ""
            displayState = .idle
            return
        }

        if snap.trackID != currentTrackID {
            currentTrackID = snap.trackID
            clear()
            trackDuration = snap.durationSeconds
            header = "\(snap.title) — \(snap.artist)"
            trackTitle = snap.title
            trackArtist = snap.artist
            trackSubtitle = snap.album.isEmpty
                ? snap.source.rawValue
                : "\(snap.album) · \(snap.source.rawValue)"
            loadLyrics(for: snap)
            return
        }

        guard snap.state == .playing else {
            // Paused: nothing can change, so skip the position round-trip. Also
            // drop the extrapolation base so a later resume doesn't briefly
            // extrapolate across the paused gap.
            lastPosition = nil
            lastPositionAt = nil
            displayState = .paused
            return
        }

        guard !lines.isEmpty else {
            lastPosition = nil
            lastPositionAt = nil
            displayState = .noLyrics
            return
        }

        let pos: Double
        if metadataTick, let p = bridge.position() {
            pos = p; lastPosition = p; lastPositionAt = Date()
        } else if let lp = lastPosition, let at = lastPositionAt {
            // Playback advances in real time, so extrapolation is exact apart
            // from seeks, which the next probe corrects.
            pos = lp + Date().timeIntervalSince(at)
        } else if let p = bridge.position() {
            pos = p; lastPosition = p; lastPositionAt = Date()
        } else {
            return
        }

        updateMenuLine(at: pos)
        updatePopoverLines(at: pos)
    }

    /// Instrumental gaps (the intro, or a bare-timestamp line) show a steady
    /// placeholder rather than an empty title, so the item keeps its width.
    private func updateMenuLine(at pos: Double) {
        guard let idx = LRCParser.index(at: pos, in: menuLines) else {
            if shownMenuIndex != -1 {
                shownMenuIndex = -1
                lineText = gapPlaceholder
                displayState = .instrumental
            }
            return
        }
        if idx != shownMenuIndex {
            shownMenuIndex = idx
            let text = menuLines[idx].text
            lineText = text.isEmpty ? gapPlaceholder : text
            displayState = text.isEmpty ? .instrumental : .playing
        }
    }

    private func updatePopoverLines(at pos: Double) {
        let idx = LRCParser.index(at: pos, in: lines) ?? -1
        guard idx != shownLyricIndex else { return }
        shownLyricIndex = idx
        previousLine = idx > 0 ? lines[idx - 1].text : ""
        currentLine = idx >= 0 ? lines[idx].text : ""
        nextLine = (idx >= 0 && idx + 1 < lines.count) ? lines[idx + 1].text : ""
    }

    /// Prefer a source that is actively playing; fall back to a paused one so a
    /// paused track still shows its header. Spotify wins ties (listed first).
    private func pickActive() -> (PlaybackBridge, NowPlaying)? {
        var pausedHit: (PlaybackBridge, NowPlaying)?
        for bridge in bridges {
            guard let snap = bridge.snapshot() else { continue }
            if snap.state == .playing { return (bridge, snap) }
            if pausedHit == nil { pausedHit = (bridge, snap) }
        }
        return pausedHit
    }

    private func clear() {
        lines = []
        menuLines = []
        lastPosition = nil
        lastPositionAt = nil
        shownMenuIndex = -1
        shownLyricIndex = -2
        lineText = ""
        previousLine = ""
        currentLine = ""
        nextLine = ""
    }

    // MARK: Lyric fetch
    //
    // Bound to a single Task per track. On a 503 the task sleeps and retries the
    // SAME track in a loop — so a track that starts during a backoff window is no
    // longer permanently starved of lyrics (the old bug where the retry was
    // pinned to whichever track was current when the 503 arrived).

    private func loadLyrics(for snap: NowPlaying) {
        fetchTask?.cancel()
        let id = snap.trackID
        let title = snap.title, artist = snap.artist
        let album = snap.album, duration = snap.durationSeconds

        fetchTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let result = await self.lrclib.fetch(
                    title: title, artist: artist, album: album, duration: duration)
                if Task.isCancelled { return }
                guard id == self.currentTrackID else { return }   // track moved on

                // A fetch that lands while paused still stores its lines so they
                // are ready on resume, but must not touch the header/lineText —
                // that would clobber the "Paused" header the toggle just set.
                switch result {
                case .synced(let l):
                    self.lines = l
                    self.rebuildMenuLines()
                    self.shownLyricIndex = -2
                    if !self.isPaused { self.header = "\(title) — \(artist)" }
                    return
                case .unavailable:
                    self.lines = []
                    self.menuLines = []
                    self.shownMenuIndex = -1
                    if !self.isPaused {
                        self.lineText = ""
                        self.header = "No synced lyrics found"
                        self.displayState = .noLyrics
                    }
                    return
                case .retry(let after):
                    // Server is shedding load; back off, then retry this track.
                    try? await Task.sleep(for: .seconds(after + 0.5))
                }
            }
        }
    }

    // MARK: Menu actions

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            lineText = ""
            header = "Paused"
            displayState = .paused
        } else {
            // Pausing overwrote the header with "Paused". The track hasn't
            // changed, so tick()'s track-change branch won't rebuild it — restore
            // it now from the last snapshot so the menu doesn't read "Paused"
            // while lyrics scroll. Then drop the snapshot to force an immediate
            // re-probe and redraw, which also corrects the header if the track
            // changed while paused.
            shownMenuIndex = -1
            shownLyricIndex = -2
            lastPosition = nil
            lastPositionAt = nil
            if let snap = lastSnapshot {
                header = "\(snap.title) — \(snap.artist)"
            }
            lastSnapshot = nil
        }
    }

    func setWidth(_ w: LyricWidth) {
        widthPreference = w
        UserDefaults.standard.set(w.rawValue, forKey: Keys.width)
        lyricWidth = MenuBarMetrics.textWidth(w)
        boxWidth = MenuBarMetrics.boxWidth(w)
        rebuildMenuLines()
    }

    func setTickInterval(_ v: Double) {
        tickInterval = v
        UserDefaults.standard.set(v, forKey: Keys.tick)
    }

    func refreshLoginState() {
        loginEnabled = LoginItem.isEnabled
    }

    /// Registers/unregisters the login item, then snaps the toggle back to the
    /// real system state whether or not the change succeeded.
    func setLogin(_ on: Bool) {
        try? LoginItem.setEnabled(on)
        loginEnabled = LoginItem.isEnabled
    }
}
