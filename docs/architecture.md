# Architecture

LyricBar is a single macOS app target with no dependencies. One async poll loop
in `PlaybackModel` reads the players, fetches lyrics, and drives the menu bar
item.

```
Task.sleep(tick) → probeSources(): Spotify | Music (AppleScript) → track changed?
                                              → LRCLibClient.fetch (async, per track)
                                              → LRCParser.parse → [LyricLine] ──┐
                                                                                │
        lines      ──→ previous / current / next triplet (unrendered) ←──────────┤
        menuLines  ──→ LyricReflow.expand(width:) ──→ menu bar item ←────────────┘

        player position + lyricOffset ──→ LRCParser.index(at:) → lineText / currentLine
```

The parsed lines are kept twice. `lines` is the original timing; `menuLines` is
the same track re-split to fit the current box width. Both are `[LyricLine]`, so
`index(at:)` searches them the same way. Changing the width preference or the
screen layout rebuilds only `menuLines`.

## Files

| file | role |
| --- | --- |
| `LyricBarApp.swift` | `App` entry point. An empty `Settings` scene (required by `App`) and an `AppDelegate` that creates the model and the controller, then calls `model.start()`. |
| `StatusItemController.swift` | Owns the `NSStatusItem`: sets `length`, hosts `LyricLabel`, pops up the menu on click and builds it as its own `NSMenuDelegate`, and re-renders via `withObservationTracking`. |
| `LyricLabel.swift` | The SwiftUI view that draws the lyric, and `PassthroughHostingView`, which hosts it inside the status item button. |
| `PlaybackModel.swift` | `@MainActor @Observable`. The poll loop, source selection, position extrapolation, the per-track fetch, the update check, the width preference and screen-change re-snapping, and the per-track timing offset. |
| `ItemPopover.swift` | An `NSPopover` anchored to the item; used for Settings and Tips. |
| `SettingsView.swift` | The width slider, the lyric timing stepper, and Open at Login. See [width.md](width.md) and [lyrics.md](lyrics.md#per-track-timing-offset). |
| `TipsView.swift` | Usage tips shown from **Tips…**. |
| `MenuHeader.swift` | The wrapping SwiftUI header row of the menu. See [menu-bar-item.md](menu-bar-item.md#the-menu). |
| `MenuBarMetrics.swift` | Text measurement, `menuWidth`, `WidthLadder`, screen geometry. |
| `LyricText.swift` | `fittedFontSize`, the font-size backstop. |
| `FitLog.swift` | The `render` logger and number/rect formatters. |
| `UpdateChecker.swift` | GitHub Releases check. See [releasing.md](releasing.md). |
| `LoginItem.swift` | `SMAppService.mainApp` wrapper for Open at Login. |
| `Playback/NowPlaying.swift` | `PlaybackBridge`, `BridgeSnapshot` (`now` / `unavailable` / `denied`), `NowPlaying`, and `PlaybackScript`, the AppleScript plumbing both bridges share. |
| `Playback/SpotifyBridge.swift`, `Playback/MusicBridge.swift` | One `actor` per player, each holding two compiled scripts. |
| `Lyrics/LRCParser.swift` | Parses `[mm:ss.xx]` tags into sorted `LyricLine`s; `index(at:)` binary-searches the active line. |
| `Lyrics/LyricReflow.swift` | Splits lines too wide for the box and times each chunk. See [lyrics.md](lyrics.md). |
| `Lyrics/LRCLibClient.swift` | The LRCLIB client. `Sendable`, runs off the main actor. |

## Source selection

`probeSources()` asks the bridges in order and prefers one that is **playing**.
If none is, it falls back to a **paused** source so its track still shows, and
reports separately whether any source refused Automation. Spotify is listed
first, so it wins ties.

Metadata is probed about once a second, gated on elapsed `ContinuousClock` time.
Player position is read at `tickInterval` (0.5s) and extrapolated between probes
(`lastPosition + elapsed`); the next probe corrects seeks. Use `ContinuousClock`,
not `Date`, for anything that measures elapsed time — wall-clock time jumps on
NTP and daylight-saving changes.

## AppleScript runs on the bridge actors

`NSAppleScript` blocks its thread until the player replies, and the default
Apple Event timeout is about two minutes. The bridges are therefore `actor`s and
`PlaybackBridge` is `Sendable` with `async` methods, so a hung player never
blocks the main actor. Each actor owns its compiled scripts, so one
`NSAppleScript` instance is never used from two threads.

- Every script wraps its commands in
  `with timeout of PlaybackScript.eventTimeoutSeconds seconds` (2s), which bounds
  how long a hung player can stall the poll loop. A timeout is error -1712, which
  resolves to `.unavailable`, so the item falls back to idle.
- Keep `if it is not running` **outside** the timeout block; it is answered
  locally.
- `tick()` re-checks `hidden` and `currentTrackID` after every `await`, because
  either can change while a bridge call is suspended.
- The position sample is stamped with `clock.now` after `position()` returns, so
  probe latency does not skew extrapolation.

Verified live: with Spotify stopped (`kill -STOP`), the main thread stayed idle
in the event loop, the item fell back to `♪` about 2s later, and the lyric
returned about 0.5s after `kill -CONT`.

## Test seams

`PlaybackModel.init` takes its `UserDefaults`, `[PlaybackBridge]` and
`LyricsProvider`, defaulting to the real ones, and only assigns state.
(`LyricsProvider` exists for this seam, not for a second implementation.) Work
starts in `start()`, which only `AppDelegate` calls. Tests construct a model and
never call `start()`.

- `refreshNow()` forces a full metadata probe and awaits one tick.
- `awaitPendingLyrics()` awaits the per-track fetch.
- The test `FakeBridge` is a `@MainActor` class with a `nonisolated let source`,
  which makes it `Sendable` while the `@MainActor` suite mutates it directly.

The test bundle is hosted (`TEST_HOST` is the app). `AppDelegate.isRunningTests`
detects that and creates neither the model nor the status item, so tests never
prompt for Automation, depend on what is playing, or resize the real menu bar.

## Known gaps

- **The previous/current/next triplet is computed but not shown.** It survives
  the removal of the old popover as content for a future richer surface. If none
  arrives, delete it, `lines`' extra role, and their tests.
- **`position()` cannot report a denial.** Only `snapshot()` distinguishes
  `denied`, which is what drives the UI.
- **A hang longer than the timeout re-fetches lyrics.** The player reads as
  unavailable, the track is forgotten, and lyrics are fetched again when it
  answers.
- **No artwork.** It would cost an Apple Event per track on the hot path.
