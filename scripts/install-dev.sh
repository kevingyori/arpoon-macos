#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.deriveddata"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/Arpoon.app"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required to generate the Xcode project before building." >&2
  exit 1
fi

xcodegen generate --spec "$ROOT_DIR/project.yml"

xcodebuild \
  -project "$ROOT_DIR/Arpoon.xcodeproj" \
  -scheme Arpoon \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

ditto "$APP_PATH" /Applications/Arpoon.app
open /Applications/Arpoon.app
