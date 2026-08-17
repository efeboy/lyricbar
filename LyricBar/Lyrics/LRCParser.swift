import Foundation

struct LyricLine: Equatable, Sendable {
    var time: Double
    var text: String
}

enum LRCParser {

    static func parse(_ lrc: String) -> [LyricLine] {
        let timestamp = #/\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/#
        var out: [LyricLine] = []

        for row in lrc.components(separatedBy: .newlines) {
            let stamps = Array(row.matches(of: timestamp))
            guard let last = stamps.last else { continue }

            let text = row[last.range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            for stamp in stamps {
                let (_, minutes, seconds, fraction) = stamp.output
                var time = (Double(minutes) ?? 0) * 60 + (Double(seconds) ?? 0)
                if let fraction {
                    time += (Double(fraction) ?? 0) / pow(10, Double(fraction.count))
                }
                out.append(LyricLine(time: time, text: text))
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    static func index(at time: Double, in lines: [LyricLine]) -> Int? {
        guard !lines.isEmpty, time >= lines[0].time else { return nil }

        var low = 0
        var high = lines.count - 1
        var best = 0
        while low <= high {
            let middle = (low + high) / 2
            if lines[middle].time <= time {
                best = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return best
    }
}
