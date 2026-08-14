# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

LyricBar is a macOS menu bar app that shows time-synced lyrics for whatever
**Spotify or Apple Music** is currently playing. It is a SwiftUI `MenuBarExtra`
app with no third-party dependencies. Sources live under `LyricBar/`; the app is
built from `LyricBar.xcodeproj`, a standard Xcode **macOS App target** (not SwiftPM
— an app bundle is required for `MenuBarExtra` and `SMAppService`).

## Build, install, run

`open LyricBar.xcodeproj`, then build/run the **LyricBar** scheme (⌘R). There is
no `swift build` step and no `launchctl`/`codesign` deploy dance anymore — that
was the old bare-executable design and it is gone.

The target is already configured this way; each of these is load-bearing, so
don't "clean them up":

- Deployment target **macOS 14.0** (`MenuBarExtra`/`SMAppService` are 13+, but the
  `@Observable` model requires 14).
- Bundle identifier **`net.local.lyricbar`** — `SMAppService.mainApp` keys off it.
- **Hardened Runtime on**, **App Sandbox off** (`ENABLE_APP_SANDBOX = NO`),
  entitlements at `LyricBar/LyricBar.entitlements` (sending Apple Events to
  Spotify/Music is incompatible with the sandbox without discouraged temporary
  exceptions).
- **No `Info.plist` file.** Xcode generates it from `INFOPLIST_KEY_*` build
  settings. `INFOPLIST_KEY_LSUIElement = YES` keeps the app out of the Dock and
  app switcher, and `INFOPLIST_KEY_NSAppleEventsUsageDescription` supplies the
  Automation prompt string — without that string the prompt never appears and
  lyrics silently never load.
- `LyricBar/` is a **synchronized folder group** (Xcode 16+): files on disk are
  in the target automatically. Add a `.swift` file to the folder and it compiles;
  there is no pbxproj membership to edit. Keep non-source files (docs, notes) out
  of that folder so they aren't swept into the bundle.
- **Swift 6 language mode**, but deliberately *without* Xcode's newer
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY`
  defaults. Either one would pull `LRCLibClient` onto the main actor and run its
  JSON decoding there, quietly undoing the off-main-actor design below.

"Open at login" is a menu toggle backed by `SMAppService.mainApp`; the system
tracks it under System Settings → General → Login Items. Quitting no longer has to
disable it (there is no `KeepAlive` to fight).

## Tests

`LyricBarTests` is a Swift Testing bundle covering the pure logic: `LRCParser`,
`LRCParser.index(at:)`, and `LRCLibClient.bestMatch(among:duration:)` — the LRCLIB
duration matching, split out of `fetch` precisely so it can be tested without the
network.

```sh
xcodebuild -project LyricBar.xcodeproj -scheme LyricBar test
```

It is a **hosted** bundle (`TEST_HOST` is the app), so `test` launches LyricBar.
`PlaybackModel.isRunningTests` detects that and skips `start()`, so a test run
never fires Apple Events at Spotify/Music — otherwise tests would prompt for
Automation and depend on whatever happens to be playing. If you ever add tests
that need the loop running, drive it explicitly rather than removing that guard.

A clean build proves nothing about whether the menu bar item renders or whether
Automation permission was granted. Verify UI-adjacent behavior by running the app
and observing the menu bar.

## Architecture

Data flows one way each tick, driven by a single async loop in `PlaybackModel`:

```
Task.sleep(tick) → pickActive(): Spotify | Music (AppleScript) → track changed?
                                              → LRCLibClient.fetch (async, per track)
                                              → LRCParser.parse → [LyricLine]
        player position ──────────────────────→ LRCParser.index(at:) → lineText
