import Foundation
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

    // MARK: Published, read by the menu bar

    /// The lyric line (or a placeholder) shown next to the icon. Empty => icon only.
    private(set) var lineText: String = ""
    /// Menu header: what is playing, or why nothing shows. Never lyric text.
    private(set) var header: String = "Starting…"
    /// Mirrors the login-item registration so the menu toggle reflects reality.
    private(set) var loginEnabled: Bool = LoginItem.isEnabled
    /// Whether lyric updates are paused.
    private(set) var isPaused: Bool = false

    /// Character budget for the menu bar; the label truncates natively to fit.
    private(set) var maxChars: Int
    /// Poll interval in seconds.
    private(set) var tickInterval: Double

    /// Reserved width for the lyric text, from the chosen character count at the
    /// menu bar font's rough average width per character.
    var menuWidth: CGFloat { CGFloat(maxChars) * 7.0 }

    // MARK: Internals (not part of the observable UI surface)

    @ObservationIgnored private let bridges: [PlaybackBridge] = [SpotifyBridge(), MusicBridge()]
    @ObservationIgnored private let lrclib = LRCLibClient()

    @ObservationIgnored private var activeBridge: PlaybackBridge?
    @ObservationIgnored private var lines: [LyricLine] = []
    @ObservationIgnored private var currentTrackID: String?
    @ObservationIgnored private var shownIndex = -1

    @ObservationIgnored private var lastSnapshot: NowPlaying?
    @ObservationIgnored private var lastPosition: Double?
    @ObservationIgnored private var lastPositionAt: Date?
    @ObservationIgnored private var tickCount = 0

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?

    private var gapPlaceholder: String { "♪" }

    private enum Keys {
        static let width = "maxChars"
        static let tick = "tickInterval"
    }

    init() {
        let storedWidth = UserDefaults.standard.integer(forKey: Keys.width)
        maxChars = [40, 48, 60, 80].contains(storedWidth) ? storedWidth : 48
        let storedTick = UserDefaults.standard.double(forKey: Keys.tick)
        tickInterval = [0.2, 0.5, 1.0].contains(storedTick) ? storedTick : 0.5
        if !Self.isRunningTests { start() }
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
            return
        }

        if snap.trackID != currentTrackID {
            currentTrackID = snap.trackID
            clear()
            header = "\(snap.title) — \(snap.artist)"
            loadLyrics(for: snap)
            return
        }

        // Paused, or no synced lyrics: nothing can change on the fine tick, so
        // skip the position round-trip. Also drop the extrapolation base so a
        // later resume doesn't briefly extrapolate across the paused gap.
        guard snap.state == .playing, !lines.isEmpty else {
            lastPosition = nil
            lastPositionAt = nil
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

        // Instrumental gaps (the intro, or a bare-timestamp line) show a steady
        // placeholder rather than an empty title, so the item keeps its width.
        guard let idx = LRCParser.index(at: pos, in: lines) else {
            if shownIndex != -1 { shownIndex = -1; lineText = gapPlaceholder }
            return
        }
        if idx != shownIndex {
            shownIndex = idx
            let text = lines[idx].text
            lineText = text.isEmpty ? gapPlaceholder : text
        }
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
        lastPosition = nil
        lastPositionAt = nil
        shownIndex = -1
        lineText = ""
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
                    self.shownIndex = -1
                    if !self.isPaused { self.header = "\(title) — \(artist)" }
                    return
                case .unavailable:
                    self.lines = []
                    self.shownIndex = -1
                    if !self.isPaused {
                        self.lineText = ""
                        self.header = "No synced lyrics found"
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
        } else {
            // Pausing overwrote the header with "Paused". The track hasn't
            // changed, so tick()'s track-change branch won't rebuild it — restore
            // it now from the last snapshot so the menu doesn't read "Paused"
            // while lyrics scroll. Then drop the snapshot to force an immediate
            // re-probe and redraw, which also corrects the header if the track
            // changed while paused.
            shownIndex = -1
            lastPosition = nil
            lastPositionAt = nil
            if let snap = lastSnapshot {
                header = "\(snap.title) — \(snap.artist)"
            }
            lastSnapshot = nil
        }
    }

    func setMaxChars(_ n: Int) {
        maxChars = n
        UserDefaults.standard.set(n, forKey: Keys.width)
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
