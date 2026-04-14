#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/Mirror"
APP_PATH="/Applications/Mirror.app"
DMG_PATH="$DIST_DIR/Mirror.dmg"

if [[ ! -d "$APP_PATH" ]]; then
  "$ROOT_DIR/scripts/install.sh"
fi

rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"

ditto "$APP_PATH" "$STAGE_DIR/Mirror.app"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname Mirror \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created $DMG_PATH"
