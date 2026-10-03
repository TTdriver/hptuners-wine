#!/usr/bin/env bash
set -euo pipefail
task_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
task_source=$task_root/build/wineftd2xx
task_revision=030c66f69052511276a5af5524ace093463d74cf
for task_tool in git make winegcc winebuild gcc objcopy wget tar sed; do
  command -v "$task_tool" >/dev/null || { printf 'Missing build tool: %s\n' "$task_tool"; exit 1; }
done
if [[ -e "$task_source" ]]; then
  printf 'Build directory already exists: %s\nRemove or move it before rebuilding.\n' "$task_source"
  exit 1
fi
mkdir -p "$task_root/build"
git clone https://github.com/brentr/wineftd2xx.git "$task_source"
git -C "$task_source" checkout --detach "$task_revision"
sed -i 's/\r$//' "$task_source/ftd2xx.c" "$task_source/Makefile"
git -C "$task_source" apply --check "$task_root/patches/wineftd2xx.patch"
git -C "$task_source" apply "$task_root/patches/wineftd2xx.patch"
make -C "$task_source"
printf '\nBuilt: %s/ftd2xx.dll.so\n' "$task_source"
