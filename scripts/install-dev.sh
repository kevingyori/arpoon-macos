#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.deriveddata"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/AppHarpoon.app"

xcodebuild \
  -project "$ROOT_DIR/AppHarpoon.xcodeproj" \
  -scheme AppHarpoon \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

ditto "$APP_PATH" /Applications/AppHarpoon.app
open /Applications/AppHarpoon.app
