import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class PlaybackModel {

    var lineText: String {
        PlaybackModel.displayText(chunk: chunk,
                                  probing: fit.probeWidth != nil,
                                  state: displayState)
    }

    static func displayText(chunk: String, probing: Bool, state: DisplayState) -> String {
        guard !probing, state.holdsLyric, !chunk.isEmpty else {
            return state == .denied ? deniedPlaceholder : gapPlaceholder
        }
        return chunk
    }

    private(set) var header = PlaybackModel.startingHeader
    private(set) var displayState = DisplayState.idle
    private(set) var trackTitle = PlaybackModel.idleTitle
    private(set) var trackArtist = ""
    private(set) var trackSubtitle = ""
    private(set) var previousLine = ""
    private(set) var currentLine = ""
    private(set) var nextLine = ""

    var boxWidth: CGFloat {
        fit.probeWidth ?? lyricBoxWidth
    }

    var fittedWidth: CGFloat { fit.fittedWidth }

    private(set) var lyricBoxWidth: CGFloat

    var widthPreference: LyricWidth {
        get { storedWidth }
        set {
            guard newValue != storedWidth else { return }
            storedWidth = newValue
            defaults.set(newValue.rawValue, forKey: Keys.width)
            applyFittedWidth()
        }
    }

    var isHidden: Bool {
        get { hidden }
        set {
            guard newValue != hidden else { return }
            hidden = newValue
            newValue ? enterHidden() : leaveHidden()
        }
    }

    var loginEnabled: Bool {
        get { loginRegistered }
        set {
            try? LoginItem.setEnabled(newValue)
            loginRegistered = LoginItem.isEnabled
        }
    }

    var loginSupported: Bool { LoginItem.isSupported }

    enum DisplayState: String, Equatable {
        case playing, instrumental, loading, noLyrics, paused, idle, denied

        var opacity: Double {
            switch self {
            case .playing, .instrumental, .noLyrics, .denied: 1.0
            case .loading, .paused:                           0.55
            case .idle:                                       0.30
            }
        }

        var holdsLyric: Bool {
            switch self {
            case .playing, .instrumental, .loading:   true
            case .noLyrics, .paused, .idle, .denied:  false
            }
        }
    }

    private var chunk = ""
    private var storedWidth: LyricWidth
    private var hidden = false
    private var loginRegistered = LoginItem.isEnabled

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock = ContinuousClock()
    @ObservationIgnored private let bridges: [PlaybackBridge]
    @ObservationIgnored private let lyrics: any LyricsProvider
    @ObservationIgnored private let fit: FitCoordinator

    @ObservationIgnored private var activeBridge: PlaybackBridge?
    @ObservationIgnored private var lines: [LyricLine] = []
    @ObservationIgnored private var menuLines: [LyricLine] = []
    @ObservationIgnored private var trackDuration: Double = 0
    @ObservationIgnored private var currentTrackID: String?
    @ObservationIgnored private var shownMenuLine: Shown?
    @ObservationIgnored private var shownLyricLine: Shown?
    @ObservationIgnored private var fetching = false
    @ObservationIgnored private var automationDenied = false

    @ObservationIgnored private var lastSnapshot: NowPlaying?
    @ObservationIgnored private var positionSample: (position: Double, at: ContinuousClock.Instant)?
    @ObservationIgnored private var lastMetadataProbe: ContinuousClock.Instant?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?

    private static let gapPlaceholder = "♪"
    private static let deniedPlaceholder = "⚠\u{FE0E}"
    private static let startingHeader = "Starting…"
    private static let idleTitle = "Nothing playing"
    private static let hiddenHeader = "Lyrics hidden"
    private static let loadingHeader = "Loading lyrics…"
    private static let noLyricsHeader = "No synced lyrics found"
    private static let deniedTitle = "Automation access denied"
    private static let deniedDetail = "LyricBar cannot read Spotify or Music"
    private static let deniedHint = "Privacy & Security → Automation"
    private static let tickInterval: Double = 0.5
    private static let metadataInterval: Double = 1

    private enum Keys {
        static let width = "lyricWidth"
    }

    init(defaults: UserDefaults = .standard,
         bridges: [PlaybackBridge] = [SpotifyBridge(), MusicBridge()],
         lyrics: any LyricsProvider = LRCLibClient()) {
        self.defaults = defaults
        self.bridges = bridges
        self.lyrics = lyrics

        let width = LyricWidth(rawValue: defaults.string(forKey: Keys.width) ?? "") ?? .fill
        let fit = FitCoordinator(defaults: defaults)

        self.fit = fit
        storedWidth = width
        lyricBoxWidth = MenuBarMetrics.boxWidth(width, fittedWidth: fit.fittedWidth)
        fit.onRefit = { [weak self] refit in self?.handleRefit(refit) }
    }

    func start() {
        fit.observeScreenChanges()
        startPolling()

        if let cached = fit.launchFit {
            FitLog.calibration.notice("""
                cacheHit signature=\(MenuBarFit.signature(), privacy: .public) \
                box=\(FitLog.points(cached.boxWidth), privacy: .public) \
                rightEdge=\(FitLog.points(cached.rightEdge), privacy: .public) \
                lyricBox=\(FitLog.points(self.lyricBoxWidth), privacy: .public) \
                preference=\(self.storedWidth.rawValue, privacy: .public)
                """)
        } else {
            FitLog.calibration.notice("""
                cacheMiss signature=\(MenuBarFit.signature(), privacy: .public) \
                preference=\(self.storedWidth.rawValue, privacy: .public)
                """)
            fit.calibrate(reason: .launchNoCache)
        }
    }

    func refreshNow() async {
        lastMetadataProbe = nil
        await tick()
    }

    func awaitPendingLyrics() async {
        await fetchTask?.value
    }

    func refreshLoginState() {
        loginRegistered = LoginItem.isEnabled
    }

    func openAutomationSettings() {
        guard let url = URL(string: Self.automationSettingsURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private static let automationSettingsURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

    private func applyFittedWidth() {
        lyricBoxWidth = MenuBarMetrics.boxWidth(storedWidth, fittedWidth: fittedWidth)
        rebuildMenuLines()
    }

    private func rebuildMenuLines() {
        menuLines = LyricReflow.expand(lines, trackDuration: trackDuration, width: lyricBoxWidth)
        shownMenuLine = nil
    }

    private func handleRefit(_ refit: FitCoordinator.Refit) {
        applyFittedWidth()
        switch refit {
        case .calibrated(let reason):
            FitLog.calibration.notice("""
                applied reason=\(reason.rawValue, privacy: .public) \
                fittedWidth=\(FitLog.points(self.fittedWidth), privacy: .public) \
                preference=\(self.storedWidth.rawValue, privacy: .public) \
                lyricBox=\(FitLog.points(self.lyricBoxWidth), privacy: .public) \
                menuLines=\(self.menuLines.count, privacy: .public)
                """)
        case .restoredFromCache:
            FitLog.calibration.notice("""
                screenChangeCacheHit \
                box=\(FitLog.points(self.fittedWidth), privacy: .public) \
                lyricBox=\(FitLog.points(self.lyricBoxWidth), privacy: .public)
                """)
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while true {
                guard let self, !Task.isCancelled else { return }
                await self.tick()
                do {
                    try await Task.sleep(for: .seconds(PlaybackModel.tickInterval))
                } catch {
                    return
                }
            }
        }
    }

    private func tick() async {
        guard !hidden else { return }
        let started = clock.now
        let probeMetadata = lastMetadataProbe
            .map { $0.duration(to: started).seconds >= Self.metadataInterval } ?? true

        if probeMetadata {
            lastMetadataProbe = started
            fit.checkDrift()
            let probe = await probeSources()
            guard !hidden else { return }
            automationDenied = probe.denied && probe.active == nil
            activeBridge = probe.active?.bridge
            lastSnapshot = probe.active?.snapshot
        }

        guard let snapshot = lastSnapshot, let bridge = activeBridge else {
            if automationDenied { goDenied() } else { goIdle() }
            return
        }

        if snapshot.trackID != currentTrackID {
            currentTrackID = snapshot.trackID
            clear()
            trackDuration = snapshot.durationSeconds
            show(snapshot)
            header = Self.loadingHeader
            displayState = .loading
            loadLyrics(for: snapshot)
            return
        }

        guard snapshot.state == .playing else {
            positionSample = nil
            shownMenuLine = nil
            displayState = .paused
            return
        }

        guard !lines.isEmpty else {
            positionSample = nil
            displayState = fetching ? .loading : .noLyrics
            return
        }

        guard let position = await position(from: bridge, probing: probeMetadata),
              !hidden, snapshot.trackID == currentTrackID else { return }
        updateMenuLine(at: position)
        updatePopoverLines(at: position)
    }

    private func position(from bridge: PlaybackBridge, probing: Bool) async -> Double? {
        if probing || positionSample == nil, let probed = await bridge.position() {
            positionSample = (probed, clock.now)
            return probed
        }
        guard let sample = positionSample else { return nil }
        return sample.position + sample.at.duration(to: clock.now).seconds
    }

    private enum Shown: Equatable {
        case beforeFirstLine
        case line(Int)

        init(_ index: Int?) {
            self = index.map(Shown.line) ?? .beforeFirstLine
        }
    }

    private struct SourceProbe {
        var active: (bridge: PlaybackBridge, snapshot: NowPlaying)?
        var denied = false
    }

    private func probeSources() async -> SourceProbe {
        var probe = SourceProbe()
        for bridge in bridges {
            switch await bridge.snapshot() {
            case .denied:
                probe.denied = true
            case .unavailable:
                continue
            case .now(let snapshot):
                if snapshot.state == .playing {
                    probe.active = (bridge, snapshot)
                    return probe
                }
                if probe.active == nil { probe.active = (bridge, snapshot) }
            }
        }
        return probe
    }

    private func show(_ snapshot: NowPlaying) {
        header = "\(snapshot.title) — \(snapshot.artist)"
        trackTitle = snapshot.title
        trackArtist = snapshot.artist
        trackSubtitle = snapshot.album.isEmpty
            ? snapshot.source.rawValue
            : "\(snapshot.album) · \(snapshot.source.rawValue)"
    }

    private func goIdle() {
        guard displayState != .idle else { return }
        currentTrackID = nil
        clear()
        header = Self.idleTitle
        trackTitle = Self.idleTitle
        trackArtist = ""
        trackSubtitle = ""
        displayState = .idle
    }

    private func goDenied() {
        guard displayState != .denied else { return }
        currentTrackID = nil
        clear()
        header = Self.deniedTitle
        trackTitle = Self.deniedTitle
        trackArtist = Self.deniedDetail
        trackSubtitle = Self.deniedHint
        displayState = .denied
    }

    private func updateMenuLine(at position: Double) {
        let target = Shown(LRCParser.index(at: position, in: menuLines))
        guard target != shownMenuLine else { return }
        shownMenuLine = target
        guard case .line(let index) = target else {
            chunk = ""
            displayState = .instrumental
            return
        }
        chunk = menuLines[index].text
        displayState = chunk.isEmpty ? .instrumental : .playing
    }

    private func updatePopoverLines(at position: Double) {
        let target = Shown(LRCParser.index(at: position, in: lines))
        guard target != shownLyricLine else { return }
        shownLyricLine = target
        guard case .line(let index) = target else {
            previousLine = ""
            currentLine = ""
            nextLine = ""
            return
        }
        previousLine = index > 0 ? lines[index - 1].text : ""
        currentLine = lines[index].text
        nextLine = index + 1 < lines.count ? lines[index + 1].text : ""
    }

    private func clear() {
        lines = []
        menuLines = []
        positionSample = nil
        shownMenuLine = nil
        shownLyricLine = nil
        fetching = false
        chunk = ""
        previousLine = ""
        currentLine = ""
        nextLine = ""
    }

    private func enterHidden() {
        chunk = ""
        header = Self.hiddenHeader
        displayState = .paused
    }

    private func leaveHidden() {
        shownMenuLine = nil
        shownLyricLine = nil
        positionSample = nil
        if let snapshot = lastSnapshot {
            header = "\(snapshot.title) — \(snapshot.artist)"
        }
        lastSnapshot = nil
    }

    private func loadLyrics(for snapshot: NowPlaying) {
        fetchTask?.cancel()
        fetching = true
        let id = snapshot.trackID
        let title = snapshot.title
        let artist = snapshot.artist
        let album = snapshot.album
        let duration = snapshot.durationSeconds

        fetchTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let result = await self.lyrics.fetch(
                    title: title, artist: artist, album: album, duration: duration)
                if Task.isCancelled { return }
                guard id == self.currentTrackID else { return }

                switch result {
                case .synced(let parsed):
                    self.fetching = false
                    self.lines = parsed
                    self.rebuildMenuLines()
                    self.shownLyricLine = nil
                    if !self.hidden { self.header = "\(title) — \(artist)" }
                    return
                case .unavailable:
                    self.fetching = false
                    self.lines = []
                    self.menuLines = []
                    self.shownMenuLine = nil
                    if !self.hidden {
                        self.chunk = ""
                        self.header = Self.noLyricsHeader
                        self.displayState = .noLyrics
                    }
                    return
                case .retry(let after):
                    try? await Task.sleep(for: .seconds(after + 0.5))
                }
            }
        }
    }
}
