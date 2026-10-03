#!/usr/bin/env bash
set -euo pipefail
task_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
task_installed=${HPT_FTDI_LIBRARY:-/usr/lib/x86_64-linux-gnu/wine/ftd2xx.dll.so}
task_name=Scanner
if [[ ${HPT_APPLICATION:-scanner} == editor ]]; then task_name=Editor; fi
task_prefix=${WINEPREFIX:-$HOME/.wine}
task_app="$task_prefix/drive_c/Program Files/HP Tuners/VCM Suite/VCM $task_name.exe"
task_state=${XDG_STATE_HOME:-$HOME/.local/state}/hptuners-wine
mkdir -p "$task_state"
exec 9>"$task_state/session.lock"
if ! flock -n 9; then
  printf 'An HP Tuners Wine session is already running. Close it before starting another.\n'
  exit 1
fi
task_matches=()
for task_device in /sys/bus/usb/devices/*; do
  [[ -f "$task_device/idVendor" && -f "$task_device/idProduct" && -f "$task_device/serial" ]] || continue
  [[ $(cat "$task_device/idVendor") == 0403 && $(cat "$task_device/idProduct") == 6015 ]] || continue
  [[ $(cat "$task_device/serial") == MPVI* ]] || continue
  for task_candidate in "$task_device":*; do
    [[ -d "$task_candidate" ]] && task_matches+=("$(basename "$task_candidate")")
  done
done
if [[ ${#task_matches[@]} != 1 ]]; then
  printf 'Connect exactly one MPVI2 by USB, then try again.\n'
  exit 1
fi
task_interface=${task_matches[0]}
task_driver_path=/sys/bus/usb/devices/$task_interface/driver
task_driver=none
[[ ! -e "$task_driver_path" ]] || task_driver=$(basename "$(readlink -f "$task_driver_path")")
if [[ $task_driver != none && $task_driver != ftdi_sio ]]; then
  printf 'MPVI2 is in use by %s. Close other Wine/VM sessions and reconnect USB.\n' "$task_driver"
  exit 1
fi
task_patch=$task_root/../build/wineftd2xx/ftd2xx.dll.so
if [[ ! -f "$task_patch" || ! -f "$task_app" ]]; then
  printf "Build the bridge and install VCM Suite in the selected Wine prefix first.\n"
  exit 1
fi
task_patch_hash=$(sha256sum "$task_patch" | cut -d' ' -f1)
if [[ -f "$task_installed" && $(sha256sum "$task_installed" | cut -d' ' -f1) == "$task_patch_hash" ]]; then
  printf 'Experimental bridge is already installed. Finish the previous test and let it restore before using this launcher.\n'
  exit 1
fi
task_backup_dir=$(mktemp -d "$task_state/backup-XXXXXX")
task_backup=$task_backup_dir/ftd2xx.dll.so
task_had_original=0
if [[ -f "$task_installed" ]]; then
  task_had_original=1
  task_owner=$(stat -c '%u:%g' "$task_installed")
  task_mode=$(stat -c '%a' "$task_installed")
  cp "$task_installed" "$task_backup"
  task_original_hash=$(sha256sum "$task_backup" | cut -d' ' -f1)
else
  task_original_hash=none
fi
task_log=$task_state/${task_name,,}-$(date +%Y%m%d-%H%M%S).log
task_swapped=0
task_detached=0
task_cleanup() {
  trap - EXIT
  if [[ $task_swapped == 1 ]]; then
    if [[ -f "$task_installed" && $(sha256sum "$task_installed" | cut -d' ' -f1) == "$task_patch_hash" ]]; then
      if [[ $task_had_original == 0 ]]; then
        sudo rm -- "$task_installed"
        printf "Temporary FTDI bridge removed.\n"
      elif sudo cp "$task_backup" "$task_installed" && sudo chown "$task_owner" "$task_installed" && sudo chmod "$task_mode" "$task_installed"; then
        printf 'Original FTDI bridge restored.\n'
      else
        printf 'Restore failed. Backup: %s\n' "$task_backup"
      fi
    else
      printf 'Bridge changed during session; original backup: %s\n' "$task_backup"
    fi
  fi
  if [[ $task_detached == 1 && -d "/sys/bus/usb/devices/$task_interface" && ! -e "$task_driver_path" ]]; then
    if printf '%s' "$task_interface" | sudo tee /sys/bus/usb/drivers/ftdi_sio/bind >/dev/null; then
      printf 'Linux serial driver restored.\n'
    else
      printf 'Reconnect MPVI2 USB to restore its Linux serial driver.\n'
    fi
  elif [[ $task_detached == 1 && -d "/sys/bus/usb/devices/$task_interface" ]]; then
    printf 'Reconnect MPVI2 USB after Wine releases it to restore its Linux serial driver.\n'
  fi
}
trap task_cleanup EXIT
printf 'Starting HP Tuners %s. Keep this terminal open until it closes.\n' "$task_name"
sudo -v
task_swapped=1
sudo install -m 0644 "$task_patch" "$task_installed"
if [[ $task_driver == ftdi_sio ]]; then
  printf '%s' "$task_interface" | sudo tee /sys/bus/usb/drivers/ftdi_sio/unbind >/dev/null
  task_detached=1
fi
printf 'Original bridge SHA256: %s\nBackup: %s\n' "$task_original_hash" "$task_backup" >"$task_log"
set +e
FTDID=0403:6015 WINEDLLOVERRIDES=ftd2xx=b WINEPREFIX="$task_prefix" \
  WINEDEBUG=err+all LIBUSB_DEBUG=0 wine "$task_app" >>"$task_log" 2>&1
task_status=$?
set -e
printf '%s closed (status %s). Log: %s\n' "$task_name" "$task_status" "$task_log"
exit "$task_status"
