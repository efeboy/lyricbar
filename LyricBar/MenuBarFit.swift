import AppKit

@MainActor
enum MenuBarFit {

    struct Fit: Equatable, Sendable {
        var boxWidth: CGFloat
        var rightEdge: CGFloat
    }

    static let probeResolution: CGFloat = 8
    private static let settleTimeout = Duration.milliseconds(700)
    private static let appearTimeout = Duration.seconds(5)
    private static let pollInterval = Duration.milliseconds(20)
    private static let neighbourGrace = Duration.milliseconds(140)
    private static let defaultsPrefix = "fittedBox."

    static var itemFrame: CGRect? {
        guard let window = NSApp.windows.first(where: { $0.className.contains("StatusBar") }) else {
            return nil
        }
        let frame = window.frame
        guard frame.minX > 0, frame.minY > 0, frame.width > 0 else { return nil }
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

    static func crowdsNeighbours(_ frame: CGRect, rightEdge: CGFloat, leftLimit: CGFloat?) -> Bool {
        if abs(frame.maxX - rightEdge) >= 1 { return true }
        if let leftLimit, frame.minX < leftLimit { return true }
        return false
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
        guard upperBound > floor else { return nil }

        apply(floor)
        guard let base = await frame(forBox: floor, timeout: appearTimeout) else { return nil }
        let rightEdge = base.maxX

        var fitting = floor
        var crowding = optimisticBound(rightEdge: rightEdge,
                                       leftLimit: leftLimit,
                                       upperBound: upperBound)

        if await accepts(crowding, rightEdge: rightEdge, leftLimit: leftLimit, apply: apply) {
            fitting = crowding
        } else {
            await recover(to: fitting, apply: apply)
            while crowding - fitting > probeResolution {
                let candidate = ((fitting + crowding) / 2).rounded()
                if await accepts(candidate, rightEdge: rightEdge, leftLimit: leftLimit, apply: apply) {
                    fitting = candidate
                } else {
                    crowding = candidate
                    await recover(to: fitting, apply: apply)
                }
            }
        }

        apply(fitting)
        _ = await frame(forBox: fitting, timeout: settleTimeout)
        return Fit(boxWidth: fitting, rightEdge: rightEdge)
    }

    private static func accepts(_ box: CGFloat,
                                rightEdge: CGFloat,
                                leftLimit: CGFloat?,
                                apply: @MainActor (CGFloat) -> Void) async -> Bool {
        apply(box)
        guard await frame(forBox: box, timeout: settleTimeout) != nil else { return false }
        try? await Task.sleep(for: neighbourGrace)
        guard let frame = itemFrame, matches(frame, box: box) else { return false }
        return !crowdsNeighbours(frame, rightEdge: rightEdge, leftLimit: leftLimit)
    }

    private static func recover(to box: CGFloat, apply: @MainActor (CGFloat) -> Void) async {
        apply(box)
        _ = await frame(forBox: box, timeout: settleTimeout)
        try? await Task.sleep(for: neighbourGrace)
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
