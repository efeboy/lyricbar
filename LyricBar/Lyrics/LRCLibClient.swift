import Foundation

struct LRCLibTrack: Decodable, Sendable {
    let id: Int
    let trackName: String?
    let artistName: String?
    let duration: Double?
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?
}

enum LyricsFetchResult: Sendable {
    case synced([LyricLine])
    case unavailable
    case retry(after: Double)
}

final class LRCLibClient: Sendable {

    static let durationTolerance: Double = 5

    private static let base = URL(string: "https://lrclib.net")!
    private static let identifier = "LyricBar v1.0 (https://github.com/local/lyricbar)"
    private static let timeout: TimeInterval = 12
    private static let backpressureStatus = 503
    private static let defaultRetryAfter: Double = 1

    func fetch(title: String, artist: String, album: String, duration: Double) async -> LyricsFetchResult {
        let signature = Self.endpoint("api/get", [
            .init(name: "track_name", value: title),
            .init(name: "artist_name", value: artist),
            .init(name: "album_name", value: album),
            .init(name: "duration", value: String(Int(duration.rounded()))),
        ])

        switch await load(signature, expectingList: false) {
        case .retry(let after):
            return .retry(after: after)
        case .ok(let tracks):
            if let track = tracks.first {
                if let lines = Self.lines(from: track) { return .synced(lines) }
                if track.instrumental { return .unavailable }
            }
        case .failed:
            break
        }

        let search = Self.endpoint("api/search", [
            .init(name: "track_name", value: title),
            .init(name: "artist_name", value: artist),
        ])

        switch await load(search, expectingList: true) {
        case .retry(let after):
            return .retry(after: after)
        case .failed:
            return .unavailable
        case .ok(let results):
            guard let match = Self.bestMatch(among: results, duration: duration),
                  let lines = Self.lines(from: match) else { return .unavailable }
            return .synced(lines)
        }
    }

    static func bestMatch(among results: [LRCLibTrack], duration: Double) -> LRCLibTrack? {
        let synced = results.filter { $0.syncedLyrics?.isEmpty == false }
        guard let closest = synced.min(by: {
            abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration)
        }) else { return nil }
        return abs((closest.duration ?? 0) - duration) <= durationTolerance ? closest : nil
    }

    private static func lines(from track: LRCLibTrack) -> [LyricLine]? {
        guard !track.instrumental,
              let synced = track.syncedLyrics, !synced.isEmpty else { return nil }
        let lines = LRCParser.parse(synced)
        return lines.isEmpty ? nil : lines
    }

    private static func endpoint(_ path: String, _ query: [URLQueryItem]) -> URL {
        base.appending(path: path).appending(queryItems: query)
    }

    private static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(identifier, forHTTPHeaderField: "Lrclib-Client")
        request.setValue(identifier, forHTTPHeaderField: "User-Agent")
        return request
    }

    private enum Response {
        case ok([LRCLibTrack])
        case retry(Double)
        case failed
    }

    private func load(_ url: URL, expectingList: Bool) async -> Response {
        do {
            let (data, response) = try await URLSession.shared.data(for: Self.request(for: url))
            guard let http = response as? HTTPURLResponse else { return .failed }

            if http.statusCode == Self.backpressureStatus {
                let after = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                return .retry(after ?? Self.defaultRetryAfter)
            }
            guard http.statusCode == 200 else { return .failed }

            let decoder = JSONDecoder()
            if expectingList {
                return .ok(try decoder.decode([LRCLibTrack].self, from: data))
            }
            return .ok([try decoder.decode(LRCLibTrack.self, from: data)])
        } catch {
            return .failed
        }
    }
}
