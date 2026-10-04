# The menu bar item

## One fixed box in every state

```
┌──────────────────── lyricBoxWidth ───────────────┐
│              ──── centered lyric ────            │   playing
│                       ♪                          │   instrumental / loading /
│                                                  │   noLyrics / paused / idle
│                       ⚠︎                          │   denied
└──────────────────────────────────────────────────┘
        item on screen = lyricBoxWidth + 16pt system padding
```

Nothing about the item's geometry depends on `DisplayState`, so the item only
changes size when the user moves the width slider or the screen changes (see
[width.md](width.md)). The text is centred, so every
line shares a midpoint and nothing appears to shift. States differ only by
`DisplayState.opacity`.

`DisplayState.holdsLyric` answers "may this state show a lyric" — a content
question, never a width one. Do not attach geometry to it.

**Do not reintroduce a collapsing box.** The item once shrank to 32pt when idle,
to fix an "item vanished" report. That report was really caused by a
miscalculated 556pt box; at a sensible width (~240pt) a centred `♪` reads as
idle. If the empty states look wrong, check the width first.

## The width is set directly

The width is `statusItem.length`, assigned outright. The system adds
`systemItemPadding` (16pt) on top, so `length` is the content width:

```
length   32    48    80    96
window   48    64    96   112      <- always length + 16
```

`render()` assigns `statusItem.length = box` with nothing added. Adding the
padding to `length` makes the item 16pt wider than the rung the user picked.

**Do not reintroduce `MenuBarExtra` or a fixed-size-image label.** `MenuBarExtra`
exposes no `NSStatusItem` and ignores `.frame(width:)` on its label, so the item
sizes itself to the text. The only fixed-width workaround under it was drawing
the lyric into an image, which loses real text, crispness across displays, and
native animation. `MenuBarExtra` still has no width API as of the SDK 27 docs.

Do not assert `NSHostingView.fittingSize` in a test: it reports the width pinned
on the SwiftUI view, not what AppKit gives the status item.

## The lyric is a SwiftUI view in the AppKit item

AppKit owns what only it can do — `statusItem.length` and the button.
SwiftUI draws the lyric.

`StatusItemController` adds a `PassthroughHostingView<LyricLabel>` to
`statusItem.button`, sized to the button with an autoresizing mask, and
`render()` replaces its `rootView` with plain values (`text`, `boxWidth` (the model's `lyricBoxWidth`),
`opacity`). The button's own `title` is set to `""` once.

- **`hitTest` returns `nil`**, so clicks reach the button and the menu opens.
- **`sizingOptions = []`**, so the label can never push its size into the item.
- **Plain values, not the model**, so `render()` stays the one place the model
  and the drawing meet.
- VoiceOver reads the button's `setAccessibilityLabel(text)`; the SwiftUI view is
  `.accessibilityHidden(true)` so the lyric is not read twice.

Inside `LyricLabel`:

- **The text is `.fixedSize()` inside `.frame(width: boxWidth).clipped()`.** Do
  not use `.lineLimit(1)`: SwiftUI would add "…", and lyrics are never truncated.
- **Line changes crossfade** with `.id(text)` + `.transition(.opacity)` under an
  animation keyed on `text` (`lineCrossfade`, 0.18s). Width-only renders, such as
  moving the slider, do not crossfade.
- **State changes fade** with `.opacity(opacity)` under an animation keyed on
  `opacity` (`stateFade`, 0.35s). The first render does not animate.
- **Both animations sit inside `.frame(width:)`**, so the width is never
  animated — width and text often change in the same render when the width changes
  mid-line.
- Opacity lives on the view only; the text is always full-strength `.primary`.
  Applying it twice would multiply (0.3 × 0.3).

Verified live on 2026-09-28: unchanged geometry, crisp centred text, clicks open
the menu, legible under the menu-open highlight, smooth crossfades, dark text on
a light menu bar, and no `clipped` renders.

A karaoke-style sweep, if ever wanted, would be a SwiftUI `.mask` with an
animated `LinearGradient` on the `Text`.

## The placeholder

`PlaybackModel.lineText` can never be empty: every "nothing to read" case falls
back to `♪` (or `⚠︎` when denied), so the box always shows something and stays
clickable. The decision is `PlaybackModel.displayText(chunk:state:)`, a static
function over plain values. It returns the lyric only when the state
`holdsLyric` and the chunk is non-empty.

## The menu

The button's action (on mouse down) calls `menu.popUp(positioning:at:in:)` with a
screen point 1pt below the item's window, where AppKit places status menus
itself. It is not `statusItem.menu`: AppKit never makes a status item's menu
narrower than the item, so a 400pt lyric box meant a 416pt menu. Popped up, the
menu is `menuWidth` (160pt) wide or as wide as its widest row. Pass the point in
screen coordinates (`in: nil`); a point inside the button landed the menu over
the menu bar, and AppKit pushed it down with a scroll arrow hiding the header.
On macOS 27 `button.highlight(true)` may not draw the item's pill while the menu
is open. The menu is AppKit on purpose — its SwiftUI equivalent is
`MenuBarExtra(.menu)`, which the width rules out. The one setting that needs
more than a checkmark, the width, lives in a popover (see
[width.md](width.md#settings)).

- **The first row is `model.header`, disabled** — the status line ("Loading
  lyrics…", "No synced lyrics found", "Lyrics hidden", "Nothing playing",
  "Automation access denied"). Keep it a label.
- **The header is a SwiftUI `MenuHeader` in `NSMenuItem.view`**, `menuWidth`
  wide. For a track it is two single lines, title then artist, each ending in
  "…" when too long, so the artist always shows; `PlaybackModel.headerLines`
  splits them, and every track header is built by `trackHeader(title:artist:)`
  so the split can recognise it. Status messages ("Loading lyrics…") wrap to two
  lines. An `NSMenu`
  is as wide as its widest row, and a long "Title — Artist" as a plain title once
  made the whole menu 497pt. The header is track metadata, not a lyric, so the
  never-truncate rule does not apply. Today the ⌘-shortcut rows set the width
  (~177pt).
- **It is rebuilt in `menuNeedsUpdate`** rather than kept in sync.
- **`autoenablesItems = false`**, or AppKit greys out every item in an
  `LSUIElement` app. Quit targets `NSApp` explicitly.
- **"Hide Lyrics", not "Pause Lyrics"**, because under a track name "Pause"
  reads as pausing the music, which this app cannot do.
- **Open Automation Settings…** appears only when `displayState == .denied`, and
  **Update Available…** only when a newer release exists.
- **Settings…** (⌘,) toggles the Settings popover: the width slider and **Open
  at Login**. The popover calls `refreshLoginState()` when it appears, since
  `SMAppService` can change outside the app.
- **Tips…** toggles a popover (`TipsView`) with ⌘-drag to reorder, the overflow
  arrow when the bar is full, ⌘P, and what `♪` means. Both popovers are
  `ItemPopover`s anchored to the item.
- The version row shows `CFBundleShortVersionString`.
- No transport, seek, or progress. The bridges are read-only by design.

The menu is the click target, not a popover. A lyric popover was removed because
most states left it empty and its Automation explanation did not fit; an `NSMenu`
sizes to its content. The popovers hold only Settings and Tips.
