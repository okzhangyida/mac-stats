#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
INFO_PLIST="${1:?usage: apply-build-number.sh <Info.plist>}"
RECORD="$PROJECT_DIR/Build/build-numbers.json"

DISPLAY_BUILD="$(plutil -extract current.build raw -o - "$RECORD")"
MACOS_BUILD="$(plutil -extract current.platformMappings.macOSCFBundleVersion raw -o - "$RECORD")"

if [[ -z "$DISPLAY_BUILD" || -z "$MACOS_BUILD" ]]; then
    echo "error: allocate a build number before building" >&2
    exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $MACOS_BUILD" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :MacStatsBuildNumber $DISPLAY_BUILD" "$INFO_PLIST"
