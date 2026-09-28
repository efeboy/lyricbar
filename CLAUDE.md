# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

LyricBar is a macOS menu bar app that shows time-synced lyrics for whatever
**Spotify or Apple Music** is currently playing. The menu bar item is a
hand-rolled `NSStatusItem` owned by `StatusItemController`; clicking it opens a
native `NSMenu` carrying the status line and the settings. No third-party
dependencies. Sources live
under `LyricBar/`; the app is built from `LyricBar.xcodeproj`, a standard Xcode
**macOS App target** (not SwiftPM — an app bundle is required for a status item
and `SMAppService`).

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
no `swift build` step and no `launchctl` deploy dance.

**To get a change into the app the user actually runs, use the `ship` skill**
(`.claude/skills/ship/SKILL.md`), which drives `Scripts/dist.sh` and then
verifies the install. The one rule worth repeating here: **never `ditto` an
`xcodebuild build` output into `/Applications`.** It is signed `Apple
Development`, keeps `get-task-allow`, is single-architecture, and `spctl`
rejects it — only `archive` + `-exportArchive` produce a distributable. The
invariant the skill maintains is that exactly one current `LyricBar.app` exists,
at `/Applications`; the app shows no version anywhere, so a stale copy launched
from Spotlight is indistinguishable from a fix that did not work.

The target is already configured this way; each of these is load-bearing, so
don't "clean them up":

- Deployment target **macOS 14.0** (`SMAppService` is 13+, but the `@Observable`
  model and the no-argument `NSApp.activate()` both require 14).
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

"Open at login" is a toggle in the status item's menu, backed by
`SMAppService.mainApp`; the system tracks it under System Settings → General →
Login Items.

## Tests

```sh
xcodebuild -project LyricBar.xcodeproj -scheme LyricBar test
```

79 tests in 9 Swift Testing suites:

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
  fits its box at the font size `LyricText` picks, and no character is ever
  dropped. It asserts inequalities, not exact splits, so it does not drift.
