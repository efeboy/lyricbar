# LyricBar — Xcode app target setup

The old bare SwiftPM executable (`Sources/LyricBar/main.swift`) is replaced by a
real macOS **App** target so `MenuBarExtra` and `SMAppService` work the textbook
way. The Swift sources, `Info.plist`, and entitlements in this `App/` folder are
complete — you just need to create the target and add them.

## 1. Create the app target

In Xcode: **File ▸ New ▸ Project… ▸ macOS ▸ App**

- Product Name: **LyricBar**
- Interface: **SwiftUI**
- Language: **Swift**
- Uncheck Tests/Core Data.
- Save it at the repo root (`<repo root>`).

Delete the auto-generated `ContentView.swift` and the template `…App.swift`
(this folder already provides `LyricBarApp.swift`).

## 2. Add these sources to the target

Drag every `.swift` file under `App/` into the project navigator, **Add to
target: LyricBar**:

- `LyricBarApp.swift`
- `PlaybackModel.swift`
- `LoginItem.swift`
- `Playback/NowPlaying.swift`, `Playback/SpotifyBridge.swift`, `Playback/MusicBridge.swift`
- `Lyrics/LRCParser.swift`, `Lyrics/LRCLibClient.swift`

## 3. Target settings

**General / Deployment:** macOS **14.0** minimum (MenuBarExtra + SMAppService
are macOS 13+, but the `@Observable` model requires macOS 14 — same minimum the
old package used).

**Signing & Capabilities:**
- Set your Team (or "Sign to Run Locally" for a personal build).
- Enable **Hardened Runtime**.
- Add **App Sandbox = Off** (or just use the provided `LyricBar.entitlements`).
- Point **Code Signing Entitlements** build setting at `App/LyricBar.entitlements`.

**Info.plist:** either set **Info.plist File** = `App/Info.plist`, or add these
keys via the target's Info tab / build settings:
- `LSUIElement` = YES  (`INFOPLIST_KEY_LSUIElement = YES`)
- `NSAppleEventsUsageDescription` = the string in `App/Info.plist`
  (`INFOPLIST_KEY_NSAppleEventsUsageDescription = …`)

**Bundle identifier:** set to `net.local.lyricbar` (matches the old LaunchAgent
label; `SMAppService.mainApp` keys off the bundle id).

## 4. First run

- Build & run. The icon appears in the menu bar.
- macOS prompts once for Automation control of **Spotify** and **Music** — allow
  both (otherwise no lyrics, silently). Verify later in
  System Settings ▸ Privacy & Security ▸ Automation.
- Toggle **Open at login**; confirm it shows under
  System Settings ▸ General ▸ Login Items as "LyricBar".

## Notes

- No more `launchctl`, plist writing, or re-signing dance — `SMAppService`
  handles login registration, and Quit no longer has to disable it.
- Long lines truncate natively in the menu bar (the old scroll marquee is gone —
  there's no Apple API for it).
- Both Spotify and Apple Music are supported; whichever is playing wins, Spotify
  breaking ties.
