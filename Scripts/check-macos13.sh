#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
BUILD_CACHE="$PROJECT_DIR/.build/macos13-check"

cd "$PROJECT_DIR"
mkdir -p "$BUILD_CACHE/module" "$BUILD_CACHE/clang" "$BUILD_CACHE/swiftpm"
export MACOSX_DEPLOYMENT_TARGET=13.0
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_CACHE/module"
export CLANG_MODULE_CACHE_PATH="$BUILD_CACHE/clang"
export XDG_CACHE_HOME="$BUILD_CACHE/swiftpm"

swift test --disable-sandbox
swift build --disable-sandbox -c release

test -f Resources/Info.plist
test -f Resources/PrivacyInfo.xcprivacy
test -f Sources/MacStats/Resources/en.lproj/Localizable.strings
test -f Sources/MacStats/Resources/zh-Hans.lproj/Localizable.strings

echo "macOS 13 compatibility checks passed."
