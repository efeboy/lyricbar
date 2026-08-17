import Foundation

final class SpotifyBridge: PlaybackBridge {

    let source: PlaybackSource = .spotify

    private static let millisecondThreshold: Double = 10_000

    private let snapshotScript = PlaybackScript.compiled("""
    tell application "Spotify"
        if it is not running then return "\(PlaybackScript.notRunning)"
        set pState to player state as text
        if pState is "\(PlaybackScript.stopped)" then return "\(PlaybackScript.stopped)"
        set theTrack to current track
        return pState & "\(PlaybackScript.unitSeparator)" & (id of theTrack) ¬
            & "\(PlaybackScript.unitSeparator)" & (name of theTrack) ¬
            & "\(PlaybackScript.unitSeparator)" & (artist of theTrack) ¬
            & "\(PlaybackScript.unitSeparator)" & (album of theTrack) ¬
            & "\(PlaybackScript.unitSeparator)" & (duration of theTrack)
    end tell
    """)

    private let positionScript = PlaybackScript.compiled("""
    tell application "Spotify"
        if it is not running then return -1
        return player position
    end tell
    """)

    func position() -> Double? {
        PlaybackScript.position(from: positionScript)
    }

    func snapshot() -> NowPlaying? {
        guard let fields = PlaybackScript.fields(from: snapshotScript),
              let state = PlayerState(rawValue: fields[0]) else { return nil }

        let reported = Double(fields[5]) ?? 0
        let seconds = reported > Self.millisecondThreshold ? reported / 1000 : reported

        return NowPlaying(source: source, state: state, trackID: fields[1],
                          title: fields[2], artist: fields[3], album: fields[4],
                          durationSeconds: seconds)
    }
}
