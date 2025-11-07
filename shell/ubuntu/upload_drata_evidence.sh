#!/usr/bin/env bash
set -euo pipefail

# Script that generates a set of screenshots in Ubuntu (GNOME) to provide as evidence for SOC 2 compliance
# This is an alternative to Drata agent.
# Schedule periodically with cron/systemd timers if needed.
#
# Usage:
#   ./upload_drata_evidence_ubuntu.sh "<URL_TO_POST>" "<DRATA_KEY>"
#
# Dependencies:
#   wmctrl xdotool gnome-screenshot curl
#   gnome-disk-utility (gnome-disks), gnome-control-center, seahorse, update-manager
#   clamtk (optional antivirus GUI)

sudo apt update && sudo apt install -y wmctrl xdotool gnome-screenshot gnome-disk-utility gnome-control-center seahorse update-manager curl

# Optional antivirus GUI:
sudo apt install -y clamtk


timestamp="$(date +"%Y-%m-%d_%H-%M-%S")"

url_to_post=${1:? "Missing 1st arg: URL to POST"}
drata_key=${2:? "Missing 2nd arg: Drata key"}

encryption_outfile="$HOME/screenshot_disk_encryption_${timestamp}.png"
lockscreen_outfile="$HOME/screenshot_lock_screen_${timestamp}.png"
password_manager_outfile="$HOME/screenshot_password_manager_${timestamp}.png"
software_update_outfile="$HOME/screenshot_software_update_${timestamp}.png"
antivirus_outfile="$HOME/antivirus_update_${timestamp}.png"

info()  { echo "[INFO] $*"; }
warn()  { echo "[WARN] $*" >&2; }
error() { echo "[ERROR] $*" >&2; }

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || { error "Missing command: $c"; exit 127; }
  done
}

# Ensure core tools exist
require_cmd wmctrl xdotool gnome-screenshot curl

# Ask permission using zenity if available; otherwise fall back to terminal prompt.
confirm_gui() {
  if command -v zenity >/dev/null 2>&1; then
    zenity --question \
      --title="Permission Required" \
      --text="This script will open the necessary windows to provide evidence to Drata. Continue?" \
      --ok-label="Continue" --cancel-label="Cancel"
    return $?
  else
    echo
    echo "This script will open the necessary windows to provide evidence to Drata."
    read -r -p "Do you want to continue? [y/N]: " ans
    case "${ans:-N}" in y|Y) return 0 ;; *) return 1 ;; esac
  fi
}

# Try to screenshot the active window; if that fails (Wayland policies etc.), fallback to full screen.
shoot_active_or_full() {
  local outfile="$1"
  if gnome-screenshot -w -B -f "$outfile" 2>/dev/null; then
    return 0
  else
    warn "Window capture failed; falling back to full-screen screenshot."
    gnome-screenshot -B -f "$outfile"
  fi
}

# Open a program (in background), wait for its window, activate it, screenshot, then try to close it.
open_and_capture() {
  local launch_cmd="$1"      # command to launch the app/window
  local match_pattern="$2"   # substring or regex used to find the window title via wmctrl -l
  local outfile="$3"         # file to write screenshot to
  local wait_secs="${4:-8}"  # time to allow the window to appear

  info "Opening: $launch_cmd"
  # Launch detached
  bash -lc "$launch_cmd" >/dev/null 2>&1 &

  info "Waiting up to ${wait_secs}s for window: $match_pattern"
  local found_id=""
  for _ in $(seq 1 "$wait_secs"); do
    # wmctrl output: 0x03c00007 <desktop> <host> <title...>
    if wmctrl -l | grep -iE "$match_pattern" >/dev/null 2>&1; then
      found_id="$(wmctrl -l | grep -iE "$match_pattern" | awk '{print $1; exit}')"
      break
    fi
    sleep 1
  done

  if [[ -z "${found_id}" ]]; then
    warn "Window not found for pattern '$match_pattern'. Will try screenshot anyway."
  else
    info "Activating window id: $found_id"
    wmctrl -ia "$found_id" || true
    sleep 1
  fi

  info "Taking screenshot -> $outfile"
  shoot_active_or_full "$outfile"
  echo "✅ Screenshot saved to: $outfile"

  # Best-effort close (some apps may stay resident)
  if [[ -n "${found_id}" ]]; then
    info "Closing window id: $found_id"
    wmctrl -ic "$found_id" || true
  fi
}

