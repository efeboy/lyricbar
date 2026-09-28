import Foundation

struct Release: Decodable, Equatable, Sendable {
    let tagName: String
    let pageURL: URL

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case pageURL = "html_url"
    }
}

struct UpdateChecker: Sendable {

    static let checkInterval: Duration = .seconds(24 * 60 * 60)

    private static let latestRelease = URL(string: "https://api.github.com/repos/efeboy/lyricbar/releases/latest")!
    private static let timeout: TimeInterval = 12

    let currentVersion: String

    func newerRelease() async -> Release? {
        var request = URLRequest(url: Self.latestRelease)
        request.timeoutInterval = Self.timeout
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("LyricBar/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data),
              Self.isNewer(release.tagName, than: currentVersion) else { return nil }
        return release
    }

    static func isNewer(_ tag: String, than current: String) -> Bool {
        guard let candidate = components(tag), let installed = components(current) else { return false }
        for index in 0..<max(candidate.count, installed.count) {
            let lhs = index < candidate.count ? candidate[index] : 0
            let rhs = index < installed.count ? installed[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    static func components(_ version: String) -> [Int]? {
        let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }
    }
}
