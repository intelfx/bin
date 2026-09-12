#!/bin/bash

set -exo pipefail
shopt -s extglob

IN="$1"
OUT="$2"

DIR="$IN"
DIR="${DIR%%/*}"
DIR="${DIR##*/}"
DIR="${DIR%%.*}"

mkdir -p "$(dirname "$OUT")"

COLOURSPACE="b-w"
EXT="pgm"
if [[ $DIR == 4 ]]; then
	EXT="pnm"
	COLOURSPACE="srgb"
fi

vips colourspace "$IN" "$OUT.tmp1.$EXT" "$COLOURSPACE"
cjpegli -d 1 "$OUT.tmp1.$EXT" "$OUT"
#cjpeg -grayscale -q 90 -outfile "$OUT" "$OUT.tmp1.pgm"
rm -f "$OUT".tmp*
