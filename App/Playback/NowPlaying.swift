import Foundation

// MARK: - Playback source model
//
// A single normalized snapshot of "what is playing right now", regardless of
// whether it came from Spotify or Apple Music. The rest of the app never sees
// the source-specific AppleScript quirks — those are absorbed by the bridges.

enum PlaybackSource: String, Sendable {
    case spotify = "Spotify"
    case appleMusic = "Music"
}

enum PlayerState: String, Sendable {
    case stopped, playing, paused
}

/// One immutable observation of the active player.
struct NowPlaying: Equatable, Sendable {
    var source: PlaybackSource
    var state: PlayerState
    var trackID: String
    var title: String
    var artist: String
    var album: String
    var durationSeconds: Double
}

/// A playback source that can be interrogated over AppleScript.
///
/// Both concrete bridges wrap precompiled `NSAppleScript` objects. Each call is
/// an Apple Event round-trip to the target app and is by far the dominant cost
/// of this app, so callers poll metadata about once a second and position at the
/// finer tick rate.
protocol PlaybackBridge: AnyObject {
    var source: PlaybackSource { get }
    /// Current track + state, or nil if the app is not running / stopped.
    func snapshot() -> NowPlaying?
    /// Playback position in seconds, or nil if unavailable.
    func position() -> Double?
}
