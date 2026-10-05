# Width

The lyric box is a width the user picks from a fixed ladder in Settings. LyricBar
does not measure the menu bar. It used to, and the reasons it stopped are below;
read them before adding any kind of auto-fit back.

## The ladder

`WidthLadder.rungs` is 160–400pt in `step` (40pt) increments; the default is
240pt, close to what the old measurement found on a 14" notched display.

- `available(widest:)` drops rungs wider than `MenuBarMetrics.widestBox()` (the
  status strip right of the notch, less the 16pt padding), and never returns an
  empty list.
- `snapped(_:widest:)` maps any width to the nearest available rung.
  `PlaybackModel.widthPreference` stores the chosen rung (`lyricWidthPoints`);
  `lyricBoxWidth` is that rung snapped to the current screen.
- On `didChangeScreenParametersNotification` the model re-snaps, so moving to a
  smaller display narrows the box without losing the preference.

`lyricBoxWidth` is the item's length and the reflow budget at once. It depends
only on the rung and the screen, never on `DisplayState`.

The budget is in points, not characters: in the menu bar font a character spans
3.47pt ("i") to 12.85pt ("W"). Show points in Settings, never a character count.

The font is `NSFont.menuBarFont(ofSize:)`, read from the system via
`baseFontSize`. Resolve screen geometry against `MenuBarMetrics.menuBarScreen`
(`NSScreen.screens.first`), never `NSScreen.main`, which follows keyboard focus
across displays.

### Settings

The menu's **Settings…** (⌘,) toggles an `ItemPopover` (an `NSPopover` anchored
to the status item button) hosting `SettingsView`: the width slider, the
**Lyric timing** stepper, and the **Open at Login** toggle. A popover rather than a
window: an `LSUIElement` app has no app menu, the SwiftUI `Settings` scene can
only be opened from an `NSMenu` through a private selector, and a window would
need its own activation and focus handling for a single slider. The popover is
`.transient`, so any click outside closes it; `NSApp.activate()` runs first so
the slider takes the first click.

The slider edits a local `draft`, not the model. The item resizes once, when the
drag ends (`onEditingChanged(false)`), or `settleDelay` (0.4s) after a keyboard or
click change. Applying every step live moved the item, and with it the popover
and the knob, out from under the cursor; with a lyric playing the slider was
uncontrollable. The pt label follows the draft. `widthPreference`'s setter snaps
and persists. With only one available rung the slider is omitted.

The **Lyric timing** stepper ([lyrics.md](lyrics.md#per-track-timing-offset))
commits on every click, with no draft: an offset changes which line shows, not
the item's geometry, so nothing moves under the cursor. Its **Reset** button is
always present and only disabled at 0, so the popover never changes height. The
section is disabled while lyrics are hidden or the song has no synced lyrics.

### Migration

The first launch after the change converts the old `lyricWidth` band
(`compact`/`standard`/`fill`, shares of the measured fit) to 160/200/240pt, and
deletes the measurement cache (`fittedBox.*`, `fitSlack`).

## Why there is no auto-fit

macOS has no API for free menu bar room, and none was added in macOS 27
(`expandedInterfaceDelegate` is about click handling). LyricBar used to find the
widest box by trying widths on the live item and watching its own frame:

1. **It moved everything.** Each try resized the item, sliding every icon to its
   left, and each too-wide try shoved a neighbour ~69pt before recovering. A
   seeded, creeping search cut a cold start to one shove, but could not remove it.
2. **On macOS 27 it cannot see the failure.** Status items are now hosted by
   `MenuBarAgent`, and a crowded bar folds items on our left behind a new
   overflow chevron. Our own right edge does not move when that happens. Measured
   on 2026-10-04: calibration reported `outcome=fitted` at 404pt while the
   Claude, Weather and Passwords icons sat stacked behind the chevron. The old
   binary search has the same blind spot.
3. **The alternatives cost more than they give.**
   - `CGWindowListCopyWindowInfo` and the SkyLight window lists show only
     full-width 1728×33 bars on macOS 27; per-item windows are gone. Ice,
     Bartender, Hidden Bar and Thaw broke on 27 beta 1 for this reason.
   - Accessibility can read every item's slot from `MenuBarAgent`'s windows, and
     the chevron, with no motion (this is what Ice's and Thaw's macOS 27 work
     uses). It needs the Accessibility permission and relies on an undocumented
     tree. Untrusted, every read of another app's items fails with -25211.

So the user chooses. If the box is too wide, macOS folds other icons into the
overflow chevron rather than hiding LyricBar; picking a narrower rung brings them
back. If auto-fit is ever revisited, the Accessibility route is the only one that
detects folding; do not reintroduce probing the item's own frame.

## Logging

The `render` category of subsystem `net.local.lyricbar` logs `drew` per render
(`.debug`) and `clipped` when text overflows its box (`.error`). `clipped …
fontSize=9.0` means the backstop hit its floor and still overflowed: the reflow
budget is wrong. `LoginItem` logs `failed` under `login`.

```sh
log stream --predicate 'subsystem == "net.local.lyricbar"' --level debug --style compact
```

In zsh, `log` is a shell built-in; call `/usr/bin/log` from scripts.

`render` measures each render a second time (`fittedFontSize` plus one
`textWidth`). That is cheap because renders happen on line changes; if `render()`
ever fires per frame, gate `logFit` first.

Every `FitLog` helper takes only numbers or rects, and `render` logs `chars=`
rather than text, so the logs cannot carry a lyric. Don't add a `FitLog` helper
that takes a `String`, and never mark a lyric `.public`.

## Verifying against the live item

No test can show the item is right. Install an archived build, open Settings,
drag the slider across every rung, and check:

- the item resizes immediately and the lyric stays centred;
- at the widest rung, other icons fold into the chevron and come back when you
  narrow it;
- `log stream … --level debug` shows no `clipped`.
