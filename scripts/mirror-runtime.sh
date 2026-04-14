#!/bin/zsh
set -u

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ADB="/opt/homebrew/bin/adb"
ENGINE_NAME="sc""rcpy"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER_APP="$SCRIPT_DIR/../Helpers/MirrorScreen.app"
ENGINE_PATH="$HELPER_APP/Contents/MacOS/MirrorScreen"
STATE_DIR="$HOME/Library/Application Support/Mirror"
LAST_DEVICE_FILE="$STATE_DIR/last-device"

fail() {
  /usr/bin/printf "%b\n" "$1"
  exit 1
}

device_state() {
  local serial="$1"
  "$ADB" devices | /usr/bin/awk -v serial="$serial" '$1 == serial { print $2; exit }'
}

first_network_device() {
  "$ADB" devices | /usr/bin/awk '$1 ~ /:/ && $2 == "device" { print $1; exit }'
}

first_usb_device() {
  "$ADB" devices | /usr/bin/awk '$1 !~ /:/ && $2 == "device" { print $1; exit }'
}

has_waiting_permission() {
  "$ADB" devices | /usr/bin/awk '$2 == "unauthorized" { found = 1 } END { exit found ? 0 : 1 }'
}

phone_ip_for_usb() {
  local serial="$1"
  "$ADB" -s "$serial" shell ip route 2>/dev/null | /usr/bin/awk '
    /wlan0/ {
      for (i = 1; i <= NF; i++) {
        if ($i == "src") {
          print $(i + 1)
          exit
        }
      }
    }'
}

remember_device() {
  local serial="$1"
  /bin/mkdir -p "$STATE_DIR"
  print -r -- "$serial" > "$LAST_DEVICE_FILE"
}

if [[ ! -x "$ADB" || ! -x "$ENGINE_PATH" ]]; then
  fail "Mirror is missing one of its local components.\n\nOpen Terminal and install the missing tools, then open Mirror again."
fi

"$ADB" start-server >/dev/null 2>&1 || fail "Mirror could not start the Android connection service.\n\nRestart your Mac and open Mirror again."

target=""

if [[ -f "$LAST_DEVICE_FILE" ]]; then
  last_device="$(/bin/cat "$LAST_DEVICE_FILE" 2>/dev/null)"
  if [[ -n "$last_device" && "$last_device" == *:* ]]; then
    "$ADB" connect "$last_device" >/dev/null 2>&1
    if [[ "$(device_state "$last_device")" != "device" ]]; then
      "$ADB" kill-server >/dev/null 2>&1
      "$ADB" start-server >/dev/null 2>&1
      "$ADB" connect "$last_device" >/dev/null 2>&1
    fi
    if [[ "$(device_state "$last_device")" == "device" ]]; then
      target="$last_device"
    fi
  fi
fi

if [[ -z "$target" ]]; then
  target="$(first_network_device)"
fi

if [[ -z "$target" ]]; then
  usb_device="$(first_usb_device)"
  if [[ -n "$usb_device" ]]; then
    phone_ip="$(phone_ip_for_usb "$usb_device")"
    if [[ -n "$phone_ip" ]]; then
      "$ADB" -s "$usb_device" tcpip 5555 >/dev/null 2>&1
      /bin/sleep 1
      network_device="$phone_ip:5555"
      "$ADB" connect "$network_device" >/dev/null 2>&1

      if [[ "$(device_state "$network_device")" == "device" ]]; then
        target="$network_device"
      else
        target="$usb_device"
      fi
    else
      target="$usb_device"
    fi
  fi
fi

if [[ -z "$target" ]]; then
  if has_waiting_permission; then
    fail "Your phone is waiting for permission.\n\nUnlock it, tap Allow on the debugging prompt, then open Mirror again."
  fi

  fail "Mirror could not find your phone.\n\nMake sure your phone is unlocked and on the same network as your Mac.\n\nFor first-time setup, connect your phone with USB once, allow debugging, and open Mirror again."
fi

if [[ "$target" == *:* ]]; then
  remember_device "$target"
fi

CURRENT_DEVICE_FILE="$STATE_DIR/current-device"
/bin/mkdir -p "$STATE_DIR"
print -r -- "$target" > "$CURRENT_DEVICE_FILE"
trap '/bin/rm -f "$CURRENT_DEVICE_FILE"' EXIT INT TERM

/usr/bin/open -n "$HELPER_APP" --args \
  --window-title Mirror \
  -s "$target" \
  --video-bit-rate 20M \
  --video-codec h265 \
  --video-buffer 0 \
  --no-audio

helper_pid=""
for _ in {1..20}; do
  helper_pid="$(/usr/bin/pgrep -f "MirrorScreen.app/Contents/MacOS/MirrorScreen" | /usr/bin/head -1)"
  [[ -n "$helper_pid" ]] && break
  /bin/sleep 0.2
done

if [[ -n "$helper_pid" ]]; then
  while /bin/kill -0 "$helper_pid" 2>/dev/null; do
    /bin/sleep 0.5
  done
fi