- **`MenuBarBoxTests`** — what `LyricText` alone guarantees: the fitted font size
  stays inside `[minimumFontSize, baseFontSize]` for every state and every content
  shape, a line too wide to shrink bottoms out at the floor, and the dimmed states
  rank below `.playing`. Centering and clip-don't-ellipsize used to be asserted
  here too, on the `NSAttributedString`; they now live in `LyricLabel`'s modifier
  chain, which a test cannot inspect, and are verified live instead (see "The
  lyric is a SwiftUI view"). `holdsLyric` is asserted here as a
  *content* question — which states may render a lyric — not a width one; the box
  is the same in every state. It does **not** assert that arbitrary text fits the box —
  nothing promises that, and asserting it here fails on raw unreflowed lines. The
  end-to-end fit guarantee is `NoTruncationTests`, on reflowed chunks.
- **`MenuBarFitTests`** — the pure half of the fit calibration:
  `crowdsNeighbours`, `optimisticBound`, the cache round-trip, and signatures.
- **`PlaybackModelTests`** — the tick logic, driven through injected fakes: track
  changes, the loading window, instrumental intros, resuming mid-line, hide/show, Spotify winning
  ties, and Automation denial. `refreshNow()` forces a full metadata probe and
  `awaitPendingLyrics()` waits on the per-track fetch, so every case is
  deterministic without a clock or the network.

It is a **hosted** bundle (`TEST_HOST` is the app), so `test` launches LyricBar.
`AppDelegate.isRunningTests` detects that and creates neither the model nor the
status item — otherwise tests would prompt for Automation, depend on whatever
happens to be playing, and resize the real menu bar item.

The model itself has **no test awareness**. `PlaybackModel.init` only assigns
state; the poll loop, the screen observer and the launch calibration begin in
`start()`, which `AppDelegate` calls *after* creating the `StatusItemController`,
so the calibration's first read of `MenuBarFit.itemWindow` finds a real item.
Tests construct a model and never call `start()`. If you ever add tests that
need the loop running, drive it explicitly (`refreshNow()`) rather than calling
`start()` — that would reach the real bridges.

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
        lines      ──→ previous / current / next triplet (unrendered) ←──────────┤
        menuLines  ──→ LyricReflow.expand(width:) ──→ menu bar item ←────────────┘

        player position ──→ LRCParser.index(at:) → lineText / currentLine
```

The parsed lines are kept twice on purpose. `lines` is the original timing and is
the triplet's source; `menuLines` is the same track re-split to whatever fits
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
  an `actor` holding two script sources plus the source-specific duration
  handling. See "AppleScript never runs on the main actor".
- **`Lyrics/LRCParser.swift`** — turns `[mm:ss.xx]` tags into sorted `LyricLine`s;
  `index(at:)` binary-searches the active line.
- **`Lyrics/LyricReflow.swift`** — splits lines too wide for the menu bar across
  their own time window, and hands each chunk a timestamp.
- **`MenuBarMetrics.swift`** — text measurement, the `LyricWidth` bands, and the
  screen geometry the calibration starts from.
- **`MenuBarFit.swift`** — measures how wide the item can actually be on *this*
  menu bar, by watching the real status item. See below.
- **`FitLog.swift`** — the `os.Logger` handles and the geometry formatters the
  width detection logs through. See "The width detection logs itself".
- **`Lyrics/LRCLibClient.swift`** — `LRCLibClient` (`Sendable`, runs off the main
  actor).
- **`LoginItem.swift`** — thin `SMAppService.mainApp` wrapper for the login toggle.
- **`FitCoordinator.swift`** — `@MainActor @Observable`; drives `MenuBarFit` over
  the app's lifetime: the calibration task and its `probeWidth`, the drift
  watchdog, the screen-change observer, and the `fittedWidth` they produce.
  `MenuBarFit` answers "how wide can the item be right now"; the coordinator
  decides *when* to ask. It knows nothing about lyrics or the width preference:
  it reports each refit through `onRefit`, and `PlaybackModel.handleRefit`
  reapplies the band, rebuilds `menuLines`, and logs the model-side fields
  (`preference`, `lyricBox`, `menuLines`) on the `applied` and
  `screenChangeCacheHit` lines.
- **`PlaybackModel.swift`** — `@MainActor @Observable`; owns the poll loop, source
  selection, position extrapolation, the per-track fetch task, and a
  `FitCoordinator`. `boxWidth` and `lineText` read the coordinator's
  `probeWidth`; observation reaches through the nested `@Observable`, so the
  controller's tracking of `model.boxWidth` still fires on every probe.
- **`LyricText.swift`** — owns `fittedFontSize`, the pure font-size backstop.
- **`LyricLabel.swift`** — the SwiftUI view that draws the lyric inside the status
  item button, and `PassthroughHostingView`, the `NSHostingView` that hosts it.
- **`StatusItemController.swift`** — owns the `NSStatusItem`, sets `length` and the
  hosted `LyricLabel`'s `rootView`, builds the menu on demand as its own
  `NSMenuDelegate`, and pushes model changes to the item via
  `withObservationTracking`.
- **`LyricBarApp.swift`** — the `App` entry point: a `Settings` scene to satisfy
  SwiftUI's need for one, an `NSApplicationDelegateAdaptor` that creates the
  controller. The `Settings` scene is empty and exists only because `App`
  requires a `body`; the one real SwiftUI view is `LyricLabel`.

### Source selection

`probeSources()` snapshots the bridges in order and prefers whichever is
**playing**; if none is playing it falls back to a **paused** source so its header
still shows, and it separately reports whether any source refused Automation.
**Spotify wins ties** (it is listed first). Metadata is probed about once a second
— gated on `ContinuousClock` elapsed time, not on a tick counter, so it stays once
a second whatever `tickInterval` is. Only `player position` runs at the finer
`tickInterval` (0.5s), and it is extrapolated between probes (`lastPosition + elapsed`), which is exact apart
from seeks — the next probe corrects those.

`ContinuousClock`, not `Date`, deliberately: `Date` is wall-clock and jumps on
NTP corrections and daylight-saving changes, which would make the extrapolated
position leap. Timing that measures *elapsed* time must be monotonic.

### AppleScript never runs on the main actor

`SpotifyBridge` and `MusicBridge` are **actors**, and `PlaybackBridge` is
`Sendable` with `async` `snapshot()` / `position()`. `NSAppleScript` blocks its
thread until the target app replies, and the default Apple Event timeout is
about two minutes, so running it on the main actor (as the app used to) meant a
hung Spotify froze the status item and its menu with it. Each actor owns its own
compiled scripts, so a single `NSAppleScript` instance is never used from two
threads at once — the actor's serial execution is the whole thread-safety story.

Every script also wraps its application commands in
`with timeout of PlaybackScript.eventTimeoutSeconds seconds` (2s). Off the main
actor a hang no longer freezes the UI, but it would still stall the poll loop,
which awaits each probe; the timeout bounds that stall. A timed-out event is
error -1712, which is not a denial code, so it resolves to `.unavailable` and
the item falls back to idle rather than to `⚠︎`. Keep `if it is not running`
**outside** the timeout block: it is answered locally and must not wait.

`tick()` is `async` for this reason, and it **re-checks `hidden` and
`currentTrackID` after every `await`**: the user can hide lyrics, or a probe can
change tracks, while a bridge call is suspended, and applying a stale result
after that would redraw a lyric the user just hid. The position sample is
stamped with `clock.now` *after* `position()` returns, not with the tick's start
time, so probe latency does not skew the extrapolation.

## The menu bar item

### It is ONE FIXED BOX, in every state

```
every state:
┌──────────────────── lyricBoxWidth ───────────────┐
│              ──── centered lyric ────            │   playing
│                       ♪                          │   instrumental / loading /
│                                                  │   noLyrics / paused / idle
│                       ⚠︎                          │   denied
└──────────────────────────────────────────────────┘
        item on screen = boxWidth + 16pt system padding
```

`boxWidth` is `probeWidth ?? lyricBoxWidth` — one number, no branch on state.
**Nothing about the item's geometry depends on `DisplayState` any more**, so the
item cannot move except when the fit itself is recalibrated or the user picks a
different band. That is the strongest form of the guarantee this whole subsystem
exists for, and it is the shape the design kit specifies: all fourteen variants
of `LyricBar / Menu Bar Item` are the same width.

Centering is what stops the *apparent* movement: left-aligned text starts at the
same edge every line and ends somewhere new, so the block still reads as
shifting. Centered, all lines share a midpoint. The states are told apart purely
by `DisplayState.opacity`, applied as `LyricLabel`'s `.opacity` — see the
animation section for why it lives on the view and not in the text's colour.

**This replaced a collapsing box, and the history is worth knowing before you
reintroduce one.** The item used to shrink to a 32pt placeholder in `.idle`,
`.noLyrics`, `.paused` and `.denied`, because a wide box holding a 30%-opacity
`♪` had drawn a bug report of "it vanished from the taskbar". That report was
against a **556pt** box — the width the old hard-coded `otherItemsReserve: 200`
produced, which was wrong by ~300pt. Once `MenuBarFit` started measuring the real
bar the box became ~247pt on the reference display, and a centred glyph in it
reads as idle rather than broken. The collapse was a fix for a bug whose actual
cause was fixed elsewhere.

So if the empty states ever look wrong again, **check the fit before reaching for
a collapse**: an item that looks vacant is far more likely to be a calibration
that ran wide than a box that needs to shrink.

`DisplayState.holdsLyric` still exists and is still load-bearing — but it now
governs **content only**, never width. It answers "may this state render a lyric",
which `displayText` uses to fall back to `♪`. Do not reattach it to geometry.

### The width is SET directly, and the lyric is real text

The item is an `NSStatusItem` created in `StatusItemController`. Its width is
`statusItem.length`, assigned outright, and the lyric is a SwiftUI `Text` in
`LyricLabel` — real text, which stays crisp at any scale and follows the menu
bar's appearance through `.foregroundStyle(.primary)`. VoiceOver reads the
button's `setAccessibilityLabel(text)`; the SwiftUI view is
`.accessibilityHidden(true)` so the lyric is not announced twice.

**Measured: the system adds `systemItemPadding` (16pt) on top of `length`.** So
`length` is the *content* width, not the on-screen footprint:

```
length   32    48    80    96
window   48    64    96   112      <- always length + 16
```

That is why `render()` assigns `statusItem.length = box` with nothing added, and
why `MenuBarFit.matches` still compares the window frame against
`box + systemItemPadding`. Assigning `length = box + padding` instead makes every
probe miss by 16pt: the floor never "appears", `calibrate` returns nil, and **no
fit is written at all**. Its signature is an *empty* `fittedBox` key — distinct
from a fit pinned at the 80pt floor, which means the probes ran and were all
rejected. That distinction is the fastest way to tell a geometry bug from a
settle/recover bug.

The button's own `title` is set to `""` once and never touched again; it would
otherwise draw underneath the hosted view. (`NSStatusItem.title` and
`attributedTitle` are deprecated anyway — the button properties were the live
path while the lyric was an `attributedTitle`.)

**Why this used to be an image.** Under `MenuBarExtra` there was no `length` to
set — its entire public API is eight initializers, none of which expose the
underlying `NSStatusItem`. A `.frame(width:)` on the label was ignored and the
item sized itself to the label's content. Measured then, framed at 572pt:

```
chars    1     4    12    30    60    90
item   28pt  51pt 111pt 246pt 471pt 696pt      <- frame pinned at 572pt, ignored
```

An image's *dimensions* were honored where a frame was not, so a fixed-size
template image was the only lever available. That workaround is gone. Do not
reintroduce it, and do not reintroduce `MenuBarExtra` to "simplify" the scene.

This was also believed fixed once before, wrongly, because `MenuBarBoxTests`
asserted `NSHostingView(...).fittingSize` — which faithfully reports whatever
width is pinned on a SwiftUI view and has nothing to do with what AppKit gives the
status item. If you ever see `fittingSize` in a test here again, it is measuring
the wrong thing.

### The lyric is a SwiftUI view, hosted in the AppKit item

**Why hybrid and not `MenuBarExtra`.** `MenuBarExtra` still has no width API
(checked against the SDK 27 docs), and the only way to get a fixed width out of
it is the fixed-size-image workaround above, which was rejected again on
2026-09-28 for the reasons that section gives. So the split is exact: AppKit
owns the one thing only AppKit can do — `statusItem.length` and the item's
window, which `MenuBarFit` measures — and SwiftUI draws everything inside it.

`StatusItemController` adds a `PassthroughHostingView<LyricLabel>` as a subview
of `statusItem.button`, sized to the button's bounds with an autoresizing mask,
and `render()` replaces its `rootView` with plain values (`text`, `boxWidth`,
`opacity`). Three details there are load-bearing:

- **`hitTest` returns `nil`.** Otherwise the hosting view swallows the click and
  the menu never opens. Clicks fall through to the button, and AppKit's
  `statusItem.menu` handling is untouched.
- **`sizingOptions = []`.** The hosting view creates no constraints from its
  content, so the label can never push its own size back into the status item.
  That is precisely the failure `MenuBarExtra` had — the item sizing itself to
  the label — and the width must only ever come from `length`.
- **Plain values, not the model.** `LyricLabel` takes three values, the same
  reason `displayText` is static: `render()` stays the only place the model and
  the drawing meet, and it is still the place `logFit` measures.

Inside `LyricLabel`:

- **The text is `.fixedSize()` inside `.frame(width: boxWidth).clipped()`.** Do
  **not** replace this with `.lineLimit(1)`: SwiftUI truncates a single line with
  "…", which breaks "Lyrics must never be truncated". `fixedSize` lets an
  overflowing line keep its natural width; the frame centres it and `clipped`
  cuts it, which is what `.byClipping` did for the attributed string.
- **Line changes crossfade** through `.id(text)` + `.transition(.opacity)` under
  an `.animation(.easeInOut(duration: lineCrossfade), value: text)` (0.18s).
  Keying the animation on `text` is what gives width-only renders — every
  calibration probe — no crossfade, which the AppKit version needed an explicit
  `shownText` guard for.
- **State changes fade** through `.opacity(opacity)` under an animation keyed on
  `opacity` (`stateFade`, 0.35s). SwiftUI does not animate the first render, so
  the item still does not fade up from nothing at launch.
- **Both animation modifiers sit *inside* the `.frame(width:)`.** An
  `.animation` modifier only animates the modifiers above it in the chain, so the
  box width is never animated. That matters at the end of a calibration, where
  the width (probe → fitted) and the text (`♪` → lyric) change in the same
  render: with the frame inside the animation, the label would visibly resize for
  0.18s while `statusItem.length` had already snapped.

**`DisplayState.opacity` is the view's opacity, not the text's colour.** The text
is always full-strength `.primary`. Applying opacity in both places would
multiply them (0.3 x 0.3 = 0.09).

Verified on the live item when this landed (2026-09-28), because none of it is
testable: same window geometry as the AppKit label (269pt at `minX=980` on the
reference display, box 253); crisp, centred text in the menu bar font; clicks
open the menu through the hosting view; the standard rounded highlight appears
behind the item while the menu is open with the lyric still legible over it;
lines crossfade and pause/resume fades without jumps; the text turns dark on a
light menu bar; and a stream of renders across playing, instrumental, loading
and idle logged no `clipped` line.

**A karaoke-style sweep**, if it is ever wanted, is now a SwiftUI `.mask` with an
animated `LinearGradient` on the `Text` — not the `CAGradientLayer` on the
button's backing layer this section used to describe, which assumed the lyric
was the button's own title.

### There is no icon

The old `quote.closing` glyph existed to stop an empty lyric collapsing to a
zero-width, unclickable item; an explicitly-set `length` guarantees that
regardless of the string, and a permanent glyph beside text the user is reading just competes
with it. What replaces it is an invariant one level up: `PlaybackModel.lineText`
is a computed property that **can never be empty** — every "nothing to read" case
falls back to `♪`, so the box always has something visible and the menu is
always reachable. That guarantee matters more now that the box no longer
collapses: an empty string in a 247pt box would be an invisible, unclickable
item. Keep it where it is; scattering placeholder
assignments across the tick branches is what it replaced.

That decision is `PlaybackModel.displayText(chunk:probing:state:)`, a **static
function over plain values** so tests can drive every combination — the same reason
`LyricLabel` does not take the model. It returns the placeholder unless
all three hold: not probing, the state `holdsLyric`, and the chunk is non-empty.

**The `probing:` argument is not politeness, it is a shipped bug.** `boxWidth` is
`probeWidth ?? lyricBoxWidth`, so a calibration probe *overrides* the box down to
as little as the 80pt floor — while `menuLines`
is still reflowed for the old budget, because `applyFittedWidth()` only rebuilds it
*after* calibration finishes. Render a lyric in that window and `fittedFontSize`
bottoms out at 9pt, the text still overflows, and the label's clip cuts it mid-word.
Observed live as `Somewher` in a ~40pt item, when FaceTime added a status item
mid-song and the drift watchdog recalibrated underneath the lyric.

The **guard** is `probeWidth != nil`, read in `lineText` — that is the real
signal and it is exact. The `render` log's `probing=` field is a *derived*
approximation, `box != lyricBox`, because the controller cannot see `probeWidth`.
It used to also require `state.holdsLyric`, which was right only while the box
collapsed by state: a differing box could then mean either a probe or a
placeholder. Now that every state shares one width, `box != lyricBox` means a
probe and nothing else, so the extra term only made probe-time renders in
non-lyric states log `probing=false`. Observed on the drift recalibration that
followed this change: `box=244 lyricBox=247 probing=false` while a probe was
plainly driving it.

Measured across a launch calibration with music playing, the box walks
32 → 80 → 268 → 80 → 174 → 174 → 221 → 245 → 257 → 245 → 251 → 245 (the 268 → 80
step is a rejection recovering to the floor). **All twelve of those renders must be
the placeholder**; the nine that follow, at a settled 245pt, are the lyric. A
drift-triggered run measured after the box was unified walks
80 → 308 → 80 → 194 → 251 → 194 → 223 → 237 → 244 → 237 and converges at 237. A live
check that counts clips is the only way to see this — no test can, because the
probe sequence needs a real menu bar.

`LyricLabel` and `LyricText.fittedFontSize` take plain values, not the model —
that is what lets a test drive every state. Keep it that way:
`StatusItemController.render` is the only place the two are joined.

### The width is MEASURED, not guessed (`MenuBarFit`)

Apple documents no API for how much menu bar room is free, and `NSStatusBar`'s own
docs say so outright:

> Because there is limited space in which to display status items, status items
> are not guaranteed to be available at all times. For this reason, do not rely
> on them being available…

So the app measures. The status item lives in an `NSStatusBarWindow` **in this
process**, so its frame is readable:

```swift
statusItem.button?.window?.frame
```

`StatusItemController.render` hands that window to `MenuBarFit.itemWindow` (a weak
reference) on every render, and `itemFrame` reads it from there. It used to be
found by scanning `NSApp.windows` for a `className` containing `"StatusBar"`, which
worked but matched a private class name by string; owning the item made the window
directly reachable.

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
  be animating, and **our own origin may not have moved yet**. Hence
  `neighbourGrace` (140ms) before any geometry is read.

  That grace originally guarded only the probe verdicts, and **not the floor
  measurement every probe is compared against** — which shipped a bug that
  collapsed the item to 80pt in the field. Reproduced from the logs: a drift
  recalibration starts while the item is 271pt wide at `minX=981`; shrinking it
  to 96 changes the width immediately but leaves the origin stale for ~150ms, so
  the baseline read landed as `width=96` at `minX=981` and computed
  `rightEdge = 1077` instead of 1252. Every probe was then judged against a right
  edge 175pt off, all were rejected, and the search pinned at the floor. It never
  showed on a cold launch, where the item goes 32→80pt with no wide layout to
  unwind, so both origin and width settle together.

  The fix is structural rather than another sleep: **`settle(at:timeout:apply:)`
  is now the only way geometry is read.** It applies the width, waits for the
  width to match, waits `neighbourGrace`, then re-reads and re-validates, and
  returns both the `arrived` and the `settled` frame. `calibrate`'s floor
  baseline, `probe` and `recover` all go through it. If you add a fourth reader,
  route it through `settle` too — do not call `frame(forBox:)` directly.
  `floorRelaidOut` logs the `arrived` → `settled` correction whenever it is
  non-zero, which is how you confirm the guard is doing work: a drift-triggered
  recalibration on the reference machine logs
  `arrivedMaxX=1077 settledMaxX=1252 shift=175`.

On the reference machine this converges to **254pt** — against the 556pt that the
old hard-coded `otherItemsReserve: 200` produced. That constant was wrong by
~300pt, which is why the item looked like it had vanished: it was a mostly-empty
556pt box with a faint 30%-opacity `♪` centred in it.

A **drift watchdog** (`FitCoordinator.checkDrift`, called from the metadata
tick) re-reads the frame; if `maxX` has left
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

We own the `NSStatusItem` now, but its *position among other apps' items* is still
chosen by the system — don't write geometry that needs it.

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
- For anything finer, **read the log subsystem** described in the next section —
  it reports every probe and its verdict, with the app launched normally. That
  replaces the throwaway stderr scaffold this section used to recommend; the two
  sweep tables above were obtained with one, before the subsystem existed. If you
  still need a one-off scaffold for something the categories do not cover, run the
  binary directly (`LyricBar.app/Contents/MacOS/LyricBar 2> log`), **delete it
  before committing**, and never log lyric text.

### The width detection logs itself

Width detection is the one subsystem no test can cover, so it is **permanently
instrumented** with Apple's unified logging (`os.Logger`, `LyricBar/FitLog.swift`)
— the mechanism Apple's documentation prescribes and which it explicitly prefers
over `print`/`NSLog`. Three width categories under subsystem `net.local.lyricbar`:

- **`calibration`** — the whole `MenuBarFit.calibrate` lifecycle: `begin`,
  `floorSettled`, `optimisticBound`, one `probe#N` line per candidate carrying its
  verdict and the frame it was judged on, `recover`, `converged`. Around it,
  `cacheHit`/`cacheMiss` at launch, `stored` on the defaults key, and
  `requested`/`noFit` from `FitCoordinator.calibrate(reason:)` and `applied`
  from `PlaybackModel.handleRefit` — where `reason` is a
  `FitCoordinator.Reason` raw value: `launch-no-cache`, `drift-squeezed` or
  `screen-change`.

  **The `stored`/`invalidated` lines live at the `FitCoordinator` call sites, not
  inside `MenuBarFit.store`/`invalidate`.** Those two are pure cache functions
  that `MenuBarFitTests` drives directly with synthetic values, so logging inside
  them put lines like `stored box=4 rightEdge=1250` into the real unified log on
  every `xcodebuild test` — indistinguishable, during a later investigation, from
  the fit having collapsed. The coordinator's `calibrate` and screen observer
  only begin in `PlaybackModel.start()`, which no test calls, and `checkDrift` — which
  `PlaybackModelTests` does reach, through `tick()` — returns before logging
  anything because no status item exists under test, so `MenuBarFit.itemFrame`
  is nil. That is why the coordinator is where anything user-visible must be
  logged. Keep it that way: if a test ever drives the coordinator with a real
  frame, those lines will leak into the unified log again.
- **`drift`** — the watchdog: `observed` (with direction and the probe count
  toward `driftProbesBeforeRecalibration`), `settled`, `roomFreed`, and
  `suppressed reason=cooldown`.
- **`render`** — one line per status item render: `drew` at `.debug`, and
  `clipped` at `.error` when the drawn text is wider than the box it went into.

A fourth category, **`login`**, is not part of the width detection and so is
not a `FitLog` handle: `LoginItem` owns its own `Logger` and writes one `.error`
line, `failed enabling=… code=… status=…`, when `SMAppService.register()` or
`unregister()` throws. It used to be `try?`, which made a refused registration
indistinguishable from a checkmark that simply did not stick. The menu still
reads the real state back through `LoginItem.isEnabled` afterwards, so the UI
never claims a registration that failed.

Watch it with the app launched normally — no terminal-attached binary, no
scaffold to delete afterwards:

```sh
log stream --predicate 'subsystem == "net.local.lyricbar"' --level debug --style compact
```

**The levels are chosen for what survives, not for how loud they are.** Unified
logging persists `.notice` and `.error` to disk; `.info` is memory-only and gets
evicted, and `.debug` is not captured at all unless something is streaming. So
the entire `calibration` and `drift` narrative — including every `probe#N`
verdict and every `recover` — is `.notice` or `.error`, and is readable hours
later with no streamer attached and no `log config`:

```sh
log show --predicate 'subsystem == "net.local.lyricbar"' --last 6h --style compact
```

Only the `render` category's per-render `drew` line is `.debug`, because it is
the one high-volume signal and it is the one you can afford to lose — `clipped`,
the render fault, is `.error` and always persists. To keep `drew` you must either
stream while it happens (`--level debug`), or enable capture for the subsystem
up front:

```sh
sudo log config --mode "level:debug" --subsystem net.local.lyricbar   # persists until reset
sudo log config --reset --subsystem net.local.lyricbar
```

Do not "tidy" a `probe#N` line down to `.info`. It would still show in a live
stream, which is exactly why the regression would go unnoticed, and it would
vanish from every after-the-fact investigation — the only kind this subsystem
usually gets.

A healthy first-launch calibration on the reference machine, captured that way
and trimmed to the calibration category:

```
cacheMiss signature=1728-1117-2-956-772-1-130 preference=fill
begin floor=80 upperBound=756 leftLimit=956 padding=16
floorSettled minX=1156 maxX=1252 width=96 rightEdge=1252
optimisticBound start=280 span=200 resolution=8
probe#1 box=280 verdict=rejected reason=moved-right-edge shift=69
probe#2 box=180 verdict=accepted
probe#3 box=230 verdict=accepted
probe#4 box=255 verdict=accepted
probe#5 box=268 verdict=rejected reason=moved-right-edge shift=69
probe#6 box=262 verdict=rejected reason=moved-right-edge shift=69
converged box=255 outcome=fitted probes=6 elapsed=1650ms
```

**Rejections are not failures.** A binary search has to reject; probes 1, 5 and 6
are how it found the boundary. What an actual fault looks like:

| line | what it means |
| --- | --- |
| `abandoned reason=floor-never-appeared` | our item never reached `floor + padding`. Geometry bug — suspect `length` being assigned with the padding added. Nothing is written to defaults at all: this is the empty-`fittedBox`-key case above. |
| `converged outcome=pinned-at-floor` | every probe was rejected. Suspect the settle/recover logic, not the geometry. |
| `probe#N reason=never-settled` | the item never took the requested width within `settleTimeout`. |
| `probe#N reason=lost-width-during-grace` | it took the width, then lost it while `neighbourGrace` elapsed — the bar was still reflowing under it. |
| `probe#N reason=crossed-left-limit` | the item reached left of `auxiliaryTopRightArea.minX`. |
| `abandoned reason=floor-lost-width-during-grace` | the baseline reached the floor width and lost it again before settling. The bar is thrashing; nothing is cached and the old `fittedWidth` is kept. |
| `floorRelaidOut shift=…` | **not a fault** — the settle guard corrected a stale origin on the baseline read. Expect it on drift-triggered recalibrations, never on a cold launch. A large `shift` here is exactly the bug that used to pin the fit at the floor. |
| `noFit` | calibration returned nil; `fittedWidth` kept its old value and nothing was cached. |
| `clipped … probing=true` | the shipped bug from "The width is SET directly": a lyric rendered while a probe drives the box. `chars=1` on every `probing=true` line is the guard working. |
| `clipped … probing=false fontSize=9.0` | the backstop bottomed out at the floor and still overflowed — the reflow budget is wrong, not the fit. |

**Why this cannot leak a lyric.** `os.Logger` redacts dynamic strings by default
and leaves scalars public, which happens to encode this project's
never-log-lyric-text rule in the type system. Every `FitLog` helper takes only
`CGFloat`, `CGRect` or `Duration`, so it is *structurally* incapable of carrying
text, and the `render` category logs `chars=` — a count — rather than the string.
The explicit `privacy: .public` markers exist only to un-redact those geometry
strings. **Do not add a `FitLog` helper that takes a `String`**, and never mark a
lyric `.public`.

Two shapes elsewhere exist only to feed these lines: `DisplayState` carries a
`String` raw value so it can name itself, and
`MenuBarFit.crowding(_:rightEdge:leftLimit:)` reports *which* guard tripped, with
`crowdsNeighbours` derived from it so the pure function `MenuBarFitTests` covers
keeps its signature.

The cost is a measurement per render (`fittedFontSize` plus one `textWidth`) that
duplicates work `LyricLabel` already does when it picks its font. Renders are line changes,
not a hot loop, and `.debug` records are dropped unless something is streaming —
but if a future change makes `render()` fire per frame, gate `logFit` first.

### The budget is points, not characters

In the menu bar font a character spans 3.47pt ("i") to 12.85pt ("W") — a factor
of 3.7. A character budget sized for average text lets a capital-heavy line
overrun the fixed box; sized for the worst case it wastes most of the bar.
`MenuBarMetrics.typicalCharacters` used to report a count in the Width menu — a
readout only, never a layout input. It is gone with the labels it fed: a menu row
reading `Standard (~37 characters)` states a number the user cannot do anything
with, in a control whose only honest job is taste. Don't put a measurement back
into a menu title.

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
nothing. Shares (0.5 / 0.75 / 1.0) are guaranteed distinct and ordered on any
display, which is the whole point of a control that adapts to the device.
`bandsStayDistinct` in `MenuBarBoxTests` pins that; don't reintroduce absolute
points without it failing.

**There are three bands, not four, and `wide` (0.82) is the one that went.**
Wide and Fit Menu Bar differ by a fifth of the fit on a control the user cannot
preview before choosing, and the fit calibration already sizes the item to the
real bar — so the band picker is taste, and taste does not need a fourth notch.
A stored `"wide"` preference from an older build no longer decodes and falls
back to the `.fill` default; there is deliberately no migration for a cosmetic
one-off. Both tests iterate `LyricWidth.allCases`, so neither pins the count.

`lyricBoxWidth` is also the reflow budget — with no icon slot the box and the text
area are one span, so there is deliberately only one number. Note that
`rebuildMenuLines` must use `lyricBoxWidth` and never `boxWidth`: the latter is
whatever a calibration probe is currently driving, and reflowing a track to the
80pt probe floor would shred it.

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
   fit at the minimum font size, the line is left whole and `LyricText` shrinks
   it. Calmer than flashing chunks past.
3. **Otherwise split anyway.** If it does not fit even shrunk, chunks that flash
   past are still better than words the user never sees.
4. **A single word wider than the whole box is broken at grapheme boundaries**
   (`graphemePlan`). Rare (`Supercalifragilisticexpialidocious`) but real, and at
   the 80pt floor an 18-character word already qualifies.
5. **`LyricText.fittedFontSize` is the backstop**, shrinking from the base size
   toward `MenuBarMetrics.minimumFontSize` (9pt) until the string fits.

**Step 5 stops at the floor whether or not the string fits** — it bounds the font
size, it does not promise the text fits the box. What makes the guarantee hold is
that steps 1–4 have already split the line into chunks that fit at the *base* font,
so the backstop only ever has to absorb the tight-window case from step 2. Handed a
raw unreflowed line it will happily bottom out at 9pt and still overflow, and the
button's `.byClipping` then clips it. So assert end-to-end fit on **reflowed
chunks** (`NoTruncationTests`), never on raw lines.

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
store**, not `didSet`, so the setter can persist to `UserDefaults` and rebuild
the reflow while the getter stays a plain read. They were shaped this way to bind
SwiftUI `Picker`/`Toggle` via `@Bindable`; the menu sets them directly now, but
the shape is still what keeps persistence out of the call sites. Do not
"simplify" them into plain stored properties with observers.

### Clicking the item opens a menu, and there is no popover

`statusItem.menu = menu` — AppKit shows it on click, highlights the button while
it is open, and dismisses it. There is no `togglePopover`, no `NSApp.activate()`,
and no `NSHostingController`; the only view code is `LyricLabel`, which draws the
lyric and never receives a click.

**The menu stays AppKit on purpose.** It is the native control for a status
item's menu, and its SwiftUI equivalent is `MenuBarExtra(.menu)`, which the width
rules out. Moving Width and Open at Login into a SwiftUI `Settings` window
instead would need either the private `showSettingsWindow:` selector (an
`LSUIElement` app has no SwiftUI environment in an `NSMenu` action to call
`openSettings` from) or a hand-built window — a heavier, less native surface for
two settings.

**The popover was deleted because it was mostly empty.** It rendered
`trackTitle` / `trackArtist` / `trackSubtitle` and the previous/current/next
triplet, and nothing else — so in four of the seven `DisplayState` cases
(`instrumental`, `loading`, `noLyrics`, `idle`) it was a track header above a
blank 108pt box. It also duplicated what Spotify and Music already show, and its
one genuinely load-bearing string, the Automation explanation, **did not fit**:
"LyricBar cannot read Spotify or Music" measures 227pt into the ~192pt title
column at `lineLimit(1)`, so the only state that had to explain itself was
truncated. An `NSMenu` sizes to its content, so the same string fits.

**The menu's first row is `model.header`, disabled.** That property was assigned
in eight places and asserted by four tests while **no view read it** — the status
vocabulary the app computes ("Loading lyrics…", "No synced lyrics found",
"Lyrics hidden", "Nothing playing", "Automation access denied") existed and was
thrown away. Wiring it here is what turns those four empty states into
informative ones, and it is why the menu is a status surface and not only a
settings surface. If you ever make the row actionable, it stops being a label;
keep it disabled.

**The menu is rebuilt in `menuNeedsUpdate`, not kept in sync.** It is opened a
handful of times a session, so building it fresh is cheaper than observing
`header`, `isHidden`, `loginEnabled`, `widthPreference` and `displayState` and
patching items. It also means the login checkmark is read after
`refreshLoginState()`, which is the only way it can be right — `SMAppService`
state can change outside the app.

**`autoenablesItems = false`.** With the default on, AppKit disables any item
whose action nothing in the responder chain validates, which greys out the whole
menu for an `LSUIElement` app with no main window. Quit therefore targets `NSApp`
explicitly rather than relying on the chain.

**The first action is "Hide Lyrics", not "Pause Lyrics".** It sits directly under
the status row showing the track, where "Pause" reads as *pause the music* — a
thing this app deliberately cannot do. The model property is `isHidden` and the
header it sets is "Lyrics hidden" for the same reason; `DisplayState.paused`
still means the player is paused, and the hidden state borrows it because both
are "no lyric to show".

**The menu is settings and status, nothing else.** No transport, no seek, no
progress — this is a lyrics-only tool and the bridges are read-only by design.

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
paused. Treat per-tick-rate CPU claims with suspicion: don't reintroduce a tick
rate *setting* on CPU grounds without re-profiling the SwiftUI build first.

**There used to be an `UpdateSpeed` picker** (200ms / 500ms / 1s) and it was
removed as an option nobody could act on. It was never a CPU tradeoff — see the
paragraph above, which is why its titles only ever claimed responsiveness — and
lyric lines change every few seconds, so none of the three settings differed
perceptibly. `PlaybackModel.tickInterval` is the surviving constant, fixed at the
old `.balanced` value (0.5s). The `tickInterval` defaults key it persisted under
is now unread; leaving a stale key behind is harmless, and nothing migrates it.

Measure with cumulative CPU time over ≥60s, not instantaneous `ps %cpu` — the load
is bursty and sampling gives readings between 1.5% and 9% for the same steady
state.

## Conventions

Tuning lives near its use (`PlaybackModel.tickInterval`, the `LyricWidth` bands,
`MenuBarMetrics.minimumBoxWidth` / `minimumFontSize`, `MenuBarFit.probeResolution`
and its timeouts, `LyricReflow.minChunkDuration`). Prefer a named constant over a
literal, since a name is the only explanation the source is allowed to carry.

Every user-facing string is `String(localized:)`, and `LyricBar/Localizable.xcstrings`
is the catalog. It is English-only for now; the point is that adding a language
is a translation job, not a code change. **Building in Xcode keeps the catalog in
sync — `xcodebuild` does not.** A new string built only from the command line
compiles and shows in English, but never reaches the catalog, so build once in
the IDE before committing a new string. The `"\(title) — \(artist)"` header is
deliberately not localized: it is two proper nouns and a dash. The tests compare
against the English strings, which holds because the test host runs in the
development language.

Never print lyric text to logs, stdout, or the menu header; the header shows track
and artist only. Diagnostics — including test failure messages — report timing
structure, counts, and geometry, not content.

Prefer Swift's `async`/`await` over Combine, and framework APIs over hand-rolled
equivalents: `SMAppService` over `launchctl`,
`os.Logger` over `print`/`NSLog`,
`NSFont.menuBarFont` over a hand-picked font, `NotificationCenter.notifications`
(async sequence) over `addObserver` + `MainActor.assumeIsolated`, `Regex` literals
over `NSRegularExpression`, `URL.appending(path:queryItems:)` over force-unwrapped
`URLComponents`, `ContinuousClock` over `Date` for elapsed time, `NSMenu` +
`NSMenuDelegate` over a hand-rolled panel, and the async poll loop over
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
opacity instead of the dimmed `♪`, the menu's status row reads "Automation access
denied", and the menu grows an **Open Automation Settings…** item that
deep-links to
`x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`.

**That item is gated on `displayState == .denied`** and is absent otherwise. It
is a recovery action for a state most users never reach, so leaving it in the
menu permanently costs every user a row to explain a problem they do not have —
and it appears exactly where the status row has just named the problem. Gate it
on `displayState` and not on `automationDenied`: the latter is
`@ObservationIgnored`, and while `menuNeedsUpdate` reads both fresh on every open
so observation no longer decides it, `displayState` is the value the rest of the
UI already agrees on.

`snapshot()` returns `BridgeSnapshot`, not `NowPlaying?`, precisely so this
distinction cannot be dropped again — an optional had nowhere to put "denied".

## Injection and test seams

`PlaybackModel.init` takes its `UserDefaults`, its `[PlaybackBridge]` and a
`LyricsProvider`, all defaulted to the real ones, so `PlaybackModelTests` drives
the tick logic with fakes and never touches Apple Events or the network.
`LRCLibClient` conforms to `LyricsProvider`; that protocol exists for the seam,
not for a second implementation.

Two internal methods exist for tests and nothing else, and their names say so:
`refreshNow()` clears `lastMetadataProbe` and awaits one tick, so a test gets a
full metadata probe rather than waiting out `metadataInterval`;
`awaitPendingLyrics()` awaits the per-track fetch `Task`. Prefer driving those
over adding sleeps. The test `FakeBridge` is a `@MainActor` class with a
`nonisolated let source` — that is what makes it `Sendable` while the
`@MainActor` suite still mutates `next` and `positionValue` directly.

## Known gaps

Not yet addressed, in rough priority order:

- **The triplet is computed and rendered nowhere.** `previousLine`,
  `currentLine`, `nextLine`, `updatePopoverLines(at:)` and the `trackTitle` /
  `trackArtist` / `trackSubtitle` trio all survive the popover's removal, still
  updating every tick and still covered by `PlaybackModelTests`. They are kept
  because the popover was removed **for now** — the triplet is the one thing a
  single-line status item cannot show, so it is the obvious content for any
  richer surface later. If that surface never arrives, delete them and their
  tests rather than leaving the model computing for nobody. Note `lines` exists
  only for them and for the `lines.isEmpty` no-lyrics check; `menuLines` drives
  everything visible.

- **`position()` cannot report a denial.** `snapshot()` carries the distinction and
  is what drives the UI, so this is cosmetic — but the asymmetry is a trap if
  position ever becomes the primary probe.
- **The drift watchdog cannot grow the box mid-session** by design; the extra room
  is only picked up on the next launch. If that ever feels stale, the fix is a
  user-initiated "re-measure" action, not making drift bidirectional.
- **No artwork anywhere.** Both bridges expose it over AppleScript, but reading
  it per track would add an Apple Event round-trip on the hot path, and the menu
  has nowhere to put it.
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