# ----- Confirm -----
info "Requesting permission..."
if ! confirm_gui; then
  warn "Operation cancelled by user."
  exit 130
fi

# ----- Antivirus (optional: ClamTk if installed) -----
if command -v clamtk >/dev/null 2>&1; then
  open_and_capture "clamtk" "ClamTk|ClamAV" "$antivirus_outfile" 12
else
  warn "Antivirus GUI (clamtk) not found; skipping antivirus screenshot."
  # Create a placeholder with system info, so the upload fields remain consistent.
  info "Creating placeholder antivirus evidence."
  printf "Antivirus GUI not installed on this system (%s)\n" "$(date)" | convert -background white -fill black -pointsize 14 -gravity northwest -annotate +20+20 @- "$antivirus_outfile" 2>/dev/null || \
    echo "Antivirus GUI not installed on this system" > "$antivirus_outfile"
fi

# ----- Disk Encryption (show Disks) -----
# The Disks app clearly shows whether volumes are LUKS-encrypted.
require_cmd gnome-disks
open_and_capture "gnome-disks" "Disks" "$encryption_outfile" 10

# ----- Lock Screen settings -----
# Open GNOME Settings; Screen Lock lives under Privacy. Deep-linking varies by distro, so we open Settings and capture.
require_cmd gnome-control-center
open_and_capture "gnome-control-center privacy" "Settings|Privacy|Screen Lock" "$lockscreen_outfile" 10

# ----- Software Update -----
# Ubuntu's Software Updater
if command -v update-manager >/dev/null 2>&1; then
  open_and_capture "update-manager" "Software Updater" "$software_update_outfile" 20
else
  warn "update-manager not found; trying GNOME Software Updates view."
  if command -v gnome-software >/dev/null 2>&1; then
    open_and_capture "gnome-software --mode updates" "Software|Updates" "$software_update_outfile" 15
  else
    warn "No graphical updater found; capturing apt policy as placeholder."
    (apt-cache policy && date) | sed -n '1,40p' | \
      convert -background white -fill black -pointsize 12 -gravity northwest -annotate +20+20 @- "$software_update_outfile" 2>/dev/null || \
      apt-cache policy | head -n 50 > "$software_update_outfile"
  fi
fi

# ----- Password manager (Passwords and Keys / Seahorse) -----
if command -v seahorse >/dev/null 2>&1; then
  open_and_capture "seahorse" "Passwords and Keys|Seahorse" "$password_manager_outfile" 10
else
  warn "seahorse not found; creating placeholder password evidence."
  printf "Passwords & Keys (seahorse) not installed on this system (%s)\n" "$(date)" | convert -background white -fill black -pointsize 14 -gravity northwest -annotate +20+20 @- "$password_manager_outfile" 2>/dev/null || \
    echo "Passwords & Keys (seahorse) not installed" > "$password_manager_outfile"
fi

# ----- Upload -----
info "Uploading documentation..."

curl -X POST "$url_to_post" \
  -H "x-drata-key: ${drata_key}" \
  -H "Content-Type: multipart/form-data" \
  -F "encryptionFile=@${encryption_outfile}" \
  -F "lockscreenFile=@${lockscreen_outfile}" \
  -F "passwordManagerFile=@${password_manager_outfile}" \
  -F "antivirusFile=@${antivirus_outfile}" \
  -F "softwareUpdateFile=@${software_update_outfile}"

# ----- Cleanup -----
rm -f "$encryption_outfile" \
      "$lockscreen_outfile" \
      "$password_manager_outfile" \
      "$software_update_outfile" \
      "$antivirus_outfile"

info "Done."
exit 0