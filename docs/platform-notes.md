# Platform notes

Constraints that are easy to break, mostly around AppleScript and Apple's
frameworks.

## AppleScript

- **`st` is a reserved token.** `set st to 5` is a syntax error, which silently
  breaks the whole script at runtime. Avoid short, grammar-adjacent identifiers.
- **Never coerce `player position` to text.** `as text` uses the system locale
  and can produce `134,2799`, which `Double()` rejects. Read the descriptor's
  `doubleValue` (`PlaybackScript.position(from:)`).
- **Spotify's `duration` is in milliseconds**, despite its dictionary saying
  seconds; `SpotifyBridge` divides above `millisecondThreshold`. **Apple Music's
  is already seconds.** Verify dictionaries with `sdef`.
- **Apple Music has extra states** (`fast forwarding`, `rewinding`), collapsed to
  `playing` in-script. Track identity is `persistent ID` for Music and `id` for
  Spotify.

## Automation permission

macOS asks once per controlled app. The prompt needs
`INFOPLIST_KEY_NSAppleEventsUsageDescription` and, under the Hardened Runtime,
the `com.apple.security.automation.apple-events` entitlement. Without the string
the prompt never appears.

A refused prompt returns **-1743** (`errAEEventNotPermitted`); **-1744** means
consent is still pending. `PlaybackScript.fields` maps both to `.denied`, which
is why `snapshot()` returns `BridgeSnapshot` rather than `NowPlaying?`.
`probeSources` reports a denial only when nothing else is playing, so one refused
app never masks another that works. Denied, the item shows `⚠︎` at full opacity,
the status row reads "Automation access denied", and the menu offers **Open
Automation Settings…**
(`x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`).
That item is gated on `displayState == .denied`.

Inspecting the TCC database needs Full Disk Access; check System Settings ▸
Privacy & Security ▸ Automation instead.

## Swift and Observation

- **A `Regex` is not `Sendable`**, so a regex literal cannot be a `static let`
  under Swift 6. `LRCParser.parse` binds it as a local constant.
- **`@Observable` stored-property initializers** cannot reference `Self.x`;
  spell out the type (`PlaybackModel.idleTitle`). `init` cannot read one assigned
  property to compute another, so compute into locals first.
- **Settable observable properties use `get`/`set` over a private store**, not
  `didSet`, so the setter can persist and rebuild the reflow. Keep that shape.
- Build settings deliberately omit `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
  and `SWIFT_APPROACHABLE_CONCURRENCY`; either would move `LRCLibClient`'s
  decoding onto the main actor.

## Open at Login

`SMAppService.Status` has two "off" states: `.notFound` (never registered) and
`.notRegistered` (unregistered). `LoginItem.isEnabled` tests `== .enabled`; a
`!= .notRegistered` test would report a fresh install as enabled.

`SMAppService.mainApp` registers whatever path the app was launched from, so
`LoginItem.isStableLocation` rejects paths containing `/DerivedData/` or
`/Build/Products/` and the toggle is greyed out there. Both markers are needed.
A copy in `/Applications` works normally; failures are logged to the `login`
category.

## Localization

Every user-facing string is `String(localized:)`, extracted into
`LyricBar/Localizable.xcstrings` (English only for now). **Only an Xcode IDE
build syncs the catalog; `xcodebuild` does not**, so build once in Xcode before
committing a new string. The `"\(title) — \(artist)"` header is deliberately not
localized.

## Performance

Steady-state CPU was ~4.5% of one core on the old AppKit build, and it was
status-item overhead, not the poll loop — identical playing or paused. Don't add
a tick-rate setting on CPU grounds without re-profiling. Measure cumulative CPU
time over at least 60s; instantaneous `ps %cpu` swings between 1.5% and 9%.
