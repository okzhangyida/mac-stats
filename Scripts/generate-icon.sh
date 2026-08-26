#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SOURCE_PNG="$PROJECT_DIR/Resources/AppIcon-1024.png"
MENUBAR_PNG="$PROJECT_DIR/Resources/MenuBarIcon.png"
MENUBAR_2X_PNG="$PROJECT_DIR/Resources/MenuBarIcon@2x.png"
ICONSET_DIR="$PROJECT_DIR/.build/AppIcon.iconset"
OUTPUT_ICNS="$PROJECT_DIR/Resources/AppIcon.icns"

mkdir -p "$PROJECT_DIR/Resources" "$ICONSET_DIR"
swift "$PROJECT_DIR/Scripts/generate-icon.swift" "$SOURCE_PNG" "$MENUBAR_PNG" "$MENUBAR_2X_PNG"

sips -z 16 16 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$SOURCE_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

swift "$PROJECT_DIR/Scripts/pack-icns.swift" "$ICONSET_DIR" "$OUTPUT_ICNS"
echo "$OUTPUT_ICNS"
