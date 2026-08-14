import Foundation

// MARK: - LRCLIB client
//
// Endpoints verified against server source (tranxuanthang/lrclib, server/src/router.rs):
//   GET /api/get     - requires track_name + artist_name; album_name & duration optional
//   GET /api/search  - q OR track_name/artist_name/album_name
// Response fields are camelCase: syncedLyrics, plainLyrics, instrumental, duration.
// The server identifies clients via `Lrclib-Client` (preferred over User-Agent) and
// sheds load with 503 + Retry-After when its semaphore is exhausted (errors.rs).

struct LRCLibTrack: Decodable {
    var id: Int
    var trackName: String?
    var artistName: String?
    var duration: Double?
    var instrumental: Bool
    var plainLyrics: String?
    var syncedLyrics: String?
}

enum LyricsFetchResult: Sendable {
    case synced([LyricLine])
    case unavailable      // no synced lyrics, or instrumental
    case retry(after: Double)
}

final class LRCLibClient: Sendable {
    private let base = URL(string: "https://lrclib.net")!
    private let client = "LyricBar v1.0 (https://github.com/local/lyricbar)"

    private func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.timeoutInterval = 12
        r.setValue(client, forHTTPHeaderField: "Lrclib-Client")
        r.setValue(client, forHTTPHeaderField: "User-Agent")
        return r
    }

    func fetch(title: String, artist: String, album: String, duration: Double) async -> LyricsFetchResult {
        // 1. Exact-signature lookup.
        var c = URLComponents(url: base.appendingPathComponent("api/get"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "track_name", value: title),
            .init(name: "artist_name", value: artist),
            .init(name: "album_name", value: album),
            .init(name: "duration", value: String(Int(duration.rounded()))),
        ]
        switch await get(c.url!, decodeArray: false) {
        case .retry(let s): return .retry(after: s)
        case .ok(let tracks):
            if let t = tracks.first, let l = usable(t) { return .synced(l) }
            if let t = tracks.first, t.instrumental { return .unavailable }
        case .failed: break
        }

        // 2. Fall back to search, then pick the closest duration match.
        //    Album names differ between releases (remasters, archive editions),
        //    so signature lookups miss often; duration is the reliable key.
        var s = URLComponents(url: base.appendingPathComponent("api/search"),
                              resolvingAgainstBaseURL: false)!
        s.queryItems = [
            .init(name: "track_name", value: title),
            .init(name: "artist_name", value: artist),
        ]
        switch await get(s.url!, decodeArray: true) {
        case .retry(let sec): return .retry(after: sec)
        case .failed: return .unavailable
        case .ok(let results):
            let candidates = results.filter { $0.syncedLyrics?.isEmpty == false }
            let best = candidates.min {
                abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration)
            }
            // Reject matches more than 5s off - likely a different edit entirely,
            // and wrong-length lyrics drift badly against playback.
            if let b = best, abs((b.duration ?? 0) - duration) <= 5, let l = usable(b) {
                return .synced(l)
            }
            return .unavailable
        }
    }

    private func usable(_ t: LRCLibTrack) -> [LyricLine]? {
        guard !t.instrumental, let s = t.syncedLyrics, !s.isEmpty else { return nil }
        let lines = LRCParser.parse(s)
        return lines.isEmpty ? nil : lines
    }

    private enum GetResult {
        case ok([LRCLibTrack])
        case retry(Double)
        case failed
    }

    private func get(_ url: URL, decodeArray: Bool) async -> GetResult {
        do {
            let (data, resp) = try await URLSession.shared.data(for: request(url))
            guard let http = resp as? HTTPURLResponse else { return .failed }

            if http.statusCode == 503 {
                let after = (http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)) ?? 1
                return .retry(after)
            }
            guard http.statusCode == 200 else { return .failed }

            let dec = JSONDecoder()
            if decodeArray {
                return .ok(try dec.decode([LRCLibTrack].self, from: data))
            }
            return .ok([try dec.decode(LRCLibTrack.self, from: data)])
        } catch {
            return .failed
        }
    }
}
