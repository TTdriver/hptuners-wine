#!/usr/bin/env bash
set -euo pipefail
task_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
task_state=${XDG_STATE_HOME:-$HOME/.local/state}/hptuners-wine
task_installed=${HPT_FTDI_LIBRARY:-/usr/lib/x86_64-linux-gnu/wine/ftd2xx.dll.so}
[[ $# == 1 && -f $1 ]] || { echo 'Usage: recover-bridge.sh SESSION_LOG'; exit 2; }
exec 9>"$task_state/session.lock"
flock -n 9 || { echo 'Close the active HP Tuners session first.'; exit 1; }
task_field() { sed -n "s/^$1: //p" "$2" | head -n 1; }
task_hash=$(task_field 'Original bridge SHA256' "$1")
task_backup=$(task_field 'Backup' "$1")
task_owner=$(task_field 'Owner' "$1")
task_mode=$(task_field 'Mode' "$1")
task_patch=$task_root/../build/wineftd2xx/ftd2xx.dll.so
[[ -f $task_patch && -f $task_installed ]] || { echo 'Bridge files missing; recovery stopped.'; exit 1; }
[[ $(sha256sum "$task_installed" | cut -d' ' -f1) == $(sha256sum "$task_patch" | cut -d' ' -f1) ]] || { echo 'Installed bridge differs from the patch; recovery stopped.'; exit 1; }
if [[ $task_hash == none ]]; then
  sudo rm -- "$task_installed"
else
  [[ $task_hash =~ ^[0-9a-f]{64}$ && -f $task_backup ]] || { echo 'Invalid backup record.'; exit 1; }
  [[ $(sha256sum "$task_backup" | cut -d' ' -f1) == "$task_hash" ]] || { echo 'Backup hash mismatch; recovery stopped.'; exit 1; }
  # Older logs lack ownership metadata. cp preserves the destination metadata.
  if [[ -n $task_owner || -n $task_mode ]]; then
    [[ $task_owner =~ ^[0-9]+:[0-9]+$ && $task_mode =~ ^[0-7]{3,4}$ ]] || { echo 'Invalid ownership record.'; exit 1; }
  fi
  sudo cp -- "$task_backup" "$task_installed"
  if [[ -n $task_owner ]]; then
    sudo chown "$task_owner" "$task_installed"
    sudo chmod "$task_mode" "$task_installed"
  fi
fi
echo 'Bridge recovered. Reconnect MPVI2 USB before launching again.'
