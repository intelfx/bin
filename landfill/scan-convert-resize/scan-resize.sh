#!/bin/bash

set -exo pipefail
shopt -s extglob

IN="$1"
OUT="$2"

NR="$IN"
NR="${NR##*/}"
NR="${NR##+([^0-9]).}"
NR="${NR%%.*}"
NR="${NR##+(0)}"

if (( NR > 176 )); then
	exit
fi

mkdir -p "$(dirname "$OUT")"
if (( NR == 1 )); then
	COORDS=(623 60 8320 12106)
elif (( NR == 176 )); then
	COORDS=(965 50 8320 12106)
elif (( (NR % 2) == 1 )); then
	COORDS=(623 0 8320 12106)
else
	COORDS=(965 0 8320 12106)
fi
SCALING_FACTOR="0.25"
COLOURSPACE="b-w"
OUT_SETTINGS="[compression=9]"

vips extract_area "$IN" "$OUT.tmp1.v" "${COORDS[@]}"
vips resize "$OUT.tmp1.v" "$OUT.tmp2.v" "$SCALING_FACTOR"
vips colourspace "$OUT.tmp2.v" "$OUT$OUT_SETTINGS" "$COLOURSPACE"
rm -f "$OUT".tmp*
