import Foundation

final class MusicBridge: PlaybackBridge {

    let source: PlaybackSource = .appleMusic

    private let snapshotScript = PlaybackScript.compiled("""
    tell application "Music"
        if it is not running then return "\(PlaybackScript.notRunning)"
        set rawState to player state as text
        if rawState is "\(PlaybackScript.stopped)" then return "\(PlaybackScript.stopped)"
        if rawState is "paused" then
            set pState to "paused"
        else
            set pState to "playing"
        end if
        set theTrack to current track
        return pState & "\(PlaybackScript.unitSeparator)" & (persistent ID of theTrack) ¬
            & "\(PlaybackScript.unitSeparator)" & (name of theTrack) ¬
            & "\(PlaybackScript.unitSeparator)" & (artist of theTrack) ¬
            & "\(PlaybackScript.unitSeparator)" & (album of theTrack) ¬
            & "\(PlaybackScript.unitSeparator)" & (duration of theTrack)
    end tell
    """)

    private let positionScript = PlaybackScript.compiled("""
    tell application "Music"
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

        return NowPlaying(source: source, state: state, trackID: fields[1],
                          title: fields[2], artist: fields[3], album: fields[4],
                          durationSeconds: Double(fields[5]) ?? 0)
    }
}
