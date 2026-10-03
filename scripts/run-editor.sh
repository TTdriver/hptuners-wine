#!/usr/bin/env bash
set -euo pipefail
task_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export HPT_APPLICATION=editor
exec bash "$task_root/run-scanner.sh"
