#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.deriveddata-release"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/Arpoon.app"
ZIP_PATH="$ROOT_DIR/Arpoon-macOS.zip"

xcodebuild \
  -project "$ROOT_DIR/Arpoon.xcodeproj" \
  -scheme Arpoon \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

rm -f "$ZIP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Created $ZIP_PATH"
