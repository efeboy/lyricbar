import Testing
@testable import LyricBar

// LRCLIB's exact-signature endpoint misses often (album names differ across
// remasters and archive editions), so the search fallback carries most tracks.
// Duration is the only reliable key there, and picking the wrong edit produces
// lyrics that drift steadily out of sync — the worst failure this app has.

@Suite("LRCLIB duration matching")
struct LRCLibMatchingTests {

    /// Only the fields `bestMatch` reads; the rest of the payload is irrelevant here.
    private func track(id: Int = 1, duration: Double?, synced: String? = "[00:01.00] la") -> LRCLibTrack {
        LRCLibTrack(id: id, trackName: "Song", artistName: "Artist", duration: duration,
                    instrumental: false, plainLyrics: nil, syncedLyrics: synced)
    }

    @Test("Picks the closest duration, not the first hit")
    func picksClosest() {
        let results = [
            track(id: 1, duration: 200),
            track(id: 2, duration: 181),
            track(id: 3, duration: 178),
        ]

        #expect(LRCLibClient.bestMatch(among: results, duration: 180)?.id == 2)
    }

    @Test("Rejects the closest hit when it is still too far off")
    func rejectsDistant() {
        let results = [track(id: 1, duration: 240), track(id: 2, duration: 300)]

        #expect(LRCLibClient.bestMatch(among: results, duration: 180) == nil)
    }

    // The tolerance is inclusive; a hit exactly at the limit is still the same
    // recording as far as this app is concerned.
    @Test("The tolerance boundary is inclusive", arguments: [
        (180.0 + LRCLibClient.durationTolerance, true),
        (180.0 - LRCLibClient.durationTolerance, true),
        (180.0 + LRCLibClient.durationTolerance + 0.01, false),
        (180.0 - LRCLibClient.durationTolerance - 0.01, false),
    ])
    func toleranceBoundary(candidateDuration: Double, accepted: Bool) {
        let match = LRCLibClient.bestMatch(among: [track(duration: candidateDuration)], duration: 180)

        #expect((match != nil) == accepted)
    }

    // A hit with no synced lyrics is useless even at a perfect duration match —
    // and must not crowd out a slightly-worse hit that does have them.
    @Test("Hits without synced lyrics never win")
    func ignoresUnsynced() {
        let results = [
            track(id: 1, duration: 180, synced: nil),
            track(id: 2, duration: 180, synced: ""),
            track(id: 3, duration: 183, synced: "[00:01.00] la"),
        ]

        #expect(LRCLibClient.bestMatch(among: results, duration: 180)?.id == 3)
    }

    @Test("No results, no match")
    func emptyResults() {
        #expect(LRCLibClient.bestMatch(among: [], duration: 180) == nil)
    }

    // A missing duration reads as 0, which must not sneak past the tolerance
    // check for a normal-length track.
    @Test("A hit with no duration is treated as unmatched")
    func missingDuration() {
        #expect(LRCLibClient.bestMatch(among: [track(duration: nil)], duration: 180) == nil)
    }
}
