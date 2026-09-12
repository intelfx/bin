#!/bin/bash

set -exo pipefail
shopt -s extglob

SCRIPT_DIR="$(dirname "$(realpath "$BASH_SOURCE")")"
IN_DIR="${1%%/}"
TMP_DIR_RESIZED="$IN_DIR.resized"
TMP_DIR_CONVERTED="$IN_DIR.converted"
OUT_FILE_PNG="$IN_DIR.png.pdf"
OUT_FILE="$IN_DIR.jpg.pdf"

find "$IN_DIR" -type f \
	| parallel "${SCRIPT_DIR@Q}/scan-resize.sh {} ${TMP_DIR_RESIZED@Q}/{/.}.png"

find "$IN_DIR.resized" -type f \
	| parallel "${SCRIPT_DIR@Q}/scan-convert.sh {.}.png ${TMP_DIR_CONVERTED@Q}/{/.}.jpg"

img2pdf --output "$OUT_FILE_PNG" --imgsize 300dpi "$TMP_DIR_RESIZED"/*.png
img2pdf --output "$OUT_FILE" --imgsize 300dpi "$TMP_DIR_CONVERTED"/*.jpg
