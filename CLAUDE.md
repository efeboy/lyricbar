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

"Open at login" is a toggle in the popover's options pull-down, backed by
`SMAppService.mainApp`; the system tracks it under System Settings → General →
Login Items. Quitting no longer has to
disable it (there is no `KeepAlive` to fight).

## Tests

`LyricBarTests` is a Swift Testing bundle covering the pure logic: `LRCParser`,
`LRCParser.index(at:)`, `LRCLibClient.bestMatch(among:duration:)` — the LRCLIB
duration matching, split out of `fetch` precisely so it can be tested without the
network — and `LyricReflow` (where a long line breaks, and when each chunk swaps).
`MenuBarBoxTests` renders `LyricLabel` in an `NSHostingView` and asserts the box is
one width across every state — the shift regression, pinned.

`LyricReflowTests` injects its own `measure` closure (1pt per character) instead
of calling into the system font. Real metrics would make the expected splits
drift with the OS version, and none of the logic under test cares where the
widths come from.

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
                                              → LRCParser.parse → [LyricLine] ──┐
                                                                                │
        lines      ──→ popover triplet (previous / current / next) ←─────────────┤
        menuLines  ──→ LyricReflow.expand(width:) ──→ menu bar item ←────────────┘

        player position ──→ LRCParser.index(at:) → lineText / currentLine
```

The parsed lines are kept twice on purpose. `lines` is the original timing and is
what the popover shows; `menuLines` is the same track re-split to whatever fits
the current menu bar width. Both are plain `[LyricLine]`, so `index(at:)` searches
them identically — the reflow adds timestamps, it does not introduce a second
lookup path. Changing the width preference or the screen layout rebuilds only
`menuLines`.

Files under `LyricBar/`:

- **`Playback/NowPlaying.swift`** — `PlaybackBridge` protocol + the normalized
  `NowPlaying` snapshot every source resolves to (`PlaybackSource`, `PlayerState`).
- **`Playback/SpotifyBridge.swift`**, **`Playback/MusicBridge.swift`** — each wraps
  two precompiled `NSAppleScript` objects (metadata snapshot, playback position).
- **`Lyrics/LRCParser.swift`** — turns `[mm:ss.xx]` tags into sorted `LyricLine`s;
  `index(at:)` binary-searches the active line.
- **`Lyrics/LyricReflow.swift`** — splits lines too wide for the menu bar across
  their own time window, and hands each chunk a timestamp.
- **`MenuBarMetrics.swift`** — text measurement, the `LyricWidth` bands, and the
  fixed box derived from `NSScreen.auxiliaryTopRightArea` on `menuBarScreen`.
- **`Lyrics/LRCLibClient.swift`** — `LRCLibClient` (`Sendable`, runs off the main
  actor).
- **`LoginItem.swift`** — thin `SMAppService.mainApp` wrapper for the login toggle.
- **`PlaybackModel.swift`** — `@MainActor @Observable`; owns the poll loop, source
  selection, position extrapolation, and the per-track fetch task.
- **`LyricBarApp.swift`** — the `MenuBarExtra` scene: the label (icon + lyric), the
  popover, and the options pull-down.

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

**The menu bar item must always keep its icon.** The `quote.closing` image is the
always-present, always-clickable anchor for the popover; only the lyric text beside
it varies. An empty lyric shows the icon alone, never a zero-width item.

**The menu bar item is ONE FIXED BOX.** `model.boxWidth` is pinned on the OUTER
container and the icon and lyric are laid out inside it:

```
┌──────────────────── boxWidth ────────────────────┐
│ [icon 18] gap 4 │ ─────── lyricWidth ─────────── │
└──────────────────────────────────────────────────┘
```

Pinning the outer frame rather than the inner `Text` is load-bearing. Sizing the
`Text` and letting the `HStack` add itself up leaves the total at the mercy of the
symbol's own metrics; pinning the container makes the width independent of what
the icon and text each report. The `Text` is rendered even when empty, so every
state occupies the same width and the item never pushes other status items out of
reach. `maxWidth` would size to the current line and make the whole menu bar
twitch on every lyric. The states are told apart by `DisplayState.opacity`.

`MenuBarBoxTests` measures `NSHostingView(...).fittingSize` across all five states
and asserts one distinct width. `LyricLabel` therefore takes plain values, not the
model — that is what lets a test drive every state.

The width comes from a `LyricWidth` preference (Compact / Standard / Wide) clamped
down by `MenuBarMetrics.availableTextWidth`, which reads
`NSScreen.auxiliaryTopRightArea` — on a notched Mac exactly the strip right of the
notch, which is where status items live — and reserves room for other items. The
preference can only be reduced, never raised, by the display.

**Resolve geometry against `MenuBarMetrics.menuBarScreen`, never `NSScreen.main`.**
`.main` is the screen with the *key window*, so it follows whichever app the user
focuses; on a multi-display setup it flips between displays of different widths and
the box silently resizes. That was a real shipped bug. The menu bar lives on
`NSScreen.screens.first`.

`MenuBarExtra` does not expose its `NSStatusItem`, so the item's actual origin is
unknowable — don't write geometry that needs it.

**The budget is points, not characters.** In the menu bar font a character spans
3.47pt ("i") to 12.85pt ("W") — a factor of 3.7. A character budget sized for
average text lets a capital-heavy line overrun the fixed box; sized for the worst
case it wastes most of the bar. `MenuBarMetrics.typicalCharacters` reports a count
for the Width menu, and is a readout only — never a layout input.

There is no scrolling marquee — macOS has no menu bar API for one, and it was
dropped in the SwiftUI rewrite. Long lines are split by `LyricReflow` instead of
truncated, which is why the width is a hard budget rather than a hint.

**The scene is `.menuBarExtraStyle(.window)`, and that has consequences.** The
`.menu` style would give menu rows for free but cannot show the track header and
the previous/current/next triplet, so the popover is a `.window`. The cost is that
`MenuBarExtra` then has **no right-click menu** — both mouse buttons open the
popover, and SwiftUI exposes no secondary-menu hook. Settings and Quit therefore
live in an ellipsis `Menu` inside the popover header, which AppKit still renders
as a real NSMenu. Getting true right-click would mean a hand-rolled `NSStatusItem`;
don't reintroduce one for that alone.

**The popover shows the song and its lyrics, nothing else.** No transport, no
seek, no progress — this is a lyrics-only tool and the bridges are read-only by
design. Anything that is not a lyric belongs in the pull-down.

**A split plan is ranked by chunk count first**, then break quality, then even
widths. Ranking by balance first looks reasonable and is wrong: narrower chunks
each sit closer to half the budget, so the sum of deviations keeps falling as you
split further, and a two-way break loses to a three-way one. Every extra chunk
shortens the window each is on screen for, and a tidier break is no help if the
text flashes past. `LyricReflow.minChunkDuration` is the floor below which the
line is left whole and truncated instead.

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

Tuning lives near its use (poll `tickInterval`, the `LyricWidth` bands and
`otherItemsReserve` in `MenuBarMetrics`, `LyricReflow.minChunkDuration`). The
comments explaining *why* a constraint exists are load-bearing — several encode
bugs that cost significant debugging. Preserve them when editing nearby code.

Never print lyric text to logs, stdout, or the menu header; the header shows track
and artist only. Diagnostics should report timing structure and line counts, not
content.

Prefer Swift's `async`/`await` over Combine, and framework APIs over hand-rolled
equivalents (`MenuBarExtra` over `NSStatusItem`, `SMAppService` over `launchctl`,
the async poll loop over `Timer`). The rewrite deliberately removed those
hand-rolls; don't reintroduce them.
