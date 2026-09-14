#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
OUTPUT_DIR="$PROJECT_DIR/dist"
APP_DIR="$OUTPUT_DIR/Mac Stats.app"
UNIVERSAL_ROOT="$PROJECT_DIR/.build/universal"
ARM_ROOT="$UNIVERSAL_ROOT/arm64"
INTEL_ROOT="$UNIVERSAL_ROOT/x86_64"
PLIST="$PROJECT_DIR/Resources/Info.plist"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
BUNDLE_IDENTIFIER="${MAC_STATS_BUNDLE_ID:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")}" 

build_architecture() {
    local architecture="$1"
    local scratch="$2"
    swift build -c release --triple "${architecture}-apple-macosx13.0" --scratch-path "$scratch"
}

cd "$PROJECT_DIR"
mkdir -p "$UNIVERSAL_ROOT/module" "$UNIVERSAL_ROOT/clang" "$UNIVERSAL_ROOT/swiftpm"
export SWIFTPM_MODULECACHE_OVERRIDE="$UNIVERSAL_ROOT/module"
export CLANG_MODULE_CACHE_PATH="$UNIVERSAL_ROOT/clang"
export XDG_CACHE_HOME="$UNIVERSAL_ROOT/swiftpm"

if [[ ! -f "$PROJECT_DIR/Resources/AppIcon.icns" || ! -f "$PROJECT_DIR/Resources/MenuBarIcon.png" || ! -f "$PROJECT_DIR/Resources/MenuBarIcon@2x.png" ]]; then
    "$PROJECT_DIR/Scripts/generate-icon.sh"
fi

build_architecture arm64 "$ARM_ROOT"
build_architecture x86_64 "$INTEL_ROOT"

ARM_BINARY="$(swift build -c release --triple arm64-apple-macosx13.0 --scratch-path "$ARM_ROOT" --show-bin-path)/MacStats"
INTEL_BINARY="$(swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path "$INTEL_ROOT" --show-bin-path)/MacStats"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
lipo -create "$ARM_BINARY" "$INTEL_BINARY" -output "$APP_DIR/Contents/MacOS/MacStats"
cp "$PLIST" "$APP_DIR/Contents/Info.plist"
"$PROJECT_DIR/Scripts/apply-build-number.sh" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$APP_DIR/Contents/Info.plist"
if [[ -n "${MAC_STATS_ANALYTICS_ENDPOINT:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :MacStatsAnalyticsEndpoint $MAC_STATS_ANALYTICS_ENDPOINT" "$APP_DIR/Contents/Info.plist"
fi
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Resources/MenuBarIcon.png" "$APP_DIR/Contents/Resources/MenuBarIcon.png"
cp "$PROJECT_DIR/Resources/MenuBarIcon@2x.png" "$APP_DIR/Contents/Resources/MenuBarIcon@2x.png"
cp "$PROJECT_DIR/Resources/PrivacyInfo.xcprivacy" "$APP_DIR/Contents/Resources/PrivacyInfo.xcprivacy"
for localization in "$PROJECT_DIR"/Sources/MacStats/Resources/*.lproj; do
    ditto "$localization" "$APP_DIR/Contents/Resources/${localization:t}"
done

if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --deep --options runtime --timestamp=none --sign - "$APP_DIR"
else
    codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
lipo -archs "$APP_DIR/Contents/MacOS/MacStats"
echo "$APP_DIR"
