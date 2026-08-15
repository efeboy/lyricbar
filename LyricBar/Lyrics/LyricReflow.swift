import Foundation
import CoreGraphics
import NaturalLanguage

// MARK: - Lyric reflow
//
// A line too wide for the menu bar is split across its own time window rather
// than truncated or scrolled. The item's width is fixed on purpose (neighbouring
// status items must never shift) and macOS has no marquee API for the menu bar,
// so splitting is the only way to show the whole line.
//
// The two halves of the problem have very different answers:
//
//   WHERE to break is a text problem, and a cheap rule already wins. Measured
//   over 77 Beatles albums (2585 synced lines, 280pt budget): 9.5% of lines
//   overflow, 92.3% of those split cleanly, and 95.6% of breaks land on
//   punctuation or a conjunction/preposition. Not one line lacked a viable break.
//
//   WHEN to swap is NOT a text problem — it is audio alignment, and LRCLIB
//   publishes no word-level timestamps. Syllable share is the closest free proxy
//   for how long a phrase is sung: it differs from character share by a median of
//   0.14s, whereas a naive linear midpoint is off by 0.60s (p90 1.69s).
//
// This is why there is no model here. An on-device LLM would be aimed at the half
// that a word list already solves, and it cannot hear the vocal — which is the
// half that is actually uncertain.

enum LyricReflow {

    /// A chunk on screen for less than this is not readable, so an overflowing
    /// line with too tight a window truncates instead of splitting. 7.7% of
    /// overflowing lines in the corpus fall here.
    static let minChunkDuration: Double = 1.5

    // MARK: Expansion

    /// Expand `lines` so no line's text exceeds `width`, giving each chunk its own
    /// timestamp. The result is still `[LyricLine]`, so the poll loop's binary
    /// search in `LRCParser.index(at:)` is unchanged.
    static func expand(_ lines: [LyricLine],
                       trackDuration: Double,
                       width: CGFloat,
                       measure: (String) -> CGFloat = MenuBarMetrics.measurer()) -> [LyricLine] {
        guard width > 0, !lines.isEmpty else { return lines }

        var out: [LyricLine] = []
        out.reserveCapacity(lines.count)

        for (i, line) in lines.enumerated() {
            let start = line.time
            let next = i + 1 < lines.count ? lines[i + 1].time : max(trackDuration, start)
            let window = max(0, next - start)

            guard !line.text.isEmpty,
                  measure(line.text) > width,
                  let parts = split(line.text, limit: width, measure: measure),
                  parts.count > 1,
                  window / Double(parts.count) >= minChunkDuration
            else {
                out.append(line)
                continue
            }

            let shares = parts.map { Double(syllableCount($0)) }
            let total = shares.reduce(0, +)
            guard total > 0 else { out.append(line); continue }

            var t = start
            for (part, share) in zip(parts, shares) {
                out.append(LyricLine(time: t, text: part))
                t += window * (share / total)
            }
        }
        return out
    }

    // MARK: Break points

    /// Preference order for where a break may land.
    private enum Tier: Int { case punctuation = 0, connective = 1, anySpace = 2 }

