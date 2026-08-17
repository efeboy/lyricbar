import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class PlaybackModel {

    var lineText: String {
        chunk.isEmpty ? Self.gapPlaceholder : chunk
    }

    private(set) var header = PlaybackModel.startingHeader
    private(set) var displayState = DisplayState.idle
    private(set) var trackTitle = PlaybackModel.idleTitle
    private(set) var trackArtist = ""
    private(set) var trackSubtitle = ""
    private(set) var previousLine = ""
    private(set) var currentLine = ""
    private(set) var nextLine = ""
    private(set) var boxWidth: CGFloat
    private(set) var fittedWidth: CGFloat

    var widthPreference: LyricWidth {
        get { storedWidth }
        set {
            guard newValue != storedWidth else { return }
            storedWidth = newValue
            defaults.set(newValue.rawValue, forKey: Keys.width)
            applyFittedWidth()
        }
    }

    var updateSpeed: UpdateSpeed {
        get { storedSpeed }
        set {
            guard newValue != storedSpeed else { return }
            storedSpeed = newValue
            defaults.set(newValue.rawValue, forKey: Keys.speed)
        }
    }

    var isPaused: Bool {
        get { paused }
        set {
            guard newValue != paused else { return }
            paused = newValue
            newValue ? enterPause() : leavePause()
        }
    }

    var loginEnabled: Bool {
        get { loginRegistered }
        set {
            try? LoginItem.setEnabled(newValue)
            loginRegistered = LoginItem.isEnabled
        }
    }

    enum DisplayState: Equatable {
        case playing, instrumental, noLyrics, paused, idle

        var opacity: Double {
            switch self {
            case .playing, .instrumental, .noLyrics: 1.0
            case .paused:                            0.55
            case .idle:                              0.30
            }
        }
    }

    private var chunk = ""
    private var storedWidth: LyricWidth
    private var storedSpeed: UpdateSpeed
    private var paused = false
    private var loginRegistered = LoginItem.isEnabled

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock = ContinuousClock()
    @ObservationIgnored private let bridges: [PlaybackBridge] = [SpotifyBridge(), MusicBridge()]
    @ObservationIgnored private let lrclib = LRCLibClient()

    @ObservationIgnored private var activeBridge: PlaybackBridge?
    @ObservationIgnored private var lines: [LyricLine] = []
    @ObservationIgnored private var menuLines: [LyricLine] = []
    @ObservationIgnored private var trackDuration: Double = 0
    @ObservationIgnored private var currentTrackID: String?
    @ObservationIgnored private var shownMenuIndex = -1
    @ObservationIgnored private var shownLyricIndex = -2

    @ObservationIgnored private var lastSnapshot: NowPlaying?
    @ObservationIgnored private var positionSample: (position: Double, at: ContinuousClock.Instant)?
    @ObservationIgnored private var lastMetadataProbe: ContinuousClock.Instant?

    @ObservationIgnored private var expectedRightEdge: CGFloat?
    @ObservationIgnored private var lastCalibration: ContinuousClock.Instant?
    @ObservationIgnored private var driftedProbes = 0
    @ObservationIgnored private var isCalibrating = false

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var fitTask: Task<Void, Never>?
    @ObservationIgnored private var screenTask: Task<Void, Never>?

    private static let gapPlaceholder = "♪"
    private static let startingHeader = "Starting…"
    private static let idleTitle = "Nothing playing"
    private static let pausedHeader = "Paused"
    private static let noLyricsHeader = "No synced lyrics found"
    private static let metadataInterval: Double = 1
    private static let recalibrationCooldown: Double = 30
    private static let driftProbesBeforeRecalibration = 2
    private static let driftTolerance = MenuBarFit.probeResolution

    private enum Keys {
        static let width = "lyricWidth"
        static let speed = "tickInterval"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let width = LyricWidth(rawValue: defaults.string(forKey: Keys.width) ?? "") ?? .fill
        let speed = UpdateSpeed(rawValue: defaults.double(forKey: Keys.speed)) ?? .balanced
        let cached = MenuBarFit.cachedFit(for: MenuBarFit.signature(), in: defaults)
        let fitted = cached?.boxWidth ?? MenuBarMetrics.minimumBoxWidth

        storedWidth = width
        storedSpeed = speed
        fittedWidth = fitted
        boxWidth = MenuBarMetrics.boxWidth(width, fittedWidth: fitted)
        expectedRightEdge = cached?.rightEdge

        guard !Self.isRunningTests else { return }
        observeScreenChanges()
        startPolling()
        if cached == nil { calibrate() }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func refreshLoginState() {
        loginRegistered = LoginItem.isEnabled
    }

    private func applyFittedWidth() {
        boxWidth = MenuBarMetrics.boxWidth(storedWidth, fittedWidth: fittedWidth)
        rebuildMenuLines()
    }

    private func rebuildMenuLines() {
        menuLines = LyricReflow.expand(lines, trackDuration: trackDuration, width: boxWidth)
        shownMenuIndex = -1
    }

    private func calibrate() {
        fitTask?.cancel()
        fitTask = Task { [weak self] in
            guard let self else { return }
            self.isCalibrating = true
            defer { self.isCalibrating = false }

            let fit = await MenuBarFit.calibrate(
                upperBound: MenuBarMetrics.widestBox(),
                leftLimit: MenuBarMetrics.statusStripLeftEdge()
            ) { [weak self] candidate in
                self?.boxWidth = candidate
            }

            guard !Task.isCancelled else { return }
            if let fit {
                MenuBarFit.store(fit, for: MenuBarFit.signature(), in: self.defaults)
                self.fittedWidth = fit.boxWidth
                self.expectedRightEdge = fit.rightEdge
                self.lastCalibration = self.clock.now
            }
            self.applyFittedWidth()
        }
    }

    private func checkFitDrift(now: ContinuousClock.Instant) {
        guard !isCalibrating,
              let expected = expectedRightEdge,
              let frame = MenuBarFit.itemFrame else { return }

        guard abs(frame.maxX - expected) > Self.driftTolerance else {
            driftedProbes = 0
            return
        }
        driftedProbes += 1
        guard driftedProbes >= Self.driftProbesBeforeRecalibration else { return }
        if let last = lastCalibration,
           last.duration(to: now).seconds < Self.recalibrationCooldown { return }

        driftedProbes = 0
        MenuBarFit.invalidate(MenuBarFit.signature(), in: defaults)
        calibrate()
    }

    private func observeScreenChanges() {
        screenTask = Task { [weak self] in
            let changes = NotificationCenter.default
                .notifications(named: NSApplication.didChangeScreenParametersNotification)
                .map { _ in () }
            for await _ in changes {
                guard let self else { return }
                if let cached = MenuBarFit.cachedFit(for: MenuBarFit.signature(), in: self.defaults) {
                    self.fittedWidth = cached.boxWidth
                    self.expectedRightEdge = cached.rightEdge
                    self.applyFittedWidth()
                } else {
                    self.calibrate()
                }
            }
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while true {
                guard let self, !Task.isCancelled else { return }
                let interval = self.storedSpeed.seconds
                self.tick()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
            }
        }
    }

    private func tick() {
        guard !paused else { return }
        let now = clock.now
        let probeMetadata = lastMetadataProbe
            .map { $0.duration(to: now).seconds >= Self.metadataInterval } ?? true

        if probeMetadata {
            lastMetadataProbe = now
            checkFitDrift(now: now)
            if let (bridge, snapshot) = pickActive() {
                activeBridge = bridge
                lastSnapshot = snapshot
            } else {
                activeBridge = nil
                lastSnapshot = nil
            }
        }

        guard let snapshot = lastSnapshot, let bridge = activeBridge else {
            goIdle()
            return
        }

        if snapshot.trackID != currentTrackID {
            currentTrackID = snapshot.trackID
            clear()
            trackDuration = snapshot.durationSeconds
            show(snapshot)
            loadLyrics(for: snapshot)
            return
        }

        guard snapshot.state == .playing else {
            positionSample = nil
            displayState = .paused
            return
        }

        guard !lines.isEmpty else {
            positionSample = nil
            displayState = .noLyrics
            return
        }

        guard let position = position(from: bridge, probing: probeMetadata, now: now) else { return }
        updateMenuLine(at: position)
        updatePopoverLines(at: position)
    }

    private func position(from bridge: PlaybackBridge,
                          probing: Bool,
                          now: ContinuousClock.Instant) -> Double? {
        if probing, let probed = bridge.position() {
            positionSample = (probed, now)
            return probed
        }
        if let sample = positionSample {
            return sample.position + sample.at.duration(to: now).seconds
        }
        guard let probed = bridge.position() else { return nil }
        positionSample = (probed, now)
        return probed
    }

    private func pickActive() -> (PlaybackBridge, NowPlaying)? {
        var pausedHit: (PlaybackBridge, NowPlaying)?
        for bridge in bridges {
            guard let snapshot = bridge.snapshot() else { continue }
            if snapshot.state == .playing { return (bridge, snapshot) }
            if pausedHit == nil { pausedHit = (bridge, snapshot) }
        }
        return pausedHit
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
        currentTrackID = nil
        clear()
        header = Self.idleTitle
        trackTitle = Self.idleTitle
        trackArtist = ""
        trackSubtitle = ""
        displayState = .idle
    }

    private func updateMenuLine(at position: Double) {
        guard let index = LRCParser.index(at: position, in: menuLines) else {
            if shownMenuIndex != -1 || displayState != .instrumental {
                shownMenuIndex = -1
                chunk = ""
                displayState = .instrumental
            }
            return
        }
        guard index != shownMenuIndex else { return }
        shownMenuIndex = index
        chunk = menuLines[index].text
        displayState = chunk.isEmpty ? .instrumental : .playing
    }

    private func updatePopoverLines(at position: Double) {
        let index = LRCParser.index(at: position, in: lines) ?? -1
        guard index != shownLyricIndex else { return }
        shownLyricIndex = index
        previousLine = index > 0 ? lines[index - 1].text : ""
        currentLine = index >= 0 ? lines[index].text : ""
        nextLine = (index >= 0 && index + 1 < lines.count) ? lines[index + 1].text : ""
    }

    private func clear() {
        lines = []
        menuLines = []
        positionSample = nil
        shownMenuIndex = -1
        shownLyricIndex = -2
        chunk = ""
        previousLine = ""
        currentLine = ""
        nextLine = ""
    }

    private func enterPause() {
        chunk = ""
        header = Self.pausedHeader
        displayState = .paused
    }

    private func leavePause() {
        shownMenuIndex = -1
        shownLyricIndex = -2
        positionSample = nil
        if let snapshot = lastSnapshot {
            header = "\(snapshot.title) — \(snapshot.artist)"
        }
        lastSnapshot = nil
    }

    private func loadLyrics(for snapshot: NowPlaying) {
        fetchTask?.cancel()
        let id = snapshot.trackID
        let title = snapshot.title
        let artist = snapshot.artist
        let album = snapshot.album
        let duration = snapshot.durationSeconds

        fetchTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let result = await self.lrclib.fetch(
                    title: title, artist: artist, album: album, duration: duration)
                if Task.isCancelled { return }
                guard id == self.currentTrackID else { return }

                switch result {
                case .synced(let parsed):
                    self.lines = parsed
                    self.rebuildMenuLines()
                    self.shownLyricIndex = -2
                    if !self.paused { self.header = "\(title) — \(artist)" }
                    return
                case .unavailable:
                    self.lines = []
                    self.menuLines = []
                    self.shownMenuIndex = -1
                    if !self.paused {
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

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}