```

Files under `LyricBar/`:

- **`Playback/NowPlaying.swift`** — `PlaybackBridge` protocol + the normalized
  `NowPlaying` snapshot every source resolves to (`PlaybackSource`, `PlayerState`).
- **`Playback/SpotifyBridge.swift`**, **`Playback/MusicBridge.swift`** — each wraps
  two precompiled `NSAppleScript` objects (metadata snapshot, playback position).
- **`Lyrics/LRCParser.swift`** — turns `[mm:ss.xx]` tags into sorted `LyricLine`s;
  `index(at:)` binary-searches the active line.
- **`Lyrics/LRCLibClient.swift`** — `LRCLibClient` (`Sendable`, runs off the main
  actor).
- **`LoginItem.swift`** — thin `SMAppService.mainApp` wrapper for the login toggle.
- **`PlaybackModel.swift`** — `@MainActor @Observable`; owns the poll loop, source
  selection, position extrapolation, and the per-track fetch task.
- **`LyricBarApp.swift`** — the `MenuBarExtra` scene; the label (icon + truncated
  lyric) and the SwiftUI menu.

### Source selection

`pickActive()` snapshots the bridges in order and prefers whichever is **playing**;
if none is playing it falls back to a **paused** source so its header still shows.
**Spotify wins ties** (it is listed first). Metadata is probed about once a second;
only `player position` runs at the finer tick, and it is extrapolated between
probes (`lastPosition + elapsed`), which is exact apart from seeks — the next probe
corrects those.

### Constraints that are easy to break

**`st` is a reserved token in AppleScript.** `set st to 5` is a syntax error on
its own, with no application involved. Using it as a variable name silently breaks
the whole script at runtime — `snapshot()` returns nil and the app concludes
nothing is playing. Avoid short, grammar-adjacent identifiers in AppleScript.

**Never coerce `player position` to text.** AppleScript's `as text` uses the
system locale, which yields a comma decimal separator here (`134,2799`) that
`Double()` rejects. Read the descriptor's `doubleValue` instead. Applies to both
the Spotify and Music bridges.

**Spotify's `duration` is milliseconds** despite its scripting dictionary saying
"in seconds". `SpotifyBridge` normalizes defensively (`> 10_000` → divide).
**Apple Music's `duration` is already seconds** — do not apply the same divide.
Verify each dictionary with `sdef` rather than trusting the docs.

**Apple Music has extra player states.** `player state` can be `fast forwarding`
or `rewinding`; `MusicBridge` collapses those to `playing` in-script so the shared
`PlayerState` enum stays small. Use `persistent ID` for the track identity — it is
stable across launches (Spotify uses `id`).

**The menu bar item must always keep its icon.** The `quote.bubble` image is the
always-present, always-clickable anchor for the menu; only the lyric text beside it
varies. An empty lyric shows the icon alone, never a zero-width item.

**Width is pinned so neighbours don't shift.** The lyric `Text` truncates natively
(`.lineLimit(1).truncationMode(.tail)`) inside a fixed `frame(maxWidth:)` derived
from the chosen character count. There is no scrolling marquee — macOS has no menu
bar API for one, and it was dropped in the SwiftUI rewrite.

**Automation permission gates everything.** macOS prompts once per controlled app
(Spotify, Music). Denied, the app runs and shows no lyrics. The TCC database needs
Full Disk Access to inspect, so verify via System Settings → Privacy & Security →
Automation instead. This requires `NSAppleEventsUsageDescription` and, under the
Hardened Runtime, the `com.apple.security.automation.apple-events` entitlement.

### LRCLIB API

Verified against the server source (github.com/tranxuanthang/lrclib, MIT), not
the client-rendered docs page:

- `GET /api/get` requires `track_name` + `artist_name`; `album_name` and
  `duration` are optional. Matches on an exact signature, so it misses often when
  album names differ across releases (remasters, archive editions).
- `GET /api/search` is the reliable path — the client falls back to it and picks
  the candidate whose duration is closest, rejecting matches more than 5s off.
- Responses are camelCase (`syncedLyrics`, `plainLyrics`, `instrumental`).
- The server prefers the `Lrclib-Client` header over `User-Agent`.
- No API key, but there **is** backpressure: a semaphore sheds load with
  **503 + `Retry-After`**. The per-track fetch `Task` sleeps and retries the *same*
  track in a loop, so a track that starts during a backoff window still gets its
  lyrics (do not pin the retry to whichever track was current when the 503 arrived).

Tracks with no synced match, and instrumentals, render as the icon alone.

### Performance

On the old AppKit build, steady state was ~4.5% of one core and it was **menu-bar
status-item overhead, not the poll loop** — measured identical whether playing or
paused. Treat per-tick-rate CPU claims with suspicion: don't advertise the update
speed options as CPU tradeoffs without re-profiling the SwiftUI build first.

Measure with cumulative CPU time over ≥60s, not instantaneous `ps %cpu` — the load
is bursty and sampling gives readings between 1.5% and 9% for the same steady
state.

## Conventions

Tuning lives near its use (poll `tickInterval`, the `maxChars` width budget). The
comments explaining *why* a constraint exists are load-bearing — several encode
bugs that cost significant debugging. Preserve them when editing nearby code.

Never print lyric text to logs, stdout, or the menu header; the header shows track
and artist only. Diagnostics should report timing structure and line counts, not
content.

Prefer Swift's `async`/`await` over Combine, and framework APIs over hand-rolled
equivalents (`MenuBarExtra` over `NSStatusItem`, `SMAppService` over `launchctl`,
the async poll loop over `Timer`). The rewrite deliberately removed those
hand-rolls; don't reintroduce them.
