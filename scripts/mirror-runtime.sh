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
LOG_DIR="$HOME/Library/Logs/Mirror"
LOG_FILE="$LOG_DIR/mirror.log"

/bin/mkdir -p "$LOG_DIR"
if [[ -f "$LOG_FILE" ]]; then
  log_size=$(/usr/bin/stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
  if (( log_size > 5242880 )); then
    /bin/mv -f "$LOG_FILE" "$LOG_DIR/mirror.log.1"
  fi
fi

log() {
  local timestamp
  timestamp="$(/bin/date "+%Y-%m-%d %H:%M:%S")"
  /usr/bin/printf "[%s] %s\n" "$timestamp" "$1" >> "$LOG_FILE"
}

fail() {
  log "FAIL: $(/usr/bin/printf '%b' "$1" | /usr/bin/tr '\n' ' ')"
  /usr/bin/printf "%b\n" "$1"
  exit 1
}

log "--- Mirror session start ---"

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

offer_adb_install() {
  local response
  response="$(/usr/bin/osascript <<'OSA' 2>/dev/null
try
    display dialog "Mirror needs the Android platform tools to talk to your phone." & return & return & "Install them now with Homebrew?" buttons {"Cancel", "Install"} default button "Install" with title "Mirror"
    return button returned of result
on error
    return "Cancel"
end try
OSA
)"
  if [[ "$response" != "Install" ]]; then
    return 1
  fi

  local brew_path=""
  if [[ -x /opt/homebrew/bin/brew ]]; then
    brew_path=/opt/homebrew/bin/brew
  elif [[ -x /usr/local/bin/brew ]]; then
    brew_path=/usr/local/bin/brew
  fi

  if [[ -z "$brew_path" ]]; then
    /usr/bin/osascript <<'OSA' >/dev/null 2>&1
try
    set response to button returned of (display dialog "Homebrew is required to install the Android platform tools." & return & return & "Install Homebrew from brew.sh first, then open Mirror again." buttons {"Open brew.sh", "OK"} default button "Open brew.sh" with title "Mirror")
    if response is "Open brew.sh" then
        do shell script "open https://brew.sh"
    end if
end try
OSA
    return 1
  fi

  log "opening Terminal to run: $brew_path install android-platform-tools"
  /usr/bin/osascript <<OSA >/dev/null 2>&1
tell application "Terminal"
    activate
    do script "$brew_path install android-platform-tools"
end tell
OSA
  return 0
}

if [[ ! -x "$ADB" ]]; then
  log "adb missing at $ADB"
  if offer_adb_install; then
    fail "Mirror is installing the Android platform tools in Terminal.\n\nWhen Terminal finishes, open Mirror again."
  fi
  fail "Mirror needs the Android platform tools.\n\nInstall them with:\n  brew install android-platform-tools\n\nThen open Mirror again."
fi

if [[ ! -x "$ENGINE_PATH" ]]; then
  fail "Mirror is missing its streaming engine.\n\nReinstall Mirror from the latest DMG, then open it again."
fi

log "adb: $ADB"
log "engine: $ENGINE_PATH"

if ! "$ADB" start-server >>"$LOG_FILE" 2>&1; then
  fail "Mirror could not start the Android connection service.\n\nRestart your Mac and open Mirror again."
fi

target=""
connect_detail=""
last_device=""

if [[ -f "$LAST_DEVICE_FILE" ]]; then
  last_device="$(/bin/cat "$LAST_DEVICE_FILE" 2>/dev/null)"
  log "last-device file: $last_device"
  if [[ -n "$last_device" && "$last_device" == *:* ]]; then
    connect_detail="$("$ADB" connect "$last_device" 2>&1)"
    log "adb connect $last_device: $connect_detail"
    if [[ "$(device_state "$last_device")" != "device" ]]; then
      log "first connect did not reach device state, bouncing adb server"
      "$ADB" kill-server >>"$LOG_FILE" 2>&1 || true
      "$ADB" start-server >>"$LOG_FILE" 2>&1 || true
      connect_detail="$("$ADB" connect "$last_device" 2>&1)"
      log "adb connect $last_device (retry): $connect_detail"
    fi
    if [[ "$(device_state "$last_device")" == "device" ]]; then
      target="$last_device"
      log "using last device: $target"
    fi
  fi
fi

