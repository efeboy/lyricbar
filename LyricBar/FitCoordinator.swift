import AppKit
import Observation

@MainActor
@Observable
final class FitCoordinator {

    enum Reason: String {
        case launchNoCache = "launch-no-cache"
        case driftSqueezed = "drift-squeezed"
        case screenChange = "screen-change"
    }

    enum Refit {
        case calibrated(Reason)
        case restoredFromCache
    }

    private(set) var fittedWidth: CGFloat
    private(set) var probeWidth: CGFloat?

    @ObservationIgnored let launchFit: MenuBarFit.Fit?
    @ObservationIgnored var onRefit: (Refit) -> Void = { _ in }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock = ContinuousClock()
    @ObservationIgnored private var expectedRightEdge: CGFloat?
    @ObservationIgnored private var lastCalibration: ContinuousClock.Instant?
    @ObservationIgnored private var driftedProbes = 0
    @ObservationIgnored private var isCalibrating = false
    @ObservationIgnored private var fitTask: Task<Void, Never>?
    @ObservationIgnored private var screenTask: Task<Void, Never>?

    private static let recalibrationCooldown: Double = 30
    private static let driftProbesBeforeRecalibration = 2
    private static let driftTolerance = MenuBarFit.probeResolution

    init(defaults: UserDefaults) {
        let cached = MenuBarFit.cachedFit(for: MenuBarFit.signature(), in: defaults)
        self.defaults = defaults
        launchFit = cached
        fittedWidth = cached?.boxWidth ?? MenuBarMetrics.minimumBoxWidth
        expectedRightEdge = cached?.rightEdge
    }

    func calibrate(reason: Reason) {
        FitLog.calibration.notice("""
            requested reason=\(reason.rawValue, privacy: .public) \
            wasCalibrating=\(self.isCalibrating, privacy: .public) \
            fittedWidth=\(FitLog.points(self.fittedWidth), privacy: .public)
            """)
        fitTask?.cancel()
        fitTask = Task { [weak self] in
            guard let self else { return }
            self.isCalibrating = true
            defer {
                self.isCalibrating = false
                self.probeWidth = nil
            }

            let fit = await MenuBarFit.calibrate(
                upperBound: MenuBarMetrics.widestBox(),
                leftLimit: MenuBarMetrics.statusStripLeftEdge()
            ) { [weak self] candidate in
                self?.probeWidth = candidate
            }

            guard !Task.isCancelled else {
                FitLog.calibration.notice("cancelled reason=\(reason.rawValue, privacy: .public)")
                return
            }
            if let fit {
                MenuBarFit.store(fit, for: MenuBarFit.signature(), in: self.defaults)
                FitLog.calibration.notice("""
                    stored signature=\(MenuBarFit.signature(), privacy: .public) \
                    box=\(FitLog.points(fit.boxWidth), privacy: .public) \
                    rightEdge=\(FitLog.points(fit.rightEdge), privacy: .public)
                    """)
                self.fittedWidth = fit.boxWidth
                self.expectedRightEdge = fit.rightEdge
                self.lastCalibration = self.clock.now
            } else {
                FitLog.calibration.error("""
                    noFit reason=\(reason.rawValue, privacy: .public) \
                    keeping=\(FitLog.points(self.fittedWidth), privacy: .public) \
                    nothingWrittenToDefaults=true
                    """)
            }
            self.onRefit(.calibrated(reason))
        }
    }

    func checkDrift() {
        guard !isCalibrating, probeWidth == nil,
              let expected = expectedRightEdge,
              let frame = MenuBarFit.itemFrame else { return }

        let drift = frame.maxX - expected
        guard abs(drift) > Self.driftTolerance else {
            if driftedProbes > 0 {
                FitLog.drift.info("""
                    settled drift=\(FitLog.points(drift), privacy: .public) \
                    tolerance=\(FitLog.points(Self.driftTolerance), privacy: .public) \
                    discardedProbes=\(self.driftedProbes, privacy: .public)
                    """)
            }
            driftedProbes = 0
            return
        }
        driftedProbes += 1
        FitLog.drift.notice("""
            observed drift=\(FitLog.points(drift), privacy: .public) \
            direction=\(drift < 0 ? "squeezed" : "freed", privacy: .public) \
            expectedRightEdge=\(FitLog.points(expected), privacy: .public) \
            \(FitLog.geometry(frame), privacy: .public) \
            probe=\(self.driftedProbes, privacy: .public)/\(Self.driftProbesBeforeRecalibration, privacy: .public)
            """)
        guard driftedProbes >= Self.driftProbesBeforeRecalibration else { return }
        driftedProbes = 0
        MenuBarFit.invalidate(MenuBarFit.signature(), in: defaults)
        FitLog.drift.notice("""
            invalidated signature=\(MenuBarFit.signature(), privacy: .public) \
            drift=\(FitLog.points(drift), privacy: .public)
            """)

        guard drift < 0 else {
            expectedRightEdge = frame.maxX
            FitLog.drift.notice("""
                roomFreed drift=\(FitLog.points(drift), privacy: .public) \
                newRightEdge=\(FitLog.points(frame.maxX), privacy: .public) \
                recalibrating=false pickedUpOnNextLaunch=true
                """)
            return
        }
        if let last = lastCalibration {
            let sinceLast = last.duration(to: clock.now).seconds
            if sinceLast < Self.recalibrationCooldown {
                FitLog.drift.notice("""
                    suppressed reason=cooldown \
                    sinceLastCalibration=\(Int(sinceLast), privacy: .public)s \
                    cooldown=\(Int(Self.recalibrationCooldown), privacy: .public)s
                    """)
                return
            }
        }
        calibrate(reason: .driftSqueezed)
    }

    func observeScreenChanges() {
        screenTask?.cancel()
        screenTask = Task { [weak self] in
            let changes = NotificationCenter.default
                .notifications(named: NSApplication.didChangeScreenParametersNotification)
                .map { _ in () }
            for await _ in changes {
                guard let self else { return }
                FitLog.calibration.notice("""
                    screenChange signature=\(MenuBarFit.signature(), privacy: .public) \
                    screens=\(NSScreen.screens.count, privacy: .public) \
                    widestBox=\(FitLog.points(MenuBarMetrics.widestBox()), privacy: .public)
                    """)
                if let cached = MenuBarFit.cachedFit(for: MenuBarFit.signature(), in: self.defaults) {
                    self.fittedWidth = cached.boxWidth
                    self.expectedRightEdge = cached.rightEdge
                    self.onRefit(.restoredFromCache)
                } else {
                    self.calibrate(reason: .screenChange)
                }
            }
        }
    }
}
