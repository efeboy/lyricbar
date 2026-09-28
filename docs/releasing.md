# Building, installing and releasing

## Target settings

These are load-bearing; don't "clean them up":

- Deployment target **macOS 14.0** (`@Observable` and the no-argument
  `NSApp.activate()` need 14).
- Bundle identifier **`net.local.lyricbar`**; `SMAppService.mainApp` keys off it.
- **Hardened Runtime on, App Sandbox off.** Sending Apple Events to Spotify and
  Music is incompatible with the sandbox, which also rules out the App Store.
- **No `Info.plist` file.** It is generated from `INFOPLIST_KEY_*` settings,
  including `LSUIElement = YES` (no Dock icon) and the Automation prompt string.
- `LyricBar/` is a **synchronized folder group**: any file in it joins the
  target. Keep non-source files out of it.
- **Swift 6 language mode**, without default main-actor isolation.

## Installing a build locally

Only `archive` + `-exportArchive` produce an installable app. **Never copy an
`xcodebuild build` output into `/Applications`**: it is signed Apple
Development, keeps `get-task-allow`, is single-architecture, and Gatekeeper
rejects it.

Keep exactly one current `LyricBar.app`, at `/Applications`. The version row
shows only the marketing version, so two builds of the same version look
identical, and Spotlight can launch a stale copy from a build folder. When a
fixed bug is reported again, check which bundle is running first:

```sh
ps -o command= -p "$(pgrep -x LyricBar)"
mdfind "kMDItemFSName == 'LyricBar.app'" | grep -v '/.Trash/'
```

Move stale copies to the Trash rather than deleting them. `.metadata_never_index`
in a build folder does not reliably keep its bundles out of Spotlight.

## Releasing

`Scripts/dist.sh` archives a universal Release build, exports it with Developer
ID, verifies the notarization requirements (Developer ID, Hardened Runtime,
secure timestamp, no `get-task-allow`), notarizes and staples the app, builds a
DMG, then notarizes, staples and verifies the DMG. It needs a Developer ID
Application certificate and a `notarytool` keychain profile (default
`lyricbar-notary`).

1. Set `MARKETING_VERSION` to the new version.
2. Run `Scripts/dist.sh`. It uploads to Apple and takes a few minutes.
3. `gh release create vX.Y dist/LyricBar-X.Y.dmg` with install notes.
4. Check the downloaded DMG with
   `spctl -a -vvv -t open --context context:primary-signature`.

A notarized app still shows a one-time "downloaded from the Internet" prompt on
first launch; that is expected.

## Updates

`UpdateChecker` runs at `start()` and every `checkInterval` (24h). It GETs
`https://api.github.com/repos/efeboy/lyricbar/releases/latest` without a token,
and if `tag_name` is newer than `CFBundleShortVersionString` the menu shows
**Update Available (vX.Y)…**, which opens the release page. The user installs by
dragging the new app over the old one.

- **The repository must stay public.** GitHub returns 404 for a private repo
  without a token, which the checker treats as "no release" — making it private
  would silently disable updates for every installed copy.
- Any non-200 response, including 404 before the first release, means no update.
  There is no error UI.
- The unauthenticated limit is 60 requests an hour per IP; daily is far below it.
- **Tags must be plain dotted integers, optionally `v`-prefixed** (`v1.2`,
  `1.2.1`). Anything else, such as `v1.3-beta`, never offers an update. Keep
  `MARKETING_VERSION` and the tag in step.

The repository was made public on 2026-09-28 after a history rewrite replaced the
author email with the GitHub noreply address and quoted lyrics with invented
lines. Keep real lyrics and personal addresses out of commits.
