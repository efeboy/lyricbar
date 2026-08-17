import Foundation
import CoreGraphics
import NaturalLanguage

enum LyricReflow {

    static let minChunkDuration: Double = 1.5

    static func expand(_ lines: [LyricLine],
                       trackDuration: Double,
                       width: CGFloat,
                       measure: (String) -> CGFloat = MenuBarMetrics.measurer(),
                       measureShrunk: (String) -> CGFloat =
                        MenuBarMetrics.measurer(fontSize: MenuBarMetrics.minimumFontSize))
    -> [LyricLine] {
        guard width > 0, !lines.isEmpty else { return lines }

        var out: [LyricLine] = []
        out.reserveCapacity(lines.count)

        for (index, line) in lines.enumerated() {
            let start = line.time
            let next = index + 1 < lines.count ? lines[index + 1].time : max(trackDuration, start)
            let window = max(0, next - start)

            guard !line.text.isEmpty, measure(line.text) > width else {
                out.append(line)
                continue
            }

            let parts = split(line.text, limit: width, measure: measure)
            let flashesPastTooFast = window / Double(parts.count) < minChunkDuration
            let readableWhenShrunk = measureShrunk(line.text) <= width

            guard parts.count > 1, !(flashesPastTooFast && readableWhenShrunk) else {
                out.append(line)
                continue
            }

            let shares = parts.map { Double(syllableCount($0)) }
            let total = shares.reduce(0, +)
            guard total > 0 else {
                out.append(line)
                continue
            }

            var time = start
            for (part, share) in zip(parts, shares) {
                out.append(LyricLine(time: time, text: part))
                time += window * (share / total)
            }
        }
        return out
    }

    static func split(_ text: String,
                      limit: CGFloat,
                      measure: (String) -> CGFloat = MenuBarMetrics.measurer()) -> [String] {
        guard limit > 0 else { return [text] }
        guard measure(text) > limit else { return [text] }
        return wordPlan(text, limit: limit, measure: measure)
            ?? graphemePlan(text, limit: limit, measure: measure)
    }

    private enum Tier: Int {
        case punctuation = 0, connective = 1, anySpace = 2
    }

    private struct Plan {
        var count: Int
        var worstTier: Int
        var imbalance: CGFloat
        var parts: [String]

        var rank: (Int, Int, CGFloat) { (count, worstTier, imbalance) }
    }

    private static func wordPlan(_ text: String,
                                 limit: CGFloat,
                                 measure: (String) -> CGFloat) -> [String]? {
        let words = text.split(separator: " ").map(String.init)
        guard words.count > 1 else { return nil }
        let tiers = breakTiers(for: words, in: text)

        var memo = [Int: Plan?]()

        func best(from start: Int) -> Plan? {
            if start == words.count {
                return Plan(count: 0, worstTier: -1, imbalance: 0, parts: [])
            }
            if let cached = memo[start] { return cached }

            var result: Plan?
            for end in (start + 1)...words.count {
                let chunk = words[start..<end].joined(separator: " ")
                let chunkWidth = measure(chunk)
                if chunkWidth > limit { break }
                guard let tail = best(from: end) else { continue }

                let tier = end == words.count ? -1 : tiers[end].rawValue
                let candidate = Plan(count: tail.count + 1,
                                     worstTier: max(tier, tail.worstTier),
                                     imbalance: abs(chunkWidth - limit / 2) + tail.imbalance,
                                     parts: [chunk] + tail.parts)
                if result.map({ candidate.rank < $0.rank }) ?? true {
                    result = candidate
                }
            }
            memo[start] = result
            return result
        }

        guard let plan = best(from: 0), plan.parts.count > 1 else { return nil }
        return plan.parts
    }

    private static func graphemePlan(_ text: String,
                                     limit: CGFloat,
                                     measure: (String) -> CGFloat) -> [String] {
        var parts: [String] = []
        var current = ""

        for character in text {
            let candidate = current + String(character)
            if !current.isEmpty, measure(candidate) > limit {
                parts.append(current)
                current = String(character)
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { parts.append(current) }

        let trimmed = parts
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return trimmed.isEmpty ? [text] : trimmed
    }

    private static func breakTiers(for words: [String], in text: String) -> [Tier] {
        let classes = lexicalClasses(of: text, expecting: words.count)

        var tiers = [Tier](repeating: .anySpace, count: words.count)
        for index in 1..<words.count {
            let endsClause = words[index - 1].unicodeScalars.last
                .map { clauseEnders.contains(Character($0)) } ?? false
            if endsClause {
                tiers[index] = .punctuation
            } else if isConnective(words[index], tag: classes?[index]) {
                tiers[index] = .connective
            }
        }
        return tiers
    }

    private static let clauseEnders: Set<Character> = [",", ".", ";", ":", "!", "?", "—", "–", "-"]

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
        if tag == .conjunction || tag == .preposition { return true }
        let bare = word.lowercased()
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        return connectives.contains(bare)
    }

    private static let connectives: Set<String> = [
        "and", "but", "or", "so", "yet", "that", "when", "while", "who", "which",
        "because", "if", "though", "although", "as", "than", "then", "for", "with",
        "without", "before", "after", "till", "until", "to", "in", "on", "at",
        "of", "from", "like", "where", "how", "why",
    ]

    static func syllableCount(_ phrase: String) -> Int {
        phrase.split(separator: " ").reduce(0) { $0 + syllables(in: String($1)) }
    }

    private static func syllables(in word: String) -> Int {
        let letters = word.lowercased().filter(\.isLetter)
        guard !letters.isEmpty else { return 0 }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]

        var count = 0
        var previousWasVowel = false
        for character in letters {
            let isVowel = vowels.contains(character)
            if isVowel && !previousWasVowel { count += 1 }
            previousWasVowel = isVowel
        }
        if letters.hasSuffix("e") && count > 1 && !letters.hasSuffix("le") { count -= 1 }
        return max(1, count)
    }
}
