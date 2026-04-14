#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="/tmp/MirrorBuild"
APP_DIR="$BUILD_DIR/Mirror.app"
ICONSET_DIR="$BUILD_DIR/Mirror.iconset"
ICON_FILE="$BUILD_DIR/applet.icns"
SOURCE_ICON="$ROOT_DIR/assets/mirror-icon.png"
SOURCE_SCRIPT="$ROOT_DIR/MirrorLauncher.applescript"
DEST_APP="/Applications/Mirror.app"

ENGINE_NAME="sc""rcpy"
ENGINE_PATH="/opt/homebrew/bin/$ENGINE_NAME"

if [[ ! -x /opt/homebrew/bin/adb || ! -x "$ENGINE_PATH" ]]; then
  echo "Missing Android platform tools or the local Mirror engine."
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$ICONSET_DIR"

sips -z 16 16 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_64x64.png" >/dev/null
sips -z 128 128 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_1024x1024.png" >/dev/null

python3 "$ROOT_DIR/scripts/make_icns.py" "$ICONSET_DIR" "$ICON_FILE"

osacompile -o "$APP_DIR" "$SOURCE_SCRIPT"
cp "$ICON_FILE" "$APP_DIR/Contents/Resources/applet.icns"
ditto "$APP_DIR" "$DEST_APP"
touch "$DEST_APP"
qlmanage -r cache >/dev/null 2>&1 || true
killall Dock >/dev/null 2>&1 || true

echo "Installed $DEST_APP"
