#!/bin/bash

set -exo pipefail
shopt -s extglob

IN_DIR="$1"
TMP_DIR_RESIZED="${IN_DIR%%/}.resized"
TMP_DIR_CONVERTED="${IN_DIR%%/}.converted"
OUT_FILE_PNG="${IN_DIR%%/}.png.pdf"
OUT_FILE="${IN_DIR%%/}.jpg.pdf"

find "$IN_DIR" -type f \
	| parallel "./scan-resize.sh {} ${TMP_DIR_RESIZED@Q}/{/}"

find "$IN_DIR.resized" -type f \
	| parallel "./scan-convert.sh {} ${TMP_DIR_CONVERTED@Q}/{/.}.jpg"

img2pdf --output "$OUT_FILE_PNG" --imgsize 300dpi "$TMP_DIR_RESIZED"/*.png
img2pdf --output "$OUT_FILE" --imgsize 300dpi "$TMP_DIR_CONVERTED"/*.jpg
