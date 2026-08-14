import Testing
@testable import LyricBar

// The LRC grammar is the app's only real parsing surface, and it is fed by a
// public database where providers disagree about the fraction separator and its
// digit count. These cases are transcribed from live LRCLIB payloads.

@Suite("LRC parsing")
struct LRCParsingTests {

    @Test("Tags become timed lines, sorted by time")
    func parsesAndSorts() {
        let lines = LRCParser.parse("""
        [00:12.00] second
        [00:03.50] first
        [01:00.00] third
        """)

        #expect(lines.map(\.text) == ["first", "second", "third"])
        #expect(lines.map(\.time) == [3.5, 12.0, 60.0])
    }

    // `[mm:ss.xx]` is the common form, but `[mm:ss:xx]` and 1-3 fraction digits
    // all appear in the wild. A fraction is a decimal, not a fixed hundredths
    // field: "5" is half a second, "05" is a twentieth.
    @Test("Fraction separators and digit counts", arguments: [
        ("[00:01.50] x", 1.5),
        ("[00:01:50] x", 1.5),
        ("[00:01.5] x", 1.5),
        ("[00:01.05] x", 1.05),
        ("[00:01.500] x", 1.5),
        ("[00:01] x", 1.0),
    ])
    func fractionScaling(source: String, expected: Double) {
        let lines = LRCParser.parse(source)
        #expect(lines.count == 1)
        #expect(abs((lines.first?.time ?? -1) - expected) < 1e-9)
    }

    @Test("Minutes past 99 still parse")
    func longMinutes() {
        #expect(LRCParser.parse("[100:30.00] late").first?.time == 6030)
    }

    // A repeated chorus is published as one text with several timestamps; each
    // must become its own line or the chorus shows only on its first pass.
    @Test("One line with several timestamps expands to several lines")
    func repeatedChorus() {
        let lines = LRCParser.parse("[00:10.00][01:20.00][02:30.00] chorus")

        #expect(lines.count == 3)
        #expect(lines.allSatisfy { $0.text == "chorus" })
        #expect(lines.map(\.time) == [10.0, 80.0, 150.0])
    }

    @Test("Untagged lines — metadata headers, blanks — are dropped")
    func skipsUntagged() {
        let lines = LRCParser.parse("""
        [ar: Some Artist]
        [ti: Some Song]

        [00:05.00] only this
        trailing junk
        """)

        #expect(lines.map(\.text) == ["only this"])
    }

    // A bare timestamp marks an instrumental gap. It must survive parsing as an
    // empty line so the model can swap in its placeholder and hold the item width.
    @Test("Bare timestamps survive as empty lines")
    func keepsEmptyLines() {
        let lines = LRCParser.parse("[00:00.00]\n[00:04.00] words")

        #expect(lines.count == 2)
        #expect(lines.first?.text == "")
    }
}

@Suite("Active line lookup")
struct LRCIndexTests {

    private let lines = [
        LyricLine(time: 10, text: "a"),
        LyricLine(time: 20, text: "b"),
        LyricLine(time: 30, text: "c"),
    ]

    @Test("Nothing is active before the first timestamp")
    func beforeStart() {
        #expect(LRCParser.index(at: 0, in: lines) == nil)
        #expect(LRCParser.index(at: 9.999, in: lines) == nil)
    }

    @Test("An empty lyric set has no active line")
    func empty() {
        #expect(LRCParser.index(at: 42, in: []) == nil)
    }

    // The line becomes active exactly at its timestamp and stays active until the
    // next one — off-by-one here would show every line a beat early or late.
    @Test("Boundaries are inclusive at the start of a line", arguments: [
        (10.0, 0), (10.001, 0), (19.999, 0),
        (20.0, 1), (29.999, 1),
        (30.0, 2),
    ])
    func boundaries(position: Double, expected: Int) {
        #expect(LRCParser.index(at: position, in: lines) == expected)
    }

    @Test("The last line stays active past the end of the file")
    func pastEnd() {
        #expect(LRCParser.index(at: 10_000, in: lines) == 2)
    }
}
