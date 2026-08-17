import Foundation

enum PlaybackSource: String, Sendable {
    case spotify = "Spotify"
    case appleMusic = "Music"
}

enum PlayerState: String, Sendable {
    case stopped, playing, paused
}

struct NowPlaying: Equatable, Sendable {
    var source: PlaybackSource
    var state: PlayerState
    var trackID: String
    var title: String
    var artist: String
    var album: String
    var durationSeconds: Double
}

protocol PlaybackBridge: AnyObject {
    var source: PlaybackSource { get }
    func snapshot() -> NowPlaying?
    func position() -> Double?
}

enum PlaybackScript {
    static let unitSeparator = "\u{001F}"
    static let notRunning = "notrunning"
    static let stopped = "stopped"
    static let expectedFieldCount = 6

    static func compiled(_ source: String) -> NSAppleScript? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.compileAndReturnError(&error)
        return script
    }

    static func position(from script: NSAppleScript?) -> Double? {
        var error: NSDictionary?
        guard let descriptor = script?.executeAndReturnError(&error) else { return nil }
        let value = descriptor.doubleValue
        return value < 0 ? nil : value
    }

    static func fields(from script: NSAppleScript?) -> [String]? {
        var error: NSDictionary?
        guard let descriptor = script?.executeAndReturnError(&error),
              let raw = descriptor.stringValue,
              raw != notRunning, raw != stopped else { return nil }

        let fields = raw.components(separatedBy: unitSeparator)
        return fields.count >= expectedFieldCount ? fields : nil
    }
}
