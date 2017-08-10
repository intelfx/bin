#!/bin/bash

set -e
shopt -s nullglob

SRC="$(systemd-path user-download)"
DEST="$(systemd-path user-documents)/X-Plane Output/FMS plans"

for file in "$SRC"/*.fms; do
	mv -v "$file" "$DEST"
done
