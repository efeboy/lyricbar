import Testing
import CoreGraphics
@testable import LyricBar

// The menu bar item is fixed-width on purpose, so an over-wide line has to be
// split across its own time window. These tests pin the two halves of that rule:
// WHERE the break lands (a word-list problem, solved) and WHEN the chunk swaps
// (a syllable-share proxy, since LRCLIB has no word-level timestamps).
//
// Every case measures 1pt per character rather than calling into the system
// font. Real metrics would make the expected splits drift with the OS version,
// and none of the logic under test cares where the widths come from.

@Suite("Lyric reflow")
struct LyricReflowTests {

    private let measure: (String) -> CGFloat = { CGFloat($0.count) }

    // Girl, verse 1 — the running example in the spec.
    private let girlLine = "Was the sky so grey at dawn that the rain would find its way?"

    // MARK: Where to break

    @Test("Breaks on a connective when there is no punctuation")
    func breaksOnConnective() {
        let parts = LyricReflow.split(girlLine, limit: 40, measure: measure)

        #expect(parts == ["Was the sky so grey at dawn",
                          "that the rain would find its way?"])
    }

    // Punctuation outranks a connective even when the connective would give more
    // balanced chunks — a comma is where the singer actually pauses.
    @Test("Punctuation outranks a connective")
    func prefersPunctuation() {
        let parts = LyricReflow.split("I kept the old keys, so I would find the way back",
                                      limit: 35, measure: measure)

        #expect(parts == ["I kept the old keys,", "so I would find the way back"])
    }

    @Test("Every chunk fits the limit")
    func chunksFit() throws {
        let parts = try #require(LyricReflow.split(girlLine, limit: 24, measure: measure))

        #expect(parts.count > 2)
        #expect(parts.allSatisfy { measure($0) <= 24 })
        #expect(parts.joined(separator: " ") == girlLine)
    }

    @Test("A single word can never be split")
    func singleWord() {
        #expect(LyricReflow.split("supercalifragilistic", limit: 5, measure: measure) == nil)
    }

    // A word wider than the whole budget leaves no viable plan at all; the caller
    // falls back to truncating that line.
    @Test("Nil when no arrangement fits")
    func unsplittable() {
        #expect(LyricReflow.split("antidisestablishmentarianism now", limit: 10, measure: measure) == nil)
    }

    // MARK: When to swap

    @Test("Chunk times divide the window by syllable share")
    func timesFollowSyllables() {
        let expanded = LyricReflow.expand([LyricLine(time: 90, text: girlLine),
                                           LyricLine(time: 96, text: "Did we ever look back")],
                                          trackDuration: 150, width: 40, measure: measure)

        // Both halves are seven syllables, so the swap lands on the midpoint.
        #expect(expanded.count == 3)
        #expect(expanded[0].time == 90)
        #expect(abs(expanded[1].time - 93) < 0.001)
        #expect(expanded[2].time == 96)
    }

    // Splitting a line whose window is too short would flash a chunk faster than
    // it can be read; truncation is the better failure there.
    @Test("A window too short to hold both chunks is left whole")
    func refusesTightWindow() {
        let line = LyricLine(time: 90, text: girlLine)
        let expanded = LyricReflow.expand([line, LyricLine(time: 92, text: "next")],
                                          trackDuration: 150, width: 40, measure: measure)

        #expect(expanded == [line, LyricLine(time: 92, text: "next")])
    }

    @Test("Lines that already fit pass through untouched")
    func passThrough() {
        let lines = [LyricLine(time: 0, text: "short"), LyricLine(time: 5, text: "also short")]

        #expect(LyricReflow.expand(lines, trackDuration: 60, width: 40, measure: measure) == lines)
    }

    // `LRCParser.index(at:)` binary-searches the result, so expansion must not
    // disturb the ordering it relies on.
    @Test("Output stays sorted by time")
    func staysSorted() {
        let expanded = LyricReflow.expand([LyricLine(time: 10, text: girlLine),
                                           LyricLine(time: 20, text: girlLine),
                                           LyricLine(time: 30, text: "end")],
                                          trackDuration: 40, width: 24, measure: measure)

        #expect(expanded == expanded.sorted { $0.time < $1.time })
    }

    // The final line has no successor, so its window runs to the end of the track.
    @Test("The last line's window runs to the track duration")
    func lastLineUsesDuration() {
        let expanded = LyricReflow.expand([LyricLine(time: 100, text: girlLine)],
                                          trackDuration: 110, width: 40, measure: measure)

        #expect(expanded.count == 2)
        #expect(expanded[1].time > 100 && expanded[1].time < 110)
    }

    // MARK: Syllables

    @Test("Vowel groups estimate sung length", arguments: [
        ("young", 1),
        ("pleasure", 2),   // silent trailing "e"
        ("little", 2),     // but "-le" is its own syllable
        ("the", 1),        // never below one
        ("Was the sky so grey at dawn", 7),
    ])
    func syllables(phrase: String, expected: Int) {
        #expect(LyricReflow.syllableCount(phrase) == expected)
    }
}
