# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

LyricBar is a macOS menu bar app that shows time-synced lyrics for whatever
**Spotify or Apple Music** is currently playing. It is a SwiftUI `MenuBarExtra`
app with no third-party dependencies. Sources live under `LyricBar/`; the app is
built from `LyricBar.xcodeproj`, a standard Xcode **macOS App target** (not SwiftPM
— an app bundle is required for `MenuBarExtra` and `SMAppService`).

## THE SOURCE HAS NO COMMENTS — THIS FILE IS WHERE THE "WHY" LIVES

By explicit request, `LyricBar/` and `LyricBarTests/` contain **zero comments**.
Names and structure carry the *what*; every constraint, measurement, and
hard-won bug fix that used to sit in a comment is written down here instead.

**That makes this file load-bearing in a way it was not before.** If you change
code that this document explains, update this document in the same commit. If
you are tempted to add a clarifying comment to a `.swift` file, put it here.
Do not reintroduce comments — not even `// MARK:` dividers.

## Build, install, run

`open LyricBar.xcodeproj`, then build/run the **LyricBar** scheme (⌘R). There is
no `swift build` step and no `launchctl`/`codesign` deploy dance.

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
Login Items.

## Tests

```sh
xcodebuild -project LyricBar.xcodeproj -scheme LyricBar test
```

71 tests in 8 Swift Testing suites:

- **`LRCParserTests`** — the LRC grammar (fraction separators and digit counts,
  repeated chorus timestamps, CRLF payloads) and `index(at:)` boundaries.
- **`LRCLibMatchingTests`** — `bestMatch(among:duration:)`, split out of `fetch`
  precisely so the duration matching can be tested without the network.
- **`LyricReflowTests`** — where a long line breaks and when each chunk swaps.
  Injects its own `measure`/`measureShrunk` closures (1pt per character, and
  9/13 of that) instead of calling into the system font: real metrics would make
  the expected splits drift with the OS version, and none of the logic under test
  cares where the widths come from.
- **`NoTruncationTests`** — the opposite choice on purpose. Uses *real* menu bar
  metrics across five box widths to assert the end-to-end guarantee: every chunk
  fits its box at the font size `LyricImage` picks, and no character is ever
  dropped. It asserts inequalities, not exact splits, so it does not drift.
- **`MenuBarBoxTests`** — `LyricImage.render` returns one width across every
  state, and an over-wide line shrinks into the box rather than widening it.
- **`MenuBarFitTests`** — the pure half of the fit calibration:
  `crowdsNeighbours`, `optimisticBound`, the cache round-trip, and signatures.
- **`PlaybackModelTests`** — the tick logic, driven through injected fakes: track
  changes, the loading window, instrumental intros, pause/resume, Spotify winning
  ties, and Automation denial. `refreshNow()` forces a full metadata probe and
  `awaitPendingLyrics()` waits on the per-track fetch, so every case is
  deterministic without a clock or the network.

It is a **hosted** bundle (`TEST_HOST` is the app), so `test` launches LyricBar.
`PlaybackModel.isRunningTests` detects that and skips the poll loop, the screen
observer, and the fit calibration — otherwise tests would prompt for Automation,
depend on whatever happens to be playing, and resize the real menu bar item. If
you ever add tests that need the loop running, drive it explicitly rather than
removing that guard.

**A test in this repo cannot prove the menu bar item is correct.** It can only
prove the image is the size we think. A clean build proves nothing about whether
the item renders or whether Automation was granted. See "Verifying against the
live item" below.

## Architecture

Data flows one way each tick, driven by a single async loop in `PlaybackModel`:

