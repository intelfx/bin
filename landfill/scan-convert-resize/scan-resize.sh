#!/bin/bash

set -exo pipefail
shopt -s extglob

IN="$1"
OUT="$2"

DIR="$IN"
DIR="${DIR%%/*}"
DIR="${DIR##*/}"
DIR="${DIR%%.*}"

FN="$IN"
FN="${FN##*/}"
FN="${FN%%.*}"
NR="${FN##page_}"

LR="${NR##+([0-9])_}"

mkdir -p "$(dirname "$OUT")"

SCALING_FACTOR="0.25"
COLOURSPACE="b-w"
OUT_SETTINGS="[compression=9]"

if [[ $DIR == 1 ]]; then
	if [[ $FN == page_1788781750_1 ]]; then
		COORDS=(512 147 8308 12060)
	elif [[ $FN == page_1788798530_2 ]]; then
		COORDS=(1376 51 8333 12077)
	elif (( LR == 1 )); then
		COORDS=(522 6 8293 12085)
	else
		COORDS=(1373 0 8293 12090)
	fi
elif [[ $DIR == 2 ]]; then
	if [[ $FN == page_1788883644_1 ]]; then
		COORDS=(401 73 8410 12032)
	elif [[ $FN == page_1788883981_2 ]]; then
		COORDS=(1379 46 8434 12055)
	elif (( LR == 1 )); then
		COORDS=(391 18 8418 11985)
	else
		COORDS=(1373 10 8425 11983)
	fi
elif [[ $DIR == 3 ]]; then
	if (( LR == 1 )); then
		COORDS=(14 24 10186 13183)
	else
		COORDS=(0 16 10180 13191)
	fi
elif [[ $DIR == 4 ]]; then
	COORDS=(888 26 4826 10216)
	COLOURSPACE=(srgb)
fi

vips extract_area "$IN" "$OUT.tmp1.v" "${COORDS[@]}"
vips resize "$OUT.tmp1.v" "$OUT.tmp2.v" "$SCALING_FACTOR"
vips colourspace "$OUT.tmp2.v" "$OUT$OUT_SETTINGS" "$COLOURSPACE"
rm -f "$OUT".tmp*
