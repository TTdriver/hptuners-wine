#!/usr/bin/env bash
set -euo pipefail
task_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
task_desktop=$(xdg-user-dir DESKTOP)
[[ -d $task_desktop ]] || { echo 'Desktop folder not found.'; exit 1; }
# Escape the quoted argument using desktop-entry Exec escaping rules.
task_exec=${task_root//\\/\\\\}
task_exec=${task_exec//\"/\\\"}
task_exec=${task_exec//\$/\\\$}
task_exec=${task_exec//\`/\\\`}
task_exec=${task_exec//%/%%}
for task_app in Scanner Editor; do
  task_file="$task_desktop/HP Tuners $task_app.desktop"
  cat >"$task_file" <<EOF
[Desktop Entry]
Type=Application
Name=HP Tuners $task_app (Wine USB)
Exec=/bin/bash "$task_exec/run-desktop.sh" ${task_app,,}
Icon=applications-engineering
Terminal=true
Categories=Utility;
EOF
  chmod 755 "$task_file"
  if ! gio set "$task_file" metadata::trusted true; then
    echo "Right-click $task_file and choose Allow Launching."
  fi
done
