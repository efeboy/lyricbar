import Foundation

// MARK: - Spotify bridge
//
// Property names verified against `sdef /Applications/Spotify.app`:
//   application: `player state` (stopped/playing/paused), `player position` (real, seconds)
//   track:       `id`, `name`, `artist`, `album`, `duration` (integer, MILLISECONDS in practice)
//
// Two constraints that cost real debugging time, preserved here:
//
//  * `st` is a RESERVED token in AppleScript — `set st to …` is a syntax error
//    on its own. Never use short, grammar-adjacent identifiers for variables.
//
//  * NEVER coerce `player position` to text. AppleScript's `as text` uses the
//    system locale, which here yields a comma decimal ("134,2799") that
//    Double() rejects. Read the numeric descriptor's `doubleValue` instead.

final class SpotifyBridge: PlaybackBridge {
    let source: PlaybackSource = .spotify

    private let snapshotScript: NSAppleScript?
    private let positionScript: NSAppleScript?
    private static let sep = "\u{001F}"   // unlikely to appear in metadata

    init() {
        snapshotScript = NSAppleScript(source: """
        tell application "Spotify"
            if it is not running then return "notrunning"
            set pState to player state as text
            if pState is "stopped" then return "stopped"
            set theTrack to current track
            return pState & "\(Self.sep)" & (id of theTrack) & "\(Self.sep)" & (name of theTrack) ¬
                & "\(Self.sep)" & (artist of theTrack) & "\(Self.sep)" & (album of theTrack) ¬
                & "\(Self.sep)" & (duration of theTrack)
        end tell
        """)
        positionScript = NSAppleScript(source: """
        tell application "Spotify"
            if it is not running then return -1
            return player position
        end tell
        """)
        var err: NSDictionary?
        snapshotScript?.compileAndReturnError(&err)
        positionScript?.compileAndReturnError(&err)
    }

    func position() -> Double? {
        var err: NSDictionary?
        guard let d = positionScript?.executeAndReturnError(&err) else { return nil }
        let v = d.doubleValue
        return v < 0 ? nil : v
    }

    func snapshot() -> NowPlaying? {
        var err: NSDictionary?
        guard let desc = snapshotScript?.executeAndReturnError(&err),
              let raw = desc.stringValue else { return nil }
        if raw == "notrunning" || raw == "stopped" { return nil }

        let parts = raw.components(separatedBy: Self.sep)
        guard parts.count >= 6, let state = PlayerState(rawValue: parts[0]) else { return nil }

        // `duration` is documented as seconds but the app reports milliseconds
        // (probe: 217773 for a 3:37 track). Normalise defensively.
        let rawDuration = Double(parts[5]) ?? 0
        let seconds = rawDuration > 10_000 ? rawDuration / 1000.0 : rawDuration

        return NowPlaying(source: source, state: state, trackID: parts[1],
                          title: parts[2], artist: parts[3], album: parts[4],
                          durationSeconds: seconds)
    }
}
