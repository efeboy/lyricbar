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

enum BridgeSnapshot: Equatable, Sendable {
    case now(NowPlaying)
    case unavailable
    case denied
}

protocol PlaybackBridge: Sendable {
    var source: PlaybackSource { get }
    func snapshot() async -> BridgeSnapshot
    func position() async -> Double?
}

enum PlaybackScript {

    static let eventTimeoutSeconds = 2
    static let unitSeparator = "\u{001F}"
    static let notRunning = "notrunning"
    static let stopped = "stopped"
    static let expectedFieldCount = 6
    static let permissionDenied = -1743
    static let consentRequired = -1744

    enum Fields: Equatable {
        case values([String])
        case unavailable
        case denied
    }

    static func compiled(_ source: String) -> NSAppleScript? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.compileAndReturnError(&error)
        return script
    }

    static func isDenial(_ error: NSDictionary?) -> Bool {
        guard let code = error?[NSAppleScript.errorNumber] as? Int else { return false }
        return code == permissionDenied || code == consentRequired
    }

    static func position(from script: NSAppleScript?) -> Double? {
        var error: NSDictionary?
        guard let descriptor = script?.executeAndReturnError(&error) else { return nil }
        let value = descriptor.doubleValue
        return value < 0 ? nil : value
    }

    static func fields(from script: NSAppleScript?) -> Fields {
        var error: NSDictionary?
        guard let descriptor = script?.executeAndReturnError(&error) else {
            return isDenial(error) ? .denied : .unavailable
        }
        guard let raw = descriptor.stringValue,
              raw != notRunning, raw != stopped else { return .unavailable }

        let values = raw.components(separatedBy: unitSeparator)
        return values.count >= expectedFieldCount ? .values(values) : .unavailable
    }
}