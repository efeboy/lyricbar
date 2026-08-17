import Testing
import AppKit
@testable import LyricBar

@Suite("Menu bar fit")
@MainActor
struct MenuBarFitTests {

    private static let suiteName = "net.local.lyricbar.fit-tests"

    private func scratchDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: Self.suiteName) ?? .standard
        defaults.removePersistentDomain(forName: Self.suiteName)
        return defaults
    }

    private func frame(x: CGFloat, width: CGFloat) -> CGRect {
        CGRect(x: x, y: 1085, width: width, height: 33)
    }

    @Test("An item that keeps its right edge is not crowding anybody")
    func settledItemIsAccepted() {
        let settled = frame(x: 984, width: 266)

        #expect(!MenuBarFit.crowdsNeighbours(settled, rightEdge: 1250, leftLimit: 956))
    }

    @Test("A right edge that moved means neighbours were pushed aside")
    func displacedNeighboursAreRejected() {
        let pushed = frame(x: 1026, width: 291)

        #expect(MenuBarFit.crowdsNeighbours(pushed, rightEdge: 1250, leftLimit: 956))
    }

    @Test("An item reaching left of the status strip is rejected")
    func reachingPastStripIsRejected() {
        let overTheNotch = frame(x: 659, width: 591)

        #expect(MenuBarFit.crowdsNeighbours(overTheNotch, rightEdge: 1250, leftLimit: 956))
    }

    @Test("With no notch there is no left limit to violate")
    func noLeftLimit() {
        let wide = frame(x: 40, width: 1210)

        #expect(!MenuBarFit.crowdsNeighbours(wide, rightEdge: 1250, leftLimit: nil))
    }

    @Test("Sub-point jitter in the right edge is tolerated")
    func toleratesRounding() {
        let jittered = frame(x: 984, width: 266.4)

        #expect(!MenuBarFit.crowdsNeighbours(jittered, rightEdge: 1250, leftLimit: 956))
    }

    @Test("The search starts from the geometry, not from the whole strip")
    func optimisticBoundUsesTheNotch() {
        #expect(MenuBarFit.optimisticBound(rightEdge: 1250, leftLimit: 956, upperBound: 756) == 278)
    }

    @Test("With no notch the search starts at the widest allowed box")
    func optimisticBoundWithoutNotch() {
        #expect(MenuBarFit.optimisticBound(rightEdge: 1250, leftLimit: nil, upperBound: 756) == 756)
    }

    @Test("The starting bound never exceeds the widest allowed box")
    func optimisticBoundIsClamped() {
        #expect(MenuBarFit.optimisticBound(rightEdge: 2000, leftLimit: 100, upperBound: 300) == 300)
    }

    @Test("A strip with no room still starts at the readable floor")
    func optimisticBoundFloors() {
        #expect(MenuBarFit.optimisticBound(rightEdge: 1000, leftLimit: 990, upperBound: 756)
                == MenuBarMetrics.minimumBoxWidth)
    }

    @Test("A measured fit survives a round trip through preferences")
    func cacheRoundTrip() {
        let defaults = scratchDefaults()
        let signature = MenuBarFit.signature()
        let fit = MenuBarFit.Fit(boxWidth: 250, rightEdge: 1250)

        #expect(MenuBarFit.cachedFit(for: signature, in: defaults) == nil)
        MenuBarFit.store(fit, for: signature, in: defaults)
        #expect(MenuBarFit.cachedFit(for: signature, in: defaults) == fit)

        MenuBarFit.invalidate(signature, in: defaults)
        #expect(MenuBarFit.cachedFit(for: signature, in: defaults) == nil)
    }

    @Test("A cached width below the floor is discarded rather than trusted")
    func rejectsUnusableCache() {
        let defaults = scratchDefaults()
        let signature = MenuBarFit.signature()

        MenuBarFit.store(MenuBarFit.Fit(boxWidth: 4, rightEdge: 1250),
                         for: signature, in: defaults)

        #expect(MenuBarFit.cachedFit(for: signature, in: defaults) == nil)
    }

    @Test("The signature is stable for one display arrangement")
    func signatureIsStable() {
        #expect(MenuBarFit.signature() == MenuBarFit.signature())
        #expect(!MenuBarFit.signature().isEmpty)
    }

    @Test("A different display arrangement gets a different signature")
    func signatureVariesByScreen() throws {
        let screen = try #require(MenuBarMetrics.menuBarScreen)

        #expect(MenuBarFit.signature(for: screen) == MenuBarFit.signature())
        #expect(MenuBarFit.signature(for: nil) != MenuBarFit.signature(for: screen))
    }
}