```
Task.sleep(tick) → probeSources(): Spotify | Music (AppleScript) → track changed?
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

- **`Playback/NowPlaying.swift`** — `PlaybackBridge` protocol, `BridgeSnapshot`
  (`now` / `unavailable` / `denied`), the normalized `NowPlaying` snapshot every
  source resolves to (`PlaybackSource`, `PlayerState`),
  and `PlaybackScript`, which holds the AppleScript plumbing both bridges share
  (compile, read a numeric descriptor, split a separator-delimited snapshot).
- **`Playback/SpotifyBridge.swift`**, **`Playback/MusicBridge.swift`** — each is
  now just two script sources plus the source-specific duration handling.
- **`Lyrics/LRCParser.swift`** — turns `[mm:ss.xx]` tags into sorted `LyricLine`s;
  `index(at:)` binary-searches the active line.
- **`Lyrics/LyricReflow.swift`** — splits lines too wide for the menu bar across
  their own time window, and hands each chunk a timestamp.
- **`MenuBarMetrics.swift`** — text measurement, the `LyricWidth` bands,
  `UpdateSpeed`, and the screen geometry the calibration starts from.
- **`MenuBarFit.swift`** — measures how wide the item can actually be on *this*
  menu bar, by watching the real status item. See below.
- **`Lyrics/LRCLibClient.swift`** — `LRCLibClient` (`Sendable`, runs off the main
  actor).
- **`LoginItem.swift`** — thin `SMAppService.mainApp` wrapper for the login toggle.
- **`PlaybackModel.swift`** — `@MainActor @Observable`; owns the poll loop, source
  selection, position extrapolation, the per-track fetch task, and the fit.
- **`LyricImage.swift`** — draws the lyric centered into the fixed-size template
  image the status item actually sizes itself from, shrinking the font if needed.
- **`LyricBarApp.swift`** — the `MenuBarExtra` scene: the label (the lyric image),
  the popover, and the options pull-down.

### Source selection

`probeSources()` snapshots the bridges in order and prefers whichever is
**playing**; if none is playing it falls back to a **paused** source so its header
still shows, and it separately reports whether any source refused Automation.
**Spotify wins ties** (it is listed first). Metadata is probed about once a second
— gated on `ContinuousClock` elapsed time, not on a tick counter, so the rate is
the same at every update speed. Only `player position` runs at the finer tick, and
it is extrapolated between probes (`lastPosition + elapsed`), which is exact apart
from seeks — the next probe corrects those.

`ContinuousClock`, not `Date`, deliberately: `Date` is wall-clock and jumps on
NTP corrections and daylight-saving changes, which would make the extrapolated
position leap. Timing that measures *elapsed* time must be monotonic.

## The menu bar item

### It is ONE FIXED BOX *while there is a lyric* — and collapses when there isn't

```
playing / instrumental gap:
┌──────────────────── lyricBoxWidth ───────────────┐
│              ──── centered lyric ────            │
└──────────────────────────────────────────────────┘

idle / no lyrics found / paused:
┌── 32pt ──┐
│    ♪     │
└──────────┘
        item on screen = boxWidth + 16pt system padding
