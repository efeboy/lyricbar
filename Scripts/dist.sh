#!/bin/bash
#
# Build, sign, notarize and package LyricBar for distribution outside the App Store.
#
#   Scripts/dist.sh [keychain-profile]      (default profile: lyricbar-notary)
#
# One-time setup. Storing the app-specific password in the keychain keeps it out
# of shell history:
#
#   xcrun notarytool store-credentials lyricbar-notary \
#     --apple-id <apple-id> --team-id TV42VPF482
#
# Apple requires all of the following for notarization, and every one of them is
# a step below rather than an assumption:
#
#   - a "Developer ID Application" certificate. NOT Apple Development and NOT
#     Apple Distribution; Apple's docs reject both by name.
#   - the Hardened Runtime (set in the target, verified here).
#   - a secure timestamp.
#   - no com.apple.security.get-task-allow entitlement.
#
# The App Store and TestFlight are not alternatives for this app. App Sandbox is
# mandatory there, and the sandbox forbids "sending Apple Events to arbitrary
# apps" — which is precisely how LyricBar reads Spotify and Music.

set -euo pipefail

PROFILE="${1:-lyricbar-notary}"
TEAM_ID="TV42VPF482"
CERT="Developer ID Application"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="$OUT/$STAMP"
ARCHIVE="$WORK/LyricBar.xcarchive"
EXPORT="$WORK/export"
STAGE="$WORK/stage"
APP="$EXPORT/LyricBar.app"

step() { printf '\n==> %s\n' "$1"; }

step "checking for a $CERT certificate"
# Capture once and match with a here-string. Piping into `grep -q` under
# `set -o pipefail` is a trap: grep exits on the first match, the writer takes
# SIGPIPE and returns 141, and the pipeline is reported as failed.
IDENTITIES="$(security find-identity -v -p codesigning)"
grep -q "$CERT" <<<"$IDENTITIES" \
  || { echo "no '$CERT' certificate in the keychain."; echo \
       "create one: Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application"; exit 1; }
grep "$CERT" <<<"$IDENTITIES"

mkdir -p "$WORK"

# Keep Spotlight out of the output tree. Every run leaves a LyricBar.app in
# export/ and another in stage/, and an indexed bundle is one Spotlight can
# offer the user in place of the real install — which is exactly how a fixed
# bug went on being reported for hours. `.metadata_never_index` is Apple's
# marker for "do not index this directory tree"; it only takes effect for
# content indexed after it exists, hence creating it before the archive.
touch "$OUT/.metadata_never_index"

# archive, NOT build. `xcodebuild build` signs with the development certificate,
# leaves get-task-allow in place, and emits a single-architecture binary despite
# ARCHS listing both. Only the archive/export workflow produces a distributable.
step "archiving (universal, Release)"
xcodebuild -project "$ROOT/LyricBar.xcodeproj" -scheme LyricBar -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" archive

step "exporting with Developer ID"
cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" -exportPath "$EXPORT"

step "verifying the exported app against Apple's notarization requirements"
SIG="$(codesign -dvvv "$APP" 2>&1)"
ENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p -)"
grep -q "Authority=$CERT" <<<"$SIG"  || { echo "FAIL: not signed with $CERT"; exit 1; }
grep -q "flags=.*runtime" <<<"$SIG"  || { echo "FAIL: Hardened Runtime is not enabled"; exit 1; }
grep -q "^Timestamp=" <<<"$SIG"      || { echo "FAIL: no secure timestamp"; exit 1; }
if grep -q '"com.apple.security.get-task-allow" => 1' <<<"$ENTS"; then
  echo "FAIL: get-task-allow is present, notarization would be rejected"; exit 1
fi
ARCHS="$(lipo -archs "$APP/Contents/MacOS/LyricBar")"
echo "signed, hardened, timestamped, no get-task-allow; architectures: $ARCHS"
case "$ARCHS" in *x86_64*arm64*|*arm64*x86_64*) ;; *) echo "WARNING: not universal ($ARCHS)";; esac

# Notarize the app first and staple it, so the copy placed inside the disk image
# already carries its own ticket. A stapled app validates with no network.
step "notarizing the app"
ditto -c -k --keepParent "$APP" "$WORK/app-submit.zip"
xcrun notarytool submit "$WORK/app-submit.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

step "building the disk image"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/LyricBar.app"
ln -s /Applications "$STAGE/Applications"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$OUT/LyricBar-$VERSION.dmg"
hdiutil create -volname "LyricBar" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --sign "$CERT: EFE YEKTA KAYA ($TEAM_ID)" --timestamp "$DMG"

# The disk image is notarized and stapled in its own right, so Gatekeeper clears
# it before the user ever mounts it.
step "notarizing the disk image"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

step "verifying the finished disk image as a downloader receives it"
xcrun stapler validate "$DMG"
spctl -a -vvv -t open --context context:primary-signature "$DMG"

printf '\nready to distribute: %s (%s)\n' "$DMG" "$(du -h "$DMG" | cut -f1)"
