import AppKit

@MainActor
enum MenuBarFit {

    struct Fit: Equatable, Sendable {
        var boxWidth: CGFloat
        var rightEdge: CGFloat
    }

    enum Crowding: String, Sendable {
        case movedRightEdge = "moved-right-edge"
        case crossedLeftLimit = "crossed-left-limit"
    }

    enum SettleFailure: Error, Sendable {
        case neverSettled
        case lostWidth
    }

    enum ProbeOutcome: Sendable {
        case accepted(CGRect)
        case neverSettled
        case lostWidth(CGRect?)
        case crowded(Crowding, CGRect)
    }

    static let probeResolution: CGFloat = 8
    private static let settleTimeout = Duration.milliseconds(700)
    private static let appearTimeout = Duration.seconds(5)
    private static let pollInterval = Duration.milliseconds(20)
    private static let neighbourGrace = Duration.milliseconds(140)
    private static let defaultsPrefix = "fittedBox."

    static weak var itemWindow: NSWindow?

    static var itemFrame: CGRect? {
        guard let frame = itemWindow?.frame,
              frame.minX > 0, frame.minY > 0, frame.width > 0 else { return nil }
        return frame
    }

    static func signature(for screen: NSScreen? = MenuBarMetrics.menuBarScreen) -> String {
        guard let screen else { return "noscreen" }
        let strip = screen.auxiliaryTopRightArea ?? .zero
        return [
            Int(screen.frame.width), Int(screen.frame.height),
            Int(screen.backingScaleFactor), Int(strip.minX), Int(strip.width),
            NSScreen.screens.count, Int(MenuBarMetrics.baseFontSize * 10),
        ].map(String.init).joined(separator: "-")
    }

    static func cachedFit(for signature: String, in defaults: UserDefaults = .standard) -> Fit? {
        guard let stored = defaults.array(forKey: defaultsPrefix + signature) as? [Double],
              stored.count == 2, stored[0] >= MenuBarMetrics.minimumBoxWidth else { return nil }
        return Fit(boxWidth: stored[0], rightEdge: stored[1])
    }

    static func store(_ fit: Fit, for signature: String, in defaults: UserDefaults = .standard) {
        defaults.set([Double(fit.boxWidth), Double(fit.rightEdge)],
                     forKey: defaultsPrefix + signature)
    }

