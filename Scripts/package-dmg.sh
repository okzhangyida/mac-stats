#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="${1:-$PROJECT_DIR/dist/Mac Stats.app}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
LABEL="${MAC_STATS_PACKAGE_LABEL:-UNNOTARIZED}"
DMG_PATH="$PROJECT_DIR/dist/Mac-Stats-${VERSION}-${LABEL}-universal.dmg"
STAGING_DIR="$(mktemp -d /tmp/mac-stats-dmg.XXXXXX)"
trap 'rm -rf "$STAGING_DIR"' EXIT

ditto "$APP_DIR" "$STAGING_DIR/Mac Stats.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -quiet -volname "Mac Stats" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
hdiutil verify "$DMG_PATH"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
echo "$DMG_PATH"
