on run
  do shell script "export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; PHONE='192.168.1.6:5555'; ENGINE='/opt/homebrew/bin/sc'\"'rcpy'\"; /opt/homebrew/bin/adb start-server >/dev/null 2>&1; /opt/homebrew/bin/adb connect \"$PHONE\" >/dev/null 2>&1; if /opt/homebrew/bin/adb devices | /usr/bin/grep -q \"^${PHONE}[[:space:]]*device\"; then \"$ENGINE\" --window-title Mirror -s \"$PHONE\" >/dev/null 2>&1; else \"$ENGINE\" --window-title Mirror >/dev/null 2>&1; fi"
end run
