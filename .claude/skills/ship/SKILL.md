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
before the fix. Ten `LyricBar.app` bundles were indexed at the time. The menu
now shows a version row, but it is the marketing version only, so **two builds
of the same version look identical in the UI** — and every unreleased fix is one
of those. Only the paths and the logs tell them apart.

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

**A healthy machine prints exactly one line: `/Applications/LyricBar.app`.**
Anything else can be offered by Spotlight and picked by the user.

Move build outputs - `DerivedData`, the repo's `build/`, and the `export/` copy
a local ship just installed from - to `~/.Trash/lyricbar-stale-<stamp>/`. The
export copy is the easiest one to forget: it is byte-identical to what you just
installed, which makes it the most convincing wrong answer Spotlight can give.

**Ask before touching `dist/`.** The `.dmg` at its root is the deliverable and
must stay. The timestamped run folders under it are intermediates
(`xcarchive` + `export/` + `stage/`), and each one adds two more indexed
bundles.

### Stop them being indexed in the first place

`.metadata_never_index` is Apple's marker for "do not index this directory
tree". `Scripts/dist.sh` now creates one in `dist/` before it archives; the
same marker belongs anywhere builds land:

```sh
touch ~/Library/Developer/Xcode/DerivedData/.metadata_never_index
touch <repo>/build/.metadata_never_index
```

**The marker is not retroactive.** It stops future indexing; bundles already in
the index stay there, and moving the directory does not flush them - measured.
So the marker prevents the next trap while the `~/.Trash` sweep clears the
current one. Both are needed.

If the user reports odd behaviour, or says the app is not what you built, run
the `mdfind` sweep before debugging code.

## Do not

- install a `build` output anywhere (above)
- `rm -rf` any bundle - use `~/.Trash`
- delete `dist/` archives without asking
- commit or push without per-action approval; `main` needs it every time
- report "shipped" without the verification block above actually passing
