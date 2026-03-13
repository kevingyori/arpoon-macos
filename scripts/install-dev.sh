#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.deriveddata"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/Arpoon.app"

xcodebuild \
  -project "$ROOT_DIR/Arpoon.xcodeproj" \
  -scheme Arpoon \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

ditto "$APP_PATH" /Applications/Arpoon.app
open /Applications/Arpoon.app