```

Centering is what stops the *apparent* movement once the width is genuinely
fixed: left-aligned text starts at the same edge every line and ends somewhere
new, so the block still reads as shifting. Centered, all lines share a midpoint.
The states are told apart by `DisplayState.opacity`, baked into the image's alpha
because a template image uses alpha as its tint mask.

**The collapse is not a weakening of the fixed box — read `DisplayState.holdsLyric`
before touching it.** The box exists to stop *line-to-line* jitter, and it still
does: it never changes while lyrics are playing. But holding 200-odd points open
around a 30%-opacity `♪` does not read as "nothing playing", it reads as broken
empty menu bar — that is exactly what prompted a bug report of "it vanished from
the taskbar". So the width switches on *state transitions*, of which there are a
handful per track, never per line.

`.instrumental` deliberately **keeps** the full box. Intros, outros and
bare-timestamp gaps happen mid-song, so collapsing on them would flicker the item
during playback, which is the very thing the fixed box exists to prevent.
`.loading` holds it for the same reason: it sits between a track change and the
fetch landing, and most tracks do have lyrics, so holding avoids a width change at
the exact moment the first line appears. `.idle`, `.noLyrics`, `.paused` and
`.denied` collapse — all of which last for a track or longer. If you add a
`DisplayState` case, decide which side of that line it is on.

The placeholder width comes from `MenuBarMetrics.placeholderBoxWidth(for:)`, with
a `minimumPlaceholderWidth` floor so the item stays comfortably clickable — the
popover is only reachable through it.

### `MenuBarExtra` IGNORES a frame pinned on its label — the lyric must be an image

This is the single most expensive thing to relearn in this codebase. A
`.frame(width:)` on the label view has no effect on the status item, which sizes
itself to the label's content. Measured on the live item with the label framed at
572pt:

```
chars    1     4    12    30    60    90
item   28pt  51pt 111pt 246pt 471pt 696pt      ← frame pinned at 572pt, ignored
```

**What the item does honor is an image's dimensions.** `LyricImage.render` draws
the lyric centered into a `boxWidth`-wide template image, and the same sweep then
reads a constant 588pt across every string length. Do not replace that `Image`
with a `Text`, however much tidier it looks.

This was believed fixed once before, wrongly, because `MenuBarBoxTests` asserted
`NSHostingView(...).fittingSize` — which faithfully reports whatever width is
pinned on a SwiftUI view and has nothing to do with what AppKit gives the status
item. If you ever see `fittingSize` in a test here again, it is measuring the
wrong thing.

### There is no icon

The old `quote.closing` glyph existed to stop an empty lyric collapsing to a
zero-width, unclickable item; a fixed-size image guarantees that regardless of
the string, and a permanent glyph beside text the user is reading just competes
with it. What replaces it is an invariant one level up: `PlaybackModel.lineText`
is a computed property that **can never be empty** — every "nothing to read" case
falls back to `♪`, so the box always has something visible and the popover is
always reachable. Keep that guarantee where it is; scattering placeholder
assignments across the tick branches is what it replaced.

`LyricLabel` takes plain values, not the model — that is what lets a test drive
every state.

### The width is MEASURED, not guessed (`MenuBarFit`)

Apple documents no API for how much menu bar room is free, and `NSStatusBar`'s own
docs say so outright:

> Because there is limited space in which to display status items, status items
> are not guaranteed to be available at all times. For this reason, do not rely
> on them being available…

So the app measures. The status item lives in an `NSStatusBarWindow` **in this
process**, so its frame is readable:

```swift
NSApp.windows.first { $0.className.contains("StatusBar") }?.frame
```

An earlier version of this file claimed the item's origin was unknowable. It is
not — only its *ordering* among other apps' items is. The frame is the ground
truth this whole subsystem is built on.

**What a too-wide item actually does.** It is *not* hidden. It shoves the user's
other status items sideways, and past a point it collapses over the notch.
Measured on a 1728×1117 notched display whose status strip is `x ∈ [956, 1728]`:

```
requested box   item x    item width   item right edge
 100 → 250      1134→984   116→266     1250   ← stable: nobody displaced
 275            1026       291         1317   ← neighbours pushed out
 550             979       566         1545   ← ~300pt of them gone
 575+            659       591         1250   ← collapses across the notch