    static func invalidate(_ signature: String, in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsPrefix + signature)
    }

    static func crowding(_ frame: CGRect, rightEdge: CGFloat, leftLimit: CGFloat?) -> Crowding? {
        if abs(frame.maxX - rightEdge) >= 1 { return .movedRightEdge }
        if let leftLimit, frame.minX < leftLimit { return .crossedLeftLimit }
        return nil
    }

    static func crowdsNeighbours(_ frame: CGRect, rightEdge: CGFloat, leftLimit: CGFloat?) -> Bool {
        crowding(frame, rightEdge: rightEdge, leftLimit: leftLimit) != nil
    }

    static func optimisticBound(rightEdge: CGFloat,
                                leftLimit: CGFloat?,
                                upperBound: CGFloat) -> CGFloat {
        guard let leftLimit else { return upperBound }
        let geometric = rightEdge - leftLimit - MenuBarMetrics.systemItemPadding
        return min(upperBound, max(MenuBarMetrics.minimumBoxWidth, geometric))
    }

    static func calibrate(upperBound: CGFloat,
                          leftLimit: CGFloat?,
                          apply: @MainActor (CGFloat) -> Void) async -> Fit? {
        let floor = MenuBarMetrics.minimumBoxWidth
        let clock = ContinuousClock()
        let started = clock.now
        let key = signature()

        FitLog.calibration.notice("""
            begin signature=\(key, privacy: .public) \
            floor=\(FitLog.points(floor), privacy: .public) \
            upperBound=\(FitLog.points(upperBound), privacy: .public) \
            leftLimit=\(FitLog.points(leftLimit), privacy: .public) \
            padding=\(FitLog.points(MenuBarMetrics.systemItemPadding), privacy: .public)
            """)

        guard upperBound > floor else {
            FitLog.calibration.error("""
                abandoned reason=upper-bound-not-above-floor \
                upperBound=\(FitLog.points(upperBound), privacy: .public) \
                floor=\(FitLog.points(floor), privacy: .public)
                """)
            return nil
        }

        let baseline = await settle(at: floor, timeout: appearTimeout, apply: apply)
        guard case .success(let base) = baseline else {
            if case .failure(.lostWidth) = baseline {
                FitLog.calibration.error("""
                    abandoned reason=floor-lost-width-during-grace \
                    grace=\(FitLog.milliseconds(neighbourGrace), privacy: .public)ms \
                    wantedWidth=\(FitLog.points(floor + MenuBarMetrics.systemItemPadding), privacy: .public) \
                    \(FitLog.geometry(itemFrame), privacy: .public)
                    """)
            } else {
                FitLog.calibration.error("""
                    abandoned reason=floor-never-appeared \
                    waited=\(FitLog.milliseconds(appearTimeout), privacy: .public)ms \
                    wantedWidth=\(FitLog.points(floor + MenuBarMetrics.systemItemPadding), privacy: .public) \
                    \(FitLog.geometry(itemFrame), privacy: .public)
                    """)
            }
            return nil
        }
        let rightEdge = base.settled.maxX
        let baselineShift = base.settled.maxX - base.arrived.maxX

        if abs(baselineShift) >= 1 {
            FitLog.calibration.notice("""
                floorRelaidOut arrivedMaxX=\(FitLog.points(base.arrived.maxX), privacy: .public) \
                settledMaxX=\(FitLog.points(base.settled.maxX), privacy: .public) \
                shift=\(FitLog.points(baselineShift), privacy: .public) \
                grace=\(FitLog.milliseconds(neighbourGrace), privacy: .public)ms
                """)
        }

        FitLog.calibration.notice("""
            floorSettled \(FitLog.geometry(base.settled), privacy: .public) \
            rightEdge=\(FitLog.points(rightEdge), privacy: .public)
            """)

        var fitting = floor
        var crowding = optimisticBound(rightEdge: rightEdge,
                                       leftLimit: leftLimit,
                                       upperBound: upperBound)
        var probes = 0

        FitLog.calibration.notice("""
            optimisticBound start=\(FitLog.points(crowding), privacy: .public) \
            span=\(FitLog.points(crowding - fitting), privacy: .public) \
            resolution=\(FitLog.points(probeResolution), privacy: .public)
            """)

        if await accepts(crowding, rightEdge: rightEdge, leftLimit: leftLimit,
                         index: &probes, apply: apply) {
            fitting = crowding
        } else {
            await recover(to: fitting, apply: apply)
            while crowding - fitting > probeResolution {
                let candidate = ((fitting + crowding) / 2).rounded()
                if await accepts(candidate, rightEdge: rightEdge, leftLimit: leftLimit,
                                 index: &probes, apply: apply) {
                    fitting = candidate
                } else {
                    crowding = candidate
                    await recover(to: fitting, apply: apply)
                }
            }
        }

        apply(fitting)
        let settled = await frame(forBox: fitting, timeout: settleTimeout)

        if fitting == floor {
            FitLog.calibration.error("""
                converged box=\(FitLog.points(fitting), privacy: .public) \
                outcome=pinned-at-floor probes=\(probes, privacy: .public) \
                rightEdge=\(FitLog.points(rightEdge), privacy: .public) \
                elapsed=\(FitLog.milliseconds(started.duration(to: clock.now)), privacy: .public)ms \
                \(FitLog.geometry(settled), privacy: .public)
                """)
        } else {
            FitLog.calibration.notice("""
                converged box=\(FitLog.points(fitting), privacy: .public) \
                outcome=fitted probes=\(probes, privacy: .public) \
                rightEdge=\(FitLog.points(rightEdge), privacy: .public) \
                elapsed=\(FitLog.milliseconds(started.duration(to: clock.now)), privacy: .public)ms \
                \(FitLog.geometry(settled), privacy: .public)
                """)
        }

        return Fit(boxWidth: fitting, rightEdge: rightEdge)
    }

    private static func accepts(_ box: CGFloat,
                                rightEdge: CGFloat,
                                leftLimit: CGFloat?,
                                index: inout Int,
                                apply: @MainActor (CGFloat) -> Void) async -> Bool {
        index += 1
        let number = index
        let outcome = await probe(box, rightEdge: rightEdge, leftLimit: leftLimit, apply: apply)

        switch outcome {
        case .accepted(let frame):
            FitLog.calibration.notice("""
                probe#\(number, privacy: .public) box=\(FitLog.points(box), privacy: .public) \
                verdict=accepted \(FitLog.geometry(frame), privacy: .public)
                """)
            return true

        case .neverSettled:
            FitLog.calibration.error("""
                probe#\(number, privacy: .public) box=\(FitLog.points(box), privacy: .public) \
                verdict=rejected reason=never-settled \
                waited=\(FitLog.milliseconds(settleTimeout), privacy: .public)ms \
                wantedWidth=\(FitLog.points(box.rounded() + MenuBarMetrics.systemItemPadding), privacy: .public) \
                \(FitLog.geometry(itemFrame), privacy: .public)
                """)
            return false

        case .lostWidth(let frame):
            FitLog.calibration.error("""
                probe#\(number, privacy: .public) box=\(FitLog.points(box), privacy: .public) \
                verdict=rejected reason=lost-width-during-grace \
                grace=\(FitLog.milliseconds(neighbourGrace), privacy: .public)ms \
                wantedWidth=\(FitLog.points(box.rounded() + MenuBarMetrics.systemItemPadding), privacy: .public) \
                \(FitLog.geometry(frame), privacy: .public)
                """)
            return false

        case .crowded(let reason, let frame):
            FitLog.calibration.notice("""
                probe#\(number, privacy: .public) box=\(FitLog.points(box), privacy: .public) \
                verdict=rejected reason=\(reason.rawValue, privacy: .public) \
                \(FitLog.geometry(frame), privacy: .public) \
                expectedRightEdge=\(FitLog.points(rightEdge), privacy: .public) \
                shift=\(FitLog.points(frame.maxX - rightEdge), privacy: .public) \
                leftLimit=\(FitLog.points(leftLimit), privacy: .public)
                """)
            return false
        }
    }

    private static func probe(_ box: CGFloat,
                              rightEdge: CGFloat,
                              leftLimit: CGFloat?,
                              apply: @MainActor (CGFloat) -> Void) async -> ProbeOutcome {
        switch await settle(at: box, timeout: settleTimeout, apply: apply) {
        case .failure(.neverSettled):
            return .neverSettled
        case .failure(.lostWidth):
            return .lostWidth(itemFrame)
        case .success(let frames):
            if let reason = crowding(frames.settled, rightEdge: rightEdge, leftLimit: leftLimit) {
                return .crowded(reason, frames.settled)
            }
            return .accepted(frames.settled)
        }
    }

    private static func settle(
        at box: CGFloat,
        timeout: Duration,
        apply: @MainActor (CGFloat) -> Void
    ) async -> Result<(arrived: CGRect, settled: CGRect), SettleFailure> {
        apply(box)
        guard let arrived = await frame(forBox: box, timeout: timeout) else {
            return .failure(.neverSettled)
        }
        try? await Task.sleep(for: neighbourGrace)
        guard let settled = itemFrame, matches(settled, box: box) else {
            return .failure(.lostWidth)
        }
        return .success((arrived, settled))
    }

    private static func recover(to box: CGFloat, apply: @MainActor (CGFloat) -> Void) async {
        switch await settle(at: box, timeout: settleTimeout, apply: apply) {
        case .success(let frames):
            FitLog.calibration.notice("""
                recover box=\(FitLog.points(box), privacy: .public) outcome=settled \
                \(FitLog.geometry(frames.settled), privacy: .public)
                """)
        case .failure:
            FitLog.calibration.error("""
                recover box=\(FitLog.points(box), privacy: .public) outcome=never-settled \
                \(FitLog.geometry(itemFrame), privacy: .public)
                """)
        }
    }

    private static func matches(_ frame: CGRect, box: CGFloat) -> Bool {
        abs(frame.width - (box.rounded() + MenuBarMetrics.systemItemPadding)) < 1
    }

    private static func frame(forBox box: CGFloat, timeout: Duration) async -> CGRect? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let frame = itemFrame, matches(frame, box: box) { return frame }
            try? await Task.sleep(for: pollInterval)
        }
        return nil
    }
}
