#!/usr/bin/env bash
# Keep launch errors visible, including failures before Wine starts.
task_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
case ${1:-} in
  scanner|editor) bash "$task_root/run-$1.sh"; task_status=$? ;;
  *) echo 'Usage: run-desktop.sh scanner|editor'; task_status=2 ;;
esac
printf '\nLauncher finished (status %s).\n' "$task_status"
if [[ -t 0 ]]; then read -r -p 'Press Enter to close this terminal.'; fi
exit "$task_status"