```

So the signal for "too wide" is **our right edge moving**: while we fit, the
neighbours to our right pin `maxX` in place; the moment we crowd them, `maxX`
jumps. That is exactly `MenuBarFit.crowdsNeighbours`, plus a second guard that we
never reach left of `auxiliaryTopRightArea.minX`.

`calibrate` binary-searches the widest non-crowding box:

1. Render at the 80pt floor, wait for the item to settle, record `rightEdge`.
2. Start the search at `optimisticBound` — `rightEdge - stripLeftEdge - padding`,
   not the whole strip, so the first probe overshoots by tens of points rather
   than hundreds.
3. Binary search down to `probeResolution` (8pt).
4. Cache the result in `UserDefaults` under a screen-configuration signature, so
   only the very first launch on a given display arrangement pays for it.

**Two non-obvious things about that search, both found the hard way:**

- **A probe perturbs what it measures.** Probing a wide box displaces the
  neighbours, and their layout does not snap back instantly, so the *next*
  measurement is taken against a disturbed menu bar. The first version of this
  search rejected every candidate and converged on the 80pt floor for that
  reason. Every rejection is now followed by `recover(to: fitting)` — reapply the
  last good width, wait for it to settle, then continue — so each measurement is
  always approached from below, from a settled state.
- **Waiting for our own width is not waiting for the layout.** `frame(forBox:)`
  returns as soon as *our* item is the requested size; the neighbours may still
  be animating. Hence `neighbourGrace` (140ms) before the verdict is read.

On the reference machine this converges to **254pt** — against the 556pt that the
old hard-coded `otherItemsReserve: 200` produced. That constant was wrong by
~300pt, which is why the item looked like it had vanished: it was a mostly-empty
556pt box with a faint 30%-opacity `♪` centred in it.

A **drift watchdog** in the metadata tick re-reads the frame; if `maxX` has left
`expectedRightEdge` by more than `driftTolerance` for two consecutive probes
(another app added or removed a status item), it invalidates the cache and
recalibrates. This is observed behaviour, not theory: a relaunch found the right
edge at 1202 instead of the cached 1250 and correctly re-fitted from 254pt to
208pt.

Both bounds on it exist to stop that self-healing from thrashing, and neither is
optional:

- **`driftTolerance` is `probeResolution` (8pt), not 1pt.** Neighbouring items
  change width for harmless reasons — a clock going from `9:41` to `10:41` — and
  re-running a whole calibration for a few points would resize the item in front
  of the user for no gain, since 8pt is the search resolution anyway.
- **`recalibrationCooldown` is 30s**, and the check is suppressed entirely while
  `isCalibrating` or while `probeWidth` is set (the calibration drives the width
  itself, so its own probes would otherwise read as drift).
- **Drift acts in one direction only.** Being squeezed (`maxX` moved left, another
  item appeared) recalibrates, because continuing to crowd a neighbour is a real
  fault. Room *freeing up* does not: it only invalidates the cache so the next
  launch picks the extra width up. Growing mid-session is a cosmetic gain paid for
  with a visible resize, and a width that changes under the user while they are
  reading is the complaint this whole subsystem started from.

`MenuBarExtra` does not expose its `NSStatusItem`, so the item's *position among
other apps' items* is not controllable — don't write geometry that needs it.

### Verifying against the live item

Because no test can prove this, verify by measurement:

- The calibration writes its answer to `UserDefaults`, so this is the cheapest
  end-to-end check there is:
  ```sh
  defaults delete net.local.lyricbar && open <built>/LyricBar.app
  sleep 15 && defaults read net.local.lyricbar
  ```
  A `fittedBox.<signature>` of `(254, 1250)` means it converged and did not
  displace anyone. A value equal to the 80pt floor means every probe was
  rejected — suspect the settle/recover logic, not the geometry.
- For anything finer, add a temporary stderr log of the frame and run the binary
  directly (`LyricBar.app/Contents/MacOS/LyricBar 2> log`) rather than via `open`.
  Both sweep tables above were obtained that way. **Delete the scaffold before
  committing**, and never log lyric text.

### The budget is points, not characters

In the menu bar font a character spans 3.47pt ("i") to 12.85pt ("W") — a factor
of 3.7. A character budget sized for average text lets a capital-heavy line
overrun the fixed box; sized for the worst case it wastes most of the bar.
`MenuBarMetrics.typicalCharacters` reports a count for the Width menu, and is a
readout only — never a layout input.

The font is **`NSFont.menuBarFont(ofSize:)`**, the documented font for menu bar
items, rather than a hand-picked `systemFont(ofSize: 13, weight: .semibold)`.
It resolves to 13pt here but is read from the system (`baseFontSize`), so the
measurement follows the platform instead of assuming. This also means the older
corpus coverage figures below were measured against the semibold font and are
indicative, not exact.

**The `LyricWidth` bands are shares of the measured fit, not absolute points.**
They were absolute (120 / 280 / 360 / ∞, clamped down by the fit) and that is a
trap on a crowded menu bar: with the fit at 254pt, Standard, Wide and Fit Menu Bar
*all* clamped to 254, so the menu offered four choices and three of them did
nothing. Shares (0.45 / 0.65 / 0.82 / 1.0) are guaranteed distinct and ordered on
any display, which is the whole point of a control that adapts to the device.
`bandsStayDistinct` in `MenuBarBoxTests` pins that; don't reintroduce absolute
points without it failing.

`lyricBoxWidth` is also the reflow budget — with no icon slot the box and the text
area are one span, so there is deliberately only one number. Note that
`rebuildMenuLines` must use `lyricBoxWidth` and never `boxWidth`: the latter is
the placeholder width in the non-lyric states, and reflowing a track to 32pt
would shred it.

**Resolve geometry against `MenuBarMetrics.menuBarScreen`, never `NSScreen.main`.**
Apple's docs define `main` as "the screen object containing the window with the
keyboard focus", so it follows whichever app the user focuses; on a multi-display
setup it flips between displays of different widths and the box silently resizes.
That was a real shipped bug. The menu bar lives on `NSScreen.screens.first`.

## Lyrics must never be truncated

There is no scrolling marquee — macOS has no menu bar API for one. Long lines are
handled by a cascade that has **no truncating branch at all**:

1. **Split at word boundaries** (`LyricReflow.split` → `wordPlan`) so every chunk
   fits the box at the base font, and give each chunk its own timestamp.
2. **A tight window prefers shrinking to splitting.** If the line's time window
   cannot give each chunk `minChunkDuration` (1.5s), and the whole line *would*
   fit at the minimum font size, the line is left whole and `LyricImage` shrinks
   it. Calmer than flashing chunks past.
3. **Otherwise split anyway.** If it does not fit even shrunk, chunks that flash
   past are still better than words the user never sees.
4. **A single word wider than the whole box is broken at grapheme boundaries**
   (`graphemePlan`). Rare (`Supercalifragilisticexpialidocious`) but real, and at
   the 80pt floor an 18-character word already qualifies.
5. **`LyricImage.fittedFontSize` is the backstop**, shrinking from the base size
   toward `MenuBarMetrics.minimumFontSize` (9pt) until the string fits.

Step 2 is exact rather than a fudge factor: `expand` takes a **`measureShrunk`**
closure that measures at the minimum font size, so "would this fit if shrunk"
is a real measurement. That is also why it is injectable — the tests supply both
closures.

`NoTruncationTests` asserts the guarantee end to end with real metrics: every
chunk fits, and `letters(chunks.joined()) == letters(line)` — nothing dropped.

**A split plan is ranked by chunk count first**, then break quality, then even
widths. Ranking by balance first looks reasonable and is wrong: narrower chunks
each sit closer to half the budget, so the sum of deviations keeps falling as you
split further, and a two-way break loses to a three-way one. Every extra chunk
shortens the window each is on screen for.

Where to break was measured over 77 Beatles albums (2585 synced lines, 280pt
budget): 9.5% of lines overflow, 92.3% of those split cleanly, and 95.6% of
breaks land on punctuation or a conjunction/preposition. Band coverage at the
time: 120pt showed 32.0% of lines whole, 280pt 90.5%, 360pt 97.9%.

When to swap is **not** a text problem — it is audio alignment, and LRCLIB
publishes no word-level timestamps. Syllable share is the closest free proxy:
it differs from character share by a median of 0.14s, whereas a naive linear
midpoint is off by 0.60s (p90 1.69s). This is why there is no model here: an
on-device LLM would be aimed at the half a word list already solves, and it
cannot hear the vocal, which is the half that is actually uncertain.

## Constraints that are easy to break

**`st` is a reserved token in AppleScript.** `set st to 5` is a syntax error on
its own, with no application involved. Using it as a variable name silently breaks
the whole script at runtime — `snapshot()` returns nil and the app concludes
nothing is playing. Avoid short, grammar-adjacent identifiers in AppleScript.

**Never coerce `player position` to text.** AppleScript's `as text` uses the
system locale, which yields a comma decimal separator here (`134,2799`) that
`Double()` rejects. Read the descriptor's `doubleValue` instead —
`PlaybackScript.position(from:)` is the only place that happens.

**Spotify's `duration` is milliseconds** despite its scripting dictionary saying
"in seconds". `SpotifyBridge` normalizes defensively (`> millisecondThreshold` →
divide). **Apple Music's `duration` is already seconds** — do not apply the same
divide. Verify each dictionary with `sdef` rather than trusting the docs.

**Apple Music has extra player states.** `player state` can be `fast forwarding`
or `rewinding`; `MusicBridge` collapses those to `playing` in-script so the shared
`PlayerState` enum stays small. Use `persistent ID` for the track identity — it is
stable across launches (Spotify uses `id`).

**`NSImage(size:flipped:drawingHandler:)`'s block must be safe to call from any
thread**, and is deferred — Apple's docs: "AppKit executes it on the same thread
on which you draw the image itself, which can be any thread of your app." So
`LyricImage` builds the `NSAttributedString` and picks the font size *outside* the
handler and only calls `draw` inside it. Do not move measurement into the block.

**A `Regex` is not `Sendable`,** so a regex literal cannot be a `static let` under
Swift 6 (`static property 'timestamp' is not concurrency-safe`). `LRCParser.parse`
binds it as a local constant instead — still compile-time checked, which is the
whole reason it is a literal rather than `try! NSRegularExpression`.

**`SMAppService.Status` has two "off" states, not one.** An app that has never
been registered reports `.notFound`; one that was registered and then
unregistered reports `.notRegistered`. Both mean "not a login item", which is why
`LoginItem.isEnabled` tests `== .enabled` — a `!= .notRegistered` test looks
equivalent and would report a fresh install as already enabled. Observed on the
live service from `/Applications`: `.notFound` → `register()` → `.enabled` →
`unregister()` → `.notRegistered`.

**`@Observable` and stored-property initializers.** `Self.someStatic` in a stored
property's initializer fails with "covariant 'Self' type cannot be referenced from
a stored property initializer" — spell the type out (`PlaybackModel.idleTitle`).
Likewise `init` cannot read one already-assigned property to compute another
(the macro routes them through accessors), so `init` computes into locals first.

**Settable observable properties use an explicit `get`/`set` over a private
store**, not `didSet`. That is what lets the pull-down bind `Picker`/`Toggle`
directly via `@Bindable` while the setter still persists to `UserDefaults` and
rebuilds the reflow. Do not "simplify" them into plain stored properties with
observers.

**The scene is `.menuBarExtraStyle(.window)`, and that has consequences.** The
`.menu` style would give menu rows for free but cannot show the track header and
the previous/current/next triplet. The cost is that `MenuBarExtra` then has **no
right-click menu** — both mouse buttons open the popover, and SwiftUI exposes no
secondary-menu hook. Settings and Quit therefore live in an ellipsis `Menu` inside
the popover header, which AppKit still renders as a real NSMenu. Getting true
right-click would mean a hand-rolled `NSStatusItem`; don't reintroduce one for
that alone.

**The popover shows the song and its lyrics, nothing else.** No transport, no
seek, no progress — this is a lyrics-only tool and the bridges are read-only by
design. Anything that is not a lyric belongs in the pull-down.

**Automation permission gates everything.** macOS prompts once per controlled app
(Spotify, Music). Denied, the app runs and shows no lyrics. The TCC database needs
Full Disk Access to inspect, so verify via System Settings → Privacy & Security →
Automation instead. This requires `NSAppleEventsUsageDescription` and, under the
Hardened Runtime, the `com.apple.security.automation.apple-events` entitlement.

## LRCLIB API

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

Tracks with no synced match, and instrumentals, render as a dimmed `♪`.

The `Lrclib-Client` identifier is `LyricBar/1.0 (https://github.com/efeboy/lyricbar)`,
taken from the git remote. LRCLIB asks for a real contact, so keep it pointing at
something reachable if the repository ever moves.

## Performance

On the old AppKit build, steady state was ~4.5% of one core and it was **menu-bar
status-item overhead, not the poll loop** — measured identical whether playing or
paused. Treat per-tick-rate CPU claims with suspicion: don't advertise the update
speed options as CPU tradeoffs without re-profiling the SwiftUI build first. The
`UpdateSpeed` titles describe responsiveness only, for that reason.

Measure with cumulative CPU time over ≥60s, not instantaneous `ps %cpu` — the load
is bursty and sampling gives readings between 1.5% and 9% for the same steady
state.

## Conventions

Tuning lives near its use (`UpdateSpeed`, the `LyricWidth` bands,
`MenuBarMetrics.minimumBoxWidth` / `minimumFontSize`, `MenuBarFit.probeResolution`
and its timeouts, `LyricReflow.minChunkDuration`). Prefer a named constant over a
literal, since a name is the only explanation the source is allowed to carry.

Never print lyric text to logs, stdout, or the menu header; the header shows track
and artist only. Diagnostics — including test failure messages — report timing
structure, counts, and geometry, not content.

Prefer Swift's `async`/`await` over Combine, and framework APIs over hand-rolled
equivalents: `MenuBarExtra` over `NSStatusItem`, `SMAppService` over `launchctl`,
`NSFont.menuBarFont` over a hand-picked font, `NotificationCenter.notifications`
(async sequence) over `addObserver` + `MainActor.assumeIsolated`, `Regex` literals
over `NSRegularExpression`, `URL.appending(path:queryItems:)` over force-unwrapped
`URLComponents`, `ContinuousClock` over `Date` for elapsed time, `Picker` +
`@Bindable` over hand-rolled `Toggle` bindings, and the async poll loop over
`Timer`. The rewrite deliberately removed those hand-rolls; don't reintroduce them.

## Automation denial

A refused Automation prompt returns AppleScript error **-1743**
(`errAEEventNotPermitted`); **-1744** means consent has not been given yet. The
app used to swallow both and show "Nothing playing", which is indistinguishable
from Spotify being closed — the user had no way to learn why lyrics never
appeared.

`PlaybackScript.fields` now reads the error dictionary and returns `.denied`
rather than `.unavailable`, so the bridges resolve to `BridgeSnapshot.denied`.
`probeSources` reports a denial **only when nothing else is playing**: one
refused app must not mask the other working. The item then shows `⚠︎` at full
opacity instead of the dimmed `♪`, the popover reads "Automation access denied /
Privacy & Security → Automation", and the pull-down has an **Open Automation
Settings…** item that deep-links to
`x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`.

`snapshot()` returns `BridgeSnapshot`, not `NowPlaying?`, precisely so this
distinction cannot be dropped again — an optional had nowhere to put "denied".

## Injection and test seams

`PlaybackModel.init` takes its `UserDefaults`, its `[PlaybackBridge]` and a
`LyricsProvider`, all defaulted to the real ones, so `PlaybackModelTests` drives
the tick logic with fakes and never touches Apple Events or the network.
`LRCLibClient` conforms to `LyricsProvider`; that protocol exists for the seam,
not for a second implementation.

Two internal methods exist for tests and nothing else, and their names say so:
`refreshNow()` clears `lastMetadataProbe` and ticks, so a test gets a full
metadata probe rather than waiting out `metadataInterval`; `awaitPendingLyrics()`
awaits the per-track fetch `Task`. Prefer driving those over adding sleeps.

## Known gaps

Not yet addressed, in rough priority order:

- **`position()` cannot report a denial.** `snapshot()` carries the distinction and
  is what drives the UI, so this is cosmetic — but the asymmetry is a trap if
  position ever becomes the primary probe.
- **The drift watchdog cannot grow the box mid-session** by design; the extra room
  is only picked up on the next launch. If that ever feels stale, the fix is a
  user-initiated "re-measure" action, not making drift bidirectional.
- **No artwork in the popover.** Both bridges expose it over AppleScript, but
  reading it per track would add an Apple Event round-trip on the hot path.
- **`LoginItem` is disabled, not fixed, in development.** `SMAppService.mainApp`
  registers whatever bundle path it was launched from, so a build output would
  register a path that later disappears. `isStableLocation` rejects any path
  containing `/DerivedData/` **or** `/Build/Products/` and greys the toggle out.
  Both markers are needed: the first version checked only `/DerivedData/`, which
  `xcodebuild -derivedDataPath build` walks straight past — its output lands in
  `build/Build/Products/Release/` and would have been treated as a real install.
  `LoginItemTests` pins both shapes. A copy in `/Applications` works normally,
  which is the only way to exercise the toggle at all — verified there
  end-to-end: `isSupported` is true, `register()` moves the service to
  `.enabled`, and `unregister()` takes it back off, while the same binary run
  from `Build/Products/Release/` reports `isSupported` false and never reaches
  `register()`. No test can cover that; it needs an installed bundle and an
  env-gated stderr probe, deleted afterwards like the menu bar scaffolds.
