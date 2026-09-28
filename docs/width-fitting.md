# Width fitting

macOS has no API for how much menu bar room is free, so `MenuBarFit` measures it
by watching the real status item. The item's window is in this process, and
`StatusItemController.render` hands it to `MenuBarFit.itemWindow` (weak) on every
render; `itemFrame` reads it from there. The frame is readable; only the item's
ordering among other apps' items is chosen by the system — don't write geometry
that depends on it.

## What "too wide" looks like

A too-wide item is not hidden. It pushes neighbouring items aside, and past a
point it collapses across the notch. Measured on a 1728×1117 notched display
with the status strip at `x ∈ [956, 1728]`:

```
requested box   item x    item width   item right edge
 100 → 250      1134→984   116→266     1250   ← fits: nobody displaced
 275            1026       291         1317   ← neighbours pushed out
 575+            659       591         1250   ← collapses across the notch
```

So the signal is **our right edge moving**: while we fit, the items to our right
hold `maxX` still. That is `MenuBarFit.crowdsNeighbours`, plus a guard that we
never reach left of `auxiliaryTopRightArea.minX`.

## Calibration

`calibrate` binary-searches the widest non-crowding box:

1. Settle at the 80pt floor and record `rightEdge`.
2. Start at `optimisticBound` (`rightEdge - stripLeftEdge - padding`).
3. Binary-search down to `probeResolution` (8pt).
4. Cache the result in `UserDefaults` under a screen-configuration signature.

Two rules keep the search honest:

- **Recover after every rejection.** A wide probe displaces neighbours, and they
  do not snap back instantly. `recover(to:)` reapplies the last good width and
  settles before the next probe, so each measurement starts from a settled bar.
- **Read geometry only through `settle(at:timeout:apply:)`.** It applies the
  width, waits for it to match, waits `neighbourGrace` (140ms), then re-reads.
  Our own origin can lag our width by ~150ms; reading early once produced a
  right edge 175pt off and pinned the fit at the floor. The floor baseline,
  `probe` and `recover` all use `settle`. Route any new reader through it too;
  never call `frame(forBox:)` directly.

On the reference display this converges at about 253–255pt.

## Drift watchdog

`FitCoordinator.checkDrift`, called from the metadata tick, compares the item's
`maxX` with `expectedRightEdge`. Two consecutive probes beyond `driftTolerance`
mean another app added or removed a status item.

- **`driftTolerance` is `probeResolution` (8pt)**, so a clock growing from
  `9:41` to `10:41` does not trigger a recalibration.
- **`recalibrationCooldown` is 30s**, and the check is skipped while calibrating
  or while `probeWidth` is set.
- **It acts in one direction.** Being squeezed recalibrates now. Room freeing up
  only invalidates the cache, so the next launch uses it; the width never grows
  under the user mid-session.

## Width bands

`LyricWidth` bands are **shares of the measured fit** (0.5 / 0.75 / 1.0), so they
stay distinct on a crowded bar. Absolute point values used to collapse into the
same clamped width. `bandsStayDistinct` pins this. A stored preference that no
longer decodes (such as the removed `wide`) falls back to `.fill`.

`lyricBoxWidth` is both the box and the reflow budget. `rebuildMenuLines` must use
`lyricBoxWidth`, never `boxWidth`, which follows calibration probes.

The budget is in points, not characters: in the menu bar font a character spans
3.47pt ("i") to 12.85pt ("W"). Don't show a character count in the Width menu.

The font is `NSFont.menuBarFont(ofSize:)`, read from the system via
`baseFontSize`. Resolve screen geometry against `MenuBarMetrics.menuBarScreen`
(`NSScreen.screens.first`), never `NSScreen.main`, which follows keyboard focus
across displays.

## Logging

The width detection is permanently instrumented with `os.Logger` under subsystem
`net.local.lyricbar`:

