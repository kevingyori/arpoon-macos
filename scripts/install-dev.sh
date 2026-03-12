#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.deriveddata"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/Harpoon.app"

xcodebuild \
  -project "$ROOT_DIR/Harpoon.xcodeproj" \
  -scheme Harpoon \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

ditto "$APP_PATH" /Applications/Harpoon.app
open /Applications/Harpoon.app
