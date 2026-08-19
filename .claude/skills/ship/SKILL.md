---
name: ship
description: Build, install and verify LyricBar so exactly one current copy exists on the machine. Use whenever a change needs to reach the running app - "ship it", "install it", "update the app", "let me test the fix", "why is it still doing X after we fixed it" - and before asking the user to observe live behaviour. Also use to sweep stale LyricBar.app bundles.
---

# Shipping LyricBar

## The invariant

**Exactly one current LyricBar.app, at `/Applications`, and that is what the user
runs.** Everything else on disk is older than it.

This exists because it was violated. A fix was committed, verified live, and the
user still saw the bug for hours - they had launched LyricBar from Spotlight,
which offered a `DerivedData/Build/Products/Release` copy built eight hours
before the fix. Ten `LyricBar.app` bundles were indexed at the time. The app has
no version display and no update check, so **nothing in the UI tells you which
build you are looking at.** Only the paths and the logs do.

Treat "the user reports a bug we already fixed" as a build-identity question
first and a code question second.

## Decide which of the two paths you are on

| you want | do this | goes to `/Applications`? |
| --- | --- | --- |
| to check a change compiles / tests pass | `xcodebuild ... build` or `test` | **no** |
| to observe live behaviour, or hand the app back to the user | `Scripts/dist.sh` | **yes** |

There is no third path. In particular there is no "quick install" - see below.

## Never install a `build` output

`xcodebuild build` produces something that looks installable and is not.
Measured on this project:

- signed `Apple Development`, not `Developer ID Application`
- `com.apple.security.get-task-allow` present
- `arm64` only, though `ARCHS` lists both
- `spctl` rejects it; no stapled ticket

`ditto`ing that into `/Applications` yields an app that runs on this machine and
fails everywhere else, with a signature that cannot be notarized. Only
`archive` + `-exportArchive` produce a distributable, which is what
`Scripts/dist.sh` does. This mistake has been made once already.

## Shipping

```sh
Scripts/dist.sh [keychain-profile]        # default profile: lyricbar-notary
```

Archive -> export -> verify -> notarize -> staple -> DMG -> notarize -> staple
-> validate. It asserts rather than hopes at every step, so a green run is
evidence. It needs a `Developer ID Application` certificate and a stored
notarytool profile; if either is missing it fails early and says so.

Notarization uploads the binary to Apple and takes minutes. **Confirm with the
user before running it** - it is outward-facing and not free.

If the user only needs a correct local install and does not want to notarize,
say so explicitly and stop at archive + export; do not silently substitute a
`build` output.

Then install and restart:

```sh
pkill -x LyricBar; sleep 2
mkdir -p ~/.Trash/lyricbar-stale-$(date +%Y%m%d-%H%M%S)
mv /Applications/LyricBar.app ~/.Trash/lyricbar-stale-<stamp>/
ditto <export>/LyricBar.app /Applications/LyricBar.app
open /Applications/LyricBar.app
```

Use `mv` into a timestamped `~/.Trash` folder. Never `rm -rf`.

Keeping the same `/Applications` path matters: `SMAppService.mainApp` registers
the bundle path it was launched from, so replacing in place preserves any login
item registration.

## Verify - do not assume

```sh
ps -o command= -p "$(pgrep -x LyricBar)"     # must be /Applications/...
codesign -dvvv /Applications/LyricBar.app 2>&1 | grep -E 'Authority=|flags=|^Timestamp='
codesign -d --entitlements - --xml /Applications/LyricBar.app | plutil -p - | grep get-task-allow
lipo -archs /Applications/LyricBar.app/Contents/MacOS/LyricBar
spctl -a -vvv /Applications/LyricBar.app
```

Expect `Authority=Developer ID Application`, `flags=...runtime`, a `Timestamp=`,
**no** `get-task-allow`, `x86_64 arm64`, and `accepted`.

Then confirm the running process is instrumented and the fragile subsystem is
healthy - a build predating the logging is silent, which is itself the signal:

```sh
log show --predicate 'subsystem == "net.local.lyricbar"' --last 2m --style compact
```

A launch must produce `cacheHit` or `cacheMiss` and, on a miss, a full
calibration ending `converged ... outcome=fitted`. **No output at all means the
running binary predates the logging** - you are looking at a stale build, not a
working one. See CLAUDE.md, "The width detection logs itself".

## Sweep stale bundles

```sh
mdfind "kMDItemFSName == 'LyricBar.app'" | grep -v '/.Trash/'
```

Anything older than `/Applications` can be offered by Spotlight and picked by
the user. Move Xcode `DerivedData` copies to `~/.Trash/lyricbar-stale-<stamp>/`.

**Leave `dist/` alone.** Those are deliberate signed release archives, not
clutter. Ask before touching them.

Xcode recreates `DerivedData` bundles on the next IDE build, so this reduces the
trap rather than removing it. If the user reports odd behaviour, re-run the
`mdfind` sweep before debugging code.

## Do not

- install a `build` output anywhere (above)
- `rm -rf` any bundle - use `~/.Trash`
- delete `dist/` archives without asking
- commit or push without per-action approval; `main` needs it every time
- report "shipped" without the verification block above actually passing
