#!/usr/bin/env bash
set -euo pipefail

# Script that generates a set of screenshots in MacOS to provide as evidence for SOC 2 compliance
# This is an alternative to Drata agent
# Please setup this shell to run periodically through a Cron job

timestamp="$(date +"%Y-%m-%d_%H-%M-%S")"

url_to_post=$1
drata_key=$2

encryption_outfile="$HOME/screenshot_disk_encryption_${timestamp}.png"
lockscreen_outfile="$HOME/screenshot_lock_screen_${timestamp}.png"
password_manager_outfile="$HOME/screenshot_password_manager_${timestamp}.png"
software_update_outfile="$HOME/screenshot_software_update_${timestamp}.png"
antivirus_outfile="$HOME/antivirus_update_${timestamp}.png"

info()  { echo "[INFO] $*"; }
warn()  { echo "[WARN] $*" >&2; }
error() { echo "[ERROR] $*" >&2; }

take_screenshot() {
  info "Taking screen screenshot of window..."

  sleep 0.5

  file_name=$1
  window_id=$2

  info "Taking screen screenshot of window..."
  /usr/sbin/screencapture -l$window_id -x "$file_name"
  echo "✅ Screenshot saved to: $file_name"

  info "Closing window..."
  osascript <<EOF
tell application "System Events"
    repeat with p in (every process whose visible is true)
        try
            repeat with w in windows of p
                if value of attribute "AXWindowID" of w is ${window_id} then
                    tell p to tell w to perform action "AXClose"
                    return
                end if
            end repeat
        end try
    end repeat
end tell
EOF
}

confirm_gui_macos() {
  /usr/bin/osascript <<'OSA' >/dev/null
set dialogText to "This script will open the necessary windows to provide evidence to Drata. Do you want to continue?"
display dialog dialogText with title "Permission Required" buttons {"Cancel", "Continue"} default button "Continue" with icon caution
OSA
}

confirm_terminal_fallback() {
  echo
  echo "This script will open the necessary windows to provide evidence to Drata"
  read -r -p "Do you want to continue? [y/N]: " ans
  case "${ans:-N}" in y|Y) return 0 ;; *) return 1 ;; esac
}

info "Requesting permission (GUI) on macOS..."
if ! confirm_gui_macos; then
  warn "Operation cancelled by user."
  exit 130
fi


#Antivirus - Bitdefender
open /Applications/BitdefenderVirusScanner.app
sleep 5
pip3 install pyobjc-framework-Quartz
bitdefender_window_id=$(python3 get-bitdefender-window.py)
take_screenshot $antivirus_outfile $bitdefender_window_id


#FileVault
info "Opening FileVault settings (System Settings → Privacy & Security → FileVault)..."
open "x-apple.systempreferences:com.apple.preference.security?FileVault"
sleep 2
take_screenshot $encryption_outfile $(osascript -e 'tell app "System Settings" to id of window 1')
  
#Lock screen
open "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension"
take_screenshot $lockscreen_outfile $(osascript -e 'tell app "System Settings" to id of window 1')

#Software update
open "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
take_screenshot $software_update_outfile $(osascript -e 'tell app "System Settings" to id of window 1')

#Password manager
open "x-apple.systempreferences:com.apple.Passwords-Settings.extension"
take_screenshot $password_manager_outfile $(osascript -e 'tell app "System Settings" to id of window 1')


info "Closing System Settings/Preferences..."
/usr/bin/osascript <<'OSA' >/dev/null 2>&1 || true
tell application "System Settings" to quit
tell application "System Preferences" to quit
OSA

info "Uploading documentation..."

curl -X POST $url_to_post \
-H "x-drata-key: ${drata_key}" \
-H "Content-Type: multipart/form-data" \
-F "encryptionFile=@${encryption_outfile}" \
-F "lockscreenFile=@${lockscreen_outfile}" \
-F "passwordManagerFile=@${password_manager_outfile}" \
-F "antivirusFile=@${antivirus_outfile}" \
-F "softwareUpdateFile=@${software_update_outfile}"

rm $encryption_outfile
rm $lockscreen_outfile
rm $password_manager_outfile
rm $software_update_outfile
rm $antivirus_outfile

info "Done."
exit 0