# LyricBar

[![Latest release](https://img.shields.io/github/v/release/efeboy/lyricbar)](https://github.com/efeboy/lyricbar/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
[![License: MIT](https://img.shields.io/github/license/efeboy/lyricbar)](LICENSE)

A macOS menu bar app that shows time-synced lyrics for whatever **Spotify** or
**Apple Music** is currently playing — one line at a time, right in the menu
bar. No Dock icon, no window, no account.

<img src="LyricBar/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="96" alt="LyricBar icon">

## Install

1. Download the latest `LyricBar-x.y.dmg` from
   [Releases](https://github.com/efeboy/lyricbar/releases/latest).
2. Open it and drag **LyricBar** into **Applications**.
3. Launch LyricBar from Applications. The first time, macOS asks
   *"LyricBar is an app downloaded from the Internet. Are you sure you want to
   open it?"* — choose **Open**. A `♪` appears in the menu bar.
4. Play something in Spotify or Music. macOS asks once per app whether LyricBar
   may control it — choose **Allow**. That permission is how LyricBar reads what
   is playing; it never controls playback.

Requires **macOS 14 Sonoma or later**, on Apple Silicon or Intel. The app is
signed and notarized by Apple, so the only prompt at first launch is that
one-time "downloaded from the Internet" confirmation — never a "cannot be
opened" block.

### Using it

Click the lyric to open the menu:

- the first row says what is playing, or why no lyric is showing
- **Hide Lyrics** (⌘P) — keep the item but stop showing lines
- **Settings…** (⌘,) — a popover with **Open at Login** and a slider for how much
  of the menu bar the lyric may use, 160–400pt. If it is too wide for your bar, macOS tucks other icons behind its
  overflow arrow; slide it narrower to bring them back.
- **Tips…** — a few pointers, such as ⌘-dragging the lyric to move it along the
  menu bar
- **Update Available…** appears when a newer release is out

If you refused the permission prompt, the item shows `⚠︎` and the menu offers
**Open Automation Settings…**, which goes straight to System Settings ▸ Privacy &
Security ▸ Automation.

### Updating and removing

When the menu shows **Update Available…**, download the new DMG and drag the app
over the old one in Applications. To remove LyricBar, quit it from its menu and
move it to the Trash (turn off **Open at Login** first if you enabled it).

### What it sends where

- The **title, artist, album and duration** of the playing track go to
  [LRCLIB](https://lrclib.net), a free community lyrics database, to find synced
  lyrics. Nothing else about your library is sent, and there is no account or
  analytics.
- Once a day it asks **GitHub** whether a newer LyricBar release exists.
- LyricBar never writes lyrics to its logs.

Tracks with no synced lyrics on LRCLIB, and instrumentals, show a dimmed `♪`.

## Build from source

Requires Xcode 16 or later (the project uses synchronized folder groups).

```sh
open LyricBar.xcodeproj
```

Select the **LyricBar** scheme and press ⌘R. There is no package manifest and no
third-party dependency — it is a plain Xcode app target, because a status item
and `SMAppService` both need a real app bundle.

**Open at Login** is greyed out for builds run from DerivedData or
`Build/Products`, which would otherwise register a path that vanishes on the
next clean build. It works for a copy in `/Applications`.

To produce a signed, notarized DMG, see `Scripts/dist.sh` (needs a Developer ID
certificate and a stored `notarytool` profile).

## Tests

```sh
xcodebuild -project LyricBar.xcodeproj -scheme LyricBar test
```

Swift Testing suites cover LRC parsing, the active-line search, LRCLIB duration
matching, where a long line breaks and when each chunk swaps, the guarantee that
no lyric is ever truncated, the menu bar fit arithmetic, the update-version
comparison, and the playback tick logic driven through injected fakes. The test
host never starts the poll loop, so tests never touch Spotify, Music, the
network, or the real menu bar.

A green build proves nothing about whether the menu bar item renders or whether
Automation was granted. Verify UI-adjacent behaviour by running the app.

## Layout

```
LyricBar/                     app sources (synchronized folder — add a file, it builds)
├── LyricBarApp.swift         App entry point and AppDelegate
├── StatusItemController.swift  the NSStatusItem, its width, and its menu
├── LyricLabel.swift          SwiftUI view that draws the lyric inside the item
├── PlaybackModel.swift       @Observable model; owns the poll loop
├── ItemPopover.swift         popovers anchored to the item (Settings, Tips)
├── SettingsView.swift        width slider and Open at Login
├── TipsView.swift            usage tips
├── MenuHeader.swift          the menu's wrapping header row
├── MenuBarMetrics.swift      text measurement, width ladder, screen geometry
├── LyricText.swift           font-size backstop for lines that barely overflow
├── UpdateChecker.swift       GitHub Releases check
├── LoginItem.swift           SMAppService wrapper
├── FitLog.swift              render logging
├── Playback/                 NowPlaying snapshot + Spotify / Music AppleScript bridges
├── Lyrics/                   LRC parser, reflow, LRCLIB client
├── Localizable.xcstrings     String Catalog
├── Assets.xcassets           app icon, accent color
└── LyricBar.entitlements     sandbox off, Apple Events on
LyricBarTests/                Swift Testing suites
```

The Swift sources carry **no comments** by design — the reasoning behind them is
in [`docs/`](docs): [architecture](docs/architecture.md),
[the menu bar item](docs/menu-bar-item.md), [width](docs/width.md),
[lyrics](docs/lyrics.md), [platform notes](docs/platform-notes.md),
[releasing](docs/releasing.md) and [testing](docs/testing.md). Read the relevant
one before changing the width, `LyricLabel`, or the bridges.

`Info.plist` is generated by Xcode from `INFOPLIST_KEY_*` build settings —
`LSUIElement` and `NSAppleEventsUsageDescription` are set there, not in a file.

## License

[MIT](LICENSE). Lyrics are fetched at runtime from [LRCLIB](https://lrclib.net) and are
not part of this repository or its license.
