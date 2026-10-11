#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.deriveddata"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/Arpoon.app"
BUNDLE_ID="dev.kevingyori.Arpoon"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required to generate the Xcode project before building." >&2
  exit 1
fi

xcodegen generate --spec "$ROOT_DIR/project.yml"

# Ad-hoc signatures change on every build, so macOS treats each build as a new app and drops its
# Accessibility permission. Signing with a stable Apple Development identity keeps the grant
# across rebuilds. Override with ARPOON_SIGNING_IDENTITY / ARPOON_DEVELOPMENT_TEAM if needed.
SIGNING_ARGS=()
IDENTITY="${ARPOON_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -n 1)}"
if [[ -n "$IDENTITY" ]]; then
  TEAM_ID="${ARPOON_DEVELOPMENT_TEAM:-$(security find-certificate -c "$IDENTITY" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU=\([^,/]*\).*/\1/p')}"
  if [[ -n "$TEAM_ID" ]]; then
    echo "Signing with \"$IDENTITY\" (team $TEAM_ID)"
    SIGNING_ARGS=(
      CODE_SIGN_STYLE=Manual
      "CODE_SIGN_IDENTITY=$IDENTITY"
      "DEVELOPMENT_TEAM=$TEAM_ID"
    )
  fi
fi

if [[ ${#SIGNING_ARGS[@]} -eq 0 ]]; then
  echo "No Apple Development identity found; using ad-hoc signing. Accessibility permission will need re-granting after each build." >&2
fi

xcodebuild \
  -project "$ROOT_DIR/Arpoon.xcodeproj" \
  -scheme Arpoon \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  "${SIGNING_ARGS[@]}" \
  build

# `open` only activates an already-running copy, so quit it first to actually launch the new build.
if pgrep -f "/Applications/Arpoon.app/Contents/MacOS/Arpoon" >/dev/null; then
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    pgrep -f "/Applications/Arpoon.app/Contents/MacOS/Arpoon" >/dev/null || break
    sleep 0.25
  done
fi

ditto "$APP_PATH" /Applications/Arpoon.app
open /Applications/Arpoon.app
