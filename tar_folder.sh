#!/bin/bash

DIR="${1%%/}"

[[ -d "$DIR" ]] || { echo "== \"$DIR\" is not a directory" >&2; exit 1; }
echo "-- Tar"
tar -cf "$DIR.tar" "$DIR" || { echo "== Tarring failed" >&2; exit 1; }
echo "-- Rmdir"
rm -rf "$DIR"
