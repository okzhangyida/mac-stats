#!/bin/zsh
set -euo pipefail

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the full Developer ID Application certificate name.}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile.}"

PROJECT_DIR="${0:A:h:h}"
MAC_STATS_BUNDLE_ID="${MAC_STATS_BUNDLE_ID:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PROJECT_DIR/Resources/Info.plist")}"
export CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"
export MAC_STATS_BUNDLE_ID
export MAC_STATS_ANALYTICS_ENDPOINT="${MAC_STATS_ANALYTICS_ENDPOINT:-https://macstats-api.justbro.ai/v1/events}"
export MAC_STATS_PACKAGE_LABEL="candidate"

"$PROJECT_DIR/Scripts/build-universal.sh"
DMG_PATH="$("$PROJECT_DIR/Scripts/package-dmg.sh" "$PROJECT_DIR/dist/Mac Stats.app")"
codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
FINAL_DMG="${DMG_PATH/-candidate-universal.dmg/-notarized-universal.dmg}"
mv "$DMG_PATH" "$FINAL_DMG"
rm -f "$DMG_PATH.sha256"
hdiutil verify "$FINAL_DMG"
shasum -a 256 "$FINAL_DMG" > "$FINAL_DMG.sha256"
echo "$FINAL_DMG"
