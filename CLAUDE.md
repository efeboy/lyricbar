# CLAUDE.md

Guidance for Claude Code in this repository.

## What this is

LyricBar is a macOS menu bar app that shows time-synced lyrics for whatever
Spotify or Apple Music is playing. It is a single Xcode app target
(`LyricBar.xcodeproj`, sources in `LyricBar/`, tests in `LyricBarTests/`) with no
third-party dependencies. The item is an `NSStatusItem` owned by
`StatusItemController`; the lyric is drawn by a SwiftUI view hosted inside it;
clicking it pops up an `NSMenu`, and Settings and Tips are popovers.

It is public (MIT) and distributed to friends as a notarized DMG on GitHub
Releases.

## Where the reasoning lives

The Swift sources have **no comments**, by explicit request. Design reasoning
lives in `docs/`:

| doc | read before touching |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | the poll loop, bridges, `PlaybackModel`, test seams |
| [docs/menu-bar-item.md](docs/menu-bar-item.md) | `StatusItemController`, `LyricLabel`, the menu, placeholders |
| [docs/width.md](docs/width.md) | `WidthLadder`, Settings, `FitLog`, and why there is no auto-fit |
| [docs/lyrics.md](docs/lyrics.md) | `LyricReflow`, `LyricText`, `LRCLibClient` |
| [docs/platform-notes.md](docs/platform-notes.md) | AppleScript, Automation, `LoginItem`, localization |
| [docs/releasing.md](docs/releasing.md) | build settings, `Scripts/dist.sh`, `UpdateChecker` |
| [docs/testing.md](docs/testing.md) | the test suites and what they cannot prove |

## Working rules

- **No comments in `.swift` files**, not even `// MARK:`. Put explanations in
  `docs/`, and update the relevant doc in the same commit as the code.
- **Never print lyric text** — not to logs, stdout, test messages, or the menu
  header. Test fixtures use invented lines. Never commit real lyrics or personal
  email addresses; the repository is public.
- Prefer a named constant over a literal; tuning lives near its use.
- Prefer framework APIs and `async`/`await`: `SMAppService`, `os.Logger`,
  `NSFont.menuBarFont`, `NotificationCenter.notifications`, `Regex` literals,
  `URL.appending(path:queryItems:)`, `ContinuousClock`, `NSMenu`, and the async
  poll loop over `Timer`. No Combine.
- New user-facing strings use `String(localized:)`. Build once in the Xcode IDE
  so the String Catalog picks them up; `xcodebuild` does not.
- Xcode rewrites `project.pbxproj` and the shared scheme on its own. Diff them
  before any reset or checkout, and commit Xcode's changes separately.

## Invariants

Each is explained in `docs/`; breaking one has shipped a bug before.

- **The item is one fixed box in every state.** Its width is `lyricBoxWidth`,
  the user's rung snapped to the screen; geometry never depends on `DisplayState`.
- **`statusItem.length = box`, never `box + padding`.** The system adds 16pt.
- **No `MenuBarExtra`, no image label.** It cannot hold a fixed width.
- **`LyricLabel` clips, never ellipsizes**: `.fixedSize()` inside a clipped
  frame, not `.lineLimit(1)`. Animations stay inside the frame.
- **`PassthroughHostingView.hitTest` returns `nil`** and `sizingOptions = []`.
- **`lineText` is never empty.**
- **No auto-fit by probing the item's own frame.** On macOS 27 it cannot see
  neighbours folded into the overflow chevron. The width is the user's choice.
- **Resolve screens with `MenuBarMetrics.menuBarScreen`, never `NSScreen.main`.**
- **AppleScript runs only on the bridge actors**, with a 2s event timeout.
  `tick()` re-checks state after every `await`.
- **Lyrics are never truncated.** Reflow first; `fittedFontSize` is only the
  backstop.
- **`FitLog` helpers never take a `String`**, and only `render`'s `drew` is
  `.debug`.
- **Keep the repository public** and release tags plain (`vX.Y`), or the update
  check breaks silently.

## Build, test, verify

```sh
open LyricBar.xcodeproj                                          # ⌘R to run
xcodebuild -project LyricBar.xcodeproj -scheme LyricBar test     # 73 tests
```

A passing test run does not prove the menu bar item works. For anything visible,
install an archived build and check it live (see
[docs/width.md](docs/width.md#verifying-against-the-live-item)).

To install or release, use the local `ship` skill (`.claude/skills/ship/`, not in
the repo) or follow [docs/releasing.md](docs/releasing.md). Never copy an
`xcodebuild build` output into `/Applications`. Notarizing, pushing to `main`,
and publishing a release each need the user's explicit go-ahead.
