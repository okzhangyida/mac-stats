#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
CONFIGURATION="${1:-release}"
OUTPUT_DIR="$PROJECT_DIR/dist"
APP_DIR="$OUTPUT_DIR/Mac Stats.app"
BUILD_CACHE="$PROJECT_DIR/.build/local-cache"

cd "$PROJECT_DIR"
mkdir -p "$BUILD_CACHE/module" "$BUILD_CACHE/clang" "$BUILD_CACHE/swiftpm"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_CACHE/module"
export CLANG_MODULE_CACHE_PATH="$BUILD_CACHE/clang"
export XDG_CACHE_HOME="$BUILD_CACHE/swiftpm"
if [[ ! -f "$PROJECT_DIR/Resources/AppIcon.icns" || ! -f "$PROJECT_DIR/Resources/MenuBarIcon.png" || ! -f "$PROJECT_DIR/Resources/MenuBarIcon@2x.png" ]]; then
    "$PROJECT_DIR/Scripts/generate-icon.sh"
fi
swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/MacStats" "$APP_DIR/Contents/MacOS/MacStats"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Resources/MenuBarIcon.png" "$APP_DIR/Contents/Resources/MenuBarIcon.png"
cp "$PROJECT_DIR/Resources/MenuBarIcon@2x.png" "$APP_DIR/Contents/Resources/MenuBarIcon@2x.png"
cp "$PROJECT_DIR/Resources/PrivacyInfo.xcprivacy" "$APP_DIR/Contents/Resources/PrivacyInfo.xcprivacy"
for localization in "$PROJECT_DIR"/Sources/MacStats/Resources/*.lproj; do
    ditto "$localization" "$APP_DIR/Contents/Resources/${localization:t}"
done
codesign --force --deep --options runtime --timestamp=none --sign - "$APP_DIR"

echo "$APP_DIR"
