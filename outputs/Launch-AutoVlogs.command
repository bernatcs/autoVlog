#!/bin/zsh

launcher_dir="$(cd "$(dirname "$0")" && pwd)"
"$launcher_dir/VlogForge" >"$launcher_dir/AutoVlogs.log" 2>&1 &
disown
