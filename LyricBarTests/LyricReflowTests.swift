import Testing
import CoreGraphics
@testable import LyricBar

@Suite("Lyric reflow")
@MainActor
struct LyricReflowTests {

    private let measure: (String) -> CGFloat = { CGFloat($0.count) }
    private let measureShrunk: (String) -> CGFloat = { CGFloat($0.count) * 9 / 13 }

    private let girlLine = "Was the sky so grey at dawn that the rain would find its way?"

    private func expand(_ lines: [LyricLine], trackDuration: Double, width: CGFloat) -> [LyricLine] {
        LyricReflow.expand(lines, trackDuration: trackDuration, width: width,
                           measure: measure, measureShrunk: measureShrunk)
    }

    private func letters(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    @Test("Breaks on a connective when there is no punctuation")
    func breaksOnConnective() {
        let parts = LyricReflow.split(girlLine, limit: 40, measure: measure)

        #expect(parts == ["Was the sky so grey at dawn",
                          "that the rain would find its way?"])
    }

    @Test("Punctuation outranks a connective")
    func prefersPunctuation() {
        let parts = LyricReflow.split("I kept the old keys, so I would find the way back",
                                      limit: 35, measure: measure)

        #expect(parts == ["I kept the old keys,", "so I would find the way back"])
    }

    @Test("Every chunk fits the limit")
    func chunksFit() {
        let parts = LyricReflow.split(girlLine, limit: 24, measure: measure)

        #expect(parts.count > 2)
        #expect(parts.allSatisfy { measure($0) <= 24 })
        #expect(parts.joined(separator: " ") == girlLine)
    }

    @Test("A line that already fits comes back whole")
    func fittingLineIsOneChunk() {
        #expect(LyricReflow.split("Girl", limit: 40, measure: measure) == ["Girl"])
    }

    @Test("A word wider than the whole box is broken, never dropped")
    func oversizedWordIsBroken() {
        let parts = LyricReflow.split("supercalifragilistic", limit: 5, measure: measure)

        #expect(parts.count > 1)
        #expect(parts.allSatisfy { measure($0) <= 5 })
        #expect(parts.joined() == "supercalifragilistic")
    }

    @Test("A line containing an oversized word still keeps every letter")
    func oversizedWordInALine() {
        let line = "antidisestablishmentarianism now"
        let parts = LyricReflow.split(line, limit: 10, measure: measure)

        #expect(parts.count > 1)
        #expect(parts.allSatisfy { measure($0) <= 10 })
        #expect(letters(parts.joined()) == letters(line))
    }

    @Test("Chunk times divide the window by syllable share")
    func timesFollowSyllables() {
        let expanded = expand([LyricLine(time: 90, text: girlLine),
                               LyricLine(time: 96, text: "Did we ever look back")],
                              trackDuration: 150, width: 40)

        #expect(expanded.count == 3)
        #expect(expanded[0].time == 90)
        #expect(abs(expanded[1].time - 93) < 0.001)
        #expect(expanded[2].time == 96)
    }

    @Test("A tight window keeps the line whole when shrinking can fit it")
    func tightWindowShrinksInsteadOfSplitting() {
        let line = LyricLine(time: 90, text: girlLine)
        let next = LyricLine(time: 92, text: "next")

        #expect(expand([line, next], trackDuration: 150, width: 50) == [line, next])
    }

    @Test("A tight window still splits when shrinking cannot fit it")
    func tightWindowSplitsRatherThanHide() {
        let line = LyricLine(time: 90, text: girlLine)
        let expanded = expand([line, LyricLine(time: 92, text: "next")],
                              trackDuration: 150, width: 30)

        #expect(expanded.count > 2)
        #expect(expanded.dropLast().allSatisfy { measure($0.text) <= 30 })
    }

    @Test("Lines that already fit pass through untouched")
    func passThrough() {
        let lines = [LyricLine(time: 0, text: "short"), LyricLine(time: 5, text: "also short")]

        #expect(expand(lines, trackDuration: 60, width: 40) == lines)
    }

    @Test("Output stays sorted by time")
    func staysSorted() {
        let expanded = expand([LyricLine(time: 10, text: girlLine),
                               LyricLine(time: 20, text: girlLine),
                               LyricLine(time: 30, text: "end")],
                              trackDuration: 40, width: 24)

        #expect(expanded == expanded.sorted { $0.time < $1.time })
    }

    @Test("The last line's window runs to the track duration")
    func lastLineUsesDuration() {
        let expanded = expand([LyricLine(time: 100, text: girlLine)],
                              trackDuration: 110, width: 40)

        #expect(expanded.count == 2)
        #expect(expanded[1].time > 100 && expanded[1].time < 110)
    }

    @Test("Vowel groups estimate sung length", arguments: [
        ("young", 1),
        ("pleasure", 2),
        ("little", 2),
        ("the", 1),
        ("Was the sky so grey at dawn", 7),
    ])
    func syllables(phrase: String, expected: Int) {
        #expect(LyricReflow.syllableCount(phrase) == expected)
    }
}

@Suite("No truncation")
@MainActor
struct NoTruncationTests {

    private static let lines = [
        "Girl",
        "Was the sky so grey at dawn that the rain would find its way?",
        "I kept the old keys, so I would find the way back",
        "Supercalifragilisticexpialidocious",
        "antidisestablishmentarianism now",
        "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
    ]

    private func letters(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    @Test("Every rendered chunk fits its box at real menu bar metrics",
          arguments: [80.0, 120.0, 250.0, 360.0, 556.0])
    func chunksFitTheBox(box: CGFloat) {
        for (index, line) in Self.lines.enumerated() {
            let expanded = LyricReflow.expand([LyricLine(time: 0, text: line)],
                                              trackDuration: 30, width: box)
            for (position, chunk) in expanded.enumerated() {
                let size = LyricImage.fittedFontSize(for: chunk.text, boxWidth: box)
                let width = MenuBarMetrics.textWidth(chunk.text, fontSize: size)

                #expect(width <= box,
                        "line \(index) chunk \(position): \(width)pt at \(size)pt exceeds \(box)pt")
                #expect(size >= MenuBarMetrics.minimumFontSize)
            }
        }
    }

    @Test("No characters are lost on the way to the menu bar",
          arguments: [80.0, 120.0, 250.0, 360.0, 556.0])
    func nothingIsDropped(box: CGFloat) {
        for (index, line) in Self.lines.enumerated() {
            let expanded = LyricReflow.expand([LyricLine(time: 0, text: line)],
                                              trackDuration: 30, width: box)

            #expect(letters(expanded.map(\.text).joined()) == letters(line),
                    "line \(index) lost characters at \(box)pt")
        }
    }

    @Test("A tight window never costs a single character",
          arguments: [80.0, 250.0])
    func nothingIsDroppedInATightWindow(box: CGFloat) {
        for (index, line) in Self.lines.enumerated() {
            let expanded = LyricReflow.expand([LyricLine(time: 0, text: line),
                                               LyricLine(time: 1, text: "next")],
                                              trackDuration: 30, width: box)
            let shown = expanded.prefix(while: { $0.text != "next" })

            #expect(letters(shown.map(\.text).joined()) == letters(line),
                    "line \(index) lost characters at \(box)pt")
        }
    }
}
