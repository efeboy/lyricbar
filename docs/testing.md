# Testing

```sh
xcodebuild -project LyricBar.xcodeproj -scheme LyricBar test
```

78 tests in 9 Swift Testing suites:

| suite | covers |
| --- | --- |
| `LRCParserTests` (two suites) | The LRC grammar (fraction separators and digit counts, repeated timestamps, CRLF) and `index(at:)` boundaries. |
| `LRCLibMatchingTests` | `bestMatch(among:duration:)`, split out of `fetch` so duration matching is testable offline. |
| `LyricReflowTests` | Where a long line breaks and when each chunk swaps. Uses injected metrics (1pt per character, and 9/13 of that) so expected splits don't drift with the OS. |
| `NoTruncationTests` | The end-to-end guarantee with real menu bar metrics across five box widths: every chunk fits, and no character is lost. Asserts inequalities, not exact splits. |
| `MenuBarBoxTests` | `fittedFontSize` stays within `[minimumFontSize, baseFontSize]`, overflow bottoms out at the floor, dimmed states rank below `.playing`, `holdsLyric` per state, and the `WidthLadder`: even rungs, hiding rungs that don't fit, snapping, band migration. |
| `PlaybackModelTests` | The width preference persisting and migrating, the per-track timing offset (direction, persistence per track, clamping, removal at 0), the title/artist header split, and the tick logic through injected fakes: track changes, loading, instrumental intros, resuming mid-line, hide/show, Spotify winning ties, Automation denial. |
| `LoginItemTests` | `isStableLocation` for installed and build-output paths. |
| `UpdateCheckerTests` | `isNewer(_:than:)`: numeric comparison, missing components as zero, non-numeric tags never newer. |

Fixtures use invented lyric lines. The replacements keep the originals' shape —
break points, punctuation, and syllable counts — because the reflow tests depend
on it.

## What tests cannot prove

Tests cannot show that the menu bar item renders, that Automation was granted,
or that centring and clipping in `LyricLabel` look right; `LyricLabel`'s modifier
chain cannot be inspected. Verify those on the live app — see
[width.md](width.md#verifying-against-the-live-item).

The test bundle is hosted, and `AppDelegate` creates nothing under test. Drive the
model with `refreshNow()` and `awaitPendingLyrics()` rather than sleeps; never
call `start()` from a test, which would reach the real players.