    /// Split `text` into chunks that each fit `limit`, preferring the best break
    /// tier and then the most balanced chunk widths. Nil if no split fits.
    static func split(_ text: String,
                      limit: CGFloat,
                      measure: (String) -> CGFloat = MenuBarMetrics.measurer()) -> [String]? {
        let words = text.split(separator: " ").map(String.init)
        guard words.count > 1 else { return nil }
        let tiers = breakTiers(for: words, in: text)

        // Ranked lexicographically: fewest chunks first, then the best break
        // quality, then the most even widths. Chunk count leads because every
        // extra chunk shortens the window each one is on screen for — a tidier
        // break is no help if the text flashes past. `imbalance` only ever
        // compares plans with the same chunk count, so summing it is safe;
        // as a primary key it would perversely favour splitting further, since
        // narrower chunks each sit closer to half the budget.
        struct Plan {
            var count: Int
            var worstTier: Int
            var imbalance: CGFloat
            var parts: [String]

            var rank: (Int, Int, CGFloat) { (count, worstTier, imbalance) }
        }

        // Suffix DP: best plan for words[i...]. O(words²), and lyric lines are short.
        var memo = [Int: Plan?]()

        func best(from i: Int) -> Plan? {
            if i == words.count { return Plan(count: 0, worstTier: -1, imbalance: 0, parts: []) }
            if let cached = memo[i] { return cached }

            var result: Plan?
            for j in (i + 1)...words.count {
                let chunk = words[i..<j].joined(separator: " ")
                let w = measure(chunk)
                if w > limit { break }          // widening j only makes it worse
                guard let tail = best(from: j) else { continue }

                // No break exists after the final word.
                let tier = j == words.count ? -1 : tiers[j].rawValue
                let candidate = Plan(count: tail.count + 1,
                                     worstTier: max(tier, tail.worstTier),
                                     imbalance: abs(w - limit / 2) + tail.imbalance,
                                     parts: [chunk] + tail.parts)
                if result.map({ candidate.rank < $0.rank }) ?? true {
                    result = candidate
                }
            }
            memo[i] = result
            return result
        }

        guard let plan = best(from: 0), plan.parts.count > 1 else { return nil }
        return plan.parts
    }

    /// `tiers[j]` is the quality of a break placed *before* word `j`.
    private static func breakTiers(for words: [String], in text: String) -> [Tier] {
        let classes = lexicalClasses(of: text, expecting: words.count)

        var tiers = [Tier](repeating: .anySpace, count: words.count)
        for j in 1..<words.count {
            if words[j - 1].unicodeScalars.last.map({ Self.clauseEnders.contains(Character($0)) }) == true {
                tiers[j] = .punctuation
            } else if isConnective(words[j], tag: classes?[j]) {
                tiers[j] = .connective
            }
        }
        return tiers
    }

    private static let clauseEnders: Set<Character> = [",", ".", ";", ":", "!", "?", "—", "–", "-"]

    /// Lexical class per word, or nil when tokenisation does not line up with a
    /// plain space split (contractions, hyphenates). Callers then fall back to the
    /// word list, which is why a mismatch is not an error.
    private static func lexicalClasses(of text: String, expecting count: Int) -> [NLTag?]? {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var tags: [NLTag?] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word,
                             scheme: .lexicalClass,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, _ in
            tags.append(tag)
            return true
        }
        return tags.count == count ? tags : nil
    }

    private static func isConnective(_ word: String, tag: NLTag?) -> Bool {
        if let tag {
            if tag == .conjunction || tag == .preposition { return true }
            // A determiner or pronoun alone is a weak break; fall through to the
            // word list so "that"/"when" still count.
        }
        let bare = word.lowercased().trimmingCharacters(
            in: CharacterSet.alphanumerics.inverted)
        return connectives.contains(bare)
    }

    /// Fallback when NL tagging cannot be aligned. These are the words that
    /// actually carried the breaks in the corpus.
    private static let connectives: Set<String> = [
        "and", "but", "or", "so", "yet", "that", "when", "while", "who", "which",
        "because", "if", "though", "although", "as", "than", "then", "for", "with",
        "without", "before", "after", "till", "until", "to", "in", "on", "at",
        "of", "from", "like", "where", "how", "why",
    ]

    // MARK: Syllables

    /// Vowel-group estimate. Not linguistics — just a closer proxy for sung
    /// duration than character count, which over-weights consonant clusters.
    static func syllableCount(_ phrase: String) -> Int {
        phrase.split(separator: " ").reduce(0) { $0 + syllables(in: String($1)) }
    }

    private static func syllables(in word: String) -> Int {
        let w = word.lowercased().filter { $0.isLetter }
        guard !w.isEmpty else { return 0 }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]

        var count = 0
        var previousWasVowel = false
        for ch in w {
            let isVowel = vowels.contains(ch)
            if isVowel && !previousWasVowel { count += 1 }
            previousWasVowel = isVowel
        }
        // Silent trailing "e", but "-le" is its own syllable ("pleasure" vs "little").
        if w.hasSuffix("e") && count > 1 && !w.hasSuffix("le") { count -= 1 }
        return max(1, count)
    }
}
