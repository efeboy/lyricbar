import Foundation

// MARK: - Apple Music bridge
//
// Property names verified against `sdef /System/Applications/Music.app`:
//   application: `player state` (stopped/playing/paused/fast forwarding/rewinding),
//                `player position` (real, SECONDS — unlike Spotify)
//   track:       `persistent ID` (text, stable across launches), `name`,
//                `artist`, `album`, `duration` (real, SECONDS)
//
// Same two rules as the Spotify bridge apply: avoid reserved short identifiers,
// and read `player position` as a number, never coerced to locale-formatted text.

final class MusicBridge: PlaybackBridge {
    let source: PlaybackSource = .appleMusic

    private let snapshotScript: NSAppleScript?
    private let positionScript: NSAppleScript?
    private static let sep = "\u{001F}"

    init() {
        // `player state` has more values than Spotify's; collapse fast-forward /
        // rewind into "playing" so the shared PlayerState enum stays small.
        snapshotScript = NSAppleScript(source: """
        tell application "Music"
            if it is not running then return "notrunning"
            set rawState to player state as text
            if rawState is "stopped" then return "stopped"
            if rawState is "paused" then
                set pState to "paused"
            else
                set pState to "playing"
            end if
            set theTrack to current track
            return pState & "\(Self.sep)" & (persistent ID of theTrack) & "\(Self.sep)" & (name of theTrack) ¬
                & "\(Self.sep)" & (artist of theTrack) & "\(Self.sep)" & (album of theTrack) ¬
                & "\(Self.sep)" & (duration of theTrack)
        end tell
        """)
        positionScript = NSAppleScript(source: """
        tell application "Music"
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

        // Music already reports seconds, so no millisecond normalisation.
        let seconds = Double(parts[5]) ?? 0

        return NowPlaying(source: source, state: state, trackID: parts[1],
                          title: parts[2], artist: parts[3], album: parts[4],
                          durationSeconds: seconds)
    }
}
