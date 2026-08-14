import Foundation

// MARK: - LRC parsing
//
// Format confirmed from live LRCLIB data: lines tagged `[mm:ss.xx]`.
// Some providers use `[mm:ss:xx]` or 3-digit fractions, so both are accepted.
// A single line may carry multiple timestamps (repeated chorus).

struct LyricLine: Equatable, Sendable {
    var time: Double
    var text: String
}

enum LRCParser {
    private static let tagPattern = try! NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)

    static func parse(_ lrc: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for raw in lrc.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = tagPattern.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty, let last = matches.last else { continue }

            let text = ns.substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)

            for m in matches {
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var frac = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let fs = ns.substring(with: m.range(at: 3))
                    frac = (Double(fs) ?? 0) / pow(10, Double(fs.count))
                }
                out.append(LyricLine(time: min * 60 + sec + frac, text: text))
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    /// Index of the line active at `t`, or nil before the first line.
    static func index(at t: Double, in lines: [LyricLine]) -> Int? {
        guard !lines.isEmpty, t >= lines[0].time else { return nil }
        var lo = 0, hi = lines.count - 1, best = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= t { best = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return best
    }
}