if [[ -z "$target" ]]; then
  connected=(${(f)"$("$ADB" devices | /usr/bin/awk 'NR > 1 && $2 == "device" { print $1 }')"})
  if (( ${#connected[@]} > 1 )); then
    log "multiple devices visible: ${connected[*]}"
    chosen="$(/usr/bin/osascript - "${connected[@]}" <<'OSA' 2>/dev/null
on run argv
    set chosenItems to choose from list argv with prompt "Mirror sees more than one phone. Which one should I open?"
    if chosenItems is false then return ""
    return item 1 of chosenItems as string
end run
OSA
)"
    if [[ -n "$chosen" ]]; then
      target="$chosen"
      log "picker selected: $target"
    else
      log "picker cancelled"
      fail "Mirror needs a phone to mirror.\n\nOpen Mirror again and pick one when prompted."
    fi
  fi
fi

if [[ -z "$target" ]]; then
  target="$(first_network_device)"
  [[ -n "$target" ]] && log "picked existing network device: $target"
fi

if [[ -z "$target" ]]; then
  usb_device="$(first_usb_device)"
  if [[ -n "$usb_device" ]]; then
    log "found usb device: $usb_device"
    phone_ip="$(phone_ip_for_usb "$usb_device")"
    if [[ -n "$phone_ip" ]]; then
      log "phone wlan0 ip: $phone_ip"
      "$ADB" -s "$usb_device" tcpip 5555 >>"$LOG_FILE" 2>&1 || true
      /bin/sleep 1
      network_device="$phone_ip:5555"
      connect_detail="$("$ADB" connect "$network_device" 2>&1)"
      log "adb connect $network_device: $connect_detail"

      if [[ "$(device_state "$network_device")" == "device" ]]; then
        target="$network_device"
        log "switched to wifi target: $target"
      else
        target="$usb_device"
        log "wifi switch failed, staying on usb: $target"
      fi
    else
      target="$usb_device"
      log "no wlan0 ip, staying on usb: $target"
    fi
  fi
fi

if [[ -z "$target" ]]; then
  log "no target selected. adb devices:"
  "$ADB" devices >> "$LOG_FILE" 2>&1

  if has_waiting_permission; then
    fail "Your phone is waiting for permission.\n\nUnlock it, tap Allow on the debugging prompt, then open Mirror again."
  fi

  detail=""
  if [[ -n "$last_device" ]]; then
    detail="Last known phone: $last_device"
    if [[ -n "$connect_detail" ]]; then
      clean="$(/usr/bin/printf '%s' "$connect_detail" | /usr/bin/sed -n 's/^failed to connect to .*: //p' | /usr/bin/head -1)"
      [[ -n "$clean" ]] && detail="$detail\nReason: $clean"
    fi
    detail="$detail\n\n"
  fi

  fail "Mirror could not find your phone.\n\n${detail}Make sure your phone is unlocked and on the same Wi-Fi as your Mac.\n\nFirst-time setup: plug the phone in with USB once, allow debugging, and open Mirror again.\n\nLog: ~/Library/Logs/Mirror/mirror.log"
fi

if [[ "$target" == *:* ]]; then
  remember_device "$target"
fi

CURRENT_DEVICE_FILE="$STATE_DIR/current-device"
/bin/mkdir -p "$STATE_DIR"
print -r -- "$target" > "$CURRENT_DEVICE_FILE"
trap '/bin/rm -f "$CURRENT_DEVICE_FILE"; log "--- Mirror session end ---"' EXIT INT TERM

saved_x=""
saved_y=""
saved_w=""
saved_h=""
WINDOW_FRAME_FILE="$STATE_DIR/window-frame"
if [[ -f "$WINDOW_FRAME_FILE" ]]; then
  read -r saved_x saved_y saved_w saved_h < "$WINDOW_FRAME_FILE" 2>/dev/null || true
  if [[ -n "$saved_x" && -n "$saved_y" && -n "$saved_w" && -n "$saved_h" ]]; then
    log "restoring window frame: x=$saved_x y=$saved_y w=$saved_w h=$saved_h"
  else
    saved_x=""
  fi
fi

launch_helper() {
  local -a args
  args=(
    --window-title Mirror
    -s "$target"
    --video-bit-rate 20M
    --video-codec h265
    --video-buffer 0
    --no-audio
  )

  if [[ -n "$saved_x" ]]; then
    args+=(--window-x "$saved_x" --window-y "$saved_y" --window-width "$saved_w" --window-height "$saved_h")
  fi

  if [[ -f "$STATE_DIR/always-on-top" ]]; then
    args+=(--always-on-top)
    log "always-on-top enabled"
  fi

  log "launching helper for $target"
  /usr/bin/open -n "$HELPER_APP" --args "${args[@]}"

  local pid=""
  local _
  for _ in {1..20}; do
    pid="$(/usr/bin/pgrep -f "MirrorScreen.app/Contents/MacOS/MirrorScreen" | /usr/bin/head -1)"
    [[ -n "$pid" ]] && break
    /bin/sleep 0.2
  done

  if [[ -z "$pid" ]]; then
    log "helper pid not found after launch"
    return 1
  fi

  log "helper pid: $pid"
  while /bin/kill -0 "$pid" 2>/dev/null; do
    /bin/sleep 0.5
  done
  log "helper pid $pid exited"
  return 0
}

target_reachable() {
  if [[ "$target" == *:* ]]; then
    local result
    result="$("$ADB" connect "$target" 2>&1)"
    [[ "$result" == *"connected to"* || "$result" == *"already connected"* ]]
  else
    [[ "$(device_state "$target")" == "device" ]]
  fi
}

try_reconnect() {
  local _
  for _ in {1..30}; do
    /bin/sleep 1
    if target_reachable; then
      return 0
    fi
  done
  return 1
}

while true; do
  launch_helper || break

  if target_reachable; then
    log "helper exited with target still reachable; treating as user-initiated close"
    break
  fi

  log "helper exited and target unreachable; attempting reconnect for up to 30s"
  if try_reconnect; then
    log "reconnected to $target, relaunching helper"
    continue
  fi

  log "reconnect failed after 30s"
  if [[ -n "$(first_usb_device)" ]]; then
    fail "Mirror lost your phone over Wi-Fi.\n\nYour phone is back on USB though — open Mirror again and it will re-enable Wi-Fi mirroring.\n\nLog: ~/Library/Logs/Mirror/mirror.log"
  fi
  fail "Mirror lost your phone and couldn't reconnect.\n\nPhone: $target\n\nIf your phone restarted, plug it in with USB once and open Mirror again.\n\nOtherwise make sure the phone is awake and on the same Wi-Fi.\n\nLog: ~/Library/Logs/Mirror/mirror.log"
done