| category | contents |
| --- | --- |
| `calibration` | `cacheHit`/`cacheMiss`, `requested`, `begin`, `floorSettled`, `optimisticBound`, one `probe#N` per candidate with its verdict, `recover`, `converged`, `stored`, `applied`, `noFit` |
| `drift` | `observed`, `settled`, `invalidated`, `roomFreed`, `suppressed reason=cooldown` |
| `render` | `drew` per render (`.debug`), `clipped` when text overflows its box (`.error`) |
| `login` | `failed` when `SMAppService` register/unregister throws (owned by `LoginItem`) |

Calibration reasons are `FitCoordinator.Reason` raw values: `launch-no-cache`,
`drift-squeezed`, `screen-change`.

**Levels are chosen for persistence.** `.notice` and `.error` persist to disk;
`.info` is memory-only; `.debug` is kept only while streaming. Everything in
`calibration` and `drift` is `.notice` or `.error` so it can be read after the
fact. Only `drew` is `.debug`. Don't lower a `probe#N` line to `.info`.

```sh
log stream --predicate 'subsystem == "net.local.lyricbar"' --level debug --style compact
log show   --predicate 'subsystem == "net.local.lyricbar"' --last 6h --style compact
```

In zsh, `log` is a shell built-in; call `/usr/bin/log` from scripts.

`stored` and `invalidated` are logged by `FitCoordinator`, not inside
`MenuBarFit.store`/`invalidate`, which tests call with synthetic values. Logging
there would put fake fits into the real unified log on every test run.

`render` measures each render a second time (`fittedFontSize` plus one
`textWidth`). That is cheap because renders happen on line changes; if `render()`
ever fires per frame, gate `logFit` first.

Every `FitLog` helper takes only numbers, rects or durations, and `render` logs
`chars=` rather than text, so the logs cannot carry a lyric. Don't add a `FitLog`
helper that takes a `String`, and never mark a lyric `.public`.

### A healthy calibration

```
cacheMiss signature=1728-1117-2-956-772-1-130 preference=fill
begin floor=80 upperBound=756 leftLimit=956 padding=16
floorSettled minX=1153 maxX=1249 width=96 rightEdge=1249
optimisticBound start=277 span=197 resolution=8
probe#1 box=277 verdict=rejected reason=moved-right-edge shift=69
recover box=80 outcome=settled
probe#2 box=179 verdict=accepted
probe#3 box=228 verdict=accepted
probe#4 box=253 verdict=accepted
probe#5 box=265 verdict=rejected reason=moved-right-edge shift=69
probe#6 box=259 verdict=rejected reason=moved-right-edge shift=69
converged box=253 outcome=fitted probes=6
```

Rejections are how a binary search finds the boundary; they are not faults.

### Faults

| line | meaning |
| --- | --- |
| `abandoned reason=floor-never-appeared` | The item never reached `floor + padding`. Suspect `length` assigned with padding added. Nothing is cached. |
| `converged outcome=pinned-at-floor` | Every probe was rejected. Suspect settle/recover, not geometry. |
| `probe#N reason=never-settled` | The item never took the requested width within `settleTimeout`. |
| `probe#N reason=lost-width-during-grace` | It took the width, then lost it during `neighbourGrace`. |
| `probe#N reason=crossed-left-limit` | The item reached left of `auxiliaryTopRightArea.minX`. |
| `abandoned reason=floor-lost-width-during-grace` | The bar is thrashing; nothing cached, old fit kept. |
| `floorRelaidOut shift=…` | Not a fault: `settle` corrected a stale origin. Expected on drift recalibrations. |
| `noFit` | Calibration returned nil; the old fit is kept. |
| `clipped … probing=true` | A lyric rendered during a probe — the probing guard failed. |
| `clipped … probing=false fontSize=9.0` | The backstop hit its floor and still overflowed; the reflow budget is wrong. |

## Verifying against the live item

No test can prove the item is right. To check the fit end to end:

```sh
defaults delete net.local.lyricbar "fittedBox.<signature>"   # keeps the Width preference
open /Applications/LyricBar.app
sleep 15 && defaults read net.local.lyricbar
```

A cached `(box, rightEdge)` near `(253, 1249)` on the reference display means it
converged. A box equal to the 80pt floor means every probe was rejected. For more
detail, read the `calibration` log. Stream `render` at `--level debug` and look
for `clipped` to check text fit.
