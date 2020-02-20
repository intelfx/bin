#!/bin/bash

dir="$1"

most_recent_mtime="$(find "$dir" -mindepth 1 -maxdepth 1 -printf '%T@\n' | sort -n | tail -n1)"
[[ "$most_recent_mtime" ]] || exit 1
touch -d "@$most_recent_mtime" "$dir"
