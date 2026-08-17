import Testing
@testable import LyricBar

@Suite("LRCLIB duration matching")
struct LRCLibMatchingTests {

    private func track(id: Int = 1,
                       duration: Double?,
                       synced: String? = "[00:01.00] la") -> LRCLibTrack {
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

    @Test("The tolerance boundary is inclusive", arguments: [
        (180.0 + LRCLibClient.durationTolerance, true),
        (180.0 - LRCLibClient.durationTolerance, true),
        (180.0 + LRCLibClient.durationTolerance + 0.01, false),
        (180.0 - LRCLibClient.durationTolerance - 0.01, false),
    ])
    func toleranceBoundary(candidateDuration: Double, accepted: Bool) {
        let match = LRCLibClient.bestMatch(among: [track(duration: candidateDuration)],
                                           duration: 180)

        #expect((match != nil) == accepted)
    }

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

    @Test("A hit with no duration is treated as unmatched")
    func missingDuration() {
        #expect(LRCLibClient.bestMatch(among: [track(duration: nil)], duration: 180) == nil)
    }
}
