import Testing
@testable import LyricBar

@Suite("Update check")
struct UpdateCheckerTests {

    @Test("A higher release is newer, compared numerically", arguments: [
        ("v1.2", "1.1"),
        ("1.10", "1.9"),
        ("v2.0", "1.99"),
        ("1.1.1", "1.1"),
    ])
    func newer(tag: String, current: String) {
        #expect(UpdateChecker.isNewer(tag, than: current))
    }

    @Test("The same or an older release is not an update", arguments: [
        ("v1.1", "1.1"),
        ("1.1.0", "1.1"),
        ("v1.0", "1.1"),
        ("1.9", "1.10"),
    ])
    func notNewer(tag: String, current: String) {
        #expect(!UpdateChecker.isNewer(tag, than: current))
    }

    @Test("A tag that is not a version never offers an update", arguments: [
        "nightly", "v1.2-beta", "", "1..2",
    ])
    func unparseableTags(tag: String) {
        #expect(!UpdateChecker.isNewer(tag, than: "1.1"))
    }
}
