#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="/tmp/MirrorBuild"
APP_DIR="$BUILD_DIR/Mirror.app"
HELPER_APP="$APP_DIR/Contents/Helpers/MirrorScreen.app"
ICONSET_DIR="$BUILD_DIR/Mirror.iconset"
ICON_FILE="$BUILD_DIR/Mirror.icns"
SOURCE_ICON="$ROOT_DIR/assets/mirror-icon.png"
SOURCE_APP="$ROOT_DIR/Sources/MirrorApp.swift"
RUNTIME_SCRIPT="$ROOT_DIR/scripts/mirror-runtime.sh"
DEST_APP="/Applications/Mirror.app"

ENGINE_NAME="sc""rcpy"
ENGINE_PATH="/opt/homebrew/bin/$ENGINE_NAME"
ENGINE_BINARY="$HELPER_APP/Contents/MacOS/MirrorScreen"

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

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
mkdir -p "$HELPER_APP/Contents/MacOS" "$HELPER_APP/Contents/Resources"
swiftc "$SOURCE_APP" -framework AppKit -o "$APP_DIR/Contents/MacOS/Mirror"
cp "$ICON_FILE" "$APP_DIR/Contents/Resources/Mirror.icns"
cp "$SOURCE_ICON" "$APP_DIR/Contents/Resources/Mirror.png"
cp "$ICON_FILE" "$HELPER_APP/Contents/Resources/Mirror.icns"
cp "$SOURCE_ICON" "$HELPER_APP/Contents/Resources/Mirror.png"
cp "$ENGINE_PATH" "$ENGINE_BINARY"
chmod u+w "$ENGINE_BINARY"
python3 - "$ENGINE_BINARY" <<'PY'
import pathlib
import sys

binary = pathlib.Path(sys.argv[1])
data = binary.read_bytes()
engine_name = b"sc" + b"rcpy"
marker = b"../app/src/" + engine_name + b".c\0" + engine_name + b"\0Could not request"
index = data.find(marker)

if index == -1:
    raise SystemExit("Could not patch Mirror app name")

name_offset = index + len(b"../app/src/") + len(engine_name) + len(b".c\0")
patched = data[:name_offset] + b"Mirror" + data[name_offset + len(engine_name):]
binary.write_bytes(patched)
PY
chmod +x "$ENGINE_BINARY"
codesign --force --sign - --preserve-metadata=entitlements,requirements,flags,runtime "$ENGINE_BINARY"
cat > "$HELPER_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Mirror</string>
  <key>CFBundleExecutable</key>
  <string>MirrorScreen</string>
  <key>CFBundleIconFile</key>
  <string>Mirror.icns</string>
  <key>CFBundleIdentifier</key>
  <string>app.mirror.screen</string>
  <key>CFBundleName</key>
  <string>Mirror</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.4</string>
  <key>CFBundleVersion</key>
  <string>0.1.4</string>
  <key>LSEnvironment</key>
  <dict>
    <key>SCRCPY_ICON_PATH</key>
    <string>/Applications/Mirror.app/Contents/Helpers/MirrorScreen.app/Contents/Resources/Mirror.png</string>
  </dict>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST
cp "$RUNTIME_SCRIPT" "$APP_DIR/Contents/Resources/mirror-runtime.sh"
chmod +x "$APP_DIR/Contents/Resources/mirror-runtime.sh"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Mirror</string>
  <key>CFBundleExecutable</key>
  <string>Mirror</string>
  <key>CFBundleIconFile</key>
  <string>Mirror.icns</string>
  <key>CFBundleIdentifier</key>
  <string>app.mirror.launcher</string>
  <key>CFBundleName</key>
  <string>Mirror</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.4</string>
  <key>CFBundleVersion</key>
  <string>0.1.4</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST
rm -rf "$DEST_APP"
ditto "$APP_DIR" "$DEST_APP"
touch "$DEST_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$DEST_APP" >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true
killall Dock >/dev/null 2>&1 || true

echo "Installed $DEST_APP"
